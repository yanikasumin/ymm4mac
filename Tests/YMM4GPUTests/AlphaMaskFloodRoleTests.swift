#if os(macOS)
import Metal
import XCTest
@testable import YMM4GPU
import YMM4Core

/// MetalAlphaMaskEffect の Flood 代替トークンの識別が、ラベル文字列
/// ではなく ImageReference の役割で行われることの検証。
///
/// 恒等経路（全面不透明マスク = 出力は本体画像そのもの）に入る条件は
/// 「入力1の実体が未登録」かつ「役割が .floodSubstitute」の両方である。
final class AlphaMaskFloodRoleTests: XCTestCase {

    private var devices: MetalGraphicsDevices!
    private var context: MetalGraphicsContext!
    private var sourceReference: ImageReference!
    private var sourceTexture: MTLTexture!
    private let sourceBounds = RectF(left: -32, top: -24, right: 32, bottom: 24)

    override func setUpWithError() throws {
        devices = try MetalGraphicsDevices()
        context = devices.makeContext(targetSize: PixelSize(width: 64, height: 48))

        // 本体画像: 透明テクスチャとは別の実テクスチャを登録する。
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 64, height: 48, mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        sourceTexture = try XCTUnwrap(devices.device.makeTexture(descriptor: descriptor))
        sourceReference = ImageReference(label: "source")
        devices.register(
            sourceReference,
            image: MetalImage(texture: sourceTexture, bounds: sourceBounds)
        )
    }

    override func tearDown() {
        devices = nil
        context = nil
        sourceReference = nil
        sourceTexture = nil
    }

    private func makeEffect() -> MetalAlphaMaskEffect {
        let effect = MetalAlphaMaskEffect(context: context)
        effect.setInput(0, sourceReference)
        return effect
    }

    private func outputTexture(of effect: MetalAlphaMaskEffect) -> MTLTexture? {
        guard let output = effect.output else { return nil }
        return devices.image(for: output)?.texture
    }

    /// ラベルが "flood" でも役割が通常なら恒等経路に入らない
    /// （未登録の通常参照は従来どおり全面透明として扱われる）。
    func testFloodLabelWithNormalRoleDoesNotTakeIdentityPath() throws {
        let effect = makeEffect()
        effect.setInput(1, ImageReference(label: "flood"))

        let texture = try XCTUnwrap(outputTexture(of: effect))
        XCTAssertTrue(
            texture === devices.transparentTexture,
            "ラベルだけで恒等経路に入ってはならない"
        )
        effect.dispose()
    }

    /// 役割を持つトークンは、ラベルが何であっても恒等経路に入る。
    func testFloodSubstituteRoleTakesIdentityPathRegardlessOfLabel() throws {
        let effect = makeEffect()
        effect.setInput(1, ImageReference(label: "unrelated-name", role: .floodSubstitute))

        let texture = try XCTUnwrap(outputTexture(of: effect))
        XCTAssertTrue(
            texture === sourceTexture,
            "Flood 代替トークンでは出力が本体画像そのものになるはず"
        )
        effect.dispose()
    }

    /// 役割を持つトークンでも実体が登録されていれば恒等経路には
    /// 入らず、その実体をマスクとして使う（役割と未登録は別の条件）。
    func testFloodSubstituteRoleWithRegisteredImageUsesMaskPath() throws {
        let maskReference = ImageReference(label: "mask", role: .floodSubstitute)
        devices.register(
            maskReference,
            image: MetalImage(texture: devices.transparentTexture, bounds: sourceBounds)
        )
        let effect = makeEffect()
        effect.setInput(1, maskReference)

        let texture = try XCTUnwrap(outputTexture(of: effect))
        XCTAssertFalse(
            texture === sourceTexture,
            "実体が登録されている参照を Flood 代替として扱ってはならない"
        )
        effect.dispose()
    }
}
#endif
