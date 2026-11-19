import XCTest
@testable import YMM4Core

/// MAC-0029: プロパティメタデータ層の往復検証。
///
/// 記述子の読み書きがモデルの実プロパティと往復すること、アニメーション
/// 付き数値の定数値編集（畳み込みと先頭値のみの書き換え）、列挙の未知
/// メンバ名の保持、エフェクトの「開く→編集→書き戻す」往復を確認する。
final class PropertyMetadataTests: XCTestCase {

    private func descriptor(
        _ descriptors: [PropertyDescriptor], _ id: String
    ) throws -> PropertyDescriptor {
        try XCTUnwrap(descriptors.first { $0.id == id }, "記述子 \(id) が無い")
    }

    /// 音量・パンのスライダ仕様が期待値どおり解決されていること。
    /// 期待値は抽出データ `slider-attributes.json` の実測値（両型とも
    /// Volume は F1・単位 %・0〜100、Pan は F1・単位なし・-100〜100）。
    private func assertAudioSliderSpecs(
        _ descriptors: [PropertyDescriptor], file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let volume = try descriptor(descriptors, "Volume")
        let volumeSpec = try XCTUnwrap(volume.sliderSpec, "Volume の仕様が解決されていない", file: file, line: line)
        XCTAssertEqual(volumeSpec.defaultMin, 0, file: file, line: line)
        XCTAssertEqual(volumeSpec.defaultMax, 100, file: file, line: line)
        XCTAssertEqual(volumeSpec.stringFormat, "F1", file: file, line: line)
        XCTAssertEqual(volumeSpec.unit, "%", file: file, line: line)
        XCTAssertEqual(volumeSpec.delta, 0.1, accuracy: 1e-12, file: file, line: line)

        let pan = try descriptor(descriptors, "Pan")
        let panSpec = try XCTUnwrap(pan.sliderSpec, "Pan の仕様が解決されていない", file: file, line: line)
        XCTAssertEqual(panSpec.defaultMin, -100, file: file, line: line)
        XCTAssertEqual(panSpec.defaultMax, 100, file: file, line: line)
        XCTAssertEqual(panSpec.stringFormat, "F1", file: file, line: line)
        XCTAssertEqual(panSpec.unit, "", file: file, line: line)
    }

    // MARK: - 基本プロパティ（全アイテム共通）

    func testBaseItemDescriptorsRoundTrip() throws {
        let item = TextItem()
        let descriptors = ItemPropertyMetadata.descriptors(for: item)

        let frame = try descriptor(descriptors, "Frame")
        XCTAssertTrue(frame.setIntegerValue(42))
        XCTAssertEqual(item.frame, 42)
        XCTAssertEqual(frame.integerValue, 42)

        let length = try descriptor(descriptors, "Length")
        XCTAssertTrue(length.setIntegerValue(90))
        XCTAssertEqual(item.length, 90)

        let remark = try descriptor(descriptors, "Remark")
        XCTAssertEqual(remark.displayName, "備考")
        XCTAssertTrue(remark.setStringValue("メモ"))
        XCTAssertEqual(item.remark, "メモ")

        let hidden = try descriptor(descriptors, "IsHidden")
        XCTAssertEqual(hidden.displayName, "非表示")
        XCTAssertTrue(hidden.setBoolValue(true))
        XCTAssertTrue(item.isHidden)
    }

    func testDescriptorIDsAreUniquePerItem() {
        for item: BaseItem in [TextItem(), VoiceItem(), ImageItem(), AudioItem(), VideoItem()] {
            let ids = ItemPropertyMetadata.descriptors(for: item).map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, "\(type(of: item)) で ID が重複している")
        }
    }

    // MARK: - アニメーション付き数値

    func testAnimationConstantEditCollapsesToConstant() throws {
        let item = TextItem()
        item.x = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(10), AnimationValue(210)]
        )
        let x = try descriptor(ItemPropertyMetadata.descriptors(for: item), "X")
        XCTAssertEqual(x.displayName, "X")

        XCTAssertTrue(x.setAnimationConstantValue(55))
        XCTAssertEqual(item.x.animationType, .none)
        XCTAssertEqual(item.x.values.count, 1)
        XCTAssertEqual(item.x.firstValue, 55)
        // 定数化したので、どのフレームでも同じ値になる。
        let context = AnimationEvaluationContext(frame: 45, length: 90, fps: 30)
        XCTAssertEqual(context.value(of: item.x), 55)
    }

    func testAnimationFirstValueEditPreservesTypeAndValues() throws {
        let item = TextItem()
        item.opacity = Animation(
            defaultValue: 100, minValue: 0, maxValue: 100,
            animationType: .linear,
            values: [AnimationValue(100), AnimationValue(0)]
        )
        let opacity = try descriptor(ItemPropertyMetadata.descriptors(for: item), "Opacity")
        XCTAssertEqual(opacity.displayName, "不透明度")

        XCTAssertTrue(opacity.setAnimationFirstValue(80))
        XCTAssertEqual(item.opacity.animationType, .linear)
        XCTAssertEqual(item.opacity.values.map(\.value), [80, 0])
    }

    func testAnimationValueIndexEditWritesSecondValue() throws {
        // FE-R13-003: 移動量指定の第2値は記述子のインデックス指定
        // 経路で書く。クランプは呼び出し側が渡す対称範囲が効き、
        // 定義範囲 [0, 100] では負値が 0 へ丸められない。
        let item = TextItem()
        item.x = Animation(
            defaultValue: 0, minValue: 0, maxValue: 100,
            animationType: .movementAmount,
            values: [AnimationValue(10)]
        )
        let x = try descriptor(ItemPropertyMetadata.descriptors(for: item), "X")
        XCTAssertTrue(x.setAnimationValue(-30, atValueIndex: 1, clampRange: -100...100))
        XCTAssertEqual(item.x.values.map(\.value), [10, -30])
        XCTAssertEqual(item.x.animationType, .movementAmount)
    }

    func testAnimationEditClampsToDefinitionRange() throws {
        let item = TextItem()
        let opacity = try descriptor(ItemPropertyMetadata.descriptors(for: item), "Opacity")
        XCTAssertTrue(opacity.setAnimationConstantValue(150))
        XCTAssertEqual(item.opacity.firstValue, 100)
        XCTAssertTrue(opacity.setAnimationConstantValue(-5))
        XCTAssertEqual(item.opacity.firstValue, 0)
    }

    func testAnimationEvaluationContextReadsCurrentFrameValue() throws {
        let item = TextItem()
        item.length = 90
        item.x = Animation(
            defaultValue: 0, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(0), AnimationValue(90)],
            length: 90, videoFPS: 30
        )
        let x = try descriptor(ItemPropertyMetadata.descriptors(for: item), "X")
        let animation = try XCTUnwrap(x.animationValue)
        let context = AnimationEvaluationContext(frame: 45, length: 90, fps: 30)
        XCTAssertEqual(context.value(of: animation), 45, accuracy: 1e-9)
    }

    // MARK: - 数値・真偽・列挙・色

    func testFadeAndBlendRoundTrip() throws {
        let item = TextItem()
        let descriptors = ItemPropertyMetadata.descriptors(for: item)

        let fadeIn = try descriptor(descriptors, "FadeIn")
        XCTAssertEqual(fadeIn.displayName, "フェードイン")
        XCTAssertTrue(fadeIn.setNumberValue(0.5))
        XCTAssertEqual(item.fadeIn, 0.5)
        XCTAssertEqual(fadeIn.numberValue, 0.5)

        let blend = try descriptor(descriptors, "Blend")
        XCTAssertEqual(blend.displayName, "合成モード")
        XCTAssertEqual(blend.stringValue, "Normal")
        XCTAssertTrue(blend.setStringValue("Add"))
        XCTAssertEqual(item.blend, .add)
        // 未知のメンバ名は unknown として保持され、そのまま往復する。
        XCTAssertTrue(blend.setStringValue("FutureBlend"))
        XCTAssertEqual(item.blend, .unknown("FutureBlend"))
        XCTAssertEqual(blend.stringValue, "FutureBlend")

        let inverted = try descriptor(descriptors, "IsInverted")
        XCTAssertTrue(inverted.setBoolValue(true))
        XCTAssertTrue(item.isInverted)
    }

    func testSetNumberValueRejectsNonFiniteValues() throws {
        let item = TextItem()
        let fadeIn = try descriptor(ItemPropertyMetadata.descriptors(for: item), "FadeIn")
        XCTAssertTrue(fadeIn.setNumberValue(0.5))
        XCTAssertEqual(item.fadeIn, 0.5)
        // 非有限値は書き込まれず false を返し、既存値が保持される
        // （FE-R3-118-02。モデルへ入ると保存時に 0.0 へ化ける）。
        XCTAssertFalse(fadeIn.setNumberValue(.nan))
        XCTAssertEqual(item.fadeIn, 0.5)
        XCTAssertFalse(fadeIn.setNumberValue(.infinity))
        XCTAssertEqual(item.fadeIn, 0.5)
        XCTAssertFalse(fadeIn.setNumberValue(-.infinity))
        XCTAssertEqual(item.fadeIn, 0.5)
        // 有限値の通常動作は変わらない。
        XCTAssertTrue(fadeIn.setNumberValue(0.75))
        XCTAssertEqual(item.fadeIn, 0.75)
    }

    func testKindMismatchReturnsNilAndFalse() throws {
        let item = TextItem()
        let frame = try descriptor(ItemPropertyMetadata.descriptors(for: item), "Frame")
        XCTAssertNil(frame.numberValue)
        XCTAssertFalse(frame.setBoolValue(true))
        XCTAssertNil(frame.animationValue)
    }

    // MARK: - TextItem 固有

    func testTextItemSpecificDescriptors() throws {
        let item = TextItem()
        let descriptors = ItemPropertyMetadata.descriptors(for: item)

        let text = try descriptor(descriptors, "Text")
        XCTAssertEqual(text.displayName, "テキスト")
        guard case .text(let multiline) = text.kind else {
            return XCTFail("Text は文字列型のはず")
        }
        XCTAssertTrue(multiline)
        XCTAssertTrue(text.setStringValue("こんにちは"))
        XCTAssertEqual(item.text, "こんにちは")

        let font = try descriptor(descriptors, "Font")
        XCTAssertTrue(font.setStringValue("Hiragino Sans"))
        XCTAssertEqual(item.appearance.font, "Hiragino Sans")

        let fontSize = try descriptor(descriptors, "FontSize")
        XCTAssertEqual(fontSize.displayName, "サイズ")
        XCTAssertTrue(fontSize.setAnimationConstantValue(48))
        XCTAssertEqual(item.appearance.fontSize.firstValue, 48)

        let fontColor = try descriptor(descriptors, "FontColor")
        let red = Color(alpha: 255, red: 255, green: 0, blue: 0)
        XCTAssertTrue(fontColor.setColorValue(red))
        XCTAssertEqual(item.appearance.fontColor, red)
        XCTAssertEqual(fontColor.colorValue, red)

        let wordWrap = try descriptor(descriptors, "WordWrap")
        XCTAssertTrue(wordWrap.setStringValue("Character"))
        XCTAssertEqual(item.appearance.wordWrap, .character)

        let basePoint = try descriptor(descriptors, "BasePoint")
        XCTAssertTrue(basePoint.setStringValue("CenterCenter"))
        XCTAssertEqual(item.appearance.basePoint, .centerCenter)

        let bold = try descriptor(descriptors, "Bold")
        XCTAssertTrue(bold.setBoolValue(true))
        XCTAssertTrue(item.appearance.bold)
    }

    // MARK: - VoiceItem（字幕側の映像プロパティと音声）

    func testVoiceItemDescriptorsTargetJimakuAndAudio() throws {
        let item = VoiceItem()
        let descriptors = ItemPropertyMetadata.descriptors(for: item)

        let serif = try descriptor(descriptors, "Serif")
        XCTAssertEqual(serif.displayName, "セリフ")
        XCTAssertTrue(serif.setStringValue("セリフです"))
        XCTAssertEqual(item.serif, "セリフです")

        let volume = try descriptor(descriptors, "Volume")
        XCTAssertTrue(volume.setAnimationConstantValue(80))
        XCTAssertEqual(item.volume.firstValue, 80)

        // 字幕側の X は VoiceItem 自身の保持値（JimakuX）を指す。
        let jimakuX = try descriptor(descriptors, "JimakuX")
        XCTAssertTrue(jimakuX.setAnimationConstantValue(120))
        XCTAssertEqual(item.x.firstValue, 120)

        let visibility = try descriptor(descriptors, "JimakuVisibility")
        XCTAssertTrue(visibility.setStringValue("Custom"))
        XCTAssertEqual(item.jimakuVisibility, .custom)
    }

    // MARK: - VideoItem / AudioItem の音声プロパティ（FE-R8-001）

    /// VideoItem に音量・パンの記述子があり、モデルの保持値と往復し、
    /// スライダ仕様が具象型（VideoItem）の宣言で解決されること。
    func testVideoItemVolumePanDescriptors() throws {
        let item = VideoItem()
        let descriptors = ItemPropertyMetadata.descriptors(for: item)

        let volume = try descriptor(descriptors, "Volume")
        XCTAssertEqual(volume.displayName, "音量")
        XCTAssertEqual(volume.group, "音声")
        XCTAssertTrue(volume.setAnimationConstantValue(80))
        XCTAssertEqual(item.volume.firstValue, 80)
        XCTAssertEqual(volume.animationValue?.firstValue, 80)

        let pan = try descriptor(descriptors, "Pan")
        XCTAssertEqual(pan.displayName, "パン")
        XCTAssertEqual(pan.group, "音声")
        XCTAssertTrue(pan.setAnimationConstantValue(-30))
        XCTAssertEqual(item.pan.firstValue, -30)
        XCTAssertEqual(pan.animationValue?.firstValue, -30)

        try assertAudioSliderSpecs(descriptors)
    }

    /// AudioItem も同様に音量・パンが編集でき、スライダ仕様が
    /// 具象型（AudioItem）の宣言で解決されること。
    func testAudioItemVolumePanDescriptors() throws {
        let item = AudioItem()
        let descriptors = ItemPropertyMetadata.descriptors(for: item)

        let volume = try descriptor(descriptors, "Volume")
        XCTAssertEqual(volume.displayName, "音量")
        XCTAssertEqual(volume.group, "音声")
        XCTAssertTrue(volume.setAnimationConstantValue(65))
        XCTAssertEqual(item.volume.firstValue, 65)
        XCTAssertEqual(volume.animationValue?.firstValue, 65)

        let pan = try descriptor(descriptors, "Pan")
        XCTAssertEqual(pan.displayName, "パン")
        XCTAssertEqual(pan.group, "音声")
        XCTAssertTrue(pan.setAnimationConstantValue(45))
        XCTAssertEqual(item.pan.firstValue, 45)
        XCTAssertEqual(pan.animationValue?.firstValue, 45)

        try assertAudioSliderSpecs(descriptors)
    }

    // MARK: - グループ化

    func testSectionsPreserveGroupOrder() {
        let item = TextItem()
        let sections = PropertyMetadata.sections(
            from: ItemPropertyMetadata.descriptors(for: item)
        )
        XCTAssertEqual(sections.map(\.name), ["基本", "描画", "テキスト", "フォント"])
        let draw = sections.first { $0.name == "描画" }
        XCTAssertEqual(draw?.descriptors.count, 13)
    }

    // MARK: - エフェクト

    func testZoomEffectDescriptorsRoundTrip() throws {
        let definition = ZoomEffectDefinition()
        let descriptors = EffectPropertyMetadata.descriptors(for: definition)

        let zoom = try descriptor(descriptors, "Zoom")
        XCTAssertEqual(zoom.displayName, "全体")
        XCTAssertTrue(zoom.setAnimationConstantValue(150))
        XCTAssertEqual(definition.zoom.firstValue, 150)

        let nearest = try descriptor(descriptors, "IsNearestNeighbor")
        XCTAssertEqual(nearest.displayName, "ドット絵")
        XCTAssertTrue(nearest.setBoolValue(true))
        XCTAssertTrue(definition.isNearestNeighbor)

        let enabled = try descriptor(descriptors, "IsEnabled")
        XCTAssertTrue(enabled.setBoolValue(false))
        XCTAssertFalse(definition.isEnabled)
    }

    func testEffectEditingBridgeWritesBackIntoItem() throws {
        let item = TextItem()
        let source = ZoomEffectDefinition()
        source.zoom.setFirstValue(200)
        item.videoEffects = [VideoEffectRegistry.encode(source)]

        let opened = try XCTUnwrap(EffectPropertyEditing.openDefinition(for: item, at: 0))
        let zoomEffect = try XCTUnwrap(opened as? ZoomEffectDefinition)
        XCTAssertEqual(zoomEffect.zoom.firstValue, 200)

        let zoom = try descriptor(EffectPropertyMetadata.descriptors(for: zoomEffect), "Zoom")
        XCTAssertTrue(zoom.setAnimationConstantValue(300))
        XCTAssertTrue(EffectPropertyEditing.writeBack(zoomEffect, for: item, at: 0))

        // 書き戻した保持列を再度開くと、編集が反映されている。
        let reopened = try XCTUnwrap(
            EffectPropertyEditing.openDefinition(for: item, at: 0) as? ZoomEffectDefinition
        )
        XCTAssertEqual(reopened.zoom.firstValue, 300)
        // 保存形式（.ymmp のエンコード）にも編集が乗る。
        let encoded = YmmpCodec.encode(makeProject(with: item))
        XCTAssertTrue(encoded.contains("300"))
    }

    // MARK: - エフェクト編集時の入れ子未知フィールド保持（UI29-01 / MAC-0032）

    /// 既知エフェクト（ZoomEffect）の各階層に未知キーを仕込んだプロジェクト。
    /// 仕込み位置: エフェクトのトップレベル、Zoom（Animation）の内部、
    /// Bezier の内部。Animation と Bezier の内部は型付きコーデックが
    /// 読み落とすため、修正前は編集の書き戻しで消えていた。
    private func projectTextWithUnknownNestedEffectFields() -> String {
        """
        {"Timelines":[{"Name":"","Items":[{"$type":"YukkuriMovieMaker.Project.Items.TextItem, YukkuriMovieMaker","Frame":0,"Layer":0,"Length":30,"VideoEffects":[{"$type":"YukkuriMovieMaker.Project.Effects.ZoomEffect, YukkuriMovieMaker","Zoom":{"Values":[{"Value":150.0}],"Span":0.0,"AnimationType":"なし","Bezier":{"Points":[],"IsQuadratic":false,"FutureBezierKey":42},"FutureAnimationKey":"keep-me","FutureNested":{"Inner":[1,2,3]}},"ZoomX":{"Values":[{"Value":100.0}],"Span":0.0,"AnimationType":"なし","Bezier":{"Points":[],"IsQuadratic":false}},"ZoomY":{"Values":[{"Value":100.0}],"Span":0.0,"AnimationType":"なし","Bezier":{"Points":[],"IsQuadratic":false}},"IsNearestNeighbor":false,"IsEnabled":true,"FutureTopLevel":{"Note":"top"}}]}]}]}
        """
    }

    private func assertUnknownNestedFieldsSurvive(
        in effect: JSONValue, file: StaticString = #filePath, line: UInt = #line
    ) {
        // トップレベル（定義の additionalFields 経由で従来から保持される）。
        XCTAssertEqual(
            effect.field("FutureTopLevel")?.field("Note")?.stringValue, "top",
            file: file, line: line
        )
        // Animation の内部（型付きコーデックが読み落とす階層）。
        let zoom = effect.field("Zoom")
        XCTAssertEqual(
            zoom?.field("FutureAnimationKey")?.stringValue, "keep-me",
            file: file, line: line
        )
        XCTAssertEqual(
            zoom?.field("FutureNested")?.field("Inner"),
            .array([.number(1), .number(2), .number(3)]),
            file: file, line: line
        )
        // Bezier の内部（さらに深い階層）。
        XCTAssertEqual(
            zoom?.field("Bezier")?.field("FutureBezierKey")?.intValue, 42,
            file: file, line: line
        )
    }

    func testEffectEditPreservesUnknownNestedFields() throws {
        let (project, _) = try YmmpCodec.decode(projectTextWithUnknownNestedEffectFields())
        let item = try XCTUnwrap(project.timelines.first?.items.first as? TextItem)

        // 編集は IsEnabled の1項目だけ（UI29-01 の再現条件）。
        let opened = try XCTUnwrap(EffectPropertyEditing.openDefinition(for: item, at: 0))
        let enabled = try descriptor(EffectPropertyMetadata.descriptors(for: opened), "IsEnabled")
        XCTAssertTrue(enabled.setBoolValue(false))
        XCTAssertTrue(EffectPropertyEditing.writeBack(opened, for: item, at: 0))

        // 書き戻し直後の保持列で、未知キーが全階層に残り、編集も反映される。
        assertUnknownNestedFieldsSurvive(in: item.videoEffects[0].value)
        XCTAssertEqual(item.videoEffects[0].value.field("IsEnabled")?.boolValue, false)

        // 保存 → 再読み込みでも残る。
        let saved = YmmpCodec.encode(project)
        let (reloaded, _) = try YmmpCodec.decode(saved)
        let reloadedItem = try XCTUnwrap(reloaded.timelines.first?.items.first as? TextItem)
        assertUnknownNestedFieldsSurvive(in: reloadedItem.videoEffects[0].value)
        XCTAssertEqual(reloadedItem.videoEffects[0].value.field("IsEnabled")?.boolValue, false)

        // 編集していない既知の値は元のまま。
        let reopened = try XCTUnwrap(
            EffectPropertyEditing.openDefinition(for: reloadedItem, at: 0) as? ZoomEffectDefinition
        )
        XCTAssertEqual(reopened.zoom.firstValue, 150)
    }

    func testEffectEditInsideAnimationPreservesUnknownKeysInSameField() throws {
        let (project, _) = try YmmpCodec.decode(projectTextWithUnknownNestedEffectFields())
        let item = try XCTUnwrap(project.timelines.first?.items.first as? TextItem)

        // 未知キーを含む Animation 自体（Zoom）を編集しても、同じ
        // オブジェクト内の未知キーは再帰マージで保持される。
        let opened = try XCTUnwrap(
            EffectPropertyEditing.openDefinition(for: item, at: 0) as? ZoomEffectDefinition
        )
        let zoom = try descriptor(EffectPropertyMetadata.descriptors(for: opened), "Zoom")
        XCTAssertTrue(zoom.setAnimationConstantValue(300))
        XCTAssertTrue(EffectPropertyEditing.writeBack(opened, for: item, at: 0))

        assertUnknownNestedFieldsSurvive(in: item.videoEffects[0].value)
        XCTAssertEqual(
            item.videoEffects[0].value.field("Zoom")?.field("Values")?
                .arrayValue?.first?.field("Value")?.doubleValue,
            300
        )
    }

    func testUneditedProjectWithUnknownNestedFieldsRoundTripsToFixedPoint() throws {
        // 無編集の往復は従来どおり固定点であり、未知キーも生保持のまま残る
        // （修正が通常の読み込み・保存経路を変えていないことの回帰）。
        let (project, _) = try YmmpCodec.decode(projectTextWithUnknownNestedEffectFields())
        let first = YmmpCodec.encode(project)
        let (reloaded, _) = try YmmpCodec.decode(first)
        let second = YmmpCodec.encode(reloaded)
        XCTAssertEqual(first, second)
        let item = try XCTUnwrap(reloaded.timelines.first?.items.first as? TextItem)
        assertUnknownNestedFieldsSurvive(in: item.videoEffects[0].value)
    }

    func testEffectEditingBridgeRejectsUnknownAndOutOfRange() {
        let item = TextItem()
        item.videoEffects = [PreservedObject(.object([
            (key: "$type", value: .string("SomeCommunity.Effect, SomePlugin")),
            (key: "Value", value: .number(1)),
        ]))]
        XCTAssertNil(EffectPropertyEditing.openDefinition(for: item, at: 0))
        XCTAssertNil(EffectPropertyEditing.openDefinition(for: item, at: 5))
        // 未知の型は生保持のまま失われない。
        XCTAssertEqual(EffectPropertyEditing.effectList(for: item)?.count, 1)
        XCTAssertNil(EffectPropertyEditing.effectList(for: AudioItem()))
    }

    // MARK: - ファイル参照（FE-R1-043）

    /// R2-B01 対応: 動画・音声・画像の各アイテムに filePath 種別の
    /// FilePath 記述子があり、パスの読み書きがモデルへ届く。
    /// 種別は .text ではなく .filePath で、対象種別とサムネイル
    /// 表示の有無は本家の FileSelector 属性どおり。
    func testFilePathDescriptorsForMediaItems() throws {
        let video = VideoItem()
        let videoDescriptor = try descriptor(
            ItemPropertyMetadata.descriptors(for: video), "FilePath"
        )
        XCTAssertEqual(
            videoDescriptor.kind, .filePath(group: .video, showsThumbnail: true)
        )
        XCTAssertEqual(videoDescriptor.filePathSpec?.group, .video)
        XCTAssertEqual(videoDescriptor.filePathSpec?.showsThumbnail, true)

        let audio = AudioItem()
        let audioDescriptor = try descriptor(
            ItemPropertyMetadata.descriptors(for: audio), "FilePath"
        )
        XCTAssertEqual(
            audioDescriptor.kind, .filePath(group: .audio, showsThumbnail: false)
        )

        let image = ImageItem()
        let imageDescriptor = try descriptor(
            ItemPropertyMetadata.descriptors(for: image), "FilePath"
        )
        XCTAssertEqual(
            imageDescriptor.kind, .filePath(group: .image, showsThumbnail: true)
        )

        // テキストアイテムにはファイル参照は付かない。
        let textDescriptors = ItemPropertyMetadata.descriptors(for: TextItem())
        XCTAssertNil(textDescriptors.first { $0.id == "FilePath" })
    }

    /// R2-B04 対応: 相対パスは絶対化されず、そのまま読み書きされる
    /// （解決は供給層がプロジェクト位置を基準に行う）。
    /// setter はパスの保持だけで、長さや素材情報には触らない。
    func testFilePathRoundTripsVerbatimWithoutTouchingLength() throws {
        let item = AudioItem()
        item.length = 123
        let path = try descriptor(
            ItemPropertyMetadata.descriptors(for: item), "FilePath"
        )
        XCTAssertTrue(path.setStringValue("素材/音声.wav"))
        XCTAssertEqual(item.filePath, "素材/音声.wav")
        XCTAssertEqual(path.stringValue, "素材/音声.wav")
        XCTAssertEqual(item.length, 123)
        XCTAssertEqual(item.contentLength, .zero)
        XCTAssertEqual(item.originalContentLength, .zero)
    }

    private func makeProject(with item: BaseItem) -> Project {
        let timeline = Timeline()
        timeline.items = [item]
        let project = Project()
        project.timelines = [timeline]
        return project
    }
}
