import Foundation

/// 編集イベントが属するプロジェクトの世代を示すスタンプ。
///
/// プロジェクトの差し替え（新規作成・読み込み）ごとに所有者
/// （`ProjectEditAttribution`）が世代を進め、それ以前に発行された
/// スタンプは陳腐化する。アプリ層の編集コールバックは、ビュー生成時に
/// 捕捉したスタンプを持ち、効果を及ぼす直前に現行世代と照合することで、
/// プロジェクト切り替え後に遅れて配送された旧プロジェクト向けの
/// 編集イベントを、モデル変更と Undo 記録の前に棄却する（FE-R30-130-02）。
///
/// スタンプは世代番号だけを持ち、プロジェクトの実体への参照は持たない。
/// 発行は所有者だけが行う（イニシャライザはモジュール内）。
public struct EditProjectStamp: Equatable, Sendable {
    /// 世代番号。所有者が発行した順に単調増加する。
    public let generation: UInt64

    init(generation: UInt64) {
        self.generation = generation
    }
}

/// プロジェクト世代の所有者。プロジェクトごとに1つ、プロジェクトの
/// 差し替えを行う側（アプリ層の `WorkspaceState`）が保持する。
///
/// 契約:
/// - `currentStamp()` はその時点で現行のプロジェクト向けに発行される
///   スタンプを返す。同じ世代では常に同じスタンプが返る。
/// - `advance()` はプロジェクトの差し替え時に呼び、世代を進める。
///   進める前のスタンプは以後 `isCurrent(_:)` が偽になる（陳腐化）。
/// - `isCurrent(_:)` は提示されたスタンプが現行世代のものかを返す。
///
/// スレッド安全性は持たない。`EditRecorder` と同じ前提（UI の編集は
/// メインスレッド／メインアクターで直列化される）で使うこと。
public final class ProjectEditAttribution {
    private var generation: UInt64 = 0

    public init() {}

    /// 現行世代のスタンプ。編集コールバックの捕捉側が保持する。
    public func currentStamp() -> EditProjectStamp {
        EditProjectStamp(generation: generation)
    }

    /// 提示されたスタンプが現行世代のものか。
    public func isCurrent(_ stamp: EditProjectStamp) -> Bool {
        stamp.generation == generation
    }

    /// 世代を進める（プロジェクトの差し替え時に1回呼ぶ）。
    /// 進める前に発行されたスタンプは全て陳腐化する。
    public func advance() {
        generation &+= 1
    }
}
