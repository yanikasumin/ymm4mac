import Foundation

/// アイテム単位で共有されるキーフレーム位置の集合。
///
/// 本家では `KeyFrames` をアイテムが1つ所有し、そのアイテムの全 `Animation` が
/// 同じものを共有する。プロパティごとに別のキーフレーム位置を持つことはできない。
/// 位置はアイテム内相対フレームで、昇順に保たれる。
public struct KeyFrames: Equatable, Sendable {
    /// キーフレーム位置（アイテム内相対フレーム、昇順、重複なし）。
    public private(set) var frames: [Int]

    public init(frames: [Int] = []) {
        var unique: [Int] = []
        for frame in frames.sorted() where unique.last != frame {
            unique.append(frame)
        }
        self.frames = unique
    }

    /// 指定位置のキーフレームのインデックス。無ければ nil。
    public func index(of frame: Int) -> Int? {
        frames.firstIndex(of: frame)
    }

    public func contains(_ frame: Int) -> Bool {
        frames.contains(frame)
    }

    /// キーフレームを追加し、挿入位置のインデックスを返す。既にある場合は nil。
    @discardableResult
    public mutating func insert(_ frame: Int) -> Int? {
        guard !frames.contains(frame) else { return nil }
        let index = frames.firstIndex(where: { $0 > frame }) ?? frames.count
        frames.insert(frame, at: index)
        return index
    }

    /// キーフレームを削除し、削除前のインデックスを返す。無ければ nil。
    @discardableResult
    public mutating func remove(_ frame: Int) -> Int? {
        guard let index = frames.firstIndex(of: frame) else { return nil }
        frames.remove(at: index)
        return index
    }

    /// キーフレームを等間隔位置へ寄せる。
    ///
    /// 本家 `Distribute(length)` の規則: i 番目（1始まり）の位置は
    /// `i * length / (count + 1)`（整数演算）。
    ///
    /// - Returns: 位置が実際に変わったら true（既に等間隔な場合と
    ///   空の場合は false。無変更の操作を編集として扱わないための
    ///   判定。FE-R33-131-02）。
    @discardableResult
    public mutating func distribute(length: Int) -> Bool {
        let count = frames.count
        guard count > 0 else { return false }
        let before = frames
        for i in frames.indices {
            frames[i] = (i + 1) * length / (count + 1)
        }
        return frames != before
    }

    // MARK: - 分割用の一括削除（本家 RemovesLeft / RemovesRight）

    /// `frame` 以下のキーフレームを取り除き、残りを `frame` だけ前へ
    /// ずらした集合。本家 `RemovesLeft(frame)` の結果。
    public func removingLeft(_ frame: Int) -> KeyFrames {
        KeyFrames(frames: frames.filter { frame < $0 }.map { $0 - frame })
    }

    /// `frame` 以上のキーフレームを取り除いた集合。
    /// 本家 `RemovesRight(frame)` の結果。
    public func removingRight(_ frame: Int) -> KeyFrames {
        KeyFrames(frames: frames.filter { $0 < frame })
    }

    /// `RemovesLeft(frame)` で取り除かれる個数（`frame` 以下の個数）。
    /// 本家が変更イベントで渡すインデックスに一致する。
    public func removedCountByRemovingLeft(_ frame: Int) -> Int {
        frames.count - removingLeft(frame).frames.count
    }

    /// `RemovesRight(frame)` で取り除かれる個数（`frame` 以上の個数）。
    public func removedCountByRemovingRight(_ frame: Int) -> Int {
        frames.count - removingRight(frame).frames.count
    }
}
