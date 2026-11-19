import XCTest
@testable import YMM4Core

/// ImageReference の役割（role）の検証。Flood 代替トークンの識別を
/// ラベル文字列から型付きの役割へ移したこと（ラベル依存の解消）に伴う。
final class ImageReferenceRoleTests: XCTestCase {

    func testDefaultRoleIsNormal() {
        XCTAssertEqual(ImageReference().role, .normal)
        XCTAssertEqual(ImageReference(label: "flood").role, .normal)
    }

    func testRoleIsIndependentOfLabel() {
        // ラベルが "flood" でも役割は通常でありうるし、役割を持つ
        // トークンのラベルは何でもよい。識別は役割だけで行う。
        let substitute = ImageReference(label: "anything", role: .floodSubstitute)
        XCTAssertEqual(substitute.role, .floodSubstitute)
        XCTAssertEqual(substitute.label, "anything")

        let labeledOnly = ImageReference(label: "flood")
        XCTAssertEqual(labeledOnly.label, "flood")
        XCTAssertEqual(labeledOnly.role, .normal)
    }
}

/// 合成器がクリッピングのマスクとして渡す参照の役割の検証。
final class TimelineComposerFloodTokenTests: XCTestCase {

    private func makeComposer(
        timeline: Timeline,
        maskFactory: FakeAlphaMaskFactory
    ) -> TimelineComposer {
        let log = CompositionEventLog()
        let factory = RecordingTargetFactory(log: log)
        return TimelineComposer(
            scene: TimelineScene(timeline: timeline),
            targetFactory: factory,
            sourceProvider: { _ in
                let source = FakeChainSource()
                source.outputs = [StandardSourceOutput(
                    output: ImageReference(label: "img"),
                    drawingEffect: CompositionFakeDrawingEffect(name: "DE", log: log)
                )]
                return source
            },
            effectProvider: FakeEffectProvider(),
            alphaMaskFactory: maskFactory
        )
    }

    func testClippingWithoutPreviousImagePassesFloodSubstituteToken() throws {
        let timeline = Timeline()
        let item = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 0)
        item.isClippingWithObjectAbove = true
        timeline.items = [item]
        let maskFactory = FakeAlphaMaskFactory()
        let composer = makeComposer(timeline: timeline, maskFactory: maskFactory)

        try composer.update(time: .zero, usage: .paused)

        // 直前の画像が無いため、合成器は Flood 代替トークンを渡す。
        // その素性はラベルではなく役割でなければならない。
        XCTAssertEqual(maskFactory.masks.count, 1)
        let passed = try XCTUnwrap(maskFactory.masks[0].inputs[1] ?? nil)
        XCTAssertEqual(passed.role, .floodSubstitute)
    }

    func testClippingWithPreviousImagePassesPreviousOutput() throws {
        let timeline = Timeline()
        let below = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 0)
        let clipping = makeVisualItem(TextItem(), frame: 0, length: 90, layer: 1)
        clipping.isClippingWithObjectAbove = true
        timeline.items = [below, clipping]
        let maskFactory = FakeAlphaMaskFactory()
        let composer = makeComposer(timeline: timeline, maskFactory: maskFactory)

        try composer.update(time: .zero, usage: .paused)

        // 直前の画像がある場合はその出力が渡り、Flood 代替にはならない。
        XCTAssertEqual(maskFactory.masks.count, 1)
        let passed = try XCTUnwrap(maskFactory.masks[0].inputs[1] ?? nil)
        XCTAssertEqual(passed.role, .normal)
    }
}
