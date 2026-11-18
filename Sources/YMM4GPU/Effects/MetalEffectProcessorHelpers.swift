#if os(macOS)
import Foundation
import Metal
import YMM4Core

/// GPU エフェクト処理器 第2段（MAC-0028）。
///
/// 第1段（色変換系10種）に続き、幾何変換・ぼかし／マスク・影／塗り・
/// ワープ・イン／アウト・ランダム／反復の31種を Metal で実装する。
/// 各処理器のパラメータ意味論は本家の逆コンパイル実コード
/// （Player.Video.Effects 配下の該当クラス）で確認したものだけを
/// 実装し、式の根拠は各処理器のコメントに記す。数式がコンパイル済み
/// カスタムシェーダ（.cso）の中にしか無いもの、D2D 組み込みで計算式が
/// 公開されていないもの、メッシュ描画系、エフェクト内ファイル読み込み
/// が要るものは素通しのまま残す（対象外の一覧と理由は実装記録側）。
///
/// 中間画像が画面サイズへ折り畳まれている点（MAC-0012 レビュー条件
/// G12-01..06）により、本家の無限平面と差が出うる箇所は各処理器の
/// コメントに差分として明記する。

// MARK: - 共通ヘルパ

extension MetalEffectProcessor {
    /// Animation の現在フレーム評価（本家の GetValue(frame, length, fps)）。
    func evaluate(_ animation: Animation, _ description: EffectDescription) -> Double {
        let (frame, length, fps) = evaluationContext(description)
        return animation.value(atFrame: frame, length: length, fps: fps)
    }

    /// イン／アウト系のイージング値。Core の
    /// `InOutEffectProcessorBase.easingValue`（本家 GetEasingValue）と
    /// 同じ式を、Metal 処理器側でも使えるよう再掲する。
    func inOutEasingValue(
        _ definition: InOutEffectDefinitionBase,
        _ description: EffectDescription,
        from: Double,
        to: Double
    ) -> Double {
        let positionSeconds = description.itemDescription.itemPosition.time
        let durationSeconds = description.itemDescription.itemDuration.time
        let time = definition.effectTimeSeconds
        let inRate = (definition.isInEffect && time > 0)
            ? min(max(positionSeconds / time, 0), 1)
            : 1
        let outRate = (definition.isOutEffect && time > 0)
            ? min(max((durationSeconds - positionSeconds) / time, 0), 1)
            : 1
        let rate = min(inRate, outRate)
        let eased = EasingFamily.getValue(
            family: definition.easingFamily, mode: definition.easingMode, rate: rate
        )
        return from + (to - from) * eased
    }

    /// ランダム系の乱数率。Core の `RandomEffectProcessorBase.randomValue`
    /// （本家 GetRandomValue）と同じ式を再掲する。種は定義の randomSeed
    /// （本家 GetHashCode の代替。対応付けは未解決事項として既存台帳に
    /// 記録済み）。
    func randomRate(
        _ definition: RandomEffectDefinitionBase,
        _ description: EffectDescription,
        parameterID: Int64
    ) -> Double {
        let (frame, length, fps) = evaluationContext(description)
        let span = definition.span.value(atFrame: frame, length: length, fps: fps)
        if span != 0 {
            return Animation.randomMoveRate(
                seed: definition.randomSeed,
                id: parameterID,
                frame: frame,
                fps: fps,
                span: span,
                seedOffset: Int64(description.inputIndex)
            )
        }
        return StatelessRandom.getDouble(keys: [
            definition.randomSeed,
            parameterID,
            Int64(frame),
            Int64(description.inputIndex),
        ])
    }

    /// 反復系のイージング値。Core の `RepeatEffectProcessorBase.easingValue`
    /// （本家 GetEasingValue）と同じ式を再掲する。Span = 0 の偶奇は
    /// 処理器側の実測（奇数フレーム = to）に従う。
    func repeatEasingValue(
        _ definition: RepeatEffectDefinitionBase,
        _ description: EffectDescription,
        from: Double,
        to: Double
    ) -> Double {
        let (frame, length, fps) = evaluationContext(description)
        let span = definition.span.value(atFrame: frame, length: length, fps: fps)
        let centerOffset = definition.isCentering ? -(to - from) / 2 : 0
        if span == 0 {
            return centerOffset + (frame % 2 != 0 ? to : from)
        }
        var seconds = description.itemDescription.itemPosition.time
        if definition.isCentering && definition.easingMode == .inOut {
            seconds += span / 4
        }
        let rate = Animation.repeatMoveRate(
            sec: seconds, span: span,
            family: definition.easingFamily, mode: definition.easingMode
        )
        return centerOffset + from + (to - from) * rate
    }

    /// 透視行列（本家の Transform3D チェーン末尾の固定行列。M34 = −0.001）。
    var perspectiveMatrix: Matrix4x4 {
        var matrix = Matrix4x4.identity
        matrix.m34 = -0.001
        return matrix
    }

    /// 行列が恒等かどうか（16要素の直接比較）。
    func isIdentity(_ matrix: Matrix4x4) -> Bool {
        matrix == .identity
    }

    /// 回転系の画像行列。本家 RotateEffect の非3D分岐:
    /// Scale(DrawDescription.Zoom, 原点) · Rz(Z°) · Ry(−Y°) · Rx(−X°) · 透視。
    /// 左端の変換が先に適用される（System.Numerics の行ベクトル規約）。
    func rotationBakeMatrix(zoom: Vector2, angleX: Double, angleY: Double, angleZ: Double) -> Matrix4x4 {
        let scale = Matrix4x4.createScale(x: zoom.x, y: zoom.y, z: 1, center: .zero)
        let rz = Matrix4x4.createRotationZ(angleZ * Double.pi / 180)
        let ry = Matrix4x4.createRotationY(-angleY * Double.pi / 180)
        let rx = Matrix4x4.createRotationX(-angleX * Double.pi / 180)
        return scale * rz * ry * rx * perspectiveMatrix
    }

    /// 回転系の画像焼き込みと戻り DrawDescription の対。
    /// 3D 分岐では画像は無変換で、回転は DrawDescription 側へ積む
    /// （本家 RotateEffect.Update の戻り値どおり）。
    func bakeRotation(
        input: MetalImage,
        description: EffectDescription,
        angleX: Double,
        angleY: Double,
        angleZ: Double,
        is3D: Bool
    ) throws -> MetalImage? {
        guard !is3D else { return input }
        let matrix = rotationBakeMatrix(
            zoom: description.drawDescription.zoom,
            angleX: angleX, angleY: angleY, angleZ: angleZ
        )
        guard !isIdentity(matrix) else { return input }
        let outputBounds = MetalDrawingEffect.boundingRect(of: input.bounds, transformedBy: matrix)
        return try renderTransformed(
            input: input, matrix: matrix, outputBounds: outputBounds,
            interpolation: description.drawDescription.zoomInterpolationMode
        )
    }

    /// 回転系の戻り DrawDescription（3D: 回転を加算、非3D: Zoom を等倍へ）。
    func rotationDrawDescription(
        _ description: EffectDescription,
        angleX: Double,
        angleY: Double,
        angleZ: Double,
        is3D: Bool
    ) -> DrawDescription {
        var result = description.drawDescription
        if is3D {
            result.rotation = Vector3(
                x: result.rotation.x + angleX,
                y: result.rotation.y + angleY,
                z: result.rotation.z + angleZ
            )
        } else {
            result.zoom = Vector2(x: 1, y: 1)
        }
        return result
    }

    /// 傾斜の中心点。本家 SkewEffect の switch（Center → 原点、
    /// Custom → パラメータ、他は入力境界の辺）どおり。
    func skewCenter(
        mode: SkewCenterPoint, centerX: Double, centerY: Double, bounds: RectF
    ) -> (x: Double, y: Double) {
        switch mode {
        case .center, .unknown:
            // unknown は定義の既定 (.center) として評価する（MAC-0018 の方針）。
            return (0, 0)
        case .custom:
            return (centerX, centerY)
        case .top:
            return (0, bounds.top)
        case .bottom:
            return (0, bounds.bottom)
        case .left:
            return (bounds.left, 0)
        case .right:
            return (bounds.right, 0)
        }
    }

    /// 傾斜行列。本家 Matrix3x2.CreateSkew(angleX, angleY, center) の
    /// 4x4 埋め込み（M12 = tan(angleY), M21 = tan(angleX),
    /// M41 = −cy・tan(angleX), M42 = −cx・tan(angleY)）。
    func skewMatrix(angleX: Double, angleY: Double, center: (x: Double, y: Double)) -> Matrix4x4 {
        let tanX = tan(angleX * Double.pi / 180)
        let tanY = tan(angleY * Double.pi / 180)
        return Matrix4x4(
            m11: 1, m12: tanY, m13: 0, m14: 0,
            m21: tanX, m22: 1, m23: 0, m24: 0,
            m31: 0, m32: 0, m33: 1, m34: 0,
            m41: -center.y * tanX, m42: -center.x * tanY, m43: 0, m44: 1
        )
    }

    /// 傾斜の画像焼き込み（本家 SkewEffect: AffineTransform2D のみ、
    /// DrawDescription は無変更）。
    func bakeSkew(
        input: MetalImage,
        description: EffectDescription,
        angleX: Double,
        angleY: Double,
        center: (x: Double, y: Double)
    ) throws -> MetalImage? {
        let matrix = skewMatrix(angleX: angleX, angleY: angleY, center: center)
        guard !isIdentity(matrix) else { return input }
        let outputBounds = MetalDrawingEffect.boundingRect(of: input.bounds, transformedBy: matrix)
        return try renderTransformed(
            input: input, matrix: matrix, outputBounds: outputBounds,
            interpolation: description.drawDescription.zoomInterpolationMode
        )
    }
}

/// 単色ブラシの色を取り出す（BRUSH46 で型付きモデルへ移行）。
/// ブラシ自体が無い場合は本家の既定（単色ブラシ・白:
/// SolidColorBrushParameter の初期色 Colors.White）として扱う。
/// 単色ブラシでないパラメータ（グラデーション等）と、オブジェクト
/// でない生値のブラシは nil を返し、呼び出し側がブラシ塗り経路
/// （`brushFillImage`）か素通しへ倒す。
func solidBrushColor(_ brush: Brush?) -> Color? {
    guard let brush else { return .white }
    guard brush.nonObjectRawValue == nil,
          case .solidColor(let parameter) = brush.parameter
    else { return nil }
    return parameter.color
}

extension MetalEffectProcessor {
    /// 型付きブラシの塗り画像を `outputBounds` 全体へ描く。
    /// 単色ブラシ（呼び出し側の既存経路が担当）と GPU で描けない
    /// ブラシ（グラデーションメッシュ・ノイズ・生保持）は nil で、
    /// 呼び出し側は素通しにする。`patternBounds` は本家がブラシの
    /// Update へ渡す境界（エフェクトごとに異なる）。
    func brushFillImage(
        brush: Brush?,
        patternBounds: RectF,
        outputBounds: RectF,
        description: EffectDescription
    ) throws -> MetalImage? {
        guard let brush else { return nil }
        let (frame, length, fps) = evaluationContext(description)
        guard let spec = MetalBrushFillRenderer.spec(
            brush: brush, patternBounds: patternBounds,
            frame: frame, length: length, fps: fps
        ) else { return nil }
        return try brushRenderer.render(spec: spec, outputBounds: outputBounds)
    }
}

/// "#AARRGGBB" 形式の色文字列を読む（本家の Color 保存形式）。
func parseARGBColor(_ text: String) -> Color? {
    var hex = text
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard hex.count == 8, let value = UInt32(hex, radix: 16) else { return nil }
    return Color(
        alpha: UInt8((value >> 24) & 0xFF),
        red: UInt8((value >> 16) & 0xFF),
        green: UInt8((value >> 8) & 0xFF),
        blue: UInt8(value & 0xFF)
    )
}

#endif
