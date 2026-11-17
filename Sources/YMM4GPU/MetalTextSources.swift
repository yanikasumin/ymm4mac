#if os(macOS)
import CoreGraphics
import CoreText
import Foundation
import Metal
import YMM4Core

// MARK: - フォント解決

/// 本家のフォント解決（FontSettings + TextFormatDescription）に相当する。
///
/// 本家は FontName（フェイス単位の表示名）を SystemFonts + CustomFonts
/// から完全一致で検索し、見つからなければ CanonicalFontName が空の
/// 既定フォントに落とす。太字は「アイテム Bold が true かつ解決した
/// フェイスのウェイトが Bold(700) 未満のときだけ 700 へ引き上げる」
/// 条件付きで、斜体は Italic 指定時にフェイスのスタイルを Italic へ
/// 差し替える。Mac 側は CoreText の名前引きで同じ規則を再現するが、
/// 名前体系（Win32FamilyNames 等）とフォールバック先が異なるため、
/// 同じプロジェクトでも選ばれるフェイスがずれうる（台帳に記録）。
struct MetalFontResolution {
    /// 解決したフォント（太字・斜体の規則適用後）。
    var font: CTFont
    /// 解決したフェイス本来のウェイト（CoreText の trait 値。Bold は 0.4）。
    var canonicalWeight: Double
    /// 名前が実在フェイスに解決できたか。
    var isResolved: Bool
}

enum MetalFontResolver {
    /// CoreText の trait ウェイトにおける Bold の値（kCTFontWeightBold）。
    static let boldWeight = 0.4

    /// 名前だけを解決する（太字・斜体は適用しない）。見つからなければ
    /// nil（呼び出し側がフォールバックを決める）。
    static func face(named name: String, size: Double) -> (font: CTFont, weight: Double)? {
        guard !name.isEmpty else { return nil }
        // CTFontCreateWithName は存在しない名前でも既定フォントを黙って
        // 返すため、返ったフォントの名前群と照合して検証する。
        let candidate = CTFontCreateWithName(name as CFString, CGFloat(size), nil)
        if matches(candidate, name: name) {
            return (candidate, weight(of: candidate))
        }
        // コレクション全体から表示名・フルネーム・ファミリ名で探す。
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        guard let descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection)
                as? [CTFontDescriptor]
        else { return nil }
        for descriptor in descriptors {
            let postScript = descriptorValue(descriptor, kCTFontNameAttribute)
            let family = descriptorValue(descriptor, kCTFontFamilyNameAttribute)
            let style = descriptorValue(descriptor, kCTFontStyleNameAttribute)
            let display = descriptorValue(descriptor, kCTFontDisplayNameAttribute)
            let full = fullName(of: descriptor)
            let candidates = [postScript, family, style, display, full,
                              family.map { $0 + " " + (style ?? "") }]
            if candidates.contains(where: { $0?.caseInsensitiveCompare(name) == .orderedSame }) {
                let font = CTFontCreateWithFontDescriptor(descriptor, CGFloat(size), nil)
                return (font, weight(of: font))
            }
        }
        return nil
    }

    /// 本家の規則でフォントを解決する。名前が解決できない場合は
    /// fallback（装飾範囲用は基準フォント）か、無ければシステム既定
    /// フォントに落とす（本家で CanonicalFontName が空のときの
    /// DirectWrite フォールバックに相当する近似）。
    static func resolve(
        named name: String, size: Double, bold: Bool, italic: Bool,
        fallback: MetalFontResolution? = nil
    ) -> MetalFontResolution {
        let base: (font: CTFont, weight: Double, resolved: Bool)
        if let face = face(named: name, size: size) {
            base = (face.font, face.weight, true)
        } else if let fallback {
            // 装飾フォントが解決できない場合は基準フォントの記録へ
            // フォールバックするが、太字・斜体の規則はその上で適用する
            // （本家も font2 = 基準フォントとして同じ規則を通す）。
            base = (fallback.font, fallback.canonicalWeight, fallback.isResolved)
        } else {
            let system = CTFontCreateUIFontForLanguage(.system, CGFloat(size), nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, CGFloat(size), nil)
            base = (system, weight(of: system), false)
        }
        var font = base.font
        // 太字: Bold 指定かつフェイスのウェイトが Bold 未満のときだけ引き上げる。
        if bold && base.weight < boldWeight {
            if let bolded = CTFontCreateCopyWithSymbolicTraits(
                font, CGFloat(size), nil, .traitBold, .traitBold
            ) {
                font = bolded
            }
        }
        // 斜体: Italic 指定時は Italic スタイルへ。指定が無ければフェイス本来。
        if italic {
            if let italicized = CTFontCreateCopyWithSymbolicTraits(
                font, CGFloat(size), nil, .traitItalic, .traitItalic
            ) {
                font = italicized
            }
        }
        return MetalFontResolution(
            font: font, canonicalWeight: base.weight, isResolved: base.resolved
        )
    }

    static func weight(of font: CTFont) -> Double {
        let descriptor = CTFontCopyFontDescriptor(font)
        guard let traits = CTFontDescriptorCopyAttribute(
            descriptor, kCTFontTraitsAttribute
        ) as? [CFString: Any],
              let value = traits[kCTFontWeightTrait] as? NSNumber
        else { return 0 }
        return value.doubleValue
    }

    private static func matches(_ font: CTFont, name: String) -> Bool {
        let keys: [CFString] = [
            kCTFontPostScriptNameKey, kCTFontFullNameKey,
            kCTFontFamilyNameKey, kCTFontStyleNameKey,
        ]
        for key in keys {
            if let value = CTFontCopyName(font, key) as String?,
               value.caseInsensitiveCompare(name) == .orderedSame {
                return true
            }
        }
        let descriptor = CTFontCopyFontDescriptor(font)
        if descriptorValue(descriptor, kCTFontDisplayNameAttribute)?
            .caseInsensitiveCompare(name) == .orderedSame {
            return true
        }
        if let family = CTFontCopyName(font, kCTFontFamilyNameKey) as String?,
           let style = CTFontCopyName(font, kCTFontStyleNameKey) as String?,
           (family + " " + style).caseInsensitiveCompare(name) == .orderedSame {
            return true
        }
        return false
    }

    private static func descriptorValue(
        _ descriptor: CTFontDescriptor, _ key: CFString
    ) -> String? {
        CTFontDescriptorCopyAttribute(descriptor, key) as? String
    }

    private static func fullName(of descriptor: CTFontDescriptor) -> String? {
        guard let family = descriptorValue(descriptor, kCTFontFamilyNameAttribute),
              let style = descriptorValue(descriptor, kCTFontStyleNameAttribute)
        else { return nil }
        return style == "Regular" ? family : family + " " + style
    }
}

// MARK: - 評価済みテキスト様式

/// フレーム位置で評価済みのテキスト様式一式。TextSource / JimakuSource が
/// アイテム（字幕は解決済み外観）から組み立てて描画器へ渡す。
/// DisplayInterval / HideInterval の単位は本家どおりミリ秒。
struct MetalTextStyleValues {
    var fontName: String
    var bold: Bool
    var italic: Bool
    var fontSize: Double
    var lineHeightPercent: Double
    var letterSpacing: Double
    var wordWrap: WordWrap
    var maxWidth: Double
    var basePoint: BasePoint
    var fontColor: Color
    var style: TextStyle
    var styleColor: Color
    var underline: Bool
    var strikethrough: Bool
    var isDevidedPerCharacter: Bool
    var displayIntervalMs: Double
    var displayDirection: TypewriterAnimationDirection
    var hideIntervalMs: Double
    var hideDirection: TypewriterAnimationDirection
}

/// 描画器が出す断片1件。テクスチャと、その平面配置・時間窓。
struct MetalTextPiece {
    var texture: MTLTexture
    /// 平面座標におけるテクスチャの境界（Source の局所座標系）。
    var bounds: RectF
    /// アイテム位置への加算オフセット（分割時のみ非ゼロ）。
    var drawingOffset: Vector2
    var timeOffset: TimeSpanValue
    var durationOffset: TimeSpanValue
}

// MARK: - レイアウト内部表現

private struct TextGlyph {
    var glyph: CGGlyph
    var font: CTFont
    var fontSize: Double
    var advance: Double
    var spacingAfter: Double
    var runeIndex: Int
    var color: Color
    var style: TextStyle
    var styleColor: Color
    var underline: Bool
    var strikethrough: Bool
    /// 行内でのペン位置（行頭からの累積）。
    var x: Double
}

private struct TextLine {
    var glyphs: [TextGlyph] = []
    var width: Double = 0
    var ascent: Double = 0
    var descent: Double = 0
    var leading: Double = 0
    /// 配置ボックス内での行の左端（配置揃え適用後）。
    var xOffset: Double = 0
    /// ブロック先頭からこの行のベースラインまでの距離。
    var baselineFromTop: Double = 0
    var naturalHeight: Double { ascent + descent + leading }
}

/// テキストのラスタライズ器。本家 TextSource / JimakuSource が共有する
/// DirectWrite パイプライン（フォーマット生成→レイアウト→背景・前景の
/// 2パス描画→合成）の CoreText 置換。
///
/// 本家との主な差分（台帳に記録）:
/// - レイアウト計測は CoreText の行メトリクスを使うため、行の高さ・
///   ベースライン・改行位置が DirectWrite と完全には一致しない。
/// - 縁取りはグリフ輪郭パスへのストロークで再現する（線幅・結合規則は
///   本家の式どおり）。NSAttributedString の stroke 属性は使わない。
/// - 制御タグ（ルビ・タイミングタグ）とユーザー辞書のアスタリスク
///   置換は未実装。タイプライターはタグ無しの場合の範囲計算のみ再現する。
/// - ラスタライズ先は有限のテクスチャであり、本家の無限平面コマンド
///   リストと違い、テクスチャ範囲外は切り取られる（パディングで緩和）。
final class MetalTextRasterizer {
    private let devices: MetalGraphicsDevices

    init(devices: MetalGraphicsDevices) {
        self.devices = devices
    }

    /// テクスチャ寸法の上限（デバイス上限に合わせる）。
    private static let maxTextureDimension = 16384

    /// テキストを断片列へラスタライズする。表示対象が無ければ空を返す。
    func rasterize(
        text rawText: String,
        decorations rawDecorations: [TextDecoration],
        style values: MetalTextStyleValues,
        timeMs: Double,
        durationMs: Double,
        isTrimEndSpace: Bool
    ) -> [MetalTextPiece] {
        // 前処理: 本家 ApplyNormalize（NFC 正規化＋行末スペース除去）。
        // アスタリスク置換はユーザー辞書（設定層）に依存するため未実装で、
        // 辞書が空の本家と同じく無変換になる。
        let (text, decorations) = Self.normalize(
            text: rawText, decorations: rawDecorations, isTrimEndSpace: isTrimEndSpace
        )
        guard !text.isEmpty else { return [] }

        let runes = Array(text.unicodeScalars)
        // UTF-16 オフセット → ルーン番号の対応表。
        var runeIndexByUTF16: [Int: Int] = [:]
        var utf16Offset = 0
        for (index, scalar) in runes.enumerated() {
            runeIndexByUTF16[utf16Offset] = index
            utf16Offset += scalar.utf16.count
        }
        runeIndexByUTF16[utf16Offset] = runes.count

        let isVertical = Self.isVertical(values.basePoint)
        if isVertical {
            return rasterizeVertical(
                text: text, decorations: decorations, values: values,
                runes: runes, runeIndexByUTF16: runeIndexByUTF16
            )
        }

        // フォント解決と属性付き文字列の構築。
        let baseFont = MetalFontResolver.resolve(
            named: values.fontName, size: values.fontSize,
            bold: values.bold, italic: values.italic
        )
        let attributed = Self.buildAttributedString(
            text: text, decorations: decorations, values: values,
            baseFont: baseFont, runes: runes
        )
        let runeTraits = Self.buildRuneTraits(
            runeCount: runes.count, decorations: decorations, values: values
        )

        // 行分割とグリフ抽出。
        var lines = layoutLines(
            attributed: attributed, values: values, baseFont: baseFont,
            runeTraits: runeTraits, runeIndexByUTF16: runeIndexByUTF16
        )
        guard !lines.isEmpty else { return [] }

        // 行の積み上げ（Proportional 行間: 全行の高さとベースラインを
        // LineHeight/100 倍する。本家は第1行の Baseline/Height 比を
        // 全行のベースライン割合に使うが、ここでは行ごとの上昇量に
        // 同じ倍率を掛ける近似とする。台帳に記録）。
        let lineHeightRate = values.lineHeightPercent / 100
        let firstLine = lines[0]
        var blockHeight = 0.0
        for index in lines.indices {
            lines[index].baselineFromTop = blockHeight + lines[index].ascent * lineHeightRate
            blockHeight += lines[index].naturalHeight * lineHeightRate
        }
        let layoutWidth = values.wordWrap == .noWrap || values.maxWidth <= 0
            ? (lines.map(\.width).max() ?? 0)
            : values.maxWidth
        for index in lines.indices {
            switch Self.textAlignment(of: values.basePoint) {
            case .leading: lines[index].xOffset = 0
            case .center: lines[index].xOffset = (layoutWidth - lines[index].width) / 2
            case .trailing: lines[index].xOffset = layoutWidth - lines[index].width
            }
        }

        // 配置原点（本家 TextLayoutDescription.CreateTextLayout の戻り値）。
        let positionX: Double
        switch Self.textAlignment(of: values.basePoint) {
        case .leading: positionX = 0
        case .center: positionX = -layoutWidth / 2
        case .trailing: positionX = -layoutWidth
        }
        let firstHeight = firstLine.naturalHeight
        let firstBaseline = firstLine.ascent
        let positionY: Double
        switch Self.paragraphAlignment(of: values.basePoint) {
        case .near:
            positionY = firstBaseline * (1 - lineHeightRate)
        case .center:
            positionY = (firstBaseline - firstHeight / 2) * (1 - lineHeightRate)
        case .far:
            positionY = (firstHeight - firstBaseline) * (lineHeightRate - 1)
        }
        let topOffset: Double
        switch Self.paragraphAlignment(of: values.basePoint) {
        case .near: topOffset = 0
        case .center: topOffset = -blockHeight / 2
        case .far: topOffset = -blockHeight
        }

        if values.isDevidedPerCharacter {
            return rasterizeDivided(
                lines: lines, values: values,
                positionX: positionX, positionY: positionY, topOffset: topOffset,
                runeCount: runes.count, timeMs: timeMs, durationMs: durationMs
            )
        }

        // タイプライター（タグ無し）の表示範囲。本家 GetTextRange。
        let visible = Self.visibleRange(
            values: values, timeMs: timeMs, durationMs: durationMs,
            runeCount: runes.count
        )
        guard visible.start < visible.end else { return [] }

        let pad = Int(ceil(values.fontSize / 7)) + 2
        let textureWidth = min(
            Self.maxTextureDimension, Int(ceil(layoutWidth)) + pad * 2
        )
        let textureHeight = min(
            Self.maxTextureDimension, Int(ceil(blockHeight)) + pad * 2
        )
        guard textureWidth > 0, textureHeight > 0 else { return [] }
        let boundsLeft = positionX - Double(pad)
        let boundsTop = positionY + topOffset - Double(pad)
        guard let texture = drawBitmap(
            width: textureWidth, height: textureHeight,
            boundsLeft: boundsLeft, boundsTop: boundsTop,
            lines: lines, positionX: positionX, positionY: positionY,
            topOffset: topOffset, values: values,
            visibleRange: visible, onlyRune: nil
        ) else { return [] }
        return [
            MetalTextPiece(
                texture: texture,
                bounds: RectF(
                    left: boundsLeft, top: boundsTop,
                    right: boundsLeft + Double(textureWidth),
                    bottom: boundsTop + Double(textureHeight)
                ),
                drawingOffset: .zero,
                timeOffset: .zero,
                durationOffset: .zero
            ),
        ]
    }

    // MARK: - 文字分割

    /// 文字単位の分割出力。本家はグリフクラスタごとに、その視覚中心が
    /// 原点に来るコマンドリストを作り、DrawingOffset に中心の平面座標、
    /// TimeOffset / DurationOffset に表示・消去の時間窓を持たせる。
    /// 表示フィルタ（FilterDisplayOutputs）もここで適用する。
    private func rasterizeDivided(
        lines: [TextLine], values: MetalTextStyleValues,
        positionX: Double, positionY: Double, topOffset: Double,
        runeCount: Int, timeMs: Double, durationMs: Double
    ) -> [MetalTextPiece] {
        // 全グリフをレイアウト順に平坦化する。
        struct PlacedGlyph {
            var glyph: TextGlyph
            var centerX: Double
            var baselineY: Double
            var lineAscent: Double
            var lineDescent: Double
        }
        var placed: [PlacedGlyph] = []
        for line in lines {
            for glyph in line.glyphs {
                placed.append(PlacedGlyph(
                    glyph: glyph,
                    centerX: positionX + line.xOffset + glyph.x + glyph.advance / 2,
                    baselineY: positionY + topOffset + line.baselineFromTop,
                    lineAscent: line.ascent,
                    lineDescent: line.descent
                ))
            }
        }
        let count = placed.count
        guard count > 0 else { return [] }

        // 表示・消去の順位（本家 CustomTextRendererBase の rank 計算）。
        let displayRanks = Self.ranks(
            count: count, direction: values.displayDirection, seed: runeCount
        )
        let hideRanks = Self.ranks(
            count: count, direction: values.hideDirection, seed: runeCount &+ 1
        )

        var pieces: [MetalTextPiece] = []
        for (index, entry) in placed.enumerated() {
            let timeOffsetMs = min(
                0, -values.displayIntervalMs * Double(displayRanks[index])
            )
            let durationOffsetMs = min(
                0, -values.hideIntervalMs * Double(count - 1 - hideRanks[index])
            )
            // FilterDisplayOutputs（制御タグ無しの場合）。
            if values.displayIntervalMs != 0, !(0 <= timeMs + timeOffsetMs) {
                continue
            }
            if values.hideIntervalMs != 0,
               !(timeMs + timeOffsetMs < durationMs + durationOffsetMs + timeOffsetMs) {
                continue
            }
            let glyph = entry.glyph
            let fontAscent = CTFontGetAscent(glyph.font)
            let fontDescent = CTFontGetDescent(glyph.font)
            let centerAboveBaseline = (fontAscent - fontDescent) / 2
            let centerY = entry.baselineY - centerAboveBaseline
            let pad = Int(ceil(glyph.fontSize / 7)) + 2
            let textureWidth = min(
                Self.maxTextureDimension, Int(ceil(glyph.advance)) + pad * 2
            )
            let textureHeight = min(
                Self.maxTextureDimension,
                Int(ceil(fontAscent + fontDescent)) + pad * 2
            )
            guard textureWidth > 0, textureHeight > 0 else { continue }
            // テクスチャ中心がグリフの視覚中心に一致するよう描く。
            // drawBitmap へ渡す座標は平面座標（境界の原点基準）であり、
            // ビットマップ座標ではない。境界は中心原点なので、ペン位置は
            // 進み量の半分だけ負側、ベースラインは視覚中心から
            // centerAboveBaseline だけ下（平面は y 下向き）になる。
            let boundsLeft = -Double(textureWidth) / 2
            let boundsTop = -Double(textureHeight) / 2
            var singleLine = TextLine()
            var singleGlyph = glyph
            singleGlyph.x = -glyph.advance / 2
            singleLine.glyphs = [singleGlyph]
            singleLine.ascent = fontAscent
            singleLine.descent = fontDescent
            singleLine.baselineFromTop = centerAboveBaseline
            guard let texture = drawBitmap(
                width: textureWidth, height: textureHeight,
                boundsLeft: boundsLeft, boundsTop: boundsTop,
                lines: [singleLine], positionX: 0, positionY: 0, topOffset: 0,
                values: values, visibleRange: (start: 0, end: Int.max),
                onlyRune: glyph.runeIndex
            ) else { continue }
            pieces.append(MetalTextPiece(
                texture: texture,
                bounds: RectF(
                    left: boundsLeft, top: boundsTop,
                    right: boundsLeft + Double(textureWidth),
                    bottom: boundsTop + Double(textureHeight)
                ),
                drawingOffset: Vector2(x: entry.centerX, y: centerY),
                timeOffset: TimeSpanValue(seconds: timeOffsetMs / 1000),
                durationOffset: TimeSpanValue(seconds: durationOffsetMs / 1000)
            ))
        }
        return pieces
    }

    /// 方向に対する順位列。Random は本家が GetHashCode() 由来の種で
    /// 決めるため再現不能（本家自体も実行ごとに変わる）。ここでは
    /// テキスト長由来の決定的なシャッフルで代用する（台帳に記録）。
    private static func ranks(
        count: Int, direction: TypewriterAnimationDirection, seed: Int
    ) -> [Int] {
        switch direction {
        case .fromFirst:
            return Array(0..<count)
        case .fromLast:
            return Array((0..<count).reversed())
        case .random, .unknown:
            var order = Array(0..<count)
            var state = UInt64(bitPattern: Int64(seed)) &* 0x9E3779B97F4A7C15 &+ 0x1234567
            for i in stride(from: count - 1, through: 1, by: -1) {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let j = Int((state >> 33) % UInt64(i + 1))
                order.swapAt(i, j)
            }
            var result = [Int](repeating: 0, count: count)
            for (rank, index) in order.enumerated() {
                result[index] = rank
            }
            return result
        }
    }

    // MARK: - 縦書き

    /// 縦書き（BasePoint が V 系）の経路。CTFramesetter の縦組み
    /// （columns が右から左へ進む）からグリフを取り出し、本家の
    /// 転置した配置式（原点 X はベースライン補正の符号反転、原点 Y は
    /// TextAlignment を LayoutHeight へ適用）で平面へ写す。
    /// CoreText の縦組みメトリクスは DirectWrite と異なるため近似である
    /// （台帳に記録）。文字分割・タイプライターは縦書きでは未対応。
    private func rasterizeVertical(
        text: String, decorations: [TextDecoration],
        values: MetalTextStyleValues,
        runes: [Unicode.Scalar], runeIndexByUTF16: [Int: Int]
    ) -> [MetalTextPiece] {
        let baseFont = MetalFontResolver.resolve(
            named: values.fontName, size: values.fontSize,
            bold: values.bold, italic: values.italic
        )
        let attributed = Self.buildAttributedString(
            text: text, decorations: decorations, values: values,
            baseFont: baseFont, runes: runes
        )
        let runeTraits = Self.buildRuneTraits(
            runeCount: runes.count, decorations: decorations, values: values
        )
        let framesetter = CTFramesetterCreateWithAttributedString(
            attributed as CFAttributedString
        )
        // 本家は MaxWidth プロパティを縦書きでは MaxHeight として使う。
        let constraintHeight = values.maxWidth > 0 ? values.maxWidth : 100_000
        var suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0),
            Self.verticalFrameAttributes(),
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat(constraintHeight)),
            nil
        )
        if suggested.width <= 0 { suggested.width = 1 }
        if suggested.height <= 0 { suggested.height = 1 }
        let framePath = CGPath(
            rect: CGRect(x: 0, y: 0, width: suggested.width, height: suggested.height),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: 0, length: 0), framePath,
            Self.verticalFrameAttributes()
        )

        let frameWidth = Double(suggested.width)
        let frameHeight = Double(suggested.height)
        // 第1列のメトリクスでベースライン補正（本家の転置式）。
        let ctLines = CTFrameGetLines(frame) as? [CTLine] ?? []
        var origins = [CGPoint](repeating: .zero, count: ctLines.count)
        if !ctLines.isEmpty {
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        }
        var firstAscent = values.fontSize
        var firstThickness = values.fontSize
        if let first = ctLines.first {
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(first, &ascent, &descent, &leading)
            firstAscent = Double(ascent)
            firstThickness = Double(ascent + descent + leading)
        }
        let lineHeightRate = values.lineHeightPercent / 100
        let num2: Double
        switch Self.paragraphAlignment(of: values.basePoint) {
        case .near:
            num2 = firstAscent * (1 - lineHeightRate)
        case .center:
            num2 = (firstAscent - firstThickness / 2) * (1 - lineHeightRate)
        case .far:
            num2 = (firstThickness - firstAscent) * (lineHeightRate - 1)
        }
        let positionX = -num2
        let positionY: Double
        switch Self.textAlignment(of: values.basePoint) {
        case .leading: positionY = 0
        case .center: positionY = -frameHeight / 2
        case .trailing: positionY = -frameHeight
        }

        _ = origins
        _ = runeTraits
        // 縦書きの描画はフレーム座標系のまま CTFrameDraw で描く。
        // 属性（フォント・色）は属性付き文字列から効くが、縁取り・影の
        // 幾何パスと字間の自前加算は横書き経路だけの対応になる
        // （縦書きの差分として台帳に記録）。
        let pad = Int(ceil(values.fontSize / 7)) + 2
        let textureWidth = min(Self.maxTextureDimension, Int(ceil(frameWidth)) + pad * 2)
        let textureHeight = min(Self.maxTextureDimension, Int(ceil(frameHeight)) + pad * 2)
        guard textureWidth > 0, textureHeight > 0,
              let bitmap = CGContext(
                data: nil, width: textureWidth, height: textureHeight,
                bitsPerComponent: 8, bytesPerRow: textureWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
              )
        else { return [] }
        bitmap.translateBy(x: CGFloat(pad), y: CGFloat(pad))
        CTFrameDraw(frame, bitmap)
        guard let texture = upload(bitmap: bitmap) else { return [] }
        let boundsLeft = positionX - Double(pad)
        let boundsTop = positionY - Double(pad)
        return [
            MetalTextPiece(
                texture: texture,
                bounds: RectF(
                    left: boundsLeft, top: boundsTop,
                    right: boundsLeft + Double(textureWidth),
                    bottom: boundsTop + Double(textureHeight)
                ),
                drawingOffset: .zero,
                timeOffset: .zero,
                durationOffset: .zero
            ),
        ]
    }

    private static func verticalFrameAttributes() -> CFDictionary {
        [kCTFrameProgressionAttributeName:
            NSNumber(value: CTFrameProgression.rightToLeft.rawValue)] as CFDictionary
    }

    // MARK: - 行レイアウト（横書き）

    private func layoutLines(
        attributed: NSAttributedString,
        values: MetalTextStyleValues,
        baseFont: MetalFontResolution,
        runeTraits: RuneTraits,
        runeIndexByUTF16: [Int: Int]
    ) -> [TextLine] {
        let fullText = attributed.string
        // 段落分割（\r\n は1つの改行として扱う）。
        var paragraphs: [(range: NSRange, runeOffset: Int)] = []
        var searchStart = 0
        var runeCursor = 0
        let nsText = fullText as NSString
        while searchStart <= nsText.length {
            let rest = NSRange(location: searchStart, length: nsText.length - searchStart)
            let newlineRange = nsText.rangeOfCharacter(
                from: CharacterSet(charactersIn: "\r\n"), range: rest
            )
            if newlineRange.location == NSNotFound {
                paragraphs.append((
                    range: NSRange(location: searchStart, length: nsText.length - searchStart),
                    runeOffset: runeCursor
                ))
                break
            }
            paragraphs.append((
                range: NSRange(location: searchStart, length: newlineRange.location - searchStart),
                runeOffset: runeCursor
            ))
            var newlineLength = newlineRange.length
            if newlineRange.length == 1,
               nsText.character(at: newlineRange.location) == 0x0D,
               newlineRange.location + 1 < nsText.length,
               nsText.character(at: newlineRange.location + 1) == 0x0A {
                newlineLength = 2
            }
            let paragraphRunes = nsText.substring(
                with: NSRange(location: searchStart, length: newlineRange.location - searchStart)
            ).unicodeScalars.count
            runeCursor += paragraphRunes + 1
            searchStart = newlineRange.location + newlineLength
            if searchStart > nsText.length { break }
            if searchStart == nsText.length {
                // 末尾の改行は空の最終行を生む。
                paragraphs.append((range: NSRange(location: searchStart, length: 0), runeOffset: runeCursor))
                break
            }
        }

        var lines: [TextLine] = []
        for paragraph in paragraphs {
            let sub = attributed.attributedSubstring(from: paragraph.range)
            if sub.length == 0 {
                var line = TextLine()
                line.ascent = CTFontGetAscent(baseFont.font)
                line.descent = CTFontGetDescent(baseFont.font)
                line.leading = CTFontGetLeading(baseFont.font)
                lines.append(line)
                continue
            }
            let ctLines: [CTLine]
            let wraps = (values.wordWrap == .wholeWord || values.wordWrap == .character)
                && values.maxWidth > 0
            if wraps {
                ctLines = breakLines(
                    attributed: sub, width: values.maxWidth,
                    characterBreak: values.wordWrap == .character
                )
            } else {
                ctLines = [CTLineCreateWithAttributedString(sub as CFAttributedString)]
            }
            for ctLine in ctLines {
                var line = TextLine()
                var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
                CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading)
                line.ascent = Double(ascent)
                line.descent = Double(descent)
                line.leading = Double(leading)
                line.glyphs = extractGlyphs(
                    from: ctLine, attributed: sub, runeTraits: runeTraits,
                    runeIndexByUTF16: runeIndexByUTF16,
                    paragraphUTF16Offset: paragraph.range.location
                )
                // 行末グリフの字間は本家が 0 に戻す（ApplyZeroTrailingAtLineEnds）。
                if !line.glyphs.isEmpty {
                    line.glyphs[line.glyphs.count - 1].spacingAfter = 0
                }
                line.width = line.glyphs.map { $0.advance + $0.spacingAfter }.reduce(0, +)
                lines.append(line)
            }
        }
        return lines
    }

    /// CTTypesetter による折り返し。本家の WordWrap（WholeWord は単語
    /// 単位、Character はクラスタ単位）に対応する。
    private func breakLines(
        attributed: NSAttributedString, width: Double, characterBreak: Bool
    ) -> [CTLine] {
        let typesetter = CTTypesetterCreateWithAttributedString(
            attributed as CFAttributedString
        )
        var lines: [CTLine] = []
        var index = 0
        let total = attributed.length
        while index < total {
            let count = characterBreak
                ? CTTypesetterSuggestClusterBreak(typesetter, index, width)
                : CTTypesetterSuggestLineBreak(typesetter, index, width)
            let fit = max(1, count)
            let line = CTTypesetterCreateLineWithOffset(
                typesetter, CFRange(location: index, length: fit), 0
            )
            lines.append(line)
            index += fit
        }
        return lines.isEmpty
            ? [CTLineCreateWithAttributedString(attributed as CFAttributedString)]
            : lines
    }

    /// CTLine からグリフ列を取り出す。進み量は CoreText の整形結果を
    /// そのまま使い、字間は自前で後方へ加える（本家の trailing 方式）。
    private func extractGlyphs(
        from line: CTLine,
        attributed: NSAttributedString,
        runeTraits: RuneTraits,
        runeIndexByUTF16: [Int: Int],
        paragraphUTF16Offset: Int
    ) -> [TextGlyph] {
        var result: [TextGlyph] = []
        var penX = 0.0
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            var advances = [CGSize](repeating: .zero, count: count)
            CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let font = attributes[kCTFontAttributeName as String] as! CTFont
            let fontSize = CTFontGetSize(font)
            for i in 0..<count {
                let stringIndex = indices[i] + paragraphUTF16Offset
                let runeIndex = runeIndexByUTF16[stringIndex] ?? 0
                let traits = runeTraits.traits(for: runeIndex)
                let advance = Double(advances[i].width)
                result.append(TextGlyph(
                    glyph: glyphs[i],
                    font: font,
                    fontSize: fontSize,
                    advance: advance,
                    spacingAfter: traits.spacing,
                    runeIndex: runeIndex,
                    color: traits.color,
                    style: traits.style,
                    styleColor: traits.styleColor,
                    underline: traits.underline,
                    strikethrough: traits.strikethrough,
                    x: penX
                ))
                penX += advance + traits.spacing
            }
        }
        return result
    }

    // MARK: - ビットマップ描画

    /// 行列をビットマップへ描き、テクスチャ化する。座標変換:
    /// 平面座標 (px, py) はビットマップの (px − boundsLeft, py − boundsTop)
    /// へ写り、CGContext の y-up へは高さで反転する。グリフパスは
    /// ベースライン原点・y-up のため、平行移動だけで一致する。
    private func drawBitmap(
        width: Int, height: Int,
        boundsLeft: Double, boundsTop: Double,
        lines: [TextLine],
        positionX: Double, positionY: Double, topOffset: Double,
        values: MetalTextStyleValues,
        visibleRange: (start: Int, end: Int),
        onlyRune: Int?
    ) -> MTLTexture? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let bitmap = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
            ) else { return false }
            for pass in 0..<2 {
                for line in lines {
                    let baselinePlaneY = positionY + topOffset + line.baselineFromTop
                    for glyph in line.glyphs {
                        if let onlyRune, glyph.runeIndex != onlyRune { continue }
                        if glyph.runeIndex < visibleRange.start
                            || glyph.runeIndex >= visibleRange.end { continue }
                        let glyphPlaneX = positionX + line.xOffset + glyph.x
                        if pass == 0 {
                            drawStylePass(
                                bitmap: bitmap, glyph: glyph,
                                planeX: glyphPlaneX, baselinePlaneY: baselinePlaneY,
                                boundsLeft: boundsLeft, boundsTop: boundsTop,
                                height: height
                            )
                        } else {
                            drawForegroundPass(
                                bitmap: bitmap, glyph: glyph,
                                planeX: glyphPlaneX, baselinePlaneY: baselinePlaneY,
                                boundsLeft: boundsLeft, boundsTop: boundsTop,
                                height: height
                            )
                        }
                    }
                    if pass == 1 {
                        drawLineDecorations(
                            bitmap: bitmap, line: line,
                            positionX: positionX,
                            baselinePlaneY: baselinePlaneY,
                            boundsLeft: boundsLeft, boundsTop: boundsTop,
                            height: height, visibleRange: visibleRange,
                            onlyRune: onlyRune
                        )
                    }
                }
            }
            return true
        }
        guard drawn else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = devices.device.makeTexture(descriptor: descriptor)
        else { return nil }
        bytes.withUnsafeBytes { buffer in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: buffer.baseAddress!, bytesPerRow: width * 4
            )
        }
        return texture
    }

    private func upload(bitmap: CGContext) -> MTLTexture? {
        let width = bitmap.width
        let height = bitmap.height
        guard let data = bitmap.data else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = devices.device.makeTexture(descriptor: descriptor)
        else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
            withBytes: data, bytesPerRow: bitmap.bytesPerRow
        )
        return texture
    }

    /// 背景パス: 縁取り（輪郭ストローク）と影（オフセット塗り）。
    /// 本家 CustomTextBackgroundRenderer の幾何規則どおり:
    /// 線幅は Border 系が EmSize/7、Light 系が EmSize/14。結合は
    /// Border 系が Round、SharpBorder 系が MiterOrBevel（MiterLimit 2）。
    /// 影のオフセットは EmSize/24、不透明度は Shadow が 1.0、
    /// ShadowLight が 0.5。ぼかしは無い。
    private func drawStylePass(
        bitmap: CGContext, glyph: TextGlyph,
        planeX: Double, baselinePlaneY: Double,
        boundsLeft: Double, boundsTop: Double, height: Int
    ) {
        switch glyph.style {
        case .normal, .unknown:
            return
        case .shadow, .shadowLight:
            let offset = glyph.fontSize / 24
            guard let path = translatedGlyphPath(
                glyph: glyph, planeX: planeX, baselinePlaneY: baselinePlaneY,
                boundsLeft: boundsLeft, boundsTop: boundsTop, height: height,
                extraX: offset, extraPlaneY: offset
            ) else { return }
            let alpha = Double(glyph.styleColor.alpha) / 255
                * (glyph.style == .shadow ? 1.0 : 0.5)
            bitmap.setFillColor(Self.cgColor(glyph.styleColor, alphaScale: alpha))
            bitmap.addPath(path)
            bitmap.fillPath()
        case .border, .borderLight, .sharpBorder, .sharpBorderLight:
            guard let path = translatedGlyphPath(
                glyph: glyph, planeX: planeX, baselinePlaneY: baselinePlaneY,
                boundsLeft: boundsLeft, boundsTop: boundsTop, height: height,
                extraX: 0, extraPlaneY: 0
            ) else { return }
            let isLight = glyph.style == .borderLight || glyph.style == .sharpBorderLight
            let isSharp = glyph.style == .sharpBorder || glyph.style == .sharpBorderLight
            bitmap.setStrokeColor(Self.cgColor(glyph.styleColor, alphaScale: 1))
            bitmap.setLineWidth(CGFloat(glyph.fontSize / (isLight ? 14 : 7)))
            bitmap.setLineJoin(isSharp ? .miter : .round)
            bitmap.setMiterLimit(2)
            bitmap.addPath(path)
            bitmap.strokePath()
        }
    }

    /// 前景パス: グリフ本体を前景色で塗る。輪郭パスが得られない
    /// グリフ（カラーグリフ等）は CTFontDrawGlyphs へフォールバックする。
    private func drawForegroundPass(
        bitmap: CGContext, glyph: TextGlyph,
        planeX: Double, baselinePlaneY: Double,
        boundsLeft: Double, boundsTop: Double, height: Int
    ) {
        if let path = translatedGlyphPath(
            glyph: glyph, planeX: planeX, baselinePlaneY: baselinePlaneY,
            boundsLeft: boundsLeft, boundsTop: boundsTop, height: height,
            extraX: 0, extraPlaneY: 0
        ), !path.isEmpty {
            bitmap.setFillColor(Self.cgColor(glyph.color, alphaScale: 1))
            bitmap.addPath(path)
            bitmap.fillPath(using: .evenOdd)
            return
        }
        var glyphID = glyph.glyph
        var position = CGPoint(
            x: CGFloat(planeX - boundsLeft),
            y: CGFloat(Double(height) - (baselinePlaneY - boundsTop))
        )
        bitmap.setFillColor(Self.cgColor(glyph.color, alphaScale: 1))
        withUnsafePointer(to: &glyphID) { glyphPtr in
            withUnsafePointer(to: &position) { positionPtr in
                CTFontDrawGlyphs(glyph.font, glyphPtr, positionPtr, 1, bitmap)
            }
        }
    }

    private func translatedGlyphPath(
        glyph: TextGlyph, planeX: Double, baselinePlaneY: Double,
        boundsLeft: Double, boundsTop: Double, height: Int,
        extraX: Double, extraPlaneY: Double
    ) -> CGPath? {
        guard let path = CTFontCreatePathForGlyph(glyph.font, glyph.glyph, nil)
        else { return nil }
        var transform = CGAffineTransform(
            translationX: CGFloat(planeX - boundsLeft + extraX),
            y: CGFloat(Double(height) - (baselinePlaneY + extraPlaneY - boundsTop))
        )
        return path.copy(using: &transform)
    }

    /// 下線・打消し線を行単位で引く。本家は前景・背景の両レンダラで
    /// 線を描く二重構造だが、可視結果の近似として前景色の塗り矩形で
    /// 代表させる。打消し線の位置は CoreText に公開メトリクスが無いため
    /// x-height の半分で近似する（台帳に記録）。
    private func drawLineDecorations(
        bitmap: CGContext, line: TextLine, positionX: Double,
        baselinePlaneY: Double,
        boundsLeft: Double, boundsTop: Double, height: Int,
        visibleRange: (start: Int, end: Int), onlyRune: Int?
    ) {
        func segments(_ keyPath: KeyPath<TextGlyph, Bool>) -> [(TextGlyph, TextGlyph)] {
            var result: [(TextGlyph, TextGlyph)] = []
            var current: (TextGlyph, TextGlyph)?
            for glyph in line.glyphs {
                if let onlyRune, glyph.runeIndex != onlyRune { continue }
                if glyph.runeIndex < visibleRange.start
                    || glyph.runeIndex >= visibleRange.end { continue }
                if glyph[keyPath: keyPath] {
                    if current == nil {
                        current = (glyph, glyph)
                    } else {
                        current!.1 = glyph
                    }
                } else if let finished = current {
                    result.append(finished)
                    current = nil
                }
            }
            if let finished = current { result.append(finished) }
            return result
        }
        for (first, last) in segments(\.underline) {
            let thickness = max(1, CTFontGetUnderlineThickness(first.font))
            // CTFontGetUnderlinePosition はベースラインからの y-up 距離
            // （通常は負値＝下方）。
            let position = CTFontGetUnderlinePosition(first.font)
            let planeY = baselinePlaneY - Double(position)
            fillPlaneRect(
                bitmap: bitmap,
                x: positionX + line.xOffset + first.x,
                y: planeY,
                width: (last.x + last.advance) - first.x,
                height: Double(thickness),
                color: first.color,
                boundsLeft: boundsLeft, boundsTop: boundsTop, height: height
            )
        }
        for (first, last) in segments(\.strikethrough) {
            let thickness = max(1, CTFontGetUnderlineThickness(first.font))
            let planeY = baselinePlaneY
                - Double(CTFontGetXHeight(first.font)) / 2 - Double(thickness) / 2
            fillPlaneRect(
                bitmap: bitmap,
                x: positionX + line.xOffset + first.x,
                y: planeY,
                width: (last.x + last.advance) - first.x,
                height: Double(thickness),
                color: first.color,
                boundsLeft: boundsLeft, boundsTop: boundsTop, height: height
            )
        }
    }

    private func fillPlaneRect(
        bitmap: CGContext, x: Double, y: Double, width: Double, height rectHeight: Double,
        color: Color, boundsLeft: Double, boundsTop: Double, height: Int
    ) {
        bitmap.setFillColor(Self.cgColor(color, alphaScale: 1))
        let contextY = Double(height) - (y + rectHeight - boundsTop)
        bitmap.fill(CGRect(
            x: CGFloat(x - boundsLeft), y: CGFloat(contextY),
            width: CGFloat(width), height: CGFloat(rectHeight)
        ))
    }

    static func cgColor(_ color: Color, alphaScale: Double) -> CGColor {
        CGColor(
            red: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255,
            alpha: CGFloat(color.alpha) / 255 * CGFloat(alphaScale)
        )
    }

    // MARK: - 属性付き文字列とルーン特性

    struct RuneTraits {
        var spacing: [Double]
        var color: [Color]
        var style: [TextStyle]
        var styleColor: [Color]
        var underline: [Bool]
        var strikethrough: [Bool]

        func traits(for rune: Int) -> (
            spacing: Double, color: Color, style: TextStyle,
            styleColor: Color, underline: Bool, strikethrough: Bool
        ) {
            guard spacing.indices.contains(rune) else {
                return (0, .white, .normal, .black, false, false)
            }
            return (
                spacing[rune], color[rune], style[rune],
                styleColor[rune], underline[rune], strikethrough[rune]
            )
        }
    }

    /// ルーン単位の特性表（字間上書き・前景色・スタイル上書き・線）。
    /// 本家はレイアウトへの範囲上書きとレンダラ側のエントリ表でこれを
    /// 表す。装飾の位置ずらし・回転はここでは扱わない（未実装として
    /// 台帳に記録）。
    static func buildRuneTraits(
        runeCount: Int, decorations: [TextDecoration],
        values: MetalTextStyleValues
    ) -> RuneTraits {
        var traits = RuneTraits(
            spacing: [Double](repeating: values.letterSpacing, count: runeCount),
            color: [Color](repeating: values.fontColor, count: runeCount),
            style: [TextStyle](repeating: values.style, count: runeCount),
            styleColor: [Color](repeating: values.styleColor, count: runeCount),
            underline: [Bool](repeating: values.underline, count: runeCount),
            strikethrough: [Bool](repeating: values.strikethrough, count: runeCount)
        )
        for decoration in decorations where decoration.hasDecoration {
            let start = max(0, decoration.start)
            let end = min(runeCount, decoration.start + decoration.length)
            guard start < end else { continue }
            for rune in start..<end {
                if let spacing = decoration.characterSpacing {
                    traits.spacing[rune] = spacing
                }
                if let foreground = decoration.foreground {
                    traits.color[rune] = foreground
                }
                if let styleType = decoration.styleType,
                   let style = textStyle(fromDecorationValue: styleType) {
                    traits.style[rune] = style
                    if let decorationColor = decoration.decorationColor {
                        traits.styleColor[rune] = decorationColor
                    }
                }
                if decoration.isUnderline { traits.underline[rune] = true }
                if decoration.isStrikethrough { traits.strikethrough[rune] = true }
            }
        }
        return traits
    }

    /// 装飾の StyleType（本家 Style 列挙の数値）から TextStyle へ。
    static func textStyle(fromDecorationValue value: Int) -> TextStyle? {
        switch value {
        case 0: return .normal
        case 1: return .shadow
        case 2: return .shadowLight
        case 3: return .border
        case 4: return .borderLight
        case 5: return .sharpBorder
        case 6: return .sharpBorderLight
        default: return nil
        }
    }

    /// 属性付き文字列を構築する。フォントと前景色だけを CoreText の
    /// 属性で与え、字間は進み量の自前加算で扱うため kern 属性は付けない。
    static func buildAttributedString(
        text: String, decorations: [TextDecoration],
        values: MetalTextStyleValues, baseFont: MetalFontResolution,
        runes: [Unicode.Scalar]
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: attributed.length)
        let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        attributed.addAttribute(fontKey, value: baseFont.font, range: fullRange)
        attributed.addAttribute(
            colorKey, value: cgColor(values.fontColor, alphaScale: 1), range: fullRange
        )
        // ルーン範囲 → UTF-16 範囲の換算表。
        var utf16Starts: [Int] = []
        var offset = 0
        for scalar in runes {
            utf16Starts.append(offset)
            offset += scalar.utf16.count
        }
        utf16Starts.append(offset)
        for decoration in decorations where decoration.hasDecoration {
            let startRune = max(0, decoration.start)
            let endRune = min(runes.count, decoration.start + decoration.length)
            guard startRune < endRune else { continue }
            let range = NSRange(
                location: utf16Starts[startRune],
                length: utf16Starts[endRune] - utf16Starts[startRune]
            )
            // フォント: 装飾のフォント名が解決できなければ基準フォントの
            // 記録へフォールバックする（本家の FirstOrDefault(font)）。
            let fontName = decoration.font ?? values.fontName
            let resolved = MetalFontResolver.resolve(
                named: fontName,
                size: values.fontSize * decoration.scale,
                bold: decoration.isBold || values.bold,
                italic: decoration.isItalic || values.italic,
                fallback: decoration.font == nil ? nil : MetalFontResolution(
                    font: CTFontCreateCopyWithAttributes(
                        baseFont.font, CGFloat(values.fontSize * decoration.scale),
                        nil, nil
                    ),
                    canonicalWeight: baseFont.canonicalWeight,
                    isResolved: baseFont.isResolved
                )
            )
            attributed.addAttribute(fontKey, value: resolved.font, range: range)
            if let foreground = decoration.foreground {
                attributed.addAttribute(
                    colorKey, value: cgColor(foreground, alphaScale: 1), range: range
                )
            }
        }
        return attributed
    }

    // MARK: - 前処理

    /// 本家 TextHelper.ApplyNormalize の再現: NFC 正規化し、
    /// IsTrimEndSpace のとき行末の空白を除去する。装飾の範囲は
    /// ルーン対応表で張り直す（対応が取れない場合は範囲をクランプする）。
    static func normalize(
        text: String, decorations: [TextDecoration], isTrimEndSpace: Bool
    ) -> (text: String, decorations: [TextDecoration]) {
        let normalized = text.precomposedStringWithCanonicalMapping
        var resultText = normalized
        if isTrimEndSpace {
            // 行末除去は改行種別を保ったまま各行の末尾空白を削る。
            var output = ""
            var current = ""
            func flush(end: String) {
                var line = current
                while line.last == " " || line.last == "　" || line.last == "\t" {
                    line.removeLast()
                }
                output += line + end
                current = ""
            }
            var index = normalized.startIndex
            while index < normalized.endIndex {
                let ch = normalized[index]
                let next = normalized.index(after: index)
                if ch == "\r", next < normalized.endIndex, normalized[next] == "\n" {
                    flush(end: "\r\n")
                    index = normalized.index(after: next)
                } else if ch == "\r" || ch == "\n" {
                    flush(end: String(ch))
                    index = next
                } else {
                    current.append(ch)
                    index = next
                }
            }
            flush(end: "")
            resultText = output
        }
        // 装飾範囲の張り直し: 正規化でルーン数が変わらない通常ケースは
        // そのまま。変わった場合は開始・長さをクランプする。
        let originalRunes = text.unicodeScalars.count
        let resultRunes = resultText.unicodeScalars.count
        var adjusted = decorations
        if originalRunes != resultRunes {
            adjusted = decorations.map { decoration in
                var copy = decoration
                copy.start = min(copy.start, resultRunes)
                copy.length = min(copy.length, resultRunes - copy.start)
                return copy
            }
        }
        return (resultText, adjusted)
    }

    // MARK: - 配置

    enum TextAlignmentKind { case leading, center, trailing }
    enum ParagraphAlignmentKind { case near, center, far }

    static func isVertical(_ basePoint: BasePoint) -> Bool {
        switch basePoint {
        case .vTopRight, .vCenterRight, .vBottomRight,
             .vTopCenter, .vCenterCenter, .vBottomCenter,
             .vTopLeft, .vCenterLeft, .vBottomLeft:
            return true
        default:
            return false
        }
    }

    /// 本家 TextFormatDescription の TextAlignment 決定表（横書き）。
    static func textAlignment(of basePoint: BasePoint) -> TextAlignmentKind {
        switch basePoint {
        case .leftTop, .leftCenter, .leftBottom,
             .vTopRight, .vTopCenter, .vTopLeft:
            return .leading
        case .centerTop, .centerCenter, .centerBottom,
             .vCenterRight, .vCenterCenter, .vCenterLeft:
            return .center
        default:
            return .trailing
        }
    }

    /// 本家 TextFormatDescription の ParagraphAlignment 決定表（横書き）。
    static func paragraphAlignment(of basePoint: BasePoint) -> ParagraphAlignmentKind {
        switch basePoint {
        case .leftTop, .centerTop, .rightTop,
             .vTopRight, .vCenterRight, .vBottomRight:
            return .near
        case .leftCenter, .centerCenter, .rightCenter,
             .vTopCenter, .vCenterCenter, .vBottomCenter:
            return .center
        default:
            return .far
        }
    }

    /// タイプライター表示範囲（制御タグ無し）。本家
    /// CustomTextRendererBase.GetTextRange の、CharacterTiming が無い
    /// 経路の再現。単位はミリ秒、範囲はルーン番号。
    static func visibleRange(
        values: MetalTextStyleValues, timeMs: Double, durationMs: Double,
        runeCount: Int
    ) -> (start: Int, end: Int) {
        var start = 0
        var end = runeCount
        if values.displayIntervalMs > 0 {
            if values.displayDirection == .fromFirst {
                end = Int(timeMs / values.displayIntervalMs) + 1
            } else {
                start = runeCount - Int(timeMs / values.displayIntervalMs) - 1
            }
        }
        if values.hideIntervalMs > 0 {
            var hideStart = 0
            var hideEnd = runeCount
            if values.hideDirection == .fromFirst {
                hideStart = runeCount
                    - Int((durationMs - timeMs) / values.hideIntervalMs) - 1
            } else {
                hideEnd = Int((durationMs - timeMs) / values.hideIntervalMs) + 1
            }
            start = max(start, hideStart)
            end = min(end, hideEnd)
        }
        if end < start { start = end }
        start = max(0, start)
        end = min(runeCount, end)
        return (start, end)
    }
}

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
