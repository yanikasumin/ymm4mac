import Foundation

/// 映像エフェクト定義のプロパティメタデータ（GPUShadowMask 系）。
///
/// `EffectPropertyMetadata.descriptors(for:)` の具象定義別ビルダー。
/// 表示名・グループは本家の `Display` 属性（`Texts` リソース）、
/// 数値範囲は本家の `Range` / スライダ属性に根拠を持つ。
/// 根拠が取れない表示名はプロパティ名そのままにする。
public extension EffectPropertyMetadata {

    /// BackgroundImageEffectDefinition の固有パラメータ。
    static func backgroundImageEffectDescriptors(_ d: BackgroundImageEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "X", group: "背景画像",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "背景画像",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Opacity", displayName: "不透明度", group: "背景画像",
                get: { d.opacity }, set: { d.opacity = $0 }
            ),
            .animation(
                id: "Zoom", displayName: "拡大率", group: "背景画像",
                get: { d.zoom }, set: { d.zoom = $0 }
            ),
            .number(
                id: "PlaybackRate", displayName: "再生速度", group: "背景画像", range: -100000...100000,
                get: { d.playbackRate }, set: { d.playbackRate = $0 }
            ),
            .text(
                id: "FilePath", displayName: "ファイル", group: "背景画像",
                get: { d.filePath }, set: { d.filePath = $0 }
            ),
            .animation(
                id: "Top", displayName: "上", group: "余白",
                get: { d.top }, set: { d.top = $0 }
            ),
            .animation(
                id: "Bottom", displayName: "下", group: "余白",
                get: { d.bottom }, set: { d.bottom = $0 }
            ),
            .animation(
                id: "Left", displayName: "左", group: "余白",
                get: { d.left }, set: { d.left = $0 }
            ),
            .animation(
                id: "Right", displayName: "右", group: "余白",
                get: { d.right }, set: { d.right = $0 }
            )
        ]
    }

    /// ChromaKeyEffect2Definition の固有パラメータ。
    static func chromaKeyEffect2Descriptors(_ d: ChromaKeyEffect2Definition) -> [PropertyDescriptor] {
        [
            .enumeration(
                id: "DistanceMode", displayName: "色差計算方法", group: "クロマキー",
                options: chromakeyDistanceModeOptions,
                get: { d.distanceMode }, set: { d.distanceMode = $0 }
            ),
            .color(
                id: "KeyColor", displayName: "キー色", group: "クロマキー",
                get: { d.keyColor }, set: { d.keyColor = $0 }
            ),
            .animation(
                id: "Threshold2", displayName: "閾値", group: "クロマキー",
                get: { d.threshold2 }, set: { d.threshold2 = $0 }
            ),
            .animation(
                id: "Smoothness", displayName: "なめらかさ", group: "クロマキー",
                get: { d.smoothness }, set: { d.smoothness = $0 }
            ),
            .animation(
                id: "Despill", displayName: "色補正", group: "クロマキー",
                get: { d.despill }, set: { d.despill = $0 }
            ),
            .boolean(
                id: "IsInvert", displayName: "反転", group: "クロマキー",
                get: { d.isInvert }, set: { d.isInvert = $0 }
            )
        ]
    }

    /// ChromaKeyEffectDefinition の固有パラメータ。
    static func chromaKeyEffectDescriptors(_ d: ChromaKeyEffectDefinition) -> [PropertyDescriptor] {
        [
            .color(
                id: "Color", displayName: "キー色", group: "クロマキー",
                get: { d.color }, set: { d.color = $0 }
            ),
            .animation(
                id: "Tolerance", displayName: "色範囲", group: "クロマキー",
                get: { d.tolerance }, set: { d.tolerance = $0 }
            ),
            .boolean(
                id: "Feather", displayName: "境界をぼかす", group: "クロマキー",
                get: { d.feather }, set: { d.feather = $0 }
            ),
            .boolean(
                id: "IsInvert", displayName: "反転", group: "クロマキー",
                get: { d.isInvert }, set: { d.isInvert = $0 }
            )
        ]
    }

    /// FillBackgroundEffectDefinition の固有パラメータ。
    static func fillBackgroundEffectDescriptors(_ d: FillBackgroundEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Opacity", displayName: "不透明度", group: "背景塗りつぶし",
                get: { d.opacity }, set: { d.opacity = $0 }
            ),
            .animation(
                id: "Round", displayName: "角丸半径", group: "背景塗りつぶし",
                get: { d.round }, set: { d.round = $0 }
            ),
            .enumeration(
                id: "BlendMode", displayName: "合成モード", group: "背景塗りつぶし",
                options: blendOptions,
                get: { d.blendMode }, set: { d.blendMode = $0 }
            ),
            .boolean(
                id: "IsBackgroundOnly", displayName: "背景のみ", group: "背景塗りつぶし",
                get: { d.isBackgroundOnly }, set: { d.isBackgroundOnly = $0 }
            ),
            .animation(
                id: "Top", displayName: "上", group: "余白",
                get: { d.top }, set: { d.top = $0 }
            ),
            .animation(
                id: "Bottom", displayName: "下", group: "余白",
                get: { d.bottom }, set: { d.bottom = $0 }
            ),
            .animation(
                id: "Left", displayName: "左", group: "余白",
                get: { d.left }, set: { d.left = $0 }
            ),
            .animation(
                id: "Right", displayName: "右", group: "余白",
                get: { d.right }, set: { d.right = $0 }
            )
        ]
    }

    /// FillForegroundEffectDefinition の固有パラメータ。
    static func fillForegroundEffectDescriptors(_ d: FillForegroundEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Opacity", displayName: "不透明度", group: "前景塗りつぶし",
                get: { d.opacity }, set: { d.opacity = $0 }
            ),
            .enumeration(
                id: "BlendMode", displayName: "合成モード", group: "前景塗りつぶし",
                options: blendOptions,
                get: { d.blendMode }, set: { d.blendMode = $0 }
            ),
            .boolean(
                id: "IsBrushOnly", displayName: "模様のみ", group: "前景塗りつぶし",
                get: { d.isBrushOnly }, set: { d.isBrushOnly = $0 }
            )
        ]
    }

    /// FrameLineEffectDefinition の固有パラメータ。
    static func frameLineEffectDescriptors(_ d: FrameLineEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Opacity", displayName: "不透明度", group: "枠線",
                get: { d.opacity }, set: { d.opacity = $0 }
            ),
            .animation(
                id: "Thickness", displayName: "太さ", group: "枠線",
                get: { d.thickness }, set: { d.thickness = $0 }
            ),
            .enumeration(
                id: "RenderPlacement", displayName: "配置", group: "枠線",
                options: renderPlacementOptions,
                get: { d.renderPlacement }, set: { d.renderPlacement = $0 }
            ),
            .enumeration(
                id: "Type", displayName: "枠種類", group: "枠線",
                options: frameLineTypeOptions,
                get: { d.type }, set: { d.type = $0 }
            ),
            .animation(
                id: "Top", displayName: "上", group: "余白",
                get: { d.top }, set: { d.top = $0 }
            ),
            .animation(
                id: "Bottom", displayName: "下", group: "余白",
                get: { d.bottom }, set: { d.bottom = $0 }
            ),
            .animation(
                id: "Left", displayName: "左", group: "余白",
                get: { d.left }, set: { d.left = $0 }
            ),
            .animation(
                id: "Right", displayName: "右", group: "余白",
                get: { d.right }, set: { d.right = $0 }
            )
        ]
    }

    /// GradientEffectDefinition の固有パラメータ。
    static func gradientEffectDescriptors(_ d: GradientEffectDefinition) -> [PropertyDescriptor] {
        [
            .enumeration(
                id: "GradientType", displayName: "種類", group: "グラデーション",
                options: gradientTypeOptions,
                get: { d.gradientType }, set: { d.gradientType = $0 }
            ),
            .animation(
                id: "X", displayName: "X", group: "グラデーション",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "グラデーション",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Opacity", displayName: "不透明度", group: "グラデーション",
                get: { d.opacity }, set: { d.opacity = $0 }
            ),
            .animation(
                id: "Size", displayName: "サイズ", group: "グラデーション",
                get: { d.size }, set: { d.size = $0 }
            ),
            .animation(
                id: "Rotation", displayName: "回転角", group: "グラデーション",
                get: { d.rotation }, set: { d.rotation = $0 }
            ),
            .enumeration(
                id: "ExtendMode", displayName: "繰り返し", group: "グラデーション",
                options: extendModeOptions,
                get: { d.extendMode }, set: { d.extendMode = $0 }
            ),
            .enumeration(
                id: "Blend", displayName: "合成モード", group: "グラデーション",
                options: blendOptions,
                get: { d.blend }, set: { d.blend = $0 }
            )
        ]
    }

    /// InnerShadowEffectDefinition の固有パラメータ。
    static func innerShadowEffectDescriptors(_ d: InnerShadowEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "X", group: "影（内側）",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "影（内側）",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Opacity", displayName: "不透明度", group: "影（内側）",
                get: { d.opacity }, set: { d.opacity = $0 }
            ),
            .animation(
                id: "Blur", displayName: "ぼかし", group: "影（内側）",
                get: { d.blur }, set: { d.blur = $0 }
            ),
            .enumeration(
                id: "BlendMode", displayName: "合成モード", group: "影（内側）",
                options: blendOptions,
                get: { d.blendMode }, set: { d.blendMode = $0 }
            )
        ]
    }

    /// MaskEffectDefinition の固有パラメータ。
    static func maskEffectDescriptors(_ d: MaskEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "X", group: "図形切り抜き",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "図形切り抜き",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Opacity", displayName: "不透明度", group: "図形切り抜き",
                get: { d.opacity }, set: { d.opacity = $0 }
            ),
            .animation(
                id: "Angle", displayName: "回転角", group: "図形切り抜き",
                get: { d.angle }, set: { d.angle = $0 }
            ),
            .text(
                id: "ShapeType2", displayName: "種類", group: "図形切り抜き",
                get: { d.shapeType2 }, set: { d.shapeType2 = $0 }
            ),
            .animation(
                id: "Blur", displayName: "ぼかし", group: "図形切り抜き",
                get: { d.blur }, set: { d.blur = $0 }
            ),
            .boolean(
                id: "InvertMask", displayName: "領域反転", group: "図形切り抜き",
                get: { d.invertMask }, set: { d.invertMask = $0 }
            )
        ]
    }

    /// OutlineEffectDefinition の固有パラメータ。
    static func outlineEffectDescriptors(_ d: OutlineEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "StrokeThickness", displayName: "太さ", group: "縁取り",
                get: { d.strokeThickness }, set: { d.strokeThickness = $0 }
            ),
            .animation(
                id: "Blur", displayName: "ぼかし", group: "縁取り",
                get: { d.blur }, set: { d.blur = $0 }
            ),
            .animation(
                id: "Quality", displayName: "品質", group: "縁取り",
                get: { d.quality }, set: { d.quality = $0 }
            ),
            .animation(
                id: "Smoothness", displayName: "なめらかさ", group: "縁取り",
                get: { d.smoothness }, set: { d.smoothness = $0 }
            ),
            .animation(
                id: "X", displayName: "X", group: "縁取り / 描画",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "縁取り / 描画",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Opacity", displayName: "不透明度", group: "縁取り / 描画",
                get: { d.opacity }, set: { d.opacity = $0 }
            ),
            .animation(
                id: "Zoom", displayName: "拡大率", group: "縁取り / 描画",
                get: { d.zoom }, set: { d.zoom = $0 }
            ),
            .animation(
                id: "Rotation", displayName: "回転角", group: "縁取り / 描画",
                get: { d.rotation }, set: { d.rotation = $0 }
            ),
            .boolean(
                id: "IsOutlineOnly", displayName: "縁のみ", group: "縁取り",
                get: { d.isOutlineOnly }, set: { d.isOutlineOnly = $0 }
            ),
            .boolean(
                id: "IsAngular", displayName: "角縁取り", group: "縁取り",
                get: { d.isAngular }, set: { d.isAngular = $0 }
            )
        ]
    }

    /// ShadowEffectDefinition の固有パラメータ。
    static func shadowEffectDescriptors(_ d: ShadowEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "X", group: "影",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "影",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Opacity", displayName: "不透明度", group: "影",
                get: { d.opacity }, set: { d.opacity = $0 }
            ),
            .animation(
                id: "Zoom", displayName: "拡大率", group: "影",
                get: { d.zoom }, set: { d.zoom = $0 }
            ),
            .animation(
                id: "Angle", displayName: "回転角", group: "影",
                get: { d.angle }, set: { d.angle = $0 }
            ),
            .animation(
                id: "Blur", displayName: "ぼかし", group: "影",
                get: { d.blur }, set: { d.blur = $0 }
            ),
            .boolean(
                id: "IsRotateAtCenter", displayName: "中心で回転", group: "影",
                get: { d.isRotateAtCenter }, set: { d.isRotateAtCenter = $0 }
            )
        ]
    }

    /// TextureEffectDefinition の固有パラメータ。
    static func textureEffectDescriptors(_ d: TextureEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "X", group: "画像貼り付け",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "画像貼り付け",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Zoom", displayName: "拡大率", group: "画像貼り付け",
                get: { d.zoom }, set: { d.zoom = $0 }
            ),
            .animation(
                id: "Rotation", displayName: "回転角", group: "画像貼り付け",
                get: { d.rotation }, set: { d.rotation = $0 }
            ),
            .text(
                id: "FilePath", displayName: "ファイル", group: "画像貼り付け",
                get: { d.filePath }, set: { d.filePath = $0 }
            ),
            .number(
                id: "PlaybackRate", displayName: "再生速度", group: "画像貼り付け", range: -100000...100000,
                get: { d.playbackRate }, set: { d.playbackRate = $0 }
            ),
            .number(
                id: "ContentOffset", displayName: "再生位置", group: "画像貼り付け",
                get: { d.contentOffset.seconds }, set: { d.contentOffset = TimeSpanValue(seconds: $0) }
            ),
            .boolean(
                id: "IsInverted", displayName: "左右反転", group: "画像貼り付け",
                get: { d.isInverted }, set: { d.isInverted = $0 }
            )
        ]
    }
}
