# 引継書 — 次の作業者はここから読む

更新: **2026-11-17**。現状: モデル層＋.ymmp 互換層（MAC-0005）＋編集操作・モデル残件（MAC-0007・0008）＋描画層の土台（MAC-0009、`Sources/YMM4Core/Rendering/`）＋合成の実行部（MAC-0010）＋映像アイテム範囲の是正（MAC-0011）＋GPU 実行器と基本 Source（MAC-0012、`Sources/YMM4GPU/`）＋音声パイプラインの芯（MAC-0013、`Sources/YMM4Core/Audio/`）＋テキスト描画と VoiceItem 実効値の共通解決（MAC-0014、`Sources/YMM4GPU/MetalTextSources.swift` と `Sources/YMM4Core/Items/VoiceItemJimaku.swift`）＋キャラクター参照の保存・解決契約の是正（MAC-0015）＋音声 QA（MAC-0016）＋書き出しの芯（MAC-0017、`Sources/YMM4Core/Export/`）＋映像エフェクト定義層と変換型処理器（MAC-0018、`Sources/YMM4Core/Effects/`）＋定義層の合成チェーン接続（MAC-0019）＋VoiceItem の字幕エフェクト解決の接続（MAC-0020）＋GPU 失敗の検出・通知契約（MAC-0021）＋GPU 処理系エフェクトの定義層（MAC-0022）＋GPU エフェクト Metal 処理器 第1段（MAC-0023、Mac 検証済み・統合済み）＋音声リサンプラの高品質化（MAC-0024）＋実 Source 群＝動画・シーン・フレームバッファ・立ち絵（MAC-0025、`Sources/YMM4GPU/MetalMediaSources.swift`）＋書き出しの実接続（MAC-0026、実エンコード検証済み）＋合成グループの Source（MAC-0027）＋書き出しの解析・結果表現の是正（MAC-0030）＋エフェクト編集の入れ子未知フィールド保持（MAC-0032）＋GPU エフェクト Metal 処理器 第2段・内部合成への供給元伝播・上下反転是正（MAC-0028）＋GPU テクスチャ確保失敗のエラー伝播統一（MAC-0033）＋DebugApp フロントエンドの形（PR #32）＋レベルメーターの本家構成化と誤記修正（UI32-01）＋監査で確定した P1 の解消＝書き出しスナップショット（MAC-0034）・EffectItem 描画 Source とクリッピング実効マスク（MAC-0035）・トランジション合成の配線（MAC-0036）と、リサンプラ正式形（MAC-0037）まで統合済み。デバッグ用アプリ（MAC-0006、`Apps/DebugApp/`）は本人の Mac でビルド・実ファイル読み込み・往復まで確認完了し、合成プレビュー欄と本家ワークスペースの形（PR #32）を備える。現行ツリーはクリーン検証でルート＋DebugApp ともビルド成功・警告0（2026-11-17）。テストは Mac 実機で全432件・0失敗（`swift test --parallel`、2026-11-17 の MAC-0034〜0037 統合後実測）。

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
- **製品 UI の実装はまだない。** GPU 合成は MAC-0012 で基礎（Metal 実行器＋画像・図形 Source）が入り、MAC-0014 でテキスト・字幕 Source が入り、MAC-0025 で動画・シーン・フレームバッファ・立ち絵の実 Source が入り、MAC-0027 で合成グループの Source も入って Source は全種別が揃った（AVFoundation 非対応コンテナは未対応のまま）。音声は MAC-0013 でパイプラインの芯（ストリーム基盤・処理器連鎖・ミックス・グループバス）が入り、MAC-0016 で QA（ドリフト実測とシーク量子化の修正）を行い、MAC-0024 でリサンプラの生成芯を帯域制限補間へ高品質化し、MAC-0026 でデコード実体（AVFoundation）と書き出し接続が入った（ユーザーエフェクト・再生接続は未実装）。書き出しは MAC-0017 で芯（状態機械・FFmpeg ライター・ラウドネス）が入り、MAC-0026 でフレーム供給・音声ミックスとの接続と実エンコード検証まで完了した。映像エフェクトは MAC-0018 で定義層と変換型処理器が入り、MAC-0019 で合成チェーンへの接続（生保持のまま消費側で型付き復元）、MAC-0020 で VoiceItem の字幕エフェクト解決の接続まで済み、MAC-0022 で GPU 処理系73種の定義層も揃った。GPU 処理系の処理器（Metal）は第1段10種を MAC-0023 で実装し Mac 検証済みで統合済み、残り63種は次段。GPU 実行の異常系は MAC-0021 で失敗の検出・通知契約を実装済み。
- **全体監査の P1（AUD-01・02・03・07）とリサンプラ正式形を統合した（MAC-0034〜0037、統合 PR）。** EffectItem・トランジション・クリッピングが描画経路で効くようになり、書き出しはジョブ専有スナップショットを読む形になった。リサンプラは正式仕様（Kaiser 窓 β=8.96・片側96零交差）と正式合格値を固定した。監査の残作業は AUD-04（PngWav ライター）と AUD-06（Metal 初期化失敗の診断）。
- **デモ版を .app バンドル化した（MAC-0039）。** `Apps/DebugApp/package-app.sh`＋`Info.plist` で `YMM4 for Mac.app` を組み立て、本人の Mac の `~/Applications` へ配置済み。バンドル内バイナリの全自動テスト実走は確認済みだが、Dock へのアイコン表示は未確認 — 次回の引き渡し時に LaunchServices 経由の起動で実機確認すること。
- **デモ版内蔵の全自動テストを実装した（MAC-0038）。** DebugApp のボタン／環境変数／トリガファイルから起動し、フレーム合成・シーク・音声処理・書き出し・起動とメモリを実機で自動測定して、JSON レポートを Mac 上の `~/ymm4-work/YMM4MacAutoTest/`（report-<日時>.json と latest.json）へ出す。測定値の正本はレポートファイル（文書へ転記しない）。release ビルドで起動→測定→レポート→終了の完走を検証済み。構造整理の各単位の回帰確認には、整理前後の release レポート比較を使う。

## 次にすること

1. リポジトリ構造の全面整理を実施する（コード再配置は全ファイル計画 W1〜W12、文書再編は事実の種類ごとの正本化・課題台帳の新設・履歴の history/ 分離・notes の正本化＋INDEX・ハーネスの git 管理化）。完了まで機能追加を止める。各単位の回帰確認には MAC-0038 の全自動テスト（release レポートの前後比較）を使う。順序はオーナー決定（2026-11-18）で「全面整理を形の完成より先」へ変更された。
2. フロントエンドの形の完成（全量解析 UI-FRONTEND-FULL-INVENTORY と差分台帳 UI-FRONTEND-DIFF の潰し切り。構造整理の完了後に行う）。
3. 統合ブロック（MAC-0034〜0037）の ChatGPT レビュー第6ラウンド（プロジェクト内チャット、Thinking High）を行い、指摘を実コードで照合して処分する。
4. 整理と形の完了後に機能作業を再開する（残りの内蔵エフェクト処理器32種の実処理化＝Outline から、実時間再生、VoiceItem 音声供給、AUD-04・06。締切は 2026-11-24）。
5. 正式な開発基準は要件定義 v1.2。以降の要件変更・例外実装には本人の事前承認を求める。

## 中断前チェックリスト

- [ ] 変更したファイル・シンボル・コミットが実装台帳に記録されている
- [ ] 変更の理由・具体的動作・本家との差分・Mac固有リソース所有権が説明されている
- [ ] 重要な実装の結果と失敗条件、テスト手順が記録されている
- [ ] As-built、課題、解析側の互換マトリクスが整合している
- [ ] 要件逸脱は事前承認を得ており、未承認例外をマージしていない
- [ ] 次の作業と現在のブランチ・コミットが書かれている

## 2026-11-17 更新 — 台帳転記（PR #32・UI32-01）と全体監査の残作業（AUD-01〜04・06）

- **転記（AUD-05 の是正の一部）**: PR #32（DebugApp フロントエンドの形）と UI32-01（レベルメーターの本家構成化＋「シーインタブ」誤記修正）は実施済みだったが IMPLEMENTATION_LOG / STATUS / HANDOFF に項目が無かった（全体監査 A-5(2)）。本バッチで IMPLEMENTATION_LOG に PR32 項と UI32-01 項を追加し、STATUS・本書の現行状態を同期した。作業内容の正本は解析側 `analysis-notes/UI-FRONTEND-DIFF.md`（形と接続台帳）と `REVIEW-DISPOSITION-MAC0028-FRONTEND.md`（UI32-01 の処分と本家構成の確定内容）。
- **AUD-05 のもう1件（履歴と現行状態の分離）**: MAC-0033 項末尾の「注意」にあった「DebugApp はビルド失敗する」は、並行作業の検証コピーがフロントエンド編集中間状態を拾った際の一時的な観測であり、現行ツリーの状態ではない。当該の注意は MAC-0033 項側で履歴として分離し直した。現行状態はクリーン検証（~/verify-clean/YMM4Mac、2026-11-17）でルート＋DebugApp ともビルド成功・警告0が正本。
- **監査で確定した残作業（従来の台帳に無かった欠落。詳細は STATUS の「監査で確定した残作業」セクションと解析側 `AUDIT-2026-11-17-FULL.md`）**:
  - AUD-01: EffectItem の描画 Source（本家 EffectSource）が未実装。`MetalSourceProvider` にケースが無く透明を返し、FrameBuffer 境界も発生しないため、蓄積画像への形状マスクが全経路で効かない。kiminihare では EffectItem 0件。
  - AUD-02: トランジション合成（本家 TransitionSource）が未配線。`TransitionItemPicker` は実装・テスト済みだが合成器から未使用で、TransitionItem は空 Source。除外規則だけが再現されているため遷移区間で下位レイヤーが消え、前後合成も描かれない。kiminihare では TransitionItem 0件。
  - AUD-03: クリッピング（IsClippingWithObjectAbove）の実効マスクが未適用。`AlphaMaskEffectFactory` の本番実装が無く（テストの Fake のみ）、呼び出し側も渡さないため常に nil。テキスト・字幕・映像の共通プロパティで影響範囲は広い。
  - AUD-04: PngWav ライター（連番画像＋WAV）が未実装。本家同梱3系統のうち実装は FFmpeg のみ（MF 相当の未実装は MAC-0017 に記録済み）。
  - AUD-06: Metal 初期化失敗の診断が無い。`MetalGraphicsDevices` の初期化が失敗を `try?` で握って devices が nil になり、PreviewBox / TimelineExporter は理由なく nil を返す。発生条件の現実性は未確定。

## 2026-11-17 更新 — GPU テクスチャ確保失敗のエラー伝播統一（MAC-0033）

- GPU28-03（ChatGPT レビュー第5ラウンド、処分は `analysis-notes/REVIEW-DISPOSITION-MAC0028-FRONTEND.md` で採用確定）の修正。従来は `MetalEffectProcessor.makeTexture` の確保失敗が nil として各ヘルパーを伝播し、基底 `update` が入力をそのまま出力として公開していた。コマンドバッファ失敗は同じファイル内でも throw しており、MAC-0021 の失敗通知契約とも不統一だった。
- 契約の形: Core の `VideoEffectProcessor.update` は元々 throws で、`MetalEffectProcessor.update` も `try render(...)` 済みのため、プロトコル変更なしに直接 throw へ統一した（失敗を画像側に記録して close() で送出する代替形は不採用。処理器の失敗はその場で連鎖の呼び出し側へ伝播するのが第4章の意味論に合う）。
- 変更: `Sources/YMM4GPU/MetalEffectProcessors.swift`（`makeTexture` を throw 化し、失敗時は既存ケース `MetalRenderError.textureCreationFailed(width:height:)` を投げる。確保失敗が nil の唯一の意味だった基底ヘルパ8種＝renderColorEffect / renderGaussianBlurred / renderDirectionalBlurred / renderRectangleMosaic / renderTransformed / renderWarp / renderComposite / renderMorphology を非 Optional 戻りへ変更。基底 `render` の契約コメントに「nil は効果なしが正当な場合だけ、資源失敗は throw」を明記）と `Sources/YMM4GPU/MetalEffectProcessorsStage2.swift`（呼び出し側の `guard let … else { return nil }` を7箇所で通常の let へ。`renderRoundedRectFill` と FrameLine の `renderSolidRects` は、nil を「出力境界が空の正当な無処理」だけに限定し、テクスチャ確保は textureCreationFailed、コマンドバッファ／エンコーダ生成は commandBufferFailed を投げるよう分離）。
- 無変更の素通し: プレーン前提ガード（GPU28-01、基底 update の入力素通し）、単色ブラシ以外での Shadow / FillBackground / FillForeground / FrameLine の素通し（GPU28-02）、非矩形モザイクの素通し、σ≤0 等で入力を返す経路。残存する nil は値のパース失敗（parseARGBColor 等）と空境界の無処理だけであることを grep で全数監査した。
- 検証: Mac 実機（検証コピー ~/verify-gpu28-03/YMM4Mac）でルートパッケージの `swift build` 成功・警告0（変更2ファイルの強制再コンパイルで確認）。画素ハーネスを同コピーへ向け替えて再実行: mac0023 = 25 PASS / 0 FAIL、mac0028 = 90 PASS / 0 FAIL（いずれも従来どおり全合格）。Linux 全件テストは IMPLEMENTATION_LOG の MAC-0033 項を参照。
- 確保失敗の実行時模擬（専用ハーネス ~/mac0033-harness、本人の Mac と `~/workspace/ymm4-work/mac0033-harness/`）: 回転処理器へ Zoom = 100000 を与えて出力テクスチャ寸法を約905万 px（上限16384 超）にする決定的な失敗を試みたが、この Mac（macOS 26）では上限超えディスクリプタが makeTexture の nil 戻りより前に Metal のディスクリプタ検証アサーションで abort する（exit 134。MTL_DEBUG_LAYER=0 / METAL_DEVICE_WRAPPER_TYPE=0 でも回避不可）。寸法経路で nil 戻りを決定的に再現する手段が無いため、ハーネスは対照2件（通常拡縮で更新成功・出力公開）PASS、失敗ケース3件は環境変数 MAC0033_RUN_FAILURE_CASE=1 のときだけ実行する SKIP 表示とした。アサーション出力の要求寸法 9050967 は、要求がデバイスへ実際に到達した傍証。メモリ枯渇による再現は本人の実機を不安定化させるため採らない。throw 経路の担保はコード監査（確保箇所は全て throw する makeTexture 経由か明示 throw）に拠る。
- （履歴 — 現行状態ではない）本件の検証時、検証コピー ~/verify-gpu28-03 がフロントエンド編集中間状態（`SwiftUI.Color` 修飾の入る約2分前の ProjectView.swift）を拾い、DebugApp パッケージの `Color` 型曖昧性（SwiftUI.Color と YMM4Core.Color）によるビルド失敗として観測された。当初は本項・STATUS・IMPLEMENTATION_LOG の MAC-0033 項に現行状態として記録したが、全体監査 AUD-05 の指摘で分離する。現行ツリーの ProjectView.swift は修飾済みであり、クリーン検証（~/verify-clean/YMM4Mac、2026-11-17）でルート＋DebugApp ともビルド成功・警告0を確認済み。本変更（YMM4GPU の2ファイルのみ、公開 API の変更なし）とは無関係である点は従来の記録どおり。

## 2026-11-17 更新 — エフェクト編集の入れ子未知フィールド保持（MAC-0032）

- UI29-01（ChatGPT レビュー第4ラウンド、処分確定）の修正。MAC-0029 の `EffectPropertyEditing.writeBack` が型付き定義から全体を再エンコードしていたため、既知エフェクトの入れ子オブジェクト内（`Animation` や `Bezier` の内部）の未知キーが、無関係な1項目の編集でも保存時に消えていた。無編集保存では生保持のため失われない、編集経路に固有の欠陥。
- 修正: `Sources/YMM4Core/Effects/VideoEffectRegistry.swift` に `encode(_:preservingUnknownFieldsOf:)` を新設し、`writeBack`（`Sources/YMM4Core/Editing/EffectPropertyMetadata.swift`）は対象スロットの現在の要素を土台に重ねて書き戻す。トップレベルは型付きエンコードが正（未知キーは定義の `additionalFields` 経由で既に含まれ、空にした `Remark` や旧キー移行は定義側の判断が残る）。入れ子は元の並びを土台に再帰マージし、元だけのキーを全階層で保持する。配列・スカラは型付き側で置換。元の `$type`（移行適用後）が定義の型と異なる場合は重ねず通常 encode を返す。通常の `encode(_:)`・読み込み・保存・再生（TypedEffectPairProvider）の経路は無変更。
- 検証: `PropertyMetadataTests` に新規3件（IsEnabled のみ編集で全階層保持＋保存→再読み込み、Animation 自体の編集でも同一オブジェクト内の未知キー保持、無編集往復の固定点回帰）。書き戻しを通常 encode へ戻すと編集系2件が失敗することを確認済み。全件は Linux で413件・0失敗。Mac 実機ビルドは未実施（変更は Foundation のみの Core 内で、`writeBack` のシグネチャは不変）。
- 境界: 配列要素内部の未知キーは保持対象外。旧形式の指令キー `From` / `To` は未知キーとして保持される（本家は書き出さないキーだが、実ファイル2件で出現数0のため特別扱いなし）。

## 2026-11-17 更新 — GPU エフェクト Metal 処理器 第2段＋内部合成への供給元伝播（MAC-0028、Mac 検証済み・統合済み）

- 実装は分離ツリー `ymm4mac-gpufx2`（MAC-0027 統合直後から分岐）で行われ、検証完了後にファイル単位でメインへ統合した。`MetalEffectProcessorsStage2.swift`（新規1,888行）と `MetalGraphics.swift` / `MetalEffectProcessors.swift` / `MetalSources.swift` は gpufx2 版を採用。`MetalExport.swift` と `PreviewBox.swift` は gpufx2 版をそのまま入れず、配線差分だけを main 版へ手で移した（gpufx2 版は MAC-0030 以前の severity API を使う／ファイル切替修正の deinit dispose が無いため）。YMM4Core とテストは無変更。
- 第2段の実処理器は31種: Rotate / Skew / CenterPoint / Crop / Margin / CopyAndReverse / Tiling / AutomaticZoom / RoundCorner / BorderBlur / DirectionalBlur / ChromaticAberration / Shadow / FillBackground / FillForeground / FrameLine / Morphology / DrawLazyEffect / Jump / InOutBorderBlur / InOutGaussianBlur / InOutMosaic / InOutMoveFromOutsideImage / InOutGetUp / InOutRotate / InOutSkew / InOutJump / RandomRotate / RandomSkew / RepeatRotate / RepeatSkew。GPU 階層73種のうち実処理器ありが41種（第1段10＋第2段31）、素通しが32種（ArcBend / BackgroundImage / ChromaKey / ChromaKey2 / CircularDuplicator / Crash / CropByAngle / DisplacementMap / Gradient / HalfTone / HalfToneBorderBlur / HalfToneOutline / HalfToneShadow / HightlightsAndShadows / HlslPixelShaderCode / HlslPixelShaderFile / InOutCrash / InOutTransition / InnerHalfToneShadow / InnerShadow / Mask / MeshDeformation / NoiseColorShift / NoiseDisplacementMap / Noise / Outline / PolarTransform / RadialBlur / RadialLight / RandomDuplicator / Sharpen / Texture）。全 Metal 処理器共通の前提: 入力画像が恒等変換でなく不透明度≠1 の場合は素通しになる（MetalEffectProcessor.update のガード。DrawDescription 書き換えフックは通る）。実プロジェクトでの発動頻度は未測定。
- 供給元伝播: MetalSourceProvider が `effectProvider` を受け取り、シーン・合成グループの内部合成器と子供給元へ同じインスタンスを再帰的に伝播する（未設定時は TypedEffectPairProvider へフォールバック）。PreviewBox と MetalExportVideoProvider は共有インスタンスを生成して外側の TimelineComposer と供給元の両方へ渡す。書き出し側は `timeline:` も渡すため、合成グループが書き出しで透明になる問題（レビュー指摘 EX26-01）は解消した。グループ自身のエフェクトは外側で一度だけ適用され、内部合成器は子だけを扱うため二重適用にならない。
- 上下反転の是正: main 側の `makePremultipliedTexture` は CGContext へ反転して描いており、画像・動画のデコード結果が上下逆だった（MAC-0012 以来）。gpufx2 側の検証プローブ（四象限画像）で発見し、独立プローブで main 側コードでも再現を確認した。従来のハーネスは単色・対称パターン・被覆数の検証のみで検出できなかった（MAC-0031 のテキスト帯状化と同じ検証の穴）。gpufx2 版では反転を除去し、ハーネスに向き回帰ケース（左上が赤・左下が青）を追加した。
- 検証: Linux 全413件・0失敗（従来410件＋3件は、統合用コピーの取得時点でメインクローン側に入っていた並行タスク UI29-01 のテスト追加。本件による Core・テストの変更はゼロ）。Mac 実機（検証コピー ~/verify-integrate/YMM4Mac）でルート＋DebugApp のビルド成功・警告0（GPU 全ソースの強制再コンパイルで確認）。画素ハーネス: mac0028 = 90 PASS / 0 FAIL（第2段31種の解析的検証＋伝播2件＋向き回帰を含む）、mac0023 = 25、mac0025 = 18、mac0027 = 15、いずれも全合格。mac0031（実ファイル frame 2810 の分割テキスト）はピース形状が完全なグリフであることを確認（合成全体の数値プロファイルは FillBackground 処理器が有効化されたため MAC-0031 記録時と異なる）。書き出し伝播の専用ハーネス（~/mac0028-export-harness）で、合成グループの子が書き出しフレームに現れること（被覆10,000px・中心白）と、グループ内部の子の Invert が書き出しでも効くことを画素で確認した（全6項目合格）。
- 未解決: 本家との画素一致は未検証（ハーネスはシェーダ式からの解析的期待値との照合。本家環境が無いため Golden Master は到達不可）。素通し32種の実処理器化が次段。Shadow / FillBackground / FillForeground / FrameLine は単色ブラシ以外（グラデーション等）で素通し（ブラシサブシステムが差し替え点）。DirectionalBlur は D2D 内部方式が非公開のため1次元ガウス近似。ChromaticAberration は Strength=100 で拡縮率の下限を追加した差分がある（コードに記録）。非矩形モザイクの素通しとモザイクサイズのアニメーション評価（GPU23-01 / 02）は従来どおり未対応。

## 2026-11-17 更新 — 書き出しの解析・結果表現の是正（MAC-0030）

- ChatGPT レビューの指摘 EX17-05（P1）/ EX17-06（P1）/ EX17-07（P2）/ EX17-08（P2）を実コードで照合し、全件一致を確認して是正した。あわせて文書の精密化2件（EF18-02: MAC-0019 項の固定点の射程限定、GPU22-05: MAC-0022 項への Gradient 旧キー転送の防御差分の記録）も反映した。
- EX17-05 / 06: `LoudnessAnalysis` に解析計画 `plan(loudness:compressor:)` と `skippedResult(for:)` を新設し、ストリーミング版 `analyze(stream:frameCount:loudness:compressor:hz:fps:)` を追加した（チャンク列版との最終値計算は私設の Accumulator で共有）。`TimelineExportAudioProvider` は計画が読み取り不要を示す場合、解析用ミキサー自体を生成せず音声を一切読まない。必要な場合も固定長の1配列を使い回すため、全区間の保持（48kHz ステレオ Float32 で1時間あたり約1.38GB）は無くなった。`makeChunks` はテスト補助として残置。
- EX17-07: `VideoFileWriting` に `producesOutputFile`（既定 true）を追加し、`FFmpegProcessWriter` は音声・映像とも `-f null` の構成で false を返す。`ExportOutcome` に `finalizeSucceeded` を新設し、`outputProduced = finalizeSucceeded && writer.producesOutputFile` とした（ファイルシステムの実在確認ではなく writer の申告に基づく）。DebugApp の書き出し要約は、成果物が無い完了をパス表示にしないよう追随した。
- EX17-08: `ExportError.Severity`（warning / fatal）を廃止し、原因の対処可能性を表す `Cause`（actionable / unresolvable）へ置き換えた。`FFmpegErrorClassifier` の一致は actionable、付随ファイル失敗などを outcome.warning へ入れる際も原因分類は書き換えない（副次性は置き場所で表す）。分類器の文言表自体は無変更。
- 検証: 書き出し関係のテストを先行実行し全件合格（新規9件: 解析計画、ストリーミング無読込、ストリーミング＝チャンク列の一致、Provider の無読込2件＋対照1件、成果物の区別、対処可能な finalize 失敗、両系統 null。既存の断言4件を新軸へ更新）。Mac 実機でルート＋DebugApp のビルド成功・警告0。全スイートの件数は IMPLEMENTATION_LOG の MAC-0030 項を参照。
- 未解決: なし（本件の範囲内）。解析対象範囲は従来どおりタイムライン全体で、本家の EncodeFrom / EncodeTo による部分解析とは異なる点は MAC-0026 以来の既存差分のまま。

## 2026-11-17 更新 — 合成グループの Source 実装（MAC-0027、Mac 検証済み）

- `Sources/YMM4GPU/MetalMediaSources.swift` に `MetalCompositeSource` を追加した（同ファイルは920行に）。MetalSourceProvider に合成グループの分岐を追加し、`MetalRenderTarget` に描画内容境界の追跡を、`MetalImage` に `texturePlaneRect` / `planeOffset` を導入した。新規テスト CompositeGroupTests 5件。
- 本家の意味論（実コードで確認）: 合成グループは `CompositeSource` が自前文脈と内部 `TimelineSource` を持ち、子をタイムライン絶対時刻で中間画像へ合成する。中心は `CompositeCenter` が ImageCenter のとき内部画像の局所境界（内容境界）の中心、それ以外（ScreenCenter・未知値）は (0,0) で、平行移動 −center は DrawingOffset = +center / Center = (0,0) として表される。グループの `GroupEffects` は子へ流れず（親グループ解決は合成グループで打ち切られる）、グループ自身の `VideoEffects` が合成結果全体へ一度だけ適用される。
- 実装の要点: MetalCompositeSource は自前文脈を所有し、内部 TimelineComposer（CompositeItemPicker 束縛）が子を絶対時刻で合成する。MetalRenderTarget が描画内容の境界を追跡し、close() 成功時に bounds = 内容境界 / texturePlaneRect = 画面範囲として再登録する。MetalImage の texturePlaneRect / planeOffset（境界とテクスチャ平面範囲の分離）は、描画先画像の UV が bounds 基準でずれていた潜在問題の是正でもある。内部出力はテクスチャを共有したまま境界と planeOffset をずらして登録し、コピーは作らない。
- 検証: Linux 全377件・0失敗（当時）。Mac 実機ビルド成功・警告0。画素ハーネス15項目全合格（子の表示＝被覆10,000px・中心不透明白、グループ不透明度50%→中心アルファ128、Invert が一度だけ適用、回転軸が ImageCenter / ScreenCenter で本家どおり、入れ子の合成グループで孫が表示され内側の不透明度が効く）。回帰確認として MAC-0023・MAC-0025 のハーネスを再実行し全合格。
- 未解決: 合成グループ内部の子には GPU 色エフェクトが効かない（内部合成器のエフェクト供給元が既定の TypedEffectPairProvider のまま。シーン内部も同じ差分で、本家は内部でも効くため可視差分として残る）。画面外にはみ出す子は画面サイズで切り取られる（MAC-0012 以来の台帳差分。境界・中心・UV の意味論は平面モデルに一致させた）。

## 2026-11-17 更新 — 書き出しの実接続（MAC-0026、実エンコード検証済み）

- MAC-0017 の書き出しの芯へ実音声・実映像を接続した。新規 `Sources/YMM4Core/Export/ExportAudioProvider.swift`（`TimelineExportAudioProvider`）、新規 `Sources/YMM4GPU/MetalExport.swift`（`AVFoundationPCMProviderFactory` / `MetalExportVideoProvider` / ファサード `TimelineExporter`）、変更 `MetalGraphics.swift`（`readBGRA` 追加）と DebugApp の `ProjectView.swift`（書き出し UI）。新規テスト ExportAudioProviderTests 5件。
- 音声供給は2パス: 解析パスで `TimelineAudioMixer` の出力を `LoudnessAnalysis` に通し BS.1770 の測定値・音量係数・コンプレッサ倍率を得て、書き出しパスでは別のミキサーへ `DynamicsProcessorStream`（volume = 音量係数、ratio = コンプレッサ倍率）を被せる。素材デコードは `AVFoundationPCMProviderFactory` が AVAssetReader で全体を float32 / 2ch 化し、失敗時は nil = 無音（本家ファクトリの意味論）。
- 映像供給は PreviewBox と同一構成の合成経路でフレームを合成し、`readBGRA` でセッションの借用バッファへ読み戻す。DebugApp には保存先指定・進捗・キャンセル・解析値の要約表示つきの書き出し UI を追加した。
- 検証: Linux 全377件・0失敗（当時）。Mac 実機ビルド成功・警告0。当初 Mac に ffmpeg が無くスタブで配線を実測検証した（映像ストリームは30フレーム×NV12 バイト数ちょうどでプレビュー合成と Y プレーンがビット一致、音声はサンプル数ちょうど・RMS が理論値と一致、ラウドネス解析のピーク −6.0206 dB が理論値と一致）。その後 ffmpeg 9.0.2 を導入し実エンコードを検証した: export.mp4（H.264 64×48 30fps 30フレーム＋AAC 48kHz ステレオ、尺1.000秒）が生成され、復号フレームの中心が白・隅が黒で合成と一致、音声 RMS −8.99 dB（理論値 −9.03 dB、AAC 誤差内）。
- 未解決: 素材デコードは全体をメモリ展開する方式で長時間素材のメモリ量は未検証。AVAssetReader のトリム情報を無視している。VoiceItem の音声は無音のまま（voiceProviderResolver 未接続）。

## 2026-11-17 更新 — 実 Source 群: 動画・シーン・フレームバッファ・立ち絵（MAC-0025、Mac 検証済み）

- 新規 `Sources/YMM4GPU/MetalMediaSources.swift`（781行）に MetalVideoSource / MetalSceneSource / MetalFrameBufferSource / MetalTachieSource を実装した。`MetalSources.swift` に共有ヘルパーと MetalSourceProvider の分岐を追加し、PreviewBox / ProjectView はプロジェクト全タイムラインをシーン解決子として渡すよう配線した。
- MetalVideoSource: 本家同様に自前文脈を所有し、デコーダ生成は初回と FilePath 変更時のみ。素材時刻は `PlaybackRateMap.getSourceTime`、ループは素材 Duration の剰余。デコーダは AVAssetImageGenerator を採用した（本家のランダムアクセス型デコード規則に一致させるため。AVAssetReader ではない。async API はセマフォで橋渡し）。素材を開いた時点で実 Duration を `item.contentLength` へ反映する。
- MetalSceneSource: 自前文脈を所有し内側 TimelineComposer が借用する（第2章契約）。SceneId 変更時のみ再生成。入れ子上限は本家どおり「親チェーンに同一 ID が10回で生成拒否」。
- MetalFrameBufferSource: MAC-0009 / 0010 の FrameBufferSource 契約の Metal 実体。Flood → 入力の SourceOver 描画 → Crop 矩形の専用パスで蓄積を実体化した。
- MetalTachieSource: 描画は本家同様プラグイン全面委譲のため境界型 `MetalTachieRenderer` / `MetalTachieRendererFactory` を新設し、顔説明を本家式で境界へ渡す。既定 factory は nil（プラグイン不在時の本家挙動）。LipSync の包絡計算と口形評価は未実装で、音量は本家のフォールバック値、口形は常時 silent。
- 検証: Linux 全372件・0失敗。Mac 実機ビルド成功・警告0。ヘッドレスハーネス全件合格（動画 mp4 のフレーム0=赤／フレーム45=青・被覆3,072px 一致、シーン入れ子で白図形10,000px、フレームバッファ蓄積10,000px、立ち絵の顔説明2件到達、自己参照シーンが上限で正常終了）。
- 未解決: SAR（表示幅補正）未対応。AVFoundation が開けないコンテナ（MKV / WebM / TS 等）は透明フォールバック＋差し替え点のままで、FFmpeg 併用は未判断。合成グループ（Composite GroupItem）の Source は未実装で透明になる（MAC-0027 で対応予定）。（合成グループの Source は MAC-0027 で実装済み。）

## 2026-11-17 更新 — 音声リサンプラの高品質化 第1段（MAC-0024）

- `ResamplerStream`（`Sources/YMM4Core/Audio/AudioResampling.swift`）の生成芯を線形補間から帯域制限補間へ差し替えた。新規 `BandLimitedResamplingCore`（窓関数 sinc、Blackman 窓、片側48零点、scale=1 で97タップ、ダウンスンプル時は比率に応じてカーネルを広げて折り返し防止）。解析側 `analysis-notes/AUDIO-FIDELITY-PLAN.md` の計画に基づく。
- 契約側は無変更: 長さ・シーク・位置の変換式と Hz 一致時の素通しは従来どおりで、位置写像は不変（インパルスピーク位置が式どおり一致することをテストで確認）、DC は厳密保存。MAC-0016 のドリフト／境界テストは全件無変更で合格。
- 品質実測（新規 AudioResamplerQualityTests 6件）: 通過利得の平坦さ 1k〜20kHz で ±0.00032 dB 以内。イメージ抑制 −88.7 dB（線形補間 −9.6 dB、改善 79.2 dB）。折り返し抑制 −113.4 dB（線形補間 −13.1 dB、改善 100.3 dB）。**閾値は実測ベースの暫定回帰ガードであり、正式合格値は ChatGPT レビューとオーナー承認で決める。**
- 既存テストの期待値変更1件: AudioPipelineTests のランプ中点 1.5 → 1.5456（旧値は線形補間が区分線形信号をそのまま再現したときの値。帯域制限再構成の真値は約1.5456で、3種の窓で独立確認。経緯はテスト内コメントに記録）。
- 検証: 全372件・0失敗でメインへ統合済み。PlaybackRate 系は線形補間のまま（SOLA の差し替え点）。AVAudioConverter エンジンとの比較選定は未実施。本家 MFT との波形等価性は引き続き未検証（本家環境なし）。

## 2026-11-17 更新 — GPU エフェクト Metal 処理器 第1段（MAC-0023、Mac 検証済み・統合済み）

- 当初は分離ツリー `ymm4mac-metalfx` で実装し、Mac 検証の完了後にメインクローンへ統合した。`Sources/YMM4GPU/MetalEffectProcessors.swift`（830行）。`MetalEffectPairProvider` が Core の `TypedEffectPairProvider` を内包し、対象エフェクトだけを Metal 処理器つきのラッパ定義へ差し替える（ラッパは元の定義インスタンスでキャッシュし、連鎖の再利用判定が依拠する定義の同一性を安定させる）。DebugApp の PreviewBox はこの供給元を使うよう接続した。
- 対象10種: Invert、Monocolorization、Sepia、Tint、Exposure、GammaCorrection、Posterize、LinearTransfer、GaussianBlur、Mosaic。対象外の GPU 処理系は従来どおり内包先の組（暫定素通し等）が使われる。
- **状態**: 当初は Mac へ到達できず検証未実施・未統合だったが、その後 Mac 実機検証が完了した。ルート＋デバッグアプリのビルド成功・警告0。ヘッドレス画素検証は対象10種すべて合格し、Invert・Monocolorization・Sepia・GammaCorrection 等はシェーダ式からの解析値と完全一致した。**メインクローンへ統合済み**。PreviewBox の統合形は MAC-0025 のシーン解決（プロジェクト全タイムラインを sceneResolver として渡す）と本件の MetalEffectPairProvider 接続を併せ持つ。
- 次にすること: 残り63種の Metal 処理器（第2段以降）。定義層の読み取り方法は変えない。

## 2026-11-17 更新 — GPU 処理系エフェクトの定義層73種（MAC-0022、処理器は暫定）

- 本家内蔵エフェクトの未登録分73種の定義クラスを `Sources/YMM4Core/Effects/` に新規実装し、レジストリ登録総数は95種（MAC-0018 の変換群22種＋73種）になった。本家内蔵101種についてはコミュニティ移行先等を除き定義層が揃い、対象から漏れた本家内蔵エフェクトは無い。
- 新規ファイル: GPUTransformEffects（14種）／GPUBlurEffects（12種）／GPUColorEffects（11種）／GPUShadowFillEffects（9種）／GPUWarpEffects（8種）／GPUMaskKeyEffects（3種）／GPUInOutEffects（10種）／GPURandomRepeatEffects（4種）／GPUCustomEffects（2種）／GPUEffectSupport（暫定処理器 `GPUEffectPassthroughProcessor`、基底 `GPUEffectDefinitionBase`、新規列挙型19種）。変更は `VideoEffectRegistry.swift` への登録追加。
- **処理器は全て暫定の素通し**（入力をそのまま返す）。パラメータの型付き復元・往復保全のみが成立し、描画への反映は次段の Metal 処理器まで無い。次段では `GPUEffectPassthroughProcessor` を種別ごとの実処理器へ置き換える（定義層の読み取り方法は変えない）。（第1段10種は MAC-0023 で実装し、Mac 検証を経てメインへ統合済み。）
- 検証: 73クラス全てについて本家定義クラスの永続プロパティ名と Swift 側キーを機械照合し欠落0。旧互換キーの転送6件（Sepia／Gradient／CenterPoint／ChromaKey2／Mask／InOutRotate）をテストで固定。新規 GPUEffectsTests 27件を含む全366件・0失敗。
- 未解決: 多態パラメータ内部（Brush、DisplacementMapTransform、NoiseParameter、MosaicParameter、Mask の ShapeParameter）は生保持のまま。GradientStop／MeshDeformationPoint は一部型付けの新規構造体（残部は追加フィールド保持）。

## 2026-11-17 更新 — GPU 失敗の検出・通知契約（MAC-0021）

- 発端は ChatGPT レビュー第2弾の指摘 G12-07（処分記録は解析側 `analysis-notes/REVIEW-DISPOSITION-MAC0012-0014.md`）。`MetalRenderTarget.close()` がコマンドバッファの status / error を検査せず、不完全な画像が正常な Output として公開されうる問題への対応。
- 変更: RenderTarget プロトコルの `close()` を throws 化（`Rendering/EffectedItemSource.swift`）。EffectedItemSource は失敗した描画先を出力として公開せず dispose して再送出する。`Rendering/TimelineSource.swift` の FrameBuffer 境界と最終合成の close も try 化し、最終合成の失敗時は出力を差し替えず旧出力を保持する。`MetalRenderTarget` に `MetalRenderError`（textureCreationFailed / commandBufferFailed）を新設し、テクスチャ生成失敗は保持して close() で投げ、コマンドバッファの .error 状態を close() で検出して投げる。正常経路（同期完了・合成順序）は無変更。
- 検証: CompositionTests に失敗注入（RecordingRenderTarget）と新規3件（アイテム側／合成側／FrameBuffer 境界の close 失敗で update が投げ、出力が差し替わらないこと）を追加し、全337件合格（当時）。Mac 実機ビルド成功。
- 付随修正: ルート `Package.swift` に最低対応 OS macOS 26.0（CR-001）を宣言し、DebugApp 側も `.v26` 相当へ統一した。これにより MAC-0017 の `FFmpegProcessWriter` が Mac ビルドで可用性エラーになる既存問題が解消した（Linux テスト・Mac ビルド両方で再確認済み）。宣言は `.macOS("26.0")` の文字列形式（Linux 側 Swift 6.1 の PackageDescription が `.v26` ケースを持たないため）。

## 2026-11-17 更新 — VoiceItem の字幕エフェクト解決の接続（MAC-0020）

- MAC-0014 の `VoiceItem.resolvedVideoEffects` を、MAC-0019 の供給経路（`TypedEffectPairProvider.ownEffectPairs`、`Sources/YMM4Core/Effects/VideoEffectRegistry.swift`）へ接続した。対象が VoiceItem でキャラクターが解決済みの場合に限り供給列を解決列へ切り替え、それ以外は保持列（JimakuVideoEffects）を使う。
- 本家実コードの確認: `VoiceItem.cs` の IVideoItem.VideoEffects getter（L813–841）は、Custom→自身、Visible→キャラクター側（無ければ空）、Hidden→空、UseCharacterSetting→キャラクターが存在し IsJimakuVisible のときだけキャラクター側。MAC-0014 の `resolvedVideoEffects` はこの getter と正確に一致する（解決ロジック自体は変更なし）。
- キャラクター未解決時のフォールバック（保持列）で描画結果へ影響しない根拠: 字幕表示ゲート（MAC-0014）により character が nil では字幕自体が出ない。
- 検証: TypedEffectPairProviderVoiceJimakuTests 5件（EffectsTests.swift）を追加し、全334件・0失敗。ローカル作業のみで push はしていない（push は親側の検証後）。

## 2026-11-17 更新 — 映像エフェクト定義層のコーデック＋合成チェーン接続（MAC-0019）

- MAC-0018 の定義層を合成チェーンへ接続した。**設計判断: 保持形式は「生保持のまま＋消費側で型付き復元」**。モデル層は全箇所 PreservedObject のまま、保存経路は無変更。型付き定義は消費側（TypedEffectPairProvider）の一時的なビューとし、保存時に型付き encode で再直列化しない。根拠は実ファイルの初回保存バイト列を変えない保証（キー順・空 Remark 省略・数値再直列化の正規化を避ける）。`VideoEffectRegistry.encode` は変換として利用可能なまま残置した。
- 変更: `Rendering/TimelineSource.swift`（TimelineComposer の既定 effectProvider を EmptyEffectPairProvider → TypedEffectPairProvider へ。DebugApp の PreviewBox は供給元未指定のため自動接続される）、`Rendering/EffectedItemSource.swift`（既定供給元の変更と陳腐化コメントの更新）、`Effects/VideoEffectRegistry.swift`（TypedEffectPairProvider にキーフレーム文脈の伝播を追加。定義生成時と所有アイテムの KeyFrames 変更時にだけ `setKeyFrames` を再伝播し、定義インスタンスは作り直さない）。
- 対象キー: VisualItem 系 VideoEffects／VoiceItem の JimakuVideoEffects／GroupItem の VideoEffects／TachieFaceItem・VoiceItem の TachieFaceEffects。SceneItem／TransitionItem の Before・AfterVideoEffects は対象外。
- 検証: EffectWiringTests 4件を新規追加し全329件合格（当時）。実ファイル2件で接続前と完全一致（158アイテム・780,172バイト／142アイテム・693,977バイト、読み飛ばし・移行0、固定点到達）。ローカル作業のみで push はしていない（push は親側の検証後）。

## 2026-11-17 更新 — 映像エフェクト定義層＋DrawDescription 変換型処理器（MAC-0018、コーデック接続は次段）

- `Sources/YMM4Core/Effects/` に定義層と変換型処理器を実装した（新規9ファイル）。型は: VideoEffectDefinitionBase（定義の共通基盤 = $type 対応・Animation 型パラメータ・追加フィールド保持・IsEnabled）、VideoEffectRegistry（$type 名→定義型のレジストリ）、DrawDescriptionEffectProcessor（変換型処理器の基盤）、各エフェクト定義＋処理器。`Animation.randomMoveRate` / `repeatMoveRate` を private → public に変更した（共有計算の再利用のため）。
- レジストリ登録は22種: Zoom、Opacity、DrawPosition、InOutFade、InOutMove、InOutZoom、InOutMoveFromOutsideFrame、RandomMove、RandomOpacity、RandomZoom、RepeatMove、RepeatOpacity、RepeatZoom、ShowOnlyPreview、Billboard、CameraFov、CameraPosition、CameraLookAt、CameraWraparound、PolarDrawPosition、XYToPolarTransform、MotionTracking。登録外で GroupedDrawingEffect（グループ合成用、$type を持たない）を用意し、GroupedDrawing は GroupItem.GroupEffects（自身の VideoEffects ＋ GroupedDrawing の計算プロパティ）として供給される本家の形に合わせた。
- 実測事項: 実ファイルの CameraPositionEffect で $type 形式・キー順・既定値復元を検証した。Repeat 系 Span=0 の偶奇は処理器コードに従うと Animation 本体と逆になる（本家の処理器側どおりに再現）。
- 差分: ZoomEffect の補間方式は設定層未実装のため入力値を維持。乱数シードは GetHashCode 対応付けが無いため `randomSeed`（既定0）で代替（値一致は未解決）。未知の列挙名は原文保持＋既定値評価（本家は読込失敗）。
- **未実施（次段）**: YmmpCodec への組み込み（`VideoEffectRegistry.decode/encode` と `TypedEffectPairProvider` の接続、キーフレーム文脈の伝播）。現時点では .ymmp 読み込み時のエフェクトは従来どおり PreservedObject の生保持で、定義層と処理器は単体検証済みの状態。GPU 処理系161種の定義・処理器も次段。（接続は MAC-0019 で実施した。ただし方式はコーデックへの組み込みではなく「生保持のまま＋消費側で型付き復元」である。）
- 検証: EffectsTests 35件を含む全325件合格（従来214＋MAC-0015 の4＋MAC-0016 の16＋MAC-0017 の56＋本件35）、警告なし。ローカル作業のみで push はしていない（push は親側の検証後）。

## 2026-11-17 更新 — 書き出し（mp4）の芯（MAC-0017）

- `Sources/YMM4Core/Export/` に書き出しの芯を実装した（新規6ファイル、Foundation のみ）。型は: ExportSession（状態機械。正常／キャンセル／例外の全経路で finalize が正確に1回、結果状態は型で区別。第6章の契約追加 W6-C2/C3）、ExportSettings（設定の明示受け渡し。本家の設定シングルトン直接読みとは異なる第7章 C5 の是正どおり）、FFmpegArguments（本家の癖を含む引数生成の純粋関数と NV12 変換 = BT.709 リミテッド。色宣言は NV12 経路のみの非対称を本家どおり維持）、FFmpegProcessWriter（音声 WAV 一時ファイルと映像の別プロセス＋終了時 `-c copy` mux の本家方式。プロセス起動は差し替え点）、LoudnessAnalysis の BS1770LoudnessAnalyzer（二段ゲーティング。既定の DownMaximumVolume では生成されない）、DynamicsProcessorStream（DynamicsProcessor と EnvelopeFollower。Ratio=1 高速経路は本家と厳密一致）。
- 差分: 終了コード検査の追加（是正）、映像書き込みの同期化（バッファ契約の非対称＝映像は単一配列の借用・音声はフレームごとの新規スライス、は維持）、プロセス引数の配列正準形、ハードウェアエンコーダ解決は差し替え点のみで未適用、MF ライター相当は未実装。
- 未解決: EnvelopeFollower の係数法則は NWaves が逆コンパイル集合に無く再構成のため、Ratio≠1 の波形一致は未検証（音声忠実度の優先確認対象）。**実 ffmpeg での書き出しは未検証**（Mac 統合時）。GPU フレーム供給・音声ミックスとの接続は次段で、書き出しはまだ製品経路につながっていない。（フレーム供給・音声ミックスとの接続と実エンコード検証は MAC-0026 で実施済み。）
- 検証: ExportTests 56件を含む全テストで合格（総数は MAC-0018 の項を参照）。ローカル作業のみで push はしていない（push は親側の検証後）。

## 2026-11-17 更新 — 音声 QA：ドリフト実測とシーク量子化の修正（MAC-0016）

- MAC-0013 の音声パイプラインを実測で検証した（本人が YMM で替え歌制作を行うため音声忠実度は優先事項、本人の指示 2026-11-17）。**位置カウンタは全チェーン（リサンプル跨ぎ・ミキサー・グループバス・定速200%・可変速）で5分時点まで累積ドリフト 0 サンプル**。
- 見つけて直したバグ: 内容位置に系統的な −1 フレームずれ。原因は `InMemoryPCMProvider.seek`（`Sources/YMM4Core/Audio/PCMProvider.swift`）の tick→サンプル変換の切り捨てが、本家式（PositionToTime）の床誤差と重なる二重量子化。本家ファイルソースには無い構造だったため、seek を最も近いフレーム境界への丸め（`.toNearestOrEven`）へ変更した。修正後はシーク着地が全測定位置でサンプル厳密、内容偏差 ±0.09 フレーム以内。
- 既存テスト AudioPipelineTests の期待値1件を 0.75 → 0.375 に修正した（旧期待値自体がずれの症状だった）。
- 残る量子化（アイテム開始が2サンプル早まる等）は本家式由来で逸脱ではないため未修正。
- 追加テスト16件: AudioDriftTests 7件、AudioSampleAccuracyTests 9件（エコーのシーク読み vs 逐次読みがビット一致、ループ境界フレーム厳密、グループ分割点の内容連続性など）。
- 計画: 解析側 `analysis-notes/AUDIO-FIDELITY-PLAN.md` を作成した（リサンプラ芯の高品質化と SOLA の段階計画）。Resampler の MFT 等価性・SOLA は引き続き未解決で、同計画の対象。

## 2026-11-17 更新 — キャラクター参照の保存・解決契約の是正（MAC-0015）

- MAC-0014 で残した保存側の是正を行った。根拠は本家 `VoiceItem.cs` L173–195: アイテムの実行時参照 `Character` は [JsonIgnore] で、保存は `CharacterName` のみ。`CharacterName` の getter は `Character?.Name ?? characterName`。ChatGPT レビュー第2ラウンドの指摘を実コードで照合し採用したもの。
- 変更: `Items/TextItems.swift`（VoiceItem）と `Items/CompositeItems.swift`（TachieItem / TachieFaceItem）の `encodeKnownFields` から "Character" オブジェクトの書き出しを削除し、CharacterName は `character?.name ?? characterName` を書くようにした。decode 側の "Character" ケースは旧形式（自前の旧保存ファイル）互換のため残置し、保存時に本家形式へ正規化される。名前→参照の解決自体は MAC-0014 の `YmmpCodec.resolveCharacterReferences` で実装済み。
- 検証: CharacterReferenceTests 4件（本家形式での名前解決と同一インスタンス性、保存時に "Character" キーが無いこと、往復の固定点、旧形式の読込と正規化）。
- 注意（検証の穴だった点）: 実ファイル検証に使った本家ファイル2件はキャラクター0件で、この経路は実ファイルでは未踏だった。是正の根拠は実コード照合である。

## 2026-11-17 更新 — テキスト描画と VoiceItem 実効値の共通解決（MAC-0014）

- テキスト描画を `Sources/YMM4GPU/MetalTextSources.swift` に実装した（全て `#if os(macOS)`）。型は: MetalFontResolver（CoreText での名前解決。CTFontCreateWithName の結果を名前群と照合して検証し、コレクション走査も行う。太字は「Bold 指定かつ解決フェイスのウェイト < 700」のときだけ引き上げる本家規則）、MetalTextRasterizer（本家の前処理→レイアウト→背景／前景の分離描画を CoreText で独立実装。縁取りはグリフ輪郭パスへのストロークで線幅 EmSize/7・Light 系 /14、影はオフセット EmSize/24。タイプライターはタグなし経路、文字単位分割は TimeOffset / DurationOffset つき）、MetalTextSource（TextItem）、MetalJimakuSource（VoiceItem 字幕）。`MetalSourceProvider` は TextItem → MetalTextSource、VoiceItem → MetalJimakuSource を返すようになった。
- **JimakuVisibility の解決時点は「Source 生成時」ではない**（本家実コードで確認）。`VoiceItem.CreateVideoSource` は無条件に JimakuSource を返し、表示可否・外観は `JimakuSource.UpdateResource` が Update のたびに判定し、変形は IVideoItem の動的 getter が読まれるたびに解決される。したがって解決は YMM4Core の共通仕組みに置いた: 新規 `Sources/YMM4Core/Items/VoiceItemJimaku.swift` に `VoiceItem.jimakuIsVisible` / `jimakuAppearance` / `resolvedX` 等と、`VideoItemProperties` 拡張の実効値アクセサ（`effectiveX` 等。VoiceItem のときだけ解決、他は保持値をそのまま返す）を実装し、EffectedItemSource / TimelineSource / DrawOrdering の読み取りを全てアクセサ経由へ切り替えた。新しい描画コードがアイテムの X/Y/Zoom/Opacity 等を読むときは必ず effective* を使うこと（保持プロパティの直接読み取りは本家不一致になる）。
- Character 参照: 本家の `Character` は [JsonIgnore] で保存されるのは `CharacterName` だけ。`YmmpCodec.decode` の最後に、Project.Characters から名前で引いて VoiceItem / TachieItem / TachieFaceItem の `character` を解決する処理を追加した。**保存時に "Character" オブジェクトを書き出す現行コーデックの是正は MAC-0015 で行う（本件では触っていない）**。
- 検証: VM（Linux）`swift test` 全214件合格・警告なし。本人の Mac（SSH）でルート＋デバッグアプリの `swift build` 成功・警告なし。ヘッドレスハーネス（Mac /tmp）で sample.ymmp フレーム45（TextItem「こんにちは、世界」）のテキスト領域に非透明 2,492 px、フレーム210（字幕「セリフです」）の字幕領域に 1,179 px、縦書きプローブで 2,531 px を確認。本家形式 JSON（"Character" キーなし）で参照解決と実効 X = 120（Character 側）も確認した。**プレビュー欄の画面上での目視は未実施**。本家実機とのピクセル比較は環境が無いため未実施で IMPLEMENTED 止まり。
- 差分・未実装（台帳 MAC-0014 に記録）: フォント名体系とフォールバック先の相違、CoreText の行メトリクスによるレイアウトのずれ、縁取りのストローク幾何の相違、制御タグ（ルビ・タイミング）とアスタリスク辞書は未実装、装飾の位置ずらし・回転は未実装、縦書きは近似経路（縁取り・影・分割・タイプライター未対応）、ラスタライズは有限テクスチャで巨大テキストは切れる、Random 順位は決定的シャッフルで代用。フォント既定値（Texts.DefaultFont）は引き続き未確定。
- ローカル作業のみで push はしていない（push は親側の検証後）。解析側の Mac As-built・互換マトリクスへの同期は PR 時に行う。

## 2026-11-17 更新 — 音声パイプラインの芯（MAC-0013）

- `Sources/YMM4Core/Audio/` に音声パイプラインの芯を実装した（Foundation のみ、Linux でテスト可能）。実装は分離ツリーで先行し、ファイルのコピーで統合した（既存ファイルの変更なし）。型は: AudioStream（本家 AudioStreamBase の意味論 = float32 / 2ch 固定プルモデル、Position はインターリーブ済みサンプル数で内部読み取り分だけ進む、TimeToPosition = ticks × 2 × Hz / 10⁷ で偶数切り捨て、バッファのゼロ初期化は呼び出し側の責務）と InputFrameWindow（範囲外は無音、終端を記録）、PCMProvider / PCMProviderFactory（デコードの差し替え点。本家 IAudioFileSource 相当）と InMemoryPCMProvider、FileAudioStream（provider が nil なら 48000 Hz・長さ 0 の無音）、EffectedAudioItemSource（本家のチェーン順序を再現: NegativeSeekable → 可変レート時 VariablePlaybackRate／定速時 Reverse・Loop・ContentOffset → Echo → 条件付き Resampler → PlaybackRate → VoiceItem のみ Upsampler → タイムライン Hz への Resampler → ユーザー音声エフェクト → VolumePan → Resampler）、処理器群（NegativeSeekable、ContentOffset、Loop、Reverse = 1秒ブロック反転、Echo = フィードバックで反復回数 min(50, ceil(log 0.01 / log decay))、VolumePan = サンプル対ごとに Animation 評価・線形パン法則、Resampler、PlaybackRate、VariablePlaybackRate、Upsampler）、TimelineAudioMixer（読み取り範囲と交差するリソースだけ開閉、レイヤー音量 LayerSettings.Volumes / 100、float 加算ミックス、リミッターなし = 本家どおり）と音声グループバス（AudioGroupResolver がグループ境界で区間分割して DirectGroups と Owner を算出し、完全所有の子は GroupAudioBusSource 経由でのみ鳴らして二重加算を避ける）。詳細と本家との差分は IMPLEMENTATION_LOG の MAC-0013。
- AudioItemProperties プロトコルには AudioItem / VideoItem / SceneItem / VoiceItem が適合する。VoiceItem の音声フェードは字幕側の fadeIn と名前が衝突するため `audioFadeIn` / `audioFadeOut` として公開した。
- 未実装・差し替え点のままのもの: デコードの実体（PCMProvider の実物。メディア読み込みの段で扱う）、ユーザー音声エフェクト約40種（AudioEffectProvider の差し替え点のみ。既定は空）、SOLA ピッチ補正（リサンプリングへフォールバック）、Upsampler の Linear / Cubic 以外のカーネル、再生（プレビュー）・書き出しへの接続。音声の実出力はまだどこにもつながっていない。
- 未解決: Resampler の本家 MFT との等価性は未検証（線形補間を採用し、長さ・シークの変換式のみ本家一致）。Upsampler の本家既定設定値も未検証。シークは ticks 経由で精度が落ちる（本家も同じ）。本家の並列ミックスは逐次加算に置換（結果は同一）。
- 検証: `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（リポジトリルート）で全214件合格（従来194＋新規20、AudioPipelineTests）、警告なし。本家実機との比較は環境が無いため未実施で IMPLEMENTED 止まり。ローカル作業のみで push はしていない（push は親側の検証後）。

## 2026-11-17 更新 — GPU 実行器と基本 Source（MAC-0012）

- 新規ターゲット `Sources/YMM4GPU/`（Metal）に GPU 実行器を実装した。全ソース `#if os(macOS)` で、Linux では空モジュール（`swift test` は従来どおり全194件合格）。型は: MetalGraphicsDevices（MTLDevice 共有、パイプライン・サンプラ・1×1 透明テクスチャの即時生成、ImageReference の登録表）、MetalGraphicsContext（消費者ごとの文脈。自分の MTLCommandQueue を所有し RenderTargetFactory を兼ねる。第2章の契約どおりデバイスは共有・文脈は消費者ごとに新規）、MetalImage（ImageReference の実体 = MTLTexture＋平面座標の境界＋変換＋不透明度＋補間方式。属性は BGRA 8bit / Premultiplied）、MetalRenderTarget（RenderTarget の実物。画面サイズのテクスチャへ畳み込み、close() で同期完了）、MetalDrawingEffect（DrawingEffect の実物。ズーム×ワールド×透視の変換と不透明度を実体へ記録する遅延評価。PlaneSplitGeometryProviding も実装）、MetalImageSource（ImageIO デコード、失敗時は 1×1 透明）、MetalShapeSource（RectangleShapeParameter＋単色ブラシを SDF で描画。本家の実現化規則の可視結果を再現）、MetalEmptySource（未対応種別の透明 Source）、MetalSourceProvider（種別→Source の供給元）。
- デバッグアプリに合成プレビュー欄を追加した（`Apps/DebugApp/Sources/YMM4MacDebug/PreviewBox.swift` が新規、ProjectView に画像表示＋フレームスライダ）。開いた .ymmp の現在フレームを TimelineComposer ＋ Metal で合成し、読み戻した CGImage を表示する。既存の診断・往復チェックは不変。
- 検証（本人の Mac、SSH 経由）: ルートパッケージとデバッグアプリの `swift build` 成功（警告なし）。ヘッドレスハーネスで sample.ymmp のフレーム 0 / 10 / 45 の合成が例外なく完了し、図形（100×100 白、中心が不透明白）と画像（/tmp/image.png 64×48 赤、中心が不透明赤）のピクセルを読み戻しで確認した。**プレビュー欄の画面上での目視は未実施**（次に本人がアプリを起動したときの確認対象）。実ファイルの素材は Mac 上に無いため、実ファイルを開いた場合のプレビューは素材不在で透明になる見込み。
- 差分・未実装（台帳 MAC-0012 に記録）: 描画先は無限平面ではなく画面サイズへ畳み込む（画面外の中間結果は段階ごとに切り取られる）、コマンドは close() で同期実行、BlendMode の特殊合成は通常合成に倒す（差し替え点）、図形テクスチャ上限 4096、画像は ImageIO で読める形式のみ。テキスト Source・個別エフェクト・動画デコード・FrameBuffer / Scene / Tachie の実 Source・アルファマスク実物・BSP 本体・先読み・キャッシュ・TimelineItemRects は引き続き未実装（該当アイテムは透明。合成グループの子は従来どおり描かれる）。
- ローカル作業のみで push はしていない（push は親側の検証後）。

## 2026-11-17 更新 — 映像アイテム範囲の是正（MAC-0011）

- MAC-0010 の照合で残した不整合を解消した。モデル層: `VideoItemProperties` プロトコル（本家 IVideoItem の映像プロパティ一式）を `Items/BaseItem.swift` に追加し、VisualItem・VoiceItem・TransitionItem が適合。VoiceItem は字幕側プロパティを jimakuX 等から x / y / … / videoEffects へ改名して保持し、保存キーを本家の [JsonProperty] 指定どおりに是正した（**JimakuX の保存キーは "Y"、JimakuY は "X" と入れ替わる**。Z 以降は IVideoItem と同名キー、FadeIn / FadeOut と VideoEffects は Jimaku* のまま）。TransitionItem は従来「保存時に既定値を書き、読み込み時は捨てる」だった一式を、既定値を初期値として型付き保持し往復させる形に変えた（本家は get 専用で値を保持しない。データ保全優先の意図的な差分で、本家が書くファイルでは常に既定値のため実ファイルでは差は出ない）。
- 描画層: EffectedOutput / EffectedItemSource の対象型、EffectPairProvider.ownEffectPairs、TimelineComposer の sourceProvider と資源対象、OrderedDrawResource の便利初期化子を `BaseItem & VideoItemProperties` に統一。TimelineComposer は VoiceItem / TransitionItem にも資源を生成し、TachieFaceItem は資源を持たない。isVideoItemEquivalent は適合判定そのものになった。PickFaceItems の対象（TachieFaceItem / VoiceItem）は変更なし。詳細と差分は IMPLEMENTATION_LOG の MAC-0011。
- 未解決として残るもの: VoiceItem の JimakuVisibility / キャラクター解決は未実装（自前値をそのまま公開する。字幕 Source＝本家 JimakuSource の段で置き場を決める）。（MAC-0014 で解消済み: 解決は YMM4Core の共通アクセサに置き、読み込み時の CharacterName 解決も実装した。）X / Y 入れ替わりは逆コンパイル済みコードが唯一の根拠で、VoiceItem を含む実ファイルでの裏取りは未実施。旧形式キー（MAC-0010 以前の ymm4mac が書いた "JimakuX" 等）を含むファイルでは該当キーが追加フィールド保持になる。デバッグ用サンプル sample.ymmp は MAC-0011 追補で現行コーデックにより再生成済みのため、もう該当しない。
- 検証: `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（リポジトリルート）で全194件合格（従来187＋新規7）、警告なし。ローカル作業のみで push はしていない（push は親側の検証後）。

## 2026-11-17 更新 — 合成の実行部（MAC-0010）

- `Sources/YMM4Core/Rendering/` に合成の実行部を実装した（Foundation のみ、GPU に触れない抽象描画先の形）。新規ファイル: `EffectedItemSource.swift`（エフェクト連鎖の処理器・定義・組と供給元 EffectPairProvider、描画先の抽象 RenderTarget / RenderTargetFactory、AlphaMaskEffect の境界、EffectedOutput / EffectedItemSource / EffectedItemError）と `TimelineSource.swift`（TimelineScene、TachieSource、TimelineGroupResolver、TimelineComposer / TimelineCompositionError）。MAC-0009 側は `Source.update` と `DrawingEffectProcessor.update` を throws 化しただけ（失敗契約を型で表すため。非 throws の既存実装はそのまま適合）。詳細と本家との差分は IMPLEMENTATION_LOG の MAC-0010。
- 確定契約の実装ポイント: 連鎖の再利用は位置基準・差し替えは新側の SetInput → Update 完了後に旧側を破棄・再利用時の SetInput は入力参照が変わった場合だけ再発行。出力0件でも有効な出力を返す。失敗時の旧 Output は Source.Update／連鎖の失敗では無事（旧描画先の破棄は全出力の更新完了後）。TimelineComposer は UpdateResources で範囲外の実行部を破棄し、親エフェクトを毎回再構築（顔・声解決→グループ解決の順）。FrameBuffer 境界は所有権移転＋Input/FrameSize 設定＋次回 Update 冒頭での解放までを契約として実装し、実描画は描画先の抽象に留めた。
- 未実装として残したもの（いずれも台帳に記録）: 先読み（PrefetchResources）、キャッシュ（CacheProvider。呼び出し位置のみ差し替え点）、TimelineItemRects、CameraFinalizer の内部、診断文字列の境界問い合わせとパラメータ JSON。実行部の対象は VisualItem のみで、VoiceItem / TransitionItem は資源を持たない。（MAC-0011 で是正済み。）
- 照合で見つけた不整合: MAC-0009 の ItemPicker が使う VideoItemCandidate の範囲（VisualItem + TachieFaceItem）は、本家 IVideoItem の実装範囲（VisualItem 系譜 + VoiceItem + TransitionItem、TachieFaceItem は含まない）と異なる。逆コンパイル済みコードのクラス宣言で確認した。（モデル層の保持と合わせて MAC-0011 で解消。）
- 検証: `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（リポジトリルート、.build を消したクリーンビルドを含む）で全187件合格（従来160＋新規27）、警告なし。ローカル作業のみで push はしていない（push は親側の検証後）。
- 次段の描画系作業（いずれも未着手）: GPU 実行器（IGraphicsDevices 相当・Context・CommandList の実記録と合成実行。第1章・第2章の契約。RenderTarget / Source / 処理器の実物はここで生まれる）、個別エフェクトの実装（モデル層 PreservedObject から VideoEffectDefinition を供給する EffectPairProvider の実物を含む）、基本 Source（画像・図形・テキスト）、テキスト描画、メディア読み込み（デコーダ）、PlaneSplitBsp 本体、先読み・キャッシュ・TimelineItemRects の実物。描画バックエンド（Metal 等）は未確定事項であり、採用前に本人の承認と最小限の実証が要る。音声・書き出し・UI も未着手のまま。

## 2026-11-17 更新 — デバッグ用アプリ初回ビルド（失敗→修正済み、再ビルド待ち）

- 本人の Mac で `10bf59c`（main）に対し `swift run` を実行。初回ビルドは `ContentView.swift` の `Animation` 名前衝突（YMM4Core.Animation と SwiftUI.Animation）で失敗。
- 修正済み: 型宣言とイニシャライザを `YMM4Core.Animation` と完全修飾（IMPLEMENTATION_LOG の MAC-0006 追補）。本人が main を pull して再ビルドすれば確認できる。再ビルド結果と、実 .ymmp があれば読み込み診断・往復チェックの結果が次の記録対象。
- **再ビルド成功（2026-11-17 本人確認）**: アプリは起動し、ファイルなし確認（VideoInfo 既定値 1920×1080 / 30 FPS / 48000 Hz、アニメーション評価の直線移動の値とランダム移動の再現性）は全項目クリア。
- 実 .ymmp の確認は本人の手元にファイルがないため未実施。代替として確認用サンプル `Apps/DebugApp/Sample/sample.ymmp` を用意した（YmmpCodec で生成し、未知 $type アイテムを1件注入。読み込み診断に読み飛ばしが1件出るのが正しい表示。キャラクター2件、タイムライン2件、メインのアイテムは読み飛ばしを除き6件）。本家が生成した実ファイルではないため、実ファイルでの検証は引き続き未実施。
- **実ファイル判明・検証済み（2026-11-17）**: 本人が古い本家 .ymmp 2件を提供。アプリでは BOM が原因で読み込み失敗（offset 0）となったが、原因を特定して互換層を修正済み（IMPLEMENTATION_LOG の MAC-0005 追補）。ローカル検証では2件とも読み込み成功・読み飛ばし0件・往復の固定点到達を確認した。本人が main を pull してアプリで開き直し、表示（ファイル1: アイテム158件・1920×1080・60 FPS／ファイル2: アイテム142件）が一致するかを確認するのが次の記録対象。
- **サンプルのタイムライン切替も確認済み（2026-11-17 本人確認）**: sample.ymmp を開いてメイン⇄サブの切替ができた。これでデバッグアプリの確認項目は全て完了。
- **アプリ側でも確認完了（2026-11-17、スクリーンショットで確認）**: ファイル1（kiminihare.ymmp）をアプリで開き、タイムライン1件・キャラクター0件・1920×1080・60 FPS・48,000 Hz・現在フレーム 4,513・アイテム158件がローカル検証と一致。読み込み診断は「読み飛ばし・型移行なし」、往復チェックは「固定点に到達（780172 バイト）」でローカル検証のバイト数とも一致し、コピー保存（kiminihare.roundtrip.ymmp）も作成された。本人の指摘2点はどちらもファイル側の内容が理由で不具合ではない: (1) タイムラインが1つしか選べないのは、このファイル自体がタイムライン1件のみを含むため（複数タイムラインの切替確認には2件入りのサンプル sample.ymmp を使う）。(2) 選択中 TextItem の X/Y が動かないのは、そのアニメーション種別が「なし」（単一の定数値）のためで、全フレーム同値が正しい評価結果である。

## 2026-11-17 更新 — 描画層の土台（MAC-0009）

- `Sources/YMM4Core/Rendering/` に GPU に触れない合成ロジックを実装した（Foundation のみ、Linux でテスト可能）。内容: ImageReference（描画グラフへの不透明参照）、Source / SourceOutput / DrawingEffectProcessor / FrameBufferSource プロトコルと StandardSourceOutput、DrawDescription 値型、説明レコード（Timeline / Item / Effect）、ItemPicker（CompositeItemPicker 全体／グループ用、TransitionItemPicker）、描画順序（3キー）と ZIndex・四隅算出、DrawSegmentBuilder。詳細と本家との差分は IMPLEMENTATION_LOG の MAC-0009。
- BSP 本体（PlaneSplitBsp）は未実装。`PlaneSplitOrdering` プロトコルの差し替え点にしてあり、既定の NullPlaneSplitOrdering では全ランが逐次描画へフォールバックする（本家でも Sort が nil なら逐次）。
- 検証: `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（リポジトリルート、.build を消したクリーンビルドを含む）で全160件合格（従来129＋新規31）、警告なし。ローカル作業のみで push はしていない。
- 次段の描画系作業（いずれも未着手）: GPU 実行器（IGraphicsDevices 相当・Context・CommandList の記録と合成実行。第1章・第2章の契約）、EffectedItemSource 相当（エフェクト連鎖・ParentEffects 再構築・FrameBuffer 境界）、TimelineSource 相当（資源管理・先読み・合成の統合）、テキスト描画、メディア読み込み（デコーダ）、PlaneSplitBsp 本体。描画バックエンド（Metal 等）は未確定事項であり、採用前に本人の承認と最小限の実証が要る。音声・書き出し・UI も未着手のまま。

## 2026-11-16 更新 — デバッグ用アプリの殻（MAC-0006）

- 本人の指示「明日の朝までに実ソフトでデバッグできる段階まで」で追加。開き方: 本人の Mac で `Apps/DebugApp/Package.swift` を Xcode で開いて実行する（または同ディレクトリで `swift run`）。
- できること: .ymmp を開く（読み込み診断＝未知 $type の読み飛ばし・型移行の一覧つき）、タイムライン／アイテム一覧、VisualItem の X/Y/Z アニメーションのスクラブ評価、往復固定点チェック、コピー保存。サンプル Animation の評価スクラブも残してある。
- 注意: 製品 UI ではなく検証の殻。UI 実装方式は未確定のまま。Package の platforms 宣言はハーネス都合で macOS 14 としてある（製品の最低対応は macOS 26.0 のまま）。

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
