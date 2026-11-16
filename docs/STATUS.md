# Mac版開発の進捗・課題

更新: 2026-11-16。基準: リポジトリの初期化段階。

| 項目 | 状態 | 根拠 |
|---|---|---|
| Publicの開発リポジトリ `yanikasumin/ymm4mac` | VERIFIED | GitHubでPublic設定を確認（2026-11-16にオーナーが変更）。解析リポジトリもPublic |
| README・作業規則・設計／実装／引継ぎ文書 | IMPLEMENTED | 本リポジトリに保存 |
| 要件定義v1.0への参照 | VERIFIED | オーナー承認済みのv1.0が正式発効。解析repoの[PR #2](https://github.com/yanikasumin/ymm4-native-research/pull/2)がマージ済み |
| Macネイティブアプリのコード | **NOT STARTED / 未確認** | 初期段階で実装コードなし |
| Windows本家とMac版の互換テスト | NOT STARTED | 比較対象のMac版実装なし |
| 技術選定、GPU、UI、Audio、Export | PROPOSED | 解析repoの設計案のみ |

## 次の優先課題

1. **要件定義v1.0を正式な開発基準として適用する。** 初版の承認はMuse経由の伝達で記録済み。新たな変更・例外実装は本人の事前承認を要する。
2. [6境界の本家解析](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/11-RENDERING-OWNERSHIP-BOUNDARIES.md)を踏まえ、ChatGPTから実装仕様の提示を受ける。C#／Swiftや描画方式は未決定。
3. 本家とMacのGolden Master比較素材を整備する。
4. UI技術・描画バックエンドは採用前に最小限の実証と比較試験を行う。
5. 実装が始まったら変更と同時にAs-built・実装台帳・課題・引継ぎ文書を更新する。

**非対象**: `yanikasumin/YMM4M-custom` はWineベースの既存互換環境であり、本ネイティブ移植の開発進捗に算入しない。
