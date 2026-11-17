import Foundation

/// 映像エフェクトの `$type` 名 → 定義型の対応表（レジストリ）。
///
/// .ymmp 読み込み時に既知の本体エフェクトを型付きで復元し、未知の
/// エフェクト（コミュニティ・プラグイン）は nil を返して従来どおり
/// `PreservedObject` の生保持に委ねる。GPU 処理系の本体エフェクトも
/// 定義層は型付きで復元するが、処理器は次段の実装までの暫定の素通し
/// （`GPUEffectPassthroughProcessor`）である。読み込み時は本家同様に
/// `RenamedTypeResolver` の型移行を先に適用する（移行先がコミュニティ
/// 名前空間になる 11 件は本体ではないため、移行の結果として未知になる）。
public enum VideoEffectRegistry {
    /// 登録済みの $type 名かどうか（型移行の適用後で判定する）。
    public static func isKnown(typeName: String) -> Bool {
        makeDefinition(typeName: RenamedTypeResolver.resolveTypeName(typeName)) != nil
    }

    /// 生保持オブジェクトを型付き定義へ復元する。未知の型・オブジェクト
    /// でない値・$type の無い値は nil（呼び出し側は生保持を維持する）。
    public static func decode(_ preserved: PreservedObject) -> VideoEffectDefinitionBase? {
        let migrated = preserved.applyingTypeMigration()
        guard let typeName = migrated.typeName,
              let definition = makeDefinition(typeName: typeName),
              case .object(let fields) = migrated.value
        else {
            return nil
        }
        definition.decodeFields(fields)
        return definition
    }

    /// $type 名から空の定義（既定値）を生成する。型移行を適用したうえで
    /// 判定し、未登録なら nil。エフェクト追加 UI が新規エフェクトの
    /// 初期値を得るための公開口（本家 VideoEffectFactory の生成相当）。
    public static func makeEmptyDefinition(typeName: String) -> VideoEffectDefinitionBase? {
        makeDefinition(typeName: RenamedTypeResolver.resolveTypeName(typeName))
    }

    /// $type 名から空の定義を生成する。未登録なら nil。
    private static func makeDefinition(typeName: String) -> VideoEffectDefinitionBase? {
        switch typeName {
        case ZoomEffectDefinition.typeName: return ZoomEffectDefinition()
        case OpacityEffectDefinition.typeName: return OpacityEffectDefinition()
        case DrawPositionEffectDefinition.typeName: return DrawPositionEffectDefinition()
        case InOutFadeEffectDefinition.typeName: return InOutFadeEffectDefinition()
        case InOutMoveEffectDefinition.typeName: return InOutMoveEffectDefinition()
        case InOutZoomEffectDefinition.typeName: return InOutZoomEffectDefinition()
        case InOutMoveFromOutsideFrameEffectDefinition.typeName:
            return InOutMoveFromOutsideFrameEffectDefinition()
        case RandomMoveEffectDefinition.typeName: return RandomMoveEffectDefinition()
        case RandomOpacityEffectDefinition.typeName: return RandomOpacityEffectDefinition()
        case RandomZoomEffectDefinition.typeName: return RandomZoomEffectDefinition()
        case RepeatMoveEffectDefinition.typeName: return RepeatMoveEffectDefinition()
        case RepeatOpacityEffectDefinition.typeName: return RepeatOpacityEffectDefinition()
        case RepeatZoomEffectDefinition.typeName: return RepeatZoomEffectDefinition()
        case ShowOnlyPreviewEffectDefinition.typeName: return ShowOnlyPreviewEffectDefinition()
        case BillboardEffectDefinition.typeName: return BillboardEffectDefinition()
        case CameraFovEffectDefinition.typeName: return CameraFovEffectDefinition()
        case CameraPositionEffectDefinition.typeName: return CameraPositionEffectDefinition()
        case CameraLookAtEffectDefinition.typeName: return CameraLookAtEffectDefinition()
        case CameraWraparoundEffectDefinition.typeName: return CameraWraparoundEffectDefinition()
        case PolarDrawPositionEffectDefinition.typeName: return PolarDrawPositionEffectDefinition()
        case XYToPolarTransformEffectDefinition.typeName: return XYToPolarTransformEffectDefinition()
        case MotionTrackingEffectDefinition.typeName: return MotionTrackingEffectDefinition()
        // GPU 処理系（定義層のみ。処理器は暫定の素通し）
        case ArcBendEffectDefinition.typeName: return ArcBendEffectDefinition()
        case AutomaticZoomEffectDefinition.typeName: return AutomaticZoomEffectDefinition()
        case CenterPointEffectDefinition.typeName: return CenterPointEffectDefinition()
        case CopyAndReverseEffectDefinition.typeName: return CopyAndReverseEffectDefinition()
        case CropByAngleEffectDefinition.typeName: return CropByAngleEffectDefinition()
        case CropEffectDefinition.typeName: return CropEffectDefinition()
        case MarginEffectDefinition.typeName: return MarginEffectDefinition()
        case PolarTransformEffectDefinition.typeName: return PolarTransformEffectDefinition()
        case RotateEffectDefinition.typeName: return RotateEffectDefinition()
        case RoundCornerEffectDefinition.typeName: return RoundCornerEffectDefinition()
        case SkewEffectDefinition.typeName: return SkewEffectDefinition()
        case TilingEffectDefinition.typeName: return TilingEffectDefinition()
        case CircularDuplicatorEffectDefinition.typeName: return CircularDuplicatorEffectDefinition()
        case RandomDuplicatorEffectDefinition.typeName: return RandomDuplicatorEffectDefinition()
        case BorderBlurEffectDefinition.typeName: return BorderBlurEffectDefinition()
        case DirectionalBlurEffectDefinition.typeName: return DirectionalBlurEffectDefinition()
        case GaussianBlurEffectDefinition.typeName: return GaussianBlurEffectDefinition()
        case RadialBlurEffectDefinition.typeName: return RadialBlurEffectDefinition()
        case SharpenEffectDefinition.typeName: return SharpenEffectDefinition()
        case MosaicEffectDefinition.typeName: return MosaicEffectDefinition()
        case HalfToneBorderBlurEffectDefinition.typeName: return HalfToneBorderBlurEffectDefinition()
        case HalfToneEffectDefinition.typeName: return HalfToneEffectDefinition()
        case HalfToneOutlineEffectDefinition.typeName: return HalfToneOutlineEffectDefinition()
        case HalfToneShadowEffectDefinition.typeName: return HalfToneShadowEffectDefinition()
        case InnerHalfToneShadowEffectDefinition.typeName: return InnerHalfToneShadowEffectDefinition()
        case RadialLightEffectDefinition.typeName: return RadialLightEffectDefinition()
        case ChromaticAberrationEffectDefinition.typeName: return ChromaticAberrationEffectDefinition()
        case ExposureEffectDefinition.typeName: return ExposureEffectDefinition()
        case GammaCorrectionEffectDefinition.typeName: return GammaCorrectionEffectDefinition()
        case HightlightsAndShadowsEffectDefinition.typeName:
            return HightlightsAndShadowsEffectDefinition()
        case InvertEffectDefinition.typeName: return InvertEffectDefinition()
        case LinearTransferEffectDefinition.typeName: return LinearTransferEffectDefinition()
        case MonocolorizationEffectDefinition.typeName: return MonocolorizationEffectDefinition()
        case PosterizeEffectDefinition.typeName: return PosterizeEffectDefinition()
        case SepiaEffectDefinition.typeName: return SepiaEffectDefinition()
        case TintEffectDefinition.typeName: return TintEffectDefinition()
        case NoiseColorShiftEffectDefinition.typeName: return NoiseColorShiftEffectDefinition()
        case OutlineEffectDefinition.typeName: return OutlineEffectDefinition()
        case ShadowEffectDefinition.typeName: return ShadowEffectDefinition()
        case InnerShadowEffectDefinition.typeName: return InnerShadowEffectDefinition()
        case FillBackgroundEffectDefinition.typeName: return FillBackgroundEffectDefinition()
        case FillForegroundEffectDefinition.typeName: return FillForegroundEffectDefinition()
        case FrameLineEffectDefinition.typeName: return FrameLineEffectDefinition()
        case GradientEffectDefinition.typeName: return GradientEffectDefinition()
        case TextureEffectDefinition.typeName: return TextureEffectDefinition()
        case BackgroundImageEffectDefinition.typeName: return BackgroundImageEffectDefinition()
        case CrashEffectDefinition.typeName: return CrashEffectDefinition()
        case DisplacementMapEffectDefinition.typeName: return DisplacementMapEffectDefinition()
        case MeshDeformationEffectDefinition.typeName: return MeshDeformationEffectDefinition()
        case NoiseDisplacementMapEffectDefinition.typeName:
            return NoiseDisplacementMapEffectDefinition()
        case NoiseEffectDefinition.typeName: return NoiseEffectDefinition()
        case MorphologyEffectDefinition.typeName: return MorphologyEffectDefinition()
        case DrawLazyEffectEffectDefinition.typeName: return DrawLazyEffectEffectDefinition()
        case JumpEffectDefinition.typeName: return JumpEffectDefinition()
        case ChromaKeyEffectDefinition.typeName: return ChromaKeyEffectDefinition()
        case ChromaKeyEffect2Definition.typeName: return ChromaKeyEffect2Definition()
        case MaskEffectDefinition.typeName: return MaskEffectDefinition()
        case InOutBorderBlurEffectDefinition.typeName: return InOutBorderBlurEffectDefinition()
        case InOutGaussianBlurEffectDefinition.typeName: return InOutGaussianBlurEffectDefinition()
        case InOutMosaicEffectDefinition.typeName: return InOutMosaicEffectDefinition()
        case InOutMoveFromOutsideImageEffectDefinition.typeName:
            return InOutMoveFromOutsideImageEffectDefinition()
        case InOutGetUpEffectDefinition.typeName: return InOutGetUpEffectDefinition()
        case InOutRotateEffectDefinition.typeName: return InOutRotateEffectDefinition()
        case InOutSkewEffectDefinition.typeName: return InOutSkewEffectDefinition()
        case InOutCrashEffectDefinition.typeName: return InOutCrashEffectDefinition()
        case InOutJumpEffectDefinition.typeName: return InOutJumpEffectDefinition()
        case InOutTransitionEffectDefinition.typeName: return InOutTransitionEffectDefinition()
        case RandomRotateEffectDefinition.typeName: return RandomRotateEffectDefinition()
        case RandomSkewEffectDefinition.typeName: return RandomSkewEffectDefinition()
        case RepeatRotateEffectDefinition.typeName: return RepeatRotateEffectDefinition()
        case RepeatSkewEffectDefinition.typeName: return RepeatSkewEffectDefinition()
        case HlslPixelShaderCodeEffectDefinition.typeName:
            return HlslPixelShaderCodeEffectDefinition()
        case HlslPixelShaderFileEffectDefinition.typeName:
            return HlslPixelShaderFileEffectDefinition()
        default: return nil
        }
    }

    /// 型付き定義を生保持オブジェクトの形へ戻す。
    public static func encode(_ definition: VideoEffectDefinitionBase) -> PreservedObject {
        PreservedObject(definition.encode())
    }

    /// 型付き定義を生保持オブジェクトの形へ戻す（編集の書き戻し用）。
    ///
    /// 型付きコーデックは入れ子オブジェクト内部の未知キーを保持しない
    /// （例: `Animation` の保存形式は既知4項目だけで再構成される）ため、
    /// `encode(_:)` の結果をそのまま保持列へ戻すと、編集したエフェクトの
    /// 内部にあった未知キーが保存時に消える（UI29-01）。ここでは元の
    /// 生保持を土台に型付きエンコードを重ね、未知キーを原文から回収する。
    ///
    /// 重ね方の規則:
    /// - トップレベルは型付きエンコードの並びとキーが正。未知キーは
    ///   定義の `additionalFields` 経由で既に型付き側へ含まれており、
    ///   定義が消費したキー（空にした `Remark`、旧キーからの移行など）は
    ///   定義側の判断どおり出す・出さないが決まる。
    /// - それより内側は元の並びを土台に再帰マージし、元だけにあるキー
    ///   （＝型付きコーデックが読み落とした未知キー）を全階層で保持する。
    /// - 配列とスカラは型付き側で置換する（配列要素の内部はマージしない）。
    ///
    /// 前提: `definition` は `original` から `decode` で開かれたもの。
    /// 元の `$type`（型移行の適用後）が定義の型と異なる場合は重ねず、
    /// 通常の `encode(_:)` の結果を返す。
    public static func encode(
        _ definition: VideoEffectDefinitionBase,
        preservingUnknownFieldsOf original: PreservedObject
    ) -> PreservedObject {
        let encoded = encode(definition)
        let migrated = original.applyingTypeMigration()
        guard migrated.typeName == type(of: definition).typeName else {
            return encoded
        }
        return PreservedObject(
            overlayTypedEncoding(encoded.value, onto: migrated.value)
        )
    }

    /// トップレベルの重ね合わせ。型付きエンコードのフィールドを正とし、
    /// 両側にオブジェクトとして存在するフィールドだけ入れ子マージで
    /// 元の未知キーを回収する。
    private static func overlayTypedEncoding(_ overlay: JSONValue, onto base: JSONValue) -> JSONValue {
        guard case .object(let overlayFields) = overlay,
              case .object(let baseFields) = base else {
            return overlay
        }
        return .object(overlayFields.map { field in
            guard let baseValue = baseFields.first(where: { $0.key == field.key })?.value,
                  case .object = field.value, case .object = baseValue else {
                return field
            }
            return (key: field.key, value: mergeNestedFields(base: baseValue, overlay: field.value))
        })
    }

    /// 入れ子オブジェクトの再帰マージ。元の並びを土台にし、共有キーは
    /// （両側ともオブジェクトなら再帰、それ以外は型付き側で）置換、
    /// 元だけのキーは保持、型付き側だけのキーは末尾へ追加する。
    private static func mergeNestedFields(base: JSONValue, overlay: JSONValue) -> JSONValue {
        guard case .object(let baseFields) = base,
              case .object(let overlayFields) = overlay else {
            return overlay
        }
        var result: [(key: String, value: JSONValue)] = baseFields.map { field in
            guard let overlayValue = overlayFields.first(where: { $0.key == field.key })?.value else {
                return field
            }
            return (key: field.key, value: mergeNestedFields(base: field.value, overlay: overlayValue))
        }
        result += overlayFields.filter { field in
            !baseFields.contains(where: { $0.key == field.key })
        }
        return .object(result)
    }
}

/// 型付き定義を MAC-0010 のエフェクト連鎖へ供給する `EffectPairProvider`。
///
/// モデル層のエフェクト列（`[PreservedObject]`）をレジストリで型付けし、
/// 所有アイテムごとに定義インスタンスをキャッシュする。連鎖の再利用判定
/// は定義の同一性で行われるため、供給元が毎回新しい定義を作ると処理器が
/// 毎フレーム差し替わってしまう。キャッシュは生保持列の内容が変わった
/// ときだけ作り直す（再読み込み等）。未知のエフェクトは連鎖へ出さない
/// （生保持はモデル側に残り、保存では失われない）。
///
/// 保持形式は生保持のままとする（MAC-0019 の設計判断）: 型付き定義は
/// 消費側で作る一時的なビューであり、保存経路は生保持をそのまま書き出す。
/// 型付き encode で再直列化すると、キー順の正規化や数値の再直列化で
/// 実ファイルの初回保存バイト列が変わりうるため、往復の固定点を保つ側を
/// 採る。定義の編集を保存へ反映する編集 UI の段では、この供給元が保持
/// する定義と生保持列の同期を別途設計する。
///
/// キーフレーム文脈（MAC-0019）: 本家ではアイテムの `SetKeyFrames` が
/// `GetAnimatables()` 経由でエフェクト定義の `Animation` へも伝播する。
/// 定義は消費側で遅延生成されるため、生成時と、所有アイテムの
/// `KeyFrames` が変わったときに `setKeyFrames(_:)` で伝播させる。
/// GroupedDrawing はグループ自身の Animation を直接読む処理器であり、
/// そちらは GroupItem の `forEachAnimation` で既に文脈が届いているため
/// 追加の伝播は要らない。
///
/// グループの親エフェクトは本家どおり「グループ自身の VideoEffects ＋
/// 合成された GroupedDrawingEffect」の順で供給する。顔エフェクトは
/// 顔アイテム自身（TachieFaceItem / VoiceItem）の TachieFaceEffects を
/// その顔アイテムを時間基準として供給する。
public final class TypedEffectPairProvider: EffectPairProvider {
    private struct CachedDefinitions {
        var source: [PreservedObject]
        var definitions: [VideoEffectDefinitionBase]
        /// 定義群へ最後に伝播した所有アイテムのキーフレーム文脈。
        var appliedKeyFrames: KeyFrames?
    }

    private var cache: [ObjectIdentifier: CachedDefinitions] = [:]
    private var groupedDrawingCache: [ObjectIdentifier: GroupedDrawingEffectDefinition] = [:]
    /// トランジション前後エフェクト用のキャッシュ。前後で別エントリに
    /// しないと、所有アイテムが同じため通常のキャッシュと衝突する。
    private var transitionCache: [ObjectIdentifier: [Bool: CachedDefinitions]] = [:]

    public init() {}

    public func ownEffectPairs(for item: BaseItem & VideoItemProperties) -> [EffectPair] {
        definitions(owner: item, source: ownEffectSource(for: item)).map {
            EffectPair(timeSource: item, definition: $0)
        }
    }

    /// アイテム自身のエフェクトの供給元になる保持列を返す。
    ///
    /// VoiceItem では本家の IVideoItem 読み取り経路に合わせ、字幕エフェクト
    /// は保持列そのものではなく JimakuVisibility による解決済み列
    /// （MAC-0014 の `VoiceItem.resolvedVideoEffects`。Custom のときだけ
    /// 自身、それ以外はキャラクター側）から復元する。ただしキャラクター
    /// が解決できていない場合はアイテム自身の保持列へフォールバックする。
    /// 本家ではキャラクターの無い VoiceItem の字幕は表示ゲート
    /// （JimakuSource の判定、MAC-0014 の `jimakuIsVisible`）で字幕自体が
    /// 出ないため、この場合にどちらの列を供給しても描画結果は変わらない。
    /// VoiceItem 以外では実効値と保持列が一致する（`effectiveVideoEffects`
    /// の定義どおり）ため、従来どおり保持列をそのまま使う。
    private func ownEffectSource(for item: BaseItem & VideoItemProperties) -> [PreservedObject] {
        if let voice = item as? VoiceItem, voice.character != nil {
            return voice.resolvedVideoEffects
        }
        return item.videoEffects
    }

    public func groupEffectPairs(
        for group: GroupItem, childIndex: Int, childCount: Int
    ) -> [EffectPair] {
        var pairs = definitions(owner: group, source: group.videoEffects).map {
            EffectPair(
                timeSource: group, definition: $0,
                groupIndex: childIndex, groupCount: childCount
            )
        }
        pairs.append(EffectPair(
            timeSource: group,
            definition: groupedDrawingDefinition(for: group),
            groupIndex: childIndex, groupCount: childCount
        ))
        return pairs
    }

    public func faceEffectPairs(for faceItem: BaseItem) -> [EffectPair] {
        let source: [PreservedObject]
        if let face = faceItem as? TachieFaceItem {
            source = face.tachieFaceEffects
        } else if let voice = faceItem as? VoiceItem {
            source = voice.tachieFaceEffects
        } else {
            return []
        }
        return definitions(owner: faceItem, source: source).map {
            EffectPair(timeSource: faceItem, definition: $0)
        }
    }

    /// キャッシュを全て破棄する（プロジェクト再読み込み時など）。
    public func invalidateCache() {
        cache = [:]
        groupedDrawingCache = [:]
        transitionCache = [:]
    }

    private func definitions(
        owner: BaseItem, source: [PreservedObject]
    ) -> [VideoEffectDefinitionBase] {
        let key = ObjectIdentifier(owner)
        var entry: CachedDefinitions
        if let cached = cache[key], cached.source == source {
            entry = cached
        } else {
            entry = CachedDefinitions(
                source: source,
                definitions: source.compactMap { VideoEffectRegistry.decode($0) },
                appliedKeyFrames: nil
            )
        }
        // キーフレーム文脈の伝播。生成直後（appliedKeyFrames が nil）と、
        // 所有アイテムの KeyFrames が変わったときだけ再伝播する。
        if entry.appliedKeyFrames != owner.keyFrames {
            for definition in entry.definitions {
                definition.setKeyFrames(owner.keyFrames)
            }
            entry.appliedKeyFrames = owner.keyFrames
        }
        cache[key] = entry
        return entry.definitions
    }

    /// トランジション前後の全体エフェクト（本家 TransitionItem の
    /// BeforeVideoEffects / AfterVideoEffects）。時間基準はトランジション
    /// アイテム自身。定義の同一性を保つため前後別々にキャッシュする
    /// （MAC-0036）。
    public func transitionEffectPairs(
        for item: TransitionItem, isBefore: Bool
    ) -> [EffectPair] {
        let source = isBefore ? item.beforeVideoEffects : item.afterVideoEffects
        let key = ObjectIdentifier(item)
        var entry: CachedDefinitions
        if let cached = transitionCache[key]?[isBefore], cached.source == source {
            entry = cached
        } else {
            entry = CachedDefinitions(
                source: source,
                definitions: source.compactMap { VideoEffectRegistry.decode($0) },
                appliedKeyFrames: nil
            )
        }
        if entry.appliedKeyFrames != item.keyFrames {
            for definition in entry.definitions {
                definition.setKeyFrames(item.keyFrames)
            }
            entry.appliedKeyFrames = item.keyFrames
        }
        transitionCache[key, default: [:]][isBefore] = entry
        return entry.definitions.map {
            EffectPair(timeSource: item, definition: $0)
        }
    }

    private func groupedDrawingDefinition(for group: GroupItem) -> GroupedDrawingEffectDefinition {
        let key = ObjectIdentifier(group)
        if let cached = groupedDrawingCache[key] {
            return cached
        }
        let definition = GroupedDrawingEffectDefinition(group: group)
        groupedDrawingCache[key] = definition
        return definition
    }
}
