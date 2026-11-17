#!/bin/bash
# YMM4 for Mac（デバッグ版）を .app バンドルに組み立てる。
#
# ビルド済み実行ファイルは単体では macOS の通常のアプリとして扱われず、
# Dock にアイコンが出ない（ウィンドウが他のアプリの後ろに埋もれる）。
# このスクリプトは SwiftPM でビルドした実行ファイルを、同梱の
# Info.plist と一緒に `YMM4 for Mac.app` へ組み立てて通常のアプリの
# 形にする。
#
# 使い方:
#   ./package-app.sh [出力先ディレクトリ]
#     出力先の既定は ~/Applications。組み立てた .app は Finder や
#     Dock から通常のアプリとして起動できる。
#   CONFIGURATION=debug ./package-app.sh
#     ビルド構成の既定は release。debug にも切り替えられる。
#
# 署名はアドホック（codesign --sign -）。ローカルビルド用の暫定形で、
# 配布用の Developer ID 署名・公証は行わない。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="YMM4 for Mac"
EXECUTABLE_NAME="YMM4MacDebug"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${1:-$HOME/Applications}"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"

cd "$SCRIPT_DIR"
swift build -c "$CONFIGURATION"
BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
cp "$BIN_PATH/$EXECUTABLE_NAME" "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
cp "$SCRIPT_DIR/Info.plist" "$APP_PATH/Contents/Info.plist"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"

codesign --force --sign - "$APP_PATH"

echo "組み立て完了: $APP_PATH"
