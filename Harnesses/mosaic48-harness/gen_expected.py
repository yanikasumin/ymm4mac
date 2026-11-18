#!/usr/bin/env python3
"""mosaic48-harness の入力画像と期待フレームを生成する。

期待値は本家カスタムシェーダの DXBC 逆アセンブルから抽出した参照実装
(../../mosaic48-scratch の shader_reference.py と同じ式) に、Metal の
線形サンプラ (テクセル中心基準、範囲外は透明) を組み合わせて作る。
出力先は /tmp/mosaic48/ (ハーネスの作業ディレクトリ)。

入力パターンは画素座標の符号化 (R = x*4, G = y*4, B = (x + 2y) mod 256,
A = 255) で、サンプル元の画素を出力色から追えるようにしてある。
フレーム画素 (x, y) の平面座標は (-32 + x + 0.5, -32 + y + 0.5)。

実行には numpy が必要 (float32 丸めの再現用)。検証用 Mac には
numpy が無いため、生成は VM 側で行い、/tmp/mosaic48/ の生成物を
Mac の同パスへ転送してからハーネスを実行する。
"""
import math
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_reference as ref  # noqa: E402

W = 64
H = 64
OUT = "/tmp/mosaic48"


def input_pixel(x, y):
    return (x * 4, y * 4, (x + 2 * y) % 256, 255)


def sample_linear(sx, sy):
    """平面座標 (sx, sy) を入力画像から線形サンプルする (範囲外は透明)。"""
    u = sx + W / 2.0
    v = sy + H / 2.0
    fu = u - 0.5
    fv = v - 0.5
    i0 = math.floor(fu)
    j0 = math.floor(fv)
    tu = fu - i0
    tv = fv - j0
    acc = [0.0, 0.0, 0.0, 0.0]
    for dj in (0, 1):
        for di in (0, 1):
            w = (tu if di else 1 - tu) * (tv if dj else 1 - tv)
            ii = i0 + di
            jj = j0 + dj
            if 0 <= ii < W and 0 <= jj < H:
                p = input_pixel(ii, jj)
                for c in range(4):
                    acc[c] += w * p[c]
    return acc


def expected_frame(shape, size, seed=0.0):
    """期待フレームを BGRA バイト列で返す。"""
    out = bytearray()
    for y in range(H):
        for x in range(W):
            pos = (-W / 2.0 + x + 0.5, -H / 2.0 + y + 0.5)
            if shape == "circle":
                sp = ref.circle(pos, size)
                color = [0.0, 0.0, 0.0, 0.0] if sp is None else sample_linear(*sp)
            elif shape == "triangle":
                color = sample_linear(*ref.triangle(pos, size))
            elif shape == "hexagon":
                color = sample_linear(*ref.hexagon(pos, size))
            elif shape == "voronoi":
                color = sample_linear(*ref.voronoi(pos, size, seed))
            elif shape == "delaunay":
                color = sample_linear(*ref.delaunay(pos, size, seed))
            else:
                raise ValueError(shape)
            r, g, b, a = (int(round(c)) for c in color)
            out += bytes((b, g, r, a))
    return bytes(out)


def write_png(path):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = bytearray()
    for y in range(H):
        raw.append(0)
        for x in range(W):
            r, g, b, a = input_pixel(x, y)
            raw += bytes((r, g, b, a))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw)))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


CASES = [
    ("circle16", "circle", 16.0, 0.0),
    ("triangle16", "triangle", 16.0, 0.0),
    ("hexagon16", "hexagon", 16.0, 0.0),
    ("voronoi16", "voronoi", 16.0, 0.0),
    ("delaunay16", "delaunay", 16.0, 0.0),
    ("circle10", "circle", 10.0, 0.0),
    ("voronoi13", "voronoi", 13.0, 0.0),
    ("triangle20", "triangle", 20.0, 0.0),
    ("hexagon12", "hexagon", 12.0, 0.0),
    ("delaunay18", "delaunay", 18.0, 0.0),
    # サイズアニメーション検証用 (直線移動 8 -> 24 の両端)
    ("circle8", "circle", 8.0, 0.0),
    ("circle24", "circle", 24.0, 0.0),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    write_png(os.path.join(OUT, "ident.png"))
    for name, shape, size, seed in CASES:
        data = expected_frame(shape, size, seed)
        with open(os.path.join(OUT, f"expected_{name}.bin"), "wb") as f:
            f.write(data)
        print(f"{name}: {len(data)} bytes")
    print("done")


if __name__ == "__main__":
    main()
