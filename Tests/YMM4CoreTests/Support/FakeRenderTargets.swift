import XCTest
@testable import YMM4Core

// 合成系テストの共有フェイク（描画先）。
//
// W1（構造整理）で、CompositeGroupTests と EffectWiringTests に同名で
// 定義されていた StubTarget / StubTargetFactory を、記録機能を持つ形に
// 一本化してここへ集約した（EffectWiringTests 側は記録を使わないため、
// 記録する形で代替できる）。

/// 描画先のスタブ。ブレンド指定つき描画の回数を記録する。
final class StubTarget: RenderTarget {
    let image = ImageReference(label: "target")
    private(set) var drawBlendCount = 0
    func beginDraw() {}
    func clear() {}
    func fillRect(_ rect: RectF, color: Color) {}
    func drawImage(_ image: ImageReference) {}
    func drawImage(_ image: ImageReference, blend: Blend, interpolation: InterpolationMode) {
        drawBlendCount += 1
    }
    func endDraw() {}
    func close() throws {}
    func dispose() {}
}

/// 生成した描画先を蓄積するファクトリ。
final class StubTargetFactory: RenderTargetFactory {
    private(set) var targets: [StubTarget] = []
    func makeTarget() -> any RenderTarget {
        let target = StubTarget()
        targets.append(target)
        return target
    }
}
