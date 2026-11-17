import Foundation
import Metal
import YMM4Core
import YMM4GPU

// MAC-0033 検証ハーネス: GPU テクスチャ確保失敗が「効果なしの素通し」と
// 区別され、MetalRenderError として伝播することの確認（GPU28-03）。
//
// 回転処理器へ DrawDescription の Zoom = 100000 を与えると、出力境界が
// 約 900 万 px 四方になり、Metal の 2D テクスチャ寸法上限（16384）を
// 決定的に超える。そのとき:
// - update が MetalRenderError.textureCreationFailed を投げる
// - 入力がそのまま出力として公開されない（output は nil のまま）
// ことを見る。対照として、通常の拡縮では更新が成功し出力が公開される。
//
// 環境上の制約（2026-11-17 実測）: この Mac（macOS 26）では、上限を
// 超えるディスクリプタは makeTexture が nil を返す前に Metal の
// ディスクリプタ検証アサーションでプロセスが abort する
// （"Texture Descriptor Validation … width (9050967) greater than the
// maximum allowed size of 16384"、exit 134。MTL_DEBUG_LAYER=0 /
// METAL_DEVICE_WRAPPER_TYPE=0 でも回避不可）。寸法経路で nil 戻りを
// 決定的に再現する手段が無いため、失敗ケースは環境変数
// MAC0033_RUN_FAILURE_CASE=1 のときだけ実行し、既定では SKIP と
// 表示する。throw 経路そのものの担保は、確保箇所が全て throw する
// makeTexture 経由であることのコード監査（grep）に拠る。
// なおアサーション出力の寸法 9050967 は、要求寸法がデバイス到達前に
// 素通しされず実際に確保要求されたことの傍証にはなる。

var failures = 0
@MainActor
func check(_ condition: Bool, _ label: String) {
    print("\(condition ? "PASS" : "FAIL"): \(label)")
    if !condition { failures += 1 }
}

let devices = MetalGraphicsDevices()!
let context = devices.makeContext()

// 入力: 64×64 のテクスチャを中心原点の境界で登録する。
let descriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false
)
descriptor.usage = [.renderTarget, .shaderRead]
descriptor.storageMode = .shared
let inputTexture = devices.device.makeTexture(descriptor: descriptor)!
let inputReference = ImageReference(label: "mac0033-input")
devices.register(
    inputReference,
    image: MetalImage(
        texture: inputTexture,
        bounds: RectF(left: -32, top: -32, right: 32, bottom: 32)
    )
)

@MainActor
func makeDescription(zoom: Double) -> EffectDescription {
    let base = TimelineSourceDescription(
        screenSize: PixelSize(width: 64, height: 64),
        timelinePosition: FramePosition(frame: 0, fps: 30),
        timelineDuration: FramePosition(frame: 90, fps: 30),
        fps: 30,
        usage: .paused,
        sceneId: UUID(),
        scenes: []
    )
    let item = TimelineItemSourceDescription(base, itemFrame: 0, itemLength: 90, layer: 0)
    return EffectDescription(
        itemDescription: item,
        drawDescription: DrawDescription(zoom: Vector2(x: zoom, y: zoom))
    )
}

@MainActor
func makeProcessor() -> MetalRotateProcessor {
    let definition = RotateEffectDefinition()
    definition.z.values = [AnimationValue(45)]
    let processor = MetalRotateProcessor(context: context, definition: definition)
    processor.setInput(inputReference)
    return processor
}

// 対照: 通常の拡縮では更新が成功し、出力が公開される。
do {
    let processor = makeProcessor()
    do {
        _ = try processor.update(makeDescription(zoom: 1))
        check(true, "control: update succeeds at zoom 1")
    } catch {
        check(false, "control: update succeeds at zoom 1 (threw \(error))")
    }
    check(processor.output != nil, "control: output published")
    processor.dispose()
}

// 本題: 巨大な拡縮で出力テクスチャ確保が決定的に失敗する。
// ただし冒頭コメントのとおり、この環境では nil 戻りの前に検証
// アサーションで abort するため、既定では実行せず SKIP とする。
let runFailureCase = ProcessInfo.processInfo.environment["MAC0033_RUN_FAILURE_CASE"] == "1"
if !runFailureCase {
    print("SKIP: failure: update throws textureCreationFailed (Metal descriptor validation aborts first in this environment)")
    print("SKIP: failure: requested size exceeds texture limit")
    print("SKIP: failure: input not published as output")
}
if runFailureCase {
    let processor = makeProcessor()
    var thrown: Error?
    do {
        _ = try processor.update(makeDescription(zoom: 100_000))
    } catch {
        thrown = error
    }
    if let renderError = thrown as? MetalRenderError,
       case .textureCreationFailed(let width, let height) = renderError {
        check(true, "failure: update throws textureCreationFailed")
        check(
            width > 16384 && height > 16384,
            "failure: requested size exceeds texture limit (\(width)x\(height))"
        )
    } else {
        check(
            false,
            "failure: update throws textureCreationFailed (got \(String(describing: thrown)))"
        )
        check(false, "failure: requested size exceeds texture limit")
    }
    check(processor.output == nil, "failure: input not published as output")
    processor.dispose()
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
