import Foundation

/// 本家 IVideoItem の実装範囲に対応するかの判定。
///
/// 本家で IVideoItem を実装するのは VisualItem の系譜に加えて VoiceItem と
/// TransitionItem であり、TachieFaceItem は実装しない（IFaceItem のみ）。
/// MAC-0009 の ItemPicker が使う VideoItemCandidate（VisualItem +
/// TachieFaceItem）とは範囲が異なる。こちらは本家の実装範囲に合わせ、
/// 選定側との不整合は未解決事項として台帳に記録する。
func isVideoItemEquivalent(_ item: BaseItem) -> Bool {
    item is VisualItem || item is VoiceItem || item is TransitionItem
}

/// シーン（タイムライン＋識別子）。本家 ISceneInfo の具象に相当する。
/// シーン解決（SceneItem からの内部 TimelineSource 生成・入れ子上限）は
/// 次段の責務であり、ここでは保持と説明への受け渡しだけを行う。
public final class TimelineScene: SceneInfo {
    public let sceneID: UUID
    public var timeline: Timeline
    /// 自シーン＋親シーンの情報列（説明レコードへそのまま渡る）。
    public var scenes: [any SceneInfo]

    public init(sceneID: UUID = UUID(), timeline: Timeline) {
        self.sceneID = sceneID
        self.timeline = timeline
        self.scenes = []
        self.scenes = [self]
    }
}

/// 立ち絵 Source への顔・声の受け渡し。本家 TachieSource の ActiveVoice /
/// ActiveFaces に対応する。TimelineSource 相当が顔解決の結果をここへ書く。
public protocol TachieSource: Source {
    /// 現在の声（顔アイテム列のうち最初の VoiceItem。無ければ nil）。
    var activeVoice: VoiceItem? { get set }
    /// 現在の顔アイテム列（レイヤー降順）。
    var activeFaces: [any FaceItem] { get set }
}

/// グループ階層の解決。本家 TimelineGroupResolver に対応する。
///
/// 規則（本家実コードどおり）:
/// - 親候補は「非表示でなく、レイヤーが表示中」の GroupItem のみ。
/// - 直接の親: グループのレイヤー < アイテムのレイヤー <= グループの
///   レイヤー + GroupRange を満たし、IsGroupOnly のグループはグループ番号が
///   一致する（0 でない）アイテムにだけ適用される。
/// - 祖先は再帰的に集め、重複を除き、レイヤー降順に並べ、合成グループに
///   当たったところで打ち切る（合成グループ自身は含まない。合成グループの
///   効果は子へは流れず、子の描画は合成グループ内部で行われる）。
/// - 子の列挙: 映像アイテム（合成グループ自身は除く）のうち、その親列に
///   対象グループを含むもの。レイヤー昇順。
public struct TimelineGroupResolver {
    private let items: [BaseItem]
    private let visibleGroups: [GroupItem]

    public init(items: [BaseItem], isLayerVisible: (Int) -> Bool) {
        self.items = items
        self.visibleGroups = items
            .compactMap { $0 as? GroupItem }
            .filter { !$0.isHidden && isLayerVisible($0.layer) }
    }

    /// アイテムの親グループ列（近い順＝レイヤー降順、合成グループで打ち切り）。
    public func parentGroups(of item: BaseItem) -> [GroupItem] {
        var seen = Set<ObjectIdentifier>()
        var collected: [GroupItem] = []
        for group in parentsAndGrandparents(of: item, from: visibleGroups)
        where seen.insert(ObjectIdentifier(group)).inserted {
            collected.append(group)
        }
        let sorted = collected.sorted { $0.layer > $1.layer }
        return Array(sorted.prefix { !$0.isComposite })
    }

    /// グループの子アイテム列（レイヤー昇順）。
    public func children(of group: GroupItem) -> [BaseItem] {
        items
            .filter { item in
                isVideoItemEquivalent(item)
                    && !((item as? GroupItem)?.isComposite ?? false)
                    && parentGroups(of: item).contains { $0 === group }
            }
            .sorted { $0.layer < $1.layer }
    }

    private func parentsAndGrandparents(of item: BaseItem, from groups: [GroupItem]) -> [GroupItem] {
        let parents = directParents(of: item, from: groups)
        var result = parents
        let parentIDs = Set(parents.map { ObjectIdentifier($0) })
        let rest = groups.filter { !parentIDs.contains(ObjectIdentifier($0)) }
        for parent in parents {
            result += parentsAndGrandparents(of: parent, from: rest)
        }
        return result
    }

    private func directParents(of item: BaseItem, from groups: [GroupItem]) -> [GroupItem] {
        groups.filter { group in
            (!group.isGroupOnly || (group.group != 0 && group.group == item.group))
                && group.layer < item.layer
                && item.layer <= group.layer + group.groupRange
        }
    }
}

/// アイテム更新の失敗。本家 TimelineSource は並列更新の例外をアイテム情報
/// （Type / Label / Frame / Length / Layer / Group）つきで包み直す。
/// FrameBuffer 経路の更新失敗は包まれない（本家でも try/catch の外）。
public enum TimelineCompositionError: Error {
    case itemUpdateFailed(
        itemTypeName: String,
        label: String,
        frame: Int,
        length: Int,
        layer: Int,
        group: Int,
        underlying: any Error
    )

    /// 本家の包みメッセージと同じ形式の説明文。
    public var message: String {
        switch self {
        case let .itemUpdateFailed(itemTypeName, label, frame, length, layer, group, _):
            return "アイテムの更新に失敗しました。 Type=\(itemTypeName), Label=\(label), Frame=\(frame), Length=\(length), Layer=\(layer), Group=\(group)"
        }
    }
}

/// タイムライン全体の合成実行部。本家 TimelineSource に対応する。
///
/// シーンとアイテム群を管理し、Update（時刻と用途）で1フレーム分の合成結果
/// （出力参照）を返す。デバイス相当は借用であり、ここが所有するのは
/// アイテムごとの EffectedItemSource と、現在の描画先と、FrameBuffer へ
/// 渡した描画先の蓄積だけである。
///
/// Update の手順（第5章で確定した固定順序）:
/// 1. キャッシュの設定変更チェック（この層では差し替え点の呼び出しのみ）
/// 2. UpdateResources（範囲外の実行部の破棄・不足分の生成・親エフェクト再構築）
/// 3. 先読み（この層では未実装。合成結果に影響しない性能最適化であり、
///    位置だけを残す。台帳に記録）
/// 4. FrameBuffer 以外の全資源の更新（失敗はアイテム情報つきで包む。
///    この時点で失敗しても旧合成結果の参照は保持されるが、その内容が
///    前フレームと同一である保証はない。第5章の精密化1）
/// 5. 旧描画先と FrameBuffer 蓄積の解放
/// 6. 描画順序・セグメント構築（MAC-0009）のうえで描画先へ合成
/// 7. キャッシュのクリア（差し替え点の呼び出しのみ）
///
/// FrameBuffer 境界（IMG-04 の実体）: 合成の途中で FrameBuffer アイテムに
/// 当たると、現在の描画先を閉じて所有権を蓄積側へ移し、それを Source の
/// Input として設定してから FrameBuffer の実行部を更新し、新しい描画先で
/// 合成を続ける。蓄積は次回 Update の手順5で解放される。FrameBuffer の
/// 更新失敗は包まれず、合成途中の描画先が残る（第5章の精密化2と同じく、
/// 完了した出力は得られない）。
public final class TimelineComposer {
    /// 対象シーン。
    public let scene: TimelineScene
    /// 現在の合成結果。初回 Update の完了までは nil。
    public private(set) var output: ImageReference?

    private let picker: any ItemPicker
    private let targetFactory: any RenderTargetFactory
    private let sourceProvider: (VisualItem) -> any Source
    private let effectProvider: any EffectPairProvider
    private let segmentBuilder: DrawSegmentBuilder
    private let zoomInterpolationMode: InterpolationMode
    private let cameraFinalizer: (DrawDescription) -> DrawDescription
    private let alphaMaskFactory: (any AlphaMaskEffectFactory)?
    private let cacheInvalidationCheck: () -> Void
    private let cacheClear: () -> Void

    private var resources: [ObjectIdentifier: EffectedItemSource] = [:]
    private var currentTarget: (any RenderTarget)?
    private var frameBufferInputs: [any RenderTarget] = []
    /// クリッピング時に「直前の画像」が無い場合の代替（本家は白の Flood
    /// エフェクト出力を用いる。この層ではトークンで代用する）。
    private let floodOutput = ImageReference(label: "flood")

    public init(
        scene: TimelineScene,
        picker: any ItemPicker = CompositeItemPicker(),
        targetFactory: any RenderTargetFactory,
        sourceProvider: @escaping (VisualItem) -> any Source,
        effectProvider: any EffectPairProvider = EmptyEffectPairProvider(),
        segmentBuilder: DrawSegmentBuilder = DrawSegmentBuilder(),
        zoomInterpolationMode: InterpolationMode = .linear,
        cameraFinalizer: @escaping (DrawDescription) -> DrawDescription = { $0 },
        alphaMaskFactory: (any AlphaMaskEffectFactory)? = nil,
        cacheInvalidationCheck: @escaping () -> Void = {},
        cacheClear: @escaping () -> Void = {}
    ) {
        self.scene = scene
        self.picker = picker
        self.targetFactory = targetFactory
        self.sourceProvider = sourceProvider
        self.effectProvider = effectProvider
        self.segmentBuilder = segmentBuilder
        self.zoomInterpolationMode = zoomInterpolationMode
        self.cameraFinalizer = cameraFinalizer
        self.alphaMaskFactory = alphaMaskFactory
        self.cacheInvalidationCheck = cacheInvalidationCheck
        self.cacheClear = cacheClear
    }

    /// 対象タイムライン。
    public var timeline: Timeline { scene.timeline }
    /// 画面の幅（VideoInfo）。
    public var width: Int { scene.timeline.videoInfo.width }
    /// 画面の高さ（VideoInfo）。
    public var height: Int { scene.timeline.videoInfo.height }

    /// 1フレーム分を合成し、output を差し替える。
    public func update(time: TimeSpanValue, usage: TimelineSourceUsage) throws {
        cacheInvalidationCheck()

        let timeline = scene.timeline
        let videoInfo = timeline.videoInfo
        let fps = videoInfo.fps
        let frame = FrameTime.frame(from: time.seconds, fps: fps)

        let childItems = updateResources(frame: frame)
        // 先読み（本家 PrefetchResources）はここで呼ばれる。合成結果に影響
        // しない性能最適化であり、この層では未実装（台帳に記録）。

        let base = TimelineSourceDescription(
            screenSize: PixelSize(width: videoInfo.width, height: videoInfo.height),
            timelinePosition: FramePosition(frame: frame, fps: fps),
            timelineDuration: FramePosition(frame: timeline.length, fps: fps),
            fps: fps,
            usage: usage,
            sceneId: scene.sceneID,
            scenes: scene.scenes
        )

        // FrameBuffer 以外の全資源を更新する。本家は Parallel.ForEach で
        // 並列化するが、こちらは選定順に逐次実行する（並列化は実行順序を
        // 規定しない最適化であり、例外の集約形式は本家でも未確定）。
        for item in childItems {
            guard let effected = resources[ObjectIdentifier(item)] else { continue }
            if effected.source as? FrameBufferSource != nil { continue }
            let itemFrame = max(0, frame - item.frame)
            let itemLength = max(1, item.length)
            let description = itemDescription(
                base: base, item: effected.item, itemFrame: itemFrame, itemLength: itemLength
            )
            do {
                try effected.update(description)
            } catch {
                throw TimelineCompositionError.itemUpdateFailed(
                    itemTypeName: type(of: item).typeName,
                    label: item.label,
                    frame: item.frame,
                    length: item.length,
                    layer: item.layer,
                    group: item.group,
                    underlying: error
                )
            }
        }

        // 前回の合成結果と FrameBuffer 蓄積を、合成の開始時点で解放する。
        currentTarget?.dispose()
        currentTarget = nil
        for input in frameBufferInputs {
            input.dispose()
        }
        frameBufferInputs = []
        // 平面分割の断片資源は断片画像の生成（GPU 実行層）と一体であり、
        // この層では保持する資源が無い。

        // 描画順序とセグメント構築（MAC-0009）。
        var drawResources: [OrderedDrawResource] = []
        for item in childItems {
            guard let effected = resources[ObjectIdentifier(item)] else { continue }
            drawResources.append(OrderedDrawResource(
                visualItem: effected.item,
                isFrameBufferSource: effected.source as? FrameBufferSource != nil,
                drawDescriptions: effected.outputDrawDescriptions,
                planeSplitQuad: effected.getPlaneSplitQuad()
            ))
        }
        let segments = segmentBuilder.buildSegments(from: DrawOrdering.ordered(drawResources))

        var target = targetFactory.makeTarget()
        currentTarget = target
        target.beginDraw()
        target.clear()
        // 背景色は Clear 色ではない: 透明でクリアした後、背景色の不透明度が
        // あれば画面中心の矩形として描く（第5章）。
        let background = videoInfo.backgroundColor
        if background.alpha > 0 {
            target.fillRect(
                RectF(
                    left: -Double(videoInfo.width) / 2, top: -Double(videoInfo.height) / 2,
                    right: Double(videoInfo.width) / 2, bottom: Double(videoInfo.height) / 2
                ),
                color: background
            )
        }

        var drawnAnything = false
        var lastDrawnImage: ImageReference?
        for segment in segments {
            switch segment {
            case let .planeSplit(runResources, fragments):
                // 断片の描画に先立ち、資源の並びでクリッピングの手続きだけを
                // 行う（本家と同じ2段構成）。
                for resource in runResources {
                    guard let effected = resources[ObjectIdentifier(resource.item)] else { continue }
                    if effected.item.isClippingWithObjectAbove {
                        effected.setAlphaMask(lastDrawnImage ?? floodOutput)
                    } else {
                        lastDrawnImage = effected.output
                    }
                }
                for fragment in fragments {
                    let resource = runResources[fragment.resourceIndex]
                    guard let effected = resources[ObjectIdentifier(resource.item)] else { continue }
                    // 切断のある断片は断片画像の生成が要る。この層では生成
                    // できないためステップ自体を落とす（本家でも生成できない
                    // 断片は Steps から落ちる）。
                    if fragment.hasCuts { continue }
                    if let image = effected.output {
                        target.drawImage(
                            image, blend: effected.item.blend, interpolation: zoomInterpolationMode
                        )
                    }
                    drawnAnything = true
                }
            case let .single(resource):
                guard let effected = resources[ObjectIdentifier(resource.item)] else { continue }
                if let frameBufferSource = effected.source as? FrameBufferSource {
                    // FrameBuffer 境界: 現在の描画先を閉じて所有権を蓄積側へ
                    // 移し、Input として設定してから実行部を更新する。
                    // この更新の失敗は包まれない（本家でも try/catch の外）。
                    if !drawnAnything {
                        target.fillRect(
                            RectF(left: 0, top: 0, right: 0, bottom: 0), color: .transparent
                        )
                    }
                    target.endDraw()
                    // 本家の境界順序は EndDraw → ターゲット解除 → Close
                    // （EffectedItemSource 側の順序とは異なる）。この層では
                    // ターゲット解除が観測できないため endDraw → close に
                    // 畳まれる。
                    target.close()
                    currentTarget = nil
                    frameBufferInputs.append(target)
                    let closedTarget = target
                    frameBufferSource.input = closedTarget.image
                    frameBufferSource.frameSize = PixelSize(
                        width: videoInfo.width, height: videoInfo.height
                    )
                    // FrameBuffer 経路ではアイテム内位置の 0 クランプと
                    // 長さの max(1, …) を行わない（本家どおり）。
                    let description = itemDescription(
                        base: base,
                        item: effected.item,
                        itemFrame: frame - effected.item.frame,
                        itemLength: effected.item.length
                    )
                    try effected.update(description)

                    let newTarget = targetFactory.makeTarget()
                    currentTarget = newTarget
                    target = newTarget
                    target.beginDraw()
                    target.clear()
                    if !frameBufferSource.clearBackground {
                        // 背景をクリアしない場合は前回の蓄積を引き継ぐ。
                        target.drawImage(closedTarget.image)
                    }
                }
                // クリッピング対象は描画に先立ってマスクを設定される。
                // 自身の出力は描かれるが、「直前の画像」としては数えない。
                if effected.item.isClippingWithObjectAbove {
                    effected.setAlphaMask(lastDrawnImage ?? floodOutput)
                }
                if let image = effected.output {
                    target.drawImage(
                        image, blend: effected.item.blend, interpolation: zoomInterpolationMode
                    )
                }
                if !effected.item.isClippingWithObjectAbove {
                    lastDrawnImage = effected.output
                }
                drawnAnything = true
            }
        }

        if !drawnAnything {
            target.fillRect(RectF(left: 0, top: 0, right: 0, bottom: 0), color: .transparent)
        }
        target.endDraw()
        target.close()
        output = target.image

        // TimelineItemRects（当たり判定用データ）の再構築は、画像境界の
        // 問い合わせ（GPU 実行層）が要るためこの層では行わない（台帳に記録）。

        cacheClear()
    }

    /// 所有する資源を解放する。
    public func dispose() {
        for effected in resources.values {
            effected.dispose()
        }
        resources = [:]
        currentTarget?.dispose()
        currentTarget = nil
        for input in frameBufferInputs {
            input.dispose()
        }
        frameBufferInputs = []
        output = nil
    }

    /// 資源管理（本家 UpdateResources に対応）。選定されたアイテム列を返す。
    ///
    /// - 範囲外のアイテムと非合成グループの実行部はその場で破棄する。
    /// - 不足分を生成する。資源を持つのは映像アイテムだけであり、
    ///   非合成グループは資源を持たない（合成グループは1アイテムとして
    ///   資源を持つ）。この層の実行部は VisualItem を対象とするため、
    ///   VoiceItem / TransitionItem は資源を持たない（台帳に記録）。
    /// - 親エフェクトは毎回再構築する: 全資源の親エフェクトを消去 →
    ///   立ち絵の顔・声解決（顔エフェクト）→ グループの親エフェクト
    ///   （近い親の順）の順で積む。
    private func updateResources(frame: Int) -> [BaseItem] {
        let timeline = scene.timeline
        let childItems = picker.pickItems(in: timeline, frame: frame)
        let childIDs = Set(childItems.map { ObjectIdentifier($0) })

        for (id, effected) in resources {
            let isNonCompositeGroup = (effected.item as? GroupItem).map { !$0.isComposite } ?? false
            if !childIDs.contains(id) || isNonCompositeGroup {
                effected.dispose()
                resources.removeValue(forKey: id)
            }
        }

        for item in childItems {
            guard let visual = item as? VisualItem else { continue }
            if let group = visual as? GroupItem, !group.isComposite { continue }
            let id = ObjectIdentifier(item)
            if resources[id] == nil {
                resources[id] = EffectedItemSource(
                    item: visual,
                    source: sourceProvider(visual),
                    targetFactory: targetFactory,
                    effectProvider: effectProvider,
                    cameraFinalizer: cameraFinalizer,
                    zoomInterpolationMode: zoomInterpolationMode,
                    alphaMaskFactory: alphaMaskFactory
                )
            }
        }

        for effected in resources.values {
            effected.parentEffects = []
        }

        // 立ち絵の顔・声解決。同じキャラクターの顔アイテムをレイヤー降順に
        // 集め、最初の VoiceItem を声、先頭を顔エフェクトの時間基準にする。
        let faceItems = picker.pickFaceItems(in: timeline, frame: frame)
        for item in childItems {
            guard let tachie = item as? TachieItem,
                  let effected = resources[ObjectIdentifier(item)],
                  let tachieSource = effected.source as? any TachieSource
            else { continue }
            let faces = faceItems
                .filter { faceCharacter(of: $0) === tachie.character }
                .sorted { $0.layer > $1.layer }
            tachieSource.activeVoice = faces.compactMap { $0 as? VoiceItem }.first
            tachieSource.activeFaces = faces.compactMap { $0 as? any FaceItem }
            if let active = faces.first {
                effected.parentEffects += effectProvider.faceEffectPairs(for: active)
            }
        }

        // グループの親エフェクト。子位置と子総数は解決側が算出する。
        let resolver = TimelineGroupResolver(items: childItems) { layer in
            !timeline.layerSettings.setting(forLayer: layer).isHidden
        }
        for item in childItems {
            guard let effected = resources[ObjectIdentifier(item)] else { continue }
            for group in resolver.parentGroups(of: item) {
                let children = resolver.children(of: group)
                let childIndex = children.firstIndex { $0 === item } ?? -1
                effected.parentEffects += effectProvider.groupEffectPairs(
                    for: group, childIndex: childIndex, childCount: children.count
                )
            }
        }

        return childItems
    }

    /// アイテム説明の構築。本家 CreateItemSourceDescription に対応する。
    /// RenderScale はタイムライン説明（親スケールなし）とアイテムの Zoom
    /// 評価値から ComposeRenderScale で合成する。
    private func itemDescription(
        base: TimelineSourceDescription,
        item: VisualItem,
        itemFrame: Int,
        itemLength: Int
    ) -> TimelineItemSourceDescription {
        var description = TimelineItemSourceDescription(
            base, itemFrame: itemFrame, itemLength: itemLength, layer: item.layer
        )
        let itemScale = abs(item.zoom.value(atFrame: itemFrame, length: itemLength, fps: base.fps) / 100)
        description.renderScale = TimelineItemSourceDescription.composeRenderScale(
            parentRenderScale: nil, itemScale: itemScale
        )
        return description
    }

    /// 顔アイテムのキャラクター（VoiceItem / TachieFaceItem のみが持つ）。
    private func faceCharacter(of item: BaseItem) -> Character? {
        if let voice = item as? VoiceItem { return voice.character }
        if let face = item as? TachieFaceItem { return face.character }
        return nil
    }
}
