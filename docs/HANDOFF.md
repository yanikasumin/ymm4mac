# 引継書 — 次の作業者はここから読む

更新: **2026-11-16**。現状: 開発リポジトリ初期設定。アプリコードはまだなし。

## 作業環境とリポジトリ

- Macネイティブ開発: https://github.com/yanikasumin/ymm4mac （Private、main）
- 本家解析: https://github.com/yanikasumin/ymm4-native-research （Private）
- 要件定義: https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/REQUIREMENTS.md
- v0.1の要件PR: https://github.com/yanikasumin/ymm4-native-research/pull/1 （**オーナーによってマージ済み**。ただし文書の未承認表記・v0.1の正式な扱いは要確認）
- 本家解析の基準コミット: `9e2ea95e88d2e20cb30b7040f53ef521a4c0b412`
- 開発初期化の最初のコミット: `eb4201ceaad6997406e5c8aaea779ce8e1b02858`
- 既存Wine系の別プロジェクト: https://github.com/yanikasumin/YMM4M-custom （対象外）

## 現時点で完了

- 新しいPrivate開発リポジトリの作成を確認。
- READMEと開発ルール・As-built・詳細実装記録の最初の構成を設置。
- 本家解析や要件は解析repoに残し、相互参照するようにした。
- **UI、動画デコード、GPU合成、音声、書き出しの実装はまだない。**

## 次にすること

1. 要件の正式版の扱いを確認し、要件の変更承認フローを維持する。
2. 本家クラスの依存を分析し、SwiftとC#の境界およびGPUの所有権を検証する。
3. 現実のコードと試験に基づいて実装を開始し、`IMPLEMENTATION_LOG.md`に自然言語で逐次説明する。
4. 各セッションで実装のコードパス、コミット、テスト、未解決事項をここへ更新する。

## 中断前チェックリスト

- [ ] 変更したファイル・シンボル・コミットが実装台帳に記録されている
- [ ] 変更の理由・具体的動作・本家との差分・Mac固有リソース所有権が説明されている
- [ ] 重要な実装の結果と失敗条件、テスト手順が記録されている
- [ ] As-built、課題、解析側の互換マトリクスが整合している
- [ ] 要件逸脱は事前承認を得ており、未承認例外をマージしていない
- [ ] 次の作業と現在のブランチ・コミットが書かれている
