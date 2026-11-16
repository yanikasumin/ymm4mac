# 引継書 — 次の作業者はここから読む

更新: **2026-11-16**。現状: 開発リポジトリ初期設定。アプリコードはまだなし。

## 作業環境とリポジトリ

- Macネイティブ開発: https://github.com/yanikasumin/ymm4mac （Public、main。2026-11-16にオーナーが変更）
- 本家解析: https://github.com/yanikasumin/ymm4-native-research （Public、2026-11-16にオーナーが変更）
- 要件定義: https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/REQUIREMENTS.md
- 要件定義の履歴: [初版v0.1 PR #1](https://github.com/yanikasumin/ymm4-native-research/pull/1)はマージ済み。オーナーの承認は**Muse経由の伝達**で受領し、v1.0が2026-11-16に正式発効。[正式化PR #2](https://github.com/yanikasumin/ymm4-native-research/pull/2)はマージ済み（`1fbc38827552272cb20bf28b960f264b668a29ea`）。本人の原発言の正確な日時は不明。
- 本家解析の基準コミット: `9e2ea95e88d2e20cb30b7040f53ef521a4c0b412`
- 開発初期化の最初のコミット: `eb4201ceaad6997406e5c8aaea779ce8e1b02858`
- 既存Wine系の別プロジェクト: https://github.com/yanikasumin/YMM4M-custom （対象外）

## 現時点で完了

- 新しい開発リポジトリの作成を確認（当初Private、現在はPublic）。
- READMEと開発ルール・As-built・詳細実装記録の最初の構成を設置。
- 本家解析や要件は解析repoに残し、相互参照するようにした。
- **UI、動画デコード、GPU合成、音声、書き出しの実装はまだない。**

## 次にすること

1. 要件定義v1.0を正式なベースラインとして維持し、以降の変更・例外実装には本人の事前承認を求める。
2. [本家の6境界解析](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/11-RENDERING-OWNERSHIP-BOUNDARIES.md)を参照し、ChatGPTが次に提示する具体的な実装仕様を待って対象作業を確定する。Swift/C#、描画方式は未決定。
3. 現実のコードと試験に基づいて実装を開始し、`IMPLEMENTATION_LOG.md`に自然言語で逐次説明する。
4. 各セッションで実装のコードパス、コミット、テスト、未解決事項をここへ更新する。

## 中断前チェックリスト

- [ ] 変更したファイル・シンボル・コミットが実装台帳に記録されている
- [ ] 変更の理由・具体的動作・本家との差分・Mac固有リソース所有権が説明されている
- [ ] 重要な実装の結果と失敗条件、テスト手順が記録されている
- [ ] As-built、課題、解析側の互換マトリクスが整合している
- [ ] 要件逸脱は事前承認を得ており、未承認例外をマージしていない
- [ ] 次の作業と現在のブランチ・コミットが書かれている

## 2026-11-16 更新 — 正式要件v1.0同期（本PRはレビュー待ち）

本家解析リポジトリで[PR #2](https://github.com/yanikasumin/ymm4-native-research/pull/2)がマージされ、要件v1.0が正式発効した。今回の`ymm4mac`側作業は`README.md`、`AGENTS.md`、`docs/STATUS.md`、`docs/HANDOFF.md`の承認状態とPublic表記の同期に限る。**本開発リポジトリ側PRはMuseの差分レビューと本人判断までマージしない。** 実装コード、技術選定、ビルド、テストは変更していない。
