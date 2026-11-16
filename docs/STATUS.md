# Mac版開発の進捗・課題

更新: 2026-11-16。基準: リポジトリの初期化段階。

| 項目 | 状態 | 根拠 |
|---|---|---|
| Privateの開発リポジトリ `yanikasumin/ymm4mac` | VERIFIED | GitHubで存在と可視性を確認 |
| README・作業規則・設計／実装／引継ぎ文書 | IMPLEMENTED | 本リポジトリに保存 |
| 要件定義への参照 | IMPLEMENTED | 解析repo内のREQUIREMENTSへのリンク |
| Macネイティブアプリのコード | **NOT STARTED / 未確認** | 初期段階で実装コードなし |
| Windows本家とMac版の互換テスト | NOT STARTED | 比較対象のMac版実装なし |
| 技術選定、GPU、UI、Audio、Export | PROPOSED | 解析repoの設計案のみ |

## 次の優先課題

1. 解析側の要件定義v0.1はマージ済みだが文書が未承認表記のため、ユーザーによる正式な扱いを確認する。黙ってv1.0に変更しない。
2. 本家の編集ドメイン（C#）の移植可能性とWPF／Direct2Dの依存境界をコードから調べる。
3. 本家とMacのGolden Master比較素材を整備する。
4. UI技術・描画バックエンドは採用前に最小限の実証と比較試験を行う。
5. 実装が始まったら変更と同時にAs-built・実装台帳・課題・引継ぎ文書を更新する。

**非対象**: `yanikasumin/YMM4M-custom` はWineベースの既存互換環境であり、本ネイティブ移植の開発進捗に算入しない。
