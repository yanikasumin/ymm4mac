# ymm4mac

macOSネイティブ版 YukkuriMovieMaker 4 移植プロジェクト。

開発リポジトリ `yanikasumin/ymm4mac` と解析リポジトリ `yanikasumin/ymm4-native-research` は、ともに**Public**（2026-11-16にオーナーが変更）。

**現状:** 開発リポジトリの初期設定中。映像編集機能の実装・動作はまだ確認されていません。

## 開発方針

- **UI・操作:** 本家YMM4の画面構成・操作体系・編集結果に可能な限り忠実。
- **バックエンド:** Windows依存を、同等機能を持つmacOS標準APIや実績あるOSSで機能代替。
- **品質:** 高速、安定、軽量、簡潔な設計、読みやすいコード。
- **対象:** macOS、Apple Silicon優先。Wine・Windows仮想環境に依存しない。
- **変更管理:** 要件変更・例外実装は事前に理由と影響を説明し、ユーザー承認を得る。

## 仕様と解析資料

要件定義・本家の逆コンパイル解析・設計仮説の参照元:

- [解析リポジトリ](https://github.com/yanikasumin/ymm4-native-research)
- [要件定義](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/REQUIREMENTS.md)
- [本家の設計図](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/01-ORIGINAL-ARCHITECTURE.md)
- [Mac版の設計案](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/02-MAC-DESIGN-PROPOSAL.md)
- [全体進捗と課題](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/04-STATUS-ISSUES.md)

**要件定義の正式な状態:** [v1.0](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/REQUIREMENTS.md)は、オーナーが初版v0.1の内容を承認し、2026-11-16に正式発効した。承認は**Muse経由の伝達**として記録され、[正式化PR #2](https://github.com/yanikasumin/ymm4-native-research/pull/2)はマージ済み（`1fbc38827552272cb20bf28b960f264b668a29ea`）。新たな要件変更・例外実装には引き続き本人の明示承認が必要。

## このリポジトリの文書

- [AGENTS.md](AGENTS.md): 作業者向けの開発規則
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): Mac版の**実際の**構造（実装ができたら追記）
- [docs/IMPLEMENTATION_LOG.md](docs/IMPLEMENTATION_LOG.md): 「何を・どこに・どう」実装したかの自然言語解説
- [docs/STATUS.md](docs/STATUS.md): 実装進捗・未解決問題
- [docs/HANDOFF.md](docs/HANDOFF.md): 作業中断・再開用
