import XCTest
@testable import YMM4Core

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

/// エフェクト説明を作る。
private func makeEffectDescription(
    frame: Int = 0,
    duration: Int = 90,
    fps: Int = 30,
    usage: TimelineSourceUsage = .paused,
    screenSize: PixelSize = PixelSize(width: 1920, height: 1080),
    drawDescription: DrawDescription = DrawDescription(
        draw: .zero, zoom: Vector2(x: 1, y: 1), opacity: 1
    ),
    inputIndex: Int = 0
) -> EffectDescription {
    let base = TimelineSourceDescription(
        screenSize: screenSize,
        timelinePosition: FramePosition(frame: frame, fps: fps),
        timelineDuration: FramePosition(frame: 900, fps: fps),
        fps: fps,
        usage: usage,
        sceneId: UUID(),
        scenes: []
    )
    let item = TimelineItemSourceDescription(base, itemFrame: frame, itemLength: duration, layer: 0)
    return EffectDescription(
        itemDescription: item, drawDescription: drawDescription, inputIndex: inputIndex, inputCount: 1
    )
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

// MARK: - レジストリと往復

final class VideoEffectRegistryTests: XCTestCase {

    func testAllRegisteredTypeNamesDecode() {
        let typeNames = [
            ZoomEffectDefinition.typeName,
            OpacityEffectDefinition.typeName,
            DrawPositionEffectDefinition.typeName,
            InOutFadeEffectDefinition.typeName,
            InOutMoveEffectDefinition.typeName,
            InOutZoomEffectDefinition.typeName,
            InOutMoveFromOutsideFrameEffectDefinition.typeName,
            RandomMoveEffectDefinition.typeName,
            RandomOpacityEffectDefinition.typeName,
            RandomZoomEffectDefinition.typeName,
            RepeatMoveEffectDefinition.typeName,
            RepeatOpacityEffectDefinition.typeName,
            RepeatZoomEffectDefinition.typeName,
            ShowOnlyPreviewEffectDefinition.typeName,
            BillboardEffectDefinition.typeName,
            CameraFovEffectDefinition.typeName,
            CameraPositionEffectDefinition.typeName,
            CameraLookAtEffectDefinition.typeName,
            CameraWraparoundEffectDefinition.typeName,
            PolarDrawPositionEffectDefinition.typeName,
            XYToPolarTransformEffectDefinition.typeName,
            MotionTrackingEffectDefinition.typeName,
        ]
        XCTAssertEqual(typeNames.count, 22)
        for typeName in typeNames {
            let preserved = PreservedObject(.object([(key: "$type", value: .string(typeName))]))
            let decoded = VideoEffectRegistry.decode(preserved)
            XCTAssertNotNil(decoded, typeName)
            XCTAssertTrue(VideoEffectRegistry.isKnown(typeName: typeName), typeName)
            XCTAssertEqual(
                VideoEffectRegistry.encode(decoded!).value.field("$type")?.stringValue, typeName
            )
            assertFixedPoint(decoded!)
        }
    }

    func testUnknownTypesReturnNil() {
        // コミュニティ系は生保持のまま。
        let gpu = PreservedObject(.object([
            (key: "$type", value: .string(
                "YukkuriMovieMaker.Project.Effects.ColorCorrectionEffect, YukkuriMovieMaker")),
        ]))
        XCTAssertNil(VideoEffectRegistry.decode(gpu))
        // コミュニティ移行先は本体ではないため未知。
        let community = PreservedObject(.object([
            (key: "$type", value: .string(
                "YukkuriMovieMaker.Project.Effects.WaveEffect, YukkuriMovieMaker")),
        ]))
        XCTAssertNil(VideoEffectRegistry.decode(community))
        // $type の無い値も nil。
        XCTAssertNil(VideoEffectRegistry.decode(PreservedObject(.object([]))))
    }

    /// 本家リネーム（OutlineLiteEffect → OutlineEffect）の移行先が
    /// GPU 系の定義層として登録されたため、移行後に型付きで復元される。
    func testRenamedOutlineLiteDecodesAsOutline() {
        let renamed = PreservedObject(.object([
            (key: "$type", value: .string(
                "YukkuriMovieMaker.Project.Effects.OutlineLiteEffect, YukkuriMovieMaker")),
        ]))
        let decoded = VideoEffectRegistry.decode(renamed)
        XCTAssertTrue(decoded is OutlineEffectDefinition)
        XCTAssertEqual(
            VideoEffectRegistry.encode(decoded!).value.field("$type")?.stringValue,
            OutlineEffectDefinition.typeName
        )
    }

    /// 実ファイル（本家保存）に実在した CameraPositionEffect の形で復元する。
    func testRealFileCameraPositionEffect() {
        let json: JSONValue = .object([
            (key: "$type", value: .string(
                "YukkuriMovieMaker.Project.Effects.CameraPositionEffect, YukkuriMovieMaker")),
            (key: "X", value: animJSON(values: [17.2, -17.2], span: 0.47, type: "ランダム移動")),
            (key: "Y", value: animJSON(values: [6.0, -7.0], span: 0.25, type: "ランダム移動")),
            (key: "Z", value: animJSON(values: [6.0, -6.4], span: 0.38, type: "ランダム移動")),
            (key: "RotationY", value: animJSON(values: [14.6])),
            (key: "RotationX", value: animJSON(values: [0])),
            (key: "RotationZ", value: animJSON(values: [0])),
            (key: "IsEnabled", value: .bool(true)),
        ])
        let decoded = VideoEffectRegistry.decode(PreservedObject(json))
        let definition = decoded as? CameraPositionEffectDefinition
        XCTAssertNotNil(definition)
        guard let definition else { return }
        XCTAssertEqual(definition.x.values.map { $0.value }, [17.2, -17.2])
        XCTAssertEqual(definition.x.span, 0.47)
        XCTAssertEqual(definition.x.animationType, .random)
        XCTAssertEqual(definition.rotationY.values.map { $0.value }, [14.6])
        // 実ファイルに無い ChangeFov / Fov は既定値になる。
        XCTAssertFalse(definition.changeFov)
        XCTAssertEqual(definition.fov.values.map { $0.value }, [56.7380926])
        XCTAssertTrue(definition.additionalFields.isEmpty)
        // 書き出しのキー順は実ファイルと同じ（自前プロパティ → 基底）。
        guard case .object(let fields) = VideoEffectRegistry.encode(definition).value else {
            XCTFail("オブジェクトでない")
            return
        }
        XCTAssertEqual(fields.map { $0.key }, [
            "$type", "X", "Y", "Z", "RotationY", "RotationX", "RotationZ",
            "ChangeFov", "Fov", "IsEnabled",
        ])
        assertFixedPoint(definition)
    }

    func testUnknownKeysAndRemarkArePreserved() {
        let json: JSONValue = .object([
            (key: "$type", value: .string(ZoomEffectDefinition.typeName)),
            (key: "Zoom", value: animJSON(values: [150])),
            (key: "FutureParam", value: .number(42)),
            (key: "Remark", value: .string("メモ")),
            (key: "IsEnabled", value: .bool(false)),
        ])
        let definition = VideoEffectRegistry.decode(PreservedObject(json)) as? ZoomEffectDefinition
        XCTAssertNotNil(definition)
        guard let definition else { return }
        XCTAssertEqual(definition.zoom.values.map { $0.value }, [150])
        XCTAssertFalse(definition.isEnabled)
        XCTAssertEqual(definition.remark, "メモ")
        XCTAssertEqual(definition.additionalFields.map { $0.key }, ["FutureParam"])
        let encoded = VideoEffectRegistry.encode(definition).value
        XCTAssertEqual(encoded.field("FutureParam"), .number(42))
        XCTAssertEqual(encoded.field("Remark"), .string("メモ"))
        assertFixedPoint(definition)
    }

    func testEmptyRemarkIsNotWritten() {
        let definition = ZoomEffectDefinition()
        let encoded = VideoEffectRegistry.encode(definition).value
        XCTAssertNil(encoded.field("Remark"))
        XCTAssertEqual(encoded.field("IsEnabled"), .bool(true))
    }
}

// MARK: - 基本の描画変換

final class BasicDrawEffectProcessorTests: XCTestCase {

    func testZoom() throws {
        let definition = ZoomEffectDefinition()
        definition.zoom.values = [AnimationValue(200)]
        definition.zoomX.values = [AnimationValue(50)]
        definition.zoomY.values = [AnimationValue(100)]
        let processor = definition.createProcessor()
        let result = try processor.update(makeEffectDescription())
        XCTAssertEqual(result.zoom.x, 1.0, accuracy: 1e-9)
        XCTAssertEqual(result.zoom.y, 2.0, accuracy: 1e-9)
        // 素通し: 出力は入力そのもの。
        let image = ImageReference(label: "in")
        processor.setInput(image)
        XCTAssertTrue(processor.output === image)
        processor.clearInput()
        XCTAssertNil(processor.output)
    }

    func testZoomNearestNeighbor() throws {
        let definition = ZoomEffectDefinition()
        definition.isNearestNeighbor = true
        let result = try definition.createProcessor().update(makeEffectDescription())
        XCTAssertEqual(result.zoomInterpolationMode, .nearestNeighbor)
    }

    func testOpacityRelativeAndAbsolute() throws {
        let relative = OpacityEffectDefinition()
        relative.opacity.values = [AnimationValue(50)]
        var result = try relative.createProcessor().update(makeEffectDescription())
        XCTAssertEqual(result.opacity, 0.5, accuracy: 1e-9)

        let absolute = OpacityEffectDefinition()
        absolute.opacity.values = [AnimationValue(50)]
        absolute.isAbsolute = true
        result = try absolute.createProcessor().update(makeEffectDescription(
            drawDescription: DrawDescription(draw: .zero, zoom: Vector2(x: 1, y: 1), opacity: 0.8)
        ))
        XCTAssertEqual(result.opacity, 0.5, accuracy: 1e-9)
    }

    func testDrawPosition() throws {
        let definition = DrawPositionEffectDefinition()
        definition.x.values = [AnimationValue(10)]
        definition.y.values = [AnimationValue(-5)]
        definition.z.values = [AnimationValue(3)]
        let result = try definition.createProcessor().update(makeEffectDescription(
            drawDescription: DrawDescription(
                draw: Vector3(x: 1, y: 1, z: 1), zoom: Vector2(x: 1, y: 1), opacity: 1
            )
        ))
        XCTAssertEqual(result.draw.x, 11, accuracy: 1e-9)
        XCTAssertEqual(result.draw.y, -4, accuracy: 1e-9)
        XCTAssertEqual(result.draw.z, 4, accuracy: 1e-9)
        XCTAssertEqual(result.controllers.count, 1)
        XCTAssertTrue(result.controllers.first?.owner === definition)
    }
}

// MARK: - イン／アウト

final class InOutEffectProcessorTests: XCTestCase {

    /// 線形イージング・1 秒に設定したフェード定義。
    private func makeLinearFade() -> InOutFadeEffectDefinition {
        let definition = InOutFadeEffectDefinition()
        definition.easingFamily = .linear
        definition.easingMode = .in
        definition.effectTimeSeconds = 1.0
        definition.value = 0
        return definition
    }

    func testFadeRates() throws {
        let processor = makeLinearFade().createProcessor()
        // 10 秒のアイテム、fps 10。開始直後は 0。
        var result = try processor.update(makeEffectDescription(frame: 0, duration: 100, fps: 10))
        XCTAssertEqual(result.opacity, 0, accuracy: 1e-9)
        // 0.5 秒経過で半分。
        result = try processor.update(makeEffectDescription(frame: 5, duration: 100, fps: 10))
        XCTAssertEqual(result.opacity, 0.5, accuracy: 1e-9)
        // 中央では完全に効く。
        result = try processor.update(makeEffectDescription(frame: 50, duration: 100, fps: 10))
        XCTAssertEqual(result.opacity, 1, accuracy: 1e-9)
        // 終了 0.1 秒前はアウト側で 0.1。
        result = try processor.update(makeEffectDescription(frame: 99, duration: 100, fps: 10))
        XCTAssertEqual(result.opacity, 0.1, accuracy: 1e-9)
    }

    func testMoveFromOutsideFrame() throws {
        let definition = InOutMoveFromOutsideFrameEffectDefinition()
        definition.easingFamily = .linear
        definition.easingMode = .in
        definition.effectTimeSeconds = 1.0
        XCTAssertEqual(definition.value, .left)
        let result = try definition.createProcessor().update(
            makeEffectDescription(frame: 5, duration: 100, fps: 10)
        )
        // 左から: -1920 → 0 の半分。
        XCTAssertEqual(result.draw.x, -960, accuracy: 1e-9)
        XCTAssertEqual(result.draw.y, 0, accuracy: 1e-9)
    }

    func testMoveAndZoom() throws {
        let move = InOutMoveEffectDefinition()
        move.easingFamily = .linear
        move.easingMode = .in
        move.effectTimeSeconds = 1.0
        move.value = 40
        var result = try move.createProcessor().update(
            makeEffectDescription(frame: 5, duration: 100, fps: 10)
        )
        XCTAssertEqual(result.draw.x, 20, accuracy: 1e-9)

        let zoom = InOutZoomEffectDefinition()
        zoom.easingFamily = .linear
        zoom.easingMode = .in
        zoom.effectTimeSeconds = 1.0
        zoom.value = 0
        zoom.x = 0
        zoom.y = 100
        result = try zoom.createProcessor().update(
            makeEffectDescription(frame: 5, duration: 100, fps: 10)
        )
        // X: (0 → 1 の半分 0.5) × 全体 (0 → 1 の半分 0.5) = 0.25。Y: 1 × 0.5。
        XCTAssertEqual(result.zoom.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(result.zoom.y, 0.5, accuracy: 1e-9)
    }

    func testInOutDefaultsAndRoundTrip() {
        let json: JSONValue = .object([
            (key: "$type", value: .string(InOutFadeEffectDefinition.typeName)),
            (key: "Value", value: .number(25)),
        ])
        let definition = VideoEffectRegistry.decode(PreservedObject(json)) as? InOutFadeEffectDefinition
        XCTAssertNotNil(definition)
        guard let definition else { return }
        XCTAssertEqual(definition.value, 25)
        XCTAssertTrue(definition.isInEffect)
        XCTAssertTrue(definition.isOutEffect)
        XCTAssertEqual(definition.effectTimeSeconds, 0.3)
        XCTAssertEqual(definition.easingFamily, .expo)
        XCTAssertEqual(definition.easingMode, .out)
        assertFixedPoint(definition)
    }
}

// MARK: - ランダム／反復

final class RandomRepeatEffectProcessorTests: XCTestCase {

    func testRandomMoveSpanZeroDeterminismAndRange() throws {
        let definition = RandomMoveEffectDefinition()
        definition.randomSeed = 42
        definition.span.values = [AnimationValue(0)]
        let first = definition.createProcessor()
        let second = definition.createProcessor()
        let description = makeEffectDescription(frame: 7)
        let a = try first.update(description)
        let b = try second.update(description)
        XCTAssertEqual(a.draw.x, b.draw.x, accuracy: 0)
        XCTAssertEqual(a.draw.y, b.draw.y, accuracy: 0)
        // Span = 0 の乱数は [0, 1) なので、振れは ±振れ幅/2 の範囲内。
        XCTAssertTrue((-50...50).contains(a.draw.x))
        XCTAssertTrue((-50...50).contains(a.draw.y))
        XCTAssertEqual(a.draw.z, 0, accuracy: 1e-9) // Z の既定振れ幅は 0。
    }

    func testRandomMoveSmoothSpanDeterminism() throws {
        let definition = RandomMoveEffectDefinition()
        definition.randomSeed = 7
        // Span は既定 0.13（滑らか）。
        let description = makeEffectDescription(frame: 11)
        let a = try definition.createProcessor().update(description)
        let b = try definition.createProcessor().update(description)
        XCTAssertEqual(a.draw.x, b.draw.x, accuracy: 0)
        XCTAssertTrue(a.draw.x.isFinite)
    }

    func testRepeatSpanZeroParity() throws {
        let definition = RepeatMoveEffectDefinition()
        definition.span.values = [AnimationValue(0)]
        definition.x.values = [AnimationValue(100)]
        definition.y.values = [AnimationValue(0)]
        definition.z.values = [AnimationValue(0)]
        let processor = definition.createProcessor()
        // 中央寄せあり: 偶数フレームは -50、奇数フレームは +50。
        var result = try processor.update(makeEffectDescription(frame: 2))
        XCTAssertEqual(result.draw.x, -50, accuracy: 1e-9)
        result = try processor.update(makeEffectDescription(frame: 3))
        XCTAssertEqual(result.draw.x, 50, accuracy: 1e-9)
        // 中央寄せなし: 偶数 0、奇数 100。
        definition.isCentering = false
        result = try processor.update(makeEffectDescription(frame: 2))
        XCTAssertEqual(result.draw.x, 0, accuracy: 1e-9)
        result = try processor.update(makeEffectDescription(frame: 3))
        XCTAssertEqual(result.draw.x, 100, accuracy: 1e-9)
    }

    func testRepeatSpanPositiveKnownPoint() throws {
        let definition = RepeatMoveEffectDefinition()
        definition.span.values = [AnimationValue(1.0)]
        definition.x.values = [AnimationValue(100)]
        definition.y.values = [AnimationValue(0)]
        definition.z.values = [AnimationValue(0)]
        // fps 10、フレーム 0: 中央寄せ＋InOut で時間を 1/4 進め、
        // 三角波の率は 0.5、Sine InOut(0.5) = 0.5 なので -50 + 100*0.5 = 0。
        let result = try definition.createProcessor().update(
            makeEffectDescription(frame: 0, fps: 10)
        )
        XCTAssertEqual(result.draw.x, 0, accuracy: 1e-9)
    }

    func testRepeatOpacityHasNoCentering() throws {
        let definition = RepeatOpacityEffectDefinition()
        definition.span.values = [AnimationValue(0)]
        definition.opacity.values = [AnimationValue(0)]
        XCTAssertFalse(definition.isCentering)
        let processor = definition.createProcessor()
        // 偶数フレームは from = 100 → 不透明度はそのまま。
        var result = try processor.update(makeEffectDescription(frame: 2))
        XCTAssertEqual(result.opacity, 1, accuracy: 1e-9)
        // 奇数フレームは to = 0 → 0。
        result = try processor.update(makeEffectDescription(frame: 3))
        XCTAssertEqual(result.opacity, 0, accuracy: 1e-9)
        // IsCentering は保存されない。
        let encoded = VideoEffectRegistry.encode(definition).value
        XCTAssertNil(encoded.field("IsCentering"))
        // ファイルに IsCentering があっても型付きにはならず生保持される。
        let json: JSONValue = .object([
            (key: "$type", value: .string(RepeatOpacityEffectDefinition.typeName)),
            (key: "IsCentering", value: .bool(true)),
        ])
        let decoded = VideoEffectRegistry.decode(PreservedObject(json)) as? RepeatOpacityEffectDefinition
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.additionalFields.map { $0.key }, ["IsCentering"])
        XCTAssertFalse(decoded?.isCentering ?? true)
    }
}

// MARK: - プレビュー専用／カメラ／極座標

final class CameraAndPreviewEffectProcessorTests: XCTestCase {

    func testShowOnlyPreview() throws {
        let definition = ShowOnlyPreviewEffectDefinition()
        let processor = definition.createProcessor()
        var result = try processor.update(makeEffectDescription(usage: .playing))
        XCTAssertEqual(result.opacity, 1, accuracy: 1e-9)
        result = try processor.update(makeEffectDescription(usage: .exporting))
        XCTAssertEqual(result.opacity, 0, accuracy: 1e-9)
        result = try processor.update(makeEffectDescription(usage: .paused))
        XCTAssertEqual(result.opacity, 0, accuracy: 1e-9)
        definition.isPaused = true
        result = try processor.update(makeEffectDescription(usage: .paused))
        XCTAssertEqual(result.opacity, 1, accuracy: 1e-9)
    }

    func testBillboard() throws {
        let definition = BillboardEffectDefinition()
        XCTAssertEqual(definition.mode, .spherical)
        var result = try definition.createProcessor().update(makeEffectDescription())
        XCTAssertEqual(result.billboard, .spherical)
        definition.mode = .none
        result = try definition.createProcessor().update(makeEffectDescription())
        XCTAssertEqual(result.billboard, .spherical)
        definition.mode = .cylindrical
        result = try definition.createProcessor().update(makeEffectDescription())
        XCTAssertEqual(result.billboard, .cylindrical)
    }

    func testCameraFov() throws {
        let definition = CameraFovEffectDefinition()
        // 既定の画角は高さ 1080 で距離 1000 になる値。
        var result = try definition.createProcessor().update(makeEffectDescription())
        XCTAssertEqual(result.perspectiveDistance ?? -1, 1000, accuracy: 1.0)
        definition.fov.values = [AnimationValue(0)]
        result = try definition.createProcessor().update(makeEffectDescription())
        XCTAssertEqual(result.perspectiveDistance, .infinity)
    }

    func testCameraPositionTranslationAndCenteredRotation() throws {
        let definition = CameraPositionEffectDefinition()
        definition.x.values = [AnimationValue(100)]
        var result = try definition.createProcessor().update(makeEffectDescription())
        XCTAssertEqual(result.camera.m41, -100, accuracy: 1e-9)
        XCTAssertEqual(result.camera.m42, 0, accuracy: 1e-9)
        XCTAssertEqual(result.camera.m43, 0, accuracy: 1e-9)

        definition.rotationZ.values = [AnimationValue(90)]
        result = try definition.createProcessor().update(makeEffectDescription())
        // (1000, 0, 0) は平行移動後に (900, 0, 0)、中心 (0,0,1000) まわりの
        // Z 回転 90 度で (0, 900, 0) になる。
        let transformed = result.camera.transform(Vector3(x: 1000, y: 0, z: 0))
        XCTAssertEqual(transformed.x, 0, accuracy: 1e-9)
        XCTAssertEqual(transformed.y, 900, accuracy: 1e-9)
        XCTAssertEqual(transformed.z, 0, accuracy: 1e-9)
    }

    func testCameraLookAtDefaultIsIdentity() throws {
        let definition = CameraLookAtEffectDefinition()
        let result = try definition.createProcessor().update(makeEffectDescription())
        XCTAssertEqual(result.camera, .identity)
        XCTAssertNil(result.perspectiveDistance)
    }

    func testPolarDrawPosition() throws {
        let definition = PolarDrawPositionEffectDefinition()
        definition.radius.values = [AnimationValue(100)]
        definition.angle.values = [AnimationValue(90)]
        definition.angle2.values = [AnimationValue(0)]
        let result = try definition.createProcessor().update(makeEffectDescription())
        XCTAssertEqual(result.draw.x, 0, accuracy: 1e-9)
        XCTAssertEqual(result.draw.y, 100, accuracy: 1e-9)
        // 同期: Z 回転へ 角度 + 90。
        XCTAssertEqual(result.rotation.z, 180, accuracy: 1e-9)
        XCTAssertEqual(result.rotation.y, 0, accuracy: 1e-9)
    }

    func testXYToPolarTransform() throws {
        let definition = XYToPolarTransformEffectDefinition()
        let result = try definition.createProcessor().update(makeEffectDescription(
            drawDescription: DrawDescription(
                draw: Vector3(x: 0, y: 50, z: 0), zoom: Vector2(x: 1, y: 1), opacity: 1
            )
        ))
        // Draw.x = 0 なので角度 0、Draw は (0, -50, 0) へ置き換わる。
        XCTAssertEqual(result.draw.x, 0, accuracy: 1e-9)
        XCTAssertEqual(result.draw.y, -50, accuracy: 1e-9)
        // 同期時の Z 回転には +170 の定数が入る。
        XCTAssertEqual(result.rotation.z, 170, accuracy: 1e-9)
    }
}

// MARK: - グループ描画

final class GroupedDrawingEffectTests: XCTestCase {

    func testGroupedDrawingTransform() throws {
        let group = GroupItem()
        group.x.values = [AnimationValue(10)]
        group.zoom.values = [AnimationValue(200)]
        let definition = GroupedDrawingEffectDefinition(group: group)
        XCTAssertTrue(definition.isEnabled)
        let result = try definition.createProcessor().update(makeEffectDescription(
            drawDescription: DrawDescription(
                draw: Vector3(x: 5, y: 5, z: 0), zoom: Vector2(x: 1, y: 1), opacity: 1
            )
        ))
        // 子の位置 (5, 5) を 2 倍してからグループ位置 (10, 0) を加える。
        XCTAssertEqual(result.draw.x, 20, accuracy: 1e-9)
        XCTAssertEqual(result.draw.y, 10, accuracy: 1e-9)
        XCTAssertEqual(result.zoom.x, 2, accuracy: 1e-9)
        XCTAssertEqual(result.zoom.y, 2, accuracy: 1e-9)
    }
}

// MARK: - モーショントラッキング

final class MotionTrackingEffectTests: XCTestCase {

    private func makeDefinition() -> MotionTrackingEffectDefinition {
        let definition = MotionTrackingEffectDefinition()
        definition.path.rects = [
            MotionTrackingRectValue(top: -50, bottom: 50, left: -50, right: 50),
            MotionTrackingRectValue(top: -50, bottom: 50, left: 50, right: 150),
        ]
        return definition
    }

    func testTrackingDelta() throws {
        let definition = makeDefinition()
        let result = try definition.createProcessor().update(makeEffectDescription(frame: 1))
        // 中心が (0, 0) → (100, 0) へ移動。同サイズなので拡縮なし。
        XCTAssertEqual(result.draw.x, 100, accuracy: 1e-9)
        XCTAssertEqual(result.draw.y, 0, accuracy: 1e-9)
        XCTAssertEqual(result.zoom.x, 1, accuracy: 1e-9)
        // 操作点: 矩形枠（現在フレームのみ）＋中心線＋現在矩形 = 3 組。
        XCTAssertEqual(result.controllers.count, 3)
    }

    func testTrackingReverseAndZoom() throws {
        let definition = makeDefinition()
        definition.isReverce = true
        var result = try definition.createProcessor().update(makeEffectDescription(frame: 1))
        XCTAssertEqual(result.draw.x, -100, accuracy: 1e-9)

        let zoomDefinition = MotionTrackingEffectDefinition()
        zoomDefinition.path.rects = [
            MotionTrackingRectValue(top: -50, bottom: 50, left: -50, right: 50),
            MotionTrackingRectValue(top: -100, bottom: 100, left: -100, right: 100),
        ]
        result = try zoomDefinition.createProcessor().update(makeEffectDescription(frame: 1))
        XCTAssertEqual(result.zoom.x, 2, accuracy: 1e-9)
        zoomDefinition.isFixedSize = true
        result = try zoomDefinition.createProcessor().update(makeEffectDescription(frame: 1))
        XCTAssertEqual(result.zoom.x, 1, accuracy: 1e-9)
    }

    func testTrackingEmptyAndEditing() throws {
        let empty = MotionTrackingEffectDefinition()
        var result = try empty.createProcessor().update(makeEffectDescription())
        XCTAssertEqual(result.draw.x, 0, accuracy: 1e-9)
        XCTAssertEqual(result.opacity, 1, accuracy: 1e-9)

        let editing = makeDefinition()
        editing.path.isEditing = true
        editing.path.target = .currentItem
        result = try editing.createProcessor().update(makeEffectDescription(frame: 1))
        XCTAssertEqual(result.draw.x, 0, accuracy: 1e-9)
        editing.path.target = .background
        result = try editing.createProcessor().update(makeEffectDescription(frame: 1))
        XCTAssertEqual(result.opacity, 0, accuracy: 1e-9)
    }

    func testPathRoundTripWithLegacyAlgorithmIndex() {
        let json: JSONValue = .object([
            (key: "$type", value: .string(MotionTrackingEffectDefinition.typeName)),
            (key: "Smooth", value: .number(2)),
            (key: "Path", value: .object([
                (key: "Target", value: .string("CurrentItem")),
                (key: "Rects", value: .array([
                    .object([
                        (key: "Top", value: .number(-10)),
                        (key: "Bottom", value: .number(10)),
                        (key: "Left", value: .number(-20)),
                        (key: "Right", value: .number(20)),
                        (key: "IsTracking", value: .bool(true)),
                    ]),
                ])),
                (key: "AlgorithmIndex", value: .number(3)),
            ])),
        ])
        let definition = VideoEffectRegistry.decode(PreservedObject(json)) as? MotionTrackingEffectDefinition
        XCTAssertNotNil(definition)
        guard let definition else { return }
        XCTAssertEqual(definition.smooth, 2)
        XCTAssertEqual(definition.path.target, .currentItem)
        XCTAssertEqual(definition.path.rects.count, 1)
        XCTAssertEqual(definition.path.rects.first?.left, -20)
        XCTAssertEqual(definition.path.rects.first?.isTracking, true)
        // 旧インデックス 3 は "Nano" へ変換され、AlgorithmIndex 自体は書き出されない。
        XCTAssertEqual(definition.path.algorithmName, "Nano")
        let encoded = VideoEffectRegistry.encode(definition).value
        XCTAssertNil(encoded.field("Path")?.field("AlgorithmIndex"))
        XCTAssertEqual(encoded.field("Path")?.field("AlgorithmName"), .string("Nano"))
        assertFixedPoint(definition)
    }
}

// MARK: - 連鎖契約への適合

private final class CountingProcessor: VideoEffectProcessor {
    private(set) var input: ImageReference?
    var output: ImageReference? { input }
    private(set) var setInputCount = 0
    private(set) var updateCount = 0
    private(set) var disposeCount = 0

    func setInput(_ image: ImageReference?) {
        setInputCount += 1
        input = image
    }

    func clearInput() {
        input = nil
    }

    func update(_ description: EffectDescription) throws -> DrawDescription {
        updateCount += 1
        var result = description.drawDescription
        result.opacity = 0.5
        return result
    }

    func dispose() {
        disposeCount += 1
    }
}

private final class CountingDefinition: VideoEffectDefinitionBase {
    private(set) var processors: [CountingProcessor] = []

    override func createProcessor() -> any VideoEffectProcessor {
        let processor = CountingProcessor()
        processors.append(processor)
        return processor
    }
}

final class EffectChainContractTests: XCTestCase {

    private func makeOutput(item: TextItem) -> EffectedOutput {
        EffectedOutput(item: item)
    }

    private func makeItemDescription() -> TimelineItemSourceDescription {
        let base = TimelineSourceDescription(
            screenSize: PixelSize(width: 1920, height: 1080),
            timelinePosition: FramePosition(frame: 0, fps: 30),
            timelineDuration: FramePosition(frame: 900, fps: 30),
            fps: 30,
            usage: .paused,
            sceneId: UUID(),
            scenes: []
        )
        return TimelineItemSourceDescription(base, itemFrame: 0, itemLength: 90, layer: 0)
    }

    func testReuseReplacementAndShrink() throws {
        let item = TextItem()
        let output = makeOutput(item: item)
        let definition = CountingDefinition()
        let pair = EffectPair(timeSource: item, definition: definition)
        let inputA = StandardSourceOutput(output: ImageReference(label: "a"), drawingEffect: nil)
        let description = makeItemDescription()

        // 1 回目: 処理器が生成され、SetInput → Update が走る。
        try output.update(
            inputIndex: 0, inputCount: 1, input: inputA,
            itemDescription: description, effects: [pair], applyItemTransform: false
        )
        XCTAssertEqual(definition.processors.count, 1)
        let processor = definition.processors[0]
        XCTAssertEqual(processor.setInputCount, 1)
        XCTAssertEqual(processor.updateCount, 1)
        XCTAssertEqual(output.drawDescription.opacity, 0.5, accuracy: 1e-9)

        // 2 回目（同じ定義・同じ入力）: 再利用され、SetInput は再発行されない。
        try output.update(
            inputIndex: 0, inputCount: 1, input: inputA,
            itemDescription: description, effects: [pair], applyItemTransform: false
        )
        XCTAssertEqual(definition.processors.count, 1)
        XCTAssertEqual(processor.setInputCount, 1)
        XCTAssertEqual(processor.updateCount, 2)

        // 3 回目（入力が差し替わる）: SetInput が再発行される。
        let inputB = StandardSourceOutput(output: ImageReference(label: "b"), drawingEffect: nil)
        try output.update(
            inputIndex: 0, inputCount: 1, input: inputB,
            itemDescription: description, effects: [pair], applyItemTransform: false
        )
        XCTAssertEqual(processor.setInputCount, 2)
        XCTAssertEqual(processor.updateCount, 3)

        // 4 回目（定義が差し替わる）: 新しい処理器が作られ、旧処理器は
        // 新側の更新完了後に破棄される。
        let replacement = CountingDefinition()
        try output.update(
            inputIndex: 0, inputCount: 1, input: inputB,
            itemDescription: description,
            effects: [EffectPair(timeSource: item, definition: replacement)],
            applyItemTransform: false
        )
        XCTAssertEqual(replacement.processors.count, 1)
        XCTAssertEqual(processor.disposeCount, 1)

        // 5 回目（連鎖が縮む）: 末尾の処理器が破棄される。
        try output.update(
            inputIndex: 0, inputCount: 1, input: inputB,
            itemDescription: description, effects: [], applyItemTransform: false
        )
        XCTAssertEqual(replacement.processors[0].disposeCount, 1)
    }
}

// MARK: - 供給元（EffectPairProvider）

final class TypedEffectPairProviderTests: XCTestCase {

    func testOwnPairsCacheAndUnknownSkip() {
        let item = TextItem()
        item.videoEffects = [
            PreservedObject(.object([
                (key: "$type", value: .string(ZoomEffectDefinition.typeName)),
            ])),
            PreservedObject(.object([
                (key: "$type", value: .string(
                    "YukkuriMovieMaker.Project.Effects.ColorCorrectionEffect, YukkuriMovieMaker")),
            ])),
        ]
        let provider = TypedEffectPairProvider()
        let first = provider.ownEffectPairs(for: item)
        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(first[0].definition is ZoomEffectDefinition)
        XCTAssertTrue(first[0].timeSource === item)
        // 2 回目は同じ定義インスタンス（連鎖の再利用判定が同一性のため）。
        let second = provider.ownEffectPairs(for: item)
        XCTAssertTrue(first[0].definition as AnyObject === second[0].definition as AnyObject)
    }

    func testGroupPairsAppendGroupedDrawing() {
        let group = GroupItem()
        group.videoEffects = [
            PreservedObject(.object([
                (key: "$type", value: .string(OpacityEffectDefinition.typeName)),
            ])),
        ]
        let provider = TypedEffectPairProvider()
        let pairs = provider.groupEffectPairs(for: group, childIndex: 2, childCount: 5)
        XCTAssertEqual(pairs.count, 2)
        XCTAssertTrue(pairs[0].definition is OpacityEffectDefinition)
        XCTAssertTrue(pairs[1].definition is GroupedDrawingEffectDefinition)
        XCTAssertEqual(pairs[1].groupIndex, 2)
        XCTAssertEqual(pairs[1].groupCount, 5)
        let again = provider.groupEffectPairs(for: group, childIndex: 0, childCount: 1)
        XCTAssertTrue(pairs[1].definition as AnyObject === again[1].definition as AnyObject)
    }

    func testFacePairs() {
        let face = TachieFaceItem()
        face.tachieFaceEffects = [
            PreservedObject(.object([
                (key: "$type", value: .string(ZoomEffectDefinition.typeName)),
            ])),
        ]
        let provider = TypedEffectPairProvider()
        let pairs = provider.faceEffectPairs(for: face)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertTrue(pairs[0].timeSource === face)

        let voice = VoiceItem()
        voice.tachieFaceEffects = [
            PreservedObject(.object([
                (key: "$type", value: .string(OpacityEffectDefinition.typeName)),
            ])),
        ]
        XCTAssertEqual(provider.faceEffectPairs(for: voice).count, 1)
        // 顔アイテムでないものには供給しない。
        XCTAssertTrue(provider.faceEffectPairs(for: TextItem()).isEmpty)
    }

    func testDisabledDefinitionsAreMarkedForChainFiltering() {
        let item = TextItem()
        item.videoEffects = [
            PreservedObject(.object([
                (key: "$type", value: .string(ZoomEffectDefinition.typeName)),
                (key: "IsEnabled", value: .bool(false)),
            ])),
        ]
        let provider = TypedEffectPairProvider()
        let pairs = provider.ownEffectPairs(for: item)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertFalse(pairs[0].definition.isEnabled)
    }
}

// MARK: - VoiceItem の字幕エフェクト解決の接続（MAC-0020）

/// 供給元が VoiceItem の字幕エフェクトを、保持列ではなく JimakuVisibility
/// による解決済み列（MAC-0014 の `resolvedVideoEffects`）から復元すること
/// の検証。自前とキャラクター側は定義型で区別する（自前 = Zoom、
/// キャラクター側 = Opacity）。
final class TypedEffectPairProviderVoiceJimakuTests: XCTestCase {

    private func rawEffect(_ typeName: String) -> PreservedObject {
        PreservedObject(.object([(key: "$type", value: .string(typeName))]))
    }

    private func makeVoice(
        visibility: JimakuVisibility, character: Character?
    ) -> VoiceItem {
        let voice = VoiceItem()
        voice.jimakuVisibility = visibility
        voice.videoEffects = [rawEffect(ZoomEffectDefinition.typeName)]
        voice.character = character
        return voice
    }

    private func makeCharacter(isJimakuVisible: Bool = true) -> Character {
        let character = Character()
        character.name = "テストキャラ"
        character.isJimakuVisible = isJimakuVisible
        character.jimakuVideoEffects = [rawEffect(OpacityEffectDefinition.typeName)]
        return character
    }

    func testCustomUsesOwnEffects() {
        // キャラクターが解決されていても、Custom では自前のエフェクトだけが効く。
        let voice = makeVoice(visibility: .custom, character: makeCharacter())
        let provider = TypedEffectPairProvider()
        let pairs = provider.ownEffectPairs(for: voice)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertTrue(pairs[0].definition is ZoomEffectDefinition)
        XCTAssertTrue(pairs[0].timeSource === voice)
    }

    func testVisibleUsesCharacterEffectsNotOwn() {
        // Custom 以外ではキャラクター側が効き、自前は効かない。
        let voice = makeVoice(visibility: .visible, character: makeCharacter())
        let provider = TypedEffectPairProvider()
        let pairs = provider.ownEffectPairs(for: voice)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertTrue(pairs[0].definition is OpacityEffectDefinition)
        XCTAssertTrue(pairs[0].timeSource === voice)
    }

    func testUseCharacterSettingFollowsCharacterJimakuVisibility() {
        let character = makeCharacter()
        let voice = makeVoice(visibility: .useCharacterSetting, character: character)
        let provider = TypedEffectPairProvider()
        // キャラクター側で字幕が表示される間はキャラクター側のエフェクト。
        let pairs = provider.ownEffectPairs(for: voice)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertTrue(pairs[0].definition is OpacityEffectDefinition)
        // キャラクター側で字幕が非表示になると、解決済み列は空になる。
        character.isJimakuVisible = false
        XCTAssertTrue(provider.ownEffectPairs(for: voice).isEmpty)
    }

    func testHiddenYieldsNoEffects() {
        let voice = makeVoice(visibility: .hidden, character: makeCharacter())
        let provider = TypedEffectPairProvider()
        XCTAssertTrue(provider.ownEffectPairs(for: voice).isEmpty)
    }

    func testUnresolvedCharacterFallsBackToOwnEffects() throws {
        // CharacterName がどのキャラクターとも一致しないファイルでは参照が
        // 未解決（character == nil）のまま残り、供給元は自前の保持列へ
        // フォールバックする。
        let project = Project()
        let timeline = Timeline()
        let character = Character()
        character.name = "別キャラ"
        character.jimakuVideoEffects = [rawEffect(OpacityEffectDefinition.typeName)]
        project.characters.append(character)
        let voice = VoiceItem()
        voice.frame = 0
        voice.length = 90
        voice.layer = 0
        voice.characterName = "テストキャラ"
        voice.jimakuVisibility = .visible
        voice.videoEffects = [rawEffect(ZoomEffectDefinition.typeName)]
        timeline.items = [voice]
        project.timelines.append(timeline)

        let (decoded, _) = try YmmpCodec.decode(YmmpCodec.encode(project))
        let decodedVoice = try XCTUnwrap(
            decoded.timelines.first?.items.compactMap { $0 as? VoiceItem }.first
        )
        XCTAssertNil(decodedVoice.character)

        let provider = TypedEffectPairProvider()
        let pairs = provider.ownEffectPairs(for: decodedVoice)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertTrue(pairs[0].definition is ZoomEffectDefinition)
    }
}
