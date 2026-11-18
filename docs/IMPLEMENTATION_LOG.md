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
- 構造整理 W2〜W10 の記録は各 PR が正本（W2 = #68、W3 = #67、W4 = #72、W5 = #73、W6 = #74、W8 = #75、W7 = #76、W9 = #77、W10 = #78）

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
