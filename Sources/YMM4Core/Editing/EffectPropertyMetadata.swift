import Foundation

/// 映像エフェクト定義のプロパティメタデータ（MAC-0029、FXMETA で全種別化）。
///
/// アイテム側と同じ仕組みで、エフェクト定義のパラメータを記述子化する。
/// 共通プロパティ（IsEnabled / Remark）は全定義に付き、具象定義ごとに
/// 固有パラメータの記述を追加する。拡大縮小・不透明度・描画位置は
/// 本ファイル、残りの具象定義はカテゴリ別ファイルのビルダー
/// （`specificDescriptors(for:)` 経由）に置く。
/// 表示名は本家の `Texts` リソース（`ZoomEffect*Name` 等）に根拠がある
/// ものはその文言を使い、無いもの（IsEnabled / Remark）はプロパティ名
/// そのままにする。
///
/// 記述子で表現できない複合プロパティ（ブラシ、ノイズ／モザイクの
/// パラメータオブジェクト、変形マップの Transform、グラデーションの
/// 色停止点列、メッシュ変形の点列、マスクの図形パラメータ、
/// モーショントラッキングのパス）は、本家でも入れ子の専用エディタで
/// 編集する対象であり、単一記述子の対象外として欠落を台帳に記録する。
public enum EffectPropertyMetadata {
    /// エフェクト定義の編集可能プロパティを宣言順に返す。
    public static func descriptors(for definition: VideoEffectDefinitionBase) -> [PropertyDescriptor] {
        var result: [PropertyDescriptor] = [
            .boolean(
                id: "IsEnabled", displayName: "IsEnabled", group: "共通",
                get: { definition.isEnabled }, set: { definition.isEnabled = $0 }
            ),
            .text(
                id: "Remark", displayName: "Remark", group: "共通",
                get: { definition.remark }, set: { definition.remark = $0 }
            ),
        ]
        switch definition {
        case let zoom as ZoomEffectDefinition:
            result += [
                .animation(
                    id: "Zoom", displayName: "全体", group: "拡大縮小",
                    get: { zoom.zoom }, set: { zoom.zoom = $0 }
                ),
                .animation(
                    id: "ZoomX", displayName: "横方向", group: "拡大縮小",
                    get: { zoom.zoomX }, set: { zoom.zoomX = $0 }
                ),
                .animation(
                    id: "ZoomY", displayName: "縦方向", group: "拡大縮小",
                    get: { zoom.zoomY }, set: { zoom.zoomY = $0 }
                ),
                .boolean(
                    id: "IsNearestNeighbor", displayName: "ドット絵", group: "拡大縮小",
                    get: { zoom.isNearestNeighbor }, set: { zoom.isNearestNeighbor = $0 }
                ),
            ]
        case let opacity as OpacityEffectDefinition:
            result += [
                .animation(
                    id: "Opacity", displayName: "不透明度", group: "不透明度",
                    get: { opacity.opacity }, set: { opacity.opacity = $0 }
                ),
                .boolean(
                    id: "IsAbsolute", displayName: "絶対値", group: "不透明度",
                    get: { opacity.isAbsolute }, set: { opacity.isAbsolute = $0 }
                ),
            ]
        case let position as DrawPositionEffectDefinition:
            result += [
                .animation(
                    id: "X", displayName: "X", group: "描画位置",
                    get: { position.x }, set: { position.x = $0 }
                ),
                .animation(
                    id: "Y", displayName: "Y", group: "描画位置",
                    get: { position.y }, set: { position.y = $0 }
                ),
                .animation(
                    id: "Z", displayName: "Z", group: "描画位置",
                    get: { position.z }, set: { position.z = $0 }
                ),
            ]
        default:
            break
        }
        result += specificDescriptors(for: definition)
        return result
    }
}

/// アイテムが保持する映像エフェクト列（生保持）と型付き定義の橋渡し。
///
/// モデル層の保持形式は生保持のまま（MAC-0019 の設計判断）であり、
/// 編集は「レジストリで型付き定義へ開く → 記述子で編集する →
/// `VideoEffectRegistry.encode` で保持列へ書き戻す」の往復で行う。
/// 書き戻しで保持列の内容が変わるため、消費側の供給元
/// （`TypedEffectPairProvider`）はキャッシュを作り直し、プレビュー
/// にも編集が反映される。未知の型（コミュニティ・プラグイン）は
/// 型付き編集の対象外として nil を返し、生保持はそのまま残る。
/// 書き戻しは元の生保持を土台に重ねる形で行い、型付きコーデックが
/// 読み落とす入れ子の未知キーも保存で失われない（UI29-01 / MAC-0032）。
public enum EffectPropertyEditing {
    /// アイテムが保持する映像エフェクト列。対象は `VisualItem` 系譜・
    /// `VoiceItem`・`TransitionItem`（いずれも保持列は字幕側／映像側の
    /// 自前分）。それ以外は nil。
    public static func effectList(for item: BaseItem) -> [PreservedObject]? {
        switch item {
        case let visual as VisualItem:
            return visual.videoEffects
        case let voice as VoiceItem:
            return voice.videoEffects
        case let transition as TransitionItem:
            return transition.videoEffects
        default:
            return nil
        }
    }

    /// 保持列の要素を型付き定義として開く。未知の型・範囲外は nil。
    public static func openDefinition(for item: BaseItem, at index: Int) -> VideoEffectDefinitionBase? {
        guard let list = effectList(for: item), list.indices.contains(index) else {
            return nil
        }
        return VideoEffectRegistry.decode(list[index])
    }

    /// 編集済みの型付き定義を保持列の同じ位置へ書き戻す。
    /// 元の要素を土台に重ねて書き戻すため、型付きで読み落とした
    /// 入れ子の未知キーも保持される。対象外のアイテム・範囲外は false。
    @discardableResult
    public static func writeBack(
        _ definition: VideoEffectDefinitionBase, for item: BaseItem, at index: Int
    ) -> Bool {
        switch item {
        case let visual as VisualItem:
            guard visual.videoEffects.indices.contains(index) else { return false }
            visual.videoEffects[index] = VideoEffectRegistry.encode(
                definition, preservingUnknownFieldsOf: visual.videoEffects[index]
            )
            return true
        case let voice as VoiceItem:
            guard voice.videoEffects.indices.contains(index) else { return false }
            voice.videoEffects[index] = VideoEffectRegistry.encode(
                definition, preservingUnknownFieldsOf: voice.videoEffects[index]
            )
            return true
        case let transition as TransitionItem:
            guard transition.videoEffects.indices.contains(index) else { return false }
            transition.videoEffects[index] = VideoEffectRegistry.encode(
                definition, preservingUnknownFieldsOf: transition.videoEffects[index]
            )
            return true
        default:
            return false
        }
    }
}
