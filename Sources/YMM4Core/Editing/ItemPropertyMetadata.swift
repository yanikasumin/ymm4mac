import Foundation

/// アイテムのプロパティメタデータ（MAC-0029）。
///
/// 全アイテム種に共通する基本プロパティと、`VisualItem` 系譜の描画
/// プロパティはここで一括して記述する。個別のアイテム種は、自分の
/// 固有プロパティの記述を追加するだけでインスペクタに並ぶ。
/// 表示名は本家の `Texts` リソース（`BaseItem*Name` / `VisualItem*Name` /
/// `TextItem*Name` / `VoiceItem*Name` と各 enum メンバ名）に根拠がある
/// ものはその文言を使い、根拠が取れないものはプロパティ名そのままにする。
public enum ItemPropertyMetadata {
    /// アイテムの編集可能プロパティを宣言順に返す。
    /// アニメーション種別にはスライダ表示仕様（FE-R1-042）を解決して
    /// 付ける。所有型の候補は「具象アイテム型 → `VisualItem` →
    /// `BaseItem`」の順: 本家ではプロパティごとに宣言クラスが異なり
    /// （Volume は具象型、X 等は `VisualItem`、`PlaybackRate2` は
    /// 具象型ごとに範囲が異なる再宣言）、最初に一致した宣言を使う。
    public static func descriptors(for item: BaseItem) -> [PropertyDescriptor] {
        var result = baseDescriptors(for: item)
        if let visual = item as? VisualItem {
            result += videoDescriptors(group: "描画", idPrefix: "", accesses: videoAccesses(of: visual))
        }
        if let voice = item as? VoiceItem {
            result += voiceDescriptors(for: voice)
        }
        if let text = item as? TextItem {
            result += textItemDescriptors(for: text)
        }
        return AnimationSliderTable.resolving(
            result, ownerCandidates: sliderOwnerCandidates(for: item)
        )
    }

    /// スライダ仕様の所有型候補（具象型の $type 名＋宣言基底の
    /// 完全修飾名）。基底側はポートの型階層ではなく本家の宣言場所を
    /// 表すため、完全修飾名を直接書く。
    private static func sliderOwnerCandidates(for item: BaseItem) -> [String] {
        var candidates: [String] = [type(of: item).typeName]
        if item is VisualItem {
            candidates.append("YukkuriMovieMaker.Project.Items.VisualItem")
        }
        candidates.append("YukkuriMovieMaker.Project.Items.BaseItem")
        return candidates
    }

    // MARK: - 読み書きアクセスの組み立て

    /// クラスプロパティへの読み書きをキーパスから作る。
    private typealias Access<Value> = (get: () -> Value, set: (Value) -> Void)

    private static func access<Object: AnyObject, Value>(
        _ object: Object, _ keyPath: ReferenceWritableKeyPath<Object, Value>
    ) -> Access<Value> {
        (get: { object[keyPath: keyPath] }, set: { object[keyPath: keyPath] = $0 })
    }

    // MARK: - 全アイテム共通（BaseItem）

    private static func baseDescriptors(for item: BaseItem) -> [PropertyDescriptor] {
        let group = "基本"
        return [
            .integer(
                id: "Frame", displayName: "フレーム", group: group,
                get: { item.frame }, set: { item.frame = $0 }
            ),
            .integer(
                id: "Length", displayName: "長さ", group: group,
                get: { item.length }, set: { item.length = $0 }
            ),
            .integer(
                id: "Layer", displayName: "レイヤー", group: group,
                get: { item.layer }, set: { item.layer = $0 }
            ),
            .integer(
                id: "Group", displayName: "Group", group: group,
                get: { item.group }, set: { item.group = $0 }
            ),
            .animation(
                id: "PlaybackRate2", displayName: "再生速度", group: group,
                get: { item.playbackRate2 }, set: { item.playbackRate2 = $0 }
            ),
            .text(
                id: "Remark", displayName: "備考", group: group,
                get: { item.remark }, set: { item.remark = $0 }
            ),
            .boolean(
                id: "IsLocked", displayName: "ロック", group: group,
                get: { item.isLocked }, set: { item.isLocked = $0 }
            ),
            .boolean(
                id: "IsHidden", displayName: "非表示", group: group,
                get: { item.isHidden }, set: { item.isHidden = $0 }
            ),
        ]
    }

    // MARK: - 映像プロパティ一式（VisualItem 系譜と VoiceItem の字幕）

    private struct VideoAccesses {
        var x: Access<Animation>
        var y: Access<Animation>
        var z: Access<Animation>
        var opacity: Access<Animation>
        var zoom: Access<Animation>
        var rotation: Access<Animation>
        var fadeIn: Access<Double>
        var fadeOut: Access<Double>
        var blend: Access<Blend>
        var isInverted: Access<Bool>
        var isClippingWithObjectAbove: Access<Bool>
        var isAlwaysOnTop: Access<Bool>
        var isZOrderEnabled: Access<Bool>
    }

    private static func videoAccesses(of visual: VisualItem) -> VideoAccesses {
        VideoAccesses(
            x: access(visual, \.x), y: access(visual, \.y), z: access(visual, \.z),
            opacity: access(visual, \.opacity), zoom: access(visual, \.zoom),
            rotation: access(visual, \.rotation),
            fadeIn: access(visual, \.fadeIn), fadeOut: access(visual, \.fadeOut),
            blend: access(visual, \.blend),
            isInverted: access(visual, \.isInverted),
            isClippingWithObjectAbove: access(visual, \.isClippingWithObjectAbove),
            isAlwaysOnTop: access(visual, \.isAlwaysOnTop),
            isZOrderEnabled: access(visual, \.isZOrderEnabled)
        )
    }

    private static func videoAccesses(of voice: VoiceItem) -> VideoAccesses {
        VideoAccesses(
            x: access(voice, \.x), y: access(voice, \.y), z: access(voice, \.z),
            opacity: access(voice, \.opacity), zoom: access(voice, \.zoom),
            rotation: access(voice, \.rotation),
            fadeIn: access(voice, \.fadeIn), fadeOut: access(voice, \.fadeOut),
            blend: access(voice, \.blend),
            isInverted: access(voice, \.isInverted),
            isClippingWithObjectAbove: access(voice, \.isClippingWithObjectAbove),
            isAlwaysOnTop: access(voice, \.isAlwaysOnTop),
            isZOrderEnabled: access(voice, \.isZOrderEnabled)
        )
    }

    /// 表示名は `VisualItem*Name` / `VoiceItemJimaku*Name`（いずれも
    /// 本家リソースで同文言）による。
    private static func videoDescriptors(
        group: String, idPrefix: String, accesses a: VideoAccesses
    ) -> [PropertyDescriptor] {
        [
            .animation(
                id: idPrefix + "X", displayName: "X", group: group,
                get: a.x.get, set: a.x.set
            ),
            .animation(
                id: idPrefix + "Y", displayName: "Y", group: group,
                get: a.y.get, set: a.y.set
            ),
            .animation(
                id: idPrefix + "Z", displayName: "Z", group: group,
                get: a.z.get, set: a.z.set
            ),
            .animation(
                id: idPrefix + "Opacity", displayName: "不透明度", group: group,
                get: a.opacity.get, set: a.opacity.set
            ),
            .animation(
                id: idPrefix + "Zoom", displayName: "拡大率", group: group,
                get: a.zoom.get, set: a.zoom.set
            ),
            .animation(
                id: idPrefix + "Rotation", displayName: "回転角", group: group,
                get: a.rotation.get, set: a.rotation.set
            ),
            .number(
                id: idPrefix + "FadeIn", displayName: "フェードイン", group: group,
                get: a.fadeIn.get, set: a.fadeIn.set
            ),
            .number(
                id: idPrefix + "FadeOut", displayName: "フェードアウト", group: group,
                get: a.fadeOut.get, set: a.fadeOut.set
            ),
            .enumeration(
                id: idPrefix + "Blend", displayName: "合成モード", group: group,
                options: blendOptions,
                get: a.blend.get, set: a.blend.set
            ),
            .boolean(
                id: idPrefix + "IsInverted", displayName: "左右反転", group: group,
                get: a.isInverted.get, set: a.isInverted.set
            ),
            .boolean(
                id: idPrefix + "IsClippingWithObjectAbove", displayName: "クリッピング", group: group,
                get: a.isClippingWithObjectAbove.get, set: a.isClippingWithObjectAbove.set
            ),
            .boolean(
                id: idPrefix + "IsAlwaysOnTop", displayName: "手前に表示", group: group,
                get: a.isAlwaysOnTop.get, set: a.isAlwaysOnTop.set
            ),
            .boolean(
                id: idPrefix + "IsZOrderEnabled", displayName: "Z値順に表示", group: group,
                get: a.isZOrderEnabled.get, set: a.isZOrderEnabled.set
            ),
        ]
    }

    // MARK: - VoiceItem 固有

    private static func voiceDescriptors(for voice: VoiceItem) -> [PropertyDescriptor] {
        var result: [PropertyDescriptor] = [
            .text(
                id: "Serif", displayName: "セリフ", group: "音声", multiline: true,
                get: { voice.serif }, set: { voice.serif = $0 }
            ),
            .animation(
                id: "Volume", displayName: "音量", group: "音声",
                get: { voice.volume }, set: { voice.volume = $0 }
            ),
            .animation(
                id: "Pan", displayName: "パン", group: "音声",
                get: { voice.pan }, set: { voice.pan = $0 }
            ),
            .enumeration(
                id: "JimakuVisibility", displayName: "字幕の設定", group: "字幕",
                options: jimakuVisibilityOptions,
                get: { voice.jimakuVisibility }, set: { voice.jimakuVisibility = $0 }
            ),
        ]
        result += videoDescriptors(group: "字幕", idPrefix: "Jimaku", accesses: videoAccesses(of: voice))
        result += appearanceDescriptors(group: "字幕", accesses: appearanceAccesses(of: voice))
        return result
    }

    // MARK: - TextItem 固有

    private static func textItemDescriptors(for text: TextItem) -> [PropertyDescriptor] {
        var result: [PropertyDescriptor] = [
            .text(
                id: "Text", displayName: "テキスト", group: "テキスト", multiline: true,
                get: { text.text }, set: { text.text = $0 }
            ),
        ]
        result += appearanceDescriptors(group: "フォント", accesses: appearanceAccesses(of: text))
        return result
    }

    // MARK: - フォント外観一式（TextAppearance）

    private struct AppearanceAccesses {
        var font: Access<String>
        var fontSize: Access<Animation>
        var lineHeight2: Access<Animation>
        var letterSpacing2: Access<Animation>
        var maxWidth: Access<Animation>
        var wordWrap: Access<WordWrap>
        var basePoint: Access<BasePoint>
        var fontColor: Access<Color>
        var style: Access<TextStyle>
        var styleColor: Access<Color>
        var bold: Access<Bool>
        var italic: Access<Bool>
        var underline: Access<Bool>
        var strikethrough: Access<Bool>
        var isTrimEndSpace: Access<Bool>
        var isDevidedPerCharacter: Access<Bool>
        var displayInterval: Access<Double>
        var displayDirection: Access<TypewriterAnimationDirection>
        var hideInterval: Access<Double>
        var hideDirection: Access<TypewriterAnimationDirection>
    }

    private static func appearanceAccesses(of text: TextItem) -> AppearanceAccesses {
        AppearanceAccesses(
            font: access(text, \.appearance.font),
            fontSize: access(text, \.appearance.fontSize),
            lineHeight2: access(text, \.appearance.lineHeight2),
            letterSpacing2: access(text, \.appearance.letterSpacing2),
            maxWidth: access(text, \.appearance.maxWidth),
            wordWrap: access(text, \.appearance.wordWrap),
            basePoint: access(text, \.appearance.basePoint),
            fontColor: access(text, \.appearance.fontColor),
            style: access(text, \.appearance.style),
            styleColor: access(text, \.appearance.styleColor),
            bold: access(text, \.appearance.bold),
            italic: access(text, \.appearance.italic),
            underline: access(text, \.appearance.underline),
            strikethrough: access(text, \.appearance.strikethrough),
            isTrimEndSpace: access(text, \.appearance.isTrimEndSpace),
            isDevidedPerCharacter: access(text, \.appearance.isDevidedPerCharacter),
            displayInterval: access(text, \.appearance.displayInterval),
            displayDirection: access(text, \.appearance.displayDirection),
            hideInterval: access(text, \.appearance.hideInterval),
            hideDirection: access(text, \.appearance.hideDirection)
        )
    }

    private static func appearanceAccesses(of voice: VoiceItem) -> AppearanceAccesses {
        AppearanceAccesses(
            font: access(voice, \.appearance.font),
            fontSize: access(voice, \.appearance.fontSize),
            lineHeight2: access(voice, \.appearance.lineHeight2),
            letterSpacing2: access(voice, \.appearance.letterSpacing2),
            maxWidth: access(voice, \.appearance.maxWidth),
            wordWrap: access(voice, \.appearance.wordWrap),
            basePoint: access(voice, \.appearance.basePoint),
            fontColor: access(voice, \.appearance.fontColor),
            style: access(voice, \.appearance.style),
            styleColor: access(voice, \.appearance.styleColor),
            bold: access(voice, \.appearance.bold),
            italic: access(voice, \.appearance.italic),
            underline: access(voice, \.appearance.underline),
            strikethrough: access(voice, \.appearance.strikethrough),
            isTrimEndSpace: access(voice, \.appearance.isTrimEndSpace),
            isDevidedPerCharacter: access(voice, \.appearance.isDevidedPerCharacter),
            displayInterval: access(voice, \.appearance.displayInterval),
            displayDirection: access(voice, \.appearance.displayDirection),
            hideInterval: access(voice, \.appearance.hideInterval),
            hideDirection: access(voice, \.appearance.hideDirection)
        )
    }

    /// 表示名は `TextItem*Name` による。DisplayDirection / HideInterval /
    /// HideDirection はリソースに名前が無いためプロパティ名そのまま。
    private static func appearanceDescriptors(
        group: String, accesses a: AppearanceAccesses
    ) -> [PropertyDescriptor] {
        [
            .text(
                id: "Font", displayName: "フォント", group: group,
                get: a.font.get, set: a.font.set
            ),
            .animation(
                id: "FontSize", displayName: "サイズ", group: group,
                get: a.fontSize.get, set: a.fontSize.set
            ),
            .animation(
                id: "LineHeight2", displayName: "行の高さ", group: group,
                get: a.lineHeight2.get, set: a.lineHeight2.set
            ),
            .animation(
                id: "LetterSpacing2", displayName: "文字間隔", group: group,
                get: a.letterSpacing2.get, set: a.letterSpacing2.set
            ),
            .animation(
                id: "MaxWidth", displayName: "折り返し幅", group: group,
                get: a.maxWidth.get, set: a.maxWidth.set
            ),
            .enumeration(
                id: "WordWrap", displayName: "折り返し", group: group,
                options: wordWrapOptions,
                get: a.wordWrap.get, set: a.wordWrap.set
            ),
            .enumeration(
                id: "BasePoint", displayName: "文字揃え", group: group,
                options: basePointOptions,
                get: a.basePoint.get, set: a.basePoint.set
            ),
            .color(
                id: "FontColor", displayName: "文字色", group: group,
                get: a.fontColor.get, set: a.fontColor.set
            ),
            .enumeration(
                id: "Style", displayName: "装飾", group: group,
                options: textStyleOptions,
                get: a.style.get, set: a.style.set
            ),
            .color(
                id: "StyleColor", displayName: "装飾色", group: group,
                get: a.styleColor.get, set: a.styleColor.set
            ),
            .boolean(
                id: "Bold", displayName: "太字", group: group,
                get: a.bold.get, set: a.bold.set
            ),
            .boolean(
                id: "Italic", displayName: "イタリック", group: group,
                get: a.italic.get, set: a.italic.set
            ),
            .boolean(
                id: "Underline", displayName: "下線", group: group,
                get: a.underline.get, set: a.underline.set
            ),
            .boolean(
                id: "Strikethrough", displayName: "打ち消し線", group: group,
                get: a.strikethrough.get, set: a.strikethrough.set
            ),
            .boolean(
                id: "IsTrimEndSpace", displayName: "行末スペース削除", group: group,
                get: a.isTrimEndSpace.get, set: a.isTrimEndSpace.set
            ),
            .boolean(
                id: "IsDevidedPerCharacter", displayName: "文字ごとに分割", group: group,
                get: a.isDevidedPerCharacter.get, set: a.isDevidedPerCharacter.set
            ),
            .number(
                id: "DisplayInterval", displayName: "表示間隔", group: group,
                get: a.displayInterval.get, set: a.displayInterval.set
            ),
            .enumeration(
                id: "DisplayDirection", displayName: "DisplayDirection", group: group,
                options: typewriterDirectionOptions,
                get: a.displayDirection.get, set: a.displayDirection.set
            ),
            .number(
                id: "HideInterval", displayName: "HideInterval", group: group,
                get: a.hideInterval.get, set: a.hideInterval.set
            ),
            .enumeration(
                id: "HideDirection", displayName: "HideDirection", group: group,
                options: typewriterDirectionOptions,
                get: a.hideDirection.get, set: a.hideDirection.set
            ),
        ]
    }

    // MARK: - 列挙の選択肢（表示名は本家 `Texts` リソースのメンバ名）

    private static func options<E: HonkeEnum>(
        _ pairs: [(E, String)]
    ) -> [PropertyEnumOption] {
        pairs.map { PropertyEnumOption(value: $0.honkeName, displayName: $1) }
    }

    private static let blendOptions = options([
        (.normal, "通常"), (.add, "加算"), (.subtract, "減算"), (.multiply, "乗算"),
        (.screen, "スクリーン"), (.overlay, "オーバーレイ"), (.lighter, "比較（明）"),
        (.darker, "比較（暗）"), (.luminosity, "輝度"), (.color, "カラー"),
        (.linearBurn, "焼き込み（リニア）"), (.linearLight, "リニアライト"),
        (.difference, "差分"), (.colorBurn, "焼き込みカラー"), (.darkerColor, "カラー比較（暗）"),
        (.colorDodge, "覆い焼きカラー"), (.linearDodge, "覆い焼き（リニア） - 加算"),
        (.lighterColor, "カラー比較（明）"), (.softLight, "ソフトライト"),
        (.hardLight, "ハードライト"), (.vividLight, "ビビッドライト"),
        (.pinLight, "ピンライト"), (.hardMix, "ハードミックス"), (.exclusion, "除外"),
        (.hue, "色相"), (.saturation, "彩度"), (.dissolve, "ディザ合成"),
        (.division, "除算"), (.destinationOver, "背景"), (.destinationOut, "削除"),
        (.sourceAtop, "背景でクリッピング"), (.xor, "重ならない部分のみ"),
        (.maskInvert, "色反転マスク"),
    ] as [(Blend, String)])

    private static let wordWrapOptions = options([
        (.noWrap, "折り返さない"), (.wholeWord, "単語単位で折り返す"),
        (.character, "文字単位で折り返す"),
    ] as [(WordWrap, String)])

    private static let textStyleOptions = options([
        (.normal, "なし"), (.shadow, "影"), (.shadowLight, "影（薄）"),
        (.border, "丸縁取り"), (.borderLight, "丸縁取り（薄）"),
        (.sharpBorder, "角縁取り"), (.sharpBorderLight, "角縁取り（薄）"),
    ] as [(TextStyle, String)])

    private static let basePointOptions = options([
        (.leftTop, "左揃え　[上]"), (.centerTop, "中央揃え[上]"), (.rightTop, "右揃え　[上]"),
        (.leftCenter, "左揃え　[中]"), (.centerCenter, "中央揃え[中]"), (.rightCenter, "右揃え　[中]"),
        (.leftBottom, "左揃え　[下]"), (.centerBottom, "中央揃え[下]"), (.rightBottom, "右揃え　[下]"),
        (.vTopRight, "縦書 上揃え　[右]"), (.vCenterRight, "縦書 中央揃え[右]"),
        (.vBottomRight, "縦書 下揃え　[右]"), (.vTopCenter, "縦書 上揃え　[中]"),
        (.vCenterCenter, "縦書 中央揃え[中]"), (.vBottomCenter, "縦書 下揃え　[中]"),
        (.vTopLeft, "縦書 上揃え　[左]"), (.vCenterLeft, "縦書 中央揃え[左]"),
        (.vBottomLeft, "縦書 下揃え　[左]"),
    ] as [(BasePoint, String)])

    private static let jimakuVisibilityOptions = options([
        (.useCharacterSetting, "キャラクターの設定に従う"), (.visible, "表示"),
        (.hidden, "非表示"), (.custom, "個別に設定する"),
    ] as [(JimakuVisibility, String)])

    /// 本家リソースにメンバ名が無いため、表示名はメンバ名そのまま。
    private static let typewriterDirectionOptions = options([
        (.fromFirst, "FromFirst"), (.fromLast, "FromLast"), (.random, "Random"),
    ] as [(TypewriterAnimationDirection, String)])
}
