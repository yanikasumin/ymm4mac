# 実装台帳 — 何を・どこに・どう実装したか

この文書は実装の履歴の正本である（追記専用）。各変更について「何を・どこに・どう実装したか」を自然言語で記録する。現行状態は [STATUS.md](STATUS.md)、構造は [ARCHITECTURE.md](ARCHITECTURE.md)、次にやることは [HANDOFF.md](HANDOFF.md)、課題の台帳は GitHub Issues を参照すること。

## 索引

- DOC-0001 — 開発リポジトリの初期化
- MAC-0001 — モデル層の土台: VideoInfo と Animation
- MAC-0002 — Animation 評価の数式置き換え
- MAC-0003 — ドメインモデル: Project / Timeline / アイテム13クラス
- MAC-0004 — 編集操作: 追加・衝突解決・グループ移動・分割・ChangeFrameRate・削除
- MAC-0005 — .ymmp 互換層
- MAC-0006 — デバッグ用アプリの殻
- MAC-0007 — 残りの編集操作
- MAC-0008 — 隣接削除系・Character 型付き拡張・ShapeParameter 完全化
- MAC-0009 — 描画層の土台
- MAC-0010 — 合成の実行部
- MAC-0011 — 映像アイテム範囲の是正
- MAC-0012 — GPU 実行器
- MAC-0013 — 音声パイプラインの芯
- MAC-0014 — テキスト描画
- MAC-0015 — キャラクター参照の保存・解決契約の是正
- MAC-0016 — 音声 QA：ドリフト実測とシーク量子化の修正
- MAC-0017 — 書き出し
- MAC-0018 — 映像エフェクト定義層＋DrawDescription 変換型処理器
- MAC-0019 — 映像エフェクト定義層のコーデック＋合成チェーン接続
- MAC-0020 — VoiceItem の字幕エフェクト解決の接続
- MAC-0021 — GPU 失敗の検出・通知契約
- MAC-0022 — GPU 処理系エフェクトの定義層73種
- MAC-0023 — GPU エフェクト Metal 処理器 第1段
- MAC-0024 — 音声リサンプラの高品質化 第1段
- MAC-0025 — Video／Scene／FrameBuffer／Tachie の実 Source
- MAC-0026 — 書き出しの実接続
- MAC-0027 — 合成グループの Source 実装
- MAC-0028 — GPU エフェクト Metal 処理器 第2段と内部合成への供給元伝播、画像／動画の上下反転是正
- MAC-0030 — 書き出しの解析・結果表現の是正
- MAC-0032 — エフェクト編集の書き戻しで入れ子の未知キーが消える問題の修正
- MAC-0033 — GPU テクスチャ確保失敗のエラー伝播統一
- MAC-0034 — 書き出しのモデル共有によるデータ競合の解消
- MAC-0035 — EffectItem 描画 Source
- MAC-0036 — 画面遷移
- MAC-0037 — 音声リサンプラの正式形
- MAC-0038 — デモ版内蔵のデバッグ用全自動テスト
- MAC-0039 — DebugApp の .app バンドル化
- MAC-0040 — VoiceItem の音声供給（Issue #51）
- MAC-0043 — PngWav ライター（PNG 連番＋WAV 書き出し）（Issue #49）
- MAC-0044 — Metal 初期化診断（失敗を握りつぶさない）（Issue #50）
- MAC-0041 — サウンドレベルメーター（Issue #52）
- MAC-0042 — 実時間再生（音声マスタークロック）（Issue #52）
- R6-FIX — レビュー第6ラウンド指摘の処分: リピート再開（R6-01）・開始失敗の通知（R6-03）・チャンク生成の世代競合
- PR32 — DebugApp フロントエンドの形
- UI-FORM — フロントエンドの形の完成（レイアウト・ツールバー・メニュー・コンテキストメニュー・ドロップイン等）
- UI32-01 — レベルメーターの本家構成化と誤記修正
- W1 — 構造整理 第1単位: テスト基盤の整備とハーネスの git 管理化
- BRUSH46 — ブラシ基盤: 型付きブラシモデルと GPU 塗り（Issue #46。MAC 番号は PR 時に付番）
- MOSAICRECT — 矩形モザイクの本家方式化（5点サンプル平均）
- GRADMESH — グラデーションメッシュブラシの型付き化と GPU 描画
- NOISE7 — Noise エフェクト残り7種の実処理化（Block / Perlin / Cellular / Voronoi / Simplex / Marble / Flow）。既存3種の差分に関する記述の一部は NOISEFIX で訂正
- NOISEFIX — Noise 既存3種（Fractal / Random / Curl）の本家シェーダとの差分是正
- 構造整理 W2〜W10 の記録は各 PR が正本（W2 = #68、W3 = #67、W4 = #72、W5 = #73、W6 = #74、W8 = #75、W7 = #76、W9 = #77、W10 = #78）
- INTEG-20261118 — 機能フェーズ10単位の統合（PR #84〜#93）と統合後検証
- FE-UNIT6 — フロントエンド単位6: セリフ入力・キャラクター・辞書ウィンドウの検査と修正（FE-R1-018 処分）

## 実装記録（変更IDごとに自然言語で追記）

#### DOC-0001 — 開発リポジトリの初期化

- 目的: 解析リポジトリからMac版ソースと実装記録を分離し、中断しても他の担当が引き継げる入口を設ける。
- 変更先: `yanikasumin/ymm4mac` の `README.md`, `AGENTS.md`, `docs/`, `.github/pull_request_template.md`, `.gitignore`。
- 実装: コードは追加していない。解析repoの要件・本家設計・互換マトリクスへリンクを設け、設計と実体、確認済みと仮説を分ける。実装が始まればここへ機能ごとに追記する。
- 本家との差分: 動画編集の動作への変更なし。開発運用の文書のみ。
- 検証: GitHub上のファイル存在を確認する。ビルドや映像処理のテストは**未実施**。
- 承認: 要件変更は行っていない。

#### MAC-0001 — モデル層の土台: VideoInfo と Animation（IMPLEMENTED）

**何を実装したか。** Swift パッケージの土台と、モデル層のうち VideoInfo（解像度・FPS・サンプリングレート）と Animation（値の時間変化）の独立実装。仕様の正本は解析側の抽出仕様 `MODEL-SPEC-EXTRACTION.md`（訂正記録を含む）§3・§6。

**どこを変更したか。** 本リポジトリ main（開始コミット `9b5d1fd`）の作業ツリーに `Package.swift`、`Sources/YMM4Core/`（Color / FrameTime / VideoInfo / AnimationType / KeyFrames / Animation）、`Tests/YMM4CoreTests/` を新規追加（本記録時点では未コミット・未 push）。

**どう実装したか。**
- `VideoInfo`: 既定値 1920×1080 / 30 FPS / 48000 Hz。本家の Range 属性を有効範囲の定数として保持し、`isWithinValidRanges` で検証する。本家の setter はクランプしないため、代入は素通しとし範囲外もそのまま保持する。フレーム⇔時間換算は `FrameTime`（AwayFromZero 丸め、FrameToTime は 100ns tick 粒度）に FPS を渡す。
- `AnimationType`: 本家の数値テーブルをそのまま写した列挙（基本型8、イージング10科×8、ベジェ2）。分類規則（キーフレーム対応・IsEasing・IsInterpolationEasing・IsInterpolation）を計算プロパティで再現した。
- `Animation`: values / animationType / span / bezier と定義値（default・min・max・loop）を保持。評価は本家 GetValue の分岐のうち数式が抽出済みの範囲（なし、直線移動、瞬間移動、移動量指定、反復移動の Span=0）を実装し、最終処理（Loop 剰余、[min, max] クランプ）を全型に適用する。キーフレーム位置は `位置 * fps / videoFPS` の整数演算で評価尺度へ換算する。キーフレーム追加時は「その位置での現在値」を挿入し（曲線は不変）、値の連動はキーフレーム対応の型に限る（訂正済み仕様どおり）。削除も対称に連動する。
- `KeyFrames`: アイテム単位で共有される位置集合（昇順・重複なし）と Distribute を実装。

**本家との差分。** 内部実装のみで、ユーザーから見える差はない（モデル層の基盤であり UI はまだない）。意図的に未実装の部分: イージング関数の数式、スプライン重み（Cubic.GetWeight）、ベジェ評価、ランダム移動の乱数生成、反復移動の Span>0 は本家の数式・方式が未抽出のため、該当型の評価は暫定の線形補間／先頭値で代用し、コード内に明記した。VERIFIED とはしない。

**メモリ・並行性。** 全て値型（struct）で、所有権は値セマンティクスに帰着する。スレッドや非同期は扱わない。

**検証。** Linux VM 上の Swift 6.1.2 で `swift test` を実行し、全26件合格（VideoInfo 6件、AnimationType 5件、Animation 15件）。macOS 上でのビルドは未実施（Foundation のみのコードであり、macOS 固有 API は使っていない）。

**次の担当へ。** 残課題は未抽出の数式群（上記）の抽出と評価の置き換え、KeyFrames の RemovesLeft/RemovesRight（分割用）、Timeline / BaseItem の実装。

#### MAC-0002 — Animation 評価の数式置き換え（IMPLEMENTED）

**何を実装したか。** MAC-0001 で暫定実装（線形補間／先頭値で代用）だった `Animation` の評価分岐を、抽出済みの数式で全て置き換えた。対象はイージング全科、補間移動・加減速移動のスプライン加重平均、_Int イージング系の全体率経路、ベジェ評価（Linear_Bezier / Interpolation_Bezier）、ランダム移動（Span = 0 / Span > 0）、反復移動（Span > 0 と Span = 0 のパリティ修正）。数式の正本は解析側の `ANIMATION-FORMULAS.md`（全項目確定済み）。

**どこを変更したか。** 本リポジトリの作業ツリー（本記録時点では未コミット・未 push）。新規: `Sources/YMM4Core/Easing.swift`、`Cubic.swift`、`StatelessRandom.swift`、`BezierAnimation.swift`。変更: `Animation.swift`（評価の全面置き換え、`randomSeed` の追加、ベジェ型定義を `BezierAnimation.swift` へ移動）、`AnimationType.swift`（`easingFamilyAndMode` の追加）。テスト新規: `Tests/YMM4CoreTests/EasingTests.swift`（`CubicTests` を含む）、`StatelessRandomTests.swift`、`BezierAnimationTests.swift`、`AnimationEvaluationTests.swift`。既存テストの期待値修正2件（反復移動 Span = 0 のパリティ、瞬間移動の最終フレーム）。

**どう実装したか。**
- 評価の分岐構造を本家 `GetValue` の分岐連鎖どおりに再構成した。キーフレーム系の4経路（補間移動系／_Int 系＋Interpolation_Bezier／Linear_Bezier／その他のキーフレーム対応型）は本家では早期 return であり、最終処理（Loop 剰余・クランプ）を通らない。MAC-0001 の「最終処理を全型に適用」は本家と異なる暫定措置だったため改めた。
- イージング: 科ごとの In 素関数＋端点ラッパー（t = 0 で 0、t = 1 で 1 を強制）、Out / InOut / OutIn は全科共通の汎用合成。Jump の InOut 特例を含む。Bounce は本家どおりループで区間を確定してから閉形式を評価する。_Int 版と非 _Int 版は同一の関数を返し、違いは評価経路だけである（仕様書側の誤りは解析側 `MODEL-SPEC-EXTRACTION.md` の訂正記録4に記録）。
- スプライン: `Cubic.GetWeight`（A = -0.5）は符号付き距離のまま計算し、絶対値化は呼び出し側の経路による。補間移動経路は率の連続座標変換（最初と最後の区間だけ率を加工する）＋符号付き距離の加重平均。ループ条件は本家 `Animation.cs` の「区間数 + 1」までを含み、値の範囲を1つ超えた位置は `GetKeyFrameValue` の末尾フォールバックで最後の値になる（このため2値補間の中点は単純な中間値にならない）。なお `ANIMATION-FORMULAS.md` §1.1 の擬似コードの上限表記とは1つずれるため、実コードを優先した（数式側の確認事項として別途報告）。
- _Int 経路: 全体率にイージングを適用し、位置 = 率 × 区間数として、距離は絶対値化・インデックスはクランプ（距離計算にはクランプ前の位置を使う）で加重平均する。重み和が 0 の場合のフォールバックも本家どおり再現した。
- ベジェ: アンカー点＋相対制御点オフセット（float 成分で保持）。区間ごとに制御点の X のみクランプし、係数 a〜c は float 精度で計算してから double へ広げ、x(t) = rate を Newton 法（最大5回）で解いて y(t) を Bernstein 形で評価する。IsQuadratic は本家 `ToQuadraticPoints` の点列変換後に同じ3次評価を適用する。
- ランダム移動: `StatelessRandom` の Mix 方式（初期状態 0x9E3779B97F4A7C15、キー列の混合）を再現した。Span > 0 は重み和での正規化をしない加重和である。
- 反復移動: Span > 0 は Span/2 を半周期とする三角波に Sine InOut を適用。Span = 0 は `(int)(rate * totalFrame)` の偶奇で、奇数フレーム＝開始値、偶数フレーム＝終了値（従来実装の仮定と逆だったため修正）。

**本家との差分。** ユーザーから見える差として意図したものはない。残る既知の差: (1) ランダム移動の乱数列は、本家のシード材料 `GetHashCode()` の具体値との対応付けが未確定のため本家と一致しない。Swift 側は `Animation.randomSeed`（既定 0）で代用し、決定的性質（同一入力で同一結果）だけを保証する。(2) Bounce の素関数は、本家では t < -1/11 で区間確定が終了しないため、反復回数に上限を設けた（通常の率 0...1 では到達しない）。(3) 瞬間移動で frame == totalFrame のとき、本家は最後の区間の開始値を返す（従来実装は終了値を返していたため、テスト期待値を本家に合わせて変更した）。

**メモリ・並行性。** 全て値型（struct / enum）で、所有権は値セマンティクスに帰着する。スレッドや非同期は扱わない。

**検証。** Linux VM 上の Swift 6.1.2 で `swift test` を実行し、全60件合格（従来26件＋新規34件）。期待値は本家の数式を独立に計算した既知ベクトルで固定した（StatelessRandom のキー列→生成値、スプライン加重平均の各経路、ベジェ評価、反復移動 Span > 0）。macOS 上でのビルドは未実施。本家実機との比較試験（Golden Master）は未実施のため VERIFIED ではなく IMPLEMENTED とする。

**次の担当へ。** 残課題は `GetHashCode()` 対応付けの確定（本家実機での乱数列採取が必要）、Timeline / BaseItem の実装、KeyFrames の RemovesLeft/RemovesRight、`ANIMATION-FORMULAS.md` §1.1 のループ上限表記の確認。

#### MAC-0003 — ドメインモデル: Project / Timeline / アイテム13クラス（IMPLEMENTED）

**何を実装したか。** モデル層の中心となるドメインモデル一式。`Project`（Timelines / Characters / CollapsedGroups / LayoutXml / ToolStates / FilePath / SelectedTimelineIndex）、`Timeline`（Items / CurrentFrame / Length・MaxLayer のキャッシュ / LayerSettings / TimelineVerticalLine / 選択）、アイテム13クラス（Audio / Video / Voice / Text / Image / Shape / Effect / Group / Scene / FrameBuffer / Tachie / TachieFace / Transition）と共通基底 `BaseItem` / `VisualItem`、`Character`（型付きは Name / GroupName / Color / Layer のみ）。仕様の正本は解析側 `MODEL-SPEC-EXTRACTION.md`（訂正記録を含む）と実コード。

**どこを変更したか。** 本リポジトリの作業ツリー（本記録時点では未コミット・未 push）。新規: `Sources/YMM4Core/Items/BaseItem.swift`（BaseItem / VisualItem）、`Items/MediaItems.swift`（Audio / Video / Image）、`Items/TextItems.swift`（TextDecoration / TextAppearance / Text / Voice）、`Items/CompositeItems.swift`（Shape / Effect / Group / Scene / FrameBuffer / Tachie / TachieFace / Transition）、`Project.swift`、`Timeline.swift`、`TimelineSupport.swift`（LayerSetting / LayerSettings / TimelineVerticalLine / SerializableToolState）、`Character.swift`、`Enums.swift`（Blend 他9種）、`HonkeFormat.swift`（TimeSpanValue / Color の "#AARRGGBB" / RenamedTypeResolver / PreservedObject / AnimationType のメンバ名対応）、`PlaybackRateMap.swift`。変更: `KeyFrames.swift`（removingLeft / removingRight と除去個数）、`Animation.swift`（setFirstValue、分割連動 applyKeyFramesRemovesLeft / Right）。

**どう実装したか。**
- アイテムはクラス（参照型）とした。本家の編集操作は「コミット前の入力アイテム自体の書き換え」を含み、C# の参照セマンティクスが前提のため。`Animation` の文脈（キーフレーム・長さ・基準 FPS）は本家同様、所有アイテムから `forEachAnimation` のオーバーライド列挙で全 `Animation` へ伝播する。`KeyFrames` / `Length` の代入（didSet）と `SetFPS` が伝播点。
- `Timeline.Length` / `MaxLayer` は本家と同じく保持フィールドを持つキャッシュで、追加・置換・移動では Expand（最大へ広げる）、削除では Refresh（再計算）という使い分けもそのまま再現した。CurrentFrame は負値を 0 に丸め、ロック中は変更できない。
- 意味論をモデル化しない値（エフェクト列、図形・遷移・発音・音声パラメータ等のプラグイン型オブジェクト）は `PreservedObject`（$type を含む生 JSON）で保持する。モデル化していないプロパティは各モデル型の `additionalFields`（順序保持）に残し、保存時に書き戻す。
- `Character` は約50プロパティのうち識別・表示に必要な4つだけを型付けし、残りは追加フィールドで往復保持する。
- 列挙型は StringEnumConverter のメンバ名で読み書きし、未知の名前は `unknown` として名前を保持して書き戻す。
- `TimeSpan` は tick（Int64）の値型 `TimeSpanValue` で保持し、"c" 形式文字列と相互変換する。色は "#AARRGGBB"、Guid は小文字の "d" 形式。
- 分割時の右側 `ContentOffset` 計算のため `PlaybackRateMap`（フレームごとのレート評価＋台形積分の累積テーブル、GetSourceTime / GetConsumedContent）を実装した。定数判定は「レートの型が なし」。

**本家との差分。** ユーザーから見える差として意図したものはない。内部実装の違い・既知の割り切り:
- `GroupItem` が本家で独自保持に上書きする FadeIn / Opacity 等は、保存形式が同一のため継承した保持をそのまま使う。
- `EffectItem.Zoom`（get 専用・毎回新規）と `IsInverted`（JsonIgnore）、`TransitionItem` の一時プロパティ群（X 等の get 専用、IsClippingWithObjectAbove と VideoEffects の setter 無効）は、本家の観測可能な挙動に合わせて「保存時は既定値を書き、読み込み時は捨てる」キーとして扱う。
- `ShapeItem` / `EffectItem` の新規作成時の ShapeParameter 既定値は、本家は `RectangleShapeParameter` の全プロパティを持つインスタンスだが、ここでは $type のみの最小オブジェクトで代用する（本家で読み込みは可能だが、本家で再保存した際の形とは異なる）。
- TextItem / VoiceItem のフォント既定値は本家リソース `Texts.DefaultFont` の実文字列が逆コンパイル済みコードから特定できず、空文字列とした（未解決）。
- `Timeline` の新規作成時の名前（本家はリソース文字列）も同様に空文字列。
- `ContentLength` / `OriginalContentLength` は本家ではファイルから求める派生値のため、モデルでは保持値（既定 0）とし、ファイルからの算出は行わない。
- `Project.FilePath` の「参照ファイルが無ければ空にする」規則は保存スナップショット構築側の責務として、モデルでは保持のみとした。
- AddItems / ReplaceItems / MoveItems は本家では private だが、アプリ側の利用のため public にした。

**仕様書と実コードの矛盾（実コードを優先した点）。** (1) 衝突判定 `IntersectsWith` は仕様書で半開区間の重なりと「推定」されていたが、実コードの条件式を場合分けで検証し、長さ1以上の区間では半開区間の重なりと等価であることを確認した。(2) `ResolveItemCollision` のデルタ列は仕様書の「+(999 - layer)」ではなく実コードの Range 意味論どおり最大 +(998 - layer)、負側は -(layer - 1) まで。(3) `Length` / `MaxLayer` / `KeyFrames.Frames` 等の private setter プロパティは、Newtonsoft が復元するため読み込み時に復元する方針とした（仕様書では未検証だった点）。

**メモリ・並行性。** アイテム・Timeline・Project・Character・LayerSettings はクラス（参照セマンティクスが本家の意味論に必要）。それ以外は値型。スレッドや非同期は扱わない。

**検証。** MAC-0005 の互換層テストと MAC-0004 の編集テストで検証（全87件合格、うち新規27件）。本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**次の担当へ。** Character の型付き範囲の拡張は必要になった時点で。フォント既定値とタイムライン名のリソース文字列は本家実機（リソースアセンブリ）の確認が必要。

#### MAC-0004 — 編集操作: 追加・衝突解決・グループ移動・分割・ChangeFrameRate・削除（IMPLEMENTED）

**何を実装したか。** `Timeline` の編集操作一式を `Sources/YMM4Core/TimelineEditing.swift` に実装した。対象は本家 `Timeline` の TryAddItems / IsMovable / GetMovableDeltaFrame / MoveSelectedAndGroupedItems / ResolveItemCollision（3形態）/ ResolveItemCollisionInItems / ResolveAllItemsCollision / RenewGroupIDs / Group・Ungroup / SplitItems（+ SplitItemsCore、選択モード5種と Center の履歴処理）/ ChangeFrameRate / DeleteItems 系と、アイテム側の `BaseItem.split(atRelativeFrame:)`（KeyFrames の RemovesLeft / RemovesRight 連動を含む）。

**どう実装したか。** 本家の実コードを逐条で写した。特に:
- TryAddItems: 前処理（SetFPS→集合内衝突解決→グループ ID 再発行）は入力アイテム自体を書き換え、原子的保証は Items へのコミット段階のみ。レイヤー探索は希望オフセットから増加方向に 999 - maxLayer まで、次に -minLayer から希望の直前まで。
- 集合内衝突解決 `ResolveItemCollisionInItems` は「自分と重なる他者がいる側が上がる」ため、処理順の早いアイテムが上がる（直観と逆だが本家の挙動どおりで、テストで固定した）。
- GetMovableDeltaFrame: 範囲外の境界補正（フレーム下限、レイヤー下限、キャッシュ済み MaxLayer による上限）の後に、衝突距離の最大分だけフレームデルタを縮小する。フレームデルタ 0 で動けない場合はレイヤーデルタを 0 へ寄せる。「移動不可なのに衝突相手が無い」場合は本家は例外を投げるため、到達不能分岐として fatalError にした。
- 分割: 左右とも JSON 往復による複製から作る（本家 GetClone と同じ経路）。キーフレーム連動はキーフレーム対応の AnimationType のみで、切断位置の現在値を開始値（右）／終了値（左）として値列を再構築する。評価はキーフレーム集合を更新する前に行う。グループ ID の再発行は左右の断片集合に対して別々に行われ、単独になった側は解散する。右側の ContentOffset は定数レートなら消費分の加算、非定数なら PlaybackRateMap の積分で置換（開始レートが負なら反転）。
- ChangeFrameRate: Frame / Length は比率の切り捨て換算、キーフレームは換算後に前方向（単調化）・後方向（Length 未満化）・先頭ずらし（Length 延長）の3段修復。書き戻し順（率 > 1 で後ろから）は SetFrame の置換イベントが値を変えないため一括置換と等価。換算後に重なりが生じたレイヤーには LayerSettings.Insert で空レイヤーを挿入し、重なるアイテムをフレーム降順に1つずつ下げ、範囲内の GroupItem.GroupRange を広げる。CurrentFrame は整数演算で換算。

**本家との差分。** なし（意味論の再現が目的）。GetMovableDeltaFrame は本家 private だが検証とアプリ利用のため public にした。

**検証。** `Tests/YMM4CoreTests/TimelineEditingTests.swift` 15件: 衝突解決の探索順（増加優先・減少への回り込み）、TryAddItems の探索順と前処理（衝突の上がり方向、グループ再発行と単独解散、失敗時も前処理の書き換えが残ること）、グループ移動のデルタ縮小と 0 クランプ、分割のキーフレーム連動（対応型／非対応型、定数レートと非定数レートの ContentOffset）、分割でのグループ解散、ChangeFrameRate 30→60 / 30→24（キーフレーム修復、レイヤー挿入）、削除時のキャッシュ再計算。全件合格。本家実機との比較は未実施のため IMPLEMENTED。

**次の担当へ。** DeleteAndMove、長さ変更（ChangeItemsStart / End 系）、スナップ（GetSnappedDelta）は未実装。必要になった時点で本家コードから起こす。

#### MAC-0005 — .ymmp 互換層（IMPLEMENTED）

**何を実装したか。** `Sources/YMM4Core/YmmpCodec.swift` と基盤の `JSONValue.swift`（順序保持 JSON 値＋自前パーサ／シリアライザ）、`CodecSupport.swift`（Animation 等の JSON 形状変換）。読み込み（$type 解決、RenamedTypeResolver の移行、未知 $type の読み飛ばしと診断記録、旧形式の単一 Timeline 取り込み、YMM3 XML の拒否）と、保存（1行 JSON、一時ファイル→再読込検証→コピー）。

**どう実装したか。**
- Newtonsoft の設定を再現: TypeNameHandling.Auto、Simple アセンブリ形式、StringEnumConverter、エラー時は $type を握り潰す（ここでは読み飛ばして `YmmpLoadDiagnostics.skippedItems` に記録し、呼び出し側が取得できる形で返す）。型移行はアイテムの $type では診断にも記録し、エフェクト等の入れ子では保持オブジェクトの $type を書き換える（本家は移行先の型で読むため再保存時は移行先名になる）。
- データ保全: モデル化していないプロパティは追加フィールド（順序保持）として保持し書き戻す。数値は元のリテラル文字列を保持するため、読み込んだ数値は一字一句そのまま書き戻される。モデル側が生成する数値は Newtonsoft の最短往復形式で整形する。
- デコードは「既定インスタンスを生成してからキーを文書順に適用する」Newtonsoft の方式に合わせた。旧互換の set 専用プロパティ（Animation の From / To、Text / Voice の LineHeight / LetterSpacing、GroupItem の IsCompressFrame）は読み込み時の指令として処理し、書き出さない。ShapeItem の旧互換プロパティはパラメータの実型依存のため型付けせず追加フィールドで往復保持する方針とした。
- 読み込み後、各タイムラインのアイテムへ VideoInfo の FPS を注入する（本家でタイムライン配置時に行われる注入の再現）。Timeline の Length / MaxLayer はファイルにあれば復元し、無ければ再計算する。
- 保存の検証は「一時ファイルを再読込して例外なく復元できること」。本家は復元結果が null でないことの確認であり、それより強めの検証になっている（内部実装の違いのみ）。

**本家との差分。** (1) 未知 $type の「アイテム」は本家同様に読み飛ばすが、エフェクト等の入れ子オブジェクトは本家では null 化されるところを、データ保全方針（本人の確定方針）を優先して生 JSON のまま保持する。(2) 保存時の本ファイルへのコピーは削除＋コピーの2段（本家は File.Copy の上書き）。(3) 未知の enum 名は本家では例外になるところを、名前を保持して書き戻す。

**検証。** `Tests/YMM4CoreTests/YmmpCodecTests.swift` 12件: 数値リテラルの保持、往復の固定点（複数種のアイテム・キャラクター・ツール状態・レイヤー設定を含む Project を保存→再読込→再保存し、正規化 JSON の差分ゼロ。型移行が適用されるため固定点は2回目の往復で判定）、ファイル保存の往復、本家形式を模した手書き JSON の読み込み（Length / MaxLayer の復元を含む）、未知 $type の読み飛ばしと記録、未知プロパティの保持、型移行の適用、旧形式の取り込み、XML の拒否、TimeSpan / AnimationType 名 / 色の形式。全件合格（全体で87件）。本家実機が生成した実ファイルでの検証は未実施（フィクスチャ採取待ち）のため IMPLEMENTED 止まり。

**次の担当へ。** 本家実機の .ymmp フィクスチャ（FIXTURE-PLAN の P0 群）が採取できたら、本テスト群に実ファイルの往復を追加して VERIFIED へ進めること。設定ファイル（SettingsBase 系）も同じ Json 設定を共有するため、設定の読み書きが必要になったら本互換層を再利用できる。

**MAC-0005 追補（2026-11-17）— BOM 付き実ファイルの読み込み失敗と修正、実ファイル検証。** 本人が提供した本家実ファイル2件（いずれも UTF-8 BOM 付き＋インデント付き JSON）が、デバッグアプリで `invalidJSON("値の形式が不正です (offset 0)")` となり読み込めなかった。原因は2段構え: `decode` は BOM を除去した文字列で XML 判定をしていたが、パーサには未除去の原文を渡していたため、JSONParser が先頭の U+FEFF で失敗した。本家（StreamReader + Newtonsoft）は BOM を透過的に処理する。修正: (1) パーサへは BOM・空白を除去した文字列を渡す。(2) `load(fromFile:)` で UTF-16（LE / BE）の BOM があれば UTF-16 として復号する（本家の StreamReader の文字コード判定に合わせた）。回帰テスト2件を追加（BOM 付き JSON の読み込み、UTF-16 ファイルの読み込み）。**実ファイル検証（本家生成ファイルでの初の検証）**: 提供された2件とも読み込み成功。ファイル1: タイムライン1件・キャラクター0件・アイテム158件（Text 56 / Video 46 / Image 53 / Audio 1 / Shape 2）、1920×1080・60 FPS、読み飛ばし0件・型移行0件、往復の固定点に到達（再保存 780,172 バイト）。ファイル2: アイテム142件（Text 47 / Video 41 / Image 51 / Audio 1 / Shape 2）、1920×1080・60 FPS、読み飛ばし0件・型移行0件、固定点に到達（693,977 バイト）。なお再保存のバイト数が原本より小さいのは、原本のインデント＋BOM に対し再保存が1行 JSON のためであり、固定点は自形式の往復で判定している。本家での再保存結果とのバイト比較は本家環境がないため未実施。実ファイル自体は絶対パスを含むためリポジトリには含めていない（検証はローカルの一時テストで実施し、テストは削除済み）。

#### MAC-0006 — デバッグ用アプリの殻（IMPLEMENTED）

**何を実装したか。** 本人が実ソフトでデバッグできる段階として、YMM4Core を呼び出す検証用アプリを用意した。製品 UI ではなく、読み込み経路とアニメーション評価を Xcode でステップ実行・目視確認するための殻であり、UI 実装方式の未確定事項（基本指示 第9章）に対する決定ではない。

**どこを変更したか。** 新規パッケージ `Apps/DebugApp/`（ルートパッケージとは独立した SwiftPM パッケージとし、ルートの `swift test` が Linux で回り続けるように分離）。`Package.swift`（YMM4Core へのパス依存）、`Sources/YMM4MacDebug/YMM4MacDebugApp.swift`、`ContentView.swift`、`ProjectView.swift`。

**どう実装したか。** ContentView は VideoInfo 既定値の表示、サンプル Animation のフレームスクラブ評価、.ymmp ファイルの選択（fileImporter）と `YmmpCodec.load(fromFile:)` による読み込みを行う。読み込み後は ProjectView がタイムライン切替、VideoInfo と現在フレーム、アイテム一覧（型名・ラベル・Frame / Length / Layer / Group）、選択アイテムの詳細を表示し、VisualItem については X / Y / Z アニメーションをアイテム内フレームでスクラブ評価する。読み込み診断（読み飛ばした未知 $type アイテムと型移行の一覧）をそのまま表示し、往復チェックとして「読み込み→保存文字列生成→再読込→再保存文字列生成」の固定点一致を確認できるほか、本家手順の保存（`YmmpCodec.save`）でコピーを書き出せる。

**本家との差分。** 検証用の殻であり、本家 UI の再現ではない（ユーザーから見える違いとして意図的に割り切った範囲であり、製品 UI の仕様決定ではない）。

**検証。** この VM（Linux）では SwiftUI / AppKit をビルドできないため、アプリ側のビルドは未実施。呼び出す YMM4Core 側は `swift test` 全87件合格で検証済み。アプリのビルド確認は macOS 上（本人の Mac の Xcode）で Package を開くことが初回確認となる — 未実施と明記する。

**次の担当へ。** 本人の Mac で初回ビルドを通し、実物の .ymmp が手元にあれば開いて読み込み診断と往復チェックの結果を記録すること。本家を動かせる環境は現時点でないため（2026-11-16 本人確認）、フィクスチャ採取による VERIFIED 化は環境が用意されるまで到達不可であり、その間は IMPLEMENTED の格付けを維持する。

**MAC-0006 追補（2026-11-17）— 初回ビルド失敗と修正。** 本人の Mac で `10bf59c`（main）に対し `Apps/DebugApp` で `swift run` を実行し、初回ビルドが失敗した。エラーは `ContentView.swift:21:28` の `'Animation' is ambiguous for type lookup in this context` と、それに伴う34行目の二次的エラー。原因は `YMM4Core.Animation` と `SwiftUI.Animation` の名前衝突（この VM では SwiftUI をビルドできないため事前に検出できなかった）。修正: `ContentView.swift` の型宣言とイニシャライザ呼び出しを `YMM4Core.Animation` と完全修飾した（対象はこの2箇所のみ。`ProjectView.swift` は型名を書いていないため対象外）。**再ビルドは本人の Mac で成功し、アプリの起動とファイルなし確認（VideoInfo 既定値、アニメーション評価の値とランダム移動の再現性）は全項目クリアした（2026-11-17 本人確認）。** 実 .ymmp の読み込み確認は本人の手元にファイルがなく未実施。代替の確認用サンプルとして `Apps/DebugApp/Sample/sample.ymmp` を追加した（YmmpCodec で生成、未知 $type アイテム1件を注入し読み込み診断の表示も確認できるようにしたもの。生成時に読み飛ばし1件と往復固定点をテストで検証済み。本家生成の実ファイルではない）。

#### MAC-0007 — 残りの編集操作（DeleteAndMove / 長さ変更 / スナップ）（IMPLEMENTED）

**何を実装したか。** MAC-0004 で未実装だった編集操作3群を、本家 `Timeline`（`YukkuriMovieMaker.Project/Timeline.cs`）の実コードの意味論どおりに実装した。(1) `DeleteAndMove` / `DeleteAndMoveAll`（削除して後続を詰める。戻り値は新しい現在フレーム）。(2) アイテム長変更の一族: 入口 `ChangeSelectedAndGroupedItemsLength`（選択＋グループへ一括適用）、伸縮可能量 `GetExpandableDeltaLength`、開始側変更 `ChangeItemsStart`、終了側変更 `ChangeItemsEnd`。隣接アイテムへの影響モード `NeighborAffectMode`（Default / None / Stretch）は `YukkuriMovieMaker.Settings/NeighborAffectMode.cs` の定義どおり列挙型として追加した。(3) スナップ吸着量 `GetSnappedDelta`。

**どこを変更したか。** `Sources/YMM4Core/TimelineEditing.swift`（`Timeline` の extension に3群を追加）、`Sources/YMM4Core/Enums.swift`（`NeighborAffectMode` 追加）、`Tests/YMM4CoreTests/TimelineEditingTests.swift`（新規25件）。ローカル作業のみ（push なし）。

**どう実装したか。** DeleteAndMove は対象ごとに「同じレイヤーで対象終了位置以降のアイテムを対象の長さだけ前進」→削除→Refresh の順で処理し、現在フレームは対象ごとに `newFrame - max(newFrame - 対象.Frame, 0)` で更新する（本家の実コードどおりの式。DeleteAndMoveAll の「空き区間と重なる分だけ引く」式とは非対称であり、本家の挙動としてそのまま採用した）。DeleteAndMoveAll は対象ごとに空き区間リストを他アイテムで分割（本家のローカル関数 GetSpace の3分岐）し、空き区間を後ろから順に全レイヤーへ適用する。GetExpandableDeltaLength は4分岐（開始短縮／終了短縮／開始伸長／終了伸長）を本家どおりに再現し、短縮側は長さとキーフレーム位置から「相対位置1以上を残す」制限、伸長側は同レイヤー隣接アイテムとの間隔（None）または隣接側の切り取り可能量（Stretch、再帰呼び出しで算出）で制限する。本家の再帰呼び出しは `int.MinValue` / `int.MaxValue` を変化量として渡すが、Swift の Int 演算で溢れないよう等価な比較式に置き換えた（意味は同一）。ChangeItemsStart は開始フレーム移動・長さ増減・ContentOffset の換算（定数レートは比率換算、非定数レートは PlaybackRateMap の積分テーブル。分割処理と同一の流儀）・キーフレーム連動・Stretch 時の隣接アイテム調整（重なり分の切り取り／接していた隣の伸長、グループ全員に波及）を実装。ChangeItemsEnd は長さ増減のみで、Stretch 時は隣の開始側を切り取る（ContentOffset は0で丸め）か、重なり分を後ろへ押し出す（ContentOffset は丸めなし加算。本家の非対称性どおり）。GetSnappedDelta は近傍レイヤー（baseLayer 自身は除外）の他アイテムの開始・終了・キーフレーム絶対位置、extraSnapPoints（本家の引数 snapPoints）、現在フレームを候補とし、代表点群との最小距離が frameDistance 以内の最近候補へ吸着する移動量を返す（同点の場合は列挙順の早い方。本家の安定ソート＋First と等価）。

**本家との差分。** 意図的な差分は次の3点のみ。(a) `GetExpandableDeltaLength` は本家では空のアイテム列に対して例外を投げるが、Swift 側の入口 `changeSelectedAndGroupedItemsLength` は選択が空なら何もしない（本家の UI 経路でも選択なしでは呼ばれない前提であり、防御的な内部差分）。(b) 伸長分岐で `NeighborAffectMode.Default` が渡された場合、本家は `NotImplementedException` を投げる。Swift では前提違反として fatalError とした（Default は設定値であり、ViewModel が None / Stretch へ解決してから渡すのが本家の実経路。TimelineItemViewModel.cs で確認）。(c) 本家の `Math.Max(x, -2147483647)` 等の Int32 溢れ対策は Swift の 64bit Int では不要なため省略した。その他の観測された本家の癖（DeleteAndMove の現在フレーム式、ChangeItemsEnd の ContentOffset 丸めの有無の非対称、DeleteAndMoveAll で覆っているアイテム自身も詰めの対象になること）は差分ではなく本家の挙動として再現した。なお本家の隣接削除系（DeleteItemSpace 等）は今回の対象外。

**メモリ・並行性。** すべて値の読み書きのみで新規の所有関係は生じない。DeleteAndMoveAll の空き区間リストは対象ごとに使い捨て。

**検証。** `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（Linux、Swift 6.1.2）で全112件合格（従来87件＋新規25件）、警告・エラーなし。新規テストは DeleteAndMove 5件（同レイヤーのみ／現在フレームの式／複数選択の累積／グループ／選択なし・空）、DeleteAndMoveAll 3件（全レイヤー／完全被覆／部分被覆）、開始側変更7件（短縮・キーフレーム制限・隣接ブロック・フレーム0制限・Stretch 切り取りと伸長・非定数レート）、終了側変更5件（キーフレーム制限・隣接ブロック・Stretch 引き寄せと押し出し・変化量0と選択なし）、スナップ5件（終了位置吸着・同レイヤーと遠方レイヤーの除外・現在フレーム・キーフレーム・extraSnapPoints と ignoreItems）。期待値はすべて本家コードから手計算で導いた。本家実機との比較試験は未実施のため IMPLEMENTED 止まり（環境がない間は到達不可、MAC-0006 と同じ事情）。

**次の担当へ。** MAC-0004 の「次の担当へ」にあった3群は本エントリで解消。残るモデル層の未実装は Character の型付き範囲の拡張と ShapeParameter 既定インスタンスのプロパティ一式（MAC-0003 / 0005 の記録どおり）。

#### MAC-0008 — 隣接削除系・Character 型付き拡張・ShapeParameter 完全化（IMPLEMENTED）

**何を実装したか。** モデル層で残っていた3件を、本家の実コードの意味論どおりに実装した。(1) 空間を詰める削除の一族: `DeleteItemSpace`（指定レイヤーの指定位置の空間）、`DeleteTimelineSpace`（全レイヤー、戻り値は詰めた量）、`DeleteAllLayerSpaces`、`DeleteAllTimelineSpaces`、`DeleteIsolatedRanges`（選択範囲のうち他アイテムに覆われていない孤立区間の削除）。いずれも本家 `Timeline.cs`（570–723行）に実在し、MainModel 経由で MainViewModel のコマンドから実際に呼ばれる経路であることを grep で確認した。(2) `Character` の型付き範囲拡張: 従来は Name / GroupName / Color / Layer の4件のみ型付きで残り82件は追加フィールド保持だったものを、本家 `Character.cs` の全プロパティ（保存対象86件＋set 専用の旧互換2件。宣言順・型・既定値を実コードで確認）に拡張した。(3) `ShapeParameter` の完全化: 従来は $type のみの最小スタンドインだった既定インスタンスを、本家 `RectangleShapeParameter` の継承列（StrokeShapeParameterBase → SizeAndAspectShapeParameterBase → CommonShapeParameterBase）の全プロパティで型付き化した。

**どこを変更したか。** `Sources/YMM4Core/TimelineEditing.swift`（削除系5メソッド＋共通の詰め処理を追加）、`Sources/YMM4Core/Character.swift`（全面改訂。`KeyGesture` / `VoiceDescription` 構造体を同ファイルに追加）、`Sources/YMM4Core/ShapeParameter.swift`（新規。`ShapeParameter` / `RectangleShapeParameter` / `Brush` / `BrushParameter` / `SolidColorBrushParameter` / `LegacyShapeType`）、`Sources/YMM4Core/Items/CompositeItems.swift`（ShapeItem / EffectItem の `shapeParameter` を型付きモデルへ差し替え、旧互換キーの転送を追加）、`Sources/YMM4Core/Enums.swift`（`SizeMode` 追加）、`Sources/YMM4Core/CodecSupport.swift`（旧互換 Animation の読み込みと `Animation.CopyFrom` 相当の写し処理を追加）。テストは `Tests/YMM4CoreTests/TimelineEditingTests.swift`（新規9件）と `Tests/YMM4CoreTests/YmmpCodecTests.swift`（新規6件、既存1件の前提修正）。ローカル作業のみ（push なし）。

**どう実装したか。** (1) DeleteItemSpace は「frame 以前に終わる同レイヤーアイテムの最大終了位置（無ければ 0）」から「frame より後に始まる同レイヤーアイテムの最小開始位置」までの間隔だけ後続を前へずらす。DeleteAll 系はフレーム順ソート（本家 OrderBy と同じく安定）した列へ「被覆済み終了位置 coveredEnd」と「累積詰め量」を持ちながら1パスで詰める共通処理にし、DeleteAllTimelineSpaces では被覆判定がレイヤーをまたぐ本家の挙動（全アイテム通算の最大終了位置）もそのまま再現した。DeleteIsolatedRanges は本家の2つの ImmutableList ビルダー（全体／選択＋グループ）への操作を配列の写しで再現し、境界での分割（splitItemsCore の Remove/Add を両ビルダーへ適用）→孤立部分の除去→「to を上限とする詰め」の順に処理する。最後に Items / SelectedItems の順で代入し（本家の代入順どおり）、Length / MaxLayer を再計算する。(2) Character は書き出しキー順を本家の宣言順に統一し、型は本家の実型に合わせた: Animation は各プロパティの定義値（既定値・範囲）で初期化、色・列挙型は既存の HonkeEnum / Color、ContentOffset は TimeSpanValue、KeyFrames はそのまま保持。プラグインインタフェース型（VoiceParameter / TachieCharacterParameter / TachieDefaultItemParameter / TachieDefaultFaceParameter と音声・映像エフェクト列）は他モデルと同じく PreservedObject の生保持とし、二重保持にならないよう追加フィールドからは除外した。Voice は VoiceDescription の実フィールド（API / Arg のみが保存対象、話者オブジェクトは JsonIgnore）で構造体化した。TachieType は System.Type への参照であり、他モデルの Type プロパティ（ShapeType2 等）と同じく型名文字列で保持した（未設定時は null）。AdditionalForegroundTemplateName / AdditionalBackgroundTemplateName は本家で初期値が null のため Optional で保持する。旧互換の LineHeight / LetterSpacing は TextItem と同じく set 専用として読み込み時に LineHeight2 / LetterSpacing2 の先頭値へ転送し、書き出さない。(3) RectangleShapeParameter の既定値は実コードどおり: StrokeThickness は 4000.0（StrokeShapeParameterBase の初期値）、Size / Width / Height は 100、AspectRate / Round は 0、SizeMode は SizeAspect。Brush は既定プラグインが `[PrimaryPlugin]` の SolidColorBrushPlugin であること、そのパラメータが SolidColorBrushParameter（Color = Colors.White）であることを PluginLoader の解決規則（PrimaryPlugin 属性優先）と実クラスで確認した。ShapeType2 の既定値も `[PrimaryPlugin]` の QuadrilateralShapePlugin の型名に合わせた（従来は空文字列）。未知の $type のパラメータは従来どおり PreservedObject で生保持する。ShapeItem / EffectItem の旧互換キー（ShapeItem: Size / AspectRate / StrokeThickness / Stroke / ShapeType、EffectItem: ShapeType のみ実在）も読み込み時に転送するようになった: Size 等は範囲 (int.MinValue, int.MaxValue) で読み込んでパラメータ側の Animation へ CopyFrom 相当（値列・種類・Span・ベジェ）で写し、Stroke はブラシが単色の場合だけその色へ、ShapeType は `ShapeTypeEx.ToPluginType` の対応表で現行プラグイン型名へ変換する。パラメータが型付き（rectangle）でない場合に Size 等が来たときは、本家ではキャスト例外で読み込み自体が失敗するが、Swift では追加フィールドに保持して読み込みを継続する（データ保全優先の意図的な緩和）。また本家では ShapeParameter の setter が null を無視するため、null が来ても既定インスタンスを保持する挙動に合わせた。パラメータ内の Animation 群は本家 GetAnimatables と同様にアイテムの forEachAnimation へ組み込んだ（キーフレーム連動・分割連動の対象になる）。

**型付き化を見送った項目と理由。** Character: VoiceParameter / TachieCharacterParameter / TachieDefaultItemParameter / TachieDefaultFaceParameter はプラグインインタフェース型で実型が開かれているため、モデル全体の方針どおり PreservedObject の生保持（$type 移行は適用される）。AudioEffects / JimakuVideoEffects / TachieItemVideoEffects / TachieDefaultFaceEffects も同じ理由で PreservedObject の列。KeyGesture は WPF の Key / ModifierKeys 列挙型名がファイル形式の一部であるため、Swift 側に列挙型を作らず名前文字列の構造体とした（未知のキー名もそのまま往復する）。ShapeParameter: RectangleShapeParameter 以外の組み込み図形パラメータ（Circle / Triangle 等）は固有プロパティの棚卸しが未了のため生保持のまま（既定インスタンスの完全化が本件の範囲）。Brush の Parameter も SolidColorBrushParameter 以外は生保持。

**本家との差分。** 意図的な差分は次のとおり。(a) DeleteItemSpace / DeleteTimelineSpace / DeleteIsolatedRanges は前提条件を満たさない呼び出し（後続なし・対象なし・選択なし）で本家は LINQ の例外になるが、Swift では何もしない／0 を返す（呼び出し側の Can 判定が前提条件を保証する経路は本家と同じ。MAC-0007 の入口 no-op と同じ判断）。(b) 旧互換キー Size 等＋型付きでないパラメータの組み合わせは本家では読み込み失敗になるが、Swift では追加フィールド保持で継続する（上記）。(c) Brush.Parameter が null／非オブジェクトの場合、本家は null を保持するが、Swift では既定（単色）へ倒す（実ファイルでは到達しない前提）。その他の本家の癖（DeleteAllTimelineSpaces のレイヤーをまたぐ被覆判定、DeleteIsolatedRanges の詰め上限が to であること、StrokeThickness の既定 4000、MouseSmooth の綴りと既定 4、IsDevidedPerCharacter の綴り）は差分ではなく再現した。

**メモリ・並行性。** 削除系は参照型アイテムの Frame 書き換えのみで新規の所有関係は生じない。DeleteIsolatedRanges のビルダー配列は操作中だけの使い捨て。Character / ShapeParameter は値の保持のみ。

**検証。** `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（Linux、Swift 6.1.2、.build を消して再実行）で全127件合格（従来112件＋新規15件）、警告・エラーなし。新規テストの内訳: 削除系9件（DeleteItemSpace の基本・全アイテムより前・後続なし、DeleteTimelineSpace の戻り値と無対象、DeleteAllLayerSpaces、DeleteAllTimelineSpaces のレイヤーまたぎ、DeleteIsolatedRanges の全削除・部分被覆・選択なし）、Character 2件（型付き全群の往復固定点＋追加フィールドに未知キーだけが残ること、本家形式 JSON＋旧互換キーの転送と書き戻し不在）、ShapeParameter 4件（既定インスタンスの往復固定点と既定値、本家形式 JSON の型付き読み込み、旧互換キーの転送と書き戻し不在、未知 $type の生保持）。期待値はすべて本家コードから手計算で導いた。既存テスト testRoundTripFixedPoint は、追加フィールド保持の例として使っていた "Voice" が型付き化されたため、未知キー "SomeFutureProperty" へ差し替えた（意図は不変）。本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**未解決事項。** (a) KeyGesture の保存形式が列挙型名の文字列であることは解析ノート（MODEL-INFRA-FACTS）とコンバータの読み取り側コードで確認したが、本家実機のファイルでの実測は未実施（環境がない間は到達不可）。数値形式で書かれた場合もリテラル保持で往復は壊れないようにはしてある。(b) RectangleShapeParameter 以外の組み込み図形パラメータの固有プロパティは未棚卸し（生保持で往復は保たれる）。(c) Character の SetFPS が行うアニメーション文脈の伝播（VoiceItemLength / TachieItemLength と FPS の注入）は、アイテム側の文脈注入の仕組みに Character が組み込まれていないため未実装（保存形式には影響しない）。

**次の担当へ。** モデル層の未実装は本エントリで解消した（Character の型付き範囲、ShapeParameter 既定インスタンス、隣接削除系）。残る主要な未着手は描画層・音声・書き出し・UI。本人の Mac でのデバッグ用アプリ初回ビルド確認と、実物 .ymmp での読み込み診断・往復チェックは引き続き本人の報告待ち。

#### MAC-0009 — 描画層の土台（GPU に触れない合成ロジック）（IMPLEMENTED）

**何を実装したか。** 描画層のうち GPU に触れない合成ロジック部分を、技術仕様 第1章（画像参照契約 IMG-01〜03・IMG-05）・第3章（ISource / ISourceOutput）・第5章（TimelineSource）の照合済み契約に基づき、Foundation のみで実装した。内容は: (1) 抽象画像契約（ピクセル実体を持たない不透明な画像参照型）。(2) Source / SourceOutput のプロトコル（Controllers / Outputs / Update の3メンバ＋破棄。Draw メソッドは存在しない）。(3) DrawDescription 値型。(4) アイテム選択（全体用・グループ用・トランジション用）。(5) 描画順序（3キー）と平面分割のラン判定・セグメント構築（BSP 本体は差し替え点に留め、逐次描画へフォールバック）。

**どこを変更したか。** 新規 `Sources/YMM4Core/Rendering/` に7ファイル: `Geometry.swift`（Vector2 / Vector3 / Matrix4x4 / RectF）、`ImageReference.swift`、`DrawDescription.swift`（DrawDescription、InterpolationMode、BillboardMode、VideoController / VideoEffectController / ControllerPoint と付随列挙）、`SourceDescriptions.swift`（TimelineSourceDescription / TimelineItemSourceDescription / EffectDescription、FramePosition、PixelSize、TimelineSourceUsage、SceneInfo）、`Source.swift`（Source / SourceOutput / DrawingEffectProcessor / FrameBufferSource プロトコル、StandardSourceOutput）、`ItemPickers.swift`（ItemPicker、CompositeItemPicker、TransitionItemPicker、FaceItem）、`DrawOrdering.swift`（OrderedDrawResource、DrawOrdering、DrawSegment、PlaneSplitOrdering / NullPlaneSplitOrdering、DrawSegmentBuilder）。テストは新規 `Tests/YMM4CoreTests/RenderingTests.swift`（31件）。ローカル作業のみ（push なし）。

**どう実装したか。** (1) `ImageReference` はラベルだけを持つ final class とし、第1章の契約（スナップショットではなくグラフ参照、有効範囲は生成した Update から次の Update の開始まで、参照の同一性≠内容の同一性、SetInput は所有権を移さず ClearInput は入力を破棄しない）を型の文書として明記した。実体の生成・解放は GPU 実行層の責務として切り離した。(2) Source プロトコルは本家 ISource の形そのまま（IDisposable は Swift の dispose() メソッドで表す）。SourceOutput は Output（画像参照）＋ DrawingEffect（DrawingEffectProcessor プロトコル。IVideoEffectProcessor のうち入力設定と DrawDescription 確定の境界だけを切り出したもの）＋ DrawingOffset / Center / TimeOffset / DurationOffset（TimeSpanValue）。具象の StandardSourceOutput は本家 SourceOutput と同じく生成時に全プロパティを固定し、所有／借用は dontDispose の反転（ownsDrawingEffect）で切り替える。Dispose の順序も本家どおり ClearInput → 破棄。(3) DrawDescription は本家レコードの全主要メンバ（Draw / CenterPoint / Zoom / Rotation / Camera / ZoomInterpolationMode / Opacity / Invert / Controllers / PerspectiveDistance / Billboard）を値型で保持し、既定値は本家 CreateEmptyDrawDescription と一致させた（位置 0、拡縮 1、回転 0、単位カメラ、不透明度 0、補間 Cubic）。(4) 説明レコードは本家 TimelineSourceDescription / TimelineItemSourceDescription / EffectDescription を再現した。本家は継承だが Swift では基底を保持する合成とし、RenderScale の引き継ぎ（親がアイテム説明なら継承）と ComposeRenderScale（親・子とも不正値は 1 に倒し、積が有限でないか float 最大値を超えれば 1）を実コードどおりに実装した。FrameTime は既存の換算列挙型と分離し、値保持用の FramePosition（frame + fps、time は tick 粒度換算）とした。(5) CompositeItemPicker は本家 CompositeItemPicker の実コードどおり: 全体用は「フレームを含む・非表示でない・レイヤー表示中」を候補とし、合成グループの子を除外し、最大レイヤーの TransitionItem（子として除外されるものは数えない）より下を除外する。グループ用はフレームをグループ末尾でクランプし、レイヤー範囲と IsGroupOnly のグループ番号一致で子を選ぶ。TransitionItemPicker は isBefore でフレームをトランジション開始−1 に固定し、トランジションより下のレイヤーのみを対象とし、囲む合成グループがあればその子に限定し、親以外の合成グループの子を除外する。PickFaceItems は IFaceItem の実装範囲（TachieFaceItem / VoiceItem のみ、本家どおり）を FaceItem マーカーで表した。(6) 描画順序は本家 GetOrderedTimelineResources の3段キー（IsAlwaysOnTop → ZIndex → Layer、全て昇順、同キーは入力順を保持する安定ソート）。ZIndex は本家 EffectedItemSource.GetZIndex の合成行列（中心まわりの反転スケール × 回転Z × 回転Y（符号反転）× 回転X（符号反転）× 平行移動 × カメラ × 透視 M34=−0.001）を Matrix4x4（System.Numerics 互換の行優先・行ベクトル規約）で再現し、MatrixHelper.Transform と同じく w で割って原点の Z を取り、出力群の最大値（空なら 0）とした。平面分割の四隅は本家 GetPlaneSplitQuad の nil 条件を全て再現した純粋関数とした（出力0件、変換なし・不一致、境界なし、空の境界、w ≤ 0.001 または非有限、Z > 999、IsValidQuad（Newell 法線の長さ < 0.01））。入力は次段が DrawingEffect から供給する前提で PlaneSplitOutputGeometry（ワールド変換＋入力境界）として切り出した。(7) DrawSegmentBuilder は本家 CreateDrawSegments の分岐をそのまま再現した: ラン参加条件は ZOrder 有効かつ FrameBuffer でないこと、ランは IsAlwaysOnTop が先頭と同一の間だけ伸び、2件未満は単独、四隅が計算できない資源で小区間に切り、小区間は「2件以上かつ順序付けが必要な組があり Sort が断片列を返した場合」のみ平面分割セグメントになる。BSP 本体は PlaneSplitOrdering プロトコルの差し替え点とし、既定の NullPlaneSplitOrdering（順序付け不要・Sort は常に nil）で全ランが逐次描画へフォールバックする。本家でも Sort が nil を返せば逐次描画になるため、フォールバック先の意味論は一致する。

**本家との差分。** 意図的な差分は次のとおり。(a) 幾何値は本家 float（32bit）ではなく Double で保持する（モデル層の他要素と統一）。Z の同値境界など 32bit 境界ケースで順序が変わりうる内部差分。(b) 説明レコードは継承でなく合成で表した（外部から見える値は同じ）。(c) DrawDescription の CustomValues（型と名前をキーにした異種辞書）は Swift の値型に等価な表現がないため未収録。消費者が現れた時点で再評価する。(d) ControllerPoint のドラッグ等の対話コールバックは編集 UI 層の関心として未収録（位置・形状・選択状態のみ）。(e) ImageReference は実体を持たないトークンのため破棄操作を持たない。本家 SourceOutput は画像も DisposeCollector で破棄するが、こちらで StandardSourceOutput.dispose が破棄するのは所有する DrawingEffect のみ（実体の解放は GPU 実行層の責務）。(f) PickItems の戻り値は IEnumerable ではなく配列（判定が純粋で副作用を持たない点は同じ）。(g) PlaneSplitBsp 本体（RequiresBspOrdering の共面・画面境界判定、Sort、断片上限 256、断片画像生成）は未実装で、既定では平面分割セグメントは生成されない（分岐構造とフォールバックは本家と一致）。

**メモリ・並行性。** 幾何・説明・順序付けは値型で、選定・順序・セグメント構築は共有状態を持たない純粋計算。ImageReference と各プロトコルの実装は参照型で、所有者は第1章・第3章の契約どおり（SourceOutput の所有者は生成した Source、消費者は破棄しない）。同一 Source インスタンスへの並行 Update の安全性は本家でも未確定（第3章）のため、契約には含めていない。

**検証。** `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（Linux、Swift 6.1.2、.build を消したクリーンビルドを含む）で全160件合格（従来129件＋新規31件）、警告・エラーなし。新規テストの内訳: Source 契約6件（偽 Source への説明の受け渡し、StandardSourceOutput の所有／借用別の破棄、RenderScale の引き継ぎと ComposeRenderScale の各分岐、FramePosition の時間換算）、アイテム選択10件（基本フィルタ、合成グループの子除外、非合成グループでは除外しない、グループ用の末尾クランプと範囲、IsGroupOnly の番号一致、トランジション規則、グループ子トランジションを基準にしないこと、顔アイテム選定、TransitionItemPicker の前フレーム固定と親合成制限）、描画順序・セグメント15件（ZIndex の平行移動＋透視除算＝100/0.9、最大値と空=0、回転・反転が原点 Z に影響しないこと、カメラ適用、四隅の恒等変換と境界統合、nil 条件7分岐、3キー順序、非参加資源の単独化、Null 順序付けでの逐次フォールバック、偽順序付けでの平面分割生成・Sort nil フォールバック・要否 false での Sort 未呼び出し、四隅 nil でのラン分割、IsAlwaysOnTop 変化でのラン分断）。期待値はすべて本家コードから手計算で導いた。本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**未解決事項。** (a) Update 前の Outputs の状態は本家でも実装依存で統一されていない（第3章 §3.4）。契約として固定しない。(b) 失敗した Update の後に旧 Output をどこまで維持できるかは本家でも未確定。(c) BSP 本体の幾何条件の全容（特に Sort が null を返す条件）は本家解析でも未確定（第5章）。実装時に別途扱う。(d) DrawDescription.CustomValues と VideoController の対話コールバックは、モーショントラッキング等の消費者が現れた時点で要否を判断する。(e) SceneInfo は識別子のみの契約であり、シーン解決（内部 TimelineSource の生成・入れ子上限）は次段。

**次の担当へ。** 残る描画系の仕事は次段: GPU 実行器（IGraphicsDevices 相当と Context、CommandList の記録・合成実行、第1章・第2章の契約）、EffectedItemSource 相当（エフェクト連鎖の実行と DrawDescription の確定、ParentEffects の再構築、FrameBuffer 境界の合成フェーズ）、TimelineSource 相当（資源管理・先読み・合成の統合）、テキスト描画、メディア読み込み（デコーダ）、PlaneSplitBsp 本体。描画バックエンド（Metal 等）の選定は未確定事項であり、採用前に本人の承認と最小限の実証が要る。

#### MAC-0010 — 合成の実行部（EffectedItemSource / TimelineSource 相当）（IMPLEMENTED）

**何を実装したか。** 描画層の次段として、合成の実行部を GPU に触れない抽象描画先の形で Foundation のみで実装した。技術仕様 第4章（EffectedItemSource）・第5章（TimelineSource）の照合済み契約に基づく。内容は: (1) アイテムごとに Source の生出力を、エフェクト連鎖＋親グループのエフェクト＋アイテム変換を通した1つの出力へ変換する実行部（本家 EffectedItemSource / EffectedSourceOutput）。(2) シーンとアイテム群を管理し、Update（時刻と用途）で1フレーム分の合成結果を返す実行部（本家 TimelineSource）と、グループ階層の解決（本家 TimelineGroupResolver）。(3) 描画先の抽象（本家 ID2D1DeviceContext + ID2D1CommandList の組の置換）。

**どこを変更したか。** 新規 `Sources/YMM4Core/Rendering/EffectedItemSource.swift`（VideoEffectProcessor / VideoEffectDefinition / EffectPair / EffectPairProvider / EmptyEffectPairProvider、RenderTarget / RenderTargetFactory、AlphaMaskEffect / AlphaMaskEffectFactory、PlaneSplitGeometryProviding、EffectedOutput、EffectedItemSource、EffectedItemError）と `Sources/YMM4Core/Rendering/TimelineSource.swift`（TimelineScene、TachieSource、TimelineGroupResolver、TimelineComposer、TimelineCompositionError）。MAC-0009 側の最小変更として `Sources/YMM4Core/Rendering/Source.swift` の `DrawingEffectProcessor.update` と `Source.update` を throws 化した（失敗契約を型で表すため。非 throws の既存実装はそのまま適合する）。テストは新規 `Tests/YMM4CoreTests/CompositionTests.swift`（27件）と、RenderingTests の呼び出し側1件の追随。ローカル作業のみ（push なし）。

**どう実装したか。** (1) EffectedOutput（本家 EffectedSourceOutput）: 連鎖の再利用は位置（index）基準で、差し替え条件はエフェクト定義のインスタンス同一性。差し替え時は新しい処理器の SetInput → Update が完了してから旧処理器を ClearInput → Dispose する。再利用時は保持する入力参照と現在の入力が同一なら SetInput を再発行しないが Update は常に行う。縮小は末尾からのみ。DrawDescription は各段の Update の戻り値で連鎖的に書き換わる。初期 DrawDescription は本家 CreateDrawDescriotion どおり（TimeOffset / DurationOffset をフレーム換算して位置・長さへ加算、フェード係数は min(1, …) 同士の小さい方で下限クランプなし、Opacity は評価値/100 × フェード係数）。エフェクト説明は本家 CreateEffectDescription どおり（基底説明から作り直し、アイテム内位置 = タイムライン位置 − 時間基準アイテムの開始 + オフセット）。DrawingEffect の失敗だけを EffectedItemError（アイテム型名・エフェクト数・グラフ表現）で包み、連鎖途中の失敗は包まず伝播する。CameraFinalizer は本家内部が未確定のため差し替え点（既定は恒等）とした。(2) EffectedItemSource: Source.Update → UpdateEffects の順。出力数の調整は末尾だけ（超過は破棄、不足は生成）。連鎖 = 供給元の自前エフェクト ++ parentEffects を IsEnabled で濾したもの。全出力の更新が完了した直後に旧合成結果を破棄し、新しい描画先へ合成する（出力0件でも透明な 1x1 矩形で有効な出力を返す）。クリッピング時は AlphaMaskEffect（差し替え点）へ合成結果を入力0として渡し、その出力を最終出力とする。DrawDescription は先頭出力のもの、無ければ空。(3) TimelineComposer（本家 TimelineSource）: Update の固定順序 = キャッシュ設定変更チェック（差し替え点の呼び出しのみ）→ UpdateResources → 並列更新（FrameBuffer 以外。失敗はアイテム情報 Type / Label / Frame / Length / Layer / Group つきの TimelineCompositionError で包む）→ 旧描画先と FrameBuffer 蓄積の解放 → MAC-0009 の順序付け・セグメント構築 → 描画先へ合成 → キャッシュクリア（差し替え点）。背景色は Clear 色ではなく、透明クリアの後に不透明度があれば中心矩形として描く。何も描かれなかった場合は空矩形の目印を描く。クリッピング対象は描画に先立ち「直前の画像」（無ければ Flood 代替トークン）をマスクとして設定され、自身は直前の画像として数えない。FrameBuffer 境界では現在の描画先を閉じて所有権を蓄積側へ移し、Input / FrameSize を設定してから実行部を更新（アイテム内位置の 0 クランプと長さの max(1, …) は行わない。失敗は包まない）、新しい描画先で合成を続け、ClearBackground が false なら閉じた描画先を引き継ぎ描画する。蓄積は次回 Update の合成開始時点で解放される。UpdateResources は範囲外アイテムと非合成グループの実行部をその場で破棄し、不足分を生成し、親エフェクトを毎回再構築する（全消去 → 立ち絵の顔・声解決: 同じキャラクターの顔アイテムをレイヤー降順に集め、最初の VoiceItem を ActiveVoice、先頭を顔エフェクトの時間基準にする → グループの親エフェクト: TimelineGroupResolver の親列の順に、子位置・子総数を添えて積む）。(4) TimelineGroupResolver: 親候補は非表示でなくレイヤー表示中の GroupItem のみ。直接の親は レイヤー範囲＋IsGroupOnly のグループ番号一致で判定し、祖先は再帰収集→重複除去→レイヤー降順→合成グループで打ち切り（合成グループ自身は含まない）。子の列挙は映像アイテム（合成グループ自身を除く）のうち親列に対象グループを含むもの、レイヤー昇順。

**本家との差分。** 意図的な差分・未実装は次のとおり。(a) 失敗意味論のうち「合成ステップ（旧描画先の破棄後）の失敗で旧 Output が破棄済みを指しうる」は、タイミングの構造（破棄位置）だけを再現した。この層の描画先操作は例外を投げないため、実際に失敗するのは GPU 実行層の段である。(b) DrawingEffect が nil の出力では、本家は例外になる経路だが、MAC-0009 が内部の一時出力で DrawingEffect を任意としたため、変形なしで通す。(c) 並列更新は本家 Parallel.ForEach だが、こちらは選定順の逐次実行（並列化は順序を規定しない最適化であり、例外の集約形式は第5章でも未確定）。(d) 先読み（PrefetchResources）は未実装。合成結果に影響しない性能最適化であり、呼び出し位置だけを残した。先読み済み資源の引き継ぎも無い。(e) キャッシュ（CacheProvider）は未実装。設定変更チェックとクリアは差し替え点の呼び出し位置のみ再現した。(f) TimelineItemRects の再構築は未実装（画像境界の問い合わせ＝GPU 実行層が必要）。(g) 描画先のターゲット設定／解除はターゲット自身へ畳み込んだため、本家に2通りある終了順序（EffectedItemSource 側と FrameBuffer 境界）はどちらも endDraw → close として観測される。(h) DiagnoseGraphNodes の境界問い合わせ（GetImageLocalBounds）と FAIL 判定、問題エフェクトのパラメータ JSON 添付は行わず、診断文字列はノード名と出力ラベルで表す。(i) 実行部の対象は VisualItem のみ。VoiceItem / TransitionItem は本家では IVideoItem として資源を持つが、モデル層の VoiceItem は視覚プロパティを持たない（BaseItem 系譜）ため資源を持たない。関連して、MAC-0009 の ItemPicker が使う VideoItemCandidate の範囲（VisualItem + TachieFaceItem）は本家 IVideoItem の実装範囲（VisualItem 系譜 + VoiceItem + TransitionItem。TachieFaceItem は含まない）と異なることを逆コンパイル済みコードで確認した。選定側の不整合として未解決に残す（本件では選定側を変更しない）。（この不整合は MAC-0011 で解消した。）(j) アルファマスクの生成が差し替え点に留まる構成（factory 未指定）では、クリッピング対象の出力はマスク未適用になる。(k) ズーム補間方式は本家では設定（YMMSettings）から読むが、設定層が未実装のため差し替え点（既定 .linear）とした。CreateDrawDescription の初期値も同じ差し替え点を使う。

**メモリ・並行性。** 所有関係: TimelineComposer が EffectedItemSource 群と現在の描画先と FrameBuffer 蓄積を所有し、EffectedItemSource が Source・描画先・EffectedOutput 群を所有し、EffectedOutput が処理器群を所有する。DrawingEffect と入力画像は借用で破棄しない。親エフェクトの組（EffectPair）は値の借用データであり、所有は移らない。破棄順序は本家の DisposeCollector の逆順を近似する（この層では観測可能なのは各偽実装の記録のみ）。並行性は持たない（逐次実行）。

**検証。** `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（Linux、Swift 6.1.2、.build を消したクリーンビルドを含む）で全187件合格（従来160件＋新規27件）、警告・エラーなし。新規テストの内訳: EffectedItemSource 15件（再利用時の SetInput 省略、差し替え順序＝新側の Update 完了後に旧側を破棄、DrawDescription の連鎖書き換え、入力変化時の SetInput 再発行、末尾縮小、無効エフェクトの除外、0出力時の有効な出力、Source 失敗・連鎖失敗での旧 Output 保持、DrawingEffect 失敗の包み、applyItemTransform=false の素通し、フェードと不透明度の評価、クリッピングのマスク適用、グループ位置と時間基準の説明、TimeOffset の換算）、TimelineGroupResolver 3件（親列の順序と合成グループでの打ち切り、IsGroupOnly の一致と非表示グループ、レイヤー表示フィルタ）、TimelineComposer 9件（範囲外アイテムの破棄、親エフェクトの再構築、自前→グループの連鎖順序、描画順序どおりの描画先への到達、背景矩形と無描画の目印、アイテム失敗の包みと旧出力保持、FrameBuffer 境界の所有権移転と引き継ぎ描画・次回解放、立ち絵の顔・声解決、Dispose）。期待値はすべて本家コードから手計算で導いた。本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**未解決事項。** (a) CameraFinalizer の内部（本家未確定）。(b) 診断文字列の境界問い合わせ・パラメータ JSON（GPU 実行層・直列化層の段）。(c) 先読み・キャッシュ・TimelineItemRects（上記 (d) (e) (f)）。(d) MAC-0009 の VideoItemCandidate と本家 IVideoItem の範囲の不整合（上記 (i)）。モデル層の VoiceItem が視覚プロパティを持たない件と合わせて、選定・モデル側の照合が別途要る。（MAC-0011 で解消。）(e) 同一 Source への並行 Update の安全性、失敗した Update 後の旧 Output の維持範囲は第3章・第4章でも未確定のまま。

**次の担当へ。** 残る描画系の仕事は次段: GPU 実行器（IGraphicsDevices 相当と Context、CommandList の実記録・合成実行、第1章・第2章の契約。描画先・Source・処理器の実物はここで生まれる）、個別エフェクトの実装（VideoEffectDefinition への橋渡し。モデル層の PreservedObject から定義インスタンスを供給する EffectPairProvider の実物を含む）、基本 Source（画像・図形・テキスト）の実装、テキスト描画、メディア読み込み（デコーダ）、PlaneSplitBsp 本体、音声、書き出し、UI。先読み・キャッシュ・TimelineItemRects は GPU 実行器の段で合わせて扱うのが自然。

#### MAC-0011 — 映像アイテム範囲の是正（VoiceItem / TransitionItem の IVideoItem 保持と候補範囲の統一）（IMPLEMENTED）

**何を実装したか。** MAC-0010 の照合で見つかった不整合の是正。本家 IVideoItem の実装範囲は「VisualItem 系譜 + VoiceItem + TransitionItem」（TachieFaceItem は IFaceItem のみで含まない）であるのに対し、MAC-0009/0010 時点では (a) モデル層の VoiceItem は映像プロパティを誤った保存キーで保持しており本家のキーは追加フィールドへ落ち、TransitionItem は読み込み時に値を捨てていて、(b) 描画層の候補範囲・実行部の対象が VisualItem + TachieFaceItem（MAC-0009 の VideoItemCandidate）／VisualItem のみ（MAC-0010 の実行部）で本家とずれていた。本件でモデル層に映像プロパティ一式を持たせ、描画層の範囲を本家どおりに統一した。MAC-0010 の差分 (i)・未解決 (d) と HANDOFF の不整合メモは本件で解消。

**どこを変更したか。** ローカル作業のみ（push なし）。`Sources/YMM4Core/Items/BaseItem.swift`: `VideoItemProperties` プロトコル（本家 IVideoItem の映像プロパティ一式。クラス制約のみ）を追加し、VisualItem が適合。`Sources/YMM4Core/Items/TextItems.swift`: VoiceItem の字幕側プロパティを jimakuX 等から x / y / z / opacity / zoom / rotation / fadeIn / fadeOut / blend / isInverted / isClippingWithObjectAbove / isAlwaysOnTop / isZOrderEnabled / videoEffects へ改名して一式を保持し、保存キーを本家の [JsonProperty] 指定どおりに是正。`Sources/YMM4Core/Items/CompositeItems.swift`: TransitionItem に映像プロパティ一式を型付きで保持（従来は保存時に既定値を書き、読み込み時は捨てていた）。`Sources/YMM4Core/Rendering/EffectedItemSource.swift`: EffectedOutput / EffectedItemSource の対象型と EffectPairProvider.ownEffectPairs の引数を `BaseItem & VideoItemProperties` へ変更。`Sources/YMM4Core/Rendering/TimelineSource.swift`: TimelineComposer の sourceProvider と資源対象を同範囲へ変更し、isVideoItemEquivalent は適合判定そのものにした。`Sources/YMM4Core/Rendering/DrawOrdering.swift`: OrderedDrawResource の便利初期化子の引数を同範囲へ変更（引数ラベル visualItem → videoItem）。テストは YmmpCodecTests に4件、CompositionTests に3件を追加し、FakeEffectProvider / registerSource のシグネチャを追随させた。

**どう実装したか。** (1) VoiceItem: 本家の保持実体は Jimaku* プロパティであり、保存キーは [JsonProperty] 指定で JimakuX → "Y"、JimakuY → "X"（**X と Y が入れ替わる**）、JimakuZ → "Z"、JimakuOpacity → "Opacity"、JimakuZoom → "Zoom"、JimakuRotation → "Rotation"、JimakuBlend → "Blend"、JimakuIsInverted → "IsInverted"、JimakuIsClippingWithObjectAbove → "IsClippingWithObjectAbove"、JimakuIsAlwaysOnTop → "IsAlwaysOnTop"、JimakuIsZOrderEnabled → "IsZOrderEnabled" となり、JimakuFadeIn / JimakuFadeOut と JimakuVideoEffects だけが Jimaku* の名前のまま保存される（逆コンパイル済み VoiceItem.cs で実測）。従来の ymm4mac は "JimakuX" 等のキーで読み書きしていたため、本家ファイルでは該当キーが追加フィールドへ落ち、ymm4mac が書いたファイルは本家で字幕の位置等が読めない状態だった。是正後は型付きプロパティが本家のキーで往復し、追加フィールドに残らない。既定値は本家どおり（X / Y / Z = 0（範囲 ±100000）、Opacity = 100（0..100）、Zoom = 100（0..100000）、Rotation = 0、FadeIn / FadeOut = 0、Blend = Normal（Blend 列挙の先頭値 0。本家の VisualItem の未初期化フィールドと一致）、各フラグ false、VideoEffects 空）。(2) TransitionItem: 本家では一式が式本体の get 専用プロパティ（アクセスのたびに既定の新規値を返す。X / Y / Z = Animation(0, ±100000)、Opacity = Animation(100, 0..100)、Zoom = Animation(100, 0..100000)、Rotation = Animation(0, ±100000)、FadeIn / FadeOut = 0、Blend = Normal、フラグ false、VideoEffects は空を返し setter は何もしない）で、保存はされるが読み込み結果は保持されない。ここでは既定値を初期値として型付き保持し、読み込んだ値を往復させ、アニメーション文脈の伝播（forEachAnimation）にも参加させた（差分は後述）。(3) 描画層: 実行部の対象型を合成型 `BaseItem & VideoItemProperties` に統一し、TimelineComposer はこの範囲のアイテムに資源を生成する（非合成グループの除外は従来どおり）。TachieFaceItem は適合しないため資源を持たない。PickFaceItems の対象（TachieFaceItem / VoiceItem が FaceItem である点）は変更していない。

**本家との差分。** 意図的な差分は次のとおり。(a) TransitionItem の映像プロパティ: 本家は読み込み値を保持しない（get 専用で常に既定値）が、こちらは型付きで保持し往復させる。データ保全（読み込み→保存で値を落とさない）を優先する判断。本家が書き出すファイルでは常に既定値のため、実ファイルでは差は現れない。同様に本家ではこの一式は GetAnimatables に含まれず文脈伝播の対象外だが、こちらは forEachAnimation に参加させる。(b) VoiceItem の IVideoItem 解決: 本家は JimakuVisibility とキャラクターによる解決（カスタム以外ではキャラクター側の X / Y / … を優先し、無ければ自前値。FadeIn / FadeOut はキャラクターの JimakuFadeIn / JimakuFadeOut。VideoEffects は表示方法ごとに切替わり、Hidden では空）を行うが、ここでは解決を行わず自前の保持値をそのまま公開する。解決は字幕 Source（本家 JimakuSource）実装の段で扱う。(c) EffectItem の Zoom / IsInverted（本家で get 専用・[JsonIgnore] のため読み込み時に捨てる従来の扱い）は本件の対象外で変更していない。

**メモリ・並行性。** 変更なし（参照型モデルへの保持追加と型の付け替えのみ）。所有関係は従来どおり TimelineComposer → EffectedItemSource → Source / EffectedOutput。

**検証。** `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（Linux、Swift 6.1.2）で全194件合格（従来187件＋新規7件）、警告・エラーなし。新規テストの内訳: YmmpCodecTests 4件（VoiceItem の型付き往復と、raw JSON 上のキー配置＝"X" キーに Y の値・"Y" キーに X の値が入り "JimakuX" 等のキーが存在しないこと、追加フィールドに映像キーが残らないこと。本家形式キーのリテラル読み込みで型付き配置と追加フィールド空を確認。TransitionItem の型付き往復と追加フィールド。TransitionItem の既定値）、CompositionTests 3件（isVideoItemEquivalent の範囲、PickFaceItems の対象が不変であること、TimelineComposer の資源対象＝VoiceItem / TransitionItem は資源を持って更新・範囲外で破棄され、TachieFaceItem には Source が要求されないこと）。既存の実ファイル検証（kiminihare 系2件）は VoiceItem / TransitionItem を含まない（アイテム種別は Text / Video / Image / Audio / Shape のみ）ため影響しない。本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**未解決事項。** (a) VoiceItem の JimakuVisibility / キャラクター解決（上記 (b)）。字幕 Source 実装の段で、解決をアイテム側に置くか Source 側に置くかを含めて決める。(b) VoiceItem の X / Y 入れ替わりは逆コンパイル済みコードの [JsonProperty] 指定が唯一の根拠であり、VoiceItem を含む実 .ymmp での裏取りは未実施。実ファイルが得られたら再確認する。(c) 旧形式キー（"JimakuX" 等、MAC-0010 以前の ymm4mac が書いた形式）で保存されたファイルでは、該当キーは追加フィールドとして保持される（値は失われないが型付きにはならない）。デバッグ用サンプル `Apps/DebugApp/Sample/sample.ymmp` がこの形式を含んでいた（MAC-0011 追補で現行コーデックにより再生成し解消）。

**次の担当へ。** 描画系の次段は MAC-0010 の「次の担当へ」のとおり（GPU 実行器、個別エフェクト、基本 Source、テキスト描画、メディア読み込み、BSP 本体）。基本 Source の段では VoiceItem の字幕 Source（本家 JimakuSource）が対象に入るため、上記未解決 (a) の解決の置き場をそこで決めること。

**MAC-0011 追補（2026-11-17）— デバッグ用サンプル sample.ymmp の再生成。** 旧サンプルは MAC-0011 以前のコーデックで生成されており、VoiceItem の字幕プロパティが旧形式キー（"JimakuX" 等）で書かれていた。旧ファイルの読み直し→再保存では旧キーが追加フィールドに残るだけで変換できないため、一時テストでプロジェクトをコード構築し、現行 `YmmpCodec` でエンコードし直して `Apps/DebugApp/Sample/sample.ymmp` を上書きした（未知 $type アイテムはエンコード後の JSON への直接注入。生成・検証用の一時テストは検証後に削除済み）。構成は従来の役割を引き継ぎつつ拡充した: キャラクター2件（テストキャラ／サブキャラ。テストキャラには未知キー SomeFutureProperty を追加フィールドとして保持）、タイムライン2件（メイン 640×360／サブ 1920×1080、切替確認用）、メインのアイテムは型付き8件（Text／Image／Video／Audio／Voice／Shape／Transition／Group）＋未知 $type（FutureItem）1件、サブは Text 1件。VoiceItem の字幕プロパティには既定値と異なる値（x = 11、y = 22、FadeIn = 0.5、FadeOut = 0.25、JimakuVisibility = Custom、JimakuVideoEffects にプラグインエフェクト1件）を持たせ、本家形式キー（x は "Y"、y は "X" に入れ替わり、"JimakuFadeIn" 等）で保存される形にした。検証（一時テストで実施）: 生成ファイルを読み直し、読み飛ばしがちょうど1件（タイムライン0・要素インデックス8・FutureItem）、アイテムレベルの型移行記録は0件（TextItem の入れ子エフェクト WaveEffect にはコミュニティ移行が適用される）、VoiceItem の字幕プロパティが型付きで往復し追加フィールドが空であること、raw テキストに旧形式キー（"JimakuX"／"JimakuY"／"JimakuZ"／"JimakuOpacity"／"JimakuZoom"／"JimakuRotation"／"JimakuBlend"／"JimakuIsInverted"）が存在しないこと、保存→再読込→再保存の固定点到達を確認した。一時テスト削除後の全件テストは194件合格。これにより MAC-0011 未解決事項 (c) のうちサンプルに関する部分は解消（旧形式キー一般の扱いは不変）。本家生成の実ファイルではない点も従来どおり。

#### MAC-0012 — GPU 実行器（Metal）と基本 Source、デバッグアプリの合成プレビュー（IMPLEMENTED）

**何を実装したか。** MAC-0010 の「次の担当へ」で残した GPU 実行器と基本 Source を実装し、デバッグアプリで「開いた .ymmp の1フレームが絵として表示される」状態にした。対象は技術仕様 第1章（IMG 契約）・第2章（IGraphicsDevices）・第3章（ISource / ISourceOutput）の確定事項と、MAC-0009 / 0010 で定義した抽象（ImageReference、RenderTarget / RenderTargetFactory、DrawingEffectProcessor、Source）の実物化である。内容は: (1) ルートパッケージへの新規ターゲット `YMM4GPU`（製品ライブラリ。全ソースを `#if os(macOS)` で包み、Linux では空モジュール）。(2) Metal 描画基盤: デバイス共有＋文脈は消費者ごとに新規生成（第2章の契約）、ImageReference の実体として MTLTexture と平面座標の境界・変換・不透明度・補間方式を保持する `MetalImage` と、デバイス単位の登録表。(3) 抽象描画先 RenderTarget の Metal 実装。(4) DrawingEffect の Metal 実装（変換の遅延記録）。(5) 基本 Source: 画像（ImageItem）・図形（ShapeItem の RectangleShapeParameter＋単色ブラシ）・未対応種別向けの空 Source と、種別から Source を供給する `MetalSourceProvider`。(6) デバッグアプリへの合成プレビュー欄（TimelineComposer ＋ Metal で現在フレームを合成し、読み戻した CGImage を表示。フレームスライダで再合成）。

**どこを変更したか。** ローカル作業のみ（push なし）。`Package.swift`: 製品 `YMM4GPU` とターゲット（YMM4Core 依存）を追加。新規 `Sources/YMM4GPU/` 4ファイル: `MetalGraphics.swift`（MetalGraphicsDevices、MetalImage、MetalGraphicsContext、シェーダ一式、CGImage 読み戻し）、`MetalRenderTarget.swift`（MetalRenderTarget）、`MetalDrawingEffect.swift`（MetalDrawingEffect）、`MetalSources.swift`（MetalImageSource、MetalShapeSource、MetalEmptySource、MetalSourceProvider）。`Apps/DebugApp/Package.swift`: YMM4GPU 製品への依存を追加。新規 `Apps/DebugApp/Sources/YMM4MacDebug/PreviewBox.swift`（合成セッションの保持者）。`Apps/DebugApp/Sources/YMM4MacDebug/ProjectView.swift`: プレビュー欄（画像表示＋フレームスライダ）と resetPreview / renderPreview を追加。既存の読み込み診断・往復チェックには触れていない。

**どう実装したか。** (1) 座標系は本家どおり平面座標（原点＝画面中心、x 右・y 下、単位ピクセル）。MetalImage の属性は本家どおり BGRA 8bit / Premultiplied を基本とする（IMG-06: 合成コアに色管理なし）。(2) MetalGraphicsDevices: MTLDevice を所有し、パイプライン（テクスチャ付き／単色／図形 SDF の3種）・サンプラ（最近傍／線形）・1×1 透明テクスチャをコンストラクタで即時生成する（本家の即時生成と同じ）。`makeContext()` が消費者ごとの文脈（MetalGraphicsContext、自分の MTLCommandQueue を所有し RenderTargetFactory を兼ねる）を返す。登録表はデバイス共有で NSLock 保護。(3) MetalRenderTarget: 文脈の targetSize（画面サイズ）のテクスチャ（.bgra8Unorm、renderTarget＋shaderRead、shared）を実体とし、トークンを画面矩形の境界で登録する。記録はコマンドバッファへ畳み込み、Clear は「次のパスを透明でクリアする」フラグとして再現する（記録途中の Clear がそれまでの内容を破棄する点まで含む）。fillRect は Premultiplied 化した単色で、drawImage は入力の境界四隅へ実体の変換（透視の w を頂点の w に残して補間を透視補正）を適用したテクスチャ付き四角形で描く。合成は全パイプライン共通で Premultiplied の通常合成（SourceOver）。close() で commit して完了まで待つ。(4) MetalDrawingEffect: 本家の連鎖（ズーム Affine → Crop → Transform3D → 不透明度 ColorMatrix）を中間テクスチャなしで再現し、入力実体へ「入力自身の変換 × ズーム変換 × ワールド変換 × 透視（M34 = −0.001）」の合成変換と不透明度・補間方式を記録した実体を出力として登録する。ワールド変換は本家 CreateWorldMatrix どおり（回転Z → 回転Y（符号反転）→ 回転X（符号反転）→ 平行移動 → カメラ）。ズームは反転（中心まわりの x 反転）→ 拡縮の順。ズーム 0・不透明度 0 のときは本家の空差し替えどおり 1×1 透明（不透明度 0）を出す。PlaneSplitGeometryProviding として、ワールド変換そのものと、入力境界へ入力変換とズーム変換を適用した外接矩形（本家の Crop 出力境界に相当。未更新・空では nil）を返す。(5) MetalImageSource: コンストラクタで自前の文脈を生成して所有し（本家と同じ）、読み込みは初回 Update と FilePath 変更時だけ。ImageIO でデコードして Premultiplied BGRA テクスチャ化し（寸法上限 16384、超過時は比例縮小）、中心が原点になる配置（本家の (−幅/2, −高さ/2) 描画。端数は本家どおり 0 方向へ切り捨て）で登録する。相対パスは .ymmp のあるフォルダ基準。失敗時は本家の代替（CreateEmptyBitmap）と同じく 1×1 完全透明。出力は dontDispose の StandardSourceOutput。(6) MetalShapeSource: GetSize の式どおりに寸法を評価する（WidthHeight / SizeAspect の2分岐）。描画は本家の実現化規則の可視結果を SDF で再現する: 枠線の太さが min(幅, 高さ)/2 + 0.25 を超えれば全面塗り、そうでなければ内側へ太さ分の帯。角の丸み（Round）は角丸半径。図形中心が原点のテクスチャ（寸法上限 4096）へ描き込み、評価キー（幅・高さ・丸み・太さ・色）が変わったときだけ再描画する。ブラシは単色のみ対象で、それ以外は白で代用する（本家の既定ブラシも単色・白）。(7) MetalEmptySource / MetalSourceProvider: ImageItem → 画像、ShapeItem → 図形、それ以外（Text・Video・Scene・Tachie・Effect・合成グループを含む）は透明な空 Source を返す。合成グループの子は TimelineComposer 側の資源として別途処理される（従来どおり）ため、グループ自体が空でも子は描かれる。非合成グループの Source は本家でも描画内容を持たない。(8) デバッグアプリ: PreviewBox がセッション（ファイル＋タイムライン）ごとにデバイス・文脈・TimelineComposer を保持し、フレーム変更で再合成して CGImage を読み戻す。文脈の targetSize は描画のたびにタイムラインの VideoInfo へ合わせる。

**本家との差分。** 意図的な差分・未実装は次のとおり。(a) 本家のコマンドリストは無限平面だが、こちらは描画先ごとに画面サイズのテクスチャへ畳み込む。画面外へはみ出す内容は本家では最終合成まで残るのに対し、こちらでは各描画先の段階で切り取られる（内部差分。観測差が出るのは、画面外にはみ出した中間結果を後段が画面内へ戻す変形・クリッピング等に限られる）。(b) 記録したコマンドは close() で一括実行し完了まで待つ。本家は描画グラフの遅延評価で GPU 完了の区別自体が無い（第1章）。観測可能な順序は保たれるが、非同期性は再現していない（内部差分）。(c) Blend の特殊合成（本家の BlendImage 相当）は未実装で、drawImage の blend 引数は通常合成に倒す（差し替え点）。BlendMode ごとの合成式は後段で扱う。(d) DrawingEffect の出力は初回 Update の前は nil（本家では生成直後から出力が存在するが、消費者は Update 後にしか読まない。内部差分）。(e) 図形のテクスチャ寸法上限 4096: 巨大な図形では境界が粗くなる（内部差分）。本家の WidenedIntersection の幾何そのものではなく可視結果（内側の帯）の再現である点も含む。(f) 画像デコードは macOS 標準（ImageIO）で読める形式のみ。本家のプラグイン経路（WIC 等）は対象外。Windows 形式のパスは Mac 上に存在しないため解決できず透明に落ちる（実ファイルの素材が Mac に無い場合の表示はこの経路になる）。(g) テキスト Source は未実装（次ブロック）。動画・シーン・立ち絵・FrameBuffer の実 Source、個別エフェクト（VideoEffectProcessor の実物）、アルファマスクの実物、BSP 本体、先読み・キャッシュ・TimelineItemRects は引き続き未実装で、該当アイテムは透明になる（合成グループの子と、親エフェクト無しの素通しは除く）。(h) FrameBuffer アイテムの実 Source が無いため、MAC-0010 の所有権移転の実描画確認はまだ行えていない。

**メモリ・並行性。** 所有関係: MetalGraphicsDevices がデバイスと共有資源（パイプライン・サンプラ・透明テクスチャ）と登録表を所有する。MetalGraphicsContext は自分のコマンドキューを所有し、デバイスは借用。MetalRenderTarget は自分のテクスチャを所有し、破棄時に登録を外す。Source は自前の文脈と DrawingEffect を所有し（本家の所有構造どおり）、デコード／描画したテクスチャを保持する。MetalDrawingEffect の出力は登録のみでテクスチャは入力の借用（本家の参照共有と同じ）。描画先の close() は同期完了のため、読み戻し時点で GPU 完了が保証される。登録表のみ NSLock で保護し、それ以外は単一スレッドの逐次実行（MAC-0010 の実行部と同じ前提）。

**検証。** (a) VM（Linux、Swift 6.1.2）: `swift test` 全194件合格、警告・エラーなし。YMM4GPU は Linux では空モジュールとなり既存テストへ影響しない。(b) 本人の Mac（macOS 26.3、Swift 6.2.4、SSH 経由で実施）: ルートパッケージ `swift build` 成功、デバッグアプリ `swift build` 成功（いずれも警告なし）。ビルドエラー3件（レンダーパス／パイプラインのアタッチメントが Optional、CGBitmapInfo の定数名、TimelineComposer の引数名 targetFactory）はその場で修正した。(c) ヘッドレス検証ハーネス（Mac 上 /tmp の使い捨てパッケージ。sample.ymmp ＋ /tmp/image.png（64×48 の赤 PNG を生成）を使用）: 読み込みで読み飛ばし1件（FutureItem）を確認。フレーム0・10・45 の合成が例外なく完了し、読み戻しで次を確認した: フレーム0 = 図形（100×100・白）が中心に不透明で出る（非透明 10,000 px、中心ピクセル BGRA (255,255,255,255)）、フレーム10 = 同じ、フレーム45 = 画像が中心に出る（非透明 3,072 px ＝ 64×48 と一致、中心ピクセルは不透明赤）。切り分けの過程で頂点ストライドの不整合（QuadVertex の実ストライド 32 に対し頂点記述子へ 24 と固定していた）を発見・修正した（頂点記述子は MemoryLayout から取る）。(d) 未検証: デバッグアプリの画面上での目視（プレビュー欄の表示そのもの）は未実施で、次に本人がアプリを起動した際の確認対象。実ファイル（kiminihare 系）の素材は Mac 上に存在しないため、それらを開いた場合のプレビューは素材不在の透明表示になる見込みで、見た目の正しさは検証していない。本家実機とのピクセル比較（Golden Master）は環境が無いため未実施であり、本件は IMPLEMENTED 止まり。

**未解決事項。** (a) 上記差分 (a) の無限平面の再現要否（中間テクスチャの動的サイズ化が要るかは、クリッピング／マスクの実物化の段で判断する）。(b) BlendMode の合成式一式（差分 (c)）。(c) 図形以外の図形パラメータ（生保持の $type）と単色以外のブラシ。(d) TextSource / JimakuSource（次ブロック。VoiceItem の JimakuVisibility / キャラクター解決の置き場もここで決める。MAC-0011 未解決 (a)）。(e) デバイス喪失時の扱い: 本家には抽象側の復旧が無くプレイヤーだけが再試行する（第2章）ため、こちらも未実装のまま揃えた。

**次の担当へ。** 描画系の次段: テキスト描画（TextSource / JimakuSource。CoreText によるレイアウトと背景・前景の分離描画、フォント解決と条件付き太字、輪郭の幾何描画が本家との乖離リスク。TEXT-RENDERING-FACTS 参照）、個別エフェクトの実装（196件。本体101件から。DrawDescription 変換のみの22件と素通し8件が先行候補。PreservedObject から VideoEffectDefinition を供給する EffectPairProvider の実物を含む）、メディア読み込み（動画デコード。AVFoundation のコンテナ対応が狭いため FFmpeg 併用が最初の論点。MEDIA-IO-FACTS 参照）、FrameBuffer / Scene / Tachie の実 Source、アルファマスクの実物、BSP 本体。プレビューの目視確認結果が得られたら本台帳へ追記すること。

#### MAC-0013 — 音声パイプラインの芯（AudioStream 連鎖・アイテム音声・タイムラインミックス・グループバス）（IMPLEMENTED）

**何を実装したか。** 音声パイプラインの芯を Foundation のみで実装した。内容は: (1) 本家 AudioStreamBase の意味論を再現するプルモデルの音声ストリーム基盤 `AudioStream`。(2) 音声ファイルのデコードを差し替え点として切り出す `PCMProvider` / `PCMProviderFactory`。(3) アイテム単位で素材ストリームへ処理器の連鎖を組む `EffectedAudioItemSource`（本家 EffectedAudioItemSource 相当）と、連鎖を構成する処理器群。(4) タイムライン全体のミックス `TimelineAudioMixer` と、音声グループのバス処理（`AudioGroupResolver` / `GroupAudioBusSource`）。ユーザー音声エフェクトの実物、デコードの実体、再生（プレビュー）・書き出しへの接続は本件の範囲外で、差し替え点までとした。

**どこを変更したか。** 新規 `Sources/YMM4Core/Audio/` に8ファイル: `AudioStream.swift`（AudioStream、InputFrameWindow）、`PCMProvider.swift`（PCMProvider / PCMProviderFactory、InMemoryPCMProvider、FileAudioStream）、`EffectedAudioItemSource.swift`（AudioItemProperties、AudioEffectDefinition / AudioEffectProvider / EmptyAudioEffectProvider、VoiceUpsamplingMode、AudioChainOptions、EffectedAudioItemSource、AudioSourceFactory）、`AudioEffectProcessors.swift`（AudioEffectProcessorBase、SimpleAudioEffectProcessorBase、NegativeSeekableAudioStream、ContentOffsetAudioStream、LoopAudioStream、ReverseAudioStream、EchoAudioStream）、`AudioResampling.swift`（InterpolationKernel と Linear / Cubic の各カーネル、ResamplerStream、PlaybackRateStream、VariablePlaybackRateStream、UpsamplerStream）、`VolumePanStream.swift`（VolumePanStream）、`AudioGroups.swift`（AudioGroupSegment、AudioGroupResolver、SegmentGateStream、GroupEffectChainStream、AudioGroupStreamBuilder、GroupAudioBusSource）、`TimelineAudioMixer.swift`（TimelineAudioMixer）。テストは新規 `Tests/YMM4CoreTests/AudioPipelineTests.swift`（20件）。実装は分離ツリーで先行し、ファイルのコピーで本ツリーへ統合した（既存ファイルの変更なし）。push はしていない（親側の検証後）。

**どう実装したか。** (1) `AudioStream`: 本家 AudioStreamBase どおり float32 / 2ch 固定のプルモデルとし、`Position` はインターリーブ済みサンプル数で数え、内部の読み取りが返した分だけ進む。`TimeToPosition` は ticks × 2 × Hz / 10⁷ で偶数へ切り捨て、`PositionToTime` は商と剰余に分けて本家どおりに換算する。読み取り先バッファのゼロ初期化は本家と同じく呼び出し側の責務とし、ストリームは無音区間を書かない。`InputFrameWindow` はチャンク単位のランダムアクセス窓で、範囲外は無音として返し、終端到達を記録する。(2) デコード差し替え点: 本家 IAudioFileSource / AudioFileSourceFactory に相当する `PCMProvider` / `PCMProviderFactory` をプロトコルとして切り出し、合成 PCM 用の `InMemoryPCMProvider` を用意した。`FileAudioStream`（本家 AudioSource 相当）は provider が nil の場合に 48000 Hz・長さ 0 の無音になる。(3) `EffectedAudioItemSource`: 本家のチェーン順序をそのまま再現した — NegativeSeekable →（可変レート時は VariablePlaybackRate、定速時は Reverse・Loop・ContentOffset）→ Echo →（レート 100% 超かつ素材 Hz が 20000 未満のときだけ Resampler）→ PlaybackRate →（VoiceItem のみ Upsampler）→ タイムライン Hz への Resampler → ユーザー音声エフェクト → VolumePan → Resampler。読み取りは出力 Hz 換算でアイテム長にクランプし、負位置には無音の前置を付ける。既存の `PlaybackRateMap` と `Animation.value(atFrame:length:fps:)` を再利用した。チェーンの入力側プロトコル `AudioItemProperties` には AudioItem / VideoItem / SceneItem / VoiceItem が適合し、VoiceItem の音声フェードは字幕側（MAC-0011 の `fadeIn`）との名前衝突を避けて `audioFadeIn` / `audioFadeOut` として公開した。(4) 処理器: いずれも入力ストリームへの委譲で動作する。Reverse は1秒ブロック単位の反転、Echo はフィードバック型で反復回数 = min(50, ceil(log 0.01 / log decay))、VolumePan はサンプル対ごとに Animation を評価し（フェード係数 = min(1, t/fadeIn, (継続時間 − t)/fadeOut)、線形パン法則、音量が定数 0 のときのミュート近道を含む）、Resampler は線形補間で Hz 一致時は素通し（長さ・シークの変換式は本家 MFT ラッパーの式に一致させた）、Upsampler は本家の位置対応式（入力位置 = 出力位置 / rate + 1/(2·rate) − 0.5）を再現した。(5) `TimelineAudioMixer`: 読み取り範囲と交差するリソースだけを読み取りのたびに開閉し、非表示アイテム・非表示レイヤーを除外し、レイヤー音量（LayerSettings.Volumes / 100）を適用して float 加算でミックスする。リミッターは本家どおり置かない。読み取りはタイムライン長でクランプし、シーク時は全リソースを破棄する。グループバスは `AudioGroupResolver` がアイテム範囲をグループ境界で区間分割し、親・祖先をレイヤー降順に列挙して DirectGroups（最初の IsAudioComposite までの接頭列）と Owner（最初の IsAudioComposite）を算出する。完全に所有される子はトップレベルへ直接加算せず `GroupAudioBusSource`（バスミックス → グループエフェクト → Resampler）経由でのみ鳴らし、二重加算を避ける。部分的に重なる区間は `SegmentGateStream` で非所有部分だけを通し、グループ内部の連鎖は `PositionShiftStream` でグループ相対座標に移して評価する。入れ子シーンのタイムラインも対象に含む。

**本家との差分。** 意図的な差分・未実装は次のとおり。(a) Resampler の補間は線形補間を採用した。本家 MFT リサンプラとの等価性は**未検証**であり、一致させたのは長さ・シークの変換式のみ。(b) SOLA ピッチ補正（本家 PlaybackRateSolaTimeStretchEffect / VariableSolaPitchCorrectionEffect）は未実装で、差し替え点でリサンプリングへフォールバックする。(c) ユーザー音声エフェクト約40種は未実装。`AudioEffectProvider` の差し替え点（既定は空）のみを用意した。グループエフェクトの有効判定は生 JSON の `IsEnabled`（欠落時は有効）で行う。(d) Upsampler のカーネルは Linear / Cubic のみ（Lanczos / Blackman / Hanning / Hamming / Mitchell-Netravali / NearestNeighbor は未実装）。既定モードは本家のフォールバック分岐に従い Cubic としたが、本家の既定設定値そのものは未検証。(e) VariablePlaybackRate の素材枯渇点は累積 tick 走査＋二分探索で近似した（本家 FindContentExhaustedTime の Swift 等価物が PlaybackRateMap に無いため）。(f) シークは ticks を経由するため精度が落ちる（本家も同じ。本家の癖として再現）。(g) 本家の並列ミックス＋Interlocked 加算は逐次加算に置き換えた（各 Source の音声とレイヤー音量を加算する数学的な処理は同じだが、加算順序が変わるため Float32 の丸め結果まで一致する保証はない。本家の非決定的な並列加算順序は再現しない）。読み取りバッファは本家の再利用と違い読み取りごとに確保する。(h) LoopAudioStream のリワインド後の Position の癖は本家どおり写した。Echo のシーク前読み取り経路は本家では失敗する経路だが、こちらはバッファ初期化で防御した（実フローでは常にシークが先行する）。(i) VoiceItem の PCM はモデルにファイルパスが無いため、`voiceProviderResolver` の注入で供給する形にした。

**メモリ・並行性。** ストリームは参照型で、所有関係は連鎖の外側（EffectedAudioItemSource / TimelineAudioMixer / GroupAudioBusSource）が内側の入力ストリームを保持する一方向のみ。処理器は入力への委譲で状態を持ち回らず、各ストリームの Position が唯一の可変状態。並行性は持たない（逐次読み取り。本家の並列ミックスは上記差分 (g) のとおり置換）。

**検証。** `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（Linux、Swift 6.1.2）で全214件合格（従来194件＋新規20件）、警告・エラーなし。新規テストは AudioPipelineTests の20件で、ストリーム基盤の位置換算、チェーン順序と各処理器（反転・ループ・エコー・音量パン・リサンプリング・再生レート・アップサンプリング）、タイムラインミックスとグループバス（二重加算の回避を含む）、入れ子シーンを対象とする。Foundation のみのコードであり macOS 固有 API は使っていない。本家実機との比較試験は環境が無いため未実施であり、本件は IMPLEMENTED 止まり。

**未解決事項。** (a) Resampler の MFT 等価性（上記差分 (a)）。波形レベルの一致が必要になった時点で、本家環境での採取と比較が要る。(b) SOLA ピッチ補正の実装要否と方式。(c) ユーザー音声エフェクト約40種の定義層と処理器（映像側のエフェクト定義層と同型の仕事）。(d) デコードの実体（PCMProvider の実物。動画デコードと共通のメディア読み込みの段で、FFmpeg 併用の要否と合わせて扱う）。(e) 再生（プレビュー）と書き出しへの接続。音声の実出力はまだどこにもつながっていない。(f) Upsampler の本家既定設定値の確定。

**次の担当へ。** 音声の次段は、デコード実体の供給（メディア読み込みの段）、ユーザー音声エフェクトの実装、プレビュー再生（AVAudioEngine 等）と書き出し（第6章の契約）への TimelineAudioMixer の接続である。Resampler の等価性検証は本家環境が用意された場合の採取対象に含めること。

#### MAC-0014 — テキスト描画（TextSource / JimakuSource）と VoiceItem 実効値の共通解決（IMPLEMENTED）

**何を実装したか。** TextItem と VoiceItem（字幕）の描画を CoreText で実装し、プレビュー合成でテキストが出る状態にした。あわせて MAC-0011 で先送りした VoiceItem の JimakuVisibility／キャラクター解決の置き場を確定し実装した。内容は: (1) テキスト描画の実物 `MetalTextSource`（本家 TextSource 相当）と `MetalJimakuSource`（本家 JimakuSource 相当）を新規ターゲット YMM4GPU に追加し、`MetalSourceProvider` が TextItem → テキスト、VoiceItem → 字幕を供給するようにした（従来はどちらも透明な空 Source）。(2) 本家の前処理（正規化・制御タグ解析）→ IDWriteTextFormat → IDWriteTextLayout → 背景（装飾）／前景（グリフ）の分離描画 → SourceOutput 群というパイプラインを、CoreText による独立実装 `MetalTextRasterizer` として再現した（フォント解決と条件付き太字、縁取り・影の幾何、配置原点、タイプライター、文字単位分割の TimeOffset / DurationOffset を含む。実測の正本は解析側 TEXT-RENDERING-FACTS）。(3) VoiceItem の実効値解決を描画パイプライン全体の共通仕組みとして YMM4Core に実装した（下記）。

**JimakuVisibility の解決時点（本家根拠）。** 本家 `VoiceItem.CreateVideoSource` は無条件に `new JimakuSource(devices, this, FPS)` を返し、生成時点では何も解決しない。表示可否と外観は `JimakuSource.UpdateResource` が Update のたびに判定する: 表示ゲートは `JimakuVisibility == Hidden || Character == null || (UseCharacterSetting && !Character.IsJimakuVisible)`、外観は `Custom` のときだけアイテム自身、それ以外は Character の値を参照する。さらに変形（X/Y/Z・Opacity・Zoom・Rotation・FadeIn/FadeOut・Blend・反転・クリッピング・IsAlwaysOnTop・IsZOrderEnabled・VideoEffects）は VoiceItem の IVideoItem 明示的実装 getter が読まれるたびに解決される。したがって「Source 生成時点で確定させる」設計は本家と一致しないため採らず、解決を YMM4Core の共通アクセサに置き、JimakuSource・EffectedItemSource・TimelineSource・DrawOrdering の全利用箇所がそれを通る形にした（ChatGPT レビュー第2ラウンドの制約1と一致する）。

**どこを変更したか。** ローカル作業のみ（push なし）。YMM4Core（最小限）: 新規 `Sources/YMM4Core/Items/VoiceItemJimaku.swift`（`VoiceItem.jimakuIsVisible` / `jimakuAppearance` / `resolvedX` 等の実効値一式と、`VideoItemProperties` 拡張の `effectiveX` 等の共通アクセサ）。`Sources/YMM4Core/Rendering/EffectedItemSource.swift` / `TimelineSource.swift` / `DrawOrdering.swift`: アイテムの保持プロパティの直接読み取りを実効値アクセサ経由へ切り替え。`Sources/YMM4Core/YmmpCodec.swift`: デコード完了時に `Project.Characters` から `CharacterName` で VoiceItem / TachieItem / TachieFaceItem の実行時参照を解決する処理を追加（本家の `Character` は [JsonIgnore] で保存されるのは名前だけであるため。本家ファイルでは参照が未解決のままになっていた）。YMM4GPU: 新規 `Sources/YMM4GPU/MetalTextSources.swift`（MetalFontResolver、MetalTextRasterizer、MetalTextSource、MetalJimakuSource）。`Sources/YMM4GPU/MetalSources.swift`: Provider の分岐追加とコメント更新。保存時に "Character" オブジェクトを書き出す現行コーデックの是正は本件では触っていない（MAC-0015 の範囲）。

**どう実装したか。** (1) フォント解決（MetalFontResolver）: 本家は Font 文字列を SystemFonts＋CustomFonts からフェイス表示名の完全一致で探し、見つからなければ空名で作成する。CoreText には表示名の単一検索が無いため、CTFontCreateWithName の結果を名前群（PostScript / Full / Family / Style / Display / Family+Style）と照合して検証し（存在しない名前でも既定フォントが黙って返るため）、コレクション全体の記述子走査も行う。太字は本家どおり「アイテム Bold が true かつ解決フェイスの標準ウェイト < Bold(700)」のときだけ太字へ引き上げ、斜体は Italic 指定時に付ける。装飾範囲のフォントは同じ規則で解決し、解決できなければ基準フォントへフォールバックする。(2) レイアウト: 前処理は NFC 正規化と IsTrimEndSpace 時の行末空白除去（アスタリスク置換はユーザー辞書が空の本家と同等で無変換）。字間は trailing 側のみへの加算として自前で進み量へ足し、行末では 0 に戻す。折り返しは段落ごとに CTLine / CTTypesetter で行い、行間は LineHeight/100 の倍率を適用する。配置原点は本家 TextLayoutDescription の式（横位置は TextAlignment、縦位置は ParagraphAlignment と第1行メトリクスの行間適用前後の差）を再現した。出力の Center は本家の ComposeOutputs どおり原点。(3) 描画: BGRA Premultiplied のビットマップへ2パスで描く。背景パスは縁取り（グリフ輪郭パスへのストローク。線幅は Border・SharpBorder が EmSize/7、Light 系が /14、結合は Round / Miter、MiterLimit 2）と影（輪郭の塗り、オフセット EmSize/24、不透明度 1.0 / 0.5）。前景パスは輪郭パスの塗り。下線・打消し線は行単位の塗り矩形。ラスタライズ結果は評価済み様式＋表示範囲のキャッシュキーが変わったときだけ再生成する。(4) タイプライターと分割: 非分割は本家 GetTextRange のタグなし経路で表示範囲を切り取る。分割（IsDevidedPerCharacter）時はグリフごとに「視覚中心がテクスチャ中心」の小テクスチャを作り、DrawingOffset に中心座標、TimeOffset = min(0, −DisplayInterval × 表示順位)、DurationOffset = min(0, −HideInterval × (総数−1−消去順位)) を持たせ、本家 FilterDisplayOutputs の条件で出し分ける。(5) 縦書きは CTFramesetter の縦組みでフレーム全体を描く近似経路（MaxWidth は MaxHeight として使用、原点は本家の転置式）。(6) JimakuSource: 表示ゲートは `jimakuIsVisible`、外観は `jimakuAppearance`（Custom または Character なしなら自身の appearance、それ以外は Character の外観プロパティ群から組み立てた TextAppearance）を使い、解決自体は共通仕組みに委ねて Source 内では局所解決しない。VoiceItem の jimaku プロパティの X/Y キー入れ替わり（MAC-0011）はモデル層の保持どおり入力になる。

**本家との差分。** 意図的な差分・未実装は次のとおり。(a) フォント解決: 本家は Win32 のフェイス表示名体系であり、CoreText の名前体系・フォールバック先と異なるため、同じプロジェクトでも選ばれるフェイスと太さがずれうる（内部差分だが見た目に現れる）。(b) レイアウト計測は CoreText の行メトリクスを使うため、行高・ベースライン・改行位置が DirectWrite と完全には一致しない。行間（Proportional）のベースライン割合の扱いも近似（行ごとの ascent への倍率適用）。(c) 縁取りは輪郭パスへの CG ストロークで再現したが、D2D のストローク幾何（輪郭の中心線から内外へ半分ずつ太る）とはアルゴリズムが異なり、太さと角の形がずれうる。(d) 制御タグ（ルビ・タイミングタグ）とユーザー辞書のアスタリスク置換は未実装。タイプライターはタグなし経路のみで、ルビは描画されない。(e) 装飾の位置ずらし（OffsetX/OffsetY・絶対配置）と回転（RotationZ）は未実装。装飾で対応するのはフォント（名前・Scale・太字・斜体）・前景色・字間上書き・Style＋DecorationColor・下線・打消し線のみ。(f) 縦書きは近似経路で、縁取り・影・字間・分割・タイプライターは未対応。(g) ラスタライズ先は有限テクスチャで範囲外は切り取られる（本家は無限平面コマンドリスト）。縁取りはみ出し分のパディングで緩和しているが、巨大なテキストでは切れる。(h) Random タイプライターの順位は本家が GetHashCode() 由来で再現不能（本家自体も実行ごとに変わる）ため、テキスト長由来の決定的シャッフルで代用した。(i) 下線・打消し線は単一パスの塗り矩形（本家は背景・前景の二重構造で Style が線にも効く）。打消し線の位置は x-height/2 の近似。(j) `resolvedVideoEffects` で未知の JimakuVisibility 保存名を Visible と同じ扱いに倒した（本家は例外経路）。(k) 非表示時のクリア頻度: 本家 JimakuSource は可視→非表示の遷移時に一度だけクリアし、連続する非表示 Update では早期リターンする（JimakuSource.cs L103–113）。こちらは非表示の Update のたびに空化＋クリアを実行する。出力は同じく空でクリアは冪等なため可視差は無い（内部差分。2026-11-17 レビュー R14-04 で同意し記録）。(l) Character が nil の場合の字幕エフェクト供給: 本家 getter は空列を返すが、こちらは保持列を供給する（MAC-0020 で記録済みの描画中立な差分。字幕自体が表示ゲートで描画されない。2026-11-17 レビュー R14-05）。

**メモリ・並行性。** MetalTextSource / MetalJimakuSource は画像・図形の Source と同じく自前の文脈（MetalGraphicsContext）を所有し、ラスタライズ済みテクスチャはデバイス登録表へ登録した MetalImage として保持する（出力は dontDispose の StandardSourceOutput で、effect と参照の破棄は Source 側）。再ラスタライズ時は旧テクスチャの登録を外してから差し替える。実効値アクセサは値の読み取りのみで状態を持たない。実行は単一スレッドの逐次実行（従来どおり）。

**検証。** (a) VM（Linux、Swift 6.1.2）: `swift test` 全214件合格、警告・エラーなし（YMM4Core 側の実効値・参照解決の変更に対する回帰確認。YMM4GPU は Linux では空）。(b) 本人の Mac（macOS 26.3、Swift 6.2.4、SSH 経由）: ルートパッケージとデバッグアプリの `swift build` 成功、警告なし。ビルドエラー5件（CTFontCollection / CTFrame の非 Optional 化、CTFontCreateUIFontForLanguage の Optional、縦組み属性値の型）はその場で修正した。(c) ヘッドレス検証ハーネス（Mac 上 /tmp の使い捨てパッケージ）: sample.ymmp を合成し、フレーム45（TextItem「こんにちは、世界」、X=50）でテキスト想定領域に非透明 2,492 px（画面全体 5,610 px）、フレーム210（VoiceItem 字幕「セリフです」、Custom）で字幕想定領域に非透明 1,179 px を確認。縦書きプローブ（BasePoint = 縦書き・右上、6文字）でも 80×203 のテクスチャに非透明 2,531 px を確認。本家形式の JSON（VoiceItem に "Character" キーが無く CharacterName のみ）では Character 参照が名前で解決され、JimakuVisibility=Visible・Character の X=120・アイテム自身の X=0 のとき実効 X が 120 になること（制約1の具体例）を確認した。(d) 未検証: デバッグアプリの画面上での目視、本家実機とのピクセル比較（Golden Master）は環境が無いため未実施であり、本件は IMPLEMENTED 止まり。

**未解決事項。** (a) 上記差分 (a)〜(i) の解消要否（フォント名体系の対応表、レイアウト計測の一致度、縁取り幾何）。(b) 制御タグ（ルビ・タイミング）とアスタリスク辞書の実装（モデル層に辞書・タグ情報の保持が要る）。(c) 装飾の位置ずらし・回転。(d) フォント既定値（Texts.DefaultFont の実文字列）は引き続き未確定。(e) Character の保存側是正（"Character" オブジェクトを書き出さない）は MAC-0015 で行う。(f) 解析側の Mac As-built・互換マトリクスへの同期は本実装の確定（PR）時に行う。

**次の担当へ。** 描画系の次段: 個別エフェクトの実装（196件。本体101件から。DrawDescription 変換のみの22件と素通し8件が先行候補。EffectPairProvider の実物を含む）、メディア読み込み（動画デコード。MEDIA-IO-FACTS 参照）、FrameBuffer / Scene / Tachie の実 Source、アルファマスクの実物、BSP 本体。テキストについては、実ファイルを開いた際の見た目の確認（フォント解決のずれの実測）が最初の検証対象。MAC-0015（Character 保存側の是正）が次に控える。

#### MAC-0015 — キャラクター参照の保存・解決契約の是正（IMPLEMENTED）

**何を実装したか。** MAC-0014 で読み込み側（`CharacterName` からの参照解決）を実装した際に残した、保存側の是正。本家ではアイテムの実行時参照 `Character` は保存されず、保存されるのは `CharacterName` のみである。従来のコーデックは "Character" オブジェクト自体を書き出していたため本家形式とずれていた。ChatGPT レビュー第2ラウンドの指摘を実コードで照合し、採用したもの。

**どこを変更したか。** `Sources/YMM4Core/Items/TextItems.swift`（VoiceItem のエンコード）と `Sources/YMM4Core/Items/CompositeItems.swift`（TachieItem / TachieFaceItem のエンコード）の `encodeKnownFields`。テストは新規 `Tests/YMM4CoreTests/CharacterReferenceTests.swift`（4件）。

**どう実装したか。** 本家 `VoiceItem.cs`（L173–195）で確認した契約どおりにした: 実行時参照 `Character` は [JsonIgnore] で保存対象外、保存は `CharacterName` のみ、その getter は `Character?.Name ?? characterName`。3アイテムの `encodeKnownFields` から "Character" オブジェクトの書き出しを削除し、`CharacterName` には `character?.name ?? characterName` を書くよう変更した。decode 側の "Character" ケースは、自前の旧保存ファイル（MAC-0014 以前の形式）との互換のため残置し、読み込んだファイルは次回保存時に本家形式へ正規化される。名前→参照の解決自体は MAC-0014 で `YmmpCodec.resolveCharacterReferences` として実装済みのものを使う。

**本家との差分。** 保存形式のずれは解消し、本家形式に一致する。残る差は decode 側で旧形式の "Character" オブジェクトも受け付ける点のみ（本家には無い互換経路だが、書き出しには現れない内部差分）。

**メモリ・並行性。** 変更なし（エンコード時のキー選択のみ）。

**検証。** CharacterReferenceTests 4件: 本家形式（CharacterName のみ）での名前解決と、解決先が Project.Characters の同一インスタンスであること、保存時に "Character" キーが存在しないこと、保存→再読込→再保存の往復の固定点、旧形式ファイルの読み込みと再保存時の正規化。全件合格（統合後の総数は MAC-0018 の検証項を参照）。**検証の穴だった点**: MAC-0005 追補の実ファイル検証に使った本家ファイル2件はキャラクター0件であり、この経路（キャラクター参照の保存・解決）は実ファイルでは未踏だった。是正の根拠は本家実コード（VoiceItem.cs）の照合である。

**未解決事項。** キャラクターを含む本家実ファイルでの往復検証は未実施（本家を動かせる環境が無い事情は従来どおり）。

**次の担当へ。** キャラクター参照の保存・解決契約は本件で読み書き両方向が揃った。

#### MAC-0016 — 音声 QA：ドリフト実測とシーク量子化の修正（IMPLEMENTED）

**何を実装したか。** MAC-0013 の音声パイプラインについて、位置の累積ドリフトとシーク着地精度を実測で検証し、見つかった系統的なずれを修正した。本人が YMM で替え歌制作を行うため、音声の位置ずれ・波形のずれは創作に直結する優先度の高い欠陥として扱う（本人の指示、2026-11-17）。

**どこを変更したか。** `Sources/YMM4Core/Audio/PCMProvider.swift`（`InMemoryPCMProvider.seek` の丸め方式）。既存テスト `Tests/YMM4CoreTests/AudioPipelineTests.swift` の期待値1件を修正。新規テスト `Tests/YMM4CoreTests/AudioDriftTests.swift`（7件）と `Tests/YMM4CoreTests/AudioSampleAccuracyTests.swift`（9件）。計画文書として解析側に `analysis-notes/AUDIO-FIDELITY-PLAN.md`（リサンプラ芯の高品質化と SOLA の段階計画）を作成した。

**どう実装したか。** (1) ドリフト実測: 位置カウンタの累積ドリフトは、対象チェーン（リサンプル跨ぎ・ミキサー・グループバス・定速200%・可変速）についてローカル計測で 300 秒（5分）まで 0 サンプルであることを確認した。コミット済みテスト（AudioDriftTests）で再現可能な範囲は経路ごとに異なり、リサンプル跨ぎ 300 秒・ミキサー 300 秒・可変速 180 秒・フレーム単位読み 180 秒・定速200% は出力 120 秒・グループバス 60 秒である（従来の「全チェーン5分」という書き方は両者を混同していたため、2026-11-17 の ChatGPT レビュー指摘を受けて区別して明記する）。(2) 見つけて直したバグ: 内容位置に系統的な −1 フレームずれがあった。原因は `InMemoryPCMProvider.seek` の tick→サンプル変換の切り捨てが、呼び出し側（`PositionToTime`、本家式）の床誤差と重なる二重量子化である。なお本家でも、AudioSource が `PositionToTime` で TimeSpan 化し、ファイルソースが `TimeToPosition`（整数除算の切り捨て）でサンプル位置へ戻す二段の量子化は存在する（`AudioSource.cs` L33–36、`MFAudioFileSource.cs` L922–930、`FFmpegAudioFileSource.cs` L479–480 で照合。2026-11-17 の ChatGPT レビュー R16-01/02 の事実精密化を採用）。本家の量子化は両段とも切り捨てで一貫しているのに対し、こちらで観測された系統的な −1 フレームは本家式の `PositionToTime` と provider 側切り捨ての組み合わせで生じたため、seek を最も近いフレーム境界への丸め（`.toNearestOrEven`）へ変更した。修正後はシーク着地が全測定位置でサンプル厳密になり、内容偏差は ±0.09 フレーム以内に収まった。(3) 既存テストの期待値1件を 0.75 → 0.375 に修正した。旧期待値自体がこのずれの症状を固定していたもの。(4) 残る量子化（アイテム開始が2サンプル早まる等）は本家式（TimeToPosition / PositionToTime の換算）由来であり、本家からの逸脱ではないため未修正とした。

**本家との差分。** seek の丸め変更は合成 PCM provider への是正であり、本家の換算式自体は変更していない。ただし丸め方式は本家と同一ではない: 本家のファイルソースは `TimeToPosition` の切り捨てで着地するため、要求位置から最大1フレーム手前に着地しうる。こちらは最近傍丸めで要求フレームへ着地させる独立実装の精度改善であり、本家の二重切り捨てが1フレーム落ちる条件では、本家と内容位置が1フレーム異なりうる。MAC-0013 で記録した差分（Resampler の MFT 等価性は未検証、SOLA 未実装、ユーザー音声エフェクト未実装 等）は不変。

**メモリ・並行性。** 変更なし。

**検証。** 新規16件（AudioDriftTests 7件、AudioSampleAccuracyTests 9件）を含む統合後の全テストで合格（総数は MAC-0018 の検証項を参照）。AudioSampleAccuracyTests には、エコーのシーク読みと逐次読みのビット一致、ループ境界のフレーム厳密性、グループ分割点での内容連続性を含む。本家実機との波形比較は環境が無いため未実施であり、本件は IMPLEMENTED 止まり。

**未解決事項。** (a) Resampler の MFT 等価性と補間品質（現状は線形補間）。(b) SOLA ピッチ補正。(a)(b) の段階計画は `analysis-notes/AUDIO-FIDELITY-PLAN.md` に切り出した。(c) 実デコード（PCMProvider の実物）が入った時点で、実素材でのシーク精度の再測定が必要。

**次の担当へ。** 音声忠実度の次段は AUDIO-FIDELITY-PLAN の段階計画（リサンプラ芯の高品質化 → SOLA）。MAC-0017 の EnvelopeFollower の波形一致も音声忠実度の優先確認対象である。

#### MAC-0017 — 書き出し（mp4）の芯（IMPLEMENTED）

**何を実装したか。** 書き出しの芯を Foundation のみで実装した。技術仕様 第6章（IVideoFileWriter）の確定契約に基づく。内容は: (1) 書き出しセッションの状態機械。(2) FFmpeg 引数生成（本家の癖を含む純粋関数）。(3) BS.1770 ラウドネス解析とダイナミクス処理。(4) 本家方式（音声・映像の別プロセス＋終了時 mux）のプロセスライター。(5) NV12 変換（BT.709 リミテッド）。GPU からのフレーム供給と音声ミックスとの接続は本件の範囲外であり、書き出しの芯までである。

**どこを変更したか。** 新規 `Sources/YMM4Core/Export/`: `ExportSession.swift`（状態機械）、`ExportSettings.swift`（設定の明示受け渡し）、`FFmpegArguments.swift`（引数生成と NV12 変換）、`FFmpegProcessWriter.swift`（プロセスライター）、`LoudnessAnalysis.swift`（BS1770LoudnessAnalyzer）、`DynamicsProcessorStream.swift`（DynamicsProcessor と EnvelopeFollower）。テストは新規 `Tests/YMM4CoreTests/ExportTests.swift`（56件）。

**どう実装したか。** (1) `ExportSession`: 正常終了・キャンセル・例外の全経路で finalize が正確に1回だけ走ることを状態遷移で保証し、結果状態（正常／失敗／キャンセル）は型で区別する（第6章の契約追加 W6-C2/C3）。(2) FFmpeg 引数生成は本家の癖を含む純粋関数とし、生成結果をテストで固定できる形にした。(3) `BS1770LoudnessAnalyzer` は二段ゲーティング（絶対 −70 LKFS／相対 −10 LU）を実装し、既定モード（DownMaximumVolume、ピーク基準）ではアナライザ自体が生成されない第6章 §8 の確定事項どおりの生成条件とした。音量係数は DynamicsProcessor の入力音量として適用され、Ratio=1 の高速経路（直接乗算）は本家と厳密一致する。(4) `FFmpegProcessWriter`: 音声（WAV 一時ファイル）と映像を別プロセスで書き、終了時に `-c copy` で mux する本家方式を再現した。プロセス起動は差し替え点に分離した。(5) NV12 変換は BT.709 リミテッドレンジ。色宣言は NV12 経路のみに付け、BGRA 経路には付けない非対称を本家どおり維持した。

**本家との差分。** 意図的な差分は次のとおり。(a) 終了コード検査を追加した（本家には検査しない経路がある。是正として意図的に追加）。(b) 映像書き込みは同期化した（本家は Task による並行書き込み。呼び出し側のバッファ契約＝映像 byte 列は全書き出しを通して単一配列の借用、音声はフレームごとの新規スライス、という非対称は維持した）。(c) プロセス引数は配列の正準形で渡す（本家には文字列連結の箇所がある）。(d) ハードウェアエンコーダの解決は差し替え点を用意したが未適用。(e) MF ライター相当は未実装（本家同梱の第2の書き出し経路）。

**メモリ・並行性。** 映像バッファは全書き出しを通して単一配列の借用、音声はフレームごとの新規スライス（第6章の呼び出し側契約どおり）。finalize は Dispose 相当の終了手続きに集約し、どの終了経路でも1回だけ実行される。

**検証。** ExportTests 56件を含む統合後の全テストで合格（総数は MAC-0018 の検証項を参照）。引数生成、状態機械の遷移（正常／キャンセル／例外時の finalize）、ラウドネスのモード分岐と係数計算を対象とする。**実 ffmpeg での書き出しは未検証**（Mac 統合時に実施する）。

**未解決事項。** (a) EnvelopeFollower の係数法則は、本家が使う NWaves が逆コンパイル集合に無く、再構成で実装したため、Ratio≠1 の波形一致は未検証。音声忠実度の優先確認対象とする。(b) 実 ffmpeg での書き出し検証（Mac 統合時）。(c) MF ライター相当。(d) GPU フレーム供給・音声ミックスとの接続は次段。

**次の担当へ。** 次段は書き出しの接続（TimelineComposer のフレーム列と TimelineAudioMixer のミックスを ExportSession へ供給する段）と、Mac 上での実 ffmpeg 検証。EnvelopeFollower の係数法則の裏取りは音声忠実度 QA（MAC-0016 の系）と合わせて扱う。

#### MAC-0018 — 映像エフェクト定義層＋DrawDescription 変換型処理器（IMPLEMENTED、コーデック接続は次段）

**何を実装したか。** 映像エフェクトの定義層を型付けし、GPU を使わない「DrawDescription 変換のみ」で完結する処理器群を実装した。本家の映像エフェクトは定義（Animation 型パラメータの保持）と処理器（CreateVideoEffect で生成）が分離しており、MAC-0010 では処理器チェーンの契約だけがあった。本件で定義層と変換型の処理器が揃った。ただし **YmmpCodec への組み込みは未実施**であり、現時点では定義層と処理器が単体で検証済みの状態である（.ymmp 読み込み時のエフェクトは従来どおり PreservedObject の生保持のまま）。

**どこを変更したか。** 新規 `Sources/YMM4Core/Effects/` 9ファイル: `VideoEffectDefinitionBase.swift`（定義の共通基盤）、`VideoEffectRegistry.swift`（$type 名→定義型のレジストリ）、`DrawDescriptionEffectProcessor.swift`（変換型処理器の基盤）、`BasicDrawEffects.swift`、`InOutEffects.swift`、`RandomRepeatEffects.swift`、`CameraEffects.swift`、`PreviewAndGroupEffects.swift`、`MotionTrackingEffect.swift`。変更: `Sources/YMM4Core/Animation.swift` の `randomMoveRate` / `repeatMoveRate` を private から public へ変更した（定義層との共有計算の再利用のため）。テストは新規 `Tests/YMM4CoreTests/EffectsTests.swift`（35件）。

**どう実装したか。** (1) 定義の共通基盤は、$type 名との対応、Animation 型パラメータの読み書き、未対応キーの追加フィールド保持によるデータ保全、IsEnabled を備える。(2) レジストリ登録は22種: Zoom、Opacity、DrawPosition、InOutFade、InOutMove、InOutZoom、InOutMoveFromOutsideFrame、RandomMove、RandomOpacity、RandomZoom、RepeatMove、RepeatOpacity、RepeatZoom、ShowOnlyPreview、Billboard、CameraFov、CameraPosition、CameraLookAt、CameraWraparound、PolarDrawPosition、XYToPolarTransform、MotionTracking。登録外として GroupedDrawingEffect（グループ合成用。$type を持たない）を用意した。(3) GroupedDrawing は、GroupItem.GroupEffects（自身の VideoEffects ＋ GroupedDrawing の計算プロパティ）として供給される本家の形に合わせた。(4) 実測事項: 実ファイルの CameraPositionEffect で $type 形式・キー順・既定値の復元を検証した。Repeat 系の Span=0 の偶奇は、処理器コードに従うと Animation 本体の評価と逆になる（本家の処理器側の実装どおりに再現した）。(5) 処理器は MAC-0010 のチェーン契約（位置基準の再利用、SetInput の省略規則、DrawDescription の連鎖書き換え）に適合させた。

**本家との差分。** 意図的な差分は次のとおり。(a) ZoomEffect の補間方式は設定層（YMMSettings）が未実装のため、入力値を維持する（本家は設定から読む）。(b) 乱数系エフェクトのシードは、本家 `GetHashCode()` との対応付けが存在しないため `Animation.randomSeed`（既定0）で代替した。値一致は未解決（MAC-0002 以来の既知事項）。(c) 未知の列挙名は原文保持＋既定値で評価する（本家は読み込み失敗になる経路。データ保全優先の緩和）。

**メモリ・並行性。** 定義はモデル層の他要素と同じ保持方式（参照型の定義インスタンス＋追加フィールド保持）。処理器の所有関係は MAC-0010 の連鎖契約どおり。

**検証。** `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（Linux、Swift 6.1.2）で全 **325件** 合格（従来214件＋MAC-0015 の4件＋MAC-0016 の音声 QA 16件＋MAC-0017 の書き出し56件＋本件35件）、警告・エラーなし。EffectsTests は定義の往復（型付き復元→保存で値が保たれる）、変換式の代表ケース、チェーン契約への適合を対象とする。本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**未解決事項。** (a) YmmpCodec への組み込み（`VideoEffectRegistry.decode/encode` と `TypedEffectPairProvider` の接続、キーフレーム文脈の伝播）は次段。(b) GPU 処理系161種の定義・処理器も次段。(c) 乱数シードの値一致（上記差分 (b)）。

**次の担当へ。** 次段はコーデック接続（レジストリ経由の型付き復元と、EffectedItemSource へ TypedEffectPairProvider で定義を供給する段）と、GPU 処理系エフェクトの定義・処理器。書き出しの接続（MAC-0017 の次段）も並行候補である。（コーデック＋合成チェーン接続は MAC-0019、VoiceItem の字幕エフェクト解決の接続は MAC-0020 で実施した。）

#### MAC-0019 — 映像エフェクト定義層のコーデック＋合成チェーン接続（IMPLEMENTED）

**何を実装したか。** MAC-0018 で単体検証済みだった映像エフェクト定義層を、.ymmp の保持形式と合成チェーンへ接続した。読み込み済みプロジェクトのエフェクトが、合成時に型付き定義として処理器チェーンへ供給されるようになった。接続の設計判断は「保持形式は生保持のまま＋消費側で型付き復元」であり、YmmpCodec への組み込みは行わない（下記）。

**どこを変更したか。** `Sources/YMM4Core/Rendering/TimelineSource.swift`（TimelineComposer の既定 effectProvider を EmptyEffectPairProvider から TypedEffectPairProvider へ変更）、`Sources/YMM4Core/Rendering/EffectedItemSource.swift`（既定供給元の変更と陳腐化したコメントの更新）、`Sources/YMM4Core/Effects/VideoEffectRegistry.swift`（TypedEffectPairProvider にキーフレーム文脈の伝播を追加）。テストは新規 `Tests/YMM4CoreTests/EffectWiringTests.swift`（EffectWiringTests 4件）。DebugApp の PreviewBox は供給元を指定していないため、既定の変更により自動的に接続される（アプリ側の変更なし）。

**どう実装したか。** (1) 保持形式の判断: モデル層は全箇所で従来どおり PreservedObject の生保持のままとし、保存経路は一切変更しない。型付き定義は消費側（TypedEffectPairProvider）が合成時に作る一時的なビューとし、保存時に型付き encode で再直列化することはしない。この判断が保証する射程は、型付きエフェクト定義の消費経路が既存の生 JSON 保存経路を変更せず、エフェクトの保存結果を新たに正規化しないことまでである（型付き encode を経由すると、キー順の並び替え、空の Remark の省略、数値の再直列化による表記の正規化が入りうる）。プロジェクト全体の固定点は YmmpCodec の検証結果に依存する（EF18-02 による精密化、MAC-0030 で是正）。`VideoEffectRegistry.encode` は変換用途として利用可能なまま残置した。(2) 接続先: TimelineComposer の既定の EffectPairProvider を TypedEffectPairProvider に差し替えた。供給対象のキーは、VisualItem 系の VideoEffects、VoiceItem の JimakuVideoEffects、GroupItem の VideoEffects、TachieFaceItem・VoiceItem の TachieFaceEffects とした。SceneItem / TransitionItem の Before・AfterVideoEffects は対象外とした（供給経路が別系統のため）。(3) キーフレーム文脈の伝播: TypedEffectPairProvider は、定義の生成時と、所有アイテムの KeyFrames が変更されたときにだけ `setKeyFrames` を再伝播する。定義インスタンス自体は作り直さない（MAC-0010 の連鎖の再利用規則が、定義インスタンスの同一性で差し替えを判定するため）。

**本家との差分。** 本家は読み込み時にエフェクトを型付き定義としてモデル層に保持するが、こちらはモデル層では生保持とし、型付き定義は消費側の一時的なビューに留める。合成時の評価・描画への影響はない（供給される定義と処理器は MAC-0018 のもの）。保存の出力は生保持の経路のままであるため、本家形式との関係は MAC-0005 以来の保持方針から変わらない。SceneItem / TransitionItem の Before・AfterVideoEffects が未接続な点は本件の範囲外とした未実装である。

**メモリ・並行性。** 型付き定義は TypedEffectPairProvider が作る一時的なビューであり、所有関係は MAC-0010 の連鎖契約（TimelineComposer → EffectedItemSource → 処理器群）のまま。定義インスタンスは KeyFrames 変更時にも再生成されず、文脈だけが再伝播される。

**検証。** `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（Linux、Swift 6.1.2）で全329件合格（従来325件＋新規4件）、警告・エラーなし。新規の EffectWiringTests は既定供給元の接続と対象キーの範囲を対象とする。さらに MAC-0005 追補の実ファイル2件で、接続前と往復結果が完全一致することを確認した（ファイル1: 158アイテム・再保存 780,172 バイト、ファイル2: 142アイテム・693,977 バイト。いずれも読み飛ばし0件・型移行0件・固定点到達）。本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**未解決事項。** (a) GPU 処理系161種の定義・処理器は未登録のままで、それらは型付き復元の対象にならない。(b) SceneItem / TransitionItem の Before・AfterVideoEffects の供給経路。(c) VoiceItem の字幕エフェクトは、この時点では保持列（JimakuVideoEffects）がそのまま供給され、JimakuVisibility による解決列（MAC-0014 の resolvedVideoEffects）は未接続だった（MAC-0020 で解消）。

**次の担当へ。** GPU 処理系エフェクトの定義・処理器が次段。VoiceItem の字幕エフェクト解決の接続は MAC-0020 で行った。

#### MAC-0020 — VoiceItem の字幕エフェクト解決の接続（IMPLEMENTED）

**何を実装したか。** MAC-0014 で実装した VoiceItem の実効値解決のうち、字幕エフェクト列（`resolvedVideoEffects`）を MAC-0019 の供給経路へ接続した。字幕の映像エフェクトが、JimakuVisibility とキャラクター設定に応じて本家どおりに切り替わるようになった。

**本家実コードの確認。** 本家 `VoiceItem.cs` の IVideoItem.VideoEffects getter（L813–841）を実コードで確認した: Custom → アイテム自身の列、Visible → キャラクター側の列（キャラクターが無ければ空）、Hidden → 空、UseCharacterSetting → キャラクターが存在し `IsJimakuVisible` のときだけキャラクター側の列。MAC-0014 の `resolvedVideoEffects` はこの getter と正確に一致することを確認した（解決ロジック自体は変更なし。本件は供給への接続のみ）。

**どこを変更したか。** `Sources/YMM4Core/Effects/VideoEffectRegistry.swift` の `TypedEffectPairProvider.ownEffectPairs`。テストは `Tests/YMM4CoreTests/EffectsTests.swift` に TypedEffectPairProviderVoiceJimakuTests（5件）を追加。

**どう実装したか。** `ownEffectPairs` は、対象アイテムが VoiceItem であり、かつキャラクターが解決済み（character 参照が引けている）の場合に限り、供給列として保持列（JimakuVideoEffects）ではなく `resolvedVideoEffects` を使う。それ以外（VoiceItem でない、またはキャラクター未解決）の場合は従来どおり保持列を使う。キャラクター未解決時に保持列へフォールバックしても描画結果へ影響しないのは、字幕の表示ゲート（MAC-0014: character が nil では字幕自体が表示されない）により、その VoiceItem の字幕が出力されないためである。

**本家との差分。** 解決の意味論は本家の getter と一致させた（上記の実コード確認）。残る違いは解決の置き場のみで、本家は IVideoItem の動的 getter が読まれるたびに解決するのに対し、こちらは MAC-0014 以来の方針どおり共通アクセサと供給側での解決であり、観測可能な結果は同じになる。

**メモリ・並行性。** 変更なし（供給列の選択のみ）。

**検証。** `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（Linux、Swift 6.1.2）で全334件合格（従来329件＋新規5件）、警告・エラーなし。新規の TypedEffectPairProviderVoiceJimakuTests は、JimakuVisibility の各モードでの供給列の切り替わりと、キャラクター未解決時のフォールバックを対象とする。本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**未解決事項。** VoiceItem を含む本家実ファイルでの裏取りは未実施（MAC-0011 以来の事項。実ファイルが得られたら、字幕エフェクトの切り替わりを含めて再確認する）。

**次の担当へ。** VoiceItem の字幕まわり（表示ゲート・外観・変形・映像エフェクト）の解決は本件で全て供給経路へ接続された。残る映像エフェクトの主項目は GPU 処理系161種の定義・処理器である。

#### MAC-0021 — GPU 失敗の検出・通知契約（RenderTarget.close() の throws 化）（IMPLEMENTED）

**何を実装したか。** GPU 実行の失敗を、合成の呼び出し側が検出できる契約にした。発端は ChatGPT レビュー第2弾の指摘 G12-07（処分記録は解析側 `analysis-notes/REVIEW-DISPOSITION-MAC0012-0014.md`）: `MetalRenderTarget.close()` がコマンドバッファの status / error を検査しておらず、テクスチャ生成の失敗や GPU 実行エラーがあっても正常終了として扱われ、不完全な画像が正常な Output として公開されうる状態だった。本件で失敗は例外として上位へ伝播し、不完全な画像は出力として公開されない。

**どこを変更したか。** `Sources/YMM4Core/Rendering/EffectedItemSource.swift`（RenderTarget プロトコルの `close()` を throws 化し、EffectedItemSource 側の呼び出しを追随）、`Sources/YMM4Core/Rendering/TimelineSource.swift`（FrameBuffer 境界と最終合成の close を try 化）、`Sources/YMM4GPU/MetalRenderTarget.swift`（`MetalRenderError` の新設と失敗検出）。テストは `Tests/YMM4CoreTests/CompositionTests.swift` に失敗注入の仕組みと新規3件を追加。付随修正として `Package.swift`（ルート）と `Apps/DebugApp/Package.swift` の最低対応 OS 宣言（下記）。

**どう実装したか。** (1) 抽象側: RenderTarget プロトコルの `close()` を `func close() throws` へ変更した。EffectedItemSource は close が失敗した描画先を出力として公開せず、その場で dispose してからエラーを再送出する。(2) TimelineComposer 側: FrameBuffer 境界の close と最終合成の close を try 化した。最終合成の close が失敗した場合は出力を差し替えず、旧出力が保持される。(3) Metal 側: エラー型 `MetalRenderError`（`textureCreationFailed` / `commandBufferFailed`）を新設した。テクスチャ生成に失敗した場合はその事実を保持しておき close() で投げる。コマンドバッファについては commit → waitUntilCompleted の後に status == .error を検出して投げる。正常経路（同期完了・合成順序）は無変更である。

**本家との差分。** 本家は GPU 完了の区別自体を持たず失敗の通知契約も無い（第1章）。こちらは Swift 側の安全性のための追加契約であり、本家の観測可能な正常系の挙動は変えない。失敗時に旧出力を保持する扱いは、MAC-0010 以来の「失敗した更新で旧 Output を壊さない」方針に沿う。

**メモリ・並行性。** 失敗した描画先は公開されずに dispose される（所有関係は従来どおり）。同期完了モデルも無変更。

**検証。** `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（Linux、Swift 6.1.2）で全337件合格（従来334件＋新規3件）。新規テストは、RecordingRenderTarget への失敗注入により、アイテム側／合成側／FrameBuffer 境界の各 close 失敗で update が例外を投げ、出力が差し替わらないことを対象とする。Mac 実機ビルド成功（ルート＋デバッグアプリ）。

**付随修正（Package.swift の最低対応 OS 宣言）。** ルート `Package.swift` に最低対応 OS macOS 26.0（CR-001）を宣言し、DebugApp 側の宣言も `.v26` 相当へ統一した。これにより、MAC-0017 の `FFmpegProcessWriter` が Mac ビルドで可用性エラー（macOS 10.15 以降の API を下限未宣言のまま使う形）になる既存問題が解消した。宣言は `.macOS("26.0")` の文字列形式とした（Linux 側 Swift 6.1 の PackageDescription が `.v26` のケースを持たないため）。Linux テスト・Mac ビルドの両方で再確認済み。

**未解決事項。** GPU 失敗時の利用者への提示方法（製品 UI の段で扱う）。本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**次の担当へ。** 描画の異常系は本件で契約として閉じた。残る描画系の主項目は GPU 処理系エフェクトの処理器（MAC-0022 で定義層を実装済み）。

#### MAC-0022 — GPU 処理系エフェクトの定義層73種（IMPLEMENTED、処理器は暫定の素通し）

**何を実装したか。** 本家内蔵エフェクトのうち未登録だった GPU 処理系73種の定義クラスを型付きで実装し、レジストリへ登録した。登録総数は95種（MAC-0018 の DrawDescription 変換群22種＋本件73種）となり、本家内蔵101種については、コミュニティ移行先等を除き定義層が揃った。対象から漏れた本家内蔵エフェクトは無い。ただし処理器は全て暫定の素通しであり、パラメータの型付き復元・往復保全のみが成立する。描画への反映は次段の Metal 処理器まで無い。

**どこを変更したか。** 新規 `Sources/YMM4Core/Effects/` 10ファイル: `GPUTransformEffects.swift`（変形系14種）、`GPUBlurEffects.swift`（ぼかし系12種）、`GPUColorEffects.swift`（色調系11種）、`GPUShadowFillEffects.swift`（影・塗り系9種）、`GPUWarpEffects.swift`（歪み系8種）、`GPUMaskKeyEffects.swift`（マスク・キー系3種）、`GPUInOutEffects.swift`（出入り系10種）、`GPURandomRepeatEffects.swift`（ランダム・反復系4種）、`GPUCustomEffects.swift`（カスタム系2種）、`GPUEffectSupport.swift`（暫定処理器 `GPUEffectPassthroughProcessor`、GPU 定義の基底 `GPUEffectDefinitionBase`、新規列挙型18種）。変更: `VideoEffectRegistry.swift` への73種の登録。テストは新規 `Tests/YMM4CoreTests/GPUEffectsTests.swift`（27件）。

**どう実装したか。** (1) 定義クラスは MAC-0018 の基盤（VideoEffectDefinitionBase）の作法に従い、$type 対応・Animation 型パラメータ・追加フィールド保持によるデータ保全を備える。GPU 系は共通基底 `GPUEffectDefinitionBase` を介する。(2) 処理器は暫定として `GPUEffectPassthroughProcessor`（入力をそのまま返す素通し）を全種に割り当てた。MAC-0019 の消費側の型付き復元により、合成チェーンへは型付き定義として供給されるが、描画結果にはまだ影響しない。(3) 旧互換キーの転送6件を実装しテストで固定した（Sepia / Gradient / CenterPoint / ChromaKey2 / Mask / InOutRotate の旧形式キーから現行プロパティへの読み替え）。

**本家との差分。** 定義（パラメータの保持と往復）は本家と一致させる一方、処理器が素通しのため、GPU 処理系エフェクトの描画結果は本家と異なる（エフェクトが効かない）。これは未実装の明示であり、次段の Metal 処理器で解消する。多態パラメータの内部（Brush、DisplacementMapTransform、NoiseParameter、MosaicParameter、Mask の ShapeParameter）は型付き化せず生保持のままである。GradientStop / MeshDeformationPoint は一部のみ型付けした新規構造体で、残部は追加フィールド保持とした。Gradient の旧キー転送には防御の差分がある: Stops が2要素未満の異常な旧ファイルでは、本家は ColorTo の setter が Stops[1] を無条件に参照するため失敗しうるが、Swift 側はデータ保全を優先し、要素がある場合だけ転送して回避する（GPU22-05、MAC-0030 で記録）。

**メモリ・並行性。** 定義は MAC-0018 と同じ保持方式（参照型の定義インスタンス＋追加フィールド保持）。暫定処理器は入力参照をそのまま返すため、新たな資源は生じない。

**検証。** 73クラス全てについて、本家定義クラスの永続プロパティ名と Swift 側のキー（読み書き）を機械照合し、欠落0を確認した。`~/workspace/tools/swift-6.1.2/usr/bin/swift test`（Linux、Swift 6.1.2）で、新規 GPUEffectsTests 27件を含む全366件・0失敗。GPUEffectsTests は定義の往復（型付き復元→保存で値が保たれる）と旧互換キーの転送を対象とする。本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**未解決事項。** (a) GPU 処理系73種の Metal 処理器（次段）。(b) 多態パラメータ内部の型付き化（Brush 等、上記）。(c) GradientStop / MeshDeformationPoint の完全な型付け。

**次の担当へ。** 次段は Metal 処理器の実装で、`GPUEffectPassthroughProcessor` を種別ごとの実処理器へ置き換える。定義層は本件で揃っているため、処理器の段ではパラメータの読み取り方法は変更しない。（Metal 処理器の第1段は MAC-0023 で実装し、Mac 検証を経てメインへ統合済み。）

- **件数訂正（2026-11-18、構造整理 W11）**: 本項の当初記載「新規列挙型19種」は誤りで、実ファイルの列挙は18件（現行の `Effects/GPU/GPUEffectEnums.swift` で確認）。結論に変更はない。

#### MAC-0023 — GPU エフェクト Metal 処理器 第1段（IMPLEMENTED、Mac 検証済み・統合済み）

**何を実装したか。** MAC-0022 で定義層が揃った GPU 処理系エフェクトのうち10種について、Metal による実処理器を実装した（第1段）。対象は色変換系8種（Invert、Monocolorization、Sepia、Tint、Exposure、GammaCorrection、Posterize、LinearTransfer）と GaussianBlur、Mosaic。これらは合成チェーンで描画へ反映される。当初は分離ツリーで実装し、Mac 検証が未実施だったため統合を保留していたが、Mac 実機でのビルド・画素検証が完了し、メインクローンへ統合済みである。

**どこを変更したか。** 新規 `Sources/YMM4GPU/MetalEffectProcessors.swift`（830行）、変更 `Apps/DebugApp/Sources/YMM4MacDebug/PreviewBox.swift`（TimelineComposer の供給元として MetalEffectPairProvider を渡すよう接続）。当初は分離ツリー `ymm4mac-metalfx` で実装し、Mac 検証の完了後に本リポジトリへ統合した。PreviewBox の統合形は、MAC-0025 のシーン解決（プロジェクト全タイムラインを sceneResolver として渡す）と本件の MetalEffectPairProvider 接続を併せ持つ。

**どう実装したか。** (1) `MetalEffectPairProvider`（EffectPairProvider の Metal 実装）が Core の `TypedEffectPairProvider` を内包し、供給される（定義, 処理器）の組のうち対象10種の定義だけを、Metal 処理器つきのラッパ定義へ差し替える。対象外は内包先の組（DrawDescription 変換型処理器、または暫定の素通し）をそのまま使う。(2) ラッパ定義は元の定義インスタンスをキーにキャッシュし、連鎖の再利用判定が依拠する定義インスタンスの同一性を安定させる。(3) DebugApp の PreviewBox はこの供給元を使うようになったため、プレビューでは対象エフェクトが描画へ反映される経路ができた。

**本家との差分。** 対象10種は描画へ反映され、Mac 実機のヘッドレスハーネスで画素検証が全件合格した（Invert・Monocolorization・Sepia・GammaCorrection 等はシェーダ式からの解析値と完全一致）。ただし検証の期待値は解析値であり、本家実機との画素比較は本家を動かせる環境が無いため未実施である。対象外の GPU 処理系63種は引き続き暫定の素通しで、描画には反映されない（MAC-0022 の状態のまま）。

**メモリ・並行性。** ラッパ定義のキャッシュは供給元（MetalEffectPairProvider）が保持する。処理器（MetalEffectProcessor）は出力用の ImageReference を自身で持ち、描画結果の MetalImage を devices の登録表へその参照で登録し、dispose() で登録を解除する。入力は借用であり所有しない（第1章の契約どおり）。

**検証。** Linux（Swift 6.1.2）で全366件合格（実装当時）。ただし YMM4GPU は Linux では `#if os(macOS)` により空モジュールになるため、この合格は Core 側の回帰確認に留まり、MetalEffectProcessors.swift のコンパイル検証にはならない。**Mac 実機検証（統合時に実施）: ルート＋デバッグアプリのビルド成功・警告0。ヘッドレスハーネスによる画素検証は対象10種すべて合格し、Invert・Monocolorization・Sepia・GammaCorrection 等は解析値と完全一致した。** 本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**未解決事項。** (a) GPU 処理系の残り63種の Metal 処理器（第2段以降）。(b) 多態パラメータ内部の型付き化（MAC-0022 の未解決事項を引き継ぐ）。(c) 本家実機との画素比較（本家環境が必要）。

**次の担当へ。** 第2段では残り63種の処理器を種別ごとに置き換える。定義層の読み取り方法は変えない（MAC-0022 の方針）。

#### MAC-0024 — 音声リサンプラの高品質化 第1段（窓関数 sinc 芯への差し替え）（IMPLEMENTED）

**何を実装したか。** `ResamplerStream` のサンプル生成芯を、線形補間から帯域制限補間（窓関数 sinc）へ差し替えた。MAC-0013 で未検証として残した Resampler の品質に対する第1段で、解析側 `analysis-notes/AUDIO-FIDELITY-PLAN.md` の計画（リサンプラ芯の高品質化）に基づく。本人の音声忠実度優先の指示（2026-11-17）を受けたもの。

**どこを変更したか。** `Sources/YMM4Core/Audio/AudioResampling.swift`（新規 `BandLimitedResamplingCore` と、ResamplerStream の生成芯の差し替え）。テストは新規 `Tests/YMM4CoreTests/AudioResamplerQualityTests.swift`（6件）と、`Tests/YMM4CoreTests/AudioPipelineTests.swift` の期待値1件の変更（下記）。

**どう実装したか。** (1) 芯は窓関数 sinc 補間: Blackman 窓、片側48零点、scale=1 で97タップ。ダウンスンプル時は比率に応じてカーネルを広げ、折り返し（エイリアス）を防ぐ。(2) 契約側は無変更: 長さ・シーク・位置の変換式と、Hz 一致時の素通しは従来どおり。(3) 位置写像は不変である（インパルスのピーク位置が出力でも式どおりの位置に来ることを新規テストで確認）。(4) DC（直流成分）は厳密に保存される。

**本家との差分。** 本家の MFT リサンプラとの波形等価性は、本家を動かせる環境が無いため引き続き未検証である。本件は「本家と同一の補間」の再現ではなく、測定可能な高忠実度の達成を目的とする（計画書の方針）。PlaybackRate / VariablePlaybackRate の補間は線形のままで、そちらは SOLA の差し替え点として残る。

**メモリ・並行性。** 変更なし（生成芯の差し替えのみ。ストリームの所有・読み取りモデルは MAC-0013 のまま）。

**検証。** `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（Linux、Swift 6.1.2）で全372件・0失敗（従来366件＋新規6件）。品質実測（AudioResamplerQualityTests）: 通過利得の平坦さは 1k〜20kHz で ±0.00032 dB 以内。イメージ抑制 −88.7 dB（線形補間では −9.6 dB、改善 79.2 dB）。折り返し抑制の当初実測値（−113.4 dB、線形補間では −13.1 dB、改善 100.3 dB とした分）は、入力ナイキストを超える妨害波を使った測定系の欠陥により無効である（ChatGPT レビュー指摘 QA24-01、処分は analysis-notes/REVIEW-DISPOSITION-MAC0023-0029）。是正した測定系（妨害波は入力ナイキスト内・出力ナイキスト外）で再測定した結果、48k→44.1k の阻止帯域は −75 dB 級（23.5kHz の −78.6 dB はサイドローブのリプルの山、23.9kHz の −75.3 dB が床の水準）であった。詳細は analysis-notes/AUDIO-FIDELITY-PLAN.md §3.1.1。**これらの閾値は実測ベースの暫定回帰ガードであり、正式な合格値は ChatGPT レビューとオーナー承認で決める。** MAC-0016 のドリフト／境界テスト（AudioDriftTests・AudioSampleAccuracyTests）は全件無変更で合格した。

**既存テストの期待値変更（1件）。** AudioPipelineTests のランプ中点の期待値を 1.5 → 1.5456 へ変更した。旧値 1.5 は線形補間が区分線形信号をそのまま再現したときの値であり、帯域制限再構成における真値は約 1.5456（3種の窓で独立に確認）。経緯はテスト内のコメントに記録済み。MAC-0016 の 0.75 → 0.375 と同じく、旧期待値が旧実装の見かけを固定していたケースである。

**未解決事項。** (a) 本家 MFT との波形等価性（本家環境が必要）。(b) AVAudioConverter エンジンとの比較選定は未実施。(c) PlaybackRate 系の補間品質（SOLA の段で扱う）。(d) 品質閾値の正式合格値の決定（ChatGPT レビュー＋オーナー承認）。

**次の担当へ。** リサンプラは本件で高忠実度化した。残る音声忠実度の主項目は SOLA（PlaybackRate のピッチ補正）の実測・実装と、EnvelopeFollower（MAC-0017）の Ratio≠1 の検証である。

#### MAC-0025 — Video／Scene／FrameBuffer／Tachie の実 Source（IMPLEMENTED、Mac 検証済み）

**何を実装したか。** MAC-0012 で空 Source（透明）のままだった VideoItem・SceneItem・FrameBufferItem・TachieItem について、Metal による実 Source を実装した。基本 Source は画像・図形・テキスト・字幕に加え、動画・シーン・フレームバッファ・立ち絵まで揃った。

**どこを変更したか。** 新規 `Sources/YMM4GPU/MetalMediaSources.swift`（781行）: `MetalVideoSource`、`MetalSceneSource`、`MetalFrameBufferSource`、`MetalTachieSource` と、立ち絵描画の境界型（`MetalTachieRenderer` / `MetalTachieRendererFactory`、顔説明 `MetalTachieFaceDescription` / `MetalTachieUpdateDescription`）。変更: `Sources/YMM4GPU/MetalSources.swift`（共有ヘルパーと MetalSourceProvider の分岐追加）、`Apps/DebugApp/Sources/YMM4MacDebug/PreviewBox.swift` と `ProjectView.swift`（プロジェクト全タイムラインをシーン解決子として渡す配線）。

**どう実装したか。** (1) MetalVideoSource: 本家同様に自前文脈を所有し、デコーダの生成は初回と FilePath 変更時のみ。素材時刻は `PlaybackRateMap.getSourceTime` で求め、ループは素材 Duration の剰余で処理する。デコーダは AVAssetImageGenerator を採用した（本家のランダムアクセス型のデコード規則＝任意時刻のフレーム取得に一致させるためで、逐次読みの AVAssetReader は採らない。async API はセマフォで同期へ橋渡しする）。素材を開いた時点で実 Duration を `item.contentLength` へ反映する。(2) MetalSceneSource: 自前文脈を所有し、内側の TimelineComposer がその文脈を借用する（第2章の文脈契約）。SceneId 変更時のみ再生成する。入れ子上限は本家どおり「親チェーンに同一 ID が10回現れたら生成拒否」。(3) MetalFrameBufferSource: MAC-0009 / 0010 で用意した FrameBufferSource 契約（第1章 IMG-04）の Metal 実体。Flood → 入力を SourceOver で描画 → Crop 矩形を専用パスで適用し、蓄積が画素レベルで成立することを確認した。(4) MetalTachieSource: 描画は本家同様プラグインへの全面委譲であるため境界型を新設し、顔説明を本家式に構築して境界へ渡す。既定 factory（EmptyTachieRendererFactory）は nil を返し、プラグイン不在時の本家挙動に一致させる。

**本家との差分。** (a) AVFoundation が開けないコンテナ（MKV / WebM / TS 等）はデコードできず、透明フォールバック＋差し替え点のままである。FFmpeg 併用の要否は未判断（本家は FFmpeg と MediaFoundation の二系統を持つ）。(b) SAR（表示幅補正）は未対応。(c) 立ち絵の LipSync は包絡計算と口形評価が未実装で、音量は本家のフォールバック値、口形は常に .silent（LipSyncFrames がモデル層で生保持のため）。(d) 合成グループ（Composite GroupItem）の Source は未実装で透明になる（MAC-0027 で対応予定）。

**メモリ・並行性。** Video / Scene の各 Source は自前文脈を所有し、シーンの内側 Composer はそれを借用する（所有関係は MAC-0012 以来の方針どおり）。動画デコードの async 取得はセマフォで同期化し、更新モデルは従来どおり同期的である。

**検証。** Linux（Swift 6.1.2）で全372件・0失敗。Mac 実機ビルド成功・警告0。ヘッドレスハーネス全件合格: 動画 mp4 でフレーム0=赤／フレーム45=青、被覆3,072px 一致。シーン入れ子で白図形10,000px。フレームバッファ蓄積10,000px。立ち絵の顔説明2件が境界へ到達。自己参照シーンが入れ子上限で正常に打ち切られる。本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**未解決事項。** (a) SAR 未対応。(b) AVFoundation 非対応コンテナの扱い（FFmpeg 併用は未判断）。(c) LipSync の包絡計算と口形評価。(d) 合成グループ（Composite GroupItem）の Source（MAC-0027）。

**次の担当へ。** 基本 Source は本件で一通り揃った。残る描画系の主項目は合成グループの Source（MAC-0027）、GPU 処理系エフェクト処理器の第2段以降、書き出しへのフレーム供給接続である。（合成グループの Source は MAC-0027 で、書き出しへの供給接続は MAC-0026 で実施済み。）

#### MAC-0026 — 書き出しの実接続（音声・映像の供給と実エンコード検証）（IMPLEMENTED、実エンコード検証済み）

**何を実装したか。** MAC-0017 で実装した書き出しの芯（ExportSession / FFmpegProcessWriter / ラウドネス解析 / DynamicsProcessor）へ、タイムラインの実音声と実映像フレームを供給する経路を接続した。これにより、タイムラインから mp4 を実際に書き出せるようになった。

**どこを変更したか。** 新規 `Sources/YMM4Core/Export/ExportAudioProvider.swift`（98行、`TimelineExportAudioProvider`）、新規 `Sources/YMM4GPU/MetalExport.swift`（301行、`AVFoundationPCMProviderFactory`、`MetalExportVideoProvider`、ファサード `TimelineExporter`、キャンセル用 `TimelineExportCancellation`）。変更: `Sources/YMM4GPU/MetalGraphics.swift`（`MetalGraphicsDevices.readBGRA` を追加）、`Apps/DebugApp/Sources/YMM4MacDebug/ProjectView.swift`（書き出し UI = 保存先指定・進捗・キャンセル・解析値の要約表示、`ExportUIState` / `ExportJob`）。新規テスト `Tests/YMM4CoreTests/ExportAudioProviderTests.swift`（5件）。

**どう実装したか。** (1) 音声供給 `TimelineExportAudioProvider` は2パスの構成である。解析パスでは `TimelineAudioMixer` の出力チャンクを `LoudnessAnalysis` に通し、BS.1770 の測定値・音量係数（volumeRate）・コンプレッサ倍率（compressorRate）を得る（結果は `analysisResult` として公開）。書き出しパスでは別のミキサーへ `DynamicsProcessorStream`（volume = 解析の volumeRate、ratio = compressorRate、attack / release / lookAhead は CompressorSettings）を被せ、`audioSamples(forFrame:)` がフレームごとの新規配列を返す（尾部はゼロ埋め）。DynamicsProcessorStream の内部状態はシークで初期化される設計のため、生成直後に位置0へ明示シークする。(2) 素材デコードは `AVFoundationPCMProviderFactory` が担い、AVAssetReader で素材全体を float32 / 2ch へデコードして `InMemoryPCMProvider` 化する。デコード失敗時は nil = 無音とし、本家ファクトリの意味論（読めない素材は無音）に合わせた。(3) 映像供給 `MetalExportVideoProvider` は PreviewBox と同一構成の合成経路（TimelineComposer + MetalSourceProvider + MetalEffectPairProvider）でフレームを合成し、`readBGRA` でセッションの借用バッファへ読み戻す。(4) ファサード `TimelineExporter` が映像供給・音声供給・FFmpegProcessWriter・ExportSession を組み立て、DebugApp の書き出し UI から呼べるようにした。

**本家との差分。** (a) 素材デコードは全体をメモリへ展開する方式であり、本家のストリーミング読みとは異なる。長時間素材でのメモリ使用量は未検証。(b) AVAssetReader のサンプルバッファに付くトリム情報は無視している（素材先頭の無音パディング等がある形式では開始位置がずれる可能性がある）。(c) VoiceItem の音声は従来どおり無音である（`voiceProviderResolver` は未接続の差し替え点のまま）。

**メモリ・並行性。** 音声供給の解析パスと書き出しパスは別々のミキサーを持ち、解析のためにミックスを一度通す（本家の読み直し方式と同じ構造）。映像バッファは MAC-0017 の契約どおり単一配列の借用である。書き出しジョブは DebugApp 側でバックグラウンド実行し、進捗は MainActor 経由で UI へ反映、キャンセルは TimelineExportCancellation（NSLock 保護）で伝える。

**検証。** Linux（Swift 6.1.2）で全377件・0失敗（当時。新規5件を含む）。Mac 実機ビルド成功・警告0。当初 Mac に ffmpeg が無かったため、まずスタブで配線を実測検証した: 映像ストリームは 30 フレーム × NV12 バイト数ちょうどで、プレビュー合成と Y プレーンがビット一致。音声はサンプル数ちょうど、RMS が理論値と一致。ラウドネス解析のピーク −6.0206 dB が理論値と一致。その後 ffmpeg 9.0.2 を導入して実エンコードを検証した: export.mp4（H.264、64×48、30fps、30フレーム＋AAC 48kHz ステレオ、尺1.000秒）が生成され、復号フレームの中心が白・隅が黒で合成結果と一致し、音声 RMS は −8.99 dB（理論値 −9.03 dB、AAC の誤差内）だった。本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**未解決事項。** (a) 素材デコードのメモリ展開方式（長時間素材のメモリ量は未検証）。(b) AVAssetReader のトリム情報の無視。(c) VoiceItem の音声が無音（voiceProviderResolver 未接続）。

**次の担当へ。** 書き出しは実経路として成立した。残る主項目は製品 UI、GPU 処理系エフェクト処理器の第2段以降、合成グループ内部・シーン内部への GPU エフェクト適用（MAC-0027 の未解決事項）である。

#### MAC-0027 — 合成グループの Source 実装（IMPLEMENTED、Mac 検証済み）

**何を実装したか。** MAC-0025 で未実装だった合成グループ（Composite GroupItem）の Source を実装した。合成グループの子は中間画像へ合成され、グループ全体が1つの画像として外側の合成へ渡るようになった。

**どこを変更したか。** `Sources/YMM4GPU/MetalMediaSources.swift` に `MetalCompositeSource` を追加（同ファイルは920行に）。変更: `Sources/YMM4GPU/MetalSources.swift`（MetalSourceProvider に合成グループの分岐を追加）、`Sources/YMM4GPU/MetalRenderTarget.swift`（描画された内容境界の追跡を追加）、`Sources/YMM4GPU/MetalGraphics.swift`（`MetalImage` に `texturePlaneRect` / `planeOffset` を導入）。新規テスト `Tests/YMM4CoreTests/CompositeGroupTests.swift`（5件）。

**どう実装したか。** 本家の意味論は実コードで確認した: 合成グループは `CompositeSource` が自前文脈と内部 `TimelineSource` を持ち、子をタイムライン絶対時刻で中間画像へ合成する。中心は `CompositeCenter` が ImageCenter のとき内部画像の局所境界（内容境界）の中心、それ以外（ScreenCenter・未知値）は (0,0) で、平行移動 −center は DrawingOffset = +center / Center = (0,0) として表される。グループの `GroupEffects` は子へ流れず（親グループ解決は合成グループで打ち切られる）、グループ自身の `VideoEffects` が合成結果全体へ一度だけ適用される。Swift 側の `MetalCompositeSource` は自前文脈を所有し、内部 TimelineComposer（CompositeItemPicker 束縛）が子を絶対時刻で合成する。中心決定のために `MetalRenderTarget` が描画内容の境界（描画された画像の変換後境界と fillRect の和集合）を追跡し、close() 成功時に bounds = 内容境界 / texturePlaneRect = 画面範囲として再登録する。あわせて `MetalImage` に境界とテクスチャ平面範囲を分ける表現（texturePlaneRect / planeOffset）を導入し、出力登録（DrawingEffect・Metal エフェクト処理器・FrameBuffer）でこれらを伝播させた。これは描画先画像のように bounds がテクスチャ実範囲より小さい画像で UV が bounds 基準になり画素対応がずれていた潜在問題の是正でもある。

**本家との差分。** (a) 合成グループ内部の子には GPU 色エフェクトが効かない。内部合成器のエフェクト供給元が既定（TypedEffectPairProvider）のままで、MetalEffectPairProvider は外側の合成にだけ接続されているためである（シーン内部も同じ差分。本家は内部でも GPU エフェクトが効くため可視差分として残る）。(b) 本家の内部合成は無限平面だが、こちらは画面サイズのテクスチャへ折り畳まれるため、画面外にはみ出す子は切り取られる（MAC-0012 以来の台帳差分。境界・中心・UV の意味論は平面モデルに一致させた）。

**メモリ・並行性。** MetalCompositeSource は Scene と同様に自前文脈を所有し、内部 Composer はそれを借用する。内部出力の画像はテクスチャを共有したまま境界と planeOffset をずらして登録し、コピーは作らない。内部出力が無い場合は 1×1 透明を返す。

**検証。** Linux（Swift 6.1.2）で全377件・0失敗（当時。新規 CompositeGroupTests 5件を含む）。Mac 実機ビルド成功・警告0。画素ハーネス15項目全合格: 合成グループの子図形が表示される（被覆10,000px・中心不透明白）、グループ不透明度50%で中心アルファ128（全体へ一度の適用）、グループの Invert で白図形が黒になる（2回適用なら白へ戻るため一度だけの適用を確認）、回転軸が ImageCenter では内容中心・ScreenCenter では原点になること、入れ子の合成グループで孫図形が表示され内側グループの不透明度が二重合成を通して効くこと。回帰確認として MAC-0023（色エフェクト画素検証）と MAC-0025（動画・シーン・フレームバッファ・立ち絵）のハーネスを再実行し全合格だった。本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**未解決事項。** (a) 合成グループ内部・シーン内部の子への GPU 色エフェクト適用（内部合成器への MetalEffectPairProvider 接続）。(b) 画面外にはみ出す子の切り取り（画面サイズへの畳み込み、MAC-0012 以来の差分）。

**次の担当へ。** 描画系の Source は本件で全種別が揃った。残る描画系の主項目は GPU 処理系エフェクト処理器の第2段以降（残り63種）と、内部合成器への GPU エフェクト接続である。

#### MAC-0030 — 書き出しの解析・結果表現の是正（ChatGPT レビュー指摘 EX17-05〜EX17-08 の処分）（IMPLEMENTED）

**何を実装したか。** MAC-0017（書き出しの芯）と MAC-0026（実接続）に対する ChatGPT レビューの指摘4件を処分した。いずれも実コードで照合し、指摘どおりの不整合が存在することを確認してから是正した。(EX17-05) ラウドネス解析の省略が接続側で効いておらず、解析不要の設定でも音声を全区間読み直していた。(EX17-06) 解析が全フレーム分の配列を蓄積し、長時間の書き出しでメモリを圧迫していた。(EX17-07) 両ストリーム無効の書き出しで、成果物が無いのに「出力あり」と報告されていた。(EX17-08) エラーの重大度軸に「対処可能性」と「成否」が混在し、一次的なエンコード失敗が「警告」と表示されうる矛盾があった。あわせて文書の精密化2件（EF18-02、GPU22-05）を本項で反映した。

**どこを変更したか。** `Sources/YMM4Core/Export/LoudnessAnalysis.swift`（解析計画とストリーミング解析の新設、累積器への共有化）、`Sources/YMM4Core/Export/ExportAudioProvider.swift`（計画による判定へ変更）、`Sources/YMM4Core/Export/ExportSession.swift`（ExportError の軸分離、VideoFileWriting への producesOutputFile 追加、ExportOutcome への finalizeSucceeded 追加）、`Sources/YMM4Core/Export/FFmpegProcessWriter.swift`（分類器の軸変更、producesOutputFile の実装）、`Sources/YMM4GPU/MetalExport.swift`（ExportError 生成箇所の追随）、`Apps/DebugApp/Sources/YMM4MacDebug/ProjectView.swift`（書き出し要約の表示追随）。テストは `Tests/YMM4CoreTests/ExportTests.swift` と `Tests/YMM4CoreTests/ExportAudioProviderTests.swift`（新規9件、既存の断言4件を新軸へ更新）。

**どう実装したか。** (EX17-05) `LoudnessAnalysis` に解析計画 `plan(loudness:compressor:)`（Plan: requiresReading / volumeRate / compressorRate）と `skippedResult(for:)` を新設した。`TimelineExportAudioProvider` は音声を読む前に計画を判定し、読み取り不要（Loudness=Disabled かつ Compressor=Disabled、または Disabled かつ Custom）の場合は解析用ミキサー自体を生成せず、倍率だけを確定する。本家 VideoFileWriter.cs L128–141 の分岐（解析ブロックの入口条件と Custom 時の倍率設定のみ）と一致する。(EX17-06) ストリーミング版 `analyze(stream:frameCount:loudness:compressor:hz:fps:)` を追加し、本家どおり固定長の1配列を使い回してフレーム単位でアナライザとピーク測定へ逐次渡すようにした。チャンク列版 `analyze(chunks:...)` との間で最終値の計算がずれないよう、1チャンク分の取り込みと確定計算を私設の Accumulator へ共有化した。`makeChunks` はテスト補助として残置した（全区間の保持は 48kHz ステレオ Float32 で1時間あたり約1.38GB に達していた）。(EX17-07) `VideoFileWriting` に `producesOutputFile`（プロトコル拡張で既定 true）を追加し、`FFmpegProcessWriter` はレイアウトが音声・映像とも `-f null` の場合に false を返す。`ExportOutcome` に `finalizeSucceeded` を新設し、`outputProduced = finalizeSucceeded && writer.producesOutputFile` とした。DebugApp の要約は、成果物が無い完了では出力パスを表示しない。(EX17-08) `ExportError.Severity`（warning / fatal）を廃止し、原因の対処可能性を表す `Cause`（actionable = 特定でき対処可能 / unresolvable = 特定できない・対処不能）へ置き換えた。`FFmpegErrorClassifier` の文言表の一致は actionable になる。付随ファイル生成の失敗など副次的な失敗は、従来どおり `ExportOutcome.warning` へ入れることで表し、その際エラー自体の cause は書き換えない（以前は severity を warning へ書き換えていた）。成否は completion / finalizeSucceeded / outputProduced が担う。

**本家との差分。** 解析の省略条件・倍率の確定方法は本家の分岐どおりで、新たな差分は生じない。解析対象の範囲は従来どおりタイムライン全体であり、本家の EncodeFrom / EncodeTo による部分範囲の解析とは異なる（MAC-0026 以来の既存差分、本件の範囲外）。結果表現（ExportOutcome / ExportError）は Mac 版の内部契約であり、本家に対応物はない。文書の精密化: (EF18-02) MAC-0019 項の「どう実装したか」(1) にあった固定点の保証の表現を、「型付きエフェクト定義の消費経路は既存の生 JSON 保存経路を変更せず、エフェクトの保存結果を新たに正規化しない。プロジェクト全体の固定点は YmmpCodec の検証結果に依存する」という射程へ限定した。(GPU22-05) MAC-0022 項の「本家との差分」へ、Gradient の旧キー転送で Stops が2要素未満の異常な旧ファイルでは本家は失敗しうる（ColorTo の setter が Stops[1] を無条件に参照する）が Swift 側は防御して回避する、という差分を追記した（実コード照合済み: 本家 GradientEffect.cs の ColorTo setter のガードは `Stops.Count >= 0` のみ、Swift 側は `stops.count > 1` を要求する）。

**メモリ・並行性。** 解析パスの保持量は固定長1フレーム分（48kHz / 30fps で 3,200 サンプル）＋アナライザ内部のブロック蓄積のみとなり、書き出し時間に比例しなくなった。Accumulator は値型で、解析は従来どおり初期化時の同期処理である。

**検証。** `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（Linux、Swift 6.1.2）で全410件・0失敗（従来401件＋新規9件）。新規テストの内訳: 解析計画の分岐（ExportTests）、ストリーミング版が計画省略時にストリームを読まないこと（読み取り回数を数えるフェイク）、ストリーミング版とチャンク列版でピーク・LKFS・倍率が一致すること（3設定の組み合わせ）、Provider の初期化で解析不要設定では素材が一切読まれないこと2件と解析あり設定では読まれる対照1件（ExportAudioProviderTests）、finalize 成功＋成果物なしの区別、対処可能な finalize 失敗でも completion が failed になること、FFmpeg の両系統 null で producesOutputFile が false になりプロセスが起動しないこと。既存テストの前提変更は、重大度軸の廃止に伴う断言4件の置き換えのみで、「全区間保持」に依存する期待は無かった（makeChunks のテストは読み方自体の検証であり不変）。Mac 実機でルート＋DebugApp の `swift build` 成功・警告0（UI 追随を含む）。

**未解決事項。** 本件の範囲内では無し。

**次の担当へ。** 書き出し系で残る既知の未解決は MAC-0017 / MAC-0026 由来のもの（EnvelopeFollower の Ratio≠1 波形一致、素材デコードの全体メモリ展開、AVAssetReader のトリム情報、VoiceItem の音声）であり、本件では扱っていない。

#### MAC-0032 — エフェクト編集の書き戻しで入れ子の未知キーが消える問題の修正（UI29-01 の処分）（IMPLEMENTED）

**何を実装したか。** MAC-0029 のプロパティ編集（`EffectPropertyEditing`）で既知エフェクトを編集すると、そのエフェクト内部の入れ子オブジェクトにある未知キーが保存時に消失していた（ChatGPT レビュー第4ラウンドの指摘 UI29-01。処分は `analysis-notes/REVIEW-DISPOSITION-MAC0023-0029.md` で採用確定）。型付きコーデックは `Animation` や `Bezier` 等の入れ子オブジェクトを既知フィールドだけで再構成するため、定義の `additionalFields`（トップレベルの未知キー保持）では守れなかった。データ保全はハード要件のため、編集の書き戻しを「元の生保持を土台に型付きエンコードを重ねる」方式へ改めた。無編集の読み込み・保存では従来どおり生保持のままであり、消失は編集経路に固有だった。

**どこを変更したか。** `Sources/YMM4Core/Effects/VideoEffectRegistry.swift`（未知フィールド保持つき encode の新設）、`Sources/YMM4Core/Editing/EffectPropertyMetadata.swift`（`EffectPropertyEditing.writeBack` が保持つき encode を使うよう変更）。テストは `Tests/YMM4CoreTests/PropertyMetadataTests.swift`（新規3件）。クラス構成に変更はないため ARCHITECTURE は不変。

**どう実装したか。** (1) `VideoEffectRegistry.encode(_:preservingUnknownFieldsOf:)` を新設し、型付きエンコードの結果を元の `PreservedObject` へ重ねる。トップレベルは型付きエンコードの並びとキーを正とする（未知キーは定義の `additionalFields` 経由で既に型付き側へ含まれており、定義が消費したキー — 空にした `Remark`、旧キーからの移行 — は定義側の判断どおり出す・出さないが決まる）。トップレベルで両側にオブジェクトとして存在するフィールドだけ、入れ子マージで元の未知キーを回収する。(2) 入れ子マージは元の並びを土台に再帰する: 共有キーは両側ともオブジェクトなら再帰、それ以外は型付き側で置換する。元だけのキーは保持し、型付き側だけのキーは末尾へ追加する。配列とスカラは型付き側で置換し、配列要素の内部はマージしない。(3) 元の `$type`（型移行の適用後）が定義の型と異なる場合は重ねず、通常の `encode(_:)` の結果を返す（別種エフェクトのフィールドが混入しないための防御）。(4) `writeBack` は3種のアイテム（VisualItem 系譜 / VoiceItem / TransitionItem）とも、対象スロットの現在の要素を元の生保持として保持つき encode へ渡す。通常の `encode(_:)`、読み込み・保存経路、`TypedEffectPairProvider` の消費経路は無変更。

**本家との差分。** 本家は型付きオブジェクトだけを保存する設計であり、未知キーは本家では残らない（読み込みで無視されるか、未知の型自体が失敗する）。こちらはデータ保全方針（本人の確定方針）により編集後も未知キーを保持する意図的な差分であり、既知フィールドの編集結果と保存形式は従来と同一である。ユーザーから見える操作の違いは生じない。

**メモリ・並行性。** 書き戻し時に元の JSON 値とエンコード結果を1回走査する線形処理のみで、追加の保持状態は持たない。同期処理であり並行性の変更はない。

**検証。** 新規テスト3件（`PropertyMetadataTests`）: (a) ZoomEffect のトップレベル／`Animation` 内部／`Bezier` 内部に未知キーを仕込んだプロジェクトを読み込み、IsEnabled の1項目だけを編集すると、書き戻し直後と保存→再読み込み後の両方で未知キーが全階層に残り、編集も反映される。(b) 未知キーを含む `Animation` 自体（Zoom）を編集しても、同じオブジェクト内の未知キーが残る。(c) 無編集の往復が固定点のままである回帰。書き戻しを修正前の通常 encode へ戻すと (a)(b) が入れ子の未知キーの欠落で失敗することを確認済みであり、再現テストとして成立する。全件は `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（Linux、Swift 6.1.2）で全413件・0失敗（従来410件＋新規3件）。Mac 実機ビルドは未実施（変更は Foundation のみの YMM4Core 内で macOS 固有 API を含まず、`writeBack` のシグネチャも不変のため DebugApp 側への影響はない）。

**未解決事項。** (1) 配列要素の内部（例: `Animation` の `Values` 要素オブジェクト内）の未知キーは、配列を型付き側で置換する規則のため編集時に保持されない。オブジェクト階層の未知キーは全て保持される。(2) 旧形式の指令キー `From` / `To` が `Animation` 内にある場合、入れ子マージでは未知キーとして保持される。本家は保存時に書き出さないキーであり、実ファイル2件（upload.ymmp / upload-2.ymmp）では出現数0を確認したため、指令として消費する特別扱いは入れていない。

**次の担当へ。** UI29-01 は本件で解消。レビュー処分の残りは優先順位どおり EX26-01 / CG27-01（MAC-0028 の統合で解消見込み）と QA24-01（測定系の是正と再測定）。

#### MAC-0028 — GPU エフェクト Metal 処理器 第2段と内部合成への供給元伝播、画像／動画の上下反転是正（IMPLEMENTED、Mac 検証済み・統合済み）

**何を実装したか。** MAC-0022 で定義層を揃えた GPU 処理系73種のうち、第1段（MAC-0023）で対象外だった63種について Metal 実処理器の第2段を実装した。あわせて、MAC-0027 の未解決事項だった「合成グループ内部・シーン内部の子への GPU エフェクト適用」（内部合成器のエフェクト供給元が既定のまま）と、ChatGPT レビュー指摘 EX26-01（書き出し側が MetalSourceProvider へタイムラインを渡しておらず、合成グループが書き出しで透明になる。処分は REVIEW-DISPOSITION-MAC0023-0029）を解消する供給元伝播を実装した。さらに、統合検証の過程で main 側の既存バグ（画像・動画のデコードテクスチャの上下反転、MAC-0012 以来）を発見し是正した。実装は分離ツリー `ymm4mac-gpufx2`（MAC-0027 統合直後から分岐）で先行し、本件で検証のうえメインへ統合した（統合番号は実装順の MAC-0028 を使う。台帳への記載は統合時点）。

**どこを変更したか。** 新規 `Sources/YMM4GPU/MetalEffectProcessorsStage2.swift`（1,888行）。`Sources/YMM4GPU/MetalGraphics.swift`（ワープシェーダ mode 0–5、合成パス、モルフォロジーカーネルの追加。モザイクパイプラインの生成位置の移動）。`Sources/YMM4GPU/MetalEffectProcessors.swift`（MetalEffectPairProvider の差し替え分岐へ第2段31種を追加、第1段の GaussianBlur 実装を第2段と共有する形へ再構成、DrawDescription 書き換えフック `modifiedDrawDescription` の導入）。`Sources/YMM4GPU/MetalSources.swift`（MetalSourceProvider への effectProvider 伝播、makePremultipliedTexture の反転除去。相対パス解決は MAC-0031 と同内容の修正を独自に含んでいた）。`Sources/YMM4GPU/MetalExport.swift` と `Apps/DebugApp/Sources/YMM4MacDebug/PreviewBox.swift` は gpufx2 版をそのまま入れず、配線差分（共有 effectProvider の生成と、MetalSourceProvider への `timeline:` / `effectProvider:` の受け渡し）だけを main 版へ手で移した（gpufx2 版は MAC-0030 以前の severity API を使うため現行 Core でコンパイルできず、PreviewBox にはファイル切替修正の deinit dispose が無いため）。YMM4Core とテストは無変更（gpufx2 由来の Core 変更はゼロ）。

**どう実装したか。** (1) 第2段の実処理器31種: Rotate / Skew / CenterPoint / Crop / Margin / CopyAndReverse / Tiling / AutomaticZoom / RoundCorner / BorderBlur / DirectionalBlur / ChromaticAberration / Shadow / FillBackground / FillForeground / FrameLine / Morphology / DrawLazyEffect / Jump / InOutBorderBlur / InOutGaussianBlur / InOutMosaic / InOutMoveFromOutsideImage / InOutGetUp / InOutRotate / InOutSkew / InOutJump / RandomRotate / RandomSkew / RepeatRotate / RepeatSkew。各処理器のパラメータ意味論は本家の逆コンパイル実コード（Player.Video.Effects 配下）で確認したものだけを実装し、式の根拠は各処理器のコメントに記した。数式がコンパイル済みカスタムシェーダ（.cso）の中にしか無いもの、D2D 組み込みで計算式が公開されていないもの、メッシュ描画系、エフェクト内ファイル読み込みが要るものは素通しのまま残した。(2) DrawDescription の書き換え（回転の3D分岐・中心点・自動ズーム・ジャンプ・描画遅延等）は本家でも画像変換とは独立に行われるため、`modifiedDrawDescription` フックとして分離し、入力がプレーンでない素通し経路でもフックは通す構造にした。(3) 供給元伝播: MetalSourceProvider が `effectProvider` を任意引数で受け取り（未設定時は従来どおり TypedEffectPairProvider へフォールバック）、シーン・合成グループの内部合成器生成（sceneComposerFactory / compositeComposerFactory）が子供給元と内部 TimelineComposer の両方へ同じインスタンスを再帰的に伝播する。PreviewBox と MetalExportVideoProvider は MetalEffectPairProvider の単一インスタンスを生成し、外側の TimelineComposer と MetalSourceProvider の両方へ渡す。書き出し側は `timeline:` も渡す。内部合成器が扱うのは子アイテムだけであり、グループ自身のエフェクトは外側のチェーンで一度だけ適用されるため二重適用にはならない。(4) 上下反転の是正: `makePremultipliedTexture` は CGContext のビットマップ文脈へ反転（translateBy / scaleBy）して描いていたが、ビットマップ文脈のメモリは先頭行が画像の上端になるため反転は不要であり、反転して描くとテクスチャが上下逆になっていた。反転を除去し、経緯をコメントに記録した。

**本家との差分。** (a) 素通しのままの32種（ArcBend / BackgroundImage / ChromaKey / ChromaKey2 / CircularDuplicator / Crash / CropByAngle / DisplacementMap / Gradient / HalfTone / HalfToneBorderBlur / HalfToneOutline / HalfToneShadow / HightlightsAndShadows / HlslPixelShaderCode / HlslPixelShaderFile / InOutCrash / InOutTransition / InnerHalfToneShadow / InnerShadow / Mask / MeshDeformation / NoiseColorShift / NoiseDisplacementMap / Noise / Outline / PolarTransform / RadialBlur / RadialLight / RandomDuplicator / Sharpen / Texture）は描画に反映されない（未実装の明示であり、次段の対象）。GPU 階層73種のうち実処理器ありが41種（第1段10＋第2段31）になった。(b) 条件付き素通し: Shadow / FillBackground / FillForeground / FrameLine は単色ブラシ以外（グラデーション等）では素通しになる（ブラシサブシステムが差し替え点）。(c) DirectionalBlur は D2D 内部方式が非公開のため1次元ガウス近似。(d) ChromaticAberration は Strength=100 で拡縮率の下限を追加した（本家との差分としてコードに記録）。(e) 全 Metal 処理器共通の前提として、入力画像が恒等変換でなく不透明度≠1 の場合は素通しになる（MetalEffectProcessor.update のガード。DrawDescription 書き換えフックは通る）。実プロジェクトでの発動頻度は未測定。(f) 中間画像が画面サイズへ折り畳まれている点（MAC-0012 の G12-01..06）により本家の無限平面と差が出うる箇所は、各処理器のコメントに差分として明記した。(g) 上下反転の是正は本家との一致方向への是正であり、新たな差分ではない。従来の main は本家の表示とも一致していなかった。(h) 本人の実プロジェクト（kiminihare.ymmp）の使用量との関係: FillBackground（51件）と Morphology（25件）が本件で新たに描画へ反映されるようになった。使用量最大の2種（StripeGlitchNoise 74件、ColorCorrection 71件）と ColorShift（2件）はコミュニティプラグイン製エフェクトであり、内蔵定義の対象外として生保持のまま描画されない。これは本家でもプラグインが無ければ描画されない挙動と同種であり、本件の未実装ではない。内蔵で使用量が多く残る素通しは Outline（52件）である。

**メモリ・並行性。** エフェクト供給元は生成側（PreviewBox / MetalExportVideoProvider）が MetalEffectPairProvider の単一インスタンスを所有し、内部合成器はそれを借用する（再帰伝播先も同じインスタンス）。処理器の中間テクスチャは第1段と同じ所有規則（文脈の描画先を経由し、close() の同期完了で解放可能になる）で、新規の所有関係は生じない。MetalSourceProvider の追加引数は既定 nil のため、既存の呼び出し側の生成・解放順序は変わらない。

**検証。** `~/workspace/tools/swift-6.1.2/usr/bin/swift test`（Linux、Swift 6.1.2）で全413件・0失敗。件数が従来の410件から3件増えているのは、統合用コピーの取得時点でメインクローン側に並行タスク（UI29-01）のテスト追加が入っていたためで、本件による Core・テストの変更はゼロである。Mac 実機（検証コピー ~/verify-integrate/YMM4Mac、ローカルツリーと md5 一致を確認）でルート＋DebugApp の `swift build` 成功、GPU 全ソースと PreviewBox の強制再コンパイルで警告0。画素ハーネス（~/mac0028-harness）: 90 PASS / 0 FAIL（第2段31種の解析的検証＝回転・傾斜・切り抜き・影・塗り・モルフォロジーの膨張／収縮・イン／アウト系・ランダム系の実角度照合等、伝播2件＝シーン内部・グループ内部の子への Invert 適用、向き回帰1件＝四象限画像で左上が赤・左下が青）。回帰ハーネスを統合ツリーへ向け替えて再実行: mac0023 = 25 PASS / 0 FAIL、mac0025 = 18 PASS / 0 FAIL、mac0027 = 15 PASS / 0 FAIL（いずれも統合前と同件数）。mac0031（実ファイル upload.ymmp の frame 2810）は、分割テキストの各ピースが完全なグリフ形状であること（段階 (a) の形状プロファイルが MAC-0031 是正後と同等）を確認した。合成全体の数値プロファイルは、FillBackground 処理器が有効化されたことで MAC-0031 記録時（32,123px・高さ96px）から変わり、背景塗りを含む 165,763px・高さ137px になった（退行ではなく第2段の有効化による差）。書き出し伝播の専用ハーネス（~/mac0028-export-harness、MetalExportVideoProvider の借用バッファを直接読む）を新設し全6項目合格: 合成グループの子が書き出しフレームに現れる（被覆10,000px・中心が不透明な白）、グループ内部の子の Invert が書き出しでも効く（中心が黒）、子なしグループは書き出しで何も描かない（対照）。これにより EX26-01 の解消はコード確認だけでなく書き出し実フレームの画素でも裏付けた。上下反転については、gpufx2 側のプローブに加え、main 側コード（本人の Mac の ~/ymm4mac）へ同じ四象限画像を合成する独立プローブでも出力が完全に上下反転していることを確認した（左上に本来の左下の青）。本家実機との比較試験は未実施のため IMPLEMENTED 止まり（画素の期待値はシェーダ式からの解析値であり、本家 Direct2D 出力との画素一致は主張しない）。

**未解決事項。** (a) 素通し32種の実処理器化（上記 (a)）。(b) プレーン前提ガード（差分 (e)）の実プロジェクトでの発動頻度が未測定で、エフェクトの重ね方によっては実装済みの効果が効かない場面がありうる。(c) 本家との画素一致（Golden Master は本家環境が無いため到達不可）。(d) 非矩形モザイクの素通しとモザイクサイズのアニメーション評価の未完（レビュー指摘 GPU23-01 / GPU23-02）は本件でも未対応のまま。(e) ブラシサブシステム（単色以外のブラシ）の実物化。

**次の担当へ。** 描画系で残る主項目は素通し32種の処理器化である。使用量の観点では Outline（実プロジェクトで52件）が最大だが、輪郭生成の方式確定が前提になる。HLSL カスタムシェーダ2種は実行基盤の判断が要る。あわせて、プレーン前提ガードの発動頻度を実プロジェクトで測ることが、実装済み効果の実効範囲を確定するうえで必要である。

#### MAC-0033 — GPU テクスチャ確保失敗のエラー伝播統一（GPU28-03 の処分）（IMPLEMENTED、Mac 検証済み）

**何を実装したか。** ChatGPT レビュー第5ラウンドの指摘 GPU28-03（処分は `analysis-notes/REVIEW-DISPOSITION-MAC0028-FRONTEND.md` で採用確定）: GPU エフェクト処理器のテクスチャ確保失敗が、確保ヘルパーの nil 戻りとして伝播し、基底処理器の `update` が入力をそのまま出力として公開していた。同じファイル内でもコマンドバッファ失敗は `MetalRenderError` を throw しており、MAC-0021 で入れた描画先の失敗通知契約とも不統一で、確保失敗だけが無言の素通しになっていた。確保失敗を「効果なしの素通し」と区別し、エラーとして伝播させるよう統一した。

**どこを変更したか。** `Sources/YMM4GPU/MetalEffectProcessors.swift`（基底ヘルパー群と `makeTexture`）、`Sources/YMM4GPU/MetalEffectProcessorsStage2.swift`（第2段の呼び出し側と2つの描画ヘルパー）。YMM4Core・テスト・公開 API は無変更。クラス構成に変更はないため ARCHITECTURE は不変。

**どう実装したか。** 契約の形は実コードで判断した: Core の `VideoEffectProcessor.update` は元々 throws であり（`Sources/YMM4Core/Rendering/EffectedItemSource.swift`。失敗時は例外を投げる契約で、連鎖側は DrawingEffect の失敗だけを包み処理器の失敗は伝播のみ）、基底 `MetalEffectProcessor.update` も `try render(...)` で呼んでいたため、プロトコル変更なしに直接 throw へ統一できた。失敗を画像／文脈側に記録して次の close() で送出する代替形（MAC-0021 の描画先方式）は、処理器には close() 相当の確定点が無く、失敗をその場で連鎖の呼び出し側へ伝播させる方が第4章の意味論に合うため採らなかった。(1) `makeTexture` を throw 化し、デバイスの確保失敗で既存ケース `MetalRenderError.textureCreationFailed(width:height:)`（MAC-0021 で新設済み）を投げる。(2) 確保失敗が nil の唯一の意味だった基底ヘルパ8種（renderColorEffect / renderGaussianBlurred / renderDirectionalBlurred / renderRectangleMosaic / renderTransformed / renderWarp / renderComposite / renderMorphology）は戻りを非 Optional へ変更し、内部の `guard let … else { return nil }` を通常の let へ置き換えた。空境界で透明画像を返す経路（renderTransformed 等）と、σ≤0 や寸法1以下で入力を返す経路は従来どおり。(3) 第2段の呼び出し側で、非 Optional 化したヘルパを受ける `guard let … else { return nil }` 7箇所（RoundCorner / BorderBlur / InOutBorderBlur のマスク、Shadow の3段、FillForeground のマスク、DrawLazyEffect の変換）を通常の let へ置き換えた。(4) 自前でデバイス確保する2ヘルパー（`renderRoundedRectFill` と FrameLine の `renderSolidRects`）は、nil を「出力境界が空＝描くものが無い正当な無処理」だけに限定し、テクスチャ確保失敗は textureCreationFailed、コマンドバッファ／エンコーダ生成失敗は commandBufferFailed を投げるよう分離した。(5) 基底 `render` の契約コメントに「nil を返してよいのは効果なしが正当な場合だけであり、資源失敗は MetalRenderError を投げる」ことを明記した。基底 `update` の nil → 入力登録のフォールバック自体は、正当な無処理を返す将来の処理器のための契約として残置した。

**本家との差分。** 本家には対応する失敗通知経路が無く、これは MAC-0021 と同じく Swift 側の契約追加である（本家の失敗挙動の再現ではない）。正常経路の描画結果は無変更であり、ユーザーから見える違いは生じない。失敗時に不完全な画像が正常な出力として公開されなくなる点だけが変わる。

**変更しなかった素通し（既知制限のまま）。** プレーン前提ガード（GPU28-01: 入力が恒等変換でなく不透明度≠1 のとき基底 update が入力を素通しする。DrawDescription フックは通る）、単色ブラシ以外での Shadow / FillBackground / FillForeground / FrameLine の素通し（GPU28-02、ブラシサブシステムが差し替え点）、非矩形モザイクの素通し（GPU23-01）。残存する nil 戻りは、値のパース（parseARGBColor、モザイクのパラメータ抽出）と空境界の無処理だけであることを grep で全数監査した。

**メモリ・並行性。** 所有関係・解放順序の変更はない。throw した時点でその段の中間テクスチャは解放され（ARC）、連鎖の後段は実行されない。同期実行の構造も無変更。

**検証。** Linux: `~/workspace/tools/swift-6.1.2/usr/bin/swift test` で全414件・0失敗（本件の変更は macOS 限定ファイルのみで Core・テストは無変更。実行は並行タスクのテスト実行と VM を共有し約26分を要した）。Mac 実機（検証コピー ~/verify-gpu28-03/YMM4Mac）: ルートパッケージの `swift build` 成功、変更2ファイルの強制再コンパイルで警告0。画素ハーネスを同コピーへ向け替えて再実行: mac0023 = 25 PASS / 0 FAIL、mac0028 = 90 PASS / 0 FAIL（いずれも従来どおり全合格で退行なし）。確保失敗の実行時模擬として専用ハーネスを新設した（本人の Mac の ~/mac0033-harness、正本は `~/workspace/ymm4-work/mac0033-harness/`）: 回転処理器へ DrawDescription の Zoom = 100000 を与え、出力テクスチャ寸法を約905万 px（2D 上限16384 超）にして確保を決定的に失敗させる設計で、対照2件（通常拡縮で更新成功・出力公開）は PASS。ただし失敗ケース自体の実行は、この Mac（macOS 26）では上限超えディスクリプタが makeTexture の nil 戻りより前に Metal のディスクリプタ検証アサーションでプロセスが abort するため成立しなかった（アサーション出力に要求寸法 9050967 が記録され、exit 134。MTL_DEBUG_LAYER=0 / METAL_DEVICE_WRAPPER_TYPE=0 でも回避不可）。寸法経路で nil 戻りを決定的に再現する手段が無いため、失敗ケース3件は環境変数 MAC0033_RUN_FAILURE_CASE=1 のときだけ実行する SKIP 表示とし、throw 経路の担保はコード監査（確保箇所は全て throw する makeTexture 経由か明示 throw）に拠る。メモリ枯渇による再現は本人の実機を不安定化させるため採らなかった。アサーション出力の要求寸法は、要求が素通しされずデバイスへ実際に到達した傍証にはなる。

**未解決事項。** (1) 確保失敗の throw を実行時に観測する検証は上記の環境制約で未実施（コード監査で代替）。実運用で nil が返るのはメモリ圧迫時等であり、その経路は本件の throw 化で初めて通知されるようになった。(2) DebugApp パッケージは ProjectView.swift の `Color` 型曖昧性エラーでビルド失敗するが、本件と無関係なフロントエンド側の既存状態（本件の変更に公開 API の変更はない）。（追記 2026-11-17: この失敗は並行作業の検証コピーがフロントエンド編集中間状態を拾った際の観測であり、現行ツリーではクリーン検証（~/verify-clean）でルート＋DebugApp ともビルド成功・警告0を確認済み。全体監査 AUD-05 の分離記録として、現行状態の正本は STATUS / HANDOFF とする。）

**次の担当へ。** GPU28-03 は本件で解消。第5ラウンド処分の残りは UI32-01（レベルメーターの L/R 2本化、フロントエンド側）と QA24-01 の比較試験（掃引＋窓長 48/64/96 比較）。GPU28-01 / 02 は既知制限として継続。

#### PR32 — DebugApp フロントエンドの形（本家ワークスペースの再現）（IMPLEMENTED、Mac 検証済み）

**何を実装したか。** 本人の指示（2026-11-17）「フロントエンドの最優先は、まともに使えて欠陥も機能不全もない本家同様のデザイン。バックエンドと接続していなくてもいいから形だけでも先に仕上げろ」を受け、DebugApp の殻を本家 YMM4 のメインウィンドウの形へ作り替えた。設計の源泉は本家の逆コンパイル実コードの解析（解析側 `analysis-notes/UI-LAYOUT-FACTS.md` 第1部＝配置、第2部 §10–16＝意味論）と公開資料の照合（同 `UI-WEB-REFERENCE-CHECK.md`）であり、本人が示した本家スクリーンショットは検証用の正解としてのみ使った。本家との差分と未接続箇所の台帳は解析側 `analysis-notes/UI-FRONTEND-DIFF.md` が正本。本項は PR #32 のマージ（2026-11-17、main = 85759543）時点で台帳転記が漏れていたものを、全体監査 AUD-05（A-5(2)）の指摘で追記したものである。

**どこを変更したか。** `Apps/DebugApp/`（`ContentView.swift` / `ProjectView.swift` / `PreviewBox.swift` / `YMM4MacDebugApp.swift` ほか）。PR #32 としてマージ済み。YMM4Core / YMM4GPU の変更はない（プレビュー選択・移動は既存の記述子経路と合成経路を使う）。

**どう実装したか。** (1) メニューバーを App の `.commands` で構築した（ファイル／編集／レイアウト／ツール／ヘルプの5系統。新規 Cmd+N・開く Cmd+O・プロジェクトのコピーを保存 Cmd+S・動画の設定・動画出力・バージョン情報は実動し、その他は押せるスタブ）。(2) 起動はファイル選択でゲートせず、新規の空プロジェクト（1920×1080 / 60 FPS / 48,000 Hz＝本家の新規既定）で全パネルが揃ったワークスペースへ直接入る形にした（`WorkspaceState`）。あわせて、ファイル切替時に旧プロジェクトの表示が残る不具合を `ContentView` の `@State loadSequence` と `.id(loadSequence)` で修正し、`PreviewBox` に `deinit { dispose() }` を追加した。(3) トランスポートは全要素を構築した（再生／一時停止・停止・速度コンボ x0.25–x8.0（x1.0 以外は赤字太字＝本家規則）・リピート・コントロールポイント表示・倍率コンボ・フィット・シーク一式・位置スライダ・音量スライダ＋%表示・ミュート）。シーク系と表示倍率は実動し、実時間再生は未接続（ボタンの押下と状態表示のみ）。(4) シーン切替はタイムライン領域上部のタブ列とし（切替は実動）、ヘッダー帯の Picker は廃止した。(5) タイムライン帯はツールバー行、本家色の本体（目盛り・4px のキーフレーム帯・赤い再生ヘッド）、ステータスバー（時刻／フレームを入力欄として確定時にシーク、映像情報ボタンは「動画の設定」を開く。本家に無い Hz 表示とアイテム件数は除去）を備える。波形は決定的な疑似波形で形を作り（実波形は音声デコード接続後）、レイヤーラベルの表示切替・名前変更・背景色は Core の `LayerSetting` へ実書き込みし、レイヤー追加／削除はスタブ、レイヤー全体の音量は保持先が Core に無いためローカル状態のみ。(6) セリフ入力行はキャラクター選択＋設定ボタン＋プレースホルダ「ここにセリフを入力」＋追加ボタン（空テキストでは無効＝本家規則）で、入力と選択は実動し、VoiceItem の生成は未接続。(7) プレビューはクリック選択とドラッグ移動を実装した（レターボックス補正つき逆変換でヒットテストし、重なり優先は本家の描画順序＝最後が最前面。ドラッグは記述子経路で X/Y へ書き込む）。選択ハンドル（四隅 ▢＝拡大率、辺中点 ◯＝回転角）は表示のみでドラッグは未接続。ヒットテストの境界は近似である（中心は評価済み X/Y、寸法は種別ごとの代替値、回転は無視）。(8) ダイアログは「動画の設定」（`Timeline.videoInfo` へ実書き込み、`VideoInfo` の Range でクランプ）と「動画出力」（既存の書き出し実行へ接続。正規化／コンプレッサの選択は形のみ）。(9) 右ペインの見出しは「アイテム」、未選択時は「アイテムが選択されていません」とし、インスペクタは MAC-0029 のメタデータ駆動生成を使う。(10) ウィンドウは `.defaultSize(1600×1000)` ＋ `.windowResizability(.contentMinSize)`、ルートに `minWidth: 1100 / minHeight: 700` を置き、標準の Mac アプリとしてリサイズできる形にした（`fixedSize` と ideal サイズ指定は grep 監査で 0 件）。

**本家との差分。** 形の差分は UI32-01（次項）で解消したレベルメーターを除き、UI-FRONTEND-DIFF の照合で本家形に一致させた。残る差は接続の欠落であり、形の差ではない: 実時間再生（音声クロック同期を含む）、セリフ入力からの VoiceItem 生成、選択ハンドルのドラッグ、タイムライン帯のドラッグ編集（移動・端トリム・分割等は Core に操作が存在するが UI 未接続）、レイヤー追加／削除、実波形、ショートカット（Cmd+N/O/S のみで本家の既定69件は未実装）。ドッキング（AvalonDock）の再現はしていない（レビュー指摘 UI32-02。DebugApp は検証用の殻で UI 技術は要件 §11 未決定のため、製品 UI 設計時の構造メモとして保留）。下部のデバッグタブ（書き出し／読み込み診断／往復チェック）とヘッダー帯は本家に無い殻側の追加である。

**メモリ・並行性。** フロントエンドの状態は SwiftUI の `@State` に閉じ、合成・書き出しの所有関係は従来の経路（PreviewBox / MetalExport）のままで新規の所有関係は生じない。

**検証。** Mac 実機（検証コピー）でルート＋DebugApp のビルド成功・警告0。インスペクタの統合検証は専用ハーネス M2 で 17 PASS / 0 FAIL（実アプリ階層＋実ファイル kiminihare.ymmp の TextItem で、数値欄の入力・フォーカス離脱での確定・スライダの即時反映をモデルへの書き込みまで確認）。形の完成条件チェックは UI-FRONTEND-DIFF の8項目中、インスペクタ統合を除く7項目が作業完了時点で合格し、残る1項目は M2 で合格した。本人の Mac へはマイルストーン完了時に1回だけ同期・再起動して引き渡した。画面の目視確認と物理マウス／キーボードの経路はヘッドレスでは到達できない（合成マウスイベントは SwiftUI のジェスチャへ届かないことを実測済み）ため、本人の実機確認待ちである。

**未解決事項。** 上記の未接続群（接続フェーズの作業）。タイムラインキャンバスのプラットフォームビュー配置に関する M2 の所見（階層位置の異常値）は SSH からは判定できず、目視確認待ち。

**次の担当へ。** 接続フェーズの入口は UI-FRONTEND-DIFF の接続台帳。実時間再生は本家意味論（音声がマスタークロック、33ms ポーリング、UI-LAYOUT-FACTS §12）が前提。

#### UI32-01 — レベルメーターの本家構成化と誤記修正（IMPLEMENTED、Mac 検証済み）

**何を実装したか。** ChatGPT レビュー第5ラウンドの指摘 UI32-01（処分は解析側 `analysis-notes/REVIEW-DISPOSITION-MAC0028-FRONTEND.md` で採用確定）: PR #32 のレベルメーターは単一バー1本だったが、本家はピークメーターが L/R ステレオ対の2本、ラウドネスメーターが別カラムの1本という構成である（処分時に本家 TimelineView.xaml と SoundLevelMeter / YMMSettings を実コードで確定。こちらの従来記録はグリッド数をバーの本数と取り違えていた）。メーター帯を本家構成へ作り替え、あわせて誤記1件を修正した。

**どこを変更したか。** `Apps/DebugApp/Sources/YMM4MacDebug/ProjectView.swift`（`levelMeters` の置き換え）、`Apps/DebugApp/Sources/YMM4MacDebug/YMM4MacDebugApp.swift`（誤記）。解析側 `UI-LAYOUT-FACTS.md` の §5.1 と §16 のメーター記述も確定構成へ訂正した。

**どう実装したか。** (1) ピークメーターは L/R 2本の縦バー（各幅10）で既定表示。ラウドネスメーターは独立カラム1本（幅20＝本家グリッド幅）で、`isLoudnessMeterEnabled`（既定 false＝本家 `LoudnessMeterSettings` の生成引数どおり）のときだけ左側へ追加表示する。表示切替は本家どおりメーター帯のコンテキストメニューに2つのトグル（ピーク／ラウドネス）を置いた（本家 TimelineView の TogglePeakMeterVisibility / ToggleLoudnessMeterVisibility に対応）。(2) 各バーは本家 VerticalLevelMeter の構造で再構成した: 背景の色帯（赤 #D50000 / 黄 #FFC400 / 緑 #4CAF50 / 灰 #546E7A、不透明度0.2）、Peak バー（同帯を Peak 位置でクランプ、不透明度0.6）、0 dB 超過時の赤オーバーレイ、Average（RMS）の黒線、PeakHold 線（属する帯の色）。範囲は 0〜−60 dB の線形。色帯の区切りは本家設定の既定値どおり（ピーク側＝ SoundLevelMeterSettings 既定: 赤 0…−3 / 黄 −3…−35 / 緑 −5…−15。ラウドネス側＝ YMMSettings の生成引数: 赤 0…−12 / 黄 −12…−45 / 緑 −14…−25）。(3) 付随要素として、右上に単位表記（ピーク側 "dB" / ラウドネス側 "LKFS"）、5 dB ごとの目盛り刻み、ホバー時の目盛り数値（−5…−60）のオーバーレイ、ツールチップ（本家の書式 "L: -∞ dB / R: -∞ dB" / "-∞ LUFS"）を備えた。(4) 呼び出し側の固定幅 `.frame(width: 24)` は撤去し、カラム幅は内容駆動にした。(5) 誤記: `YMM4MacDebugApp.swift` L105 の「シーインタブを常に表示」を「シーンタブを常に表示」へ修正した。(6) 実装上の注意として、`Color` が `YMM4Core.Color` と曖昧になる箇所はこのファイル群の慣例どおり `SwiftUI.Color` と明示した。

**本家との差分。** 形は本家構成に一致させた。値は未接続である（音声レベルの供給は再生接続フェーズの作業で、無信号時は下限 −60 dB 固定）。静止状態の見た目は本家の無信号状態（背景の色帯が見える形）に合わせてあり、欠陥には見えない。

**メモリ・並行性。** 表示状態（有効フラグとホバー）を持つだけの変更で、所有関係の変更はない。

**検証。** Mac 実機（検証コピー ~/verify-frontend/YMM4Mac、MD5 一致を確認）でルート＋DebugApp のビルド成功・警告0（変更2ファイルを強制再コンパイルして確認）。寸法はコード計算で確認した: 高さは不変（メーター列は右カラムの行高合計 317pt の範囲内）。幅は従来の固定24pt に対して既定時20pt、ラウドネス有効時40pt で、隣接カラムが吸収し、最小ウィンドウ幅1100でもタイムライン帯は約658pt を確保できる。画面の目視確認は未実施（SSH からスクリーンショット不可）。特にホバー時の目盛り数値オーバーレイの見え方は次回引き渡し時の実機確認待ち。

**未解決事項。** メーターへの実レベル供給（再生接続と一体）。目視確認。

**次の担当へ。** UI32-01 は本件で解消。第5ラウンド処分の残りは QA24-01 の比較試験のみ（GPU28-03 は MAC-0033 で解消済み）。MAC32-01 は将来条件として処分ファイルに記録済み。


#### MAC-0034 — 書き出しのモデル共有によるデータ競合の解消（AUD-07）（IMPLEMENTED、Mac 検証済み）

**何を実装したか。** ChatGPT 最終QAレビューで新規 P1 として確定した AUD-07（処分は解析側 `analysis-notes/REVIEW-DISPOSITION-AUDIT.md` で採用確定）の修正。`ExportJob`（DebugApp）が編集中の Timeline と `project.timelines` を直接保持し、`Task.detached` の書き出しが開始時に長さと動画設定を読み、全フレームを通じて同じオブジェクト群を生で読み続けていた。UI 側の変更経路（レイヤー設定の下付き代入と append、デスクリプタ経由のアイテム値、動画設定の差し替え、アイテム配列の追加・削除）は書き出し中も有効であり、出力への編集混入にとどまらず配列の並行変更によるクラッシュを起こしえた。`ExportJob` の doc コメントは「ジョブは生成後に単一のバックグラウンドスレッドからのみ触れる」ことを安全性の根拠としていたが、前提が誤っていた（ジョブ自体ではなく、ジョブが保持するモデルオブジェクトが UI と共有されていた）。

**どこを変更したか。** `Sources/YMM4Core/YmmpCodec.swift`（`Project.makeExportSnapshot(of:)` の新設と `YmmpError.timelineNotInProject` の追加）、`Apps/DebugApp/Sources/YMM4MacDebug/ProjectView.swift`（`runExport` がスナップショットを構築してジョブへ渡す形へ変更、`ExportJob` の doc コメントを実態へ是正）、`Tests/YMM4CoreTests/ExportSnapshotTests.swift`（新規3件）。作業は分離ツリー `ymm4mac-exportsnap` で実施し、本項は統合時の転記である。

**どう実装したか。** (1) 書き出し開始時（`runExport`、UI スレッド上）で `project.makeExportSnapshot(of: timeline)` を呼び、プロジェクト全体を YmmpCodec でエンコード→デコードしてジョブ専有のインスタンス群を作る。対象は `timelines` 全体（SceneItem の解決が他タイムラインを引くため対象タイムラインだけでは不十分）。キャラクター参照はデコード時にスナップショット内のキャラクターへ張り直され、アイテム側の参照がスナップショット内のインスタンスを保持するため、ジョブが保持する timelines だけでスナップショット全体が生存する。(2) 対象タイムラインの対応付けは同一性（`===`）のインデックスで行い、返る timeline はスナップショット側 timelines の同一要素である（内部合成の同一性前提を保つ）。(3) スナップショットを構築できない場合は、編集中のモデルを共有する形へフォールバックせず、状態欄へ理由を表示して書き出し自体を中止する。(4) 進捗の総フレーム数はスナップショット側の長さから取る。(5) `ExportJob` の doc コメントは、安全性の根拠を「保持するモデルがジョブ専有のスナップショットであり編集中のプロジェクトとインスタンスを共有しない」ことへ是正した。UI の全面無効化は行っていない（応急処置に留まるため）。

**なぜその実装なのか。** 手書きの深い複製はフィールドの写し漏れ（MAC-0032 が防いだ類の欠陥）と未知フィールドの生保持（PreservedObject）の複製仕様の二重管理を招く。固定点が検証済みの既存コーデック往復を使えば、写し漏れを構造的に避けられる。コストは書き出し開始時の1回の符号化・復号のみで、実ファイル規模（〜780KB）では書き出し全体の時間に対して無視できる。

**本家との差分。** 本家の書き出しは WPF の単一 UI スレッドモデルを前提としており、対応する競合自体が存在しない。こちらは内部の並行性の修正であり、ユーザーから見える差は「書き出し結果は開始時点のプロジェクト状態で確定し、書き出し中の編集は出力へ混入しない」という点だけである。書き出し結果の意味論（範囲・設定・解析）は無変更。UI を無効化しないため、書き出し中も編集は継続できる。

**メモリ・並行性。** スナップショットの所有者はジョブのみで、解放はジョブの終了時。書き出しセッション（TimelineExporter 以下）はスナップショットだけを読む。`ExportJob` の `@unchecked Sendable` は、専有スナップショットの存在によって初めて前提が成立する形になった。ARCHITECTURE はクラス構成の変更がないため不変（対象は既存コーデックへの API 追加とアプリ層の受け渡しのみ）。

**検証。** 新規 `ExportSnapshotTests` 3件（生成時点の内容一致＝タイムライン単位の符号化が元と同一・参照がスナップショット内へ解決されること、生成後の元モデル変更＝アイテム値・動画設定の差し替え・アイテム配列の追加と削除・レイヤー設定の下付き代入と追加・キャラクター改名・他タイムライン改名が書き出し側の値へ一切漏れないこと、プロジェクト外タイムラインの拒否）。Linux 全件テストは全417件・0失敗（従来414件＋3件）。Mac 実機（検証コピー ~/verify-exportsnap/YMM4Mac）でルート＋DebugApp のビルド成功・警告0。既存の書き出し検証（スタブハーネス mac0026、同コピーへ向け替えて実行）は全項目合格（19 PASS / 0 FAIL、ALL PASS。ピーク −6.0206 dB・映像 stdin 138,240 バイト・Y プレーン一致・ffmpeg 起動3回は MAC-0026 の基準値と同一）。なお同ハーネスの stub.log は追記式のため、同一作業ディレクトリへの再実行では起動回数チェックが偽陽性で失敗する（新規ディレクトリでは全合格を確認済み。ハーネス側の性質であり本件の退行ではない）。

**未解決事項。** 実際の競合そのもの（書き出し実行中の実編集）はヘッドレスでは再現検証できない。担保はスナップショットの独立性を固定したテストと、ジョブがスナップショット以外へ到達しないことのコード監査に拠る。実機で書き出し中に編集しても出力が開始時点の状態で確定することは、本人の実機確認待ち。

**次の担当へ。** AUD-07 は本件で解消。監査の残作業は AUD-01〜04・06（STATUS の監査セクション）。

**統合。** 本項の変更は統合 PR でメインへ反映済み（確定番号はツリー側の MAC-0034 を据え置き）。統合後の検証（Linux 全件・Mac ビルド・ハーネス再実行・実ファイル往復）は STATUS を参照。統合後の最終実測として、Mac 実機で `swift test --parallel` 全432件・0失敗を確認した（内訳の突合: 従来414件＋本項3件＋MAC-0035 の1件＋MAC-0036 の12件＋MAC-0037 の差分2件＝432件）。


#### MAC-0035 — EffectItem 描画 Source（AUD-01）とクリッピング実効マスク（AUD-03）（IMPLEMENTED、Mac 検証済み）

**何を実装したか。** 全体監査（解析側 `analysis-notes/AUDIT-2026-11-17-FULL.md`、処分は `REVIEW-DISPOSITION-AUDIT.md` で全件採用確定）の AUD-01 と AUD-03 を解消した。AUD-01: `MetalSourceProvider.source(for:)` に EffectItem の分岐が無く空 Source（透明）になっていたため、本家 EffectSource（FrameBufferSource のサブクラス）相当の Source を実装し、蓄積画像へ図形マスクを適用する描画までを通した。AUD-03: Core 合成器が `setAlphaMask` まで配線済みだったクリッピング（IsClippingWithObjectAbove）について、`AlphaMaskEffectFactory` の本番（Metal）実装を作り、プレビュー・書き出し・シーン・複合グループの全生成経路で注入した。あわせて処分の付帯確定事項 B-1（EffectSource の基底コンストラクタへ FrameBufferItem として null を渡す特殊性）と B-2（白 Flood の実体 (i) と、マスク入力が描画段で後から設定される順序 (ii)）を再現した。実装は分離ツリー `ymm4mac-effectsrc` で行い、本項は統合 PR でメインへ反映された（ツリー側では MAC-0034 と記録していたが、確定番号は MAC-0035）。

**どこを変更したか。** 新規 `Sources/YMM4GPU/MetalEffectSources.swift`（MetalEffectSource と MetalEffectItemDrawingEffect）と `Sources/YMM4GPU/MetalAlphaMask.swift`（MetalAlphaMaskEffect と MetalAlphaMaskEffectFactory）。変更: `Sources/YMM4GPU/MetalMediaSources.swift`（MetalFrameBufferSource を共通基底クラスへ分離）、`Sources/YMM4GPU/MetalSources.swift`（EffectItem 分岐の追加、図形ラスタライズの静的ヘルパー公開、内部合成器工場への factory 伝播）、`Sources/YMM4GPU/MetalGraphics.swift`（ワープシェーダへ mode 6＝調整済みマスクによる切り抜きを追加）、`Sources/YMM4GPU/MetalExport.swift` と `Apps/DebugApp/Sources/YMM4MacDebug/PreviewBox.swift`（TimelineComposer へ factory を注入）、`Sources/YMM4Core/Items/CompositeItems.swift`（EffectItem へ型付き `Blur` を追加）、`Tests/YMM4CoreTests/YmmpCodecTests.swift`（Blur の往復テスト1件）。文書: 本項、STATUS（冒頭・大きな表・監査セクション・優先課題）、HANDOFF、ARCHITECTURE（ファイル構成と描画（GPU 実行）の記述）。

**どう実装したか。** (1) FrameBuffer の分離: 本家 EffectSource は FrameBufferSource のサブクラスだが、基底コンストラクタへ FrameBufferItem として null を渡す（EffectSource.cs）。null の場合の意味論は ClearBackground=false、背景 Flood は不透明な黒（0,0,0,1）、切り抜き境界は入力境界の拡張なし（±画面サイズ/2 ちょうど）である。従来の `MetalFrameBufferSource` は実アイテム前提の値（ClearBackground 等）を保持値から読んでいたため、そのまま転用すると意味論がずれる。そこで共通部（Flood→SourceOver→Crop の実体化、入力の所有権、出力の登録）を `MetalFrameBufferSourceBase` へ分離し、意味論の差分3点（`behaviorClearBackground` / `floodIsTransparent` / `expandsBoundsToInput`）をフックとして基底の既定値を全て null 時の意味論に置いた。実アイテム側は薄いサブクラスが保持値でフックを上書きし、公開 API（型名・初期化子）は不変。`MetalEffectSource` は基底をそのまま使い、描画効果だけを差し替える。(2) マスク描画効果: 本家 EffectItemDrawingEffect は原始 Mask のラッパであり、その処理列は「図形画像 → Crop → Transform3D（Rz·Ry(−符号)·Rx(−符号)·平行移動·カメラ·透視 M34=−0.001。ズームなし）→ 透明 Flood への合成 → Crop（境界は反転時＝入力画像の局所境界、それ以外＝変換後マスクの境界）→ GaussianBlur（σ=Blur、Soft 境界）→ 色行列による α 反転（反転時）→ 色行列による不透明度 → D2D AlphaMask（入力0=本体、入力1=処理済みマスク）」である。これを既存の Metal ヘルパー（renderTransformed / renderGaussianBlurred / renderWarp）の組み合わせで再現し、最後の AlphaMask はワープシェーダの mode 6（調整済みマスク α で入力を切り抜く）として追加した。不透明度は DrawDescription.Opacity × フェード係数であり、フェード係数は本家が EffectDescription のアイテム局所位置・長さから再計算するため、CreateDrawDescription で適用済みのフェードが二重に効く。本家の実挙動であるため再現し、「修正」はしていない。図形画像は MetalShapeSource のラスタライズを静的ヘルパーとして切り出して再利用し、RenderKey でキャッシュする。平面分割の幾何（PlaneSplitGeometryProviding）は本家 Mask の IBoundsQuadProvider（マスク画像の局所境界 × 透視込みの全行列）に倣った。(3) クリッピングマスク: `MetalAlphaMaskEffect` は出力参照を固定で返し、入力が設定されるたびに出力実体を作り直して登録し直す。本家は効果グラフの遅延評価により、出力が公開された後（描画段）で SetAlphaMask されても最終描画へ反映される（B-2(ii)）。こちらは消費者が描画時に登録表を引く構造のため、再実体化による登録の差し替えで同じ意味論になる。実体化は warp mode 3（素のアルファマスク、平面座標サンプリング）。入力0未設定なら出力を登録解除、入力1未設定なら透明を登録（D2D の未設定入力の扱いに対応）。(4) 白 Flood（B-2(i)）: 先行画像が無い場合に合成器が渡す "flood" トークンは、本家 TimelineSource がコンストラクタで作る不透明な白の Flood 出力に対応する。全面不透明なマスクによる AlphaMask は恒等変換（出力＝入力）であるため、本体画像をそのまま出力として登録して解決した。当初は 1×1 の白テクスチャを実体として warp で読む形を実装したが、border サンプラでは線形フィルタの足跡が境界色（透明黒）と混ざり全面が減衰した（64×64 画面の隅で α≈74/255 を実測）。clampToEdge への切替は、図形マスク側で縁テクセルが境界の外へ複写されて漏れる（EffectItem のマスクが反対側へ効く）ため不採用とし、恒等解決へ落ち着いた。(5) Core の `EffectItem.Blur`: 本家は `Animation(0, 0, 250)` の型付きプロパティだが、こちらは追加フィールドの生保持だけだった。型付き化し、エンコードのキー並びは本家の宣言順（ShapeParameter と InvertMask の間）に一致させ、`forEachAnimation` の走査にも加えた。

**本家との差分。** (a) ShapeParameter が型付きでない（生保持＝図形プラグイン由来）EffectItem は、マスク画像を生成できないため透明マスクとして扱う（本家でも図形プラグインが無ければ図形は生成されない。矩形以外の型付き図形も、MetalShapeSource の対応範囲＝矩形のみという既存制限をそのまま受ける）。(b) アルファマスクの GPU 実行が失敗した場合、この境界（`setInput`）は例外を投げられないため、マスク未適用の本体を正しい出力として公開せず透明を登録する（MAC-0021 の方針の適用）。描画効果側の失敗は従来契約どおり EffectedItemError として伝播する。(c) フェードの二重適用は本家の実挙動の再現であり差分ではない。(d) 白 Flood の恒等解決は、全面不透明マスクという入力条件の下で D2D AlphaMask と厳密に等価であり、見える差分はない。

**メモリ・並行性。** factory は生成経路ごとに、その合成器が使う MetalGraphicsContext へ束縛して生成する（デバイスと登録表は全経路で共有され、文脈の所有関係は従来どおり）。アルファマスク効果は入力設定のたびに中間テクスチャを1枚作る（描画段の設定で実質1回）。出力として本体画像自身を登録する Flood 経路では新規確保はない（登録は参照の結び付けのみで、テクスチャの所有はアイテム描画先のまま）。図形テクスチャのキャッシュは描画効果が所有し、dispose で解放する。FrameBuffer 基底分離による所有関係の変更はない。

**検証。** 画素ハーネスを新設した（本人の Mac の ~/mac0034-harness、正本は `~/workspace/ymm4-work/mac0034-harness/`）。kiminihare は EffectItem・クリッピング指定とも0件で受入検証に使えないため、64×64 の人工最小プロジェクトで25項目を検証し全合格: EffectItem 単体（Flood の不透明な黒が Invert で白になり、マスク外は透明のまま、被覆が右半分ちょうど2048px）、赤画像＋EffectItem（右半分だけ Invert のシアン、左半分は無変更）、InvertMask（左右が入れ替わる）、Opacity 50%（合成が単回適用の灰色128。二重適用なら緑成分≈64 になるため判別可能）、図形によるクリッピング（赤の被覆が 32×32＝1024px ちょうど、形状外は α0）、先行画像なしのクリッピング（Flood で全面表示）、合成グループ内部のクリッピング、シーン内部のクリッピング、書き出し経路（MetalExportVideoProvider の借用バッファ直読）のクリッピング。Mac 実機（検証コピー ~/verify-effectsrc/YMM4Mac）でルート＋DebugApp の `swift build` 成功、変更 GPU ファイルの強制再コンパイルで警告0。回帰ハーネスを同コピーへ向け替えて再実行: mac0023 = 25 PASS / 0 FAIL、mac0025 = 18 PASS / 0 FAIL、mac0027 = 15 PASS / 0 FAIL、mac0028 = 90 PASS / 0 FAIL（FrameBuffer と図形 Source の分離・再構成による退行なし）。Linux: `~/workspace/tools/swift-6.1.2/usr/bin/swift test` で全415件・0失敗（従来414件＋Blur 往復テスト1件）。このテスト実行の後に変更したのは macOS 限定の GPU ファイル（サンプラ方式の差し替えと撤回）と文書のみで、Linux のテスト対象である YMM4Core は同一であり、最終ツリーでの `swift build` 成功も確認済み。本家実機との比較試験は未実施のため IMPLEMENTED 止まり（期待値は逆コンパイル実コードからの解析値）。

**未解決事項。** (1) メインクローンへの統合は統合 PR で完了。(2) 矩形以外の図形パラメータ（MetalShapeSource の対応範囲の拡張は別件）。(3) 本家との画素一致（Golden Master は本家環境が無いため到達不可）。

**次の担当へ。** AUD-01 / AUD-03 は本件で解消。監査の残りは AUD-02（トランジション合成の配線）、AUD-04（PngWav ライター）、AUD-06（Metal 初期化失敗の診断）。STATUS の大きな表・監査セクションは統合時に確定形（MAC-0035）へ更新済み。

#### MAC-0036 — 画面遷移（TransitionSource）の配線（AUD-02 の処分）（IMPLEMENTED、Mac 検証済み）

**何を実装したか。** 全体監査 AUD-02（正本は解析側 `analysis-notes/AUDIT-2026-11-17-FULL.md` と処分 `REVIEW-DISPOSITION-AUDIT.md`）: TransitionItemPicker は実装・テスト済みだが合成器から一度も使われず、MetalSourceProvider に TransitionItem 用の Source が無かった。そのため主合成側の除外規則だけが効き、遷移区間では下位レイヤーが主合成から消える一方、前後画面の合成もブレンドも描かれなかった。本家 TransitionSource の意味論を実装し、MetalSourceProvider へ配線した。番号は並行作業（AUD-01 / AUD-03）が MAC-0034 を使用しているため 0035 とした。

**本家の意味論（逆コンパイル実読で確定）。** TransitionSource は内部に TimelineSource を2つ持ち、両側へ同一の現在時刻の更新記述を渡す。Before 側のピッカーだけが選定フレームを transitionItem.Frame − 1 に固定する（選定アイテムのアニメーションは静止しない。処分 AUD-02 の訂正どおりで、Mac 側 ItemPickers.swift の既存解釈と一致したためピッカーは無変更）。各側は EffectedTimelineSource（内側合成 → 画面矩形で Crop → Before/AfterVideoEffects 連鎖（IsEnabled のみ）→ DrawingEffect（恒等 DrawDescription））を通る。ITransitionSource の生成し直しはパラメータ参照が変わったときだけ。内蔵パラメータは9種（None / Switch / Fade / Slide / Push / DoubleOpenDoor / DoubleSlideDoor / Slice / RuleImage）で、TransitionItem の既定は PushTransitionParameter。Fade は D2D CrossFade の式 output = Weight × Destination + (1 − Weight) × Source（入力0 = After、入力1 = Before、Weight = イージング済み進行率。式は Microsoft Learn で確認）。Switch は進行フレームが尺の半分未満で Before、それ以外で After。パラメータの既定値（Easing は Fade / Slide / Push / ドア / Slice が Expo・InOut、RuleImage のみ Linear・InOut、Angle 既定 0、Slice の Slices 6 / Shift 0 / Start Left / Direction Alternating、Target / OverlayTarget 既定 Before、RuleImage の Tolerance 3 / KeepAspect true）は各クラスのフィールド初期化子の実測。

**どこを変更したか。** 新規2件: `Sources/YMM4Core/Effects/TransitionParameters.swift`（パラメータの型付き復号。$type のクラス名で9種＋unknown を判定し、nil は本家のフィールド初期化子どおり Push。Animation 項目は CodecSupport.decodeAnimation で読み、キーフレーム文脈は applyKeyFrames で伝播）、`Sources/YMM4GPU/MetalTransitionSources.swift`（MetalTransitionSource とブレンド階層＝基底 MetalTransitionBlend（MetalEffectProcessor の描画パス機械を再利用）＋内蔵8種＋TransitionGeometry（本家の象限式・DoorResources・SliceResources の移し替え））。変更5件: `Sources/YMM4GPU/MetalSources.swift`（TransitionItem ケースの追加と、内部合成器ファクトリ／全体エフェクト供給の2メソッド。シーン・合成グループと同じ捕捉を共有）、`Sources/YMM4GPU/MetalGraphics.swift`（合成シェーダへ加重和モード2（a × opacityA + b × opacityB）とマスク乗算モード3（b × opacityB × a.a）を追加。既存モード0 / 1 は無変更）、`Sources/YMM4GPU/MetalEffectProcessors.swift` と `Sources/YMM4Core/Effects/VideoEffectRegistry.swift`（Before/AfterVideoEffects の定義供給 `transitionEffectPairs(for:isBefore:)` を Metal / 型付きの両供給元へ追加。EffectPairProvider プロトコル自体は無変更で、既存のテスト用供給元を壊さない）、`Tests/YMM4CoreTests/TransitionParameterTests.swift`（新規12件）。**TimelineSource.swift 等の合成器ファイルは無変更。** 文書: 本台帳、ARCHITECTURE（ファイル一覧へ MetalTransitionSources を追加、テスト件数 414 → 426）、STATUS（AUD-02 を解消済みに更新）、HANDOFF（統合待ちの記録）。

**どう実装したか。** (1) MetalTransitionSource は自前文脈と自前 DrawingEffect を所有し、供給元のファクトリが文脈ごとに子 MetalSourceProvider と TransitionItemPicker（isBefore の別）を持つ TimelineComposer を構築する（合成グループ・シーンと同じ内部合成の形）。下位レイヤーのトランジションも再帰的に内部合成を持つ。(2) 各側の連鎖は Core の EffectedOutput（applyItemTransform = false、入力は描画効果なしの StandardSourceOutput）で実行し、全体エフェクトの定義は合成器と同じ供給元から取る（GPU エフェクトの差し替えが全体エフェクトにも効く）。(3) Crop の等価実現: 内部合成器の出力テクスチャは画面サイズだが、その登録の境界は内容境界（画面より大きいアイテムでは画面を超える）であり、そのまま平行移動すると空いた側が端画素の引き伸ばしで埋まる。そこで同じテクスチャを画面矩形の境界・平面範囲で登録し直した参照を連鎖とブレンドへ渡す。(4) ブレンド: Fade は合成シェーダの加重和モードで自前参照へ公開。Switch は前後どちらかの参照をそのまま返す。None / Slide / Push / ドア系 / Slice は描画先へ順序描画し、平行移動は境界＋planeOffset の登録差し替え（MetalCompositeSource の中心ずらしと同じ写像。描画は記録時点で実体を解決するため逐次再登録が安全）、回転は変換行列の登録差し替えで表す。ドアとスライスのマスクは本家の四角形を白でラスタライズしたテクスチャをマスク乗算モードで適用する。(5) ブレンドの作り直しはパラメータの保持値が変わったときだけ（下記の内部差分）。キーフレーム文脈は毎回伝播する。

**本家との差分（内部実装の違い。ユーザーから見える違いはない）。** (1) ブレンド作り直しの判定がパラメータ参照の変化ではなく保持値（PreservedObject、Equatable）の変化。(2) ブレンドへは毎回その時点の前後画像参照を渡す（Mac 合成器の描画先はフレームごとに新しい参照になるため）。(3) 本家は2つの内部合成を Parallel.ForEach で更新するが、こちらは逐次（観測結果は同一）。(4) Crop はテクスチャの再登録で等価に実現。(5) 型付きでも Metal でもないカスタム EffectPairProvider では Before/AfterVideoEffects を供給しない（本家では常にアイテムの保持列が使われるため、カスタム供給元向けの制限として記録）。

**差し替え点（未実装として記録）。** RuleImage はシェーダ本体が外部コンパイル済みリソース（ShaderResourceUri.Get("Transition")）で逆コンパイル集合に含まれず、閾値の法則が未確認のため実装しなかった（捏造しない）。RuleImage と未知方式（プラグイン）は Switch の挙動へ倒す。プラグイン方式の差し替え点は MetalTransitionBlend.make の種別分岐。

**メモリ・並行性。** MetalTransitionSource が所有するのは自前文脈・DrawingEffect・内部合成器2つ・連鎖2つ・ブレンド1つで、dispose で全て解放する。ブレンドの描画先はフレームごとに作り直し、前回のものは次回 blend の先頭で解放する（EffectedItemSource の出力描画先と同じ所有形態。消費側が前フレーム出力を読み終えた後のタイミング）。平行移動・マスク用の登録はブレンド所有の scratch 参照を使い回し、dispose で登録解除する。画面矩形へ登録し直した前後参照は Source 所有で dispose 時に解除する。

**検証。** Linux: `~/workspace/tools/swift-6.1.2/usr/bin/swift test` で全426件・0失敗（従来414件＋新規12件＝パラメータ復号の種別判定・既定値・easedRate・前後キャッシュ分離・コーデック往復）。Mac 実機（検証コピー ~/verify-transition/YMM4Mac）: ルート＋DebugApp の `swift build` 成功・警告0。画素ハーネスを新設した（本人の Mac の ~/mac0035-harness、正本は `~/workspace/ymm4-work/mac0035-harness/`）: kiminihare 両ファイルは TransitionItem 0件で受入検証に使えないため、人工の最小プロジェクト（64×48 / 30fps、赤の全面図形 frame 0〜99 と青の全面図形 frame 100〜199 をレイヤー0、TransitionItem frame 100 / length 20 をレイヤー1）で27件全合格。内訳: Fade（Linear）の中点 frame 110 で中心画素 (128, 0, 128)（理論値 127.5 の丸め範囲内）、端点 frame 100 = 赤・frame 119 = (13, 0, 242)（率 0.95 の理論値どおり）、区間外 frame 99 = 赤・frame 120 = 青（主合成のみ）、Switch の中点切替、Push（既定パラメータ）の中点で左半分 = 青・右半分 = 赤、Slide（Target = After）も同形、DoubleSlideDoor の両端扉と中央露出、DoubleOpenDoor の蝶番近傍と中央露出、Slice（2帯・Down）の帯移動、BeforeVideoEffects の Invert が Before 側だけに効くこと（frame 100 で (0, 255, 255)、中点で (0, 128, 255)）。開発中に画素ハーネスで検出した不具合が1件ある: 実装当初は内部合成の出力（内容境界つき登録）をそのままブレンドへ渡していたため Push / Slide の空いた側が端画素で埋まった。上記 (3) の画面矩形への登録し直しで解消し、全ケース再合格した。本家実機との比較試験は未実施のため IMPLEMENTED 止まり（画素の期待値は本家コードの式からの解析値であり、本家 Direct2D 出力との画素一致は主張しない）。

**統合時の継ぎ目の是正。** トランジション内部合成器（Before / After）は、本ブロックの設計時点では AlphaMask factory の注入対象に含まれていなかった。AUD-03（MAC-0035）の「全生成経路で注入する」契約に合わせ、統合時に `transitionComposerFactory` でも factory を注入した（合成グループ・シーンの内部合成器と同じ形）。これにより遷移前後の内部合成でもクリッピングが効く。

**未解決事項。** RuleImage の閾値法則（シェーダ未確認）とプラグイン方式は差し替え点のまま。解析側の Mac As-built と互換マトリクスの同期は統合時に行う。本件は分離コピーツリー（`~/workspace/ymm4-work/ymm4mac-transition/`）での実装であり、メインクローンへの統合は統合 PR で完了した。統合後の検証は STATUS を参照。

#### MAC-0037 — 音声リサンプラの正式形（Kaiser 窓・片側96零交差への固定）（IMPLEMENTED）

**何を実装したか。** MAC-0024 で帯域制限補間化した ResamplerStream の生成芯について、QA24-01（レビュー第4ラウンドで確定した測定系の欠陥）の処分として行った再測定と比較試験（解析側 `analysis-notes/AUDIO-FIDELITY-PLAN.md` §3.1.1・§3.1.2）を受け、窓関数と正式合格値を正式仕様として固定し、製品形へ実装した。正式合格値と窓仕様はオーナー承認事項だったが、オーナーが「要件定義の趣旨に従って任せる」と委任した（2026-11-17）ため、基本指示の優先順位（互換性・忠実度 > 速度）と音声忠実度最優先の方針に従い、合格値を実装に合わせて下げる事後調整をせず、暫定目標候補どおりの水準を満たす唯一の候補を採用した。決定の正本は AUDIO-FIDELITY-PLAN §3.1.3。

**どこを変更したか。** `Sources/YMM4Core/Audio/AudioResampling.swift`（生成芯の窓を Kaiser 窓へ差し替え、実験フックを撤去）、`Tests/YMM4CoreTests/AudioResamplerQualityTests.swift`（合格値を合否判定として固定する正式テストへ再構成。候補比較用の AudioResamplerWindowComparisonTests は役割を終えたため qa ツリー内で削除し、掃引は正式テストへ統合）。作業は分離ツリー `ymm4mac-resample-qa` で実施し、本項は統合時の転記である。

**どう実装したか。** 窓関数 = Kaiser 窓（β = 8.96、設計減衰 A ≈ 90 dB に対応）、支持幅 = 片側 96 零交差（scale = 1 で計 193 タップ）。Bessel I0 は比較試験の実装と同じ級数評価（製品形として早期終了つき）。リサンプラの契約（長さ・シーク・素通し規則、位置写像、中心遅延 0）は無変更。正式合格値は 48k→44.1k で阻止帯域 [23.2k–24kHz]（25Hz 格子掃引）の最悪値 −80 dB 以下、通過帯域 20kHz までの平坦さ ±0.1 dB 以内とし、`AudioResamplerQualityTests` の testFormalStopbandSweep / testFormalPassbandFlatness が合否を固定する。

**なぜその実装なのか。** 同じ測定系での候補比較（§3.1.2）で、正式合格値を満たしたのは Kaiser 96 のみだった（Blackman 96 は阻止帯域の最悪値 −79.10 dB で 0.9 dB 不足）。窓長の延長では改善が頭打ちで（48→64 で +15.0 dB、64→96 で +3.8 dB）、制限要因は窓関数のサイドローブ構造だった。コストは素朴実装で Blackman 48 比 Release 約 3.1 倍だが、上記の優先順位により許容した。係数テーブル化／ポリフェーズ化は将来作業として残す。

**本家との差分。** 本家のリサンプラは Media Foundation の実装であり波形等価性は未検証のまま（従来どおり）。本件は Mac 側の品質仕様の固定であり、本家との差分を新たに生むものではない。

**検証。** 最終形での再測定（qa ツリー、同測定系・同 VM）: 掃引の最悪値 −94.54 dB @23,200Hz（合格値 −80 dB に対し余裕 14.5 dB）、通過平坦さは 6 点全てで |利得| ≤ 0.000031 dB、スポット値も §3.1.2 の実験値と一致。qa ツリーの全件テスト（48 クラス・413 件＝ツリー側の基準件数）を分割実行で完走し 0 失敗（AudioDriftTests・AudioSampleAccuracyTests を含む。ランプ再構成の期待値 1.5456 は Kaiser でも理論値と一致し変更不要だった）。統合後のメインでの全件検証は STATUS を参照。留保: 25Hz 格子の最悪値は真の連続最悪値より数 dB 楽観的な可能性がある（§3.1.2 と同じ）。

**未解決事項。** 係数テーブル化／ポリフェーズ化による高速化（将来作業）。Apple Silicon での Release コスト実測は未実施（コスト比は共有 VM 上の測定）。本家 MFT との波形等価性は本家環境が無いため未検証。

**次の担当へ。** QA24-01 は本件で完了（第5ラウンドで測定系は採用可・品質は条件付き採用可となり、本件で正式形へ固定）。残る音声課題は SOLA の本家パラメータ実測と実装、EnvelopeFollower の Ratio≠1 検証、EX26-02 / 03。

#### MAC-0038 — デモ版内蔵のデバッグ用全自動テスト（IMPLEMENTED、Mac 検証済み）

**何を実装したか。** オーナー指示（2026-11-17 21:58、22:29 に「デバッグ用全自動テストツール」の指す対象が本件であることを確認）に基づき、デモ版（Apps/DebugApp）の内蔵機能として、オーナーの Mac 実機でボタン1つで応答性能を全自動測定し、結果をアプリ内要約＋JSON レポートファイルに残す仕組みを実装した。本家に相当機能は無い（デバッグ専用機能であり、本家互換の対象ではない）。目的は (1) ビルドごとの数値比較、(2) 構造整理の各単位での回帰確認、(3) SSH では画面確認できない実機応答性の実測経路の確保。

**どこを変更したか。** 新規2件: `Apps/DebugApp/Sources/YMM4MacDebug/AutoTestReport.swift`（レポートの Codable モデル、出力先・自動実行トリガ・起動時間・機械情報・メモリ使用量の環境ヘルパー `AutoTestEnvironment`）、`Apps/DebugApp/Sources/YMM4MacDebug/AutoTestRunner.swift`（画面状態 `AutoTestState` と測定ジョブ `AutoTestJob`）。変更1件: `Apps/DebugApp/Sources/YMM4MacDebug/ContentView.swift`（上部バーへ「全自動テスト」ボタン、結果要約の表示、起動時のトリガ消費と画面表示時刻の記録）。**YMM4Core / YMM4GPU は無変更**（公開 API のみ使用）。文書: 本台帳、ARCHITECTURE（DebugApp の説明へ追記）、STATUS（基準行・反映境界・デバッグ用アプリ行）、HANDOFF（完了項目と次の順序）。

**どう実装したか。** 測定対象は「ファイルから読み込んだプロジェクトが開いていればそれ、無ければ同梱サンプル（Apps/DebugApp/Sample/sample.ymmp、ソースファイルからの相対位置で解決）、それも読めなければ開いている（空の）プロジェクト」。測定は書き出しと同じ `Project.makeExportSnapshot` の専有スナップショットに対して行い、測定中の画面編集と競合させない（AUD-07 と同じ方針。スナップショットを構築できない場合のみ開いているモデルを直接測り、その旨をレポートへ注記する）。測定5項目:
(1) フレーム合成時間 — PreviewBox と同じ生成手順（MetalGraphicsDevices → 文脈 → MetalSourceProvider ＋ MetalEffectPairProvider → TimelineComposer）で自前のセッションを組み立て、ウォームアップ1回の後、タイムライン全体から等間隔に最大30フレーム＋最終フレームを合成。update のみ／update＋CGImage 読み戻し（このアプリのプレビュー表示の実際の経路）を分けて計測し、それぞれ平均・95パーセンタイル・最大を出す。60fps 予算 16.7ms との合否は読み戻し込みの p95 で判定する。
(2) シーク応答 — 非連続な7位置（中点・0・末尾・1/4・3/4・10・1/3）へ順に飛び、各位置で update＋読み戻しが返るまでを計測。
(3) 音声オフライン処理速度 — タイムラインミックスは書き出しと同じファクトリ構成の `TimelineAudioMixer` で先頭最大10秒を読み切り実時間比を出す。リサンプラ単体は 1kHz 正弦波10秒を `ResamplerStream`（Kaiser 正式形）で 44.1k→48k と 48k→44.1k の両方向変換し、それぞれ実時間比を出す。
(4) 書き出し速度 — `TimelineExporter` のファサードと同じ供給側（MetalExportVideoProvider ＋ TimelineExportAudioProvider）と ExportSession の組み立てを、先頭最大180フレームの範囲だけに区切って実行する。供給側の構築（ラウドネス解析を含む）時間とセッション実行時間を分けて記録し、fps は実行時間基準（framesWritten / 実行秒）。ffmpeg は /opt/homebrew/bin/ffmpeg → /usr/local/bin/ffmpeg → PATH の順で解決する。出力ファイルは測定後に削除する。
(5) 起動時間とメモリ — 起動時間は sysctl のプロセス開始時刻（p_starttime）から ContentView の初回 onAppear まで。メモリは測定完了時点で mach task_info の常駐サイズと物理フットプリントを記録する。
レポートは `~/ymm4-work/YMM4MacAutoTest/report-<yyyyMMdd-HHmmss>.json` と `latest.json`（同内容）へ原子的に書き出す。項目ごとに実測値と条件（対象プロジェクト・解像度・フレーム範囲・機械情報・ビルド構成）を持ち、素材が無い項目は透明フォールバックになる前提を notes へ常時明記する。起動経路は3つ: 画面のボタン、環境変数 `YMM4MAC_AUTOTEST=1`（`YMM4MAC_AUTOTEST_EXIT=1` を併せると測定後にアプリを終了する。SSH からの無人検証用）、トリガファイル `~/ymm4-work/YMM4MacAutoTest/RUN`（起動時に1回だけ消費＝削除）。

**なぜその実装なのか。** 測定値の正本をレポートファイルに一元化し、文書へ転記しないことで、過去に起きた「同じ事実の複数文書への書き写しによる齟齬（414/413 件の併記）」と同じ失敗を構造的に避けた（事実の種類ごとの正本化。文書には実施事実とレポートの場所だけを書く）。レポートにビルド構成（debug / release）を含めたのは、CPU 処理の実時間比が構成で桁違いに変わるため（下記検証）で、ラベル無しの数値同士を比較すると誤読するからである。書き出し測定でファサードを使わず範囲を区切ったのは、ファサードがタイムライン全体を対象とし、実プロジェクト（約12,000フレーム）では測定が分単位になるためで、供給側とセッションの構成要素は本番と同一である。合成セッションを PreviewBox の再利用ではなく同手順の組み立てにしたのは、update のみ／読み戻し込みの分離計測に合成器への直接アクセスが要るため（経路の実体は同一）。

**本家との差分。** 本家に無いデバッグ専用機能であり、互換性上の差分は生まない。Core / GPU の公開 API のみを使い、製品側コードへは一切手を入れていない。

**メモリ・並行性。** 測定ジョブは ExportJob と同じ @unchecked Sendable の箱で、スナップショットを単一のバックグラウンドスレッドからのみ触り、UI へは MainActor 経由でのみ戻す。合成セッション・書き出しの映像供給は測定後に dispose する。レポート書き出しは .atomic で行い、途中終了で壊れた JSON を残さない。

**検証。** Mac 実機（検証コピー ~/ymm4-work/verify-autotest/YMM4Mac）: ルート＋DebugApp の `swift build`（debug）と DebugApp の `swift build -c release` がいずれも成功・**警告0**。release ビルドを環境変数トリガで実機実行し、起動→測定→レポート生成→自己終了まで **約8.5秒** で完走（終了コード0）。得られた値（対象＝同梱サンプル 640×360 / 30fps / 400フレーム / 8アイテム、Apple M2・macOS 26.3）: 合成（読み戻し込み）平均 約1.04ms / p95 約2.47ms / 最大 約5.27ms、シーク平均 約1.88ms、リサンプラ実時間比 44.1→48k **×3.09** / 48→44.1k **×2.93**（perf 監査の release 実測 ×2.98〜3.01 と一致。合成値が監査の kiminihare 1080p 実測 8.1〜8.8ms より小さいのは対象素材と解像度の違いであり、条件はレポートに記録される）、書き出し 180フレーム完走・約272fps、起動 約0.86秒。debug ビルドでも同じ経路で完走を確認した（リサンプラは未最適化のため ×0.16 / ×0.14 と桁違いに遅く、実行全体で約2.5分。レポートの buildConfiguration と notes で自己表示される。性能の正本は release のレポートとする）。既存テストへの影響: 本変更は DebugApp 内に閉じ、ルートパッケージのテスト対象を含まないため、既存テスト（全432件・0失敗、MAC-0034〜0037 統合時の Mac 実測が基準）への影響はない。非退行はルート＋DebugApp の Mac ビルド成功・警告0で確認した。

**未解決事項。** 対象タイムラインは先頭の1本のみ（シーンタブで選択中のタイムラインではない）。起動時間は「プロセス開始→最初の画面表示（onAppear）」の定義であり、ウィンドウの実描画完了までは含まない。debug ビルドではリサンプラ測定だけで分単位かかるため、日常の応答確認は release ビルドのレポートを正本とする運用。

**次の担当へ。** レポートの回収は `~/ymm4-work/YMM4MacAutoTest/latest.json`（Mac 上）。構造整理の各単位では、整理前後で release ビルドのレポートを取り、合成 p95 とリサンプラ実時間比の退行有無を比較すること。測定項目の追加は AutoTestJob の execute() へ足し、レポート形式を変える場合は formatVersion を上げる。

#### MAC-0039 — DebugApp の .app バンドル化（IMPLEMENTED、Mac 検証済み。Dock 表示は未確認）

**何を実装したか。** デモ版（DebugApp）は従来、ビルド済み実行ファイルを直接起動する形だったため、macOS の通常のアプリとして扱われず Dock にアイコンが出なかった（ウィンドウが他のアプリの後ろに埋もれて呼び出しにくい、という実害が本人の実機で発生）。パッケージング手順をリポジトリ内に正本として置き、`YMM4 for Mac.app` を組み立てて通常のアプリとして起動できる形にした。本家に相当する変更は無い（デバッグ用アプリの配布形態の話であり、本家互換の対象ではない）。

**どこを変更したか。** 新規2件: `Apps/DebugApp/Info.plist`、`Apps/DebugApp/package-app.sh`。変更1件: `Apps/DebugApp/Sources/YMM4MacDebug/YMM4MacDebugApp.swift`（`DebugAppDelegate` を追加）。**YMM4Core / YMM4GPU は無変更。** 文書: 本台帳、STATUS（基準行・反映境界・デバッグ用アプリ行）、HANDOFF（完了項目）。

**どう実装したか。** `package-app.sh` は SwiftPM でビルドし（既定 release、`CONFIGURATION` で切替）、実行ファイルを `Contents/MacOS/` へ、同梱の `Info.plist` と `PkgInfo` を `Contents/` へ配置して、アドホック署名（`codesign --sign -`）で仕上げる。出力先の既定は `~/Applications`。`Info.plist` の要点: `CFBundleIdentifier` = `com.yanikasumin.ymm4mac.debug`、`CFBundleName` / `CFBundleDisplayName` = `YMM4 for Mac`、`CFBundleExecutable` = `YMM4MacDebug`、`LSMinimumSystemVersion` = `26.0`、`NSHighResolutionCapable` = true。アプリ側の保険として、`DebugAppDelegate.applicationDidFinishLaunching` で `NSApp.setActivationPolicy(.regular)` を指定する（バンドル無し実行でも Dock へ登録されるようにする再確認であり、バンドルから起動した場合は無害）。

**検証。** Mac 実機（検証コピー `~/ymm4-work/verify-appbundle/YMM4Mac`）: DebugApp の `swift build -c release` 成功・警告0（変更ファイルの再コンパイルでも警告なし）。組み立てた `~/Applications/YMM4 for Mac.app` は構造が `Contents/{Info.plist, MacOS/YMM4MacDebug, PkgInfo, _CodeSignature/}` で、`plutil -lint` OK、`codesign --verify` 合格。バンドル内の実行ファイルを環境変数 `YMM4MAC_AUTOTEST=1 YMM4MAC_AUTOTEST_EXIT=1` で起動し、全自動テスト（MAC-0038）が完走（終了コード0）してレポート `report-20261118-010826.json` と `latest.json` が `~/ymm4-work/YMM4MacAutoTest/` へ出力された（buildConfiguration = release、全セクション揃い）。本人の起動中アプリ（別プロセス）には触れていない。**Dock へのアイコン表示そのものは画面操作を伴うため未確認**であり、次回の引き渡し時に LaunchServices 経由の起動で実機確認する。

**未解決事項。** Dock 表示の実機確認（上記）。配布用の Developer ID 署名・公証は対象外（アドホック署名はローカルビルド用の暫定形）。

#### W1 — 構造整理 第1単位: テスト基盤の整備とハーネスの git 管理化（IMPLEMENTED、Mac 検証済み）

構造整理（全ファイル計画の作業単位 W1。計画書は解析側 FULL-RESTRUCTURE-PLAN-2026-11-17 §4.4・§3.10・§5.1）。製品コードは無変更で、移動と重複排除のみを行った。

- **Tests のドメイン別フォルダ化**: `Tests/YMM4CoreTests/` 直下の25ファイルを、本体構造と鏡像のフォルダ（Animation / Audio / Effects / Export / Rendering / Format / Model / Editing）へ移動した。ファイルの分割は本単位に含めない（後続単位の担当）。
- **Support/ の新設と重複ダブルの集約**: 各テストファイルに私用定義されていた同一・同型の偽実装を `Tests/YMM4CoreTests/Support/` へ集約した。
  - `TestPCMProviders.swift`: PCMProviderFactory の同一実装4件（旧 MapProviderFactory / DriftProviderFactory / AccuracyProviderFactory / ExportAudioProviderTests 内の同名実装）を `MapPCMProviderFactory` へ一本化。あわせて音声テスト共通の構築ヘルパ（constantProvider / rampProvider / constantAnimation / makeAudioItem）を集約した（rampProvider は offset 引数つき、makeAudioItem は volume 引数つきの形に統一し、既存の呼び出しは既定値で互換）。makeTimeline はファイルごとにシグネチャが異なるため集約していない。
  - `FakeSources.swift`: 同名で仕様の異なる StubSource 2件を、最小形 `StubSource` と記録形 `RecordingStubSource` の2型として集約した。
  - `FakeRenderTargets.swift`: StubTarget / StubTargetFactory を記録機能を持つ形に一本化した（EffectWiringTests 側は記録を使わないため代替可能）。
  - `FakeProcessors.swift`: 同一の素通し実装2件（旧 StubDrawingEffect / PassThroughDrawingEffect）を `PassThroughDrawingEffect` へ一本化し、StubProcessor / StubDefinition を集約した。
  - `FakeProviders.swift`: StubEffectProvider を集約した。
  - 計画からの変更点: RenderingTests と CompositionTests の FakeDrawingEffect は同名だが仕様が全く異なる（入力・破棄の記録 vs 名前＋イベントログ＋エラー注入）ため、集約するとテストの振る舞いが変わる。集約せず各ファイルに残した。
- **ハーネスの git 管理化**: Mac 側の作業領域に散らばっていた画素検証ハーネス9件（mac0023 / mac0025 / mac0026 / mac0027 / mac0028 / mac0031 / mac0033 / mac0034 / mac0035）を `Harnesses/` へ取り込んだ。各 Package.swift の依存パスは検証用コピーの絶対パスからリポジトリルートへの相対パス（`../..`）へ変更し、`Harnesses/README.md` に目的・実行方法・期待値を文書化した。ffmpeg スタブ（mac0026）には実行権限を付けた。旧世代の metalfx ハーネスと性能監査用ベンチ（perfbench / resamplebench）は現役の検証資産ではないため取り込み対象外とした。
- **検証**: Linux で影響範囲のテストを実行し全合格（対象6クラス計55件・0失敗。内訳: AudioPipeline 20件、AudioDrift 7件、AudioSampleAccuracy 11件、CompositeGroup 5件、EffectWiring 4件、ExportAudioProvider 8件。これに AudioResamplerQualityTests 9件・0失敗を加え、合計64件・全合格）。Mac 実機でルート＋DebugApp のビルド成功・警告0、取り込んだハーネス9件をリポジトリ内配置から実行し従来値どおり全合格（mac0023 = 25、mac0025 = 18、mac0026 = 19、mac0027 = 15、mac0028 = 90、mac0031 = IoU 1.000、mac0033 = 通常ケース2件・失敗ケースは既定 SKIP、mac0034 = 25、mac0035 = 27）。全自動テストの release レポート比較では、整理前（MAC-0039 時点のレポート）と整理後で合成 p95 が 5.19 ms → 4.89 ms、リサンプラ実時間比が 2.90 / 2.95 → 3.12 / 3.12 と同等であることを確認した（測定の正本はレポートファイル）。
- **件数訂正（2026-11-18）**: 本項の当初記載（66件）と PR #69 本文の当初記載（計86件とその内訳）は、実測の裏付けのない誤記であったため、上記の実測値（対象6クラス計55件＋AudioResamplerQualityTests 9件＝合計64件・全合格）に訂正した。結論（全合格・Mac ビルド警告0・ハーネス値・全自動テスト比較）に変更はない。

#### UI-FORM — フロントエンドの形の完成（IMPLEMENTED、Mac 検証済み。目視未確認）

- **レイアウト（Issue #37/#38）**: ProjectView の構成を本家 DefaultLayout に合わせた。左カラムは「プレビュー＋トランスポート（初期高さ 400、6px スプリッタで調整可）」の下にタイムラインが残り高さを取り、右カラムは幅 400 で全高。デバッグ機能（書き出し・診断・往復チェック・ログ）は製品レイアウトから外し、ステータスバーの下に折りたたみドロワーとして分離した（既定は閉）。
- **レイヤー行（Issue #39/#40）**: 行高 32・ラベル幅 80 は従来から本家一致。serif 行との重なりは、固定高レイアウトを廃してタイムライン領域を残り高さにし、ストリップ全体を構造的にクリップすることで解消方向にした（根本原因の切り分けは未実施。目視確認待ち）。
- **ツールバー（Issue #41）**: 5種（ズーム／アイテム追加／編集／プロジェクト／フィードバック）をアイコン化し、ツールチップは本家 Command.TextWithShortcut の形（名称＋ショートカット併記）にした。アイテム追加は13種ボタン＋テンプレート／最近のドロップダウン、編集は波形・グリッドの SplitButton とメーターのドロップダウンを含む。取り消し／やり直し／切り取り・コピー・貼り付けはバックエンド（履歴・クリップボード）が無いため無効表示。
- **ホイールズーム（Issue #42）**: 目盛り帯の上でのスクロールを本家 TimelineScaleViewModel どおり ×1.125／×0.875 刻みにした（NSEvent のローカル監視で目盛り矩形内だけ消費）。
- **メニュー実体化**: ファイル（新規／開く／追加／動画の設定／動画出力／サムネイル出力／コピー保存）、編集（現在位置で分割／アイテム操作／タイムライン操作）、レイアウト（既定に戻す）、ヘルプ（本家と同じ外部リンク）を接続。接続先の無い項目（テンプレート適用・バックアップ復元・Exo出力・字幕インポート・ツールウィンドウ群・ボイス操作・整列ほか）は無効表示にし、理由は各所のコメントに残した。
- **レイヤー追加／削除**: ラベルの右クリックメニューと ⋯ メニューから挿入／削除／上下移動／全表示／他を非表示／設定リセットを接続（アイテムと LayerSetting の番号付け替えを含む）。
- **プレビューハンドル**: 選択アイテムの四隅（拡大率）と辺中点（回転角）のドラッグを実装。書き込みは PropertyDescriptor 経由で先頭値／定数値の規則に従う。
- **serif 行 → VoiceItem**: 追加で VoiceItem を生成し、キャラクター・セリフ・再生ヘッド位置を設定。「追加してシーク」も接続。長さは音声供給（Issue #51）が未接続のため1秒の仮置き。
- **コンテキストメニュー**: キャンバス背景／目盛り／アイテム上／レイヤーラベル／シーンタブを追加。本家は右クリック位置を対象にするが SwiftUI では位置が取れないため、再生ヘッド位置とクリック対象で代替（差異として記録）。レイヤーの切り取り／コピー／貼り付けはクリップボードが無いため未収録。
- **ドロップイン**: タイムラインへファイルをドロップすると、本家の判定順（動画→音声→画像）と拡張子集合で分類してアイテム化する（長さは仮置き）。単一の .ymmp はプロジェクトとして開く。字幕ファイルの分岐は未実装。
- **エフェクト追加ポップアップ**: 登録済み定義95種を検索＋分類リストから選んで追加するポップアップと、各行の削除を EffectInspectorView に実装。表示名・カテゴリ・検索キーワードは本家定義クラスの [VideoEffect] 属性と Texts リソースから全95件を実測抽出して収録した（カテゴリは本家8種: アニメーション／カメラ／加工／合成／装飾／登場退場／配置／描画）。検索は表示名＋キーワードへの部分一致で、入力中はカテゴリより優先（本家 FilteredEffects の規則。かな種の無視だけは Foundation に対応が無く未対応）。本家の「仮挿入＋閉じたら確定／取り消し」とお気に入り・最近使った項目は、保存先が無いため未実装（選択即追加に簡略化）。
- **アニメーション種別メニュー**: PropertyDescriptor に種別セッターを追加（値は保持し種別のみ変更）し、標準10種＋イージング10グループ×8（通常／補間）のメニューをアニメーション行へ実装。
- **文字列テーブル**: UIStrings を新設し、アプリメニュー・ツールバー・コンテキストメニュー等の表示文字列を集約（多言語化の前提）。一部画面には未移行の直書きが残る。
- **Core 変更**: PropertyMetadata のアニメーションアクセスに種別セッターを追加、VideoEffectRegistry に空の定義を作る makeEmptyDefinition を追加。いずれも既存の振る舞いは不変。
- **照合監査での是正（本家コード実測に基づく）**: トランスポート行の高さを本家 PreviewView.xaml の操作行どおり 24 にし、速度コンボ幅 60・倍率コンボ幅 80・音量 TextBoxSlider 幅 150（ミュート→音量の並び）へ合わせた。レイヤー行高の増減は本家 SizeUpLayer／SizeDownLayer どおり ±1・下限14・上限なしに是正。タイムラインズームは下限 0.01・拡大上限 4000（ZoomIn／ZoomOutTimeline コマンド）、スライダは TimelineView.xaml 572 の TextBoxSlider（全幅120・数値欄41・範囲 0.1–150）＋ TimelineLogScaleConverter の対数変換式をそのまま実装した（ホイール拡大の上限だけは安全のためコマンド上限 4000 を流用）。アイテム追加・セリフ追加・ドロップの配置レイヤーは本家 GetCurrentLayer()（表示中ビューポートの最上段 = Viewport.Top / LayerHeight）に統一した。セリフ行は MinHeight 26（列幅 146／120 は従来から一致）。
- **根拠が取れず未確認のまま残した値**: エフェクト追加ポップアップの初期サイズ（本家はリサイズ可＋設定に保持で固定寸法なし）、シー��タブ行の高さ 24、プレビュースプリッタのクランプ範囲（120–900）、プレビューハンドルの割当て（隅=拡大率・辺中点=回転角は本家 XAML に直接の根拠がない独自の割当て）。
- **検証**: Mac 実機でルート＋DebugApp の debug／release ビルド成功・警告0、全テスト 432 件・0 失敗（変更前と同数・回帰なし）。見た目の最終確認は未実施（目視未確認）。
#### MAC-0040 — VoiceItem の音声供給（Issue #51）（IMPLEMENTED、Mac 検証済み。ただし .NET 実キャッシュでの検証は未実施）

**何を実装したか。** VoiceItem は字幕が出ても音声が無音だった（MAC-0026 で残した未解決）。プロジェクトに既に存在する音声 — .ymmp 内の `VoiceCache` と、カスタム音声ファイル — を書き出しと音声ミックスの両経路へ供給する接続を実装した。音声合成エンジンそのものは Mac 版に無いため、エンジン生成は対象外（下記「本家との差分」）。

**本家根拠（実コード照合）。** `VoiceItem.cs`（解析側デコンパイル）: `CreateAudioSource(Scene)` は `AudioSource(FilePath, 0)` を返し通常のファイルデコード経路で開く（L1812–1815）。`FilePath` は保存対象外の計算プロパティで `voiceFile?.FullName ?? customVoiceFilePath`（L298）。`voiceFile` はエンジン生成の一時ファイル、または `VoiceCache` から復元した一時ファイルであり、`VoiceCache` は音声ファイル全体を Brotli 圧縮して保持したもの（`CreateVoiceCacheAsync` L1665–1683 が圧縮、`CreateVoiceFileFromCacheAsync` L1644–1663 が解凍して `TemporaryFile` へ書き出す）。`customVoiceFilePath` は発音記号列がカスタム音声の場合にそのパス自体が入る（`IsCustomVoice` L1590–1598: 絶対ファイル URI として解釈でき、拡張子が音声分類に含まれること。`CreateVoiceFileAsync` L1702–1709 が設定）。解決順はカスタム音声 → キャッシュ → エンジン生成。

**どこを変更したか。** 新規: `Sources/YMM4GPU/Export/VoiceAudioProvider.swift`（`VoicePCMProviderResolver` と `BrotliDecompression`）、`Tests/YMM4GPUTests/VoiceAudioProviderTests.swift`。変更: `Sources/YMM4GPU/Export/TimelineExporter.swift` と `Apps/DebugApp/Sources/YMM4MacDebug/AutoTestRunner.swift`（`AudioSourceFactory` 生成時に resolver を接続）、`Package.swift`（テストターゲット `YMM4GPUTests` を新設。GPU 層には従来テストターゲットが無かった）。YMM4Core は無変更（差し替え点 `voiceProviderResolver` は MAC-0013 で用意済み）。

**どう実装したか。** `VoicePCMProviderResolver.provider(for:)` が本家の分岐順で解決する: (1) `hatsuon` がカスタム音声パスなら `PCMProviderFactory.createProvider(filePath: hatsuon, audioTrackIndex: 0)`。(2) `voiceCache` があれば Brotli 解凍し、一時ファイルへ書いて同じ factory で開く。(3) どちらも無ければ nil（`FileAudioStream` が無音へ倒す＝本家で生成前に相当）。カスタム音声の判定は本家 `IsCustomVoice` の再現で、拡張子リストは本家 `FileExtensions.GetDefaultExtentions` の音声分類（動画コンテナ全種＋音声11種。解析側 MEDIA-IO-FACTS §8.2 が根拠）。Brotli 解凍は Compression フレームワークの `COMPRESSION_BROTLI`（raw Brotli、RFC 7932）。

**なぜその実装なのか／本家との差分。** 本家は復元先の一時ファイルに拡張子を付けない（`TemporaryFile` の既定は "tmp"）が、AVFoundation は拡張子から形式を推定するため中身が WAV の .tmp ファイルを開けない（実測で "Cannot Open" を確認）。Mac 版の適応として、解凍データの先頭バイト（RIFF/WAVE、ID3・MPEG 同期、OggS、fLaC、ftyp、FORM）から形式を推定して拡張子を付ける。一時ファイルの所有権も異なる: 本家はアイテムが保持し破棄時に削除するが、Mac 版の素材デコードは全体をメモリへ展開する方式（MAC-0026）のため、resolver がデコード完了直後に削除して完結させる（現行の唯一の factory 実装が全デコード方式であることに依存する）。エンジン生成（`Speaker.CreateVoiceAsync`）は Mac 版に音声合成エンジンが無いため未実装であり、キャッシュもカスタム音声も無い VoiceItem は無音のままになる。本家では編集時に自動生成される点がユーザーから見える差分であり、エンジン供給は将来の差し替え点（この resolver の前段）として残る。

**検証。** Mac 実機（検証コピー ~/ymm4-work/voice51-YMM4Mac）でフルスイート 441 件（既存 432＋新規 9）・失敗 0、ルート＋DebugApp のビルド成功・警告 0（2026-11-18。他担当の検証 2 件と並行実行のため重量級テストに数十分を要した）。Linux でも 432 件・失敗なし。新規テスト `VoiceAudioProviderTests` 9件は Mac 実機で全合格: Brotli 解凍が Google 公式実装で圧縮したフィクスチャ（48kHz/16bit/ステレオ WAV 9644 バイト）とバイト完全一致すること（SHA-256 で照合）、VoiceCache から PCM が供給されサンプル値が元の PCM16 と一致すること、カスタム音声ファイルからの供給、壊れたキャッシュでの無音化、供給なしでの無音、判定・形式推定の単体、ミキサー経由で VoiceItem の音が現れること。**未実施**: .NET の `BrotliStream` が書いた実キャッシュでの検証（本家生成の VoiceCache を持つ実ファイルが手元に無いため。形式は同じ RFC 7932 であり、Google 公式実装の圧縮データで相互運用は実証済み）。実時間再生への供給は Issue #52（再生基盤そのものが未実装）で、同じ `AudioSourceFactory` 経路を使う。

**次の担当へ。** 音声合成エンジンを導入する際は、この resolver の解決順の末尾（エンジン生成）に相当する供給を前段へ追加する形になる。`providerFromTemporaryFile` は factory が全デコード方式である前提で一時ファイルを即削除しているため、ストリーミング方式の factory を導入する場合は所有権の見直しが必要。
#### MAC-0043 — PngWav ライター（PNG 連番＋WAV 書き出し）（Issue #49）

##### 何を実装したか

本家の3系統目のライターである PngWav（`YukkuriMovieMaker.Plugin.
FileWriter.PngWav`）を実装した。出力フォルダへ PNG 連番と WAV を
書き出す。書き出しセッション（ExportSession）から駆動でき、
TimelineExporter にも実合成経路の入口 `runPngWav` を追加した。
書き出しダイアログの形式選択 UI への組み込みは本記録の範囲外
（UI 側の作業単位で扱う）。

##### どこを変更したか

- 新規 `Sources/YMM4Core/Export/PngWavFileWriter.swift`:
  VideoFileWriting 実装（本家 PngWavFileWriter の再現）
- 新規 `Sources/YMM4Core/Export/WavFileWriter.swift`:
  WAV（RIFF）逐次書き出し（本家 Commons の WavFileWriter 相当）
- 新規 `Sources/YMM4Core/Export/PNGEncoder.swift`:
  PNG エンコーダ（純粋 Swift 実装）
- `Sources/YMM4Core/Export/ExportSettings.swift`:
  `PngWavExportSettings` を追加
- `Sources/YMM4GPU/Export/TimelineExporter.swift`:
  `runPngWav(outputDirectory:settings:cancellation:onProgress:)`
  を追加（run() と同じ契約。全尺・進捗通知つき）
- 新規 `Tests/YMM4CoreTests/Export/PngWavWriterTests.swift`（9 件）
- `docs/ARCHITECTURE.md`: Export 配下の3ファイルを行追加

##### どう実装したか

本家仕様の根拠（デコンパイル済みコード）:

- `PngWavFileWriter.cs` コンストラクタ: 引数は出力フォルダ、
  ファイル名、VideoInfo、PNG 有効フラグ、WAV 有効フラグ。
  SupportedStreams は2フラグから決まる。無効なストリームへの
  書き込みは NotImplementedException。
- 同 WriteVideoCore: PNG は `{FileName}_{index}.png`（index は
  0 始まり）、WIC で BGRA・Premultiplied・96 dpi・
  VideoInfo の PixelWidth/PixelHeight でエンコード。
- 同 WriteAudioCore: WavFileWriter（float・Hz・2ch・depth 32・
  formatID 3）。`wavWriter == null || 残量 < サンプル数` のとき
  破棄して `{FileName}_{index}.wav`（0 始まり）を開く。
  1 回の書き込みを複数ファイルに分割しない。
- `YukkuriMovieMaker.Commons/WavFileWriter.cs`: 44 バイトの
  RIFF ヘッダ（fmt 16 バイト、サイズ欄は初期値 0）を書き、
  Dispose でオフセット 4 = 位置 − 8、オフセット 40 = 位置 − 44
  に埋め直す。GetRemainingWritableSampleCount は
  `(int.MaxValue − 現在位置) / depth`（depth はビット数 = 32。
  本家の式をそのまま踏襲）。
- `PngWavFileWriterSettings.cs`: FileName 既定値 "untitled"、
  IsPngOutputEnabled / IsWavOutputEnabled とも既定 true。
  プラグイン定義は OutputPathMode = Directory。
  GetVideoConfigView が FileName = プロジェクト名を代入する
  （UI の副作用）。

Mac 側の設計判断:

- PNG エンコードは WIC の代わりに純粋 Swift のエンコーダ
  （PNGEncoder）。BGRA → RGBA の並べ替え、premultiplied の
  画素値はそのまま保持、カラータイプ 6・ビット深度 8、
  pHYs チャンクで 3780 px/m（= 96 dpi）を宣言する。
  行フィルタは5種から最小絶対和で選択、圧縮は zlib 形式
  （固定ハフマン DEFLATE＋LZ77）。画素は可逆で一致する。
- ファイル系エラーは本家 TryConvertFileException（HRESULT →
  WarningException）相当として、errno から ExportError へ
  分類する。文言は既存の FFmpegErrorClassifier と揃えた
  （容量不足・権限なし・使用中は actionable、それ以外は
  unresolvable に文脈と下位エラーを保持）。
- 本家の設定シングルトン＋UI 副作用（FileName への
  プロジェクト名代入）は再現せず、PngWavExportSettings の
  値として明示的に渡す（W6-C9 の ExportSettings と同じ方針）。
- WavFileWriter のバイト上限は引数 `byteLimit`（既定
  Int32.max = 本家どおり）として差し替え可能にし、分割の
  テストを小さな上限で検証できるようにした。PngWavFileWriter
  にも同じ差し替え点（`wavByteLimit`）を持つ。
- 出力フォルダが無い場合は init で作成する（本家は呼び出し側
  の前提。実利用上の差異として記録）。

##### 検証

- 単体テスト 9 件（Tests/YMM4CoreTests/Export/
  PngWavWriterTests.swift）: WAV ヘッダの各フィールドと
  ペイロードのビット一致、残量式（(2044 − 44) / 32 = 62 等）、
  supportedStreams の組合せ、無効ストリーム書き込みの例外、
  PNG の番号付けと独立デコーダ（テスト側実装の CRC-32・
  inflate・全フィルタ解除・Adler-32 照合）による可逆往復、
  37×23 グラデーションの往復、WAV 分割（上限 2044 バイトで
  100 float × 3 回 → 3 ファイルに各 100 float、4 本目は無い）、
  分割なしの単一ファイル、セッション統合（30 フレーム・
  fps 30・48 kHz → PNG 30 枚 proj_0.png … proj_29.png、
  WAV データ 384000 バイト = ちょうど 1.000 秒）。
- 全スイート: Linux 441 件・失敗 0（従来 432 件 + 新規 9 件）。
  Mac でも全スイートを実行し、新規 9 件を含む 438 件の完了と
  失敗 0 を確認した。残り 3 件は長時間かかる音声ドリフト系の
  既存テスト（本変更と無関係）で、本記録の作成時点ではまだ
  実行中だった（Mac が他作業と競合し、スイート全体の実行に
  通常の数倍の時間を要した）。
- ハーネス Harnesses/media4950-harness（Mac・release）:
  実合成経路から runPngWav を実行し completed、PNG 30 枚、
  WAV 1 秒分、PNG を ImageIO でデコード可能（64×64）を確認。
  同ハーネスで既存の FFmpeg 実エンコード（30 フレーム）も
  completed し、ffprobe の duration = 1.000000 秒を再確認した。

##### 未解決事項

- 書き出しダイアログでの形式選択（現在は mp4 固定表示）と
  PngWav の配線は UI 側の作業単位で未実施。本記録の範囲は
  ライター本体と TimelineExporter の入口まで。
- PNG の圧縮率は WIC と一致しない（可逆性と dpi 宣言は一致。
  圧縮方式の差異は仕様上の等価範囲と判断）。

#### MAC-0044 — Metal 初期化診断（失敗を握りつぶさない）（Issue #50）

##### 何を実装したか

`MetalGraphicsDevices` の初期化が失敗しても理由が残らなかった
問題（監査 AUD-06）を解消した。初期化を failable init から
throws へ変え、失敗の種別と下位エラーを保持する型
`MetalInitializationError` を新設。プレビューと書き出しの
入口で利用者向けの理由文を表示し、自動テストのレポートにも
理由を記録する。種別ごとのフォールバックは作らない（Issue の
方針どおり）。

##### どこを変更したか

- 新規 `Sources/YMM4GPU/Graphics/MetalInitializationError.swift`:
  種別（deviceUnavailable / shaderLibraryFailed /
  shaderFunctionMissing / pipelineCreationFailed /
  samplerCreationFailed / textureCreationFailed）、
  利用者向け理由文 `userMessage`、種別＋下位エラーの
  `description`
- `Sources/YMM4GPU/Graphics/MetalGraphicsDevices.swift`:
  `init?()` を `init() throws` へ。全ての nil 返し・try? を
  対応する種別の throw に置換。シェーダソースを引数で受ける
  初期化子 `init(shaderSource:)` を差し替え点として分離
  （失敗の人為的誘発に使う）
- `Sources/YMM4GPU/Export/MetalExportVideoProvider.swift` /
  `TimelineExporter.swift`: init を throws に伝播
- DebugApp `Export/ExportJob.swift`: MetalInitializationError
  を捕捉し、状態表示に理由文を含める
- DebugApp `Preview/PreviewBox.swift`: 非 failable 化し、
  失敗時は `initializationFailure` に理由文を保持。
  `Views/ProjectView.swift` がそれをプレビューエラーとして表示
- DebugApp `AutoTest/AutoTestRunner.swift`: CompositionSession
  が失敗理由を保持し、合成計測と書き出し計測の双方で
  レポートに理由を記録する

##### どう実装したか

- 本家相当の既存契約: GPU 層の失敗検出は MAC-0021 で
  MetalRenderError（close() から throw）に統一済み。本件は
  その入口側（初期化）で同じ原則を適用したもの。
- 初期化の段階ごとに種別を割り当てた: デバイス取得不可、
  シェーダライブラリのコンパイル失敗（MTLLibrary のエラーを
  文字列で保持）、シェーダ関数の不足（関数名を保持。検査順は
  従来どおり）、パイプライン生成失敗（対象名＋下位エラー）、
  サンプラ生成失敗（対象名）、透明テクスチャ生成失敗
  （寸法を保持）。
- 表示文言は種別ごとに固定の日本語文＋保持した名前・寸法を
  埋め込む形とし、経路（プレビュー／書き出し／自動テスト）
  ごとに別文言を作らない。
- 失敗の再現は、壊れたシェーダソースと関数を欠いた
  シェーダソースを `init(shaderSource:)` に渡すことで行う
  （本番経路と同じ初期化を通る）。

##### 検証

- ハーネス Harnesses/media4950-harness（Mac・release）:
  正常初期化（Apple M2 で成功）、壊れたシェーダ →
  shaderLibraryFailed（理由文「GPU シェーダの初期化に
  失敗しました」、description に MTLLibraryErrorDomain の
  コンパイルエラーを保持）、ymm4MosaicKernel だけを欠く
  シェーダ → shaderFunctionMissing（理由文に不足関数名を
  含む）を実測で確認。全 11 件 PASS。
- Mac ビルド: ルートパッケージ・DebugApp とも警告・エラー 0
  （debug）。全テストは Linux 441 件・失敗 0。Mac でも
  全スイートを実行し 438 件の完了と失敗 0 を確認した
  （残り 3 件は MAC-0043 の検証項に記した長時間の既存
  テストで、本記録の作成時点では実行中）。
- DebugApp の自動テスト（MAC-0039 の方式、一時バンドルから
  実行）で AutoTestRunner の変更経路を実行した。終了コード 0、
  レポートの合成・書き出しとも error なし・書き出しは
  completed で、Metal 初期化エラーは記録されなかった。

##### 未解決事項

- 理由文の画面表示そのもの（GUI のスクリーンショット等）は
  未検証。検証したのは、初期化失敗が種別と理由文を伴って
  入口まで伝播することと、表示先への配線がコンパイルと
  自動テスト実行を通ることまで。

#### MAC-0041 — サウンドレベルメーター（Issue #52 の前提部品）（IMPLEMENTED、Mac / Linux 検証済み）

**どう実装したか。** 本家 `SoundLevelMeter`（YukkuriMovieMaker.Player.Audio）の再現を `Sources/YMM4Core/Audio/SoundLevelMeter.swift` に新設した。1 秒分のサンプル列を受け取り、1/60 秒区間ごとにピーク（区間の最大絶対値、0.001 未満は −60 dB）と RMS を計算してバッファ位置付きで蓄積する。RMS は前回呼び出しの末尾 5 区間と連結した列の、区間開始から 6 区間分の窓で取る（本家の `prevSamples.Concat(...).Skip(...).Take(...)` そのまま）。ラウドネスは内包する BS.1770-3 アナライザ（K 特性フィルタ、400ms ブロック・75% オーバーラップ、直近 30 ブロック保持）が供給し、区間値の Peak 欄に Momentary、Rms 欄に ShortTerm が入る。`setCurrentPosition` は指定位置以前の最新区間値を現在値として採用して古い蓄積を捨て、表示ピークは減衰指定時に 1 回 0.5 dB ずつ下げ、ホールドは新しいピークが上回るか保持位置から 10 秒を超えたときに更新する（本家 `CreateLevelMeterValue`）。シーク時は現在値を保持したままホールドと蓄積だけを破棄する（本家 `Seek`）。公開値は本家どおり Left / Right / Loudness の 3 系統。

**本家との差分。** 構造・意味論の差分はない。K 特性フィルタの係数式は書き出し側の `BS1770LoudnessAnalyzer` と同一の RBJ 式だが、あちらは統合ラウドネス専用でブロック値を公開しないため、ブロック列を持つ別実装として内包した（係数式の重複は意図的。統合は将来の論点）。

**検証。** 新規テスト `SoundLevelMeterTests` 10 件（理論値照合: 定数 0.5 のピーク −6.0206 dB、RMS の 6 区間窓と前回末尾の連結、減衰 0.5 dB、ホールド 10 秒失効、シーク時の現在値保持、無信号の下限）を Linux と Mac の両方で全合格。

#### MAC-0042 — 実時間再生（音声マスタークロック）（Issue #52）（IMPLEMENTED、Mac 検証済み。実機での目視確認は未実施）

**何を実装したか。** プレビューの再生ボタンを実動化した。音声を時刻の正（マスタークロック）とし、映像フレームとレベルメーターをそれに追従させる。本家の該当クラスは `TimelineAudioPlayer`（再生統括）、`AudioPlayer`（NAudio 出力）、`TimelineVideoPlayer`（映像追従）、`TimelineSourceSampleProviderWithLevelMeter`（供給とメーター測定）。

**どこを変更したか。** 新規: `Sources/YMM4GPU/Playback/PlaybackAudioSource.swift`、`Sources/YMM4GPU/Playback/RealtimePlaybackEngine.swift`、`Tests/YMM4GPUTests/PlaybackTests.swift`。変更: `Apps/DebugApp/Sources/YMM4MacDebug/ProjectView.swift`（トランスポート・シーク・メーターの実接続）、`PreviewBox.swift`（合成時の usage 受け渡し）。

**どう実装したか。** `PlaybackAudioSource` は本家の供給プロバイダの再現で、`TimelineAudioMixer` の出力を 2 秒のリングバッファに 1 秒窓単位で先読みし、各窓を `SoundLevelMeter.process` へ通してから読み出しへ回す。終端以降は無音を要求分だけ返し続ける。シークはミキサーとメーターの両方へ伝える。`RealtimePlaybackEngine` は AVAudioEngine + AVAudioPlayerNode で出力し、供給元から 1 秒チャンクを専用キューで生成して最大 2 つ先行スケジュールする（状態変更は世代カウンタで古いチャンクを無効化）。位置は 33ms ポーリング（本家どおり）で `Position = StartPosition + playerTime の消費フレーム数 / Hz` として求め、`timeline.currentFrame` へ同期する。ポーリングのたびに音量を即時反映し、速度・方式の変更を検出したら現在位置からエンジンを作り直す（本家のポーリング内再生成）。速度ノードは本家どおり速度 ≠ 1.0 のときだけ挿入し、リサンプリング = AVAudioUnitVarispeed、タイムストレッチ = AVAudioUnitTimePitch（既定方式は本家の設定既定どおり TimeStretching）。再生中のシークは一時停止してから位置を移し再開しない（SeekBehavior の既定 = Pause）。停止は一時停止＋先頭シーク。終端到達時はリピート有効なら位置だけを開始位置へ戻す（本家 `EndAudioTask` の意味論どおり、再生自体は継続しない）。UI 側はエンジンの位置通知でプレビューフレームを更新し、再生中は合成 usage を `.playing` に切り替える。メーター帯はエンジンの `SoundLevelMeter` の現在値をそのまま表示し、ツールチップは本家の `LevelMeterText` / `LoudnessText` の書式にした。

**本家との差分。** (1) 音量の適用点: 本家はソース側の VolumeSampleProvider、Mac 版は出力段（mainMixerNode）。メーターはどちらも音量適用前のソースを測るため表示値の意味は変わらない。(2) クロックの取得: 本家は WaveOut のデバイス消費時間 × 速度、Mac 版は playerTime の消費フレーム数。速度ノードが消費するソースフレーム数で数えるため等価。(3) 位置の基準点: playerTime のサンプル時刻はノードの再生開始から累積するため、開始位置へ直接加算する。「最初に時刻を取得できた時点を開始とみなす」方式は、その時点までの消費（実測約 0.25 秒）を切り捨てて位置が定常的に遅れるため採らなかった。(4) 映像追従: 本家は次フレームを先行合成して提示時刻を待つ方式、Mac 版はポーリングごとに現在フレームを合成して表示する簡略方式（フレーム落ちの扱いは将来の論点）。(5) Varispeed の速度範囲は 0.25–4.0 で、本家の MFT リサンプラには無い上限がある（TimePitch は 1/32–32 で UI の速度域を全て覆う）。(6) チャンク形式は非インターリーブ Float32（AVAudioEngine の接続はインターリーブ形式を受け付けず、実機で接続例外を確認したため）。(7) シーク時のオフライン・メーター更新は本家の設定既定が無効（`IsSoundLevelMeterUpdateOnSeekEnabled` の既定 false）のため実装しない。

**メモリ・並行性。** エンジンと供給元（ミキサー・工場）は `RealtimePlaybackEngine` が保持し、`dispose` で解放する。状態の読み書きと通知はメインスレッド／メインキューに統一し、チャンク生成キューからの供給読み取りだけを `sourceAccessLock` で直列化する（`@unchecked Sendable` の根拠としてコード内に明記）。

**検証。** Mac 実機（検証コピー ~/ymm4-work/realtime52/YMM4Mac）で新規テスト 9 件（供給元の既知 PCM・メーター反応・終端無音・リング境界跨ぎ、エンジンの位置計算・クランプ・シーク同期）＋ MAC-0041 の 10 件が全合格（集計: 19 tests, 0 failures）。フルスイートは総数 460 件（`swift test --parallel` の進捗表示による実測）全件を実行し、失敗を示す出力行は 0 件だった（並列実行の最終集計行がログに残らなかったため、件数ベースの集計は個別実行分で担保する: 音声まわり既存テスト 37 件＋Voice 9 件も 0 failures を集計取得済み）。ルート／DebugApp とも debug・release の両構成でビルド成功・警告 0。同期精度は実測ハーネス（無音タイムラインの実再生）で測定: 速度 1.0 で 6 秒再生し、位置と壁時計のずれは開始ラグ込みで最大約 0.21 秒、1 秒以降のドリフト（ずれの時間変化）は ±20ms 以内（ポーリング周期 33ms の量子化の範囲）で系統的な時計のずれは検出されず。開始ラグの内訳は play() の所要 82–150ms（AVAudioEngine 構築）と消費開始まで 115–183ms で、本家も再生ごとにプレイヤーを作り直すため同種のラグがある。速度 2.0 では位置が期待どおり約 2 倍速で進行した。終端到達（停止・位置 = 終端）とリピート（位置が開始位置へ戻り再生は停止）の実挙動も同ハーネスで確認した。**未検証**: 実素材（音声ファイル付きプロジェクト）での聴感上の同期、アプリ画面での目視確認（再生中のフレーム追従とメーターの振れ）は本人確認待ち。

**次の担当へ。** 開始ラグの短縮（エンジンの事前構築）、映像側の先行合成方式への移行、K 特性フィルタ係数の `BS1770LoudnessAnalyzer` との統合は、いずれも設計論点として残してある。ストリーミング供給（Issue #54）が入る場合はチャンク生成の前提（ミキサーのプル読み）が変わるため、この層の見直しが要る。

#### SOLA53 — SOLA による音高補正（Issue #53）（IMPLEMENTED、検証の詳細は末尾）

**何を実装したか。** アイテムの再生速度を変えたときの音高補正（SOLA 方式）を実装した。従来は方式（`PlaybackRateAudioProcessingMode`）によらず線形補間のリサンプリングで代替していたため、速度を変えると音程も一緒に変わっていた。今回、アイテムの方式が SOLA のときに本家どおりピッチを保つ経路が有効になった。対象は定数速度（本家 `PlaybackRateSolaTimeStretchEffect`）と可変速度（本家 `VariableSolaPitchCorrectionEffect`）の両方で、書き出しと実時間再生（MAC-0042、同じミキサー経路を読む）の両方に効く。

**本家の仕様（実測した裏取り）。** 本家は全経路で SoundTouch.Net 2.3.2（SoundTouch の C# 移植、本家同梱 DLL）を `SoundTouchProcessor` として使い、パラメータは Tempo / Pitch / Channels / SampleRate のみ設定し、窓パラメータ類はライブラリ既定のままであることを逆コンパイルで確認した。同梱 DLL 自体も逆コンパイルして仕様を抽出した: シーケンス長は tempo の一次式を 40–90ms にクランプした自動値、探索窓は同じく 15–20ms、重なりは 8ms 固定。時間伸縮段は相互相関（正規化、探索窓内は二乗和の差分更新）で重なり位置を全探索し、線形クロスフェードでつなぐ。音程変換は「有効レート = pitch、有効テンポ = tempo / pitch」への分解で、有効レート ≦ 1 ならレート変換→時間伸縮、> 1 なら時間伸縮→レート変換の順に接続し、切替時は処理済み出力と未処理入力を移送する。レート変換は 3 次補間（係数表あり）＋アンチエイリアス FIR（長さ 64、Hamming 窓 sinc、カットオフはレートで切替、係数は合計 16384 へ拡縮し符号方向へ 0.5 を加えた float を 2^14 で割る。同梱版では整数化の切り捨ては行われていない）。方式の決定はアイテム側の `PlaybackRateAudioProcessingMode`（既定 Resampling）で、本家 `EffectedItemSource` が `CreateFixedPlaybackRateEffects` / `CreateVariablePlaybackRateEffects` で処理器を選ぶ。定数速度で速度 0 のときは方式によらずリサンプリング側になる。可変速度の補正は長さを変えず、入力を 1/50 秒ずつ読み、ブロック中央時刻の速度から `pitch = min(1 / |rate|, 4)`（速度の絶対値が 0.001 以下なら 1）を設定してから供給する。プレビュー再生の速度変更（本家 `AudioPlayer`）も既定はタイムストレッチで同じプロセッサを使うが、Mac 版の再生エンジン側は MAC-0042 で AVAudioUnitTimePitch を採用済みであり、本作業の対象はアイテム側のパイプラインに限る（論点として残す）。

**どこを変更したか。** 新規: `Sources/YMM4Core/Audio/SoundTouchProcessor.swift`（処理芯: FIFO・時間伸縮段・レート変換段・プロセッサ全体）、`Sources/YMM4Core/Audio/SolaStreams.swift`（`SolaTimeStretchStream`、`VariableSolaPitchCorrectionStream`）、`Tests/YMM4CoreTests/Audio/SolaPitchCorrectionTests.swift`（新規 9 件）。変更: `Sources/YMM4Core/Audio/EffectedAudioItemSource.swift`（方式で処理器を切替）、`Sources/YMM4Core/Animation/PlaybackRateMap.swift`（`Table.getRate` を追加。本家 `GetRate` のフレーム内線形補間）、`Sources/YMM4Core/Audio/ResamplerStreams.swift`（差し替え点コメントの更新）、`docs/ARCHITECTURE.md`。

**どう実装したか。** 処理芯は抽出仕様の再実装（逆コンパイルコードの複写ではない）で、数値の丸め・演算順序まで仕様に合わせた。ステレオ専用（本家の利用箇所はすべて 2ch）。`SolaTimeStretchStream` は本家どおり、長さ = 入力長 / tempo（無制限は無制限のまま）、シークは位置 × tempo を入力へ転送してプロセッサを再初期化、読み取りは入力を 1 秒ずつ供給し終端でフラッシュする。フラッシュは本家と同じく「期待出力フレーム数 = 入力フレーム数 / (有効レート × 有効テンポ)」の累積式で目標を決め、無音供給で不足を埋めて目標数へ切り詰めるため、総出力数は式どおりに一致し累積ずれが出ない。`VariableSolaPitchCorrectionStream` は長さを変えず、ブロックごとの音程設定と段の接続替え（音程が 1 を跨ぐと有効レートが 1 を跨ぐ）も本家どおり再現した。

**本家との差分。** （1）ユーザー音声エフェクト側の `PlaybackRateEffect` / `TimeStretchEffect`（音声エフェクトとしての再生速度・タイムストレッチ、後者は位相ボコーダ方式も持つ）は、Mac 版では音声エフェクト定義の型付き化自体が未実施のため対象外（アイテム側の速度処理とは別経路）。（2）負の定数速度は本家では `FixedReversePlaybackRateAudioEffect`（内容窓＋反転＋速度）が担うが、Mac 版は従来どおり Reverse → 速度処理器の並びで、方式が SOLA なら反転の後段に `SolaTimeStretchStream` が入る（処理順は本家と同じ）。（3）プレビュー再生の速度ノードは MAC-0042 の AVAudioUnit 系のまま（上記）。

**メモリ・並行性。** 処理芯はストリームごとに所有され、チェーンの強参照で保持される（本家の Dispose 管理に対応）。バッファは FIFO の配列蓄積で、消費側は先頭オフセットで進め、肥大時のみ圧縮する。スレッドは呼び出し側（ミキサーのプル読み）に直列化される前提で、内部にロックは持たない。

**検証。** 新規テスト 9 件（Linux・Mac とも全合格）: 定数 2 倍速・0.5 倍速で総フレーム数が式どおり（48000 / 96000 フレームに一致）かつ基本周波数が 440Hz ±10Hz に保たれること、シーク後の残り長と音程、対比としてリサンプリング方式では 880Hz へ動くこと、`GetPitch` の値とクランプ、可変補正で総数が入力長と一致し音程が保たれること、チェーン接続（方式 SOLA / Resampling の切替、可変＋SOLA）。検証中に判明した注意: 素の `PlaybackRateStream` はチェーン側で打ち切られる前提で自身は終端を返さないため、テストの読み切りヘルパが無限に読み続けてメモリを使い切った（処理器の欠陥ではなくテスト側の問題として修正済み）。Mac 実機: ビルド警告ゼロ、フルスイート 469 件（従来 460＋新規 9）を並列実行し失敗の記録なし、加えて音声関連＋新規の 56 件を選択再実行して 0 失敗を明示確認（内訳: AudioPipeline 20、AudioResamplerQuality 9、AudioSampleAccuracy 11、AudioDrift 7、SolaPitchCorrection 9）。Linux: 新規 9 件は全合格、フルスイートは VM の資源制限で途中終了したため未完（Mac 側で担保）。

**次の担当へ。** 解析リポジトリ側の互換マトリクス同期は PR 側の作業。プレビュー再生の速度ノード（AVAudioUnitTimePitch / Varispeed）を本処理芯へ寄せるかは設計論点として未確定（本家はプレビューも SoundTouch で、方式既定はタイムストレッチ）。

#### STREAM54 — PCM 供給のストリーミング化（Issue #54）（IMPLEMENTED、Mac 検証済み）

**何を実装したか。** 音声素材のデコードを「ファイル全体をメモリへ読み切る」方式から、必要な分だけ逐次デコードするストリーミング方式へ変えた。対象は `PCMProviderFactory` の実体（書き出し・ラウドネス解析・実時間再生のすべてが読む素材供給）であり、呼び出し側（`FileAudioStream`、ミキサー、書き出し、再生供給元）の変更はない。Issue の応急処置（デコード先配列への reserveCapacity）は、全デコード経路そのものを無くしたため不要になった。

**どこを変更したか。** 新規 `Sources/YMM4GPU/Export/AVFoundationStreamingPCMProvider.swift`（`AVFoundationStreamingPCMProvider`）。改修 `Sources/YMM4GPU/Export/AVFoundationPCMProviderFactory.swift`（全体デコードの静的メソッドを削除し、ストリーミング供給元を返す工場にした。メタデータ＝トラック・時間範囲・形式記述の async 読み込みの同期橋渡しは工場側に集約）。改修 `Sources/YMM4GPU/Export/VoiceAudioProvider.swift`（一時ファイルの所有権の変更、下記）。新規テスト `Tests/YMM4GPUTests/StreamingPCMProviderTests.swift`（7 件）。

**本家の仕様（実測した裏取り）。** 本家のファイルソース契約 `IAudioFileSource`（YukkuriMovieMaker.Plugin.FileSource）は `Duration` / `Hz` / `Seek(TimeSpan)` / `Read(float[], offset, count)` のプル型ストリーミングであり、移植側 `PCMProvider` と同型。実体の一つ `MFAudioFileSource`（YukkuriMovieMaker.Plugin.FileSource.MediaFoundation）は SourceReader を保持して逐次読みし、シーク時はプリロール（圧縮音声 300ms、長いシーク 1 秒）を取って目標位置まで読み飛ばす。また素材の開始時刻 `streamStartTime` を保持し、提示時刻から差し引いて論理位置を数える。

**どう実装したか。** 供給元は `AVAssetReader` ＋ `AVAssetReaderTrackOutput`（出力設定は従来どおり float32 / 2ch / インターリーブ）を保持し、`read` の要求に応じて `copyNextSampleBuffer` でデコードを進める。保持するデコード済みサンプルは読み取りバッファの分だけ。シークはリーダーを作り直し（`AVAssetReader` は後方へ戻れない）、開始時刻を目標位置へ置く。返るバッファの提示時刻（PTS）から絶対フレームを数え、目標より前の部分は切り捨てて着地させる（本家のプリロールと同じ発想）。原点はトラックの時間範囲の開始時刻とし、本家の `streamStartTime` 補正と同じにする。シークの tick → フレーム変換は `InMemoryPCMProvider` と同じ最近傍丸め（MAC-0016 で QA 済みの規則を供給元ごとに変えない）。デコード列に欠落がある区間は無音で埋めて進める（途中で止めると呼び出し側が早期終端と誤認するため。本家も時刻基準で読み進める）。素材開始前の負位置は従来どおり無音として数える。

**メモリ・並行性。** 資産・トラック・リーダーは供給元が所有し、破棄時に `cancelReading` する。読み取りは従来どおり単一スレッド前提（ロックなし。ミキサーのプル読みに直列化される）。VoiceCache の一時ファイルは、供給元が読み取りの間ファイルを開いたままにするため、寿命を供給元の寿命へ結び替えた: `VoicePCMProviderResolver` は即時削除（defer）をやめ、`TemporaryFilePCMProvider`（破棄時に削除する包み）を返す。生成失敗時はその場で削除する。本家でも `voiceFile` はアイテムが保持して破棄で消える構造であり、結び先が違うだけで「使う側が持ち、使い終われば消える」点は同じ。

**本家との差分。** （1）全長（`duration`）はデコード総量ではなくトラックの時間範囲から決める。ストリーミングでは終端まで読む前に全長が要るための内部実装の違いで、通常の素材では一致する。（2）読み取り途中でリーダーが失敗した場合は終端として扱う（従来の全デコードは全体の失敗で供給元自体が nil になった）。（3）圧縮形式のシーク着地は PTS 基準で切り捨てるためサンプル単位で正確だが、本家のプリロール方式（読み飛ばし）と結果が一致するかは本家環境での比較未実施。

**検証。** 新規テスト7件を含む GPU テスト25件・音声テスト20件は Mac 実機で 0 失敗を個別に確認。フルスイート実行ログ（Mac `/tmp/stream54-test.log`）に失敗記録は無いが、総計行の確定は担当終了時点で未記録のため、PR 前の統合検証で取る。ハーネス（1時間・691,200,044 バイトの WAV を生成して実測）: 全読み 345,600,000 サンプルを 0.87 秒で処理し、メモリ増加は 19 MiB でファイル長に比例しないこと、末尾付近へのシークが要求フレームへ着地することを確認（ALL PASS、Mac `/tmp/stream54-harness.log`）。

**次の担当へ。** 解析リポジトリ側の互換マトリクス同期は PR 側の作業。1 時間級素材での実測（ハーネス）は検証欄に記す範囲に留まる。

#### GPU45 — 内蔵 GPU エフェクト実処理化 第1弾（Issue #45。IMPLEMENTED、Mac 検証済み。InOutCrash は未実装）

対象5種のうち4種を実処理化した。土台は main `58bcf2b`（PR #82/#83 マージ後）。変更ファイル: `Sources/YMM4GPU/Graphics/MetalGraphicsDevices.swift`（シェーダ4種とパイプライン登録を追加）、`Sources/YMM4GPU/Effects/MetalEffectProcessorsShadowFill.swift`（Outline / Gradient）、`Sources/YMM4GPU/Effects/MetalEffectProcessorsBlurMask.swift`（HalfToneShadow）、`Sources/YMM4GPU/Effects/MetalEffectProcessorsNoise.swift`（新規。Noise）、`Sources/YMM4GPU/Effects/MetalEffectProcessorBase.swift`（登録2スイッチ）。

- **Outline（輪郭）**: 本家 `OutlineEffect.cs` の処理連鎖をそのまま実装した。太さは小数1桁へ銀行丸めした上で `DecomposeThicknessToSteps`（2の冪への貪欲分解、降順）で段分けし、段ごとに OutlineLite 相当（中心＋N方向の最大 α。N = min(Quality, (int)(step×2)² + 1)、標本距離は入力テクスチャ高さ基準の UV ステップ、本家シェーダ `outlinelite.cso` の実測どおり）を適用する。続いて FeatherAlpha（`featheralpha.cso` 実測の smoothstep 式、Smoothness/100)、ブラシ単色の塗りを膨張像でマスク、GaussianBlur(σ = Blur)、Opacity、合成（IsOutlineOnly または移動ありなら DestinationOut、それ以外は元画像を上へ SourceOver)、最後に回転→拡大→平行移動のアフィン（移動がある場合のみ）と切り抜き相当の合成。本家根拠: `OutlineEffect.cs`（DecomposeThicknessToSteps は同ファイル 347 行付近）、`OutlineLite.cs` の出力境界拡張（ceil(StepPx) / 辺）。
- **Gradient**: 本家 `GradientEffect.cs` のとおり、入力矩形へグラデーションを描き（ブラシ変換は回転→平行移動の行ベクトル順、Round は回転なし）、ブレンド後に元画像の α でマスクして戻す。色補間は D2D の Gamma.StandardRgb = 格納値の成分ごとの線形補間（Vortice の CreateGradientStopCollection 既定）。Convex は CPU 側でストップを鏡像化してから Linear として処理する。ExtendMode は Clamp / Wrap / Mirror を t へ適用。Normal 以外のブレンドモードは既存の塗り系プロセッサと同じ方針で Normal 合成へ落とす（差分として記録）。
- **HalfToneShadow**: 本家連鎖（GaussianBlur → 単色化（白・KeepBrightness 反映）→ HalfTone カスタムシェーダ → Opacity → 回転・平行移動 → 元画像を上へ合成）を実装。HalfTone 本体は `halftone.cso`（約3,400 dword）の逆アセンブルから全数式を抽出した: 候補中心ごとに cov = clamp(K・輝度・Size − 距離、0、1)、最大の候補が勝ち、出力 = cov × (勝者のサンプル色 × (1 − Strength) + Color × Strength)。K は Triangle = 1 + Distance/√3、Rectangle / Rhombus = 1 + Distance/√2。候補集合はモード別に逆アセンブルから読み取った格子オフセットそのまま（Rectangle = セル中心の3×3、Rhombus = √2・Distance の四隅＋中心、Triangle = パリティ調整した基点＋7点）。出力境界の拡張は本家 `HalfTone.cs` の ceil((Distance/2)・√2) / 辺。モード値 1 以外の未知値は本家どおり Rhombus 分岐へ落ちる。
- **Noise**: 本家 `NoiseEffect.cs` の配線（生成器の赤成分だけを NoiseBlend で入力へ乗算。IsColor なら R/G/B 別生成器でシードオフセット +100/+200/+300、IsAlpha なら A が +0、使わないチャンネルは白 = 係数1）と、`BasicNoiseParameterBase.SetParameterTo` の定数変換（X/Y/Z は速度×アイテム内フレームを加えて剰余、Scale は 100 / max(0.001, 値 × Size/100)、Seed はオフセット % 1234、Angle は符号反転してラジアン化）を実装。生成器3種をシェーダ逆アセンブルから抽出して実装した: **Random = 値ノイズ**（格子ハッシュは整数演算まで完全抽出。定数 0xAE3CC725 ほか4定数、折り返し h ^= h.wxyz ^ (h >> 13)、s ^= s >> 11、s ^= s·s、値 = s / 2³²）、**Fractal = 値ノイズのオクターブ蓄積**（FractalMode の整形3種を含む）、**Curl = シンプレックスノイズの差分**（シンプレックス本体は本家変種の定数まで抽出: permute の +10、減衰 (0.5 − |x|²)⁴、出力 ×52.5 + 0.5)。後処理連鎖（Threshold 引き伸ばし → Strength 変換 → Levels 量子化（round half to even、Levels = 255 のときだけ素通し）→ saturate）は3シェーダ共通の尾部から抽出。ワープ前段（WarpStrength ≠ 0 のとき）も抽出どおり実装したが、実プロジェクトの全実例は WarpStrength = 0 で未使用。
- **InOutCrash は未実装（本弾の対象外として確定）**: 本家は `CrashMeshBuilder` がアイテムの GetHashCode を種にメッシュを破砕し頂点シェーダで変形する（`InOutCrashEffect.cs` ほか計約960行＋ `meshdeformation*.cso`)。種は .NET のオブジェクト同一性ハッシュで本家実行ごとに非決定的であり、移植側 GPU 層には全面四角形・コンピュート以外の汎用メッシュ描画経路が無い。別作業単位（メッシュ描画基盤）として切り出すのが妥当と判断し、現行の素通しを維持した。
- **本家との差分・未確定事項**: (1) Curl のオクターブ評価点の組（±0.1 の軸対応）は逆アセンブルから完全には確定できず、(0, ±0.1, 0) の組を採用した近似である（係数 0.78125 と整形・蓄積は抽出どおり）。(2) Noise の IsColor=false かつ IsAlpha=false の経路（1生成器が R/G/B を兼ねる）のシードオフセットは本家コードから確定できず +0 とした。実プロジェクトでは未使用の経路。(3) IsUniqueSeed のシード基礎値はパラメータの .NET GetHashCode で、対応付け未確定のため 0 とした（実プロジェクトの全実例は IsUniqueSeed = false)。(4) Threshold = 1 のときの除算は本家では 0 除算になるため分母に下限 1e-6 を置いた。Fractal の Octaves = 0 も同様に 0 とした。(5) Noise の残り7種（Block / Perlin / Cellular / Voronoi / Simplex / Marble / Flow）は生成器未抽出のため素通しのまま（定義が来ても従来どおり素通しになる）。(6) HalfTone の Triangle 候補集合はレジスタ追跡を伴う抽出で、画素単位の照合は粗検証のみ（ドット画素の存在と範囲外 α = 0 を確認）。Rectangle / Rhombus は予測値と一致する画素を確認済み。(7) Gradient の Round で Size = 0 のとき本家は 0 除算になるため halfSize に下限 0.01 を置いた（Linear と共通の本家式 max(Size/2, 0.01) の適用範囲を Round へ広げた形）。
- **検証**: Mac 実機で `swift build` 成功・警告 0。全テスト 444 件・0 失敗（変更前と同数。GPU の画素検証はテストターゲットでなく専用ハーネスで行う既存方針）。画素検証ハーネス（gpu45-harness、43 項目）全合格。主な実測: Outline の太さ分解 0.9 → [0.9]、3 → [2, 1]、500 → [245, 128, 64, 32, 16, 8, 4, 2, 1] が本家アルゴリズムと一致。Gradient の線形・Round・Convex・不透明度は予測値と一致（Convex は全点一致）。Outline の輪 α = 248（フェザー込みの予測どおり）、輪のみで中心 α = 0、太さ 0 で恒等、Smoothness 0 で輪 α = 255。HalfTone は Rhombus の飽和ドットが解析予測の画素に出現し、境界拡張 5（Distance 6.1）を確認。Noise は IsColor の3シード（100/200/300）の出力が独立実装（Python で同式を再現）した予測と標本4点で全チャンネル完全一致し、Random / Fractal / Curl とも平均 ≈ 127.5・決定性（2回描画でバイト一致）・非定数を確認。Strength 0 で恒等、Levels 2 で二値化、Threshold 50 で約半数が 0 へ落ちることも確認した。なお検証中の不具合1件を修正した: 白チャンネルを 1×1 テクスチャで代用すると線形サンプラの足跡が境界色（透明）と混ざり係数が 1 にならないため、入力と同寸法の白テクスチャへ変更した。全テスト実行時は他担当（#51・#49/#50）の検証と競合し、実時間で約50分を要した（結果に影響なし）。
- **次の担当へ**: InOutCrash はメッシュ描画基盤の作業単位として別途切り出すこと。Noise 残り7種は生成器シェーダ（blocknoise ほか）の逆アセンブル抽出から着手する。HalfTone Triangle の画素単位照合は候補集合の再追跡が必要。

#### BRUSH46 — ブラシ基盤: 型付きブラシモデルと GPU 塗り（Issue #46。IMPLEMENTED / Mac 検証済み。MAC 番号は PR 時に付番）

- **何を**: 本家のブラシ（単色以外のグラデーション・パターン・ビットマップ等の塗り指定）を型付きモデル化し、GPU で描けるようにした。従来は Shadow / FillBackground / FillForeground / FrameLine の4エフェクトが単色ブラシ以外を素通しし（GPU28-02 の記録）、図形の塗りは単色以外を白で代用していた。
- **モデル（Core）**: 新規 `Sources/YMM4Core/Model/BrushParameters.swift` に本家組み込みパラメータ9種のうち8種を型付き化した（LinearGradient / RadiulGradient（本家の綴りのまま）/ Checkered / Dot / Stripe / GridLine / Bitmap / Noise）。既定値・定義範囲・フィールド順は本家デコンパイル済みコード（`YukkuriMovieMaker.Brush` 配下の各 `*BrushParameter.cs` / `*BrushSource.cs`、`DrawingBrushParameterBase` / `ScalableDrawingBrushParameterBase`）の実測どおり。`BrushParameter` 列挙へ8ケースを追加し、`$type` で振り分ける。未知キー（将来追加分）は従来どおり追加フィールドとして往復保持する。
  - **グラデーションメッシュは型付き化しなかった**（生保持のまま）。点・ハンドルの保存形式が実ファイルで未確認であり、描画（Coons パッチ構築）も別単位の規模になるため。#45 で InOutCrash をメッシュ基盤の都合で分離した判断と同じ扱い。
  - **Noise の内部 NoiseParameter は生保持**にした（Core の Noise エフェクトと同じ方針）。外側の型付きフィールド（NoiseType / Color1 / Color2 / IsColor / IsUniqueSeed）だけモデル化した。
  - `Brush` にオブジェクトでない値の生保持（`nonObjectRawValue`）を追加し、旧・生保持経路と等しく壊れた値でも往復で落とさないようにした。null の Brush は従来どおり nil（キー自体を出さない）。
  - 4エフェクト定義（`ShadowFillEffects.swift`）の `brush` を `PreservedObject?` から `Brush?` へ変更し、ブラシ内 Animation を定義の `forEachAnimation` へ登録した（キーフレーム文脈がブラシ内アニメーションへ届くようにするため。本家では Brush 自身が Animatable で Parameter を子に持つ）。図形の `StrokeShapeParameterBase.forEachAnimation` もブラシ走査を追加した。
  - **変換しなかったブラシ保持箇所**（残作業として明記）: Outline の strokeBrush（Metal 処理器が未マージの #45 ブランチ側にあり、衝突回避のため触らない）、InnerShadow の brush、DisplacementMap の brush（いずれも現行 main に Metal 処理器が無い）。
- **GPU 塗り**: 新規 `Sources/YMM4GPU/Effects/MetalBrushFill.swift`（`MetalBrushFillRenderer`）とシェーダ `ymm4BrushFragment`（`MetalGraphicsDevices` へ brushPipeline と repeatSampler を追加）。ブラシをフレーム評価して `BrushFillSpec`（Equatable な評価済み仕様）へ変換し、平面座標で解析的に評価する。幾何は本家ソースの実測式どおり:
  - 線形: Pixel モードは原点基準の絶対座標（始点 = v・(−Size/2 + Offset)）、Relative モードは境界の射影長 L = W・|vx| + H・|vy| 基準（`LinearGradientBrushHelper.CalculatePoints`）。
  - 放射: 旧 Update のみ実装で Bounds を使わない絶対幾何。焦点 = 中心 + (Origin・zoom・aspect係数)、半径も同係数。ブラシ変換は回転→左右反転。D2D の楕円族 center(t) = F + t・(C − F) を二次方程式で解き、大きい方の根を採る（ハーネスで前向き計算の期待値と一致を確認）。
  - 市松・ドット・格子線: 本家はタイルビットマップ + BitmapBrush（Wrap）だが、こちらは逆変換後の座標で解析判定する。**既知の差分**: パターン境界の約1pxの縁の柔らかさ（本家は MultiSampleLinear 補間で縁が滲む）が無い。
  - ストライプ: 本家どおり幅・オフセットへ zoom を掛けた線形グラデーション（分岐点4点・Wrap）として線形モードへ畳んだ。
  - ビットマップ: 画像ファイルのみ（ImageIO デコード。動画ファイルは未対応で素通し）。変換は平行移動（−幅/2, −高さ/2。整数除算）→ 拡縮 → 描画変換。パスは絶対パス／file URL のみ解決する（エフェクト側にプロジェクト基準フォルダが届かないため。相対パスは未解決として素通し）。補間は D2D ビットマップブラシの既定（線形）と仮定した（本家ソースで明示設定は未確認）。
  - グラデーションの分岐点補間は成分線形（本家 Gamma.StandardRgb 相当）→ Premultiplied 化で、#45 の Gradient 実装で検証済みの規約と同じ。分岐点は Offset 昇順へ並べ替え、128点超は未対応（素通し）。
  - 格子線の Zoom 評価は本家が GetValue(frame, length, frame) と fps 位置へ frame を渡す不整合を持つが、こちらは通常評価とした（アニメーションしない限り一致する。**論点として残す**）。
- **処理器の接続**: 4処理器とも単色経路は従来のまま不変更とし、単色でない場合だけ「ブラシ塗りを効果ごとの境界で描き、各効果の被覆（入力α・角丸被覆・帯矩形）で切り取る」経路を追加した。本家がブラシの Update へ渡す境界はエフェクトごとに実測で確定した（Shadow = 入力境界、FillForeground = 入力境界、FillBackground = 拡張・正規化した塗り矩形、FrameLine = 種別ごとの帯の外接矩形）。GPU で描けないブラシ（メッシュ・ノイズ・生保持・ビットマップ動画等）は従来どおり素通し。図形 Source（`MetalShapeSource`）は再描画キーへ評価済み仕様を含め、被覆率×ブラシ塗りで描く。描けない場合は従来の白代用へ倒す。EffectItem のマスク形状（`MetalEffectSources`）も同じキー構築へ追随した。
- **検証**:
  - Core 単体テスト新規15件（`Tests/YMM4CoreTests/Model/BrushParameterTests.swift`: 8種の往復＋未知キー保持、メッシュ／コミュニティの生保持、非オブジェクト値の保持、4定義の Brush フィールド往復とアニメーション走査・キーフレーム到達）全合格。
  - Mac 実機: `swift build` 成功・警告0。全テスト459件のうち重い音声3スイート（AudioDrift / AudioResamplerQuality / AudioSampleAccuracy、計27件）を除く432件を並列実行し全合格・終了コード0。音声3スイートは本変更の差分に音声ファイルが含まれないため分離し、別途バックグラウンドで実行した（結果は PR 側で最終確認）。直列実行では AudioDriftTests.testResamplerChainDriftFiveMinutes 単体がデバッグビルド＋他担当の並行負荷の下で12分以上を占有したため、並列実行へ切り替えた経緯がある。
  - 画素検証: 新規 `Harnesses/brush46-harness` 42件全 PASS（線形 Relative/Pixel/90°、Shadow のグラデーション、放射＋焦点ずれ放射（前向き計算の期待値）、市松の枠線、ストライプ、ドット、格子線、ビットマップ、図形のグラデーション塗り、未対応ブラシの素通し回帰）。回帰として `Harnesses/mac0028-harness` 90件全 PASS（単色ブラシの画素は従来と一致）。
  - 実ファイル（upload.ymmp、単色ブラシ105件を含む）そのものの往復は、ファイルに絶対パスが含まれリポジトリへ同梱できないため未実施。実ファイルと同形の JSON（バージョン付きプラグイン型名を含む単色ブラシ）での往復を上記単体テストで担保した。
- **未確認・論点**: (1) グラデーションメッシュの型付き化と描画は別単位。(2) ノイズブラシの GPU 描画はノイズ生成器自体が未実装（Noise エフェクト側も素通し）で待ち。(3) ビットマップブラシの動画ファイル・相対パス解決。(4) パターン境界の約1px差（解析判定 vs 本家のタイル＋線形補間）。(5) 格子線 Zoom の本家評価不整合を再現するか。(6) Outline / InnerShadow / DisplacementMap のブラシ型付き化（Outline は #45 マージ後）。

#### TRANSFORM47 — 変形・不透明度つき入力に対する共通規則（Issue #47）（IMPLEMENTED）

**何を実装したか。** GPU エフェクトの Metal 処理器が共通して持っていた「入力の実体に恒等でない変換があるか不透明度が 1 でない場合は、効果を適用せず素通しする」という基底ガード（MAC-0028 の台帳 (e) で「実プロジェクトでの発動頻度は未測定」と記録されていたもの）を、共通規則へ置き換えた。プレーンでない入力は、基底が実体化（変換と不透明度を新しいテクスチャへ焼き込む）してから各処理器の `render` へ渡す。これにより、変形・不透明度つき入力でもエフェクトが効く。

**どこを変更したか。** `Sources/YMM4GPU/Effects/MetalEffectProcessorBase.swift`（`MetalEffectProcessor.update` の素通し分岐を廃し、`materializedInput(_:)` を新設。基底クラスの前提コメントを書き換え）、`Sources/YMM4GPU/Graphics/MetalGraphicsDevices.swift`（診断カウンタ `materializedInputCount` / `noteMaterializedProcessorInput()` を追加）。新規ハーネス `Harnesses/transform47-harness/`。Core は無変更。

**どう実装したか。** 実体化は2段で、(1) 変換つき入力は `MetalDrawingEffect.boundingRect` で変換後の外接矩形を求め、既存の `renderTransformed`（AffineTransform2D / Transform3D の実体化に使う既存パス）で焼き込む。(2) 不透明度つき入力は色変換パスの mode 7（LinearTransfer）で全成分へ不透明度を乗算する。変換の実体化は不透明度を引き継がないため、不透明度の判定と適用は入力側の値で行う。実体化した入力はデバイスの診断カウンタへ1件記録される（変換と不透明度の両方があっても1件）。`modifiedDrawDescription` フックへは従来どおり実体化前の入力実体を渡す（本家の処理器が読む入力の局所境界は変換前の境界であることに対応）。プレーンな入力は従来と同一経路（比較2回のみ）で、挙動は変わらない。

**本家との裏取り。** 本家には素通しガードは存在しない。本家の処理器は入力 `ID2D1Image` を D2D エフェクトへ `SetInput(0, input, true)` でそのまま渡し、変換つき入力でも効果が効く（`GaussianBlurEffect.cs`、`InvertEffect.cs`）。本家の連鎖構成も移植側と同じで、アイテム変形（DrawingEffect = AffineTransform2D → Crop → Transform3D → ColorMatrix）は連鎖の最後に適用される（`EffectedSourceOutput.cs` の Update、`DrawingEffect.cs`）。実体化という方式自体は本家にも先例がある（FrameBufferSource 系が蓄積画像を Flood → SourceOver → Crop で実体化して後段へ渡す。MAC-0035 で確認済み）。

**なぜその実装なのか（方式の選択）。** 候補は2つあった。(a) 実体化方式（採用）: 基底で焼き込んでから渡す。各処理器の `render` の前提（入力はプレーン、テクスチャ寸法と境界が対応する）がそのまま保たれ、変更は基底1箇所に閉じる。(b) 伝播方式: 本家 D2D のように入力の変換・不透明度を出力へ引き継ぐ。各処理器の境界計算（ぼかしの境界拡張、モザイクのセル等）が変換を前提にしておらず、処理器ごとの手当てが必要になり変更量と不整合のリスクが大きい。Issue の対応方針が「入力をいったん実体化してから処理する等」と実体化を第一候補に挙げていることとも一致するため (a) を採った。

**不透明度の焼き込み方式（全成分乗算）の根拠。** MetalImage の不透明度は消費側（`MetalRenderTarget` の描画シェーダ）が `color * opacity` で全成分へ乗算する意味論であるため、実体化も全成分乗算で焼き込み、実体化の前後で最終合成が変わらないようにした。本家の ColorMatrix は M44 のみへ不透明度を掛ける（`DrawingEffect.cs` の opacityEffect 行列で実測）が、そちらは DrawDescription 層の不透明度の消費方式であり、層が違う。なお既存の `MetalDrawLazyProcessor` は DrawDescription 層の不透明度を mode 7 の (1, 1, 1, opacity) で焼き込んでおり（本家の M44 方式に一致）、MetalImage 層の規則とは別に扱った。本件では変更していない（論点として残す）。

**本家との差分。** (1) 本家の D2D エフェクトは入力の変換を出力へ伝播させる（焼き込まない）ため、ぼかし等の局所処理は変換前の座標系で効く。こちらの実体化では変換後の画素へ効果が効く。拡大された入力へのぼかし幅の見え方などが変わりうる。(2) 実体化で補間が1回増える。いずれも、現行の連鎖でプレーンでない入力自体が発生しないため、観測されるのは将来 Source や処理器の出力が変換・不透明度を持つようになった場合に限る。

**発動頻度の測定（Issue の対応方針の第一段）。** 静的測定: 本人の実プロジェクト2件（upload.ymmp 158アイテム / upload-2.ymmp 142アイテム）を数えたところ、GroupItem・TransitionItem・EffectItem・SceneItem は両ファイルとも 0 件で、アイテム種別は Audio / Image / Shape / Video / Text のみ。現行の全 Source 出力・全処理器の出力・描画先の出力はいずれもプレーンな実体しか出さないことをコードで棚卸し済みであり、処理器入力が非プレーンになる構成要素は実プロジェクトに存在しない。実行時測定: 新規ハーネスの測定モードで両ファイルを読み込み、エフェクト持ちアイテムがアクティブなフレームを最大40フレームサンプリングして合成したところ、実体化の発動は両ファイルとも **0 回** であった。すなわち旧ガードの素通しも実際には発動していなかった。本規則は現時点では「暗黙の不変条件が将来壊れた場合に、エフェクトが黙って効かなくなる事態を防ぐ」ためのものとして位置づける。

**検証。** Mac 実機（検証コピー ~/verify-transform47/YMM4Mac）: ルートパッケージ `swift build` 成功。新規ハーネス transform47-harness **13 件全 PASS**（不透明度つき入力＋Invert、回転つき入力＋Invert、拡大つき入力＋GaussianBlur、回転＋不透明度の複合＋Invert、プレーン入力の回帰、素通し処理器でも実体化が保持されること、各ケースでのカウンタの増分）。画素の期待値はシェーダ式からの解析値（Invert は (A−R, A−G, A−B, A)、不透明度 0.5 の焼き込み後は (100, 50, 25, 128) 等）。検証の過程で、不透明度の焼き込みを (1, 1, 1, opacity) とした初版では RGB が乗算されず期待値と一致しないことをハーネスが検出し、全成分乗算へ是正した（上記の根拠どおり）。既存ハーネスの回帰: mac0023 = 25、mac0025 = 18、mac0026 = 19、mac0027 = 15、mac0028 = 90、mac0034 = 25、mac0035 = 27 の全件 PASS（いずれも従来件数と一致・FAIL 0）、mac0033 は通常ケース ALL PASS（失敗ケースは既知の制約で SKIP）、mac0031 は全体合成の数値プロファイルが従来記録と完全一致（165,763px・高さ137px）。Mac 全スイートは **444 件・失敗 0**（`swift test --parallel`、全件列挙と失敗マーカー皆無で確認。他担当の検証と競合し、重い音声スイート3件の完了に長時間を要した）。ルート＋DebugApp のビルド成功（警告 0。製品コード全体を依存に含むハーネスの release ビルドでも警告・エラーなし）。Linux テストは本変更が YMM4Core を含まない（YMM4GPU は Linux では空モジュール）ため参考確認として実行したが、VM の共有 CPU では音声系の重いテストが完了せず、最終確認時点で実行継続中である（Mac 側の同一 444 件の全合格を正本とする）。本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**次の担当へ。** 論点: (1) DrawLazy の不透明度焼き込み（DrawDescription 層、M44 方式）と MetalImage 層の規則（全成分乗算）の不整合は既存事項として未検証。本家の実コードは M44 方式であり、描画段の全成分乗算との合成結果の差は別途検証が要る。(2) 伝播方式との差（ぼかしの座標系）は、非プレーン入力を出す Source が将来実装された時点で再評価する。(3) 診断カウンタはデバイス単位の累計であり、リセット手段は無い（測定は前後差分で取る）。

#### MOSAIC48 — モザイクの非矩形対応とサイズアニメーション評価（Issue #48）（IMPLEMENTED、Mac 検証済み。本家との画素一致は下記の範囲）

**何を実装したか。** モザイクエフェクト（本家 `YukkuriMovieMaker.Project.Effects.MosaicEffect`）の残件2件を解消した。(1) 非矩形モザイク（円形・三角形・六角形・ボロノイ・ドロネー）が素通しだったのを実処理にした。(2) モザイクの Size アニメーションが定義側で不完全にしか復元されず（ベジェ曲線が落ちる）、キーフレームも伝播しなかったのを、他のエフェクトと同じ評価規則に揃えた。

**本家根拠。** 形状は `MosaicType` の宣言順（Circle / Triangle / Rectangle / Hexagon / Delaunay / Voronoi）。6形状のパラメータクラスはいずれも `SizeMosaicParameterBase` を継承し、保持プロパティは Size（Animation、既定 10、範囲 0–2000）のみで、`SetParameterTo` も Size だけを渡す。描画は Player 側カスタムエフェクト（Direct2D）が担い、Size の setter クランプは全形状 1–5000。シェーダ6種の DXBC 逆アセンブルから抽出した式を仕様として再実装した（逆アセンブル文自体は実装へ複写していない）。Delaunay / Voronoi の Seed は本家ではパラメータ生成時に `GetHashCode()` で決まる実行時値で、ファイルには保存されない。

**どこを変更したか。** 新規 `Sources/YMM4Core/Model/MosaicParameter.swift`（形状6種の型付きパラメータ。$type で判別し、未知の型は `.preserved` として生保持へ倒す）、`Sources/YMM4Core/Effects/GPU/BlurEffects.swift` の `MosaicEffectDefinition`（`mosaicParameter` を生保持から型付きへ変更、ベジェを含む完全な Animation 復元と `forEachAnimation` によるキーフレーム伝播を追加）、`Sources/YMM4GPU/Effects/MetalBlurMosaicProcessors.swift` の `MetalMosaicProcessor`（部分デコードを廃し、Size を通常のアニメーション評価で取得）、`Sources/YMM4GPU/Graphics/MetalGraphicsDevices.swift` の Warp フラグメントへ mode 7–11（円形・三角形・六角形・ボロノイ・ドロネー）を追加。検証資産として `Harnesses/mosaic48-harness/`（画素ハーネス＋参照実装＋期待値生成スクリプト）を新設。

**どう実装したか。** 定義層は ShapeParameter / Brush と同じ型付き＋生保持フォールバックの形にした。処理器は Size を `value(atFrame:length:fps:)` で評価して 1–5000 にクランプし、矩形は既存の矩形モザイク描画、他5形状は Warp 経路で代表点を計算して線形サンプルする。座標基準は本家シェーダの SCENE_POSITION（入力平面座標）に合わせた。Seed は既存の `VideoEffectDefinitionBase.randomSeed`（GetHashCode の代替として用意されていたが未使用だったもの）を渡す。

**本家との差分（ユーザーから見えるもの）。**
- 矩形モザイク: 本家シェーダはセル内5点の平均だが、従来の移植はセル内全テクセルの平均で、本作業の範囲外として据え置いた（従来差分の継続）。
- 円形モザイクの格子位相: 中心 = (round(pos/Size) + 0.5)・Size の字面どおりで、格子は中心側へ寄る（円の外側が広く透明になる）。本家字面の再現であり意図的な選択。
- Delaunay のブロック選択: 本家は角度和（winding）と atan2 近似多項式でブロックを選ぶが、移植は三角形所属による幾何学的な等価判定へ置き換えた。非凸四角形と境界では本家と違う三角形を選ぶ場合がある（下記検証の範囲では参照と一致）。
- 出力範囲の拡張: 本家のカスタムエフェクトは形状ごとに描画範囲を広げるが、Player 側の `MosaicEffect` は DrawDescription を変えず最終描画は入力範囲で切れるため、移植でも入力範囲のままにした。
- Voronoi / Delaunay の散らばり: 本家は Seed が実行ごとに不定で、GPU の sin 実装にも依存するため、安定した「本家の出力」が存在しない。移植は数学的に正しい sin へ寄せた決定的な散らばりにした（Metal の sin は引数が大きいと粗く、実測で fract 値が 1/128 刻みに量子化されたため、Cody-Waite 分割で引数削減してから sin を計算する）。

**検証。** Mac 実機でルートパッケージビルド成功・警告0。画素ハーネス（64×64、識別パターン入力、参照は逆アセンブル抽出式の独立実装＋線形サンプルの再現）: 円形・三角形・六角形は Size 16／10／12／20 で全画素一致（不一致 0px）。サイズアニメーション（直線移動 8→24）は先頭フレーム全画素一致、最終フレーム 5px（0.122%、円の半径境界の float 判定割れ）。ボロノイ／ドロネーは独立参照と 11〜218px（0.269〜5.322%）の不一致が残るが、特徴点ハッシュの実測値を参照へ差し替えた照合では全ケース 0px となり、差がハッシュの float32 丸め（81セル中9セルで最大 0.066 の差）だけに由来することを確認した。未知の形状パラメータは素通しになることも確認した。Core テストは GPUEffectsTests にモザイクの往復・ベジェ保持・キーフレーム伝播の4件を追加。Mac フルスイートは 447 件・0 失敗（所要 3936 秒。うち AudioDriftTests 7件が 2016 秒を占める重量級で、分離せず単一実行で完走させた）。

**未解決。** Seed と本家の GetHashCode の対応（対応付け自体が不可能で、散らばりの再現性は本家にも無い）。Delaunay の非凸四角形・境界での本家 winding 判定との等価性（参照実装同士の一致までで、本家実出力との比較は Seed 不定のため実施不能）。矩形の5点平均への是正は別件。

#### TRIM55 — 素材の提示タイムスタンプとトリム（Issue #55）（IMPLEMENTED、Mac 検証済み）

**何を実装したか。** 音声・映像素材の提示開始位置（提示タイムスタンプ）を論理時刻の基準にそろえた。従来の音声供給はトラックの時間範囲の開始を原点にしていたため、提示開始オフセットを持つ素材（前方に提示上の無音区間がある素材）では、オフセット分が無音として前に残り、全長にも混入して配置がずれていた（内部課題 EX26-03 の後半。実測: 開始時刻 +2 秒の MOV で全長が 4.0 秒になり、音が論理フレーム 120001 から始まった）。あわせて、シークの着地方式を本家と同じ「プリロール＋提示時刻での着地」に変えた。目標位置から直接読み始めると、形式によってはデコーダの遅延補正が外れて内容が提示時刻からずれるためである（MP3 で実測: 1.5 秒へ直接シークするとトーン終了境界でトーンが鳴り、0.5 秒では開始が約 500 フレーム遅れた）。

**どこを変更したか。** 改修 `Sources/YMM4GPU/Export/AVFoundationPCMProviderFactory.swift`（トラックのセグメントを読み、提示区間＝最初の非空セグメントの提示開始位置から最後の非空セグメントの提示終端まで、を計算する `presentationRange` を追加。映像側と共有するため internal）。改修 `Sources/YMM4GPU/Export/AVFoundationStreamingPCMProvider.swift`（初期化子が提示区間を受け取り、全長・提示時刻の原点・リーダーの終端をすべて提示区間基準にした。シーク時のリーダーは目標の 1 秒前から作り、提示時刻で着地する）。改修 `Sources/YMM4GPU/Sources/Media/MetalVideoSource.swift`（映像も同じ規則: 提示区間から提示長と提示開始位置を求め、フレーム取得時に提示開始位置を加算して資産タイムラインへ読み替える。全長＝提示長になり、`VideoItem.contentLength` への反映も提示長になった）。新規テスト `Tests/YMM4GPUTests/PresentationTimestampTests.swift`（3 件）。新規ハーネス `Harnesses/trim55-harness`（供給元の実測＋資産診断＋映像診断）。

**本家の仕様（実測した裏取り）。** 本家のファイルソースは音声・映像とも同型の補正をする。`MFAudioFileSource`（YukkuriMovieMaker.Plugin.FileSource.MediaFoundation）は最初のサンプルの `SampleTime` を `streamStartTime` として保持し（ReadFirstSampleTime、負値は 0）、`Duration` から差し引き、シーク時は論理時刻に加算して絶対時刻へ戻す。着地はサンプルの `SampleTime` と比較し、目標より前の部分をバッファ内オフセットで読み飛ばす。プリロールは圧縮音声 300ms、.mts/.ts/.mp3 は 1 秒。`FFmpegAudioFileSource`（同 FFmpeg）はストリームの `start_time` を `streamStartTime` とし（L147–154）、`Duration` はストリームの長さ、シークは 1 秒前から読み直してフレームの `best_effort_timestamp` で着地する（L465–478）。`MFVideoFileSource` も最初のサンプルの SampleTime で同型の補正をする（L206–231、L463）。アイテム側の `AudioItem.ContentLength` はファイルソースの `Duration` そのものである（AudioItem.cs L243–262）。MP3 専用プラグイン（FileSource.Mp3）は未逆コンパイルのため内部は未確認。

**どう実装したか。** AVFoundation の世界で提示開始位置に対応するのは、トラックのセグメント列における最初の非空セグメントの `timeMapping.target.start` である（提示開始オフセットは空セグメントとして表現される。実測で確認）。論理時刻 0 = その位置、全長 = 最後の非空セグメントの提示終端 − 提示開始位置。セグメントが読めない・非空が無い場合は従来どおりトラックの時間範囲へ倒す。シークはリーダーを目標の 1 秒前（提示開始位置とトラック範囲の先頭でクランプ）から作り直し、返るバッファの提示時刻から提示開始位置を差し引いて論理フレームへ数える。着地の丸め規則（最近傍）は MAC-0016 の既存規則のまま変えていない。AAC のエンコーダ遅延（priming）は、編集リストで提示から外れている素材では従来から正しく落ちていた（実測で不変を確認）。編集リストで外れていない素材では提示に含まれるのがコンテナの意味論であり、本家 FFmpeg 経路の実測（ffmpeg デコードとの照合）でも同じ位置になったため、追加の除去はしない。

**本家との差分。** （1）提示開始位置の取得元が「最初のサンプルの提示時刻」ではなく「セグメントの提示配置」である（内部実装の違い。空セグメント区間にも無音バッファが提示時刻付きで返るため、最初のバッファの提示時刻では提示開始位置を特定できないことを実測で確認した）。（2）プリロール量は形式によらず一律 1 秒（本家 FFmpeg 版と同じ割り切り。MF 版は形式依存）。非圧縮素材では不要な分も最大 1 秒分だけ先行デコードするが、着地は提示時刻で決まるため内容は変わらない。（3）映像の提示開始前の区間について、本家は「フレームなし」を返すが、移植側は AVAssetImageGenerator が範囲外でエラーを返すため前フレーム維持／透明に倒れる（見た目の差として残る）。

**検証。** YMM4GPUTests 28 件（新規 3 件を含む）は Mac 実機で個別実行し、総計行付きで 0 失敗を確認。フルスイート 479 件は Mac で並列実行（`swift test --parallel`、ログは Mac `/tmp/trim55-test.log`）し、全 479 件の開始と、失敗・エラー・断言失敗の痕跡 0 件を確認した（SwiftPM の並列モードは総計行を出力しないため、総計は開始件数と失敗痕跡で担保する）。ビルド警告 0。ハーネス実測（素材は「無音 0.5 秒＋440Hz トーン 1.0 秒＋無音 0.5 秒、48kHz」が正解）: WAV（従来素材）は全長 2.0 秒・トーン [24001, 71999]・シーク着地誤差なしで従来どおり。AAC（編集リストで priming を外す M4A）も同値で不変。開始時刻 +2 秒の PCM MOV は、全長 4.0 秒→2.0 秒、トーン開始論理フレーム 120001→24001 に是正。開始時刻付き AAC MP4 は全長 2.0213 秒・トーン開始 25025 で、ffmpeg デコード＋本家の開始時刻意味論と一致。MP3（LAME）は全読み不変のまま、シーク 0.5 秒で無音→トーン、1.5 秒でトーン→ほぼ無音に是正（着地の直接測定でも誤差なし）。映像は AVAssetImageGenerator 単体で、提示オフセット付き MP4 の空セグメント区間がフレームなし（エラー）になることと、実セグメント区間が正しく引けることを確認した。MetalVideoSource 自体の合成経路での実測は未実施。

**次の担当へ。** 解析リポジトリ側の互換マトリクス同期は PR 側の作業。映像の提示開始前区間の見た目（本家はフレームなし、移植は前フレーム維持／透明）は差分として残っている。
#### R6-05 — ストリーミング音声の終端外シークを終端として扱う（レビュー第6ラウンド指摘 P2 の処分。IMPLEMENTED、Mac 検証済み）

**何を直したか。** `AVFoundationStreamingPCMProvider`（STREAM54）で、素材の終端以降へのシークが全デコードへ退化していた。`ensureReader()` は要求位置の開始時刻が終端より前の場合だけリーダーへ時間範囲を設定し、終端以降では時間範囲未設定のリーダーを開始していた。この場合 `AVAssetReader` は素材全体を先頭からデコードし、読み取りループが提示時刻（PTS）で全量を捨て続けるため、長い素材では終端外シーク 1 回で素材全体のデコード負荷がかかった。戻り値の意味論（終端として 0 件）は従来から成立していたため、利用者から見える不具合ではなく負荷の問題である。

**どこを変更したか。** `Sources/YMM4GPU/Export/AVFoundationStreamingPCMProvider.swift` の `ensureReader()`。開始時刻と終端時刻の計算をリーダー生成より前へ移し、開始時刻が終端時刻以降ならリーダーを作らず `reachedEnd` を立てて nil を返すようにした。範囲内の場合は時間範囲を常に設定する（従来の条件付き設定を無条件化）。終端の定義は従来どおりトラックの時間範囲の終端（`duration` と同じ出所）で、提示区間基準（提示開始＋提示長さで終端を決める考え方）と同型である。テストは `Tests/YMM4GPUTests/StreamingPCMProviderTests.swift` に3件追加し、`Harnesses/stream54-harness` に終端外シークと復帰の確認を追加した。

**本家との差分。** なし（内部の負荷の是正のみ。読み取りの戻り値・着地精度・無音区間の意味論は不変）。

**検証。** Mac 実機でルートパッケージ `swift build` 成功・警告0、`swift build --build-tests` でも警告0。`StreamingPCMProviderTests` は新規3件（終端直前の最終フレームを読んでから終端になる／ちょうど終端へのシークで 0 件／終端以降へのシークで 0 件かつ先頭へ戻して通常どおり読める）を含む10件が全合格。`YMM4GPUTests` 全体は28件・0失敗。stream54 ハーネス（1時間・691,200,044 バイトの WAV）: 全読み 345,600,000 サンプル照合一致、メモリ増加 20 MiB（素材長に比例しない）、終端付近へのシーク着地、終端以降へのシークが約 2 µs で終端を返すこと（全デコードへ退化していないことの実測。同ファイルの全読みは同実行で 92.5 秒）、その後の先頭へのシーク復帰、すべて合格（ALL PASS）。なお新規テストのうち「ちょうど終端」「終端以降」は戻り値の意味論の回帰固定であり、リーダーを作らないこと自体はコード構造とハーネスの経過時間で担保した。

**次の担当へ。** なし（本件は完結）。
#### TEXT60 — 制御タグ（ルビ・タイミング）とユーザー辞書（Issue #60）（IMPLEMENTED、Mac 検証済み。MAC 番号は PR 時に付番）

**何を実装したか。** テキストアイテム・字幕の制御タグとユーザー辞書を実装した。制御タグは色 `<#色[,装飾色]>`、フォント `<s サイズ[,フォント[,スタイル]]>` と `<@フォント[,スタイル]>`（`<@+B>` 等の増減指定を含む）、位置 `<p X,Y>` と比例版 `<pp X,Y>`、ルビ `<rb 親文字,ルビ[,サイズ%[,X[,Y[,フォント[,スタイル[,前景色[,装飾色]]]]]]]>`、回転 `<rot 角度>`、表示速度 `<r 文字数/秒>`、待ち `<w 秒>` と `<w*倍率>`、消去 `<c 秒>`、字間 `<ls 字間>`。数値には `+=` 等の演算子接頭辞が使え、タグ直前の `\` でエスケープできる。解釈できないタグは状態を戻して文字として残る。ユーザー辞書はアスタリスク（伏せ字）・単語・発音の3リストを持ち、アスタリスクは描画前処理へ、単語・発音は読み変換の前後段の適用部品として実装した。

**本家根拠。** 仕様は逆コンパイル済みコードで確定した: タグ文法と処理は `ControlTagParser.cs`（タグ正規表現、タグ別解析、装飾の統合、文字タイミング計算、区間フィルタ、ルビの装飾切り出し）、処理順は `TextSource.cs` / `JimakuSource.cs`（アスタリスク置換→正規化→タグ解析→タイミング計算→区間フィルタ）、アスタリスクの装飾追従は `TextHelper.ApplyAsterisk`、辞書のデータ形式・既定値・保存先は `UserDictionary.cs` と `KanjiToYomiBase.ConvertAsync`（辞書はプロジェクトファイルではなくアプリ設定として設定ディレクトリ配下の JSON に保存される）。色名表は WPF `Colors` の名前付き色＋本家追加の rebeccapurple。

**どこを変更したか。** 新規 `Sources/YMM4Core/Text/` 配下: `ControlTagParser.swift`（タグ解析・タイミング計算・区間フィルタ・読み上げ用平文変換）、`ControlTagTypes.swift`（演算子・タイミングタグ・ルビ情報・タイミング情報の型）、`TextPreprocessor.swift`（アスタリスク置換と辞書適用）、`WordSet.swift`（置換エントリと .NET 互換の置換文字列展開）、`UserDictionary.swift`（3リストと本家キー名での JSON 往復）、`UserDictionaryDefaults.swift`（既定エントリ 110 件: アスタリスク 2・単語 107・発音 1、本家の並び順どおり）、`NamedColors.swift`（色名表 148 件）。変更: `Sources/YMM4GPU/Sources/Text/MetalTextRasterizer.swift`（前処理を本家の順序へ組み込み、タイミングがある場合の文字単位の表示判定、分割出力の時刻オフセット、横書き非分割でのルビ描画）、`Sources/YMM4GPU/Sources/Text/MetalTextSources.swift`（タグを含むテキストは非分割でも時刻をキャッシュキーに含める）。テスト新規 `Tests/YMM4CoreTests/Text/ControlTagParserTests.swift`（36 件）と `UserDictionaryTests.swift`（15 件）。

**どう実装したか。** 解析器は本家と同じく、タグを取り除いたクリーンテキスト・タグ装飾と既存装飾の統合結果・タイミングタグ・ルビ情報を返す。内部位置は移植側の装飾に合わせてルーン（Unicode スカラ）単位とした（本家は UTF-16 単位。サロゲートペアを含むテキストでは位置がずれる内部差分）。装飾の統合、ルビ範囲の既存装飾の対応づけ、タイミングの区間分割と表示順の並べ替え、区間フィルタでの装飾・ルビ・タイミングの写し直しは本家の規則どおり。ラスタライザは従来の正規化のみだった前処理を本家の5段へ置き換えた。辞書は既定値（アスタリスクは全件無効）で接続し、設定層が無い現状では本家の初期状態と同じ無変換になる。

**本家との差分（ユーザーから見えるもの）。**
- ルビの描画は横書き・非分割経路のみ。縦書きと文字分割ではルビを描かない（縦書きは従来から CTFrameDraw の一括描画で、文字分割はグリフ単位出力のため）。
- ルビの配置は親文字範囲の中央上に置く近似で、本家 RubyHelper の詳細なレイアウト（ルビ側の装飾・均等配置）とは異なる。ルビ自体の装飾（rubyDecorations）は解析結果に保持するが描画では未適用。
- 装飾のオフセット・回転は解析結果に含まれるが描画では未適用（MAC-0014 以来の既存差分の継続）。
- タイミングがある場合の HideInterval による区間内の段階的な消去は、非分割では省略、分割では順位ベースの項で近似した。
- ランダム表示順の乱数列は .NET `System.Random` と一致しない（本家は種が GetHashCode 由来で実行ごとに変わるため、一致自体が不可能）。
- 辞書の編集 UI と設定ファイルへの保存・読み込みは未実装（アプリ設定層が存在しないため、辞書モデルと JSON 往復、適用部品まで）。読み上げ側の辞書適用も、移植に読み変換経路が無いため部品の提供まで。
- 正規表現は ICU 方言で、.NET 方言との差と 500 ミリ秒のタイムアウト強制は未対応。アスタリスク経路の `${名前}` 展開は番号形式のみ（ICU からグループ名が取得できないため）。

**検証。** Mac 実機（macOS 26.3）でフルパッケージのビルド成功・警告 0。対象テストのみ実行: ControlTagParserTests 36 件・UserDictionaryTests 15 件・回帰として YmmpCodecTests 25 件、計 76 件すべて合格（フルスイートは実行していない）。タグ文字列を含む TextItem の .ymmp 往復で、テキストと装飾が失われないことをテストで確認した。ルビ描画とタイミング表示の目視確認は未実施。

**未解決。** 辞書の設定層接続（編集 UI・保存先）は設定層の新設が前提。縦書き・文字分割でのルビ描画。ルビ配置の本家 RubyHelper との一致検証（本家実出力との比較環境が無い）。
#### FXMETA — エフェクトプロパティメタデータの全種別化（IMPLEMENTED / VERIFIED）

**何を実装したか。** プロパティエディタが編集 UI を生成するためのメタデータ（`EffectPropertyMetadata`、MAC-0029 で基盤と代表3種のみ実装済み）を、レジストリ登録の内蔵エフェクト全95種に揃えた。従来は拡大縮小・不透明度・描画位置の3種だけが固有パラメータの記述子を持ち、残り92種は共通プロパティ（IsEnabled / Remark）のみだった。今回の追加は固有パラメータ記述子500件（全95種の合計は共通を除き509件）。

**どこを変更したか。** `Sources/YMM4Core/Editing/EffectPropertyMetadata.swift`（本体の振り分けへ `specificDescriptors(for:)` の呼び出しを追加し、冒頭コメントを実態へ更新）、新規 `EffectPropertyMetadataCatalog.swift`（具象定義別の振り分け、列挙型の選択肢一覧、イージング専用経路）、新規カテゴリ別ビルダーファイル5件（`EffectPropertyMetadataDraw.swift` / `EffectPropertyMetadataGPUTransform.swift` / `EffectPropertyMetadataGPUColor.swift` / `EffectPropertyMetadataGPUShadowMask.swift` / `EffectPropertyMetadataGPUInOut.swift`、定義側のファイル編成に対応）、新規テスト `Tests/YMM4CoreTests/Editing/EffectPropertyMetadataTests.swift`（5件）。

**どう実装したか。** 記述子の並びは各定義の保存形式のキー順（`encodeKnownFields` の並び、中間基底のキーは具象側の後に続く。本家ファイルの並びと一致）とした。表示名・グループは本家の各エフェクトクラスの `Display` 属性が指す `Texts` リソースの文言、数値範囲は本家の `Range` 属性（無ければスライダ属性の上下限）、列挙の選択肢は本家の列挙メンバの `Display` 属性の文言を使った。根拠が取れない表示名はプロパティ名そのままにする（従来方針どおり）。`EasingFamily` / `EasingMode` と `BillboardMode` は `HonkeEnum` に適合しないため、保存名への変換を定義層の既存変換（`effectHonkeName`、Billboard は定義の encode と同じ対応表）で行う専用経路をカタログに置いた。Billboard の未知 Mode 名は定義側に原文保持があるため読み取りでは原文を返し、書き込みは既知3値のみを対象とする（未知値を消す公開口が定義側に無いための制約。既知の値を選べば通常どおり反映される）。`TextureEffect.ContentOffset`（本家 `TimeSpan`）は記述子体系に時刻型が無いため、秒の数値として読み書きする（値の意味は同一。tick 単位の保持は定義側が担う）。

**本家との差分。** 本家で `AutoGenerateField` により入れ子の専用エディタを生成する複合プロパティは、単一記述子の対象外とした（18件）: ブラシ（Shadow / InnerShadow / FillBackground / FillForeground / FrameLine の各 Brush、Outline の StrokeBrush、DisplacementMap の Brush）、DisplacementMap / NoiseColorShift / NoiseDisplacementMap の Transform、Noise 系3種の NoiseParameter、Mosaic の MosaicParameter、Mask の ShapeParameter、Gradient の Stops（色停止点列）、MeshDeformation の Points（点列）、MotionTracking の Path。これらは本家でも単一フィールドでは編集しない対象であり、値そのものは定義層で保持されている（MosaicParameter は型付き、その他は生保持）。RepeatOpacity の IsCentering は本家では固定 false・保存対象外（`JsonIgnore`）のダミー上書きであるため対象外とした。本家の旧 API プロパティ（`[Obsolete]`、例: Sepia の Intensity、ChromaKey2 の Threshold、Gradient の ColorFrom / ColorTo）は定義層が保存キーとして持たないため、もともと対象外である。

**検証。** 棚卸しの実数: 定義層は95種、メタデータ既存は3種、今回92種を追加し全95種が揃った。保存キーと本家プロパティの照合では、差分は全て旧 API プロパティ・decode 専用の互換キー（CenterPoint の Mode）・入れ子列挙の宣言として説明が付いた。Animation の既定値・最小・最大は本家 `new Animation(...)` の初期化子と264件照合し、不一致0。Blend の選択肢33件はアイテム側メタデータの既存一覧と集合一致。新規テスト5件（全95種の網羅＝記述子 ID 列と保存キーの一致、ID 一意性、対象外キーの不在、全記述子の書き込み往復、アニメーション既定値の範囲内確認）と既存 PropertyMetadataTests 17件が、Linux と Mac の双方で全合格（計22件・0失敗）。Mac 実機でルートパッケージのビルド成功・警告0。フルスイートは他作業と並行中のため未実施（対象テストのみ実行）。

**未解決。** 対象外とした複合プロパティ18件を編集 UI から扱うには、記述子体系へ入れ子オブジェクト用の種別を足す設計判断が別途必要（現行体系の範囲では未確定）。数値プロパティのうち本家に `Range` もスライダ属性も無いものは範囲なし（無制限）とした。本家の `ShowPropertyEditorWhen`（条件付き表示、3件）に対応する仕組みは記述子体系に無いため、該当プロパティも常時表示の前提で記述した。

**追記（FXMETA-COMP で解消）。** 上記の「対象外とした複合プロパティ18件」は、記述子体系へ複合種別（`.object` / `.collection`）を1層だけ足す設計（第7ラウンドで決定）により全件対象化した。本節の「本家との差分」にある対象外の記述は FXMETA 時点の記録であり、現行の実態は本台帳末尾の FXMETA-COMP 節が正本。RepeatOpacity の IsCentering は引き続き対象外。
#### R6-FIX — レビュー第6ラウンド指摘の処分: リピート再開（R6-01）・開始失敗の通知（R6-03）・チャンク生成の世代競合（IMPLEMENTED、Mac 検証済み）

**何を実装したか。** 実時間再生（MAC-0042）に対するレビュー第6ラウンドの指摘のうち、再生エンジンに関わる3件を処分した。(1) R6-01（P1・修正必須）: リピート有効時、終端到達で表示位置が開始位置へ戻るだけで再生が再開されなかった不具合の修正。(2) R6-03（P2）: 音声エンジンの起動失敗が握りつぶされていたのを、型付きの失敗として通知し UI へ表示できる形にした。(3) 照合課題: 同ラウンドの打ち切られた初回生成にだけ現れた「旧世代のチャンク生成タスクがシーク後の位置から音声を読み取って消費する」競合の指摘候補を実コードで照合し、実在したため本単位で併せて修正した。

**どこを変更したか。** branch `fix/r6-01-repeat`（開始点 = main `8df38dd`）。`Sources/YMM4GPU/Playback/RealtimePlaybackEngine.swift`（`poll` の終端処理と速度変更経路、`buildEngineAndStart` の失敗処理、`renderChunk` の世代確認、クラス冒頭の仕様コメント）、新規 `Sources/YMM4GPU/Playback/PlaybackStartError.swift`、`Apps/DebugApp/Sources/YMM4MacDebug/ProjectView.swift`（開始失敗の通知配線と読み込み診断タブへの表示）、`Tests/YMM4GPUTests/PlaybackTests.swift`（`RealtimePlaybackRepeatTests` を追加）。

**どう実装したか。**
- R6-01: `poll` の終端分岐で、停止処理（`endPlayback`）の後に表示位置を開始位置へ戻し、通常の再生開始経路 `play()` を呼ぶ。供給の再シーク、プレイヤーの再構築、メーターの位置合わせ（供給シークに含まれる）はすべて `play` 側の既存経路に委ね、リピート専用の開始処理は作らなかった。開始位置が終端そのものの場合のみ、再開しても即座に終端へ戻るため再開しない。一時停止時に「位置だけが開始位置へ戻る」挙動は従来どおり変更していない。
- R6-03: 新規の型付きエラー `PlaybackStartError`（`engineStartFailed`、`userMessage` を持つ。`MetalInitializationError` と同じ契約）に `AVAudioEngine.start()` の失敗を載せ、`lastStartError` への保持と `onStartFailed` コールバックでの通知を行う。開始が成功すると `lastStartError` は nil へ戻る。ProjectView は通知を受けて理由文を保持し、読み込み診断タブへ表示する（再生が始まれば消える）。失敗別の個別フォールバックは作っていない。
- 世代競合: `renderChunk` が期待世代を受け取り、供給ロック（`sourceAccessLock`）の保持中に世代を確認してから読むよう変更した。併せて `poll` の速度変更経路で世代更新（`bumpGeneration`）をシークより先へ移した。

**照合課題の結論（実在した。根拠は実コードの制御フロー）。** 修正前の `renderChunk` は引数 `startingAtSamples` を実際の読み取り位置に使っておらず、供給元の現在位置から無条件に `source.read` していた。世代の確認は生成後のメインキューでのスケジュール判定でしか行われておらず、読み取りによる供給位置の消費は取り消せない。`fillSchedule` が直列の生成キューへ積んだ旧世代タスクが、シーク（一時停止→再生、再生中のシーク、速度変更による作り直し）の後に実行されると、シーク後の位置から1チャンク（1秒）を読み捨て、新しい世代の先頭1秒が欠落する（該当箇所は修正前の `fillSchedule` の async 積み込みと `renderChunk` の無条件読み取り）。修正後は、シーク（`seekSource`）も同じ供給ロックを取るため「確認→読み取り」がシークに対して不可分になり、古い世代は供給元を一切読まない。速度変更経路の世代更新をシークより先へ移したのは、シーク直後に古い世代が割り込む窓を残さないため。

**本家との差分。** リピート再開は本家のリピート再生（`IsRepeatPlayEnabled`）の意味への是正であり、新しい差分は生まない。開始失敗の通知は Mac 側の診断契約（MAC-0021 の「失敗は握りつぶさず通知する」、Issue #50 の Metal 診断と同方針）の再生側への拡張で、本家に相当する表示はない。

**メモリ・並行性。** 世代カウンタと供給ロックは既存のものをそのまま使い、新しいロック・キューは追加していない。`renderChunk` の世代確認は供給ロック保持中に行い、世代ロックは末端の短い区間のみで取得する（ロックの取得順序は従来から変えていない）。開始失敗時は従来どおりエンジン一式を破棄し、失敗の保持は値型1件のみ。

**検証。** Mac 実機（検証コピー ~/ymm4-work/ymm4mac-fix-r601）: ルートパッケージ `swift build` 成功・警告 0。`swift test --filter Playback` は 16 件全合格（新規 `RealtimePlaybackRepeatTests` 2 件を含む）。受入試験は 1 秒の音声付きタイムラインを実再生し、供給プロバイダの読み取り総量が 1 周分（96,000 サンプル）を超えることで 2 周目の出力を確認する方式で、リピート ON では再開と読み取りの継続を、OFF では終端での停止・位置のタイムライン長一致・読み取り総量が 1 周分を超えないことを確認した。切り分けとして、修正前のエンジンへ戻した検証コピーでは ON の試験が失敗した（10.3 秒、2周目の読み取りが観測できず、再生は停止したまま）。OFF の試験は修正前後とも合格。Mac フルスイート（`swift test --parallel`、517 件）は、513 件目まで実行され失敗 0 を確認した時点で Mac への接続が切れ、残り4件（長時間のドリフト試験）は本記録の時点で未確認である（接続回復後に /tmp/r601-full.log で確定させること）。世代競合の修正は、決定的な再現には生成キューの実行順序の制御が要り自動テスト化が困難なため、自動テストなし（コード照合と上記の不可分性の論証で確認）。R6-03 の失敗経路も、`AVAudioEngine.start()` の失敗をテストから強制する手段がないため自動テストなし（型と配線はビルドで確認）。

**次の担当へ。** 本単位の範囲外: R6-02（再生制御と映像合成のメインキュー占有。高負荷時の実測が要る）、R6-04（PngWav の UI 接続）、R6-05（ストリーミングの終端外シーク）、R6-06（クリッピングの GPU 失敗通知）。開始失敗の表示先は当面は読み込み診断タブであり、フロントエンド側でより目立つ表示先が決まれば配線先だけを移す。
#### MOSAICRECT — 矩形モザイクの本家方式化（5点サンプル平均）（IMPLEMENTED、Mac 検証済み）

**何を実装したか。** 矩形モザイクの色決定方式を、従来の「セル内全テクセルの平均」から本家方式の「セル内5点サンプルの平均」へ是正した。MOSAIC48 で範囲外として記録されていた差分の解消。

**本家根拠。** 本家カスタムシェーダ `Mosaic` の DXBC 逆アセンブル（`mosaic_dis.txt`。C# ラッパ `Mosaic.cs` は Size の設定のみで、範囲は 1–5000 にクランプ）。逆アセンブルから抽出した方式: (1) Size == 1 のときは現在画素をそのままサンプルする。(2) セル格子はシーン座標（入力平面座標）の原点基準で、セル原点 = pos − floormod(pos, Size)（負座標では床方向の剰余）。(3) セルは入力矩形（InputRect）で切り取られる。(4) 色は切り取られたセル内の5点 — 中心 (1/2, 1/2) と (1/3, 1/3), (1/3, 2/3), (2/3, 1/3), (2/3, 2/3) — の線形サンプルの平均（合計 × 0.2）。第2段のイン／アウトモザイクも本家では同じ `Mosaic` カスタム効果を使う（`InOutMosaicEffect.cs` で Size = max(1, イージング値)）ため、共通ヘルパの是正で両方に効く。

**どこを変更したか。** `Sources/YMM4GPU/Graphics/MetalGraphicsDevices.swift`（Warp フラグメントへ mode 12 を追加。1/3・2/3 は本家のコンパイル済み定数 float32(1/3) = 0.3333333432674408 等を字面どおり使用）、`Sources/YMM4GPU/Effects/MetalEffectProcessorBase.swift`（`renderRectangleMosaic` をコンピュートカーネルから Warp mode 12 経由へ置き換え、不要になった `RectangleMosaicUniforms` を削除）、`Sources/YMM4GPU/Effects/MetalBlurMosaicProcessors.swift`（差分を記録していたコメントを是正後の説明へ更新）。検証資産として `Harnesses/mosaic48-harness` へ矩形ケースを追加（参照実装 `shader_reference.py` へ `rectangle_points`、期待値生成へ rect16 / rect13 / rect20 / rect1、ハーネスへケース 9.5）。あわせて同ハーネスの `MetalGraphicsDevices()!`（現行の throwing 初期化子と合わずコンパイル不能だった箇所）を `try!` へ修正した。

**残置したもの。** 旧コンピュートカーネル `ymm4MosaicKernel` と `mosaicPipeline` は描画に使われなくなったが、デバイス初期化の関数インベントリとして残した（初期化診断ハーネスが同名関数を欠落検出の対象にしているため）。コード内コメントにその旨を明記した。

**検証。** Mac 実機: ルートパッケージ `swift build` 成功・警告 0。画素ハーネス mosaic48-harness は全ケース PASS で、矩形の新規4ケース（Size 16 = 割り切れる寸法、13 / 20 = 割り切れず端セルの切り取りが効く寸法、1 = 素通し）は参照実装と**全画素一致（不一致 0px）**。参照は DXBC 抽出式の独立実装＋線形サンプルの再現で、サンプル点の位置まで含めて一致した。関連テスト（`--filter "Brush|Mosaic"`）21件全合格。フルスイートは他担当の並行作業のため未実行。

#### GRADMESH — グラデーションメッシュブラシの型付き化と GPU 描画（IMPLEMENTED、Mac 検証済み）

**何を実装したか。** BRUSH46 で生保持のみだったグラデーションメッシュブラシ（本家 `GradientMeshBrushParameter`）を型付きモデル化し、GPU 描画まで実装した。格子点の色を Coons パッチで補間して塗る。

**本家根拠（いずれもデコンパイル済みコード）。** パラメータと既定値: `GradientMeshBrushParameter.cs`（HorizontalCount / VerticalCount 既定 2、CoordinateMode 既定 Relative、Width / Height は Animation 既定 100・範囲 0–100000、ExtendOutside 既定 true、既定点は Red / Gold / RoyalBlue / Cyan で先頭点のみ IsSelected。基底 `ScalableDrawingBrushParameterBase` の Zoom 既定 100 と `DrawingBrushParameterBase` の配置変換フィールドを継承）。点: `GradientMeshPoint.cs`（X / Y と8本のハンドルが Animation、4つのカスタムフラグ、Color、IsSelected）。論理配置とスナップショット: 同ファイルの `GetLogicalPointPositions` / `GetLogicalPointSnapshots`（配置 = −W/2 + W・列/(横点数−1) + 点 X・(W/100)、ハンドルは内向きかつカスタムの方向だけが位置＋ハンドル値・(W/100) を持ち、それ以外は null）。座標変換: `GradientMeshCoordinateHelper.cs`（ToLocal は Relative で境界寸法/100・Pixel で等倍、変換 = ブラシ行列 × 境界中心への平行移動、拡張境界は出力境界の逆変換像）。パッチ構築: `GradientMeshPatchBuilder.cs`（内部点は D2D `D2D1GetGradientMeshInteriorPointsFromCoonsPatch`、非カスタムハンドルは接線（中央差分、端は一方向差分）の 1/3 で導出、ExtendOutside 時は境界を全点位置と使用カスタムハンドルへ拡張し、帯パッチと四隅の双線形パッチで出力境界まで覆う）。描画: `GradientMeshBrushSource.cs`（メッシュをコマンドリストへ描いて Clamp の ImageBrush 化。対象範囲は ±(MaximumBitmapSize/2 − 1)）。

**どこを変更したか。** Core: `Sources/YMM4Core/Model/BrushParameters.swift`（`GradientMeshPointValue` と `GradientMeshBrushParameter` を新設。本家の宣言順で読み書きし、未知キーは追加フィールドとして保持）、`Sources/YMM4Core/Model/Brush.swift`（`BrushParameter.gradientMesh` を追加し、復元・保存・アニメーション走査へ接続）。GPU: 新規 `Sources/YMM4GPU/Effects/GradientMeshGeometry.swift`（スナップショットのローカル化、接線導出、Coons 内部点、拡張パッチ構築、テッセレーション）、`Sources/YMM4GPU/Effects/MetalBrushFill.swift`（`BrushFillSpec` の mode 6 と仕様構築、頂点バッファ描画 `renderMesh`）、`Sources/YMM4GPU/Graphics/MetalGraphicsDevices.swift`（頂点色シェーダ `ymm4MeshVertex` / `ymm4MeshFragment` と `meshPipeline` を追加）。

**どう実装したか。** パッチの内部点は D2D 関数の閉形式（境界制御点の線形結合から双線形項を引く形）を再実装し、Coons 曲面の直接評価との一致を数値検証した（ランダムな境界 200 組 × 20 点で最大誤差 2.1e-14）。描画はパッチを CPU 側で一様分割（16×16）してテンソル積三次ベジェで位置を評価し、頂点色の三角形として描く。色は四隅色の (u, v) 双線形補間（パッチが保持する色は四隅のみで、テンソル積の色格子は双線形埋め込みに帰着する）。点数と格子点数が一致しない等の不正なパラメータでは本家どおり透明な塗りになる。保存形式の JSON キーはデコンパイル済みモデルに基づく（実ファイルでの出現は未確認。実ファイル2件には GradientMesh の出現なし）。

**本家との差分。** (1) テッセレーション密度と外周エッジのアンチエイリアス（本家の PatchEdgeMode）は D2D 内部依存のため再現しない。こちらは一様 16 分割で、外周はアンチエイリアスなし。(2) 拡張の対象境界は本家では MaximumBitmapSize の矩形だが、こちらは塗り境界を使う。描画範囲の外側は結果に影響しないため、見える範囲の色は変わらない。(3) 色補間が双線形である点は、D2D の色モデル（四隅色のみ）からの帰結として採ったもので、本家の実出力との画素比較は未実施。

**検証。** Mac 実機: `swift build` 成功・警告 0。Core 単体テスト `BrushParameterTests` 12件全合格（新規: メッシュの往復保存（JSON 一致）と既定値の確認。従来の「生保持のまま」テストは型付き往復へ置き換えた）。GPU 単体テスト新規 `GradientMeshGeometryTests` 5件全合格（既定格子の双線形一致、カスタムハンドル時の中心移動 (0,0) → (4,0) のテンソル積評価一致、拡張の被覆範囲と隅色、変換の適用、不正な点数で空になること）。画素ハーネス brush46-harness は全ケース PASS（新規: 既定メッシュの中心 (140, 148, 124)・左上 (252, 5, 4)・右下 (5, 248, 251) が解析値と一致、W=H=50 での拡張あり／なし、Pixel モード。既存ケース11は「メッシュは描画されない」前提が変わったため、影が不透明度 50% で付く確認へ更新し、実測アルファ 128 で一致）。フルスイートは他担当の並行作業のため未実行（関連フィルタ 21 件は全合格）。

**R7-01 処分（レビュー第7ラウンド、PR 作成後の追補）。** 読み込んだ点数（HorizontalCount / VerticalCount）は保存互換のため無制限に保持されるが、描画側の2箇所（GradientMeshGeometry.build と MetalBrushFill のメッシュ分岐）が点数の乗算を無検証で行っており、外部ファイル由来の極端な値では整数オーバーフローでプロセスが停止し得た。処分: Core の GradientMeshBrushParameter に描画用上限 maximumPointCount = 50（本家 UI の範囲 2〜50 の上限）を置き、両箇所で乗算より前に上限を検証する形にした。保存データの読み書きは従来どおり無制限で、往復で値は失われない。検証は GradientMeshGeometryTests に極端な点数（10億×10億）で空のジオメトリが返るテストを追加して行う。
#### NOISE7 — Noise エフェクト残り7種の実処理化（IMPLEMENTED、Mac 検証済み。本家との画素一致は DXBC 実行参照との照合範囲）

**何を実装したか。** Noise エフェクト（本家 `YukkuriMovieMaker.Project.Effects.NoiseEffect`）の生成器10種のうち、素通しだった残り7種（Block / Perlin / Cellular / Voronoi / Simplex / Marble / Flow）を実処理にした。既存の Fractal / Random / Curl と合わせて全10種が描画される。パラメータ側は Cellular / Voronoi の DistanceMode・OutputMode、Marble の StripeInterval・StripeWarpAmount、Flow の FlowAmount の読み取りと定数受け渡しを追加した。

**本家根拠。** 描画式と定数は全種とも本家シェーダの DXBC 逆アセンブルから抽出した（作業領域 gpu45-scratch の blocknoise / perlinnoise / cellularnoise / voronoinoise / simplexnoise / marblenoise / flownoise の各逆アセンブル）。パラメータの定数変換は逆コンパイル済み C# の `SetParameterTo` で確認した: DistanceMode / OutputMode は列挙値の int キャスト、Marble の StripeInterval は生 float（Animation 既定 64、範囲 1–2000）、StripeWarpAmount は生値（既定 100、0–1000）、Flow の FlowAmount は値 / 100（既定 100、0–1000）。.ymmp 上の列挙は文字列名で保存される（Cellular の OutputMode は F1 / F2 / Difference、Voronoi は CellValue / Edge）。

**どこを変更したか。** branch `noise7/remaining-types`（base = main 8df38dd）。`Sources/YMM4GPU/Graphics/MetalGraphicsDevices.swift`（Noise シェーダへ生成器7種と振り分けを追加。既存3種の経路は無変更）、`Sources/YMM4GPU/Effects/MetalEffectProcessorsNoise.swift`（種別コード 3–9 の割り当て、新規パラメータの読み取り、ユニフォーム受け渡し）。検証資産として `Harnesses/noise7-harness/` を新設し、`Harnesses/README.md` へ登録した。Core は無変更。

**どう実装したか。** 新規7種は既存3種と前段が異なるため、フラグメントシェーダで種別コード 3 以上を専用経路へ分岐し、後段（Threshold / Strength / Levels のポスト処理）は既存の `ymm4NoisePost` を共用した（ポスト処理の式と Levels 条件は逆アセンブルと一致することを確認済みで、変更なし）。本家シェーダから実測した共通規則: (1) オクターブは「カウンタが Octaves 以下の間」= Octaves + 1 回評価する。(2) Z はオクターブの周波数で拡縮しない（XY のみ）。(3) ワープの第1評価点には +(19.1, 7.3, 3.7) のオフセットがある。(4) 座標変換はスケール後に ×(1/64) が入る。(5) FractalMode の整形はモード 0 では生値をそのまま使う。種別固有の要点: Block は XY がセル内一定で Z のみフェード補間したセルハッシュ。Perlin は格子点ごとにタグ 0 / 1 / 2 の整数ハッシュから勾配（各成分 = ハッシュ ×2 − 1、正規化なし）を作り内積を三次フェードで補間する。Cellular は 3×3×3 近傍の特徴点との距離の小さい方2つを追跡し、F1 / F2 の初期値はどちらも 1.0（本家の初期化どおり）。距離は Euclidean は length、Manhattan は ×(2/3)、Chebyshev は ×1.2。Voronoi の F1 / F2 初期値は 10.0 で、CellValue は勝者セルのハッシュ値、Edge は 1 − saturate(F2 − F1)。Simplex は評価点へシードハッシュ ×289 のオフセットを加えた既存の snoise（×52.5 + 0.5 形）。Marble は縞位相 = 回転後 x / StripeInterval × 2π で、StripeWarpAmount ≠ 0 のときだけ値ノイズで位相を歪ませる（歪み量 = (n×2 − 1) × StripeWarpAmount × 2π/100）。Flow は2次元の回転勾配ノイズで、オクターブごとに勾配場で評価点を移流させる。permute の mod289 入力が (ix, ix + sx, ix + 1)、加算側が (iy, iy + sy, iy + 1) という非対称な構成と、第2角のスキューが −0.5×(iy + sy) である点は、逆アセンブルのレジスタ手順どおりに転記した（検証の節参照）。

**Voronoi の決定性について。** モザイクの Voronoi はシードが C# 側の GetHashCode 由来で再現不能だったが、Noise の Voronoi は特徴点・勝者値ともシェーダ内の整数ハッシュ（セル座標 + シード、タグ付き）だけで決まる決定的な処理であり、画素単位の照合が可能だった。実際に照合した（検証の節）。

**検証。** 期待値は、本家シェーダの DXBC を命令単位で実行するインタプリタ（作業領域 noise7-scratch）の出力。インタプリタ自体の妥当性は、既にマージ済みの移植 Fractal との照合ケース（fractal-cross）で担保した: 既存3種の既知の差分（オクターブ回数と ×(1/64)）を補正した条件ではバイト完全一致した。画素ハーネス noise7-harness（32×32、39ケース: 各種別の既定・整形モード・ワープ・角度・オフセット・スケール・色モード・ポスト処理・FlowAmount 変化など）で MetalNoiseProcessor 経由の実描画と比較した結果、37ケースがバイト完全一致（最大差 0）。残り2ケース（vor-cell / vor-manh-cell）は同一の1画素（行26・列5）だけが 1 バイト差（参照 157 に対して 158）で、勝者セルの取り違えではなくバイト境界での float 丸め差である。Flow は初版の転記で2箇所（permute 入力と第2角のスキュー）の読み違いがあり系統的にずれていたが、逆アセンブルのレジスタ手順を追い直して是正し、全ケース一致に至った。Mac 実機（検証コピー ~/ymm4-work/noise7-YMM4Mac）: ルートパッケージ `swift build` 成功・警告 0、対象テスト（GPUEffectRegistryTests / GPUEffectValuePreservationTests / GPUEffectLegacyKeyTests の計30件）0 失敗。Mac フルスイートは本単位では未実施（対象テストとハーネスのみ実行）。本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**本家との差分・未解決。** (1) 既存3種（Fractal / Random / Curl）には本単位で変更していない差分が実測で確認された: ワープ第1評価点の +(19.1, 7.3, 3.7) オフセット欠落、オクターブ回数が Octaves 回（本家は Octaves + 1 回）、座標変換の ×(1/64) 欠落。是正は既存種の描画結果を変えるため本単位の範囲外とし、別途処分が要る。(2) IsUniqueSeed のシード基礎値（パラメータの GetHashCode 由来）は従来どおり未確定で 0 として扱う（全種共通の既存差分）。(3) Flow の周波数・振幅の更新は逆アセンブルのパックされたレジスタ更新を標準セマンティクスで読むと交差して見える箇所があるが、実測では通常の更新（周波数 ×Lacunarity、振幅 ×Gain）でインタプリタ参照と完全一致したため、通常の更新を採用した。
#### NOISEFIX — Noise 既存3種（Fractal / Random / Curl）の本家シェーダとの差分是正（IMPLEMENTED、Mac 検証済み。本家との画素一致は DXBC 実行参照との照合範囲）

**何を実装したか。** NOISE7 の検証で実測された、既存3種（Fractal / Random / Curl）と本家シェーダとの差分を是正した。対象は (1) ワープ第1評価点の +(19.1, 7.3, 3.7) オフセット欠落、(2) Fractal / Curl のオクターブ回数が Octaves 回で本家より1回不足、(3) 座標変換の ×(1/64) 欠落。あわせて noise7-harness に既存3種のケース8件（fractal-default / fractal-warp / fractal-turb / fractal-ridge / random-default / random-warp / curl-default / curl-warp）を追加し、全47ケースで照合できるようにした。従来ハーネス側にあった fractal-cross の補正（Octaves+1・Scale×64 のポート側補償）は撤去した。

**本家根拠。** 本家シェーダの DXBC 逆アセンブル（作業領域 gpu45-scratch の fractalnoise / randomnoise / curlnoise）。3種は別々のシェーダであり、前段の規則は種別ごとに異なることを逆アセンブルで確認した。特に (3) は Fractal / Curl のシェーダにだけ存在し、Random のシェーダには無い。NOISE7 記録の未解決 (1) は3種共通の差分として ×(1/64) 欠落を挙げていたが、Random についてはこの限りでなかったため、本記録で訂正する。

**どこを変更したか。** branch `noisefix/existing-three`（base = main 12df5ea）。`Sources/YMM4GPU/Graphics/MetalGraphicsDevices.swift` の `ymm4NoiseFragment` 既存3種経路: ワープ第1評価点を `q + (19.1, 7.3, 3.7)` へ是正、スケール後に ×0.015625 を追加（ただし noiseType == 1（Random）では適用しない条件分岐つき）、Fractal / Curl のオクターブループ条件を `octave < uniforms.octaves` から `octave <= uniforms.octaves` へ変更。Random は単一評価でオクターブループを持たないため (2) の対象外。`Harnesses/noise7-harness/` にケース8件と期待値（refs/）を追加し、`Harnesses/README.md` の noise7 行を更新した。Core は無変更。

**どう実装したか。** 既存3種の経路は NOISE7 の新規7種と違い、シェーダごとに前段規則が異なるため、種別分岐の内側で吸収した。×(1/64) はスケール直後・回転直前の位置に置き、Random のみ条件分岐で除外した（Random の逆アセンブルではスケールの直後に回転が続く）。ワープの第2評価点オフセット (47.2, 31.6, 11.9) と、ワープ評価自体の ×(1/64)（warpScale への乗算）は従来どおりで変更していない。

**検証。** 期待値は NOISE7 と同じ DXBC インタプリタの出力。既存39ケースの期待値は再生成しても全てバイト同一だった（インタプリタの決定性を確認）。Mac 実機（検証コピー ~/ymm4-work/verify-noisefix-YMM4Mac）: ルートパッケージ `swift build` 成功。noise7-harness 全47ケースを実描画と比較し、本単位の対象である既存3種のケースは全て最大差 0（バイト完全一致）。NOISE7 由来の Voronoi CellValue 系2ケース（vor-cell / vor-manh-cell）は最大差 1 が残る（NOISE7 節に記録済みの境界画素。第8ラウンド処分で下記のとおり原因を特定）。是正の途中経過として、×(1/64) を3種共通に適用した段階では Fractal / Curl が一致し Random の2ケースだけが系統的にずれた（最大差 194）ため、Random の逆アセンブルを読み直して上記の種別差を特定した。Mac フルスイートは、全586件から AudioDriftTests の7件を除いた579件を並列実行した（ドリフト試験はオーナー指示により既定で省略）。失敗は StreamingPCMProviderTests.testMemoryDoesNotGrowWithLongFile の1件のみ（メモリ増加量 35,651,632 バイトが上限 34,603,008 バイト = 33 MiB を超過）。同テストは単独実行では合格し、本単位の変更範囲（Noise シェーダ）とは無関係で、統合後スイート（main 12df5ea）でも合格していたため、並列実行時の計測揺らぎと判断した。本家実機との比較試験は未実施のため IMPLEMENTED 止まり。

**第8ラウンドレビュー処分（PR #102、条件付き採用可・P1 なし・P2 4件）。** R8-01: 比較スクリプト compare.py が不一致でも終了コード 0 を返し、最大差 3 以下を合格扱いにしていた欠陥を是正した。全ケース最大差 0 でなければ非 0 終了とする厳密判定に変更し、改竄した出力で非 0 終了することも確認した。R8-03: 重点ケース5件を追加し全52ケース化した（fractal-oct0 / curl-oct0 / curl-turb / curl-ridge / random-axes）。この追加で Curl の FractalMode 系2ケースの期待値が実描画と一致しないことが判明し、原因はインタプリタ側の不具合と特定した: DXBC の分岐修飾子（`if X ; z` = ゼロのとき分岐）をコメント除去で落としており、Curl シェーダの FractalMode 分岐が反転していた。インタプリタを修正して全52ケースの期待値を再生成したところ、変更は curl-turb / curl-ridge の2件のみで、修正後の期待値と実描画はバイト完全一致した（移植側の実装は正しかった）。なお全シェーダで `; z` 分岐は Curl と HalfTone の各1箇所のみ。HalfTone の期待値は修正前インタプリタで生成されているため、再検証を Issue に切り出した。R8-04: PR に混入していた Python バイトコード（__pycache__）を追跡対象から外し、.gitignore に __pycache__/ と *.pyc を追加した。combos.swift の生成スクリプト gen_harness.py はリポジトリ内のハーネスフォルダへ収録した（期待値の生成はインタプリタと逆アセンブル成果物に依存するため作業領域に残る）。R8-02: メモリ増加量テストは最終コミットで単独3回再実行し全て合格した。ただし処分は「揺らぎで解消」ではなく、プロセス全体のメモリを測る試験が並列スイートと干渉する既知の試験環境問題として Issue に切り出し OPEN のままにする（閾値の引き上げはしない）。最終状態: 全52ケース中50ケースがバイト完全一致。残る vor-cell / vor-manh-cell は各1画素のみ最大差 1 で、インタプリタの値がバイト境界（157.5 / 255）で実描画より 1 ulp 低く出る精度差であり、NOISE7 以来の既知差分として残置する。

**本家との差分・未解決。** IsUniqueSeed のシード基礎値（パラメータの GetHashCode 由来）は従来どおり未確定で 0 として扱う（全種共通の既存差分、本単位でも変更なし）。
#### INTEG-20261118 — 機能フェーズ10単位の統合（PR #84〜#93）と統合後検証

**何を統合したか。** 並行して実装された10単位を main へ順に統合した。対応は次のとおり。#84 = MAC-0040（VoiceItem 音声供給、#51）、#85 = MAC-0041・0042（実時間再生、#52）、#86 = SOLA53（#53）、#87 = STREAM54（#54）、#88 = MAC-0043（PngWav、#49）、#89 = MAC-0044（Metal 初期化診断、#50）、#90 = GPU45（#45 第1弾）、#91 = BRUSH46（#46）、#92 = TRANSFORM47（#47）、#93 = MOSAIC48（#48）。統合後の main は `8df38dd`。

**統合時の競合と解消。** (1) #85: PreviewBox.render は #52 の usage 引数と main 側の nil ガードを両立させた。ProjectView は再生側の関数（再生エンジン停止・速度/音量/ミュートの変更伝播）を採り、表示文字列と寸法はフロントエンド側を採った。(2) MetalGraphicsDevices: #50 の throws 形式を基底とし、#45 のシェーダ関数5件と #46 のブラシ関数・リピートサンプラーを同形式で追加した。(3) #46 と #45: Outline が生保持のまま渡す StrokeBrush 用に、型付き Brush 版と並べて PreservedObject 版の solidBrushColor を残置した（引数の型によるオーバーロード）。(4) 台帳とハーネス README の競合は両側を保持した。

**検証。** 統合中間状態（#85 統合直後）で Mac フルスイート 481 件・0 失敗。統合後の最終状態で 515 件すべてが開始し、失敗・エラーの記録 0（Mac、ログは /tmp/final-merge-test.log、EXIT:0）。brush46・transform47・media4950 の各ハーネスは統合後に全 PASS。

**統合で見つかった追随漏れ。** #50 の初期化子 throws 化に対し、既存ハーネス mac0023・mac0025・mac0027・mac0028・mac0031・mac0033・mac0034・mac0035 が `MetalGraphicsDevices()!` のままで main 上でコンパイル不能だった。本記録の PR で `try!` へ追随させ、8件すべてのビルド成功を Mac で確認した。あわせて mac0034 には MetalExportVideoProvider の初期化子 throws 化への未追随（旧来の失敗可能初期化子を前提にした条件バインディング）もあり、同 PR で do-catch 形式へ是正した（mosaic48 ハーネスの初期化子追随は MOSAICRECT の PR で修正済み）。brush46・transform47 のハーネスは統合時に追随済み。

**未解決。** 統合結果のレビュー（第6ラウンド）は条件付き採用可。指摘の処分は R6-FIX の記録を参照。STATUS.md のテキスト描画行（Issue #60 の状態）は TEXT60 の PR 側で更新する。

#### R6-04 — PngWav 形式の UI 接続（レビュー第6ラウンド指摘 P2 の処分。IMPLEMENTED、Mac ビルド検証済み）

**何を実装したか。** 動画出力ダイアログで書き出し形式を選べるようにした。従来は MP4 固定の表示だけで、PngWav（MAC-0043 で実装済みの PNG 連番＋WAV ライター）を UI から選べなかった。

**どこを変更したか。** Apps/DebugApp の ExportDialogView.swift（全面改訂）、ExportJob.swift（ExportRequest の追加と振り分け）、ProjectView.swift（呼び出し側の追随）。

**どう実装したか。** ダイアログに形式の選択（mp4（H.264 / AAC）／ PNG+WAV（連番画像と音声））を置いた。PngWav 選択時は出力先をフォルダ選択（NSOpenPanel、フォルダ作成可）に切り替え、ファイル名接頭辞と PNG / WAV の出力トグルを出す。接頭辞の初期値はプロジェクト名（本家は設定 UI を開く副作用でプロジェクト名へ上書きする構造だったものを、明示的な初期値として置き換えた）。確定内容は ExportRequest（.mp4(fileURL) / .pngWav(directoryURL, settings)）として ExportJob へ渡り、ジョブが TimelineExporter.run / runPngWav へ振り分ける。形式を切り替えたら出力先は選び直させる（ファイルとフォルダで種類が違うため）。PNG / WAV の両方無効、または接頭辞が空の場合は「出力」を押せないようにした（成果物が生まれない構成を事前に止める）。

**検証。** Mac で DebugApp パッケージのビルド成功（Build complete、エラーなし）。runPngWav 自体の書き出し検証は MAC-0043（PR #88）で実施済みであり、本単位は UI 接続のみのため書き出しの再検証はしていない。ダイアログの実表示はフロントエンド目視確認の際に併せて確認する。

**第10ラウンドレビューの処分（2026-11-18、条件付き採用可 → 全件処分済み）。** R10-01【P1】既存ファイルの破壊的上書きと接頭辞のパス解釈: PngWavFileWriter の初期化で接頭辞を単一のファイル名成分として検証する述語（isValidFileName — パス区切り・親ディレクトリ参照・空白のみ・NUL を拒否）を追加し、有効なストリームの拡張子について同名の連番ファイルが残っている出力先は開始前に型付きエラーで拒否するようにした。ダイアログ側の出力可否判定も同じ述語を使う。単体テスト2件（不正な接頭辞の拒否、既存ファイルの保護と拡張子別の衝突判定）を追加。R10-02【P2】接頭辞の初期値を project.filePath（.ymmp 内の保存値）から sourceURL（今開いているファイル）へ変更。R10-03【P2】UI 接続後の実書き出し: ダイアログが生成するのと同じ ExportRequest を ExportJob へ渡す経路で、サンプルプロジェクト（530 フレーム）を使い PNG+WAV 両方・PNG のみ・WAV のみ・衝突時の拒否と既存ファイル無傷・不正な接頭辞の拒否を Mac 実機で検証し全件通過（リリースビルド。純 Swift 製 PNG エンコーダがデバッグビルドでは 530 フレームの書き出しに実用的な時間で終わらないため。検証用テストは作業コピーのみの使い捨てでリポジトリには含めない。ダイアログの物理操作そのものは GUI 操作手段がないため未実施で、実表示の確認はフロントエンド目視確認に残る）。R10-04・R10-05【P2】R6-02-MEAS と SOLA-DIFF の断定的な文言（実負荷の下限、UI 遅延の断定、効果原因の断定、音質差の断定）を、測定・記録の範囲に収まる表現へ修正した。

#### R6-02-MEAS — 高負荷再生時のメインキュー占有の実測（レビュー第6ラウンド指摘 P2。MEASURED）

**測り方。** 本人の実プロジェクト（158 アイテム、11,994 フレーム、60 fps、1920×1080）を対象に、アプリの実経路（メインキューの 33 ms タイマ → ProjectView.onPositionChanged → 同期 renderPreview() → PreviewBox.render = TimelineComposer.update ＋ CGImage 読み戻し）をハーネス（r602-harness）で再現し、Mac 実機で測定した。生データはフレーム単位の JSONL（census）と summary.json。

**結果（Phase A: 全フレーム合成、usage=.playing）。** 平均 20.2 ms、中央値 20.7 ms、p95 44.9 ms、最大 90.3 ms、失敗 0 件。60 fps の1フレーム予算 16.7 ms の超過は 7,021 フレーム（58.5%）、33 ms 超過は 2,549（21.3%）。最も重い 30 秒区間はフレーム 9217–11016（平均 36.7 ms/フレーム）。最重フレーム群（フレーム 10810–10938、最大 90.3 ms）はアクティブなアイテムが 3 件の区間にある。件数の多さでは説明できないため特定の効果処理等が主要因である可能性があるが、効果別の計測はしておらず原因は未同定。

**結果（Phase B: アプリ方式の再現、最重 30 秒区間）。** ティック 802 回 / 30 秒（定格は約 909 回）。ティック間隔は平均 37.5 ms、p95 45.8 ms、最大 128.4 ms、50 ms 超過 21 回。描画時間は平均 35.4 ms、p95 45.8 ms、最大 128.3 ms で、33 ms 予算に対する占有率は約 1.07。メインキューが飽和し、再生位置の更新が実時間に追いつかない。描画処理による最大 128.3 ms の連続占有が観測され、その間のメインキュー作業（UI 入力等）に遅延が生じうる（遅延そのものは直接測定していない）。

**測定の限界。** 素材ファイルは Mac 上に無い（プロジェクト内の参照は Windows パス）ため、動画・画像ソースは透明フォールバックで描かれている。実素材を使用する場合はデコード等による追加負荷が生じる可能性があるため、本測定の結果を実素材使用時の性能と同一視できない。応答性プローブ（メインキューへ no-op を積む方式）は積む位置が描画完了直後だったため指標にならず、遮断時間は描画時間の分布で評価した。2026-11-17 の性能監査（典型 8.1–8.8 ms）は機能フェーズ前で測定範囲が同一とは限らず、単純な劣化比較はしない。

**結論と次。** R6-02 の懸念は実測で裏付けられた。対策の本筋は「合成をメインキューから外す＋遅れたらフレームを落として最新位置へ追いつく」。描画経路の設計変更にあたるため、設計相談（第9ラウンド）で並行解析してから着工し、締切までの実施範囲を決める。

#### R6-02-FIX — プレビュー合成の背景キュー化とモデル隔離（第9ラウンド設計の第1段階。IMPLEMENTED、受け入れ実測済み）

**何を実装したか。** プレビュー合成をメインキューから外し、描画側は編集モデルから独立したスナップショットだけを読む形にした。設計は第9ラウンドの処方どおり: 世代番号による結果破棄だけでは読み取り時点の競合を取り消せないため、データの隔離と結果の新旧判定を分けた。

**どこを変更したか。** Apps/DebugApp に PreviewRenderWorker.swift を新設。ProjectView.swift のプレビュー配線を全面差し替え（PreviewBox の直接保持と同期 renderPreview を廃止）。PreviewBox 自体は変更していない。

**どう実装したか。** PreviewRenderWorker が専用直列キュー（userInitiated）を持ち、PreviewBox の生成・描画・破棄を全てその上で行う。描画モデルは Project.makeExportSnapshot（JSON 往復、書き出しで実績のある経路）のスナップショットで、編集の反映時にだけメイン側で作り直して渡す。スナップショット生成のコストは同じ実プロジェクト（158 アイテム）で平均 27.97 ms（最小 27.75 / 最大 28.77、n=10）と実測したため、連続編集時は 100 ms 未満の間隔では間引き、間引いた分は遅延確定とドラッグ終了時の強制再生成で必ず反映する。描画要求は requestPreviewRender への単一入口に集約し、位置変更に伴う二重要求（スライダーの onChange と位置通知の双方が描画していた問題）を解消した。再生中はモデルに触らずフレーム要求だけを出し、編集は dirty として残して停止後の要求で反映する。要求は実行中 1 件＋保留 1 件（保留は最新で上書き）。完成画像の採用は二段階規則: 同じセッション・同じモデル版数の結果は後続要求があっても採用し、古いセッション・編集前のモデルの結果だけを捨てる（合成 36.7 ms に対して要求 33 ms 周期のため、新要求があるという理由だけで捨てると画面が更新されなくなる）。

**受け入れ実測（Phase D、同じ実プロジェクトの最重 30 秒区間で新方式を再現）。** ティック 911 回 / 30 秒（Phase B の旧方式は 802 回、定格は約 909 回）。ティック間隔は平均 33.0 ms、p95 34.3 ms、最大 37.4 ms（旧方式は平均 37.5、p95 45.8、最大 128.4）。描画中のメインキュー応答性プローブ（16 ms 周期、1,878 件）は平均 0.011 ms、最大 0.18 ms で、メインキューが描画から解放されたことを直接確認した。実効プレビュー更新は 836 フレーム / 30 秒 = 27.9 fps で、描画時間（背景キュー上 平均 37.9 ms、p95 68.1 ms、最大 111.6 ms）から決まる理論上限（約 27 fps）と整合する。60 fps の全フレーム描画ではない。音声をマスターとして映像を間引く形が達成されたものである。

**付随する変更。** サムネイル保存は、同期描画した画像ではなく現在表示中の画像を使う形になった（合成の非同期化に伴う仕様変更）。

**未解決。** 音声側（TimelineAudioMixer）は編集中の生タイムラインをエンジンのチャンク生成経路から読み続けており、映像側を隔離しても競合が残る。これは本対策で新たに生じた問題ではなく既存の未解決事項で、第9ラウンドで第2段階の処分対象とされた（Issue #106 で追跡）。素材ファイルのある環境での実測は未実施（素材が Mac 上に無い）。アプリ実機での操作感の確認はフロントエンド目視確認に残る。

**第11ラウンド処分（2026-11-18、条件付き採用可・現状ではマージ不可 → 全件処分）。** 初版のワーカーには順序制御の欠陥があり、レビュー指摘は全て実コードで確認できたため、ワーカーを再設計した。

- R11-01【P1】latest-wins が成立していなかった（初版の欠陥）。要求ごとに直列キューへブロックを積む構造では、描画中は保留スロットへの書き込み自体が実行されず、要求がキューの中に蓄積していた。再設計: 要求はキューへ仕事を積まず、ロック保護の保留スロット（最大1件）へ最新値だけを書き込む。描画ループは1描画ごとにブロックを積み直すため、モデル差し替え・無効化が描画の合間に割り込める。
- R11-02【P1】再生中の編集でもモデル差し替えが走っていた。モデルへ触るか否かは要求の属性ではなく実際の再生状態（isPlayingForm）で決める形に変更。ドラッグ終了時の強制再生成も同じ単一入口を通す。再生中の編集は dirty に保留され、停止への遷移時に確定する（R11-05 と併せて処分）。
- R11-03【P2】初期化失敗の通知にも識別子（キー・世代・版数）を付け、受信側で照合する。
- R11-04【P2】セッション世代を導入（再初期化のたびに増加）。採番は呼び出し側が一元化し、ワーカーは受け取った識別子をそのまま返す（二重採番の廃止）。位置世代（epoch）は当初追加したが、保留が単一スロットであるため取り出し時点で常に最新であり、追加の間引き機構としては不要と確認して置かないことにした。
- R11-05【P2】再生→停止の遷移時に、保留中の編集を強制反映して最終フレームを要求する（自然終了で位置通知が来ない経路への対処）。
- R11-06【P2】スナップショット生成失敗は理由をステータスへ表示し、遅延再試行を予約する。遅延確定は DispatchWorkItem 1件に集約し、セッション切替で取り消す。
- R11-07【P2】Phase D の実測値の撤回と再実測。下記のとおり初版の受け入れ実測（Phase D）は測定方法自体に欠陥があったため、その数値（実効 27.9 fps 等）は撤回する。
- R11-08【P2】サムネイル保存は、現在位置・現在モデルに対応する画像が表示済みの場合だけ即時保存し、それ以外は対応画像の完成を待ってから保存する。

**Phase D 実測の撤回。** Phase D のハーネスは新方式の「再現」であり、本物のワーカーを通していなかった。再現側にも初版と同じ間引き不成立の構造が含まれていたうえ、配信数の数え方に測定区間後の完了分が混入しうる形で、報告値同士が整合しなかった（配信 836 件 × 描画平均 37.9 ms が測定区間 30 秒を超える）。よって Phase D の数値は受け入れ根拠として撤回する。メインキューが描画から解放されるという方向性の結論は、下記の再実測でも維持された。

**再実測（Phase E、本物の PreviewRenderWorker を実プロジェクトの最重30秒区間で駆動。ハーネスは Harnesses/preview-worker-harness、PreviewCore にリンク）。** ティック 911 回（定格約909）、間隔 平均 33.0 / p95 34.3 / 最大 36.6 ms。ワーカー計数: 要求 912 件（ティック 911＋準備1）、上書き 138 件、描画開始 774・完了 774（912 − 138 = 774 で計数が完全に閉じる）、配信 773 件、実効プレビュー 25.8 fps。配信フレームの音声位置からの遅延は平均 2.81 フレーム（約47 ms）、p95 5、最大 8 フレームで、区間を通じて増え続けない。メインキュー応答プローブ（16 ms 周期、1,879 件）は平均 0.015 ms、p95 0.05 ms、最大 1.04 ms。

**順序制御の単体テスト（PreviewCoreTests、Mac で 4 件合格）。** 描画を門で止めて10件要求しても保留は最後の1件だけ（描画は2回だけ実行）。描画中のモデル差し替えで旧モデルが破棄され新モデルが描かれる。無効化した世代は描かれず次世代だけが描かれる。初期化失敗の通知に識別子が付く。テストの過程でさらに2件の競合を発見して修正した: モデル差し替えブロックが保留を消すため、差し替え呼び出し直後の要求が実行順序によって永遠に描かれない経路があった（保留は消さない形に変更）。無効化ブロックが保留を消す範囲を、無効化呼び出し時点までの要求だけに限定した（通し番号による区切り）。
**第12ラウンド再レビュー（2026-11-18、条件付き採用可）と処分。** R11-01〜08 は全件解消認定され、Phase E の計数整合も認定された。新規指摘は P1×1（R12-01）と P2×5（R12-02〜06）で、全件処分した。
- R12-01【P1、マージ必須条件】フレーム要求に発行時点の識別子を付け、要求はその識別子のモデルでだけ描く。識別子が現行モデルと異なる要求は消費せずに残して描画ループを止め、対象モデルの設置完了時にワーカー側が描画を再開する。モデル差し替えより先に積まれた描画ブロックが新世代の要求を旧モデルで消費し、要求が失われる経路を遮断した。レビュアー指定の必須試験2件を追加（新版数向けに先行した要求が旧モデルで描かれず新モデルで描かれること、無効化と新世代設置の途中の要求が新世代で描かれること）。単体テストは計6件全合格。あわせて Identity と SessionKey に Sendable 適合を追加した（Swift 6 の送信診断への対応）。
- R12-02【P2】停止中は現在位置と一致するフレームの配信だけを採用する（シーク前に始まった描画の結果で表示が巻き戻らない）。再生中は従来どおり多少古いフレームも採用する。
- R12-03【P2】遅延確定をスロットル化した。既に予約がある場合は先送りせず、発火時に予約を空へ戻すため、連続編集でも約 100 ms ごとに最新状態が反映される（従来は呼ばれるたびに取り消して張り直すため、編集が続く間は確定しないデバウンスだった）。
- R12-04【P2】受け入れ実測のメインキュー応答プローブを背景キュー起点に変更した（メインキュー上のタイマでは、タイマ自体の遅延を観測できない）。
- R12-05【P2】実測の配信数を正常画像と失敗に分け、計測区間内とドレイン分も分けて記録する形にした。
- R12-06【P2】サムネイル保存の保留に、形式だけでなく要求時点の識別子とフレームを持たせた。同じモデルの別フレームが先に完成した場合は別フレームを保存せず取り消し、モデルが変わった場合も取り消す。
- 再実測（Phase E、計測器の修正後）: 要求 912・上書き 114・描画 798（912 − 114 = 798 で整合）、正常画像の配信 797 件（準備描画を除く。うち区間内 795・ドレイン 2）、失敗 0、実効 26.5 fps、配信遅延 平均 2.77 フレーム・p95 5・最大 8、背景起点プローブ 平均 0.012 ms・最大 0.72 ms（1,879 件）。

**第13ラウンド確認（2026-11-18）と R13-01 の処分。** R12-01〜06 は全件解消認定された。そのうえで新規 P1 が1件指摘された。
- R13-01【P1】描画ループの停止判定が、要求の確認と別のロック区間になっていた。確認と停止の間に届いた要求は「ループ稼働中」と誤認して起動の機会を失い、保留されたまま描かれない経路があった（lost wake-up）。処分: step() の要求確認と停止判定を単一のロック区間で完結させた。停止前に届いた要求は確認の対象になり、停止後に届いた要求は loopActive == false を見てループを起動できる。回帰試験として、停止境界をまたぐ要求の往復を100回繰り返し、全て描かれることを確認する試験を追加した。第15ラウンドで解消認定され、修正は PR #111 としてマージ済み。
#### R6-06 — AlphaMask の描画失敗を利用者へ知らせる診断（第9ラウンド設計。IMPLEMENTED、PR #107 マージ後の main へ載せ替え済み）

**問題。** クリッピングのマスク合成（MetalAlphaMaskEffect）が GPU 実行に失敗すると、透明画像へのフォールバックは行われるが失敗自体は無言で、利用者には「アイテムが消えた」ようにしか見えなかった。合成器側は効果の内部で完結する失敗を観測できず、プレビューの成功経路がエラーを消していた。

**何を実装したか。** 描画セッションが所有する診断収集先（RenderDiagnosticsCollector、YMM4GPU に新設）を導入し、失敗は種別ごとに集約（回数・最新内容・通し番号）される。MetalAlphaMaskEffect の warp 失敗時に透明フォールバックは維持したまま収集先へ報告する。Core の AlphaMaskEffect.setInput の非 throwing 契約は変更していない（本家の D2D 効果境界の形を維持するため、この境界では型付き例外への変換はしない）。

**伝播。** セッションの所有者はプレビューでは PreviewBox。MetalSourceProvider の子供給元（シーン・合成グループ・トランジション）と内部合成器の MetalAlphaMaskEffectFactory へ同じ収集先を伝播させるため、内部合成で発生した失敗も外側のセッションへ届く。書き出し経路（MetalExportVideoProvider）は今回の対象外で、収集先は未接続（失敗は従来どおり無言）。必要になれば同じ形で接続できる。

**表示。** PreviewRenderWorker が描画ごとの失敗（現在の失敗状態）とセッション履歴の集約を完了通知に含める。ProjectView は現在の失敗をプレビュー下端の通知で示し（正常な描画が完了すると解消）、履歴は診断タブに残す。現在の失敗状態と診断履歴を分けたのは第9ラウンドの設計どおりで、一時的な失敗の表示が成功フレームで消えても、調査用の履歴はセッション中残る。

**検証。** Mac で DebugApp のビルド成功。収集先の集約規則（同一種別の集約、通し番号による切り分け、クリア）の単体テスト3件を追加し合格。実際の GPU 失敗を意図的に発生させる手段が無いため、失敗時の表示経路そのものは実機未検証（配線は型検査とビルドで確認済み）。素材のある環境での確認はフロントエンド目視確認に残る。


**第14ラウンドレビュー（2026-11-18、条件付き採用可）と処分。**
- R14-01【P1】トランジション内部の子プロバイダへ診断収集先が伝播していなかった（transitionComposerFactory の makeComposer で childProvider の生成に diagnostics を渡していなかった。他の子供給元の生成箇所は全て渡していた）。子プロバイダの生成にも同じ収集先を渡すよう修正した。
- R14-02【P2】モデル版数の変更時に診断の表示状態（現在の失敗・履歴）もリセットするようにした。診断の所有者はモデルごとに作り直される描画セッションであり、旧モデルの診断を持ち越さない。
- R14-03【P2】描画失敗の通知にも、正常画像と同じ採用条件（停止中は現在位置と一致するフレームだけ）を適用した。シーク前の失敗通知が現在の表示を消さない。
- 確認試験を追加した: 偽セッションで診断を記録し、失敗のある描画では今回分が非空・次の正常な描画では空・履歴には残ること、モデル切替後に旧モデルの診断が混入しないことを検証する（PreviewCoreTests）。
- 第16ラウンドで R14-01〜03 は全件解消認定され、PR #111 との統合も確認された。新規の R16-01【P2・非ブロッキング】として、追加試験の偽セッション設定（描画中にテスト側から変更する可変フラグ）に競合があると指摘された。処分: 記録対象を「診断を記録するフレーム集合」の不変設定に変え、描画中の変更を無くした。

#### MAC32-01-FIX — エフェクト編集マージの型ガード（Issue #57。IMPLEMENTED）

**問題。** 編集の書き戻しで未知キーを保持する再帰マージ（VideoEffectRegistry.mergeNestedFields、MAC-0032 で導入）は、入れ子オブジェクトの `$type` が編集前後で変わった場合にも再帰し、旧型の未知キーを新型のオブジェクトへ混入させていた。多態パラメータ（ブラシ等）が編集可能になったため、Issue #57 の発動条件（多態パラメータが編集可能になるタイミング）が成立した。

**実装。** mergeNestedFields の入口で、両側とも `$type` を持ち値が異なる場合は再帰せず型付き側をそのまま返す。どちらか一方でも `$type` を持たない場合は型の同一性を判定できないため従来どおりマージする（`Animation` のような `$type` を持たない入れ子の未知キー保持＝UI29-01 の動作を壊さない）。トップレベルの型ガードは既存の encode(_:preservingUnknownFieldsOf:) にあったため、今回の変更は入れ子レベルのみ。

**検証。** 単体テスト3件を追加（EffectMergeTypeGuardTests）。FillBackground のブラシ Parameter を SolidColor から LinearGradient へ切り替えた場合に旧型の未知キーが残らないこと、同型では保持されること、`$type` を持たない Animation 内の未知キーは型付きエンコードが落としてもマージが回収すること。Linux の Swift で 3 件とも合格（Core のみに閉じた変更のため）。

#### SOLA-DIFF — 音高保持（ピッチを保ったまま速度を変える処理）の二系統の差異（第7ラウンド合意による記録）

**アイテム側。** 各アイテムの再生速度モードは Resampling / Sola の2種（YMM4Core の PlaybackRateMode）。Sola は SolaTimeStretchStream ＋ SoundTouchProcessor（本家同梱の SoundTouch.Net 2.3.2 と同じ仕様の再実装）で処理し、プレビュー・書き出し共通の音声パイプラインで適用される。

**プレビュー全体側。** RealtimePlaybackEngine が出力段に方式ノードを挿入する（速度が 1.0 でない場合だけ挿入する構造は本家と一致）。Resampling は AVAudioUnitVarispeed（音高は速度に連動）、音高保持は AVAudioUnitTimePitch（Apple 製）。Varispeed の rate は 0.25–4.0 でクランプされ、本家の MFT リサンプラには無い上限である（コード内コメントに記録済み）。TimePitch の範囲は 1/32–32。

**差異。** 両系統は異なるアルゴリズムを使用しており、同一条件での出力波形・音質の等価性は未検証である。アイテム側 Sola が掛かった素材をプレビュー全体速度の TimePitch でさらに伸縮すると、異なる伸縮処理が二重に重なる構造になっており、書き出し（全体速度は効かない）との間にも処理経路の差がある。本家のプレビュー全体速度の音高保持の中身はデコンパイル側で未同定であり、TimePitch の等価性は未検証。是正範囲は本記録の後に判断する。

#### FE-SLIDER-CORE — スライダ表示仕様の Core 基盤（フロントエンド監査 FE-R1-042、単位2前半）

**何を実装したか。** アニメーション付き数値プロパティのスライダ表示仕様（基準範囲・表示形式・単位・刻み）を Core で保持し、記述子構築時に解決する基盤。本家は各 `Animation` プロパティへ `AnimationSliderAttribute`（StringFormat / UnitText / DefaultMin / DefaultMax）を付け、スライダの基準範囲を絶対制限（`Animation` 自身の minValue / maxValue）とは別に決める。従来のポートにはこのデータが無く、アプリ層のスライダは絶対制限全域をそのまま範囲にしていた（FE-R1-042 の欠陥）。本単位は Core の型・参照表・解決までで、スライダ UI は次単位。

**型と表。** `AnimationSliderSpec`（`Sources/YMM4Core/Editing/AnimationSliderSpec.swift`）: defaultMin / defaultMax / stringFormat / unit / unitIsResourceKey / delay と、導出プロパティ `delta`（本家 `Delta` の規則の再実装: 形式が "F<n>" なら 0.1^n、数値化できなければ 1、"D" 始まりなら 1。それ以外は本家属性自体が例外とする形式で表に存在しないため防御として 1）。`delay` は本家属性のコンストラクタが設定しないため属性由来では常に 0。参照表 `AnimationSliderTableData.swift` は抽出データ（本家デコンパイルからの `AnimationSliderAttribute` 全 1,023 件）から機械生成した Swift ソースで、生成スクリプトは解析側ワークスペースの `frontend-audit/generate_slider_table.py`（生成ファイルのヘッダに生成元と再生成方法を記載）。

**キー設計の根拠（衝突検査の実測）。** キーは (所有型の完全修飾名, プロパティ実名) とし、表示名はキーにしない（監査 Round 2 の設計判断）。抽出 1,023 件を (単純クラス名, プロパティ) で数えると一意な組は 1,018 件で、5 件の重複（`DrawingBrushParameterBase` の X / Y / Angle / Aspect と `ScalableDrawingBrushParameterBase` の Zoom）が存在する。この 5 件はいずれも `YukkuriMovieMaker.Brush` と `YukkuriMovieMaker.Plugin.Community.Brush` の同名クラス同士で、仕様値は完全一致する。完全修飾名をキーにすれば 1,023 件全てが一意になるため、完全修飾キーを採用した。所有型の正規化は、ポート側の $type 名（"完全修飾名, アセンブリ名"）から最初のコンマ以降を落とす規則で統一する（`AnimationSliderKey.ownerTypeName(fromTypeName:)`）。

**未解決の単位（38 件）。** 抽出時に単位が本家 `Texts` リソースのキー名だった 38 件は、実文字列がデコンパイル側に含まれないため、キー名のまま表へ保持し `unitIsResourceKey = true` で未解決と判別できるようにした。推測で文字列は埋めていない。実文字列の確定はリソース側の調査が別途必要（次単位以降の残件）。

**対象外（8 件）。** `ConditionalUnitAnimationSlider` の 8 件（LinearGradient の Size / Offset、GradientMesh の Width / Height 等、単位が条件で切り替わるもの）は通常の属性と意味論が異なるため今回の表に含めない。該当プロパティの記述子は仕様なしのまま残る（試験で固定）。

**記述子への解決。** `PropertyKind.animation` に `spec: AnimationSliderSpec?` を保持させ（絶対制限は従来どおり `Animation` 側）、`PropertyDescriptor.sliderSpec` で参照できるようにした。解決は入口の一括処理 `AnimationSliderTable.resolving(_:ownerCandidates:)` で行い、候補は「具象型 → 宣言基底」の順に最初に一致した宣言を使う。仕様が見つからない記述子は nil のままにし、絶対制限全域へのフォールバックはしない。不足は `AnimationSliderTable.unresolvedProperties(in:ownerCandidates:)` で診断として収集できる。

解決を組み込んだ経路: (1) アイテム（`ItemPropertyMetadata.descriptors(for:)`）— 候補は具象アイテム型の $type 名、`VisualItem`、`BaseItem`。本家では宣言場所がプロパティごとに異なる（Volume 等は具象型、X 等は `VisualItem`、`PlaybackRate2` は具象型ごとに範囲が異なる再宣言で `BaseItem` には属性自体が無い）ため、この候補順が要る。VoiceItem の字幕系は id 自体が本家プロパティ名（JimakuX 等）であり具象型で引ける。(2) エフェクト（`EffectPropertyMetadata.descriptors(for:)`）— 候補は具象定義の $type 名（本家ではエフェクトのプロパティは具象クラスが宣言する）。(3) 複合子のうち所有型を特定できるもの（`EffectPropertyMetadataComposite`）— ブラシパラメータ子（パラメータ型ごとに具象型→宣言基底の候補表を実測のクラス階層で固定）、Drawing 変換子（`DrawingBrushParameterBase`）、グラデーションメッシュ格子点（`GradientMeshPoint`）、メッシュ変形の点（`MeshDeformationPoint`）、モザイクの Size（形状ごとの具象型→`SizeMosaicParameterBase`）。

未対応の経路: 生保持オブジェクトの汎用子（rawObjectChildren 等）は所有型をその層で特定できないため解決しない（仕様なしが正で、試験でも固定）。また実装中に判明した既存の欠落として、`ItemPropertyMetadata` は VideoItem / AudioItem に Volume / Pan の記述子自体を出していない（VoiceItem のみ）。表には両型の Volume 仕様があるため、記述子側の欠落は別途処分が要る（本単位の範囲外として記録）。

**スケール計算を含めなかった判断。** 本家 `TextBoxSlider.ChangeMinMax` の2の冪スケール拡張は、監査 Round 2 の設計判断で「UI 側の派生状態」（セグメント間で最大スケールを共有する MinScale 伝播、移動量モードの対称範囲置換、端点補正といった表示モデル側の例外を含む）と位置付けられている。純粋関数として切り出しても、検証は結局コントロールの振る舞いと対で行う必要があり、Core へ先行して置くと未検証の式だけが固定されるため、本単位では含めず UI 単位で扱う。これは省略ではなく設計判断としての記録である。

**本家との差分。** ユーザーから見える差はまだ無い（UI 未接続）。内部差として、本家は属性をプロパティ宣言に直接持つが、こちらは生成表＋構築時解決で等価な情報を再現する。`ConditionalUnitAnimationSlider` と単位リソースキー 38 件は本家でも条件分岐・リソース参照で解決されるもので、こちらでは未解決のまま明示する。

**検証。** Mac（同期先 ~/ymm4-work/fe-slider/YMM4Mac）で方式名フィルタ実行し全合格: 新規 `AnimationSliderSpecTests` 14 件（表の全件性とキー一意性、両名前空間の同名クラスの一致、リソースキーの未解決表示、delta 導出 F0/F1/F2/F4、VideoItem 音量の表レベル裏取り、VoiceItem の記述子解決と単位の全角 ％、`PlaybackRate2` の型別範囲、VisualItem 経由の解決、TextItem の `PlaybackRate2` が仕様なし＋診断に載ること、ZoomEffect の解決、ブラシ子・格子点の解決、ConditionalUnit の対象外固定）、既存 `PropertyMetadataTests` 17 件、`EffectPropertyMetadataTests` 17 件（うち1件は `PropertyKind` のケース変更に伴い等値表明を `.animation(spec: nil)` へ精密化）。合計 48 件・失敗 0。AudioDrift は既定どおり除外。

**次の担当へ（アプリ層の破壊箇所）。** `PropertyKind.animation` への関連値追加により、アプリ層で式位置の `kind == .animation` 比較がコンパイル不能になる。Mac でアプリパッケージをビルドして実測した破壊は `Apps/DebugApp/Sources/YMM4MacDebug/ProjectView.swift` の 800 行目と 944 行目の2箇所のみ（エラー: member 'animation(spec:)' expects argument）。次単位（スライダ UI）で同ファイルに触る際にパターン照合へ直すこと。本単位ではアプリ層に触っていない。

**追随修正（同ブランチで実施）。** 上記2箇所（`ProjectView.swift` の `writeAnimationProperty` / `writeItemPosition`）を `guard case .animation = descriptor.kind` のパターン照合へ置き換えた（意味は従来どおり「animation 種別か」の判定で不変）。Mac（同期先 ~/ymm4-work/fe-slider/YMM4Mac）で `Apps/DebugApp` の `swift build` 成功と `AnimationSliderSpecTests` の合格を確認済み。

#### FE-R8-001 — VideoItem / AudioItem の Volume・Pan 記述子を追加（フロントエンド監査 Round 8、P2）

**何を実装したか。** `ItemPropertyMetadata.descriptors(for:)` は音量・パンの記述子を `VoiceItem` にのみ追加しており、`volume` / `pan` をモデルとして保持する `VideoItem` と `AudioItem` ではインスペクタから編集できなかった（監査 Round 8 で FE-R8-001 として採番）。両型に対して、グループ「音声」・表示名「音量」「パン」（`VoiceItem` の音声系と同一）のアニメーション記述子を追加した。追加は共通ヘルパ `audioDescriptors(volume:pan:)` に寄せ、本家で両プロパティが各具象型に宣言され `AnimationSliderAttribute` も具象型ごとに付く実態に合わせ、スライダ仕様は FE-SLIDER-CORE の解決経路で具象型の宣言から引かれる。

**検証。** Mac（同期先 ~/ymm4-work/fe-r8-001/YMM4Mac）で方式名フィルタ実行し全合格: `PropertyMetadataTests` 19 件（新規に両型の記述子の存在・get/set の結線・スライダ仕様の解決を固定）、`AnimationSliderSpecTests` 14 件、`EffectPropertyMetadataTests` 17 件。合計 50 件・失敗 0。AudioDrift は既定どおり除外。期待値（範囲・形式・単位）は抽出データ `slider-attributes.json` の両型 Volume / Pan で裏取り済み。

#### FE-UNIT6 — セリフ入力・キャラクター・辞書ウィンドウの検査と修正（フロントエンド監査 FE-R1-018。IMPLEMENTED、目視確認は未実施）

**走査結果（現行コード 5f9cd5d で再検証）。** 対象3面の状態は次のとおりだった。(1) セリフ入力行: テキスト入力・キャラクター選択・追加（AddVoiceMode の「追加してシーク」含む）は実動。一方キャラクター設定ボタンは空アクションのまま有効で、ヘルプに未接続サフィックスが付いただけだった（FE-R1-018 のとおり）。アプリ内にキャラクター編集 UI は一切無く、ツールメニューの「キャラクター編集…」も無効のままだった。結果として、キャラクターは読み込んだ .ymmp からしか存在できず、新規プロジェクトではセリフ行が恒常的に「キャラクター未登録」になり、作成する手段が無かった。(2) インスペクタ: VoiceItem の記述子にはセリフ・音量・パン・字幕系はあるが、本家のアイテム編集画面にあるキャラクター選択（VoiceItem.Character の CharacterComboBox、Order 110）と発音（Hatsuon、Order 130 の HatsuonTextBox）が無く、既存アイテムのキャラクター変更と発音の表示・編集ができなかった。TachieItem / TachieFaceItem も同様にキャラクター変更の手段が無かった。(3) 辞書ウィンドウ（TEXT60）: CRUD・保存・失敗表示は配線済みで、ストア側の試験も保存・世代・失敗・スナップショットまで揃っていた。ただし編集画面の使い方に沿った CRUD 往復（複数リスト×追加→編集→削除→再読込）の試験固定が無く、行のインデックス束縛に範囲外アクセスの余地があった（編集中に件数が変わると再描画途中で旧インデックスが評価され得る）。

**処分1 — キャラクター編集シートの新設と FE-R1-018 の解消。** `CharacterEditorView`（アプリ層、新規ファイル）を追加し、セリフ行のボタンとツールメニュー「キャラクター編集…」（WorkspaceState.isCharacterEditorPresented 経由、動画の設定と同じ表示要求パターン）の両方から開けるようにした。内容はプロジェクトのキャラクター一覧管理（追加・複製・削除）と識別に関わる基本項目（名前・グループ名・色・レイヤー・備考・音声エンジン API・話者 Arg）の編集。複製の土台として Core に `Character.cloned()`（JSON 往復の深い複製、未知フィールド含む全保持）を追加し、試験で独立性を固定した。音声エンジン／話者は両方が空なら Voice 自体を nil へ戻し、保存形式（未設定は null）を保つ。字幕・立ち絵の詳細項目（Character の全86プロパティ中、字幕の書式や立ち絵パラメータ等）はこの画面では扱わない。話者の選択 UI や立ち絵パラメータは音声合成・プラグインの基盤が Mac 版に無く、本家の設定ウィンドウ相当の広い画面は別単位の設計判断になるため、基盤待ちとして記録するに留めた。

**処分2 — 削除と改名の参照整合（データ保全）。** Mac 版の参照は読み込み時に名前で解決される（MAC-0015）ため、削除・改名は次の規則にした。改名: 解決済みアイテムの保存名は参照先の現在名から決まる（本家の CharacterName getter 規則と同じ）ため、インスタンスの改名だけで追随し、アイテム側の書き換えはしない。同名キャラクターが複数あると解決は先頭一致になるため、編集シートでは重複を警告表示する（作成・複製時は一意な名前を自動で付ける）。削除: 参照中（インスタンス一致、または未解決で名前一致）のアイテムがある場合は確認アラートを出し、件数と帰結（名前だけが残り参照を失う）を明示する。確定時は参照インスタンスを持つアイテムの参照だけを外し、名前には実効名（削除時点の現在名）を残す。これによりメモリ上の状態が「削除して保存・再読込した後」と一致し、失われるのはキャラクター定義だけになる。

**処分3 — インスペクタのキャラクター選択行。** `CharacterPickerRowView`（アプリ層、新規ファイル）を新設し、VoiceItem / TachieItem / TachieFaceItem のアイテム詳細の先頭に置いた。記述子はアイテム単体から構築されプロジェクトの一覧を知らないため、専用行としてアプリ層に置く判断である（ファイル参照の FilePathRowView と同じ構図）。3型の参照読み書きは `CharacterItemAccess` に集約した。選択は参照インスタンスと名前の両方へ書き込み、未解決の保持名は候補に無くても表示する。「（なし）」を選ぶと参照と名前の両方を空にする。あわせて Core の VoiceItem 記述子に発音（Hatsuon）を追加した（音声グループ内、セリフの直後＝本家の Order 順）。本家では発音は音声生成時にセリフから自動生成されるが、Mac 版には読み変換経路が無いため、保持値の表示・手動編集のみが対象である。

**処分4 — セリフ行の選択の帳簿。** `SerifInputView` の選択中キャラクター名は @State に名前文字列で保持され、初期化は onAppear のみだった。キャラクター編集が可能になったことで、選択中のキャラクターの削除・改名時に名前が宙に浮く経路が生じるため、一覧の名前集合が変わるたびに再検証し、存在しない名前は先頭へ倒すようにした。追加時も、一覧に無い名前は渡さず「キャラクターなし」として追加する。なお選択は名前で追うため、選択中キャラクターを改名すると（先頭でない場合）選択は先頭のキャラクターへ移る。本家は設定側のオブジェクト参照で選択を保持し改名へ追随する点が異なる（下記のモデル差異に帰属する制限として記録）。

**処分5 — 辞書ウィンドウの固定と堅牢化。** UserDictionaryStoreTests に CRUD 往復試験を追加した（3リストへの追加→保存→再読込→1件編集・1件削除→保存→再読込→全件削除で空リストが既定値で補われず空のまま残ることまで）。編集画面（UserDictionaryEditorView）のインデックス束縛3種と行の削除ボタンに範囲ガードを入れ、範囲外は読み取りでは既定値、書き込みでは無操作に倒した。

**辞書の適用先に関する区別（重要）。** 辞書の3リストは「未接続の偽コントロール」ではない。アスタリスクはテキスト描画の前処理（TextPreprocessor.applyAsterisk → MetalTextRasterizer）へ実際に適用され、編集は再描画要求（userDictionaryChanged）を通じてプレビューへ反映される。単語・発音は、適用部品（読み変換の前段・後段の置換処理）自体は実装済みだが、Mac 版には漢字→読み変換経路と TTS が存在しないため、現時点では描画・音声へ効かない。これは辞書データの編集・保存（本家の辞書機能の正当な移植範囲）の欠陥ではなく、適用先の基盤（音声合成）が未着手であることに帰属する。基盤が来た時点で、保存済みの辞書がそのまま効き始める形になっている。

**本家との差異（モデル差異として記録）。** 本家ではキャラクターの正本はアプリ設定（CharacterSettings）であり、.ymmp の Characters はアイテムから参照されているキャラクターの集合として保存時に再構築され、読み込み時にはプロジェクト側キャラクターが設定側へ取り込まれる（Project.Migrate / ImportCharacter）。Mac 版は MAC-0015 以来、キャラクターをプロジェクト保持・名前解決とするモデルで確定しており、本単位ではこのモデル差異を変更しない（編集シートはプロジェクト側の一覧を編集する）。また、追加後にセリフ欄を消さない現行挙動は本家と一致する（本家のクリアは ClearSerifTextCommand という明示コマンドのみ）。

**観測したまま別単位へ残す欠落。** 本家の VoiceItem 編集画面にあるが Mac の記述子に無い項目: Pronounce（プラグイン型で生保持のみ）、AdditionalTime、VoiceFadeIn / VoiceFadeOut、EchoIsEnabled / EchoInterval / EchoAttenuation（エコーの記述子欠落は FE-R15-006 でも別途記録済み）、PlaybackRateAudioProcessingMode、IsWaveformEnabled。いずれもモデルには保持があるが編集 UI が無い。本単位の範囲（セリフ・キャラクター・発音・辞書）を超えるため、追加は別単位とする。セリフ行の部分装飾（Decorations）の編集も未実装のままである。キャラクター編集の各操作は Undo 記録の対象外である（PR #126 の移行範囲に従い、本単位では記録経路へ触れていない。シートからの編集は requestPreviewRender(modelChanged:) の通知のみで、未保存判定には乗る）。

**検証。** Mac（同期先 ~/ymm4-work/fe-unit6-serif/YMM4Mac）で Apps/DebugApp の swift build 成功。Core テストは対象を絞って実行し全合格（72件・失敗0）: PropertyMetadataTests 23件（新規: 発音記述子の往復と並び順）、CharacterReferenceTests 8件（新規: cloned の全フィールド保持と独立性）、UserDictionaryStoreTests 9件（新規: CRUD 往復）、UserDictionaryTests 15件、EffectPropertyMetadataTests 17件（フィルタの部分一致で含む）。全スイート・AudioDriftTests は実行していない。

**手動検証チェックリスト（未実施、本人の目視確認待ち）。** (1) セリフ行のキャラクター設定ボタンとツールメニュー「キャラクター編集…」の両方から編集シートが開く。(2) シートでキャラクターを追加すると、セリフ行のピッカーとインスペクタのキャラクター選択へ即座に現れる。(3) キャラクターを改名し、参照中アイテムのあるプロジェクトを保存・再読込すると、新しい名前で解決される。(4) 参照のあるキャラクターの削除で確認が出て、確定後はアイテムが名前だけを保持し、保存・再読込しても名前が残る。(5) 複製で基本項目と保持フィールドが引き継がれる。(6) VoiceItem / TachieItem / TachieFaceItem のインスペクタ先頭でキャラクターを変更でき、プレビューへ反映される。(7) 発音欄の編集が保存・再読込で保持される。(8) 辞書エディタウィンドウの目視確認: 3リストの切替・追加・編集・削除、アプリ再起動後の復元、保存失敗時の表示と再試行。(9) セリフ行で選択中のキャラクターをシートで削除すると、ピッカーの選択が先頭へ倒れる。

## 以降の記載テンプレート

#### MAC-XXXX — [機能名]（IMPLEMENTED / VERIFIED / UNKNOWN）

**何を実装したか。** 本家の利用者がどんな操作をしたときにどう動くのか、対象要件ID。

**どこを変更したか。** repository、branch、開始コミットと終了コミットのSHA、PR、ファイルパス、クラス／関数／行番号（可能な範囲）。

**どう実装したか。** 入力→中間処理→出力の順序を文章で説明する。使用するアルゴリズム、重要な条件分岐、状態遷移、エラー処理、リトライ、UI反映を具体的に記す。

**なぜその実装なのか。** 採用したApple標準API／OSS、他候補との比較と理由、性能・依存関係への影響。

**本家との差分。** 本家の該当アセンブリ・クラス・メソッドと処理の違い。内部変更とユーザーから見える差を分ける。後者が要件逸脱なら申請IDと明示承認の証拠を示す。

**メモリ・並行性。** 入出力の型・単位、データの所有者、生成／解放、GPU完了と資源解放、スレッド／キャンセル、キャッシュ制限。

**検証。** 実際に走らせたビルド・テストコマンド、環境、期待値・結果、ログ、失敗ケース、未検証項目。

**次の担当へ。** 残課題・修正候補・次に開くべきファイル／シンボル。

※文書の更新先は AGENTS.md の「文書の更新規則（イベント別）」に従う。すべての変更がすべての文書を更新するのではなく、変更された事実の正本を確実に更新すること。

#### HT104 — HalfTone の期待値を修正済み DXBC インタプリタで再検証（Issue #104。IMPLEMENTED）

**問題。** HalfTone の画素ハーネス期待値は、DXBC インタプリタの分岐修飾子の不具合（`if X ; z` の修飾子落ちで分岐が反転する）が修正される前に作られていた。HalfTone シェーダには `; z` 分岐が1箇所あり（`if cb[0][1].w ; z`、cb の mode が 0 = 三角のときに分岐する）、モードによっては期待値が誤っていた可能性がある。また三角モードの候補集合は逆アセンブルのレジスタ追跡で抽出されたもので、画素単位の検証は粗い性質確認のみだった（旧 gpu45-harness の M ケース）。

**再検証の方法。** 修正済みインタプリタ（noise7-scratch の dxbc_interp.py）に sample 命令（双線形・透明境界。本移植の borderSampler と同じ規則）と v[2]（断片自身の UV）の駆動を追加し、halftone.cso の逆アセンブルを直接実行して期待値を再生成した。ケースは旧ハーネスの K（菱形）・L（矩形）・M（三角）と同一条件（Blur 0・不透明度 100・無変形のため、単色化は白正方形入力に対して恒等、合成は「原画の下へ」が効く）。生成器は作業領域 halftone104-scratch/halftone_ref.py、期待値は Harnesses/halftone104-harness/refs/ に凍結した。実描画は同ハーネスで MetalHalfToneShadowProcessor を駆動し、全画素を比較した（compare.py）。

**結果（モード別）。**
- 菱形（mode 2）: 全 1,764 画素がバイト完全一致。矩形（mode 1）: 全 900 画素がバイト完全一致。分岐修飾子の修正はこの2モードの期待値を変えず、旧ハーネスの解析値も正しかったことが確定した。
- 三角（mode 0）: 当初 60 画素で最大差 255。切り分けの結果、移植側の候補集合が誤っていた。インタプリタのサンプル座標を実測して格子を確定した: 行の高さは 0.866・Distance、中心は (j+0.5)・0.866・Distance、奇数行は中心が Distance の整数倍・偶数行は半セルずれ、候補は自列3点＋上下行2点ずつの7点、自列の中心インデックスは奇数行が floor(x/d+0.5)・偶数行が floor(x/d)。旧実装は基点を floor＋パリティ調整で組み立てており、格子点でない候補（行境界上の点）が混ざっていた。
- 三角の修正後: ケース1（Distance 6.1）で最大差 2（20 画素、全て部分被覆の縁画素で一様に +2）、ケース2（Distance 4.3）で最大差 1（許容超え 0）。残差は GPU サンプラの補間精度に起因する級と判断し、許容差 2 を compare.py に記録した（NOISEFIX の Voronoi 1 ulp 残差と同種の扱い）。

**変更。** MetalGraphicsDevices.swift の ymm4HalfToneFragment の三角分岐を実測した格子で組み直し、コメントに根拠を記録した。検証用に Harnesses/halftone104-harness を新設した。

**第17ラウンドレビュー（2026-11-19）と処分。** 三角格子の数学的整合性と修正方針は採用支持、Issue #104 は解消認定（到達点は「対象4ケースで菱形・矩形は完全一致、三角は最大差2以内」であって無条件の完全一致ではない）。P2 が2件あり、いずれも非ブロッキングとして処分した。
- R17-01: 比較器の許容条件が観測より広い（全画素が 1〜2 ずれても通る）。処分: compare.py に差分画素数の上限を追加した（菱形・矩形は 0、三角は実測 20 画素に余裕を持たせて 128）。
- R17-02: 期待値生成器が GitHub で再現できない。処分として本節に生成経路と候補座標の照合記録を残す。生成器は作業領域 halftone104-scratch/halftone_ref.py（修正済みインタプリタ noise7-scratch/dxbc_interp.py に sample 命令と v[2] 駆動を追加したもの）で、入力は gpu45-scratch/halftone_dis.txt（halftone.cso の逆アセンブル）。候補座標の実測照合（Distance 6.1、gate を広げて全候補をサンプルさせた取得。形式: 点 → 候補中心の集合）: (10.5, 6.5) → {(15.25, 13.207), (9.15, 13.207), (18.3, 7.924), (12.2, 7.924), (6.1, 7.924), (15.25, 2.641), (9.15, 2.641)}。(10.5, 12.0) → {(12.2, 18.49), (6.1, 18.49), (15.25, 13.207), (9.15, 13.207), (3.05, 13.207), (12.2, 7.924), (6.1, 7.924)}。(20.0, 17.0) → {(21.35, 23.772), (15.25, 23.772), (24.4, 18.49), (18.3, 18.49), (12.2, 18.49), (21.35, 13.207), (15.25, 13.207)}。(4.0, 3.0) → {(6.1, 7.924), (0.0, 7.924), (9.15, 2.641), (3.05, 2.641), (-3.05, 2.641), (6.1, -2.641), (0.0, -2.641)}。(30.0, 28.0) → {(33.55, 34.338), (27.45, 34.338), (36.6, 29.055), (30.5, 29.055), (24.4, 29.055), (33.55, 23.772), (27.45, 23.772)}。判別照合: (15.86, 6.5)（x/d = 2.6、奇数行）の自列は {12.2, 18.3, 24.4} で floor(x/d+0.5) = 3 が中心。(15.86, 12.0)（偶数行）の自列は {9.15, 15.25, 21.35} で floor(x/d) = 2 が中心。負座標: (-2.44, 12.0) の自列は {-9.15, -3.05, 3.05}、(-3.66, 6.5) の自列は {-12.2, -6.1, 0.0}。いずれも本節の格子規則と一致する。
- 残差の原因について: 検証済みなのは「対象ケースで最大 2/255 の残差があり、許容差 2 で全画素比較が通過した」ことまで。残差が GPU サンプラの補間精度に由来するか、演算順序や丸め等の別の数値演算差に由来するかは未解決として区別する（当初記録の「サンプラ補間精度級と判断」は断定として強すぎたため、本追記で改める）。

#### FXMETA-COMP — 複合プロパティ18件の記述子対象化（IMPLEMENTED / VERIFIED）

**何を実装したか。** FXMETA で対象外として記録した複合プロパティ18件（ブラシ7件: Shadow / InnerShadow / FillBackground / FillForeground / FrameLine の Brush、Outline の StrokeBrush、DisplacementMap の Brush。Transform 3件: DisplacementMap / NoiseColorShift / NoiseDisplacementMap。NoiseParameter 3件: Noise / NoiseColorShift / NoiseDisplacementMap。Mosaic の MosaicParameter、Mask の ShapeParameter、Gradient の Stops、MeshDeformation の Points、MotionTracking の Path）を、記述子体系へ複合種別を1層だけ足して対象化した（設計は第7ラウンドで決定済み）。固有パラメータ記述子は 509 件 → 527 件。

**どこを変更したか。** `Sources/YMM4Core/Editing/PropertyMetadata.swift`（`PropertyKind` へ `.object` / `.collection` を追加。関連値は持たせず Equatable を維持し、子・要素へのアクセスは `PropertyAccess` 側の新ケース `.object(children:)` / `.collection(count:elements:insert:remove:)` が持つ。`PropertyDescriptor` へ橋渡し用の computed property / メソッド（`children` / `collectionCount` / `collectionElements(at:)` / `insertCollectionElement()` / `removeCollectionElement(at:)`）とファクトリ `.object(...)` / `.collection(...)` を追加）。新規 `Sources/YMM4Core/Editing/EffectPropertyMetadataComposite.swift`（複合記述子の構築一式）。既存ビルダー4ファイル（`EffectPropertyMetadataGPUShadowMask.swift` / `EffectPropertyMetadataGPUTransform.swift` / `EffectPropertyMetadataGPUColor.swift` / `EffectPropertyMetadataDraw.swift`）へ、各定義の保存キー順の位置に複合記述子を差し込んだ。`EffectPropertyMetadata.swift` 冒頭の対象外コメントを実態へ更新。UI は `Apps/DebugApp/Sources/YMM4MacDebug/PropertyInspectorView.swift`（`PropertyRowView` の access 分岐へ `.object` / `.collection` を追加）。テストは `Tests/YMM4CoreTests/Editing/EffectPropertyMetadataTests.swift`（期待 ID 列へ18キーを保存キー順で追加、対象外一覧を RepeatOpacity.IsCentering のみへ更新、新規テスト8件を追加）。

**どう実装したか。**
- 型付きブラシ（`Brush` クラス。Shadow / FillBackground / FillForeground / FrameLine）: 子は現在のパラメータ型のフィールドから保存キー順に生成する。対象は10種のパラメータ型（solidColor / linearGradient / radialGradient / checkered / dot / stripe / gridLine / bitmap / noise / gradientMesh）。Animation は `.animation`、色は `.color`、列挙（CoordinateMode / ExtendMode / NoiseType）は `.enumeration`、グラデーションの Stops は `.collection`、グラデーションメッシュの Points は `.collection`、入れ子の `BrushDrawingTransform` は `.object` で再帰（保存形式ではパラメータ本体へインラインに並ぶが、モデル上の入れ子構造どおりに表す）。bitmap の ContentOffset は FXMETA の TextureEffect と同じく秒の数値で読み書きする。noise パラメータ内の生保持 NoiseParameter は、非 nil のときだけ生保持の汎用子記述子で対象化する。`.preserved` のパラメータ型は子なし（空の object)。パラメータ型そのものの切替 UI は範囲外（本家は型選択の専用 UI を持つ）。ブラシが未設定（nil）の間は子を持たない。
- 生保持（`PreservedObject`）の複合（上記ブラシ形の InnerShadow Brush / Outline StrokeBrush / DisplacementMap Brush、Transform 3件、NoiseParameter 3件、Mask の ShapeParameter）: 子は保存 JSON のフィールドから汎用的に生成する。フィールドの置き場は形状で決める — 値が `{Type, Parameter}` 形（本家 `Plugin.Brush.Brush` の保存形式。デコンパイル済み本家で InnerShadow / Outline / DisplacementMap のブラシが `Plugin.Brush.Brush` 型であることを確認）なら Parameter オブジェクトの中、それ以外（多態パラメータが $type 付きで直接保存される形。DisplacementMap の Transform は `DisplacementMapTransformBase` の直接保存、NoiseParameter は実プロジェクト2件で $type 直下にフィールドを持つことを実測）ならオブジェクト自身のフィールド。種別の判定: 数値→`.number`、真偽→`.boolean`、文字列→`.text`（ただし `#AARRGGBB` 形式は `.color`)、`Values` キーを持つオブジェクト→`.animation`（本家 Animation の保存形式。読み書きは定義層の既存コーデック `decodeLegacyAnimation` / `encodeAnimation` を使う。本家が範囲 (int.MinValue, int.MaxValue) で読む経路と同じ）、それ以外のオブジェクト→`.object` で再帰（深さ上限3)。`$type` は型判別子であり子にしない。配列と null は汎用の子で表現できないため子にしない。読み書きは都度ルート JSON からキー列を辿るフィールド置換で行い、触っていないフィールド（未知キー含む）はそのまま残る。表示名はフィールド名そのまま。
- MosaicParameter（型付き）: sized は Size（`.animation`）のみを子に持つ（本家の組み込み6形状とも持つプロパティは Size だけ、という既存モデル側の実測どおり）。それ以外の $type は生保持として汎用子記述子を付ける。
- コレクション: Gradient の Stops（要素は Offset `.number` 0〜1 と Color `.color`、Gradient 効果とグラデーションブラシで構築を共用）、MeshDeformation の Points（要素は X / Y `.animation` と IsSelected `.boolean`)、GradientMesh の Points（要素は GradientMeshPoint の全フィールド）、MotionTracking の Rects（要素は Top / Bottom / Left / Right `.number` と IsTracking `.boolean`)。追加は各モデルの既定値の要素を末尾へ足し、削除は位置指定。
- MotionTracking の Path は `.object` として Target（`.enumeration`。選択肢はメンバ名 Background / CurrentItem)、Rects（`.collection`)、AlgorithmName（`.text`）を保存キー順に持つ。`IsEditing` は保存対象外の実行時状態のため子にしない。
- UI: object は表示名の見出し＋子行をインデントして `PropertyRowView` を再帰表示する。collection は要素ごとに子行をまとめ、追加・削除ボタンを付け、操作後は `onEdited` を呼ぶ（追加・削除では行ローカルの世代カウンタも進め、再描画を二重に促す）。複合の表示名はプロパティ名そのまま（本家 Texts に根拠のある文言だけを使う従来方針。複合プロパティ自体に根拠のある表示名は取れなかった）。

**本家との差分。** (1) 本家は複合プロパティごとに専用エディタ（ブラシエディタ、グラデーションエディタ等）を持つが、こちらは汎用の入れ子行で全複合を一様に扱う。専用エディタ固有の操作（パラメータ型の切替、グラデーションの視覚編集、メッシュ点のキャンバス編集、トラッキング矩形の映像上編集）は対象外。(2) `BrushDrawingTransform` は保存形式ではインラインだが、こちらでは `.object` の入れ子として表示する（保存形式は変えない）。(3) 生保持の Animation フィールドを編集すると、そのフィールドは既存コーデックの標準形（Values / Span / AnimationType / Bezier の4キー）で書き戻される。触っていないフィールドは保持されるが、編集した Animation フィールド内の未知キーは保持されない（型付きプロパティの Animation と同じ扱い）。

**検証。** Mac 実機（検証コピー ~/ymm4-work/fxmeta-r2/YMM4Mac): ルートパッケージ `swift build` 成功、DebugApp `swift build` 成功。対象テスト `swift test --filter "EffectPropertyMetadataTests|PropertyMetadataTests"` は 30 件全合格（EffectPropertyMetadataTests 13件 = 従来5件 + 新規8件、PropertyMetadataTests 17件）。新規8件の内訳: 対象18件全てに複合記述子が付くこと、型付きブラシ単色の色変更（未知入れ子キーの保持を含む）、型付きブラシ線形グラデーションの Stops 追加・削除と Offset 変更、型付き MosaicParameter の Size 変更（未知キーの保持を含む）、Gradient の Stops 往復、Mesh Points の X 変更・選択切替（未知キーの保持を含む）、生保持 NoiseParameter の数値・Animation 書き換え（$type と未知フィールドの保持を含む）、生保持ブラシ形の Parameter 内 Color 書き換え。いずれも `VideoEffectRegistry.encode` の往復で保存 JSON を確認した。既存テストの期待 ID 列は18キーを保存キー順へ追加したものへ更新し、従来の509記述子の id・並び・グループ名は変更していない。Linux では YMM4CoreTests ターゲットのビルド成功までを確認（`swift test` 全体の実行は、YMM4GPUTests が macOS 限定の型を参照して Linux ではビルドできない既存事情のため不可。この失敗は変更前の main 057d0db でも同一に再現することを作業ツリー外の検証コピーで確認済みで、本変更とは無関係）。AudioDriftTests は対象外の変更のため未実行。

**未解決。** (1) パラメータ型の切替 UI（ブラシの型、モザイク形状、生保持の $type 切替）は未実装。本家の専用エディタ相当の操作であり、必要になれば別単位で扱う。(2) 生保持の入れ子で深さ4以上のオブジェクトと、配列・null のフィールドは編集対象にできない（値は保持される）。(3) 複合の子記述子の表示名はフィールド名そのままで、本家の専用エディタが持つ文言との一致は未確認（根拠が取れない文言は作らない方針のため）。

**追記（フルスイート確認の結果）。** Mac 実機でフルスイート（AudioDrift 除外）を1回実行した際は 587 件中 1 件の失敗があったが、その実行は出力を絞っていたため失敗したテストを特定できなかった。その後の切り分け再実行では、YMM4GPUTests は 42 件全合格、YMM4CoreTests は AudioResamplerQualityTests と AudioDrift を除く 544 件が全合格だった。残る AudioResamplerQualityTests（9件、dB 実測の主張を持つリサンプラ品質スイート）は、本変更とコードを共有しない（差分は Editing と DebugApp のインスペクタのみ）うえ、現在の Mac 環境では単独実行でも極端に時間がかかり（`testFormalStopbandSweep` のカーネル計算で長時間 CPU を占有する。`sample` で確認済み）、本記録の時点では完走を確認できていない。最初の1件の失敗は、このスイートか、並行実行時の負荷に起因する不安定さのどちらかと整合するが、断定はしない。
#### LIMITS — #56 / #61 / InOutCrash の現状確定（2026-11-19、締切時点の処分記録）

**#56（最重フレームの合成時間）。** 未完のまま開いた状態を維持する。性能監査（2026-11-17）の「最重フレーム合成 18.1〜18.8ms」は R6-02 以前の測定であり、その後の実測は次のとおり: プレビューは背景ワーカー化（R6-02）により表示が合成に阻害されなくなり、最密窓での持続は 26.5 fps（Phase E、素材不在条件）。ただし完了条件である「最重クラスのフレームでも合成が 16.7ms 予算内」は未達のままである。主因の同期実行（完了待ち）は描画失敗の検出（MAC-0021）の前提を兼ねており、解消には失敗検出の再設計と提出のフレーム単位への集約が一体で必要になるため、設計単位として残す。

**#61（コンプレッサ Ratio≠1 の波形等価性）。** Issue 自身の定めどおり、本家を動かせる環境（Golden Master）が無い間は「未検証」のまま閉じない。係数法則（EnvelopeFollower）は再構成であり、本家の NWaves が逆コンパイル集合に無いことが制約の本体である。Ratio=1 の一致と BS.1770 側の検証済みという現状に変更はない。

**InOutCrash（未実装の維持）。** 本家の CrashMeshBuilder は .NET のオブジェクト同一性ハッシュ（GetHashCode）を種にメッシュを破砕するため、本家の出力自体が実行ごとに非決定的であり、画素単位の一致は原理的に検証できない。加えて移植側の GPU 層には汎用メッシュ描画経路が無い（全面四角形とコンピュートのみ）。実装にはメッシュ描画基盤が前提であり、MeshDeformation の描画と同根の土台仕事として切り出す。現行の素通し（未実装の明示）を維持する。
#### LIPSYNC — 口パクの振幅評価と口形の決定（IMPLEMENTED、Mac 検証済み）

**本家の規則（逆コンパイルで確認）。** 口パクは2つの独立した経路からなる。(1) 音量: LipSyncEnvelope が声の音声（48kHz へリサンプル、音量・エコー・エフェクトなし）からフレームごとの RMS 包絡を計算する。窓の長さは Hz × smooth / fps × 2（インターリーブ済みサンプル数、上限 16,777,216）、窓の中心がフレーム位置に来るよう配置され、範囲外は 0 として数える（分母は常に窓長）。smooth はキャラクターの MouseSmooth（既定 4）。計算が無い場合の音量は、声の範囲内なら 0、範囲外・声なしなら −1。(2) 口形: 音量からは決まらず、声の LipSyncFrames（lab 解析由来の口形時系列。Pronounce 側が優先）から、その時刻以前の最後の要素の口形を取る。時系列が無ければ Silent。

**何を実装したか。** (1) Core: `LipSyncEnvelopeCalculator`（Audio/LipSyncEnvelope.swift）。供給元（PCMProvider）のレートで本家と同じ窓規則の RMS 包絡を同期計算する。本家は 48kHz へリサンプルしてから計算するが、窓は時刻で定義されるためレートは粒度にだけ影響する。(2) Core: `MouthShapeValue` / `LipSyncFrameValue`（Items/LipSyncFrame.swift）。生 JSON のまま保持されている LipSyncFrames を評価時に復号する（Shape は名前文字列と数値の両形式を受ける。保存形式は変えない）。`VoiceItem.evaluatedLipSyncFrames`（Pronounce 優先、本家 GetLipSyncFrames と同じ）と `lipSyncShape(atFrame:fps:)`。(3) GPU: MetalTachieSource が、注入された包絡の供給から音量を取り、口形を評価結果で渡すようになった。包絡は声の同一性・長さ・fps・平滑化をキーにキャッシュする（本家の署名による再計算条件の簡約形。声の内容差し替えは Source の作り直しで解消する）。供給は `makeLipSyncEnvelopeProvider(baseDirectory:)`（声の PCM 解決＋計算）をプレビュー（PreviewBox）と書き出し（MetalExportVideoProvider）の両方へ配線し、MetalSourceProvider の子供給元へも伝播する。

**残りの差分。** 本家は包絡を非同期に計算し、描画側は待ち時間つきで読み取る。こちらは同期計算＋キャッシュであり、長い声では初回表示で計算時間が出る。本家の対象音声はエフェクト適用前の声そのもの（EffectedItemSource で音量・エコー・エフェクトを無効化）であり、こちらの供給も声ファイルの素の PCM である点は一致する。立ち絵の描画器そのものはプラグイン境界（既定では描画器なし）のため、口パクが画面に出るかは描画器の有無に依存する（従来どおり）。

**検証。** 新規テスト LipSyncTests 7件が Mac で合格（無音、一定振幅での窓端の半減と中央での一致、インパルスの窓内外、引数不正の nil、口形時系列の評価、数値形式の Shape、時系列なしの silent）。立ち絵系の既存テスト 9件も合格。ルートと DebugApp のビルド成功（Mac）。

#### LIPSYNC-R20 — 第20ラウンド指摘への処分（PR #116 へ追加）

- **R20-116-01（P1、包絡の入力音声が本家と異なる）**: 本家 TachieSource は包絡の入力として、声アイテムのエフェクトチェーンを通した音声（再生速度・ContentOffset を反映し、音量制御・エコー・音声エフェクトは除く）を 48kHz で生成する。従来は生ファイルの PCM をそのまま計算していたため、速度やオフセットがあると包絡の時間位置がずれていた。ホスト側の供給を AudioSourceFactory のチェーン（オプションで音量制御・エコー・エフェクトを無効化、48kHz）へ切り替え、計算器の入力を AudioStream 一般へ広げた。
- **R20-116-02（P1、口形評価が速度・オフセットを無視）**: 本家 GetMouthShape の式どおりに変更した。定数速度では (アイテム内時刻 + ContentOffset) × 速度 / 100、可変速度では PlaybackRateMap の積分を使い、結果が負ならアイテム長の時刻から差し引く（負速度の折り返し）。
- **R20-116-03（P2、フレーム時刻の丸め）**: tick 換算を本家 FrameTime.FrameToTime と同じ AwayFromZero の丸め（既存の AudioStream.frameToTicks）へ統一した。60fps のフレーム1が 166,667 tick になることを試験で固定した。
- **R20-116-04（P2、未整列の時系列）**: 途中で打ち切らず、条件を満たす最後の要素を選ぶ本家 LastOrDefault の規則へ変更した。
- **R20-116-05（P2、描画器が無くても全音声を計算）**: 立ち絵描画器が無い場合は包絡計算を行わないようにした（口形の評価は音声計算を伴わないため従来どおり）。
- **R20-116-06（P2、平滑度の溢れ）**: 窓長の計算に溢れ検査を入れ、本家の checked 演算の失敗と同じく nil へ倒すようにした。

検証: LipSync 試験 11 件（速度・オフセット・未整列・60fps 境界・溢れを追加）と立ち絵系が Mac で全合格。ルートのビルド成功。
#### KEYFRAME-UI — キーフレーム編集 UI と値列連動の是正（IMPLEMENTED、Mac 検証済み）

**問題（実コードで確認した不具合）。** タイムラインの右クリックメニューからのキーフレーム追加・削除・全削除が、位置だけを差し替える `BaseItem.setKeyFrames` を使っていた。`Animation` 側には値列を連動させる `insertKeyFrame` / `removeKeyFrame`（追加位置での現在値を挿入し曲線を保つ）が実装・試験済みだったが、アイテム層から呼ばれておらず、追加すると値列が不足して末尾が既定値で補われ（曲線が変わる）、削除すると値がずれる状態だった。全削除も同様。また、インスペクタのアニメーション行は先頭値しか編集できず、キーフレーム区間ごとの値編集は未対応と明記されていた。

**何を実装したか。** (1) モデル層: `BaseItem` に値列連動つきの `insertKeyFrame(at:)` / `removeKeyFrame(at:)` / `removeAllKeyFrames()` / `moveKeyFrame(from:to:)` を追加し、全アニメーションへ連動させてからアイテムの集合を差し替える形にした。`Animation` には `removeAllKeyFrames()`（対応型は値を開始値と終了値へ畳む）、`moveKeyFrame(from:to:)`（隣を越えない範囲へ丸める。値はインデックス対応のため動かさない）、`segmentIndex(atFrame:)`（再生ヘッドの属する区間）、`setValue(_:atSegment:)`（区間の開始値の書き換え）を追加した。(2) 記述子層: `PropertyAccess.animation` に区間値の書き込み（setValueAtSegment）を追加し、`PropertyDescriptor.setAnimationValue(_:atSegment:)` を公開した。(3) アプリ層: 右クリックメニューの追加・削除・全削除を連動つき操作へ差し替え。タイムライン上のキーフレームマーカー（三角形）に横ドラッグを追加（離した時点で確定。ドラッグ中の追従表示はしない）。インスペクタのアニメーション行は、キーフレーム対応型でキーフレームがある場合に再生ヘッドの属する区間の開始値を表示・編集するよう変更し、キャプションで編集中の区間を明示した。

**本家との差分。** 本家の AnimationSlider はスライダ上のキーフレームマーカーを直接操作する形だが、こちらではタイムライン上のマーカーのドラッグ＋インスペクタでの区間値編集という構成で同等の編集を可能にした。ドラッグ中のライブ追従は無い（確定はドラッグ終了時）。エフェクト定義内のアニメーションはアイテムのキーフレーム集合を編集セッションへ注入して使うため、本単位の対象はアイテム自身のアニメーションである（定義側の連動は従来どおり編集セッション側の注入に依存する）。

**検証。** 新規テスト ItemKeyFrameEditingTests 7件（追加での曲線保存（評価の演算順差 1 ulp は精度つきで比較）、重複・範囲外の拒否、削除での値列復元、全削除での畳み込み、移動の丸めと値の不変、区間の特定と区間値の書き換え、非対応型での値の不変）が Mac で合格。アニメーション系の既存テストと併せて 63 件全合格。ルートパッケージと DebugApp のビルド成功（Mac）。UI の目視確認は未実施。

#### KEYFRAME-R19 — 第19ラウンド指摘への処分（PR #114 へ追加）

- **K19-01（P1、区間変更時に入力欄が追従しない）**: AnimationRowView の数値入力欄へ、編集対象区間の変化に追従する同期を追加した。フォーカス保持中（入力中）は未確定の文字列を破棄しない。あわせて、値列が短い場合の表示値も評価時の代用規則（末尾の値）に揃えた。
- **K19-02（P1、非線形イージングで追加により曲線が変わる）**: 本家の実コードで確認した。本家 `Animation` のキーフレーム変更ハンドラ（YukkuriMovieMaker.Commons/Animation.cs の KeyFrames_KeyFramesChanging）は、追加位置の現在値を `GetValue` で評価して値列へ挿入する規則であり、区間ごとのイージング再評価で曲線が変わるのは本家でも同じ挙動である。したがって実装は変更せず、本家の規則どおりであることをテストで固定した（二次 Ease In、0→100/20フレームへ10で追加すると、フレーム15 は 56.25 → 43.75 になる）。
- **K19-03（P2、不足値列の補填）**: `setValue` の補填を既定値から評価時の代用規則（末尾の有効値）へ変更し、編集対象でない位置の意味が変わらないようにした。区間の範囲外のインデックスは受け付けないことも追加した。
- レビュー (b) の境界（下限が上限を超える不整合状態）: `moveKeyFrame` に防御を追加した。なお位置列の生成側（KeyFrames の初期化）が整列と重複除去を行うため、通常の生成経路では到達しない。

検証: アニメーション系 65 件（新規2件を含む）が Mac で全合格。ルートと DebugApp のビルド成功。

#### KEYFRAME-R20 — 第20ラウンド指摘への処分（PR #114 へ追加）

- **R20-114-01（P1、フォーカス中の区間移動で別区間へ誤書き込み）**: 数値入力のセッションが編集対象区間を所有する形にした。フォーカスを得た時点で対象区間を固定し、確定はその区間へ行う。再生ヘッドが別区間へ移っても、未確定の入力が移動先の区間へ書き込まれることはない。スライダは従来どおり表示中の区間へ即時反映する。
- **R20-114-02（P1、不足値列の編集が最終端点まで変える）**: 本家の GetActiveValueCount（YukkuriMovieMaker.Commons/Animation.cs）を確認した。有効な値の個数はキーフレーム数 + 2 で、最終端点は独立した値を持つ。`setValue` は、値列がこの個数に満たない不完全なデータでは、まず評価上の有効値列（不足分は代用規則＝末尾の値で展開）へ展開してから対象位置だけを書き換えるようにした。既に揃っている正常なデータは展開しない。試験は配列だけでなく、編集前後の最終端点の評価値が変わらないことまで確認する形へ改めた。
- **R20-114-03（P2、BaseItem 側の移動範囲の防御）**: アイテム長より後方にキーフレームがある不整合データで下限が上限を超える場合、BaseItem.moveKeyFrame も移動を成立させないようにした（Animation 側の防御と対）。不整合データでの拒否を試験で固定した。

検証: アニメーション系 67 件が Mac で全合格。ルートと DebugApp のビルド成功。
#### TEXT60-DICT — ユーザー辞書の設定層（永続化・編集 UI・描画への接続）（IMPLEMENTED、Mac 検証済み）

**何を実装したか。** TEXT60 で未実装として残した辞書の設定層を実装した。(1) 永続化: `UserDictionaryStore`（YMM4Core/Text）が辞書の現在値と版数を保持し、Application Support 配下の `YMM4Mac/UserDictionary.json` へ本家の保存形式（キー名は本家のプロパティ名そのまま）で保存する。起動時に読み込み、ファイルが無い・壊れている場合は既定辞書で起動する（本家の初期化と同じく、欠けたリストは既定で補われる）。保存は一時ファイル経由の原子的な置き換え（本家の非原子的な保存でファイルが壊れる欠陥は持ち込まない）。保存先はアプリバンドルの外であり、配布時の「ユーザーデータはバンドル外」の決定に沿う。(2) 編集 UI: ツールメニューの「ユーザー辞書」を有効化し、専用ウィンドウ（アスタリスク／単語／発音の3リスト切替、エントリの有効・変換前・変換後・説明・正規表現・大文字小文字の編集、追加・削除）を実装した。編集は即座に保存され、WorkspaceState の依頼（userDictionaryChanged）経由でプレビューの再描画を依頼する。(3) 描画への接続: MetalTextRasterizer の辞書引数を設定層の現在値へ差し替え（明示指定はテスト用に残す）、MetalTextSources の両キャッシュキー（テキスト・字幕）へ辞書の版数を追加した。辞書を編集すると版数が上がり、次回描画でアスタリスク置換が新しい辞書で再ラスタライズされる。

**本家との差分。** 単語・発音リストは本家では読み変換（KanjiToYomi）の前後段へ適用されるが、Mac 版には読み変換経路も音声合成エンジンも無い（VoiceItem の音声は VoiceCache／カスタム音声ファイルのみ、Issue #51 の記録どおり）ため、現時点では適用先が無い。適用部品（TextPreprocessor の単語・発音適用）は TEXT60 で実装済みであり、読み変換経路ができた時点で接続する。編集 UI の配置（専用ウィンドウ）は本家のドッキングツールと異なるが、ドッキング基盤が無い現行構成での代替である。

**検証。** 新規テスト UserDictionaryStoreTests 4件（ファイル無しでの既定起動、更新→保存→再読込の往復と版数、壊れたファイルでの既定への倒れ、保存 JSON の本家キー名）が Mac で合格。既存の UserDictionaryTests 15件・ControlTagParserTests 36件も併せて合格（計55件）。ルートパッケージと DebugApp のビルド成功（Mac）。編集ウィンドウの目視確認は未実施（フロントエンド目視確認の際に併せて確認する）。

#### TEXT60-DICT-R18 — 第18ラウンド指摘への処分（PR #113 へ追加）

全件を実コードで照合し、全て実在すると確認して処分した。

- **R18-01（P1、Scene 修飾子の誤配置）**: 辞書ウィンドウの後に置いた `.defaultSize(1600,1000)`・`.windowResizability`・`.commands` が辞書の Window に結び付き、主ウィンドウ側の指定が消えていた。修飾子を WindowGroup 側へ移し、辞書ウィンドウには専用の `.defaultSize(860,520)` だけを残した。
- **R18-02（P1、サムネイルの旧画像保存）**: プレビューの識別子（セッションキー・世代・モデル版数）に辞書の変更が含まれず、辞書変更直後は旧画像の識別子が現在のものと一致して、そのままサムネイル保存できた。辞書変更をモデルの作り直しとして扱うよう変更した（ProjectView の `.userDictionaryChanged` でモデル要再構築を立て、保留中のサムネイル保存を取り消してから再描画を要求する）。版数が上がるため、旧画像の保存経路と旧描画結果の採用経路の両方が閉じる。
- **R18-03（P1、保存失敗の不可視化）**: `save()` が成否を返すようになり、失敗理由は `lastSaveError` に残って編集画面に表示され、再試行できる。メモリ上の辞書は失敗しても保たれる。置き換え（replaceItemAt）経路を通る2回目の保存と、保存失敗の表出をテストに追加した。
- **R18-04（P2、キー入力ごとの同期保存）**: 責務を分離した。`update` はメモリ上の辞書と版数を即時に差し替え、永続化だけを 0.3 秒の静穏期間で集約する（ストア側に集約）。編集画面を閉じるときとアプリ終了時に保留分を確定する。
- **R18-05（P2、書き出し中の辞書の一貫性）**: ストアに固定（pin）を追加し、書き出し（MP4・PngWav の両経路）は開始時点の辞書と版数を固定して全フレームで使う。固定中にプレビューが辞書を読む場合も固定された辞書になる（書き出し中は編集の反映が終了まで遅れる割り切り）。保存は固定の影響を受けず、常に最新の辞書を書く。

検証: UserDictionaryStoreTests は 7 件（置き換え経路・失敗の表出・固定の意味論を追加）になり、辞書・制御タグ系の 58 件が Mac で全合格。ルートと DebugApp のビルド成功。

#### TEXT60-DICT-R19 — 第19ラウンド指摘への処分（PR #113 へ追加）

- **R18-02 残存（サムネイル競合）**: モデル作り直しには 100ms の間引きがあり、版数が上がる前の窓では旧画像が再利用条件を満たし得た。`saveThumbnail` の再利用条件へ「モデル要再構築でないこと」を加え、作り直し保留中は保留経路（新しい描画の到着を待つ）へ倒すことで窓を閉じた。再生中に辞書を変えた場合も、停止後の作り直しまでは同じ条件で再利用されない。
- **D19-01（P1、固定の共有）**: ストア全体の固定（pin/unpin）を廃止した。代わりに `UserDictionaryStore.snapshot()` が辞書と版数の不変な組を返し、書き出し側は `MetalExportVideoProvider` の生成時（ジョブ開始時点）に取得して `MetalSourceProvider`（子供給元3箇所へも伝播）→ テキスト・字幕 Source へ渡す。プレビューは常に共有ストアの最新を読む。複数の書き出しジョブが重なっても各ジョブは自分の開始時点の辞書を使う。
- **D19-02（P1、保存の直列化）**: 保存の実行経路を保存専用の直列キュー1本へ統合した。集約保存・明示的な保存・確定保存はすべて同キュー上で実行時点の最新状態を書くため、古い書き込みが新しい状態を後から上書きしない。`onSaveResult` の読み書きもロックで保護した。

検証: UserDictionaryStoreTests は 8 件（取得した組が後の更新の影響を受けないこと、集約予約直後の確定でも最新が残ることを追加）。辞書・制御タグ系 59 件が Mac で全合格。ルートと DebugApp のビルド成功。ARCHITECTURE.md のデータフローへ辞書の所有と流れを追記した。

#### TEXT60-DICT-R20 — 第20ラウンド指摘 R20-113-01 への処分（PR #113 へ追加）

第19ラウンドの対処（即時保存分岐での再利用禁止）だけでは、非同期の保存経路が残っていた。保留中の保存は要求時点のモデル識別子へ固定されており、作り直し保留中に旧モデルの描画が完了すると、その完成通知が保留の条件と一致して旧画像を保存した。逆に作り直しが先に進むと保留自体が消去され、利用者の保存要求が無言で失われた。

処分として、保留中のサムネイル保存の意味を変えた。保留は形式とフレームだけを持ち、対象は「現在のモデルでそのフレームが完成した時点」へ結び直す。発火条件は、届いた画像が現在のモデルのものであること、作り直し保留中でないこと、フレームが一致することの3点に統一した。旧モデルの完成通知では発火せず待ち続け、モデルが作り直されても要求は消えずに新しいモデルへ引き継がれる。現在のモデルで別フレームが先に完成した場合の取消し（利用者が移動した扱い、R12-06）は維持した。辞書変更ハンドラとモデル作り直し処理にあった保留の消去も、この結び直しに合わせて撤去した（セッション自体を畳むリセット時の消去は従来どおり）。

検証: ルートと DebugApp のビルド成功。辞書・制御タグ系 59 件が Mac で全合格。サムネイル保存の発火条件はアプリ側の表示状態に依存するため単体テストの対象外であり、条件の3点をコード上で単一の判定に集約してある。
#### BSP — 平面分割（BSP）本体の実装（順序付け層は IMPLEMENTED、Mac 検証済み。有効化は断片画像生成の後）

**何を実装したか。** 本家 PlaneSplitBsp（YukkuriMovieMaker.Player.Video）の規則を、差し替え点 `PlaneSplitOrdering` の実体 `PlaneSplitBspOrdering` として実装した（Rendering/PlaneSplitBsp.swift）。BSP 木の構築（平面での分割、切断の記録、断片上限 256 で nil）、視点 (0,0,1000) からの奥→手前の巡回、順序付け要否の判定（共面の除外と画面範囲の重なり）、画面マスク多角形の算出（CreateScreenMaskPolygon の写し。断片画像生成が使う）までを含む。本家の内部算術は単精度のため、こちらも内部は Float で計算し Double の `Vector3` とは境界でのみ変換する。あわせて `PlaneSplitFragment` を本家の Fragment と同じ形（頂点列と切断列を持つ）へ拡張した。分割できない場合の多数決フォールバック（本家の Insert 内）も含めて写してある。

**有効化の前提（未了）。** `DrawSegmentBuilder` の既定は Null のままで、逐次描画フォールバックが現行の描画である。本体を既定に差すには、切断のある断片の画像生成（マスク多角形で切り取った画像を描く処理）が実行層に必要で、現行の TimelineSource は切断のある断片を描画から落とすため、本体だけを有効化すると交わる配置で画像の一部が欠ける（現行の逐次描画より悪化する）。したがって有効化は断片画像生成と同時に行う。Issue #58 の完了条件のうち「判定が分かれる配置で本家の規則どおりの描画順になること」は順序付け層では本実装とテストで満たし、描画への反映は断片画像生成が残件である。

**検証。** 新規テスト PlaneSplitBspTests 7件が Mac で合格: 交わる組での要否判定、共面・画面分離での不要判定、交わる2枚での分割（3断片、奥→平面→手前の順、切断が x=0 の線分、奥断片は z<=0・手前は z>=0）、交わらない2枚の奥→手前順序、退化した四隅での nil、マスク多角形の右半分への切取り。既存の DrawOrderingTests 15件も引き続き合格。

#### FXMETA-R21 — 第21ラウンド指摘への処分（PR #117 へ追加）

- **R21-117-01（P1、生保持アニメーションの編集で配列内の未知フィールドが消失）**: 生保持オブジェクト内の汎用アニメーションの書き戻しを、保存 JSON の既存内容を土台にした重ね合わせへ変更した。オブジェクト同士はキー単位で再帰し、配列同士は要素単位で重ねる（CodecSupport.mergePreservingUnknownFields）。Values の各要素で変更対象外のキーが保持され、アニメーション自体の未知キーも残る。試験は Values 要素内の未知キーとアニメーションの未知キーが編集後も残ることまで確認する形へ拡張した。
- **R21-117-02（P1、グラデーションメッシュの格子不整合）**: 格子寸法と点列を単一の操作として扱う形にした。GradientMeshBrushParameter.resizeGrid が既存の点を (行, 列) の位置で保持しながら寸法と点列を一体で組み替える（寸法は本家 UI の範囲 2〜50 へ丸める）。横・縦の個数の変更はこの経路を通し、点の追加は末尾へ1行、削除は対象要素を含む1行を取り除く操作とした。常に points.count == 横 × 縦 が保たれることを記述子経由の試験で固定した。
- **R21-117-03（QA、未特定の失敗と未検証の音声試験）**: 未確定のまま独立した QA 残件として維持する。なお FXMETA 実施時に Mac で継続していたリサンプラ品質試験の単独実行は、クラス名フィルタが0件に一致して終了していた（この Mac ではクラス名フィルタが一致しない場合がある）ため、実質的には未実行だった。方式名フィルタでの再実行を統合確認時に行う。

検証: 対象試験（EffectPropertyMetadataTests / PropertyMetadataTests）は Mac で再実行する。あわせて main（PR #115・#113・#114）を取り込んだ。

#### FXMETA-R22 — 第22ラウンド指摘への処分（PR #117 へ追加）

- **R22-117-01（P2、コレクション挿入/削除が無変更でも成功を報告する）**: `PropertyAccess.collection` の `insert` / `remove` クロージャの戻り値を `Bool` へ変更し、「状態が実際に変わったか」を返す契約にした（`PropertyDescriptor.collection` ファクトリと `insertCollectionElement` / `removeCollectionElement(at:)` も連動）。各ビルダの処分: グラデーションメッシュの Points は行追加が上限50行へ丸め込まれた場合と、最小2行での行削除・範囲外削除で false を返す。グラデーションの Stops、メッシュ変形の Points、モーショントラッキングの Rects は範囲外削除で false を返す（追加と通常の削除は true）。UI（`CollectionRowView`）は true の場合にだけ世代カウンタの増加と `onEdited` 通知を行う。試験はメッシュの最小行数での削除・最大行数での追加が false で状態不変であること、上限・下限までの通常操作が true であること、Stops とメッシュ変形 Points の範囲外削除が false であることを固定した。

#### FXMETA-R23 — 第23ラウンド指摘への処分（PR #117 へ追加）

- **R23-117-01（P2、不正な既存格子寸法で resizeGrid がオーバーフローする）**: `GradientMeshBrushParameter.decode` は JSON の HorizontalCount / VerticalCount をそのまま採用するため、読み込み済みの旧寸法には範囲の保証がない。従来の `resizeGrid` は `row * oldHorizontal + column` を無検査で計算しており、oldHorizontal=Int.max 等の壊れた保存ファイル由来の値で乗算・加算がオーバーフローして trap し得た（`indices.contains` の検査は添字計算の後だった）。処分: 旧添字を求める前に行・列が旧寸法の範囲内であることを確認し、添字計算を `multipliedReportingOverflow` / `addingReportingOverflow` へ置き換えた。オーバーフローする位置は既存点を引かず既定点で埋め、正常な新寸法へ復元する（例外・trap で落とさない）。decode 側の丸めは行わない（正当な範囲の寸法・点列のラウンドトリップ保持を優先し、安全化は resizeGrid 側に集約）。

検証: 新規テスト2件を BrushParameterTests へ追加し Mac で合格 — `testGradientMeshResizeGridWithCorruptOldDimensions`（horizontalCount=Int.max・verticalCount=2・点列2件で resizeGrid が trap せず 3×3 へ復元され、旧添字が安全に求まる行0は既存点を保持し、オーバーフローする行は既定点で埋まる）と `testGradientMeshResizeGridPreservesPointsByPosition`（2×2→3×2 で既存点が (行, 列) 位置どおり保持される回帰）。あわせて BrushParameterTests 全18件、EffectPropertyMetadataTests 16件、PropertyMetadataTests 17件が Mac で全合格（いずれも方式名フィルタで実行）。

#### FXMETA-R24 — 第24ラウンド指摘への処分（PR #117 へ追加）

- **R24-117-01（P2、行追加の入口で不正な旧縦寸法が trap / 意図しない行削減になる）**: GradientMesh の Points コレクション insert クロージャ（`EffectPropertyMetadataComposite.swift`）は `vertical: parameter.verticalCount + 1` を呼び出し側で計算していた。`GradientMeshBrushParameter.decode` は旧寸法を丸めず復元するため、verticalCount=Int.max では +1 自体が trap し、verticalCount=51 では resizeGrid 内で 52 が上限50へ丸められ、「行追加」のつもりが末尾行を失うのに verticalCount が変化するため true（変更あり）を返していた。処分: insert の入口で旧寸法を検証し、正常範囲（縦は追加後に上限へ収まる 2〜49行、横は 2〜50）のときだけ +1 して進め、範囲外（50行以上・負数・0・1・巨大値、および横の異常値）では状態を変えず false を返す。成功報告は「縦がちょうど +1 され横が不変」という事後条件で確認する。不正な格子の安全化は resizeGrid 側の責務（R23-117-01）に残し、insert は修復を兼ねない。削除経路（remove）は既存のガード（verticalCount > 2、`rowStart + horizontalCount <= points.count`）で実質的に安全なため変更していない。

検証: 新規テスト1件を EffectPropertyMetadataTests へ追加し Mac で合格 — `testGradientMeshInsertRejectsInvalidGridDimensions`（縦 Int.max で trap せず false・状態不変、縦51行で false・末尾行を失わない、縦1行で false、横51で縦が正常でも false・寸法不変、縦49行で true になり50行になる回帰）。縦50行での追加が false であることは既存の `testGradientMeshCollectionReportsNoChangeAtGridLimits` が覆うため流用した。あわせて EffectPropertyMetadataTests 全17件、BrushParameterTests 全18件、PropertyMetadataTests 全17件が Mac で全合格（いずれも方式名フィルタで実行）。
#### LIPSYNC-R21 — 第21ラウンド指摘への処分（PR #116 へ追加）

- **R21-116-01（P2、窓開始位置の溢れ）**: 窓長の検査に加え、開始位置の計算に使う (smooth + 1) と Int64 の乗算についても、ループ前に両端のフレームで溢れ検査を行い、溢れる場合は nil へ倒すようにした。窓長が偶然に範囲内へ収まる組合せ（Hz=1、fps と smooth が最大値）でも実行時トラップにならないことを試験で固定した。
- **R21-116-02（P2、包絡キャッシュの失効条件）**: キャッシュの照合に、包絡を決定する入力の署名を加えた。署名は声の指定、生成済み音声の有無と大きさ、再生速度（種別・値列・キーフレーム・間隔）、ContentOffset、ContentLength、ループ有無からなる。本家の再計算署名（音声ファイル・ContentOffset・ContentLength・更新世代）に相当する範囲を、同一オブジェクトへの編集でも検出できるようにした。

検証: LipSync 試験が Mac で全合格（溢れの組合せを追加）。ルートのビルド成功。あわせて main（PR #115・#113・#114）を取り込み、供給元の初期化引数（辞書スナップショットと包絡供給）の競合を両立する形で解消した。

#### LIPSYNC-R22 — 第22ラウンド指摘への処分（PR #116 へ追加）

- **R22-116-01（P2、包絡計算のオーバーフロー末尾）**: 従来の事前検査は `hz × (frame − centerOffset)` の乗算だけを見ており、`values.reserveCapacity(frameCount + 1)`、`windowStart + window`、`÷ fps × 2` のステップが無検査だった（反例: hz=1、fps=1、smooth=1、frameCount=Int.max は検査を通過して reserveCapacity でトラップ）。処分: (1) 窓の範囲 [開始, 終了) の導出を `windowRange(forFrame:)` へ集約し、減算・乗算・÷fps×2・窓長の加算の全ステップを溢れ検査つきにした。両端フレームの事前検査（R21-116-01）もこの導出へ一本化し、ループ内も同じ導出を通す。(2) 結果件数（frameCount + 1）に上限 16,777,216（窓長上限と同じ桁の安全弁）を設け、確保の前に nil へ倒すようにした。
- **R22-116-02（P2、包絡キャッシュ署名の欠落3件）**: 署名が欠いていた (1) 再生速度のベジェ（点列の全成分と2次フラグを文字列化）、(2) 音声処理モード（`playbackRateAudioProcessingMode` の honkeName。SOLA かリサンプリングかでチェーン出力が変わる）、(3) 音声キャッシュの内容、を追加した。(3) はフレームごとの全データハッシュを避け、VoiceItem に世代カウンタ `voiceCacheGeneration`（`voiceCache` の didSet で増加する単調カウンタ、保存対象外）を新設して署名へ含める方式とした。従来のバイト数比較は世代へ置き換えた。あわせて署名関数を `MetalTachieSource.envelopeSignature(of:)`（static）へ変え、試験から直接検証できるようにした。

検証: Mac で対象試験のみ実行（方式名フィルタ）。LipSyncTests の既存11件＋新規2件（異常フレーム数の nil、世代カウンタ）、EnvelopeSignatureTests 新規4件（署名の安定性、ベジェのみ・処理モードのみ・同サイズ差し替えでの署名変化）。結果は PR 本文に記録する。

#### FE-BATCH1 — フロントエンド監査 Round 1 のデータ保全系 P1 処分（アプリ層）

監査台帳は frontend-audit/FE-R1-FINDINGS.md、設計判断は FE-R2-DESIGN.md。主対象は Apps/DebugApp のアプリ層で、当初 Core は変更していない。Round 3 処分（FE-R3-118-02）では防御として Core の `PropertyDescriptor.setNumberValue` にも有限性ガードを追加した。保存ライフサイクル（FE-R1-001 / 028）とタイムライン再構築は別単位のため対象外。

- **FE-R1-003（P1、別アイテム削除で選択がずれる）**: `TimelineContextMenus.swift` のアイテム削除は、選択中アイテムと削除対象が異なる場合にインデックスを補正せず、削除位置より後ろの選択が別アイテムへ移っていた。処分: 削除前に選択中アイテムを同一性で捕捉する `captureSelectedItem()` と、削除後に同一性で引き直す `restoreSelection(of:)` を共用操作として追加し、削除経路で使う。対象が消えた場合は選択解除、選択が無かった場合は何もしない。
- **FE-R1-004（P1、レイヤー削除で選択がずれる）**: `deleteLayer(at:)` は範囲外のときだけ選択を解除し、範囲内に残った選択が別アイテムを指し得た。処分: 同じ捕捉／復元をレイヤー削除の前後に適用した。
- **FE-R1-005（P1、nan 等の入力で異常終了）**: ステータスバーの時刻入力 `parseTimeText` は `Double("nan")` / `Double("inf")` を受理し、`Int` 変換で trap していた。処分: 各要素と累積秒が有限でない場合は nil を返し、有限でもフレーム結果が `Int` の範囲を超える場合は変換前に nil を返す。フレーム数値欄（`commitStatusFrame`）は `Int(String)` が nan / inf / 桁あふれを全て nil にするため trap 経路が無いことを確認し、変更していない。
- **FE-R1-006（P1、プレビュー操作が先頭キーフレーム値を書き換える）**: プレビューのドラッグ移動・拡大・回転（`writeItemPosition` / `writeAnimationProperty`）は、キーフレーム付きアニメーションでも先頭値だけを書き換えていた。処分: 書き込みの振り分けを `writeAnimationValue` へ集約し、インスペクタ（`AnimationRowView.writeValue`、PR #114 の区間対応経路）と同一にした — 定数は定数化、キーフレーム対応型でキーフレームがある場合は再生ヘッドが属する区間（`animationContext` の相対フレームから `segmentIndex(atFrame:)`）の開始値、それ以外は先頭値。
- **FE-R1-007（P1、書き出し中に別の書き出しを開始できる）**: ツールバーの「動画出力」ボタンとダイアログの「出力」には実行中ガードが無く、`runExport` 自体も再入可能で、取消トークンの上書きと供給側の同時実行を招いた。処分: (1) `runExport` の冒頭で `exportState.isRunning` を確認し再入を弾く。(2) ツールバーの動画出力ボタンを実行中は無効化（下部タブのボタンは既に無効化済み）。(3) `ExportDialogView` に `isExportRunning` を渡し、`canExport` に含めた。
- **FE-R1-009（P1、アイテム追加が衝突解決を迂回）**: メニュー追加（`ProjectView.addItem`）、セリフ追加（`addVoiceItem`）、コンテキストメニュー追加（`addItemAtPlayhead`）、ファイルドロップ（`handleDroppedURLs`）の全経路が `addItems` 直呼びだった。処分: 全経路を Core の `tryAddItems`（FPS 注入・衝突解決・グループ ID 再発行・選択確定を持つ本家 TryAddItems 相当）へ寄せた。配置位置は引数で渡し、アイテム側への事前書き込みをやめた。ドロップは素材アイテムを全て組み立ててから一括で確定し、選択は `reflectCoreSelection` で引き直す。tryAddItems が false の場合は何も追加しない。
- **FE-R1-010（P1、右クリック移動が低水準 API 直呼び）**: 移動メニュー6項目が `moveItems`（差分加算のみ）を使っていた。処分: `moveMenuItem` を新設し、本家の通常移動である `moveSelectedAndGroupedItems`（選択＋グループ対象、衝突・範囲で移動量を縮小）へ切り替えた。対象アイテムが Core 選択に含まれない場合は、このファイルのグループ化／解除と同じ作法で対象単体を選択にしてから呼ぶ（本家でも右クリックしたアイテムが操作対象になる）。既に選択に含まれる場合は選択集合ごと移動する。
- **FE-R1-019（P1、数値欄の無編集確定で精度が失われる）**: `NumberRowView` と `AnimationRowView` は、フォーカス喪失時の確定で表示文字列（`formatNumber` は %.4g へ丸める）をそのまま書き戻していたため、触れて離れるだけで小数が丸め込まれていた。処分: 未編集とみなすテキスト（初期表示・フォーカス取得時点・スライダや区間追随などのプログラム側同期の直後）を保持し、確定時にテキストがそれと一致する場合は書き戻しも `onEdited` 通知もしない dirty 判定を両行へ入れた。確定で再整形した文字列は次の基準として同期する（Enter 確定後のフォーカス喪失で二重に丸めないため）。

- **FE-R3-118-01（P1、Round 3 指摘。FE-R1-005 の残存境界）**: `parseTimeText` の範囲判定は `frames <= Double(Int.max)` で行っていたが、`Double(Int.max)` は 2^63 へ丸められるため、フレーム結果がちょうど 2^63 になる入力（fps=1 で "9223372036854775808"）が判定をすり抜け、`Int(frames)` で trap した。処分: 浮動小数点の上限比較をやめ、変換を `Int(exactly:)` の1か所に統一し、失敗は nil を返す（有限性チェックは維持）。変換経路に他の Int 変換が残っていないことは grep で確認した。
- **FE-R3-118-02（P2、Round 3 指摘。非有限値が保存時に 0.0 へ化ける）**: 数値欄は `Double("nan")` / `Double("inf")` の解釈成功だけでモデルへ書き込んでおり、`PropertyMetadata.setNumberValue` にも有限性検査が無かったため、非有限値がモデルへ入り、保存時に `JSONValue` の `newtonsoftDoubleLiteral` が 0.0 リテラルへ置換していた。処分は2層: (1) UI 層 — `NumberRowView` と `AnimationRowView` の確定処理で、解釈した値が有限でない場合はモデルへ書き込まず `onEdited` も発火させず、表示を現在値へ戻す（FE-R1-019 の未編集判定と共存する形）。(2) Core 層（防御）— `PropertyDescriptor.setNumberValue` で非有限値を弾いて false を返す。`setNumberValue` の呼び出し元は UI の2か所（スライダ binding・数値欄の確定）とテストのみで、有限値の通常動作は変わらない。テスト: `PropertyMetadataTests.testSetNumberValueRejectsNonFiniteValues` を追加（nan / +infinity / -infinity で false を返し値が保持されること、有限値の書き込みが従来どおりであること）。

検証: アプリ層に実行可能ターゲットのテスト基盤は無い（テストターゲットは PreviewCore のみ）ため、003/004/005/019 の再現条件は本節を検証手順とする — 003: 3アイテムで末尾を選択し先頭を右クリック削除して選択が同じ個体を指すこと。004: 複数レイヤーにアイテムを置き、選択中アイテムより上のレイヤーを削除して選択が同じ個体を指すこと、選択中アイテムのレイヤー削除で選択が解除されること。005: ステータスバーの時刻欄へ "nan"、"inf"、"1:nan"、"99999999999999999999" を入力して異常終了せずシークも起きないこと。019: 小数第5位以下を持つ値（例: 0.123456789）を表示する数値欄へフォーカスして離れ、値が変わらないこと。Mac のビルド確認は当初統合 QA の全スイート実行中のため重ねず未実施と記録したが、実際には 2026-11-19 に親側で実施済みである（fe-batch1 ツリーを Mac の ~/ymm4-work/fe-batch1/YMM4Mac へ同期し、Apps/DebugApp の swift build 成功、全212ステップ）。Round 3 処分後の再検証（2026-11-19、Mac）: FE-R3-118-01 の機構を Swift スクリプトで確認した（2^63 の Double が旧ガードを通過すること、`Int(exactly:)` が nil を返すこと、fps=1・入力 "9223372036854775808" の経路再現で nil になること、正常値 90.0 / -30.0 の変換が不変であること。アプリ層にテストターゲットが無いため、回帰の固定はこの機構確認と「変換点が Int(exactly:) の1か所のみ」というコード形状による）。Apps/DebugApp の swift build 成功。`PropertyMetadataTests` の新規テスト `testSetNumberValueRejectsNonFiniteValues` と既存の setNumberValue 利用テスト（PropertyMetadataTests 3件・EffectPropertyMetadataTests 4件）を方式名フィルタで実行し全て合格（XCTest 側の Executed で判定）。

#### FE-TIMELINE — タイムライン再構築（フロントエンド監査 単位1。FE-R1-032 ほか）

監査台帳は frontend-audit/FE-R1-FINDINGS.md、設計判断は FE-R2-DESIGN.md（タイムライン節、受け入れ条件 R2-T01〜T03）。起点は PR #118 のブランチ（feat/fe-batch1 @ 99b3081）で、バッチ1のタイムライン修正（003/004/010）を含む。従来のタイムラインは「アイテムブロックにドラッグ移動・トリムが無く、背景の DragGesture がシークと ScrollView のパンを兼ねて競合し、選択は配列インデックス基準、目盛りは手動オフセットで追従してずれる」という状態だった。

**採用した構造。**
- スクロール: SwiftUI ScrollView を廃し、NSScrollView をスクロール位置の唯一の所有者にした（新設 `TimelineScrollView.swift`）。キャンバスは反転ドキュメントビューに SwiftUI コンテンツ（NSHostingView）と操作層を重ねる。目盛りは AppKit の `TimelineRulerView` がキャンバス側クリップビューの原点を描画時に直接読んで描く（独自オフセットを持たない）。レイヤーラベル列は専用 NSScrollView のクリップ原点をキャンバス側へ同期させる（双方向同期、再入ガードつき）。SwiftUI の @State（horizontalOffset / verticalOffset）へは報告用の写しとしてだけ流し、縦グリッドの間引き・仮想化の範囲・追加位置のレイヤー決定に使う。
- 操作層: 新設 `TimelineInteractionView.swift`。キャンバスの上に重なる AppKit ビューが左ボタンを一手に引き受け（右ボタンはヒットテストを素通しして下の SwiftUI コンテキストメニューへ渡す）、本家の TimelineItemView / TimelineItemViewModel の規則でドラッグセッションを回す。SwiftUI 側（`TimelineStripView.swift`）はアイテム描画とコンテキストメニューに専念し、アイテムビューは可視範囲（前後1画面分の余白つき）だけを生成する仮想化にした（FE-R1-032）。ForEach の同一性は ObjectIdentifier に変更。
- 選択: 正本を Core の `selectedItems`（同一性）に寄せた。ストリップの表示は Core 選択でハイライトし、`selectedItemIndex` は ProjectView のインスペクタ向けの写し（先頭アイテム）として従来どおり維持する。ProjectView 側の接続変更は `syncSelectionToTimeline` の1点のみ: Core の複数選択が UI 選択のアイテムを含む場合は複数選択を正として残し、含まない場合だけ従来どおり単一へ同期する（プレビュー側クリック等で UI 選択だけが動いた場合の従来動作は不変）。

**ドラッグセッションの規則（本家 TimelineItemViewModel.cs / TimelineItemView.cs で裏取り）。**
- MouseDown でモードを固定する。優先順位は本家 DecideMode どおり: 左つまみ（min(6px, 幅/3)）→右つまみ→キーフレーム近傍（6px以内）→ロックボタン→移動。移動モードのクリック選択は本家 SelectItemWithKeyboardStatus 相当（通常=未選択なら単独選択、Shift=範囲選択、トグル=後述の Command）。トリムは未選択なら単独選択にしてから始める。
- DragStart（本家 DragStartCommand）: Alt（Option）単独なら `unsafeCloneWithoutCollision()` で複製し（選択は元の側に残り、ドラッグで元の側が動く）、開始値を押さえ、`resolveItemCollision(selectedAndGroupedItems)` を呼ぶ。
- MouseMove ではモデルを逐次更新する。デルタは本家と同値になるよう「開始時からの累積 − モデルへ適用済みの分」の残り量で計算する（本家はアイテムビュー自体がモデルに追随して動くため Delta が残り量になる。こちらはビューが動かないので現在値と開始値の差で同じ量を作る）。レイヤー量は本家 GetDeltaFrameAndLayer の非対称な式（下向きは下端、上向きは上端を越えた分で切り替え）を残り量形式で再現。移動は `moveSelectedAndGroupedItems`（隣接吸着の extraDeltaFrame の振り分け条件も本家 MoveCommand どおり）、トリムは `changeSelectedAndGroupedItemsLength`、吸着は `getSnappedDelta`（対象=現在フレーム・アイテム端・キーフレーム、距離は SnapTargetPixelDistance 既定5px を換算、レイヤー距離は既定3）を使い、ビュー内に移動計算を複製していない。Shift で吸着オフ、トリムの隣接影響は Ctrl（ドラッグ途中の押下で判定。既定モード None との XOR で Stretch）。
- MouseUp で確定する。確定接続点は `TimelineStripView.onDragCommitted`（開始は `onDragBegan`、キャンセルは `onDragCancelled`）。通知契約は Round 9 で改めた（変更の有無にかかわらず必ず終了を通知し、通知はセッション状態の破棄より前に呼ぶ。詳細は本節末尾の「Round 9 処分」）。現時点では未接続で、Undo アプリ層接続単位がここへ EditCoordinator のトランザクション（開始・確定・取消）を差す。コンテキストメニュー等の離散操作は従来どおり `onEdited` 経路のままで、本単位の接続点には含めていない。
- キャンセル: Escape（ローカルキー監視）／ウィンドウの非アクティブ化（didResignKey）／対象アイテムのドラッグ中削除／対象タイムラインの差し替え、のいずれかで開始時状態へ復元する。復元は MouseDown 時点（複製より前）の全アイテムの frame / length / layer / contentOffset / キーフレームと、アイテム集合のメンバーシップ、選択をスナップショットから戻す。本家はキャプチャ喪失でも確定経路へ進むため、ここは Mac 側の安全性のための意図的な逸脱（FE-R2-DESIGN 記録済み）。
- 範囲選択: 背景ドラッグ（4px超）で矩形を表示し、MouseUp で角をフレーム／レイヤーへ切り捨て換算・正規化して `selectBetweenItems(fromFrame:fromLayer:toFrame:toLayer:)` で1回確定する（本家 CompleteSelectRange）。ドラッグ中は選択を更新しない（本家どおり矩形だけが動く）。背景の単クリックは従来の Mac 版の挙動（シーク）を維持し、ドラッグ中のシーク（スクラブ）は範囲選択へ置き換えた。
- 端の自動スクロール: 移動・トリム・キーフレーム・範囲選択の各セッションで、ポインタが可視端24px以内にある間、30msごとに12pxスクロールし、同じウィンドウ座標でドラッグ適用をやり直す。
- ロックボタン: ロック中のアイテムの右上（描画アイコンの位置、20×20px）を押して離すとロックを反転し、確定として接続点を通す（本家 ToggleLockCommand 相当）。

**Core への追加（本家 Timeline にあって移植に無かった正規 API）。**
- `Timeline.selectItem(_:)` / `toggleSelectionStatus(_:)` / `selectBetweenItems(to:)` / `selectBetweenItems(fromFrame:fromLayer:toFrame:toLayer:)`（`Sources/YMM4Core/Model/Timeline.swift`）。範囲選択の並び（アンカー→中間→対象、本家の private 本体の意味論）まで再現した。
- `Timeline.unsafeCloneWithoutCollision()`（`Sources/YMM4Core/Editing/TimelineEditing.swift`）。複製は `cloned()`（FPS 再注入込み）＋グループ ID 再発行＋ `addItems`。
- テスト: `TimelineEditingTests` に6件追加（選択ヘルパ4件、複製2件）。Mac で方式名フィルタ実行し TimelineEditingTests 26件・TimelineEditingLengthTests 29件が全合格（Executed で判定）。

**本家との差・未対応（意図的なものを含む）。**
- 選択トグルの修飾キー: 本家は Ctrl だが、Ctrl+クリックは AppKit では右ボタン（コンテキストメニュー）になるため、Command に割り当てた（プラットフォーム適応）。トリムの隣接影響の Ctrl はドラッグ途中の押下で従来どおり効く。
- トリム開始時の選択: 本家は最初の MouseMove で未選択なら単独選択にする。こちらは MouseDown で行うため、つまみを押して離すだけでも選択が変わる（実害のない範囲の差として許容）。
- 素材内部の区切り（ContentSeparations）への吸着: 本家は右トリムとキーフレームドラッグで追加の吸着先にするが、Core に ContentSeparations の供給が無いため未対応（getSnappedDelta の extraSnapPoints は空）。波形の実データ化（FE-R1-029）と同じく供給層の新設はしない。
- キーフレームの下限: 本家のキーフレームドラッグは先頭キーフレームを位置1未満へ動かせないが、Core の `moveKeyFrame` は0まで許す（PR #114 で確立した既存プリミティブをそのまま使用。1フレーム分の境界差として記録）。
- 波形は疑似波形のまま（FE-R1-029 未処分）。レイヤー音量（layerVolumes）の形のみ状態も従来どおり未接続。
- ダブルクリックでプロパティ編集へフォーカスする本家挙動（FocusToDefaultPropertyEditor）は未実装。

**検証。**
- Mac（同期先 ~/ymm4-work/fe-timeline/YMM4Mac）で Apps/DebugApp の `swift build` 成功（警告は既存の PreviewCore の Sendable 警告のみで、本単位のファイルには新規警告なし）。アプリの起動スモークテスト（8秒間生存、異常終了なし）を確認。ただし起動直後はタイムライン画面を開いていないため、ビュー構築の最終確認は下記の手動チェックに委ねる。
- モデル側の裏付け範囲: 移動・トリム・吸着・衝突縮小は Core の既存テスト（TimelineEditingTests / TimelineEditingLengthTests）が覆う意味論をそのまま使う。本単位の新規 Core API は上記の新規テスト6件で固定した。セッション自体（マウスイベントの配線）はアプリ層にテストターゲットが無いため自動検証できず、手動チェックリストで担保する。

**手動検証チェックリスト（オーナーの目視確認用）。** サンプルプロジェクト（Apps/DebugApp/Sample/sample.ymmp、9アイテム）または実プロジェクトで:
1. 起動→プロジェクトを開き、タイムラインが従来どおり表示されること（レイヤーラベル列・目盛り・再生ヘッド・アイテムの色とラベル）。
2. 横スクロールで目盛りとアイテムがずれないこと（目盛りのラベル位置とアイテム端が一致し続ける）。縦スクロールでラベル列とアイテム行がずれないこと。
3. アイテムをドラッグして左右・上下へ移動できること。隣アイテムへぶつかると手前で止まること。ドラッグ中にアイテムがポインタへ追随すること。
4. グループ化したアイテム／複数選択（Command+クリックで追加、背景ドラッグで範囲選択）がまとめて移動すること。
5. アイテムの左端・右端をつまんでトリムできること（カーソルが左右リサイズ形になる）。ドラッグ中に Ctrl を押すと隣アイテムが伸縮して追随すること（隣接影響）。Shift を押しながらだと吸着しないこと。
6. 吸着: 他アイテムの端・現在フレーム・キーフレーム付近で移動量が吸着すること。
7. Option を押しながらドラッグすると、元の位置に複製が残って元の側が動くこと。
8. キーフレームの三角形をドラッグして位置を動かせること（隣を越えない）。
9. ドラッグ中に Escape を押すと開始位置へ完全に戻ること。ドラッグ中に別のアプリへ切り替えると（非アクティブ化）開始位置へ戻ること。
10. 背景クリックでシークすること。目盛りのドラッグでシークできること。目盛り上のホイールでズームすること。
11. アイテムの右クリックメニュー（分割・グループ化・削除・移動サブメニュー等）と背景の右クリックメニュー、目盛りの右クリックメニューが従来どおり出て動作すること。削除後に選択が同じアイテムを指し続けること（FE-R1-003 の回帰確認）。
12. ロックしたアイテムの右上の鍵アイコンをクリックするとロックが外れること。
13. ドラッグでアイテムをタイムラインの端まで持っていくと自動スクロールすること。
14. ファイルをタイムラインへドロップして追加できること（従来動作の回帰確認）。
15. ズーム変更・レイヤー高さ変更・ウィンドウリサイズで表示が崩れないこと。大量アイテム（実プロジェクト、158アイテム）でスクロールとドラッグが実用速度であること（仮想化の確認）。

**Round 9 処分（FE-R9-001〜007）。** 対象は `TimelineInteractionView.swift`（001〜006）と `TimelineStripView.swift`（007）。検証: Mac で Apps/DebugApp の `swift build` 成功。Core テストは TimelineEditingTests 26件・TimelineEditingLengthTests 34件（001 の裏付けとして新規5件を追加）が全合格（Executed で判定、AudioDrift 除外）。

- FE-R9-001（P1、確定時にタイムライン長を再計算しない）: Core の移動・トリムは長さキャッシュを Expand（広げるだけ）するため、末尾アイテムを手前へ動かす・短縮してもキャッシュが長いまま残り、出力尺（TimelineExporter が `timeline.length` を使用）までずれていた。MouseUp の確定経路（移動・左右トリム・キーフレーム共通）で、本家ドラッグ完了時と同様に `refreshTimelineLengthAndMaxLayer()` を呼び、キャッシュが変わったら `onModelChanged` で再描画する。裏付けとして Core テスト5件を追加（移動での長さ・最大レイヤーの縮小、終了側トリムでの縮小、開始側トリムで終了フレーム不変、Stretch 後の computed との一致、後方移動で広がった分の保持）。いずれも「操作だけではキャッシュは縮まず、refresh で実際の値に一致する」契約を固定している。
- FE-R9-002（P1、開始通知がモデル変更より後）: MouseDown の順序を組み替えた。(1) スナップショット取得（クリック選択より前。006 と共通）、(2) クリック選択・トリムの単独選択、(3) Command トグルで外れた場合の開始中止（開始通知はまだ送っていないため対の終了通知は不要で、スナップショットは黙って破棄する）、(4) `onDragBegan`、(5) 複製・衝突解決（最初のモデル変更）、の順。確定・キャンセルの各通知も `endSession()`（スナップショット破棄）より前に呼ぶよう統一し、接続側が変更前メンバーシップを参照できる順序にした。
- FE-R9-003（P1、無変更終了時に終了通知が欠落）: 開始通知を送ったセッションは、MouseUp で変更の有無にかかわらず必ず `onDragCommitted` を送る契約に変更（無変更の確定は接続側が空の履歴として破棄できる）。ロックボタンを押して領域外で離した場合も同様に確定通知を送る。開始→確定／キャンセルの対は全経路で閉じる。
- FE-R9-004（P2、背景の範囲選択でも再生ヘッドが移動）: 背景 MouseDown の即時シークを廃止し、シークは範囲選択へ移行しなかった場合の MouseUp で確定する。
- FE-R9-005（P2、複数選択中の単クリックで単一選択にならない）: 本家の SelectCommand / SelectCommand2 の使い分けを再現。複数選択中の選択済みアイテムを修飾キーなしでクリックした場合、MouseDown では複数選択を維持し（`clickCollapseItem` に保留）、MouseUp でモデル変更が無かった場合にだけそのアイテムの単独選択へ確定する。実際にドラッグが成立した場合は複数選択を維持する。
- FE-R9-006（P2、キャンセル復元が元のアイテム順序を保持しない）: 復元方式を変更。従来は「余分を削除＋欠落を末尾へ再追加」で順序が変わっていた（重なりの当たり判定は items の後方優先のため見た目にも影響）。値の復元後に `timeline.items = snapshot.map { $0.item }` とスナップショットの列をそのまま代入し、メンバーシップと順序を一括で戻す（代入に伴う選択の掃除は直後の `selectItems(snapshotSelection)` で戻す）。あわせて選択のスナップショットはクリック選択より前（MouseDown 前の選択）に取得する契約へ変更（002 の順序変更と一体）。
- FE-R9-007（P2、短いタイムラインで背景の操作領域が不足）: ドキュメント幅を「タイムライン長由来の幅と表示幅（ビューポート幅）の大きい方」にした（`TimelineStripView` の body で `canvasWidth` を算出し、スクロール基盤の設定とキャンバス描画の両方へ渡す）。操作層はドキュメント全体を覆うため、右側の余白でもクリック（シーク）と範囲選択の開始を受けられる。`timeline.length` のキャッシュ自体は水増ししていない。

**通知契約の残りの非対称（Undo 接続単位への申し送り）。** 背景・範囲選択のセッションは開始通知（onDragBegan）を送らない設計のままだが、Escape 等でキャンセルされた場合は選択復元のために onDragCancelled が単独で呼ばれる（従来どおり）。EditCoordinator を接続する際は「開始通知のないキャンセル」を受けられる形にすること。

**手動検証チェックリストへの追加項目（Round 9 分）。**
16. 最後のアイテムを手前へ移動、または右端トリムで短縮した後、目盛りの末尾・横スクロール範囲が実際の最終フレームに合うこと（FE-R9-001）。
17. アイテムを押して動かさずに離しても不具合がないこと。複数選択中に選択済みアイテムをクリックして離すとそのアイテムだけの選択になること。ドラッグした場合は複数選択が保たれること（FE-R9-003 / 005）。
18. 背景をドラッグして範囲選択したときに再生ヘッドが動かないこと。背景の単クリックではシークすること（FE-R9-004）。
19. ドラッグ中に（別経路で）アイテムが削除されてキャンセルになった場合、アイテムの並び順と選択がドラッグ前の状態に戻ること。ドラッグ中に Escape でキャンセルした場合も、クリック前の選択に戻ること（FE-R9-006）。
20. 短いプロジェクト（タイムラインが画面幅より短い）で、右側の余白をクリックしてシークできること、余白からドラッグして範囲選択を始められること（FE-R9-007）。

**Round 10 処分（FE-R10-001〜002）。** 対象は `TimelineInteractionView.swift` のみ。検証: Mac で Apps/DebugApp の `swift build` 成功。Core テストは TimelineEditingTests 26件・TimelineEditingLengthTests 34件の計60件が全合格（Executed で判定、AudioDrift 除外）。セッションの通知配線と確定条件はアプリ層のため自動テストは無く、手動検証チェックリスト21・22で担保する（未実施。オーナーの目視確認待ち）。

- FE-R10-001（P1、キャンセル後に Core 選択とインスペクタ選択が乖離）: Round 9 でキャンセル時に Core の `selectedItems` を復元できるようになったが、`cancelSession()` のスナップショット復元経路は `onModelChanged()`（再描画＋プレビュー更新）だけを呼び、`onSelectionChanged()`（`reflectSelection()` によるインスペクタ側の選択写し `selectedItemIndex` の更新）を呼んでいなかった。このため Escape でキャンセルすると Core 選択は MouseDown 前へ戻るのにインスペクタはクリックしたアイテムを表示し続け、その後の編集操作で `ProjectView.syncSelectionToTimeline()` が UI 側の選択を Core へ再同期して、復元されたはずと違うアイテムが編集・削除対象になり得た。復元後に `onSelectionChanged()` も呼ぶよう修正し、Core 選択と選択写しの両方が MouseDown 前へ戻ることを契約にした。あわせて通知経路を全経路で点検した: 選択を変更する箇所は MouseDown のクリック選択（Command トグル／Shift 範囲／単独選択）とトリム時の単独選択、MouseUp の単独選択確定と範囲選択確定、キャンセルの範囲選択のみの経路で、いずれも `onSelectionChanged()` を呼んでおり、欠落はキャンセルのスナップショット復元経路だけだった。モデル変更の通知（ドラッグ中の各適用、MouseUp の長さ再計算、ロック切り替え、キャンセル復元）にも欠落は無かった。
- FE-R10-002（P2、ドラッグ後に元位置へ戻すと複数選択が解除される）: 単独選択への確定（FE-R9-005）の判定が「最終モデルが開始時と等しいか」だったため、複数選択中にアイテムを動かして開始位置へ戻して離すと、差分ゼロを単クリックと誤認して単独選択へ切り替わっていた。本家は MoveCommand の実行時点で `isSelectedCommandExecuted` を立てて終了時の単独選択化を抑制しており、最終差分では判断していない。セッション状態に `didExecuteEditCommand` を追加し、移動・トリム・キーフレーム移動の各適用で非ゼロのデルタのコマンドを発行した時点で立てる（結果として値が変わらなくても実行自体を数える）。MouseUp の確定条件を「最終差分なし、かつコマンド未実行」に変更し、往復ドラッグでは複数選択を維持、操作なしの単クリックでは従来どおり単独選択へ確定する。（フラグの発火条件は Round 11 で本家に合わせて改めた。下記「Round 11 処分」参照。）

**手動検証チェックリストへの追加項目（Round 10 分）。**
21. アイテム A を選択した状態で別のアイテム B を押さえ、ドラッグ中に Escape でキャンセルしたとき、タイムライン上の選択とインスペクタの表示の両方が A に戻ること。その後すぐ編集・削除操作をしても A が対象になること（FE-R10-001）。
22. 複数選択中に選択済みアイテムを数フレーム動かして元の位置へ戻して離しても、複数選択が保たれること。動かさずにクリックして離した場合は、そのアイテムだけの選択になること（FE-R10-002）。

**Round 11 処分（FE-R10-002 の発火条件の残差、FE-R11-001）。** 対象は `TimelineInteractionView.swift` のみ。検証: Mac（同期先 ~/ymm4-work/fe-timeline/YMM4Mac）で Apps/DebugApp の `swift build` 成功。Core テストは TimelineEditingTests 26件・TimelineEditingLengthTests 34件の計60件が全合格（Executed で判定、AudioDrift 除外）。今回の変更はいずれもアプリ層のセッション処理のため自動テストは無く、手動検証チェックリスト23・24で担保する（未実施。オーナーの目視確認待ち）。

- FE-R10-002（P2、残差: フラグの発火条件が本家と不一致）: Round 10 の処分は「吸着補正後のデルタが非ゼロのときに立てる」だったが、本家はデルタの値ではなくコマンドの呼び出し時点で立てる。そのため高ズーム時（例: 40px/フレーム）に1フレーム未満だけドラッグすると、量子化・吸着補正の結果がゼロになってフラグが立たず、複数選択が単独選択へ崩れていた。本家の実コードで確認した発火条件は次のとおり: `MoveCommand` は冒頭（`GetDeltaFrameAndLayer` によるデルタ計算より前）で `isSelectedCommandExecuted = true` を設定する。`ResizeHeadCommand` / `ResizeFootCommand` も冒頭（未選択なら選択した直後、デルタ計算・吸着補正より前）で同じく立てる。View 側はこれらのコマンドをドラッグ中の MouseMove のたびに実行するため、ポインタが実際に動けばデルタがゼロでも立つ。一方、キーフレーム移動の `DragDeltaCommand`（TimelineItemKeyFrameViewModel）はフラグに一切触れず、キーフレームモードの MouseDown は SelectCommand 自体を実行しない。処分: Mac 側のフラグを立てる時点を `applyMove` / `applyResize` の冒頭（実行経路に入った時点、デルタ計算・吸着補正より前）へ移し、量子化・吸着補正の結果とは独立に立てた。mouseDown では立てない（通常の単クリックまでドラッグ扱いになるため）。キーフレーム移動の経路は本家に合わせてフラグを立てないよう変更した（従来は非ゼロデルタで立てていた。`clickCollapseItem` は移動モードでしか設定されないため、この変更で観測できる挙動は変わらない）。
- FE-R11-001（P2、MouseDown 中のモデル変更に再描画通知がない）: MouseDown では `onDragBegan` の後に Option 複製（`unsafeCloneWithoutCollision()`）がアイテムを追加し、`resolveItemCollision()` がレイヤーを変更し得るが、その後に `onModelChanged()` が呼ばれていなかった。選択済みアイテムを Option+MouseDown して移動せず MouseUp すると、Core には複製が追加されるのに再描画通知が無く（タイムライン長キャッシュも変わらなければ MouseUp でも発生しない）、画面・プレビューへ反映される保証がなかった。Round 10 で報告した「モデル変更通知の全経路点検」は、ドラッグ中の各適用と確定・キャンセル経路が対象で、MouseDown 内の DragStart 変更が漏れていた。処分: 複製・衝突解決の後に、クリック選択より前に取ったスナップショットとの比較（既存の `modelDiffersFromSnapshot`。メンバーシップ＋ frame / length / layer / contentOffset / キーフレームの比較で、選択の変更は対象に含まれない）で実際に変化した場合にだけ `onModelChanged()` を呼ぶ。変化のない通常の MouseDown では通知しない。あわせて `onDragBegan`（開始の通知）と `onModelChanged`（発生済みの変更の通知）の責務の区別を、設定構造体のドキュメントコメントに明記した。

**手動検証チェックリストへの追加項目（Round 11 分）。**
23. ズームを大きくした状態（1フレームが数十pxになる倍率）で、複数選択中のアイテムを1フレーム未満だけドラッグして離しても、複数選択が保たれること。動かさずにクリックして離した場合は、そのアイテムだけの選択になること（FE-R10-002 残差）。
24. 選択済みアイテムを Option を押しながら MouseDown し、移動せずに離したとき、複製がその場でタイムラインとプレビューに表示されること。通常の（Option なし）MouseDown では余分な再描画やちらつきが無いこと（FE-R11-001）。
#### FE-SLIDER-UI — スライダ表示モデルと AnimationRowView の接続（フロントエンド監査 FE-R1-042、単位2後半）

**何を実装したか。** FE-SLIDER-CORE で Core に用意した表示仕様（`AnimationSliderSpec`）を実際のスライダへ接続し、FE-R1-042 を閉じる単位。従来の `AnimationRowView` はアニメーションの絶対制限（minValue...maxValue）をそのままスライダ範囲に使っており、基準範囲（例: 音量 0..100）に対して絶対制限（例: 0..10000）が桁違いに広い項目では、ドラッグの分解能が粗くなり値が跳んでいた。本単位で、範囲は「表示仕様の基準範囲を、同一 Animation の全有効値で共有するスケールで広げたもの」になった。土台として feat/fe-batch1（PR #118）を feat/fe-slider-core へマージ済み（競合は `ProjectView.swift` の2箇所のみ。書き込み経路はバッチ1側の `writeAnimationValue` 集約を正とし、種別判定はスライダ基盤側のパターン照合 `guard case .animation` を正として両意図を保存した）。

**スケール計算の置き場所（FE-SLIDER-CORE の判断との関係）。** 本家 `TextBoxSlider.ChangeMinMax` の式は `Sources/YMM4Core/Editing/AnimationSliderScale.swift` に純粋関数の列挙型 `AnimationSliderScale` として置いた。FE-SLIDER-CORE で先行配置を見送った理由は「消費するコントロールが無く、式だけが未検証で固定される」ことであり、本単位でコントロール（AnimationRowView）が消費する。もう1つの理由は検証可能性で、アプリ層にはテストターゲットが無いため、アプリ層に式を置くと端点補正を含む式の独立検証ができない。Core に置くのは「式」だけであり、スケールの状態は保持しない — 現在効いているスケールは表示側がモデル値から毎回導出する派生状態で、モデルへ保存しない点は監査 Round 2 の設計判断どおりである。

**式の内容（本家との対応）。** `scale(value:defaultMin:defaultMax:absoluteMin:absoluteMax:)`: 本家 `ChangeMinMax` の `Scale` の再現。基準端点で割った商の切り捨ての最大値 +1 を 2 の冪へ切り上げる。端点補正も元の式のとおり（スケール > 1 で、値がちょうど基準端点 × (スケール − 1) に一致し、その積が絶対制限の端点そのものなら 1 引く。補正後のスケールは 2 の冪とは限らず、例: 基準 ±100・絶対上限 300・値 300 では 4 → 3 になる）。指数の頭打ちとして 2^30 を置いた（有限なモデル値では到達しない防御）。`sharedScale`: 本家は各値の `TextBoxSlider.Scale` の最大値を全値の `MinScale` へ伝播させ、実効スケール（`AdjustedScale = max(MinScale, Scale)`）を全員一致させる。その固定点を1回で計算する。`currentRange`: `CurrentMin` / `CurrentMax` の再現（基準範囲をスケール倍し、絶対制限で頭打ち。基準端点が正の側では基準範囲より狭くならない）。`ranges(forValueAt:)`: 移動量指定（`AnimationType.movementAmount`）の第2値だけ、基準範囲と絶対制限の双方を ±最大絶対値の対称範囲へ置き換える本家の例外（`AnimationSliderViewModel` の値ビュー構築）。

**ビューの変更（`Apps/DebugApp/Sources/YMM4MacDebug/PropertyEditorRows.swift` の `AnimationRowView` のみ）。** (1) スライダは `descriptor.sliderSpec` がある場合だけ出し、範囲は `AnimationSliderScale.sliderRange(for:valueIndex:spec:)`（valueIndex は編集中の区間、無ければ 0）。仕様が無い項目はスライダを出さず数値入力のみ（絶対制限全域へのフォールバック禁止という設計判断）。(2) 単位は入力欄の横に caption で出す。`unitIsResourceKey`（未解決のリソースキー名）の場合はキー名をユーザーへ見せず単位なしとして扱う。(3) 数値表示は仕様の stringFormat（"F<n>"）の小数桁で整形する `formatAnimationValue(_:spec:)` を新設し、この行の全表示経路（初期表示・区間追随・スライダ同期・確定時の再整形）で使う。仕様が無い場合は従来の `formatNumber` に落とす。FE-R1-019 の未編集判定（uneditedText）は同じ整形を通るため共存する。書き込み経路（`writeValue`、区間対応）は変更していない。

**本家との差分（ユーザーから見えるもの）。** (1) 移動量指定の第2値（移動量そのもの）は、現行の Mac UI では直接編集する欄が無く（開始値のみ編集可能）、対称置換は共有スケールの計算にだけ効く。本家は第2値にも独立したスライダを持つ。Mac UI の行構成そのものの拡張は本単位の範囲外とした。(2) 単位の表示位置は入力欄の横（本家は入力欄の内側）。(3) 本家の `FixValue`（Delta から導く桁数への丸め＋クランプ）は再現していない。Mac 側の確定値は記述子の setter が絶対制限でクランプし、表示は stringFormat の桁で丸まる（モデル値自体は連続値のまま）。ドラッグも本家同様に連続（刻みへの量子化はしない）。

**検証。** Mac（同期先 ~/ymm4-work/fe-slider/YMM4Mac）で Apps/DebugApp の swift build 成功。Core テストを方式名フィルタで実行し全合格（XCTest 側の Executed で判定、AudioDrift 除外）: 新規 `AnimationSliderScaleTests` 13 件（Scale の式: 範囲内は 1、端点一致での 2 倍、端点補正の発動と (スケール−1) 判定による 4→3、2 の冪の増加、DefaultMin >= 0 の分岐。CurrentMin/Max のスケール倍と絶対制限クランプ、基準範囲を下回らないこと。R2-A01: 値が基準範囲内なら表示範囲 = 基準範囲。R2-A02: 範囲外の値で拡張される（正負両側）。R2-A03: キーフレーム区間間でスケール共有 — 末尾の値 500 が全体を 8 倍へ押し上げ全区間に効くこと、有効値列の既定値補完。R2-A04: 対称置換の範囲そのものと、共有スケールへの効果 — 対称置換なしの型との対照で固定）、既存 `AnimationSliderSpecTests` 14 件、`PropertyMetadataTests` 17 件、`EffectPropertyMetadataTests` 18 件。合計 62 件・失敗 0。

**手動検証チェックリスト（未実施。アプリ層のため目視確認が要る）。** (1) R2-A01: 音量（基準 0..100）など基準範囲が絶対制限より狭い項目で、スライダのドラッグが入力欄の値へ線形に追従し、値が跳ばないこと。(2) R2-A02: 数値入力で基準範囲外の値（例: 250）を確定して行を開き直し、スライダ範囲が拡張されて値が範囲内に収まっていること。(3) R2-A03: キーフレーム付き項目で、別区間に大きな値（例: 500）を入れた状態で他区間を表示し、スライダ範囲が全区間で同じ拡張になっていること。(4) R2-A04: 移動量指定の項目で、移動量が大きな負値でも開始値側のスライダ範囲が不必要に広がらないこと。(5) 単位表示: 単位のある項目で単位が見えること、単位がリソースキーの項目（例: 秒系）でキー名がそのまま表示されないこと。(6) 仕様の無い項目（例: TextItem の PlaybackRate2）でスライダが出ず数値入力のみになること。

**Round 13 処分（FE-R13-001 / FE-R13-002）。** (1) FE-R13-001（P1）: `AnimationRowView` の表示値は再生ヘッド位置での評価値（`animationContext.value(of:)`）だった一方、書き込みは先頭値・区間開始値へ向かっており、表示と編集対象がずれていた（移動量指定ではスライダへ渡る現在値が表示範囲の外へ出る、書き込んだ値と表示へ戻る評価値が一致しない）。本家は各スライダが担当する `AnimationValue.Value` を直接編集する（`AnimationValueSliderViewModel`）ため、表示・編集の対象値を編集対象の AnimationValue そのものへ一致させた。対応付けは Core の `AnimationSliderScale.editValue(of:valueIndex:)` へ切り出し（valueIndex はスライダ範囲計算と同一の「編集中の区間、無ければ 0」）、行側は初期表示・スライダ Binding・区間追随・確定時の再整形の全経路でこれを使う。再生ヘッドでの評価値は編集欄へ出さない（プレビュー側の表示に委ねる）。Core テストで「移動量指定の評価値 600 に対して編集対象値は開始値 0」を固定した。(2) FE-R13-002（P2）: `AnimationSliderScale.activeValues(of:)` が不足分を `defaultValue` で補っていたため、値列が短い状態（例: 拡大率を定数 50 へ変更して移動量指定へ切替、値列は [50] のまま）で、存在しない第2値（既定値 100）が対称範囲の端点として共有スケールを 2 倍へ膨らませていた。本家 `ActiveValues` は `Values.Take(GetActiveValueCount())` で存在する値だけを列挙するため、列挙をその意味論へ変更した（不足分は作らない、超過分は切り詰める）。値列の正規化そのもの（本家は編集終了時の `EndEditAsync` が担い、移動量指定の第2値は 0 で補われる）は、Mac 側の記述子書き込みに編集セッションの境界が無く即時確定のため本単位では再現せず、スケール列挙だけを揃える判断とした（正規化タイミングの差は未解決事項として残る）。従来の `testActiveValuesPadsWithDefaultValue` は Mac 側方針を固定した試験だったため本家の意味論に合わせて `testActiveValuesReturnsOnlyExistingValues` へ書き換え、回帰試験 `testSharedScaleIsNotInflatedByMissingMovementAmountValue` を追加した。

**手動検証チェックリストへの追加（未実施）。** (7) FE-R13-001: 移動量指定の項目（例: X、開始値 0・移動量 1）で再生ヘッドを進めた位置でも、入力欄とスライダが開始値 0 を示し、スライダ操作で開始値を変えると入力欄の値がそのまま一致すること。(8) FE-R13-002: 拡大率を定数 50 にしてから移動量指定へ切り替え、開始値側のスライダ範囲が不必要に広がっていない（基準範囲のまま）こと。

**次の担当へ。** 単位リソースキー 38 件の実文字列は未解決のまま（FE-SLIDER-CORE から継続）。`ConditionalUnitAnimationSlider` 8 件も仕様なしのまま。ファイル参照（FE-R1-043、`PropertyKind.filePath`）は次単位。

#### FE-FILEPATH — ファイル参照（FE-R1-043。監査 Round 2 設計の「ファイル参照」節の実装）

**本家規則の照合（着工前に逆コンパイル成果物で確認。根拠はファイル:行）。**

- 素材の再生時間（ContentLength）: 動画は `VideoFileSourceFactory.Create(devices, FilePath)?.Duration ?? Zero` の遅延取得で FilePath ごとにキャッシュし、エコー有効時はエコーの尾を加える（VideoItem.cs:242-262）。音声は `AudioFileSourceFactory.Create(FilePath, AudioTrackIndex)?.Duration ?? Zero` ＋エコーの尾（AudioItem.cs:243-262）。画像は常に Zero（ImageItem.cs:47-49）。エコーの尾は `EchoEffect(interval, attenuation/100).AdditionalDuration × (PlaybackRate2 先頭値 / 100)`（AudioItem.cs:375-378、VideoItem も同文）。AdditionalDuration は interval × 繰り返し回数で、繰り返し回数は `min(50, ceil(log(0.01)/log(attenuation)))`（EchoEffect.cs:55, 62）。
- 新規追加時の長さ決定（ResetLength、ItemEx.cs:106-117）: resetContentOffset のとき ContentOffset = 0（VoiceItem はキャラクター側のオフセット）。Length は、ContentLength ≠ Zero かつ（再生速度の先頭値 ≠ 0 または速度が定数でない）なら `max(1, VideoInfo.GetFrameFrom(GetContentLengthAppliedPlaybackRate()))`、それ以外は **300**。GetContentLengthAppliedPlaybackRate（ItemEx.cs:119-139）: ContentLength が Zero なら Zero。速度が定数でなければ `PlaybackRateMap.FindContentExhaustedTime(item.Length, item.VideoFPS, ContentOffset, ContentLength) ?? Zero`。定数なら先頭値 0 で Zero、それ以外は `FromSeconds(max(0, (ContentLength − ContentOffset).TotalSeconds) / |先頭値| × 100)`、OverflowException 時は 5 秒。FindContentExhaustedTime（PlaybackRateMap.cs:381-424）は開始位置の範囲外で Zero、符号変化の零点交差を二次方程式で解き（SolveCrossingTau、同 426-462）、表の外は終端速度で外挿し、終端速度 0 では nil。丸めは `FrameTime.TimeToFrame` = `Round(秒 × FPS, MidpointRounding.AwayFromZero)`（FrameTime.cs:7-10、VideoInfo.GetFrameFrom は VideoInfo.cs:85-88）。Mac 側 Core の `FrameTime.frame(from:fps:)` は同一規則で既存だった。
- 追加フロー: メニュー追加はファイルダイアログ（複数選択可、ファイルグループ別）を先に開き（MainViewModel.cs:3125-3222）、AddVideoItem/AddAudioItem/AddImageItem（MainModel.cs:1526-1560）が既定アイテムの複製へ FilePath を設定し、動画・音声は ResetLength(VideoInfo, resetContentOffset: true) してから AddItems する。画像は FilePath のみで Length は既定アイテムのまま。既定アイテムの Length は全種別 300（DefaultItems.cs の初期化で 14 箇所 `Length = 300`。BaseItem のフィールド初期値は 1、BaseItem.cs:27）。ダイアログをキャンセルした場合の扱いは設定 GetAddFileItemMode() で、Default は **Cancel**（何も追加しない。YMMSettings.cs:1375-1382）。追加方向 GetAddItemsOrientation() の Default は **Vertical**（YMMSettings.cs:1366-1373）。ドロップは MainViewModel.AddFileItemAsync（同 4501-4547）→ MainModel.AddItemFromFileAsync（同 1743-1778、拡張子で分類）→ 同じ Add*Item。
- 既存アイテムのファイル変更: FilePath の setter 自体は通知（"FilePath","Label","Description","ContentLength","ContentSeparations"）だけを出し、長さは変えない（VideoItem.cs:82-88、AudioItem.cs:79-88）。属性は動画 `[FileSelector(VideoItem, ShowThumbnail = true)]`（Order 200、グループ VideoGroupName）、音声 `[FileSelector(AudioItem)]`（サムネイルなし）、画像 `[FileSelector(ImageItem, ShowThumbnail = true, PropertyEditorSize.FullWidth)]`（Order 200、ImageGroupName）。長さの調整はアイテム編集の終了時（ItemEditorViewModel.cs:36-76 の EditingValue）: 素材長（OriginalContentLength）が変わっていれば ResetLength(resetContentOffset: true)。変わらず ContentLength が変わり、かつ長さの終端が素材の区切り（ContentSeparator、±1 フレーム）に乗っていれば ResetLength(false)。それ以外で再生速度が定数→定数で変わっていれば Length を比率で再計算（切り捨て、1 未満は 300、符号反転時は ContentOffset も調整）。
- 相対パス: FilePath は選択・入力された文字列のまま保持され、プロジェクトの移動時に相対パスを再基準化する（IFileItemEx.UpdateFilePath、IFileItemEx.cs:10-35）。選択時点で絶対パスへ置換する処理は無い。
- **推定（未確認）**: 編集終了時の比較に使う ContentLength の遅延キャッシュが、FilePath 変更の通知でいつ再取得されるかは全経路を追い切れていない。setter が "ContentLength" の変更通知を出すため編集側が再読込する前提で実装した。
- **未検証**: FileSelector の表示名・グループ名の実文字列は逆コンパイル成果物に資源キー名しか無く（例: VideoItemFilePathName、VideoGroupName）、実文字列は取得できない。表示名は従来の house rule（根拠が取れないものはプロパティ名そのまま）で "FilePath" とした。

**受け入れ条件 R2-B01〜B04 への対応。** 監査 Round 2 回答の条件文そのものは FE-R2-DESIGN.md に転記が無く（設計節の要点のみ）、条件文は復元できないため、設計節の要点から次の対応で試験を構成した。B01 = filePath 記述子の存在・種別・付随情報（ファイル種別／サムネイル可否）と、パスの読み書きがモデルへ届くこと、setter が長さ・素材情報へ触れないこと。B02 = 新規追加時の長さ決定規則（ResetLength 相当）。B03 = 既存アイテムのファイル変更時の調整（素材長が同じならトリム保持、変われば再決定＋オフセット 0）。B04 = 相対パスをそのまま保持し、解決は供給層でのみ行うこと。

**何を実装したか。**

- Core: `PropertyKind.filePath(group:showsThumbnail:)` と `PropertyFileGroup`（video/audio/image）を新設（Editing/PropertyMetadata.swift）。値の読み書きは `PropertyAccess.filePath`（String）で既存の仕組みを再利用し、`.text` の変種にはしていない。`stringValue` / `setStringValue` は filePath でも文字列として往復する。
- Core: `ItemPropertyMetadata` が VideoItem / AudioItem / ImageItem の先頭へ FilePath 記述子を出す（グループは動画／音声／画像、表示名 "FilePath"、サムネイル可否は本家の属性どおり動画 true・音声 false・画像 true）。
- Core: 編集操作層として `Editing/MediaItemLength.swift` を新設。`MediaFileInfo`（再生時間と寸法）、`BaseItem.recordMediaInfo`（素材長とエコーの尾を反映。素材長そのものは ContentLength と分離して originalContentLength へ保持）、`contentLengthAppliedPlaybackRate()`、`resetLength(fps:resetContentOffset:)`（本家 ResetLength 相当。フレーム変換の FPS は引数、速度が定数でない場合の消耗時刻探索はアイテム自身の Length と VideoFPS を使う本家の分担を再現）、`adjustLengthAfterFileChange(previousOriginalContentLength:fps:)`（編集終了時のファイル変更分岐）。`PlaybackRateMap.findContentExhaustedTime` を Core へ追加し、本家の零点交差・外挿の意味論を再実装した。エコーの繰り返し回数は既存の `EchoAudioStream` へ静的関数として切り出し、初期化処理と尾の計算で共有する（挙動は不変）。
- アプリ層: `MediaFileInfoFetcher`（新規）を I/O 供給層として追加。拡張子分類表（本家 FileExtensions の既定。判定順 動画→音声→画像）をここへ一元化し、ドロップ分類・追加ダイアログ・参照ダイアログで共有する。情報取得は非同期で、ファイルが存在しなければ nil。音声は既存の PCM 供給工場（`AVFoundationPCMProviderFactory`）の provider の duration、動画は AVAsset の映像トラックの提示区間（`presentationRange`。GPU 層に既存の実装を公開化して再利用）と変換適用後の寸法、画像は ImageIO のピクセル寸法（長さはゼロ）。
- アプリ層: メニュー追加は動画・音声・画像でファイルダイアログ（複数選択可、種別で絞り込み）を先に開き、情報取得が成功したファイルだけを長さ決定してから `tryAddItems` で一括確定する。キャンセル時は何も追加しない。ドロップも同じ取得・適用経路を通す（従来のプレースホルダ長 1 秒は廃止）。既存アイテムのファイル差し替えはインスペクタの filePath 行（パス欄＋「参照…」ボタン）が担い、確定前にアプリ層へ通知して変更前のパスと素材長を捕捉し、取得後に世代と対象の同一性を照合してから素材情報を記録し、長さ調整を行う。
- ARCHITECTURE.md のデータフローへメディアアイテムの追加・差し替え経路を追記した。

**本家との差分（意図的なもの）。**

- ファイルが存在しない場合の差し替え: 本家は編集終了時に ContentLength が Zero へ落ちて ResetLength が 300 を入れ得るが、Mac 側は取得失敗時に長さへ触らず状態表示で知らせる（パスの打ち間違いで利用者のトリムを消さないため）。パス文字列自体は記述子が保持する。
- 編集終了時の調整のうち、素材の区切り（ContentSeparations）へ長さ終端が乗っている場合の分岐と、再生速度の変更に伴う比率再計算の分岐は本単位では未実装（ファイル変更の分岐のみ）。ContentSeparations の供給自体が Mac 側に無い。
- エコーの尾は素材情報の記録時点で確定する（本家は ContentLength の取得時に都度計算）。エコー設定を後から変えた場合の追随はしない。
- インスペクタ行でのサムネイル表示は未実装（`showsThumbnail` は種別の契約として保持のみ）。
- 動画・画像のグループ表示文字列（「動画」「画像」）は実文字列が未検証で、アイテム種別名の UI 文字列を流用した（「音声」は既存の音声グループ表示と一致）。

**検証。** Mac（~/ymm4-work/fe-filepath/YMM4Mac）で Apps/DebugApp の `swift build` 成功（217 ステップ）。Core テストは方式名フィルタで実行し全合格（XCTest の Executed 件数で判定）: MediaItemLengthTests 19 件（長さ決定の規則を固定。定数速度・速度 0・オフセット減算とリセット・300 フォールバック・AwayFromZero 丸め・最小 1 フレーム・FPS 引数・非定数速度の消耗時刻・エコーの尾・ファイル変更時のトリム保持と再決定・消耗時刻探索の表内／外挿／終端速度 0）、PropertyMetadataTests 20 件（filePath 記述子の種別・グループ・サムネイル可否、相対パスの verbatim 往復と長さ不干渉を含む）、EffectPropertyMetadataTests 17 件、AnimationSliderSpecTests 14 件、AnimationSliderScaleTests 17 件、TimelineEditingTests 20 件、TimelineEditingLengthTests 29 件。合計 136 件、失敗 0。AudioDrift は対象外。

**手動検証チェックリスト（未実施）。** (1) メニューの「動画アイテムを追加」でファイルダイアログが開き、動画を選ぶと素材の長さでアイテムが置かれること。複数選択で複数置かれること。キャンセルでは何も追加されないこと。(2) 音声・画像でも同様で、画像は長さ 300 フレームで置かれること。(3) 取得できないファイルの扱いが区別どおりであること: 選択・ドロップ後にファイルが存在しなくなった場合は追加されず、アイテムが残らないこと。存在するがデコードできないファイル（AVFoundation で開けない形式等）は、再生時間ゼロとして長さ 300 フレームのアイテムが追加されること（意図的なフォールバック。素材を開けないこと自体の可視化は Issue #70 の範囲）。(4) 既存の動画アイテムのインスペクタに FilePath 欄と「参照…」ボタンが出て、別ファイルへ差し替えると長さが新しい素材に合わせて変わること。同じ長さの別ファイルへ差し替えるとトリムした長さとオフセットが保持されること。(5) プロジェクトフォルダ基準の相対パスを FilePath 欄へ入力すると、そのままの文字列で保存され、プレビューで解決されること。(6) 存在しないパスを入力すると状態表示に失敗が出て、長さが変わらないこと。(7) 大きな動画ファイルの追加を開始し、情報取得の完了前に別のタイムラインへ切り替えても、表示中タイムラインの選択（インスペクタの表示対象）が変わらないこと。取得中に対象タイムラインを削除した場合は、追加が確定しないこと（FE-R15-002）。(8) 既存アイテムのファイルを、より長い素材・より短い素材へ差し替えたときに、タイムライン全体の長さ（スクロール範囲や書き出し範囲）が新しい実長へ追随すること。同長の別ファイルへの差し替えではタイムライン長が変わらないこと（FE-R16-001）。

**次の担当へ。** AVFoundation で開けない形式（MKV 等）は音声・動画とも再生時間ゼロとして扱われ、長さ 300 へ倒れる。素材を開けないこと自体の可視化は Issue #70（FFmpeg 供給）の設計と合わせて判断すること。本単位の情報取得層は「長さ決定のための最小情報」に限っており、波形データ（FE-R1-029）の供給は含まない。FE-R8-001 ブランチ（Volume/Pan 記述子）とは ItemPropertyMetadata.swift の変更箇所が近いため、マージ順序に注意すること。

**監査 Round 15 の処分（FE-R15-001〜003）。**

- FE-R15-001（P2、素材長ゼロでもエコー尾を加算する）: 本家の ContentLength は素材長がゼロならエコー設定にかかわらず Zero を返す（VideoItem.cs / AudioItem.cs の取得経路で再確認）。`recordMediaInfo` を、素材長がゼロの場合は contentLength をゼロのままにするよう修正した。回帰試験 `testRecordMediaInfoWithZeroDurationIgnoresEchoTail` を追加（エコー有効・素材長ゼロで contentLength がゼロ、長さが既定 300 へ倒れることを固定）。
- FE-R15-002（P1、非同期追加の完了時に別タイムラインの選択状態を書き換える）: `addMediaFiles` の確定時に、対象タイムラインがまだプロジェクトに属していることを確認し（取得中に対象タイムラインが削除された場合は追加を確定しない）、`reflectCoreSelection` は追加先が現在表示中のタイムラインの場合だけ実行するよう変更した（別タイムラインへの追加自体は許容するが、表示中タイムラインの選択状態を書き換えない）。差し替え側の `applyFileChange` は世代＋対象同一性の照合が既にあったため、同じ水準としてタイムラインのプロジェクト所属確認を追加した。アプリ層にはテストターゲットが無いため、有効性判定・表示中判定はコードの形と手動検証チェックリスト (7) で固定する。
- FE-R15-003（P3、取得不能ファイルの検証条件の矛盾）: コードの挙動は変更せず、手動検証チェックリスト (3) を「不存在（追加されず何も残らない）」と「存在するがデコード不能（再生時間ゼロとして長さ 300 のアイテムが追加される意図的なフォールバック）」を区別する文面へ訂正した。
- 対象外として触っていないもの: FE-R15-004（ContentSeparations 終端追随・定数速度変更時の比率再計算）、FE-R15-005（サムネイル表示）、FE-R15-006（エコー設定変更時の ContentLength 再計算）。いずれも別単位へ移管済み。
- 検証: Mac（~/ymm4-work/fe-filepath/YMM4Mac）で Apps/DebugApp の `swift build` 成功。Core テストは方式名フィルタで実行し全合格（XCTest の Executed 件数で判定、AudioDrift 除外）: MediaItemLengthTests 20 件（Round 15 の回帰試験で +1）、PropertyMetadataTests 20 件、EffectPropertyMetadataTests 17 件、AnimationSliderSpecTests 14 件、AnimationSliderScaleTests 17 件、TimelineEditingTests 20 件、TimelineEditingLengthTests 29 件。合計 137 件、失敗 0。手動検証チェックリスト (3) の訂正と (7) の追加は未実施のまま（目視確認待ち）。

**監査 Round 16 の処分（FE-R16-001）。**

- FE-R16-001（P1、ファイル差し替え後にタイムライン長キャッシュが更新されない）: `applyFileChange` は `adjustLengthAfterFileChange` の戻り値（長さが決め直されたかどうか）を捨てており、アイテム長が伸びても縮んでも `Timeline.length` のキャッシュが古いまま残っていた（キャッシュは自動追随せず、書き出し範囲の決定にも使われる）。処分: 戻り値が true の場合だけ、所属タイムラインを把握しているアプリ層で `timeline.refreshTimelineLengthAndMaxLayer()` を呼ぶよう変更した。長さが変わらなかった場合は再計算しない。Core の BaseItem 側へは入れていない（アイテムは所属タイムラインを知らない。タイムライン再構築単位の R9-001 と同じ構図で、再計算の責務はタイムラインを知る側にある）。
- 検証方式: アプリ層にはテストターゲットが無いため、確定手順（記録→調整→調整が起きた場合だけ再計算）を Core テストで再現し、キャッシュ整合の契約を固定した。MediaItemLengthTests へ4件追加: 調整だけではキャッシュが追随しないこと（再計算の必要性の根拠）、拡大（10秒→20秒でキャッシュ 300→600）、短縮（20秒→10秒で 600→300）、同長差し替え（調整なし・トリムとキャッシュ整合を保持）。いずれも確定後に `timeline.length == timeline.computeCurrentLength()` が成立することを確認する。残りは手動検証チェックリスト (8) で固定する。
- 対象外として触っていないもの: FE-R16-002（別プロジェクト切り替え後の非同期継続）。別単位へ移管済み。
- 検証: Mac（~/ymm4-work/fe-filepath/YMM4Mac）で Apps/DebugApp の `swift build` 成功。Core テストは方式名フィルタで実行し全合格（XCTest の Executed 件数で判定、AudioDrift 除外）: MediaItemLengthTests 24 件（Round 16 の回帰試験で +4）、PropertyMetadataTests 20 件、EffectPropertyMetadataTests 17 件（方式名の部分一致で併せて実行）、TimelineEditingTests 20 件、TimelineEditingLengthTests 29 件。合計 110 件、失敗 0。手動検証チェックリスト (8) の追加分は未実施（目視確認待ち）。

#### FE-PREVIEW — プレビュー連携（フロントエンド監査 FE-R1-014 / 015 / 020 / 022 / 023 / 024 / 031 / 037）

**main 統合時の訂正（2026-11-19、PR #125 の競合解消）**: 本単位は旧タイムライン（SwiftUI ジェスチャ方式）を起点に実装したため、FE-R1-020 の処分としてタイムラインのキーフレームマーカーのドラッグにもロックガードを足していた。しかし main 側のタイムライン再構築（PR #121）との統合時に本家の規則を再確認したところ、本家のタイムライン側にロックによるドラッグ排除は存在しない（`TimelineItemView.cs:866` の DecideMode にロック判定は無く、移動・リサイズ・キーフレームの各コマンドは CanExecute が常時 true）。`!IsLocked` の絞り込みが存在するのはプレビュー側（`TimelineVideoPlayer.cs` の当たり判定・コントロールポイント・ハンドル）だけである。したがって統合では再構築側の構造（マーカーは描画専用、操作は AppKit 層の DecideMode）を正とし、キーフレームマーカー側のロックガードは取り下げた。FE-R1-020 の CLOSED はプレビュー側の処分に基づくもので、この訂正はタイムライン側の外挿の撤回である。

台帳の行番号は Round 1 時点（6861438c）のコードに対するもので、その後バッチ1・スライダ・ファイル参照の変更が入っているため、8件すべてを現行コード（起点 9153e53）で再検証してから処分した。

**再検証結果の一覧。**

- FE-R1-014（レイヤー表示切替がプレビューに反映されない）: **成立**。Core の合成対象選定はレイヤー非表示を正しく参照している（`TimelineSource` の選定条件、`ItemPickers`）が、ラベル列の切替経路（`mutateLayerSetting` と直接書き換え2箇所）は `layerRevision` の更新だけで `onEdited()` を呼んでおらず、プレビュー再合成が要求されなかった。インスペクタ側のアイテム非表示は `onEdited` 経由で再合成されるため対象外。
- FE-R1-015（コントロールポイント表示3モードが実表示を制御していない）: **成立**。`controlPointVisibility` の状態はトランスポート帯のメニューで変わるだけで、操作層のどこからも参照されていなかった。本家の規則は逆コンパイル成果物で確認した: 設定は4値で Default は OnSelected へ解決され（YMMSettings.GetControlPointVisibility）、コントローラの描画は「選択中アイテム・非ロック・（OnSelected なら常時／OnMouseOverPreviewArea なら領域ホバー中）」の条件（TimelineVideoPlayer.cs:2471）、当たり判定は Never 以外でのみ行われる。
- FE-R1-020（ロックしたアイテムをプレビュー上で移動・変形できる）: **成立**。プレビューの当たり判定・移動ドラッグ・ハンドルにロック確認が一切無かった。本家はプレビューの当たり判定でコントローラ経路・本体経路とも `!IsLocked` で除外し、描画条件にも非ロックを含む（TimelineVideoPlayer.cs:614-631, 760-769, 2471）。
- FE-R1-022（プレビュー倍率が縦横比を崩す）: **成立**。表示枠の寸法は本家 PreviewViewModel の式（幅・高さ独立の Min）どおりだったが、合成画像をその枠へ引き伸ばしていたため、拡大時に片辺だけがクランプされると縦横比が崩れた。本家は映像を均一倍率（PreviewAreaZoom × PreviewDisplayZoom）で描き、枠を超える分は中心で切り抜く（TimelineVideoPlayer.GetVisibleVideoSize / CreatePreviewViewTransform）。
- FE-R1-023（当たり判定と選択枠が実映像の寸法に一致しない）: **成立するが要設計判断**。現行の `previewItemBounds` は種別ごとの比率（テキスト 60%×12%、その他 30%×30%）による近似で、実描画寸法ではない。本家は合成側が公開する実矩形（TimelineItemRects）を使うが、Mac 側 Core は「当たり判定用データの再構築は画像境界の問い合わせ（GPU 実行層）が要るためこの層では行わない」と記録済み（TimelineSource.swift の末尾コメント）で、実矩形の供給経路自体が無い。供給経路の新設は合成パイプラインの設計変更に当たるため、本単位では実装せず切り分ける。近似である旨は既存コードコメントに明記済み。
- FE-R1-024（プレビュー初期化失敗時に古い画像が残る）: **成立（狭い形）**。セッション切替時（resetPreview）と描画失敗時（onRenderFailed）は画像を消すようになっていたが、モデル初期化失敗時（onModelFailed）は理由文を入れるだけで旧モデルの画像を消しておらず、表示が画像優先のため失敗が見えなかった。
- FE-R1-031（プレビュー用モデル複製をメインスレッドで同期実行）: **前提変化・要設計判断**。構造自体は残る（`refreshPreviewModel` が `makeExportSnapshot`（JSON 往復）をメインスレッドで同期実行する）。ただしこれは Round 9 の設計相談で確定した「呼び出し側がスナップショットを作り、ワーカーはそれだけを読む」方式そのもので、100ms の間引きと遅延確定、失敗時の理由表示と再試行が入り、実プロジェクト（158 アイテム）での生成コスト約 28ms は実測として記録済み。スナップショット生成をメインスレッド外へ移すと編集モデルとの競合を避ける別の所有設計が要り、確定済み設計の変更に当たるため本単位では実装せず切り分ける。
- FE-R1-037（プレビュー合成の例外理由が失われる）: **成立**。`PreviewBox.render` が `composer.update` の例外を catch して nil を返すだけで、理由が診断にも表示にも残らなかった（表示側は「例外または出力なし」の一般文のみ）。

**処分（コミットは件ごと）。**

- FE-R1-014（350d96b）: ラベル列の表示切替の全経路（目ボタン、レイヤーメニュー、全レイヤー有効化、他レイヤー無効化、設定リセット、コンテキストメニューの切替）で `onEdited()` を呼ぶよう変更した。再合成要求は単一入口 `requestPreviewRender(modelChanged:)` へ集約される既存の形のまま。
- FE-R1-015（f87a84d）: 操作ハンドルの表示条件を `showsControlPoints` としてモードへ接続した（選択中のみ=常時／マウスオーバー時=プレビュー領域の `onHover` 状態／常に表示しない=出さない）。ハンドル自体がジェスチャを持つため、非表示は操作不可を兼ねる（本家も Never では当たり判定を行わない）。選択輪郭（破線）はコントロールポイントではなく選択の所在表示と解釈し、対象外とした（解釈をここに明記する）。なおアプリメニュー側のコントロールポイント表示ボタン（YMM4MacDebugApp.swift）は空アクションのまま別件（メニュー重複・未接続系）の範囲であり、本単位では触っていない。
- FE-R1-020（62c5991）: `hitTestPreviewItem` でロックしたアイテムを除外し（下のアイテムまたは空白として扱う）、選択中でもロックしたアイテムには操作ハンドルを出さず、タイムライン帯のキーフレームマーカードラッグもロック中は動かさないようにした。関連観測: コンテキストメニューの「移動」系操作はロック中でも実行できるが、本家のメニュー操作に対するロック規則を本単位では確認しておらず、監査への申し送りとして記録に留める（プレビューと直接操作は処分済み）。
- FE-R1-022（ae37801、補正 1 件）: PreviewCore に `PreviewLayout` を新設し、表示枠・描画寸法・均一倍率・座標変換の正本にした。プレビュー画像は均一倍率の実寸で描いて表示枠で切り抜き、選択輪郭・ハンドル・ドラッグ開始点の変換も同じレイアウトを通す（移動量の換算は従来どおり均一倍率で割るため不変）。拡大時のパン（表示中心の移動）は本家にあるが、Mac 側のドラッグはアイテム移動に割り当てられているため本単位では中心切り抜きまでとし、パンは未実装として明記する。
- FE-R1-024（db5fdc8）: `onModelFailed` で描画失敗時と同じく画像と表示中フレームの記録を消してから理由文を表示するよう変更した。
- FE-R1-037（16942ec）: `PreviewBox.render` の例外を、セッションの診断収集先へ種別 `previewComposition`（`PreviewBox.compositionFailureKind`）で記録するよう変更した。ワーカーが描画ごとの診断を表示側へ渡す既存経路に乗るため通知の形は変えていない。表示側は、その描画の診断に合成例外があれば理由文を `previewError` へ含める。

**検証。** Mac（~/ymm4-work/fe-preview/YMM4Mac）で Apps/DebugApp の `swift build` 成功（218 ステップ）。PreviewCore テストは方式名フィルタで実行し全合格（XCTest の Executed 件数で判定）: PreviewLayoutTests 4 件（フィット時に切り抜きなし、拡大時に縦横比を保って中心切り抜き、縮小時、座標変換の往復と中心対応）、PreviewRenderWorkerTests 8 件（既存、回帰なし）。Core テストの参考実行: TimelineEditingTests 20 件・TimelineEditingLengthTests 29 件、全合格（本単位でルートパッケージのソースは変更していない）。AudioDrift は対象外。

**監査 Round 18 の処分（FE-R18-001、P1）。** FE-R1-022 の数式（PreviewLayout）は本家と整合していたが、SwiftUI への適用側に欠陥が残っていた。`previewView` の内側 ZStack は拡大画像（表示枠より大きい）を直接の子に持ち、その報告寸法が後段の `.frame(表示枠寸法)`（既定は中央揃え）の中で中心合わせされ、内容全体が (枠−画像)/2 だけずれる。画像は `imageOrigin` の offset でさらに同量ずれるため、画像と操作層（輪郭・ハンドル・当たり判定）が互いにずれた。処分は PreviewLayout の数式を変えず、配置だけを直した: 表示枠を座標の正本とし、内側 ZStack の frame と `previewInteractionLayer` の frame の双方に `alignment: .topLeading` を明示した。これにより内容の寸法がどれだけ大きくても、両 frame の左上＝PreviewLayout の座標原点に内容の原点が一致し、内容の寸法は親のレイアウト寸法にも原点にも影響しない。操作層側の frame も同じ処分が必要なのは、その左上が名前付き座標空間 `previewArea` の原点であり、選択アイテムの描画寸法が表示枠を超えると（全画面アイテムの拡大表示など）輪郭・ハンドルだけがジェスチャ座標からずれていたため。ドラッグ変換（移動はヒットレイヤーのローカル座標、ハンドルは `previewArea`）と当たり判定（`videoPoint` 変換）の入力前提は、どちらも表示枠左上原点であり、描画側と一致することをコード上で確認した。検証: Mac（~/ymm4-work/fe-preview/YMM4Mac）で Apps/DebugApp の `swift build` 成功。PreviewCoreTests は PreviewLayoutTests 4 件・PreviewRenderWorkerTests 8 件、全合格（回帰なし）。配置そのものはアプリ層のため自動テストでは固定できず、手動検証チェックリスト (6)(7) で固定する。

**手動検証チェックリスト（未実施）。** (1) レイヤーの目ボタンで非表示にすると、プレビューからそのレイヤーのアイテムが消え、再表示で戻ること。再生中も停止への遷移で反映されること。(2) コントロールポイント表示を「常に表示しない」にすると選択中でもハンドルが出ず、「マウスオーバー時」ではプレビューへカーソルを入れたときだけハンドルが出ること。(3) ロックしたアイテムはプレビューでクリックしても選択・移動できず、下に別のアイテムがあればそちらが掴めること。タイムライン上でキーフレームマーカーをドラッグしても動かないこと。(4) プレビュー倍率 200%・400% で映像の縦横比が崩れず、中央が拡大表示されること。選択輪郭とハンドルが見えている映像の位置と一致すること。(5) 合成で例外が起きる条件では、プレビューに理由を含む失敗文が出て、診断タブの履歴にも previewComposition の記録が残ること。(6) 倍率 200% で全画面のアイテムを選択したとき、映像の中心が表示枠の中心にあり、選択輪郭が映像の見えている範囲と一致し、アイテムをドラッグすると掴んだ位置からずれずに動き始めること（FE-R18-001）。(7) 倍率 400% でも同様に、映像中心・選択輪郭・ハンドルの表示位置が一致し、ハンドルのドラッグ開始位置と表示位置がずれないこと（FE-R18-001）。

**未解決。** FE-R1-023（実描画矩形の供給経路の新設）と FE-R1-031（スナップショット生成の所有設計）は要設計判断として切り分け。拡大時のプレビューのパン、本家のコントローラ全種（エフェクト操作点・キーフレームマーカーのプレビュー表示）への対応は未実装。コンテキストメニュー操作に対するロック規則は本家確認待ちの申し送り。
#### FE-UNDO-CORE — フロントエンド基盤（Undo/Redo）の Core 側新設（IMPLEMENTED、Mac 検証済み）

フロントエンド監査 Round 2 の設計判断（FE-R2-DESIGN.md「Undo/Redo 基盤」）に基づき、履歴の土台だけを `Sources/YMM4Core/Editing/` へ新設した。アプリ層への接続と既存編集操作の移行は次単位で行う（本節の時点では参照元なし）。スナップショット方式は設計判断で不採用が確定しているため採っていない。

- **新設ファイル・型**: `EditCommand.swift`（`EditTargetKey`、`EditCommand` プロトコル、`ValueChangeCommand<Value: Equatable>`、`ActionEditCommand`）、`EditCommandCollector.swift`（`EditCommandCollector`、モジュール内）、`EditTransaction.swift`（`EditTransaction`）、`UndoHistory.swift`（`UndoHistory`）、`EditCoordinator.swift`（`EditCoordinator`）。
- **コマンドの表現（設計判断と根拠）**: 本家 `UndoRedoPropertyChangedCommand` は「対象インスタンス＋プロパティ名＋旧値/新値」を保持し、Undo/Redo 時にリフレクションで値を戻す。Mac 版 Core にはリフレクション相当が無く、既存の `PropertyAccess` も get/set クロージャ方式のため、対象の同一性は `EditTargetKey`（`ObjectIdentifier`＋プロパティ識別子）で表し、値の適用はコマンドの `apply` クロージャが担う形にした。対象が参照型（`BaseItem` はクラス）であることとも整合する。クロージャは対象を保持する（本家も対象インスタンスを保持する）。値で表せない変更（追加・削除等）は本家 `UndoRedoActionCommand` に対応する `ActionEditCommand`（Undo/Redo クロージャ対）で表す。
- **本家意味論の再現範囲**（逆コンパイル結果は仕様抽出の参照に留め、写経はしていない）: (1) コマンド収集時の統合 — 空コマンド（旧値=新値）の破棄、同一対象＋値の連鎖がつながる場合だけ統合（`CanConnect`/`Connect` 相当）、統合結果は収集の末尾へ移動、統合結果が空になれば除去（相殺）。(2) 実行順 — Undo は値変更コマンドを逆順→手続き型コマンドを逆順、Redo はその正順。(3) 履歴 — 確定済みトランザクションを1エントリとして蓄積、容量の既定100（本家 `UndoRedoLimit` 既定値）、超過時は最古を破棄、新規確定で Redo を破棄、実質的変更が無い確定はエントリを作らず Redo も破棄しない（本家の空の `Record()` 相当）、Undo/Redo 適用中の確定は記録しない（`isUndoRedoing` 相当の記録抑制）。
- **変更の捕捉は明示トランザクション方式**（本家の `UndoRedoable` 自動監視は模倣しない）: 変更の適用は呼び出し側が行い、`EditTransaction` へは適用済みの変更をコマンドとして登録する。確定で履歴1エントリ、キャンセルは登録済みコマンドの Undo で開始状態へ巻き戻す。ドラッグ型の逐次変更は収集時の統合により「開始値→最終値」の1エントリにまとまる。同時に有効なトランザクションは1つだけ（本家のコレクタが全体で1つであることに対応）とし、開始時に前のトランザクションが残っていればキャンセル（巻き戻し）して置き換える — 放棄されたドラッグ等で半端な変更を残さないための仕様。
- **EditCoordinator の範囲**: トランザクションの開始/確定/キャンセル、履歴への登録、Undo/Redo の実行、履歴変更通知の転送だけを統括する薄い層。編集操作の実体は既存の Core 編集操作の責務のまま。対象の実在検証（例: アイテムがタイムラインに残っているか）はアプリ接続の単位で意味を持つため、本単位では入れていない。
- **変更通知**: Core には一元的な変更通知の仕組みが無い（モデルの伝播は `Timeline.items` や `BaseItem.keyFrames` 等の `didSet` フックが担う）ため、履歴側の通知は `UserDictionaryStore.onSaveResult` の前例と同じクロージャ方式（`UndoHistory.onHistoryChanged`）とし、既存の仕組みと競合させない。
- **本家との意図的な差異**: (1) 本家の Undo/Redo は非同期コマンドを含むため非同期だが、Mac 版のコマンドは全て同期のため同期 API とした。(2) 本家は履歴が空の Undo/Redo を想定しないが、こちらは `false` を返して安全に倒す。(3) スレッド保護は行わない（モデル全体が UI スレッド前提の設計であることに合わせる。本家コレクタのロックは自動監視が複数経路から発火し得るためのもの）。

検証: Mac で新規テストを方式名フィルタで実行し全合格 — `EditCoordinatorTests` 10件（R2-U01 の往復、R2-U02 の逐次変更の1エントリ化、連鎖しない変更の非統合、統合コマンドの末尾移動と Undo/Redo 適用順、手続き型コマンドの実行順、相殺・同値変更の破棄、キャンセルの巻き戻し、開始による前トランザクションの置き換え、二重確定の無視）、`UndoHistoryTests` 8件（R2-U03 の容量3での最古破棄と既定容量100、R2-U04 の新規確定による Redo 破棄・適用中の記録抑制、無変更確定での Redo 保持、空履歴での false、全消去、履歴変更通知）。関連する既存テストも方式名フィルタで実行し全合格（PropertyMetadataTests 系34件、TimelineEditingTests 20件、いずれも失敗0）。全スイートは回していない。ARCHITECTURE.md は既存の処理経路・所有権に変更が無いため未更新（接続の単位で更新する）。

##### FE-UNDO-CORE R5 処分 — 監査 Round 5 指摘4件への対応（IMPLEMENTED、Mac 検証済み）

監査 Round 5（PR #119 レビュー）で、基盤の境界条件とライフサイクル管理に4件の指摘を受けた。いずれも本節の新設ファイル内での処分であり、アプリ層・既存編集操作への影響はない。

- **FE-R5-119-01（P1）未確定トランザクション中の Undo で履歴とモデルが乖離する**: `EditCoordinator.undo()` が `activeTransaction` を見ずに履歴の Undo を実行していた（A確定→B開始・未確定→Undo→B確定、の順で値と履歴が食い違う）。処分: (1) アクティブなトランザクションがある間は Coordinator の `undo()` / `redo()` を実行せず `false` を返す（排他）。(2) 履歴操作の入口を Coordinator へ一本化 — `UndoHistory.undo()` / `redo()` を `public` からモジュール内（internal）へ変更し、`record` と合わせてアプリ層からは Coordinator 経由でのみ操作できる形にした（テストは `@testable import` で従来どおり呼び出し可能）。回帰テスト `testUndoRedoAreBlockedDuringActiveTransaction`（A確定→B未確定で Undo/Redo が false・値と履歴が不変、B確定後に初めて Undo が効く）を追加。
- **FE-R5-119-02（P2）Undo/Redo の再入防止**: `UndoHistory.undo()` / `redo()` は適用中フラグを記録抑制にしか使っておらず、適用クロージャからの再入で別のエントリを取り出せた。処分: 両メソッドの入口で適用中なら `false` を返し、フラグの復帰は `defer` に集約（内側の呼び出しが外側のフラグを解除しない）。`EditCoordinator.cancel` も、巻き戻しの適用クロージャからの再入で再帰的な巻き戻しが起きないよう、コマンド実行前に `finish()` とアクティブ解除で終了状態を確定させてから `rollback()` する順序へ変更した。回帰テスト `testUndoReentryFromApplyClosureIsRejected`（適用クロージャ内からの Undo 試行が拒否され、外側の Undo/Redo が完了して履歴が壊れない）、`testCancelReentryDoesNotRecurse`（巻き戻し中の再キャンセル・新規開始でも巻き戻しは1回だけ）を追加。
- **FE-R5-119-03（P2）容量の不変条件**: `UndoHistory.capacity` は公開された stored プロパティで、`init` の `max(0, capacity)` 補正が後からの代入に効かず、負値だと切り詰め側（`excess = count - capacity`）で空配列への `removeFirst` が trap し得た。処分: 容量の実値を非公開ストレージ（`capacityStorage`）へ移し、公開アクセサの setter で代入の全経路に `max(0, …)` の検証を通す形にした。回帰テスト `testNegativeCapacityOnEmptyHistoryBehavesAsZero` / `testNegativeCapacityOnNonEmptyHistoryTrimsAll`（空・非空の両方で負の容量を指定しても trap せず容量0として振る舞う）を追加。
- **FE-R5-119-04（P2・契約変更）開始時の暗黙キャンセルを廃止**: 従来の `beginTransaction()` は既存のアクティブなトランザクションを巻き戻して置き換えていたが、「新しい編集要求が発生した」ことだけでは前の編集を破棄してよい根拠にならない（終了イベント未処理のドラッグ結果が黙って失われる）。処分: `beginTransaction()` の戻り値を `EditTransaction?` とし、アクティブな編集がある場合は新規開始を拒否して nil を返す契約へ変更。中断は `cancel`、確定は `commit` を呼び出し側が明示する。既存テスト `testBeginReplacesActiveTransactionWithRollback` は新契約の `testBeginIsRefusedWhileTransactionIsActive` へ書き換え（拒否・無巻き戻し・明示キャンセル後の再開始を確認）。契約変更の影響範囲は Core 内とテストのみ（アプリ層は未接続のため影響なし）。併せて、適用クロージャが対象を強参照する前提（`EditTargetKey` 自体は対象を保持しない）を `EditCommand.swift` の `EditTargetKey` ドキュメントへ接続側の契約として明記した。

R5 検証: Mac で方式名フィルタで実行し全合格 — `EditCoordinatorTests` 13件（従来10件のうち置き換え前提の1件を新契約へ書き換え、R5 回帰3件を追加）、`UndoHistoryTests` 10件（従来8件＋容量の回帰2件）。関連する既存テストも全合格（PropertyMetadataTests 系34件、TimelineEditingTests 20件、いずれも失敗0）。全スイートは回していない。ARCHITECTURE.md は処理経路・所有権に変更が無いため未更新。

##### FE-UNDO-CORE R6 処分 — 監査 Round 6 指摘2件への対応（IMPLEMENTED、Mac 検証済み）

監査 Round 6（PR #119 再レビュー）で、R5 処分の残存として再入・通知まわりの2件（いずれも P1）の指摘を受けた。いずれも本節の新設ファイル内での処分であり、アプリ層・既存編集操作への影響はない。

- **FE-R6-119-01（P1）キャンセル巻き戻し中の操作排他**: R5 処分の `cancel` は巻き戻し開始前に `finish()` とアクティブ解除で終了状態を確定させていたため、巻き戻し中は Undo の排他条件（有効なトランザクションの存在）が消えており、巻き戻し途中の適用クロージャから過去の履歴エントリの Undo が実行できて履歴とモデルが乖離した（レビュアーの再現条件: A確定で Frame 0→10、B開始で Frame 20・Length 2、Bキャンセルの Length 巻き戻し中に A を Undo すると、B の残りの巻き戻しが A の変更後の値へ復元してしまう）。巻き戻し中の `beginTransaction` も成功していた。処分: `EditCoordinator` に操作状態（`OperationState`: idle / editing / restoring）を導入して一元管理し、「編集中」と「復元処理中」を区別する形にした。`activeTransaction` は状態からの算出プロパティへ変更。`cancel` は巻き戻し中、状態を restoring に保持し（`defer` で idle へ復帰）、その間は開始（nil）・確定・キャンセル・Undo/Redo（false）を全て拒否する。場当たり的な個別ガードではなく、操作の可否を操作状態の1か所で判定する。回帰テスト `testCancelRollbackBlocksUndoAndBegin`（レビュアーの再現条件そのもの: 巻き戻し中の Undo・開始が拒否され、完了後は (Frame 10 / Length 1) へ戻り、A が Undo 可能な状態で履歴が整合）を追加。既存の `testCancelReentryDoesNotRecurse` は新契約に合わせて見直し（巻き戻し中の開始が nil を返すこと、完了後は通常どおり開始できることを確認）。
- **FE-R6-119-02（P1）履歴変更通知の発火時点で記録抑制が残っている**: `UndoHistory.undo()` / `redo()` は `isApplying = true` の後 `defer` で関数終了時に復帰させていたため、`onHistoryChanged` の発火時点でも抑制が有効なままだった。通知クロージャから新しい編集を確定させると、`record` の `guard !isApplying` で履歴登録だけが黙って破棄され、モデルへの変更は残るのに Undo できない変更が生まれていた。本家 `UndoRedoManager` は `isUndoRedoing` を false へ戻してから `HistoryChanged` を発火させる（レビュアーが再照合済み）ため、本家とも異なる挙動だった。処分: 記録抑制の範囲をコマンドの適用中だけに限定する。適用部分を `applySuppressingRecording`（適用スコープ内でのみ `isApplying` を立て、`defer` で解除）へ切り出し、スタック更新を終え・抑制を解除してから `onHistoryChanged` を発火させる順序へ変更した（`undo` / `redo` とも）。適用中の記録抑制そのもの（R2-U04）は維持される。回帰テスト `testEditCommittedFromHistoryChangedNotificationIsRecorded`（Undo の通知の中から新しい編集を確定させ、その編集が履歴に登録され Undo 可能であること）を追加。

R6 検証: Mac で方式名フィルタで実行し全合格 — `EditCoordinatorTests` 15件（従来13件＋R6 回帰2件、`testCancelReentryDoesNotRecurse` は新契約へ見直し）、`UndoHistoryTests` 10件。関連する既存テストも全合格（PropertyMetadataTests 系34件、TimelineEditingTests 20件、いずれも失敗0）。全スイートは回していない。ARCHITECTURE.md は処理経路・所有権に変更が無いため未更新。
