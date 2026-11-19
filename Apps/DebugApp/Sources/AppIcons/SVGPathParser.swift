import Foundation
import SwiftUI

/// SVG パスデータ（d 属性）の解釈器。
///
/// MDI のアイコンは 24×24 キャンバス上の単一パスで、コマンドは
/// M / L / H / V / C / S / Q / T / A / Z（と相対形）を使う。
/// ここでは SVG 1.1 のパス仕様に従って解釈し、絶対座標のセグメント列へ
/// 変換する。円弧（A）は端点→中心パラメータ変換（仕様 F.6.5）を行い、
/// 90° 以下の区間に分割して 3 次ベジェで近似する（楕円弧もそのまま扱える）。
/// 解釈結果は描画（Path 化）と検証（サンプリング）の両方から使う。
public enum SVGPathParser {

    /// 絶対座標へ正規化したセグメント。円弧はベジェ近似済み。
    public enum Segment: Equatable {
        case moveTo(CGPoint)
        case lineTo(CGPoint)
        case cubicTo(CGPoint, CGPoint, CGPoint)
        case quadTo(CGPoint, CGPoint)
        case close
    }

    /// パスデータをセグメント列へ変換する。解釈できない文字があれば
    /// その時点で打ち切る（MDI の正規データでは発生しない）。
    public static func segments(from d: String) -> [Segment] {
        var scanner = Scanner(d)
        var result: [Segment] = []
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var command: Character? = nil
        var previousCubicControl2: CGPoint? = nil
        var previousQuadControl: CGPoint? = nil

        func isCommandLetter(_ c: Character) -> Bool {
            "MmLlHhVvCcSsQqTtAaZz".contains(c)
        }

        while true {
            scanner.skipSeparators()
            guard let ch = scanner.peek() else { break }
            if isCommandLetter(ch) {
                command = ch
                scanner.advance()
                if ch == "Z" || ch == "z" {
                    result.append(.close)
                    current = subpathStart
                    previousCubicControl2 = nil
                    previousQuadControl = nil
                    command = nil
                    continue
                }
            }
            guard let cmd = command else { break }
            let relative = cmd.isLowercase
            switch cmd.uppercased() {
            case "M":
                guard let p = scanner.readPoint(relativeTo: relative ? current : .zero)
                else { return result }
                result.append(.moveTo(p))
                current = p
                subpathStart = p
                previousCubicControl2 = nil
                previousQuadControl = nil
                // M の後続の座標対は L として扱う（仕様）。
                command = relative ? "l" : "L"
            case "L":
                guard let p = scanner.readPoint(relativeTo: relative ? current : .zero)
                else { return result }
                result.append(.lineTo(p))
                current = p
                previousCubicControl2 = nil
                previousQuadControl = nil
            case "H":
                guard let v = scanner.readNumber() else { return result }
                let p = CGPoint(x: relative ? current.x + v : v, y: current.y)
                result.append(.lineTo(p))
                current = p
                previousCubicControl2 = nil
                previousQuadControl = nil
            case "V":
                guard let v = scanner.readNumber() else { return result }
                let p = CGPoint(x: current.x, y: relative ? current.y + v : v)
                result.append(.lineTo(p))
                current = p
                previousCubicControl2 = nil
                previousQuadControl = nil
            case "C":
                guard let c1 = scanner.readPoint(relativeTo: relative ? current : .zero),
                      let c2 = scanner.readPoint(relativeTo: relative ? current : .zero),
                      let p = scanner.readPoint(relativeTo: relative ? current : .zero)
                else { return result }
                result.append(.cubicTo(c1, c2, p))
                previousCubicControl2 = c2
                previousQuadControl = nil
                current = p
            case "S":
                guard let c2 = scanner.readPoint(relativeTo: relative ? current : .zero),
                      let p = scanner.readPoint(relativeTo: relative ? current : .zero)
                else { return result }
                // 直前が C / S のときだけ第 1 制御点を反射する（仕様）。
                let c1 = previousCubicControl2.map {
                    CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                } ?? current
                result.append(.cubicTo(c1, c2, p))
                previousCubicControl2 = c2
                previousQuadControl = nil
                current = p
            case "Q":
                guard let q = scanner.readPoint(relativeTo: relative ? current : .zero),
                      let p = scanner.readPoint(relativeTo: relative ? current : .zero)
                else { return result }
                result.append(.quadTo(q, p))
                previousQuadControl = q
                previousCubicControl2 = nil
                current = p
            case "T":
                guard let p = scanner.readPoint(relativeTo: relative ? current : .zero)
                else { return result }
                let q = previousQuadControl.map {
                    CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                } ?? current
                result.append(.quadTo(q, p))
                previousQuadControl = q
                previousCubicControl2 = nil
                current = p
            case "A":
                guard let rx = scanner.readNumber(),
                      let ry = scanner.readNumber(),
                      let rotation = scanner.readNumber(),
                      let largeArc = scanner.readFlag(),
                      let sweep = scanner.readFlag(),
                      let p = scanner.readPoint(relativeTo: relative ? current : .zero)
                else { return result }
                let curves = arcToCubics(
                    from: current, rx: abs(rx), ry: abs(ry),
                    rotationDegrees: rotation, largeArc: largeArc,
                    sweep: sweep, to: p)
                if curves.isEmpty {
                    result.append(.lineTo(p))
                } else {
                    for (c1, c2, end) in curves {
                        result.append(.cubicTo(c1, c2, end))
                    }
                }
                previousCubicControl2 = nil
                previousQuadControl = nil
                current = p
            default:
                return result
            }
        }
        return result
    }

    /// セグメント列を、24×24 空間から rect へ写した Path にする。
    public static func path(from d: String, in rect: CGRect) -> Path {
        buildPath(segments: segments(from: d), in: rect)
    }

    /// セグメント列を rect へ写した Path にする。
    public static func buildPath(segments: [Segment], in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 24
        let sy = rect.height / 24
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + p.x * sx, y: rect.minY + p.y * sy)
        }
        for segment in segments {
            switch segment {
            case .moveTo(let p):
                path.move(to: map(p))
            case .lineTo(let p):
                path.addLine(to: map(p))
            case .cubicTo(let c1, let c2, let p):
                path.addCurve(to: map(p), control1: map(c1), control2: map(c2))
            case .quadTo(let q, let p):
                path.addQuadCurve(to: map(p), control: map(q))
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }

    /// 検証用: 曲線をサンプリングした点列（24×24 空間）を返す。
    /// 制御点ではなく曲線上の点だけを返すので、キャンバス範囲の
    /// 検査に使える。
    public static func flattenedPoints(
        from d: String, samplesPerCurve: Int = 24
    ) -> [CGPoint] {
        var points: [CGPoint] = []
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        for segment in segments(from: d) {
            switch segment {
            case .moveTo(let p):
                points.append(p)
                current = p
                subpathStart = p
            case .lineTo(let p):
                points.append(p)
                current = p
            case .cubicTo(let c1, let c2, let p):
                for i in 1...samplesPerCurve {
                    let t = CGFloat(i) / CGFloat(samplesPerCurve)
                    points.append(cubicPoint(current, c1, c2, p, t: t))
                }
                current = p
            case .quadTo(let q, let p):
                for i in 1...samplesPerCurve {
                    let t = CGFloat(i) / CGFloat(samplesPerCurve)
                    points.append(quadPoint(current, q, p, t: t))
                }
                current = p
            case .close:
                points.append(subpathStart)
                current = subpathStart
            }
        }
        return points
    }

    private static func cubicPoint(
        _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, t: CGFloat
    ) -> CGPoint {
        let u = 1 - t
        let a = u * u * u
        let b = 3 * u * u * t
        let c = 3 * u * t * t
        let d = t * t * t
        return CGPoint(
            x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
            y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
    }

    private static func quadPoint(
        _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, t: CGFloat
    ) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
            y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y)
    }

    /// 円弧の端点パラメータ → 中心パラメータ変換（SVG 1.1 F.6.5）と、
    /// 90° 以下の区間への分割＋3 次ベジェ近似。
    private static func arcToCubics(
        from p0: CGPoint, rx: Double, ry: Double, rotationDegrees: Double,
        largeArc: Bool, sweep: Bool, to p1: CGPoint
    ) -> [(CGPoint, CGPoint, CGPoint)] {
        if rx == 0 || ry == 0 || p0 == p1 { return [] }
        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx = (Double(p0.x) - Double(p1.x)) / 2
        let dy = (Double(p0.y) - Double(p1.y)) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        var rx = rx
        var ry = ry
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }

        let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var co = denominator == 0 ? 0 : sqrt(max(0, numerator / denominator))
        if largeArc == sweep { co = -co }
        let cxp = co * rx * y1p / ry
        let cyp = -co * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (Double(p0.x) + Double(p1.x)) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (Double(p0.y) + Double(p1.y)) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var a = acos(min(1, max(-1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle(
            (x1p - cxp) / rx, (y1p - cyp) / ry,
            (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        func point(at theta: Double) -> CGPoint {
            let ex = rx * cos(theta)
            let ey = ry * sin(theta)
            return CGPoint(
                x: cx + cosPhi * ex - sinPhi * ey,
                y: cy + sinPhi * ex + cosPhi * ey)
        }
        func derivative(at theta: Double) -> (Double, Double) {
            let ex = -rx * sin(theta)
            let ey = ry * cos(theta)
            return (cosPhi * ex - sinPhi * ey, sinPhi * ex + cosPhi * ey)
        }

        let chunkCount = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let chunk = delta / Double(chunkCount)
        let alpha = (4.0 / 3.0) * tan(chunk / 4)
        var curves: [(CGPoint, CGPoint, CGPoint)] = []
        for i in 0..<chunkCount {
            let t1 = theta1 + chunk * Double(i)
            let t2 = t1 + chunk
            let start = point(at: t1)
            let end = point(at: t2)
            let d1 = derivative(at: t1)
            let d2 = derivative(at: t2)
            let c1 = CGPoint(x: start.x + CGFloat(alpha * d1.0),
                             y: start.y + CGFloat(alpha * d1.1))
            let c2 = CGPoint(x: end.x - CGFloat(alpha * d2.0),
                             y: end.y - CGFloat(alpha * d2.1))
            curves.append((c1, c2, end))
        }
        return curves
    }

    /// パスデータの字句走査。数値とコマンドを順に読む。
    /// 円弧のフラグは仕様どおり 1 文字として読む（区切りなしで
    /// 後続の座標とくっついている表記があるため）。
    private struct Scanner {
        private let chars: [Character]
        private var index = 0

        init(_ s: String) { chars = Array(s) }

        func peek() -> Character? {
            index < chars.count ? chars[index] : nil
        }

        mutating func advance() { index += 1 }

        mutating func skipSeparators() {
            while let c = peek(), c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" {
                index += 1
            }
        }

        mutating func readNumber() -> CGFloat? {
            skipSeparators()
            var i = index
            if i < chars.count && (chars[i] == "+" || chars[i] == "-") { i += 1 }
            var sawDigit = false
            var sawDot = false
            while i < chars.count {
                let c = chars[i]
                if c.isNumber {
                    sawDigit = true
                    i += 1
                } else if c == "." && !sawDot {
                    sawDot = true
                    i += 1
                } else {
                    break
                }
            }
            guard sawDigit else { return nil }
            // 指数部。
            if i < chars.count && (chars[i] == "e" || chars[i] == "E") {
                var j = i + 1
                if j < chars.count && (chars[j] == "+" || chars[j] == "-") { j += 1 }
                var expDigits = false
                while j < chars.count && chars[j].isNumber {
                    expDigits = true
                    j += 1
                }
                if expDigits { i = j }
            }
            let text = String(chars[index..<i])
            guard let value = Double(text) else { return nil }
            index = i
            return CGFloat(value)
        }

        mutating func readFlag() -> Bool? {
            skipSeparators()
            guard let c = peek(), c == "0" || c == "1" else { return nil }
            index += 1
            return c == "1"
        }

        mutating func readPoint(relativeTo origin: CGPoint) -> CGPoint? {
            guard let x = readNumber(), let y = readNumber() else { return nil }
            return CGPoint(x: origin.x + x, y: origin.y + y)
        }
    }
}
