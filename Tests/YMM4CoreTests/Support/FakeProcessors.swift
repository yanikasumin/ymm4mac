import XCTest
@testable import YMM4Core

// 合成系テストの共有フェイク（描画効果・エフェクト処理器と定義）。
//
// W1（構造整理）で、CompositeGroupTests の StubDrawingEffect と
// EffectWiringTests の PassThroughDrawingEffect（同一の素通し実装）を
// PassThroughDrawingEffect に一本化し、CompositeGroupTests 専用だった
// StubProcessor / StubDefinition もここへ集約した。

/// 素通しの描画効果。入力の DrawDescription をそのまま返す。
final class PassThroughDrawingEffect: DrawingEffectProcessor {
    var output: ImageReference? = ImageReference(label: "de-out")
    func setInput(_ image: ImageReference?) {}
    func clearInput() {}
    func update(_ description: EffectDescription) throws -> DrawDescription {
        description.drawDescription
    }
    func dispose() {}
}

/// Z 位置を zDelta だけずらす処理器。受けた記述を記録する。
final class StubProcessor: VideoEffectProcessor {
    var output: ImageReference? = ImageReference(label: "fx-out")
    let zDelta: Double
    private(set) var updateDescriptions: [EffectDescription] = []

    init(zDelta: Double) { self.zDelta = zDelta }

    func setInput(_ image: ImageReference?) {}
    func clearInput() {}
    func update(_ description: EffectDescription) throws -> DrawDescription {
        updateDescriptions.append(description)
        var result = description.drawDescription
        result.draw.z += zDelta
        return result
    }
    func dispose() {}
}

/// StubProcessor を生む定義。生成した処理器を蓄積する。
final class StubDefinition: VideoEffectDefinition {
    var isEnabled = true
    let zDelta: Double
    private(set) var processors: [StubProcessor] = []

    init(zDelta: Double = 0) { self.zDelta = zDelta }

    func createProcessor() -> any VideoEffectProcessor {
        let processor = StubProcessor(zDelta: zDelta)
        processors.append(processor)
        return processor
    }
}
