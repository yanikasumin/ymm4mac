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
}
