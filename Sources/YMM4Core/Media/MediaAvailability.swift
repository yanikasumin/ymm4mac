import Foundation

/// 素材ごとの「開けたか」の状態モデル（Issue #70 段階1）。
///
/// 利用可否の判定は1か所（本レジストリ）に集約し、UI とデコーダが
/// 別々に失敗判定を持たないようにする（設計判断）。本単位では
/// 状態と、その判定材料（デコード証拠）の受け口までを置く。
/// 状態遷移を起こす実行（プローブ・デコード・再試行方針）は
/// 次段階のデコード管理者が担い、本レジストリはプロジェクト単位で
/// 1つ保持される土台として置く。
///
/// 実測（着工前実測 系統6）の反映: **終了コードとフレーム数だけでは
/// 「開けたか」の判定に不足する**。切断した MKV は終了コード 0 の
/// まま途中終了し、ペイロード破損 MP4 は終了コード 0・全フレーム
/// 出力でも stderr にデコードエラーが出た。そのため証拠には
/// stderr のエラー有無と期待フレーム数との照合を含め、終了コード 0
/// でも失敗の兆候を拾える形にしている。

// MARK: - 素材の識別

/// 状態を引くための素材キー。アイテムが保持するパス文字列（解決前の
/// 字面）と、呼び出し側が与えるアイテム識別（任意）の組。
/// 同じファイルを複数アイテムが参照する場合はパスだけでも引けるし、
/// アイテム単位の状態が必要なら識別を付けて区別できる。
public struct MediaMaterialKey: Hashable, Sendable {
    public var filePath: String
    public var itemIdentifier: String?

    public init(filePath: String, itemIdentifier: String? = nil) {
        self.filePath = filePath
        self.itemIdentifier = itemIdentifier
    }
}

// MARK: - 失敗と状態

/// 失敗の種別。UI の案内文言はこの種別で出し分ける前提。
public enum MediaAvailabilityFailureKind: String, Equatable, Sendable {
    /// ファイルが存在しない。
    case fileNotFound
    /// 非対応形式、または復号に失敗した。
    case unsupportedOrDecodeFailed
    /// FFmpeg が未設定・解決できない。
    case ffmpegUnavailable
    /// 開けた後に途中で失敗した。
    case midStreamFailure
}

/// 失敗1件。
public struct MediaAvailabilityFailure: Error, Equatable, Sendable {
    public var kind: MediaAvailabilityFailureKind
    /// 詳細（stderr 抜粋や対象の説明など、表示・診断用）。
    public var detail: String
    /// 発生時刻。
    public var occurredAt: Date

    public init(kind: MediaAvailabilityFailureKind, detail: String, occurredAt: Date) {
        self.kind = kind
        self.detail = detail
        self.occurredAt = occurredAt
    }
}

/// 素材の利用可否の状態。
public enum MediaAvailabilityState: Equatable, Sendable {
    /// まだ試していない。
    case notAttempted
    /// 読み込み中（プローブ・初回デコードの途中）。
    case loading
    /// 実際に開けて使えることが確認できた。
    case available
    /// 失敗した（種別つき）。
    case failed(MediaAvailabilityFailure)

    public var failure: MediaAvailabilityFailure? {
        if case .failed(let failure) = self { return failure }
        return nil
    }

    public var isAvailable: Bool { self == .available }
}

// MARK: - デコード証拠（判定材料）

/// デコード試行の証拠。利用可否の判定材料として、終了コード以外の
/// 兆候も保持する。判定そのものの実行はデコード段階の仕事であり、
/// ここでは材料と、その機械的な兆候抽出までを提供する。
public struct MediaDecodeEvidence: Equatable, Sendable {
    /// プロセスの終了コード。プロセスを使わない経路では nil。
    public var exitStatus: Int32?
    /// 実際に得られたフレーム数（映像）・読み取りの成否の材料。
    public var producedFrameCount: Int?
    /// 期待フレーム数（プローブ等から見込む値）。不明なら nil。
    public var expectedFrameCount: Int?
    /// stderr の抜粋（先頭部分）。全文は保持しない前提で呼び出し側が
    /// 切り詰めて渡す。
    public var standardErrorExcerpt: String?

    public init(
        exitStatus: Int32? = nil,
        producedFrameCount: Int? = nil,
        expectedFrameCount: Int? = nil,
        standardErrorExcerpt: String? = nil
    ) {
        self.exitStatus = exitStatus
        self.producedFrameCount = producedFrameCount
        self.expectedFrameCount = expectedFrameCount
        self.standardErrorExcerpt = standardErrorExcerpt
    }

    /// 失敗の兆候として抽出できる材料。
    public enum FailureIndicator: String, Equatable, Sendable {
        /// 終了コードが 0 でない。
        case exitStatusNonZero
        /// stderr にデコードエラーの文言がある。
        case standardErrorReportsDecodeError
        /// 得られたフレーム数が期待より少ない。
        case frameCountShortfall
        /// フレームが1枚も得られなかった。
        case noFramesProduced
    }

    /// stderr 中のデコードエラー文言（小文字で照合）。
    /// ffmpeg の復号失敗は "error while decoding stream"、
    /// "Invalid data found when processing input" 等の形で出る。
    private static let decodeErrorMarkers: [String] = [
        "error while decoding",
        "invalid data found",
        "decode error",
        "error submitting",
        "failed to decode",
        "corrupt input",
        "corrupt decoded frame",
    ]

    /// stderr にデコードエラーの文言があるか。
    public var standardErrorReportsDecodeError: Bool {
        guard let excerpt = standardErrorExcerpt?.lowercased() else { return false }
        return Self.decodeErrorMarkers.contains(where: { excerpt.contains($0) })
    }

    /// 証拠から機械的に読み取れる失敗の兆候。
    public var failureIndicators: [FailureIndicator] {
        var indicators: [FailureIndicator] = []
        if let exitStatus, exitStatus != 0 {
            indicators.append(.exitStatusNonZero)
        }
        if standardErrorReportsDecodeError {
            indicators.append(.standardErrorReportsDecodeError)
        }
        if let producedFrameCount, let expectedFrameCount, producedFrameCount < expectedFrameCount {
            indicators.append(.frameCountShortfall)
        }
        if producedFrameCount == 0 {
            indicators.append(.noFramesProduced)
        }
        return indicators
    }

    /// 終了コードが 0 なのに失敗の兆候があるか。実測では切断 MKV
    /// （フレーム不足）と破損 MP4（stderr のエラー）がこの形になり、
    /// 終了コードだけの判定では成功と誤る。
    public var suggestsFailureDespiteSuccessExit: Bool {
        exitStatus == 0 && !failureIndicators.isEmpty
    }
}

// MARK: - 記録とレジストリ

/// 素材1件の現在の記録。
public struct MediaAvailabilityRecord: Equatable, Sendable {
    public var key: MediaMaterialKey
    public var state: MediaAvailabilityState
    /// 最後に状態・証拠が更新された時刻。未記録の初期レコードでは
    /// エポック（1970-01-01）になり、「まだ記録が無い」ことを表す。
    public var updatedAt: Date
    /// 直近のデコード証拠。未試行では nil。
    public var lastEvidence: MediaDecodeEvidence?

    public init(
        key: MediaMaterialKey, state: MediaAvailabilityState,
        updatedAt: Date, lastEvidence: MediaDecodeEvidence?
    ) {
        self.key = key
        self.state = state
        self.updatedAt = updatedAt
        self.lastEvidence = lastEvidence
    }
}

/// プロジェクト単位で素材の利用可否を保持するレジストリ。
/// 次段階のデコード管理者（セッションプール・再試行方針の所有者）が
/// この上に載る土台であり、状態の書き込みは管理者経由に寄せる前提。
/// スレッド安全（内部ロック）で、どのキューからでも呼べる。
public final class MediaAvailabilityRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [MediaMaterialKey: MediaAvailabilityRecord] = [:]

    public init() {}

    /// 現在の記録を返す。未登録なら未試行の初期レコードを返す
    /// （読み取りでは登録しない）。
    public func record(for key: MediaMaterialKey) -> MediaAvailabilityRecord {
        lock.lock()
        defer { lock.unlock() }
        if let stored = records[key] { return stored }
        return MediaAvailabilityRecord(
            key: key, state: .notAttempted,
            updatedAt: Date(timeIntervalSince1970: 0), lastEvidence: nil
        )
    }

    public func state(for key: MediaMaterialKey) -> MediaAvailabilityState {
        record(for: key).state
    }

    /// 登録済みの件数。
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return records.count
    }

    /// 読み込み開始を記録する。
    public func beginLoading(for key: MediaMaterialKey, at date: Date = Date()) {
        update(key: key, at: date) { record in
            record.state = .loading
        }
    }

    /// 利用可を確認したことを記録する。証拠があれば併せて残す。
    public func markAvailable(
        for key: MediaMaterialKey, evidence: MediaDecodeEvidence? = nil, at date: Date = Date()
    ) {
        update(key: key, at: date) { record in
            record.state = .available
            if let evidence { record.lastEvidence = evidence }
        }
    }

    /// 失敗を記録する。更新時刻は失敗の発生時刻に合わせる。
    public func markFailed(
        for key: MediaMaterialKey, failure: MediaAvailabilityFailure,
        evidence: MediaDecodeEvidence? = nil
    ) {
        update(key: key, at: failure.occurredAt) { record in
            record.state = .failed(failure)
            if let evidence { record.lastEvidence = evidence }
        }
    }

    /// 状態を変えずに証拠だけを差し替える（途中経過の材料）。
    public func recordEvidence(
        _ evidence: MediaDecodeEvidence, for key: MediaMaterialKey, at date: Date = Date()
    ) {
        update(key: key, at: date) { record in
            record.lastEvidence = evidence
        }
    }

    /// 未試行へ戻す。素材の差し替え（同一パスの外部差し替えを含む）
    /// や再試行の起点で使う。
    public func reset(for key: MediaMaterialKey, at date: Date = Date()) {
        update(key: key, at: date) { record in
            record.state = .notAttempted
            record.lastEvidence = nil
        }
    }

    /// 記録を消す。
    public func remove(for key: MediaMaterialKey) {
        lock.lock()
        defer { lock.unlock() }
        records.removeValue(forKey: key)
    }

    /// 全記録を消す（プロジェクトの差し替え時）。
    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        records.removeAll()
    }

    /// 登録済みの全記録（パス・識別の順で安定ソート）。
    public func allRecords() -> [MediaAvailabilityRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records.values.sorted {
            ($0.key.filePath, $0.key.itemIdentifier ?? "")
                < ($1.key.filePath, $1.key.itemIdentifier ?? "")
        }
    }

    private func update(
        key: MediaMaterialKey, at date: Date,
        _ mutate: (inout MediaAvailabilityRecord) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        var record = records[key] ?? MediaAvailabilityRecord(
            key: key, state: .notAttempted,
            updatedAt: Date(timeIntervalSince1970: 0), lastEvidence: nil
        )
        mutate(&record)
        record.updatedAt = date
        records[key] = record
    }
}
