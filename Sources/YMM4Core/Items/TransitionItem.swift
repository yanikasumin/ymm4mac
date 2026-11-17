import Foundation

/// 画面遷移アイテム。本家 `TransitionItem` に対応する。
///
/// X / Y / Z / Opacity / Zoom / Rotation / FadeIn / FadeOut / Blend /
/// IsInverted / IsAlwaysOnTop / IsZOrderEnabled /
/// IsClippingWithObjectAbove / VideoEffects は、本家では式本体の
/// get 専用プロパティ（アクセスのたびに既定値を返す）で、保存はされるが
/// 読み込み結果は保持されない（IsClippingWithObjectAbove と
/// VideoEffects は setter が何もしない）。ここでは既定値を初期値として
/// 型付きで保持し、読み込んだ値を往復させる（意図的な差分: データ保全を
/// 優先する。本家が書き出すファイルでは常に既定値のため、実ファイルでは
/// 差は現れない）。アニメーション文脈の伝播にも参加させる点も本家と
/// 異なる（本家では GetAnimatables に含まれない）。
public final class TransitionItem: BaseItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.TransitionItem, YukkuriMovieMaker"
    }

    /// X 座標（本家の get 専用プロパティが返す既定値で初期化）。
    public var x: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// Y 座標（同上）。
    public var y: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// Z 座標（同上）。
    public var z: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// 不透明度（%、同上）。
    public var opacity: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 拡大率（%、同上）。
    public var zoom: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100_000)
    /// 回転角（同上）。
    public var rotation: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// フェードイン（秒）。
    public var fadeIn: Double = 0
    /// フェードアウト（秒）。
    public var fadeOut: Double = 0
    /// 反転するか。
    public var isInverted: Bool = false
    /// 合成方法。
    public var blend: Blend = .normal
    /// 常に手前に表示するか。
    public var isAlwaysOnTop: Bool = false
    /// Z オーダーを有効にするか。
    public var isZOrderEnabled: Bool = false
    /// 1つ上のオブジェクトで切り抜くか。
    public var isClippingWithObjectAbove: Bool = false
    /// 映像エフェクト（生 JSON で保持）。
    public var videoEffects: [PreservedObject] = []
    /// 遷移プラグインの型名（本家ではプライマリプラグインの型が既定）。
    public var transitionType: String = ""
    /// 遷移パラメータ（プラグイン型、生 JSON で保持）。
    public var transitionParameter: PreservedObject?
    /// 遷移前に適用する映像エフェクト（生 JSON で保持）。
    public var beforeVideoEffects: [PreservedObject] = []
    /// 遷移後に適用する映像エフェクト（生 JSON で保持）。
    public var afterVideoEffects: [PreservedObject] = []

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        super.forEachAnimation(body)
        body(&x)
        body(&y)
        body(&z)
        body(&opacity)
        body(&zoom)
        body(&rotation)
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Z", value: CodecSupport.encodeAnimation(z)),
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
            (key: "Rotation", value: CodecSupport.encodeAnimation(rotation)),
            (key: "FadeIn", value: .number(fadeIn)),
            (key: "FadeOut", value: .number(fadeOut)),
            (key: "IsInverted", value: .bool(isInverted)),
            (key: "Blend", value: .string(blend.honkeName)),
            (key: "IsAlwaysOnTop", value: .bool(isAlwaysOnTop)),
            (key: "IsZOrderEnabled", value: .bool(isZOrderEnabled)),
            (key: "IsClippingWithObjectAbove", value: .bool(isClippingWithObjectAbove)),
            (key: "VideoEffects", value: .array(videoEffects.map { $0.value })),
            (key: "TransitionType", value: .string(transitionType)),
            (key: "TransitionParameter", value: transitionParameter?.value ?? .null),
            (key: "BeforeVideoEffects", value: .array(beforeVideoEffects.map { $0.value })),
            (key: "AfterVideoEffects", value: .array(afterVideoEffects.map { $0.value })),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "X":
            CodecSupport.decodeAnimation(value, into: &x)
        case "Y":
            CodecSupport.decodeAnimation(value, into: &y)
        case "Z":
            CodecSupport.decodeAnimation(value, into: &z)
        case "Opacity":
            CodecSupport.decodeAnimation(value, into: &opacity)
        case "Zoom":
            CodecSupport.decodeAnimation(value, into: &zoom)
        case "Rotation":
            CodecSupport.decodeAnimation(value, into: &rotation)
        case "FadeIn":
            fadeIn = CodecSupport.double(value, default: fadeIn)
        case "FadeOut":
            fadeOut = CodecSupport.double(value, default: fadeOut)
        case "IsInverted":
            isInverted = CodecSupport.bool(value, default: isInverted)
        case "Blend":
            blend = CodecSupport.enumeration(value, default: blend)
        case "IsAlwaysOnTop":
            isAlwaysOnTop = CodecSupport.bool(value, default: isAlwaysOnTop)
        case "IsZOrderEnabled":
            isZOrderEnabled = CodecSupport.bool(value, default: isZOrderEnabled)
        case "IsClippingWithObjectAbove":
            isClippingWithObjectAbove = CodecSupport.bool(value, default: isClippingWithObjectAbove)
        case "VideoEffects":
            videoEffects = CodecSupport.preservedList(value)
        case "TransitionType":
            transitionType = CodecSupport.string(value, default: transitionType)
            return true
        case "TransitionParameter":
            transitionParameter = CodecSupport.preservedObject(value)
            return true
        case "BeforeVideoEffects":
            beforeVideoEffects = CodecSupport.preservedList(value)
            return true
        case "AfterVideoEffects":
            afterVideoEffects = CodecSupport.preservedList(value)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
        return true
    }
}

extension TransitionItem: VideoItemProperties {}
