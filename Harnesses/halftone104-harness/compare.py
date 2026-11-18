#!/usr/bin/env python3
"""Issue #104: ハーネス出力（/tmp/ht104/*.csv）と、修正済み DXBC
インタプリタで生成した凍結期待値（refs/）を比較する。

許容差（バイト）: 菱形・矩形は 0（完全一致が実測済み）。三角は 2
（部分被覆の縁画素で最大 +2 の残差が実測されている。残差の原因が
サンプラ補間精度か別の数値演算差かは未解決。docs/
IMPLEMENTATION_LOG.md の #104 節参照）。上限を超えたら非 0 終了。

R17-01 処分: 許容差だけでは「全画素が少しずつずれる」退行を
見逃すため、差分のある画素数にも上限を設ける。上限は実測
（三角 6.1 で 20 画素）に余裕を持たせた値で、異なる Apple
Silicon での数値差を吸収する。菱形・矩形は完全一致が前提なので
差分画素数 0 を要求する（許容差 0 と等価だが件数も明示する）。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ACTUAL = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ht104"
TOLERANCE = {
    "halftone-rhombus": 0,
    "halftone-rectangle": 0,
    "halftone-triangle": 2,
    "halftone-triangle-d43": 2,
}
# 差分（1 以上）のある画素数の上限。
MAX_DIFF_PIXELS = {
    "halftone-rhombus": 0,
    "halftone-rectangle": 0,
    "halftone-triangle": 128,
    "halftone-triangle-d43": 128,
}


def grid(path):
    return [[tuple(int(v) for v in cell.split(":"))
             for cell in line.strip().split(",")]
            for line in open(path)]


def main():
    failed = False
    for name, tol in TOLERANCE.items():
        ref = grid(os.path.join(HERE, "refs", name + ".csv"))
        act = grid(os.path.join(ACTUAL, name + ".csv"))
        if len(ref) != len(act) or len(ref[0]) != len(act[0]):
            print(f"FAIL: {name}: size mismatch")
            failed = True
            continue
        maxd = 0
        over = 0
        nonzero = 0
        for y, row in enumerate(ref):
            for x, px in enumerate(row):
                d = max(abs(px[c] - act[y][x][c]) for c in range(4))
                maxd = max(maxd, d)
                if d > 0:
                    nonzero += 1
                if d > tol:
                    over += 1
        cap = MAX_DIFF_PIXELS[name]
        status = "PASS" if over == 0 and nonzero <= cap else "FAIL"
        if status == "FAIL":
            failed = True
        print(f"{status}: {name}: max diff {maxd} (tolerance {tol}), "
              f"pixels over: {over}, diff pixels: {nonzero} (cap {cap})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
