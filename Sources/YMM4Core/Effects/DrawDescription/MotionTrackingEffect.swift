import Foundation

/// トラッキング対象。本家 `MotionTrackingTarget`（保存はメンバ名文字列）。
public enum MotionTrackingTarget: HonkeEnum {
    case background
    case currentItem
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .background: return "Background"
        case .currentItem: return "CurrentItem"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Background": self = .background
        case "CurrentItem": self = .currentItem
        default: self = .unknown(name)
        }
    }
}

/// トラッキング矩形1件。本家 `MotionTrackingRect` に対応する。
///
/// 保存キーは本家のプロパティ宣言順（Top / Bottom / Left / Right /
/// IsTracking)。本家には get 専用の `Display`（整形済み文字列）もあり、
/// Newtonsoft が書き出す可能性があるが、こちらでは未知キーとして
/// `additionalFields` に保持して書き戻す（値の再計算はしない）。
public struct MotionTrackingRectValue: Equatable, Sendable {
    public var top: Double = -50
    public var bottom: Double = 50
    public var left: Double = -50
    public var right: Double = 50
    public var isTracking: Bool = false
    /// 型付けしていないキーの生保持。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init(
        top: Double = -50, bottom: Double = 50,
        left: Double = -50, right: Double = 50,
        isTracking: Bool = false
    ) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
        self.isTracking = isTracking
    }

    /// 幅（本家 Width = Right - Left）。
    public var width: Double { right - left }
    /// 高さ（本家 Height = Bottom - Top）。
    public var height: Double { bottom - top }
    /// 中心。
    public var center: Vector2 {
        Vector2(x: (left + right) / 2, y: (top + bottom) / 2)
    }

    public static func == (lhs: MotionTrackingRectValue, rhs: MotionTrackingRectValue) -> Bool {
        lhs.top == rhs.top && lhs.bottom == rhs.bottom
            && lhs.left == rhs.left && lhs.right == rhs.right
            && lhs.isTracking == rhs.isTracking
            && lhs.additionalFields.count == rhs.additionalFields.count
            && zip(lhs.additionalFields, rhs.additionalFields).allSatisfy {
                $0.key == $1.key && $0.value == $1.value
            }
    }

    /// 文書順に読み込む。
    public mutating func decodeFields(_ fields: [(key: String, value: JSONValue)]) {
        for (key, value) in fields {
            switch key {
            case "Top":
                top = CodecSupport.double(value, default: -50)
            case "Bottom":
                bottom = CodecSupport.double(value, default: 50)
            case "Left":
                left = CodecSupport.double(value, default: -50)
            case "Right":
                right = CodecSupport.double(value, default: 50)
            case "IsTracking":
                isTracking = CodecSupport.bool(value, default: false)
            default:
                additionalFields.append((key: key, value: value))
            }
        }
    }

    public func encode() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "Top", value: .number(top)),
            (key: "Bottom", value: .number(bottom)),
            (key: "Left", value: .number(left)),
            (key: "Right", value: .number(right)),
            (key: "IsTracking", value: .bool(isTracking)),
        ]
        let known: Set<String> = ["Top", "Bottom", "Left", "Right", "IsTracking"]
        fields += additionalFields.filter { !known.contains($0.key) }
        return .object(fields)
    }
}

/// トラッキング経路。本家 `MotionTrackingPreprocessedPath` に対応する。
///
/// 保存キーは Target / Rects / AlgorithmName。`AlgorithmIndex` は旧形式の
/// set 専用キーで、読み込み時にインデックス表から AlgorithmName へ変換
/// される（書き出しはしない）。`IsEditing` は本家で [JsonIgnore] の
/// 実行時状態であり、保存対象ではない。
public struct MotionTrackingPathValue: Equatable, Sendable {
    /// 対象（既定 Background）。
    public var target: MotionTrackingTarget = .background
    /// フレーム毎の矩形列。
    public var rects: [MotionTrackingRectValue] = []
    /// トラッキングアルゴリズム名（既定 "CSRT"）。
    public var algorithmName: String = "CSRT"
    /// 編集中か（実行時状態。保存しない）。
    public var isEditing: Bool = false
    /// 型付けしていないキーの生保持。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    /// 旧形式インデックス → アルゴリズム名の表（本家の legacyAlgorithmNames）。
    private static let legacyAlgorithmNames = ["CSRT", "CSRT", "DaSiamRPN", "Nano", "Vit"]

    public static func == (lhs: MotionTrackingPathValue, rhs: MotionTrackingPathValue) -> Bool {
        lhs.target == rhs.target && lhs.rects == rhs.rects
            && lhs.algorithmName == rhs.algorithmName && lhs.isEditing == rhs.isEditing
            && lhs.additionalFields.count == rhs.additionalFields.count
            && zip(lhs.additionalFields, rhs.additionalFields).allSatisfy {
                $0.key == $1.key && $0.value == $1.value
            }
    }

    /// 文書順に読み込む（AlgorithmIndex の変換は出現位置で効くため順序が意味を持つ）。
    public mutating func decodeFields(_ fields: [(key: String, value: JSONValue)]) {
        for (key, value) in fields {
            switch key {
            case "Target":
                target = CodecSupport.enumeration(value, default: MotionTrackingTarget.background)
            case "Rects":
                if let elements = value.arrayValue {
                    rects = elements.map { element in
                        var rect = MotionTrackingRectValue()
                        if let rectFields = element.objectFields {
                            rect.decodeFields(rectFields)
                        }
                        return rect
                    }
                }
            case "AlgorithmName":
                algorithmName = CodecSupport.string(value, default: "CSRT")
            case "AlgorithmIndex":
                // set 専用の旧互換キー。範囲外は "CSRT"。
                let index = CodecSupport.int(value, default: 0)
                algorithmName = (0..<Self.legacyAlgorithmNames.count).contains(index)
                    ? Self.legacyAlgorithmNames[index]
                    : "CSRT"
            default:
                additionalFields.append((key: key, value: value))
            }
        }
    }

    public func encode() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "Target", value: .string(target.honkeName)),
            (key: "Rects", value: .array(rects.map { $0.encode() })),
            (key: "AlgorithmName", value: .string(algorithmName)),
        ]
        let known: Set<String> = ["Target", "Rects", "AlgorithmName", "AlgorithmIndex"]
        fields += additionalFields.filter { !known.contains($0.key) }
        return .object(fields)
    }
}

/// モーショントラッキング。本家 `MotionTrackingEffect`。
///
/// パラメータ（実測）: Smooth は Int(既定 0)、IsReverce / IsReverseZoom /
/// IsFixedSize は bool（既定 false。IsReverce は本家の綴りのまま)、
/// Path は MotionTrackingPreprocessedPath、ControlPointVisibleSeconds は
/// double（既定 1.0)、IsOnlyCurrentFrameRectLine は bool（既定 true)。
public final class MotionTrackingEffectDefinition: VideoEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.MotionTrackingEffect, YukkuriMovieMaker"
    }

    /// 平滑化の範囲（前後のフレーム数）。
    public var smooth: Int = 0
    /// 移動を反転するか（本家のプロパティ名の綴りのまま）。
    public var isReverce: Bool = false
    /// 拡縮を反転するか。
    public var isReverseZoom: Bool = false
    /// サイズを固定するか（拡縮を適用しない）。
    public var isFixedSize: Bool = false
    /// トラッキング経路。
    public var path = MotionTrackingPathValue()
    /// 操作点を表示する前後の秒数。
    public var controlPointVisibleSeconds: Double = 1.0
    /// 現在フレームの矩形枠だけを表示するか。
    public var isOnlyCurrentFrameRectLine: Bool = true

    public override func createProcessor() -> any VideoEffectProcessor {
        MotionTrackingEffectProcessor(definition: self)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Smooth":
            smooth = CodecSupport.int(value, default: 0)
            return true
        case "IsReverce":
            isReverce = CodecSupport.bool(value, default: false)
            return true
        case "IsReverseZoom":
            isReverseZoom = CodecSupport.bool(value, default: false)
            return true
        case "IsFixedSize":
            isFixedSize = CodecSupport.bool(value, default: false)
            return true
        case "Path":
            if let fields = value.objectFields {
                path.decodeFields(fields)
            }
            return true
        case "ControlPointVisibleSeconds":
            controlPointVisibleSeconds = CodecSupport.double(value, default: 1.0)
            return true
        case "IsOnlyCurrentFrameRectLine":
            isOnlyCurrentFrameRectLine = CodecSupport.bool(value, default: true)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Smooth", value: .number(smooth)),
            (key: "IsReverce", value: .bool(isReverce)),
            (key: "IsReverseZoom", value: .bool(isReverseZoom)),
            (key: "IsFixedSize", value: .bool(isFixedSize)),
            (key: "Path", value: path.encode()),
            (key: "ControlPointVisibleSeconds", value: .number(controlPointVisibleSeconds)),
            (key: "IsOnlyCurrentFrameRectLine", value: .bool(isOnlyCurrentFrameRectLine)),
        ] + super.encodeKnownFields()
    }
}

/// 本家 `MotionTrackingEffectProcessor` 処理器。
///
/// 先頭矩形と現在矩形（Smooth 範囲の平均）の中心差を Draw へ加算し、
/// 矩形の拡縮比を Zoom へ掛ける。操作点（中心線・矩形枠・現在矩形）は
/// 本家と同じ位置・形状・選択状態で生成するが、ドラッグ等の対話
/// コールバックは編集 UI 層の関心であり含めない（MAC-0009 の方針）。
/// 編集中の扱いも本家どおり: 対象が背景でなければ無変換、背景なら
/// 不透明度 0。
public final class MotionTrackingEffectProcessor: DrawDescriptionEffectProcessor {
    private let definition: MotionTrackingEffectDefinition

    public init(definition: MotionTrackingEffectDefinition) {
        self.definition = definition
        super.init()
    }

    public override func update(_ description: EffectDescription) -> DrawDescription {
        let path = definition.path
        let source = description.drawDescription
        if path.isEditing {
            if path.target != .background {
                return source
            }
            var result = source
            result.opacity = 0
            return result
        }
        guard let first = path.rects.first else { return source }

        let frame = description.itemFrame
        let current = Self.currentRect(rects: path.rects, frame: frame, smooth: definition.smooth)
        let direction: Double = definition.isReverce ? -1 : 1
        let delta = Vector2(
            x: (current.center.x - first.center.x) * direction,
            y: (current.center.y - first.center.y) * direction
        )
        var zoom: Double
        if definition.isFixedSize || first.width <= 0 || first.height <= 0 {
            zoom = 1
        } else {
            zoom = max(current.width / first.width, current.height / first.height)
        }
        if definition.isReverseZoom && zoom != 0 {
            zoom = 1 / zoom
        }

        var result = source
        result.draw = Vector3(
            x: source.draw.x + delta.x,
            y: source.draw.y + delta.y,
            z: source.draw.z
        )
        result.zoom = Vector2(x: source.zoom.x * zoom, y: source.zoom.y * zoom)
        result.controllers = source.controllers
            + rectLineControllers(description: description, delta: delta, zoom: zoom)
            + centerLineControllers(description: description, delta: delta, zoom: zoom)
            + currentRectControllers(description: description, delta: delta, zoom: zoom, current: current)
        return result
    }

    /// 現在フレームの矩形。前後 Smooth フレームの平均（本家 CreateCurrentRect）。
    /// 範囲が矩形列を超える場合は末尾の矩形を使う。
    static func currentRect(
        rects: [MotionTrackingRectValue], frame: Int, smooth: Int
    ) -> MotionTrackingRectValue {
        let start = max(0, frame - smooth)
        let end = max(start, min(rects.count - 1, frame + smooth))
        let slice: [MotionTrackingRectValue] = start < rects.count
            ? Array(rects[start...min(end, rects.count - 1)])
            : []
        let source = slice.isEmpty ? [rects[rects.count - 1]] : slice
        let count = Double(source.count)
        return MotionTrackingRectValue(
            top: source.reduce(0) { $0 + $1.top } / count,
            bottom: source.reduce(0) { $0 + $1.bottom } / count,
            left: source.reduce(0) { $0 + $1.left } / count,
            right: source.reduce(0) { $0 + $1.right } / count,
            isTracking: source[source.count - 1].isTracking
        )
    }

    /// 操作点の表示範囲（本家 Update の num / num2 / count）。
    private func visibleRange(description: EffectDescription) -> Range<Int> {
        let frame = description.itemFrame
        let window = Int(Double(description.fps) * definition.controlPointVisibleSeconds)
        let start = max(0, frame - window)
        let end = min(description.itemDurationFrames - 1, frame + window)
        let count = max(0, end - start + 1)
        return start..<(start + count)
    }

    /// 矩形の四隅を操作点座標へ変換する（本家 CreateRectControlPointVectors）。
    private func rectCornerPoints(
        description: EffectDescription, delta: Vector2, zoom: Double,
        rect: MotionTrackingRectValue, shape: VideoControllerPointShape
    ) -> [ControllerPoint] {
        let source = description.drawDescription
        let base = Vector3(
            x: -source.draw.x - delta.x,
            y: -source.draw.y - delta.y,
            z: 0
        )
        var corners = [
            Vector3(x: rect.left, y: rect.top, z: 0),
            Vector3(x: rect.right, y: rect.top, z: 0),
            Vector3(x: rect.right, y: rect.bottom, z: 0),
            Vector3(x: rect.left, y: rect.bottom, z: 0),
        ].map { Vector3(x: $0.x + base.x, y: $0.y + base.y, z: $0.z + base.z) }
        if zoom > 0 {
            corners = corners.map { Vector3(x: $0.x / zoom, y: $0.y / zoom, z: $0.z / zoom) }
        }
        if source.zoom.x > 0 && source.zoom.y > 0 {
            corners = corners.map {
                Vector3(x: $0.x / source.zoom.x, y: $0.y / source.zoom.y, z: 0)
            }
        }
        return corners.map { ControllerPoint(position: $0, shape: shape) }
    }

    /// 中心線の操作点列（接続 Line)。
    private func centerLineControllers(
        description: EffectDescription, delta: Vector2, zoom: Double
    ) -> [VideoEffectController] {
        let frame = description.itemFrame
        let source = description.drawDescription
        let points = visibleRange(description: description).map { x -> ControllerPoint in
            let rect = Self.currentRect(
                rects: definition.path.rects, frame: x, smooth: definition.smooth
            )
            var position = Vector3(
                x: rect.center.x - source.draw.x - delta.x,
                y: rect.center.y - source.draw.y - delta.y,
                z: 0
            )
            if zoom > 0 {
                position = Vector3(x: position.x / zoom, y: position.y / zoom, z: position.z / zoom)
            }
            if source.zoom.x > 0 && source.zoom.y > 0 {
                position = Vector3(x: position.x / source.zoom.x, y: position.y / source.zoom.y, z: 0)
            }
            let inRange = x >= 0 && x < definition.path.rects.count
            return ControllerPoint(
                position: position,
                shape: inRange ? .point : .none,
                isSelected: x == frame
            )
        }
        return [VideoEffectController(owner: definition, points: points, connection: .line)]
    }

    /// 矩形枠の操作点列（接続 Loop)。IsOnlyCurrentFrameRectLine のときは
    /// 現在フレーム分だけ。
    private func rectLineControllers(
        description: EffectDescription, delta: Vector2, zoom: Double
    ) -> [VideoEffectController] {
        let frames = definition.isOnlyCurrentFrameRectLine
            ? [description.itemFrame]
            : Array(visibleRange(description: description))
        return frames.map { x in
            let rect = Self.currentRect(
                rects: definition.path.rects, frame: x, smooth: definition.smooth
            )
            return VideoEffectController(
                owner: definition,
                points: rectCornerPoints(
                    description: description, delta: delta, zoom: zoom, rect: rect, shape: .none
                ),
                connection: .loop
            )
        }
    }

    /// 現在矩形の操作点（接続 None)。フレームが矩形列の範囲外なら付けない。
    private func currentRectControllers(
        description: EffectDescription, delta: Vector2, zoom: Double,
        current: MotionTrackingRectValue
    ) -> [VideoEffectController] {
        let frame = description.itemFrame
        guard frame >= 0 && frame < definition.path.rects.count else { return [] }
        return [VideoEffectController(
            owner: definition,
            points: rectCornerPoints(
                description: description, delta: delta, zoom: zoom, rect: current, shape: .point
            ),
            connection: .none
        )]
    }
}
