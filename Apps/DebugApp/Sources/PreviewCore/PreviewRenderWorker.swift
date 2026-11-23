import CoreGraphics
import Foundation
import YMM4Core
import YMM4GPU

/// 描画セッションの境界（PreviewBox の実体と、試験用の差し替えを
/// 同じ形で扱うためのプロトコル）。生成・描画・破棄は全て
/// PreviewRenderWorker の専用キュー上で行われる。
public protocol PreviewRenderSession: AnyObject {
    /// 初期化に失敗した場合の、利用者向けの理由文。成功時は nil。
    var initializationFailure: String? { get }
    /// この描画セッションの診断収集先（R6-06）。
    var diagnostics: RenderDiagnosticsCollector { get }
    /// 指定フレームを合成して読み戻す。失敗時は nil。
    func render(frame: Int, timeline: Timeline, usage: TimelineSourceUsage) -> CGImage?
    /// 資源を解放する。
    func dispose()
}

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
/// 順序制御（第11ラウンド R11-01 の処分で再設計）:
/// - フレーム要求はキューへ仕事を積まない。ロックで保護した保留
///   スロットへ最新値だけを書き込み、描画ループがまだ動いていな
///   ければ起動する。したがって保留は構造的に最大 1 件で、要求は
///   上書きで間引かれる（latest-wins）。
/// - 描画ループは「保留を 1 件取り出して描く」ブロックを 1 回
///   ごとにキューへ積み直す。モデルの差し替えや無効化のブロック
///   が描画と描画の間に割り込めるため、長い再生でもモデル操作が
///   飢餓しない。
/// - 結果の新旧は、呼び出し側が確定した識別子（セッションキー・
///   セッション世代・モデル版数）で判定する。採番は呼び出し側が
///   一元的に行い、ワーカーは受け取った識別子をそのまま返す
///   （二重採番はしない。R11-04）。
/// - フレーム要求にも発行時点の識別子を付け、要求はその識別子の
///   モデルでだけ描く（第12ラウンド R12-01）。識別子が現行モデル
///   と異なる要求は消費せずに残し、対象モデルが設置された時点で
///   描画を再開する。キュー順序だけに頼ると、モデル差し替えより
///   先に積まれた描画ブロックが新世代の要求を旧モデルで消費し、
///   要求が失われる経路ができるため、この照合が要る。
/// - 保留が単一スロットであるため、取り出された要求は取り出し
///   時点で常に最新であり、世代番号による追加の間引きは不要
///   （第11ラウンド処分の検討で確認し、機構を置かないことにした）。
/// - 完成した画像は、同じモデルのものであれば後続の要求があって
///   も採用する（合成 36.7 ms に対して要求 33 ms 周期のため、新
///   要求があるという理由だけで破棄すると画面が更新されなくなる）。
public final class PreviewRenderWorker: @unchecked Sendable {
    /// 結果の識別子一式。呼び出し側が確定し、通知でそのまま返る。
    public struct Identity: Equatable, Sendable {
        public var key: PreviewBox.SessionKey
        public var generation: Int
        public var version: Int

        public init(key: PreviewBox.SessionKey, generation: Int, version: Int) {
            self.key = key
            self.generation = generation
            self.version = version
        }
    }

    /// 受け入れ実測と順序テストのための計数（ロック保護）。
    public struct Stats: Equatable {
        public var requestsReceived = 0
        public var requestsOverwritten = 0
        public var rendersStarted = 0
        public var rendersCompleted = 0

        public init() {}
    }

    /// 完成画像の通知（メインキュー）。画像・識別子・フレーム、
    /// この描画で発生した診断とセッション履歴の集約（R6-06）。
    public var onImage: ((
        CGImage, Identity, Int,
        [RenderDiagnosticsCollector.Entry], [RenderDiagnosticsCollector.Entry]
    ) -> Void)?
    /// 合成が失敗したときの通知（メインキュー）。識別子・フレーム、
    /// この描画の診断とセッション履歴の集約。
    public var onRenderFailed: ((
        Identity, Int,
        [RenderDiagnosticsCollector.Entry], [RenderDiagnosticsCollector.Entry]
    ) -> Void)?
    /// モデルの初期化に失敗したときの通知（メインキュー）。
    /// 理由文と、そのモデルの識別子（R11-03）。
    public var onModelFailed: ((String, Identity) -> Void)?

    private let queue = DispatchQueue(
        label: "ymm4.preview.render", qos: .userInitiated
    )
    private let makeSessionOverride: (
        (PreviewBox.SessionKey, [Timeline], Timeline, URL?)
            -> any PreviewRenderSession
    )?
    /// 既定のセッション生成で PreviewBox へ渡す共有基盤
    /// （Issue #70 段階4）。アプリがワークスペースの基盤を差し、
    /// プレビューがアプリセッションと同じ台帳を参照するように
    /// する。セッション生成より前に差すこと。makeSession を
    /// 差し替えた場合は生成側が担うため使われない。
    public var mediaSupport: FFmpegMediaSupport?

    // MARK: - ロック保護の状態（描画の実行中は保持しない）

    /// 保留中のフレーム要求。発行時点の識別子を持ち、その識別子の
    /// モデルでだけ描かれる（R12-01）。
    private struct PendingRequest {
        var frame: Int
        var usage: TimelineSourceUsage
        var seq: Int
        var identity: Identity
    }

    private let lock = NSLock()
    private var model: (identity: Identity, session: any PreviewRenderSession, timeline: Timeline)?
    private var pending: PendingRequest?
    /// 要求の通し番号。無効化の時点で区切り、区切り以前の要求だけを
    /// 落とすために使う（無効化の後に来た要求を巻き込まない）。
    private var requestSeq = 0
    private var loopActive = false
    private var statsValue = Stats()

    /// セッション生成の差し替え点。既定は PreviewBox を作る
    /// （`mediaSupport` が差されていればそれを渡す）。
    /// 試験では描画時間を制御できる偽セッションを差し込む。
    public init(
        makeSession: ((
            PreviewBox.SessionKey, [Timeline], Timeline, URL?
        ) -> any PreviewRenderSession)? = nil
    ) {
        self.makeSessionOverride = makeSession
    }

    private func createSession(
        key: PreviewBox.SessionKey, timelines: [Timeline],
        timeline: Timeline, baseDirectory: URL?
    ) -> any PreviewRenderSession {
        if let makeSessionOverride {
            return makeSessionOverride(key, timelines, timeline, baseDirectory)
        }
        return PreviewBox(
            key: key, timeline: timeline, timelines: timelines,
            baseDirectory: baseDirectory, mediaSupport: mediaSupport
        )
    }

    public var stats: Stats {
        lock.lock()
        defer { lock.unlock() }
        return statsValue
    }

    /// 描画モデルを差し替える。識別子は呼び出し側が確定して渡す。
    /// セッションの生成と旧セッションの破棄はキュー上で行い、描画
    /// ブロックの合間に処理される。保留中のフレーム要求は消さない
    /// （別のモデル向けの要求は消費もされない。R12-01）。設置の
    /// 完了時に、このモデル向けの保留があれば描画を再開する:
    /// 要求がモデル設置より先に届いていた場合、描画ループは識別子
    /// 不一致で止まっているため、再開はここで担う。
    public func setModel(
        identity: Identity,
        timelines: [Timeline],
        timeline: Timeline,
        baseDirectory: URL?
    ) {
        queue.async { [self] in
            let newSession = createSession(
                key: identity.key, timelines: timelines,
                timeline: timeline, baseDirectory: baseDirectory
            )
            if let failure = newSession.initializationFailure {
                newSession.dispose()
                DispatchQueue.main.async { [self] in
                    onModelFailed?(failure, identity)
                }
                return
            }
            lock.lock()
            let old = model
            model = (identity, newSession, timeline)
            let shouldKick = pending?.identity == identity && !loopActive
            if shouldKick { loopActive = true }
            lock.unlock()
            old?.session.dispose()
            if shouldKick {
                queue.async { [self] in step() }
            }
        }
    }

    /// フレームの描画を要求する。キューへ仕事は積まず、保留
    /// スロットへ最新値だけを書き込む。識別子は要求の発行時点の
    /// モデルのもので、描画はそのモデルに対してだけ行われる。
    public func request(frame: Int, usage: TimelineSourceUsage, identity: Identity) {
        lock.lock()
        statsValue.requestsReceived += 1
        if pending != nil { statsValue.requestsOverwritten += 1 }
        requestSeq += 1
        pending = PendingRequest(
            frame: frame, usage: usage, seq: requestSeq, identity: identity
        )
        let shouldStart = !loopActive
        if shouldStart { loopActive = true }
        lock.unlock()
        if shouldStart {
            queue.async { [self] in step() }
        }
    }

    /// 指定世代のセッションを終了する。セッションはキュー上で
    /// 破棄する。保留の破棄は、呼び出し時点までの要求だけを対象に
    /// する（その後に来た新しい世代向けの要求を、ブロックの実行が
    /// 遅れても巻き込まない）。
    public func invalidate(generation: Int) {
        lock.lock()
        let dropThroughSeq = requestSeq
        lock.unlock()
        queue.async { [self] in
            lock.lock()
            var target: (any PreviewRenderSession)?
            if model?.identity.generation == generation {
                target = model?.session
                model = nil
            }
            if let pending, pending.seq <= dropThroughSeq {
                self.pending = nil
            }
            lock.unlock()
            target?.dispose()
        }
    }

    // MARK: - 描画ループ（キュー上、1 描画 = 1 ブロック）

    private func step() {
        lock.lock()
        let currentModel = model
        var request: PendingRequest?
        if let pending,
           let currentModel, pending.identity == currentModel.identity {
            request = pending
            self.pending = nil
        }
        if request == nil {
            // 描くべき要求がない（保留がない、モデルが未設置、また
            // は保留が別のモデル向け）。停止判定は要求の確認と同じ
            // ロック区間で完結させる。区間を分けると、確認と停止の
            // 間に届いた要求が「ループ稼働中」と誤認して起動の機会
            // を失う（lost wake-up。R13-01）。この形なら、停止前に
            // 届いた要求は上の確認の対象になっており、停止後に届
            // いた要求は loopActive == false を見てループを起動
            // できる。別のモデル向けの保留は残し、対象モデルの
            // 設置完了時に setModel 側が再開する。
            loopActive = false
        }
        lock.unlock()

        guard let request, let currentModel else { return }
        lock.lock()
        statsValue.rendersStarted += 1
        lock.unlock()
        // 描画の間に発生した診断だけを切り分けるため、開始時点の
        // 通し番号を控える（現在の失敗状態と履歴を分ける — R6-06）。
        let diagnosticsMark = currentModel.session.diagnostics.eventCount
        let image = currentModel.session.render(
            frame: request.frame, timeline: currentModel.timeline,
            usage: request.usage
        )
        let failures = currentModel.session.diagnostics.entries(after: diagnosticsMark)
        let history = currentModel.session.diagnostics.allEntries()
        lock.lock()
        statsValue.rendersCompleted += 1
        lock.unlock()
        let identity = currentModel.identity
        DispatchQueue.main.async { [self] in
            if let image {
                onImage?(image, identity, request.frame, failures, history)
            } else {
                onRenderFailed?(identity, request.frame, failures, history)
            }
        }
        queue.async { [self] in step() }
    }
}
