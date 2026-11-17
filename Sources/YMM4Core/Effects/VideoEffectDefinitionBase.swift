import Foundation

/// 映像エフェクト定義の共通基盤。本家 `VideoEffectBase` に対応する。
///
/// 定義はパラメータ（多くは `Animation`）を保持する「型」側であり、処理器は
/// `createProcessor()` で別途生成される（本家の定義／処理器分離）。
/// .ymmp 上の表現は `$type`（アセンブリ修飾名）＋プロパティの JSON であり、
/// キーの並びは本家の実ファイルに合わせて「具象クラスのプロパティ →
/// 中間基底のプロパティ → 本基底（IsEnabled / Remark）」の順にする
/// （実測: CameraPositionEffect の実ファイルで X…RotationZ の後に
/// IsEnabled が来る）。
///
/// データ保全: 対応していないキーは `additionalFields` に原文のまま保持し、
/// 保存時に書き戻す。`Remark` は実ファイルで空文字のとき書き出されない
/// ことを実測したため、空でない場合だけ書き出す。`IsEnabled` は既定値
/// true でも実ファイルに存在するため常時書き出す。
open class VideoEffectDefinitionBase: VideoEffectDefinition {
    /// .ymmp の `$type` に書かれるアセンブリ修飾名。
    open class var typeName: String { "" }

    /// 有効か。本家 `IsEnabled`（既定 true）。無効な定義は連鎖から除外される。
    public var isEnabled: Bool = true

    /// 備考。本家 `Remark`（既定 ""）。
    public var remark: String = ""

    /// 型付けしていないキーの生保持（データ保全）。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    /// 本家 `GetHashCode()`（定義オブジェクトのハッシュ）の代替シード。
    ///
    /// ランダム系エフェクトの乱数キーに使う。本家は .NET ランタイム依存の
    /// 値であり固定の対応付けが存在しないため、値の一致は未解決事項として
    /// 台帳に残す（`Animation.randomSeed` と同じ扱い）。保存対象ではない。
    public var randomSeed: Int64 = 0

    public init() {}

    /// 処理器を生成する。基底は素通し処理器を返し、具象定義が差し替える。
    open func createProcessor() -> any VideoEffectProcessor {
        DrawDescriptionEffectProcessor()
    }

    /// 診断用のパラメータ表現。本家は DrawingEffect の更新失敗時に問題
    /// エフェクトの設定 JSON を診断へ含めるため、保存形式そのものを返す
    /// （4000 文字での切り捨ては呼び出し側の責務）。
    public var diagnosticText: String? {
        encode().serialized()
    }

    // MARK: - アニメーション文脈

    /// 定義が保持する全 `Animation` へ処理を適用する。具象定義が差し替える。
    /// 本家では定義の `GetAnimatables()` がアイテムのキーフレーム伝播を
    /// 受ける経路になっており、統合時にアイテム側から辿れるよう同じ形を持つ。
    open func forEachAnimation(_ body: (inout Animation) -> Void) {}

    /// アイテムのキーフレーム文脈を全パラメータへ伝播させる。
    public func setKeyFrames(_ keyFrames: KeyFrames) {
        forEachAnimation { $0.setKeyFrames(keyFrames) }
    }

    // MARK: - 読み込み

    /// `$type` を除くフィールド列を文書順に読み込む。対応したキーは消費し、
    /// 残りは `additionalFields` へ保持する。
    public final func decodeFields(_ fields: [(key: String, value: JSONValue)]) {
        for (key, value) in fields {
            if key == "$type" { continue }
            if !decodeKnownField(key, value) {
                additionalFields.append((key: key, value: value))
            }
        }
    }

    /// 既知キーを1件読み込む。処理したら true。具象定義は自分のキーを
    /// 処理し、残りを `super` へ委譲する。
    open func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "IsEnabled":
            isEnabled = CodecSupport.bool(value, default: true)
            return true
        case "Remark":
            remark = CodecSupport.string(value, default: "")
            return true
        default:
            return false
        }
    }

    // MARK: - 書き出し

    /// 既知フィールドを本家の並びで返す。具象定義は自分のフィールドの後に
    /// `super.encodeKnownFields()` を連結する。
    open func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "IsEnabled", value: .bool(isEnabled)),
        ]
        if !remark.isEmpty {
            fields.append((key: "Remark", value: .string(remark)))
        }
        return fields
    }

    /// `$type` を先頭にした保存形式全体。既知キーと重なる追加フィールドは
    /// 二重書きを避けるため除外する（未知の列挙名など、本家では生成され
    /// ない入力への防御）。
    public final func encode() -> JSONValue {
        let known = encodeKnownFields()
        let knownKeys = Set(known.map { $0.key })
        var fields: [(key: String, value: JSONValue)] = [
            (key: "$type", value: .string(type(of: self).typeName)),
        ]
        fields += known
        fields += additionalFields.filter { !knownKeys.contains($0.key) }
        return .object(fields)
    }
}

/// 本家 `EasingType` / `EasingMode` の保存名（StringEnumConverter の
/// メンバ名）と、`EasingFamily` / `EasingMode` の対応。
///
/// 未知の名前は nil を返し、呼び出し側が原文を保持する（本家では未知の
/// 列挙名は読み込み自体が失敗する入力であり、実在ファイルには現れない。
/// データ保全のため、こちらでは原文を残して既定値で評価する）。
extension EasingFamily {
    var effectHonkeName: String {
        switch self {
        case .linear: return "Linear"
        case .sine: return "Sine"
        case .quad: return "Quad"
        case .cubic: return "Cubic"
        case .quart: return "Quart"
        case .quint: return "Quint"
        case .expo: return "Expo"
        case .circ: return "Circ"
        case .back: return "Back"
        case .elastic: return "Elastic"
        case .bounce: return "Bounce"
        case .jump: return "Jump"
        }
    }

    init?(effectHonkeName name: String) {
        switch name {
        case "Linear": self = .linear
        case "Sine": self = .sine
        case "Quad": self = .quad
        case "Cubic": self = .cubic
        case "Quart": self = .quart
        case "Quint": self = .quint
        case "Expo": self = .expo
        case "Circ": self = .circ
        case "Back": self = .back
        case "Elastic": self = .elastic
        case "Bounce": self = .bounce
        case "Jump": self = .jump
        default: return nil
        }
    }
}

extension EasingMode {
    var effectHonkeName: String {
        switch self {
        case .in: return "In"
        case .out: return "Out"
        case .inOut: return "InOut"
        case .outIn: return "OutIn"
        }
    }

    init?(effectHonkeName name: String) {
        switch name {
        case "In": self = .in
        case "Out": self = .out
        case "InOut": self = .inOut
        case "OutIn": self = .outIn
        default: return nil
        }
    }
}
