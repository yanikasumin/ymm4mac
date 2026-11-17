import Foundation

/// アニメーションの補間・イージング種別。
///
/// 数値は本家 `AnimationType` 列挙の値そのもの（.ymmp 互換のため変更禁止）。
/// イージング系は科ごとに 100 刻みの帯を持ち、末尾 1=In、2=Out、3=InOut、
/// 4=OutIn、5〜8 は同順の _Int 版。
public enum AnimationType: Int, Sendable {
    // 基本型
    case none = 0               // なし
    case linear = 1             // 直線移動
    case instant = 3            // 瞬間移動
    case movementAmount = 5     // 移動量指定
    case random = 6             // ランダム移動
    case repetitive = 8         // 反復移動
    case interpolation = 15     // 補間移動
    case accelerationDeceleration = 103 // 加減速移動

    // Quad
    case quadIn = 10001
    case quadOut = 10002
    case quadInOut = 10003
    case quadOutIn = 10004
    case quadInInt = 10005
    case quadOutInt = 10006
    case quadInOutInt = 10007
    case quadOutInInt = 10008

    // Cubic
    case cubicIn = 10101
    case cubicOut = 10102
    case cubicInOut = 10103
    case cubicOutIn = 10104
    case cubicInInt = 10105
    case cubicOutInt = 10106
    case cubicInOutInt = 10107
    case cubicOutInInt = 10108

    // Quart
    case quartIn = 10201
    case quartOut = 10202
    case quartInOut = 10203
    case quartOutIn = 10204
    case quartInInt = 10205
    case quartOutInt = 10206
    case quartInOutInt = 10207
    case quartOutInInt = 10208

    // Quint
    case quintIn = 10301
    case quintOut = 10302
    case quintInOut = 10303
    case quintOutIn = 10304
    case quintInInt = 10305
    case quintOutInt = 10306
    case quintInOutInt = 10307
    case quintOutInInt = 10308

    // Sine
    case sineIn = 10401
    case sineOut = 10402
    case sineInOut = 10403
    case sineOutIn = 10404
    case sineInInt = 10405
    case sineOutInt = 10406
    case sineInOutInt = 10407
    case sineOutInInt = 10408

    // Circ
    case circIn = 10501
    case circOut = 10502
    case circInOut = 10503
    case circOutIn = 10504
    case circInInt = 10505
    case circOutInt = 10506
    case circInOutInt = 10507
    case circOutInInt = 10508

    // Expo
    case expoIn = 10601
    case expoOut = 10602
    case expoInOut = 10603
    case expoOutIn = 10604
    case expoInInt = 10605
    case expoOutInt = 10606
    case expoInOutInt = 10607
    case expoOutInInt = 10608

    // Back
    case backIn = 10701
    case backOut = 10702
    case backInOut = 10703
    case backOutIn = 10704
    case backInInt = 10705
    case backOutInt = 10706
    case backInOutInt = 10707
    case backOutInInt = 10708

    // Elastic
    case elasticIn = 10801
    case elasticOut = 10802
    case elasticInOut = 10803
    case elasticOutIn = 10804
    case elasticInInt = 10805
    case elasticOutInt = 10806
    case elasticInOutInt = 10807
    case elasticOutInInt = 10808

    // Bounce
    case bounceIn = 10901
    case bounceOut = 10902
    case bounceInOut = 10903
    case bounceOutIn = 10904
    case bounceInInt = 10905
    case bounceOutInt = 10906
    case bounceInOutInt = 10907
    case bounceOutInInt = 10908

    // ベジェ
    case linearBezier = 100_000        // Linear_Bezier
    case interpolationBezier = 100_001 // Interpolation_Bezier
}

// MARK: - 分類規則（本家 AnimationTypeEx）

extension AnimationType {
    /// キーフレーム対応か。
    ///
    /// なし・移動量指定・反復移動・ランダム移動を除く全てが対応する。
    /// キーフレームの追加・削除に連動して `Animation.values` が増減するのは
    /// この判定が真の型だけである（訂正済み仕様）。
    public var isKeyFrameSupported: Bool {
        switch self {
        case .none, .movementAmount, .random, .repetitive:
            return false
        default:
            return true
        }
    }

    /// イージング系か（本家の内部分類: 値が 10000 より大きい）。
    public var isEasing: Bool {
        rawValue > 10_000
    }

    /// 全体率へイージングを適用してから補間するイージング系か（値 % 10 > 4）。
    public var isInterpolationEasing: Bool {
        isEasing && rawValue % 10 > 4
    }

    /// スプライン補間系か（補間移動と加減速移動のみ）。
    public var isInterpolation: Bool {
        self == .interpolation || self == .accelerationDeceleration
    }

    /// イージング系の場合の（科, モード）。それ以外は nil。
    ///
    /// 科は100刻みの帯、モードは末尾（1・5=In、2・6=Out、3・7=InOut、
    /// 4・8=OutIn）で決まる。本家の `GetEasingRate` では _Int 版と
    /// 非 _Int 版が同一の case にまとめられており、返す関数は完全に
    /// 同じである。両者の違いは評価経路だけにある（`Animation` 参照）。
    public var easingFamilyAndMode: (family: EasingFamily, mode: EasingMode)? {
        guard rawValue > 10_000, rawValue < 100_000 else { return nil }
        let family: EasingFamily
        switch rawValue / 100 {
        case 100: family = .quad
        case 101: family = .cubic
        case 102: family = .quart
        case 103: family = .quint
        case 104: family = .sine
        case 105: family = .circ
        case 106: family = .expo
        case 107: family = .back
        case 108: family = .elastic
        case 109: family = .bounce
        default: return nil
        }
        let mode: EasingMode
        switch rawValue % 10 {
        case 1, 5: mode = .in
        case 2, 6: mode = .out
        case 3, 7: mode = .inOut
        case 4, 8: mode = .outIn
        default: return nil
        }
        return (family, mode)
    }
}
