import Foundation

/// 編集セッションの所有権トークン（FE-R20-126-03）。
///
/// `EditRecorder.beginSession` が開始のたびに発行し、セッションの
/// 所有者だけが保持する。値変更の記録・セッションの確定・破棄は
/// このトークンの提示を必須とし、所有者でない経路の変更が有効な
/// セッションへ混入することを防ぐ。値は識別子でしかなく、生成は
/// `EditRecorder` だけが行う。
public struct EditSessionToken: Equatable, Sendable {
    let id: UUID

    init(id: UUID) {
        self.id = id
    }
}

/// Undo 記録の集約点（FE-UNDO-WIRING）。
///
/// Core の `EditCoordinator`（履歴とトランザクションの統括）への
/// 投入経路をここ1か所へ集約する。所有はアプリ層の `WorkspaceState`
/// が持ち、プロジェクト（ウィンドウ）ごとに1つである。各編集経路は:
///
/// - 離散編集（数値確定・トグル・選択など）: 書き込みの入口で
///   `canRecordValueChange` を確認し、記録できる場合だけモデルを
///   変更してから `recordValueChange` で記録する。セッションが
///   有効でなければ、その変更だけのトランザクションとして即時に
///   確定する。
/// - 連続編集（スライダ・ドラッグ）: `beginSession` で所有権トークン
///   つきのトランザクションを開き、途中の変更はトークンを提示して
///   同じセッションへ蓄積され（同一対象の連鎖は Core の収集規則で
///   統合される）、終了時に `commitSession` / `cancelSession` で
///   閉じる。開始が拒否された場合はトークンが得られず、その編集は
///   行われない（呼び出し側が入口で確認する）。
/// - タイムラインの構造変更（追加・削除・ドラッグ）: 変更前後の
///   スナップショット差分をコマンド化する `recordTimelineChange` /
///   `TimelineEditSnapshot` を使う。開始できない場合は変更自体を
///   実行しない（戻り値で呼び出し側へ伝える）。
///
/// セッションの所有権（FE-R20-126-03）: 有効なセッションがある間、
/// 所有者でない経路の離散編集はセッションへ取り込まず、モデルも
/// 変更しない。記録は後付けではなく、書き込み経路の入口
/// （`canRecordValueChange`）で可否を確認する形に統一する。
/// `recordValueChange` 自身もトークンの照合を行い、入口確認を
/// すり抜けた記録投入を二重に防ぐ。
///
/// トークンの失効と Coordinator の状態（FE-R21-126-01）: 受け付け
/// 可否の判定は `acceptsValueChange` の1か所に寄せ、入口確認と
/// 記録側で共有する。セッションが無い間に非 nil のトークンを提示
/// された場合は受理しない — そのトークンは終了・取消・プロジェ
/// クト切り替えで失効したセッションのものであり、失効後に届いた
/// 遅延イベントが新しい履歴へ紛れ込む経路を断つ。また、セッション
/// が無い間の離散編集は Coordinator が本当に idle のときだけ許可
/// する。復元処理中（キャンセルの巻き戻し中）は `activeTransaction`
/// が nil でも新規編集を受け付けない（入口を通った後に記録だけが
/// 拒否される不整合を防ぐ）。
///
/// 本家の自動監視（UndoRedoable）は模倣しない。ここを通らない編集は
/// 記録されず、Undo 対応とはみなさない（未移行経路は実装ログに列挙）。
///
/// 配置は Core（FE-R20-126-01）: アプリ層にはテスト対象が無く、
/// 記録の振る舞い（差分の適用でタイムラインのキャッシュが壊れない
/// こと等）を回帰テストで固定するため、集約点と差分捕捉を Core の
/// テスト対象へ移した。所有と接続の形はアプリ層時代と変えていない。
public final class EditRecorder {
    /// 履歴とトランザクションの統括（Core）。
    public let coordinator = EditCoordinator()

    /// 有効なセッション（所有権トークンとトランザクションの組）。
    /// 同時に有効なセッションは1つだけであり、所有の追跡は監査
    /// Round 10 の接続条件（開始していないセッションの終了通知では
    /// Undo 処理をしない）の実装である。
    private var session: (token: EditSessionToken, transaction: EditTransaction)?

    /// セッションが有効か。
    public var hasActiveSession: Bool { session != nil }

    /// トークンが指すセッションのトランザクション（差分の投入用）。
    /// トークンが現在のセッションと一致しない場合は nil。
    public func sessionTransaction(for token: EditSessionToken) -> EditTransaction? {
        guard let session, session.token == token else { return nil }
        return session.transaction
    }

    public init() {}

    // MARK: - セッション（連続編集）

    /// 連続編集のセッションを開始し、所有権トークンを返す。既に
    /// セッションが有効な場合、および Core 側で開始が拒否された
    /// 場合は nil を返し、その編集は開始されない（呼び出し側は
    /// トークンが得られた場合だけ書き込みへ進む）。
    @discardableResult
    public func beginSession() -> EditSessionToken? {
        guard session == nil,
              let transaction = coordinator.beginTransaction()
        else { return nil }
        let token = EditSessionToken(id: UUID())
        session = (token: token, transaction: transaction)
        return token
    }

    /// セッションを確定し、蓄積した変更を履歴1エントリとして登録する。
    /// トークンが現在のセッションと一致しない場合は何もしない
    /// （他人のセッションを誤って確定しない）。
    public func commitSession(token: EditSessionToken) {
        guard let session, session.token == token else { return }
        self.session = nil
        coordinator.commit(session.transaction)
    }

    /// セッションを破棄する。蓄積した変更は Core 側で開始状態へ
    /// 巻き戻される。タイムラインのドラッグでは、操作層自身が
    /// スナップショットから復元済みのため、こちらに蓄積される
    /// コマンドは通常は無く、巻き戻しは空振りになる。
    /// トークンが一致しない場合は何もしない。
    public func cancelSession(token: EditSessionToken) {
        guard let session, session.token == token else { return }
        self.session = nil
        coordinator.cancel(session.transaction)
    }

    /// プロジェクト切り替え時の後片付け。未確定のセッションがあれば
    /// 先に破棄（巻き戻し）してから履歴を消す順序に統一する
    /// （監査 Round 7 の接続条件）。呼び出しは `WorkspaceState` の
    /// プロジェクト差し替え直前に限る。
    public func resetForProjectSwitch() {
        if let session {
            cancelSession(token: session.token)
        }
        coordinator.history.clear()
    }

    // MARK: - 値変更の記録

    /// 値変更を受け付けるかの判定（FE-R21-126-01）。入口確認
    /// （`canRecordValueChange`）と記録側（`recordValueChange`）で
    /// 共有する唯一の判定であり、両者で結論がずれることはない。
    ///
    /// - セッションが有効な間は、その所有者（トークン一致）だけが
    ///   書き込める。
    /// - セッションが無い間は、トークンなしの離散編集だけを、
    ///   Coordinator が本当に idle（有効なトランザクションが無く、
    ///   復元処理中でもない）のときに許可する。非 nil のトークンは
    ///   失効済みとして拒否する。
    private func acceptsValueChange(sessionToken: EditSessionToken?) -> Bool {
        if let session {
            return sessionToken == session.token
        }
        guard sessionToken == nil else { return false }
        return coordinator.isIdle
    }

    /// 値の書き込みが記録可能な状態か（書き込み経路の入口確認。
    /// FE-R20-126-03、FE-R21-126-01）。
    ///
    /// false の場合、呼び出し側はモデル変更自体を行わない。
    public func canRecordValueChange(sessionToken: EditSessionToken? = nil) -> Bool {
        acceptsValueChange(sessionToken: sessionToken)
    }

    /// 適用済みの値変更を記録する。セッションが有効ならそこへ蓄積し、
    /// そうでなければその変更だけのトランザクションとして即時に
    /// 確定する。
    ///
    /// 受け付け可否は入口確認と同じ判定（`acceptsValueChange`）を
    /// 通す。所有者でない記録、失効トークンによる記録、復元処理中の
    /// 記録は混入を防ぐため破棄する。モデル変更の防止は入口確認
    /// （`canRecordValueChange`）の責務であり、ここの照合は入口を
    /// すり抜けた投入への二重の防壁である。
    public func recordValueChange<Value: Equatable>(
        target: EditTargetKey,
        oldValue: Value,
        newValue: Value,
        apply: @escaping (Value) -> Void,
        sessionToken: EditSessionToken? = nil
    ) {
        guard oldValue != newValue else { return }
        guard acceptsValueChange(sessionToken: sessionToken) else { return }
        if let session {
            session.transaction.addValueChange(
                target: target, oldValue: oldValue, newValue: newValue,
                apply: apply)
            return
        }
        guard let transaction = coordinator.beginTransaction()
        else { return }
        transaction.addValueChange(
            target: target, oldValue: oldValue, newValue: newValue,
            apply: apply)
        coordinator.commit(transaction)
    }

    // MARK: - タイムライン構造変更の記録

    /// タイムラインの構造変更（追加・削除・移動など）を、変更前後の
    /// スナップショット差分として1トランザクションに記録する。
    ///
    /// トランザクションを開始できない場合（別のトランザクションや
    /// セッションが有効な間）は `body` を実行せず false を返す
    /// （FE-R20-126-02）。「記録できない変更を無記録で実行する」と、
    /// 変更だけがモデルに残り履歴と乖離するため、実行可否は呼び出し
    /// 側が戻り値で判断する契約とする。実行した場合は true を返す
    /// （実質的な変更が無く履歴エントリが作られなかった場合も、
    /// 変更の実行自体は行われているため true）。
    @discardableResult
    public func recordTimelineChange(timeline: Timeline, _ body: () -> Void) -> Bool {
        guard let transaction = coordinator.beginTransaction() else {
            return false
        }
        let snapshot = TimelineEditSnapshot(timeline: timeline)
        body()
        snapshot.recordDiff(into: transaction, timeline: timeline)
        coordinator.commit(transaction)
        return true
    }
}
