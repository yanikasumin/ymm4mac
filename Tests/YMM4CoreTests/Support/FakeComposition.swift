import XCTest
@testable import YMM4Core

// 合成系テストの共有フェイク（合成実行部）。
//
// W7（構造整理）で、CompositionTests に私用定義されていたフェイク群を
// ここへ移し、EffectedItemSourceTests / TimelineComposerTests /
// VideoItemScopeTests の3ファイルから共有する。

// MARK: - 偽の実装（合成実行部の検証用）

final class CompositionEventLog {
    var events: [String] = []
    func add(_ event: String) { events.append(event) }
    func index(of event: String) -> Int? { events.firstIndex(of: event) }
}

struct FakeError: Error {}

/// 連鎖の処理器。呼び出しを共有ログへ記録し、DrawDescription の Z を
/// 決まった量だけ書き換える（連鎖的な書き換えの確認用）。
final class FakeChainProcessor: VideoEffectProcessor {
    let name: String
    let log: CompositionEventLog
    var output: ImageReference?
    var zDelta: Double = 0
    var errorOnUpdate: Error?
    private(set) var setInputCalls: [ImageReference?] = []
    private(set) var updateDescriptions: [EffectDescription] = []
    private(set) var disposed = false

    init(name: String, log: CompositionEventLog) {
        self.name = name
        self.log = log
        self.output = ImageReference(label: "\(name)-out")
    }

    func setInput(_ image: ImageReference?) {
        setInputCalls.append(image)
        log.add("\(name).setInput")
    }

    func clearInput() {
        log.add("\(name).clearInput")
    }

    func update(_ description: EffectDescription) throws -> DrawDescription {
        log.add("\(name).update")
        updateDescriptions.append(description)
        if let errorOnUpdate { throw errorOnUpdate }
        var result = description.drawDescription
        result.draw.z += zDelta
        return result
    }

    func dispose() {
        disposed = true
        log.add("\(name).dispose")
    }
}

final class FakeDefinition: VideoEffectDefinition {
    let name: String
    let log: CompositionEventLog
    var isEnabled = true
    var zDelta: Double = 0
    var errorOnUpdate: Error?
    private(set) var processors: [FakeChainProcessor] = []

    init(name: String, log: CompositionEventLog) {
        self.name = name
        self.log = log
    }

    func createProcessor() -> any VideoEffectProcessor {
        log.add("\(name).createProcessor")
        let processor = FakeChainProcessor(name: name, log: log)
        processor.zDelta = zDelta
        processor.errorOnUpdate = errorOnUpdate
        processors.append(processor)
        return processor
    }
}

/// DrawingEffect（アイテム変形）の偽実装。
final class CompositionFakeDrawingEffect: DrawingEffectProcessor {
    let name: String
    let log: CompositionEventLog
    var output: ImageReference?
    var errorOnUpdate: Error?
    private(set) var setInputCalls: [ImageReference?] = []
    private(set) var updateCount = 0

    init(name: String, log: CompositionEventLog) {
        self.name = name
        self.log = log
        self.output = ImageReference(label: "\(name)-out")
    }

    func setInput(_ image: ImageReference?) {
        setInputCalls.append(image)
        log.add("\(name).setInput")
    }

    func clearInput() {}

    func update(_ description: EffectDescription) throws -> DrawDescription {
        updateCount += 1
        if let errorOnUpdate { throw errorOnUpdate }
        return description.drawDescription
    }

    func dispose() {}
}

final class FakeChainSource: Source {
    var controllers: [VideoController] = []
    var outputs: [any SourceOutput] = []
    var errorOnUpdate: Error?
    private(set) var updateCount = 0
    private(set) var lastDescription: TimelineItemSourceDescription?
    private(set) var disposed = false

    func update(_ description: TimelineItemSourceDescription) throws {
        updateCount += 1
        lastDescription = description
        if let errorOnUpdate { throw errorOnUpdate }
    }

    func dispose() {
        disposed = true
    }
}

final class FakeFrameBufferSource: FrameBufferSource {
    var controllers: [VideoController] = []
    var outputs: [any SourceOutput] = []
    var input: ImageReference?
    var frameSize = PixelSize(width: 0, height: 0)
    var clearBackground = true
    private(set) var updateCount = 0
    private(set) var lastDescription: TimelineItemSourceDescription?
    private(set) var disposed = false

    func update(_ description: TimelineItemSourceDescription) throws {
        updateCount += 1
        lastDescription = description
    }

    func dispose() {
        disposed = true
    }
}

final class FakeTachieSource: TachieSource {
    var controllers: [VideoController] = []
    var outputs: [any SourceOutput] = []
    var activeVoice: VoiceItem?
    var activeFaces: [any FaceItem] = []
    private(set) var disposed = false

    func update(_ description: TimelineItemSourceDescription) throws {}

    func dispose() {
        disposed = true
    }
}

/// 描画先の記録用実装。自身の操作列（ops）と共有ログの両方へ残す。
final class RecordingRenderTarget: RenderTarget {
    let image: ImageReference
    let name: String
    let log: CompositionEventLog
    private(set) var ops: [String] = []
    private(set) var disposed = false
    /// close() で投げる失敗（失敗注入用。MAC-0021）。nil なら成功する。
    var closeError: (any Error)?

    init(name: String, log: CompositionEventLog) {
        self.name = name
        self.log = log
        self.image = ImageReference(label: name)
    }

    private func record(_ op: String) {
        ops.append(op)
        log.add("\(name).\(op)")
    }

    func beginDraw() { record("begin") }
    func clear() { record("clear") }

    func fillRect(_ rect: RectF, color: Color) {
        record("fillRect(\(rect.left),\(rect.top),\(rect.right),\(rect.bottom),a=\(color.alpha))")
    }

    func drawImage(_ image: ImageReference) {
        record("draw(\(image.label))")
    }

    func drawImage(_ image: ImageReference, blend: Blend, interpolation: InterpolationMode) {
        record("drawBlend(\(image.label))")
    }

    func endDraw() { record("end") }

    func close() throws {
        record("close")
        if let closeError { throw closeError }
    }

    func dispose() {
        disposed = true
        record("dispose")
    }
}

final class RecordingTargetFactory: RenderTargetFactory {
    let log: CompositionEventLog
    private(set) var targets: [RecordingRenderTarget] = []
    /// 生成する描画先の close() へ注入する失敗（失敗注入用。MAC-0021）。
    var closeError: (any Error)?
    /// closeError を注入する描画先の番号（1始まり）。nil なら全てに注入する。
    var closeErrorTargetNumbers: Set<Int>?

    init(log: CompositionEventLog) {
        self.log = log
    }

    func makeTarget() -> any RenderTarget {
        let number = targets.count + 1
        let target = RecordingRenderTarget(name: "T\(number)", log: log)
        if let numbers = closeErrorTargetNumbers {
            if numbers.contains(number) {
                target.closeError = closeError
            }
        } else {
            target.closeError = closeError
        }
        targets.append(target)
        return target
    }
}

final class FakeEffectProvider: EffectPairProvider {
    var ownPairs: [ObjectIdentifier: [EffectPair]] = [:]
    /// グループごとの定義列。組は呼び出し時に渡された子位置・子総数で構築する
    /// （実物の供給元と同じ作法）。
    var groupDefinitions: [ObjectIdentifier: [any VideoEffectDefinition]] = [:]
    var facePairs: [ObjectIdentifier: [EffectPair]] = [:]
    private(set) var groupCalls: [(group: GroupItem, childIndex: Int, childCount: Int)] = []

    func ownEffectPairs(for item: BaseItem & VideoItemProperties) -> [EffectPair] {
        ownPairs[ObjectIdentifier(item)] ?? []
    }

    func groupEffectPairs(for group: GroupItem, childIndex: Int, childCount: Int) -> [EffectPair] {
        groupCalls.append((group, childIndex, childCount))
        return (groupDefinitions[ObjectIdentifier(group)] ?? []).map {
            EffectPair(timeSource: group, definition: $0, groupIndex: childIndex, groupCount: childCount)
        }
    }

    func faceEffectPairs(for faceItem: BaseItem) -> [EffectPair] {
        facePairs[ObjectIdentifier(faceItem)] ?? []
    }
}

final class FakeAlphaMask: AlphaMaskEffect {
    var output: ImageReference? = ImageReference(label: "mask-out")
    private(set) var inputs: [Int: ImageReference?] = [:]
    private(set) var disposed = false

    func setInput(_ index: Int, _ image: ImageReference?) {
        inputs[index] = image
    }

    func dispose() {
        disposed = true
    }
}

final class FakeAlphaMaskFactory: AlphaMaskEffectFactory {
    private(set) var masks: [FakeAlphaMask] = []

    func makeAlphaMaskEffect() -> any AlphaMaskEffect {
        let mask = FakeAlphaMask()
        masks.append(mask)
        return mask
    }
}

func makeItemDescription(
    timelineFrame: Int = 0, itemFrame: Int = 0, itemLength: Int = 90, layer: Int = 0
) -> TimelineItemSourceDescription {
    let base = TimelineSourceDescription(
        screenSize: PixelSize(width: 1920, height: 1080),
        timelinePosition: FramePosition(frame: timelineFrame, fps: 30),
        timelineDuration: FramePosition(frame: 900, fps: 30),
        fps: 30,
        usage: .paused,
        sceneId: UUID(),
        scenes: []
    )
    return TimelineItemSourceDescription(base, itemFrame: itemFrame, itemLength: itemLength, layer: layer)
}

func makeVisualItem<T: VisualItem>(
    _ item: T, frame: Int = 0, length: Int = 90, layer: Int = 0, group: Int = 0
) -> T {
    item.frame = frame
    item.length = length
    item.layer = layer
    item.group = group
    return item
}
