import Foundation

/// キー列から決定的に乱数を生成する。本家 `StatelessRandom` に対応する。
///
/// 状態を持たず、同じキー列からは常に同じ値が得られる。生成方式は
/// 初期状態へのキー混合（Mix 関数の反復）であり、数式の正本は解析側
/// `ANIMATION-FORMULAS.md` §4.1。
///
/// - Note: 本家ではキーに `Animation.GetHashCode()`（オブジェクトの
///   ハッシュ値）が含まれる。その具体値は .NET ランタイムの実装依存であり、
///   本家と同一の乱数列を再現するための対応付けは未確定である。
///   ここで再現しているのは生成方式そのものだけである。
public enum StatelessRandom {
    private static let initialState: UInt64 = 11_400_714_819_323_198_485 // 0x9E3779B97F4A7C15

    /// キー列から [0, 1) の Double を生成する。本家 `GetDouble`。
    public static func getDouble(keys: [Int64]) -> Double {
        Double(hash(keys) >> 11) * 1.1102230246251565e-16 // 2^-53
    }

    /// キー列から [0, 1) の Float を生成する。本家 `GetFloat`。
    public static func getFloat(keys: [Int64]) -> Float {
        Float(hash(keys) >> 40) * Float(5.9604645e-08) // 2^-24
    }

    private static func hash(_ keys: [Int64]) -> UInt64 {
        var state = initialState
        for key in keys {
            // long は ulong へビット再解釈して混ぜる
            state = mix(state ^ UInt64(bitPattern: key))
        }
        return state
    }

    /// 全ての演算は mod 2^64 で行う。
    private static func mix(_ input: UInt64) -> UInt64 {
        var x = input
        x ^= x >> 27
        x &*= 4_357_703_544_722_667_091
        x ^= x >> 33
        x &*= 2_047_365_380_309_298_741
        x ^= x >> 27
        return x
    }
}
