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
/// がいる場合はそれを奪わず、次の形で共存させる（FE-R33-131-03）。
///
/// - 差し込み前のデリゲートは設置中だけ強参照で保持し、
///   windowShouldClose 以外のデリゲート通知は全てそちらへ
///   転送する（WindowCloseDelegate のメッセージ転送）。
/// - ガードの取り外し（ビューの離脱・dismantle）では、元の
///   デリゲートをウィンドウへ復元してから保持を解く。
/// - 設置後に SwiftUI 等がデリゲートを差し替えた場合は、
///   updateNSView の契機で検出し、そのデリゲートを新しい
///   「差し込み前」として包み直す（閉鎖確認が無効化されない）。
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
        nsView.ensureInstalled()
    }

    static func dismantleNSView(_ nsView: WindowCloseGuardView, coordinator: ()) {
        nsView.detach()
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
    /// デリゲートを差し込んだウィンドウ。ビューの離脱時に、
    /// どのウィンドウのデリゲートを復元すべきかを追う。
    private weak var installedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let installedWindow, installedWindow !== window {
            // 前のウィンドウから離れた（またはウィンドウ無しに
            // なった）。元のデリゲートを復元してから手放す。
            restoreDelegate(on: installedWindow)
        }
        if window != nil {
            install()
        }
    }

    /// 設置後にデリゲートを差し替えられていないかを確認し、
    /// 差し替えられていたら包み直す（updateNSView から呼ぶ）。
    func ensureInstalled() {
        guard let window, installedWindow === window else { return }
        if let closeDelegate, window.delegate === closeDelegate { return }
        install()
    }

    /// ガードの取り外し。元のデリゲートを復元する。
    func detach() {
        if let installedWindow {
            restoreDelegate(on: installedWindow)
        }
    }

    private func install() {
        guard let window else { return }
        if let existing = window.delegate as? WindowCloseDelegate {
            // 同じガードが既に差し込まれている（ビューの再配置等）。
            // 所有を引き継ぎ、ワークスペースだけ差し替える。
            closeDelegate = existing
            existing.owner = self
            existing.workspace = workspace
            installedWindow = window
            return
        }
        let delegate = WindowCloseDelegate(
            workspace: workspace, priorDelegate: window.delegate)
        delegate.owner = self
        closeDelegate = delegate
        window.delegate = delegate
        installedWindow = window
    }

    private func restoreDelegate(on window: NSWindow) {
        guard let closeDelegate, closeDelegate.owner === self,
              window.delegate === closeDelegate
        else { return }
        window.delegate = closeDelegate.priorDelegate
        self.closeDelegate = nil
        if installedWindow === window {
            installedWindow = nil
        }
    }
}

/// windowShouldClose の遮断役。判定はメインスレッド前提で、
/// 終了側（applicationShouldTerminate）の MainActor.assumeIsolated と
/// 同じ作法で WorkspaceState の確認へ橋渡しする。
///
/// windowShouldClose 以外の NSWindowDelegate 通知は、自分で実装
/// しないものを差し込み前のデリゲートへ転送する（responds と
/// forwardingTarget の上書きによる多重化。FE-R33-131-03）。
/// これにより、元のデリゲートが担っていた閉鎖以外の通知
/// （windowWillClose、移動・サイズ変更、主ウィンドウ状態など）が
/// ガードの設置で失われない。
final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    weak var workspace: WorkspaceState?
    /// 差し込み前にいたデリゲート。設置中は強参照で保持する
    /// （弱参照だと所有者がいない場合に転送先ごと消えるため。
    /// 保持は設置期間だけに限り、復元時に解放される）。
    private(set) var priorDelegate: NSWindowDelegate?
    /// このデリゲートを差し込んだガードビュー。復元は差し込んだ
    /// 本人だけが行う（ビューの作り直しで所有が移った後に、旧
    /// ビューの取り外しが新しい設置を壊さないため）。
    weak var owner: WindowCloseGuardView?

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

    // MARK: - 差し込み前デリゲートへの転送

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return priorDelegate?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let priorDelegate, priorDelegate.responds(to: aSelector) {
            return priorDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }
}
