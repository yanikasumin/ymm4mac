import Foundation

/// トランジションの対象側。本家 `YukkuriMovieMaker.Transition.TransitionTarget`
/// に対応する。各パラメータの Target / OverlayTarget がこの値を持つ。
/// 保存名は列挙子名そのもの（"Before" / "After"）。
public enum TransitionTarget: Sendable {
    case before
    case after

    public init?(honkeName name: String) {
        switch name {
        case "Before": self = .before
        case "After": self = .after
        default: return nil
        }
    }

    public var honkeName: String {
        switch self {
        case .before: return "Before"
        case .after: return "After"
        }
    }
}

/// スライスの動く方向。本家 `SliceAnimationDirection` に対応する。
public enum SliceAnimationDirection: Sendable {
    case up
    case down
    case alternating

    public init?(honkeName name: String) {
        switch name {
        case "Up": self = .up
        case "Down": self = .down
        case "Alternating": self = .alternating
        default: return nil
        }
    }

    public var honkeName: String {
        switch self {
        case .up: return "Up"
        case .down: return "Down"
        case .alternating: return "Alternating"
        }
    }
}

/// スライスの開始位置。本家 `SliceAnimationStart` に対応する。
public enum SliceAnimationStart: Sendable {
    case left
    case right
    case center
    case outside

    public init?(honkeName name: String) {
        switch name {
        case "Left": self = .left
        case "Right": self = .right
        case "Center": self = .center
        case "Outside": self = .outside
        default: return nil
        }
    }

    public var honkeName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .center: return "Center"
        case .outside: return "Outside"
        }
    }
}

/// 本家内蔵トランジション方式の種別。本家 `YukkuriMovieMaker.Transition`
/// 名前空間の *TransitionParameter クラス群に対応する。
/// `unknown` はプラグイン方式（本家でもプラグインが無ければ読み込めない）
/// であり、合成側では差し替え点として扱う。
public enum TransitionKind: Sendable {
    case none
    case switchKind
    case fade
    case slide
    case push
    case doubleOpenDoor
    case doubleSlideDoor
    case slice
    case ruleImage
    case unknown
}

/// トランジションパラメータの型付き表現。本家 `ITransitionParameter`
/// （TransitionParameterBase）の具象クラス群に対応する。
///
/// モデル層の保持形式は生 JSON（`TransitionItem.transitionParameter` の
/// PreservedObject）のままであり、こちらは消費側で作る一時的なビュー
/// （MAC-0019 のエフェクト定義と同じ設計）。パラメータが nil の場合は
/// 本家 TransitionItem のフィールド初期化子どおり Push が既定になる。
/// 既定値は本家の各パラメータクラスのフィールド初期化子で実測した。
public final class TransitionParameter {
    /// 方式の種別。
    public let kind: TransitionKind
    /// 元の $type 文字列（未知方式の診断用。既定生成時は Push の型名）。
    public let typeName: String

    /// イージングの科（Fade / Slide / Push / 各ドア / Slice。既定 Expo、
    /// RuleImage だけ Linear）。
    public var easingFamily: EasingFamily = .expo
    /// イージングの適用方向（既定 InOut）。
    public var easingMode: EasingMode = .inOut
    /// 対象側（None では OverlayTarget、Slide / 各ドア / Slice では
    /// Target。いずれも既定 Before）。
    public var target: TransitionTarget = .before
    /// 角度（度。Slide / Push / 各ドア / Slice / RuleImage。既定 0）。
    public var angle: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// スライス数（Slice。既定 6、範囲 1〜100）。
    public var slices: Animation = Animation(defaultValue: 6, minValue: 1, maxValue: 100)
    /// スライスのずれ量（%。Slice。既定 0）。
    public var shift: Animation = Animation(defaultValue: 0, minValue: 0, maxValue: 100_000)
    /// 許容誤差（RuleImage。既定 3、範囲 −50〜450）。
    public var tolerance: Animation = Animation(defaultValue: 3, minValue: -50, maxValue: 450)
    /// スライスの開始位置（Slice。既定 Left = 列挙の先頭）。
    public var start: SliceAnimationStart = .left
    /// スライスの方向（Slice。既定 Alternating）。
    public var direction: SliceAnimationDirection = .alternating
    /// ルール画像のファイル（RuleImage）。
    public var file: String?
    /// ルール画像のアスペクト比を維持するか（RuleImage。既定 true）。
    public var keepAspect: Bool = true
    /// ルール画像の被覆スケールを固定するか（RuleImage。既定 false）。
    public var isFixedCoveringScale: Bool = false
    /// ルール画像の遷移を反転するか（RuleImage。既定 false）。
    public var isReversed: Bool = false

    private init(kind: TransitionKind, typeName: String) {
        self.kind = kind
        self.typeName = typeName
    }

    /// 本家 PushTransitionParameter の型名（パラメータ未指定時の既定）。
    public static let pushTypeName =
        "YukkuriMovieMaker.Transition.PushTransitionParameter, YukkuriMovieMaker"

    /// 生保持から型付き表現を作る。未知の $type は kind = .unknown として
    /// 返し、フィールドは読まない（プラグイン方式は差し替え点）。
    public static func decode(_ preserved: PreservedObject?) -> TransitionParameter {
        guard let preserved, let typeName = preserved.typeName else {
            // 本家は TransitionParameter の初期値として Push を生成する。
            return TransitionParameter(kind: .push, typeName: pushTypeName)
        }
        let className = typeName
            .split(separator: ",").first
            .map { $0.split(separator: ".").last.map(String.init) ?? String($0) }
            ?? typeName
        let kind: TransitionKind
        switch className {
        case "NoneTransitionParameter": kind = .none
        case "SwitchTransitionParameter": kind = .switchKind
        case "FadeTransitionParameter": kind = .fade
        case "SlideTransitionParameter": kind = .slide
        case "PushTransitionParameter": kind = .push
        case "DoubleOpenDoorTransitionParameter": kind = .doubleOpenDoor
        case "DoubleSlideDoorTransitionParameter": kind = .doubleSlideDoor
        case "SliceTransitionParameter": kind = .slice
        case "RuleImageTransitionParameter": kind = .ruleImage
        default: kind = .unknown
        }
        let parameter = TransitionParameter(kind: kind, typeName: typeName)
        guard kind != .unknown else { return parameter }
        parameter.decodeFields(preserved.value)
        return parameter
    }

    private func decodeFields(_ value: JSONValue) {
        // イージング（RuleImage の既定は Linear、それ以外は Expo）。
        if kind == .ruleImage { easingFamily = .linear }
        if let name = value.field("EasingType")?.stringValue,
           let family = EasingFamily(effectHonkeName: name) {
            easingFamily = family
        }
        if let name = value.field("EasingMode")?.stringValue,
           let mode = EasingMode(effectHonkeName: name) {
            easingMode = mode
        }
        // 対象側。None は OverlayTarget、それ以外は Target キー。
        let targetKey = kind == .none ? "OverlayTarget" : "Target"
        if let name = value.field(targetKey)?.stringValue,
           let parsed = TransitionTarget(honkeName: name) {
            target = parsed
        }
        if let angleValue = value.field("Angle") {
            CodecSupport.decodeAnimation(angleValue, into: &angle)
        }
        if let slicesValue = value.field("Slices") {
            CodecSupport.decodeAnimation(slicesValue, into: &slices)
        }
        if let shiftValue = value.field("Shift") {
            CodecSupport.decodeAnimation(shiftValue, into: &shift)
        }
        if let toleranceValue = value.field("Tolerance") {
            CodecSupport.decodeAnimation(toleranceValue, into: &tolerance)
        }
        if let name = value.field("Start")?.stringValue,
           let parsed = SliceAnimationStart(honkeName: name) {
            start = parsed
        }
        if let name = value.field("Direction")?.stringValue,
           let parsed = SliceAnimationDirection(honkeName: name) {
            direction = parsed
        }
        file = value.field("File")?.stringValue
        keepAspect = CodecSupport.bool(value.field("KeepAspect"), default: keepAspect)
        isFixedCoveringScale = CodecSupport.bool(
            value.field("IsFixedCoveringScale"), default: isFixedCoveringScale
        )
        isReversed = CodecSupport.bool(value.field("IsReversed"), default: isReversed)
    }

    /// 所有アイテムのキーフレーム文脈をアニメーションへ伝播させる
    /// （本家は GetAnimatables 経由でパラメータも文脈を受ける。
    /// エフェクト定義の setKeyFrames と同じ扱い）。
    public func applyKeyFrames(_ keyFrames: KeyFrames) {
        angle.setKeyFrames(keyFrames)
        slices.setKeyFrames(keyFrames)
        shift.setKeyFrames(keyFrames)
        tolerance.setKeyFrames(keyFrames)
    }

    /// 遷移の進行率。本家各 Source が使う
    /// `Easing.GetValue(EasingType, EasingMode, frame / duration)` そのもの。
    public func easedRate(frame: Int, duration: Int) -> Double {
        guard duration > 0 else { return 0 }
        return EasingFamily.getValue(
            family: easingFamily, mode: easingMode,
            rate: Double(frame) / Double(duration)
        )
    }
}
