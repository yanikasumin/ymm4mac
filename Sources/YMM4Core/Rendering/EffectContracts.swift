import Foundation

/// エフェクト連鎖の処理器1段。本家 IVideoEffectProcessor に対応する。
///
/// MAC-0009 の DrawingEffectProcessor は Source 契約の境界（入力設定と
/// DrawDescription の確定）だけを切り出したものであり、連鎖の各段はこちらが
/// 本体になる。形は同じだが責務が違うため分ける（本家でも ISourceOutput の
/// DrawingEffect と連鎖内の処理器は同じインタフェースを共有するが、こちらでは
/// 契約の出所を型で区別する）。
///
/// 所有権（第1章 IMG-03）: SetInput は入力の所有権を移さない。ClearInput は
/// 設定されていた入力を破棄しない。Output の有効範囲は、この処理器を所有する
/// EffectedOutput の次の Update が始まるまで（IMG-05）。
public protocol VideoEffectProcessor: AnyObject {
    /// 現在の出力（入力未設定・未更新なら nil もありうる）。
    var output: ImageReference? { get }
    /// 入力を設定する。所有権は移らない。
    func setInput(_ image: ImageReference?)
    /// 入力を解除する。解除された入力は破棄されない。
    func clearInput()
    /// 説明に基づいて出力を更新し、確定した描画変換を返す。
    /// 失敗した場合は例外を投げる（呼び出し側の失敗意味論は第4章の精密化どおり）。
    @discardableResult
    func update(_ description: EffectDescription) throws -> DrawDescription
    /// 自身が所有する資源を解放する。
    func dispose()
}

/// エフェクト定義（本家 IVideoEffect に対応する、連鎖の「型」側）。
///
/// 連鎖の再利用判定はこの定義の**同一性**（インスタンス）で行う（第4章:
/// 位置 index 基準の再利用、差し替え条件は IVideoEffect 参照の不一致）。
/// モデル層の映像エフェクトは PreservedObject（生 JSON）で保持され、
/// 定義への橋渡しは `TypedEffectPairProvider` が消費側で行う（MAC-0018 /
/// MAC-0019。保持形式は生保持のままで、型付き定義は一時的なビュー）。
/// ここでは同一性・有効状態・処理器の生成だけを契約とする。
public protocol VideoEffectDefinition: AnyObject {
    /// 有効か。無効な定義は連鎖から除外される（本家 IsEnabled）。
    var isEnabled: Bool { get }
    /// 処理器を新規生成する。生成した処理器の所有権は呼び出し側へ移る。
    func createProcessor() -> any VideoEffectProcessor
    /// 診断用のパラメータ表現（任意）。本家は DrawingEffect の更新失敗時に
    /// 問題エフェクトの設定 JSON を診断文字列へ含める（4000 文字で切る）。
    /// この層では JSON 化の責務を持たないため、定義側が文字列で提供できる
    /// 場合だけ使う。
    var diagnosticText: String? { get }
}

extension VideoEffectDefinition {
    public var diagnosticText: String? { nil }
}

/// エフェクト適用の組。本家 EffectedItemSource が扱う
/// (TimeSource, Effect, GroupIndex, GroupCount) のタプルに対応する。
public struct EffectPair {
    /// エフェクトの時間基準になるアイテム（自前エフェクトはアイテム自身、
    /// グループエフェクトはグループ、顔エフェクトは顔アイテム）。
    public var timeSource: BaseItem
    /// エフェクト定義。
    public var definition: any VideoEffectDefinition
    /// グループ内の子位置（グループエフェクト用。それ以外は 0）。
    public var groupIndex: Int
    /// グループの子総数（グループエフェクト用。それ以外は 0）。
    public var groupCount: Int

    public init(
        timeSource: BaseItem,
        definition: any VideoEffectDefinition,
        groupIndex: Int = 0,
        groupCount: Int = 0
    ) {
        self.timeSource = timeSource
        self.definition = definition
        self.groupIndex = groupIndex
        self.groupCount = groupCount
    }
}

/// エフェクト定義の供給元。モデル層のエフェクト列（PreservedObject の生 JSON）
/// から定義インスタンスへの橋渡しを担う境界。実物は
/// `TypedEffectPairProvider`（レジストリで型付けし、所有アイテム単位で
/// キャッシュする）であり、`TimelineComposer` と `EffectedItemSource` の
/// 既定はそちらを使う（MAC-0019）。
public protocol EffectPairProvider {
    /// アイテム自身のエフェクト（本家 Item.VideoEffects）。
    func ownEffectPairs(for item: BaseItem & VideoItemProperties) -> [EffectPair]
    /// グループのエフェクト（本家 GroupItem.GroupEffects）。子位置と子総数は
    /// グループ解決側（TimelineGroupResolver）が算出して渡す。
    func groupEffectPairs(for group: GroupItem, childIndex: Int, childCount: Int) -> [EffectPair]
    /// 顔アイテムのエフェクト（本家 TachieFaceEffects）。時間基準は顔アイテム自身。
    func faceEffectPairs(for faceItem: BaseItem) -> [EffectPair]
}

/// エフェクトを何も供給しない供給元（連鎖を素通しにしたい場合に明示して使う）。
public struct EmptyEffectPairProvider: EffectPairProvider {
    public init() {}

    public func ownEffectPairs(for item: BaseItem & VideoItemProperties) -> [EffectPair] { [] }
    public func groupEffectPairs(for group: GroupItem, childIndex: Int, childCount: Int) -> [EffectPair] { [] }
    public func faceEffectPairs(for faceItem: BaseItem) -> [EffectPair] { [] }
}

/// 描画先（コマンドリスト相当）。本家 ID2D1DeviceContext + ID2D1CommandList の
/// 組を、GPU に触れない抽象として表したもの。GPU 実行層が実物に差し替える。
///
/// 本家には描画先の「ターゲット設定／解除」という文脈状態があるが、この層では
/// ターゲット自身が描画操作を受けるため、その状態はターゲットへ畳み込む。
/// 結果として本家に2通りある終了順序（EffectedItemSource 側は
/// EndDraw → Close → ターゲット解除、TimelineSource の FrameBuffer 境界は
/// EndDraw → ターゲット解除 → Close）は、この層ではどちらも
/// endDraw → close として観測される（内部差分。GPU 実行層で再現する）。
public protocol RenderTarget: AnyObject {
    /// 記録済みのコマンド列を表す画像参照（本家ではコマンドリスト自身が画像）。
    var image: ImageReference { get }
    /// 描画を開始する。
    func beginDraw()
    /// 透明でクリアする（本家の合成開始時の Clear に対応）。
    func clear()
    /// 矩形を塗る（背景描画と、描画対象が無い場合の目印に使う）。
    func fillRect(_ rect: RectF, color: Color)
    /// 画像をそのまま描く（本家 DrawImage(image) に対応。EffectedItemSource の
    /// 合成と FrameBuffer の引き継ぎ描画で使う）。
    func drawImage(_ image: ImageReference)
    /// 画像をアイテムのブレンドで描く（本家 TimelineSource.DrawResourceImage に
    /// 対応。本家は Blend が合成系なら DrawImage、ブレンド系なら BlendImage と
    /// 呼び分けるが、その振り分けは GPU 実行層の解釈に委ね、ここでは Blend の
    /// 値をそのまま渡す）。
    func drawImage(_ image: ImageReference, blend: Blend, interpolation: InterpolationMode)
    /// 描画を終える。
    func endDraw()
    /// コマンド列を閉じる。以後の描画はできない。
    /// GPU 実行層がコマンド実行の失敗を検出した場合はエラーを投げる。
    /// 不完全な画像を正常な出力として公開しないための契約（MAC-0021）。
    /// 抽象層（記録用実装など）は失敗しないため投げなくてよい。
    func close() throws
    /// 実体を解放する。
    func dispose()
}

/// 描画先の生成者。本家 GraphicsDevicesAndContext 相当が担う生成の境界だけを
/// 切り出したもの。生成した描画先の所有権は呼び出し側へ移る。
public protocol RenderTargetFactory {
    func makeTarget() -> any RenderTarget
}

/// アルファマスク（本家 AlphaMaskEffect に対応する2入力の特殊エフェクト）。
/// 入力0 = マスクされる側の画像、入力1 = マスク画像。生成は差し替え点とし、
/// 実装は GPU 実行層の段で行う。
public protocol AlphaMaskEffect: AnyObject {
    /// マスク適用後の出力。
    var output: ImageReference? { get }
    /// 入力を設定する（index は 0 = 本体、1 = マスク）。
    func setInput(_ index: Int, _ image: ImageReference?)
    /// 自身が所有する資源を解放する。
    func dispose()
}

/// アルファマスクの生成者。
public protocol AlphaMaskEffectFactory {
    func makeAlphaMaskEffect() -> any AlphaMaskEffect
}

/// 平面分割の四隅算出に必要な幾何情報を DrawingEffect から取り出す境界。
/// 本家では DrawingEffect（具象クラス）が WorldTransform3D と
/// GetTransform3DInputBounds を持つ。こちらではプロトコル適合で表し、
/// 適合しない DrawingEffect を持つ出力は四隅を計算できない（本家でも
/// DrawingEffect でない出力があると GetPlaneSplitQuad は nil を返す）。
public protocol PlaneSplitGeometryProviding: AnyObject {
    /// ワールド変換（3D）。
    var worldTransform3D: Matrix4x4 { get }
    /// 変換前の入力境界（取得できない場合は nil）。
    func transform3DInputBounds() -> RectF?
}

/// 当たり判定用の変換後四隅（本家 EffectedItemSource.
/// GetTransformedBoundsQuad の材料）を DrawingEffect から取り出す境界。
/// 本家では通常の DrawingEffect は描画前出力の局所境界へ確定変換
/// （反転・ズーム → 回転・平行移動・カメラ・透視）を適用した四隅を返し、
/// IBoundsQuadProvider（マスク用の EffectItemDrawingEffect）だけが
/// 独自の四隅（マスク図形の境界をマスク変換で写したもの）を返す。
/// こちらでは両者をこのプロトコルで表す: providesCustomBoundsQuad が
/// 真の実装だけが独自四隅を持ち、それ以外は入力境界へ確定変換を
/// 適用した四隅を返す。適合しない DrawingEffect を持つ出力は四隅を
/// 計算できない（本家でも DrawingEffect でない出力があると
/// GetTransformedBoundsQuad は nil を返す）。
/// 平面分割用の四隅（PlaneSplitGeometryProviding）とは変換の範囲が
/// 異なる（こちらは透視・ズーム・反転と入力自身の変換を含む）ため、
/// 流用せず別境界とする。
public protocol BoundsQuadProviding: AnyObject {
    /// 本家 IBoundsQuadProvider への適合に相当するか（独自四隅を持つか）。
    var providesCustomBoundsQuad: Bool { get }
    /// 変換後の四隅（映像中心原点・y 下向き。順序は左上・右上・右下・
    /// 左下）。取得できない場合は nil。
    func boundsQuad() -> [Vector2]?
}

/// DrawingEffect の更新失敗。本家では DrawingEffect.Update の例外だけが
/// 診断情報（アイテム型名・エフェクト数・グラフの各ノードの状態）つきで
/// 包まれる（第4章）。連鎖途中の失敗は包まれず、そのまま伝播する。
public enum EffectedItemError: Error {
    case drawingEffectUpdateFailed(
        itemTypeName: String,
        effectCount: Int,
        graphDescription: String,
        underlying: any Error
    )

    /// 本家の包みメッセージと同じ形式の説明文。
    public var message: String {
        switch self {
        case let .drawingEffectUpdateFailed(itemTypeName, effectCount, graphDescription, _):
            return "描画エフェクトの更新に失敗しました。 Item=\(itemTypeName), EffectCount=\(effectCount) \(graphDescription)"
        }
    }
}
