# ymm4mac の実装済みアーキテクチャ

更新: 2026-11-16。状態: **モデル層と .ymmp 互換層まで実装済み。描画・音声・UI は未実装。**

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
        KeyFrames.swift        アイテム単位で共有されるキーフレーム位置（分割用の一括削除を含む）
        Animation.swift        数値プロパティの時間変化と値評価（本家 GetValue の全分岐、分割連動を含む）
        Easing.swift           イージング全科（In 素関数＋端点ラッパー＋モード合成）
        Cubic.swift            スプライン補間の重みカーネル（本家 Cubic）
        StatelessRandom.swift  キー列からの決定的乱数生成（本家 StatelessRandom）
        BezierAnimation.swift  ベジェ補間の定義と Newton 法による評価
        JSONValue.swift        順序・数値リテラルを保持する JSON 値と自前パーサ／シリアライザ
        HonkeFormat.swift      TimeSpanValue（tick 保持、"c" 形式）、色の文字列形式、
                               RenamedTypeResolver、PreservedObject、AnimationType のメンバ名対応
        Enums.swift            Blend / WordWrap / Style / BasePoint 等の列挙（未知の名前は保持）
        PlaybackRateMap.swift  再生速度の積分テーブル（分割時の素材時刻計算）
        CodecSupport.swift     互換層の内部共通処理（Animation 等の JSON 形状変換）
        Character.swift        キャラクター（型付きは4プロパティ、残りは追加フィールドで保持）
        Project.swift          プロジェクト（Timelines / Characters / ToolStates 等）
        Timeline.swift         タイムライン（Length / MaxLayer はキャッシュ済み派生値）
        TimelineSupport.swift  LayerSetting(s)、TimelineVerticalLine、SerializableToolState
        TimelineEditing.swift  編集操作（追加・衝突解決・移動・分割・ChangeFrameRate・削除）
        YmmpCodec.swift        .ymmp の読み込み・保存（$type 解決、型移行、診断記録）
        Items/
          BaseItem.swift       BaseItem / VisualItem（アニメーション文脈の伝播、分割）
          MediaItems.swift     AudioItem / VideoItem / ImageItem
          TextItems.swift      TextItem / VoiceItem / TextDecoration / TextAppearance
          CompositeItems.swift Shape / Effect / Group / Scene / FrameBuffer /
                               Tachie / TachieFace / Transition の各アイテム
      Tests/YMM4CoreTests/     上記のユニットテスト（87件）
      docs/ARCHITECTURE.md     本文書
      docs/IMPLEMENTATION_LOG.md
      docs/STATUS.md
      docs/HANDOFF.md
      .github/pull_request_template.md
      .gitignore

## データフロー（実装済みの範囲）

- 読み込み: .ymmp テキスト → `JSONParser`（順序・数値リテラル保持）→ `YmmpCodec.decode` が $type を解決して `Project` / `Timeline` / アイテム13クラスを構築。未知の $type のアイテムは読み飛ばして診断情報へ記録し、未知のプロパティは各モデルの `additionalFields` に保持する。プラグイン型の値（エフェクト等）は `PreservedObject` として生 JSON のまま保持する。
- 編集: `Timeline` の編集操作（TimelineEditing.swift）がアイテム（参照型）を直接書き換える。本家の意味論どおり、前処理は入力を書き換え、原子的保証はコミット段階のみ。`Timeline.Length` / `MaxLayer` はキャッシュとして保守される。
- 保存: `YmmpCodec.encode` がモデルを追加フィールドごと JSON 化（1行）→ 一時ファイルへ書き出し → 再読込で検証 → 本ファイルへコピー。
- アイテムの複製は JSON 往復（本家 GetClone と同じ経路）で、`BaseItem.cloned()` が担う。分割はこの複製を左右に作ってから行う。

**描画・音声・書き出し・UI は未実装。** 詳細は実装台帳 MAC-0001〜MAC-0005。

## 実装後の書き方

- 実際のファイル構造と、利用者操作→編集モデル→映像／音声→表示・書き出しの呼び出しを木構造・自然言語で更新する。
- 各機能についてファイル・クラス・関数、責務、依存、I/O型、データフロー、所有権、スレッド、キャッシュ、例外処理を記述する。
- [IMPLEMENTATION_LOG](IMPLEMENTATION_LOG.md)の変更IDを参照し、本家の対象クラスと置換理由を明記する。
- 各コミットの実装・検証状況（IMPLEMENTED/VERIFIED/UNKNOWN）を区別し、単なる技術案をAs-builtに転記しない。
