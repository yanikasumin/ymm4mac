import Foundation

/// 映像エフェクト定義のプロパティメタデータ: 具象定義別の振り分けと、
/// 列挙型プロパティの選択肢（FXMETA）。
///
/// 選択肢の表示名は本家の列挙メンバの `Display` 属性（`Texts`
/// リソース）に根拠を持つ。根拠が無いメンバはメンバ名そのままにする。
public extension EffectPropertyMetadata {
    /// 具象定義ごとの固有パラメータ記述子。共通プロパティ
    /// （IsEnabled / Remark）と、拡大縮小・不透明度・描画位置
    /// （本体ファイルで定義済み）は対象外。
    static func specificDescriptors(for definition: VideoEffectDefinitionBase) -> [PropertyDescriptor] {
        switch definition {
        case let d as ArcBendEffectDefinition: return arcBendEffectDescriptors(d)
        case let d as AutomaticZoomEffectDefinition: return automaticZoomEffectDescriptors(d)
        case let d as BackgroundImageEffectDefinition: return backgroundImageEffectDescriptors(d)
        case let d as BillboardEffectDefinition: return billboardEffectDescriptors(d)
        case let d as BorderBlurEffectDefinition: return borderBlurEffectDescriptors(d)
        case let d as CameraFovEffectDefinition: return cameraFovEffectDescriptors(d)
        case let d as CameraLookAtEffectDefinition: return cameraLookAtEffectDescriptors(d)
        case let d as CameraPositionEffectDefinition: return cameraPositionEffectDescriptors(d)
        case let d as CameraWraparoundEffectDefinition: return cameraWraparoundEffectDescriptors(d)
        case let d as CenterPointEffectDefinition: return centerPointEffectDescriptors(d)
        case let d as ChromaKeyEffect2Definition: return chromaKeyEffect2Descriptors(d)
        case let d as ChromaKeyEffectDefinition: return chromaKeyEffectDescriptors(d)
        case let d as ChromaticAberrationEffectDefinition: return chromaticAberrationEffectDescriptors(d)
        case let d as CircularDuplicatorEffectDefinition: return circularDuplicatorEffectDescriptors(d)
        case let d as CopyAndReverseEffectDefinition: return copyAndReverseEffectDescriptors(d)
        case let d as CrashEffectDefinition: return crashEffectDescriptors(d)
        case let d as CropByAngleEffectDefinition: return cropByAngleEffectDescriptors(d)
        case let d as CropEffectDefinition: return cropEffectDescriptors(d)
        case let d as DirectionalBlurEffectDefinition: return directionalBlurEffectDescriptors(d)
        case let d as DisplacementMapEffectDefinition: return displacementMapEffectDescriptors(d)
        case let d as DrawLazyEffectEffectDefinition: return drawLazyEffectEffectDescriptors(d)
        case let d as ExposureEffectDefinition: return exposureEffectDescriptors(d)
        case let d as FillBackgroundEffectDefinition: return fillBackgroundEffectDescriptors(d)
        case let d as FillForegroundEffectDefinition: return fillForegroundEffectDescriptors(d)
        case let d as FrameLineEffectDefinition: return frameLineEffectDescriptors(d)
        case let d as GammaCorrectionEffectDefinition: return gammaCorrectionEffectDescriptors(d)
        case let d as GaussianBlurEffectDefinition: return gaussianBlurEffectDescriptors(d)
        case let d as GradientEffectDefinition: return gradientEffectDescriptors(d)
        case let d as HalfToneBorderBlurEffectDefinition: return halfToneBorderBlurEffectDescriptors(d)
        case let d as HalfToneEffectDefinition: return halfToneEffectDescriptors(d)
        case let d as HalfToneOutlineEffectDefinition: return halfToneOutlineEffectDescriptors(d)
        case let d as HalfToneShadowEffectDefinition: return halfToneShadowEffectDescriptors(d)
        case let d as HightlightsAndShadowsEffectDefinition: return hightlightsAndShadowsEffectDescriptors(d)
        case let d as HlslPixelShaderCodeEffectDefinition: return hlslPixelShaderCodeEffectDescriptors(d)
        case let d as HlslPixelShaderFileEffectDefinition: return hlslPixelShaderFileEffectDescriptors(d)
        case let d as InOutBorderBlurEffectDefinition: return inOutBorderBlurEffectDescriptors(d)
        case let d as InOutCrashEffectDefinition: return inOutCrashEffectDescriptors(d)
        case let d as InOutFadeEffectDefinition: return inOutFadeEffectDescriptors(d)
        case let d as InOutGaussianBlurEffectDefinition: return inOutGaussianBlurEffectDescriptors(d)
        case let d as InOutGetUpEffectDefinition: return inOutGetUpEffectDescriptors(d)
        case let d as InOutJumpEffectDefinition: return inOutJumpEffectDescriptors(d)
        case let d as InOutMosaicEffectDefinition: return inOutMosaicEffectDescriptors(d)
        case let d as InOutMoveEffectDefinition: return inOutMoveEffectDescriptors(d)
        case let d as InOutMoveFromOutsideFrameEffectDefinition: return inOutMoveFromOutsideFrameEffectDescriptors(d)
        case let d as InOutMoveFromOutsideImageEffectDefinition: return inOutMoveFromOutsideImageEffectDescriptors(d)
        case let d as InOutRotateEffectDefinition: return inOutRotateEffectDescriptors(d)
        case let d as InOutSkewEffectDefinition: return inOutSkewEffectDescriptors(d)
        case let d as InOutTransitionEffectDefinition: return inOutTransitionEffectDescriptors(d)
        case let d as InOutZoomEffectDefinition: return inOutZoomEffectDescriptors(d)
        case let d as InnerHalfToneShadowEffectDefinition: return innerHalfToneShadowEffectDescriptors(d)
        case let d as InnerShadowEffectDefinition: return innerShadowEffectDescriptors(d)
        case let d as InvertEffectDefinition: return invertEffectDescriptors(d)
        case let d as JumpEffectDefinition: return jumpEffectDescriptors(d)
        case let d as LinearTransferEffectDefinition: return linearTransferEffectDescriptors(d)
        case let d as MarginEffectDefinition: return marginEffectDescriptors(d)
        case let d as MaskEffectDefinition: return maskEffectDescriptors(d)
        case let d as MeshDeformationEffectDefinition: return meshDeformationEffectDescriptors(d)
        case let d as MonocolorizationEffectDefinition: return monocolorizationEffectDescriptors(d)
        case let d as MorphologyEffectDefinition: return morphologyEffectDescriptors(d)
        case let d as MosaicEffectDefinition: return mosaicEffectDescriptors(d)
        case let d as MotionTrackingEffectDefinition: return motionTrackingEffectDescriptors(d)
        case let d as NoiseColorShiftEffectDefinition: return noiseColorShiftEffectDescriptors(d)
        case let d as NoiseDisplacementMapEffectDefinition: return noiseDisplacementMapEffectDescriptors(d)
        case let d as NoiseEffectDefinition: return noiseEffectDescriptors(d)
        case let d as OutlineEffectDefinition: return outlineEffectDescriptors(d)
        case let d as PolarDrawPositionEffectDefinition: return polarDrawPositionEffectDescriptors(d)
        case let d as PolarTransformEffectDefinition: return polarTransformEffectDescriptors(d)
        case let d as PosterizeEffectDefinition: return posterizeEffectDescriptors(d)
        case let d as RadialBlurEffectDefinition: return radialBlurEffectDescriptors(d)
        case let d as RadialLightEffectDefinition: return radialLightEffectDescriptors(d)
        case let d as RandomDuplicatorEffectDefinition: return randomDuplicatorEffectDescriptors(d)
        case let d as RandomMoveEffectDefinition: return randomMoveEffectDescriptors(d)
        case let d as RandomOpacityEffectDefinition: return randomOpacityEffectDescriptors(d)
        case let d as RandomRotateEffectDefinition: return randomRotateEffectDescriptors(d)
        case let d as RandomSkewEffectDefinition: return randomSkewEffectDescriptors(d)
        case let d as RandomZoomEffectDefinition: return randomZoomEffectDescriptors(d)
        case let d as RepeatMoveEffectDefinition: return repeatMoveEffectDescriptors(d)
        case let d as RepeatOpacityEffectDefinition: return repeatOpacityEffectDescriptors(d)
        case let d as RepeatRotateEffectDefinition: return repeatRotateEffectDescriptors(d)
        case let d as RepeatSkewEffectDefinition: return repeatSkewEffectDescriptors(d)
        case let d as RepeatZoomEffectDefinition: return repeatZoomEffectDescriptors(d)
        case let d as RotateEffectDefinition: return rotateEffectDescriptors(d)
        case let d as RoundCornerEffectDefinition: return roundCornerEffectDescriptors(d)
        case let d as SepiaEffectDefinition: return sepiaEffectDescriptors(d)
        case let d as ShadowEffectDefinition: return shadowEffectDescriptors(d)
        case let d as SharpenEffectDefinition: return sharpenEffectDescriptors(d)
        case let d as ShowOnlyPreviewEffectDefinition: return showOnlyPreviewEffectDescriptors(d)
        case let d as SkewEffectDefinition: return skewEffectDescriptors(d)
        case let d as TextureEffectDefinition: return textureEffectDescriptors(d)
        case let d as TilingEffectDefinition: return tilingEffectDescriptors(d)
        case let d as TintEffectDefinition: return tintEffectDescriptors(d)
        case let d as XYToPolarTransformEffectDefinition: return xYToPolarTransformEffectDescriptors(d)
        default: return []
        }
    }

    // MARK: - 列挙の選択肢

    private static func options<E: HonkeEnum>(
        _ pairs: [(E, String)]
    ) -> [PropertyEnumOption] {
        pairs.map { PropertyEnumOption(value: $0.honkeName, displayName: $1) }
    }

    static let automaticZoomModeOptions = options([
        (.upDown, "拡大縮小"),
        (.upOnly, "拡大のみ"),
        (.downOnly, "縮小のみ")
    ] as [(AutomaticZoomMode, String)])

    static let automaticZoomTargetOptions = options([
        (.widthHeight, "縦横両方向"),
        (.widthOnly, "横方向のみ"),
        (.heightOnly, "縦方向のみ")
    ] as [(AutomaticZoomTarget, String)])

    static let blendOptions = options([
        (.normal, "通常"),
        (.add, "加算"),
        (.subtract, "減算"),
        (.multiply, "乗算"),
        (.screen, "スクリーン"),
        (.overlay, "オーバーレイ"),
        (.lighter, "比較（明）"),
        (.darker, "比較（暗）"),
        (.luminosity, "輝度"),
        (.color, "カラー"),
        (.linearBurn, "焼き込み（リニア）"),
        (.linearLight, "リニアライト"),
        (.difference, "差分"),
        (.colorBurn, "焼き込みカラー"),
        (.darkerColor, "カラー比較（暗）"),
        (.colorDodge, "覆い焼きカラー"),
        (.linearDodge, "覆い焼き（リニア） - 加算"),
        (.lighterColor, "カラー比較（明）"),
        (.softLight, "ソフトライト"),
        (.hardLight, "ハードライト"),
        (.vividLight, "ビビッドライト"),
        (.pinLight, "ピンライト"),
        (.hardMix, "ハードミックス"),
        (.exclusion, "除外"),
        (.hue, "色相"),
        (.saturation, "彩度"),
        (.dissolve, "ディザ合成"),
        (.division, "除算"),
        (.destinationOver, "背景"),
        (.destinationOut, "削除"),
        (.sourceAtop, "背景でクリッピング"),
        (.xor, "重ならない部分のみ"),
        (.maskInvert, "色反転マスク")
    ] as [(Blend, String)])

    static let centerPointHorizontalOptions = options([
        (.origin, "変更しない"),
        (.left, "左"),
        (.center, "中央"),
        (.right, "右"),
        (.custom, "カスタム")
    ] as [(CenterPointHorizontal, String)])

    static let centerPointVerticalOptions = options([
        (.origin, "変更しない"),
        (.top, "上"),
        (.center, "中央"),
        (.bottom, "下"),
        (.custom, "カスタム")
    ] as [(CenterPointVertical, String)])

    static let chromakeyDistanceModeOptions = options([
        (.rgb, "RGB色空間距離"),
        (.yuv, "YUV色空間距離"),
        (.yuvIgnoreLuma, "YUV色空間距離(輝度無視)"),
        (.ciede2000, "CIEDE2000色差"),
        (.colorDifference, "色差キーヤー")
    ] as [(ChromakeyDistanceMode, String)])

    static let displacementMapTransformModeOptions = options([
        (.move, "移動変形"),
        (.scale, "拡大変形"),
        (.rotate, "回転変形")
    ] as [(DisplacementMapTransformMode, String)])

    static let extendModeOptions = options([
        (.clamp, "なし"),
        (.wrap, "あり"),
        (.mirror, "反転")
    ] as [(ExtendMode, String)])

    static let frameLineTypeOptions = options([
        (.all, "全体"),
        (.top, "上"),
        (.bottom, "下"),
        (.left, "左"),
        (.right, "右")
    ] as [(FrameLineType, String)])

    static let gradientTypeOptions = options([
        (.linear, "線"),
        (.round, "円"),
        (.convex, "凸")
    ] as [(GradientType, String)])

    static let halfToneLayoutOptions = options([
        (.triangle, "三角形"),
        (.rectangle, "四角形"),
        (.rhombus, "ひし形")
    ] as [(HalfToneLayout, String)])

    static let inOutGetUpBaseLineOptions = options([
        (.top, "上辺"),
        (.bottom, "下辺"),
        (.left, "左辺"),
        (.right, "右辺"),
        (.centerX, "原点（X軸）"),
        (.centerY, "原点（Y軸）"),
        (.trueCenterX, "中央（X軸）"),
        (.trueCenterY, "中央（Y軸）")
    ] as [(InOutGetUpBaseLine, String)])

    static let inOutGetUpDirectionOptions = options([
        (.back, "奥から"),
        (.front, "手前から")
    ] as [(InOutGetUpDirection, String)])

    static let morphologyEffectModeOptions = options([
        (.erode, "輪郭を強調"),
        (.dilate, "平面を強調")
    ] as [(MorphologyEffectMode, String)])

    static let mosaicTypeOptions = options([
        (.circle, "円形"),
        (.triangle, "三角形"),
        (.rectangle, "四角形"),
        (.hexagon, "六角形"),
        (.delaunay, "ドロネー三角形分割"),
        (.voronoi, "ボロノイ分割")
    ] as [(MosaicType, String)])

    static let noiseTypeOptions = options([
        (.fractal, "バリュー"),
        (.random, "ランダム"),
        (.block, "ブロック"),
        (.perlin, "パーリン"),
        (.cellular, "セルラー"),
        (.voronoi, "ボロノイ"),
        (.simplex, "シンプレックス"),
        (.curl, "カール"),
        (.marble, "マーブル"),
        (.flow, "フロー")
    ] as [(NoiseType, String)])

    static let renderPlacementOptions = options([
        (.front, "前"),
        (.back, "後ろ")
    ] as [(RenderPlacement, String)])

    static let skewCenterPointOptions = options([
        (.center, "中央"),
        (.top, "上辺"),
        (.bottom, "下辺"),
        (.left, "左辺"),
        (.right, "右辺"),
        (.custom, "カスタム")
    ] as [(SkewCenterPoint, String)])

    static let topBottomLeftRightOptions = options([
        (.top, "上"),
        (.bottom, "下"),
        (.left, "左"),
        (.right, "右")
    ] as [(TopBottomLeftRight, String)])

    /// BillboardMode は `HonkeEnum` に適合しないため、値と表示名を
    /// 直接並べる。表示名は本家 `BillboardMode` メンバの `Display` 属性。
    static let billboardModeOptions: [PropertyEnumOption] = [
        PropertyEnumOption(value: "None", displayName: "None"),
        PropertyEnumOption(value: "Spherical", displayName: "全方向（球面）"),
        PropertyEnumOption(value: "Cylindrical", displayName: "Y軸のみ（円筒）")
    ]

    static func billboardModeName(_ mode: BillboardMode) -> String {
        switch mode {
        case .none: return "None"
        case .spherical: return "Spherical"
        case .cylindrical: return "Cylindrical"
        }
    }

    static let easingFamilyOptions: [PropertyEnumOption] = [
        PropertyEnumOption(value: "Linear", displayName: "等速 / Linear"),
        PropertyEnumOption(value: "Sine", displayName: "緩急1 / Sine（弱）"),
        PropertyEnumOption(value: "Quad", displayName: "緩急2 / Quad"),
        PropertyEnumOption(value: "Cubic", displayName: "緩急3 / Cubic"),
        PropertyEnumOption(value: "Quart", displayName: "緩急4 / Quart"),
        PropertyEnumOption(value: "Quint", displayName: "緩急5 / Quint"),
        PropertyEnumOption(value: "Expo", displayName: "緩急6 / Expo（強）"),
        PropertyEnumOption(value: "Circ", displayName: "円弧 / Circ"),
        PropertyEnumOption(value: "Back", displayName: "戻る / Back"),
        PropertyEnumOption(value: "Elastic", displayName: "バネ / Elastic"),
        PropertyEnumOption(value: "Bounce", displayName: "バウンド / Bounce"),
        PropertyEnumOption(value: "Jump", displayName: "瞬間 / Jump")
    ]

    static let easingModeOptions: [PropertyEnumOption] = [
        PropertyEnumOption(value: "In", displayName: "加速 / In"),
        PropertyEnumOption(value: "Out", displayName: "減速 / Out"),
        PropertyEnumOption(value: "InOut", displayName: "加減速 / InOut"),
        PropertyEnumOption(value: "OutIn", displayName: "減加速 / OutIn")
    ]

    // MARK: - イージング列挙（HonkeEnum 非適合のため専用経路）

    /// 本家 `EasingType`。保存名への変換は定義層の
    /// `effectHonkeName` を使う。未知の名前は現在値を保つ。
    static func easingFamilyDescriptor(
        id: String, displayName: String, group: String,
        get: @escaping () -> EasingFamily, set: @escaping (EasingFamily) -> Void
    ) -> PropertyDescriptor {
        PropertyDescriptor(
            id: id, displayName: displayName, group: group,
            kind: .enumeration(options: easingFamilyOptions),
            access: .enumeration(
                get: { get().effectHonkeName },
                set: { name in
                    if let value = EasingFamily(effectHonkeName: name) {
                        set(value)
                    }
                }
            )
        )
    }

    /// 本家 `EasingMode`。同上。
    static func easingModeDescriptor(
        id: String, displayName: String, group: String,
        get: @escaping () -> EasingMode, set: @escaping (EasingMode) -> Void
    ) -> PropertyDescriptor {
        PropertyDescriptor(
            id: id, displayName: displayName, group: group,
            kind: .enumeration(options: easingModeOptions),
            access: .enumeration(
                get: { get().effectHonkeName },
                set: { name in
                    if let value = EasingMode(effectHonkeName: name) {
                        set(value)
                    }
                }
            )
        )
    }
}
