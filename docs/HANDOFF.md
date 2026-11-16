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

## 2026-11-16 更新 — モデル層の土台を実装（MAC-0001、未コミット）

- `Package.swift` と `Sources/YMM4Core/`（VideoInfo・Animation・KeyFrames・AnimationType・FrameTime・Color）、`Tests/YMM4CoreTests/` を新規追加した。作業ツリー上の変更であり、コミット・push はまだ行っていない。
- 仕様の正本は解析側の `MODEL-SPEC-EXTRACTION.md`（訂正記録を含む）§3・§6。キーフレーム連動は「キーフレーム対応の AnimationType のみ」という訂正済みの理解で実装済み。
- テスト実行: VM 上の Swift（`~/workspace/tools/swift-6.1.2/usr/bin/swift test` をリポジトリルートで実行）で全26件合格。macOS でのビルドは未実施。
- 未実装（本家の数式・方式が未抽出のため）: イージング関数の数式、スプライン重み（Cubic.GetWeight）、ベジェ評価、ランダム移動の乱数生成、反復移動の Span>0。該当箇所はコード内に暫定である旨を明記した。
- 次の作業: 上記数式群の抽出、Timeline / BaseItem の実装、KeyFrames の RemovesLeft/RemovesRight。

## 2026-11-16 更新 — Animation 評価の数式置き換え（MAC-0002、未コミット）

- 数式群の抽出が完了（解析側 `ANIMATION-FORMULAS.md`、全項目確定済み）し、暫定評価を全て置き換えた。新規ファイル: `Sources/YMM4Core/Easing.swift`、`Cubic.swift`、`StatelessRandom.swift`、`BezierAnimation.swift`。`Animation.swift` の評価は本家 `GetValue` の分岐連鎖どおりに再構成し、キーフレーム系4経路は最終処理を通らない早期 return とした（MAC-0001 の全型への最終処理適用は本家と異なる暫定措置だった）。
- 仕様書側の誤り（_Int の割り当てが逆）は解析側 `MODEL-SPEC-EXTRACTION.md` の訂正記録4に記録した。本文 §6.3・§6.4 の書き換えはしていない。
- 実装上の判断: 補間移動経路のループ上限は `ANIMATION-FORMULAS.md` §1.1 の擬似コード表記ではなく本家 `Animation.cs` の実コード（区間数 + 1 まで、末尾フォールバックで最後の値）を優先した。数式側の確認事項として残す。
- テスト実行: VM 上の Swift（`~/workspace/tools/swift-6.1.2/usr/bin/swift test`）で全60件合格（従来26件＋新規34件）。既存テストの期待値修正2件（反復移動 Span = 0 のパリティ反転、瞬間移動の最終フレーム＝最後の区間の開始値）はいずれも本家コードに合わせたもの。
- 未確定事項: ランダム移動のシード材料である本家 `GetHashCode()` の具体値との対応付け（Swift 側は `Animation.randomSeed` で代用し、決定的性質のみ保証）。本家実機での乱数列採取が必要。
- 次の作業: Timeline / BaseItem の実装、KeyFrames の RemovesLeft/RemovesRight、Golden Master 比較素材の整備。
