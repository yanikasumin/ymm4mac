import Foundation

/// 出力1件分のエフェクト連鎖の実行部。本家 EffectedSourceOutput に対応する。
///
/// 契約（第4章で確定）:
/// - 処理器の再利用は位置（index）基準。差し替え時は新しい処理器の
///   SetInput → Update が完了してから旧処理器を ClearInput → Dispose する。
/// - 再利用時は、保持している入力参照と現在の入力が同一なら SetInput を
///   再発行しない。ただし Update は常に行う。
/// - DrawDescription は各段の Update の戻り値で連鎖的に書き換わる。
/// - 連鎖の縮小は末尾からのみ（超過分は ClearInput → Dispose）。
/// - 失敗時: 連鎖途中の失敗では Output / DrawDescription は前回のまま
///   （伝播のみ）。DrawingEffect の失敗だけは EffectedItemError で包む。
///   差し替え段で例外が出た場合、新しい処理器は記録も破棄もされずに
///   孤立しうる（本家でも同じ）。
/// - Dispose は処理器群を ClearInput → Dispose し、Output を nil にする。
///   DrawingEffect と入力画像は借用であり破棄しない。
public final class EffectedOutput {
    /// 対象アイテム（本家 IVideoItem の範囲: VisualItem 系譜 + VoiceItem +
    /// TransitionItem）。
    public let item: BaseItem & VideoItemProperties

    /// アイテム変形を適用する前の出力（連鎖の最終段の出力）。
    public private(set) var preRenderOutput: ImageReference?
    /// アイテム変形適用後の出力。applyItemTransform が false の更新では
    /// 書き換わらない（古い値が残りうる。本家と同じ。消費者は
    /// PreRenderOutput を使う）。
    public private(set) var output: ImageReference?
    /// 確定した描画変換。
    public private(set) var drawDescription: DrawDescription = .empty
    /// 現在採用している DrawingEffect（借用。破棄しない）。
    public private(set) var currentDrawingEffect: (any DrawingEffectProcessor)?

    private struct EffectResource {
        var timeSource: BaseItem
        var definition: any VideoEffectDefinition
        var groupIndex: Int
        var groupCount: Int
        var processor: any VideoEffectProcessor
        var effectInput: ImageReference?
        var effectOutput: ImageReference?
    }

    private var resources: [EffectResource] = []
    private let cameraFinalizer: (DrawDescription) -> DrawDescription
    private let zoomInterpolationMode: InterpolationMode

    public init(
        item: BaseItem & VideoItemProperties,
        cameraFinalizer: @escaping (DrawDescription) -> DrawDescription = { $0 },
        zoomInterpolationMode: InterpolationMode = .linear
    ) {
        self.item = item
        self.cameraFinalizer = cameraFinalizer
        self.zoomInterpolationMode = zoomInterpolationMode
    }

    /// 連鎖を実行し、必要ならアイテム変形まで適用する。本家
    /// EffectedSourceOutput.Update に対応する。
    public func update(
        inputIndex: Int,
        inputCount: Int,
        input: any SourceOutput,
        itemDescription: TimelineItemSourceDescription,
        effects: [EffectPair],
        applyItemTransform: Bool
    ) throws {
        var drawDescription = createDrawDescription(input: input, itemDescription: itemDescription)
        var output: ImageReference? = input.output

        // 連鎖の縮小は末尾からのみ行う。
        while effects.count < resources.count {
            let removed = resources.removeLast()
            removed.processor.clearInput()
            removed.processor.dispose()
        }

        for index in effects.indices {
            let pair = effects[index]
            if resources.count <= index
                || ObjectIdentifier(resources[index].definition) != ObjectIdentifier(pair.definition)
            {
                // 差し替え: 新しい処理器の SetInput → Update が完了してから
                // 旧処理器を破棄する。新側の Update で例外が出た場合、新しい
                // 処理器は記録も破棄もされない（本家でも孤立する）。
                let old = resources.count > index ? resources[index] : nil
                let processor = pair.definition.createProcessor()
                let effectInput = output
                processor.setInput(output)
                let effectDescription = Self.createEffectDescription(
                    itemDescription: itemDescription,
                    timeSource: pair.timeSource,
                    timeOffset: input.timeOffset,
                    durationOffset: input.durationOffset,
                    effectTarget: item,
                    drawDescription: drawDescription,
                    inputIndex: inputIndex,
                    inputCount: inputCount,
                    groupIndex: pair.groupIndex,
                    groupCount: pair.groupCount
                )
                drawDescription = try processor.update(effectDescription)
                output = processor.output
                let resource = EffectResource(
                    timeSource: pair.timeSource,
                    definition: pair.definition,
                    groupIndex: pair.groupIndex,
                    groupCount: pair.groupCount,
                    processor: processor,
                    effectInput: effectInput,
                    effectOutput: output
                )
                if resources.count <= index {
                    resources.append(resource)
                } else {
                    resources[index] = resource
                }
                if let old {
                    old.processor.clearInput()
                    old.processor.dispose()
                }
            } else {
                // 再利用: 入力参照が変わった場合だけ SetInput を再発行する。
                // Update は常に行う。
                var resource = resources[index]
                let effectInput = output
                if resource.effectInput !== output {
                    resource.processor.setInput(output)
                }
                let effectDescription = Self.createEffectDescription(
                    itemDescription: itemDescription,
                    timeSource: pair.timeSource,
                    timeOffset: input.timeOffset,
                    durationOffset: input.durationOffset,
                    effectTarget: item,
                    drawDescription: drawDescription,
                    inputIndex: inputIndex,
                    inputCount: inputCount,
                    groupIndex: pair.groupIndex,
                    groupCount: pair.groupCount
                )
                drawDescription = try resource.processor.update(effectDescription)
                output = resource.processor.output
                resource.timeSource = pair.timeSource
                resource.groupIndex = pair.groupIndex
                resource.groupCount = pair.groupCount
                resource.effectInput = effectInput
                resource.effectOutput = output
                resources[index] = resource
            }
        }

        let inputChanged = preRenderOutput !== output
        preRenderOutput = output

        guard applyItemTransform else {
            self.drawDescription = drawDescription
            return
        }

        // アイテム変形: 入力が変わったか DrawingEffect 自体が差し替わった
        // 場合だけ SetInput を発行する。
        if inputChanged || currentDrawingEffect !== input.drawingEffect {
            currentDrawingEffect = input.drawingEffect
            input.drawingEffect?.setInput(output)
        }
        let finalized = cameraFinalizer(drawDescription)
        guard let drawingEffect = input.drawingEffect else {
            // 本家はこの経路で DrawingEffect が nil だと例外になる。
            // MAC-0009 が内部の一時出力では DrawingEffect を任意としたため、
            // こちらでは変形なしで通す（意図的な差分として台帳に記録）。
            self.drawDescription = finalized
            self.output = output
            return
        }
        do {
            self.drawDescription = try drawingEffect.update(Self.createEffectDescription(
                itemDescription: itemDescription,
                timeSource: item,
                timeOffset: input.timeOffset,
                durationOffset: input.durationOffset,
                effectTarget: item,
                drawDescription: finalized,
                inputIndex: inputIndex,
                inputCount: inputCount,
                groupIndex: 0,
                groupCount: 0
            ))
        } catch {
            throw EffectedItemError.drawingEffectUpdateFailed(
                itemTypeName: type(of: item).typeName,
                effectCount: resources.count,
                graphDescription: diagnoseGraph(),
                underlying: error
            )
        }
        self.output = drawingEffect.output
    }

    /// 処理器群を ClearInput → Dispose し、Output を nil にする。
    /// DrawingEffect と入力画像は借用であり破棄しない。
    public func dispose() {
        for resource in resources {
            resource.processor.clearInput()
            resource.processor.dispose()
        }
        resources = []
        output = nil
    }

    /// 初期の描画変換。本家 CreateDrawDescriotion に対応する。
    ///
    /// フェード係数は min(1, 経過/フェードイン) と min(1, 残り/フェードアウト)
    /// の小さい方で、**下限のクランプは無い**（本家どおり。Swift 側で
    /// max(0, …) を足すと境界フレームの挙動が変わる）。
    /// ズーム補間方式は本家では設定（YMMSettings）から読む。設定層が未実装の
    /// ため、この層では差し替え点として受け取る。
    private func createDrawDescription(
        input: any SourceOutput,
        itemDescription: TimelineItemSourceDescription
    ) -> DrawDescription {
        let offsetFrames = FrameTime.frame(from: input.timeOffset.seconds, fps: itemDescription.fps)
        let durationOffsetFrames = FrameTime.frame(
            from: input.durationOffset.seconds, fps: itemDescription.fps
        )
        // 本家は基底説明から作り直す（RenderScale は引き継がない）。
        let adjusted = TimelineItemSourceDescription(
            itemDescription.base,
            itemFrame: itemDescription.itemPosition.frame + offsetFrames,
            itemLength: itemDescription.itemDuration.frame + offsetFrames + durationOffsetFrames,
            layer: itemDescription.layer
        )
        let frame = adjusted.itemPosition.frame
        let duration = adjusted.itemDuration.frame
        let fps = adjusted.fps
        let positionSeconds = adjusted.itemPosition.time
        let durationSeconds = adjusted.itemDuration.time
        // 変形の読み取りは解決済みの値（effective*）経由にする。本家では
        // IVideoItem 経由の読み取りで VoiceItem の JimakuVisibility 解決が
        // 効くため、それに合わせる（MAC-0014）。
        let fadeInFactor = item.effectiveFadeIn == 0 ? 1 : min(1, positionSeconds / item.effectiveFadeIn)
        let fadeOutFactor = item.effectiveFadeOut == 0 ? 1 : min(1, (durationSeconds - positionSeconds) / item.effectiveFadeOut)
        let fadeFactor = min(fadeInFactor, fadeOutFactor)
        let zoomValue = item.effectiveZoom.value(atFrame: frame, length: duration, fps: fps) / 100
        return DrawDescription(
            draw: Vector3(
                x: item.effectiveX.value(atFrame: frame, length: duration, fps: fps) + input.drawingOffset.x,
                y: item.effectiveY.value(atFrame: frame, length: duration, fps: fps) + input.drawingOffset.y,
                z: item.effectiveZ.value(atFrame: frame, length: duration, fps: fps)
            ),
            centerPoint: input.center,
            zoom: Vector2(x: zoomValue, y: zoomValue),
            rotation: Vector3(
                x: 0, y: 0,
                z: item.effectiveRotation.value(atFrame: frame, length: duration, fps: fps)
            ),
            camera: .identity,
            zoomInterpolationMode: zoomInterpolationMode,
            opacity: item.effectiveOpacity.value(atFrame: frame, length: duration, fps: fps) / 100 * fadeFactor,
            invert: item.effectiveIsInverted,
            controllers: []
        )
    }

    /// エフェクト説明の構築。本家 CreateEffectDescription に対応する。
    /// アイテム説明は基底から作り直す（RenderScale は引き継がない。本家の
    /// コンストラクタ束縛どおり）。アイテム内位置はタイムライン位置から
    /// 時間基準アイテムの開始を引いたものになる。
    static func createEffectDescription(
        itemDescription: TimelineItemSourceDescription,
        timeSource: BaseItem,
        timeOffset: TimeSpanValue,
        durationOffset: TimeSpanValue,
        effectTarget: BaseItem,
        drawDescription: DrawDescription,
        inputIndex: Int,
        inputCount: Int,
        groupIndex: Int,
        groupCount: Int
    ) -> EffectDescription {
        let offsetFrames = FrameTime.frame(from: timeOffset.seconds, fps: itemDescription.fps)
        let durationOffsetFrames = FrameTime.frame(from: durationOffset.seconds, fps: itemDescription.fps)
        let itemPart = TimelineItemSourceDescription(
            itemDescription.base,
            itemFrame: itemDescription.timelinePosition.frame - timeSource.frame + offsetFrames,
            itemLength: timeSource.length + offsetFrames + durationOffsetFrames,
            layer: effectTarget.layer
        )
        return EffectDescription(
            itemDescription: itemPart,
            drawDescription: drawDescription,
            inputIndex: inputIndex,
            inputCount: inputCount,
            groupIndex: groupIndex,
            groupCount: groupCount
        )
    }

    /// 診断用のグラフ表現。本家 DiagnoseGraphNodes は各ノードの画像境界を
    /// GPU へ問い合わせて OK/FAIL を判定するが、この層の画像参照には境界が
    /// 無いため、ノード名と出力の有無（ラベル）で表す。境界の問い合わせと
    /// FAIL 判定、問題エフェクトのパラメータ JSON の添付は GPU 実行層・
    /// 直列化層の段で扱う（台帳に記録）。
    private func diagnoseGraph() -> String {
        var nodes: [String] = []
        let sourceImage = resources.first?.effectInput ?? preRenderOutput
        nodes.append("Source=\(sourceImage.map { "OK(\($0.label))" } ?? "null")")
        for resource in resources {
            let name = "Effect[\(String(describing: type(of: resource.definition)))]"
            if let image = resource.effectOutput {
                nodes.append("\(name)=OK(\(image.label))")
            } else {
                nodes.append("\(name)=null")
            }
        }
        return nodes.joined(separator: " ")
    }
}

/// アイテム1件分の合成実行部。本家 EffectedItemSource に対応する。
///
/// Source の生出力を、エフェクト連鎖＋親グループのエフェクト＋アイテム変換を
/// 通した1つの出力へ変換する。所有関係: Source と、生成した描画先と、
/// 出力ごとの EffectedOutput を所有する。親エフェクト（parentEffects）は
/// TimelineSource 相当が毎回再構築して差し込む借用データであり、定義や
/// 処理器の所有は移らない。
///
/// 失敗時の旧 Output の扱い（第4章の精密化どおり）:
/// - Source.Update の失敗: UpdateEffects へ進まず、旧 Output は無事。
/// - 連鎖（EffectedOutput.Update）の失敗: 旧合成結果はまだ破棄されて
///   いないため、旧 Output は無事。
/// - 合成ステップ（旧描画先の破棄後）の失敗: 旧 Output が破棄済みの
///   描画先を指しうる（保証なし）。この層の描画先操作は例外を投げないため
///   実際に失敗するのは GPU 実行層の段であり、タイミングの構造だけを
///   ここで再現する。
public final class EffectedItemSource {
    /// 対象アイテム（本家 IVideoItem の範囲: VisualItem 系譜 + VoiceItem +
    /// TransitionItem）。
    public let item: BaseItem & VideoItemProperties
    /// 素材の Source（所有）。
    public let source: any Source
    /// アイテム変形を適用するか（本家の applyItemTransform）。
    public let applyItemTransform: Bool

    /// 親から継いだエフェクト（顔エフェクト→グループエフェクトの順）。
    /// TimelineSource 相当が UpdateResources のたびに再構築する。
    public var parentEffects: [EffectPair] = []

    /// 合成済みの出力。初回 Update の完了までは nil。
    public private(set) var output: ImageReference?
    /// 先頭出力の描画変換。出力が0件なら空の描画変換（本家
    /// CreateEmptyDrawDescription 相当）。
    public private(set) var drawDescription: DrawDescription = .empty

    private var effectedOutputs: [EffectedOutput] = []
    private var outputTarget: (any RenderTarget)?
    private var alphaMask: (any AlphaMaskEffect)?
    private let targetFactory: any RenderTargetFactory
    private let effectProvider: any EffectPairProvider
    private let cameraFinalizer: (DrawDescription) -> DrawDescription
    private let zoomInterpolationMode: InterpolationMode
    private let alphaMaskFactory: (any AlphaMaskEffectFactory)?

    public init(
        item: BaseItem & VideoItemProperties,
        source: any Source,
        targetFactory: any RenderTargetFactory,
        effectProvider: any EffectPairProvider = TypedEffectPairProvider(),
        applyItemTransform: Bool = true,
        cameraFinalizer: @escaping (DrawDescription) -> DrawDescription = { $0 },
        zoomInterpolationMode: InterpolationMode = .linear,
        alphaMaskFactory: (any AlphaMaskEffectFactory)? = nil
    ) {
        self.item = item
        self.source = source
        self.targetFactory = targetFactory
        self.effectProvider = effectProvider
        self.applyItemTransform = applyItemTransform
        self.cameraFinalizer = cameraFinalizer
        self.zoomInterpolationMode = zoomInterpolationMode
        self.alphaMaskFactory = alphaMaskFactory
    }

    /// Source を更新し、続いてエフェクト連鎖と合成を行う。
    /// 本家 EffectedItemSource.Update（UpdateSource → UpdateEffects）に対応する。
    public func update(_ description: TimelineItemSourceDescription) throws {
        try source.update(description)
        try updateEffects(description)
    }

    /// 各出力の確定した描画変換（描画順序の ZIndex 算出元）。
    public var outputDrawDescriptions: [DrawDescription] {
        effectedOutputs.map(\.drawDescription)
    }

    /// ZIndex。本家 EffectedItemSource.GetZIndex と同じく、各出力の変換後
    /// 原点 Z の最大値（出力が無ければ 0）。
    public var zIndex: Double {
        DrawOrdering.zIndex(of: outputDrawDescriptions)
    }

    /// 平面分割用の四隅。本家 GetPlaneSplitQuad の nil 条件は
    /// DrawOrdering.planeSplitQuad が担い、こちらは各出力の DrawingEffect から
    /// 幾何情報を集める。出力が0件なら nil。
    public func getPlaneSplitQuad() -> [Vector3]? {
        guard !effectedOutputs.isEmpty else { return nil }
        let geometries = effectedOutputs.map { effectedOutput -> PlaneSplitOutputGeometry in
            guard let provider = effectedOutput.currentDrawingEffect as? PlaneSplitGeometryProviding
            else {
                return PlaneSplitOutputGeometry(worldTransform: nil, inputBounds: nil)
            }
            return PlaneSplitOutputGeometry(
                worldTransform: provider.worldTransform3D,
                inputBounds: provider.transform3DInputBounds()
            )
        }
        return DrawOrdering.planeSplitQuad(outputs: geometries)
    }

    /// クリッピング用のマスクを設定する（本家 SetAlphaMask）。
    /// マスクがまだ生成されていない場合は何もしない（本家と同じ）。
    public func setAlphaMask(_ mask: ImageReference) {
        alphaMask?.setInput(1, mask)
    }

    /// 所有する資源を解放する。マスクの入力解除を先に行う（本家と同じ）。
    public func dispose() {
        alphaMask?.setInput(0, nil)
        alphaMask?.setInput(1, nil)
        outputTarget?.dispose()
        outputTarget = nil
        alphaMask?.dispose()
        alphaMask = nil
        for effectedOutput in effectedOutputs.reversed() {
            effectedOutput.dispose()
        }
        effectedOutputs = []
        source.dispose()
        output = nil
    }

    private func updateEffects(_ description: TimelineItemSourceDescription) throws {
        let snapshot = source.outputs

        // 出力数の調整は末尾だけ（超過は破棄、不足は生成）。
        while effectedOutputs.count > snapshot.count {
            effectedOutputs.removeLast().dispose()
        }
        while effectedOutputs.count < snapshot.count {
            effectedOutputs.append(EffectedOutput(
                item: item,
                cameraFinalizer: cameraFinalizer,
                zoomInterpolationMode: zoomInterpolationMode
            ))
        }

        // 連鎖 = 自前エフェクト ++ 親エフェクト。有効なものだけが対象。
        let effects = (effectProvider.ownEffectPairs(for: item) + parentEffects)
            .filter { $0.definition.isEnabled }
        for (index, sourceOutput) in snapshot.enumerated() {
            try effectedOutputs[index].update(
                inputIndex: index,
                inputCount: snapshot.count,
                input: sourceOutput,
                itemDescription: description,
                effects: effects,
                applyItemTransform: applyItemTransform
            )
        }

        // 旧合成結果の破棄は、全出力の更新が完了した直後（この前で失敗すれば
        // 旧 Output は無事。この後で失敗すれば保証はない。第4章の精密化）。
        outputTarget?.dispose()
        outputTarget = nil

        let target = targetFactory.makeTarget()
        target.beginDraw()
        if effectedOutputs.isEmpty {
            // 出力が0件でも Output は有効な参照を返す（透明な 1x1 矩形）。
            target.fillRect(RectF(left: 0, top: 0, right: 1, bottom: 1), color: .transparent)
        } else {
            for effectedOutput in effectedOutputs {
                let image = applyItemTransform ? effectedOutput.output : effectedOutput.preRenderOutput
                if let image {
                    target.drawImage(image)
                }
            }
        }
        target.endDraw()
        // 本家の終了順序は EndDraw → Close → ターゲット解除（FrameBuffer 境界の
        // EndDraw → ターゲット解除 → Close とは異なる）。この層ではターゲット
        // 解除が観測できないため endDraw → close に畳まれる。
        do {
            try target.close()
        } catch {
            // 閉じることに失敗した描画先は出力として公開せず、その場で解放
            // して失敗を呼び出し側へ伝える（MAC-0021）。
            target.dispose()
            throw error
        }
        outputTarget = target

        if applyItemTransform && item.effectiveIsClippingWithObjectAbove {
            if alphaMask == nil {
                alphaMask = alphaMaskFactory?.makeAlphaMaskEffect()
            }
            if let mask = alphaMask {
                mask.setInput(0, target.image)
                output = mask.output ?? target.image
            } else {
                // マスク生成が差し替え点に留まる間は、未適用の出力を返す
                // （意図的な差分として台帳に記録）。
                output = target.image
            }
        } else {
            if let mask = alphaMask {
                mask.setInput(0, nil)
                mask.setInput(1, nil)
                mask.dispose()
                alphaMask = nil
            }
            output = target.image
        }

        drawDescription = effectedOutputs.first?.drawDescription ?? .empty
    }
}
