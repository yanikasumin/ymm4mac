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

#endif
