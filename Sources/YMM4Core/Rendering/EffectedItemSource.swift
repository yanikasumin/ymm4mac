import Foundation

/// エフェクト連鎖の処理器1段。本家 IVideoEffectProcessor に対応する。
///
/// MAC-0009 の DrawingEffectProcessor は Source 契約の境界（入力設定と
/// DrawDescription の確定）だけを切り出したものであり、連鎖の各段はこちらが
/// 本体になる。形は同じだが責務が違うため分ける（本家でも ISourceOutput の
/// DrawingEffect と連鎖内の処理器は同じインタフェースを共有するが、こちらでは
/// 契約の出所を型で区別する）。
///
/// 所有権（第1章 IMG-03）: SetInput は入力の所有権を移さない。ClearInput は
/// 設定されていた入力を破棄しない。Output の有効範囲は、この処理器を所有する
/// EffectedOutput の次の Update が始まるまで（IMG-05）。
public protocol VideoEffectProcessor: AnyObject {
    /// 現在の出力（入力未設定・未更新なら nil もありうる）。
    var output: ImageReference? { get }
    /// 入力を設定する。所有権は移らない。
    func setInput(_ image: ImageReference?)
    /// 入力を解除する。解除された入力は破棄されない。
    func clearInput()
    /// 説明に基づいて出力を更新し、確定した描画変換を返す。
    /// 失敗した場合は例外を投げる（呼び出し側の失敗意味論は第4章の精密化どおり）。
    @discardableResult
    func update(_ description: EffectDescription) throws -> DrawDescription
    /// 自身が所有する資源を解放する。
    func dispose()
}

/// エフェクト定義（本家 IVideoEffect に対応する、連鎖の「型」側）。
///
/// 連鎖の再利用判定はこの定義の**同一性**（インスタンス）で行う（第4章:
/// 位置 index 基準の再利用、差し替え条件は IVideoEffect 参照の不一致）。
/// モデル層の映像エフェクトは現在 PreservedObject（生 JSON）で保持されており、
/// 定義への橋渡しは個別エフェクト実装の段で行う。ここでは同一性・有効状態・
/// 処理器の生成だけを契約とする。
public protocol VideoEffectDefinition: AnyObject {
    /// 有効か。無効な定義は連鎖から除外される（本家 IsEnabled）。
    var isEnabled: Bool { get }
    /// 処理器を新規生成する。生成した処理器の所有権は呼び出し側へ移る。
    func createProcessor() -> any VideoEffectProcessor
    /// 診断用のパラメータ表現（任意）。本家は DrawingEffect の更新失敗時に
    /// 問題エフェクトの設定 JSON を診断文字列へ含める（4000 文字で切る）。
    /// この層では JSON 化の責務を持たないため、定義側が文字列で提供できる
    /// 場合だけ使う。
    var diagnosticText: String? { get }
}

extension VideoEffectDefinition {
    public var diagnosticText: String? { nil }
}

/// エフェクト適用の組。本家 EffectedItemSource が扱う
/// (TimeSource, Effect, GroupIndex, GroupCount) のタプルに対応する。
public struct EffectPair {
    /// エフェクトの時間基準になるアイテム（自前エフェクトはアイテム自身、
    /// グループエフェクトはグループ、顔エフェクトは顔アイテム）。
    public var timeSource: BaseItem
    /// エフェクト定義。
    public var definition: any VideoEffectDefinition
    /// グループ内の子位置（グループエフェクト用。それ以外は 0）。
    public var groupIndex: Int
    /// グループの子総数（グループエフェクト用。それ以外は 0）。
    public var groupCount: Int

    public init(
        timeSource: BaseItem,
        definition: any VideoEffectDefinition,
        groupIndex: Int = 0,
        groupCount: Int = 0
    ) {
        self.timeSource = timeSource
        self.definition = definition
        self.groupIndex = groupIndex
        self.groupCount = groupCount
    }
}

/// エフェクト定義の供給元。モデル層のエフェクト列（PreservedObject の生 JSON）
/// から定義インスタンスへの橋渡しを担う境界であり、個別エフェクト実装の段で
/// 実物に差し替える。この層の既定実装は何も供給しない（連鎖は素通しになる）。
public protocol EffectPairProvider {
    /// アイテム自身のエフェクト（本家 Item.VideoEffects）。
    func ownEffectPairs(for item: VisualItem) -> [EffectPair]
    /// グループのエフェクト（本家 GroupItem.GroupEffects）。子位置と子総数は
    /// グループ解決側（TimelineGroupResolver）が算出して渡す。
    func groupEffectPairs(for group: GroupItem, childIndex: Int, childCount: Int) -> [EffectPair]
    /// 顔アイテムのエフェクト（本家 TachieFaceEffects）。時間基準は顔アイテム自身。
    func faceEffectPairs(for faceItem: BaseItem) -> [EffectPair]
}

/// エフェクトを何も供給しない供給元（この層の既定）。
public struct EmptyEffectPairProvider: EffectPairProvider {
    public init() {}

    public func ownEffectPairs(for item: VisualItem) -> [EffectPair] { [] }
    public func groupEffectPairs(for group: GroupItem, childIndex: Int, childCount: Int) -> [EffectPair] { [] }
    public func faceEffectPairs(for faceItem: BaseItem) -> [EffectPair] { [] }
}

/// 描画先（コマンドリスト相当）。本家 ID2D1DeviceContext + ID2D1CommandList の
/// 組を、GPU に触れない抽象として表したもの。GPU 実行層が実物に差し替える。
///
/// 本家には描画先の「ターゲット設定／解除」という文脈状態があるが、この層では
/// ターゲット自身が描画操作を受けるため、その状態はターゲットへ畳み込む。
/// 結果として本家に2通りある終了順序（EffectedItemSource 側は
/// EndDraw → Close → ターゲット解除、TimelineSource の FrameBuffer 境界は
/// EndDraw → ターゲット解除 → Close）は、この層ではどちらも
/// endDraw → close として観測される（内部差分。GPU 実行層で再現する）。
public protocol RenderTarget: AnyObject {
    /// 記録済みのコマンド列を表す画像参照（本家ではコマンドリスト自身が画像）。
    var image: ImageReference { get }
    /// 描画を開始する。
    func beginDraw()
    /// 透明でクリアする（本家の合成開始時の Clear に対応）。
    func clear()
    /// 矩形を塗る（背景描画と、描画対象が無い場合の目印に使う）。
    func fillRect(_ rect: RectF, color: Color)
    /// 画像をそのまま描く（本家 DrawImage(image) に対応。EffectedItemSource の
    /// 合成と FrameBuffer の引き継ぎ描画で使う）。
    func drawImage(_ image: ImageReference)
    /// 画像をアイテムのブレンドで描く（本家 TimelineSource.DrawResourceImage に
    /// 対応。本家は Blend が合成系なら DrawImage、ブレンド系なら BlendImage と
    /// 呼び分けるが、その振り分けは GPU 実行層の解釈に委ね、ここでは Blend の
    /// 値をそのまま渡す）。
    func drawImage(_ image: ImageReference, blend: Blend, interpolation: InterpolationMode)
    /// 描画を終える。
    func endDraw()
    /// コマンド列を閉じる。以後の描画はできない。
    func close()
    /// 実体を解放する。
    func dispose()
}

/// 描画先の生成者。本家 GraphicsDevicesAndContext 相当が担う生成の境界だけを
/// 切り出したもの。生成した描画先の所有権は呼び出し側へ移る。
public protocol RenderTargetFactory {
    func makeTarget() -> any RenderTarget
}

/// アルファマスク（本家 AlphaMaskEffect に対応する2入力の特殊エフェクト）。
/// 入力0 = マスクされる側の画像、入力1 = マスク画像。生成は差し替え点とし、
/// 実装は GPU 実行層の段で行う。
public protocol AlphaMaskEffect: AnyObject {
    /// マスク適用後の出力。
    var output: ImageReference? { get }
    /// 入力を設定する（index は 0 = 本体、1 = マスク）。
    func setInput(_ index: Int, _ image: ImageReference?)
    /// 自身が所有する資源を解放する。
    func dispose()
}

/// アルファマスクの生成者。
public protocol AlphaMaskEffectFactory {
    func makeAlphaMaskEffect() -> any AlphaMaskEffect
}

/// 平面分割の四隅算出に必要な幾何情報を DrawingEffect から取り出す境界。
/// 本家では DrawingEffect（具象クラス）が WorldTransform3D と
/// GetTransform3DInputBounds を持つ。こちらではプロトコル適合で表し、
/// 適合しない DrawingEffect を持つ出力は四隅を計算できない（本家でも
/// DrawingEffect でない出力があると GetPlaneSplitQuad は nil を返す）。
public protocol PlaneSplitGeometryProviding: AnyObject {
    /// ワールド変換（3D）。
    var worldTransform3D: Matrix4x4 { get }
    /// 変換前の入力境界（取得できない場合は nil）。
    func transform3DInputBounds() -> RectF?
}

/// DrawingEffect の更新失敗。本家では DrawingEffect.Update の例外だけが
/// 診断情報（アイテム型名・エフェクト数・グラフの各ノードの状態）つきで
/// 包まれる（第4章）。連鎖途中の失敗は包まれず、そのまま伝播する。
public enum EffectedItemError: Error {
    case drawingEffectUpdateFailed(
        itemTypeName: String,
        effectCount: Int,
        graphDescription: String,
        underlying: any Error
    )

    /// 本家の包みメッセージと同じ形式の説明文。
    public var message: String {
        switch self {
        case let .drawingEffectUpdateFailed(itemTypeName, effectCount, graphDescription, _):
            return "描画エフェクトの更新に失敗しました。 Item=\(itemTypeName), EffectCount=\(effectCount) \(graphDescription)"
        }
    }
}

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
    /// 対象アイテム。
    public let item: VisualItem

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
        item: VisualItem,
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
        let fadeInFactor = item.fadeIn == 0 ? 1 : min(1, positionSeconds / item.fadeIn)
        let fadeOutFactor = item.fadeOut == 0 ? 1 : min(1, (durationSeconds - positionSeconds) / item.fadeOut)
        let fadeFactor = min(fadeInFactor, fadeOutFactor)
        let zoomValue = item.zoom.value(atFrame: frame, length: duration, fps: fps) / 100
        return DrawDescription(
            draw: Vector3(
                x: item.x.value(atFrame: frame, length: duration, fps: fps) + input.drawingOffset.x,
                y: item.y.value(atFrame: frame, length: duration, fps: fps) + input.drawingOffset.y,
                z: item.z.value(atFrame: frame, length: duration, fps: fps)
            ),
            centerPoint: input.center,
            zoom: Vector2(x: zoomValue, y: zoomValue),
            rotation: Vector3(
                x: 0, y: 0,
                z: item.rotation.value(atFrame: frame, length: duration, fps: fps)
            ),
            camera: .identity,
            zoomInterpolationMode: zoomInterpolationMode,
            opacity: item.opacity.value(atFrame: frame, length: duration, fps: fps) / 100 * fadeFactor,
            invert: item.isInverted,
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
    /// 対象アイテム。
    public let item: VisualItem
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
        item: VisualItem,
        source: any Source,
        targetFactory: any RenderTargetFactory,
        effectProvider: any EffectPairProvider = EmptyEffectPairProvider(),
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
        target.close()
        outputTarget = target

        if applyItemTransform && item.isClippingWithObjectAbove {
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
