# ymm4mac

macOSネイティブ版 YukkuriMovieMaker 4 移植プロジェクト。

開発リポジトリ `yanikasumin/ymm4mac` と解析リポジトリ `yanikasumin/ymm4-native-research` は、ともに**Public**（2026-11-16にオーナーが変更）。

**現状:** 実装進行中。モデル層・.ymmp互換層・描画（Metal）・音声・書き出しと、検証用のデバッグ用アプリ／製品UIの土台まで実装が進んでいる。現在地と未解決事項は [docs/STATUS.md](docs/STATUS.md)、作業規則は [AGENTS.md](AGENTS.md)、次にやることは [docs/HANDOFF.md](docs/HANDOFF.md) を参照。本家実機との互換テストは、本家を動かせる環境がないため未実施（検証は本家コードとの照合と自己往復の固定点確認に限定される）。

## 開発方針

- **UI・操作:** 本家YMM4の画面構成・操作体系・編集結果に可能な限り忠実。
- **バックエンド:** Windows依存を、同等機能を持つmacOS標準APIや実績あるOSSで機能代替。
- **品質:** 高速、安定、軽量、簡潔な設計、読みやすいコード。
- **対象:** macOS 26.0以降、Apple Silicon専用（Intel Macは非対応）。実装言語はSwift。Wine・Windows仮想環境に依存しない。
- **変更管理:** 要件変更・例外実装は事前に理由と影響を説明し、ユーザー承認を得る。

## 仕様と解析資料

要件定義・本家の逆コンパイル解析・設計仮説の参照元:

- [解析リポジトリ](https://github.com/yanikasumin/ymm4-native-research)
- [要件定義](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/REQUIREMENTS.md)
- [本家の設計図](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/01-ORIGINAL-ARCHITECTURE.md)
- [Mac版の設計案](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/02-MAC-DESIGN-PROPOSAL.md)
- [課題台帳（GitHub Issues）](https://github.com/yanikasumin/ymm4mac/issues): 未解決事項の正本は Issues が担う

**要件定義の正式な状態:** 現行の正式な開発基準は[要件定義 v1.2](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/REQUIREMENTS.md)（2026-11-16発効）。v1.1で最低対応OSをmacOS 26.0 Tahoeに確定し（CR-001）、v1.2で実装言語をSwiftに確定した（CR-002）。新たな要件変更・例外実装には引き続き本人の明示承認が必要。

## このリポジトリの文書

- [AGENTS.md](AGENTS.md): 作業者向けの開発規則
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): Mac版の**実際の**構造（As-built）
- [docs/IMPLEMENTATION_LOG.md](docs/IMPLEMENTATION_LOG.md): 「何を・どこに・どう」実装したかの自然言語解説
- [docs/STATUS.md](docs/STATUS.md): 実装進捗・未解決問題
- [docs/HANDOFF.md](docs/HANDOFF.md): 作業中断・再開用
