# Mac版開発の進捗・課題

更新: 2026-11-16。基準: モデル層と .ymmp 互換層の実装完了（MAC-0005）＋デバッグ用アプリの殻（MAC-0006）時点。

| 項目 | 状態 | 根拠 |
|---|---|---|
| Publicの開発リポジトリ `yanikasumin/ymm4mac` | VERIFIED | GitHubでPublic設定を確認（2026-11-16にオーナーが変更）。解析リポジトリもPublic |
| README・作業規則・設計／実装／引継ぎ文書 | IMPLEMENTED | 本リポジトリに保存 |
| 要件定義v1.0への参照 | VERIFIED | オーナー承認済みのv1.0が正式発効。解析repoの[PR #2](https://github.com/yanikasumin/ymm4-native-research/pull/2)がマージ済み |
| Macネイティブアプリのコード | **モデル層＋.ymmp 互換層まで IMPLEMENTED** | `Sources/YMM4Core/` に VideoInfo・Animation 評価（MAC-0001・0002）に加え、Project / Timeline / アイテム13クラスのドメインモデル（MAC-0003）、編集操作一式（MAC-0004）、.ymmp 互換層（MAC-0005）を実装。Linux 上の Swift 6.1.2 で `swift test` 全87件合格（2026-11-16）。UI・描画・音声・書き出しは未着手。本家実機との比較試験（実ファイルの往復・Golden Master）は未実施であり VERIFIED ではない。ランダム移動の乱数列は本家 `GetHashCode()` との対応付けが未確定。フォント既定値（Texts.DefaultFont）とタイムライン名のリソース文字列は未確定 |
| デバッグ用アプリ（検証の殻） | IMPLEMENTED（macOS ビルド未実施） | `Apps/DebugApp/` に独立 SwiftPM パッケージとして用意（MAC-0006）。実 .ymmp を開いて中身・読み込み診断・往復固定点を確認できる。製品 UI ではない。この VM では SwiftUI をビルドできないため、初回ビルド確認は本人の Mac で行う |
| Windows本家とMac版の互換テスト | NOT STARTED | 実ファイルの往復検証はフィクスチャ採取待ち |
| 技術選定、GPU、UI、Audio、Export | PROPOSED | 解析repoの設計案のみ |

## 次の優先課題

1. **要件定義v1.0を正式な開発基準として適用する。** 初版の承認はMuse経由の伝達で記録済み。新たな変更・例外実装は本人の事前承認を要する。
2. [6境界の本家解析](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/11-RENDERING-OWNERSHIP-BOUNDARIES.md)を踏まえ、ChatGPTから実装仕様の提示を受ける。C#／Swiftや描画方式は未決定。
3. 本家とMacのGolden Master比較素材を整備する。
4. UI技術・描画バックエンドは採用前に最小限の実証と比較試験を行う。
5. 実装が始まったら変更と同時にAs-built・実装台帳・課題・引継ぎ文書を更新する。

**非対象**: `yanikasumin/YMM4M-custom` はWineベースの既存互換環境であり、本ネイティブ移植の開発進捗に算入しない。
