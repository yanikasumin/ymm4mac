import XCTest
@testable import YMM4Core

/// FXMETA: 内蔵エフェクト定義のプロパティメタデータの網羅と往復の検証。
///
/// - 網羅: レジストリ登録の全95種について、保存キーのうち記述子化の
///   対象とした全キーに記述子が存在し、並びが保存形式のキー順と一致する。
/// - 往復: 記述子経由の書き込みが定義の実プロパティへ届き、読み戻せる。
/// - 複合: FXMETA で対象外だった複合プロパティ18件は、複合種別
///   （object / collection）の記述子で対象化する（FXMETA-COMP）。
///   子記述子経由の書き込みが保存 JSON へ反映され、未知の入れ子
///   キーが保持されることを確認する。
/// - 対象外: 記述子化しないのは、本家で固定値のダミー上書きになって
///   いる RepeatOpacity の IsCentering だけであり、記述子に現れない。
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
        ("YukkuriMovieMaker.Project.Effects.DisplacementMapEffect, YukkuriMovieMaker", ["Mode", "Transform", "Blur", "IsPatternMapPreviewEnabled", "Brush"]),
        ("YukkuriMovieMaker.Project.Effects.DrawLazyEffectEffect, YukkuriMovieMaker", ["IsXYZ", "IsOpacity", "IsZoom", "IsRotation", "IsInvert", "IsCamera"]),
        ("YukkuriMovieMaker.Project.Effects.DrawPositionEffect, YukkuriMovieMaker", ["X", "Y", "Z"]),
        ("YukkuriMovieMaker.Project.Effects.ExposureEffect, YukkuriMovieMaker", ["Value"]),
        ("YukkuriMovieMaker.Project.Effects.FillBackgroundEffect, YukkuriMovieMaker", ["Opacity", "Round", "BlendMode", "IsBackgroundOnly", "Brush", "Top", "Bottom", "Left", "Right"]),
        ("YukkuriMovieMaker.Project.Effects.FillForegroundEffect, YukkuriMovieMaker", ["Opacity", "BlendMode", "IsBrushOnly", "Brush"]),
        ("YukkuriMovieMaker.Project.Effects.FrameLineEffect, YukkuriMovieMaker", ["Opacity", "Thickness", "RenderPlacement", "Type", "Top", "Bottom", "Left", "Right", "Brush"]),
        ("YukkuriMovieMaker.Project.Effects.GammaCorrectionEffect, YukkuriMovieMaker", ["Gamma", "Red", "Green", "Blue"]),
        ("YukkuriMovieMaker.Project.Effects.GaussianBlurEffect, YukkuriMovieMaker", ["Blur", "IsHardBorderMode"]),
        ("YukkuriMovieMaker.Project.Effects.GradientEffect, YukkuriMovieMaker", ["GradientType", "Stops", "X", "Y", "Opacity", "Size", "Rotation", "ExtendMode", "Blend"]),
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
        ("YukkuriMovieMaker.Project.Effects.InnerShadowEffect, YukkuriMovieMaker", ["X", "Y", "Opacity", "Blur", "BlendMode", "Brush"]),
        ("YukkuriMovieMaker.Project.Effects.InvertEffect, YukkuriMovieMaker", []),
        ("YukkuriMovieMaker.Project.Effects.JumpEffect, YukkuriMovieMaker", ["JumpHeight", "Stretch", "Period", "Distortion", "Interval", "X", "Y"]),
        ("YukkuriMovieMaker.Project.Effects.LinearTransferEffect, YukkuriMovieMaker", ["RedYIntercept", "RedSlope", "GreenYIntercept", "GreenSlope", "BlueYIntercept", "BlueSlope", "AlphaYIntercept", "AlphaSlope"]),
        ("YukkuriMovieMaker.Project.Effects.MarginEffect, YukkuriMovieMaker", ["Top", "Bottom", "Left", "Right"]),
        ("YukkuriMovieMaker.Project.Effects.MaskEffect, YukkuriMovieMaker", ["X", "Y", "Opacity", "Angle", "ShapeType2", "ShapeParameter", "Blur", "InvertMask"]),
        ("YukkuriMovieMaker.Project.Effects.MeshDeformationEffect, YukkuriMovieMaker", ["HorizontalCount", "VerticalCount", "Smoothness", "Points"]),
        ("YukkuriMovieMaker.Project.Effects.MonocolorizationEffect, YukkuriMovieMaker", ["Strength", "Color", "KeepBrightness"]),
        ("YukkuriMovieMaker.Project.Effects.MorphologyEffect, YukkuriMovieMaker", ["Mode", "Width", "Height"]),
        ("YukkuriMovieMaker.Project.Effects.MosaicEffect, YukkuriMovieMaker", ["MosaicType", "MosaicParameter"]),
        ("YukkuriMovieMaker.Project.Effects.MotionTrackingEffect, YukkuriMovieMaker", ["Smooth", "IsReverce", "IsReverseZoom", "IsFixedSize", "Path", "ControlPointVisibleSeconds", "IsOnlyCurrentFrameRectLine"]),
        ("YukkuriMovieMaker.Project.Effects.NoiseColorShiftEffect, YukkuriMovieMaker", ["Mode", "Transform", "Blur", "NoiseType", "NoiseParameter"]),
        ("YukkuriMovieMaker.Project.Effects.NoiseDisplacementMapEffect, YukkuriMovieMaker", ["Mode", "Transform", "Blur", "NoiseType", "NoiseParameter"]),
        ("YukkuriMovieMaker.Project.Effects.NoiseEffect, YukkuriMovieMaker", ["NoiseType", "NoiseParameter", "IsColor", "IsAlpha", "IsUniqueSeed"]),
        ("YukkuriMovieMaker.Project.Effects.OpacityEffect, YukkuriMovieMaker", ["Opacity", "IsAbsolute"]),
        ("YukkuriMovieMaker.Project.Effects.OutlineEffect, YukkuriMovieMaker", ["StrokeThickness", "Blur", "Quality", "Smoothness", "X", "Y", "Opacity", "Zoom", "Rotation", "StrokeBrush", "IsOutlineOnly", "IsAngular"]),
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
        ("YukkuriMovieMaker.Project.Effects.ShadowEffect, YukkuriMovieMaker", ["X", "Y", "Opacity", "Zoom", "Angle", "Blur", "IsRotateAtCenter", "Brush"]),
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
    /// FXMETA で対象外だった複合プロパティ18件は FXMETA-COMP で
    /// 全て対象化した。残る対象外は、本家で固定値のダミー上書きに
    /// なっている RepeatOpacity の IsCentering だけである。
    /// 詳細は実装台帳（FXMETA / FXMETA-COMP）を参照。
    private static let excludedKeys: [(typeName: String, keys: [String])] = [
        ("YukkuriMovieMaker.Project.Effects.RepeatOpacityEffect, YukkuriMovieMaker", ["IsCentering"]),
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
        case .object:
            // 既定の定義では対象が未設定で子が空の場合もある。
            // 子の列が取得できることだけを確認する（中身の往復は
            // 複合プロパティ専用のテストで確認する）。
            XCTAssertNotNil(descriptor.children, label)
        case .collection:
            let count = try XCTUnwrap(descriptor.collectionCount, label)
            XCTAssertGreaterThanOrEqual(count, 0, label)
            if count > 0 {
                XCTAssertNotNil(descriptor.collectionElements(at: 0), label)
            }
        }
    }

    // MARK: - 複合プロパティ（FXMETA-COMP）

    /// 対象18件（種別 $type 名 → 複合キーの列）。FXMETA で対象外
    /// だった一覧と一致する。
    private static let compositeKeys: [(typeName: String, keys: [String])] = [
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
        ("YukkuriMovieMaker.Project.Effects.ShadowEffect, YukkuriMovieMaker", ["Brush"]),
    ]

    func testCompositeDescriptorsExistForAll18() throws {
        var total = 0
        for (typeName, keys) in Self.compositeKeys {
            let definition = try XCTUnwrap(
                VideoEffectRegistry.makeEmptyDefinition(typeName: typeName), typeName
            )
            let descriptors = EffectPropertyMetadata.descriptors(for: definition)
            for key in keys {
                let descriptor = try XCTUnwrap(
                    descriptors.first { $0.id == key }, "\(typeName).\(key)"
                )
                XCTAssertTrue(
                    descriptor.kind == .object || descriptor.kind == .collection,
                    "\(typeName).\(key) は複合種別のはず"
                )
                total += 1
            }
        }
        XCTAssertEqual(total, 18)
    }

    private func topDescriptor(
        _ definition: VideoEffectDefinitionBase, _ id: String
    ) throws -> PropertyDescriptor {
        try XCTUnwrap(
            EffectPropertyMetadata.descriptors(for: definition).first { $0.id == id }, id
        )
    }

    private func childDescriptor(
        _ descriptor: PropertyDescriptor, _ id: String
    ) throws -> PropertyDescriptor {
        let children = try XCTUnwrap(descriptor.children, descriptor.id)
        return try XCTUnwrap(
            children.first { $0.id == id }, "\(descriptor.id).\(id)"
        )
    }

    private func decodeDefinition(_ json: String) throws -> VideoEffectDefinitionBase {
        var parser = JSONParser(text: json)
        let value = try parser.parse()
        return try XCTUnwrap(VideoEffectRegistry.decode(PreservedObject(value)))
    }

    /// 型付きブラシ（単色）の色変更が保存 JSON へ届き、パラメータ内の
    /// 未知キーが保持される。
    func testTypedBrushSolidColorWriteThrough() throws {
        let definition = try decodeDefinition("""
            {
              "$type": "YukkuriMovieMaker.Project.Effects.ShadowEffect, YukkuriMovieMaker",
              "Brush": {
                "Type": "YukkuriMovieMaker.Plugin.Brush.SolidColorBrushPlugin, YukkuriMovieMaker",
                "Parameter": {
                  "$type": "YukkuriMovieMaker.Plugin.Brush.SolidColorBrushParameter, YukkuriMovieMaker",
                  "Color": "#FF000000",
                  "UnknownNested": 123.5
                }
              }
            }
            """)
        let brush = try topDescriptor(definition, "Brush")
        let color = try childDescriptor(brush, "Color")
        XCTAssertEqual(color.colorValue, Color(alpha: 255, red: 0, green: 0, blue: 0))
        XCTAssertTrue(color.setColorValue(Color(alpha: 255, red: 255, green: 0, blue: 0)))

        let encoded = VideoEffectRegistry.encode(definition).value
        let parameter = try XCTUnwrap(
            encoded.field("Brush")?.field("Parameter")
        )
        XCTAssertEqual(parameter.field("Color")?.stringValue, "#FFFF0000")
        XCTAssertEqual(parameter.field("UnknownNested")?.doubleValue, 123.5)
    }

    /// 型付きブラシ（線形グラデーション）の Stops 追加・削除と
    /// Offset 変更が保存 JSON へ届く。
    func testTypedBrushLinearGradientStopsWriteThrough() throws {
        let definition = try XCTUnwrap(
            VideoEffectRegistry.makeEmptyDefinition(
                typeName: "YukkuriMovieMaker.Project.Effects.FillBackgroundEffect, YukkuriMovieMaker"
            )
        )
        let fill = try XCTUnwrap(definition as? FillBackgroundEffectDefinition)
        let brush = Brush()
        brush.type = "YukkuriMovieMaker.Plugin.Brush.LinearGradientBrushPlugin, YukkuriMovieMaker"
        brush.parameter = .linearGradient(LinearGradientBrushParameter())
        fill.brush = brush

        let brushDescriptor = try topDescriptor(definition, "Brush")
        let stops = try childDescriptor(brushDescriptor, "Stops")
        XCTAssertEqual(stops.collectionCount, 2)

        let firstElement = try XCTUnwrap(stops.collectionElements(at: 0))
        let offset = try XCTUnwrap(firstElement.first { $0.id == "Offset" })
        XCTAssertTrue(offset.setNumberValue(0.25))
        XCTAssertTrue(stops.insertCollectionElement())
        XCTAssertEqual(stops.collectionCount, 3)
        XCTAssertTrue(stops.removeCollectionElement(at: 2))
        XCTAssertEqual(stops.collectionCount, 2)

        let encoded = VideoEffectRegistry.encode(definition).value
        let stopsJSON = try XCTUnwrap(
            encoded.field("Brush")?.field("Parameter")?.field("Stops")?.arrayValue
        )
        XCTAssertEqual(stopsJSON.count, 2)
        XCTAssertEqual(stopsJSON[0].field("Offset")?.doubleValue, 0.25)
        XCTAssertEqual(stopsJSON[1].field("Offset")?.doubleValue, 1)
    }

    /// 型付き MosaicParameter の Size 変更が保存 JSON へ届き、
    /// パラメータ内の未知キーが保持される。
    func testMosaicParameterWriteThrough() throws {
        let definition = try decodeDefinition("""
            {
              "$type": "YukkuriMovieMaker.Project.Effects.MosaicEffect, YukkuriMovieMaker",
              "MosaicType": "Rectangle",
              "MosaicParameter": {
                "$type": "YukkuriMovieMaker.Project.Effects.MosaicParameters.RectangleMosaicParameter, YukkuriMovieMaker",
                "Size": { "Values": [{ "Value": 10.0 }], "Span": 0.0, "AnimationType": "なし" },
                "UnknownNested": "keep"
              }
            }
            """)
        let parameter = try topDescriptor(definition, "MosaicParameter")
        let size = try childDescriptor(parameter, "Size")
        XCTAssertEqual(size.animationValue?.values.first?.value, 10)
        XCTAssertTrue(size.setAnimationConstantValue(42))

        let encoded = VideoEffectRegistry.encode(definition).value
        let parameterJSON = try XCTUnwrap(encoded.field("MosaicParameter"))
        XCTAssertEqual(
            parameterJSON.field("Size")?.field("Values")?.arrayValue?.first?
                .field("Value")?.doubleValue,
            42
        )
        XCTAssertEqual(parameterJSON.field("UnknownNested")?.stringValue, "keep")
    }

    /// Gradient の Stops の Offset 変更と追加・削除が保存 JSON へ届く。
    func testGradientStopsWriteThrough() throws {
        let definition = try XCTUnwrap(
            VideoEffectRegistry.makeEmptyDefinition(
                typeName: "YukkuriMovieMaker.Project.Effects.GradientEffect, YukkuriMovieMaker"
            )
        )
        let stops = try topDescriptor(definition, "Stops")
        XCTAssertEqual(stops.collectionCount, 2)
        let firstElement = try XCTUnwrap(stops.collectionElements(at: 0))
        let offset = try XCTUnwrap(firstElement.first { $0.id == "Offset" })
        XCTAssertTrue(offset.setNumberValue(0.4))
        XCTAssertTrue(stops.insertCollectionElement())
        XCTAssertEqual(stops.collectionCount, 3)
        XCTAssertTrue(stops.removeCollectionElement(at: 0))
        XCTAssertEqual(stops.collectionCount, 2)

        let encoded = VideoEffectRegistry.encode(definition).value
        let stopsJSON = try XCTUnwrap(encoded.field("Stops")?.arrayValue)
        XCTAssertEqual(stopsJSON.count, 2)
        XCTAssertEqual(stopsJSON[0].field("Offset")?.doubleValue, 1)
    }

    /// MeshDeformation の Points の X 変更と選択切替が保存 JSON へ
    /// 届き、点内の未知キーが保持される。
    func testMeshPointsWriteThrough() throws {
        let definition = try decodeDefinition("""
            {
              "$type": "YukkuriMovieMaker.Project.Effects.MeshDeformationEffect, YukkuriMovieMaker",
              "Points": [
                {
                  "X": { "Values": [{ "Value": 0.0 }], "Span": 0.0, "AnimationType": "なし" },
                  "Y": { "Values": [{ "Value": 0.0 }], "Span": 0.0, "AnimationType": "なし" },
                  "IsSelected": false,
                  "UnknownNested": true
                }
              ]
            }
            """)
        let points = try topDescriptor(definition, "Points")
        XCTAssertEqual(points.collectionCount, 1)
        let element = try XCTUnwrap(points.collectionElements(at: 0))
        let x = try XCTUnwrap(element.first { $0.id == "X" })
        XCTAssertTrue(x.setAnimationConstantValue(30))
        let isSelected = try XCTUnwrap(element.first { $0.id == "IsSelected" })
        XCTAssertTrue(isSelected.setBoolValue(true))

        let encoded = VideoEffectRegistry.encode(definition).value
        let pointsJSON = try XCTUnwrap(encoded.field("Points")?.arrayValue)
        XCTAssertEqual(pointsJSON.count, 1)
        XCTAssertEqual(
            pointsJSON[0].field("X")?.field("Values")?.arrayValue?.first?
                .field("Value")?.doubleValue,
            30
        )
        XCTAssertEqual(pointsJSON[0].field("IsSelected")?.boolValue, true)
        XCTAssertEqual(pointsJSON[0].field("UnknownNested")?.boolValue, true)
    }

    /// 生保持の複合（NoiseParameter）: $type と未知フィールドを含む
    /// JSON から開き、数値フィールドと Animation フィールドを
    /// 書き換えて往復し、未知フィールドが残る。
    func testRawNoiseParameterWriteThrough() throws {
        let definition = try decodeDefinition("""
            {
              "$type": "YukkuriMovieMaker.Project.Effects.NoiseEffect, YukkuriMovieMaker",
              "NoiseType": "Fractal",
              "NoiseParameter": {
                "$type": "YukkuriMovieMaker.Project.Effects.NoiseParameters.FractalNoiseParameter, YukkuriMovieMaker",
                "Strength": { "Values": [{ "Value": 100.0, "UnknownExtension": 42.0 }], "Span": 0.0, "AnimationType": "なし", "FutureKey": "keep" },
                "CustomNumber": 3.25,
                "UnknownText": "keep-me"
              }
            }
            """)
        let parameter = try topDescriptor(definition, "NoiseParameter")
        let children = try XCTUnwrap(parameter.children)
        // $type は型判別子であり子に現れない。
        XCTAssertFalse(children.contains { $0.id == "$type" })

        let number = try childDescriptor(parameter, "CustomNumber")
        XCTAssertEqual(number.numberValue, 3.25)
        XCTAssertTrue(number.setNumberValue(7.5))
        let strength = try childDescriptor(parameter, "Strength")
        XCTAssertEqual(strength.kind, .animation)
        XCTAssertTrue(strength.setAnimationConstantValue(55))

        let encoded = VideoEffectRegistry.encode(definition).value
        let parameterJSON = try XCTUnwrap(encoded.field("NoiseParameter"))
        XCTAssertEqual(
            parameterJSON.field("$type")?.stringValue,
            "YukkuriMovieMaker.Project.Effects.NoiseParameters.FractalNoiseParameter, YukkuriMovieMaker"
        )
        XCTAssertEqual(parameterJSON.field("CustomNumber")?.doubleValue, 7.5)
        XCTAssertEqual(
            parameterJSON.field("Strength")?.field("Values")?.arrayValue?.first?
                .field("Value")?.doubleValue,
            55
        )
        // Values 要素内の未知キーと、アニメーション自体の未知キーも
        // 編集で失われない（R21-117-01）。
        XCTAssertEqual(
            parameterJSON.field("Strength")?.field("Values")?.arrayValue?.first?
                .field("UnknownExtension")?.doubleValue,
            42
        )
        XCTAssertEqual(
            parameterJSON.field("Strength")?.field("FutureKey")?.stringValue, "keep"
        )
        XCTAssertEqual(parameterJSON.field("UnknownText")?.stringValue, "keep-me")
    }

    /// グラデーションメッシュ: 格子点の追加・削除と寸法変更が、
    /// 常に points.count == 横 × 縦 を保つ（R21-117-02）。追加は
    /// 末尾へ1行、削除は対象要素を含む1行、寸法変更は既存の点を
    /// (行, 列) の位置で保持する。
    func testGradientMeshGridInvariantThroughDescriptors() throws {
        let definition = try decodeDefinition("""
            {
              "$type": "YukkuriMovieMaker.Project.Effects.ShadowEffect, YukkuriMovieMaker",
              "Brush": {
                "Type": "YukkuriMovieMaker.Plugin.Brush.GradientMeshBrushPlugin, YukkuriMovieMaker",
                "Parameter": {
                  "$type": "YukkuriMovieMaker.Brush.GradientMeshBrushParameter, YukkuriMovieMaker",
                  "HorizontalCount": 2,
                  "VerticalCount": 2,
                  "Points": [
                    { "Color": "#FFFF0000" },
                    { "Color": "#FF00FF00" },
                    { "Color": "#FF0000FF" },
                    { "Color": "#FFFFFF00" }
                  ]
                }
              }
            }
            """)
        let brush = try topDescriptor(definition, "Brush")
        let points = try childDescriptor(brush, "Points")
        XCTAssertEqual(points.collectionCount, 4)

        // 追加は1行分（横の個数だけ）増える。
        XCTAssertTrue(points.insertCollectionElement())
        XCTAssertEqual(points.collectionCount, 6)
        var encoded = VideoEffectRegistry.encode(definition).value
        var parameterJSON = try XCTUnwrap(
            encoded.field("Brush")?.field("Parameter")
        )
        XCTAssertEqual(parameterJSON.field("VerticalCount")?.doubleValue, 3)
        XCTAssertEqual(
            parameterJSON.field("Points")?.arrayValue?.count, 6
        )

        // 先頭行の要素を削除すると、その行ごと取り除かれる。
        XCTAssertTrue(points.removeCollectionElement(at: 0))
        XCTAssertEqual(points.collectionCount, 4)
        encoded = VideoEffectRegistry.encode(definition).value
        parameterJSON = try XCTUnwrap(encoded.field("Brush")?.field("Parameter"))
        XCTAssertEqual(parameterJSON.field("VerticalCount")?.doubleValue, 2)
        let colors = try XCTUnwrap(
            parameterJSON.field("Points")?.arrayValue
        ).map { $0.field("Color")?.stringValue }
        XCTAssertEqual(
            colors, ["#FF0000FF", "#FFFFFF00", "#FFFFFFFF", "#FFFFFFFF"]
        )

        // 横の寸法を広げると、既存の点は (行, 列) の位置に残る。
        let horizontal = try childDescriptor(brush, "HorizontalCount")
        XCTAssertTrue(horizontal.setIntegerValue(3))
        encoded = VideoEffectRegistry.encode(definition).value
        parameterJSON = try XCTUnwrap(encoded.field("Brush")?.field("Parameter"))
        XCTAssertEqual(parameterJSON.field("HorizontalCount")?.doubleValue, 3)
        let widened = try XCTUnwrap(
            parameterJSON.field("Points")?.arrayValue
        ).map { $0.field("Color")?.stringValue }
        XCTAssertEqual(widened.count, 6)
        XCTAssertEqual(widened[0], "#FF0000FF")
        XCTAssertEqual(widened[1], "#FFFFFF00")
    }

    /// 生保持のブラシ形（{Type, Parameter}）: 子は Parameter の中から
    /// 生成され、書き換えは Parameter の中へ届く。
    func testRawBrushParameterWriteThrough() throws {
        let definition = try decodeDefinition("""
            {
              "$type": "YukkuriMovieMaker.Project.Effects.DisplacementMapEffect, YukkuriMovieMaker",
              "Brush": {
                "Type": "YukkuriMovieMaker.Plugin.Brush.SolidColorBrushPlugin, YukkuriMovieMaker",
                "Parameter": {
                  "$type": "YukkuriMovieMaker.Plugin.Brush.SolidColorBrushParameter, YukkuriMovieMaker",
                  "Color": "#FF102030",
                  "UnknownNested": 9.0
                }
              }
            }
            """)
        let brush = try topDescriptor(definition, "Brush")
        let color = try childDescriptor(brush, "Color")
        XCTAssertEqual(color.kind, .color)
        XCTAssertTrue(color.setColorValue(Color(alpha: 255, red: 0xAA, green: 0xBB, blue: 0xCC)))

        let encoded = VideoEffectRegistry.encode(definition).value
        let parameterJSON = try XCTUnwrap(
            encoded.field("Brush")?.field("Parameter")
        )
        XCTAssertEqual(parameterJSON.field("Color")?.stringValue, "#FFAABBCC")
        XCTAssertEqual(parameterJSON.field("UnknownNested")?.doubleValue, 9.0)
        XCTAssertEqual(
            encoded.field("Brush")?.field("Type")?.stringValue,
            "YukkuriMovieMaker.Plugin.Brush.SolidColorBrushPlugin, YukkuriMovieMaker"
        )
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
