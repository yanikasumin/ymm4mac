import XCTest
@testable import YMM4Core

// GPU 処理系エフェクトの定義層（パラメータ型付け）のテスト。
//
// 処理器は次段の GPU 実装までの暫定の素通しであり、ここでは
// (1) 全定義がレジストリ経由で型付き復元できること、
// (2) 型付き復元 → 保存 → 型付き復元 → 保存 が固定点になること、
// (3) 非既定値が往復で保たれること、
// (4) 処理器が入力と DrawDescription を素通しすること、
// を確認する。

// MARK: - ヘルパー

/// Animation の保存形式（実ファイルの形: Values / Span / AnimationType）。
private func animJSON(values: [Double], span: Double = 0, type: String = "なし") -> JSONValue {
    .object([
        (key: "Values", value: .array(values.map {
            .object([(key: "Value", value: .number($0))])
        })),
        (key: "Span", value: .number(span)),
        (key: "AnimationType", value: .string(type)),
    ])
}

/// 型付き復元 → 保存 → 型付き復元 → 保存 が固定点になることを確認する。
private func assertFixedPoint(
    _ definition: VideoEffectDefinitionBase,
    file: StaticString = #filePath, line: UInt = #line
) {
    let once = VideoEffectRegistry.encode(definition).value
    guard let decoded = VideoEffectRegistry.decode(PreservedObject(once)) else {
        XCTFail("固定点確認用の再復元に失敗した", file: file, line: line)
        return
    }
    let twice = VideoEffectRegistry.encode(decoded).value
    XCTAssertEqual(once, twice, file: file, line: line)
}

/// $type のみのオブジェクトから型付き復元する。
private func decodeBare(_ typeName: String) -> VideoEffectDefinitionBase? {
    VideoEffectRegistry.decode(PreservedObject(.object([
        (key: "$type", value: .string(typeName)),
    ])))
}

/// 任意のフィールドを持つオブジェクトから型付き復元する。
private func decodeFields(
    _ typeName: String, _ fields: [(key: String, value: JSONValue)]
) -> VideoEffectDefinitionBase? {
    VideoEffectRegistry.decode(PreservedObject(.object(
        [(key: "$type", value: .string(typeName))] + fields
    )))
}

// MARK: - レジストリ登録の完全性

final class GPUEffectRegistryTests: XCTestCase {

    /// 今回登録した GPU 処理系の定義（73 種）。
    static let gpuTypeNames: [String] = [
        ArcBendEffectDefinition.typeName,
        AutomaticZoomEffectDefinition.typeName,
        CenterPointEffectDefinition.typeName,
        CopyAndReverseEffectDefinition.typeName,
        CropByAngleEffectDefinition.typeName,
        CropEffectDefinition.typeName,
        MarginEffectDefinition.typeName,
        PolarTransformEffectDefinition.typeName,
        RotateEffectDefinition.typeName,
        RoundCornerEffectDefinition.typeName,
        SkewEffectDefinition.typeName,
        TilingEffectDefinition.typeName,
        CircularDuplicatorEffectDefinition.typeName,
        RandomDuplicatorEffectDefinition.typeName,
        BorderBlurEffectDefinition.typeName,
        DirectionalBlurEffectDefinition.typeName,
        GaussianBlurEffectDefinition.typeName,
        RadialBlurEffectDefinition.typeName,
        SharpenEffectDefinition.typeName,
        MosaicEffectDefinition.typeName,
        HalfToneBorderBlurEffectDefinition.typeName,
        HalfToneEffectDefinition.typeName,
        HalfToneOutlineEffectDefinition.typeName,
        HalfToneShadowEffectDefinition.typeName,
        InnerHalfToneShadowEffectDefinition.typeName,
        RadialLightEffectDefinition.typeName,
        ChromaticAberrationEffectDefinition.typeName,
        ExposureEffectDefinition.typeName,
        GammaCorrectionEffectDefinition.typeName,
        HightlightsAndShadowsEffectDefinition.typeName,
        InvertEffectDefinition.typeName,
        LinearTransferEffectDefinition.typeName,
        MonocolorizationEffectDefinition.typeName,
        PosterizeEffectDefinition.typeName,
        SepiaEffectDefinition.typeName,
        TintEffectDefinition.typeName,
        NoiseColorShiftEffectDefinition.typeName,
        OutlineEffectDefinition.typeName,
        ShadowEffectDefinition.typeName,
        InnerShadowEffectDefinition.typeName,
        FillBackgroundEffectDefinition.typeName,
        FillForegroundEffectDefinition.typeName,
        FrameLineEffectDefinition.typeName,
        GradientEffectDefinition.typeName,
        TextureEffectDefinition.typeName,
        BackgroundImageEffectDefinition.typeName,
        CrashEffectDefinition.typeName,
        DisplacementMapEffectDefinition.typeName,
        MeshDeformationEffectDefinition.typeName,
        NoiseDisplacementMapEffectDefinition.typeName,
        NoiseEffectDefinition.typeName,
        MorphologyEffectDefinition.typeName,
        DrawLazyEffectEffectDefinition.typeName,
        JumpEffectDefinition.typeName,
        ChromaKeyEffectDefinition.typeName,
        ChromaKeyEffect2Definition.typeName,
        MaskEffectDefinition.typeName,
        InOutBorderBlurEffectDefinition.typeName,
        InOutGaussianBlurEffectDefinition.typeName,
        InOutMosaicEffectDefinition.typeName,
        InOutMoveFromOutsideImageEffectDefinition.typeName,
        InOutGetUpEffectDefinition.typeName,
        InOutRotateEffectDefinition.typeName,
        InOutSkewEffectDefinition.typeName,
        InOutCrashEffectDefinition.typeName,
        InOutJumpEffectDefinition.typeName,
        InOutTransitionEffectDefinition.typeName,
        RandomRotateEffectDefinition.typeName,
        RandomSkewEffectDefinition.typeName,
        RepeatRotateEffectDefinition.typeName,
        RepeatSkewEffectDefinition.typeName,
        HlslPixelShaderCodeEffectDefinition.typeName,
        HlslPixelShaderFileEffectDefinition.typeName,
    ]

    func testAllGPUEffectTypeNamesDecode() {
        XCTAssertEqual(Self.gpuTypeNames.count, 73)
        XCTAssertEqual(Set(Self.gpuTypeNames).count, 73)
        for typeName in Self.gpuTypeNames {
            let decoded = decodeBare(typeName)
            XCTAssertNotNil(decoded, typeName)
            XCTAssertTrue(VideoEffectRegistry.isKnown(typeName: typeName), typeName)
            guard let decoded else { continue }
            XCTAssertEqual(
                VideoEffectRegistry.encode(decoded).value.field("$type")?.stringValue, typeName
            )
            // 既定値だけの定義も往復で固定点になる（キー欠落・型崩れの検出）。
            assertFixedPoint(decoded)
        }
    }

    /// コミュニティ側の型名は引き続き未知（生保持）のままであること。
    func testCommunityTypesStillUnknown() {
        for typeName in [
            "YukkuriMovieMaker.Community.Effects.ScalingLoupeEffect, YukkuriMovieMaker.Community",
            "YukkuriMovieMaker.Project.Effects.WaveEffect, YukkuriMovieMaker",
        ] {
            XCTAssertNil(decodeBare(typeName), typeName)
            XCTAssertFalse(VideoEffectRegistry.isKnown(typeName: typeName), typeName)
        }
    }
}

// MARK: - 値の保持（代表例）

final class GPUEffectValuePreservationTests: XCTestCase {

    func testRotateValues() {
        let decoded = decodeFields(RotateEffectDefinition.typeName, [
            (key: "X", value: animJSON(values: [10, 20], span: 0.5)),
            (key: "Y", value: animJSON(values: [-5])),
            (key: "Z", value: animJSON(values: [90])),
            (key: "Is3D", value: .bool(true)),
            (key: "IsEnabled", value: .bool(false)),
            (key: "Remark", value: .string("メモ")),
        ]) as? RotateEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.x.values.map { $0.value }, [10, 20])
        XCTAssertEqual(decoded.x.span, 0.5)
        XCTAssertEqual(decoded.y.values.map { $0.value }, [-5])
        XCTAssertEqual(decoded.z.values.map { $0.value }, [90])
        XCTAssertTrue(decoded.is3D)
        XCTAssertFalse(decoded.isEnabled)
        XCTAssertEqual(decoded.remark, "メモ")
        assertFixedPoint(decoded)
    }

    func testUnknownFieldsArePreserved() {
        let decoded = decodeFields(RotateEffectDefinition.typeName, [
            (key: "SomeFutureKey", value: .number(42)),
        ]) as? RotateEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.additionalFields.count, 1)
        XCTAssertEqual(decoded.additionalFields.first?.key, "SomeFutureKey")
        let encoded = VideoEffectRegistry.encode(decoded).value
        XCTAssertEqual(encoded.field("SomeFutureKey"), .number(42))
        assertFixedPoint(decoded)
    }

    func testKeyOrderMatchesHonkeDeclaration() {
        let encoded = VideoEffectRegistry.encode(RotateEffectDefinition()).value
        XCTAssertEqual(
            encoded.objectFields?.map { $0.key },
            ["$type", "X", "Y", "Z", "Is3D", "IsEnabled"]
        )
    }

    func testAutomaticZoomEnumsAndMargins() {
        let decoded = decodeFields(AutomaticZoomEffectDefinition.typeName, [
            (key: "AutomaticZoomMode", value: .string("UpOnly")),
            (key: "AutomaticZoomTarget", value: .string("WidthOnly")),
            (key: "AutomaticZoomMarginTop", value: animJSON(values: [12])),
            (key: "IgnoreRotation", value: .bool(true)),
        ]) as? AutomaticZoomEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.automaticZoomMode, .upOnly)
        XCTAssertEqual(decoded.automaticZoomTarget, .widthOnly)
        XCTAssertEqual(decoded.automaticZoomMarginTop.values.map { $0.value }, [12])
        XCTAssertTrue(decoded.ignoreRotation)
        assertFixedPoint(decoded)
    }

    /// 未知の列挙名は原文のまま保持される（データ保全）。
    func testUnknownEnumNameIsPreserved() {
        let decoded = decodeFields(AutomaticZoomEffectDefinition.typeName, [
            (key: "AutomaticZoomMode", value: .string("FutureMode")),
        ]) as? AutomaticZoomEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.automaticZoomMode, .unknown("FutureMode"))
        let encoded = VideoEffectRegistry.encode(decoded).value
        XCTAssertEqual(encoded.field("AutomaticZoomMode")?.stringValue, "FutureMode")
        assertFixedPoint(decoded)
    }

    func testHalfToneColorAndLayout() {
        let decoded = decodeFields(HalfToneEffectDefinition.typeName, [
            (key: "Layout", value: .string("Triangle")),
            (key: "Color", value: .string("#FF102030")),
            (key: "Distance", value: animJSON(values: [7.5])),
        ]) as? HalfToneEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.layout, .triangle)
        XCTAssertEqual(decoded.color, Color(alpha: 255, red: 16, green: 32, blue: 48))
        XCTAssertEqual(decoded.distance.values.map { $0.value }, [7.5])
        assertFixedPoint(decoded)
    }

    func testGradientStops() {
        let decoded = decodeFields(GradientEffectDefinition.typeName, [
            (key: "Stops", value: .array([
                .object([
                    (key: "Offset", value: .number(0.25)),
                    (key: "Color", value: .string("#FFAA0000")),
                ]),
                .object([
                    (key: "Offset", value: .number(0.75)),
                    (key: "Color", value: .string("#FF0000BB")),
                ]),
            ])),
            (key: "GradientType", value: .string("Round")),
            (key: "Blend", value: .string("Screen")),
        ]) as? GradientEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.stops.count, 2)
        XCTAssertEqual(decoded.stops[0].offset, 0.25)
        XCTAssertEqual(decoded.stops[0].color, Color(alpha: 255, red: 170, green: 0, blue: 0))
        XCTAssertEqual(decoded.stops[1].color, Color(alpha: 255, red: 0, green: 0, blue: 187))
        XCTAssertEqual(decoded.gradientType, .round)
        XCTAssertEqual(decoded.blend, .screen)
        assertFixedPoint(decoded)
    }

    func testRawBrushAndTransformArePreservedVerbatim() {
        let brush: JSONValue = .object([
            (key: "$type", value: .string("YukkuriMovieMaker.Brush.SolidColorBrush, YukkuriMovieMaker")),
            (key: "Color", value: .string("#FF010203")),
        ])
        let decoded = decodeFields(OutlineEffectDefinition.typeName, [
            (key: "StrokeThickness", value: animJSON(values: [9])),
            (key: "StrokeBrush", value: brush),
        ]) as? OutlineEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.strokeThickness.values.map { $0.value }, [9])
        XCTAssertEqual(decoded.strokeBrush?.value, brush)
        let encoded = VideoEffectRegistry.encode(decoded).value
        XCTAssertEqual(encoded.field("StrokeBrush"), brush)
        assertFixedPoint(decoded)
    }

    func testMosaicRawParameterPreserved() {
        let parameter: JSONValue = .object([
            (key: "$type", value: .string("YukkuriMovieMaker.Plugin.Effects.RectangleMosaicParameter, YukkuriMovieMaker")),
            (key: "Size", value: .number(12)),
        ])
        let decoded = decodeFields(MosaicEffectDefinition.typeName, [
            (key: "MosaicType", value: .string("Hexagon")),
            (key: "MosaicParameter", value: parameter),
        ]) as? MosaicEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.mosaicType, .hexagon)
        // 組み込み6形状でない $type は型付き化せず生保持する。
        guard case .preserved(let preserved) = decoded.mosaicParameter else {
            XCTFail("未知のモザイクパラメータは生保持されるはず")
            return
        }
        XCTAssertEqual(preserved.value, parameter)
        assertFixedPoint(decoded)
    }

    /// 組み込み6形状のパラメータが型付き化され、Size が往復で保たれる。
    func testMosaicTypedParametersRoundTrip() {
        let shapes: [(MosaicType, String)] = [
            (.rectangle, "RectangleMosaicParameter"),
            (.circle, "CircleMosaicParameter"),
            (.triangle, "TriangleMosaicParameter"),
            (.hexagon, "HexagonMosaicParameter"),
            (.delaunay, "DelaunayMosaicParameter"),
            (.voronoi, "VoronoiMosaicParameter"),
        ]
        for (shape, typeSuffix) in shapes {
            let typeName = "YukkuriMovieMaker.Project.Effects.MosaicParameters."
                + typeSuffix + ", YukkuriMovieMaker"
            let parameter: JSONValue = .object([
                (key: "$type", value: .string(typeName)),
                (key: "Size", value: animJSON(values: [1, 10], type: "直線移動")),
            ])
            let decoded = decodeFields(MosaicEffectDefinition.typeName, [
                (key: "MosaicType", value: .string(shape.honkeName)),
                (key: "MosaicParameter", value: parameter),
            ]) as? MosaicEffectDefinition
            XCTAssertNotNil(decoded, typeSuffix)
            guard let decoded, case .sized(let sized) = decoded.mosaicParameter else {
                XCTFail("\(typeSuffix) は型付き化されるはず")
                continue
            }
            XCTAssertEqual(sized.shape, shape, typeSuffix)
            XCTAssertEqual(sized.size.values.map { $0.value }, [1, 10], typeSuffix)
            XCTAssertEqual(sized.size.animationType, .linear, typeSuffix)
            assertFixedPoint(decoded)
        }
    }

    /// Size のベジェが復元される（従来の部分復元では失われていた）。
    func testMosaicSizeBezierPreserved() {
        let size: JSONValue = .object([
            (key: "Values", value: .array([
                .object([(key: "Value", value: .number(5))]),
                .object([(key: "Value", value: .number(50))]),
            ])),
            (key: "Span", value: .number(0)),
            (key: "AnimationType", value: .string("Linear_Bezier")),
            (key: "Bezier", value: .object([
                (key: "Points", value: .array([
                    .object([
                        (key: "Point", value: .object([
                            (key: "X", value: .number(0)), (key: "Y", value: .number(0)),
                        ])),
                        (key: "ControlPoint1", value: .object([
                            (key: "X", value: .number(30)), (key: "Y", value: .number(10)),
                        ])),
                        (key: "ControlPoint2", value: .object([
                            (key: "X", value: .number(70)), (key: "Y", value: .number(90)),
                        ])),
                    ]),
                    .object([
                        (key: "Point", value: .object([
                            (key: "X", value: .number(100)), (key: "Y", value: .number(100)),
                        ])),
                        (key: "ControlPoint1", value: .object([
                            (key: "X", value: .number(100)), (key: "Y", value: .number(100)),
                        ])),
                        (key: "ControlPoint2", value: .object([
                            (key: "X", value: .number(100)), (key: "Y", value: .number(100)),
                        ])),
                    ]),
                ])),
                (key: "IsQuadratic", value: .bool(false)),
            ])),
        ])
        let parameter: JSONValue = .object([
            (key: "$type", value: .string(
                "YukkuriMovieMaker.Project.Effects.MosaicParameters.CircleMosaicParameter, YukkuriMovieMaker")),
            (key: "Size", value: size),
        ])
        let decoded = decodeFields(MosaicEffectDefinition.typeName, [
            (key: "MosaicType", value: .string("Circle")),
            (key: "MosaicParameter", value: parameter),
        ]) as? MosaicEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded, case .sized(let sized) = decoded.mosaicParameter else {
            XCTFail("CircleMosaicParameter は型付き化されるはず")
            return
        }
        XCTAssertEqual(sized.size.bezier.points.count, 2)
        XCTAssertEqual(sized.size.bezier.points.first?.controlPoint1.x, 30)
        XCTAssertEqual(sized.size.bezier.points.first?.controlPoint2.y, 90)
        assertFixedPoint(decoded)
    }

    /// アイテムのキーフレーム文脈が Size へ伝播する（本家の
    /// GetAnimatables 経由の連動）。
    func testMosaicKeyFramesPropagateToSize() {
        let parameter: JSONValue = .object([
            (key: "$type", value: .string(
                "YukkuriMovieMaker.Project.Effects.MosaicParameters.RectangleMosaicParameter, YukkuriMovieMaker")),
            (key: "Size", value: animJSON(values: [1, 10], type: "直線移動")),
        ])
        let decoded = decodeFields(MosaicEffectDefinition.typeName, [
            (key: "MosaicType", value: .string("Rectangle")),
            (key: "MosaicParameter", value: parameter),
        ]) as? MosaicEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded, case .sized(let sized) = decoded.mosaicParameter else {
            XCTFail("RectangleMosaicParameter は型付き化されるはず")
            return
        }
        XCTAssertEqual(sized.size.keyFrames.frames, [])
        decoded.setKeyFrames(KeyFrames(frames: [15, 45]))
        XCTAssertEqual(sized.size.keyFrames.frames, [15, 45])
    }

    func testNoiseDefaultsAndValues() {
        let bare = decodeBare(NoiseEffectDefinition.typeName) as? NoiseEffectDefinition
        XCTAssertNotNil(bare)
        XCTAssertEqual(bare?.noiseType, .fractal)
        XCTAssertEqual(bare?.isAlpha, true)
        XCTAssertEqual(bare?.isColor, false)

        let decoded = decodeFields(NoiseEffectDefinition.typeName, [
            (key: "NoiseType", value: .string("Simplex")),
            (key: "IsColor", value: .bool(true)),
        ]) as? NoiseEffectDefinition
        XCTAssertEqual(decoded?.noiseType, .simplex)
        XCTAssertEqual(decoded?.isColor, true)
        assertFixedPoint(decoded!)
    }

    func testMeshDeformationPoints() {
        let decoded = decodeFields(MeshDeformationEffectDefinition.typeName, [
            (key: "HorizontalCount", value: .number(3)),
            (key: "Points", value: .array([
                .object([
                    (key: "X", value: animJSON(values: [5])),
                    (key: "Y", value: animJSON(values: [-5])),
                    (key: "IsSelected", value: .bool(true)),
                ]),
            ])),
        ]) as? MeshDeformationEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.horizontalCount, 3)
        XCTAssertEqual(decoded.points.count, 1)
        XCTAssertEqual(decoded.points[0].x.values.map { $0.value }, [5])
        XCTAssertEqual(decoded.points[0].y.values.map { $0.value }, [-5])
        XCTAssertTrue(decoded.points[0].isSelected)
        assertFixedPoint(decoded)
    }

    func testCrashDoubles() {
        let decoded = decodeFields(InOutCrashEffectDefinition.typeName, [
            (key: "EffectTimeSeconds", value: .number(1.5)),
            (key: "IsInEffect", value: .bool(false)),
            (key: "Size", value: .number(75)),
        ]) as? InOutCrashEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.effectTimeSeconds, 1.5)
        XCTAssertFalse(decoded.isInEffect)
        XCTAssertEqual(decoded.size, 75)
        assertFixedPoint(decoded)
    }

    func testInOutJumpDefaults() {
        let bare = decodeBare(InOutJumpEffectDefinition.typeName) as? InOutJumpEffectDefinition
        XCTAssertNotNil(bare)
        XCTAssertEqual(bare?.x, 1000)
        XCTAssertEqual(bare?.stretch, 10)
        XCTAssertEqual(bare?.isOutReverse, true)
        XCTAssertEqual(bare?.isInReverse, false)
    }

    func testInOutTransitionFileAndEasing() {
        let bare = decodeBare(InOutTransitionEffectDefinition.typeName)
            as? InOutTransitionEffectDefinition
        XCTAssertNotNil(bare)
        XCTAssertNil(bare?.file)
        XCTAssertEqual(bare?.easingFamily, .linear)
        XCTAssertEqual(bare?.easingMode, .inOut)

        let decoded = decodeFields(InOutTransitionEffectDefinition.typeName, [
            (key: "File", value: .string("C:\\rule.png")),
            (key: "EasingType", value: .string("Cubic")),
            (key: "EasingMode", value: .string("Out")),
            (key: "Tolerance", value: animJSON(values: [120])),
        ]) as? InOutTransitionEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.file, "C:\\rule.png")
        XCTAssertEqual(decoded.easingFamily, .cubic)
        XCTAssertEqual(decoded.easingMode, .out)
        XCTAssertEqual(decoded.tolerance.values.map { $0.value }, [120])
        assertFixedPoint(decoded)
    }

    func testTextureTimeSpanAndRate() {
        let decoded = decodeFields(TextureEffectDefinition.typeName, [
            (key: "FilePath", value: .string("C:\\tex.png")),
            (key: "PlaybackRate", value: .number(150)),
            (key: "ContentOffset", value: .string("00:00:02.5000000")),
            (key: "IsInverted", value: .bool(true)),
        ]) as? TextureEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.filePath, "C:\\tex.png")
        XCTAssertEqual(decoded.playbackRate, 150)
        XCTAssertEqual(decoded.contentOffset, TimeSpanValue(ticks: 25_000_000))
        XCTAssertTrue(decoded.isInverted)
        assertFixedPoint(decoded)
    }

    func testRandomAndRepeatBaseFields() {
        let random = decodeFields(RandomRotateEffectDefinition.typeName, [
            (key: "Span", value: animJSON(values: [2])),
            (key: "Z", value: animJSON(values: [45])),
        ]) as? RandomRotateEffectDefinition
        XCTAssertNotNil(random)
        guard let random else { return }
        XCTAssertEqual(random.span.values.map { $0.value }, [2])
        XCTAssertEqual(random.z.values.map { $0.value }, [45])
        assertFixedPoint(random)

        let repeatDef = decodeFields(RepeatSkewEffectDefinition.typeName, [
            (key: "Span", value: animJSON(values: [0.25])),
            (key: "CenterPoint", value: .string("Custom")),
            (key: "AngleX", value: animJSON(values: [-30])),
        ]) as? RepeatSkewEffectDefinition
        XCTAssertNotNil(repeatDef)
        guard let repeatDef else { return }
        XCTAssertEqual(repeatDef.span.values.map { $0.value }, [0.25])
        XCTAssertEqual(repeatDef.centerPoint, .custom)
        XCTAssertEqual(repeatDef.angleX.values.map { $0.value }, [-30])
        assertFixedPoint(repeatDef)
    }

    func testHlslDefaultSource() {
        let bare = decodeBare(HlslPixelShaderCodeEffectDefinition.typeName)
            as? HlslPixelShaderCodeEffectDefinition
        XCTAssertNotNil(bare)
        XCTAssertTrue(bare!.source.hasPrefix("Texture2D InputTexture : register(t0);"))
        XCTAssertTrue(bare!.source.hasSuffix("};"))
        assertFixedPoint(bare!)

        let decoded = decodeFields(HlslPixelShaderCodeEffectDefinition.typeName, [
            (key: "Source", value: .string("float4 main() : SV_Target { return 0; }")),
            (key: "Value2", value: animJSON(values: [0.5])),
        ]) as? HlslPixelShaderCodeEffectDefinition
        XCTAssertEqual(decoded?.source, "float4 main() : SV_Target { return 0; }")
        XCTAssertEqual(decoded?.value2.values.map { $0.value }, [0.5])
        assertFixedPoint(decoded!)
    }

    func testMaskShapeParameterRawPreserved() {
        let parameter: JSONValue = .object([
            (key: "$type", value: .string("YukkuriMovieMaker.Shape.QuadrilateralShapeParameter, YukkuriMovieMaker")),
            (key: "Width", value: animJSON(values: [200])),
        ])
        let decoded = decodeFields(MaskEffectDefinition.typeName, [
            (key: "ShapeParameter", value: parameter),
            (key: "InvertMask", value: .bool(true)),
        ]) as? MaskEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.shapeParameter?.value, parameter)
        XCTAssertTrue(decoded.invertMask)
        XCTAssertEqual(
            decoded.shapeType2,
            "YukkuriMovieMaker.Shape.QuadrilateralShapePlugin, YukkuriMovieMaker"
        )
        assertFixedPoint(decoded)
    }
}

// MARK: - 旧互換（set 専用）キーの転送

final class GPUEffectLegacyKeyTests: XCTestCase {

    /// SepiaEffect.Intensity（double）は SepiaIntensity の先頭値へ転送される。
    func testSepiaLegacyIntensity() {
        let decoded = decodeFields(SepiaEffectDefinition.typeName, [
            (key: "Intensity", value: .number(0.8)),
        ]) as? SepiaEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.sepiaIntensity.values.map { $0.value }, [0.8])
        let encoded = VideoEffectRegistry.encode(decoded).value
        XCTAssertNil(encoded.field("Intensity"))
        XCTAssertNotNil(encoded.field("SepiaIntensity"))
        assertFixedPoint(decoded)
    }

    /// GradientEffect.ColorFrom / ColorTo は Stops の色へ転送される。
    func testGradientLegacyColors() {
        let decoded = decodeFields(GradientEffectDefinition.typeName, [
            (key: "ColorFrom", value: .string("#FF112233")),
            (key: "ColorTo", value: .string("#FF445566")),
        ]) as? GradientEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.stops.count, 2)
        XCTAssertEqual(decoded.stops[0].color, Color(alpha: 255, red: 17, green: 34, blue: 51))
        XCTAssertEqual(decoded.stops[1].color, Color(alpha: 255, red: 68, green: 85, blue: 102))
        let encoded = VideoEffectRegistry.encode(decoded).value
        XCTAssertNil(encoded.field("ColorFrom"))
        XCTAssertNil(encoded.field("ColorTo"))
        assertFixedPoint(decoded)
    }

    /// CenterPointEffect.Mode は Horizontal / Vertical の組へ変換される。
    func testCenterPointLegacyMode() {
        let decoded = decodeFields(CenterPointEffectDefinition.typeName, [
            (key: "Mode", value: .string("RightBottom")),
        ]) as? CenterPointEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.horizontal, .right)
        XCTAssertEqual(decoded.vertical, .bottom)
        let encoded = VideoEffectRegistry.encode(decoded).value
        XCTAssertNil(encoded.field("Mode"))
        assertFixedPoint(decoded)
    }

    /// ChromaKeyEffect2.Threshold は Threshold2 へ 21700/32767 倍で転送される。
    func testChromaKey2LegacyThreshold() {
        let decoded = decodeFields(ChromaKeyEffect2Definition.typeName, [
            (key: "Threshold", value: animJSON(values: [50])),
        ]) as? ChromaKeyEffect2Definition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.threshold2.values.count, 1)
        XCTAssertEqual(
            decoded.threshold2.values[0].value,
            50.0 * 21700.0 / 32767.0, accuracy: 1e-9
        )
        let encoded = VideoEffectRegistry.encode(decoded).value
        XCTAssertNil(encoded.field("Threshold"))
        assertFixedPoint(decoded)
    }

    /// MaskEffect.ShapeType は ShapeType2 へ変換される
    /// （数値 0 = Background、本家の対応表どおり）。
    func testMaskLegacyShapeType() {
        let decoded = decodeFields(MaskEffectDefinition.typeName, [
            (key: "ShapeType", value: .number(0)),
        ]) as? MaskEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(
            decoded.shapeType2,
            "YukkuriMovieMaker.Shape.BackgroundShapePlugin, YukkuriMovieMaker"
        )
        let encoded = VideoEffectRegistry.encode(decoded).value
        XCTAssertNil(encoded.field("ShapeType"))
        assertFixedPoint(decoded)
    }

    /// InOutRotateEffect.Value は ValueZ へ転送される。
    func testInOutRotateLegacyValue() {
        let decoded = decodeFields(InOutRotateEffectDefinition.typeName, [
            (key: "Value", value: .number(45)),
        ]) as? InOutRotateEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.valueZ, 45)
        let encoded = VideoEffectRegistry.encode(decoded).value
        XCTAssertNil(encoded.field("Value"))
        assertFixedPoint(decoded)
    }

    /// 生保持へ転送される旧互換キーは、追加フィールドとして原文のまま残る
    /// （DisplacementMapEffect の FilePath 等は内部オブジェクトへ転送される
    /// ため、内部を書き換えない側では変換しない）。
    func testDisplacementMapLegacyKeysStayRaw() {
        let decoded = decodeFields(DisplacementMapEffectDefinition.typeName, [
            (key: "FilePath", value: .string("C:\\map.png")),
            (key: "XScale", value: animJSON(values: [150])),
        ]) as? DisplacementMapEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        let encoded = VideoEffectRegistry.encode(decoded).value
        XCTAssertEqual(encoded.field("FilePath")?.stringValue, "C:\\map.png")
        XCTAssertNotNil(encoded.field("XScale"))
        assertFixedPoint(decoded)
    }
}

// MARK: - 暫定処理器（素通し）

final class GPUEffectPassthroughTests: XCTestCase {

    /// エフェクト説明を作る（EffectsTests と同じ組み立て）。
    private func makeEffectDescription(
        drawDescription: DrawDescription
    ) -> EffectDescription {
        let fps = 30
        let base = TimelineSourceDescription(
            screenSize: PixelSize(width: 1920, height: 1080),
            timelinePosition: FramePosition(frame: 10, fps: fps),
            timelineDuration: FramePosition(frame: 900, fps: fps),
            fps: fps,
            usage: .paused,
            sceneId: UUID(),
            scenes: []
        )
        let item = TimelineItemSourceDescription(base, itemFrame: 10, itemLength: 90, layer: 0)
        return EffectDescription(
            itemDescription: item, drawDescription: drawDescription, inputIndex: 0, inputCount: 1
        )
    }

    func testProcessorsArePassthrough() throws {
        let definitions: [VideoEffectDefinitionBase] = [
            RotateEffectDefinition(),
            GaussianBlurEffectDefinition(),
            OutlineEffectDefinition(),
            InOutBorderBlurEffectDefinition(),
            RandomRotateEffectDefinition(),
            RepeatSkewEffectDefinition(),
            InOutTransitionEffectDefinition(),
        ]
        let input = ImageReference()
        let drawDescription = DrawDescription(
            draw: Vector3(x: 1, y: 2, z: 3),
            zoom: Vector2(x: 1.5, y: 0.5),
            opacity: 0.75
        )
        for definition in definitions {
            let processor = definition.createProcessor()
            XCTAssertTrue(
                processor is GPUEffectPassthroughProcessor,
                "\(type(of: definition))"
            )
            guard let drawProcessor = processor as? DrawDescriptionEffectProcessor else {
                XCTFail("DrawDescriptionEffectProcessor ではない: \(type(of: definition))")
                continue
            }
            drawProcessor.setInput(input)
            XCTAssertTrue(drawProcessor.output === input)
            let result = try drawProcessor.update(makeEffectDescription(drawDescription: drawDescription))
            XCTAssertEqual(result.draw, drawDescription.draw)
            XCTAssertEqual(result.zoom, drawDescription.zoom)
            XCTAssertEqual(result.opacity, drawDescription.opacity)
            drawProcessor.clearInput()
            XCTAssertNil(drawProcessor.output)
        }
    }
}
