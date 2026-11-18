import Foundation

/// `Animation` と `KeyFrames` の JSON 形状（本家 `Animation` の
/// 保存形式）の変換。`CodecSupport` の拡張として、プリミティブ値の
/// 取り出しと分けて置く。
extension CodecSupport {
    // MARK: - Animation の JSON 形状

    /// 本家 `Animation` の保存形式を、定義値（既定値・範囲）を持つ既存の
    /// `Animation` へ読み込む。
    ///
    /// キーは文書順に適用する（Newtonsoft と同じ）。旧形式の `From` / `To`
    /// （set 専用の互換プロパティ）は読み込み時の指令として処理し、
    /// 保存時には書き出さない。
    static func decodeAnimation(_ value: JSONValue, into animation: inout Animation) {
        guard let fields = value.objectFields else { return }
        for (key, fieldValue) in fields {
            switch key {
            case "Values":
                if let elements = fieldValue.arrayValue {
                    animation.values = elements.map { element in
                        if let number = element.doubleValue {
                            return AnimationValue(number)
                        }
                        return AnimationValue(element.field("Value")?.doubleValue ?? 0)
                    }
                }
            case "Span":
                animation.span = fieldValue.doubleValue ?? animation.span
            case "AnimationType":
                if let name = fieldValue.stringValue, let type = AnimationType(honkeName: name) {
                    animation.animationType = type
                } else if let rawValue = fieldValue.intValue, let type = AnimationType(rawValue: rawValue) {
                    animation.animationType = type
                }
            case "Bezier":
                decodeBezier(fieldValue, into: &animation.bezier)
            case "From":
                // 旧互換: 先頭の値として適用される
                animation.setFirstValue(fieldValue.doubleValue ?? 0)
            case "To":
                // 旧互換: 2番目の値として適用される。値が無い場合は
                // 既定値 0 の要素を補ってから書き込む（本家の setter そのまま）。
                let newValue = fieldValue.doubleValue ?? 0
                if animation.values.isEmpty {
                    animation.values = [AnimationValue(0)]
                }
                if animation.values.count == 1 {
                    animation.values.append(AnimationValue(newValue))
                } else {
                    animation.values[1] = AnimationValue(newValue)
                }
            default:
                break
            }
        }
    }

    /// 旧互換プロパティ（set 専用）として保存された `Animation` を読み込む。
    ///
    /// 本家では `AnimationJsonConverter` が範囲 (int.MinValue, int.MaxValue)
    /// で読み込むため、実質的にクランプなしの値として取り出す。取り出した
    /// 内容は `copyAnimationContents` で本来の保持先へ写す。
    static func decodeLegacyAnimation(_ value: JSONValue) -> Animation {
        var animation = Animation(
            defaultValue: 0,
            minValue: -2_147_483_648,
            maxValue: 2_147_483_647
        )
        decodeAnimation(value, into: &animation)
        return animation
    }

    /// 本家 `Animation.CopyFrom` の範囲（値列・種類・Span・ベジェ）だけを
    /// 写す。写し先の定義値（既定値・範囲）は保持先のものが残る。
    static func copyAnimationContents(from source: Animation, into target: inout Animation) {
        target.values = source.values
        target.animationType = source.animationType
        target.span = source.span
        target.bezier = source.bezier
    }

    /// 既存の保存 JSON を土台に、新しい値を重ねる。オブジェクト同士は
    /// キー単位で再帰し、配列同士は要素単位で重ねる（共通部分は要素
    /// 同士を再帰マージし、新しい側の超過分はそのまま採用する）。
    /// 既存にだけあるキー（未知フィールド）は残る。生保持データの
    /// 編集で、既知フィールドの書き換えが未知情報を壊さないための
    /// 規則（R21-117-01）。
    static func mergePreservingUnknownFields(
        existing: JSONValue, overlay: JSONValue
    ) -> JSONValue {
        switch (existing, overlay) {
        case (.object(let existingFields), .object(let overlayFields)):
            var result = existingFields
            for field in overlayFields {
                if let index = result.firstIndex(where: { $0.key == field.key }) {
                    result[index] = (
                        key: field.key,
                        value: mergePreservingUnknownFields(
                            existing: result[index].value, overlay: field.value
                        )
                    )
                } else {
                    result.append(field)
                }
            }
            return .object(result)
        case (.array(let existingElements), .array(let overlayElements)):
            return .array(overlayElements.enumerated().map { index, element in
                existingElements.indices.contains(index)
                    ? mergePreservingUnknownFields(
                        existing: existingElements[index], overlay: element
                    )
                    : element
            })
        default:
            return overlay
        }
    }

    static func encodeAnimation(_ animation: Animation) -> JSONValue {
        .object([
            (key: "Values", value: .array(animation.values.map {
                .object([(key: "Value", value: .number($0.value))])
            })),
            (key: "Span", value: .number(animation.span)),
            (key: "AnimationType", value: .string(animation.animationType.honkeName)),
            (key: "Bezier", value: encodeBezier(animation.bezier)),
        ])
    }

    static func decodeBezier(_ value: JSONValue, into bezier: inout BezierAnimation) {
        if let points = value.field("Points")?.arrayValue {
            bezier.points = points.map { point in
                BezierAnimationPoint(
                    point: decodeVector(point.field("Point")),
                    controlPoint1: decodeVector(point.field("ControlPoint1")),
                    controlPoint2: decodeVector(point.field("ControlPoint2"))
                )
            }
        }
        if let isQuadratic = value.field("IsQuadratic")?.boolValue {
            bezier.isQuadratic = isQuadratic
        }
    }

    static func encodeBezier(_ bezier: BezierAnimation) -> JSONValue {
        .object([
            (key: "Points", value: .array(bezier.points.map { point in
                .object([
                    (key: "Point", value: encodeVector(point.point)),
                    (key: "ControlPoint1", value: encodeVector(point.controlPoint1)),
                    (key: "ControlPoint2", value: encodeVector(point.controlPoint2)),
                ])
            })),
            (key: "IsQuadratic", value: .bool(bezier.isQuadratic)),
        ])
    }

    private static func decodeVector(_ value: JSONValue?) -> BezierVector {
        BezierVector(
            x: Float(value?.field("X")?.doubleValue ?? 0),
            y: Float(value?.field("Y")?.doubleValue ?? 0)
        )
    }

    private static func encodeVector(_ vector: BezierVector) -> JSONValue {
        .object([
            (key: "X", value: .number(vector.x)),
            (key: "Y", value: .number(vector.y)),
        ])
    }

    // MARK: - KeyFrames の JSON 形状

    static func decodeKeyFrames(_ value: JSONValue?) -> KeyFrames? {
        guard let frames = value?.field("Frames")?.arrayValue else { return nil }
        return KeyFrames(frames: frames.compactMap { $0.intValue })
    }

    static func encodeKeyFrames(_ keyFrames: KeyFrames) -> JSONValue {
        .object([(key: "Frames", value: .array(keyFrames.frames.map { .number($0) }))])
    }
}
