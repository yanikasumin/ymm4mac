import XCTest
@testable import YMM4Core

/// FE-R1-042: スライダ表示仕様（本家 `AnimationSliderAttribute` の抽出表、
/// 記述子への解決、フォールバック禁止）の検証。
/// 期待値は抽出データ `slider-attributes.json` の実測値で裏取りした。
final class AnimationSliderSpecTests: XCTestCase {

    // MARK: - 表の完全性

    /// 抽出 1,023 件が全件載り、キーに重複が無いこと。
    /// 同名クラス `DrawingBrushParameterBase` は2つの名前空間に
    /// 別キーとして存在し、仕様値が一致すること（衝突検査の実測）。
    func testTableContainsAllExtractedRecordsWithoutKeyCollision() {
        XCTAssertEqual(AnimationSliderTable.count, 1023)
        let keys = AnimationSliderTable.allKeys
        XCTAssertEqual(Set(keys).count, keys.count)

        let brushDrawing = AnimationSliderTable.spec(
            ownerType: "YukkuriMovieMaker.Brush.DrawingBrushParameterBase",
            property: "X"
        )
        let communityDrawing = AnimationSliderTable.spec(
            ownerType: "YukkuriMovieMaker.Plugin.Community.Brush.DrawingBrushParameterBase",
            property: "X"
        )
        XCTAssertNotNil(brushDrawing)
        XCTAssertEqual(brushDrawing, communityDrawing)
        XCTAssertEqual(brushDrawing?.defaultMin, -500)
        XCTAssertEqual(brushDrawing?.defaultMax, 500)
    }

    /// 単位がリソースキー名のまま未解決の件は、キー名を保持し
    /// `unitIsResourceKey` で判別できること（推測で埋めない）。
    func testResourceKeyUnitStaysMarkedUnresolved() throws {
        let spec = try XCTUnwrap(AnimationSliderTable.spec(
            ownerType: "YukkuriMovieMaker.Plugin.Community.Effect.Audio.InstantLoopAudioEffect.InstantLoopAudioEffect",
            property: "RepeatCount"
        ))
        XCTAssertEqual(spec.unit, "UnitCount")
        XCTAssertTrue(spec.unitIsResourceKey)
        XCTAssertEqual(spec.defaultMin, 0)
        XCTAssertEqual(spec.defaultMax, 100)
        XCTAssertEqual(spec.stringFormat, "F0")
    }

    // MARK: - delta の導出

    /// 本家 `Delta` の導出規則: F<n> → 0.1^n。
    func testDeltaDerivationFromStringFormat() {
        func spec(_ format: String) -> AnimationSliderSpec {
            AnimationSliderSpec(
                defaultMin: 0, defaultMax: 100, stringFormat: format, unit: ""
            )
        }
        XCTAssertEqual(spec("F0").delta, 1, accuracy: 1e-12)
        XCTAssertEqual(spec("F1").delta, 0.1, accuracy: 1e-12)
        XCTAssertEqual(spec("F2").delta, 0.01, accuracy: 1e-12)
        XCTAssertEqual(spec("F4").delta, 0.0001, accuracy: 1e-12)
        // 表の実データでも同じ導出になること（F2 の実例）。
        let f2 = AnimationSliderTable.spec(
            ownerType: "YukkuriMovieMaker.Plugin.Community.Effect.Audio.Growl.GrowlEffect",
            property: "Asymmetry"
        )
        XCTAssertEqual(f2?.delta ?? -1, 0.01, accuracy: 1e-12)
    }

    /// 属性由来の仕様では Delay は常に 0（本家コンストラクタが
    /// 設定しない）。
    func testTableSpecsHaveZeroDelay() {
        let spec = AnimationSliderTable.spec(
            ownerType: "YukkuriMovieMaker.Project.Items.VideoItem", property: "Volume"
        )
        XCTAssertEqual(spec?.delay, 0)
    }

    // MARK: - アイテム記述子への解決

    /// VideoItem の音量: 具象型の宣言（0〜100、F1、単位 %）が表に
    /// あること。記述子経由の解決は FE-R8-001 で追加され、
    /// `PropertyMetadataTests` 側で固定している。
    func testVideoItemVolumeSpecInTable() throws {
        let spec = try XCTUnwrap(AnimationSliderTable.spec(
            ownerType: "YukkuriMovieMaker.Project.Items.VideoItem", property: "Volume"
        ))
        XCTAssertEqual(spec.defaultMin, 0)
        XCTAssertEqual(spec.defaultMax, 100)
        XCTAssertEqual(spec.stringFormat, "F1")
        XCTAssertEqual(spec.unit, "%")
        XCTAssertFalse(spec.unitIsResourceKey)
        XCTAssertEqual(spec.delta, 0.1, accuracy: 1e-12)
    }

    /// VoiceItem の音量は記述子経由でも引けること（0〜100、F1）。
    func testVoiceItemVolumeResolvesViaDescriptors() throws {
        let descriptors = ItemPropertyMetadata.descriptors(for: VoiceItem())
        let volume = try XCTUnwrap(descriptors.first { $0.id == "Volume" })
        let spec = try XCTUnwrap(volume.sliderSpec)
        XCTAssertEqual(spec.defaultMin, 0)
        XCTAssertEqual(spec.defaultMax, 100)
        XCTAssertEqual(spec.stringFormat, "F1")
    }

    /// VoiceItem の音量は単位が全角 ％ で、VideoItem とは別宣言。
    /// 再生速度も具象型ごとに範囲が異なる（VoiceItem は -200〜200、
    /// VideoItem は -100〜100）こと。
    func testVoiceItemResolvesToItsOwnDeclarations() throws {
        let voice = ItemPropertyMetadata.descriptors(for: VoiceItem())
        let volume = try XCTUnwrap(voice.first { $0.id == "Volume" })
        XCTAssertEqual(volume.sliderSpec?.unit, "％")
        let voiceRate = try XCTUnwrap(voice.first { $0.id == "PlaybackRate2" })
        XCTAssertEqual(voiceRate.sliderSpec?.defaultMin, -200)
        XCTAssertEqual(voiceRate.sliderSpec?.defaultMax, 200)

        let video = ItemPropertyMetadata.descriptors(for: VideoItem())
        let videoRate = try XCTUnwrap(video.first { $0.id == "PlaybackRate2" })
        XCTAssertEqual(videoRate.sliderSpec?.defaultMin, -100)
        XCTAssertEqual(videoRate.sliderSpec?.defaultMax, 100)
    }

    /// X 等は本家 `VisualItem` の宣言であり、具象型に無くても
    /// 候補の2番目で引けること。
    func testVisualItemPropertiesResolveViaBaseDeclaration() throws {
        let descriptors = ItemPropertyMetadata.descriptors(for: VideoItem())
        let x = try XCTUnwrap(descriptors.first { $0.id == "X" })
        XCTAssertEqual(x.sliderSpec?.defaultMin, -500)
        XCTAssertEqual(x.sliderSpec?.defaultMax, 500)
        XCTAssertEqual(x.sliderSpec?.unit, "px")
        let opacity = try XCTUnwrap(descriptors.first { $0.id == "Opacity" })
        XCTAssertEqual(opacity.sliderSpec?.defaultMax, 100)
    }

    /// 本家で属性を持たないプロパティ（TextItem の PlaybackRate2 は
    /// 本家 TextItem に再宣言が無く、属性は具象型のみ）では仕様が
    /// 付かず、絶対制限全域へフォールバックしないこと。診断 API が
    /// その id を報告すること。
    func testUndeclaredPropertyGetsNoSpecAndIsReportedUnresolved() throws {
        let item = TextItem()
        let descriptors = ItemPropertyMetadata.descriptors(for: item)
        let rate = try XCTUnwrap(descriptors.first { $0.id == "PlaybackRate2" })
        XCTAssertNil(rate.sliderSpec)

        let candidates = [
            type(of: item).typeName,
            "YukkuriMovieMaker.Project.Items.VisualItem",
            "YukkuriMovieMaker.Project.Items.BaseItem",
        ]
        let unresolved = AnimationSliderTable.unresolvedProperties(
            in: descriptors, ownerCandidates: candidates
        )
        XCTAssertTrue(unresolved.contains("PlaybackRate2"))
        XCTAssertFalse(unresolved.contains("X"))
        XCTAssertFalse(unresolved.contains("FontSize"))
    }

    /// 未登録の所有型・プロパティでは表が nil を返すこと。
    func testUnknownOwnerOrPropertyReturnsNil() {
        XCTAssertNil(AnimationSliderTable.spec(
            ownerType: "YukkuriMovieMaker.Project.Items.VideoItem", property: "NoSuchProperty"
        ))
        XCTAssertNil(AnimationSliderTable.spec(
            ownerType: "Example.UnknownType", property: "Volume"
        ))
    }

    // MARK: - エフェクト記述子への解決

    /// 具象エフェクト定義のプロパティ（ZoomEffect の Zoom）。
    func testEffectPropertyResolvesViaDefinitionType() throws {
        let definition = try XCTUnwrap(VideoEffectRegistry.makeEmptyDefinition(
            typeName: "YukkuriMovieMaker.Project.Effects.ZoomEffect, YukkuriMovieMaker"
        ))
        let descriptors = EffectPropertyMetadata.descriptors(for: definition)
        let zoom = try XCTUnwrap(descriptors.first { $0.id == "Zoom" })
        let spec = try XCTUnwrap(zoom.sliderSpec)
        XCTAssertEqual(spec.defaultMin, 0)
        XCTAssertEqual(spec.defaultMax, 100)
        XCTAssertEqual(spec.stringFormat, "F1")
        XCTAssertEqual(spec.unit, "%")
    }

    /// ブラシ子: ドットの Radius は具象型の宣言、Drawing の X は
    /// 宣言基底 `DrawingBrushParameterBase` の宣言で引けること。
    func testBrushChildrenResolveViaParameterAndBaseTypes() throws {
        let definition = try makeFillBackgroundDefinition()
        let fill = try XCTUnwrap(definition as? FillBackgroundEffectDefinition)
        let brush = Brush()
        brush.type = "YukkuriMovieMaker.Plugin.Brush.DotBrushPlugin, YukkuriMovieMaker"
        brush.parameter = .dot(DotBrushParameter())
        fill.brush = brush

        let brushDescriptor = try topDescriptor(definition, "Brush")
        let radius = try childDescriptor(brushDescriptor, "Radius")
        XCTAssertEqual(radius.sliderSpec?.defaultMin, 0)
        XCTAssertEqual(radius.sliderSpec?.defaultMax, 50)
        XCTAssertEqual(radius.sliderSpec?.stringFormat, "F0")
        XCTAssertEqual(radius.sliderSpec?.unit, "px")

        let drawing = try childDescriptor(brushDescriptor, "Drawing")
        let x = try childDescriptor(drawing, "X")
        XCTAssertEqual(x.sliderSpec?.defaultMin, -500)
        XCTAssertEqual(x.sliderSpec?.defaultMax, 500)
    }

    /// グラデーションメッシュの格子点: 所有型 `GradientMeshPoint`
    /// の宣言（単位 %）で引けること。
    func testGradientMeshPointResolvesViaPointType() throws {
        let definition = try makeFillBackgroundDefinition()
        let fill = try XCTUnwrap(definition as? FillBackgroundEffectDefinition)
        let brush = Brush()
        brush.type = "YukkuriMovieMaker.Plugin.Brush.GradientMeshBrushPlugin, YukkuriMovieMaker"
        brush.parameter = .gradientMesh(GradientMeshBrushParameter())
        fill.brush = brush

        let brushDescriptor = try topDescriptor(definition, "Brush")
        let points = try childDescriptor(brushDescriptor, "Points")
        let firstPoint = try XCTUnwrap(points.collectionElements(at: 0))
        let x = try XCTUnwrap(firstPoint.first { $0.id == "X" })
        XCTAssertEqual(x.sliderSpec?.unit, "%")
        XCTAssertEqual(x.sliderSpec?.defaultMin, -500)
        XCTAssertEqual(x.sliderSpec?.defaultMax, 500)
    }

    /// `ConditionalUnitAnimationSlider` 由来のプロパティ
    /// （LinearGradient の Size）は抽出表の対象外であり、仕様が
    /// 付かないこと。
    func testConditionalUnitPropertyStaysUnresolved() throws {
        let definition = try makeFillBackgroundDefinition()
        let fill = try XCTUnwrap(definition as? FillBackgroundEffectDefinition)
        let brush = Brush()
        brush.type = "YukkuriMovieMaker.Plugin.Brush.LinearGradientBrushPlugin, YukkuriMovieMaker"
        brush.parameter = .linearGradient(LinearGradientBrushParameter())
        fill.brush = brush

        let brushDescriptor = try topDescriptor(definition, "Brush")
        let size = try childDescriptor(brushDescriptor, "Size")
        XCTAssertNil(size.sliderSpec)
        // 同じブラシの Angle（通常の属性）は引ける。
        let angle = try childDescriptor(brushDescriptor, "Angle")
        XCTAssertEqual(angle.sliderSpec?.defaultMin, -360)
        XCTAssertEqual(angle.sliderSpec?.defaultMax, 360)
    }

    // MARK: - ヘルパ

    private func makeFillBackgroundDefinition() throws -> VideoEffectDefinitionBase {
        try XCTUnwrap(VideoEffectRegistry.makeEmptyDefinition(
            typeName: "YukkuriMovieMaker.Project.Effects.FillBackgroundEffect, YukkuriMovieMaker"
        ))
    }

    private func topDescriptor(
        _ definition: VideoEffectDefinitionBase, _ id: String
    ) throws -> PropertyDescriptor {
        try XCTUnwrap(
            EffectPropertyMetadata.descriptors(for: definition).first { $0.id == id }
        )
    }

    private func childDescriptor(
        _ parent: PropertyDescriptor, _ id: String
    ) throws -> PropertyDescriptor {
        try XCTUnwrap(parent.children?.first { $0.id == id })
    }
}
