# 実装台帳 — 何を・どこに・どう実装したか

2026-11-16現在、**ドキュメントの初期構築のみ**。動画編集機能の実装履歴はない。

## 実装記録（変更IDごとに自然言語で追記）

### DOC-0001 — 開発リポジトリの初期化

- 目的: 解析リポジトリからMac版ソースと実装記録を分離し、中断しても他の担当が引き継げる入口を設ける。
- 変更先: `yanikasumin/ymm4mac` の `README.md`, `AGENTS.md`, `docs/`, `.github/pull_request_template.md`, `.gitignore`。
- 実装: コードは追加していない。解析repoの要件・本家設計・互換マトリクスへリンクを設け、設計と実体、確認済みと仮説を分ける。実装が始まればここへ機能ごとに追記する。
- 本家との差分: 動画編集の動作への変更なし。開発運用の文書のみ。
- 検証: GitHub上のファイル存在を確認する。ビルドや映像処理のテストは**未実施**。
- 承認: 要件変更は行っていない。

### MAC-0001 — モデル層の土台: VideoInfo と Animation（IMPLEMENTED）

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

### MAC-0002 — Animation 評価の数式置き換え（IMPLEMENTED）

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

### MAC-0003 — ドメインモデル: Project / Timeline / アイテム13クラス（IMPLEMENTED）

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

### MAC-0004 — 編集操作: 追加・衝突解決・グループ移動・分割・ChangeFrameRate・削除（IMPLEMENTED）

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

### MAC-0005 — .ymmp 互換層（IMPLEMENTED）

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

※実装を伴う変更は、その同じ作業で `ARCHITECTURE`、`STATUS`、`HANDOFF` と解析側のAs-built・互換マトリクスを整合させる。
