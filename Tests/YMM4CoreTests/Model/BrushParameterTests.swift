import XCTest
@testable import YMM4Core

// ブラシ基盤（BRUSH46）の型付きモデルのテスト。
//
// (1) 本家組み込みブラシ 8 種（単色を除く）が型付きで復元され、
//     往復保存で JSON が一致すること（未知キーは追加フィールドとして
//     順序を保って残ること）、
// (2) 型付き化しない種別（グラデーションメッシュ・コミュニティ）は
//     生保持のまま往復すること、
// (3) 4 効果（影・背景塗り・前景塗り・枠線）の Brush フィールドが
//     型付きモデルで往復し、null は欠落として保たれること、
// (4) ブラシ内の Animation へキーフレーム文脈が伝播すること、
// を確認する。

/// Animation の保存形式（実ファイルの形）。
private func animJSON(_ value: Double) -> JSONValue {
    .object([
        (key: "Values", value: .array([.object([(key: "Value", value: .number(value))])])),
        (key: "Span", value: .number(0.0)),
        (key: "AnimationType", value: .string("なし")),
        (key: "Bezier", value: .object([
            (key: "Points", value: .array([])),
            (key: "IsQuadratic", value: .bool(false)),
        ])),
    ])
}

private func brushObject(
    plugin: String, parameter: JSONValue
) -> JSONValue {
    .object([
        (key: "Type", value: .string(plugin)),
        (key: "Parameter", value: parameter),
    ])
}

/// 復元 → 保存で入力 JSON と一致することを確認する。
private func assertBrushRoundTrip(
    _ json: JSONValue, file: StaticString = #filePath, line: UInt = #line
) -> Brush {
    let brush = Brush.decode(from: json)
    XCTAssertEqual(brush.encodeToJSONValue(), json, file: file, line: line)
    return brush
}

final class BrushParameterModelTests: XCTestCase {

    func testLinearGradientRoundTrip() {
        let parameter: JSONValue = .object([
            (key: "$type", value: .string(LinearGradientBrushParameter.typeName)),
            (key: "Stops", value: .array([
                .object([
                    (key: "Offset", value: .number(0.0)),
                    (key: "Color", value: .string("#FFFF0000")),
                ]),
                .object([
                    (key: "Offset", value: .number(0.5)),
                    (key: "Color", value: .string("#FF00FF00")),
                ]),
                .object([
                    (key: "Offset", value: .number(1.0)),
                    (key: "Color", value: .string("#FF0000FF")),
                ]),
            ])),
            (key: "CoordinateMode", value: .string("Relative")),
            (key: "Size", value: animJSON(150)),
            (key: "Offset", value: animJSON(-20)),
            (key: "Angle", value: animJSON(45)),
            (key: "ExtendMode", value: .string("Mirror")),
            (key: "FutureKey", value: .number(7.0)),
        ])
        let brush = assertBrushRoundTrip(brushObject(
            plugin: "YukkuriMovieMaker.Brush.LinearGradientBrushPlugin, YukkuriMovieMaker",
            parameter: parameter
        ))
        guard case .linearGradient(let decoded) = brush.parameter else {
            XCTFail("linearGradient として復元されること")
            return
        }
        XCTAssertEqual(decoded.stops.count, 3)
        XCTAssertEqual(decoded.stops[1].color, Color(alpha: 255, red: 0, green: 255, blue: 0))
        XCTAssertEqual(decoded.coordinateMode, .relative)
        XCTAssertEqual(decoded.size.values.map { $0.value }, [150])
        XCTAssertEqual(decoded.offset.values.map { $0.value }, [-20])
        XCTAssertEqual(decoded.angle.values.map { $0.value }, [45])
        XCTAssertEqual(decoded.extendMode, .mirror)
        XCTAssertEqual(decoded.additionalFields.map { $0.key }, ["FutureKey"])
    }

    func testRadialGradientRoundTrip() {
        let parameter: JSONValue = .object([
            (key: "$type", value: .string(RadialGradientBrushParameter.typeName)),
            (key: "Stops", value: .array([
                .object([
                    (key: "Offset", value: .number(0.0)),
                    (key: "Color", value: .string("#FFFFFFFF")),
                ]),
                .object([
                    (key: "Offset", value: .number(1.0)),
                    (key: "Color", value: .string("#FF000000")),
                ]),
            ])),
            (key: "CenterX", value: animJSON(10)),
            (key: "CenterY", value: animJSON(-5)),
            (key: "OriginX", value: animJSON(3)),
            (key: "OriginY", value: animJSON(4)),
            (key: "RadiusX", value: animJSON(120)),
            (key: "RadiusY", value: animJSON(80)),
            (key: "Zoom", value: animJSON(90)),
            (key: "Angle", value: animJSON(30)),
            (key: "Aspect", value: animJSON(-25)),
            (key: "ExtendMode", value: .string("Wrap")),
            (key: "IsInverted", value: .bool(true)),
        ])
        let brush = assertBrushRoundTrip(brushObject(
            plugin: "YukkuriMovieMaker.Brush.RadiulGradientBrushPlugin, YukkuriMovieMaker",
            parameter: parameter
        ))
        guard case .radialGradient(let decoded) = brush.parameter else {
            XCTFail("radialGradient として復元されること")
            return
        }
        XCTAssertEqual(decoded.centerX.values.map { $0.value }, [10])
        XCTAssertEqual(decoded.radiusY.values.map { $0.value }, [80])
        XCTAssertEqual(decoded.aspect.values.map { $0.value }, [-25])
        XCTAssertEqual(decoded.extendMode, .wrap)
        XCTAssertTrue(decoded.isInverted)
    }

    func testCheckeredRoundTrip() {
        let parameter: JSONValue = .object([
            (key: "$type", value: .string(CheckeredBrushParameter.typeName)),
            (key: "Color1", value: .string("#FF112233")),
            (key: "Color2", value: .string("#FF445566")),
            (key: "Size", value: animJSON(24)),
            (key: "X", value: animJSON(5)),
            (key: "Y", value: animJSON(6)),
            (key: "Angle", value: animJSON(15)),
            (key: "Aspect", value: animJSON(10)),
            (key: "IsInverted", value: .bool(true)),
        ])
        let brush = assertBrushRoundTrip(brushObject(
            plugin: "YukkuriMovieMaker.Brush.CheckeredBrushPlugin, YukkuriMovieMaker",
            parameter: parameter
        ))
        guard case .checkered(let decoded) = brush.parameter else {
            XCTFail("checkered として復元されること")
            return
        }
        XCTAssertEqual(decoded.color1, Color(alpha: 255, red: 0x11, green: 0x22, blue: 0x33))
        XCTAssertEqual(decoded.size.values.map { $0.value }, [24])
        XCTAssertEqual(decoded.drawing.x.values.map { $0.value }, [5])
        XCTAssertTrue(decoded.drawing.isInverted)
    }

    func testDotRoundTrip() {
        let parameter: JSONValue = .object([
            (key: "$type", value: .string(DotBrushParameter.typeName)),
            (key: "Foreground", value: .string("#FFFF0000")),
            (key: "Background", value: .string("#00000000")),
            (key: "Radius", value: animJSON(8)),
            (key: "Span", value: animJSON(32)),
            (key: "Zoom", value: animJSON(110)),
            (key: "X", value: animJSON(0)),
            (key: "Y", value: animJSON(0)),
            (key: "Angle", value: animJSON(0)),
            (key: "Aspect", value: animJSON(0)),
            (key: "IsInverted", value: .bool(false)),
        ])
        let brush = assertBrushRoundTrip(brushObject(
            plugin: "YukkuriMovieMaker.Brush.DotBrushPlugin, YukkuriMovieMaker",
            parameter: parameter
        ))
        guard case .dot(let decoded) = brush.parameter else {
            XCTFail("dot として復元されること")
            return
        }
        XCTAssertEqual(decoded.foreground, Color(alpha: 255, red: 255, green: 0, blue: 0))
        XCTAssertEqual(decoded.background, Color(alpha: 0, red: 0, green: 0, blue: 0))
        XCTAssertEqual(decoded.span.values.map { $0.value }, [32])
    }

    func testStripeRoundTrip() {
        let parameter: JSONValue = .object([
            (key: "$type", value: .string(StripeBrushParameter.typeName)),
            (key: "Color1", value: .string("#FFFFFFFF")),
            (key: "Width1", value: animJSON(30)),
            (key: "Color2", value: .string("#FF000000")),
            (key: "Width2", value: animJSON(10)),
            (key: "Offset", value: animJSON(4)),
            (key: "Zoom", value: animJSON(100)),
            (key: "Angle", value: animJSON(90)),
        ])
        let brush = assertBrushRoundTrip(brushObject(
            plugin: "YukkuriMovieMaker.Brush.StripeBrushPlugin, YukkuriMovieMaker",
            parameter: parameter
        ))
        guard case .stripe(let decoded) = brush.parameter else {
            XCTFail("stripe として復元されること")
            return
        }
        XCTAssertEqual(decoded.width1.values.map { $0.value }, [30])
        XCTAssertEqual(decoded.angle.values.map { $0.value }, [90])
    }

    func testGridLineRoundTrip() {
        let parameter: JSONValue = .object([
            (key: "$type", value: .string(GridLineBrushParameter.typeName)),
            (key: "StrokeColor", value: .string("#FF00FF00")),
            (key: "BackgroundColor", value: .string("#00000000")),
            (key: "Thickness", value: animJSON(2)),
            (key: "Width", value: animJSON(64)),
            (key: "Height", value: animJSON(48)),
            (key: "Zoom", value: animJSON(100)),
            (key: "X", value: animJSON(1)),
            (key: "Y", value: animJSON(2)),
            (key: "Angle", value: animJSON(0)),
            (key: "Aspect", value: animJSON(0)),
            (key: "IsInverted", value: .bool(false)),
        ])
        let brush = assertBrushRoundTrip(brushObject(
            plugin: "YukkuriMovieMaker.Brush.GridLineBrushPlugin, YukkuriMovieMaker",
            parameter: parameter
        ))
        guard case .gridLine(let decoded) = brush.parameter else {
            XCTFail("gridLine として復元されること")
            return
        }
        XCTAssertEqual(decoded.thickness.values.map { $0.value }, [2])
        XCTAssertEqual(decoded.height.values.map { $0.value }, [48])
        XCTAssertEqual(decoded.drawing.y.values.map { $0.value }, [2])
    }

    func testBitmapRoundTrip() {
        let parameter: JSONValue = .object([
            (key: "$type", value: .string(BitmapBrushParameter.typeName)),
            (key: "FilePath", value: .string("C:\\textures\\tile.png")),
            (key: "PlaybackRate", value: .number(50.0)),
            (key: "ContentOffset", value: .string("00:00:01.5000000")),
            (key: "ExtendModeX", value: .string("Mirror")),
            (key: "ExtendModeY", value: .string("Clamp")),
            (key: "Zoom", value: animJSON(200)),
            (key: "X", value: animJSON(0)),
            (key: "Y", value: animJSON(0)),
            (key: "Angle", value: animJSON(45)),
            (key: "Aspect", value: animJSON(0)),
            (key: "IsInverted", value: .bool(false)),
        ])
        let brush = assertBrushRoundTrip(brushObject(
            plugin: "YukkuriMovieMaker.Brush.BitmapBrushPlugin, YukkuriMovieMaker",
            parameter: parameter
        ))
        guard case .bitmap(let decoded) = brush.parameter else {
            XCTFail("bitmap として復元されること")
            return
        }
        XCTAssertEqual(decoded.filePath, "C:\\textures\\tile.png")
        XCTAssertEqual(decoded.playbackRate, 50)
        XCTAssertEqual(decoded.extendModeX, .mirror)
        XCTAssertEqual(decoded.extendModeY, .clamp)
    }

    func testNoiseRoundTrip() {
        let noiseParameter: JSONValue = .object([
            (key: "$type", value: .string("YukkuriMovieMaker.Project.Effects.NoiseParameters.FractalNoiseParameter, YukkuriMovieMaker")),
            (key: "Seed", value: animJSON(7)),
        ])
        let parameter: JSONValue = .object([
            (key: "$type", value: .string(NoiseBrushParameter.typeName)),
            (key: "NoiseType", value: .string("Perlin")),
            (key: "NoiseParameter", value: noiseParameter),
            (key: "Color1", value: .string("#FFFFFFFF")),
            (key: "Color2", value: .string("#FF000000")),
            (key: "IsColor", value: .bool(true)),
            (key: "IsUniqueSeed", value: .bool(false)),
        ])
        let brush = assertBrushRoundTrip(brushObject(
            plugin: "YukkuriMovieMaker.Brush.NoiseBrushPlugin, YukkuriMovieMaker",
            parameter: parameter
        ))
        guard case .noise(let decoded) = brush.parameter else {
            XCTFail("noise として復元されること")
            return
        }
        XCTAssertEqual(decoded.noiseType, .perlin)
        XCTAssertEqual(decoded.noiseParameter?.value, noiseParameter)
        XCTAssertTrue(decoded.isColor)
    }

    func testGradientMeshStaysPreserved() {
        let parameter: JSONValue = .object([
            (key: "$type", value: .string("YukkuriMovieMaker.Brush.GradientMeshBrushParameter, YukkuriMovieMaker")),
            (key: "HorizontalCount", value: .number(2.0)),
            (key: "Points", value: .array([])),
        ])
        let brush = assertBrushRoundTrip(brushObject(
            plugin: "YukkuriMovieMaker.Brush.GradientMeshBrushPlugin, YukkuriMovieMaker",
            parameter: parameter
        ))
        guard case .preserved = brush.parameter else {
            XCTFail("gradientMesh は生保持のままであること")
            return
        }
    }

    func testCommunityBrushStaysPreserved() {
        let parameter: JSONValue = .object([
            (key: "$type", value: .string("YukkuriMovieMaker.Plugin.Community.Brush.Pattern.Asanoha.AsanohaBrushParameter, YukkuriMovieMaker.Plugin.Community")),
            (key: "Color1", value: .string("#FFFFFFFF")),
        ])
        let brush = assertBrushRoundTrip(brushObject(
            plugin: "YukkuriMovieMaker.Plugin.Community.Brush.Pattern.Asanoha.AsanohaBrushPlugin, YukkuriMovieMaker.Plugin.Community",
            parameter: parameter
        ))
        guard case .preserved = brush.parameter else {
            XCTFail("コミュニティブラシは生保持のままであること")
            return
        }
    }

    func testNonObjectBrushValueIsPreserved() {
        let brush = Brush.decode(from: .string("broken"))
        XCTAssertEqual(brush.encodeToJSONValue(), .string("broken"))
    }
}

final class BrushEffectFieldTests: XCTestCase {

    private func decodeEffect(
        _ typeName: String, _ fields: [(key: String, value: JSONValue)]
    ) -> VideoEffectDefinitionBase? {
        VideoEffectRegistry.decode(PreservedObject(.object(
            [(key: "$type", value: .string(typeName))] + fields
        )))
    }

    func testShadowGradientBrushRoundTripAndAnimationTraversal() {
        let brush = brushObject(
            plugin: "YukkuriMovieMaker.Brush.LinearGradientBrushPlugin, YukkuriMovieMaker",
            parameter: .object([
                (key: "$type", value: .string(LinearGradientBrushParameter.typeName)),
                (key: "Stops", value: .array([
                    .object([
                        (key: "Offset", value: .number(0.0)),
                        (key: "Color", value: .string("#FFFF0000")),
                    ]),
                    .object([
                        (key: "Offset", value: .number(1.0)),
                        (key: "Color", value: .string("#FF0000FF")),
                    ]),
                ])),
                (key: "CoordinateMode", value: .string("Relative")),
                (key: "Size", value: animJSON(100)),
                (key: "Offset", value: animJSON(0)),
                (key: "Angle", value: animJSON(90)),
                (key: "ExtendMode", value: .string("Clamp")),
            ])
        )
        let decoded = decodeEffect(ShadowEffectDefinition.typeName, [
            (key: "Brush", value: brush),
        ]) as? ShadowEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertNotNil(decoded.brush)
        if case .linearGradient(let parameter) = decoded.brush?.parameter {
            XCTAssertEqual(parameter.angle.values.map { $0.value }, [90])
        } else {
            XCTFail("影のブラシが線形グラデーションとして復元されること")
        }
        let encoded = VideoEffectRegistry.encode(decoded).value
        XCTAssertEqual(encoded.field("Brush"), brush)

        // ブラシ内の Animation（Size / Offset / Angle の 3 つ）が
        // 定義の走査に含まれ、キーフレーム文脈が届くこと。
        var count = 0
        decoded.forEachAnimation { _ in count += 1 }
        XCTAssertEqual(count, 6 + 3)
        decoded.setKeyFrames(KeyFrames(frames: [0, 45, 89]))
        if case .linearGradient(let parameter) = decoded.brush?.parameter {
            XCTAssertEqual(parameter.angle.keyFrames.frames, [0, 45, 89])
        }
    }

    func testFillForegroundNullBrushStaysAbsent() {
        let decoded = decodeEffect(FillForegroundEffectDefinition.typeName, [
            (key: "Brush", value: .null),
        ]) as? FillForegroundEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertNil(decoded.brush)
        let encoded = VideoEffectRegistry.encode(decoded).value
        XCTAssertNil(encoded.field("Brush"))
    }

    func testFrameLineSolidBrushMatchesRealFileShape() {
        // 実ファイル（upload.ymmp）の単色ブラシの形。
        let brush = brushObject(
            plugin: "YukkuriMovieMaker.Plugin.Brush.SolidColorBrushPlugin, YukkuriMovieMaker, Version=4.24.0.3, Culture=neutral, PublicKeyToken=null",
            parameter: .object([
                (key: "$type", value: .string(SolidColorBrushParameter.typeName)),
                (key: "Color", value: .string("#FF00FF00")),
            ])
        )
        let decoded = decodeEffect(FrameLineEffectDefinition.typeName, [
            (key: "Brush", value: brush),
        ]) as? FrameLineEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        if case .solidColor(let parameter) = decoded.brush?.parameter {
            XCTAssertEqual(parameter.color, Color(alpha: 255, red: 0, green: 255, blue: 0))
        } else {
            XCTFail("枠線のブラシが単色として復元されること")
        }
        // プラグイン型名（バージョン付き）もそのまま往復すること。
        let encoded = VideoEffectRegistry.encode(decoded).value
        XCTAssertEqual(encoded.field("Brush"), brush)
    }

    func testFillBackgroundCheckeredBrushRoundTrip() {
        let brush = brushObject(
            plugin: "YukkuriMovieMaker.Brush.CheckeredBrushPlugin, YukkuriMovieMaker",
            parameter: .object([
                (key: "$type", value: .string(CheckeredBrushParameter.typeName)),
                (key: "Color1", value: .string("#FFFFFFFF")),
                (key: "Color2", value: .string("#FF000000")),
                (key: "Size", value: animJSON(16)),
                (key: "X", value: animJSON(0)),
                (key: "Y", value: animJSON(0)),
                (key: "Angle", value: animJSON(0)),
                (key: "Aspect", value: animJSON(0)),
                (key: "IsInverted", value: .bool(false)),
            ])
        )
        let decoded = decodeEffect(FillBackgroundEffectDefinition.typeName, [
            (key: "Brush", value: brush),
        ]) as? FillBackgroundEffectDefinition
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        let encoded = VideoEffectRegistry.encode(decoded).value
        XCTAssertEqual(encoded.field("Brush"), brush)
    }
}
