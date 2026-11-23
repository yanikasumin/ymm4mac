import Foundation

/// スライダ表示範囲の計算（FE-R1-042）。
///
/// 本家 `TextBoxSlider.ChangeMinMax` のスケール式と、親
/// `AnimationSliderViewModel` の MinScale 伝播・移動量指定モードの
/// 対称置換を、コントロールから切り離した純粋関数として再現する。
///
/// ここに置くのは「式」だけであり、スケールの状態は保持しない。
/// 現在効いているスケールは表示側がモデル値から毎回導出する派生状態で、
/// モデルへは保存しない（監査 Round 2 の設計判断。FE-SLIDER-CORE で
/// 式の先行配置を見送ったのは、消費するコントロールが無く検証が
/// 対にならなかったためであり、本単位で AnimationRowView が消費する
/// ことと、アプリ層にテストターゲットが無く式の独立検証が Core でしか
/// 行えないことから、式をここへ置く）。
public enum AnimationSliderScale {

    /// 値インデックスごとの範囲一式。
    ///
    /// 通常は仕様の基準範囲と絶対制限をそのまま返す。移動量指定
    /// （`AnimationType.movementAmount`）の第2値（インデックス 1、
    /// 1フレームあたりの移動量）だけは本家の例外
    /// （`AnimationSliderViewModel` の値ビュー構築）に従い、基準範囲と
    /// 絶対制限の双方を ±最大絶対値の対称範囲へ置き換える。
    public static func ranges(
        forValueAt index: Int,
        animationType: AnimationType,
        spec: AnimationSliderSpec,
        absoluteMin: Double, absoluteMax: Double
    ) -> (defaultMin: Double, defaultMax: Double, absoluteMin: Double, absoluteMax: Double) {
        if index == 1, animationType == .movementAmount {
            let defaultRadius = max(abs(spec.defaultMin), abs(spec.defaultMax))
            let absoluteRadius = max(abs(absoluteMin), abs(absoluteMax))
            return (-defaultRadius, defaultRadius, -absoluteRadius, absoluteRadius)
        }
        return (spec.defaultMin, spec.defaultMax, absoluteMin, absoluteMax)
    }

    /// 1つの値に対するスケール（本家 `TextBoxSlider.ChangeMinMax` の
    /// `Scale` の再現）。
    ///
    /// 値が基準範囲を超えた分だけ 2 の冪で拡張する。端点補正も元の式の
    /// とおり: スケールが 1 より大きく、値がちょうど
    /// 基準端点 × (スケール − 1) に一致し、かつその積が絶対制限の端点
    /// そのものなら、スケールを 1 引く（絶対制限で頭打ちになる位置では
    /// 拡張が無駄になるため）。補正後のスケールは 2 の冪とは限らない。
    public static func scale(
        value: Double, defaultMin: Double, defaultMax: Double,
        absoluteMin: Double, absoluteMax: Double
    ) -> Int {
        let minTerm = defaultMin >= 0 ? 0.0 : (value / defaultMin).rounded(.down)
        let maxTerm = defaultMax == 0 ? 0.0 : (value / defaultMax).rounded(.down)
        let m = max(minTerm, maxTerm) + 1
        var scale = 1
        if m > 1 {
            // m は有限なモデル値からは 1 以上の整数になる。指数が
            // 大きくなりすぎる入力（絶対制限自体が極端な値域）は
            // 表示上意味を持たないため 2^30 で頭打ちにする。
            let exponent = min(ceil(log2(m)), 30)
            scale = Int(pow(2.0, exponent))
        }
        if scale > 1 {
            let previous = Double(scale - 1)
            if (defaultMin * previous == value && defaultMin * previous == absoluteMin)
                || (defaultMax * previous == value && defaultMax * previous == absoluteMax) {
                scale -= 1
            }
        }
        return scale
    }

    /// 同一 `Animation` の全有効値で共有するスケール。
    ///
    /// 本家は各値の `TextBoxSlider` が出した `Scale` の最大値を
    /// 全値の `MinScale` へ伝播させ、全員の実効スケールを揃える
    /// （`AdjustedScale = max(MinScale, Scale)` で、MinScale が全員の
    /// 最大値になるため実効値は全員一致する）。ここではその固定点を
    /// 1回で計算する。
    public static func sharedScale(
        values: [Double],
        animationType: AnimationType,
        spec: AnimationSliderSpec,
        absoluteMin: Double, absoluteMax: Double
    ) -> Int {
        var result = 1
        for (index, value) in values.enumerated() {
            let r = ranges(
                forValueAt: index, animationType: animationType, spec: spec,
                absoluteMin: absoluteMin, absoluteMax: absoluteMax)
            result = max(result, scale(
                value: value, defaultMin: r.defaultMin, defaultMax: r.defaultMax,
                absoluteMin: r.absoluteMin, absoluteMax: r.absoluteMax))
        }
        return result
    }

    /// 実効スケールでの表示範囲（本家 `CurrentMin` / `CurrentMax`）。
    ///
    /// 基準範囲をスケール倍し、絶対制限で頭打ちにする。基準端点が
    /// 正の側ではスケール倍で範囲が縮むことはない（元の式は
    /// `min(端点 × スケール, 端点)` / `max(端点 × スケール, 端点)` で
    /// 基準範囲そのものを下限にしている）。
    public static func currentRange(
        defaultMin: Double, defaultMax: Double,
        absoluteMin: Double, absoluteMax: Double,
        adjustedScale: Int
    ) -> (min: Double, max: Double) {
        let s = Double(adjustedScale)
        let currentMin = max(min(defaultMin * s, defaultMin), absoluteMin)
        let currentMax = min(max(defaultMax * s, defaultMax), absoluteMax)
        return (currentMin, currentMax)
    }

    /// `values` のうち `valueIndex` の値を編集するスライダの表示範囲。
    /// スケールは全値で共有したものを、その値自身の範囲一式へ適用する。
    public static func sliderRange(
        values: [Double], valueIndex: Int,
        animationType: AnimationType,
        spec: AnimationSliderSpec,
        absoluteMin: Double, absoluteMax: Double
    ) -> (min: Double, max: Double) {
        let shared = sharedScale(
            values: values, animationType: animationType, spec: spec,
            absoluteMin: absoluteMin, absoluteMax: absoluteMax)
        let r = ranges(
            forValueAt: valueIndex, animationType: animationType, spec: spec,
            absoluteMin: absoluteMin, absoluteMax: absoluteMax)
        return currentRange(
            defaultMin: r.defaultMin, defaultMax: r.defaultMax,
            absoluteMin: r.absoluteMin, absoluteMax: r.absoluteMax,
            adjustedScale: shared)
    }

    /// `Animation` の有効値列。本家 `ActiveValues`
    /// （`Values.Take(GetActiveValueCount())`）と同じ列挙で、現在
    /// 存在する値だけを有効個数まで取り出す。存在しない値を既定値で
    /// 作らない（FE-R13-002）。
    ///
    /// 値列の正規化（個数の切り詰め・補充）は本家では編集終了時の
    /// `EndEditAsync` が担い、移動量指定の第2値は 0 で補われる。
    /// Mac 側の記述子書き込みには編集セッションの境界が無く即時に
    /// 確定するため、その正規化はここでは再現せず、スケール計算の
    /// 列挙だけを本家の意味論へ揃える。存在しない移動量が既定値
    /// として共有スケールへ参加すると、対称範囲の端点になって
    /// 不要なスケール拡張を誘発する。
    public static func activeValues(of animation: Animation) -> [Double] {
        animation.values.prefix(animation.activeValueCount).map(\.value)
    }

    /// `valueIndex` のスライダ／数値入力が表示・編集する値。
    ///
    /// 本家では各スライダが担当する `AnimationValue.Value` を直接
    /// 編集する（`AnimationValueSliderViewModel`）ため、表示値と
    /// 編集対象値は同一であり、再生ヘッド位置での評価値ではない
    /// （FE-R13-001）。値列が `valueIndex` まで実体化していない
    /// 場合は末尾値（無ければ既定値）へ落とす。書き込み側は記述子の
    /// `setAnimationValue` が不足分を実体化する。
    public static func editValue(of animation: Animation, valueIndex: Int) -> Double {
        if animation.values.indices.contains(valueIndex) {
            return animation.values[valueIndex].value
        }
        return animation.values.last?.value ?? animation.defaultValue
    }

    /// `Animation` の値インデックスを編集するスライダの表示範囲。
    public static func sliderRange(
        for animation: Animation, valueIndex: Int, spec: AnimationSliderSpec
    ) -> (min: Double, max: Double) {
        sliderRange(
            values: activeValues(of: animation), valueIndex: valueIndex,
            animationType: animation.animationType, spec: spec,
            absoluteMin: animation.minValue, absoluteMax: animation.maxValue)
    }

    // MARK: - 確定時の値の確定処理（FE-R13-004）

    /// 確定時の値の確定処理（本家 `TextBoxSlider.FixValue` の再現）。
    ///
    /// 丸めの桁数は Delta そのものではなく、本家の式
    /// `clamp((int)(1.0 / Delta / 10.0 + 1.0), 0, 15)` で決まる
    /// （F0 → 1桁、F1 → 2桁、F3以降は上限の15桁）。F2 は式の値が
    /// 浮動小数の帰結で 10.999… となり切り捨てで 10桁になる
    /// （Delta = Pow(0.1, 2) は 0.01 ちょうどではなく
    /// 0.010000000000000002。本家も同じ Pow 経路のため同値になる
    /// はずであり、11桁へ「正して」はいけない）。
    /// 桁が表示書式の小数桁と一致しないのは本家の式そのままの
    /// 帰結であり、表示桁へ寄せてはいけない。その桁で
    /// `MidpointRounding.AwayFromZero` 相当の丸めを行い、その後に
    /// [minimum, maximum] へクランプする（丸め → クランプの順序も
    /// 本家のまま）。
    ///
    /// `minimum` / `maximum` はその値のスライダの Min / Max を渡す:
    /// 通常は `Animation` の定義範囲、移動量指定の第2値では対称置換後の
    /// 絶対制限（`ranges(forValueAt:)` の absoluteMin / absoluteMax）。
    ///
    /// Delta が正でない・非有限の場合は本家に相当する入力が存在しない
    /// （属性の Delta は常に正）ため、丸め桁は上限の 15 として扱う。
    /// 値自体が非有限ならそのまま返す（呼び出し側が確定前に弾く）。
    ///
    /// 丸めは `roundedToDecimalDigits` で格納値そのものを厳密に
    /// 丸める（FE-FIXVALUE-EXACT）。「10 の冪を掛けて丸めて割り戻す」
    /// 方式は、積がちょうど中間値に着地する通常域の値（0.35、
    /// 2.675 等）で .NET と乖離し、割り戻しの誤差で巨大値でも
    /// 1 ulp ずれるため使わない（FE-P3-GUARDS の実測）。
    public static func fixedValue(
        _ value: Double, delta: Double, minimum: Double, maximum: Double
    ) -> Double {
        guard value.isFinite else { return value }
        var digits = 15
        if delta.isFinite, delta > 0 {
            // (int) 変換が溢れないよう、Double のまま先に頭打ちにする。
            let raw = 1.0 / delta / 10.0 + 1.0
            digits = raw >= 15 ? 15 : (raw <= 0 ? 0 : Int(raw))
        }
        let rounded = roundedToDecimalDigits(value, digits: digits)
        return min(max(rounded, minimum), maximum)
    }

    /// 格納された二進値そのものを十進 `digits` 桁へ
    /// `MidpointRounding.AwayFromZero` で丸めた結果に最も近い
    /// double を返す（.NET `Math.Round(value, digits,
    /// MidpointRounding.AwayFromZero)` の意味論の再現）。
    ///
    /// .NET の Math.Round は格納値の厳密な十進展開を丸める:
    /// 0.35 の格納値は中間値 0.35 より僅かに小さいため 1 桁では
    /// 0.3 になる。最短往復文字列（"0.35"）を丸める方式では
    /// 格納値と文字列の大小が逆転する値（2.675 等）で一致しない
    /// ため、文字列は経由しない。
    ///
    /// 計算は全て整数演算で厳密に行う。|value| を
    /// significand × 2^exponent へ分解すると、拡大した値
    /// |value| × 10^digits は significand × 5^digits ×
    /// 2^(exponent + digits) と厳密に書ける（10^d = 2^d × 5^d）。
    /// significand × 5^digits は 2^88 未満で 128bit に収まる。
    /// 剰余と 1/2 の比較で切り上げを決め（同点は 0 から離れる）、
    /// 得た整数を 10^digits で割りながら最も近い double へ戻す
    /// （最終変換の同点は偶数側）。拡大した値が整数になる場合は
    /// 丸め結果が値そのものになり、巨大値の恒等返却
    /// （FE-R25-128-03）もこの経路に内包される。
    ///
    /// 前提: `digits` は 0...15（呼び出し側の桁数導出が保証する）。
    private static func roundedToDecimalDigits(_ value: Double, digits: Int) -> Double {
        if value == 0 { return value }
        let negative = value.sign == .minus
        let bits = value.bitPattern
        let exponentField = Int((bits >> 52) & 0x7FF)
        let fraction = bits & 0xF_FFFF_FFFF_FFFF
        let significand: UInt64
        let exponent: Int
        if exponentField == 0 {
            // 非正規化数: 暗黙の 1 を持たない。
            significand = fraction
            exponent = -1074
        } else {
            significand = fraction | (UInt64(1) << 52)
            exponent = exponentField - 1023 - 52
        }
        var power5: UInt64 = 1
        for _ in 0..<digits { power5 *= 5 }
        // |value| × 10^digits = product × 2^shift（厳密）。
        let product = significand.multipliedFullWidth(by: power5)
        let shift = exponent + digits
        if shift >= 0 {
            // 拡大した値が整数 → 丸めた結果は値そのもの。
            return value
        }
        let k = -shift
        if k >= 89 {
            // product < 2^88 ≤ 2^(k-1) のため拡大した値は 1/2 未満。
            return negative ? -0.0 : 0.0
        }
        // n = floor(product / 2^k)、剰余 = product mod 2^k。
        let nHi: UInt64, nLo: UInt64, rHi: UInt64, rLo: UInt64
        if k < 64 {
            nHi = product.high >> k
            nLo = (product.low >> k) | (product.high << (64 - k))
            rHi = 0
            rLo = product.low & ((UInt64(1) << k) - 1)
        } else if k == 64 {
            nHi = 0
            nLo = product.high
            rHi = 0
            rLo = product.low
        } else {
            nHi = 0
            nLo = product.high >> (k - 64)
            rHi = product.high & ((UInt64(1) << (k - 64)) - 1)
            rLo = product.low
        }
        // 1/2 = 2^(k-1)。剰余が 1/2 以上なら切り上げる（同点は
        // AwayFromZero で 0 から離れる = 絶対値の切り上げ）。
        let halfHi: UInt64 = k - 1 >= 64 ? UInt64(1) << (k - 65) : 0
        let halfLo: UInt64 = k - 1 >= 64 ? 0 : UInt64(1) << (k - 1)
        var n = (hi: nHi, lo: nLo)
        if rHi > halfHi || (rHi == halfHi && rLo >= halfLo) {
            n.lo &+= 1
            if n.lo == 0 { n.hi &+= 1 }
        }
        if n.hi == 0 && n.lo == 0 { return negative ? -0.0 : 0.0 }
        // n / 10^digits に最も近い double へ変換する。結果の
        // 属する 2 の冪の区間（binade）を先に厳密に決め、その
        // 区間の格子上で丸める。区間の境界直下では下の区間の
        // 格子が2倍細かいため、大きさの見積もりだけで格子を
        // 決めると境界の向こう側の点へ丸めてしまう（例:
        // 64 の直下の値を 15 桁で丸めると 64 になる）。
        var power10: UInt64 = 1
        for _ in 0..<digits { power10 *= 10 }
        let bitLengthN = n.hi != 0
            ? 128 - n.hi.leadingZeroBitCount
            : 64 - n.lo.leadingZeroBitCount
        let bitLengthP = 64 - power10.leadingZeroBitCount
        // r = n / power10 は (2^(d-1), 2^(d+1)) に入る。
        // r ≥ 2^d かどうかで、2^e ≤ r < 2^(e+1) となる e が
        // d か d-1 に決まる。
        let d = bitLengthN - bitLengthP
        let reachesPowerOfTwo: Bool
        if d >= 0 {
            // n ≥ power10 × 2^d ⟺ (n >> d) ≥ power10。
            let sHi: UInt64, sLo: UInt64
            if d == 0 {
                sHi = n.hi
                sLo = n.lo
            } else if d < 64 {
                sHi = n.hi >> d
                sLo = (n.lo >> d) | (n.hi << (64 - d))
            } else if d == 64 {
                sHi = 0
                sLo = n.hi
            } else {
                sHi = 0
                sLo = n.hi >> (d - 64)
            }
            reachesPowerOfTwo = sHi > 0 || sLo >= power10
        } else {
            // n ≥ power10 × 2^d ⟺ (n << -d) ≥ power10。
            let s = -d
            let l0 = n.lo << s
            let l1 = (n.hi << s) | (n.lo >> (64 - s))
            let l2 = n.hi >> (64 - s)
            reachesPowerOfTwo = l2 > 0 || l1 > 0 || l0 >= power10
        }
        let binade = reachesPowerOfTwo ? d : d - 1
        // quotient = round(r × 2^(52-binade))（同点は偶数側）。
        // r < 2^52 かつ r ≥ 1e-15 程度のため、シフト量は
        // 1...103 に収まり、被除数は 2^191 未満でリム列に収まる。
        let scaleShift = 52 - binade
        var limbs: [UInt64] = [n.lo, n.hi, 0, 0, 0]
        let limbShift = scaleShift / 64
        let bitShift = scaleShift % 64
        if limbShift > 0 || bitShift > 0 {
            var shifted: [UInt64] = [0, 0, 0, 0, 0]
            for i in 0..<limbs.count {
                let source = i - limbShift
                guard source >= 0 else { continue }
                var limb = limbs[source] << bitShift
                if bitShift > 0, source > 0 {
                    limb |= limbs[source - 1] >> (64 - bitShift)
                }
                shifted[i] = limb
            }
            limbs = shifted
        }
        var quotient: UInt64 = 0
        var remainder: UInt64 = 0
        for limb in limbs.reversed() {
            // remainder < power10 が保たれるため商は 64bit に
            // 収まる。商の実値は 2^53 以下なので上位リムの商は
            // 0 になる。
            let (q, r) = power10.dividingFullWidth((high: remainder, low: limb))
            quotient = (quotient << 64) | q
            remainder = r
        }
        let twiceRemainder = remainder * 2
        if twiceRemainder > power10
            || (twiceRemainder == power10 && quotient % 2 == 1) {
            quotient += 1
        }
        // 結果 = quotient × 2^(binade-52)（quotient は [2^52, 2^53]）。
        // 2^53 へ達した場合は次の区間の 2^52 と同値。
        var resultExponentField = binade + 1023
        if quotient == UInt64(1) << 53 {
            quotient = UInt64(1) << 52
            resultExponentField += 1
        }
        let exponentBits = UInt64(resultExponentField) << 52
        let resultBits = (negative ? UInt64(1) << 63 : 0)
            | exponentBits
            | (quotient - (UInt64(1) << 52))
        return Double(bitPattern: resultBits)
    }
}
