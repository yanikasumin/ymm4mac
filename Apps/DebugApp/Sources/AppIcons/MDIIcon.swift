import SwiftUI

/// MDI アイコンのレイヤ構成。
///
/// 通常のアイコンは辞書（MDIIconPaths）の単一パス 1 層。
/// 本家独自の合成アイコン（materialdesignicons.xaml の手書き分）は、
/// MDI 単体の重ね描き＋独自図形で再構成し、ここに合成名として登録する。
/// 本家独自図形のパスデータは写さず、等価な図形を独自座標で描く
/// （ICON-MDI-MAPPING.md 1.4 の注記に従う）。
public enum MDIIconLayers {

    /// 1 層分: 24×24 空間でのパスデータと、拡大率・原点オフセット。
    public struct Layer {
        public var pathData: String
        public var scale: CGFloat = 1
        public var offset: CGPoint = .zero
    }

    /// アイコン名からレイヤ列を引く。未知の名前は nil。
    public static func layers(for name: String) -> [Layer]? {
        if let d = MDIIconPaths.paths[name] {
            return [Layer(pathData: d)]
        }
        switch name {
        case "repeat":
            // 本家 RepeatCircleArrow = RotateLeft の中央に Play（半分）。
            return [
                Layer(pathData: MDIIconPaths.paths["rotate-left"]!),
                Layer(pathData: MDIIconPaths.paths["play"]!,
                      scale: 0.5, offset: CGPoint(x: 6, y: 6)),
            ]
        case "waveform-off":
            // 本家 WaveformOff = Waveform + 斜線 1 本。斜線は本家独自
            // 図形のため写さず、独自座標の平行四辺形（帯）で描く。
            return [
                Layer(pathData: MDIIconPaths.paths["waveform"]!),
                Layer(pathData: slashPathData),
            ]
        case "vector-clipping":
            // 本家 VectorClipping = VectorDifferenceAb + 独自図形 1 つ。
            // 第 2 要素は写さず、クリッピング範囲を示す破線枠を
            // 独自に描く（旧 SF Symbol の square.dashed と同じ意味付け）。
            return [
                Layer(pathData: MDIIconPaths.paths["vector-difference-ab"]!),
                Layer(pathData: dashedFramePathData),
            ]
        case "file-filmstrip-outline":
            // 本家 FileFilmstripOutline = FileOutline の右下に Filmstrip。
            return [
                Layer(pathData: MDIIconPaths.paths["file-outline"]!),
                Layer(pathData: MDIIconPaths.paths["filmstrip"]!,
                      scale: 0.55, offset: CGPoint(x: 10.8, y: 10.8)),
            ]
        default:
            return nil
        }
    }

    /// 合成アイコン名の一覧（テストと台帳の突き合わせ用）。
    public static let compositeNames = [
        "repeat", "waveform-off", "vector-clipping", "file-filmstrip-outline",
    ]

    /// 波形オフの斜線（独自図形）。左上→右下の帯、幅 約2.2。
    private static let slashPathData =
        "M4.98,2.62 L21.38,19.02 L19.82,20.58 L3.42,4.18 Z"

    /// クリッピング枠（独自図形）。内側 2.5 の正方形の縁を、
    /// 線幅 1.6・ダッシュ 4 / ギャップ 2.5 の塗り矩形列で描く。
    private static var dashedFramePathData: String {
        let inset: CGFloat = 2.5
        let thickness: CGFloat = 1.6
        let side: CGFloat = 24 - inset * 2
        var dashes: [(start: CGFloat, length: CGFloat)] = []
        var pos: CGFloat = 0
        while pos < side {
            let len = min(4, side - pos)
            dashes.append((pos, len))
            pos += 4 + 2.5
        }
        var parts: [String] = []
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            parts.append("M\(x),\(y) h\(w) v\(h) h\(-w) Z")
        }
        for dash in dashes {
            let s = inset + dash.start
            // 上辺・下辺
            rect(s, inset, dash.length, thickness)
            rect(s, 24 - inset - thickness, dash.length, thickness)
            // 左辺・右辺
            rect(inset, s, thickness, dash.length)
            rect(24 - inset - thickness, s, thickness, dash.length)
        }
        return parts.joined(separator: " ")
    }
}

/// MDI アイコンを描く Shape。24×24 空間を rect へ写して塗る。
/// 色は通常の Shape と同じく、View として置いたときの
/// foregroundStyle が使われる。
public struct MDIIconShape: Shape {
    public let name: String

    public init(name: String) {
        self.name = name
    }

    public func path(in rect: CGRect) -> Path {
        guard let layers = MDIIconLayers.layers(for: name) else {
            return Path()
        }
        var result = Path()
        let unitX = rect.width / 24
        let unitY = rect.height / 24
        for layer in layers {
            // レイヤの scale / offset（24×24 空間）と rect への写像を
            // 合成し、解釈器に最終矩形を直接渡す。
            let layerRect = CGRect(
                x: rect.minX + layer.offset.x * unitX,
                y: rect.minY + layer.offset.y * unitY,
                width: 24 * layer.scale * unitX,
                height: 24 * layer.scale * unitY)
            result.addPath(SVGPathParser.path(from: layer.pathData, in: layerRect))
        }
        return result
    }
}

/// MDI アイコンの View。名前とサイズを指定して使う。
///
/// 無効状態の見た目は本家 ViewboxStyle（不透明度 0.3 + グレースケール）
/// に合わせ、環境の isEnabled が false のときに自動で付ける。
/// 本家もアイコン側のスタイルで無効表示を担うため、呼び出し側は
/// .disabled() を付けるだけでよい。
public struct MDIIcon: View {
    @Environment(\.isEnabled) private var isEnabled

    public let name: String
    public var size: CGFloat

    public init(_ name: String, size: CGFloat = 20) {
        self.name = name
        self.size = size
    }

    public var body: some View {
        MDIIconShape(name: name)
            .frame(width: size, height: size)
            .opacity(isEnabled ? 1 : 0.3)
            .grayscale(isEnabled ? 0 : 1)
    }
}
