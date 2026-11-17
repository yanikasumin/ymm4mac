# ymm4mac の実装済みアーキテクチャ

更新: 2026-11-18。反映境界: PR #78（構造整理 W10）まで。状態: モデル層・.ymmp 互換層・描画層（Core 契約＋Metal 実行層）・音声パイプライン・書き出し・エフェクト定義層と Metal 処理器・製品 UI の土台まで実装済み。現行状態の概要は [STATUS.md](STATUS.md)、変更の履歴は [IMPLEMENTATION_LOG.md](IMPLEMENTATION_LOG.md) を参照（この文書は構造の As-built に専念し、進捗や件数は置かない）。

この文書は **実装されている構造のみ記載するAs-built**。計画・仮説は[解析側のMac設計案](https://github.com/yanikasumin/ymm4-native-research/blob/main/docs/02-MAC-DESIGN-PROPOSAL.md)に記載。

## 現状の実体

    ymm4mac/
      README.md                開発目的・関連資料
      AGENTS.md                作業者向けの規則
      Package.swift            Swift パッケージ定義（YMM4Core / YMM4GPU ライブラリ + テスト）
      Sources/YMM4Core/        モデル層（Foundation のみ）
        Model/                 ドメインモデルの値型とプロジェクト構造
          VideoInfo.swift      解像度・FPS・サンプリングレート
          FrameTime.swift      フレーム⇔時間換算
          Project.swift        プロジェクト（Timelines / Characters / ToolStates 等）
          Timeline.swift       タイムライン（Length / MaxLayer はキャッシュ済み派生値）
          TimelineSupport.swift LayerSetting(s)、TimelineVerticalLine、SerializableToolState
          Character.swift      キャラクター（全プロパティ型付き。KeyGesture / VoiceDescription を含む）
          ShapeParameter.swift 図形パラメータ（RectangleShapeParameter と Brush を型付き、
                               それ以外の $type は生保持。旧 ShapeType の変換表を含む）
          Brush.swift          Brush の型付き部（ShapeParameter から分離）
        Animation/             時間変化と補間の評価
          Animation.swift      数値プロパティの時間変化と値評価（本家 GetValue の全分岐、分割連動を含む）
          AnimationType.swift  補間・イージング種別の数値テーブルと分類規則
          KeyFrames.swift      アイテム単位で共有されるキーフレーム位置（分割用の一括削除を含む）
          Easing.swift         イージング全科（In 素関数＋端点ラッパー＋モード合成）
          Cubic.swift          スプライン補間の重みカーネル（本家 Cubic）
          BezierAnimation.swift ベジェ補間の定義と Newton 法による評価
          StatelessRandom.swift キー列からの決定的乱数生成（本家 StatelessRandom）
          PlaybackRateMap.swift 再生速度の積分テーブル（分割時の素材時刻計算）
        Format/                .ymmp 互換層と形式の基盤
          YmmpCodec.swift      .ymmp の読み込み・保存（$type 解決、型移行、診断記録）
          JSONValue.swift      順序・数値リテラルを保持する JSON 値と自前パーサ／シリアライザ
          Color.swift          ARGB 8bit の色値
          HonkeFormat.swift    色の文字列形式、AnimationType のメンバ名対応等の残部
          TimeSpanValue.swift  TimeSpanValue（tick 保持、"c" 形式）
          RenamedTypeResolver.swift 型名移行の解決（本家 RenamedTypeResolver 相当）
          PreservedObject.swift 未知・未モデル化オブジェクトの順序保持つき生保持
          HonkeEnum.swift      本家列挙の基底（未知の名前は保持）
          TextEnums.swift      テキスト系の列挙
          VideoEnums.swift     映像系の列挙
          EditingEnums.swift   編集・表示系の列挙
          CodecSupport.swift   互換層の内部共通処理
          AnimationCodecSupport.swift Animation 等の JSON 形状変換
        Editing/
          TimelineEditing.swift  編集操作の基本（追加・移動・削除・移動可能性・スナップ）
          TimelineEditingCollision.swift 衝突解決
          TimelineEditingGroup.swift グループ ID・グループ化
          TimelineEditingSplit.swift 分割・ChangeFrameRate
          TimelineEditingDeleteAndMove.swift DeleteAndMove・長さ変更
          TimelineEditingSpace.swift 空間を詰める削除の一族
        Items/
          BaseItem.swift       BaseItem / VisualItem / VideoItemProperties
                               （アニメーション文脈の伝播、分割。本家 IVideoItem の
                               映像プロパティ一式で、適合は VisualItem 系譜 +
                               VoiceItem + TransitionItem）
          AudioItem.swift      AudioItem
          VideoItem.swift      VideoItem
          ImageItem.swift      ImageItem
          TextItem.swift       TextItem / TextDecoration / TextAppearance
          VoiceItem.swift      VoiceItem
          VoiceItemJimaku.swift VoiceItem の実効値解決（JimakuVisibility と Character
                               設定による表示可否・外観・変形・VideoEffects）と、
                               VideoItemProperties の実効値アクセサ（effectiveX 等）
          ShapeItem.swift      ShapeItem
          EffectItem.swift     EffectItem
          GroupItem.swift      GroupItem
          SceneItem.swift      SceneItem
          FrameBufferItem.swift FrameBufferItem
          TachieItems.swift    TachieItem / TachieFaceItem
          TransitionItem.swift TransitionItem
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
          DrawOrdering.swift   描画順序（3キー）、ZIndex、セグメント構築
          PlaneSplit.swift     平面分割（BSP）の判定規則と差し替え点
                               （PlaneSplitOrdering / NullPlaneSplitOrdering、
                               四隅・断片の値型）
          EffectContracts.swift エフェクト連鎖の契約群: 処理器・定義・組と供給元、
                               描画先の抽象（RenderTarget / Factory）、
                               アルファマスクの境界、PlaneSplitGeometryProviding
          EffectedItemSource.swift 合成の実行部（アイテム単位）:
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
          AudioEffectContracts.swift アイテム音声の契約群: AudioItemProperties、
                               AudioEffectProvider（ユーザー音声エフェクトの
                               差し替え点）、AudioChainOptions
          EffectedAudioItemSource.swift アイテム音声の処理器連鎖（本家のチェーン順序）、
                               AudioSourceFactory
          AudioEffectProcessors.swift NegativeSeekable / ContentOffset / Loop /
                               Reverse / Echo の各処理器と基底
          ResamplingCore.swift 補間カーネル（Linear / Cubic）と生成芯
                               BandLimitedResamplingCore（窓関数 sinc の
                               帯域制限補間。MAC-0024）
          ResamplerStreams.swift Resampler / PlaybackRate / VariablePlaybackRate /
                               Upsampler の各ストリーム
          VolumePanStream.swift VolumePan（サンプル対ごとの Animation 評価）
          AudioGroups.swift    AudioGroupResolver（グループ境界の区間分割と
                               DirectGroups / Owner の算出）、
                               AudioGroupStreamBuilder（組み立て）
          AudioGroupStreams.swift SegmentGate / GroupEffectChain の各ストリーム
          GroupAudioBusSource.swift 音声合成グループのバス（バスミックス →
                               グループエフェクト → Resampler）
          TimelineAudioMixer.swift タイムライン全体のミックス（レイヤー音量適用、
                               float 加算、リミッターなし）
        Effects/               映像エフェクト定義層＋DrawDescription 変換型処理器
                               （Foundation のみ。MAC-0018。合成チェーンへの接続は
                               MAC-0019、VoiceItem の字幕エフェクト解決の接続は MAC-0020、
                               GPU 処理系の定義層は MAC-0022）
          Base/                定義層の共通基盤と登録、変換型処理器の基盤
            VideoEffectDefinitionBase.swift 定義の共通基盤（$type 対応、Animation 型
                                 パラメータ、追加フィールド保持、IsEnabled）
            VideoEffectRegistry.swift $type 名→定義型のレジストリ（登録95種）と
                                 TypedEffectPairProvider（保持列から型付き定義を復元して
                                 EffectedItemSource へ供給する消費側の接続。キーフレーム
                                 文脈の伝播と、VoiceItem の字幕エフェクト解決列の
                                 切り替えを含む）
            DrawDescriptionEffectProcessor.swift 変換型処理器の基盤
            GPUEffectBase.swift  GPU 処理系定義の基底（GPUEffectDefinitionBase）、
                                 暫定処理器 GPUEffectPassthroughProcessor（入力をそのまま
                                 返す素通し。実処理器は次段）（MAC-0022）
          DrawDescription/     DrawDescription 変換型の定義＋処理器の対
            BasicDrawEffects.swift Zoom / Opacity / DrawPosition / Billboard 等
            InOutEffects.swift   InOutFade / InOutMove / InOutZoom 等の出入り系
            RandomRepeatEffects.swift Random 系・Repeat 系（共有計算は Animation の
                                 randomMoveRate / repeatMoveRate を再利用）
            CameraEffects.swift  CameraFov / CameraPosition / CameraLookAt /
                                 CameraWraparound / Polar 系 / XYToPolarTransform
            PreviewAndGroupEffects.swift ShowOnlyPreview、GroupedDrawingEffect
                                 （グループ合成用。$type を持たない）
            MotionTrackingEffect.swift MotionTracking
          GPU/                 GPU 処理系の定義層（MAC-0022）
            GPUEffectEnums.swift GPU 系エフェクトで共有する列挙型群
            TransformEffects.swift 変形系14種の定義
            BlurEffects.swift ぼかし系12種の定義
            ColorEffects.swift 色調系11種の定義
            ShadowFillEffects.swift 影・塗り系9種の定義
            WarpEffects.swift 歪み系8種の定義
            MaskKeyEffects.swift マスク・キー系3種の定義
            GPUInOutEffects.swift 出入り系10種の定義（DrawDescription 側と同名を
                                 避けるため接頭辞を維持。§4.2 の余地に基づく）
            GPURandomRepeatEffects.swift ランダム・反復系4種の定義（同上）
            CustomEffects.swift カスタム系2種の定義
          Transition/          画面遷移のパラメータ
            TransitionParameters.swift TransitionTarget／TransitionKind／
                                 TransitionParameter（パラメータの型付き復号）
        Export/                書き出しの芯（Foundation のみ。MAC-0017）と音声供給
                               （MAC-0026。映像供給とファサードは YMM4GPU 側）
          ExportSession.swift  書き出しセッションの状態機械（全経路で finalize 1回、
                               結果状態を型で区別）
          ExportAudioProvider.swift TimelineExportAudioProvider（音声供給。解析パスで
                               ラウドネス解析を行い、書き出しパスでは
                               DynamicsProcessorStream で包んだミキサーを供給）
          ExportSettings.swift 書き出し設定の明示受け渡し
          FFmpegArguments.swift FFmpeg 引数生成（純粋関数）と NV12 変換
                               （BT.709 リミテッド）
          FFmpegProcessWriter.swift 音声・映像の別プロセス＋終了時 mux の本家方式
                               （プロセス起動は差し替え点）
          LoudnessAnalysis.swift ラウドネス解析の倍率計算
          BS1770LoudnessAnalyzer.swift BS.1770-3 アナライザ（二段ゲーティング）
          DynamicsProcessorStream.swift DynamicsProcessor（Ratio=1 高速経路）
          EnvelopeFollower.swift エンベロープフォロワ（再構成）とリングバッファ
      Sources/YMM4GPU/         GPU 実行層（Metal。全ソース #if os(macOS)、Linux では空）
        Graphics/
          MetalGraphicsDevices.swift MetalGraphicsDevices（デバイス共有・
                               登録表・共有資源、readBGRA によるバイト列
                               読み戻しを含む）、シェーダ一式、CGImage 読み戻し
          MetalImage.swift     MetalImage（ImageReference の実体。境界と
                               テクスチャ平面範囲 texturePlaneRect /
                               planeOffset を分けて持つ。MAC-0027）
          MetalGraphicsContext.swift MetalGraphicsContext（消費者ごとの
                               文脈・描画先工場）、QuadVertex
          MetalRenderTarget.swift RenderTarget の Metal 実装（画面サイズの
                               テクスチャ、記録の畳み込みと close() での同期
                               実行。失敗は MetalRenderError として close()
                               が投げる。MAC-0021。描画内容の境界を追跡し、
                               close() 成功時に bounds = 内容境界として
                               再登録する。MAC-0027）
          MetalDrawingEffect.swift DrawingEffect の Metal 実装（変換の
                               遅延記録、PlaneSplitGeometryProviding を兼ねる）
        Sources/
          MetalImageSource.swift MetalImageSource（画像）と共有ヘルパー
                               （resolveMediaURL / makePremultipliedTexture）
          MetalShapeSource.swift MetalShapeSource（図形）
          MetalSourceProvider.swift MetalEmptySource（未対応種別の透明）、
                               MetalSourceProvider（種別ごとの分岐、シーン
                               解決子の注入。対象タイムラインとエフェクト
                               供給元を受け取り、内部合成器（シーン・合成
                               グループ）へ供給元を伝播する。MAC-0028）
          Media/
            MetalVideoSource.swift MetalVideoSource（動画、
                               AVAssetImageGenerator。MAC-0025）
            MetalSceneSource.swift MetalSceneSource（シーン入れ子）
            MetalCompositeSource.swift MetalCompositeSource（合成グループ。
                               自前文脈と内部 TimelineComposer で子を
                               中間画像へ合成。MAC-0027）
            MetalFrameBufferSources.swift MetalFrameBufferSourceBase
                               （共通部）と MetalFrameBufferSource
                               （フレームバッファ）
            MetalTachieSources.swift MetalTachieSource（立ち絵。描画は
                               境界型 MetalTachieRenderer へ委譲。MAC-0025）
          Text/
            MetalFontResolver.swift MetalFontResolver（フォント解決）と
                               様式評価（MetalTextStyleValues / MetalTextPiece）
            MetalTextRasterizer.swift MetalTextRasterizer（CoreText による
                               レイアウトと背景／前景の分離描画）
            MetalTextSources.swift MetalTextSource（テキスト）、
                               MetalJimakuSource（字幕）
          Effect/
            MetalEffectSources.swift MetalEffectSource（EffectItem。本家
                               EffectSource 相当。蓄積画像へ図形マスクを
                               適用する MetalEffectItemDrawingEffect を含む。
                               FrameBuffer 実装の共通部は
                               MetalFrameBufferSourceBase を共有。MAC-0035）
            MetalAlphaMask.swift MetalAlphaMaskEffect（クリッピングの
                               実効マスク。本家 D2D AlphaMask 相当）と
                               MetalAlphaMaskEffectFactory（MAC-0035）
          Transition/
            MetalTransitionSource.swift MetalTransitionSource（画面遷移。
                               自前文脈と Before / After の内部
                               TimelineComposer（TransitionItemPicker）を
                               持ち、各側へ Before/AfterVideoEffects を
                               適用してからブレンドで合成する。パラメータの
                               型付き復号は Core の TransitionParameters。
                               MAC-0036）
            MetalTransitionBlends.swift 内蔵ブレンド8種（Fade / Switch /
                               None / Slide / Push / DoubleSlideDoor /
                               DoubleOpenDoor / Slice）と TransitionGeometry
        Effects/
          MetalEffectProcessorBase.swift MetalEffectPairProvider
                               （TypedEffectPairProvider を内包し対象種を
                               Metal 処理器へ差し替える）、MetalEffectDefinition、
                               MetalEffectProcessor 基底、ユニフォーム群
          MetalColorEffectProcessors.swift 色変換系8種の Metal 処理器
                               （MAC-0023）
          MetalBlurMosaicProcessors.swift GaussianBlur・Mosaic の Metal
                               処理器（MAC-0023）
          MetalEffectProcessorHelpers.swift 第2段の共通ヘルパ（MAC-0028）
          MetalEffectProcessorsGeometry.swift 幾何変換系（MAC-0028）
          MetalEffectProcessorsBlurMask.swift ぼかし／マスク系（MAC-0028）
          MetalEffectProcessorsShadowFill.swift 影／塗り／枠線系（MAC-0028）
          MetalEffectProcessorsWarp.swift ワープ系（MAC-0028）
          MetalEffectProcessorsInOut.swift イン／アウト系（MAC-0028）
          MetalEffectProcessorsRandomRepeat.swift ランダム／反復系
                               （MAC-0028）
        Export/
          AVFoundationPCMProviderFactory.swift AVFoundationPCMProviderFactory
                               （AVAssetReader で素材全体を float32 / 2ch 化
                               するデコード実体。MAC-0026）
          MetalExportVideoProvider.swift MetalExportVideoProvider
                               （PreviewBox と同一構成の合成経路でフレームを
                               供給。対象タイムラインと共有のエフェクト
                               供給元を MetalSourceProvider へ渡す。MAC-0028）
          TimelineExporter.swift TimelineExporter（映像・音声供給と
                               ExportSession の組み立て。MAC-0026）
      Apps/DebugApp/           検証用デバッグアプリ（製品 UI の土台を含む）
        Package.swift          個別パッケージ定義（ルートへパス依存）
        Info.plist             バンドル情報（MAC-0039）
        package-app.sh         .app バンドルの組み立て（MAC-0039）
        Sample/sample.ymmp     検証用サンプルプロジェクト
        Sources/YMM4MacDebug/
          YMM4MacDebugApp.swift アプリ入口
          ContentView.swift    ルート画面（プロジェクト読み込みと検証サンプル）
          WorkspaceState.swift 新規プロジェクト等の作業状態
          ProjectView.swift    製品 UI の土台（プレビュー・運送系・タイムライン・
                               ステータスバー・メニュー）
          PreviewBox.swift     プレビュー合成の表示
          TimelineStripView.swift タイムライン本体
          TimelineLayerLabels.swift レイヤーラベル列
          TimelineScale.swift  目盛り
          SerifInputView.swift セリフ入力行
          PropertyInspectorView.swift アイテムのプロパティ編集
          PropertyEditorRows.swift 編集行の部品
          EffectInspectorView.swift エフェクト編集
          VideoSettingsView.swift 動画の設定ダイアログ
          ExportDialogView.swift 動画出力ダイアログ
          ExportJob.swift      書き出しジョブ（開始時にプロジェクトの
                               スナップショットを所有。MAC-0034）
          AutoTestRunner.swift 全自動テストの実行（MAC-0038）
          AutoTestReport.swift 全自動テストのレポート型（MAC-0038）
      Tests/YMM4CoreTests/     ユニットテスト（Sources のドメイン構成を鏡写し。
                               件数等の最新結果は実行記録が正本で、ここには置かない）
        Model/ Animation/ Format/ Editing/ Rendering/ Audio/ Effects/ Export/
                               各ドメインのテスト
        Support/               共有の偽実装・ヘルパ（Fake* 群、TestPCMProviders）
      Harnesses/               Mac 実機ハーネス（画素検証等。mac0023〜mac0035 の
                               9種と README。W1 で git 管理化）
      docs/ARCHITECTURE.md     本文書
      docs/IMPLEMENTATION_LOG.md
      docs/STATUS.md
      docs/HANDOFF.md
      .github/pull_request_template.md
      .gitignore

## データフロー（実装済みの範囲）

- 読み込み: .ymmp テキスト → `JSONParser`（順序・数値リテラル保持）→ `YmmpCodec.decode` が $type を解決して `Project` / `Timeline` / アイテム13クラスを構築。未知の $type のアイテムは読み飛ばして診断情報へ記録し、未知のプロパティは各モデルの `additionalFields` に保持する。プラグイン型の値（エフェクト等）は `PreservedObject` として生 JSON のまま保持する。デコードの最後に、VoiceItem / TachieItem / TachieFaceItem の実行時参照 `character` を `Project.Characters` から `characterName` で引いて解決する（本家の `Character` は [JsonIgnore] で、保存されるのは名前だけであるため）。
- 編集: `Timeline` の編集操作（TimelineEditing.swift）がアイテム（参照型）を直接書き換える。本家の意味論どおり、前処理は入力を書き換え、原子的保証はコミット段階のみ。`Timeline.Length` / `MaxLayer` はキャッシュとして保守される。
- 保存: `YmmpCodec.encode` がモデルを追加フィールドごと JSON 化（1行）→ 一時ファイルへ書き出し → 再読込で検証 → 本ファイルへコピー。
- アイテムの複製は JSON 往復（本家 GetClone と同じ経路）で、`BaseItem.cloned()` が担う。分割はこの複製を左右に作ってから行う。
- 描画（実行部まで）: `TimelineComposer.update` が `ItemPicker.pickItems` でフレーム時点の対象アイテムを選定し、資源管理（範囲外の破棄・不足分の生成）と親エフェクトの再構築（顔・声解決→グループ解決）を行う → FrameBuffer 以外の各 `EffectedItemSource` が Source を更新し、`EffectedOutput` の連鎖（処理器の位置基準の再利用・差し替え）＋アイテム変換で DrawDescription を確定 → `DrawOrdering.ordered` が3キーで順序付け → `DrawSegmentBuilder` のセグメント列に従い、抽象描画先（RenderTarget）へ合成する。FrameBuffer アイテムでは描画先を閉じて Source へ渡し、新しい描画先で合成を続ける。
- 描画（GPU 実行）: 描画先・DrawingEffect・基本 Source の実物は `Sources/YMM4GPU/`（Metal）。`MetalGraphicsDevices` がデバイスと ImageReference の登録表を所有し、`MetalGraphicsContext`（消費者ごとに生成）が描画先を供給する。DrawingEffect は中間テクスチャを作らず、入力実体へ変換（ズーム×ワールド×透視）と不透明度を記録した実体を出力として登録する（遅延評価）。描画先は画面サイズのテクスチャを実体とし、記録した描画を close() で同期実行する。RenderTarget の close() は throws であり（MAC-0021）、テクスチャ生成失敗やコマンドバッファの実行エラーは MetalRenderError として呼び出し側へ伝播し、失敗した描画先は出力として公開されない（最終合成の失敗時は旧出力が保持される）。Source の実物は画像（ImageIO デコード）、図形（SDF 描画）、テキストと字幕（CoreText でラスタライズ）、動画（AVAssetImageGenerator による時刻指定デコード）、シーン（内側 TimelineComposer の入れ子合成）、フレームバッファ（蓄積の実体化）、エフェクト（EffectItem。本家 EffectSource 相当。FrameBuffer 実装の共通部を基底クラスで共有しつつ、B-1 の特殊性＝基底へ FrameBufferItem として null を渡すため ClearBackground=false・Flood は不透明な黒・切り抜き境界は画面サイズ、を持つ専用 Source。蓄積画像へ ShapeParameter の図形をマスクとして適用し、アイテム自身の映像エフェクト列がマスク範囲にだけ効く。MAC-0035）、立ち絵（境界型 MetalTachieRenderer への委譲）、合成グループ（MetalCompositeSource が自前文脈と内部 TimelineComposer で子をタイムライン絶対時刻で中間画像へ合成。中心は CompositeCenter が ImageCenter のとき内容境界の中心、それ以外は (0,0)。グループの GroupEffects は子へ流れず、グループ自身の VideoEffects が合成結果全体へ一度だけ適用される。MAC-0027）、画面遷移（MetalTransitionSource が自前文脈と Before / After の内部 TimelineComposer（TransitionItemPicker）で遷移前後の画面を合成し、各側へ Before/AfterVideoEffects を適用してから内蔵ブレンド8種で合成する。MAC-0036）で、未対応種別は透明な空 Source になる。描画先は描画内容の境界を追跡し、MetalImage は境界とテクスチャ平面範囲（texturePlaneRect / planeOffset）を分けて持つ。動画の素材時刻は PlaybackRateMap で求め、素材を開いた時点で実 Duration が item.contentLength へ反映される。シーン解決は PreviewBox / ProjectView がプロジェクト全タイムラインを解決子として渡す。AVFoundation が開けないコンテナ（MKV / WebM / TS 等）は透明フォールバックのままで、FFmpeg 併用は未判断。エフェクト供給元は外側の合成器と内部合成器（シーン・合成グループ）で同じ MetalEffectPairProvider インスタンスを共有し、内部の子にも GPU エフェクトが効く（MAC-0028。プレビュー・書き出しとも同じ配線で、書き出し側は対象タイムラインも供給元へ渡すため合成グループが書き出しでも合成される）。クリッピング（IsClippingWithObjectAbove）の実効マスクは `MetalAlphaMaskEffectFactory` をプレビュー・書き出し・シーン・複合グループの全生成経路で TimelineComposer へ注入して有効化した（MAC-0035）。本家は効果グラフの遅延評価により描画段でのマスク入力設定が最終描画へ反映されるが、こちらは入力が設定されるたびに出力実体を作り直して登録し直すことで同じ意味論を作る。直前の画像が無い場合に合成器が渡す白 Flood のトークンは、全面不透明なマスクによる AlphaMask が恒等変換であることから、本体画像をそのまま出力として登録して解決する。画像・動画のデコードテクスチャは上下反転せずに生成する（MAC-0028 で是正。従来は反転していた）。デバッグアプリのプレビュー欄はこの経路で合成し、最終テクスチャを CGImage として読み戻して表示する。
- VoiceItem の実効値: 本家の IVideoItem プロパティは読み取りのたびに JimakuVisibility と Character 設定で解決される動的 getter であるため、描画パイプラインはアイテムの保持プロパティを直接読まず、`VideoItemProperties` の実効値アクセサ（`effectiveX` 等、VoiceItem のときだけ解決し他は保持値を返す）を通る。EffectedItemSource（変形・フェード・クリッピング）、TimelineSource（RenderScale・合成時の読み取り）、DrawOrdering（IsAlwaysOnTop・IsZOrderEnabled）が対象。字幕の表示可否と外観は `VoiceItem.jimakuIsVisible` / `jimakuAppearance` が担い、MetalJimakuSource はそれを使うだけにする。
- 音声: `TimelineAudioMixer`（AudioStream）が読み取り範囲と交差するアイテムのリソースだけを開き、各アイテムの `EffectedAudioItemSource`（素材ストリーム → 本家のチェーン順序の処理器連鎖 → VolumePan）が供給するサンプルへレイヤー音量を適用して float 加算する。音声グループに完全に所有される子は `AudioGroupResolver` の算出に基づきトップレベルへ直接加算せず、`GroupAudioBusSource`（バスミックス → グループエフェクト → Resampler）経由でのみ加算される。素材のデコード実体は MAC-0026 の `AVFoundationPCMProviderFactory`（YMM4GPU 側、AVAssetReader で全体を float32 / 2ch 化、失敗時は無音）が担い、書き出しへの接続も MAC-0026 で実装済みである。ミックス結果の再生への接続はまだ無い。位置精度は MAC-0016 で QA 済み（位置カウンタの累積ドリフトは全チェーンで 0 サンプル。`InMemoryPCMProvider` の seek は二重量子化を避けるため最も近いフレーム境界へ丸める）。Resampler の生成芯は MAC-0024 で線形補間から帯域制限補間（窓関数 sinc）へ差し替え、MAC-0037 で正式仕様（Kaiser 窓 β=8.96・片側96零交差・193タップ）へ固定した。長さ・シーク・位置の変換式は無変更で位置写像は不変、DC は厳密に保存される。正式合格値（48k→44.1k で阻止帯域 [23.2k–24kHz] の最悪値 −80 dB 以下、通過帯域 20kHz までの平坦さ ±0.1 dB 以内）を正式テスト（AudioResamplerQualityTests）が合否判定し、最終形の実測は阻止帯域の最悪値 −94.54 dB・平坦さ 0.000031 dB 以内。詳細は台帳 MAC-0037 と解析側 AUDIO-FIDELITY-PLAN §3.1 を参照。
- 映像エフェクト定義層: `Effects/` の定義型が $type 名と Animation 型パラメータを保持し、変換型の処理器が MAC-0010 の連鎖契約で DrawDescription を書き換える。登録は95種（変換群22種＋GPU 処理系73種、MAC-0022）で本家内蔵分は定義層が揃った。GPU 処理系の処理器は、第1段10種（色変換系8種＋GaussianBlur＋Mosaic、MAC-0023、`Sources/YMM4GPU/Effects/` の MetalColorEffectProcessors.swift / MetalBlurMosaicProcessors.swift）と第2段31種（幾何変換・ぼかし／マスク・影／塗り・ワープ・イン／アウト・ランダム／反復、MAC-0028、同 Effects/ の家族別7ファイル）の計41種が Metal 実処理器を持ち、Mac 実機で画素検証済み（解析値との照合）で統合済みである。残り32種は暫定の素通し（GPUEffectPassthroughProcessor）のため描画にはまだ反映されない。MetalEffectPairProvider が TypedEffectPairProvider を内包し、対象41種だけを Metal 処理器つきの定義へ差し替えて供給する。全 Metal 処理器共通の前提として、入力画像が恒等変換でなく不透明度≠1 の場合は素通しになる（DrawDescription を書き換える処理器のフックは素通し経路でも通る）。保持形式は生保持のまま（モデル層は全箇所 `PreservedObject`、保存経路は無変更）で、接続は消費側で行う: `TimelineComposer` の既定の EffectPairProvider である `TypedEffectPairProvider` が、合成時に保持列から型付き定義を一時的なビューとして復元し、`EffectedItemSource` へ供給する（対象は VisualItem 系 VideoEffects／VoiceItem の JimakuVideoEffects／GroupItem の VideoEffects／TachieFaceItem・VoiceItem の TachieFaceEffects。SceneItem の Before・AfterVideoEffects は対象外。TransitionItem の Before・AfterVideoEffects は MAC-0036 で `transitionEffectPairs` として別経路から供給される）。キーフレーム文脈は定義生成時と所有アイテムの KeyFrames 変更時にだけ再伝播され、定義インスタンスは作り直されない。VoiceItem の字幕エフェクトは、キャラクターが解決済みの場合に限り、保持列ではなく MAC-0014 の `resolvedVideoEffects`（JimakuVisibility とキャラクター設定による解決列）が供給列になる。
- 書き出し: `ExportSession`（状態機械）が書き出しの開始から終了手続き（finalize）までを管理し、`FFmpegProcessWriter` が音声（WAV 一時ファイル）と映像を別プロセスで書いて終了時に mux する本家方式を取る。映像は NV12（BT.709 リミテッド）へ変換し、色宣言は NV12 経路のみに付ける。供給の接続は MAC-0026 で実装済みである: ファサード `TimelineExporter`（YMM4GPU）が組み立て、映像は `MetalExportVideoProvider` が PreviewBox と同一構成の合成経路でフレームを合成し `readBGRA` で借用バッファへ読み戻して供給する。音声は `TimelineExportAudioProvider`（Core）が2パスで供給する: 解析パスでミックスを `LoudnessAnalysis`（`BS1770LoudnessAnalyzer` の二段ゲーティング）に通して音量係数とコンプレッサ倍率を求め、書き出しパスでは別のミキサーへ `DynamicsProcessorStream`（volume = 音量係数、ratio = コンプレッサ倍率）を被せてフレームごとのサンプルを返す。DebugApp の書き出し UI から実行でき、実 ffmpeg でのエンコードまで検証済みである（台帳 MAC-0026）。DebugApp の書き出しは開始時にプロジェクト全体のスナップショット（YmmpCodec 往復で作るジョブ専有のインスタンス群）を対象とし、書き出し中の編集は出力へ混入しない（MAC-0034）。

**製品 UI は土台まで実装済みで、形の完成（本家レイアウトへの一致、スタブの解消）は未完。動画デコードは AVFoundation の範囲で実装済み（非対応コンテナは未対応で、FFmpeg 併用は未判断）。音声はパイプラインの芯と QA、リサンプラの高品質化（MAC-0024）、デコード実体と書き出し接続（MAC-0026）までで、ユーザー音声エフェクト・再生接続が未実装。書き出しは芯に加えて実接続と実エンコード検証まで完了。映像エフェクトは定義層と変換型処理器に加え、合成チェーンへの接続（消費側の型付き復元）と VoiceItem の字幕エフェクト解決の接続まで済み、GPU 処理系は定義層（73種）に加え、処理器は第1段10種＋第2段31種＝41種が Mac 検証済みで統合済み、残り32種は素通し（未実装）。内部合成（シーン・合成グループ）へのエフェクト供給元伝播と書き出しへのタイムライン受け渡しも MAC-0028 で接続済み。** 詳細は実装台帳 MAC-0001〜MAC-0037。

## 実装後の書き方

- 実際のファイル構造と、利用者操作→編集モデル→映像／音声→表示・書き出しの呼び出しを木構造・自然言語で更新する。
- 各機能についてファイル・クラス・関数、責務、依存、I/O型、データフロー、所有権、スレッド、キャッシュ、例外処理を記述する。
- [IMPLEMENTATION_LOG](IMPLEMENTATION_LOG.md)の変更IDを参照し、本家の対象クラスと置換理由を明記する。
- 各コミットの実装・検証状況（IMPLEMENTED/VERIFIED/UNKNOWN）を区別し、単なる技術案をAs-builtに転記しない。
