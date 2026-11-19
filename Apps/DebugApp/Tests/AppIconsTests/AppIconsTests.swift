import XCTest
@testable import AppIcons

/// MDI アイコン基盤の検証。
///
/// 採用した全アイコンについて「パスが解釈できる・空でない・
/// 24×24 キャンバスに収まる」を固定する。あわせて、画面の差し込み口が
/// 参照する名前（辞書＋合成）がすべて解決できることも固定し、
/// アイコンの追加・差し替えで欠けが出たらここで落ちるようにする。
final class AppIconsTests: XCTestCase {

    /// 画面の差し込み口が参照する合成アイコン以外の名前は、
    /// すべて辞書に存在しなければならない（呼び出し側の正本は
    /// ProjectView / WorkspaceState 等。ここは欠け検出のための写し）。
    private let requiredDictionaryNames: [String] = [
        // アイテム種別
        "message-text-outline", "format-text", "video", "music", "image",
        "shape-plus", "account", "emoticon-outline", "image-auto-adjust",
        "gradient-horizontal", "chart-timeline", "image-multiple",
        "select-group", "book",
        // トランスポート
        "play", "pause", "stop", "fit-to-page", "skip-previous",
        "step-backward-2", "step-backward", "step-forward",
        "step-forward-2", "skip-next", "volume-high", "volume-off",
        "vector-bezier",
        // ツールバー・その他画面
        "magnify", "fit-to-screen", "history", "undo", "redo",
        "content-cut", "content-copy", "content-paste",
        "paper-cut-vertical", "group", "ungroup", "lock",
        "lock-open-outline", "waveform", "grid", "delete",
        "delete-sweep", "contain-start", "contain-end", "select-all",
        "chevron-down", "chevron-right", "altimeter", "file-plus",
        "folder-open", "content-save", "animation-play", "camera",
        "message-alert-outline", "plus", "minus-circle", "eye",
        "eye-off", "dots-vertical", "account-edit",
        // 合成アイコンの素材
        "rotate-left", "vector-difference-ab", "file-outline", "filmstrip",
    ]

    func testRequiredIconsExistInDictionary() {
        for name in requiredDictionaryNames {
            XCTAssertNotNil(
                MDIIconPaths.paths[name],
                "辞書に必要なアイコンが無い: \(name)")
        }
    }

    func testCompositesResolve() {
        for name in MDIIconLayers.compositeNames {
            let layers = MDIIconLayers.layers(for: name)
            XCTAssertNotNil(layers, "合成アイコンが解決できない: \(name)")
            XCTAssertFalse(layers?.isEmpty ?? true)
        }
        // 未知の名前は nil（空描画）になる。
        XCTAssertNil(MDIIconLayers.layers(for: "no-such-icon"))
    }

    func testAllAdoptedIconsParseToNonEmptyPathWithinCanvas() {
        // 円弧のベジェ近似は曲線上の点で最大 0.1 程度ずれる。
        // 制御点ではなくサンプリング点で判定するため、余裕は 0.6。
        let tolerance: CGFloat = 0.6
        for (name, d) in MDIIconPaths.paths {
            let segments = SVGPathParser.segments(from: d)
            XCTAssertFalse(segments.isEmpty, "解釈できない: \(name)")
            let points = SVGPathParser.flattenedPoints(from: d)
            XCTAssertGreaterThan(points.count, 2, "点が取れない: \(name)")
            for p in points {
                XCTAssertTrue(p.x.isFinite && p.y.isFinite,
                              "非有限の点: \(name) \(p)")
                XCTAssertGreaterThanOrEqual(p.x, -tolerance,
                                            "キャンバス左端のはみ出し: \(name) \(p)")
                XCTAssertLessThanOrEqual(p.x, 24 + tolerance,
                                         "キャンバス右端のはみ出し: \(name) \(p)")
                XCTAssertGreaterThanOrEqual(p.y, -tolerance,
                                            "キャンバス上端のはみ出し: \(name) \(p)")
                XCTAssertLessThanOrEqual(p.y, 24 + tolerance,
                                         "キャンバス下端のはみ出し: \(name) \(p)")
            }
            // 塗り面積のある図形になっていること（外接矩形が潰れていない）。
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            XCTAssertGreaterThan((xs.max()! - xs.min()!), 0.5,
                                 "横幅が潰れている: \(name)")
            XCTAssertGreaterThan((ys.max()! - ys.min()!), 0.5,
                                 "縦幅が潰れている: \(name)")
            // Shape としても空でないこと。
            let path = MDIIconShape(name: name)
                .path(in: CGRect(x: 0, y: 0, width: 24, height: 24))
            XCTAssertFalse(path.isEmpty, "Shape が空: \(name)")
        }
    }

    func testArcIconsAreIncludedAndParse() {
        // 採用集合には円弧（A）を使うアイコンが多数含まれる
        // （account、emoticon-outline 等）。解釈できていることを固定する。
        let arcIcons = MDIIconPaths.paths.filter { $0.value.contains("A") }
        XCTAssertGreaterThanOrEqual(arcIcons.count, 10)
        for (name, d) in arcIcons {
            let points = SVGPathParser.flattenedPoints(from: d)
            XCTAssertGreaterThan(points.count, 10, "円弧アイコンの解釈: \(name)")
        }
    }

    func testArcConversionAccuracy() {
        // 中心 (12,12)・半径 10 の半円。端点→中心変換と近似の誤差が
        // 小さいことを、円周上の点との距離で固定する。
        let half = SVGPathParser.flattenedPoints(
            from: "M2,12 A10,10 0 1,1 22,12")
        XCTAssertGreaterThan(half.count, 10)
        for p in half {
            let distance = hypot(p.x - 12, p.y - 12)
            XCTAssertEqual(distance, 10, accuracy: 0.2,
                           "半円の点が円周から外れた: \(p)")
        }
        // 90° の弧（sweep=1 で右上→右下）。
        let quarter = SVGPathParser.flattenedPoints(
            from: "M12,2 A10,10 0 0,1 22,12")
        for p in quarter {
            let distance = hypot(p.x - 12, p.y - 12)
            XCTAssertEqual(distance, 10, accuracy: 0.2,
                           "1/4 円の点が円周から外れた: \(p)")
        }
        // 楕円弧も破綻しないこと（rx != ry）。
        let ellipse = SVGPathParser.flattenedPoints(
            from: "M2,12 A10,6 0 1,0 22,12")
        XCTAssertGreaterThan(ellipse.count, 10)
        for p in ellipse {
            XCTAssertTrue(p.x >= 2 - 0.2 && p.x <= 22 + 0.2, "楕円弧の横範囲: \(p)")
            XCTAssertTrue(p.y >= 6 - 0.2 && p.y <= 18 + 0.2, "楕円弧の縦範囲: \(p)")
        }
    }

    func testFullCommandSetParses() {
        // 採用集合は絶対コマンド中心だが、解釈器は仕様の全コマンド
        // （相対形・S / T の反射・暗黙の繰り返し）を扱えることを固定する。
        let d = "m4,4 h16 v16 h-16 Z " +
            "M4,20 C8,12 16,12 20,20 S16,26 12,22 " +
            "M4,14 Q12,6 20,14 T20,22 " +
            "M6,6 l4,0 0,4 -4,0 Z"
        let points = SVGPathParser.flattenedPoints(from: d)
        XCTAssertGreaterThan(points.count, 50)
        for p in points {
            XCTAssertTrue(p.x.isFinite && p.y.isFinite, "非有限の点: \(p)")
            XCTAssertTrue(p.x >= -0.6 && p.x <= 26.6, "想定外の横位置: \(p)")
            XCTAssertTrue(p.y >= -0.6 && p.y <= 26.6, "想定外の縦位置: \(p)")
        }
        // Z でサブパスの開始点へ戻ること。
        let square = SVGPathParser.flattenedPoints(from: "M4,4 h16 v16 h-16 Z")
        XCTAssertEqual(square.first, CGPoint(x: 4, y: 4))
        XCTAssertEqual(square.last, CGPoint(x: 4, y: 4))
    }

    func testShapeScalesIntoRect() {
        // 24×24 以外の rect へも正しく写ること（原点と倍率）。
        let path = MDIIconShape(name: "play")
            .path(in: CGRect(x: 10, y: 20, width: 48, height: 48))
        let bounds = path.boundingRect
        XCTAssertGreaterThanOrEqual(bounds.minX, 10 - 0.1)
        XCTAssertGreaterThanOrEqual(bounds.minY, 20 - 0.1)
        XCTAssertLessThanOrEqual(bounds.maxX, 10 + 48 + 0.1)
        XCTAssertLessThanOrEqual(bounds.maxY, 20 + 48 + 0.1)
        XCTAssertGreaterThan(bounds.width, 10)
        XCTAssertGreaterThan(bounds.height, 10)
    }
}
