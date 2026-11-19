#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Material Design Icons (MDI) のパス辞書 Swift ファイルを生成する。

本家 YMM4 は MDI 全アイコンのパス図形を XAML リソース辞書として埋め込む
方式（materialdesignicongeometries.g.xaml + GeometryKeys.cs）。Mac 版は
同じ構造に寄せ、画面で実際に使うアイコンだけを Swift の辞書として
生成する（調査: analysis-notes/ICON-MDI-MAPPING.md の方針 B）。

入手元は @mdi/svg v7.4.47（Pictogrammers 公式 npm パッケージ）。
バージョンは本家 GeometryKeys.cs のキー一覧（7,447 件）と meta.json の
名前一覧の突き合わせで確定した（変換規則の差を除き完全一致。詳細は
docs/IMPLEMENTATION_LOG.md の ICON-MDI 節）。

使い方:
    npm pack @mdi/svg@7.4.47            # 取得（リポジトリには入れない）
    tar xzf mdi-svg-7.4.47.tgz          # package/ ができる
    python3 generate-mdi-icons.py package \
        [--geometry-keys <GeometryKeys.cs へのパス>] \
        [--output <出力 Swift ファイル>]

--geometry-keys を渡すと、本家のキー一覧と meta.json の名前一覧を
突き合わせて一致率を表示する（バージョン推定の再検証用）。
--output の既定は ../Sources/AppIcons/MDIIconPaths.swift。
生成は決定的（名前順ソート、書式固定）で、再実行すると同一結果になる。
"""

import argparse
import json
import os
import re
import sys

# 採用アイコン（kebab-case の公式名）。対応表の置き換え対象と、
# 本家合成アイコンの再構成に必要な素材だけを入れる。全 7,447 件は入れない。
# 出自の内訳は docs/IMPLEMENTATION_LOG.md の ICON-MDI 節に対応表がある。
ICON_NAMES = [
    # アイテム種別（本家 IconKeys.YMM4 の割り当て = 確定）
    "message-text-outline",  # ボイス
    "format-text",           # テキスト
    "video",                 # 動画
    "music",                 # 音声
    "image",                 # 画像
    "shape-plus",            # 図形
    "account",               # 立ち絵
    "emoticon-outline",      # 顔
    "image-auto-adjust",     # エフェクト
    "gradient-horizontal",   # トランジション
    "chart-timeline",        # シーン
    "image-multiple",        # フレームバッファ
    "select-group",          # グループ
    "book",                  # テンプレート（種別としても使う）
    # トランスポート
    "play",
    "pause",
    "stop",
    "rotate-left",           # リピート合成（RepeatCircleArrow）の素材
    "fit-to-page",           # フィット（対応候補）
    "skip-previous",
    "step-backward-2",
    "step-backward",
    "step-forward",
    "step-forward-2",
    "skip-next",
    "volume-high",
    "volume-off",
    "vector-bezier",         # 制御点表示（対応候補）
    # ツールバー・その他画面
    "magnify",
    "fit-to-screen",         # 全体表示（対応候補）
    "history",               # 最近使ったファイル（対応候補）
    "undo",
    "redo",
    "content-cut",
    "content-copy",
    "content-paste",
    "paper-cut-vertical",    # 分割（対応候補）
    "group",                 # グループ化（対応候補）
    "ungroup",               # グループ解除（対応候補）
    "vector-difference-ab",  # クリッピング合成（VectorClipping）の素材
    "lock",
    "lock-open-outline",     # ロック解除（対応候補）
    "waveform",              # 波形表示。波形オフ合成の素材も兼ねる
    "grid",
    "delete",
    "delete-sweep",          # 削除して詰める（対応候補）
    "contain-start",         # 左側を選択（対応候補）
    "contain-end",           # 右側を選択（対応候補）
    "select-all",
    "chevron-down",
    "chevron-right",
    "altimeter",             # メーターメニュー（対応候補）
    "file-plus",             # 新規プロジェクト（対応候補）
    "folder-open",           # プロジェクトを開く（対応候補）
    "content-save",
    "file-outline",          # EXO 出力合成（FileFilmstripOutline）の素材
    "filmstrip",             # EXO 出力合成の素材
    "animation-play",        # 動画出力（対応候補）
    "camera",                # サムネイル保存（対応候補）
    "message-alert-outline", # フィードバック（対応候補）
    "plus",                  # エフェクト追加
    "minus-circle",          # エフェクト削除（対応候補。形状一致で選択）
    "eye",                   # レイヤー表示
    "eye-off",               # レイヤー非表示
    "dots-vertical",         # レイヤー操作メニュー（対応候補）
    "account-edit",          # キャラクター設定を開く（対応候補）
]


def kebab_to_pascal(name):
    """meta.json の kebab 名を本家 GeometryKeys.cs の PascalCase へ変換する。

    本家の変換は数字の直後の英字も大文字にする（3d -> 3D、2g -> 2G、4k -> 4K）。
    """
    parts = []
    for part in name.split("-"):
        part = re.sub(r"(\d)([a-z])", lambda m: m.group(1) + m.group(2).upper(), part)
        parts.append(part[:1].upper() + part[1:])
    return "".join(parts)


def verify_version(package_dir, geometry_keys_path):
    meta = json.load(open(os.path.join(package_dir, "meta.json"), encoding="utf-8"))
    mdi_names = {kebab_to_pascal(m["name"]) for m in meta}
    src = open(geometry_keys_path, encoding="utf-8-sig").read()
    honke = set(re.findall(r"public const string (\w+)\s*=", src))
    diff = honke ^ mdi_names
    print(f"突き合わせ: 本家 {len(honke)} 件 / MDI {len(mdi_names)} 件 / "
          f"一致 {len(honke & mdi_names)} 件 / 差分 {len(diff)} 件")
    if diff:
        print("差分:", sorted(diff)[:20])
    return not diff


def extract_path(svg_path):
    text = open(svg_path, encoding="utf-8").read()
    m = re.search(r'\bd="([^"]+)"', text)
    if not m:
        raise ValueError(f"パスデータが見つからない: {svg_path}")
    return m.group(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package_dir", help="@mdi/svg を展開した package/ ディレクトリ")
    parser.add_argument("--geometry-keys", help="本家 GeometryKeys.cs へのパス（バージョン再検証）")
    parser.add_argument("--output", help="出力 Swift ファイル")
    args = parser.parse_args()

    if args.geometry_keys:
        if not verify_version(args.package_dir, args.geometry_keys):
            print("警告: バージョン推定は確定しなかった（差分あり）。生成は続行する。",
                  file=sys.stderr)

    svg_dir = os.path.join(args.package_dir, "svg")
    entries = []
    for name in sorted(set(ICON_NAMES)):
        svg_path = os.path.join(svg_dir, name + ".svg")
        if not os.path.exists(svg_path):
            print(f"エラー: アイコンが存在しない: {name}", file=sys.stderr)
            return 1
        entries.append((name, extract_path(svg_path)))

    output = args.output or os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "..", "Sources", "AppIcons", "MDIIconPaths.swift")

    lines = []
    lines.append("// このファイルは Tools/generate-mdi-icons.py が生成した。手で編集しないこと。")
    lines.append("//")
    lines.append("// 素材: Material Design Icons (@mdi/svg v7.4.47、Pictogrammers)。")
    lines.append("// アイコンは Apache License 2.0。ライセンス文は")
    lines.append("// Apps/DebugApp/Resources/License/Material Design Icons.txt に同梱。")
    lines.append("// パスデータは SVG の d 属性をそのまま文字列化した改変物である。")
    lines.append("// 本家 YMM4 も全アイコンのパス図形を辞書として埋め込む方式であり、")
    lines.append("// Mac 版は画面で使う分だけを同方式で持つ（ICON-MDI-MAPPING.md 方針 B）。")
    lines.append("")
    lines.append("/// MDI アイコン名（kebab-case）→ SVG パスデータ（24×24 キャンバス）。")
    lines.append("public enum MDIIconPaths {")
    lines.append("    public static let paths: [String: String] = [")
    for name, d in entries:
        lines.append(f'        "{name}": "{d}",')
    lines.append("    ]")
    lines.append("}")
    lines.append("")

    with open(output, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"生成完了: {output}（{len(entries)} アイコン）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
