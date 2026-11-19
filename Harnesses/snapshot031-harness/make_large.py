#!/usr/bin/env python3
"""FE-R1-031 計測用の大規模合成プロジェクトを生成する。

中規模の実プロジェクト（upload.ymmp、単一タイムライン 158 アイテム）の
Timeline.Items を丸ごと複製して連結し、アイテム数を倍率分に水増しする。
合成プロジェクトである（実在の編集結果ではない）。アイテムは同一の
Frame / Layer に重なるが、デコードとスナップショット生成の計測には
影響しない。生成物はリポジトリ外へ出すこと（.ymmp は .gitignore 対象）。

使い方: make_large.py <入力.ymmp> <出力.ymmp> [倍率=3]
"""
import copy
import json
import sys


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    factor = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    with open(src, encoding="utf-8-sig") as f:
        data = json.load(f)
    timeline = data["Timeline"]
    items = timeline["Items"]
    timeline["Items"] = [copy.deepcopy(it) for _ in range(factor) for it in items]
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    print(f"items: {len(items)} x{factor} = {len(timeline['Items'])} -> {dst}")


if __name__ == "__main__":
    main()
