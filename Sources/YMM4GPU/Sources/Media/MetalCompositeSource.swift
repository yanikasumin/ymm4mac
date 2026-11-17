#if os(macOS)
import AVFoundation
import CoreGraphics
import Foundation
import Metal
import YMM4Core

/// 合成グループ（GroupItem.IsComposite）の Source。本家 CompositeSource
/// に対応する（MAC-0027）。
///
/// 本家の意味論（実コードで確認）:
/// - 生成時に自前の文脈（CreateContext）を所有し、内部 TimelineSource は
///   同じシーン・同じタイムラインを、対象グループに束縛した
///   CompositeItemPicker で合成する。子の選定はグループのレイヤー範囲
///   （Layer < 子 <= Layer + GroupRange、IsGroupOnly 時はグループ番号の
///   一致も要求）で行われ、入れ子の合成グループの子はそのグループが
///   代表する（内部合成器の選定が再帰的に担う）。
/// - Update は内部合成をタイムライン絶対時刻で回す（ピッカー側で
///   グループ末尾フレームへクランプされる）。
/// - 出力は内部合成の画像を AffineTransform2D で −center だけ平行移動
///   したもの。center は CompositeCenter が ImageCenter のとき内部画像の
///   局所境界（内容境界）の中心、ScreenCenter のとき (0, 0)。
///   SourceOutput の DrawingOffset は +center、Center は (0, 0)。
///   これによりグループ自身の変形（回転・ズーム）は内容中心を軸に効き、
///   変形が既定値のとき合成は恒等になる。
/// - グループ自身の VideoEffects は外側の EffectedItemSource が自前
///   エフェクトとして合成結果全体へ一度だけ適用する（子へは流れない。
///   親グループ解決は合成グループで打ち切られる）。
///
/// こちらでは MetalSceneSource と同じ型で実装する: 文脈を所有し、内部
/// TimelineComposer はその文脈を借用する。平行移動は実体の境界を
/// −center ずらすことで表す（テクスチャとその平面範囲は不変であり、
/// 描画時の UV 写像で画素対応が保たれる）。
public final class MetalCompositeSource: Source {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let item: GroupItem
    private let drawingEffect: MetalDrawingEffect
    private let innerComposer: TimelineComposer
    private let outputReference = ImageReference(label: "composite-source")
    private let emptyReference = ImageReference(label: "composite-source-empty")
    private let emptyOutput: StandardSourceOutput
    private var output: StandardSourceOutput?

    /// - Parameters:
    ///   - composerFactory: 内部合成器の生成境界（供給元が、対象グループに
    ///     束縛した選定と子の供給元を持つ合成器を、この Source が所有する
    ///     文脈で構築する）。
    public init(
        devices: MetalGraphicsDevices,
        item: GroupItem,
        composerFactory: (MetalGraphicsContext) -> TimelineComposer
    ) {
        self.context = devices.makeContext()
        self.item = item
        self.drawingEffect = MetalDrawingEffect(context: context)
        self.innerComposer = composerFactory(context)
        context.devices.register(
            emptyReference,
            image: MetalImage(
                texture: context.devices.transparentTexture,
                bounds: RectF(left: 0, top: 0, right: 1, bottom: 1)
            )
        )
        self.emptyOutput = StandardSourceOutput(
            output: emptyReference, drawingEffect: drawingEffect, dontDispose: true
        )
        self.outputs = [emptyOutput]
    }

    public func update(_ description: TimelineItemSourceDescription) throws {
        // 本家は TimelinePosition の絶対時刻で内部合成を回す。
        try innerComposer.update(
            time: TimeSpanValue(seconds: description.timelinePosition.time),
            usage: description.usage
        )

        guard let innerOutput = innerComposer.output,
              let innerImage = context.devices.image(for: innerOutput)
        else {
            output = nil
            outputs = [emptyOutput]
            return
        }

        // 中心: ImageCenter のとき内部画像の局所境界（内容境界）の中心、
        // ScreenCenter のとき原点（本家 CompositeSource.Update）。
        // 本家は CompositeCenter == ImageCenter のときだけ画像中心を使い、
        // それ以外（ScreenCenter・未知値）は (0, 0)。
        let center: Vector2
        if item.compositeCenter == .imageCenter {
            center = Vector2(
                x: (innerImage.bounds.left + innerImage.bounds.right) / 2,
                y: (innerImage.bounds.top + innerImage.bounds.bottom) / 2
            )
        } else {
            center = .zero
        }

        // 平行移動（−center）は境界のずらしと planeOffset で表す。
        // テクスチャ・平面範囲・変換は内部画像のままで、ローカル座標の
        // 点は planeOffset（= center）を加えた平面位置の画素に対応する。
        context.devices.register(
            outputReference,
            image: MetalImage(
                texture: innerImage.texture,
                bounds: RectF(
                    left: innerImage.bounds.left - center.x,
                    top: innerImage.bounds.top - center.y,
                    right: innerImage.bounds.right - center.x,
                    bottom: innerImage.bounds.bottom - center.y
                ),
                texturePlaneRect: innerImage.texturePlaneRect,
                planeOffset: Vector2(
                    x: innerImage.planeOffset.x + center.x,
                    y: innerImage.planeOffset.y + center.y
                ),
                transform: innerImage.transform,
                opacity: innerImage.opacity,
                interpolation: innerImage.interpolation
            )
        )
        // DrawingOffset（= center）は出力の固定値であり、中心はフレーム
        // ごとに変わりうるため、出力は更新のたびに作り直す（本家も
        // Update のたびに旧出力を破棄して新しく作る）。
        output = StandardSourceOutput(
            output: outputReference,
            drawingEffect: drawingEffect,
            drawingOffset: center,
            center: .zero,
            dontDispose: true
        )
        outputs = [output ?? emptyOutput]
    }

    public func dispose() {
        innerComposer.dispose()
        drawingEffect.dispose()
        context.devices.unregister(outputReference)
        context.devices.unregister(emptyReference)
        outputs = []
    }
}

#endif
