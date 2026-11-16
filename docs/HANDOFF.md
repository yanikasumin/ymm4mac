# 引継書 — 次の作業者はここから読む

更新: **2026-11-16**。現状: モデル層＋.ymmp 互換層まで実装済み（MAC-0005）。デバッグ用アプリの殻（MAC-0006、`Apps/DebugApp/`）を用意し、本人の Mac で開いて実 .ymmp の読み込みをデバッグできる段階。アプリ側の macOS ビルドは未実施（この VM では SwiftUI をビルドできない）。

## 2026-11-16 更新 — デバッグ用アプリの殻（MAC-0006）

- 本人の指示「明日の朝までに実ソフトでデバッグできる段階まで」で追加。開き方: 本人の Mac で `Apps/DebugApp/Package.swift` を Xcode で開いて実行する（または同ディレクトリで `swift run`）。
- できること: .ymmp を開く（読み込み診断＝未知 $type の読み飛ばし・型移行の一覧つき）、タイムライン／アイテム一覧、VisualItem の X/Y/Z アニメーションのスクラブ評価、往復固定点チェック、コピー保存。サンプル Animation の評価スクラブも残してある。
- 注意: 製品 UI ではなく検証の殻。UI 実装方式は未確定のまま。Package の platforms 宣言はハーネス都合で macOS 14 としてある（製品の最低対応は macOS 26.0 のまま）。

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

## 2026-11-16 更新 — モデル層の完成＋.ymmp 互換層（MAC-0003〜0005、未コミット）

- ドメインモデル（Project / Timeline / アイテム13クラス / Character / LayerSettings / TimelineVerticalLine）、編集操作（TryAddItems・衝突解決・グループ移動・分割・ChangeFrameRate・削除）、.ymmp 互換層（$type 解決・RenamedTypeResolver・未知要素の保持と診断記録・本家手順の保存）を実装した。詳細は実装台帳 MAC-0003〜0005。
- 新規ファイル: `Sources/YMM4Core/` に JSONValue / HonkeFormat / Enums / PlaybackRateMap / CodecSupport / Character / Project / Timeline / TimelineSupport / TimelineEditing / YmmpCodec と `Items/`（BaseItem / MediaItems / TextItems / CompositeItems）。変更: KeyFrames（RemovesLeft/Right）、Animation（setFirstValue・分割連動）。
- テスト実行: VM 上の Swift（`~/workspace/tools/swift-6.1.2/usr/bin/swift test`）で全87件合格（従来60件＋新規27件: TimelineEditingTests 15件、YmmpCodecTests 12件）。警告なし。macOS でのビルドは未実施（Foundation のみ）。
- 実装上の判断（台帳に記録済み）: アイテムは参照型（本家の編集意味論が前提）。未知 $type のアイテムは読み飛ばし＋診断記録、入れ子のプラグイン型オブジェクトは生 JSON で保持（本家は null 化するがデータ保全方針を優先）。Timeline の Length / MaxLayer はファイルにあれば復元する。EffectItem / TransitionItem の一時プロパティは「保存時に既定値、読み込み時に破棄」。
- 未解決: フォント既定値 `Texts.DefaultFont` とタイムライン名のリソース文字列（本家リソースアセンブリの確認が必要）。ShapeParameter の既定インスタンスの全プロパティは未モデル化（$type のみの最小オブジェクトで代用）。本家実機の .ymmp フィクスチャでの往復検証は、本家を動かせる環境が現時点でないため実施できない（2026-11-16 本人確認。FIXTURE-PLAN は凍結）。VERIFIED には進めていない。
- 次の作業: 本人の Mac でのデバッグ用アプリ初回ビルド確認、実物の .ymmp があれば読み込み確認、描画層（第1〜3章の技術仕様）の実装着手。フィクスチャ採取は Windows 実行環境が用意された場合に再開する。

## 2026-11-16 更新 — Animation 評価の数式置き換え（MAC-0002、未コミット）

- 数式群の抽出が完了（解析側 `ANIMATION-FORMULAS.md`、全項目確定済み）し、暫定評価を全て置き換えた。新規ファイル: `Sources/YMM4Core/Easing.swift`、`Cubic.swift`、`StatelessRandom.swift`、`BezierAnimation.swift`。`Animation.swift` の評価は本家 `GetValue` の分岐連鎖どおりに再構成し、キーフレーム系4経路は最終処理を通らない早期 return とした（MAC-0001 の全型への最終処理適用は本家と異なる暫定措置だった）。
- 仕様書側の誤り（_Int の割り当てが逆）は解析側 `MODEL-SPEC-EXTRACTION.md` の訂正記録4に記録した。本文 §6.3・§6.4 の書き換えはしていない。
- 実装上の判断: 補間移動経路のループ上限は `ANIMATION-FORMULAS.md` §1.1 の擬似コード表記ではなく本家 `Animation.cs` の実コード（区間数 + 1 まで、末尾フォールバックで最後の値）を優先した。数式側の確認事項として残す。
- テスト実行: VM 上の Swift（`~/workspace/tools/swift-6.1.2/usr/bin/swift test`）で全60件合格（従来26件＋新規34件）。既存テストの期待値修正2件（反復移動 Span = 0 のパリティ反転、瞬間移動の最終フレーム＝最後の区間の開始値）はいずれも本家コードに合わせたもの。
- 未確定事項: ランダム移動のシード材料である本家 `GetHashCode()` の具体値との対応付け（Swift 側は `Animation.randomSeed` で代用し、決定的性質のみ保証）。本家実機での乱数列採取が必要。
- 次の作業: Timeline / BaseItem の実装、KeyFrames の RemovesLeft/RemovesRight、Golden Master 比較素材の整備。

## 2026-11-16 更新 — 残りの編集操作（MAC-0007、未コミット）

- MAC-0004 で未実装だった3群を本家 `Timeline.cs` の実コードどおりに実装した: DeleteAndMove / DeleteAndMoveAll（戻り値は新しい現在フレーム）、長さ変更の一族（`changeSelectedAndGroupedItemsLength` / `getExpandableDeltaLength` / `changeItemsStart` / `changeItemsEnd`、隣接影響モード `NeighborAffectMode` を Enums に追加）、スナップ `getSnappedDelta`。詳細と本家との差分（意図的なもの3点）は実装台帳 MAC-0007。
- テスト実行: VM 上の Swift（`~/workspace/tools/swift-6.1.2/usr/bin/swift test`）で全112件合格（従来87件＋新規25件、すべて TimelineEditingTests）。警告・エラーなし。macOS でのビルドは未実施（Foundation のみ）。
- 観測した本家の癖（差分ではなく再現済み）: DeleteAndMove の現在フレームは「対象の開始位置まで戻す」式で DeleteAndMoveAll の式と非対称。ChangeItemsEnd の Stretch では ContentOffset の丸めが開始側切り取り時のみあり、押し出し時は丸めなし。DeleteAndMoveAll では削除区間を覆っているアイテム自身も詰めの対象になる。
- 次の作業: 変更なし（本人の Mac でのデバッグ用アプリ初回ビルド確認、描画層の実装着手）。モデル層で残る未実装は Character の型付き範囲の拡張と ShapeParameter 既定インスタンスのプロパティ一式。

## 2026-11-16 更新 — モデル層の残件解消（MAC-0008、未コミット）

- MAC-0007 時点で残っていたモデル層の未実装3件を解消した: (1) 空間を詰める削除の一族（`deleteItemSpace` / `deleteTimelineSpace` / `deleteAllLayerSpaces` / `deleteAllTimelineSpaces` / `deleteIsolatedRanges`、TimelineEditing.swift）。(2) Character の全プロパティ型付き化（保存対象86件＋旧互換2件。プラグイン型は PreservedObject 生保持、TachieType は型名文字列、KeyGesture / VoiceDescription は構造体。Character.swift）。(3) ShapeParameter 既定インスタンスの完全化（新規 ShapeParameter.swift: RectangleShapeParameter と Brush / SolidColorBrushParameter を型付き化、未知 $type は生保持。ShapeItem / EffectItem の旧互換キー転送も実装）。詳細と意図的な差分・未解決事項は実装台帳 MAC-0008。
- テスト実行: VM 上の Swift（`~/workspace/tools/swift-6.1.2/usr/bin/swift test`、.build を消して再実行）で全127件合格（従来112件＋新規15件）、警告・エラーなし。macOS でのビルドは未実施（Foundation のみ）。
- 観測した本家の癖（差分ではなく再現済み）: StrokeThickness の既定値は 4000。DeleteAllTimelineSpaces の被覆判定はレイヤーをまたぐ。DeleteIsolatedRanges の詰めには to（選択範囲の終端）の上限がある。ShapeParameter / Brush の既定プラグインは `[PrimaryPlugin]` 属性で決まる（QuadrilateralShapePlugin / SolidColorBrushPlugin）。
- 次の作業: モデル層の未実装は解消した。本人の Mac でのデバッグ用アプリ初回ビルド確認、実物 .ymmp での読み込み確認、描画層（第1〜3章の技術仕様）の実装着手が残る。
