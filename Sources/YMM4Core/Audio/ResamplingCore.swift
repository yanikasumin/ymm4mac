import Foundation

/// 補間カーネル。本家 `IInterpolationAlgorithm`（Commons）に対応する。
/// `taps` は中心から片側に参照するフレーム数、`weight` は距離への重み。
public protocol InterpolationKernel {
    var taps: Int { get }
    func weight(distance: Double) -> Double
}

/// 線形補間カーネル。本家 Commons `Linear` に対応する。
public struct LinearInterpolationKernel: InterpolationKernel {
    public init() {}
    public var taps: Int { 1 }
    public func weight(distance: Double) -> Double {
        distance <= 1 ? 1 - distance : 0
    }
}

/// Cubic 補間カーネル。本家 Commons `Cubic` に対応する。
/// 重み関数はモデル層の `Cubic`（A = -0.5）をそのまま使う。
public struct CubicInterpolationKernel: InterpolationKernel {
    private let cubic = Cubic()
    public init() {}
    public var taps: Int { 2 }
    public func weight(distance: Double) -> Double {
        cubic.weight(distance: distance)
    }
}

/// 帯域制限補間（窓関数 sinc）によるサンプル生成コア。
///
/// リサンプラの「契約」（長さ・シーク・位置の変換式と素通し規則）は
/// 本家 MFT ラッパーの実測式で固定し、差し替えるのはこの生成コアだけ
/// とする設計（AUDIO-FIDELITY-PLAN §1.1 の候補 (a)）。位置写像は
/// 出力フレーム j → 素材位置 j × (Input.Hz / Hz) のままで、カーネルは
/// 中心遅延 0 の対称 FIR として構成するため、遅延は生じない。
///
/// カーネルの形（正式仕様、2026-11-17 決定。AUDIO-FIDELITY-PLAN
/// §3.1.3）:
/// - 倍率 scale = max(1, Input.Hz / Hz)。ダウンスンプル時は出力
///   ナイキストに合わせてカーネルを scale 倍に広げ、折り返しを防ぐ
///   （アップサンプル時は scale = 1 で入力ナイキストが帯域制限）。
/// - 重み h(t) = sinc(t / scale) × Kaiser 窓(t / 支持幅) / scale。
///   支持幅は片側 `halfWidthCycles` = 96 零点（scale = 1 のとき
///   片側 96 フレーム、計 193 タップ）、Kaiser 窓の β は
///   `kaiserBeta` = 8.96（設計減衰 A ≈ 90 dB に対応）。
/// - 選定経緯: 当初は Blackman 窓・片側 48 零点で「帯域端でも
///   -80dB 級」と見ていたが、QA24-01 の周波数掃引（25Hz 格子）で
///   阻止帯域 [23.2k–24kHz] の最悪値は -60.27 dB（帯域端）と判明
///   し、その記述は撤回した。同じ測定系での候補比較（§3.1.2）の
///   結果、正式合格値（阻止帯域の最悪値 -80 dB 以下、通過帯域
///   20kHz まで ±0.1 dB 以内）を余裕を持って満たしたのは
///   Kaiser 96 のみ（実測: 最悪値 -94.54 dB、平坦さ 0.0001 dB
///   未満）。制限要因は窓長ではなく窓関数のサイドローブ構造
///   だった。
/// - コストは素朴な実装のままで Blackman 48 の約 3.1 倍
///   （Release、§3.1.2）。係数テーブル化／ポリフェーズ化は
///   将来作業として計画書に残す。
/// - 出力は重みの総和で割って正規化する。定数信号が厳密に保存され、
///   DC ゲインが 1 になることを保証するため（窓掛けで落ちる
///   ゲインを補う）。本家の MFT と波形が等しいことは引き続き
///   **未検証**で、品質は自前の周波数応答実測で担保する。
struct BandLimitedResamplingCore {
    /// カーネル片側の零点数（scale = 1 のときのタップ半幅）。
    /// 正式仕様として固定（2026-11-17、§3.1.3）。
    static let halfWidthCycles = 96.0

    /// Kaiser 窓の β。設計減衰 A ≈ 90 dB（β = 0.1102 × (A − 8.7)
    /// ≈ 8.96）に対応する。正式仕様として固定（§3.1.3）。
    static let kaiserBeta = 8.96

    /// 窓の正規化分母 I0(β)。β が固定のため事前に1回だけ評価する。
    static let kaiserDenominator = besselI0(kaiserBeta)

    /// 素材位置 `sourcePosition`（入力フレーム単位）における補間値。
    /// `ratio` は Input.Hz / Hz（入力フレーム / 出力フレーム）。
    static func sample(
        window: InputFrameWindow, at sourcePosition: Double, ratio: Double
    ) -> (left: Float, right: Float) {
        let scale = max(1.0, ratio)
        let support = halfWidthCycles * scale
        let firstIndex = Int((sourcePosition - support).rounded(.up))
        let lastIndex = Int((sourcePosition + support).rounded(.down))
        var numeratorLeft = 0.0
        var numeratorRight = 0.0
        var denominator = 0.0
        for index in firstIndex...lastIndex {
            let distance = sourcePosition - Double(index)
            let weight = kernelWeight(distance: distance, scale: scale, support: support)
            if weight == 0 { continue }
            let frame = window.frame(at: index)
            numeratorLeft += Double(frame.left) * weight
            numeratorRight += Double(frame.right) * weight
            denominator += weight
        }
        guard denominator != 0 else { return (0, 0) }
        return (
            Float(numeratorLeft / denominator),
            Float(numeratorRight / denominator)
        )
    }

    /// 窓関数 sinc の重み。|distance| >= support では 0。
    static func kernelWeight(distance: Double, scale: Double, support: Double) -> Double {
        let magnitude = abs(distance)
        if magnitude >= support { return 0 }
        let scaled = distance / scale
        let sincValue = scaled == 0 ? 1.0 : sin(.pi * scaled) / (.pi * scaled)
        // Kaiser 窓。phase は -1..<1 で、支持端では I0(0)/I0(β)
        // （小さいが 0 ではない。|distance| >= support の扱いは
        // 冒頭の早期 return が担う）、中心で 1。
        let phase = distance / support
        let windowValue =
            besselI0(kaiserBeta * (1 - phase * phase).squareRoot()) / kaiserDenominator
        return sincValue * windowValue / scale
    }

    /// 第1種変形ベッセル関数 I0 の級数展開。項が和に対して
    /// 1e-15 を下回った時点で打ち切る（|x| <= 8.96 の範囲では
    /// 数十項で収束する）。
    static func besselI0(_ x: Double) -> Double {
        var sum = 1.0
        var term = 1.0
        let y = x * x / 4
        var k = 1.0
        while k < 200 {
            term *= y / (k * k)
            sum += term
            if term < sum * 1e-15 { break }
            k += 1
        }
        return sum
    }
}
