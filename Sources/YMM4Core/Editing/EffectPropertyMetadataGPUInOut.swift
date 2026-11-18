import Foundation

/// 映像エフェクト定義のプロパティメタデータ（GPUInOut 系）。
///
/// `EffectPropertyMetadata.descriptors(for:)` の具象定義別ビルダー。
/// 表示名・グループは本家の `Display` 属性（`Texts` リソース）、
/// 数値範囲は本家の `Range` / スライダ属性に根拠を持つ。
/// 根拠が取れない表示名はプロパティ名そのままにする。
public extension EffectPropertyMetadata {

    /// HlslPixelShaderCodeEffectDefinition の固有パラメータ。
    static func hlslPixelShaderCodeEffectDescriptors(_ d: HlslPixelShaderCodeEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "InputExpand", displayName: "入力拡張", group: "HLSLピクセルシェーダーコード",
                get: { d.inputExpand }, set: { d.inputExpand = $0 }
            ),
            .animation(
                id: "OutputExpand", displayName: "出力拡張", group: "HLSLピクセルシェーダーコード",
                get: { d.outputExpand }, set: { d.outputExpand = $0 }
            ),
            .animation(
                id: "Value0", displayName: "Value0", group: "HLSLピクセルシェーダーコード",
                get: { d.value0 }, set: { d.value0 = $0 }
            ),
            .animation(
                id: "Value1", displayName: "Value1", group: "HLSLピクセルシェーダーコード",
                get: { d.value1 }, set: { d.value1 = $0 }
            ),
            .animation(
                id: "Value2", displayName: "Value2", group: "HLSLピクセルシェーダーコード",
                get: { d.value2 }, set: { d.value2 = $0 }
            ),
            .animation(
                id: "Value3", displayName: "Value3", group: "HLSLピクセルシェーダーコード",
                get: { d.value3 }, set: { d.value3 = $0 }
            ),
            .text(
                id: "Source", displayName: "ソースコード", group: "HLSLピクセルシェーダーコード", multiline: true,
                get: { d.source }, set: { d.source = $0 }
            )
        ]
    }

    /// HlslPixelShaderFileEffectDefinition の固有パラメータ。
    static func hlslPixelShaderFileEffectDescriptors(_ d: HlslPixelShaderFileEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "InputExpand", displayName: "入力拡張", group: "HLSLピクセルシェーダーファイル",
                get: { d.inputExpand }, set: { d.inputExpand = $0 }
            ),
            .animation(
                id: "OutputExpand", displayName: "出力拡張", group: "HLSLピクセルシェーダーファイル",
                get: { d.outputExpand }, set: { d.outputExpand = $0 }
            ),
            .animation(
                id: "Value0", displayName: "Value0", group: "HLSLピクセルシェーダーファイル",
                get: { d.value0 }, set: { d.value0 = $0 }
            ),
            .animation(
                id: "Value1", displayName: "Value1", group: "HLSLピクセルシェーダーファイル",
                get: { d.value1 }, set: { d.value1 = $0 }
            ),
            .animation(
                id: "Value2", displayName: "Value2", group: "HLSLピクセルシェーダーファイル",
                get: { d.value2 }, set: { d.value2 = $0 }
            ),
            .animation(
                id: "Value3", displayName: "Value3", group: "HLSLピクセルシェーダーファイル",
                get: { d.value3 }, set: { d.value3 = $0 }
            ),
            .text(
                id: "File", displayName: "ソースコード", group: "HLSLピクセルシェーダーファイル",
                get: { d.file ?? "" }, set: { d.file = $0.isEmpty ? nil : $0 }
            )
        ]
    }

    /// InOutBorderBlurEffectDefinition の固有パラメータ。
    static func inOutBorderBlurEffectDescriptors(_ d: InOutBorderBlurEffectDefinition) -> [PropertyDescriptor] {
        [
            .number(
                id: "Value", displayName: "ぼかし度", group: "境界ぼかし", range: 0...250,
                get: { d.value }, set: { d.value = $0 }
            ),
            .boolean(
                id: "IsInEffect", displayName: "登場時", group: "登場退場",
                get: { d.isInEffect }, set: { d.isInEffect = $0 }
            ),
            .boolean(
                id: "IsOutEffect", displayName: "退場時", group: "登場退場",
                get: { d.isOutEffect }, set: { d.isOutEffect = $0 }
            ),
            .number(
                id: "EffectTimeSeconds", displayName: "効果時間", group: "登場退場", range: 0...100000,
                get: { d.effectTimeSeconds }, set: { d.effectTimeSeconds = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "登場退場",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "登場退場",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            )
        ]
    }

    /// InOutCrashEffectDefinition の固有パラメータ。
    static func inOutCrashEffectDescriptors(_ d: InOutCrashEffectDefinition) -> [PropertyDescriptor] {
        [
            .boolean(
                id: "IsInEffect", displayName: "登場時", group: "登場退場",
                get: { d.isInEffect }, set: { d.isInEffect = $0 }
            ),
            .boolean(
                id: "IsOutEffect", displayName: "退場時", group: "登場退場",
                get: { d.isOutEffect }, set: { d.isOutEffect = $0 }
            ),
            .number(
                id: "EffectTimeSeconds", displayName: "効果時間", group: "登場退場", range: 0...100000,
                get: { d.effectTimeSeconds }, set: { d.effectTimeSeconds = $0 }
            ),
            .number(
                id: "PlaybackRate", displayName: "再生速度", group: "登場退場", range: 0...100000,
                get: { d.playbackRate }, set: { d.playbackRate = $0 }
            ),
            .number(
                id: "Size", displayName: "破片の大きさ", group: "登場退場", range: 0...100000,
                get: { d.size }, set: { d.size = $0 }
            ),
            .animation(
                id: "X", displayName: "X", group: "砕け始める位置",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "砕け始める位置",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Z", displayName: "Z", group: "砕け始める位置",
                get: { d.z }, set: { d.z = $0 }
            ),
            .number(
                id: "FlySpeed", displayName: "飛散速度", group: "アニメーション詳細", range: 0...100000,
                get: { d.flySpeed }, set: { d.flySpeed = $0 }
            ),
            .number(
                id: "FallSpeed", displayName: "落下速度", group: "アニメーション詳細", range: 0...100000,
                get: { d.fallSpeed }, set: { d.fallSpeed = $0 }
            ),
            .number(
                id: "Delay", displayName: "時間差", group: "アニメーション詳細", range: 0...100000,
                get: { d.delay }, set: { d.delay = $0 }
            ),
            .number(
                id: "Impact", displayName: "距離影響", group: "アニメーション詳細", range: 0...100000,
                get: { d.impact }, set: { d.impact = $0 }
            ),
            .number(
                id: "RandomRotate", displayName: "ランダム回転", group: "アニメーション詳細", range: 0...100000,
                get: { d.randomRotate }, set: { d.randomRotate = $0 }
            ),
            .number(
                id: "RandomVector", displayName: "ランダム方向", group: "アニメーション詳細", range: 0...100000,
                get: { d.randomVector }, set: { d.randomVector = $0 }
            )
        ]
    }

    /// InOutGaussianBlurEffectDefinition の固有パラメータ。
    static func inOutGaussianBlurEffectDescriptors(_ d: InOutGaussianBlurEffectDefinition) -> [PropertyDescriptor] {
        [
            .number(
                id: "Value", displayName: "ぼかし度", group: "登場退場", range: 0...250,
                get: { d.value }, set: { d.value = $0 }
            ),
            .boolean(
                id: "IsInEffect", displayName: "登場時", group: "登場退場",
                get: { d.isInEffect }, set: { d.isInEffect = $0 }
            ),
            .boolean(
                id: "IsOutEffect", displayName: "退場時", group: "登場退場",
                get: { d.isOutEffect }, set: { d.isOutEffect = $0 }
            ),
            .number(
                id: "EffectTimeSeconds", displayName: "効果時間", group: "登場退場", range: 0...100000,
                get: { d.effectTimeSeconds }, set: { d.effectTimeSeconds = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "登場退場",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "登場退場",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            )
        ]
    }

    /// InOutGetUpEffectDefinition の固有パラメータ。
    static func inOutGetUpEffectDescriptors(_ d: InOutGetUpEffectDefinition) -> [PropertyDescriptor] {
        [
            .enumeration(
                id: "Base", displayName: "起点", group: "登場退場",
                options: inOutGetUpBaseLineOptions,
                get: { d.base }, set: { d.base = $0 }
            ),
            .enumeration(
                id: "Direction", displayName: "方向", group: "登場退場",
                options: inOutGetUpDirectionOptions,
                get: { d.direction }, set: { d.direction = $0 }
            ),
            .boolean(
                id: "Is3D", displayName: "三次元配置", group: "登場退場",
                get: { d.is3D }, set: { d.is3D = $0 }
            ),
            .boolean(
                id: "IsInEffect", displayName: "登場時", group: "登場退場",
                get: { d.isInEffect }, set: { d.isInEffect = $0 }
            ),
            .boolean(
                id: "IsOutEffect", displayName: "退場時", group: "登場退場",
                get: { d.isOutEffect }, set: { d.isOutEffect = $0 }
            ),
            .number(
                id: "EffectTimeSeconds", displayName: "効果時間", group: "登場退場", range: 0...100000,
                get: { d.effectTimeSeconds }, set: { d.effectTimeSeconds = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "登場退場",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "登場退場",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            )
        ]
    }

    /// InOutJumpEffectDefinition の固有パラメータ。
    static func inOutJumpEffectDescriptors(_ d: InOutJumpEffectDefinition) -> [PropertyDescriptor] {
        [
            .boolean(
                id: "IsInEffect", displayName: "登場時", group: "登場退場",
                get: { d.isInEffect }, set: { d.isInEffect = $0 }
            ),
            .boolean(
                id: "IsInReverse", displayName: "反転（登場時）", group: "登場退場",
                get: { d.isInReverse }, set: { d.isInReverse = $0 }
            ),
            .boolean(
                id: "IsOutEffect", displayName: "退場時", group: "登場退場",
                get: { d.isOutEffect }, set: { d.isOutEffect = $0 }
            ),
            .boolean(
                id: "IsOutReverse", displayName: "反転（退場時）", group: "登場退場",
                get: { d.isOutReverse }, set: { d.isOutReverse = $0 }
            ),
            .number(
                id: "EffectTimeSeconds", displayName: "効果時間", group: "登場退場", range: 0...100000,
                get: { d.effectTimeSeconds }, set: { d.effectTimeSeconds = $0 }
            ),
            .number(
                id: "JumpHeight", displayName: "高さ", group: "跳ねる", range: 0...100000,
                get: { d.jumpHeight }, set: { d.jumpHeight = $0 }
            ),
            .number(
                id: "Stretch", displayName: "伸び", group: "跳ねる", range: 0...100000,
                get: { d.stretch }, set: { d.stretch = $0 }
            ),
            .number(
                id: "Period", displayName: "周期", group: "跳ねる", range: 0...100000,
                get: { d.period }, set: { d.period = $0 }
            ),
            .number(
                id: "Distortion", displayName: "歪み", group: "着地", range: 0...100,
                get: { d.distortion }, set: { d.distortion = $0 }
            ),
            .number(
                id: "Interval", displayName: "間隔", group: "着地", range: 0...100000,
                get: { d.interval }, set: { d.interval = $0 }
            ),
            .number(
                id: "X", displayName: "X", group: "移動", range: -100000...100000,
                get: { d.x }, set: { d.x = $0 }
            ),
            .number(
                id: "Y", displayName: "Y", group: "移動", range: -100000...100000,
                get: { d.y }, set: { d.y = $0 }
            )
        ]
    }

    /// InOutMosaicEffectDefinition の固有パラメータ。
    static func inOutMosaicEffectDescriptors(_ d: InOutMosaicEffectDefinition) -> [PropertyDescriptor] {
        [
            .number(
                id: "Value", displayName: "サイズ", group: "登場退場", range: 0...5000,
                get: { d.value }, set: { d.value = $0 }
            ),
            .boolean(
                id: "IsInEffect", displayName: "登場時", group: "登場退場",
                get: { d.isInEffect }, set: { d.isInEffect = $0 }
            ),
            .boolean(
                id: "IsOutEffect", displayName: "退場時", group: "登場退場",
                get: { d.isOutEffect }, set: { d.isOutEffect = $0 }
            ),
            .number(
                id: "EffectTimeSeconds", displayName: "効果時間", group: "登場退場", range: 0...100000,
                get: { d.effectTimeSeconds }, set: { d.effectTimeSeconds = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "登場退場",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "登場退場",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            )
        ]
    }

    /// InOutMoveFromOutsideImageEffectDefinition の固有パラメータ。
    static func inOutMoveFromOutsideImageEffectDescriptors(_ d: InOutMoveFromOutsideImageEffectDefinition) -> [PropertyDescriptor] {
        [
            .enumeration(
                id: "Value", displayName: "方向", group: "登場退場",
                options: topBottomLeftRightOptions,
                get: { d.value }, set: { d.value = $0 }
            ),
            .boolean(
                id: "IsInEffect", displayName: "登場時", group: "登場退場",
                get: { d.isInEffect }, set: { d.isInEffect = $0 }
            ),
            .boolean(
                id: "IsOutEffect", displayName: "退場時", group: "登場退場",
                get: { d.isOutEffect }, set: { d.isOutEffect = $0 }
            ),
            .number(
                id: "EffectTimeSeconds", displayName: "効果時間", group: "登場退場", range: 0...100000,
                get: { d.effectTimeSeconds }, set: { d.effectTimeSeconds = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "登場退場",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "登場退場",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            )
        ]
    }

    /// InOutRotateEffectDefinition の固有パラメータ。
    static func inOutRotateEffectDescriptors(_ d: InOutRotateEffectDefinition) -> [PropertyDescriptor] {
        [
            .number(
                id: "ValueX", displayName: "X軸", group: "登場退場", range: -100000...100000,
                get: { d.valueX }, set: { d.valueX = $0 }
            ),
            .number(
                id: "ValueY", displayName: "Y軸", group: "登場退場", range: -100000...100000,
                get: { d.valueY }, set: { d.valueY = $0 }
            ),
            .number(
                id: "ValueZ", displayName: "Z軸", group: "登場退場", range: -100000...100000,
                get: { d.valueZ }, set: { d.valueZ = $0 }
            ),
            .boolean(
                id: "Is3D", displayName: "三次元配置", group: "登場退場",
                get: { d.is3D }, set: { d.is3D = $0 }
            ),
            .boolean(
                id: "IsInEffect", displayName: "登場時", group: "登場退場",
                get: { d.isInEffect }, set: { d.isInEffect = $0 }
            ),
            .boolean(
                id: "IsOutEffect", displayName: "退場時", group: "登場退場",
                get: { d.isOutEffect }, set: { d.isOutEffect = $0 }
            ),
            .number(
                id: "EffectTimeSeconds", displayName: "効果時間", group: "登場退場", range: 0...100000,
                get: { d.effectTimeSeconds }, set: { d.effectTimeSeconds = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "登場退場",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "登場退場",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            )
        ]
    }

    /// InOutSkewEffectDefinition の固有パラメータ。
    static func inOutSkewEffectDescriptors(_ d: InOutSkewEffectDefinition) -> [PropertyDescriptor] {
        [
            .number(
                id: "AngleX", displayName: "X方向", group: "登場退場", range: -100000...100000,
                get: { d.angleX }, set: { d.angleX = $0 }
            ),
            .number(
                id: "AngleY", displayName: "Y方向", group: "登場退場", range: -100000...100000,
                get: { d.angleY }, set: { d.angleY = $0 }
            ),
            .enumeration(
                id: "CenterPoint", displayName: "中心", group: "登場退場",
                options: skewCenterPointOptions,
                get: { d.centerPoint }, set: { d.centerPoint = $0 }
            ),
            .number(
                id: "CenterX", displayName: "中心X", group: "登場退場", range: -100000...100000,
                get: { d.centerX }, set: { d.centerX = $0 }
            ),
            .number(
                id: "CenterY", displayName: "中心Y", group: "登場退場", range: -100000...100000,
                get: { d.centerY }, set: { d.centerY = $0 }
            ),
            .boolean(
                id: "IsInEffect", displayName: "登場時", group: "登場退場",
                get: { d.isInEffect }, set: { d.isInEffect = $0 }
            ),
            .boolean(
                id: "IsOutEffect", displayName: "退場時", group: "登場退場",
                get: { d.isOutEffect }, set: { d.isOutEffect = $0 }
            ),
            .number(
                id: "EffectTimeSeconds", displayName: "効果時間", group: "登場退場", range: 0...100000,
                get: { d.effectTimeSeconds }, set: { d.effectTimeSeconds = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "登場退場",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "登場退場",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            )
        ]
    }

    /// InOutTransitionEffectDefinition の固有パラメータ。
    static func inOutTransitionEffectDescriptors(_ d: InOutTransitionEffectDefinition) -> [PropertyDescriptor] {
        [
            .text(
                id: "File", displayName: "パターン", group: "場面切り替え（ルール画像）",
                get: { d.file ?? "" }, set: { d.file = $0.isEmpty ? nil : $0 }
            ),
            .animation(
                id: "Tolerance", displayName: "ぼかし度", group: "場面切り替え（ルール画像）",
                get: { d.tolerance }, set: { d.tolerance = $0 }
            ),
            .animation(
                id: "Angle", displayName: "回転角", group: "場面切り替え（ルール画像）",
                get: { d.angle }, set: { d.angle = $0 }
            ),
            .boolean(
                id: "KeepAspect", displayName: "アスペクト比を維持", group: "場面切り替え（ルール画像）",
                get: { d.keepAspect }, set: { d.keepAspect = $0 }
            ),
            .boolean(
                id: "IsFixedCoveringScale", displayName: "拡大率を固定", group: "場面切り替え（ルール画像）",
                get: { d.isFixedCoveringScale }, set: { d.isFixedCoveringScale = $0 }
            ),
            .boolean(
                id: "IsInEffect", displayName: "登場時", group: "登場退場",
                get: { d.isInEffect }, set: { d.isInEffect = $0 }
            ),
            .boolean(
                id: "IsReversedInEffect", displayName: "反転（登場時）", group: "登場退場",
                get: { d.isReversedInEffect }, set: { d.isReversedInEffect = $0 }
            ),
            .boolean(
                id: "IsOutEffect", displayName: "退場時", group: "登場退場",
                get: { d.isOutEffect }, set: { d.isOutEffect = $0 }
            ),
            .boolean(
                id: "IsReversedOutEffect", displayName: "反転（退場時）", group: "登場退場",
                get: { d.isReversedOutEffect }, set: { d.isReversedOutEffect = $0 }
            ),
            .number(
                id: "EffectTimeSeconds", displayName: "効果時間", group: "登場退場", range: 0...100000,
                get: { d.effectTimeSeconds }, set: { d.effectTimeSeconds = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "登場退場",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "登場退場",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            )
        ]
    }

    /// RandomRotateEffectDefinition の固有パラメータ。
    static func randomRotateEffectDescriptors(_ d: RandomRotateEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "X軸", group: "ランダム",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y軸", group: "ランダム",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Z", displayName: "Z軸", group: "ランダム",
                get: { d.z }, set: { d.z = $0 }
            ),
            .boolean(
                id: "Is3D", displayName: "三次元配置", group: "ランダム",
                get: { d.is3D }, set: { d.is3D = $0 }
            ),
            .animation(
                id: "Span", displayName: "間隔", group: "ランダム",
                get: { d.span }, set: { d.span = $0 }
            )
        ]
    }

    /// RandomSkewEffectDefinition の固有パラメータ。
    static func randomSkewEffectDescriptors(_ d: RandomSkewEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "AngleX", displayName: "X方向", group: "傾斜変形",
                get: { d.angleX }, set: { d.angleX = $0 }
            ),
            .animation(
                id: "AngleY", displayName: "Y方向", group: "傾斜変形",
                get: { d.angleY }, set: { d.angleY = $0 }
            ),
            .enumeration(
                id: "CenterPoint", displayName: "中心", group: "傾斜変形",
                options: skewCenterPointOptions,
                get: { d.centerPoint }, set: { d.centerPoint = $0 }
            ),
            .animation(
                id: "CenterX", displayName: "中心X", group: "傾斜変形",
                get: { d.centerX }, set: { d.centerX = $0 }
            ),
            .animation(
                id: "CenterY", displayName: "中心Y", group: "傾斜変形",
                get: { d.centerY }, set: { d.centerY = $0 }
            ),
            .animation(
                id: "Span", displayName: "間隔", group: "ランダム",
                get: { d.span }, set: { d.span = $0 }
            )
        ]
    }

    /// RepeatRotateEffectDefinition の固有パラメータ。
    static func repeatRotateEffectDescriptors(_ d: RepeatRotateEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "X軸", group: "繰り返し",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y軸", group: "繰り返し",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Z", displayName: "Z軸", group: "繰り返し",
                get: { d.z }, set: { d.z = $0 }
            ),
            .boolean(
                id: "Is3D", displayName: "三次元配置", group: "繰り返し",
                get: { d.is3D }, set: { d.is3D = $0 }
            ),
            .animation(
                id: "Span", displayName: "間隔", group: "繰り返し",
                get: { d.span }, set: { d.span = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "繰り返し",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "繰り返し",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            ),
            .boolean(
                id: "IsCentering", displayName: "中央寄せ", group: "繰り返し",
                get: { d.isCentering }, set: { d.isCentering = $0 }
            )
        ]
    }

    /// RepeatSkewEffectDefinition の固有パラメータ。
    static func repeatSkewEffectDescriptors(_ d: RepeatSkewEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "AngleX", displayName: "X方向", group: "傾斜変形",
                get: { d.angleX }, set: { d.angleX = $0 }
            ),
            .animation(
                id: "AngleY", displayName: "Y方向", group: "傾斜変形",
                get: { d.angleY }, set: { d.angleY = $0 }
            ),
            .enumeration(
                id: "CenterPoint", displayName: "中心", group: "傾斜変形",
                options: skewCenterPointOptions,
                get: { d.centerPoint }, set: { d.centerPoint = $0 }
            ),
            .animation(
                id: "CenterX", displayName: "中心X", group: "傾斜変形",
                get: { d.centerX }, set: { d.centerX = $0 }
            ),
            .animation(
                id: "CenterY", displayName: "中心Y", group: "傾斜変形",
                get: { d.centerY }, set: { d.centerY = $0 }
            ),
            .animation(
                id: "Span", displayName: "間隔", group: "繰り返し",
                get: { d.span }, set: { d.span = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "繰り返し",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "繰り返し",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            ),
            .boolean(
                id: "IsCentering", displayName: "中央寄せ", group: "繰り返し",
                get: { d.isCentering }, set: { d.isCentering = $0 }
            )
        ]
    }
}
