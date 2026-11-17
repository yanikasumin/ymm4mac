import Foundation
import YMM4Core

/// アイテムの生成（追加メニュー／ツールバー／コンテキストメニュー／
/// ドロップインで共用）。
enum ItemFactory {
    /// アイテム種別から空のアイテムを生成する。
    static func makeItem(kind: AddItemKind) -> BaseItem {
        switch kind {
        case .voice: return VoiceItem()
        case .text: return TextItem()
        case .video: return VideoItem()
        case .audio: return AudioItem()
        case .image: return ImageItem()
        case .shape: return ShapeItem()
        case .tachie: return TachieItem()
        case .face: return TachieFaceItem()
        case .effect: return EffectItem()
        case .transition: return TransitionItem()
        case .scene: return SceneItem()
        case .frameBuffer: return FrameBufferItem()
        case .group: return GroupItem()
        }
    }

    /// 新規アイテムの仮の長さ（1秒分）。本家は素材の長さや生成音声から
    /// 長さを決めるが、デコード／音声供給が未接続の範囲では仮置きする
    /// （台帳に記録。接続時に実長へ差し替える）。
    static func placeholderLength(fps: Int) -> Int {
        max(fps, 1)
    }
}
