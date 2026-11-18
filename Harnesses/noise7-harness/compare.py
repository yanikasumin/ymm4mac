#!/usr/bin/env python3
"""Compare harness output (actual bytes) with interpreter refs."""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))


def load_ref(name, color):
    path = os.path.join(HERE, "refs", name + ".csv")
    rows = []
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        if color:
            rows.append([[int(p) for p in cell.split(":")]
                         for cell in line.split(",")])
        else:
            rows.append([int(v) for v in line.split(",")])
    return np.array(rows)


def main(dump_path):
    actual = {}
    cur = None
    for line in open(dump_path):
        line = line.strip()
        if line.startswith("CASE "):
            cur = line[5:]
            actual[cur] = {}
        elif line.startswith(("R ", "G ", "B ")) and cur:
            actual[cur][line[0]] = np.array(
                [int(v) for v in line[2:].split(",")]).reshape(32, 32)
        elif "RENDER-FAILED" in line:
            print(f"{line}: RENDER FAILED")
    sys.path.insert(0, HERE)
    import combos
    worst = []
    for c in combos.CASES:
        name = c["name"]
        if name not in actual:
            print(f"{name}: MISSING in harness output")
            worst.append((name, 999))
            continue
        ref = load_ref(name, c["color"])
        if c["color"]:
            diffs = []
            for ci, ch in enumerate("RGB"):
                d = np.abs(actual[name][ch].astype(int) - ref[:, :, ci])
                diffs.append(d)
            d = np.max(np.stack(diffs), axis=0)
        else:
            d = np.abs(actual[name]["R"].astype(int) - ref)
        mx = int(d.max())
        mean = float(d.mean())
        over2 = int((d > 2).sum())
        over5 = int((d > 5).sum())
        status = "OK" if mx == 0 else "MISMATCH"
        print(f"{name}: max={mx} mean={mean:.3f} >2:{over2} >5:{over5} {status}")
        worst.append((name, mx))
    bad = [n for n, m in worst if m > 0]
    print("summary:", "ALL OK" if not bad else f"needs work: {bad}")
    if bad:
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1])
