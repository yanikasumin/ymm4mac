import Foundation

/// VoiceItem の字幕解決。本家 `VoiceItem` の IVideoItem 明示的実装と
/// `JimakuSource.UpdateResource` の分岐に対応する（MAC-0014 で新設）。
///
/// 本家での解決時点は2箇所に分かれる:
/// - **外観と表示可否**: `JimakuSource.UpdateResource` が Update のたびに
///   判定する。表示ゲートは「Hidden、または Character が null、または
///   UseCharacterSetting かつ Character.IsJimakuVisible が false」のいずれか
///   で字幕自体が出ない。外観（フォント・色・スタイル等）は
///   JimakuVisibility が Custom のときだけアイテム自身の値、それ以外は
///   Character の値を参照する。
/// - **変形（X/Y/Z・不透明度・ズーム・回転・フェード・反転・合成方法・
///   映像エフェクト）**: `VoiceItem` の IVideoItem 明示的実装の getter が
///   読まれるたびに解決する。規則は全プロパティ共通で、Custom のとき
///   アイテム自身の Jimaku* 保持値、それ以外のとき Character の値
///   （Character が無ければ自身の保持値）。映像エフェクトだけは4分岐で、
///   Hidden では常に空、UseCharacterSetting ではキャラクターの字幕が
///   非表示なら空になる。
///
/// Swift 側のモデルでは保持プロパティ（`x` 等）と VideoItemProperties の
/// 適合が同居しているため、本家の明示的実装に相当する解決済み読み取りを
/// ここに分離し、描画パイプラインは `effective*` 経由で読む。保持値その
/// もの（.ymmp の読み書き対象）は従来どおりアイテム自身の値を指す。
extension VoiceItem {
    /// 字幕が表示されるか。本家 JimakuSource.UpdateResource 冒頭のゲート
    /// そのまま（Hidden / Character なし / UseCharacterSetting かつ
    /// キャラクター側で非表示、のいずれかで false）。
    public var jimakuIsVisible: Bool {
        if jimakuVisibility == .hidden { return false }
        guard let character else { return false }
        if jimakuVisibility == .useCharacterSetting && !character.isJimakuVisible {
            return false
        }
        return true
    }

    /// 解決済みの字幕外観。Custom のときアイテム自身、それ以外のとき
    /// Character の外観プロパティ群を TextAppearance として組み立てる
    /// （Character が無い場合は自身の外観を返す。表示ゲート側で字幕自体が
    /// 出ないため描画には使われない）。
    public var jimakuAppearance: TextAppearance {
        if jimakuVisibility == .custom || character == nil {
            return appearance
        }
        guard let character else { return appearance }
        var resolved = TextAppearance()
        resolved.font = character.font
        resolved.fontSize = character.fontSize
        resolved.lineHeight2 = character.lineHeight2
        resolved.letterSpacing2 = character.letterSpacing2
        resolved.wordWrap = character.wordWrap
        resolved.maxWidth = character.maxWidth
        resolved.basePoint = character.basePoint
        resolved.fontColor = character.fontColor
        resolved.style = character.style
        resolved.styleColor = character.styleColor
        resolved.bold = character.bold
        resolved.italic = character.italic
        resolved.underline = character.underline
        resolved.strikethrough = character.strikethrough
        resolved.isTrimEndSpace = character.isTrimEndSpace
        resolved.isDevidedPerCharacter = character.isDevidedPerCharacter
        resolved.displayInterval = character.displayInterval
        resolved.displayDirection = character.displayDirection
        resolved.hideInterval = character.hideInterval
        resolved.hideDirection = character.hideDirection
        return resolved
    }

    /// 字幕がアイテム自身の外観・変形を使うモードか（Custom）。
    public var jimakuUsesCustomSettings: Bool {
        jimakuVisibility == .custom
    }

    // MARK: - 解決済みの変形（本家 IVideoItem 明示的実装の getter 群）

    public var resolvedX: Animation {
        jimakuUsesCustomSettings ? x : (character?.x ?? x)
    }

    public var resolvedY: Animation {
        jimakuUsesCustomSettings ? y : (character?.y ?? y)
    }

    public var resolvedZ: Animation {
        jimakuUsesCustomSettings ? z : (character?.z ?? z)
    }

    public var resolvedOpacity: Animation {
        jimakuUsesCustomSettings ? opacity : (character?.opacity ?? opacity)
    }

    public var resolvedZoom: Animation {
        jimakuUsesCustomSettings ? zoom : (character?.zoom ?? zoom)
    }

    public var resolvedRotation: Animation {
        jimakuUsesCustomSettings ? rotation : (character?.rotation ?? rotation)
    }

    public var resolvedFadeIn: Double {
        jimakuUsesCustomSettings ? fadeIn : (character?.jimakuFadeIn ?? fadeIn)
    }

    public var resolvedFadeOut: Double {
        jimakuUsesCustomSettings ? fadeOut : (character?.jimakuFadeOut ?? fadeOut)
    }

    public var resolvedBlend: Blend {
        jimakuUsesCustomSettings ? blend : (character?.blend ?? blend)
    }

    public var resolvedIsInverted: Bool {
        jimakuUsesCustomSettings ? isInverted : (character?.isInverted ?? isInverted)
    }

    public var resolvedIsClippingWithObjectAbove: Bool {
        jimakuUsesCustomSettings
            ? isClippingWithObjectAbove
            : (character?.isClippingWithObjectAbove ?? isClippingWithObjectAbove)
    }

    public var resolvedIsAlwaysOnTop: Bool {
        jimakuUsesCustomSettings
            ? isAlwaysOnTop
            : (character?.isAlwaysOnTop ?? isAlwaysOnTop)
    }

    public var resolvedIsZOrderEnabled: Bool {
        jimakuUsesCustomSettings
            ? isZOrderEnabled
            : (character?.isZOrderEnabled ?? isZOrderEnabled)
    }

    /// 解決済みの字幕映像エフェクト。本家だけ4分岐:
    /// Custom → 自身、Visible → Character のもの（無ければ空）、
    /// Hidden → 空、UseCharacterSetting → Character の字幕が表示される
    /// ときだけ Character のもの。未知の保存名は本家では例外になる経路で、
    /// ここでは Visible と同じ扱いに倒す。
    public var resolvedVideoEffects: [PreservedObject] {
        switch jimakuVisibility {
        case .custom:
            return videoEffects
        case .visible, .unknown:
            return character?.jimakuVideoEffects ?? []
        case .hidden:
            return []
        case .useCharacterSetting:
            if let character, character.isJimakuVisible {
                return character.jimakuVideoEffects
            }
            return []
        }
    }
}

/// 描画パイプラインが読むべき解決済みの映像プロパティ。
///
/// 本家では合成側が IVideoItem 経由で読むため、VoiceItem では上記の
/// 解決が自動で効く。Swift では保持プロパティとプロトコル適合が同居する
/// ため、パイプライン側の読み取りはこの `effective*` 群に寄せる。
/// VoiceItem 以外のアイテムでは保持値をそのまま返す。
extension VideoItemProperties {
    public var effectiveX: Animation {
        (self as? VoiceItem)?.resolvedX ?? x
    }

    public var effectiveY: Animation {
        (self as? VoiceItem)?.resolvedY ?? y
    }

    public var effectiveZ: Animation {
        (self as? VoiceItem)?.resolvedZ ?? z
    }

    public var effectiveOpacity: Animation {
        (self as? VoiceItem)?.resolvedOpacity ?? opacity
    }

    public var effectiveZoom: Animation {
        (self as? VoiceItem)?.resolvedZoom ?? zoom
    }

    public var effectiveRotation: Animation {
        (self as? VoiceItem)?.resolvedRotation ?? rotation
    }

    public var effectiveFadeIn: Double {
        (self as? VoiceItem)?.resolvedFadeIn ?? fadeIn
    }

    public var effectiveFadeOut: Double {
        (self as? VoiceItem)?.resolvedFadeOut ?? fadeOut
    }

    public var effectiveBlend: Blend {
        (self as? VoiceItem)?.resolvedBlend ?? blend
    }

    public var effectiveIsInverted: Bool {
        (self as? VoiceItem)?.resolvedIsInverted ?? isInverted
    }

    public var effectiveIsClippingWithObjectAbove: Bool {
        (self as? VoiceItem)?.resolvedIsClippingWithObjectAbove ?? isClippingWithObjectAbove
    }

    public var effectiveIsAlwaysOnTop: Bool {
        (self as? VoiceItem)?.resolvedIsAlwaysOnTop ?? isAlwaysOnTop
    }

    public var effectiveIsZOrderEnabled: Bool {
        (self as? VoiceItem)?.resolvedIsZOrderEnabled ?? isZOrderEnabled
    }

    public var effectiveVideoEffects: [PreservedObject] {
        (self as? VoiceItem)?.resolvedVideoEffects ?? videoEffects
    }
}
