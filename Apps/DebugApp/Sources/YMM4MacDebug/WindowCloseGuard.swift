import AppKit
import SwiftUI

/// メインウィンドウの閉鎖に破棄確認を接続するガード
/// （FE-R32-131-02）。閉じるボタンと ⌘W は
/// DebugAppDelegate.applicationShouldTerminate（⌘Q）を通らないため、
/// NSWindow のデリゲートで windowShouldClose を遮断し、終了側と
/// 共通の WorkspaceState.confirmDiscardUnsavedChanges() を通す。
///
/// SwiftUI の WindowGroup は NSWindow のデリゲートを所有しない
/// （通常は nil）ため、コンテンツのルートに置いたビューが
/// ウィンドウへ出た時点でデリゲートを差し込む。既に別のデリゲート
/// がいる場合はそれを保持し、その windowShouldClose の拒否を
/// 先に尊重する。
///
/// 対象はこのビューを持つメインウィンドウだけ（単一ウィンドウ）。
/// ユーザー辞書編集の別ウィンドウには付けない。
struct WindowCloseGuard: NSViewRepresentable {
    let workspace: WorkspaceState

    func makeNSView(context: Context) -> WindowCloseGuardView {
        let view = WindowCloseGuardView()
        view.workspace = workspace
        return view
    }

    func updateNSView(_ nsView: WindowCloseGuardView, context: Context) {
        nsView.workspace = workspace
    }
}

/// ウィンドウへ出たタイミングでデリゲートを差し込む実体ビュー。
/// NSWindow.delegate は弱参照のため、デリゲートオブジェクトは
/// このビューが強参照で保持する。
final class WindowCloseGuardView: NSView {
    var workspace: WorkspaceState? {
        didSet { closeDelegate?.workspace = workspace }
    }
    private var closeDelegate: WindowCloseDelegate?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        if let existing = window.delegate as? WindowCloseDelegate {
            // 同じガードが既に差し込まれている（ビューの再配置等）。
            closeDelegate = existing
            existing.workspace = workspace
            return
        }
        let delegate = WindowCloseDelegate(
            workspace: workspace, priorDelegate: window.delegate)
        closeDelegate = delegate
        window.delegate = delegate
    }
}

/// windowShouldClose の遮断役。判定はメインスレッド前提で、
/// 終了側（applicationShouldTerminate）の MainActor.assumeIsolated と
/// 同じ作法で WorkspaceState の確認へ橋渡しする。
final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    weak var workspace: WorkspaceState?
    /// 差し込み前にいたデリゲート。windowShouldClose を実装して
    /// いる場合は、その拒否を閉鎖側の確認より先に尊重する。
    private weak var priorDelegate: NSWindowDelegate?

    init(workspace: WorkspaceState?, priorDelegate: NSWindowDelegate?) {
        self.workspace = workspace
        self.priorDelegate = priorDelegate
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let priorDelegate,
           priorDelegate.responds(to: #selector(NSWindowDelegate.windowShouldClose(_:))),
           priorDelegate.windowShouldClose?(sender) == false {
            return false
        }
        guard let workspace else { return true }
        return MainActor.assumeIsolated {
            if !workspace.hasUnsavedChanges { return true }
            if workspace.discardConfirmedForTermination {
                // 終了フローで確認済み。閉鎖側の確認を二重に出さず、
                // 印はここで消費する（FE-R32-131-02）。
                workspace.discardConfirmedForTermination = false
                return true
            }
            return workspace.confirmDiscardUnsavedChanges()
        }
    }
}
