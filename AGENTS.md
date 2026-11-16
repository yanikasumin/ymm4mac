# 作業者向け開発規則

このリポジトリは **Wineを用いないYMM4のmacOSネイティブ移植**用。対象はApple Siliconを優先し、ユーザーから見たUI・操作は本家YMM4に可能な限り忠実とする。

## 作業開始時の必須確認

1. [要件定義](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/REQUIREMENTS.md) と[変更承認台帳](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/08-DECISIONS-CHANGES.md)を確認する。
2. 本repoの [docs/HANDOFF.md](docs/HANDOFF.md)、[docs/STATUS.md](docs/STATUS.md)、[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) を確認する。
3. [本家解析図](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/01-ORIGINAL-ARCHITECTURE.md) と[機能互換マトリクス](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/07-COMPATIBILITY-MATRIX.md)に基づき、対象機能を特定する。
4. 各作業について要件ID、本家の該当クラス、変更予定箇所、検証方法を把握する。

## 実装規則

- 本家UIと操作の互換性を最優先する。利便性のためと称して画面構成や既存機能を削らない。
- 本家の編集ドメイン計算、ファイルの意味、キーフレーム評価を可能な限り維持する。
- Windows固有のAPIはApple標準フレームワークや保守されたOSSで機能代替してよい。ただし性能・安定性・互換性・依存コストを検証する。
- モジュール境界を単純に保つ。過剰な抽象化、重複した計算系、場当たり的なパッチを避ける。
- GPU・音声・デコーダー・キャッシュ・外部プロセスについて所有者・解放タイミング・非同期キャンセルを明確化する。
- 実装コードを本家解析済みコードと混同しない。新規実装を記録・検証しやすい構成にする。

## コード変更と文書更新は一組

機能追加、重要なバグ修正、最適化、ライブラリ導入を行ったら、**同じ作業単位で**以下を更新する。

- [docs/IMPLEMENTATION_LOG.md](docs/IMPLEMENTATION_LOG.md): 何を、どのrepo/commit/ファイル/クラス/関数に、どう実装したか。入力から出力まで自然言語で説明し、本家との差分・採用理由・メモリ所有権・テストと未確認事項を記す。
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): 実際のクラス構成とデータフロー。構想図を実装済みと称さない。
- [docs/STATUS.md](docs/STATUS.md): 完了・未完了・ブロッカー・次の検証。
- [docs/HANDOFF.md](docs/HANDOFF.md): 次回担当がすぐ続きから始められる具体的な変更点、SHA、実行コマンド、エラー。
- 解析側の[Mac As-built](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/03-MAC-AS-BUILT.md)と[互換マトリクス](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/07-COMPATIBILITY-MATRIX.md)も、対応する実装確定時に同期する。

本家との差は「内部実装の違い」と「ユーザーから見える違い」を分ける。比較試験がないものはVERIFIEDとしない。

## 要件変更の承認

要件定義の実質変更、機能削除、操作体系の逸脱、例外実装が必要なら理由・本家との差・影響・代替案を整理し、**ユーザーの明示的承認までその仕様の実装を開始・マージしない**。単なる設計仮説の追加と承認済み仕様の改訂を区別する。

2026-11-16時点で解析repoの要件定義PR #1はオーナーによってマージされているが、要件文書の版表示はv0.1／未承認のまま。版確定は別途確認し、独断でv1.0と改名しない。

## GitHubでのレビュー

PRには要件ID、本家根拠、変更したシンボル、主要な設計判断、実行したテスト、対応する実装記録、承認状況を書く。コードの根拠がない仕様上の成功宣言をしない。
