import Foundation

/// 映像エフェクト定義のプロパティメタデータ（GPUColor 系）。
///
/// `EffectPropertyMetadata.descriptors(for:)` の具象定義別ビルダー。
/// 表示名・グループは本家の `Display` 属性（`Texts` リソース）、
/// 数値範囲は本家の `Range` / スライダ属性に根拠を持つ。
/// 根拠が取れない表示名はプロパティ名そのままにする。
public extension EffectPropertyMetadata {

    /// BorderBlurEffectDefinition の固有パラメータ。
    static func borderBlurEffectDescriptors(_ d: BorderBlurEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Blur", displayName: "ぼかし度", group: "境界ぼかし",
                get: { d.blur }, set: { d.blur = $0 }
            )
        ]
    }

    /// ChromaticAberrationEffectDefinition の固有パラメータ。
    static func chromaticAberrationEffectDescriptors(_ d: ChromaticAberrationEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Strength", displayName: "強さ", group: "色収差",
                get: { d.strength }, set: { d.strength = $0 }
            )
        ]
    }

    /// DirectionalBlurEffectDefinition の固有パラメータ。
    static func directionalBlurEffectDescriptors(_ d: DirectionalBlurEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "StandardDeviation", displayName: "ぼかし度", group: "方向ブラー",
                get: { d.standardDeviation }, set: { d.standardDeviation = $0 }
            ),
            .animation(
                id: "Angle", displayName: "角度", group: "方向ブラー",
                get: { d.angle }, set: { d.angle = $0 }
            ),
            .boolean(
                id: "IsHardBorderMode", displayName: "サイズを固定", group: "方向ブラー",
                get: { d.isHardBorderMode }, set: { d.isHardBorderMode = $0 }
            )
        ]
    }

    /// ExposureEffectDefinition の固有パラメータ。
    static func exposureEffectDescriptors(_ d: ExposureEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Value", displayName: "露光", group: "露光調整",
                get: { d.value }, set: { d.value = $0 }
            )
        ]
    }

    /// GammaCorrectionEffectDefinition の固有パラメータ。
    static func gammaCorrectionEffectDescriptors(_ d: GammaCorrectionEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Gamma", displayName: "全体", group: "ガンマ値",
                get: { d.gamma }, set: { d.gamma = $0 }
            ),
            .animation(
                id: "Red", displayName: "赤", group: "ガンマ値",
                get: { d.red }, set: { d.red = $0 }
            ),
            .animation(
                id: "Green", displayName: "緑", group: "ガンマ値",
                get: { d.green }, set: { d.green = $0 }
            ),
            .animation(
                id: "Blue", displayName: "青", group: "ガンマ値",
                get: { d.blue }, set: { d.blue = $0 }
            )
        ]
    }

    /// GaussianBlurEffectDefinition の固有パラメータ。
    static func gaussianBlurEffectDescriptors(_ d: GaussianBlurEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Blur", displayName: "ぼかし度", group: "ぼかし",
                get: { d.blur }, set: { d.blur = $0 }
            ),
            .boolean(
                id: "IsHardBorderMode", displayName: "サイズを固定", group: "ぼかし",
                get: { d.isHardBorderMode }, set: { d.isHardBorderMode = $0 }
            )
        ]
    }

    /// HalfToneBorderBlurEffectDefinition の固有パラメータ。
    static func halfToneBorderBlurEffectDescriptors(_ d: HalfToneBorderBlurEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Blur", displayName: "ぼかし度", group: "網点境界ぼかし",
                get: { d.blur }, set: { d.blur = $0 }
            ),
            .enumeration(
                id: "Layout", displayName: "配置", group: "網点境界ぼかし",
                options: halfToneLayoutOptions,
                get: { d.layout }, set: { d.layout = $0 }
            ),
            .animation(
                id: "Distance", displayName: "距離", group: "網点境界ぼかし",
                get: { d.distance }, set: { d.distance = $0 }
            ),
            .animation(
                id: "Size", displayName: "サイズ", group: "網点境界ぼかし",
                get: { d.size }, set: { d.size = $0 }
            ),
            .animation(
                id: "Strength", displayName: "色の強さ", group: "網点境界ぼかし",
                get: { d.strength }, set: { d.strength = $0 }
            )
        ]
    }

    /// HalfToneEffectDefinition の固有パラメータ。
    static func halfToneEffectDescriptors(_ d: HalfToneEffectDefinition) -> [PropertyDescriptor] {
        [
            .enumeration(
                id: "Layout", displayName: "配置", group: "網点",
                options: halfToneLayoutOptions,
                get: { d.layout }, set: { d.layout = $0 }
            ),
            .animation(
                id: "Distance", displayName: "距離", group: "網点",
                get: { d.distance }, set: { d.distance = $0 }
            ),
            .animation(
                id: "Size", displayName: "サイズ", group: "網点",
                get: { d.size }, set: { d.size = $0 }
            ),
            .color(
                id: "Color", displayName: "色", group: "網点",
                get: { d.color }, set: { d.color = $0 }
            ),
            .animation(
                id: "Strength", displayName: "色の強さ", group: "網点",
                get: { d.strength }, set: { d.strength = $0 }
            )
        ]
    }

    /// HalfToneOutlineEffectDefinition の固有パラメータ。
    static func halfToneOutlineEffectDescriptors(_ d: HalfToneOutlineEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "StrokeThickness", displayName: "太さ", group: "縁取り",
                get: { d.strokeThickness }, set: { d.strokeThickness = $0 }
            ),
            .animation(
                id: "Opacity", displayName: "不透明度", group: "縁取り",
                get: { d.opacity }, set: { d.opacity = $0 }
            ),
            .animation(
                id: "Blur", displayName: "ぼかす", group: "縁取り",
                get: { d.blur }, set: { d.blur = $0 }
            ),
            .boolean(
                id: "IsOutlineOnly", displayName: "縁のみ", group: "縁取り",
                get: { d.isOutlineOnly }, set: { d.isOutlineOnly = $0 }
            ),
            .enumeration(
                id: "Layout", displayName: "配置", group: "網点",
                options: halfToneLayoutOptions,
                get: { d.layout }, set: { d.layout = $0 }
            ),
            .animation(
                id: "Distance", displayName: "距離", group: "網点",
                get: { d.distance }, set: { d.distance = $0 }
            ),
            .animation(
                id: "Size", displayName: "サイズ", group: "網点",
                get: { d.size }, set: { d.size = $0 }
            ),
            .color(
                id: "Color", displayName: "色", group: "網点",
                get: { d.color }, set: { d.color = $0 }
            ),
            .animation(
                id: "Strength", displayName: "色の強さ", group: "網点",
                get: { d.strength }, set: { d.strength = $0 }
            )
        ]
    }

    /// HalfToneShadowEffectDefinition の固有パラメータ。
    static func halfToneShadowEffectDescriptors(_ d: HalfToneShadowEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "X", group: "影",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "影",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Opacity", displayName: "不透明度", group: "影",
                get: { d.opacity }, set: { d.opacity = $0 }
            ),
            .animation(
                id: "Angle", displayName: "回転角", group: "影",
                get: { d.angle }, set: { d.angle = $0 }
            ),
            .animation(
                id: "Blur", displayName: "ぼかし", group: "影",
                get: { d.blur }, set: { d.blur = $0 }
            ),
            .enumeration(
                id: "Layout", displayName: "配置", group: "網点",
                options: halfToneLayoutOptions,
                get: { d.layout }, set: { d.layout = $0 }
            ),
            .animation(
                id: "Distance", displayName: "距離", group: "網点",
                get: { d.distance }, set: { d.distance = $0 }
            ),
            .animation(
                id: "Size", displayName: "サイズ", group: "網点",
                get: { d.size }, set: { d.size = $0 }
            ),
            .color(
                id: "Color", displayName: "色", group: "網点",
                get: { d.color }, set: { d.color = $0 }
            ),
            .animation(
                id: "Strength", displayName: "色の強さ", group: "網点",
                get: { d.strength }, set: { d.strength = $0 }
            ),
            .boolean(
                id: "KeepBrightness", displayName: "輝度を保持", group: "網点",
                get: { d.keepBrightness }, set: { d.keepBrightness = $0 }
            ),
            .boolean(
                id: "IsRotateAtCenter", displayName: "中心で回転", group: "影",
                get: { d.isRotateAtCenter }, set: { d.isRotateAtCenter = $0 }
            )
        ]
    }

    /// HightlightsAndShadowsEffectDefinition の固有パラメータ。
    static func hightlightsAndShadowsEffectDescriptors(_ d: HightlightsAndShadowsEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Highlights", displayName: "明るい場所", group: "明るさ",
                get: { d.highlights }, set: { d.highlights = $0 }
            ),
            .animation(
                id: "Shadows", displayName: "暗い場所", group: "明るさ",
                get: { d.shadows }, set: { d.shadows = $0 }
            )
        ]
    }

    /// InnerHalfToneShadowEffectDefinition の固有パラメータ。
    static func innerHalfToneShadowEffectDescriptors(_ d: InnerHalfToneShadowEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "X", group: "影",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "影",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Opacity", displayName: "不透明度", group: "影",
                get: { d.opacity }, set: { d.opacity = $0 }
            ),
            .animation(
                id: "Blur", displayName: "ぼかし", group: "影",
                get: { d.blur }, set: { d.blur = $0 }
            ),
            .enumeration(
                id: "BlendMode", displayName: "合成モード", group: "影",
                options: blendOptions,
                get: { d.blendMode }, set: { d.blendMode = $0 }
            ),
            .enumeration(
                id: "Layout", displayName: "配置", group: "網点",
                options: halfToneLayoutOptions,
                get: { d.layout }, set: { d.layout = $0 }
            ),
            .animation(
                id: "Distance", displayName: "距離", group: "網点",
                get: { d.distance }, set: { d.distance = $0 }
            ),
            .animation(
                id: "Size", displayName: "サイズ", group: "網点",
                get: { d.size }, set: { d.size = $0 }
            ),
            .color(
                id: "Color", displayName: "色", group: "網点",
                get: { d.color }, set: { d.color = $0 }
            ),
            .animation(
                id: "Strength", displayName: "色の強さ", group: "網点",
                get: { d.strength }, set: { d.strength = $0 }
            )
        ]
    }

    /// InvertEffectDefinition の固有パラメータ。
    static func invertEffectDescriptors(_ d: InvertEffectDefinition) -> [PropertyDescriptor] {
        [
            
        ]
    }

    /// LinearTransferEffectDefinition の固有パラメータ。
    static func linearTransferEffectDescriptors(_ d: LinearTransferEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "RedYIntercept", displayName: "赤切片", group: "線形色変換",
                get: { d.redYIntercept }, set: { d.redYIntercept = $0 }
            ),
            .animation(
                id: "RedSlope", displayName: "赤傾き", group: "線形色変換",
                get: { d.redSlope }, set: { d.redSlope = $0 }
            ),
            .animation(
                id: "GreenYIntercept", displayName: "緑切片", group: "線形色変換",
                get: { d.greenYIntercept }, set: { d.greenYIntercept = $0 }
            ),
            .animation(
                id: "GreenSlope", displayName: "緑傾き", group: "線形色変換",
                get: { d.greenSlope }, set: { d.greenSlope = $0 }
            ),
            .animation(
                id: "BlueYIntercept", displayName: "青切片", group: "線形色変換",
                get: { d.blueYIntercept }, set: { d.blueYIntercept = $0 }
            ),
            .animation(
                id: "BlueSlope", displayName: "青傾き", group: "線形色変換",
                get: { d.blueSlope }, set: { d.blueSlope = $0 }
            ),
            .animation(
                id: "AlphaYIntercept", displayName: "不透明度切片", group: "線形色変換",
                get: { d.alphaYIntercept }, set: { d.alphaYIntercept = $0 }
            ),
            .animation(
                id: "AlphaSlope", displayName: "不透明度傾き", group: "線形色変換",
                get: { d.alphaSlope }, set: { d.alphaSlope = $0 }
            )
        ]
    }

    /// MonocolorizationEffectDefinition の固有パラメータ。
    static func monocolorizationEffectDescriptors(_ d: MonocolorizationEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Strength", displayName: "強度", group: "単色化",
                get: { d.strength }, set: { d.strength = $0 }
            ),
            .color(
                id: "Color", displayName: "色", group: "単色化",
                get: { d.color }, set: { d.color = $0 }
            ),
            .boolean(
                id: "KeepBrightness", displayName: "輝度を保持", group: "単色化",
                get: { d.keepBrightness }, set: { d.keepBrightness = $0 }
            )
        ]
    }

    /// MosaicEffectDefinition の固有パラメータ。
    static func mosaicEffectDescriptors(_ d: MosaicEffectDefinition) -> [PropertyDescriptor] {
        [
            .enumeration(
                id: "MosaicType", displayName: "種類", group: "モザイク",
                options: mosaicTypeOptions,
                get: { d.mosaicType }, set: { d.mosaicType = $0 }
            ),
            mosaicParameterDescriptor(d)
        ]
    }

    /// NoiseColorShiftEffectDefinition の固有パラメータ。
    static func noiseColorShiftEffectDescriptors(_ d: NoiseColorShiftEffectDefinition) -> [PropertyDescriptor] {
        [
            .enumeration(
                id: "Mode", displayName: "変形方法", group: "ノイズ色ずれ",
                options: displacementMapTransformModeOptions,
                get: { d.mode }, set: { d.mode = $0 }
            ),
            preservedDescriptor(
                id: "Transform", displayName: "Transform", group: "ノイズ色ずれ",
                get: { d.transform }, set: { d.transform = $0 }
            ),
            .animation(
                id: "Blur", displayName: "ぼかし度", group: "ノイズ色ずれ",
                get: { d.blur }, set: { d.blur = $0 }
            ),
            .enumeration(
                id: "NoiseType", displayName: "種類", group: "ノイズ",
                options: noiseTypeOptions,
                get: { d.noiseType }, set: { d.noiseType = $0 }
            ),
            preservedDescriptor(
                id: "NoiseParameter", displayName: "NoiseParameter", group: "ノイズ",
                get: { d.noiseParameter }, set: { d.noiseParameter = $0 }
            )
        ]
    }

    /// PosterizeEffectDefinition の固有パラメータ。
    static func posterizeEffectDescriptors(_ d: PosterizeEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "R", displayName: "赤", group: "階調",
                get: { d.r }, set: { d.r = $0 }
            ),
            .animation(
                id: "G", displayName: "緑", group: "階調",
                get: { d.g }, set: { d.g = $0 }
            ),
            .animation(
                id: "B", displayName: "青", group: "階調",
                get: { d.b }, set: { d.b = $0 }
            )
        ]
    }

    /// RadialBlurEffectDefinition の固有パラメータ。
    static func radialBlurEffectDescriptors(_ d: RadialBlurEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Blur", displayName: "サイズ", group: "放射ブラー",
                get: { d.blur }, set: { d.blur = $0 }
            ),
            .animation(
                id: "X", displayName: "中心X", group: "放射ブラー",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "中心Y", group: "放射ブラー",
                get: { d.y }, set: { d.y = $0 }
            ),
            .boolean(
                id: "IsHardBorderMode", displayName: "サイズを固定", group: "放射ブラー",
                get: { d.isHardBorderMode }, set: { d.isHardBorderMode = $0 }
            )
        ]
    }

    /// RadialLightEffectDefinition の固有パラメータ。
    static func radialLightEffectDescriptors(_ d: RadialLightEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Value", displayName: "強さ", group: "放射光",
                get: { d.value }, set: { d.value = $0 }
            ),
            .animation(
                id: "X", displayName: "中心X", group: "放射光",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "中心Y", group: "放射光",
                get: { d.y }, set: { d.y = $0 }
            ),
            .boolean(
                id: "IsHardBorderMode", displayName: "サイズを固定", group: "放射光",
                get: { d.isHardBorderMode }, set: { d.isHardBorderMode = $0 }
            )
        ]
    }

    /// SepiaEffectDefinition の固有パラメータ。
    static func sepiaEffectDescriptors(_ d: SepiaEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Strength", displayName: "強さ", group: "セピア",
                get: { d.strength }, set: { d.strength = $0 }
            ),
            .animation(
                id: "SepiaIntensity", displayName: "色味", group: "セピア",
                get: { d.sepiaIntensity }, set: { d.sepiaIntensity = $0 }
            )
        ]
    }

    /// SharpenEffectDefinition の固有パラメータ。
    static func sharpenEffectDescriptors(_ d: SharpenEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Sharpness", displayName: "シャープ度", group: "シャープ化",
                get: { d.sharpness }, set: { d.sharpness = $0 }
            ),
            .animation(
                id: "Threshold", displayName: "しきい値", group: "シャープ化",
                get: { d.threshold }, set: { d.threshold = $0 }
            )
        ]
    }

    /// TintEffectDefinition の固有パラメータ。
    static func tintEffectDescriptors(_ d: TintEffectDefinition) -> [PropertyDescriptor] {
        [
            .color(
                id: "Color", displayName: "色", group: "色味調整",
                get: { d.color }, set: { d.color = $0 }
            )
        ]
    }
}
