# 引継書 — 次の作業者はここから読む

更新: **2026-11-17**。現状: モデル層＋.ymmp 互換層（MAC-0005）＋編集操作・モデル残件（MAC-0007・0008）＋描画層の土台（MAC-0009、`Sources/YMM4Core/Rendering/`）＋合成の実行部（MAC-0010）＋映像アイテム範囲の是正（MAC-0011）＋GPU 実行器と基本 Source（MAC-0012、`Sources/YMM4GPU/`）まで実装済み。デバッグ用アプリの殻（MAC-0006、`Apps/DebugApp/`）は本人の Mac でビルド・実ファイル読み込み・往復まで確認完了し、合成プレビュー欄を追加した。テストは Linux 上で全194件合格。

## 2026-11-17 更新 — GPU 実行器と基本 Source（MAC-0012）

- 新規ターゲット `Sources/YMM4GPU/`（Metal）に GPU 実行器を実装した。全ソース `#if os(macOS)` で、Linux では空モジュール（`swift test` は従来どおり全194件合格）。型は: MetalGraphicsDevices（MTLDevice 共有、パイプライン・サンプラ・1×1 透明テクスチャの即時生成、ImageReference の登録表）、MetalGraphicsContext（消費者ごとの文脈。自分の MTLCommandQueue を所有し RenderTargetFactory を兼ねる。第2章の契約どおりデバイスは共有・文脈は消費者ごとに新規）、MetalImage（ImageReference の実体 = MTLTexture＋平面座標の境界＋変換＋不透明度＋補間方式。属性は BGRA 8bit / Premultiplied）、MetalRenderTarget（RenderTarget の実物。画面サイズのテクスチャへ畳み込み、close() で同期完了）、MetalDrawingEffect（DrawingEffect の実物。ズーム×ワールド×透視の変換と不透明度を実体へ記録する遅延評価。PlaneSplitGeometryProviding も実装）、MetalImageSource（ImageIO デコード、失敗時は 1×1 透明）、MetalShapeSource（RectangleShapeParameter＋単色ブラシを SDF で描画。本家の実現化規則の可視結果を再現）、MetalEmptySource（未対応種別の透明 Source）、MetalSourceProvider（種別→Source の供給元）。
- デバッグアプリに合成プレビュー欄を追加した（`Apps/DebugApp/Sources/YMM4MacDebug/PreviewBox.swift` が新規、ProjectView に画像表示＋フレームスライダ）。開いた .ymmp の現在フレームを TimelineComposer ＋ Metal で合成し、読み戻した CGImage を表示する。既存の診断・往復チェックは不変。
- 検証（本人の Mac、SSH 経由）: ルートパッケージとデバッグアプリの `swift build` 成功（警告なし）。ヘッドレスハーネスで sample.ymmp のフレーム 0 / 10 / 45 の合成が例外なく完了し、図形（100×100 白、中心が不透明白）と画像（/tmp/image.png 64×48 赤、中心が不透明赤）のピクセルを読み戻しで確認した。**プレビュー欄の画面上での目視は未実施**（次に本人がアプリを起動したときの確認対象）。実ファイルの素材は Mac 上に無いため、実ファイルを開いた場合のプレビューは素材不在で透明になる見込み。
- 差分・未実装（台帳 MAC-0012 に記録）: 描画先は無限平面ではなく画面サイズへ畳み込む（画面外の中間結果は段階ごとに切り取られる）、コマンドは close() で同期実行、BlendMode の特殊合成は通常合成に倒す（差し替え点）、図形テクスチャ上限 4096、画像は ImageIO で読める形式のみ。テキスト Source・個別エフェクト・動画デコード・FrameBuffer / Scene / Tachie の実 Source・アルファマスク実物・BSP 本体・先読み・キャッシュ・TimelineItemRects は引き続き未実装（該当アイテムは透明。合成グループの子は従来どおり描かれる）。
- ローカル作業のみで push はしていない（push は親側の検証後）。

## 2026-11-17 更新 — 映像アイテム範囲の是正（MAC-0011）

- MAC-0010 の照合で残した不整合を解消した。モデル層: `VideoItemProperties` プロトコル（本家 IVideoItem の映像プロパティ一式）を `Items/BaseItem.swift` に追加し、VisualItem・VoiceItem・TransitionItem が適合。VoiceItem は字幕側プロパティを jimakuX 等から x / y / … / videoEffects へ改名して保持し、保存キーを本家の [JsonProperty] 指定どおりに是正した（**JimakuX の保存キーは "Y"、JimakuY は "X" と入れ替わる**。Z 以降は IVideoItem と同名キー、FadeIn / FadeOut と VideoEffects は Jimaku* のまま）。TransitionItem は従来「保存時に既定値を書き、読み込み時は捨てる」だった一式を、既定値を初期値として型付き保持し往復させる形に変えた（本家は get 専用で値を保持しない。データ保全優先の意図的な差分で、本家が書くファイルでは常に既定値のため実ファイルでは差は出ない）。
- 描画層: EffectedOutput / EffectedItemSource の対象型、EffectPairProvider.ownEffectPairs、TimelineComposer の sourceProvider と資源対象、OrderedDrawResource の便利初期化子を `BaseItem & VideoItemProperties` に統一。TimelineComposer は VoiceItem / TransitionItem にも資源を生成し、TachieFaceItem は資源を持たない。isVideoItemEquivalent は適合判定そのものになった。PickFaceItems の対象（TachieFaceItem / VoiceItem）は変更なし。詳細と差分は IMPLEMENTATION_LOG の MAC-0011。
- 未解決として残るもの: VoiceItem の JimakuVisibility / キャラクター解決は未実装（自前値をそのまま公開する。字幕 Source＝本家 JimakuSource の段で置き場を決める）。X / Y 入れ替わりは逆コンパイル済みコードが唯一の根拠で、VoiceItem を含む実ファイルでの裏取りは未実施。旧形式キー（MAC-0010 以前の ymm4mac が書いた "JimakuX" 等）を含むファイルでは該当キーが追加フィールド保持になる。デバッグ用サンプル sample.ymmp は MAC-0011 追補で現行コーデックにより再生成済みのため、もう該当しない。
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
- **製品 UI、動画デコード、音声、書き出しの実装はまだない。** GPU 合成は MAC-0012 で基礎（Metal 実行器＋画像・図形 Source）が入ったが、テキスト・エフェクト・動画等の実 Source は未実装。

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
