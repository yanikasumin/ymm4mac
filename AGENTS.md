# 作業者向け開発規則

このリポジトリは **Wineを用いないYMM4のmacOSネイティブ移植**用。対象はApple Silicon（arm64）専用とし、Intel Macは対応しない。最低対応OSはmacOS 26.0 Tahoe。実装言語はSwift（2026-11-16にオーナーが決定、CR-002）。ユーザーから見たUI・操作は本家YMM4に可能な限り忠実とする。開発リポジトリと解析リポジトリはいずれも**Public**。MuseはGitHub Appの対象リポジトリ追加（2026-11-16）により、ブランチ作成・ファイルpush・PR作成・マージを直接実行できる。変更はPR経由で行い、実際の差分を検証する。

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

## 文書の更新規則（イベント別）

文書は変更の種類に応じて更新する。**重要なのは、すべての変更がすべての文書を更新することではなく、変更された事実の正本が確実に更新されることである。**

| イベント | 必須更新 | 条件付き更新 |
|---|---|---|
| 純粋なファイル移動・改名 | PR、必要な参照パス | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| 機能追加・重要な修正 | PR（検証記録）、該当する課題の状態 | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)、[docs/IMPLEMENTATION_LOG.md](docs/IMPLEMENTATION_LOG.md) |
| 処理経路・所有権の変更 | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)、PR | — |
| 本家との互換性変更 | 解析側の[互換マトリクス](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/07-COMPATIBILITY-MATRIX.md)、PR | [docs/STATUS.md](docs/STATUS.md) |
| 未解決問題の発見・解消 | 課題台帳（未解決事項の正本。[GitHub Issues](https://github.com/yanikasumin/ymm4mac/issues) が担う。本文を文書側へ複製しない） | [docs/STATUS.md](docs/STATUS.md) の主要な未解決（概要のみ） |
| 要件変更・例外 | 解析側の[変更承認台帳](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/08-DECISIONS-CHANGES.md)、[要件定義](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/REQUIREMENTS.md) | — |
| 作業中断・担当交代 | [docs/HANDOFF.md](docs/HANDOFF.md) | — |

各文書の正本としての役割: [docs/STATUS.md](docs/STATUS.md) は現行状態、[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) は実際のクラス構成とデータフロー（構想図を実装済みと称さない）、[docs/IMPLEMENTATION_LOG.md](docs/IMPLEMENTATION_LOG.md) は実装判断の経緯（何を、どのrepo/commit/ファイル/クラス/関数に、どう実装したか。本家との差分・採用理由・メモリ所有権・テストと未確認事項を含む）、[docs/HANDOFF.md](docs/HANDOFF.md) は次の作業。解析側の[Mac As-built](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/03-MAC-AS-BUILT.md)と互換マトリクスは、対応する実装確定時に同期する。

本家との差は「内部実装の違い」と「ユーザーから見える違い」を分ける。比較試験がないものはVERIFIEDとしない。

## 要件変更の承認

要件定義の実質変更、機能削除、操作体系の逸脱、例外実装が必要なら理由・本家との差・影響・代替案を整理し、**ユーザーの明示的承認までその仕様の実装を開始・マージしない**。単なる設計仮説の追加と承認済み仕様の改訂を区別する。

**正式な開発基準は、[要件定義v1.2](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/REQUIREMENTS.md)である（2026-11-16発効）。** v1.1で最低対応OSをmacOS 26.0 Tahoeに確定し（CR-001）、v1.2で実装言語をSwiftに確定した（CR-002）。REQ条項56件の本文は初版から不変。以後の実質的な要件変更・例外実装は、別途本人の明示承認を要する。

## GitHubでのレビュー

PRには要件ID、本家根拠、変更したシンボル、主要な設計判断、実行したテスト、対応する実装記録、承認状況を書く。コードの根拠がない仕様上の成功宣言をしない。

## 基本指示 第1.1版の反映（2026-11-16転記）

本repoの作業規則の上位規範として、ChatGPT発行の「基本指示 第1.1版」（2026-11-16）を反映する。全文はプロジェクト記録に保存済み。要点は以下のとおりで、上記の各規則と矛盾する場合は基本指示と承認済み要件定義が優先する。

- **優先順位**: (1) 本家との編集結果・機能・操作互換性、(2) 安定性・データ保全・メモリ安全性、(3) 速度・低遅延・軽量性、(4) コードの簡明性・可読性・保守性、(5) 実装上の変更量の最小化。バベルの塔のような継ぎ接ぎ設計（場当たり的な条件分岐、同一機能の複数経路、不要な抽象化の重ね掛け）を禁止する。
- **役割**: オーナーが要件の最終決定・変更・例外実装を承認する。ChatGPTが本家解析・仕様抽出・技術仕様の策定・レビュー・QAを担う。Museが実コードの調査・実装・ビルド・テスト・GitHub操作・文書更新を担う。承認権限はChatGPTにもMuseにも移譲されない。
- **Museの設計判断の制限**: 実装方式が複数ある場合、新しい技術を採用する場合、既存の処理構造を変える場合、指示と実コードが矛盾する場合は、ChatGPTに問題と選択肢を提示する。技術的な誤りを指摘してよいが、代替設計を無断で確定しない。命名・整形・既定仕様の範囲内の局所的なバグ修正・テスト追加は通常作業として進めてよい。
- **標準工程**: Phase 1 解析（未確認事項を推測で補わない）→ Phase 2 仕様確定 → Phase 3 実装 → Phase 4 検証（未実施のテストは「未実施」と記録する）→ Phase 5 レビュー・記録（指摘を解決してからPRをマージする）。
- **コーディング**: 逆コンパイル由来の不明瞭な名称（num2、flag3等）を持ち込まない。逆コンパイルコードを実装コードへ複写しない（仕様抽出の参照資料としてのみ扱う）。コメントは動作の言い換えではなく、仕様上の理由・制約・設計判断を書く。リソースごとに生成者・所有者・借用者・解放責任者を明確にし、GPUコマンドが使用中の資源を先に解放・再利用しない。
- **報告形式**: 作業報告は「決定済み／検証済み／未解決」の3区分で行う。VERIFIEDは実際に検証した範囲にのみ使う。画素差や性能の許容値をMuseが独断で確定しない。
- **未確定事項**（基本指示 第9章。ただし後段の決定で更新済みのものを含む）: UI実装方式（AppKit/SwiftUI等）、描画方式（Metal/Core Image等）、音声合成エンジンとプラグインの個別互換性、性能・メモリの定量目標、画素単位一致が必要な範囲。実装言語（Swift基本＋理由を明示した例外容認）、最低対応macOS（26.0固定）、Intel Mac非対応は本人の決定により確定済みであり、未確定として扱わない。
