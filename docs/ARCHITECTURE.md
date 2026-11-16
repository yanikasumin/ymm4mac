# ymm4mac の実装済みアーキテクチャ

更新: 2026-11-17。状態: **モデル層と .ymmp 互換層に加え、描画層の土台と合成の実行部、GPU 実行器（Metal）と基本 Source（画像・図形）、音声パイプラインの芯まで実装済み。テキスト描画・個別エフェクト・動画デコード・製品 UI は未実装（音声のデコード実体・ユーザー音声エフェクト・再生／書き出し接続も未実装）。**

この文書は **実装されている構造のみ記載するAs-built**。計画・仮説は[解析側のMac設計案](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/02-MAC-DESIGN-PROPOSAL.md)に記載。

## 現状の実体

    ymm4mac/
      README.md                開発目的・関連資料
      AGENTS.md                作業者向けの規則
      Package.swift            Swift パッケージ定義（YMM4Core / YMM4GPU ライブラリ + テスト）
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
        Character.swift        キャラクター（全プロパティ型付き。KeyGesture / VoiceDescription を含む）
        ShapeParameter.swift   図形パラメータ（RectangleShapeParameter と Brush を型付き、
                               それ以外の $type は生保持。旧 ShapeType の変換表を含む）
        Project.swift          プロジェクト（Timelines / Characters / ToolStates 等）
        Timeline.swift         タイムライン（Length / MaxLayer はキャッシュ済み派生値）
        TimelineSupport.swift  LayerSetting(s)、TimelineVerticalLine、SerializableToolState
        TimelineEditing.swift  編集操作（追加・衝突解決・移動・分割・ChangeFrameRate・削除・
                               空間を詰める削除の一族）
        YmmpCodec.swift        .ymmp の読み込み・保存（$type 解決、型移行、診断記録）
        Items/
          BaseItem.swift       BaseItem / VisualItem / VideoItemProperties
                               （アニメーション文脈の伝播、分割。本家 IVideoItem の
                               映像プロパティ一式で、適合は VisualItem 系譜 +
                               VoiceItem + TransitionItem）
          MediaItems.swift     AudioItem / VideoItem / ImageItem
          TextItems.swift      TextItem / VoiceItem / TextDecoration / TextAppearance
          CompositeItems.swift Shape / Effect / Group / Scene / FrameBuffer /
                               Tachie / TachieFace / Transition の各アイテム
        Rendering/             描画層の土台（Foundation のみ。GPU 実行は含まない）
          Geometry.swift       Vector2 / Vector3 / Matrix4x4 / RectF
                               （System.Numerics 互換の行優先・行ベクトル規約）
          ImageReference.swift 描画グラフへの不透明な参照（本家 ID2D1Image の置換）
          DrawDescription.swift 描画変換の値型、VideoController 等の操作点
          SourceDescriptions.swift 更新の説明レコード（Timeline / Item / Effect）、
                               FramePosition、TimelineSourceUsage、SceneInfo
          Source.swift         Source / SourceOutput / DrawingEffectProcessor /
                               FrameBufferSource の各プロトコル、StandardSourceOutput
          ItemPickers.swift    アイテム選択（全体／グループ／トランジション）、FaceItem
          DrawOrdering.swift   描画順序（3キー）、ZIndex、四隅算出、セグメント構築
                               （BSP は PlaneSplitOrdering の差し替え点）
          EffectedItemSource.swift 合成の実行部（アイテム単位）: エフェクト連鎖の
                               処理器・定義・組と供給元、描画先の抽象
                               （RenderTarget / Factory）、アルファマスクの境界、
                               EffectedOutput / EffectedItemSource
          TimelineSource.swift 合成の実行部（タイムライン単位）: TimelineScene、
                               TimelineGroupResolver（グループ階層の解決）、
                               TimelineComposer（資源管理・親エフェクト再構築・
                               FrameBuffer 境界・合成の統合）
        Audio/                 音声パイプラインの芯（Foundation のみ。MAC-0013）
          AudioStream.swift    AudioStream（本家 AudioStreamBase のプルモデル基盤）、
                               InputFrameWindow（範囲外は無音のランダムアクセス窓）
          PCMProvider.swift    PCMProvider / PCMProviderFactory（デコードの差し替え点）、
                               InMemoryPCMProvider、FileAudioStream
          EffectedAudioItemSource.swift アイテム音声の処理器連鎖（本家のチェーン順序）、
                               AudioItemProperties、AudioEffectProvider（ユーザー
                               音声エフェクトの差し替え点）、AudioSourceFactory
          AudioEffectProcessors.swift NegativeSeekable / ContentOffset / Loop /
                               Reverse / Echo の各処理器と基底
          AudioResampling.swift Resampler / PlaybackRate / VariablePlaybackRate /
                               Upsampler（補間カーネルは Linear / Cubic）
          VolumePanStream.swift VolumePan（サンプル対ごとの Animation 評価）
          AudioGroups.swift    AudioGroupResolver（グループ境界の区間分割と
                               DirectGroups / Owner の算出）、GroupAudioBusSource
          TimelineAudioMixer.swift タイムライン全体のミックス（レイヤー音量適用、
                               float 加算、リミッターなし）
      Sources/YMM4GPU/         GPU 実行層（Metal。全ソース #if os(macOS)、Linux では空）
        MetalGraphics.swift    MetalGraphicsDevices（デバイス共有・登録表・共有資源）、
                               MetalImage（ImageReference の実体）、
                               MetalGraphicsContext（消費者ごとの文脈・描画先工場）、
                               シェーダ一式、CGImage 読み戻し
        MetalRenderTarget.swift RenderTarget の Metal 実装（画面サイズのテクスチャ、
                               記録の畳み込みと close() での同期実行）
        MetalDrawingEffect.swift DrawingEffect の Metal 実装（変換の遅延記録、
                               PlaneSplitGeometryProviding を兼ねる）
        MetalSources.swift     MetalImageSource（画像）、MetalShapeSource（図形）、
                               MetalEmptySource（未対応種別の透明）、MetalSourceProvider
      Apps/DebugApp/           検証用デバッグアプリ（読み込み診断・往復チェック・
                               合成プレビュー。製品 UI ではない）
      Tests/YMM4CoreTests/     上記のユニットテスト（214件）
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
- 描画（実行部まで）: `TimelineComposer.update` が `ItemPicker.pickItems` でフレーム時点の対象アイテムを選定し、資源管理（範囲外の破棄・不足分の生成）と親エフェクトの再構築（顔・声解決→グループ解決）を行う → FrameBuffer 以外の各 `EffectedItemSource` が Source を更新し、`EffectedOutput` の連鎖（処理器の位置基準の再利用・差し替え）＋アイテム変換で DrawDescription を確定 → `DrawOrdering.ordered` が3キーで順序付け → `DrawSegmentBuilder` のセグメント列に従い、抽象描画先（RenderTarget）へ合成する。FrameBuffer アイテムでは描画先を閉じて Source へ渡し、新しい描画先で合成を続ける。
- 描画（GPU 実行）: 描画先・DrawingEffect・基本 Source の実物は `Sources/YMM4GPU/`（Metal）。`MetalGraphicsDevices` がデバイスと ImageReference の登録表を所有し、`MetalGraphicsContext`（消費者ごとに生成）が描画先を供給する。DrawingEffect は中間テクスチャを作らず、入力実体へ変換（ズーム×ワールド×透視）と不透明度を記録した実体を出力として登録する（遅延評価）。描画先は画面サイズのテクスチャを実体とし、記録した描画を close() で同期実行する。Source の実物は画像（ImageIO デコード）と図形（SDF 描画）のみで、未対応種別は透明な空 Source になる。デバッグアプリのプレビュー欄はこの経路で合成し、最終テクスチャを CGImage として読み戻して表示する。
- 音声: `TimelineAudioMixer`（AudioStream）が読み取り範囲と交差するアイテムのリソースだけを開き、各アイテムの `EffectedAudioItemSource`（素材ストリーム → 本家のチェーン順序の処理器連鎖 → VolumePan）が供給するサンプルへレイヤー音量を適用して float 加算する。音声グループに完全に所有される子は `AudioGroupResolver` の算出に基づきトップレベルへ直接加算せず、`GroupAudioBusSource`（バスミックス → グループエフェクト → Resampler）経由でのみ加算される。素材のデコードは `PCMProvider` の差し替え点の先にあり実体は未実装で、ミックス結果の再生・書き出しへの接続もまだ無い。

**テキスト描画・個別エフェクト・動画デコード・書き出し・製品 UI は未実装。音声はパイプラインの芯のみで、デコード実体・ユーザー音声エフェクト・再生／書き出し接続が未実装。** 詳細は実装台帳 MAC-0001〜MAC-0013。

## 実装後の書き方

- 実際のファイル構造と、利用者操作→編集モデル→映像／音声→表示・書き出しの呼び出しを木構造・自然言語で更新する。
- 各機能についてファイル・クラス・関数、責務、依存、I/O型、データフロー、所有権、スレッド、キャッシュ、例外処理を記述する。
- [IMPLEMENTATION_LOG](IMPLEMENTATION_LOG.md)の変更IDを参照し、本家の対象クラスと置換理由を明記する。
- 各コミットの実装・検証状況（IMPLEMENTED/VERIFIED/UNKNOWN）を区別し、単なる技術案をAs-builtに転記しない。
