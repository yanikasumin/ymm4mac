import Foundation

/// 描画層の土台で使う幾何型。本家 System.Numerics の Vector2 / Vector3 /
/// Matrix4x4 と Vortice の RawRectF に対応する。
///
/// 本家は float（32bit）だが、モデル層の他の値（Animation 等）が Double のため
/// こちらも Double で保持する。順序付けなど比較結果が 32bit 境界で変わりうる
/// ことは意図的な内部差分として台帳に記録する。

/// 2次元ベクトル。
public struct Vector2: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vector2(x: 0, y: 0)
}

/// 3次元ベクトル。
public struct Vector3: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(x: 0, y: 0, z: 0)

    public static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    public static func / (lhs: Vector3, rhs: Double) -> Vector3 {
        Vector3(x: lhs.x / rhs, y: lhs.y / rhs, z: lhs.z / rhs)
    }

    /// 外積。
    public func cross(_ other: Vector3) -> Vector3 {
        Vector3(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }

    /// 内積。
    public func dot(_ other: Vector3) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    /// 長さ。
    public var length: Double {
        (x * x + y * y + z * z).squareRoot()
    }
}

/// 矩形（左・上・右・下）。本家 RawRectF に対応する。
public struct RectF: Equatable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double

    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    /// 両方を含む最小の矩形（本家 GetPlaneSplitQuad の境界統合と同じ）。
    public func union(_ other: RectF) -> RectF {
        RectF(
            left: min(left, other.left),
            top: min(top, other.top),
            right: max(right, other.right),
            bottom: max(bottom, other.bottom)
        )
    }
}

/// 4×4 行列。本家 System.Numerics.Matrix4x4 と同じ行優先（M11〜M44）で、
/// 変換は行ベクトル × 行列の規約（`v * (A * B) == (v * A) * B`）。
public struct Matrix4x4: Equatable, Sendable {
    public var m11: Double
    public var m12: Double
    public var m13: Double
    public var m14: Double
    public var m21: Double
    public var m22: Double
    public var m23: Double
    public var m24: Double
    public var m31: Double
    public var m32: Double
    public var m33: Double
    public var m34: Double
    public var m41: Double
    public var m42: Double
    public var m43: Double
    public var m44: Double

    public init(
        m11: Double, m12: Double, m13: Double, m14: Double,
        m21: Double, m22: Double, m23: Double, m24: Double,
        m31: Double, m32: Double, m33: Double, m34: Double,
        m41: Double, m42: Double, m43: Double, m44: Double
    ) {
        self.m11 = m11
        self.m12 = m12
        self.m13 = m13
        self.m14 = m14
        self.m21 = m21
        self.m22 = m22
        self.m23 = m23
        self.m24 = m24
        self.m31 = m31
        self.m32 = m32
        self.m33 = m33
        self.m34 = m34
        self.m41 = m41
        self.m42 = m42
        self.m43 = m43
        self.m44 = m44
    }

    public static let identity = Matrix4x4(
        m11: 1, m12: 0, m13: 0, m14: 0,
        m21: 0, m22: 1, m23: 0, m24: 0,
        m31: 0, m32: 0, m33: 1, m34: 0,
        m41: 0, m42: 0, m43: 0, m44: 1
    )

    /// 行列積。左の変換を先に適用する合成（System.Numerics の `*` と同じ）。
    public static func * (lhs: Matrix4x4, rhs: Matrix4x4) -> Matrix4x4 {
        Matrix4x4(
            m11: lhs.m11 * rhs.m11 + lhs.m12 * rhs.m21 + lhs.m13 * rhs.m31 + lhs.m14 * rhs.m41,
            m12: lhs.m11 * rhs.m12 + lhs.m12 * rhs.m22 + lhs.m13 * rhs.m32 + lhs.m14 * rhs.m42,
            m13: lhs.m11 * rhs.m13 + lhs.m12 * rhs.m23 + lhs.m13 * rhs.m33 + lhs.m14 * rhs.m43,
            m14: lhs.m11 * rhs.m14 + lhs.m12 * rhs.m24 + lhs.m13 * rhs.m34 + lhs.m14 * rhs.m44,
            m21: lhs.m21 * rhs.m11 + lhs.m22 * rhs.m21 + lhs.m23 * rhs.m31 + lhs.m24 * rhs.m41,
            m22: lhs.m21 * rhs.m12 + lhs.m22 * rhs.m22 + lhs.m23 * rhs.m32 + lhs.m24 * rhs.m42,
            m23: lhs.m21 * rhs.m13 + lhs.m22 * rhs.m23 + lhs.m23 * rhs.m33 + lhs.m24 * rhs.m43,
            m24: lhs.m21 * rhs.m14 + lhs.m22 * rhs.m24 + lhs.m23 * rhs.m34 + lhs.m24 * rhs.m44,
            m31: lhs.m31 * rhs.m11 + lhs.m32 * rhs.m21 + lhs.m33 * rhs.m31 + lhs.m34 * rhs.m41,
            m32: lhs.m31 * rhs.m12 + lhs.m32 * rhs.m22 + lhs.m33 * rhs.m32 + lhs.m34 * rhs.m42,
            m33: lhs.m31 * rhs.m13 + lhs.m32 * rhs.m23 + lhs.m33 * rhs.m33 + lhs.m34 * rhs.m43,
            m34: lhs.m31 * rhs.m14 + lhs.m32 * rhs.m24 + lhs.m33 * rhs.m34 + lhs.m34 * rhs.m44,
            m41: lhs.m41 * rhs.m11 + lhs.m42 * rhs.m21 + lhs.m43 * rhs.m31 + lhs.m44 * rhs.m41,
            m42: lhs.m41 * rhs.m12 + lhs.m42 * rhs.m22 + lhs.m43 * rhs.m32 + lhs.m44 * rhs.m42,
            m43: lhs.m41 * rhs.m13 + lhs.m42 * rhs.m23 + lhs.m43 * rhs.m33 + lhs.m44 * rhs.m43,
            m44: lhs.m41 * rhs.m14 + lhs.m42 * rhs.m24 + lhs.m43 * rhs.m34 + lhs.m44 * rhs.m44
        )
    }

    /// 4次元ベクトルとしての変換（除算しない）。
    public func transform(x: Double, y: Double, z: Double, w: Double)
        -> (x: Double, y: Double, z: Double, w: Double)
    {
        (
            x: x * m11 + y * m21 + z * m31 + w * m41,
            y: x * m12 + y * m22 + z * m32 + w * m42,
            z: x * m13 + y * m23 + z * m33 + w * m43,
            w: x * m14 + y * m24 + z * m34 + w * m44
        )
    }

    /// 点の変換。本家 MatrixHelper.Transform と同じく、w=1 で変換して w で割る。
    public func transform(_ point: Vector3) -> Vector3 {
        let v = transform(x: point.x, y: point.y, z: point.z, w: 1)
        return Vector3(x: v.x / v.w, y: v.y / v.w, z: v.z / v.w)
    }

    /// 平行移動（System.Numerics CreateTranslation）。
    public static func createTranslation(x: Double, y: Double, z: Double) -> Matrix4x4 {
        var result = Matrix4x4.identity
        result.m41 = x
        result.m42 = y
        result.m43 = z
        return result
    }

    /// 平行移動（System.Numerics CreateTranslation）。
    public static func createTranslation(_ vector: Vector3) -> Matrix4x4 {
        createTranslation(x: vector.x, y: vector.y, z: vector.z)
    }

    /// 中心点まわりの拡縮（System.Numerics CreateScale(scales, centerPoint)）。
    public static func createScale(x: Double, y: Double, z: Double, center: Vector3) -> Matrix4x4 {
        var result = Matrix4x4.identity
        result.m11 = x
        result.m22 = y
        result.m33 = z
        result.m41 = center.x * (1 - x)
        result.m42 = center.y * (1 - y)
        result.m43 = center.z * (1 - z)
        return result
    }

    /// X 軸まわりの回転（System.Numerics CreateRotationX、右手系）。
    public static func createRotationX(_ radians: Double) -> Matrix4x4 {
        var result = Matrix4x4.identity
        result.m22 = cos(radians)
        result.m23 = sin(radians)
        result.m32 = -sin(radians)
        result.m33 = cos(radians)
        return result
    }

    /// Y 軸まわりの回転（System.Numerics CreateRotationY、右手系）。
    public static func createRotationY(_ radians: Double) -> Matrix4x4 {
        var result = Matrix4x4.identity
        result.m11 = cos(radians)
        result.m13 = -sin(radians)
        result.m31 = sin(radians)
        result.m33 = cos(radians)
        return result
    }

    /// Z 軸まわりの回転（System.Numerics CreateRotationZ、右手系）。
    public static func createRotationZ(_ radians: Double) -> Matrix4x4 {
        var result = Matrix4x4.identity
        result.m11 = cos(radians)
        result.m12 = sin(radians)
        result.m21 = -sin(radians)
        result.m22 = cos(radians)
        return result
    }
}
