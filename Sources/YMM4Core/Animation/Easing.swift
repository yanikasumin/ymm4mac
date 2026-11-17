import Foundation

/// イージングの適用方向。本家 `EasingMode` に対応する。
public enum EasingMode: Sendable {
    case `in`
    case out
    case inOut
    case outIn
}

/// イージングの科。本家 `Easing` クラスの各静的インスタンスに対応する。
///
/// 各科は「In の素関数 f(t)」だけを持ち、Out / InOut / OutIn は全科共通の
/// 合成規則で作られる。素関数には端点ラッパーが適用され、t == 0 では 0、
/// t == 1 では 1 が強制される（例: Expo の素関数は t == 0 で 2^-10 だが、
/// ラッパーにより 0 になる）。数式の正本は解析側 `ANIMATION-FORMULAS.md` §2。
public enum EasingFamily: Sendable {
    case linear
    case sine
    case quad
    case cubic
    case quart
    case quint
    case expo
    case circ
    case back
    case elastic
    case bounce
    case jump

    /// 端点ラッパーを適用した In の素関数。
    public func inValue(_ t: Double) -> Double {
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        return rawValue(t)
    }

    /// ラッパー適用前の素関数 f_raw(t)。
    private func rawValue(_ t: Double) -> Double {
        switch self {
        case .linear:
            return t
        case .sine:
            return 1 - cos(.pi / 2 * t)
        case .quad:
            return pow(t, 2)
        case .cubic:
            return pow(t, 3)
        case .quart:
            return pow(t, 4)
        case .quint:
            return pow(t, 5)
        case .expo:
            return pow(2, -(1 - t) * 10)
        case .circ:
            return 1 - sqrt(max(0, 1 - pow(t, 2)))
        case .back:
            return pow(t, 2) * (2.70158 * t - 1.70158)
        case .elastic:
            // 本家は三角関数ではなく多項式近似を使う
            return 56 * pow(t, 5) - 105 * pow(t, 4) + 60 * pow(t, 3) - 10 * pow(t, 2)
        case .bounce:
            return Self.bounceRaw(t)
        case .jump:
            return t < 1 ? 0 : 1
        }
    }

    /// Bounce の素関数。本家はループで区間を確定してから閉形式を評価する。
    ///
    /// t が負の範囲では本家は区間確定が進み続ける（t < -1/11 では終了しない）
    /// ため、安全のため反復回数に上限を設ける。通常の率（0...1）では
    /// k = 0 までに必ず確定する。
    private static func bounceRaw(_ t: Double) -> Double {
        var k = 4
        var n = 0
        while true {
            k -= 1
            // 本家は (int)Math.Pow(2, k) で求める（k が負では 0 になる）
            n = Int(pow(2, Double(k)))
            if t >= Double(n - 1) / 11 { break }
            if k <= -64 { break }
        }
        return 1 / pow(4, Double(3 - k)) - 7.5625 * pow(Double(3 * n - 2) / 22 - t, 2)
    }

    /// モード合成を適用した値。本家 `Easing.In / Out / InOut / OutIn`。
    public func value(mode: EasingMode, rate: Double) -> Double {
        switch mode {
        case .in:
            return inValue(rate)
        case .out:
            return 1 - inValue(1 - rate)
        case .inOut:
            // Jump の InOut だけが特例（本家 Easing.InOut）
            if self == .jump {
                return rate < 0.5 ? 0 : 1
            }
            return rate < 0.5
                ? inValue(2 * rate) / 2
                : 1 - inValue(2 - 2 * rate) / 2
        case .outIn:
            return rate < 0.5
                ? 0.5 - inValue(1 - 2 * rate) / 2
                : 0.5 + inValue(2 * rate - 1) / 2
        }
    }

    /// 本家 `Easing.GetValue(EasingType, EasingMode, rate)`。
    public static func getValue(family: EasingFamily, mode: EasingMode, rate: Double) -> Double {
        family.value(mode: mode, rate: rate)
    }
}
