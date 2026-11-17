#if os(macOS)
import Foundation
import Metal
import YMM4Core

/// 画面遷移アイテム（TransitionItem）の Source。本家 TransitionSource
/// に対応する（MAC-0036 / AUD-02）。
///
/// 本家の意味論（TransitionSource.cs / TransitionItemPicker.cs で実測）:
/// - 内部に TimelineSource を2つ持ち、それぞれ専用の文脈で回す。
///   Before 側のピッカーはアイテム選定だけを transitionItem.Frame − 1 に
///   固定し、両側とも更新時刻は現在時刻（選定アイテムのアニメーションは
///   静止しない）。
/// - 各側の合成結果は EffectedTimelineSource（合成画像を画面矩形で切り
///   抜き → Before/AfterVideoEffects の連鎖 → DrawingEffect）を通る。
///   切り抜きは、内部合成器の出力テクスチャ（画面サイズ）を画面矩形の
///   境界・平面範囲で登録し直すことで等価に実現し、連鎖は Core の
///   EffectedOutput（applyItemTransform = false）で実行する。
///   初期 DrawDescription は
///   本家が固定する恒等変換であり、TransitionItem の実効値の既定
///   （X/Y = 0、Zoom/Opacity = 100、フェードなし）でも同じ値になる。
/// - ブレンドは ITransitionSource が担う。本家はパラメータの参照が
///   変わったときだけ生成し直すが、こちらは合成器の描画先がフレーム
///   ごとに新しい参照になるため、ブレンドへは毎回その時点の前後画像を
///   渡す（内部差分。観測できる結果は変わらない）。ブレンド自体の
///   作り直しはパラメータの保持値が変わったときだけ行う（本家は参照
///   変化、こちらは値変化という内部差分）。
/// - 出力は Source 自身の DrawingEffect を持つ SourceOutput で公開する
///   （本家と同じ）。
public final class MetalTransitionSource: Source {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let item: TransitionItem
    private let drawingEffect: MetalDrawingEffect
    private let beforeComposer: TimelineComposer
    private let afterComposer: TimelineComposer
    private let beforeChain: EffectedOutput
    private let afterChain: EffectedOutput
    private let effectPairs: (TransitionItem, Bool) -> [EffectPair]
    private let emptyReference = ImageReference(label: "transition-source-empty")
    private let beforeScreenReference = ImageReference(label: "transition-before-screen")
    private let afterScreenReference = ImageReference(label: "transition-after-screen")
    private let emptyOutput: StandardSourceOutput
    private var output: StandardSourceOutput?
    private var currentOutputReference: ImageReference?
    private var blend: MetalTransitionBlend?
    private var blendParameterValue: PreservedObject?
    private var hasBlendParameter = false
    private var currentParameter: TransitionParameter?

    /// - Parameters:
    ///   - composerFactory: Before / After の内部合成器を生成する境界。
    ///     供給元が TransitionItemPicker（isBefore の別）を持つ合成器を、
    ///     渡された2つの文脈で構築する。
    ///   - effectPairsProvider: Before/AfterVideoEffects の定義供給。
    ///     nil の場合はこの Source が所有する型付き供給元を使う。
    public init(
        devices: MetalGraphicsDevices,
        item: TransitionItem,
        screenSize: PixelSize,
        composerFactory: (MetalGraphicsContext, MetalGraphicsContext)
            -> (before: TimelineComposer, after: TimelineComposer),
        effectPairsProvider: ((TransitionItem, Bool) -> [EffectPair])?
    ) {
        self.context = devices.makeContext()
        self.item = item
        self.drawingEffect = MetalDrawingEffect(context: context)
        context.targetSize = screenSize
        let composers = composerFactory(devices.makeContext(), devices.makeContext())
        self.beforeComposer = composers.before
        self.afterComposer = composers.after
        self.beforeChain = EffectedOutput(item: item)
        self.afterChain = EffectedOutput(item: item)
        if let effectPairsProvider {
            self.effectPairs = effectPairsProvider
        } else {
            let typed = TypedEffectPairProvider()
            self.effectPairs = { typed.transitionEffectPairs(for: $0, isBefore: $1) }
        }
        context.devices.register(
            emptyReference,
            image: MetalImage(
                texture: context.devices.transparentTexture,
                bounds: RectF(left: 0, top: 0, right: 1, bottom: 1)
            )
        )
        self.emptyOutput = StandardSourceOutput(
            output: emptyReference, drawingEffect: drawingEffect, dontDispose: true
        )
        self.outputs = [emptyOutput]
    }

    public func update(_ description: TimelineItemSourceDescription) throws {
        // 本家は2つの TimelineSource を並列に更新する。こちらは逐次だが、
        // 観測できる結果（各側の合成画像）は同じである。
        let time = TimeSpanValue(seconds: description.timelinePosition.time)
        try beforeComposer.update(time: time, usage: description.usage)
        try afterComposer.update(time: time, usage: description.usage)

        let beforeImage = try effectedImage(
            composer: beforeComposer, chain: beforeChain,
            description: description, isBefore: true
        )
        let afterImage = try effectedImage(
            composer: afterComposer, chain: afterChain,
            description: description, isBefore: false
        )

        // パラメータの保持値が変わったらブレンドを作り直す（本家は
        // パラメータ参照の変化で作り直す。内部差分として記録）。
        if !hasBlendParameter || blendParameterValue != item.transitionParameter {
            blend?.dispose()
            currentParameter = TransitionParameter.decode(item.transitionParameter)
            blend = MetalTransitionBlend.make(
                kind: currentParameter!.kind, context: context
            )
            blendParameterValue = item.transitionParameter
            hasBlendParameter = true
        }
        guard let blend, let parameter = currentParameter else {
            publish(emptyReference)
            return
        }
        // キーフレーム文脈は所有アイテム側の変化がありうるため毎回伝播する。
        parameter.applyKeyFrames(item.keyFrames)
        let blended = try blend.blend(
            before: beforeImage, after: afterImage,
            parameter: parameter, description: description
        )
        publish(blended)
    }

    public func dispose() {
        beforeComposer.dispose()
        afterComposer.dispose()
        beforeChain.dispose()
        afterChain.dispose()
        blend?.dispose()
        blend = nil
        drawingEffect.dispose()
        context.devices.unregister(emptyReference)
        context.devices.unregister(beforeScreenReference)
        context.devices.unregister(afterScreenReference)
        outputs = []
    }

    /// 画面矩形（中心原点）。
    private var screenRect: RectF {
        RectF(
            left: -Double(context.targetSize.width) / 2,
            top: -Double(context.targetSize.height) / 2,
            right: Double(context.targetSize.width) / 2,
            bottom: Double(context.targetSize.height) / 2
        )
    }

    /// 内部合成の出力へ Before/AfterVideoEffects の連鎖を適用する
    /// （本家 EffectedTimelineSource に対応）。
    ///
    /// 本家は連鎖の前に合成画像を画面矩形で切り抜く（Crop）。こちらでは
    /// 内部合成器の出力テクスチャは画面サイズだが、その登録の境界は
    /// 内容境界（画面より大きいアイテムでは画面を超える）であり、
    /// そのまま平行移動すると空いた側が端画素の引き伸ばしで埋まって
    /// しまう。そこで同じテクスチャを画面矩形の境界・平面範囲で
    /// 登録し直した参照を連鎖とブレンドへ渡し、切り抜きと等価にする。
    private func effectedImage(
        composer: TimelineComposer,
        chain: EffectedOutput,
        description: TimelineItemSourceDescription,
        isBefore: Bool
    ) throws -> ImageReference {
        guard let composed = composer.output,
              let composedImage = context.devices.image(for: composed)
        else { return emptyReference }
        let screenReference = isBefore ? beforeScreenReference : afterScreenReference
        context.devices.register(
            screenReference,
            image: MetalImage(
                texture: composedImage.texture,
                bounds: screenRect,
                texturePlaneRect: screenRect,
                opacity: composedImage.opacity,
                interpolation: composedImage.interpolation
            )
        )
        let input = StandardSourceOutput(
            output: screenReference, drawingEffect: nil, dontDispose: true
        )
        let pairs = effectPairs(item, isBefore).filter { $0.definition.isEnabled }
        try chain.update(
            inputIndex: 0, inputCount: 1, input: input,
            itemDescription: description, effects: pairs,
            applyItemTransform: false
        )
        return chain.preRenderOutput ?? screenReference
    }

    private func publish(_ reference: ImageReference) {
        if currentOutputReference !== reference {
            currentOutputReference = reference
            output = StandardSourceOutput(
                output: reference, drawingEffect: drawingEffect, dontDispose: true
            )
        }
        outputs = [output ?? emptyOutput]
    }
}

// MARK: - ブレンド（本家 ITransitionSource 群）

/// トランジションのブレンド実行部。本家 ITransitionSource に対応する。
///
/// 実装は MetalEffectProcessor を土台にし、その描画パス機械
/// （テクスチャ確保・1パス実行・2画像合成）を再利用する。処理器としての
/// update は使わない（入力が2枚あるため契約の形が違う）。
/// 出力境界は常に画面矩形（内部合成の出力と同じ平面範囲）。
class MetalTransitionBlend: MetalEffectProcessor {
    /// 画面矩形（中心原点）。
    var screenRect: RectF {
        RectF(
            left: -Double(context.targetSize.width) / 2,
            top: -Double(context.targetSize.height) / 2,
            right: Double(context.targetSize.width) / 2,
            bottom: Double(context.targetSize.height) / 2
        )
    }

    private var currentTarget: (any RenderTarget)?
    private let scratchReference = ImageReference(label: "transition-blend-scratch")

    /// 種別ごとのブレンド生成。RuleImage はシェーダ本体（外部のコンパイル
    /// 済みリソース）が逆コンパイル集合に含まれず閾値の法則が未確認の
    /// ため、未知方式（プラグイン）と合わせて差し替え点とし、Switch の
    /// 挙動へ倒す（台帳に記録）。
    static func make(kind: TransitionKind, context: MetalGraphicsContext) -> MetalTransitionBlend {
        switch kind {
        case .fade: return FadeTransitionBlend(context: context)
        case .none: return NoneTransitionBlend(context: context)
        case .slide: return SlideTransitionBlend(context: context)
        case .push: return PushTransitionBlend(context: context)
        case .doubleSlideDoor: return DoubleSlideDoorTransitionBlend(context: context)
        case .doubleOpenDoor: return DoubleOpenDoorTransitionBlend(context: context)
        case .slice: return SliceTransitionBlend(context: context)
        case .switchKind, .ruleImage, .unknown:
            return SwitchTransitionBlend(context: context)
        }
    }

    /// 前後画像を合成し、結果の画像参照を返す。
    func blend(
        before: ImageReference, after: ImageReference,
        parameter: TransitionParameter,
        description: TimelineItemSourceDescription
    ) throws -> ImageReference {
        before
    }

    /// 新しい描画先を用意する（前回のものは解放する）。本家の
    /// コマンドリスト作り直しに相当し、消費側が前フレームの出力を
    /// 読み終えた後のこのタイミングで解放しても安全である
    /// （EffectedItemSource の出力描画先と同じ所有形態）。
    func takeTarget() -> any RenderTarget {
        currentTarget?.dispose()
        let target = context.makeTarget()
        currentTarget = target
        return target
    }

    /// 画像を平面上で平行移動した姿で描くための登録（境界を +delta、
    /// planeOffset を −delta ずらす。MetalCompositeSource の中心ずらしと
    /// 同じ写像）。描画は記録時点で実体を解決するため、描いた直後に
    /// 登録を上書きしてもよい。
    func shifted(_ reference: ImageReference, by delta: Vector2) -> ImageReference? {
        guard let image = context.devices.image(for: reference) else { return nil }
        context.devices.register(
            scratchReference,
            image: MetalImage(
                texture: image.texture,
                bounds: RectF(
                    left: image.bounds.left + delta.x, top: image.bounds.top + delta.y,
                    right: image.bounds.right + delta.x, bottom: image.bounds.bottom + delta.y
                ),
                texturePlaneRect: image.texturePlaneRect,
                planeOffset: Vector2(
                    x: image.planeOffset.x - delta.x, y: image.planeOffset.y - delta.y
                ),
                transform: image.transform,
                opacity: image.opacity,
                interpolation: image.interpolation
            )
        )
        return scratchReference
    }

    /// 画像へ変換行列を適用した姿で描くための登録（扉の開閉用）。
    func transformed(_ reference: ImageReference, by transform: Matrix4x4) -> ImageReference? {
        guard let image = context.devices.image(for: reference) else { return nil }
        context.devices.register(
            scratchReference,
            image: MetalImage(
                texture: image.texture,
                bounds: image.bounds,
                texturePlaneRect: image.texturePlaneRect,
                planeOffset: image.planeOffset,
                transform: transform,
                opacity: image.opacity,
                interpolation: image.interpolation
            )
        )
        return scratchReference
    }

    /// 白い四角形（平面座標・周回順の4点）を画面サイズのマスク
    /// テクスチャへ描く。ドアとスライスのマスク生成で共有する。
    func makeMaskTexture(corners: [Vector2]) throws -> MTLTexture {
        let width = max(1, context.targetSize.width)
        let height = max(1, context.targetSize.height)
        let texture = try makeTexture(
            width: width, height: height, usage: [.renderTarget, .shaderRead]
        )
        let halfWidth = Double(width) / 2
        let halfHeight = Double(height) / 2
        // 三角形ストリップの順序（左上・右上・左下・右下）に並べ替える。
        let order = [corners[0], corners[1], corners[3], corners[2]]
        let vertices: [QuadVertex] = order.map { point in
            QuadVertex(
                position: SIMD4<Float>(
                    Float(point.x / halfWidth), Float(-point.y / halfHeight), 0, 1
                ),
                uv: SIMD2<Float>(0, 0)
            )
        }
        var color = SIMD4<Float>(1, 1, 1, 1)
        try executePass(
            output: texture, pipeline: context.devices.solidPipeline, vertices: vertices
        ) { encoder in
            encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        }
        return texture
    }

    /// マスク画像（画面矩形の白画像）で入力画像を切り取る
    /// （本家 AlphaMask の可視結果。合成シェーダのマスク乗算モード）。
    func masked(_ input: ImageReference, maskTexture: MTLTexture) throws -> MetalImage? {
        guard let inputImage = context.devices.image(for: input) else { return nil }
        let maskImage = MetalImage(texture: maskTexture, bounds: screenRect)
        return try renderComposite(
            top: maskImage, bottom: inputImage,
            outputBounds: screenRect, mode: 3
        )
    }

    override func dispose() {
        currentTarget?.dispose()
        currentTarget = nil
        context.devices.unregister(scratchReference)
        super.dispose()
    }
}

/// 切り替え。本家 SwitchTransitionSource に対応する。
/// 中点より前は Before、中点以降は After の画像そのものを返す。
final class SwitchTransitionBlend: MetalTransitionBlend {
    override func blend(
        before: ImageReference, after: ImageReference,
        parameter: TransitionParameter,
        description: TimelineItemSourceDescription
    ) throws -> ImageReference {
        let frame = Double(description.itemPosition.frame)
        let duration = Double(description.itemDuration.frame)
        return frame < duration / 2 ? before : after
    }
}

/// フェード。本家 FadeTransitionSource に対応する。
/// D2D CrossFade の式（Microsoft Learn で確認）:
/// output = Weight × Destination + (1 − Weight) × Source。
/// 入力0 = After（Destination）、入力1 = Before（Source）、
/// Weight = イージング済み進行率。したがって
/// output = After × rate + Before × (1 − rate) であり、合成シェーダの
/// 加重和モードで Premultiplied のまま加算する。
final class FadeTransitionBlend: MetalTransitionBlend {
    private let outputReference = ImageReference(label: "transition-fade")

    override func blend(
        before: ImageReference, after: ImageReference,
        parameter: TransitionParameter,
        description: TimelineItemSourceDescription
    ) throws -> ImageReference {
        guard let beforeImage = context.devices.image(for: before),
              let afterImage = context.devices.image(for: after)
        else { return before }
        let rate = parameter.easedRate(
            frame: description.itemPosition.frame,
            duration: description.itemDuration.frame
        )
        let blended = try renderComposite(
            top: afterImage, bottom: beforeImage,
            outputBounds: screenRect, mode: 2,
            opacityTop: rate, opacityBottom: 1 - rate
        )
        context.devices.register(outputReference, image: blended)
        return outputReference
    }

    override func dispose() {
        context.devices.unregister(outputReference)
        super.dispose()
    }
}

/// 重ね合わせ（ブレンドなし）。本家 NoneTransitionSource に対応する。
/// OverlayTarget が After なら Before → After の順、Before なら
/// After → Before の順に通常合成で重ねる。
final class NoneTransitionBlend: MetalTransitionBlend {
    override func blend(
        before: ImageReference, after: ImageReference,
        parameter: TransitionParameter,
        description: TimelineItemSourceDescription
    ) throws -> ImageReference {
        let target = takeTarget()
        target.beginDraw()
        target.clear()
        if parameter.target == .after {
            target.drawImage(before)
            target.drawImage(after)
        } else {
            target.drawImage(after)
            target.drawImage(before)
        }
        target.endDraw()
        try target.close()
        return target.image
    }
}

/// スライド。本家 SlideTransitionSource に対応する。
/// Target が Before なら After を下地に Before を delta × rate だけ
/// ずらして重ね、After なら Before を下地に After を
/// −delta × (1 − rate) だけずらして重ねる。
final class SlideTransitionBlend: MetalTransitionBlend {
    override func blend(
        before: ImageReference, after: ImageReference,
        parameter: TransitionParameter,
        description: TimelineItemSourceDescription
    ) throws -> ImageReference {
        let frame = description.itemPosition.frame
        let duration = description.itemDuration.frame
        let rate = parameter.easedRate(frame: frame, duration: duration)
        let angle = parameter.angle.value(atFrame: frame, length: duration, fps: description.fps)
        let delta = TransitionGeometry.slideDirectionVector(
            angleDegrees: angle, screenSize: description.screenSize
        )
        let target = takeTarget()
        target.beginDraw()
        target.clear()
        if parameter.target == .before {
            target.drawImage(after)
            if let moved = shifted(before, by: TransitionGeometry.scale(delta, rate)) {
                target.drawImage(moved)
            }
        } else {
            target.drawImage(before)
            if let moved = shifted(after, by: TransitionGeometry.scale(delta, -(1 - rate))) {
                target.drawImage(moved)
            }
        }
        target.endDraw()
        try target.close()
        return target.image
    }
}

/// プッシュ。本家 PushTransitionSource に対応する。
/// After を −delta × (1 − rate)、Before を delta × rate へずらして
/// After → Before の順に描く（両画面が一緒に押し出される）。
final class PushTransitionBlend: MetalTransitionBlend {
    override func blend(
        before: ImageReference, after: ImageReference,
        parameter: TransitionParameter,
        description: TimelineItemSourceDescription
    ) throws -> ImageReference {
        let frame = description.itemPosition.frame
        let duration = description.itemDuration.frame
        let rate = parameter.easedRate(frame: frame, duration: duration)
        let angle = parameter.angle.value(atFrame: frame, length: duration, fps: description.fps)
        let delta = TransitionGeometry.slideDirectionVector(
            angleDegrees: angle, screenSize: description.screenSize
        )
        let target = takeTarget()
        target.beginDraw()
        target.clear()
        if let moved = shifted(after, by: TransitionGeometry.scale(delta, -(1 - rate))) {
            target.drawImage(moved)
        }
        if let moved = shifted(before, by: TransitionGeometry.scale(delta, rate)) {
            target.drawImage(moved)
        }
        target.endDraw()
        try target.close()
        return target.image
    }
}

/// ドア系（スライドドア／開きドア）の共通部。本家 DoorResources に
/// 対応するマスク（画面を斜めの直線で割った半面）を生成する。
/// Target が Before なら入力 = Before・下地 = After、After なら
/// 入力 = After・下地 = Before で進行率を 1 − rate に反転する
/// （本家の分岐どおり）。
class DoorTransitionBlend: MetalTransitionBlend {
    private var maskAngle: Double?
    private var leftMask: MTLTexture?
    private var rightMask: MTLTexture?

    /// マスク済み画像の組（左扉・右扉）と下地・進行率を用意する。
    func prepareDoors(
        before: ImageReference, after: ImageReference,
        parameter: TransitionParameter,
        description: TimelineItemSourceDescription
    ) throws -> (base: ImageReference, left: MetalImage, right: MetalImage, rate: Double, delta: Vector2)? {
        let frame = description.itemPosition.frame
        let duration = description.itemDuration.frame
        var rate = parameter.easedRate(frame: frame, duration: duration)
        let angleDegrees = parameter.angle.value(
            atFrame: frame, length: duration, fps: description.fps
        )
        let angle = TransitionGeometry.doorAngle(angleDegrees: angleDegrees)
        let input: ImageReference
        let base: ImageReference
        if parameter.target == .before {
            input = before
            base = after
        } else {
            input = after
            base = before
            rate = 1 - rate
        }
        if maskAngle != angle {
            maskAngle = angle
            let points = TransitionGeometry.doorPoints(
                angle: angle, screenSize: description.screenSize
            )
            leftMask = try makeMaskTexture(
                corners: points.map { Vector2(x: -$0.x, y: -$0.y) }
            )
            rightMask = try makeMaskTexture(corners: points)
        }
        guard let leftMask, let rightMask,
              let left = try masked(input, maskTexture: leftMask),
              let right = try masked(input, maskTexture: rightMask)
        else { return nil }
        let delta = TransitionGeometry.doorDelta(
            angle: angle, screenSize: description.screenSize
        )
        return (base, left, right, rate, delta)
    }

    override func dispose() {
        leftMask = nil
        rightMask = nil
        maskAngle = nil
        super.dispose()
    }
}

/// 両開きスライドドア。本家 DoubleSlideDoorTransitionSource に対応する。
/// 左右の扉（マスク済み入力）を GetDelta × rate だけ互いに逆向きへ
/// 平行移動して下地の上に描く。
final class DoubleSlideDoorTransitionBlend: DoorTransitionBlend {
    override func blend(
        before: ImageReference, after: ImageReference,
        parameter: TransitionParameter,
        description: TimelineItemSourceDescription
    ) throws -> ImageReference {
        guard let doors = try prepareDoors(
            before: before, after: after, parameter: parameter, description: description
        ) else { return before }
        // マスク済み画像のテクスチャは、この描画先が閉じるまで保持する。
        let keepAlive = [doors.left, doors.right]
        let target = takeTarget()
        target.beginDraw()
        target.clear()
        target.drawImage(doors.base)
        let leftReference = ImageReference(label: "transition-door-left")
        let rightReference = ImageReference(label: "transition-door-right")
        context.devices.register(leftReference, image: doors.left)
        context.devices.register(rightReference, image: doors.right)
        if let moved = shifted(
            leftReference,
            by: TransitionGeometry.scale(doors.delta, -doors.rate)
        ) {
            target.drawImage(moved)
        }
        if let moved = shifted(
            rightReference,
            by: TransitionGeometry.scale(doors.delta, doors.rate)
        ) {
            target.drawImage(moved)
        }
        target.endDraw()
        try target.close()
        context.devices.unregister(leftReference)
        context.devices.unregister(rightReference)
        _ = keepAlive
        return target.image
    }
}

/// 両開きドア（回転）。本家 DoubleOpenDoorTransitionSource に対応する。
/// 左右の扉を、それぞれの外端を蝶番として rate × 90° だけ
/// Y 回転／X 回転させ、透視（M34 = −0.001）を掛けて描く。
/// 回転中心つき行列は .NET の CreateRotation*(angle, center) と同じ
/// 「中心へ移して回転し戻す」合成で作る。
final class DoubleOpenDoorTransitionBlend: DoorTransitionBlend {
    override func blend(
        before: ImageReference, after: ImageReference,
        parameter: TransitionParameter,
        description: TimelineItemSourceDescription
    ) throws -> ImageReference {
        guard let doors = try prepareDoors(
            before: before, after: after, parameter: parameter, description: description
        ) else { return before }
        let keepAlive = [doors.left, doors.right]
        let delta = doors.delta
        let length = max(1e-9, hypot(delta.x, delta.y))
        let unit = Vector2(x: delta.x / length, y: delta.y / length)
        let width = Double(description.screenSize.width)
        let height = Double(description.screenSize.height)
        let perspective = Matrix4x4(
            m11: 1, m12: 0, m13: 0, m14: 0,
            m21: 0, m22: 1, m23: 0, m24: 0,
            m31: 0, m32: 0, m33: 1, m34: -0.001,
            m41: 0, m42: 0, m43: 0, m44: 1
        )
        let leftCenter = Vector3(
            x: -width / 2 * unit.x, y: -height / 2 * unit.y, z: 0
        )
        let rightCenter = Vector3(
            x: width / 2 * unit.x, y: height / 2 * unit.y, z: 0
        )
        let leftTransform = TransitionGeometry.rotationY(
                -.pi / 2 * doors.rate * unit.x, center: leftCenter)
            * TransitionGeometry.rotationX(
                .pi / 2 * doors.rate * unit.y, center: leftCenter)
            * perspective
        let rightTransform = TransitionGeometry.rotationY(
                .pi / 2 * doors.rate * unit.x, center: rightCenter)
            * TransitionGeometry.rotationX(
                -.pi / 2 * doors.rate * unit.y, center: rightCenter)
            * perspective
        let leftReference = ImageReference(label: "transition-door-left")
        let rightReference = ImageReference(label: "transition-door-right")
        context.devices.register(leftReference, image: doors.left)
        context.devices.register(rightReference, image: doors.right)
        let target = takeTarget()
        target.beginDraw()
        target.clear()
        target.drawImage(doors.base)
        if let rotated = transformed(leftReference, by: leftTransform) {
            target.drawImage(rotated)
        }
        if let rotated = transformed(rightReference, by: rightTransform) {
            target.drawImage(rotated)
        }
        target.endDraw()
        try target.close()
        context.devices.unregister(leftReference)
        context.devices.unregister(rightReference)
        _ = keepAlive
        return target.image
    }
}

/// スライス。本家 SliceTransitionSource に対応する。
/// 画面を角度つきの帯に切り、各帯の入力画像を帯ごとの進行率で
/// 方向ベクトル沿いにずらして下地の上に描く。帯ごとの進行率は
/// 本家の SliceTransitionSource の算出（開始位置のリマップ、Shift に
/// よる遅延の圧縮、帯ごとのイージング）をそのまま移した。
final class SliceTransitionBlend: MetalTransitionBlend {
    private var maskKey: MaskKey?
    private var masks: [MTLTexture] = []

    private struct MaskKey: Equatable {
        var slices: Int
        var angle: Double
        var width: Int
        var height: Int
    }

    override func blend(
        before: ImageReference, after: ImageReference,
        parameter: TransitionParameter,
        description: TimelineItemSourceDescription
    ) throws -> ImageReference {
        let frame = description.itemPosition.frame
        let duration = description.itemDuration.frame
        let fps = description.fps
        let slices = max(1, Int(parameter.slices.value(
            atFrame: frame, length: duration, fps: fps
        )))
        let shift = parameter.shift.value(atFrame: frame, length: duration, fps: fps) / 100
        let angleDegrees = parameter.angle.value(atFrame: frame, length: duration, fps: fps)
        let angle = TransitionGeometry.doorAngle(angleDegrees: angleDegrees)
        let rates = sliceRates(
            slices: slices, frame: frame, duration: duration, shift: shift,
            start: parameter.start, direction: parameter.direction,
            parameter: parameter
        )
        let input = parameter.target == .before ? before : after
        let base = parameter.target == .before ? after : before

        let key = MaskKey(
            slices: slices, angle: angle,
            width: description.screenSize.width, height: description.screenSize.height
        )
        if maskKey != key {
            maskKey = key
            masks = try makeSliceMasks(
                slices: slices, angle: angle, screenSize: description.screenSize
            )
        }

        let delta = TransitionGeometry.slideDirectionVector(
            angleRadians: angle, screenSize: description.screenSize
        )
        var keepAlive: [MetalImage] = []
        let target = takeTarget()
        target.beginDraw()
        target.clear()
        target.drawImage(base)
        let stripReference = ImageReference(label: "transition-slice-strip")
        for index in 0..<slices {
            guard index < masks.count,
                  let strip = try masked(input, maskTexture: masks[index])
            else { continue }
            keepAlive.append(strip)
            context.devices.register(stripReference, image: strip)
            let factor = parameter.target == .before ? rates[index] : 1 - rates[index]
            if let moved = shifted(
                stripReference, by: TransitionGeometry.scale(delta, factor)
            ) {
                target.drawImage(moved)
            }
        }
        target.endDraw()
        try target.close()
        context.devices.unregister(stripReference)
        _ = keepAlive
        return target.image
    }

    /// 帯ごとの進行率（符号つき）。本家の算出どおり、開始位置で
    /// インデックスを並べ替え、Shift で遅延を圧縮してから帯ごとに
    /// イージングを適用する。
    private func sliceRates(
        slices: Int, frame: Int, duration: Int, shift: Double,
        start: SliceAnimationStart, direction: SliceAnimationDirection,
        parameter: TransitionParameter
    ) -> [Double] {
        let groupCount = (start == .center || start == .outside)
            ? Int(ceil(Double(slices) / 2)) : slices
        return (0..<slices).map { index in
            let remapped: Int
            switch start {
            case .left: remapped = slices - index - 1
            case .right: remapped = index
            case .center:
                remapped = index < groupCount
                    ? groupCount - index - 1 : index - slices / 2
            case .outside:
                remapped = index < groupCount ? index : slices - index - 1
            }
            let sliceDuration = Double(duration) / Double(groupCount)
            let shiftAmount = sliceDuration * shift
            let total = shiftAmount * Double(groupCount - 1) + sliceDuration
            let scale = total > 0 ? Double(duration) / total : 0
            let startOffset = shiftAmount * Double(remapped) * scale
            let localDuration = sliceDuration * scale
            let progress = localDuration > 0
                ? min(1, max(0, (Double(frame) - startOffset) / localDuration)) : 0
            let eased = EasingFamily.getValue(
                family: parameter.easingFamily, mode: parameter.easingMode,
                rate: progress
            )
            switch direction {
            case .down: return eased
            case .up: return -eased
            case .alternating: return eased * Double(index % 2 * 2 - 1)
            }
        }
    }

    /// 帯マスクの列。本家 SliceResources に対応する: 被覆矩形を帯の
    /// 高さで割り、各帯の矩形を「帯方向へ平行移動 → 角度だけ回転」
    /// （.NET Matrix3x2 の行ベクトル合成順）した四角形を白で描く。
    private func makeSliceMasks(
        slices: Int, angle: Double, screenSize: PixelSize
    ) throws -> [MTLTexture] {
        let width = Double(screenSize.width)
        let height = Double(screenSize.height)
        var maskAngle = angle
        if maskAngle > .pi / 2 { maskAngle = .pi - maskAngle }
        let coveredWidth = width * cos(maskAngle) + height * sin(maskAngle)
        let coveredHeight = (width * sin(maskAngle) + height * cos(maskAngle))
            / Double(slices)
        let cosA = cos(angle)
        let sinA = sin(angle)
        var result: [MTLTexture] = []
        for index in 0..<slices {
            let translateY = floor(-coveredHeight * Double(slices - 1) / 2)
                + ceil(coveredHeight * Double(index))
            let rect: [Vector2] = [
                Vector2(x: -coveredWidth / 2, y: floor(-coveredHeight / 2)),
                Vector2(x: coveredWidth / 2, y: floor(-coveredHeight / 2)),
                Vector2(x: coveredWidth / 2, y: ceil(coveredHeight / 2)),
                Vector2(x: -coveredWidth / 2, y: ceil(coveredHeight / 2)),
            ]
            // 平行移動 → 回転（.NET Matrix3x2.CreateTranslation *
            // CreateRotation の行ベクトル順）。
            let corners = rect.map { point -> Vector2 in
                let moved = Vector2(x: point.x, y: point.y + translateY)
                return Vector2(
                    x: moved.x * cosA - moved.y * sinA,
                    y: moved.x * sinA + moved.y * cosA
                )
            }
            result.append(try makeMaskTexture(corners: corners))
        }
        return result
    }

    override func dispose() {
        masks = []
        maskKey = nil
        super.dispose()
    }
}

// MARK: - 幾何（本家の式の移し替え）

/// トランジションの幾何計算。本家 SlideTransitionSource /
/// PushTransitionSource / DoorResources / SliceResources に重複して
/// 現れる式を、意味を変えずにここへ一本化した。
enum TransitionGeometry {
    static func scale(_ vector: Vector2, _ factor: Double) -> Vector2 {
        Vector2(x: vector.x * factor, y: vector.y * factor)
    }

    /// 角度（度）→ 方向ベクトル。本家 Slide / Push の象限分岐どおり。
    /// ベクトルの大きさは「画面を横切る距離」であり、正規化しない。
    static func slideDirectionVector(
        angleDegrees: Double, screenSize: PixelSize
    ) -> Vector2 {
        var radians = angleDegrees / 180 * .pi
        radians = radians.truncatingRemainder(dividingBy: 2 * .pi)
        if radians < 0 { radians += 2 * .pi }
        return slideDirectionVector(angleRadians: radians, screenSize: screenSize)
    }

    static func slideDirectionVector(
        angleRadians: Double, screenSize: PixelSize
    ) -> Vector2 {
        let width = Double(screenSize.width)
        let height = Double(screenSize.height)
        let angle = angleRadians
        let corner = atan(height / width)
        let second = .pi - corner
        let third = .pi + corner
        let fourth = 2 * .pi - corner
        if angle < corner {
            return Vector2(x: width, y: tan(angle) * width)
        } else if angle < second {
            return Vector2(x: height / tan(angle), y: height)
        } else if angle < third {
            return Vector2(x: -width, y: -tan(angle) * width)
        } else {
            return angle < fourth
                ? Vector2(x: -height / tan(angle), y: -height)
                : Vector2(x: width, y: tan(angle) * width)
        }
    }

    /// ドア／スライスの角度。本家は −Angle をラジアン化して π/2 を加え、
    /// [0, π) へ正規化する。
    static func doorAngle(angleDegrees: Double) -> Double {
        var angle = -angleDegrees / 180 * .pi + .pi / 2
        angle = angle.truncatingRemainder(dividingBy: .pi)
        if angle < 0 { angle += .pi }
        return angle
    }

    /// 扉マスクの四角形（周回順）。本家 DoorResources.GetPoints どおり。
    static func doorPoints(angle: Double, screenSize: PixelSize) -> [Vector2] {
        let width = Double(screenSize.width)
        let height = Double(screenSize.height)
        let corner = atan(height / width)
        let second = .pi - corner
        if angle < corner {
            return [
                Vector2(x: width / 2, y: -tan(angle) * width / 2),
                Vector2(x: width / 2, y: height / 2),
                Vector2(x: -width / 2, y: height / 2),
                Vector2(x: -width / 2, y: tan(angle) * width / 2),
            ]
        } else if angle < second {
            return [
                Vector2(x: height / 2 / tan(angle), y: -height / 2),
                Vector2(x: width / 2, y: -height / 2),
                Vector2(x: width / 2, y: height / 2),
                Vector2(x: -height / 2 / tan(angle), y: height / 2),
            ]
        } else {
            return [
                Vector2(x: -width / 2, y: tan(angle) * width / 2),
                Vector2(x: -width / 2, y: -height / 2),
                Vector2(x: width / 2, y: -height / 2),
                Vector2(x: width / 2, y: -tan(angle) * width / 2),
            ]
        }
    }

    /// 扉の移動量。本家 DoorResources.GetDelta どおり（正規化しない）。
    static func doorDelta(angle: Double, screenSize: PixelSize) -> Vector2 {
        let width = Double(screenSize.width)
        let height = Double(screenSize.height)
        let corner = atan(height / width)
        let second = .pi - corner
        if angle < corner {
            return Vector2(x: 0, y: tan(angle) * width / 2 + height / 2)
        } else if angle < .pi / 2 {
            return Vector2(x: width / 2 + height / 2 / tan(angle), y: 0)
        } else if angle < second {
            return Vector2(x: width / 2 - height / 2 / tan(angle), y: 0)
        } else {
            return Vector2(x: 0, y: tan(angle) * width / 2 - height / 2)
        }
    }

    /// 中心つき Y 回転（.NET CreateRotationY(angle, center) と同じ合成）。
    static func rotationY(_ radians: Double, center: Vector3) -> Matrix4x4 {
        Matrix4x4.createTranslation(x: -center.x, y: -center.y, z: -center.z)
            * Matrix4x4.createRotationY(radians)
            * Matrix4x4.createTranslation(center)
    }

    /// 中心つき X 回転（.NET CreateRotationX(angle, center) と同じ合成）。
    static func rotationX(_ radians: Double, center: Vector3) -> Matrix4x4 {
        Matrix4x4.createTranslation(x: -center.x, y: -center.y, z: -center.z)
            * Matrix4x4.createRotationX(radians)
            * Matrix4x4.createTranslation(center)
    }
}
#endif
