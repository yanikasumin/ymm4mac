#!/usr/bin/env python3
"""Issue #104: ハーネス出力（/tmp/ht104/*.csv）と、修正済み DXBC
インタプリタで生成した凍結期待値（refs/）を比較する。

許容差（バイト）: 菱形・矩形は 0（完全一致が実測済み）。三角は 2
（部分被覆の縁画素で、GPU サンプラの補間精度に起因するとみられる
+2 までの残差が実測されている。docs/IMPLEMENTATION_LOG.md の
#104 節参照）。上限を超えたら非 0 終了。
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
        for y, row in enumerate(ref):
            for x, px in enumerate(row):
                d = max(abs(px[c] - act[y][x][c]) for c in range(4))
                maxd = max(maxd, d)
                if d > tol:
                    over += 1
        status = "PASS" if over == 0 else "FAIL"
        if over:
            failed = True
        print(f"{status}: {name}: max diff {maxd} (tolerance {tol}), "
              f"pixels over: {over}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
