#if os(macOS)
import CoreGraphics
import CoreText
import Foundation
import Metal
import YMM4Core

// MARK: - TextSource

/// テキストアイテムの Source。本家 TextSource に対応する。
///
/// 本家と同じく、コンストラクタで自前の文脈（CreateContext）を生成して
/// 所有する。再ラスタライズは、評価済みの様式と表示範囲からなるキー
/// が変わったときだけ行う（本家の差分検出による再描画の近似）。
/// 出力は通常1件（背景＋前景を1枚へ合成済み）で、Center は本家の
/// ComposeOutputs が最終出力へ default（原点）を渡すのに合わせ原点。
/// 文字分割時は文字ごとの出力になり、各出力が専用の DrawingEffect を
/// 持つ（本家も合成時に出力ごとに DrawingEffect を新規生成する）。
public final class MetalTextSource: Source {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let context: MetalGraphicsContext
    private let item: TextItem
    private let rasterizer: MetalTextRasterizer
    private var drawingEffects: [MetalDrawingEffect] = []
    private var references: [ImageReference] = []
    private var cachedKey: CacheKey?
    private var cachedOutputs: [any SourceOutput] = []

    private struct CacheKey: Equatable {
        var text: String
        var decorations: [TextDecoration]
        var fontName: String
        var bold: Bool
        var italic: Bool
        var fontSize: Double
        var lineHeightPercent: Double
        var letterSpacing: Double
        var wordWrapName: String
        var maxWidth: Double
        var basePointName: String
        var fontColor: Color
        var styleName: String
        var styleColor: Color
        var underline: Bool
        var strikethrough: Bool
        var isDevidedPerCharacter: Bool
        var displayIntervalMs: Double
        var displayDirectionName: String
        var hideIntervalMs: Double
        var hideDirectionName: String
        var visibleStart: Int
        var visibleEnd: Int
        var timeMs: Double
        var durationMs: Double
    }

    public init(devices: MetalGraphicsDevices, item: TextItem) {
        self.context = devices.makeContext()
        self.item = item
        self.rasterizer = MetalTextRasterizer(devices: devices)
    }

    public func update(_ description: TimelineItemSourceDescription) throws {
        let frame = description.itemPosition.frame
        let length = item.length
        let fps = description.fps
        let appearance = item.appearance
        let values = MetalTextStyleValues(
            fontName: appearance.font,
            bold: appearance.bold,
            italic: appearance.italic,
            fontSize: max(1, appearance.fontSize.value(atFrame: frame, length: length, fps: fps)),
            lineHeightPercent: appearance.lineHeight2.value(atFrame: frame, length: length, fps: fps),
            letterSpacing: appearance.letterSpacing2.value(atFrame: frame, length: length, fps: fps),
            wordWrap: appearance.wordWrap,
            maxWidth: appearance.maxWidth.value(atFrame: frame, length: length, fps: fps),
            basePoint: appearance.basePoint,
            fontColor: appearance.fontColor,
            style: appearance.style,
            styleColor: appearance.styleColor,
            underline: appearance.underline,
            strikethrough: appearance.strikethrough,
            isDevidedPerCharacter: appearance.isDevidedPerCharacter,
            displayIntervalMs: appearance.displayInterval,
            displayDirection: appearance.displayDirection,
            hideIntervalMs: appearance.hideInterval,
            hideDirection: appearance.hideDirection
        )
        let timeMs = description.itemPosition.time * 1000
        let durationMs = description.itemDuration.time * 1000
        rebuildIfNeeded(
            text: item.text, decorations: item.decorations, values: values,
            timeMs: timeMs, durationMs: durationMs,
            isTrimEndSpace: appearance.isTrimEndSpace
        )
    }

    public func dispose() {
        clearPieces()
        outputs = []
        cachedOutputs = []
        cachedKey = nil
    }

    /// JimakuSource と共有する再構築処理。
    func rebuildIfNeeded(
        text: String, decorations: [TextDecoration],
        values: MetalTextStyleValues,
        timeMs: Double, durationMs: Double, isTrimEndSpace: Bool
    ) {
        let visible = values.isDevidedPerCharacter
            ? (start: 0, end: 0)
            : MetalTextRasterizer.visibleRange(
                values: values, timeMs: timeMs, durationMs: durationMs,
                runeCount: text.unicodeScalars.count
            )
        let key = CacheKey(
            text: text, decorations: decorations,
            fontName: values.fontName, bold: values.bold, italic: values.italic,
            fontSize: values.fontSize, lineHeightPercent: values.lineHeightPercent,
            letterSpacing: values.letterSpacing, wordWrapName: values.wordWrap.honkeName,
            maxWidth: values.maxWidth, basePointName: values.basePoint.honkeName,
            fontColor: values.fontColor, styleName: values.style.honkeName,
            styleColor: values.styleColor, underline: values.underline,
            strikethrough: values.strikethrough,
            isDevidedPerCharacter: values.isDevidedPerCharacter,
            displayIntervalMs: values.displayIntervalMs,
            displayDirectionName: values.displayDirection.honkeName,
            hideIntervalMs: values.hideIntervalMs,
            hideDirectionName: values.hideDirection.honkeName,
            visibleStart: visible.start, visibleEnd: visible.end,
            timeMs: values.isDevidedPerCharacter ? timeMs : 0,
            durationMs: values.isDevidedPerCharacter ? durationMs : 0
        )
        if key == cachedKey {
            outputs = cachedOutputs
            return
        }
        cachedKey = key
        clearPieces()
        let pieces = rasterizer.rasterize(
            text: text, decorations: decorations, style: values,
            timeMs: timeMs, durationMs: durationMs,
            isTrimEndSpace: isTrimEndSpace
        )
        var built: [any SourceOutput] = []
        for (index, piece) in pieces.enumerated() {
            let reference = ImageReference(label: "text-source-\(index)")
            let effect = MetalDrawingEffect(context: context)
            context.devices.register(
                reference,
                image: MetalImage(texture: piece.texture, bounds: piece.bounds)
            )
            references.append(reference)
            drawingEffects.append(effect)
            built.append(StandardSourceOutput(
                output: reference, drawingEffect: effect,
                drawingOffset: piece.drawingOffset,
                timeOffset: piece.timeOffset,
                durationOffset: piece.durationOffset,
                dontDispose: true
            ))
        }
        cachedOutputs = built
        outputs = built
    }

    func clearPieces() {
        for effect in drawingEffects {
            effect.dispose()
        }
        drawingEffects = []
        for reference in references {
            context.devices.unregister(reference)
        }
        references = []
    }
}

// MARK: - JimakuSource

/// 音声アイテムの字幕 Source。本家 JimakuSource に対応する。
///
/// 本家での解決時点（実コードで確認）:
/// - Source の生成（VoiceItem.CreateVideoSource）は無条件で、解決は
///   行わない。
/// - 表示可否と外観の解決は JimakuSource.UpdateResource が Update の
///   たびに行う。表示ゲートは VoiceItem.jimakuIsVisible（MAC-0014 で
///   YMM4Core に実装した本家ゲートそのまま）、外観は
///   VoiceItem.jimakuAppearance（Custom のとき自身、それ以外は
///   Character の値）が返す解決済みの組を使う。
/// - 変形（位置・ズーム等）の解決は VoiceItem の IVideoItem getter 側の
///   責務であり、こちらでは扱わない（パイプラインが effective* 経由で
///   読む。MAC-0014）。
/// Character 参照は読み込み時に CharacterName から解決済みである前提
/// （YmmpCodec の読み込み後処理。MAC-0014）。
public final class MetalJimakuSource: Source {
    public let controllers: [VideoController] = []
    public private(set) var outputs: [any SourceOutput] = []

    private let textSource: MetalTextSourceLike

    /// TextSource と実装を共有するための薄いラッパ。字幕は TextItem を
    /// 持たないため、評価済みの入力を直接受ける経路を使う。
    private final class MetalTextSourceLike {
        let context: MetalGraphicsContext
        let rasterizer: MetalTextRasterizer
        var drawingEffects: [MetalDrawingEffect] = []
        var references: [ImageReference] = []
        var cachedKey: CacheKey?
        var cachedOutputs: [any SourceOutput] = []

        init(devices: MetalGraphicsDevices) {
            self.context = devices.makeContext()
            self.rasterizer = MetalTextRasterizer(devices: devices)
        }
    }

    /// 再ラスタライズの要否を決めるキー。解決済み外観の全値を含む
    /// （キャラクター側の値が変われば解決済みの値も変わるため、これで
    /// 検出できる）。
    private struct CacheKey: Equatable {
        var serif: String
        var decorations: [TextDecoration]
        var visibilityName: String
        var fontName: String
        var bold: Bool
        var italic: Bool
        var fontSize: Double
        var lineHeightPercent: Double
        var letterSpacing: Double
        var wordWrapName: String
        var maxWidth: Double
        var basePointName: String
        var fontColor: Color
        var styleName: String
        var styleColor: Color
        var underline: Bool
        var strikethrough: Bool
        var isDevidedPerCharacter: Bool
        var displayIntervalMs: Double
        var displayDirectionName: String
        var hideIntervalMs: Double
        var hideDirectionName: String
        var visibleStart: Int
        var visibleEnd: Int
        var timeMs: Double
        var durationMs: Double
    }

    private let item: VoiceItem

    public init(devices: MetalGraphicsDevices, item: VoiceItem) {
        self.item = item
        self.textSource = MetalTextSourceLike(devices: devices)
    }

    public func update(_ description: TimelineItemSourceDescription) throws {
        // 表示ゲート（本家 UpdateResource 冒頭）。非表示なら出力は空で、
        // 合成側が透明に倒す（本家も同じく Outputs が空になる）。
        guard item.jimakuIsVisible else {
            outputs = []
            textSource.cachedOutputs = []
            textSource.cachedKey = nil
            clearPieces()
            return
        }
        let appearance = item.jimakuAppearance
        let frame = description.itemPosition.frame
        let length = item.length
        let fps = description.fps
        let values = MetalTextStyleValues(
            fontName: appearance.font,
            bold: appearance.bold,
            italic: appearance.italic,
            fontSize: max(1, appearance.fontSize.value(atFrame: frame, length: length, fps: fps)),
            lineHeightPercent: appearance.lineHeight2.value(atFrame: frame, length: length, fps: fps),
            letterSpacing: appearance.letterSpacing2.value(atFrame: frame, length: length, fps: fps),
            wordWrap: appearance.wordWrap,
            maxWidth: appearance.maxWidth.value(atFrame: frame, length: length, fps: fps),
            basePoint: appearance.basePoint,
            fontColor: appearance.fontColor,
            style: appearance.style,
            styleColor: appearance.styleColor,
            underline: appearance.underline,
            strikethrough: appearance.strikethrough,
            isDevidedPerCharacter: appearance.isDevidedPerCharacter,
            displayIntervalMs: appearance.displayInterval,
            displayDirection: appearance.displayDirection,
            hideIntervalMs: appearance.hideInterval,
            hideDirection: appearance.hideDirection
        )
        let timeMs = description.itemPosition.time * 1000
        let durationMs = description.itemDuration.time * 1000
        let visible = values.isDevidedPerCharacter
            ? (start: 0, end: 0)
            : MetalTextRasterizer.visibleRange(
                values: values, timeMs: timeMs, durationMs: durationMs,
                runeCount: item.serif.unicodeScalars.count
            )
        let key = CacheKey(
            serif: item.serif, decorations: item.decorations,
            visibilityName: item.jimakuVisibility.honkeName,
            fontName: values.fontName, bold: values.bold, italic: values.italic,
            fontSize: values.fontSize, lineHeightPercent: values.lineHeightPercent,
            letterSpacing: values.letterSpacing, wordWrapName: values.wordWrap.honkeName,
            maxWidth: values.maxWidth, basePointName: values.basePoint.honkeName,
            fontColor: values.fontColor, styleName: values.style.honkeName,
            styleColor: values.styleColor, underline: values.underline,
            strikethrough: values.strikethrough,
            isDevidedPerCharacter: values.isDevidedPerCharacter,
            displayIntervalMs: values.displayIntervalMs,
            displayDirectionName: values.displayDirection.honkeName,
            hideIntervalMs: values.hideIntervalMs,
            hideDirectionName: values.hideDirection.honkeName,
            visibleStart: visible.start, visibleEnd: visible.end,
            timeMs: values.isDevidedPerCharacter ? timeMs : 0,
            durationMs: values.isDevidedPerCharacter ? durationMs : 0
        )
        if key == textSource.cachedKey {
            outputs = textSource.cachedOutputs
            return
        }
        textSource.cachedKey = key
        clearPieces()
        let pieces = textSource.rasterizer.rasterize(
            text: item.serif, decorations: item.decorations, style: values,
            timeMs: timeMs, durationMs: durationMs,
            isTrimEndSpace: appearance.isTrimEndSpace
        )
        var built: [any SourceOutput] = []
        for (index, piece) in pieces.enumerated() {
            let reference = ImageReference(label: "jimaku-source-\(index)")
            let effect = MetalDrawingEffect(context: textSource.context)
            textSource.context.devices.register(
                reference,
                image: MetalImage(texture: piece.texture, bounds: piece.bounds)
            )
            textSource.references.append(reference)
            textSource.drawingEffects.append(effect)
            built.append(StandardSourceOutput(
                output: reference, drawingEffect: effect,
                drawingOffset: piece.drawingOffset,
                timeOffset: piece.timeOffset,
                durationOffset: piece.durationOffset,
                dontDispose: true
            ))
        }
        textSource.cachedOutputs = built
        outputs = built
    }

    public func dispose() {
        clearPieces()
        outputs = []
        textSource.cachedOutputs = []
        textSource.cachedKey = nil
    }

    private func clearPieces() {
        for effect in textSource.drawingEffects {
            effect.dispose()
        }
        textSource.drawingEffects = []
        for reference in textSource.references {
            textSource.context.devices.unregister(reference)
        }
        textSource.references = []
    }
}
#endif
