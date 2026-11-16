import Foundation

/// TimelineSource の用途。本家 TimelineSourceUsage に対応する。
public enum TimelineSourceUsage: Sendable {
    case playing
    case paused
    case exporting
}

/// フレーム位置（フレーム番号＋FPS の組）。本家 FrameTime（値型）に対応する。
/// 既存の `FrameTime` は換算ユーティリティ（列挙型）のため、値を保持する
/// 型はこちらで分ける。時間換算は本家どおり tick 粒度で丸める。
public struct FramePosition: Equatable, Sendable {
    public var frame: Int
    public var fps: Int

    public init(frame: Int, fps: Int) {
        self.frame = frame
        self.fps = fps
    }

    /// 時間（秒）。本家 FrameTime.Time と同じ換算。
    public var time: TimeInterval {
        FrameTime.time(fromFrame: frame, fps: fps)
    }
}

/// 画面サイズ（ピクセル）。本家 System.Drawing.Size に対応する。
public struct PixelSize: Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// シーン情報への参照。本家 ISceneInfo に対応する。この層では識別子だけを
/// 契約とし、シーン解決（内部 TimelineSource の生成）は次段の責務とする。
public protocol SceneInfo: AnyObject {
    var sceneID: UUID { get }
}

/// タイムライン全体に対する更新の説明。本家 TimelineSourceDescription
/// （レコード）に対応する。
public struct TimelineSourceDescription {
    /// 画面サイズ（VideoInfo の幅×高さ）。
    public var screenSize: PixelSize
    /// タイムライン上の現在位置。
    public var timelinePosition: FramePosition
    /// タイムラインの長さ。
    public var timelineDuration: FramePosition
    /// フレームレート。
    public var fps: Int
    /// 用途。
    public var usage: TimelineSourceUsage
    /// 対象シーンの ID。
    public var sceneId: UUID
    /// 自シーン＋親シーンの情報列（シーン参照の解決用）。
    public var scenes: [any SceneInfo]

    public init(
        screenSize: PixelSize,
        timelinePosition: FramePosition,
        timelineDuration: FramePosition,
        fps: Int,
        usage: TimelineSourceUsage,
        sceneId: UUID,
        scenes: [any SceneInfo]
    ) {
        self.screenSize = screenSize
        self.timelinePosition = timelinePosition
        self.timelineDuration = timelineDuration
        self.fps = fps
        self.usage = usage
        self.sceneId = sceneId
        self.scenes = scenes
    }
}

/// 1アイテムに対する更新の説明。本家 TimelineItemSourceDescription
/// （TimelineSourceDescription のサブレコード）に対応する。本家は継承だが、
/// こちらは基底を保持する合成で表す。
public struct TimelineItemSourceDescription {
    /// タイムライン全体の説明。
    public var base: TimelineSourceDescription
    /// アイテム開始位置を 0 とするアイテム内位置。
    public var itemPosition: FramePosition
    /// アイテムの長さ。
    public var itemDuration: FramePosition
    /// アイテムのレイヤー。
    public var layer: Int
    /// 描画スケール（親のスケール×アイテムの Zoom 評価値）。既定 1。
    public var renderScale: Double

    // 基底の各値への素通し（本家では継承で見えるメンバ）。
    public var screenSize: PixelSize { base.screenSize }
    public var timelinePosition: FramePosition { base.timelinePosition }
    public var timelineDuration: FramePosition { base.timelineDuration }
    public var fps: Int { base.fps }
    public var usage: TimelineSourceUsage { base.usage }
    public var sceneId: UUID { base.sceneId }
    public var scenes: [any SceneInfo] { base.scenes }

    /// 本家のコンストラクタに対応する。基底がアイテム説明の場合は
    /// RenderScale を引き継ぐ（もう一方の初期化子を使う）。
    public init(_ base: TimelineSourceDescription, itemFrame: Int, itemLength: Int, layer: Int) {
        self.base = base
        self.itemPosition = FramePosition(frame: itemFrame, fps: base.fps)
        self.itemDuration = FramePosition(frame: itemLength, fps: base.fps)
        self.layer = layer
        self.renderScale = 1
    }

    /// 親のアイテム説明から作る場合。RenderScale は親から引き継ぐ
    /// （本家のコンストラクタの分岐どおり）。
    public init(_ parent: TimelineItemSourceDescription, itemFrame: Int, itemLength: Int, layer: Int) {
        self.base = parent.base
        self.itemPosition = FramePosition(frame: itemFrame, fps: parent.fps)
        self.itemDuration = FramePosition(frame: itemLength, fps: parent.fps)
        self.layer = layer
        self.renderScale = parent.renderScale
    }

    /// 本家 ComposeRenderScale。親スケール（アイテム説明でない／不正なら 1）
    /// ×アイテムスケール（不正なら 1）。積が有限でなく、または float の
    /// 最大値を超える場合は 1 を返す。
    public static func composeRenderScale(parentRenderScale: Double?, itemScale: Double) -> Double {
        let parent = parentRenderScale.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 1
        let item = itemScale.isFinite && itemScale > 0 ? itemScale : 1
        let product = parent * item
        if !product.isFinite || product > 3.4028234663852886E+38 {
            return 1
        }
        return product
    }
}

/// 1エフェクトに対する更新の説明。本家 EffectDescription（アイテム説明の
/// サブレコード）に対応する。エフェクト連鎖の実行自体は次段の責務だが、
/// DrawingEffectProcessor の Update 引数として契約に含める。
public struct EffectDescription {
    /// 元のアイテム説明。
    public var itemDescription: TimelineItemSourceDescription
    /// 入力時点の描画変換（連鎖の前段までの結果）。
    public var drawDescription: DrawDescription
    /// 連鎖内の入力位置。
    public var inputIndex: Int
    /// 連鎖の入力総数。
    public var inputCount: Int
    /// グループ内の子位置（グループエフェクト用。それ以外は 0）。
    public var groupIndex: Int
    /// グループの子総数（グループエフェクト用。それ以外は 0）。
    public var groupCount: Int

    public init(
        itemDescription: TimelineItemSourceDescription,
        drawDescription: DrawDescription,
        inputIndex: Int = 0,
        inputCount: Int = 1,
        groupIndex: Int = 0,
        groupCount: Int = 0
    ) {
        self.itemDescription = itemDescription
        self.drawDescription = drawDescription
        self.inputIndex = inputIndex
        self.inputCount = inputCount
        self.groupIndex = groupIndex
        self.groupCount = groupCount
    }
}
