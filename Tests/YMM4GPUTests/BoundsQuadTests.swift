import XCTest
@testable import YMM4Core
@testable import YMM4GPU

/// テスト用の説明（画面 320×240、30fps、アイテムは先頭から90フレーム）。
private func makeEffectDescription(_ drawDescription: DrawDescription) -> EffectDescription {
    let base = TimelineSourceDescription(
        screenSize: PixelSize(width: 320, height: 240),
        timelinePosition: FramePosition(frame: 0, fps: 30),
        timelineDuration: FramePosition(frame: 90, fps: 30),
        fps: 30,
        usage: .paused,
        sceneId: UUID(),
        scenes: []
    )
    let item = TimelineItemSourceDescription(base, itemFrame: 0, itemLength: 90, layer: 0)
    return EffectDescription(itemDescription: item, drawDescription: drawDescription)
}

private func assertQuad(
    _ actual: [Vector2]?, equals expected: [Vector2],
    accuracy: Double = 1e-9,
    file: StaticString = #filePath, line: UInt = #line
) {
    guard let actual else {
        XCTFail("四隅が nil", file: file, line: line)
        return
    }
    XCTAssertEqual(actual.count, expected.count, file: file, line: line)
    for (a, e) in zip(actual, expected) {
        XCTAssertEqual(a.x, e.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.y, e.y, accuracy: accuracy, file: file, line: line)
    }
}

/// MetalDrawingEffect.boundsQuad（FE-R1-023-B）: 本家
/// TransformBoundsQuad に対応し、入力境界の四隅へ合成変換
/// （入力自身の変換 → ズーム → ワールド → 透視）を適用した四隅を
/// 返すことを、実デバイスの文脈で固定する。
final class MetalDrawingEffectBoundsQuadTests: XCTestCase {

    private let inputBounds = RectF(left: -50, top: -25, right: 50, bottom: 25)

    private func makeEffect(
        devices: MetalGraphicsDevices, context: MetalGraphicsContext
    ) -> MetalDrawingEffect {
        let effect = MetalDrawingEffect(context: context)
        let token = ImageReference(label: "quad-input")
        devices.register(
            token,
            image: MetalImage(
                texture: devices.transparentTexture, bounds: inputBounds
            )
        )
        effect.setInput(token)
        return effect
    }

    /// 変換なしでは入力境界の四隅がそのまま返る。
    func testIdentityReturnsInputBoundsCorners() throws {
        let devices = try MetalGraphicsDevices()
        let context = devices.makeContext(targetSize: PixelSize(width: 320, height: 240))
        let effect = makeEffect(devices: devices, context: context)

        try effect.update(makeEffectDescription(DrawDescription(opacity: 1)))

        assertQuad(effect.boundsQuad(), equals: [
            Vector2(x: -50, y: -25), Vector2(x: 50, y: -25),
            Vector2(x: 50, y: 25), Vector2(x: -50, y: 25),
        ])
    }

    /// 平行移動は四隅へそのまま加わる（z = 0 の点では透視の w は 1）。
    func testTranslationShiftsQuad() throws {
        let devices = try MetalGraphicsDevices()
        let context = devices.makeContext(targetSize: PixelSize(width: 320, height: 240))
        let effect = makeEffect(devices: devices, context: context)
        var draw = DrawDescription(opacity: 1)
        draw.draw = Vector3(x: 10, y: 20, z: 0)

        try effect.update(makeEffectDescription(draw))

        assertQuad(effect.boundsQuad(), equals: [
            Vector2(x: -40, y: -5), Vector2(x: 60, y: -5),
            Vector2(x: 60, y: 45), Vector2(x: -40, y: 45),
        ])
    }

    /// ズーム2倍は中心（原点）から四隅を2倍へ広げる。
    func testZoomScalesQuad() throws {
        let devices = try MetalGraphicsDevices()
        let context = devices.makeContext(targetSize: PixelSize(width: 320, height: 240))
        let effect = makeEffect(devices: devices, context: context)
        var draw = DrawDescription(opacity: 1)
        draw.zoom = Vector2(x: 2, y: 2)

        try effect.update(makeEffectDescription(draw))

        assertQuad(effect.boundsQuad(), equals: [
            Vector2(x: -100, y: -50), Vector2(x: 100, y: -50),
            Vector2(x: 100, y: 50), Vector2(x: -100, y: 50),
        ])
    }

    /// Z 回転 180° は四隅の符号を反転させる（順序は保たれる）。
    func testRotation180FlipsQuad() throws {
        let devices = try MetalGraphicsDevices()
        let context = devices.makeContext(targetSize: PixelSize(width: 320, height: 240))
        let effect = makeEffect(devices: devices, context: context)
        var draw = DrawDescription(opacity: 1)
        draw.rotation = Vector3(x: 0, y: 0, z: 180)

        try effect.update(makeEffectDescription(draw))

        assertQuad(effect.boundsQuad(), equals: [
            Vector2(x: 50, y: 25), Vector2(x: -50, y: 25),
            Vector2(x: -50, y: -25), Vector2(x: 50, y: -25),
        ], accuracy: 1e-6)
    }

    /// Z 回転 90° の四隅は、回転行列を四隅へ適用した値と一致する
    /// （合成変換の結線: ズーム・ワールド・透視の順序と w 除算）。
    /// z = 0 の回転では透視の w は 1 のため、期待値は回転のみで決まる。
    func testRotation90MatchesMatrixApplication() throws {
        let devices = try MetalGraphicsDevices()
        let context = devices.makeContext(targetSize: PixelSize(width: 320, height: 240))
        let effect = makeEffect(devices: devices, context: context)
        var draw = DrawDescription(opacity: 1)
        draw.rotation = Vector3(x: 0, y: 0, z: 90)

        try effect.update(makeEffectDescription(draw))

        let rotation = Matrix4x4.createRotationZ(.pi / 2)
        let expected = [
            Vector3(x: -50, y: -25, z: 0), Vector3(x: 50, y: -25, z: 0),
            Vector3(x: 50, y: 25, z: 0), Vector3(x: -50, y: 25, z: 0),
        ].map { corner in
            let v = rotation.transform(corner)
            return Vector2(x: v.x, y: v.y)
        }
        assertQuad(effect.boundsQuad(), equals: expected, accuracy: 1e-6)
    }

    /// 未更新・入力なしでは四隅は取得できない。
    func testNoInputReturnsNil() throws {
        let devices = try MetalGraphicsDevices()
        let context = devices.makeContext(targetSize: PixelSize(width: 320, height: 240))
        let effect = MetalDrawingEffect(context: context)

        XCTAssertNil(effect.boundsQuad())
        try effect.update(makeEffectDescription(DrawDescription(opacity: 1)))
        XCTAssertNil(effect.boundsQuad())
    }
}

/// MetalEffectItemDrawingEffect.boundsQuad（FE-R1-023-B）: 本家
/// IBoundsQuadProvider（Mask.GetBoundsQuad）に対応する独自四隅。
/// マスク図形の境界へマスク変換（平行移動・回転・カメラ・透視）を
/// 適用した四隅が返ることを、平行移動の相対変化で固定する
/// （図形の実寸は図形パラメータの評価に委ね、ここでは変換の結線を
/// 検証する）。
final class MetalEffectItemDrawingEffectBoundsQuadTests: XCTestCase {

    func testMaskQuadFollowsDrawTranslation() throws {
        let devices = try MetalGraphicsDevices()
        let context = devices.makeContext(targetSize: PixelSize(width: 320, height: 240))
        let item = EffectItem()
        let effect = MetalEffectItemDrawingEffect(context: context, item: item)
        let inputToken = ImageReference(label: "mask-item-input")
        devices.register(
            inputToken,
            image: MetalImage(
                texture: devices.transparentTexture,
                bounds: RectF(left: -80, top: -60, right: 80, bottom: 60)
            )
        )
        effect.setInput(inputToken)

        XCTAssertTrue(effect.providesCustomBoundsQuad)
        try effect.update(makeEffectDescription(DrawDescription(opacity: 1)))
        let base = try XCTUnwrap(effect.boundsQuad())
        XCTAssertEqual(base.count, 4)

        var moved = DrawDescription(opacity: 1)
        moved.draw = Vector3(x: 10, y: 20, z: 0)
        try effect.update(makeEffectDescription(moved))
        let shifted = try XCTUnwrap(effect.boundsQuad())
        // 平行移動 (10, 20) が四隅へそのまま加わる（z = 0 の移動では
        // 透視の w は 1 のまま）。
        assertQuad(shifted, equals: base.map {
            Vector2(x: $0.x + 10, y: $0.y + 20)
        }, accuracy: 1e-6)
    }
}

/// マスク合成（MetalAlphaMaskEffect）の出力実体と planeOffset の
/// 前提（FE-R1-023-B の調査結果）を固定するテスト群。
///
/// 023-A の AABB 算出は、アイテム出力トークンの実体について
/// 「bounds が描画位置を表し、planeOffset は 0」という前提に乗り、
/// planeOffset を加算していない。この前提が崩れると AABB が
/// 描画位置からずれるため、登録経路ごとに実体を実測して固定する:
/// - マスク未設定（全面透明の登録）: bounds = 入力の境界、
///   planeOffset = 0、transform = 恒等。
/// - マスク適用（renderWarp の結果）: 同上。
/// - flood（直前の画像が無い場合の恒等経路）: 入力実体そのもの。
/// あわせて、planeOffset は描画先への描画で頂点位置に入らず
/// （UV サンプリングだけをずらす）、描画位置は bounds と transform
/// だけで決まることも固定する。
final class AlphaMaskPlaneOffsetTests: XCTestCase {

    private let sourceBounds = RectF(left: -20, top: -10, right: 20, bottom: 10)

    private func makeSource(
        devices: MetalGraphicsDevices
    ) -> ImageReference {
        let token = ImageReference(label: "mask-source")
        devices.register(
            token,
            image: MetalImage(
                texture: devices.transparentTexture, bounds: sourceBounds
            )
        )
        return token
    }

    /// マスク未設定では全面透明が入力の境界で登録され、
    /// planeOffset は 0、transform は恒等。
    func testTransparentPathRegistrationHasNoPlaneOffset() throws {
        let devices = try MetalGraphicsDevices()
        let context = devices.makeContext(targetSize: PixelSize(width: 64, height: 64))
        let effect = MetalAlphaMaskEffect(context: context)
        effect.setInput(0, makeSource(devices: devices))

        let output = try XCTUnwrap(effect.output)
        let image = try XCTUnwrap(devices.image(for: output))
        XCTAssertEqual(image.bounds, sourceBounds)
        XCTAssertEqual(image.planeOffset, .zero)
        XCTAssertEqual(image.transform, .identity)
    }

    /// マスク適用（renderWarp）後の出力も、境界は入力の境界のまま、
    /// planeOffset は 0、transform は恒等で登録される。
    func testWarpPathRegistrationHasNoPlaneOffset() throws {
        let devices = try MetalGraphicsDevices()
        let context = devices.makeContext(targetSize: PixelSize(width: 64, height: 64))
        let maskToken = ImageReference(label: "mask-image")
        devices.register(
            maskToken,
            image: MetalImage(
                texture: devices.transparentTexture, bounds: sourceBounds
            )
        )
        let effect = MetalAlphaMaskEffect(context: context)
        effect.setInput(0, makeSource(devices: devices))
        effect.setInput(1, maskToken)

        let output = try XCTUnwrap(effect.output)
        let image = try XCTUnwrap(devices.image(for: output))
        XCTAssertEqual(image.bounds, sourceBounds)
        XCTAssertEqual(image.planeOffset, .zero)
        XCTAssertEqual(image.transform, .identity)
    }

    /// flood（未登録の代替トークン）では入力実体そのものが登録され、
    /// その planeOffset（描画先の出力は 0）もそのまま伝わる。
    func testFloodPathRegistersSourceItself() throws {
        let devices = try MetalGraphicsDevices()
        let context = devices.makeContext(targetSize: PixelSize(width: 64, height: 64))
        let effect = MetalAlphaMaskEffect(context: context)
        effect.setInput(0, makeSource(devices: devices))
        effect.setInput(1, ImageReference(label: "flood"))

        let output = try XCTUnwrap(effect.output)
        let image = try XCTUnwrap(devices.image(for: output))
        XCTAssertEqual(image.bounds, sourceBounds)
        XCTAssertEqual(image.planeOffset, .zero)
        XCTAssertEqual(image.transform, .identity)
    }

    /// planeOffset を持つ画像を描画先へ描いても、内容境界（描画
    /// 位置）は planeOffset でずれない。planeOffset は UV
    /// サンプリングのずれであり、描画位置は bounds と transform
    /// だけで決まる（AABB 算出へ planeOffset の加算が不要な根拠）。
    func testPlaneOffsetDoesNotShiftDrawnFootprint() throws {
        let devices = try MetalGraphicsDevices()
        let context = devices.makeContext(targetSize: PixelSize(width: 64, height: 64))
        let token = ImageReference(label: "offset-image")
        devices.register(
            token,
            image: MetalImage(
                texture: devices.transparentTexture,
                bounds: sourceBounds,
                planeOffset: Vector2(x: 30, y: 40)
            )
        )
        let target = context.makeTarget()
        target.beginDraw()
        target.drawImage(token)
        target.endDraw()
        try target.close()

        let image = try XCTUnwrap(devices.image(for: target.image))
        XCTAssertEqual(image.bounds, sourceBounds)
    }
}
