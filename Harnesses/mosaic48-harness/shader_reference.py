#!/usr/bin/env python3
"""本家モザイク系カスタムシェーダ (.cso) の DXBC 逆アセンブル字面に基づく
参照実装。検証ハーネスの期待値生成に使う。

座標: pos = シーン座標 (入力平面座標), size = セル寸法 (1..5000 にクランプ済み
の値を渡すこと)。返り値はサンプル点 (シーン座標) と、透明にすべきか否か。
実際の色は入力画像をサンプル点で線形サンプルしたもの (範囲外は透明)。
"""
import math

import numpy as np


def f32(x):
    """float32 へ丸める。本家シェーダ (HLSL) も Metal も float32 で
    計算するため、ハッシュ系の式は float32 の精度で評価する
    (sin の微差が frac で増幅され、結果が全く変わるため)。"""
    return float(np.float32(x))


def frac(x):
    return x - math.floor(x)


def frac32(x):
    return f32(x - math.floor(x))


def round_ni(x):
    # DXBC round_ni: 最も近い整数へ。.5 は偶数方向ではなく切り上げ方向
    # (HLSL round と同じく half away from zero 相当を負数含め定義する)。
    if x >= 0:
        return math.floor(x + 0.5)
    return math.ceil(x - 0.5)


def clamp(v, lo, hi):
    return min(hi, max(lo, v))


# ---- 共通: Voronoi / Delaunay の seed 前処理とハッシュ ----
# DXBC 字面:
#   t = (1234.5677, 1234.9012) * seed
#   s.xy = sign により ±(1234.5677, 1234.9012)   (seed >= 0 で正)
#   s.zw = frac( ±(0.00081, 0.00080978) * seed ) (符号は t の成分符号)
#   hashInput = cellPoint + (s.x * s.z, s.y * s.w)
#   rand = frac(sin(dot(hashInput, (127.1, 311.7))) * 43758.546875),
#          frac(sin(dot(hashInput, (269.5, 183.3))) * 43758.546875)
def seed_offsets(seed):
    def sgn(v):
        return 1.0 if v >= 0 else -1.0
    sx = sgn(1234.5677490234375 * seed) * 1234.5677490234375
    sy = sgn(1234.9012451171875 * seed) * 1234.9012451171875
    sz = frac(sgn(1234.5677490234375 * seed) * 0.0008100001141428947 * seed)
    sw = frac(sgn(1234.9012451171875 * seed) * 0.0008097813697531819 * seed)
    return (sx * sz, sy * sw)


def hash_rand(hx, hy):
    def one(a, b):
        dot = f32(f32(hx * a) + f32(hy * b))
        return frac32(f32(f32(math.sin(dot)) * f32(43758.546875)))
    return (one(127.0999984741211, 311.70001220703125),
            one(269.5, 183.3000030517578))


def feature_points(qx, qy, seed):
    """3x3 近傍セルの特徴点 (セル座標系の連続値)。index = (oy+1)*3 + (ox+1)。"""
    cellx = round_ni(qx)
    celly = round_ni(qy)
    ox, oy = seed_offsets(seed)
    pts = []
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            bx = cellx + dx + ox
            by = celly + dy + oy
            rx, ry = hash_rand(bx, by)
            pts.append((cellx + dx + rx, celly + dy + ry))
    return pts


# ---- Rectangle (Mosaic) ----
# 本家字面 (MOSAICRECT で抽出): Size == 1 のときは現在画素をそのまま
# サンプルする。そうでないとき:
#   cellOrigin = floor(pos / size) * size (負座標でも床方向)
#   clampedOrigin = max(cellOrigin, rectMin)
#   clampedEnd = min(cellOrigin + size, rectMax)
#   extent = clampedEnd - clampedOrigin
# 色は clampedOrigin + extent * f (f は中心 (1/2, 1/2) と
# (1/3, 1/3), (1/3, 2/3), (2/3, 1/3), (2/3, 2/3)) の5点の
# 線形サンプルの平均。rect は入力矩形 (left, top, right, bottom)。
# 返り値はサンプル点の列。
def rectangle_points(pos, size, rect):
    if size == 1.0:
        return [pos]
    ox = math.floor(pos[0] / size) * size
    oy = math.floor(pos[1] / size) * size
    cx0 = max(ox, rect[0])
    cy0 = max(oy, rect[1])
    ex = min(ox + size, rect[2]) - cx0
    ey = min(oy + size, rect[3]) - cy0
    fractions = [
        (0.5, 0.5),
        (1.0 / 3.0, 1.0 / 3.0),
        (1.0 / 3.0, 2.0 / 3.0),
        (2.0 / 3.0, 1.0 / 3.0),
        (2.0 / 3.0, 2.0 / 3.0),
    ]
    return [(cx0 + ex * fx, cy0 + ey * fy) for fx, fy in fractions]


# ---- Circle ----
# cell = round_ni(pos/size); center = (cell + 0.5) * size
# offset = pos - center; if length(offset) > size/2 -> transparent
# else sample at center
def circle(pos, size):
    cx = round_ni(pos[0] / size)
    cy = round_ni(pos[1] / size)
    center = ((cx + 0.5) * size, (cy + 0.5) * size)
    dx = pos[0] - center[0]
    dy = pos[1] - center[1]
    dist = math.sqrt(dx * dx + dy * dy)
    if dist > size * 0.5:
        return None
    return center


# ---- Triangle ----
# q = pos/size
# sx = q.x - q.y / sqrt(3); sy = q.y * 2/sqrt(3)
# cell = round_ni(sx, sy); fx = frac(sx); fy = frac(sy)
# o = 1/3 if fx + fy <= 1 else 2/3
# base = cell + (o, o)
# sample = ((base.x + 0.5*base.y) * size, base.y * size * sqrt(3)/2)
def triangle(pos, size):
    qx = pos[0] / size
    qy = pos[1] / size
    sx = qx - qy * 0.5773502588272095
    sy = qy * 1.154700517654419
    cx = round_ni(sx)
    cy = round_ni(sy)
    fx = frac(sx)
    fy = frac(sy)
    o = 1.0 / 3.0 if (fx + fy) <= 1.0 else 2.0 / 3.0
    bx = cx + o
    by = cy + o
    return ((bx + 0.5 * by) * size, by * size * 0.8660253882408142)


# ---- Hexagon ----
# q = pos/size
# a = -q.x + q.y/sqrt(3); b = 2*q.x
# fa = frac(a); fb = frac(b)
# ca = round_ni(a); cb = round_ni(b)
# t = 3*fa + fb; c = 0 if t <= 2 else 1
# fa2 = fa + c*(1 - 2*fa); fb2 = fb + c*(1 - 2*fb)
# u = 3*fb2 + 2*fa2; d = -1 if u <= 1 else 0; d += c
# baseA = cb - abs(d) + 1
# baseB = c + ca
# sample = (baseA * size * 0.5, (sqrt(3)/2 * baseA + sqrt(3) * baseB) * size)
def hexagon(pos, size):
    qx = pos[0] / size
    qy = pos[1] / size
    a = -qx + qy * 0.5773502588272095
    b = 2.0 * qx
    fa = frac(a)
    fb = frac(b)
    ca = round_ni(a)
    cb = round_ni(b)
    t = 3.0 * fa + fb
    c = 0.0 if t <= 2.0 else 1.0
    fa2 = fa + c * (1.0 - 2.0 * fa)
    fb2 = fb + c * (1.0 - 2.0 * fb)
    u = 3.0 * fb2 + 2.0 * fa2
    d = -1.0 if u <= 1.0 else 0.0
    d += c
    base_a = cb - abs(d) + 1.0
    base_b = c + ca
    return (base_a * size * 0.5,
            (0.8660253882408142 * base_a + 1.7320507764816284 * base_b) * size)


# ---- Voronoi ----
# cell = round_ni(q); f = frac(q)
# 3x3 走査で f から最も近い特徴点 (セル相対) を探し、
# sample = (cell + bestPoint) * size
def voronoi(pos, size, seed):
    qx = pos[0] / size
    qy = pos[1] / size
    cellx = round_ni(qx)
    celly = round_ni(qy)
    fx = frac(qx)
    fy = frac(qy)
    ox, oy = seed_offsets(seed)
    best_dist = 2.0
    best = (0.0, 0.0)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            hx = cellx + dx + ox
            hy = celly + dy + oy
            rx, ry = hash_rand(hx, hy)
            px = dx + rx
            py = dy + ry
            ddx = px - fx
            ddy = py - fy
            dist = math.sqrt(ddx * ddx + ddy * ddy)
            if dist < best_dist:
                best_dist = dist
                best = (px, py)
    return ((cellx + best[0]) * size, (celly + best[1]) * size)


# ---- Delaunay ----
# 本家シェーダの構造 (DXBC 字面から確定した範囲):
#   1. 特徴点生成は Voronoi と同一 (feature_points)。
#   2. 角度和 (winding) 判定で 2x2 ブロック z in {0, 1, 3, 4} を選択する。
#   3. ブロックの4点 A=(z) B=(z+1) C=(z+3) D=(z+4) について外接円判定
#      (行列式) で対角線を選び、q を含む三角形の重心をサンプル点とする。
# この参照では 2 の winding 判定を幾何学的に等価な四角形内外判定へ、
# 3 の重心候補選択を三角形所属判定へ置き換える (非凸四角形と境界での
# 本家字面との差は未検証事項)。
def _cross(ax, ay, bx, by):
    return ax * by - ay * bx


def _in_triangle(q, a, b, c):
    d1 = _cross(b[0] - a[0], b[1] - a[1], q[0] - a[0], q[1] - a[1])
    d2 = _cross(c[0] - b[0], c[1] - b[1], q[0] - b[0], q[1] - b[1])
    d3 = _cross(a[0] - c[0], a[1] - c[1], q[0] - c[0], q[1] - c[1])
    return (d1 >= 0 and d2 >= 0 and d3 >= 0) or (d1 <= 0 and d2 <= 0 and d3 <= 0)


def _centroid(a, b, c):
    return ((a[0] + b[0] + c[0]) / 3.0, (a[1] + b[1] + c[1]) / 3.0)


def _incircle(a, b, c, d):
    """点 d が三角形 abc の外接円内にあるか (abc は反時計回り前提の
    行列式符号で判定する標準形)。"""
    ax = a[0] - d[0]
    ay = a[1] - d[1]
    bx = b[0] - d[0]
    by = b[1] - d[1]
    cx = c[0] - d[0]
    cy = c[1] - d[1]
    det = ((ax * ax + ay * ay) * (bx * cy - cx * by)
           - (bx * bx + by * by) * (ax * cy - cx * ay)
           + (cx * cx + cy * cy) * (ax * by - bx * ay))
    orient = _cross(b[0] - a[0], b[1] - a[1], c[0] - a[0], c[1] - a[1])
    return det > 0 if orient > 0 else det < 0


def delaunay(pos, size, seed):
    qx = pos[0] / size
    qy = pos[1] / size
    pts = feature_points(qx, qy, seed)
    q = (qx, qy)
    # ブロック選択: z の優先順は本家 movc 連鎖 (0 -> 1 -> 3/4) の解釈に基づく。
    # 四角形は (A, B, D, C) の周回で内外判定する。
    chosen = None
    for z in (0, 1, 3, 4):
        a, b, c, d = pts[z], pts[z + 1], pts[z + 3], pts[z + 4]
        if _in_triangle(q, a, b, d) or _in_triangle(q, a, d, c):
            chosen = (a, b, c, d)
            break
    if chosen is None:
        a, b, c, d = pts[0], pts[1], pts[3], pts[4]
        chosen = (a, b, c, d)
    a, b, c, d = chosen
    # 対角線選択: 対角線 B-C が Delaunay になるのは D が三角形 ABC の
    # 外接円内にある場合。その場合は三角形 (B, C, D) / (B, D... ) ではなく
    # (A, B, C) と (B, C, D) の分割になる。
    if _incircle(a, b, c, d):
        tris = [(a, b, c), (b, c, d)]
    else:
        tris = [(a, b, d), (a, d, c)]
    for t in tris:
        if _in_triangle(q, *t):
            g = _centroid(*t)
            return (g[0] * size, g[1] * size)
    g = _centroid(*tris[0])
    return (g[0] * size, g[1] * size)
