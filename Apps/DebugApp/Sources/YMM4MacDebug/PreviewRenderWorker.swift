import CoreGraphics
import Foundation
import YMM4Core
import YMM4GPU

/// プレビュー合成をメインキューから外すための描画ワーカー（R6-02）。
///
/// 背景: 再生中の合成は実測で平均 20.2 ms、最重区間では 33 ms の
/// 位置通知周期を超えてメインキューを飽和させていた（台帳 R6-02-MEAS）。
/// 合成器（TimelineComposer）は編集中のモデルを直接読むため、単に
/// 別キューへ移すと編集側の書き換えと読み取りが競合する。そこで
/// 描画側は編集モデルから独立したスナップショットだけを読み、
/// 生成・描画・破棄の全てをこのワーカーの専用直列キューへ閉じ込める
/// （設計相談 第9ラウンドの処方）。
///
/// 規則:
/// - モデル差し替え（setModel）は編集の反映時にだけ行う。フレーム
///   要求（request）はモデルを触らない。
/// - 要求は実行中 1 件＋保留 1 件まで。保留は常に最新の要求で上書き
///   する（古い位置の合成を省く）。
/// - 完成した画像は、同じモデルのものであれば後続の要求があっても
///   採用する（合成 36.7 ms に対して要求 33 ms 周期のため、新要求が
///   あるという理由だけで破棄すると画面が更新されなくなる）。
/// - 結果の新旧は呼び出し側がセッションキーとモデル版数で判定する。
///   キューの直列性により、生成・描画・破棄が重なることはない。
final class PreviewRenderWorker: @unchecked Sendable {
    /// 完成画像の通知（メインキューで呼ばれる）。引数は画像、その
    /// 画像を描いたセッションキーとモデル版数、要求フレーム。
    var onImage: ((CGImage, PreviewBox.SessionKey, Int, Int) -> Void)?
    /// 合成が失敗したときの通知（メインキュー）。キー・版数・フレーム。
    var onRenderFailed: ((PreviewBox.SessionKey, Int, Int) -> Void)?
    /// モデルの差し替えで初期化に失敗したときの通知（メインキュー）。
    var onModelFailed: ((String) -> Void)?

    private let queue = DispatchQueue(
        label: "ymm4.preview.render", qos: .userInitiated
    )
    // 以下は全て queue 上でのみ触る。
    private var box: PreviewBox?
    private var snapshotTimeline: Timeline?
    private var sessionKey: PreviewBox.SessionKey?
    private var modelVersion = 0
    private var isRendering = false
    private var pending: (frame: Int, usage: TimelineSourceUsage)?

    /// 描画モデルを差し替える。スナップショット側のタイムライン群を
    /// 受け取り、合成セッションを作り直す。版数はキュー側で処理順に
    /// 割り当てるため、呼び出し側は setModel の呼び出し回数を数える
    /// ことで同じ版数列を再現できる。
    func setModel(
        key: PreviewBox.SessionKey,
        timelines: [Timeline],
        timeline: Timeline,
        baseDirectory: URL?
    ) {
        queue.async { [self] in
            box?.dispose()
            box = nil
            snapshotTimeline = nil
            sessionKey = key
            modelVersion += 1
            let newBox = PreviewBox(
                key: key, timeline: timeline, timelines: timelines,
                baseDirectory: baseDirectory
            )
            if let failure = newBox.initializationFailure {
                newBox.dispose()
                DispatchQueue.main.async { [self] in
                    onModelFailed?(failure)
                }
                return
            }
            box = newBox
            snapshotTimeline = timeline
        }
    }

    /// フレームの描画を要求する。実行中なら保留へ回し、保留は常に
    /// 最新の要求で置き換える。
    func request(frame: Int, usage: TimelineSourceUsage) {
        queue.async { [self] in
            if isRendering {
                pending = (frame, usage)
                return
            }
            startRender(frame: frame, usage: usage)
        }
    }

    /// セッションを終了する。保留を消し、合成器はこのキュー上で
    /// 破棄する。進行中の描画は直列キュー上にあるため重ならない。
    func invalidate() {
        queue.async { [self] in
            pending = nil
            box?.dispose()
            box = nil
            snapshotTimeline = nil
            sessionKey = nil
        }
    }

    // MARK: - キュー上の処理

    private func startRender(frame: Int, usage: TimelineSourceUsage) {
        guard let box, let snapshotTimeline, let sessionKey else {
            isRendering = false
            return
        }
        isRendering = true
        let version = modelVersion
        let key = sessionKey
        let image = box.render(
            frame: frame, timeline: snapshotTimeline, usage: usage
        )
        isRendering = false
        DispatchQueue.main.async { [self] in
            if let image {
                onImage?(image, key, version, frame)
            } else {
                onRenderFailed?(key, version, frame)
            }
        }
        if let next = pending {
            pending = nil
            startRender(frame: next.frame, usage: next.usage)
        }
    }
}
