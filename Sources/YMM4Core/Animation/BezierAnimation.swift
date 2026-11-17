import Foundation

/// 率空間の2成分座標。本家 `System.Numerics.Vector2`（float）に対応する。
///
/// 本家は制御点座標を float で保持し、ベジェ評価の係数計算にも float
/// 精度が混ざるため、ここでも成分は Float とする。
public struct BezierVector: Equatable, Sendable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }

    public static func + (lhs: BezierVector, rhs: BezierVector) -> BezierVector {
        BezierVector(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: BezierVector, rhs: BezierVector) -> BezierVector {
        BezierVector(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static func * (lhs: BezierVector, rhs: Float) -> BezierVector {
        BezierVector(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    public static func / (lhs: BezierVector, rhs: Float) -> BezierVector {
        BezierVector(x: lhs.x / rhs, y: lhs.y / rhs)
    }
}

/// ベジェ補間のアンカー点1つ。本家 `BezierAnimationPoint` に対応する。
///
/// 制御点はアンカー点からの**相対オフセット**（絶対座標ではない）。
/// 区間の始点側の制御点には始点の `controlPoint2`、終点側には終点の
/// `controlPoint1` が使われる。
public struct BezierAnimationPoint: Equatable, Sendable {
    /// アンカー点。
    public var point: BezierVector
    /// 終点側として使われる制御点の相対オフセット。
    public var controlPoint1: BezierVector
    /// 始点側として使われる制御点の相対オフセット。
    public var controlPoint2: BezierVector

    public init(
        point: BezierVector,
        controlPoint1: BezierVector = BezierVector(x: 0, y: 0),
        controlPoint2: BezierVector = BezierVector(x: 0, y: 0)
    ) {
        self.point = point
        self.controlPoint1 = controlPoint1
        self.controlPoint2 = controlPoint2
    }

    /// 既定の制御点オフセット（CP1 = (-0.3, -0.3)、CP2 = (0.3, 0.3)）を持つ点。
    private static func createDefault(_ point: BezierVector) -> BezierAnimationPoint {
        BezierAnimationPoint(
            point: point,
            controlPoint1: BezierVector(x: -0.3, y: -0.3),
            controlPoint2: BezierVector(x: 0.3, y: 0.3)
        )
    }

    /// 既定の開始点 (0, 0)。本家 `CreateStart`。
    public static func createStart() -> BezierAnimationPoint {
        createDefault(BezierVector(x: 0, y: 0))
    }

    /// 既定の終了点 (1, 1)。本家 `CreateEnd`。
    public static func createEnd() -> BezierAnimationPoint {
        createDefault(BezierVector(x: 1, y: 1))
    }

    /// 既定の点列（開始点と終了点の2点）。本家 `CreateDefaultPoints`。
    public static func createDefaultPoints() -> [BezierAnimationPoint] {
        [createStart(), createEnd()]
    }
}

/// ベジェ補間の定義。本家 `BezierAnimation` に対応する。
///
/// 評価は率を受け取り、区間ごとに x(t) = rate を Newton 法で解いて
/// y(t) を返す。`isQuadratic` のときは評価前に点列を2次用の形へ変換する。
/// 数式の正本は解析側 `ANIMATION-FORMULAS.md` §3。
public struct BezierAnimation: Equatable, Sendable {
    public var points: [BezierAnimationPoint]
    public var isQuadratic: Bool

    public init(
        points: [BezierAnimationPoint] = BezierAnimationPoint.createDefaultPoints(),
        isQuadratic: Bool = false
    ) {
        self.points = points
        self.isQuadratic = isQuadratic
    }

    /// 率に対するベジェ曲線の値。本家 `GetAnimation(rate)`。
    public func value(atRate rate: Double) -> Double {
        if isQuadratic {
            return Self.evaluate(points: Self.toQuadraticPoints(points), rate: rate)
        }
        return Self.evaluate(points: points, rate: rate)
    }

    private static func evaluate(points: [BezierAnimationPoint], rate: Double) -> Double {
        if points.count < 2 {
            return rate
        }
        if rate <= 0 {
            return Double(points[0].point.y)
        }
        if rate >= 1 {
            return Double(points[points.count - 1].point.y)
        }
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            if rate < Double(start.point.x) || rate > Double(end.point.x) {
                continue
            }
            var p1 = start.point + start.controlPoint2
            var p2 = end.point + end.controlPoint1
            // 制御点の X のみクランプする（Y はしない）
            if p1.x > end.point.x { p1.x = end.point.x }
            if p2.x < start.point.x { p2.x = start.point.x }

            // 係数 a〜c は本家では float 精度で計算されてから double へ広がる
            // （3f 等の float リテラルが混ざる）。ここでも float のまま計算する。
            let a = Double(Float(0) - start.point.x + 3 * p1.x - 3 * p2.x + end.point.x)
            let b = Double(3 * start.point.x - 6 * p1.x + 3 * p2.x)
            let c = Double(-3 * start.point.x + 3 * p1.x)
            let d = Double(start.point.x) - rate

            var t = (rate - Double(start.point.x)) / Double(end.point.x - start.point.x)
            t = clampToUnit(t)
            for _ in 0..<5 {
                let f = ((a * t + b) * t + c) * t + d
                let derivative = (3 * a * t + 2 * b) * t + c
                if abs(derivative) < 1e-6 {
                    break
                }
                t = clampToUnit(t - f / derivative)
            }

            let u = 1 - t
            return u * u * u * Double(start.point.y)
                + 3 * u * u * t * Double(p1.y)
                + 3 * u * t * t * Double(p2.y)
                + t * t * t * Double(end.point.y)
        }
        // どの区間にも入らない場合は率をそのまま返す
        return rate
    }

    /// 2次モード用の点列変換。本家 `ToQuadraticPoints`。
    ///
    /// 元のアンカー点が持つ制御点オフセットは使われない。変換後の点列に
    /// 3次評価をそのまま適用する。
    private static func toQuadraticPoints(_ points: [BezierAnimationPoint]) -> [BezierAnimationPoint] {
        if points.count < 2 {
            return [.createStart(), .createEnd()]
        }
        if points.count == 2 {
            return [
                BezierAnimationPoint(point: points[0].point),
                BezierAnimationPoint(point: points[1].point),
            ]
        }
        var result: [BezierAnimationPoint] = []
        for index in 0..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let point: BezierVector
            let controlPoint1: BezierVector
            let controlPoint2: BezierVector
            if index == 0 {
                point = current.point
                controlPoint1 = BezierVector(x: 0, y: 0)
                controlPoint2 = (next.point - current.point) * 2 / 3
            } else if index == points.count - 2 {
                point = next.point
                controlPoint1 = (current.point - next.point) * 2 / 3
                controlPoint2 = BezierVector(x: 0, y: 0)
            } else {
                let middle = (current.point + next.point) / 2
                point = middle
                controlPoint1 = (current.point - middle) * 2 / 3
                controlPoint2 = (next.point - middle) * 2 / 3
            }
            result.append(BezierAnimationPoint(
                point: point,
                controlPoint1: controlPoint1,
                controlPoint2: controlPoint2
            ))
        }
        return result
    }

    /// 本家 `Math.Clamp(value, 0, 1)` と同じ（NaN はそのまま通す）。
    private static func clampToUnit(_ value: Double) -> Double {
        if value < 0 { return 0 }
        if value > 1 { return 1 }
        return value
    }
}
