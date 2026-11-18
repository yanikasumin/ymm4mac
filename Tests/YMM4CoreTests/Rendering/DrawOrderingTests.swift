import XCTest
@testable import YMM4Core

// MARK: - 偽の実装（Source 契約の検証用）

private final class FakePlaneSplitOrdering: PlaneSplitOrdering {
    var requiresResult = true
    var sortResult: [PlaneSplitFragment]?
    private(set) var sortCallCount = 0

    func requiresOrdering(_ a: [Vector3], _ b: [Vector3]) -> Bool {
        requiresResult
    }

    func sort(quads: [[Vector3]]) -> [PlaneSplitFragment]? {
        sortCallCount += 1
        return sortResult
    }
}

// MARK: - 描画順序とセグメント構築

final class DrawOrderingTests: XCTestCase {

    private func makeDescription(z: Double) -> DrawDescription {
        var description = DrawDescription.empty
        description.draw = Vector3(x: 0, y: 0, z: z)
        return description
    }

    private func makeResource(
        layer: Int,
        alwaysOnTop: Bool = false,
        zOrderEnabled: Bool = true,
        isFrameBufferSource: Bool = false,
        descriptions: [DrawDescription] = [],
        quad: [Vector3]? = nil
    ) -> OrderedDrawResource {
        let item = TextItem()
        item.layer = layer
        return OrderedDrawResource(
            item: item,
            alwaysOnTop: alwaysOnTop,
            zOrderEnabled: zOrderEnabled,
            layer: layer,
            isFrameBufferSource: isFrameBufferSource,
            drawDescriptions: descriptions,
            planeSplitQuad: quad
        )
    }

    private func sampleQuad() -> [Vector3] {
        [
            Vector3(x: 0, y: 0, z: 0),
            Vector3(x: 100, y: 0, z: 0),
            Vector3(x: 100, y: 50, z: 0),
            Vector3(x: 0, y: 50, z: 0),
        ]
    }

    func testZIndexFromTranslation() {
        // 原点 → 平行移動 z=100 → 透視（w = 1 - 0.001z）で 100 / 0.9。
        let z = DrawOrdering.zIndex(of: [makeDescription(z: 100)])
        XCTAssertEqual(z, 100.0 / 0.9, accuracy: 1e-9)
    }

    func testZIndexIsMaxAndEmptyIsZero() {
        XCTAssertEqual(DrawOrdering.zIndex(of: []), 0)
        let z = DrawOrdering.zIndex(of: [makeDescription(z: 10), makeDescription(z: 100)])
        XCTAssertEqual(z, 100.0 / 0.9, accuracy: 1e-9)
    }

    func testZIndexIgnoresRotationAndInvertAtOrigin() {
        var rotated = makeDescription(z: 100)
        rotated.rotation = Vector3(x: 30, y: 45, z: 90)
        rotated.invert = true
        XCTAssertEqual(DrawOrdering.zIndex(of: [rotated]), 100.0 / 0.9, accuracy: 1e-9)
    }

    func testZIndexAppliesCamera() {
        var description = makeDescription(z: 100)
        description.camera = .createTranslation(x: 0, y: 0, z: 50)
        // (100 + 50) / (1 - 0.001 * 150)
        XCTAssertEqual(DrawOrdering.zIndex(of: [description]), 150.0 / 0.85, accuracy: 1e-9)
    }

    func testOrderingThreeKeys() {
        // キー: AlwaysOnTop（後ろ）→ ZIndex → Layer。同キーは入力順を保持。
        let a = makeResource(layer: 3, descriptions: [makeDescription(z: 0)])
        let b = makeResource(layer: 1, descriptions: [makeDescription(z: 0)])
        let c = makeResource(layer: 9, descriptions: [makeDescription(z: 50)])
        let d = makeResource(layer: 0, alwaysOnTop: true, descriptions: [makeDescription(z: -100)])
        // ZOrder 無効は Z が大きくても 0 として扱われる。
        let e = makeResource(layer: 2, zOrderEnabled: false, descriptions: [makeDescription(z: 500)])

        let ordered = DrawOrdering.ordered([a, b, c, d, e])
        XCTAssertEqual(ordered.map { $0.layer }, [1, 2, 3, 9, 0])
    }

    func testPlaneSplitQuadIdentity() {
        let quad = DrawOrdering.planeSplitQuad(outputs: [
            PlaneSplitOutputGeometry(
                worldTransform: .identity,
                inputBounds: RectF(left: 0, top: 0, right: 100, bottom: 50)
            ),
        ])
        XCTAssertEqual(quad, sampleQuad())
    }

    func testPlaneSplitQuadUnionsBoundsAcrossOutputs() {
        let quad = DrawOrdering.planeSplitQuad(outputs: [
            PlaneSplitOutputGeometry(
                worldTransform: .identity,
                inputBounds: RectF(left: 0, top: 0, right: 50, bottom: 50)
            ),
            PlaneSplitOutputGeometry(
                worldTransform: .identity,
                inputBounds: RectF(left: 50, top: 0, right: 100, bottom: 50)
            ),
        ])
        XCTAssertEqual(quad, sampleQuad())
    }

    func testPlaneSplitQuadNilCases() {
        // 出力0件。
        XCTAssertNil(DrawOrdering.planeSplitQuad(outputs: []))
        // ワールド変換なし。
        XCTAssertNil(DrawOrdering.planeSplitQuad(outputs: [
            PlaneSplitOutputGeometry(
                worldTransform: nil,
                inputBounds: RectF(left: 0, top: 0, right: 100, bottom: 50)
            ),
        ]))
        // 出力間で変換が一致しない。
        XCTAssertNil(DrawOrdering.planeSplitQuad(outputs: [
            PlaneSplitOutputGeometry(
                worldTransform: .identity,
                inputBounds: RectF(left: 0, top: 0, right: 50, bottom: 50)
            ),
            PlaneSplitOutputGeometry(
                worldTransform: .createTranslation(x: 1, y: 0, z: 0),
                inputBounds: RectF(left: 50, top: 0, right: 100, bottom: 50)
            ),
        ]))
        // 入力境界が取れない。
        XCTAssertNil(DrawOrdering.planeSplitQuad(outputs: [
            PlaneSplitOutputGeometry(worldTransform: .identity, inputBounds: nil),
        ]))
        // 統合した境界が空。
        XCTAssertNil(DrawOrdering.planeSplitQuad(outputs: [
            PlaneSplitOutputGeometry(
                worldTransform: .identity,
                inputBounds: RectF(left: 10, top: 0, right: 10, bottom: 50)
            ),
        ]))
        // 変換後の Z が 999 を超える。
        XCTAssertNil(DrawOrdering.planeSplitQuad(outputs: [
            PlaneSplitOutputGeometry(
                worldTransform: .createTranslation(x: 0, y: 0, z: 1000),
                inputBounds: RectF(left: 0, top: 0, right: 100, bottom: 50)
            ),
        ]))
        // 変換で潰れて平面をなさない。
        XCTAssertNil(DrawOrdering.planeSplitQuad(outputs: [
            PlaneSplitOutputGeometry(
                worldTransform: .createScale(x: 0, y: 0, z: 1, center: .zero),
                inputBounds: RectF(left: 0, top: 0, right: 100, bottom: 50)
            ),
        ]))
    }

    func testSegmentBuilderNonJoinableBecomesSingle() {
        let builder = DrawSegmentBuilder()
        let disabled = makeResource(layer: 0, zOrderEnabled: false, quad: sampleQuad())
        let frameBuffer = makeResource(layer: 1, isFrameBufferSource: true, quad: sampleQuad())
        let segments = builder.buildSegments(from: [disabled, frameBuffer])
        XCTAssertEqual(segments.count, 2)
        for segment in segments {
            guard case .single = segment else {
                return XCTFail("単独描画になるはず")
            }
        }
    }

    func testSegmentBuilderFallsBackToSequentialWithNullOrdering() {
        let builder = DrawSegmentBuilder()
        let resources = (0..<3).map { makeResource(layer: $0, quad: sampleQuad()) }
        let segments = builder.buildSegments(from: resources)
        XCTAssertEqual(segments.count, 3)
        for segment in segments {
            guard case .single = segment else {
                return XCTFail("BSP 未実装では逐次描画へフォールバックするはず")
            }
        }
    }

    func testSegmentBuilderPlaneSplitWithFakeOrdering() {
        let ordering = FakePlaneSplitOrdering()
        ordering.sortResult = [
            PlaneSplitFragment(resourceIndex: 0, vertices: [], cuts: []),
            PlaneSplitFragment(resourceIndex: 1, vertices: [], cuts: [PlaneSplitCut(a: .zero, b: .zero)]),
        ]
        let builder = DrawSegmentBuilder(ordering: ordering)
        let resources = (0..<2).map { makeResource(layer: $0, quad: sampleQuad()) }
        let segments = builder.buildSegments(from: resources)
        XCTAssertEqual(segments.count, 1)
        guard case .planeSplit(let run, let fragments) = segments[0] else {
            return XCTFail("平面分割セグメントになるはず")
        }
        XCTAssertEqual(run.count, 2)
        XCTAssertEqual(fragments.count, 2)
        XCTAssertEqual(ordering.sortCallCount, 1)
    }

    func testSegmentBuilderSortNilFallsBack() {
        let ordering = FakePlaneSplitOrdering()
        ordering.sortResult = nil
        let builder = DrawSegmentBuilder(ordering: ordering)
        let resources = (0..<2).map { makeResource(layer: $0, quad: sampleQuad()) }
        let segments = builder.buildSegments(from: resources)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(ordering.sortCallCount, 1)
    }

    func testSegmentBuilderRequiresOrderingFalseSkipsSort() {
        let ordering = FakePlaneSplitOrdering()
        ordering.requiresResult = false
        let builder = DrawSegmentBuilder(ordering: ordering)
        let resources = (0..<2).map { makeResource(layer: $0, quad: sampleQuad()) }
        let segments = builder.buildSegments(from: resources)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(ordering.sortCallCount, 0)
    }

    func testSegmentBuilderSplitsRunAtNilQuad() {
        let ordering = FakePlaneSplitOrdering()
        ordering.sortResult = [
            PlaneSplitFragment(resourceIndex: 0, vertices: [], cuts: []),
            PlaneSplitFragment(resourceIndex: 1, vertices: [], cuts: []),
        ]
        let builder = DrawSegmentBuilder(ordering: ordering)
        let resources = [
            makeResource(layer: 0, quad: sampleQuad()),
            makeResource(layer: 1, quad: sampleQuad()),
            makeResource(layer: 2, quad: nil),
            makeResource(layer: 3, quad: sampleQuad()),
            makeResource(layer: 4, quad: sampleQuad()),
        ]
        let segments = builder.buildSegments(from: resources)
        XCTAssertEqual(segments.count, 3)
        guard case .planeSplit(let firstRun, _) = segments[0],
              case .single(let middle) = segments[1],
              case .planeSplit(let lastRun, _) = segments[2]
        else {
            return XCTFail("平面分割・単独・平面分割の列になるはず")
        }
        XCTAssertEqual(firstRun.map { $0.layer }, [0, 1])
        XCTAssertEqual(middle.layer, 2)
        XCTAssertEqual(lastRun.map { $0.layer }, [3, 4])
    }

    func testSegmentBuilderRunBrokenByAlwaysOnTopChange() {
        let ordering = FakePlaneSplitOrdering()
        ordering.sortResult = [
            PlaneSplitFragment(resourceIndex: 0, vertices: [], cuts: []),
            PlaneSplitFragment(resourceIndex: 1, vertices: [], cuts: []),
        ]
        let builder = DrawSegmentBuilder(ordering: ordering)
        let resources = [
            makeResource(layer: 0, alwaysOnTop: false, quad: sampleQuad()),
            makeResource(layer: 1, alwaysOnTop: true, quad: sampleQuad()),
        ]
        let segments = builder.buildSegments(from: resources)
        // IsAlwaysOnTop が変わるためランは分かれ、それぞれ1件で単独描画。
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(ordering.sortCallCount, 0)
    }
}
