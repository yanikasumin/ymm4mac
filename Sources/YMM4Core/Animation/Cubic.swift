import Foundation

/// スプライン補間の重みカーネル。本家 `Cubic`（`IInterpolationAlgorithm` 実装）に対応する。
///
/// A = -0.5 のとき Keys / Catmull-Rom 系のカーネルと一致する。本家では
/// 利用箇所すべてが既定値のまま使う。数式の正本は解析側
/// `ANIMATION-FORMULAS.md` §1。
public struct Cubic: Equatable, Sendable {
    /// カーネルの形状パラメータ。本家 `A`。
    public var a: Double

    public init(a: Double = -0.5) {
        self.a = a
    }

    /// 重みを参照する近傍の点数（片側）。本家 `Taps`。
    public var taps: Int { 2 }

    /// 距離に対する重み。
    ///
    /// 本家は距離の絶対値を取らない。符号付きの値が渡ればそのまま3次式に
    /// 入る（呼び出し側で絶対値化するかどうかは経路による）。NaN の場合は
    /// 本家の分岐構造により 0 になる。
    public func weight(distance: Double) -> Double {
        if distance < 1 {
            return (a + 2) * pow(distance, 3) - (a + 3) * pow(distance, 2) + 1
        }
        if distance < 2 {
            return a * pow(distance, 3) - 5 * a * pow(distance, 2) + 8 * a * distance - 4 * a
        }
        return 0
    }
}
