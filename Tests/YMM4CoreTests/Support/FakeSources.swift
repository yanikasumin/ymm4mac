import XCTest
@testable import YMM4Core

// 合成系テストの共有フェイク（Source 実装）。
//
// W1（構造整理）で、EffectWiringTests と CompositeGroupTests に同名で
// 定義されていた StubSource を、仕様の違いに合わせて2つの型として
// ここへ集約した。最小形は StubSource、呼び出し回数や破棄を記録する
// 形は RecordingStubSource。

/// 最小の Source。outputs は検証側が差し込む。
final class StubSource: Source {
    var controllers: [VideoController] = []
    var outputs: [any SourceOutput] = []
    func update(_ description: TimelineItemSourceDescription) throws {}
    func dispose() {}
}

/// 更新回数と破棄を記録する Source。init で出力1件を構成する。
final class RecordingStubSource: Source {
    var controllers: [VideoController] = []
    var outputs: [any SourceOutput] = []
    private(set) var updateCount = 0
    private(set) var disposed = false

    init(imageLabel: String) {
        outputs = [StandardSourceOutput(
            output: ImageReference(label: imageLabel),
            drawingEffect: PassThroughDrawingEffect()
        )]
    }

    func update(_ description: TimelineItemSourceDescription) throws {
        updateCount += 1
    }

    func dispose() { disposed = true }
}
