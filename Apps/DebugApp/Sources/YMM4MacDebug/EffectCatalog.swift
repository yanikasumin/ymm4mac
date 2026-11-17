import Foundation

/// エフェクト追加ポップアップのカタログ（本家 SelectVideoEffectPopup の
/// 供給元 = 登録済み全エフェクト）。型名は Core の
/// `VideoEffectRegistry` に登録済みの95件（本体エフェクトの定義層）。
/// 表示名・カテゴリ・検索キーワードは本家定義クラスの
/// `[VideoEffect]` 属性と Texts リソースから実測抽出した値で、
/// 推測分類ではない（抽出元: 解析側 YukkuriMovieMaker.Project.Effects
/// の各定義クラス＋ YukkuriMovieMaker.Resources.Localization.Texts.resx）。
/// カテゴリは本家キー8種（Branch は本体95件には出現しない）。
/// ユーザー編集可能なカテゴリ設定（本家 VideoEffectListSettings）は
/// 保持先が無いため未実装。
enum EffectCatalog {
    struct Entry {
        let typeName: String
        let displayName: String
        let category: String
        let keywords: [String]
    }

    /// カテゴリの並び（本家キーの順: Animation / Camera / Filtering /
    /// Composition / Decoration / Transition / Layout / Drawing）。
    static let categories: [String] = [
        "アニメーション", "カメラ", "加工", "合成",
        "装飾", "登場退場", "配置", "描画",
    ]

    static let entries: [Entry] = [
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.ArcBendEffect, YukkuriMovieMaker", displayName: "湾曲", category: "描画", keywords: ["湾曲", "曲げ", "bend", "arc"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.AutomaticZoomEffect, YukkuriMovieMaker", displayName: "画面内に収まるように拡大縮小", category: "描画", keywords: ["Zoom"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.BackgroundImageEffect, YukkuriMovieMaker", displayName: "背景画像", category: "装飾", keywords: ["背景", "background", "テクスチャ", "texture", "動画ファイル合成", "画像ファイル合成"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.BillboardEffect, YukkuriMovieMaker", displayName: "ビルボード", category: "カメラ", keywords: ["ビルボード", "billboard", "カメラ", "camera"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.BorderBlurEffect, YukkuriMovieMaker", displayName: "境界ぼかし", category: "加工", keywords: ["border blur"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.CameraFovEffect, YukkuriMovieMaker", displayName: "視野角", category: "カメラ", keywords: ["カメラ", "camera", "視野角", "FOV"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.CameraLookAtEffect, YukkuriMovieMaker", displayName: "注目カメラ", category: "カメラ", keywords: ["カメラ", "camera"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.CameraPositionEffect, YukkuriMovieMaker", displayName: "カメラ位置", category: "カメラ", keywords: ["カメラ", "camera"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.CameraWraparoundEffect, YukkuriMovieMaker", displayName: "回り込みカメラ", category: "カメラ", keywords: ["カメラ", "camera"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.CenterPointEffect, YukkuriMovieMaker", displayName: "中心位置", category: "描画", keywords: ["描画基準", "center point", "base point"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.ChromaKeyEffect, YukkuriMovieMaker", displayName: "クロマキー", category: "合成", keywords: ["chromakey"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.ChromaKeyEffect2, YukkuriMovieMaker", displayName: "クロマキー", category: "合成", keywords: ["chroma key"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.ChromaticAberrationEffect, YukkuriMovieMaker", displayName: "色収差", category: "加工", keywords: ["Chromatic Aberration", "chroma aberration"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.CircularDuplicatorEffect, YukkuriMovieMaker", displayName: "円形配置", category: "配置", keywords: ["円周配置"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.CopyAndReverseEffect, YukkuriMovieMaker", displayName: "複製して反転", category: "配置", keywords: []),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.CrashEffect, YukkuriMovieMaker", displayName: "砕け散る", category: "アニメーション", keywords: ["砕け散る", "クラッシュ", "crash", "割れ", "ガラス"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.CropByAngleEffect, YukkuriMovieMaker", displayName: "斜めクリッピング", category: "合成", keywords: ["clipping", "crop"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.CropEffect, YukkuriMovieMaker", displayName: "クリッピング", category: "合成", keywords: ["clipping", "crop", "クロップ"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.DirectionalBlurEffect, YukkuriMovieMaker", displayName: "方向ブラー", category: "加工", keywords: ["Directional Blur", "方向ぼかし", "移動ぼかし", "ディレクショナルブラー"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.DisplacementMapEffect, YukkuriMovieMaker", displayName: "ディスプレイスメントマップ", category: "加工", keywords: ["displacement mapping", "ディスプレイスメントマッピング", "ディスプレイスメントマップ"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.DrawLazyEffectEffect, YukkuriMovieMaker", displayName: "遅延エフェクトを描画", category: "描画", keywords: ["遅延", "lazy"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.DrawPositionEffect, YukkuriMovieMaker", displayName: "描画位置", category: "描画", keywords: ["X", "Y", "Z"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.ExposureEffect, YukkuriMovieMaker", displayName: "露光調整", category: "加工", keywords: ["exposure"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.FillBackgroundEffect, YukkuriMovieMaker", displayName: "背景塗りつぶし", category: "装飾", keywords: ["background", "fill"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.FillForegroundEffect, YukkuriMovieMaker", displayName: "前景塗りつぶし", category: "装飾", keywords: ["fill foreground"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.FrameLineEffect, YukkuriMovieMaker", displayName: "枠線", category: "装飾", keywords: ["frame line", "frame border"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.GammaCorrectionEffect, YukkuriMovieMaker", displayName: "ガンマ補正", category: "加工", keywords: ["gamma correction"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.GaussianBlurEffect, YukkuriMovieMaker", displayName: "ぼかし", category: "加工", keywords: ["Gaussian Blur", "ガウスぼかし", "ガウシアンブラー"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.GradientEffect, YukkuriMovieMaker", displayName: "グラデーション", category: "加工", keywords: ["Gradation"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.HalfToneBorderBlurEffect, YukkuriMovieMaker", displayName: "網点境界ぼかし", category: "装飾", keywords: ["ハーフトーン境界ぼかし", "halftone border blur"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.HalfToneEffect, YukkuriMovieMaker", displayName: "網点", category: "加工", keywords: ["ハーフトーン", "half tone"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.HalfToneOutlineEffect, YukkuriMovieMaker", displayName: "網点縁取り", category: "装飾", keywords: ["ハーフトーン縁取り", "half tone outline"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.HalfToneShadowEffect, YukkuriMovieMaker", displayName: "網点影", category: "装飾", keywords: ["ハーフトーン陰", "halftone shadow"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.HightlightsAndShadowsEffect, YukkuriMovieMaker", displayName: "ハイライトとシャドー", category: "加工", keywords: ["ハイライトとシャドー", "highlights and shadows", "highlight and shadow"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.HlslPixelShaderCodeEffect, YukkuriMovieMaker", displayName: "HLSLピクセルシェーダーコード", category: "加工", keywords: ["pixel shader"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.HlslPixelShaderFileEffect, YukkuriMovieMaker", displayName: "HLSLピクセルシェーダーファイル", category: "加工", keywords: ["pixel shader"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InOutBorderBlurEffect, YukkuriMovieMaker", displayName: "境界ぼかしを解除しながら登場退場", category: "登場退場", keywords: ["border blur"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InOutCrashEffect, YukkuriMovieMaker", displayName: "砕け散りながら登場退場", category: "登場退場", keywords: ["砕け散る"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InOutFadeEffect, YukkuriMovieMaker", displayName: "フェードイン・アウト", category: "登場退場", keywords: ["フェードアウト", "fade in", "fade out"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InOutGaussianBlurEffect, YukkuriMovieMaker", displayName: "ぼかしを解除しながら登場退場", category: "登場退場", keywords: ["Gaussian Blur", "ガウスぼかし", "ガウシアンブラー"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InOutGetUpEffect, YukkuriMovieMaker", displayName: "起き上がりながら登場退場", category: "登場退場", keywords: []),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InOutJumpEffect, YukkuriMovieMaker", displayName: "跳ねながら登場退場", category: "登場退場", keywords: ["jump", "ジャンプ"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InOutMosaicEffect, YukkuriMovieMaker", displayName: "モザイクを解除しながら登場退場", category: "登場退場", keywords: ["モザイク", "mosaic"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InOutMoveEffect, YukkuriMovieMaker", displayName: "移動しながら登場退場", category: "登場退場", keywords: ["move", "X", "Y", "描画位置", "座標"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InOutMoveFromOutsideFrameEffect, YukkuriMovieMaker", displayName: "画面外から登場退場", category: "登場退場", keywords: ["move"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InOutMoveFromOutsideImageEffect, YukkuriMovieMaker", displayName: "領域外から登場退場", category: "登場退場", keywords: ["move"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InOutRotateEffect, YukkuriMovieMaker", displayName: "回転しながら登場退場", category: "登場退場", keywords: ["rotation", "rotate", "angle"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InOutSkewEffect, YukkuriMovieMaker", displayName: "傾斜変形しながら登場退場", category: "登場退場", keywords: ["skew"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InOutTransitionEffect, YukkuriMovieMaker", displayName: "場面切り替え（ルール画像）", category: "登場退場", keywords: ["シーンチェンジ", "トランジション", "ワイプ", "scene change", "transition", "wipe"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InOutZoomEffect, YukkuriMovieMaker", displayName: "拡大縮小しながら登場退場", category: "登場退場", keywords: ["zoom"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InnerHalfToneShadowEffect, YukkuriMovieMaker", displayName: "網点影（内側）", category: "装飾", keywords: ["ハーフトーン陰（内側）", "inner halftone shadow"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InnerShadowEffect, YukkuriMovieMaker", displayName: "影（内側）", category: "装飾", keywords: ["陰", "inner shadow"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.InvertEffect, YukkuriMovieMaker", displayName: "色反転", category: "加工", keywords: ["color inversion", "invert"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.JumpEffect, YukkuriMovieMaker", displayName: "跳ねる", category: "アニメーション", keywords: ["jump", "ジャンプ"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.LinearTransferEffect, YukkuriMovieMaker", displayName: "線形色変換", category: "加工", keywords: ["線形色変換", "linear transfer"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.MarginEffect, YukkuriMovieMaker", displayName: "余白追加", category: "描画", keywords: ["margin", "padding", "領域拡張"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.MaskEffect, YukkuriMovieMaker", displayName: "図形切り抜き", category: "合成", keywords: ["mask", "マスク", "crop", "clipping", "クロップ", "クリッピング"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.MeshDeformationEffect, YukkuriMovieMaker", displayName: "メッシュ変形", category: "描画", keywords: ["mesh deformation", "mesh transform", "自由変形", "free deformation", "free transform"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.MonocolorizationEffect, YukkuriMovieMaker", displayName: "単色化", category: "加工", keywords: ["単色化", "monocolorization"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.MorphologyEffect, YukkuriMovieMaker", displayName: "抽象化", category: "加工", keywords: ["morphology"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.MosaicEffect, YukkuriMovieMaker", displayName: "モザイク", category: "加工", keywords: ["mosaic"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.MotionTrackingEffect, YukkuriMovieMaker", displayName: "モーショントラッキング", category: "合成", keywords: ["モーショントラッキング", "オブジェクトトラッキング", "モーショントラッカー", "オブジェクトトラッカー", "motion tracking", "object tracking", "motion tracker", "object tracker", "追従", "トラッキング", "トラッカー", "tracking", "tracker"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.NoiseColorShiftEffect, YukkuriMovieMaker", displayName: "ノイズ色ずれ", category: "加工", keywords: ["ノイズカラーシフト", "noise color shift", "ノイズディスプレイスメントマッッピング", "ノイズディスプレイスメントマップ", "noise displacement mapping"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.NoiseDisplacementMapEffect, YukkuriMovieMaker", displayName: "ノイズ歪み", category: "加工", keywords: ["ノイズディスプレイスメントマッピング", "noise displacement mapping"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.NoiseEffect, YukkuriMovieMaker", displayName: "ノイズ", category: "加工", keywords: ["noise", "砂嵐"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.OpacityEffect, YukkuriMovieMaker", displayName: "不透明度", category: "描画", keywords: ["Opacity", "Alpha"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.OutlineEffect, YukkuriMovieMaker", displayName: "縁取り", category: "装飾", keywords: ["アウトライン", "outline", "縁取り", "ふちどり", "ボーダー", "border", "アウターアウトライン", "アウターボーダー", "outer outline", "outer border"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.PolarDrawPositionEffect, YukkuriMovieMaker", displayName: "描画位置（極座標）", category: "描画", keywords: ["X", "Y"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.PolarTransformEffect, YukkuriMovieMaker", displayName: "極座標変換", category: "描画", keywords: ["polar"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.PosterizeEffect, YukkuriMovieMaker", displayName: "減色", category: "合成", keywords: ["posterize"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.RadialBlurEffect, YukkuriMovieMaker", displayName: "放射ブラー", category: "加工", keywords: ["radial blur"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.RadialLightEffect, YukkuriMovieMaker", displayName: "放射光", category: "加工", keywords: ["radial light", "閃光", "flash"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.RandomDuplicatorEffect, YukkuriMovieMaker", displayName: "ランダム配置", category: "配置", keywords: ["ランダム配置", "random arrangement", "random layout", "random duplicator"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.RandomMoveEffect, YukkuriMovieMaker", displayName: "ランダム移動", category: "アニメーション", keywords: ["random move", "震え", "X", "Y", "描画位置", "座標"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.RandomOpacityEffect, YukkuriMovieMaker", displayName: "ランダム透過", category: "アニメーション", keywords: ["random opacity"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.RandomRotateEffect, YukkuriMovieMaker", displayName: "ランダム回転", category: "アニメーション", keywords: ["random rotate", "震え", "rotation", "angle", "角度"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.RandomSkewEffect, YukkuriMovieMaker", displayName: "ランダム傾斜変形", category: "アニメーション", keywords: ["skew"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.RandomZoomEffect, YukkuriMovieMaker", displayName: "ランダム拡大縮小", category: "アニメーション", keywords: ["random zoom"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.RepeatMoveEffect, YukkuriMovieMaker", displayName: "反復移動", category: "アニメーション", keywords: ["ジャンプ", "跳ねる", "浮遊", "jump", "bound", "bounce", "float", "X", "Y", "描画位置", "座標"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.RepeatOpacityEffect, YukkuriMovieMaker", displayName: "反復透過", category: "アニメーション", keywords: ["不透明度", "点滅", "opacity", "blink", "alpha"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.RepeatRotateEffect, YukkuriMovieMaker", displayName: "反復回転", category: "アニメーション", keywords: ["揺れ", "3D回転", "角度", "rotate", "rotation", "angle"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.RepeatSkewEffect, YukkuriMovieMaker", displayName: "反復傾斜変形", category: "アニメーション", keywords: ["skew"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.RepeatZoomEffect, YukkuriMovieMaker", displayName: "反復拡大縮小", category: "アニメーション", keywords: ["浮遊", "zoom", "float"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.RotateEffect, YukkuriMovieMaker", displayName: "3D回転", category: "描画", keywords: ["角度", "rotation", "rotate", "angle"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.RoundCornerEffect, YukkuriMovieMaker", displayName: "角丸め", category: "加工", keywords: ["Rounded corners"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.SepiaEffect, YukkuriMovieMaker", displayName: "セピア", category: "加工", keywords: ["sepia"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.ShadowEffect, YukkuriMovieMaker", displayName: "影", category: "装飾", keywords: ["陰", "shadow"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.SharpenEffect, YukkuriMovieMaker", displayName: "シャープ化", category: "加工", keywords: ["sharpen"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.ShowOnlyPreviewEffect, YukkuriMovieMaker", displayName: "プレビュー時にのみ表示", category: "描画", keywords: []),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.SkewEffect, YukkuriMovieMaker", displayName: "傾斜変形", category: "描画", keywords: ["skew"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.TextureEffect, YukkuriMovieMaker", displayName: "画像の貼り付け", category: "装飾", keywords: ["前景", "foreground", "テクスチャ", "texture", "動画ファイル合成", "画像ファイル合成"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.TilingEffect, YukkuriMovieMaker", displayName: "敷き詰め", category: "配置", keywords: ["tile", "repeat", "タイル", "繰り返し", "画像ループ"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.TintEffect, YukkuriMovieMaker", displayName: "色味調整", category: "加工", keywords: ["tint"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.XYToPolarTransformEffect, YukkuriMovieMaker", displayName: "極座標変換（描画位置）", category: "描画", keywords: ["極座標変換", "polar coordinates"]),
        Entry(typeName: "YukkuriMovieMaker.Project.Effects.ZoomEffect, YukkuriMovieMaker", displayName: "拡大縮小", category: "描画", keywords: ["zoom", "aspect", "アスペクト比", "縦横比"]),
    ]

    /// 本家 FilteredEffects の規則: キーワードが入力されている間は
    /// カテゴリ条件より検索が優先される。マッチは表示名と検索
    /// キーワードへの部分一致で、大文字小文字・全半角を無視する
    /// （本家は加えてかな種も無視するが、Foundation に対応する
    /// 折りたたみが無いため未対応）。
    static func filtered(category: String?, keyword: String) -> [Entry] {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let needle = trimmed.folding(
                options: [.caseInsensitive, .widthInsensitive], locale: nil)
            return entries.filter { entry in
                entry.displayName.folding(
                    options: [.caseInsensitive, .widthInsensitive], locale: nil
                ).contains(needle)
                    || entry.keywords.contains {
                        $0.folding(
                            options: [.caseInsensitive, .widthInsensitive],
                            locale: nil
                        ).contains(needle)
                    }
            }
        }
        if let category {
            return entries.filter { $0.category == category }
        }
        return entries
    }
}
