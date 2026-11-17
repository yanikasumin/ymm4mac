import XCTest
@testable import YMM4Core

// MARK: - 偽の実装（Source 契約の検証用）

private final class FakeDrawingEffect: DrawingEffectProcessor {
    var output: ImageReference?
    private(set) var input: ImageReference?
    private(set) var clearInputCallCount = 0
    private(set) var disposed = false

    func setInput(_ image: ImageReference?) {
        input = image
    }

    func clearInput() {
        clearInputCallCount += 1
        input = nil
    }

    func update(_ description: EffectDescription) -> DrawDescription {
        description.drawDescription
    }

    func dispose() {
        disposed = true
    }
}

private final class FakeSource: Source {
    var controllers: [VideoController] = []
    var outputs: [any SourceOutput] = []
    private(set) var lastDescription: TimelineItemSourceDescription?
    private(set) var updateCount = 0
    private(set) var disposed = false

    func update(_ description: TimelineItemSourceDescription) throws {
        lastDescription = description
        updateCount += 1
    }

    func dispose() {
        disposed = true
    }
}

private func makeBaseDescription() -> TimelineSourceDescription {
    TimelineSourceDescription(
        screenSize: PixelSize(width: 1920, height: 1080),
        timelinePosition: FramePosition(frame: 0, fps: 30),
        timelineDuration: FramePosition(frame: 900, fps: 30),
        fps: 30,
        usage: .paused,
        sceneId: UUID(),
        scenes: []
    )
}

// MARK: - Source 契約

final class SourceContractTests: XCTestCase {

    func testSourceReceivesDescriptionOnUpdate() throws {
        let source = FakeSource()
        let effect = FakeDrawingEffect()
        let image = ImageReference(label: "fake")
        source.outputs = [StandardSourceOutput(output: image, drawingEffect: effect)]

        let itemDescription = TimelineItemSourceDescription(
            makeBaseDescription(), itemFrame: 15, itemLength: 60, layer: 3
        )
        try source.update(itemDescription)

        XCTAssertEqual(source.updateCount, 1)
        XCTAssertEqual(source.lastDescription?.itemPosition.frame, 15)
        XCTAssertEqual(source.lastDescription?.itemDuration.frame, 60)
        XCTAssertEqual(source.lastDescription?.layer, 3)
        XCTAssertEqual(source.lastDescription?.fps, 30)
        XCTAssertEqual(source.outputs.count, 1)
        XCTAssertTrue(source.outputs[0].output === image)
        XCTAssertTrue(source.outputs[0].drawingEffect === effect)
        XCTAssertEqual(source.outputs[0].timeOffset, .zero)
        XCTAssertEqual(source.outputs[0].durationOffset, .zero)
    }

    func testStandardSourceOutputDisposesOwnedEffect() {
        let effect = FakeDrawingEffect()
        effect.setInput(ImageReference())
        let output = StandardSourceOutput(
            output: ImageReference(), drawingEffect: effect, dontDispose: false
        )
        output.dispose()
        XCTAssertEqual(effect.clearInputCallCount, 1)
        XCTAssertTrue(effect.disposed)
        // 二重に呼んでも破棄は1回だけ。
        output.dispose()
        XCTAssertEqual(effect.clearInputCallCount, 1)
    }

    func testStandardSourceOutputDoesNotDisposeBorrowedEffect() {
        let effect = FakeDrawingEffect()
        let output = StandardSourceOutput(
            output: ImageReference(), drawingEffect: effect, dontDispose: true
        )
        output.dispose()
        XCTAssertEqual(effect.clearInputCallCount, 0)
        XCTAssertFalse(effect.disposed)
    }

    func testItemDescriptionInheritsRenderScaleFromParentItemDescription() {
        var parent = TimelineItemSourceDescription(
            makeBaseDescription(), itemFrame: 0, itemLength: 90, layer: 0
        )
        parent.renderScale = 2.5
        let child = TimelineItemSourceDescription(parent, itemFrame: 10, itemLength: 30, layer: 1)
        XCTAssertEqual(child.renderScale, 2.5)
        XCTAssertEqual(child.itemPosition.fps, 30)

        let fromBase = TimelineItemSourceDescription(
            makeBaseDescription(), itemFrame: 0, itemLength: 90, layer: 0
        )
        XCTAssertEqual(fromBase.renderScale, 1)
    }

    func testComposeRenderScale() {
        XCTAssertEqual(
            TimelineItemSourceDescription.composeRenderScale(parentRenderScale: nil, itemScale: 2),
            2
        )
        XCTAssertEqual(
            TimelineItemSourceDescription.composeRenderScale(parentRenderScale: 2, itemScale: 0.5),
            1
        )
        // 不正なアイテムスケールは 1 として扱う。
        XCTAssertEqual(
            TimelineItemSourceDescription.composeRenderScale(parentRenderScale: 2, itemScale: 0),
            2
        )
        XCTAssertEqual(
            TimelineItemSourceDescription.composeRenderScale(parentRenderScale: 2, itemScale: .nan),
            2
        )
        // 不正な親スケールは 1 として扱う。
        XCTAssertEqual(
            TimelineItemSourceDescription.composeRenderScale(parentRenderScale: -1, itemScale: 3),
            3
        )
        // 積が float の最大値を超える場合は 1。
        XCTAssertEqual(
            TimelineItemSourceDescription.composeRenderScale(parentRenderScale: 1e38, itemScale: 1e38),
            1
        )
    }

    func testFramePositionTime() {
        XCTAssertEqual(FramePosition(frame: 30, fps: 30).time, 1.0, accuracy: 1e-9)
        XCTAssertEqual(FramePosition(frame: 45, fps: 30).time, 1.5, accuracy: 1e-9)
    }
}
