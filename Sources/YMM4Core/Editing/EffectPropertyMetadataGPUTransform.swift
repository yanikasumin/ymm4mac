import Foundation

/// 映像エフェクト定義のプロパティメタデータ（GPUTransform 系）。
///
/// `EffectPropertyMetadata.descriptors(for:)` の具象定義別ビルダー。
/// 表示名・グループは本家の `Display` 属性（`Texts` リソース）、
/// 数値範囲は本家の `Range` / スライダ属性に根拠を持つ。
/// 根拠が取れない表示名はプロパティ名そのままにする。
public extension EffectPropertyMetadata {

    /// ArcBendEffectDefinition の固有パラメータ。
    static func arcBendEffectDescriptors(_ d: ArcBendEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "BendAngle", displayName: "曲げ角度", group: "湾曲",
                get: { d.bendAngle }, set: { d.bendAngle = $0 }
            ),
            .animation(
                id: "AxisAngle", displayName: "軸の角度", group: "湾曲",
                get: { d.axisAngle }, set: { d.axisAngle = $0 }
            ),
            .animation(
                id: "Anchor", displayName: "固定位置", group: "湾曲",
                get: { d.anchor }, set: { d.anchor = $0 }
            )
        ]
    }

    /// AutomaticZoomEffectDefinition の固有パラメータ。
    static func automaticZoomEffectDescriptors(_ d: AutomaticZoomEffectDefinition) -> [PropertyDescriptor] {
        [
            .enumeration(
                id: "AutomaticZoomMode", displayName: "モード", group: "画面内に収まるように拡大縮小",
                options: automaticZoomModeOptions,
                get: { d.automaticZoomMode }, set: { d.automaticZoomMode = $0 }
            ),
            .enumeration(
                id: "AutomaticZoomTarget", displayName: "対象", group: "画面内に収まるように拡大縮小",
                options: automaticZoomTargetOptions,
                get: { d.automaticZoomTarget }, set: { d.automaticZoomTarget = $0 }
            ),
            .animation(
                id: "AutomaticZoomMarginTop", displayName: "余白上下", group: "画面内に収まるように拡大縮小",
                get: { d.automaticZoomMarginTop }, set: { d.automaticZoomMarginTop = $0 }
            ),
            .animation(
                id: "AutomaticZoomMarginLeft", displayName: "余白左右", group: "画面内に収まるように拡大縮小",
                get: { d.automaticZoomMarginLeft }, set: { d.automaticZoomMarginLeft = $0 }
            ),
            .boolean(
                id: "IgnoreRotation", displayName: "回転を無視", group: "画面内に収まるように拡大縮小",
                get: { d.ignoreRotation }, set: { d.ignoreRotation = $0 }
            )
        ]
    }

    /// CenterPointEffectDefinition の固有パラメータ。
    static func centerPointEffectDescriptors(_ d: CenterPointEffectDefinition) -> [PropertyDescriptor] {
        [
            .enumeration(
                id: "Horizontal", displayName: "水平位置", group: "中心位置",
                options: centerPointHorizontalOptions,
                get: { d.horizontal }, set: { d.horizontal = $0 }
            ),
            .enumeration(
                id: "Vertical", displayName: "垂直位置", group: "中心位置",
                options: centerPointVerticalOptions,
                get: { d.vertical }, set: { d.vertical = $0 }
            ),
            .animation(
                id: "X", displayName: "X", group: "中心位置",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "中心位置",
                get: { d.y }, set: { d.y = $0 }
            ),
            .boolean(
                id: "IsKeepPosition", displayName: "位置を保持", group: "中心位置",
                get: { d.isKeepPosition }, set: { d.isKeepPosition = $0 }
            )
        ]
    }

    /// CircularDuplicatorEffectDefinition の固有パラメータ。
    static func circularDuplicatorEffectDescriptors(_ d: CircularDuplicatorEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Count", displayName: "配置数", group: "円形配置",
                get: { d.count }, set: { d.count = $0 }
            ),
            .animation(
                id: "Radius", displayName: "半径", group: "円形配置",
                get: { d.radius }, set: { d.radius = $0 }
            ),
            .animation(
                id: "CircumferenceRate", displayName: "円周", group: "円形配置",
                get: { d.circumferenceRate }, set: { d.circumferenceRate = $0 }
            ),
            .boolean(
                id: "IsSyncedAngle", displayName: "回転を同期", group: "円形配置",
                get: { d.isSyncedAngle }, set: { d.isSyncedAngle = $0 }
            )
        ]
    }

    /// CopyAndReverseEffectDefinition の固有パラメータ。
    static func copyAndReverseEffectDescriptors(_ d: CopyAndReverseEffectDefinition) -> [PropertyDescriptor] {
        [
            .enumeration(
                id: "Position", displayName: "位置", group: "複製して反転",
                options: topBottomLeftRightOptions,
                get: { d.position }, set: { d.position = $0 }
            ),
            .animation(
                id: "Distance", displayName: "距離", group: "複製して反転",
                get: { d.distance }, set: { d.distance = $0 }
            ),
            .boolean(
                id: "IsTopBottomReversed", displayName: "上下反転", group: "複製して反転",
                get: { d.isTopBottomReversed }, set: { d.isTopBottomReversed = $0 }
            ),
            .boolean(
                id: "IsLeftRightReversed", displayName: "左右反転", group: "複製して反転",
                get: { d.isLeftRightReversed }, set: { d.isLeftRightReversed = $0 }
            ),
            .boolean(
                id: "IsCentering", displayName: "中央寄せ", group: "複製して反転",
                get: { d.isCentering }, set: { d.isCentering = $0 }
            )
        ]
    }

    /// CrashEffectDefinition の固有パラメータ。
    static func crashEffectDescriptors(_ d: CrashEffectDefinition) -> [PropertyDescriptor] {
        [
            .number(
                id: "StartTime", displayName: "開始時間", group: "砕け散る", range: -100000...100000,
                get: { d.startTime }, set: { d.startTime = $0 }
            ),
            .number(
                id: "PlaybackRate", displayName: "再生速度", group: "砕け散る", range: -100000...100000,
                get: { d.playbackRate }, set: { d.playbackRate = $0 }
            ),
            .number(
                id: "Size", displayName: "破片の大きさ", group: "砕け散る", range: 0...100000,
                get: { d.size }, set: { d.size = $0 }
            ),
            .animation(
                id: "X", displayName: "X", group: "砕け始める位置",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "砕け始める位置",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Z", displayName: "Z", group: "砕け始める位置",
                get: { d.z }, set: { d.z = $0 }
            ),
            .number(
                id: "FlySpeed", displayName: "飛散速度", group: "アニメーション詳細", range: 0...100000,
                get: { d.flySpeed }, set: { d.flySpeed = $0 }
            ),
            .number(
                id: "FallSpeed", displayName: "落下速度", group: "アニメーション詳細", range: 0...100000,
                get: { d.fallSpeed }, set: { d.fallSpeed = $0 }
            ),
            .number(
                id: "Delay", displayName: "時間差", group: "アニメーション詳細", range: 0...100000,
                get: { d.delay }, set: { d.delay = $0 }
            ),
            .number(
                id: "Impact", displayName: "距離影響", group: "アニメーション詳細", range: 0...100000,
                get: { d.impact }, set: { d.impact = $0 }
            ),
            .number(
                id: "RandomRotate", displayName: "ランダム回転", group: "アニメーション詳細", range: 0...100000,
                get: { d.randomRotate }, set: { d.randomRotate = $0 }
            ),
            .number(
                id: "RandomVector", displayName: "ランダム方向", group: "アニメーション詳細", range: 0...100000,
                get: { d.randomVector }, set: { d.randomVector = $0 }
            )
        ]
    }

    /// CropByAngleEffectDefinition の固有パラメータ。
    static func cropByAngleEffectDescriptors(_ d: CropByAngleEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "X", group: "斜めクリッピング",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "斜めクリッピング",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Angle", displayName: "角度", group: "斜めクリッピング",
                get: { d.angle }, set: { d.angle = $0 }
            ),
            .animation(
                id: "Blur", displayName: "ぼかし", group: "斜めクリッピング",
                get: { d.blur }, set: { d.blur = $0 }
            ),
            .animation(
                id: "Width", displayName: "幅", group: "斜めクリッピング",
                get: { d.width }, set: { d.width = $0 }
            )
        ]
    }

    /// CropEffectDefinition の固有パラメータ。
    static func cropEffectDescriptors(_ d: CropEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Top", displayName: "上", group: "クリッピング",
                get: { d.top }, set: { d.top = $0 }
            ),
            .animation(
                id: "Bottom", displayName: "下", group: "クリッピング",
                get: { d.bottom }, set: { d.bottom = $0 }
            ),
            .animation(
                id: "Left", displayName: "左", group: "クリッピング",
                get: { d.left }, set: { d.left = $0 }
            ),
            .animation(
                id: "Right", displayName: "右", group: "クリッピング",
                get: { d.right }, set: { d.right = $0 }
            ),
            .boolean(
                id: "IsCentering", displayName: "中央寄せ", group: "クリッピング",
                get: { d.isCentering }, set: { d.isCentering = $0 }
            )
        ]
    }

    /// DisplacementMapEffectDefinition の固有パラメータ。
    static func displacementMapEffectDescriptors(_ d: DisplacementMapEffectDefinition) -> [PropertyDescriptor] {
        [
            .enumeration(
                id: "Mode", displayName: "変形方法", group: "ディスプレイスメントマップ",
                options: displacementMapTransformModeOptions,
                get: { d.mode }, set: { d.mode = $0 }
            ),
            preservedDescriptor(
                id: "Transform", displayName: "Transform", group: "ディスプレイスメントマップ",
                get: { d.transform }, set: { d.transform = $0 }
            ),
            .animation(
                id: "Blur", displayName: "ぼかし度", group: "ディスプレイスメントマップ",
                get: { d.blur }, set: { d.blur = $0 }
            ),
            .boolean(
                id: "IsPatternMapPreviewEnabled", displayName: "パターンを表示", group: "ディスプレイスメントマップ",
                get: { d.isPatternMapPreviewEnabled }, set: { d.isPatternMapPreviewEnabled = $0 }
            ),
            preservedDescriptor(
                id: "Brush", displayName: "Brush", group: "ディスプレイスメントマップ",
                get: { d.brush }, set: { d.brush = $0 }
            )
        ]
    }

    /// DrawLazyEffectEffectDefinition の固有パラメータ。
    static func drawLazyEffectEffectDescriptors(_ d: DrawLazyEffectEffectDefinition) -> [PropertyDescriptor] {
        [
            .boolean(
                id: "IsXYZ", displayName: "X/Y/Z", group: "適用する項目",
                get: { d.isXYZ }, set: { d.isXYZ = $0 }
            ),
            .boolean(
                id: "IsOpacity", displayName: "不透明度", group: "適用する項目",
                get: { d.isOpacity }, set: { d.isOpacity = $0 }
            ),
            .boolean(
                id: "IsZoom", displayName: "拡大率", group: "適用する項目",
                get: { d.isZoom }, set: { d.isZoom = $0 }
            ),
            .boolean(
                id: "IsRotation", displayName: "回転角", group: "適用する項目",
                get: { d.isRotation }, set: { d.isRotation = $0 }
            ),
            .boolean(
                id: "IsInvert", displayName: "左右反転", group: "適用する項目",
                get: { d.isInvert }, set: { d.isInvert = $0 }
            ),
            .boolean(
                id: "IsCamera", displayName: "カメラ位置", group: "適用する項目",
                get: { d.isCamera }, set: { d.isCamera = $0 }
            )
        ]
    }

    /// JumpEffectDefinition の固有パラメータ。
    static func jumpEffectDescriptors(_ d: JumpEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "JumpHeight", displayName: "高さ", group: "跳ねる",
                get: { d.jumpHeight }, set: { d.jumpHeight = $0 }
            ),
            .animation(
                id: "Stretch", displayName: "伸び", group: "跳ねる",
                get: { d.stretch }, set: { d.stretch = $0 }
            ),
            .animation(
                id: "Period", displayName: "周期", group: "跳ねる",
                get: { d.period }, set: { d.period = $0 }
            ),
            .animation(
                id: "Distortion", displayName: "歪み", group: "着地",
                get: { d.distortion }, set: { d.distortion = $0 }
            ),
            .animation(
                id: "Interval", displayName: "間隔", group: "着地",
                get: { d.interval }, set: { d.interval = $0 }
            ),
            .animation(
                id: "X", displayName: "X", group: "移動先",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "移動先",
                get: { d.y }, set: { d.y = $0 }
            )
        ]
    }

    /// MarginEffectDefinition の固有パラメータ。
    static func marginEffectDescriptors(_ d: MarginEffectDefinition) -> [PropertyDescriptor] {
        [
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

    /// MeshDeformationEffectDefinition の固有パラメータ。
    static func meshDeformationEffectDescriptors(_ d: MeshDeformationEffectDefinition) -> [PropertyDescriptor] {
        [
            .integer(
                id: "HorizontalCount", displayName: "横制御点数", group: "メッシュ変形", range: 2...32,
                get: { d.horizontalCount }, set: { d.horizontalCount = $0 }
            ),
            .integer(
                id: "VerticalCount", displayName: "縦制御点数", group: "メッシュ変形", range: 2...32,
                get: { d.verticalCount }, set: { d.verticalCount = $0 }
            ),
            .animation(
                id: "Smoothness", displayName: "なめらかさ", group: "メッシュ変形",
                get: { d.smoothness }, set: { d.smoothness = $0 }
            ),
            meshPointsCollection(d)
        ]
    }

    /// MorphologyEffectDefinition の固有パラメータ。
    static func morphologyEffectDescriptors(_ d: MorphologyEffectDefinition) -> [PropertyDescriptor] {
        [
            .enumeration(
                id: "Mode", displayName: "モード", group: "抽象化",
                options: morphologyEffectModeOptions,
                get: { d.mode }, set: { d.mode = $0 }
            ),
            .animation(
                id: "Width", displayName: "幅", group: "抽象化",
                get: { d.width }, set: { d.width = $0 }
            ),
            .animation(
                id: "Height", displayName: "高さ", group: "抽象化",
                get: { d.height }, set: { d.height = $0 }
            )
        ]
    }

    /// NoiseDisplacementMapEffectDefinition の固有パラメータ。
    static func noiseDisplacementMapEffectDescriptors(_ d: NoiseDisplacementMapEffectDefinition) -> [PropertyDescriptor] {
        [
            .enumeration(
                id: "Mode", displayName: "変形方法", group: "ノイズ歪み",
                options: displacementMapTransformModeOptions,
                get: { d.mode }, set: { d.mode = $0 }
            ),
            preservedDescriptor(
                id: "Transform", displayName: "Transform", group: "ノイズ歪み",
                get: { d.transform }, set: { d.transform = $0 }
            ),
            .animation(
                id: "Blur", displayName: "ぼかし度", group: "ノイズ歪み",
                get: { d.blur }, set: { d.blur = $0 }
            ),
            .enumeration(
                id: "NoiseType", displayName: "種類", group: "ノイズ",
                options: noiseTypeOptions,
                get: { d.noiseType }, set: { d.noiseType = $0 }
            ),
            preservedDescriptor(
                id: "NoiseParameter", displayName: "NoiseParameter", group: "ノイズ",
                get: { d.noiseParameter }, set: { d.noiseParameter = $0 }
            )
        ]
    }

    /// NoiseEffectDefinition の固有パラメータ。
    static func noiseEffectDescriptors(_ d: NoiseEffectDefinition) -> [PropertyDescriptor] {
        [
            .enumeration(
                id: "NoiseType", displayName: "種類", group: "ノイズ",
                options: noiseTypeOptions,
                get: { d.noiseType }, set: { d.noiseType = $0 }
            ),
            preservedDescriptor(
                id: "NoiseParameter", displayName: "NoiseParameter", group: "ノイズ",
                get: { d.noiseParameter }, set: { d.noiseParameter = $0 }
            ),
            .boolean(
                id: "IsColor", displayName: "色", group: "ノイズ",
                get: { d.isColor }, set: { d.isColor = $0 }
            ),
            .boolean(
                id: "IsAlpha", displayName: "不透明度", group: "ノイズ",
                get: { d.isAlpha }, set: { d.isAlpha = $0 }
            ),
            .boolean(
                id: "IsUniqueSeed", displayName: "個別シード値", group: "ノイズ",
                get: { d.isUniqueSeed }, set: { d.isUniqueSeed = $0 }
            )
        ]
    }

    /// PolarTransformEffectDefinition の固有パラメータ。
    static func polarTransformEffectDescriptors(_ d: PolarTransformEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "CoreWidth", displayName: "中心幅", group: "極座標変換",
                get: { d.coreWidth }, set: { d.coreWidth = $0 }
            ),
            .animation(
                id: "TwistAngle", displayName: "ねじれ角", group: "極座標変換",
                get: { d.twistAngle }, set: { d.twistAngle = $0 }
            )
        ]
    }

    /// RandomDuplicatorEffectDefinition の固有パラメータ。
    static func randomDuplicatorEffectDescriptors(_ d: RandomDuplicatorEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Count", displayName: "配置数", group: "ランダム配置",
                get: { d.count }, set: { d.count = $0 }
            ),
            .animation(
                id: "Range", displayName: "範囲", group: "ランダム配置",
                get: { d.range }, set: { d.range = $0 }
            ),
            .animation(
                id: "Rotation", displayName: "最大回転角", group: "ランダム配置",
                get: { d.rotation }, set: { d.rotation = $0 }
            ),
            .boolean(
                id: "IsThreeDimensional", displayName: "三次元配置", group: "ランダム配置",
                get: { d.isThreeDimensional }, set: { d.isThreeDimensional = $0 }
            ),
            .animation(
                id: "RandomMove", displayName: "最大移動速度", group: "ランダム移動",
                get: { d.randomMove }, set: { d.randomMove = $0 }
            ),
            .animation(
                id: "RandomRotation", displayName: "最大回転速度", group: "ランダム移動",
                get: { d.randomRotation }, set: { d.randomRotation = $0 }
            )
        ]
    }

    /// RotateEffectDefinition の固有パラメータ。
    static func rotateEffectDescriptors(_ d: RotateEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "X軸", group: "3D回転",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y軸", group: "3D回転",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Z", displayName: "Z軸", group: "3D回転",
                get: { d.z }, set: { d.z = $0 }
            ),
            .boolean(
                id: "Is3D", displayName: "三次元配置", group: "3D回転",
                get: { d.is3D }, set: { d.is3D = $0 }
            )
        ]
    }

    /// RoundCornerEffectDefinition の固有パラメータ。
    static func roundCornerEffectDescriptors(_ d: RoundCornerEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Radius", displayName: "半径", group: "角丸め",
                get: { d.radius }, set: { d.radius = $0 }
            ),
            .animation(
                id: "Blur", displayName: "ぼかし", group: "角丸め",
                get: { d.blur }, set: { d.blur = $0 }
            )
        ]
    }

    /// SkewEffectDefinition の固有パラメータ。
    static func skewEffectDescriptors(_ d: SkewEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "AngleX", displayName: "X方向", group: "傾斜変形",
                get: { d.angleX }, set: { d.angleX = $0 }
            ),
            .animation(
                id: "AngleY", displayName: "Y方向", group: "傾斜変形",
                get: { d.angleY }, set: { d.angleY = $0 }
            ),
            .enumeration(
                id: "CenterPoint", displayName: "中心", group: "傾斜変形",
                options: skewCenterPointOptions,
                get: { d.centerPoint }, set: { d.centerPoint = $0 }
            ),
            .animation(
                id: "CenterX", displayName: "中心X", group: "傾斜変形",
                get: { d.centerX }, set: { d.centerX = $0 }
            ),
            .animation(
                id: "CenterY", displayName: "中心Y", group: "傾斜変形",
                get: { d.centerY }, set: { d.centerY = $0 }
            )
        ]
    }

    /// TilingEffectDefinition の固有パラメータ。
    static func tilingEffectDescriptors(_ d: TilingEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "横", group: "敷き詰め",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "縦", group: "敷き詰め",
                get: { d.y }, set: { d.y = $0 }
            )
        ]
    }
}
