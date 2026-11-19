#!/usr/bin/env python3
"""FE-R1-031 計測 JSONL の集計。

results/*.jsonl を読み、(label, kind, temp) ごとに件数・平均・p50・
p95・最大を出す。パーセンタイルは nearest-rank（ソート済み列の
ceil(p/100 * n) 番目、1 始まり）。

使い方: aggregate.py [jsonl ...]（省略時は results/*.jsonl 全部）
"""
import glob
import json
import math
import sys
from collections import defaultdict

FIELDS = {
    "snapshot": ["encodeMs", "decodeMs", "totalMs", "encodedBytes"],
    "snapshot-cold-total": ["totalMs"],
    "worker-install": ["roundTripMs"],
    "worker-render": ["roundTripMs"],
    "worker-swap": ["roundTripMs"],
    "reflect-chain": ["snapshotMs", "afterSnapshotMs", "chainTotalMs"],
}


def pct(sorted_xs, p):
    if not sorted_xs:
        return float("nan")
    idx = max(1, math.ceil(p / 100.0 * len(sorted_xs)))
    return sorted_xs[idx - 1]


def main() -> None:
    paths = sys.argv[1:] or sorted(
        glob.glob("results/*.jsonl") + glob.glob("Harnesses/snapshot031-harness/results/*.jsonl")
    )
    groups = defaultdict(lambda: defaultdict(list))
    outcomes = defaultdict(lambda: defaultdict(int))
    for path in paths:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                rec = json.loads(line)
                kind = rec.get("kind")
                if kind not in FIELDS:
                    continue
                label = rec.get("label", "?")
                temp = rec.get("temp", "-")
                key = (label, kind, temp)
                for field in FIELDS[kind]:
                    if field in rec:
                        groups[key][field].append(float(rec[field]))
                if "outcome" in rec:
                    outcomes[key][rec["outcome"]] += 1
    for (label, kind, temp) in sorted(groups):
        print(f"== label={label} kind={kind} temp={temp}")
        for field, xs in sorted(groups[(label, kind, temp)].items()):
            xs.sort()
            n = len(xs)
            print(
                f"  {field}: n={n} mean={sum(xs)/n:.3f} "
                f"p50={pct(xs, 50):.3f} p95={pct(xs, 95):.3f} max={xs[-1]:.3f}"
            )
        if outcomes[(label, kind, temp)]:
            print(f"  outcomes: {dict(outcomes[(label, kind, temp)])}")


if __name__ == "__main__":
    main()
