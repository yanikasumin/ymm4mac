import Foundation

/// プロジェクトのバックアップ（本家 `MainModel.CreateBackup` /
/// `CreateBackupFilePath` / `RefreshBackupFilesList` に対応）。
///
/// 本家は未保存変更の破棄が確定した時点（破棄確認で「保存しない」を
/// 選んだとき。新規作成・開く・閉じる・終了の全経路で共通）で、
/// 破棄される現在の状態をバックアップフォルダへ .ymmp として
/// 保存する。あわせて保存のたびにフォルダ内を保持世代数までへ
/// 掃除する。本家のアプリ側ラッパ（App.xaml.cs の CreateBackup）は
/// 例外を捕捉して記録するだけであり、バックアップの失敗が破棄や
/// 終了を妨げることはない — そのため本ストアも失敗を例外でなく
/// nil で返す。
///
/// 保存先は本家の BackupDirectory（ユーザーディレクトリ配下の
/// `backup`）に相当する位置として、Application Support 配下の
/// `YMM4Mac/Backup` を使う（UserDictionaryStore の配置慣行と同じ
/// 基点）。テスト等では差し替えられる。
public final class ProjectBackupStore {
    /// 保持する世代数（本家 `YMMSettings.BackupLimit2` の既定値 15）。
    public static let retentionLimit = 15

    /// 元プロジェクトのファイル名が無い場合の基名
    /// （本家 `Texts.DefaultProjectFileName` の実文字列「無題」）。
    public static let defaultBaseName = "無題"

    /// バックアップフォルダ。テスト等では差し替えられる。
    public let directoryURL: URL

    public init(directoryURL: URL = ProjectBackupStore.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    /// 既定の保存先: Application Support/YMM4Mac/Backup。
    public static func defaultDirectoryURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("YMM4Mac", isDirectory: true)
            .appendingPathComponent("Backup", isDirectory: true)
    }

    /// バックアップのファイル名（本家 `CreateBackupFilePath` の形式:
    /// `yyyy-MM-dd HH-mm-ss-f {元ファイル名（拡張子なし）}.ymmp`。
    /// 末尾の f は秒の小数第1位）。元ファイル名が無い（未保存の新規
    /// プロジェクト）場合は本家と同じく「無題」を基名にする。
    public static func backupFileName(sourceFileName: String?, date: Date) -> String {
        var base = defaultBaseName
        if let sourceFileName, !sourceFileName.isEmpty {
            let stem = ((sourceFileName as NSString).lastPathComponent as NSString)
                .deletingPathExtension
            if !stem.isEmpty { base = stem }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let tenths = Calendar.current.component(.nanosecond, from: date) / 100_000_000
        return "\(formatter.string(from: date))-\(tenths) \(base).ymmp"
    }

    /// バックアップを作成する。失敗しても例外を投げず nil を返す
    /// （本家の扱いに合わせ、失敗が破棄を妨げないため）。成功したら
    /// 保存先の URL を返し、保持世代数の掃除も行う。
    ///
    /// 本家は書き出す Project の FilePath に保存先（バックアップ
    /// ファイル自身）のパスを入れるため、書き出しはライブモデル
    /// ではなく写しに対して行う。写しは encode → decode の往復で
    /// 作る（書き出しスナップショット・別フォルダ保存と同じ確立した
    /// 方法）。
    @discardableResult
    public func createBackup(
        of project: Project, sourceFileName: String?, date: Date = Date()
    ) -> URL? {
        let url = directoryURL.appendingPathComponent(
            Self.backupFileName(sourceFileName: sourceFileName, date: date)
        )
        do {
            let copy = try YmmpCodec.decode(YmmpCodec.encode(project)).project
            copy.filePath = url.path
            try YmmpCodec.save(copy, toFile: url.path)
        } catch {
            return nil
        }
        pruneBackups()
        return url
    }

    /// 保持世代数を超えた古いバックアップを消す（本家
    /// `RefreshBackupFilesList`: フォルダ内のファイルを更新日時の
    /// 新しい順に保持し、残りを削除する。個別の削除失敗は無視する）。
    public func pruneBackups() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let sorted = entries.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(
                forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(
                forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? .distantPast
            return lhsDate > rhsDate
        }
        for url in sorted.dropFirst(Self.retentionLimit) {
            try? fileManager.removeItem(at: url)
        }
    }
}
