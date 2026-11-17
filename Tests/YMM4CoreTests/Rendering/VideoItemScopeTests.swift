import XCTest
@testable import YMM4Core

// MARK: - 映像アイテムの範囲（MAC-0011）

final class VideoItemScopeTests: XCTestCase {

    /// 映像アイテムの範囲は本家 IVideoItem の実装範囲どおり:
    /// VisualItem 系譜 + VoiceItem + TransitionItem。TachieFaceItem と
    /// AudioItem は含まない。
    func testVideoItemEquivalentScope() {
        XCTAssertTrue(isVideoItemEquivalent(TextItem()))
        XCTAssertTrue(isVideoItemEquivalent(TachieItem()))
        XCTAssertTrue(isVideoItemEquivalent(VoiceItem()))
        XCTAssertTrue(isVideoItemEquivalent(TransitionItem()))
        XCTAssertFalse(isVideoItemEquivalent(TachieFaceItem()))
        XCTAssertFalse(isVideoItemEquivalent(AudioItem()))
    }

    /// PickFaceItems の対象（TachieFaceItem / VoiceItem が IFaceItem で
    /// ある点）は、映像アイテム範囲の是正後も本家どおり維持される。
    func testPickFaceItemsScopeUnchanged() {
        let timeline = Timeline()
        let voice = VoiceItem()
        voice.frame = 0
        voice.length = 90
        voice.layer = 2
        let face = TachieFaceItem()
        face.frame = 0
        face.length = 90
        face.layer = 3
        let text = TextItem()
        text.frame = 0
        text.length = 90
        text.layer = 1
        timeline.items = [voice, face, text]

        let picked = CompositeItemPicker().pickFaceItems(in: timeline, frame: 0)
        XCTAssertEqual(
            Set(picked.map { ObjectIdentifier($0) }),
            [ObjectIdentifier(voice), ObjectIdentifier(face)]
        )
    }

    /// TimelineComposer の資源対象が本家 IVideoItem の範囲に一致する:
    /// VoiceItem / TransitionItem は資源を持って更新され、TachieFaceItem は
    /// 資源を持たない（Source が要求されない）。
    func testComposerResourceScope() throws {
        let log = CompositionEventLog()
        let factory = RecordingTargetFactory(log: log)
        let timeline = Timeline()
        let voice = VoiceItem()
        voice.frame = 0
        voice.length = 90
        voice.layer = 2
        let transition = TransitionItem()
        transition.frame = 0
        transition.length = 90
        transition.layer = 1
        let face = TachieFaceItem()
        face.frame = 0
        face.length = 90
        face.layer = 3
        timeline.items = [voice, transition, face]

        var requested: [ObjectIdentifier] = []
        var sources: [ObjectIdentifier: FakeChainSource] = [:]
        let composer = TimelineComposer(
            scene: TimelineScene(timeline: timeline),
            targetFactory: factory,
            sourceProvider: { item in
                requested.append(ObjectIdentifier(item))
                let source = FakeChainSource()
                source.outputs = [StandardSourceOutput(
                    output: ImageReference(label: "img"),
                    drawingEffect: CompositionFakeDrawingEffect(name: "DE", log: log)
                )]
                sources[ObjectIdentifier(item)] = source
                return source
            }
        )
        try composer.update(time: .zero, usage: .paused)

        XCTAssertTrue(requested.contains(ObjectIdentifier(voice)))
        XCTAssertTrue(requested.contains(ObjectIdentifier(transition)))
        XCTAssertEqual(sources[ObjectIdentifier(voice)]?.updateCount, 1)
        XCTAssertEqual(sources[ObjectIdentifier(transition)]?.updateCount, 1)
        XCTAssertFalse(requested.contains(ObjectIdentifier(face)))
        XCTAssertNotNil(composer.output)

        // 範囲外になると VoiceItem の実行部もその場で破棄される。
        try composer.update(time: TimeSpanValue(seconds: 10), usage: .paused)
        XCTAssertEqual(sources[ObjectIdentifier(voice)]?.disposed, true)
        XCTAssertEqual(sources[ObjectIdentifier(transition)]?.disposed, true)
    }
}
