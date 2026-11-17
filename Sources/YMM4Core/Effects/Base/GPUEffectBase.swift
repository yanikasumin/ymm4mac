import Foundation

/// GPU 処理系エフェクトの暫定処理器（GPU 処理器は未実装）。
///
/// 定義層だけが型付けされた GPU 系エフェクトがエフェクト連鎖へ供給された
/// 場合に使う。入力をそのまま素通しし、`DrawDescription` も無変換で返す。
/// 本家の GPU 処理（画像そのものの加工）は行われないため、この処理器を
/// 返す定義は「描画結果が本家と異なる」ことが型の上で明示される。
/// GPU 処理器（Metal）が実装された定義から順に差し替えられる。
public final class GPUEffectPassthroughProcessor: DrawDescriptionEffectProcessor {
    public override init() {
        super.init()
    }
}

/// GPU 処理系エフェクト定義の共通基盤。
///
/// パラメータの型付け（定義層）のみを行い、処理器は暫定の素通し
/// （`GPUEffectPassthroughProcessor`）を返す。入出場系・ランダム系・
/// 反復系の GPU エフェクトは本家の中間基底（`InOutEffectDefinitionBase`
/// 等）を継承するため、この基盤ではなく各中間基底の側で
/// `createProcessor()` を暫定処理器へ差し替える。
open class GPUEffectDefinitionBase: VideoEffectDefinitionBase {
    public override func createProcessor() -> any VideoEffectProcessor {
        GPUEffectPassthroughProcessor()
    }
}
