# ymm4mac の実装済みアーキテクチャ

更新: 2026-11-16。状態: **プロジェクト初期化のみ。アプリ実装は未確認。**

この文書は **実装されている構造のみ記載するAs-built**。計画・仮説は[解析側のMac設計案](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/02-MAC-DESIGN-PROPOSAL.md)に記載。

## 現状の実体

    ymm4mac/
      README.md                開発目的・関連資料
      AGENTS.md                作業者向けの規則
      Package.swift            Swift パッケージ定義（YMM4Core ライブラリ + テスト）
      Sources/YMM4Core/        モデル層（Foundation のみ）
        Color.swift            ARGB 8bit の色値
        FrameTime.swift        フレーム⇔時間換算
        VideoInfo.swift        解像度・FPS・サンプリングレート
        AnimationType.swift    補間・イージング種別の数値テーブルと分類規則
        KeyFrames.swift        アイテム単位で共有されるキーフレーム位置
        Animation.swift        数値プロパティの時間変化と値評価（本家 GetValue の全分岐）
        Easing.swift           イージング全科（In 素関数＋端点ラッパー＋モード合成）
        Cubic.swift            スプライン補間の重みカーネル（本家 Cubic）
        StatelessRandom.swift  キー列からの決定的乱数生成（本家 StatelessRandom）
        BezierAnimation.swift  ベジェ補間の定義と Newton 法による評価
      Tests/YMM4CoreTests/     上記のユニットテスト
      docs/ARCHITECTURE.md     本文書
      docs/IMPLEMENTATION_LOG.md
      docs/STATUS.md
      docs/HANDOFF.md
      .github/pull_request_template.md
      .gitignore

**実装済みはモデル層の土台（VideoInfo と Animation）のみ。動画編集アプリの映像処理、音声処理、UI は未実装。** 詳細は実装台帳 MAC-0001・MAC-0002。

## 実装後の書き方

- 実際のファイル構造と、利用者操作→編集モデル→映像／音声→表示・書き出しの呼び出しを木構造・自然言語で更新する。
- 各機能についてファイル・クラス・関数、責務、依存、I/O型、データフロー、所有権、スレッド、キャッシュ、例外処理を記述する。
- [IMPLEMENTATION_LOG](IMPLEMENTATION_LOG.md)の変更IDを参照し、本家の対象クラスと置換理由を明記する。
- 各コミットの実装・検証状況（IMPLEMENTED/VERIFIED/UNKNOWN）を区別し、単なる技術案をAs-builtに転記しない。
