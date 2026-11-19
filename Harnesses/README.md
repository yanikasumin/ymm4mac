# 検証ハーネス

Mac 実機（Apple Silicon / macOS 26）で GPU 合成経路を画素レベルで検証する
小規模プログラム群。各ハーネスは独立した SwiftPM パッケージで、
リポジトリルートのパッケージ（YMM4Core / YMM4GPU）を相対パス `../..` で
参照する。製品コードではないため、ルートパッケージのターゲットには含めない。

W1（構造整理、2026-11-18）で、作業領域に散らばっていたものを
再現可能な資産としてここへ取り込んだ。取り込み前は依存パスが検証用
コピーの絶対パスを指していたため、置き場所が変わると動かなかった。

## 実行方法

各ハーネスとも、フォルダ内でビルドして実行する。

```sh
cd Harnesses/mac0028-harness
swift run -c release
```

標準出力に `PASS: <項目>` / `FAIL: <項目>` を1行ずつ出し、
失敗があれば終了コードが非0になる（mac0031 を除く。下表参照）。
期待値は各 main.swift の冒頭コメントと、docs/IMPLEMENTATION_LOG.md の
対応する実装記録（MAC 番号）に根拠がある。

## 一覧

| ハーネス | 検証対象 | 実行方法の差異 | 期待値（取り込み時点の実績） |
|---|---|---|---|
| mac0023-harness | GPU エフェクト Metal 処理器 第1段（10種）。解析的に導いた期待値と画素を照合 | 引数なし | 25 件全 PASS |
| mac0025-harness | 実素材 Source（動画・シーン・FrameBuffer・立絵） | 引数なし。動画素材は実行時に生成 | 18 件全 PASS |
| mac0026-harness | 書き出し接続（合成→NV12 変換、実ミックス→ラウドネス→Dynamics、ExportSession と FFmpegProcessWriter のプロセス駆動） | `swift run -c release -- <作業ディレクトリ> <スタブ ffmpeg のパス>`。スタブは同梱の `ffmpeg-stub.sh`（引数と stdin を記録する） | 実行された確認 19 件全 PASS。実 ffmpeg での実エンコード確認はハーネスの対象外（実装記録参照） |
| mac0027-harness | 合成グループ（Composite GroupItem Source） | 引数なし | 15 件全 PASS |
| mac0028-harness | GPU エフェクト Metal 処理器 第2段（31種）と内部合成器への供給元の伝播。上下反転の回帰確認を含む | 引数なし | 90 件全 PASS |
| mac0031-harness | 実ファイルのテキスト描画（文字分割）の切り分け診断。段階別に PNG と行ごとの不透明量プロファイルを出す | `swift run -c release -- <ymmp のパス> <フレーム> [出力先]`。PASS/FAIL 形式ではない診断型 | 分割文字ごとの形状一致 IoU = 1.000（実績） |
| mac0033-harness | GPU テクスチャ確保失敗が素通しと区別され MetalRenderError として伝播すること（GPU28-03） | 引数なし。失敗ケースは環境変数 `MAC0033_RUN_FAILURE_CASE=1` のときだけ実行し、既定では SKIP と表示する | 通常ケース PASS。失敗ケースは macOS 26 の Metal 検証層がプロセスを abort するため完走しない（既知の制約。throw 経路の担保はコード監査に拠る） |
| mac0034-harness | EffectItem 描画（本家 EffectSource）とクリッピングのアルファマスク | 引数なし | 25 件全 PASS |
| mac0035-harness | 画面遷移（TransitionSource の配線、ブレンド9種のうち8種） | 引数なし | 27 件全 PASS |
| media4950-harness | Issue #49（PngWav ライター）/ #50（Metal 初期化診断）。初期化失敗の人為的誘発（壊れたシェーダ・関数不足）と理由文の確認、実合成経路からの FFmpeg / PngWav 書き出し（30 フレーム、WAV 1 秒、PNG の ImageIO デコード） | 引数なし（出力先は任意で第1引数）。実 ffmpeg が /opt/homebrew/bin/ffmpeg に必要 | 11 件全 PASS |
| stream54-harness | PCM 供給のストリーミング化（Issue #54）: 1 時間 WAV の全量読み切り・全サンプル照合・常駐メモリ実測・終端付近シーク着地 | 引数なし（素材は一時ディレクトリへ生成） | 全 PASS（読み切り 0.87 秒、メモリ増加 約19MiB。2026-11-18 実測） |
| brush46-harness | ブラシ基盤（BRUSH46）: 型付きブラシの GPU 塗りを4エフェクトと図形へ適用し、本家幾何から手計算した期待値と画素を照合。未対応ブラシの素通し回帰を含む | 引数なし。ビットマップブラシ用タイルは実行時に生成 | 42 件全 PASS |
| transform47-harness | 変形・不透明度つき入力に対する共通規則（Issue #47）: 自作 Source で非プレーンな入力を連鎖へ流し、エフェクトが効くことと実体化カウンタの発動を検証。`--measure <ymmp パス>` で実プロジェクトでの発動頻度を測定する診断モードも持つ | 引数なし / `--measure <ymmp パス>` | 13 件全 PASS。測定モードは upload.ymmp / upload-2.ymmp とも発動 0 回 |
| trim55-harness | 提示タイムスタンプとトリム（Issue #55）: 提示開始オフセット・AAC 遅延・MP3 素材での音の開始位置とシーク着地の実測（harness）、資産・セグメント・提示時刻の診断（diag）、映像の提示区間とフレーム内容の診断（vdiag） | `harness <素材パス>`、`diag <素材パス> [シーク秒 [着地秒]]`、`vdiag <動画パス>`。素材は ffmpeg で別途生成（台帳 TRIM55 参照） | 5 素材すべて本家の意味論と一致（2026-11-18 実測） |
| noise7-harness | Noise 生成器の全10種（新規7種 Block / Perlin / Cellular / Voronoi / Simplex / Marble / Flow と既存3種 Fractal / Random / Curl）の計52ケースを MetalNoiseProcessor 経由で描画し、画素バイト列を標準出力へ出す（PASS/FAIL 形式ではないダンプ型） | 引数なし。出力と同梱の期待値（refs/）の比較は `python3 compare.py <出力ファイル>`（全ケース最大差 0 でなければ非 0 終了） | 52ケース中50ケースでバイト完全一致（2026-11-18 実測）。残る vor-cell / vor-manh-cell は各1画素だけ最大差 1（期待値生成インタプリタの境界丸め差。詳細は docs/IMPLEMENTATION_LOG.md の NOISE7 節と NOISEFIX 節）。期待値は本家シェーダの DXBC を実行するインタプリタの出力を凍結したもの |
| halftone104-harness | HalfTone（Issue #104）: 菱形・矩形・三角（2形状）の4ケースを MetalHalfToneShadowProcessor 経由で描画し、全画素を CSV で /tmp/ht104/ へ出す（ダンプ型） | 引数なし。比較は `python3 compare.py /tmp/ht104`（許容差: 菱形・矩形 0、三角 2） | 菱形・矩形はバイト完全一致、三角は最大差 2（部分被覆の縁画素のみ。2026-11-19 実測）。期待値は修正済み DXBC インタプリタの出力を凍結したもの。詳細は docs/IMPLEMENTATION_LOG.md の HT104 節 |
| snapshot031-harness | FE-R1-031 の計測専用: プレビュー用スナップショット生成（makeExportSnapshot）の内訳（エンコード / デコード＋参照再解決 / 合計）と、PreviewRenderWorker へのモデル差し替え往復を規模3種・冷間/温間で実測し、JSONL へ記録する（PASS/FAIL 形式ではない計測型）。detail モードは最適化・第一段階用にエンコード（ツリー構築 / 文字列化）とデコード（解析 / 構築＋再解決）を分離計測し、spin モードは `sample` によるホットスポット特定用 | `harness breakdown <ymmp> <label> <out.jsonl> <反復数>` / `harness cold-total <ymmp> <label> <out.jsonl>` / `harness worker <ymmp> <label> <out.jsonl> <描画反復> <差し替え反復> <連鎖反復>` / `harness detail <ymmp> <label> <out.jsonl> <反復数> <phase>` / `harness spin <ymmp> <秒数>`。集計は `python3 aggregate.py`。実プロジェクトと合成大規模プロジェクトはリポジトリ外に置く | 計測結果は results/snapshot031.jsonl（FE-R1-031-MEASURE）と results/codec-detail.jsonl（最適化・第一段階）と docs/IMPLEMENTATION_LOG.md の FE-R1-031 節 |

## 材料について

- 画素検証の入力は、原則としてコード内で生成する既知パターン
  （mac0023 / mac0025 / mac0027 / mac0028 / mac0034 / mac0035）。
  外部ファイルは不要。
- mac0031 だけは実プロジェクトファイル（.ymmp）を入力に取る。
  実ファイルには絶対パスが含まれるためリポジトリには同梱しない。
  実行時に手元のファイルを指定すること。
- mac0026 のスタブ ffmpeg は同梱している。実エンコードの確認には
  別途 ffmpeg の実物が要る。スタブは直接実行されるため実行権限が
  要るが、リポジトリ上は通常ファイルとして登録されている。
  クローン直後は `chmod +x Harnesses/mac0026-harness/ffmpeg-stub.sh`
  を一度実行すること。
