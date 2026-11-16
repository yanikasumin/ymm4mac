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
