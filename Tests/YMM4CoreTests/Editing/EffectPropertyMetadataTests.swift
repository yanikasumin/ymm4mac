import XCTest
@testable import YMM4Core

/// FXMETA: 内蔵エフェクト定義のプロパティメタデータの網羅と往復の検証。
///
/// - 網羅: レジストリ登録の全95種について、保存キーのうち記述子化の
///   対象とした全キーに記述子が存在し、並びが保存形式のキー順と一致する。
/// - 往復: 記述子経由の書き込みが定義の実プロパティへ届き、読み戻せる。
/// - 対象外: 記述子体系で表現できない複合プロパティ（ブラシ等の
///   入れ子オブジェクト、配列、パラメータオブジェクト）は、対象外として
///   明示した種別・キーだけであり、記述子に現れない。
final class EffectPropertyMetadataTests: XCTestCase {

    /// 種別（$type 名）ごとの固有パラメータ記述子の ID 列（保存キー順）。
    /// 共通プロパティ（IsEnabled / Remark）は全種別で先頭に付くため除く。
    private static let expectedSpecificIDs: [(typeName: String, ids: [String])] = [
        ("YukkuriMovieMaker.Project.Effects.ArcBendEffect, YukkuriMovieMaker", ["BendAngle", "AxisAngle", "Anchor"]),
        ("YukkuriMovieMaker.Project.Effects.AutomaticZoomEffect, YukkuriMovieMaker", ["AutomaticZoomMode", "AutomaticZoomTarget", "AutomaticZoomMarginTop", "AutomaticZoomMarginLeft", "IgnoreRotation"]),
        ("YukkuriMovieMaker.Project.Effects.BackgroundImageEffect, YukkuriMovieMaker", ["X", "Y", "Opacity", "Zoom", "PlaybackRate", "FilePath", "Top", "Bottom", "Left", "Right"]),
        ("YukkuriMovieMaker.Project.Effects.BillboardEffect, YukkuriMovieMaker", ["Mode"]),
        ("YukkuriMovieMaker.Project.Effects.BorderBlurEffect, YukkuriMovieMaker", ["Blur"]),
        ("YukkuriMovieMaker.Project.Effects.CameraFovEffect, YukkuriMovieMaker", ["Fov"]),
        ("YukkuriMovieMaker.Project.Effects.CameraLookAtEffect, YukkuriMovieMaker", ["X", "Y", "Z", "LookAtX", "LookAtY", "LookAtZ", "RotationZ", "ChangeFov", "Fov"]),
        ("YukkuriMovieMaker.Project.Effects.CameraPositionEffect, YukkuriMovieMaker", ["X", "Y", "Z", "RotationY", "RotationX", "RotationZ", "ChangeFov", "Fov"]),
        ("YukkuriMovieMaker.Project.Effects.CameraWraparoundEffect, YukkuriMovieMaker", ["X", "Y", "Z", "Radius", "RotationY", "RotationX", "RotationZ", "ChangeFov", "Fov"]),
        ("YukkuriMovieMaker.Project.Effects.CenterPointEffect, YukkuriMovieMaker", ["Horizontal", "Vertical", "X", "Y", "IsKeepPosition"]),
        ("YukkuriMovieMaker.Project.Effects.ChromaKeyEffect, YukkuriMovieMaker", ["Color", "Tolerance", "Feather", "IsInvert"]),
        ("YukkuriMovieMaker.Project.Effects.ChromaKeyEffect2, YukkuriMovieMaker", ["DistanceMode", "KeyColor", "Threshold2", "Smoothness", "Despill", "IsInvert"]),
        ("YukkuriMovieMaker.Project.Effects.ChromaticAberrationEffect, YukkuriMovieMaker", ["Strength"]),
        ("YukkuriMovieMaker.Project.Effects.CircularDuplicatorEffect, YukkuriMovieMaker", ["Count", "Radius", "CircumferenceRate", "IsSyncedAngle"]),
        ("YukkuriMovieMaker.Project.Effects.CopyAndReverseEffect, YukkuriMovieMaker", ["Position", "Distance", "IsTopBottomReversed", "IsLeftRightReversed", "IsCentering"]),
        ("YukkuriMovieMaker.Project.Effects.CrashEffect, YukkuriMovieMaker", ["StartTime", "PlaybackRate", "Size", "X", "Y", "Z", "FlySpeed", "FallSpeed", "Delay", "Impact", "RandomRotate", "RandomVector"]),
        ("YukkuriMovieMaker.Project.Effects.CropByAngleEffect, YukkuriMovieMaker", ["X", "Y", "Angle", "Blur", "Width"]),
        ("YukkuriMovieMaker.Project.Effects.CropEffect, YukkuriMovieMaker", ["Top", "Bottom", "Left", "Right", "IsCentering"]),
        ("YukkuriMovieMaker.Project.Effects.DirectionalBlurEffect, YukkuriMovieMaker", ["StandardDeviation", "Angle", "IsHardBorderMode"]),
        ("YukkuriMovieMaker.Project.Effects.DisplacementMapEffect, YukkuriMovieMaker", ["Mode", "Blur", "IsPatternMapPreviewEnabled"]),
        ("YukkuriMovieMaker.Project.Effects.DrawLazyEffectEffect, YukkuriMovieMaker", ["IsXYZ", "IsOpacity", "IsZoom", "IsRotation", "IsInvert", "IsCamera"]),
        ("YukkuriMovieMaker.Project.Effects.DrawPositionEffect, YukkuriMovieMaker", ["X", "Y", "Z"]),
        ("YukkuriMovieMaker.Project.Effects.ExposureEffect, YukkuriMovieMaker", ["Value"]),
        ("YukkuriMovieMaker.Project.Effects.FillBackgroundEffect, YukkuriMovieMaker", ["Opacity", "Round", "BlendMode", "IsBackgroundOnly", "Top", "Bottom", "Left", "Right"]),
        ("YukkuriMovieMaker.Project.Effects.FillForegroundEffect, YukkuriMovieMaker", ["Opacity", "BlendMode", "IsBrushOnly"]),
        ("YukkuriMovieMaker.Project.Effects.FrameLineEffect, YukkuriMovieMaker", ["Opacity", "Thickness", "RenderPlacement", "Type", "Top", "Bottom", "Left", "Right"]),
        ("YukkuriMovieMaker.Project.Effects.GammaCorrectionEffect, YukkuriMovieMaker", ["Gamma", "Red", "Green", "Blue"]),
        ("YukkuriMovieMaker.Project.Effects.GaussianBlurEffect, YukkuriMovieMaker", ["Blur", "IsHardBorderMode"]),
        ("YukkuriMovieMaker.Project.Effects.GradientEffect, YukkuriMovieMaker", ["GradientType", "X", "Y", "Opacity", "Size", "Rotation", "ExtendMode", "Blend"]),
        ("YukkuriMovieMaker.Project.Effects.HalfToneBorderBlurEffect, YukkuriMovieMaker", ["Blur", "Layout", "Distance", "Size", "Strength"]),
        ("YukkuriMovieMaker.Project.Effects.HalfToneEffect, YukkuriMovieMaker", ["Layout", "Distance", "Size", "Color", "Strength"]),
        ("YukkuriMovieMaker.Project.Effects.HalfToneOutlineEffect, YukkuriMovieMaker", ["StrokeThickness", "Opacity", "Blur", "IsOutlineOnly", "Layout", "Distance", "Size", "Color", "Strength"]),
        ("YukkuriMovieMaker.Project.Effects.HalfToneShadowEffect, YukkuriMovieMaker", ["X", "Y", "Opacity", "Angle", "Blur", "Layout", "Distance", "Size", "Color", "Strength", "KeepBrightness", "IsRotateAtCenter"]),
        ("YukkuriMovieMaker.Project.Effects.HightlightsAndShadowsEffect, YukkuriMovieMaker", ["Highlights", "Shadows"]),
        ("YukkuriMovieMaker.Project.Effects.HlslPixelShaderCodeEffect, YukkuriMovieMaker", ["InputExpand", "OutputExpand", "Value0", "Value1", "Value2", "Value3", "Source"]),
        ("YukkuriMovieMaker.Project.Effects.HlslPixelShaderFileEffect, YukkuriMovieMaker", ["InputExpand", "OutputExpand", "Value0", "Value1", "Value2", "Value3", "File"]),
        ("YukkuriMovieMaker.Project.Effects.InOutBorderBlurEffect, YukkuriMovieMaker", ["Value", "IsInEffect", "IsOutEffect", "EffectTimeSeconds", "EasingType", "EasingMode"]),
        ("YukkuriMovieMaker.Project.Effects.InOutCrashEffect, YukkuriMovieMaker", ["IsInEffect", "IsOutEffect", "EffectTimeSeconds", "PlaybackRate", "Size", "X", "Y", "Z", "FlySpeed", "FallSpeed", "Delay", "Impact", "RandomRotate", "RandomVector"]),
        ("YukkuriMovieMaker.Project.Effects.InOutFadeEffect, YukkuriMovieMaker", ["Value", "IsInEffect", "IsOutEffect", "EffectTimeSeconds", "EasingType", "EasingMode"]),
        ("YukkuriMovieMaker.Project.Effects.InOutGaussianBlurEffect, YukkuriMovieMaker", ["Value", "IsInEffect", "IsOutEffect", "EffectTimeSeconds", "EasingType", "EasingMode"]),
        ("YukkuriMovieMaker.Project.Effects.InOutGetUpEffect, YukkuriMovieMaker", ["Base", "Direction", "Is3D", "IsInEffect", "IsOutEffect", "EffectTimeSeconds", "EasingType", "EasingMode"]),
        ("YukkuriMovieMaker.Project.Effects.InOutJumpEffect, YukkuriMovieMaker", ["IsInEffect", "IsInReverse", "IsOutEffect", "IsOutReverse", "EffectTimeSeconds", "JumpHeight", "Stretch", "Period", "Distortion", "Interval", "X", "Y"]),
        ("YukkuriMovieMaker.Project.Effects.InOutMosaicEffect, YukkuriMovieMaker", ["Value", "IsInEffect", "IsOutEffect", "EffectTimeSeconds", "EasingType", "EasingMode"]),
        ("YukkuriMovieMaker.Project.Effects.InOutMoveEffect, YukkuriMovieMaker", ["Value", "Value2", "Value3", "IsInEffect", "IsOutEffect", "EffectTimeSeconds", "EasingType", "EasingMode"]),
        ("YukkuriMovieMaker.Project.Effects.InOutMoveFromOutsideFrameEffect, YukkuriMovieMaker", ["Value", "IsInEffect", "IsOutEffect", "EffectTimeSeconds", "EasingType", "EasingMode"]),
        ("YukkuriMovieMaker.Project.Effects.InOutMoveFromOutsideImageEffect, YukkuriMovieMaker", ["Value", "IsInEffect", "IsOutEffect", "EffectTimeSeconds", "EasingType", "EasingMode"]),
        ("YukkuriMovieMaker.Project.Effects.InOutRotateEffect, YukkuriMovieMaker", ["ValueX", "ValueY", "ValueZ", "Is3D", "IsInEffect", "IsOutEffect", "EffectTimeSeconds", "EasingType", "EasingMode"]),
        ("YukkuriMovieMaker.Project.Effects.InOutSkewEffect, YukkuriMovieMaker", ["AngleX", "AngleY", "CenterPoint", "CenterX", "CenterY", "IsInEffect", "IsOutEffect", "EffectTimeSeconds", "EasingType", "EasingMode"]),
        ("YukkuriMovieMaker.Project.Effects.InOutTransitionEffect, YukkuriMovieMaker", ["File", "Tolerance", "Angle", "KeepAspect", "IsFixedCoveringScale", "IsInEffect", "IsReversedInEffect", "IsOutEffect", "IsReversedOutEffect", "EffectTimeSeconds", "EasingType", "EasingMode"]),
        ("YukkuriMovieMaker.Project.Effects.InOutZoomEffect, YukkuriMovieMaker", ["Value", "X", "Y", "IsInEffect", "IsOutEffect", "EffectTimeSeconds", "EasingType", "EasingMode"]),
        ("YukkuriMovieMaker.Project.Effects.InnerHalfToneShadowEffect, YukkuriMovieMaker", ["X", "Y", "Opacity", "Blur", "BlendMode", "Layout", "Distance", "Size", "Color", "Strength"]),
        ("YukkuriMovieMaker.Project.Effects.InnerShadowEffect, YukkuriMovieMaker", ["X", "Y", "Opacity", "Blur", "BlendMode"]),
        ("YukkuriMovieMaker.Project.Effects.InvertEffect, YukkuriMovieMaker", []),
        ("YukkuriMovieMaker.Project.Effects.JumpEffect, YukkuriMovieMaker", ["JumpHeight", "Stretch", "Period", "Distortion", "Interval", "X", "Y"]),
        ("YukkuriMovieMaker.Project.Effects.LinearTransferEffect, YukkuriMovieMaker", ["RedYIntercept", "RedSlope", "GreenYIntercept", "GreenSlope", "BlueYIntercept", "BlueSlope", "AlphaYIntercept", "AlphaSlope"]),
        ("YukkuriMovieMaker.Project.Effects.MarginEffect, YukkuriMovieMaker", ["Top", "Bottom", "Left", "Right"]),
        ("YukkuriMovieMaker.Project.Effects.MaskEffect, YukkuriMovieMaker", ["X", "Y", "Opacity", "Angle", "ShapeType2", "Blur", "InvertMask"]),
        ("YukkuriMovieMaker.Project.Effects.MeshDeformationEffect, YukkuriMovieMaker", ["HorizontalCount", "VerticalCount", "Smoothness"]),
        ("YukkuriMovieMaker.Project.Effects.MonocolorizationEffect, YukkuriMovieMaker", ["Strength", "Color", "KeepBrightness"]),
        ("YukkuriMovieMaker.Project.Effects.MorphologyEffect, YukkuriMovieMaker", ["Mode", "Width", "Height"]),
        ("YukkuriMovieMaker.Project.Effects.MosaicEffect, YukkuriMovieMaker", ["MosaicType"]),
        ("YukkuriMovieMaker.Project.Effects.MotionTrackingEffect, YukkuriMovieMaker", ["Smooth", "IsReverce", "IsReverseZoom", "IsFixedSize", "ControlPointVisibleSeconds", "IsOnlyCurrentFrameRectLine"]),
        ("YukkuriMovieMaker.Project.Effects.NoiseColorShiftEffect, YukkuriMovieMaker", ["Mode", "Blur", "NoiseType"]),
        ("YukkuriMovieMaker.Project.Effects.NoiseDisplacementMapEffect, YukkuriMovieMaker", ["Mode", "Blur", "NoiseType"]),
        ("YukkuriMovieMaker.Project.Effects.NoiseEffect, YukkuriMovieMaker", ["NoiseType", "IsColor", "IsAlpha", "IsUniqueSeed"]),
        ("YukkuriMovieMaker.Project.Effects.OpacityEffect, YukkuriMovieMaker", ["Opacity", "IsAbsolute"]),
        ("YukkuriMovieMaker.Project.Effects.OutlineEffect, YukkuriMovieMaker", ["StrokeThickness", "Blur", "Quality", "Smoothness", "X", "Y", "Opacity", "Zoom", "Rotation", "IsOutlineOnly", "IsAngular"]),
        ("YukkuriMovieMaker.Project.Effects.PolarDrawPositionEffect, YukkuriMovieMaker", ["Radius", "Angle", "Angle2", "IsSyncRotation"]),
        ("YukkuriMovieMaker.Project.Effects.PolarTransformEffect, YukkuriMovieMaker", ["CoreWidth", "TwistAngle"]),
        ("YukkuriMovieMaker.Project.Effects.PosterizeEffect, YukkuriMovieMaker", ["R", "G", "B"]),
        ("YukkuriMovieMaker.Project.Effects.RadialBlurEffect, YukkuriMovieMaker", ["Blur", "X", "Y", "IsHardBorderMode"]),
        ("YukkuriMovieMaker.Project.Effects.RadialLightEffect, YukkuriMovieMaker", ["Value", "X", "Y", "IsHardBorderMode"]),
        ("YukkuriMovieMaker.Project.Effects.RandomDuplicatorEffect, YukkuriMovieMaker", ["Count", "Range", "Rotation", "IsThreeDimensional", "RandomMove", "RandomRotation"]),
        ("YukkuriMovieMaker.Project.Effects.RandomMoveEffect, YukkuriMovieMaker", ["X", "Y", "Z", "Span"]),
        ("YukkuriMovieMaker.Project.Effects.RandomOpacityEffect, YukkuriMovieMaker", ["Opacity", "Span"]),
        ("YukkuriMovieMaker.Project.Effects.RandomRotateEffect, YukkuriMovieMaker", ["X", "Y", "Z", "Is3D", "Span"]),
        ("YukkuriMovieMaker.Project.Effects.RandomSkewEffect, YukkuriMovieMaker", ["AngleX", "AngleY", "CenterPoint", "CenterX", "CenterY", "Span"]),
        ("YukkuriMovieMaker.Project.Effects.RandomZoomEffect, YukkuriMovieMaker", ["Zoom", "ZoomX", "ZoomY", "Span"]),
        ("YukkuriMovieMaker.Project.Effects.RepeatMoveEffect, YukkuriMovieMaker", ["X", "Y", "Z", "Span", "EasingType", "EasingMode", "IsCentering"]),
        ("YukkuriMovieMaker.Project.Effects.RepeatOpacityEffect, YukkuriMovieMaker", ["Opacity", "Span", "EasingType", "EasingMode"]),
        ("YukkuriMovieMaker.Project.Effects.RepeatRotateEffect, YukkuriMovieMaker", ["X", "Y", "Z", "Is3D", "Span", "EasingType", "EasingMode", "IsCentering"]),
        ("YukkuriMovieMaker.Project.Effects.RepeatSkewEffect, YukkuriMovieMaker", ["AngleX", "AngleY", "CenterPoint", "CenterX", "CenterY", "Span", "EasingType", "EasingMode", "IsCentering"]),
        ("YukkuriMovieMaker.Project.Effects.RepeatZoomEffect, YukkuriMovieMaker", ["Zoom", "ZoomX", "ZoomY", "Span", "EasingType", "EasingMode", "IsCentering"]),
        ("YukkuriMovieMaker.Project.Effects.RotateEffect, YukkuriMovieMaker", ["X", "Y", "Z", "Is3D"]),
        ("YukkuriMovieMaker.Project.Effects.RoundCornerEffect, YukkuriMovieMaker", ["Radius", "Blur"]),
        ("YukkuriMovieMaker.Project.Effects.SepiaEffect, YukkuriMovieMaker", ["Strength", "SepiaIntensity"]),
        ("YukkuriMovieMaker.Project.Effects.ShadowEffect, YukkuriMovieMaker", ["X", "Y", "Opacity", "Zoom", "Angle", "Blur", "IsRotateAtCenter"]),
        ("YukkuriMovieMaker.Project.Effects.SharpenEffect, YukkuriMovieMaker", ["Sharpness", "Threshold"]),
        ("YukkuriMovieMaker.Project.Effects.ShowOnlyPreviewEffect, YukkuriMovieMaker", ["IsPlaying", "IsPaused"]),
        ("YukkuriMovieMaker.Project.Effects.SkewEffect, YukkuriMovieMaker", ["AngleX", "AngleY", "CenterPoint", "CenterX", "CenterY"]),
        ("YukkuriMovieMaker.Project.Effects.TextureEffect, YukkuriMovieMaker", ["X", "Y", "Zoom", "Rotation", "FilePath", "PlaybackRate", "ContentOffset", "IsInverted"]),
        ("YukkuriMovieMaker.Project.Effects.TilingEffect, YukkuriMovieMaker", ["X", "Y"]),
        ("YukkuriMovieMaker.Project.Effects.TintEffect, YukkuriMovieMaker", ["Color"]),
        ("YukkuriMovieMaker.Project.Effects.XYToPolarTransformEffect, YukkuriMovieMaker", ["XRange", "ZRange", "IsClockwise", "IsSyncRotation"]),
        ("YukkuriMovieMaker.Project.Effects.ZoomEffect, YukkuriMovieMaker", ["Zoom", "ZoomX", "ZoomY", "IsNearestNeighbor"]),
    ]

    /// 記述子の対象外とした保存キー（種別 $type 名 → キー列）。
    /// 本家でも入れ子の専用エディタで編集する複合プロパティと、
    /// 本家で固定値のダミー上書きになっている RepeatOpacity の
    /// IsCentering が該当する。詳細は実装台帳（FXMETA）を参照。
    private static let excludedKeys: [(typeName: String, keys: [String])] = [
        ("YukkuriMovieMaker.Project.Effects.DisplacementMapEffect, YukkuriMovieMaker", ["Transform", "Brush"]),
        ("YukkuriMovieMaker.Project.Effects.FillBackgroundEffect, YukkuriMovieMaker", ["Brush"]),
        ("YukkuriMovieMaker.Project.Effects.FillForegroundEffect, YukkuriMovieMaker", ["Brush"]),
        ("YukkuriMovieMaker.Project.Effects.FrameLineEffect, YukkuriMovieMaker", ["Brush"]),
        ("YukkuriMovieMaker.Project.Effects.GradientEffect, YukkuriMovieMaker", ["Stops"]),
        ("YukkuriMovieMaker.Project.Effects.InnerShadowEffect, YukkuriMovieMaker", ["Brush"]),
        ("YukkuriMovieMaker.Project.Effects.MaskEffect, YukkuriMovieMaker", ["ShapeParameter"]),
        ("YukkuriMovieMaker.Project.Effects.MeshDeformationEffect, YukkuriMovieMaker", ["Points"]),
        ("YukkuriMovieMaker.Project.Effects.MosaicEffect, YukkuriMovieMaker", ["MosaicParameter"]),
        ("YukkuriMovieMaker.Project.Effects.MotionTrackingEffect, YukkuriMovieMaker", ["Path"]),
        ("YukkuriMovieMaker.Project.Effects.NoiseColorShiftEffect, YukkuriMovieMaker", ["Transform", "NoiseParameter"]),
        ("YukkuriMovieMaker.Project.Effects.NoiseDisplacementMapEffect, YukkuriMovieMaker", ["Transform", "NoiseParameter"]),
        ("YukkuriMovieMaker.Project.Effects.NoiseEffect, YukkuriMovieMaker", ["NoiseParameter"]),
        ("YukkuriMovieMaker.Project.Effects.OutlineEffect, YukkuriMovieMaker", ["StrokeBrush"]),
        ("YukkuriMovieMaker.Project.Effects.RepeatOpacityEffect, YukkuriMovieMaker", ["IsCentering"]),
        ("YukkuriMovieMaker.Project.Effects.ShadowEffect, YukkuriMovieMaker", ["Brush"]),
    ]

    // MARK: - 網羅

    func testAllRegisteredTypesHaveCompleteDescriptors() throws {
        XCTAssertEqual(Self.expectedSpecificIDs.count, 95)
        for (typeName, expectedIDs) in Self.expectedSpecificIDs {
            let definition = try XCTUnwrap(
                VideoEffectRegistry.makeEmptyDefinition(typeName: typeName),
                "\(typeName) の定義が生成できない"
            )
            let descriptors = EffectPropertyMetadata.descriptors(for: definition)
            XCTAssertEqual(
                Array(descriptors.prefix(2)).map(\.id), ["IsEnabled", "Remark"],
                "\(typeName) の共通プロパティが先頭に無い"
            )
            XCTAssertEqual(
                Array(descriptors.dropFirst(2)).map(\.id), expectedIDs,
                "\(typeName) の固有パラメータ記述子が保存キーと一致しない"
            )
        }
    }

    func testDescriptorIDsAreUniquePerType() throws {
        for (typeName, _) in Self.expectedSpecificIDs {
            let definition = try XCTUnwrap(
                VideoEffectRegistry.makeEmptyDefinition(typeName: typeName)
            )
            let ids = EffectPropertyMetadata.descriptors(for: definition).map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, "\(typeName) で ID が重複している")
        }
    }

    func testExcludedKeysHaveNoDescriptors() throws {
        for (typeName, keys) in Self.excludedKeys {
            let definition = try XCTUnwrap(
                VideoEffectRegistry.makeEmptyDefinition(typeName: typeName)
            )
            let ids = Set(EffectPropertyMetadata.descriptors(for: definition).map(\.id))
            for key in keys {
                XCTAssertFalse(ids.contains(key), "\(typeName).\(key) は対象外のはず")
            }
        }
    }

    // MARK: - 往復

    func testDescriptorWriteThrough() throws {
        for (typeName, _) in Self.expectedSpecificIDs {
            let definition = try XCTUnwrap(
                VideoEffectRegistry.makeEmptyDefinition(typeName: typeName)
            )
            let descriptors = EffectPropertyMetadata.descriptors(for: definition)
            for descriptor in descriptors.dropFirst(2) {
                try exercise(descriptor, typeName: typeName)
            }
        }
    }

    private func exercise(_ descriptor: PropertyDescriptor, typeName: String) throws {
        let label = "\(typeName).\(descriptor.id)"
        switch descriptor.kind {
        case .number:
            let current = try XCTUnwrap(descriptor.numberValue, label)
            XCTAssertTrue(descriptor.setNumberValue(current + 1.5), label)
            XCTAssertEqual(descriptor.numberValue, current + 1.5, label)
        case .integer:
            let current = try XCTUnwrap(descriptor.integerValue, label)
            XCTAssertTrue(descriptor.setIntegerValue(current + 1), label)
            XCTAssertEqual(descriptor.integerValue, current + 1, label)
        case .boolean:
            let current = try XCTUnwrap(descriptor.boolValue, label)
            XCTAssertTrue(descriptor.setBoolValue(!current), label)
            XCTAssertEqual(descriptor.boolValue, !current, label)
        case .text:
            XCTAssertTrue(descriptor.setStringValue("fxmeta-test"), label)
            XCTAssertEqual(descriptor.stringValue, "fxmeta-test", label)
        case .enumeration(let options):
            let current = descriptor.stringValue
            guard let target = options.first(where: { $0.value != current }) else {
                return
            }
            XCTAssertTrue(descriptor.setStringValue(target.value), label)
            XCTAssertEqual(descriptor.stringValue, target.value, label)
        case .color:
            let probe = Color(alpha: 12, red: 34, green: 56, blue: 78)
            let target = descriptor.colorValue == probe
                ? Color(alpha: 87, red: 65, green: 43, blue: 21) : probe
            XCTAssertTrue(descriptor.setColorValue(target), label)
            XCTAssertEqual(descriptor.colorValue, target, label)
        case .animation:
            let animation = try XCTUnwrap(descriptor.animationValue, label)
            let target = animation.defaultValue == animation.minValue
                ? animation.maxValue : animation.minValue
            XCTAssertTrue(descriptor.setAnimationConstantValue(target), label)
            XCTAssertEqual(
                descriptor.animationValue?.values.first?.value, target, label
            )
        }
    }

    // MARK: - 既定値の健全性

    /// 全種別・全アニメーション記述子で、既定値が定義範囲内に収まる。
    func testAnimationDefaultsAreWithinRange() throws {
        for (typeName, _) in Self.expectedSpecificIDs {
            let definition = try XCTUnwrap(
                VideoEffectRegistry.makeEmptyDefinition(typeName: typeName)
            )
            for descriptor in EffectPropertyMetadata.descriptors(for: definition) {
                guard let animation = descriptor.animationValue else { continue }
                XCTAssertTrue(
                    animation.minValue <= animation.defaultValue
                        && animation.defaultValue <= animation.maxValue,
                    "\(typeName).\(descriptor.id) の既定値が範囲外"
                )
                XCTAssertEqual(
                    animation.values.first?.value, animation.defaultValue,
                    "\(typeName).\(descriptor.id) の初期値が既定値と異なる"
                )
            }
        }
    }
}
