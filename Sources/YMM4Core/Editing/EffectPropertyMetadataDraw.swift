import Foundation

/// 映像エフェクト定義のプロパティメタデータ（Draw 系）。
///
/// `EffectPropertyMetadata.descriptors(for:)` の具象定義別ビルダー。
/// 表示名・グループは本家の `Display` 属性（`Texts` リソース）、
/// 数値範囲は本家の `Range` / スライダ属性に根拠を持つ。
/// 根拠が取れない表示名はプロパティ名そのままにする。
public extension EffectPropertyMetadata {

    /// BillboardEffectDefinition の固有パラメータ。
    static func billboardEffectDescriptors(_ d: BillboardEffectDefinition) -> [PropertyDescriptor] {
        [
            PropertyDescriptor(
                id: "Mode", displayName: "モード", group: "ビルボード",
                kind: .enumeration(options: billboardModeOptions),
                access: .enumeration(
                    get: { d.unrecognizedModeName ?? Self.billboardModeName(d.mode) },
                    set: { name in
                        switch name {
                        case "None": d.mode = .none
                        case "Spherical": d.mode = .spherical
                        case "Cylindrical": d.mode = .cylindrical
                        default: break
                        }
                    }
                )
            )
        ]
    }

    /// CameraFovEffectDefinition の固有パラメータ。
    static func cameraFovEffectDescriptors(_ d: CameraFovEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Fov", displayName: "視野角", group: "視野角",
                get: { d.fov }, set: { d.fov = $0 }
            )
        ]
    }

    /// CameraLookAtEffectDefinition の固有パラメータ。
    static func cameraLookAtEffectDescriptors(_ d: CameraLookAtEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "X", group: "注目カメラ",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "注目カメラ",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Z", displayName: "Z", group: "注目カメラ",
                get: { d.z }, set: { d.z = $0 }
            ),
            .animation(
                id: "LookAtX", displayName: "注目X", group: "注目カメラ",
                get: { d.lookAtX }, set: { d.lookAtX = $0 }
            ),
            .animation(
                id: "LookAtY", displayName: "注目Y", group: "注目カメラ",
                get: { d.lookAtY }, set: { d.lookAtY = $0 }
            ),
            .animation(
                id: "LookAtZ", displayName: "注目Z", group: "注目カメラ",
                get: { d.lookAtZ }, set: { d.lookAtZ = $0 }
            ),
            .animation(
                id: "RotationZ", displayName: "傾き", group: "注目カメラ",
                get: { d.rotationZ }, set: { d.rotationZ = $0 }
            ),
            .boolean(
                id: "ChangeFov", displayName: "視野角変更", group: "注目カメラ",
                get: { d.changeFov }, set: { d.changeFov = $0 }
            ),
            .animation(
                id: "Fov", displayName: "視野角", group: "注目カメラ",
                get: { d.fov }, set: { d.fov = $0 }
            )
        ]
    }

    /// CameraPositionEffectDefinition の固有パラメータ。
    static func cameraPositionEffectDescriptors(_ d: CameraPositionEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "X", group: "カメラ位置",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "カメラ位置",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Z", displayName: "Z", group: "カメラ位置",
                get: { d.z }, set: { d.z = $0 }
            ),
            .animation(
                id: "RotationY", displayName: "水平回転", group: "カメラ位置",
                get: { d.rotationY }, set: { d.rotationY = $0 }
            ),
            .animation(
                id: "RotationX", displayName: "垂直回転", group: "カメラ位置",
                get: { d.rotationX }, set: { d.rotationX = $0 }
            ),
            .animation(
                id: "RotationZ", displayName: "傾き", group: "カメラ位置",
                get: { d.rotationZ }, set: { d.rotationZ = $0 }
            ),
            .boolean(
                id: "ChangeFov", displayName: "視野角変更", group: "カメラ位置",
                get: { d.changeFov }, set: { d.changeFov = $0 }
            ),
            .animation(
                id: "Fov", displayName: "視野角", group: "カメラ位置",
                get: { d.fov }, set: { d.fov = $0 }
            )
        ]
    }

    /// CameraWraparoundEffectDefinition の固有パラメータ。
    static func cameraWraparoundEffectDescriptors(_ d: CameraWraparoundEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "中心X", group: "回り込みカメラ",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "中心Y", group: "回り込みカメラ",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Z", displayName: "中心Z", group: "回り込みカメラ",
                get: { d.z }, set: { d.z = $0 }
            ),
            .animation(
                id: "Radius", displayName: "距離", group: "回り込みカメラ",
                get: { d.radius }, set: { d.radius = $0 }
            ),
            .animation(
                id: "RotationY", displayName: "水平回転", group: "回り込みカメラ",
                get: { d.rotationY }, set: { d.rotationY = $0 }
            ),
            .animation(
                id: "RotationX", displayName: "垂直回転", group: "回り込みカメラ",
                get: { d.rotationX }, set: { d.rotationX = $0 }
            ),
            .animation(
                id: "RotationZ", displayName: "傾き", group: "回り込みカメラ",
                get: { d.rotationZ }, set: { d.rotationZ = $0 }
            ),
            .boolean(
                id: "ChangeFov", displayName: "視野角変更", group: "回り込みカメラ",
                get: { d.changeFov }, set: { d.changeFov = $0 }
            ),
            .animation(
                id: "Fov", displayName: "視野角", group: "回り込みカメラ",
                get: { d.fov }, set: { d.fov = $0 }
            )
        ]
    }

    /// InOutFadeEffectDefinition の固有パラメータ。
    static func inOutFadeEffectDescriptors(_ d: InOutFadeEffectDefinition) -> [PropertyDescriptor] {
        [
            .number(
                id: "Value", displayName: "不透明度", group: "登場退場", range: 0...100,
                get: { d.value }, set: { d.value = $0 }
            ),
            .boolean(
                id: "IsInEffect", displayName: "登場時", group: "登場退場",
                get: { d.isInEffect }, set: { d.isInEffect = $0 }
            ),
            .boolean(
                id: "IsOutEffect", displayName: "退場時", group: "登場退場",
                get: { d.isOutEffect }, set: { d.isOutEffect = $0 }
            ),
            .number(
                id: "EffectTimeSeconds", displayName: "効果時間", group: "登場退場", range: 0...100000,
                get: { d.effectTimeSeconds }, set: { d.effectTimeSeconds = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "登場退場",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "登場退場",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            )
        ]
    }

    /// InOutMoveEffectDefinition の固有パラメータ。
    static func inOutMoveEffectDescriptors(_ d: InOutMoveEffectDefinition) -> [PropertyDescriptor] {
        [
            .number(
                id: "Value", displayName: "X", group: "登場退場", range: -100000...100000,
                get: { d.value }, set: { d.value = $0 }
            ),
            .number(
                id: "Value2", displayName: "Y", group: "登場退場", range: -100000...100000,
                get: { d.value2 }, set: { d.value2 = $0 }
            ),
            .number(
                id: "Value3", displayName: "Z", group: "登場退場", range: -100000...100000,
                get: { d.value3 }, set: { d.value3 = $0 }
            ),
            .boolean(
                id: "IsInEffect", displayName: "登場時", group: "登場退場",
                get: { d.isInEffect }, set: { d.isInEffect = $0 }
            ),
            .boolean(
                id: "IsOutEffect", displayName: "退場時", group: "登場退場",
                get: { d.isOutEffect }, set: { d.isOutEffect = $0 }
            ),
            .number(
                id: "EffectTimeSeconds", displayName: "効果時間", group: "登場退場", range: 0...100000,
                get: { d.effectTimeSeconds }, set: { d.effectTimeSeconds = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "登場退場",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "登場退場",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            )
        ]
    }

    /// InOutMoveFromOutsideFrameEffectDefinition の固有パラメータ。
    static func inOutMoveFromOutsideFrameEffectDescriptors(_ d: InOutMoveFromOutsideFrameEffectDefinition) -> [PropertyDescriptor] {
        [
            .enumeration(
                id: "Value", displayName: "方向", group: "登場退場",
                options: topBottomLeftRightOptions,
                get: { d.value }, set: { d.value = $0 }
            ),
            .boolean(
                id: "IsInEffect", displayName: "登場時", group: "登場退場",
                get: { d.isInEffect }, set: { d.isInEffect = $0 }
            ),
            .boolean(
                id: "IsOutEffect", displayName: "退場時", group: "登場退場",
                get: { d.isOutEffect }, set: { d.isOutEffect = $0 }
            ),
            .number(
                id: "EffectTimeSeconds", displayName: "効果時間", group: "登場退場", range: 0...100000,
                get: { d.effectTimeSeconds }, set: { d.effectTimeSeconds = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "登場退場",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "登場退場",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            )
        ]
    }

    /// InOutZoomEffectDefinition の固有パラメータ。
    static func inOutZoomEffectDescriptors(_ d: InOutZoomEffectDefinition) -> [PropertyDescriptor] {
        [
            .number(
                id: "Value", displayName: "全体", group: "登場退場", range: 0...100000,
                get: { d.value }, set: { d.value = $0 }
            ),
            .number(
                id: "X", displayName: "横方向", group: "登場退場", range: 0...100000,
                get: { d.x }, set: { d.x = $0 }
            ),
            .number(
                id: "Y", displayName: "縦方向", group: "登場退場", range: 0...100000,
                get: { d.y }, set: { d.y = $0 }
            ),
            .boolean(
                id: "IsInEffect", displayName: "登場時", group: "登場退場",
                get: { d.isInEffect }, set: { d.isInEffect = $0 }
            ),
            .boolean(
                id: "IsOutEffect", displayName: "退場時", group: "登場退場",
                get: { d.isOutEffect }, set: { d.isOutEffect = $0 }
            ),
            .number(
                id: "EffectTimeSeconds", displayName: "効果時間", group: "登場退場", range: 0...100000,
                get: { d.effectTimeSeconds }, set: { d.effectTimeSeconds = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "登場退場",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "登場退場",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            )
        ]
    }

    /// MotionTrackingEffectDefinition の固有パラメータ。
    static func motionTrackingEffectDescriptors(_ d: MotionTrackingEffectDefinition) -> [PropertyDescriptor] {
        [
            .integer(
                id: "Smooth", displayName: "なめらかさ", group: "モーショントラッキング", range: 0...100,
                get: { d.smooth }, set: { d.smooth = $0 }
            ),
            .boolean(
                id: "IsReverce", displayName: "軌道を反転", group: "モーショントラッキング",
                get: { d.isReverce }, set: { d.isReverce = $0 }
            ),
            .boolean(
                id: "IsReverseZoom", displayName: "拡大率を反転", group: "モーショントラッキング",
                get: { d.isReverseZoom }, set: { d.isReverseZoom = $0 }
            ),
            .boolean(
                id: "IsFixedSize", displayName: "サイズを固定", group: "モーショントラッキング",
                get: { d.isFixedSize }, set: { d.isFixedSize = $0 }
            ),
            motionTrackingPathDescriptor(d),
            .number(
                id: "ControlPointVisibleSeconds", displayName: "制御点表示", group: "制御点", range: 0...60,
                get: { d.controlPointVisibleSeconds }, set: { d.controlPointVisibleSeconds = $0 }
            ),
            .boolean(
                id: "IsOnlyCurrentFrameRectLine", displayName: "簡易表示", group: "制御点",
                get: { d.isOnlyCurrentFrameRectLine }, set: { d.isOnlyCurrentFrameRectLine = $0 }
            )
        ]
    }

    /// PolarDrawPositionEffectDefinition の固有パラメータ。
    static func polarDrawPositionEffectDescriptors(_ d: PolarDrawPositionEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Radius", displayName: "半径", group: "描画位置（極座標）",
                get: { d.radius }, set: { d.radius = $0 }
            ),
            .animation(
                id: "Angle", displayName: "角度", group: "描画位置（極座標）",
                get: { d.angle }, set: { d.angle = $0 }
            ),
            .animation(
                id: "Angle2", displayName: "角度φ", group: "描画位置（極座標）",
                get: { d.angle2 }, set: { d.angle2 = $0 }
            ),
            .boolean(
                id: "IsSyncRotation", displayName: "回転を同期", group: "描画位置（極座標）",
                get: { d.isSyncRotation }, set: { d.isSyncRotation = $0 }
            )
        ]
    }

    /// RandomMoveEffectDefinition の固有パラメータ。
    static func randomMoveEffectDescriptors(_ d: RandomMoveEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "X", group: "ランダム",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "ランダム",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Z", displayName: "Z", group: "ランダム",
                get: { d.z }, set: { d.z = $0 }
            ),
            .animation(
                id: "Span", displayName: "間隔", group: "ランダム",
                get: { d.span }, set: { d.span = $0 }
            )
        ]
    }

    /// RandomOpacityEffectDefinition の固有パラメータ。
    static func randomOpacityEffectDescriptors(_ d: RandomOpacityEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Opacity", displayName: "不透明度", group: "ランダム",
                get: { d.opacity }, set: { d.opacity = $0 }
            ),
            .animation(
                id: "Span", displayName: "間隔", group: "ランダム",
                get: { d.span }, set: { d.span = $0 }
            )
        ]
    }

    /// RandomZoomEffectDefinition の固有パラメータ。
    static func randomZoomEffectDescriptors(_ d: RandomZoomEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Zoom", displayName: "全体", group: "ランダム",
                get: { d.zoom }, set: { d.zoom = $0 }
            ),
            .animation(
                id: "ZoomX", displayName: "横方向", group: "ランダム",
                get: { d.zoomX }, set: { d.zoomX = $0 }
            ),
            .animation(
                id: "ZoomY", displayName: "縦方向", group: "ランダム",
                get: { d.zoomY }, set: { d.zoomY = $0 }
            ),
            .animation(
                id: "Span", displayName: "間隔", group: "ランダム",
                get: { d.span }, set: { d.span = $0 }
            )
        ]
    }

    /// RepeatMoveEffectDefinition の固有パラメータ。
    static func repeatMoveEffectDescriptors(_ d: RepeatMoveEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "X", group: "繰り返し",
                get: { d.x }, set: { d.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: "繰り返し",
                get: { d.y }, set: { d.y = $0 }
            ),
            .animation(
                id: "Z", displayName: "Z", group: "繰り返し",
                get: { d.z }, set: { d.z = $0 }
            ),
            .animation(
                id: "Span", displayName: "間隔", group: "繰り返し",
                get: { d.span }, set: { d.span = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "繰り返し",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "繰り返し",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            ),
            .boolean(
                id: "IsCentering", displayName: "中央寄せ", group: "繰り返し",
                get: { d.isCentering }, set: { d.isCentering = $0 }
            )
        ]
    }

    /// RepeatOpacityEffectDefinition の固有パラメータ。
    static func repeatOpacityEffectDescriptors(_ d: RepeatOpacityEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Opacity", displayName: "不透明度", group: "繰り返し",
                get: { d.opacity }, set: { d.opacity = $0 }
            ),
            .animation(
                id: "Span", displayName: "間隔", group: "繰り返し",
                get: { d.span }, set: { d.span = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "繰り返し",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "繰り返し",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            )
        ]
    }

    /// RepeatZoomEffectDefinition の固有パラメータ。
    static func repeatZoomEffectDescriptors(_ d: RepeatZoomEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "Zoom", displayName: "全体", group: "繰り返し",
                get: { d.zoom }, set: { d.zoom = $0 }
            ),
            .animation(
                id: "ZoomX", displayName: "横方向", group: "繰り返し",
                get: { d.zoomX }, set: { d.zoomX = $0 }
            ),
            .animation(
                id: "ZoomY", displayName: "縦方向", group: "繰り返し",
                get: { d.zoomY }, set: { d.zoomY = $0 }
            ),
            .animation(
                id: "Span", displayName: "間隔", group: "繰り返し",
                get: { d.span }, set: { d.span = $0 }
            ),
            easingFamilyDescriptor(
                id: "EasingType", displayName: "種類", group: "繰り返し",
                get: { d.easingFamily }, set: { d.easingFamily = $0 }
            ),
            easingModeDescriptor(
                id: "EasingMode", displayName: "加減速", group: "繰り返し",
                get: { d.easingMode }, set: { d.easingMode = $0 }
            ),
            .boolean(
                id: "IsCentering", displayName: "中央寄せ", group: "繰り返し",
                get: { d.isCentering }, set: { d.isCentering = $0 }
            )
        ]
    }

    /// ShowOnlyPreviewEffectDefinition の固有パラメータ。
    static func showOnlyPreviewEffectDescriptors(_ d: ShowOnlyPreviewEffectDefinition) -> [PropertyDescriptor] {
        [
            .boolean(
                id: "IsPlaying", displayName: "再生時", group: "プレビュー時にのみ表示",
                get: { d.isPlaying }, set: { d.isPlaying = $0 }
            ),
            .boolean(
                id: "IsPaused", displayName: "一時停止時", group: "プレビュー時にのみ表示",
                get: { d.isPaused }, set: { d.isPaused = $0 }
            )
        ]
    }

    /// XYToPolarTransformEffectDefinition の固有パラメータ。
    static func xYToPolarTransformEffectDescriptors(_ d: XYToPolarTransformEffectDefinition) -> [PropertyDescriptor] {
        [
            .animation(
                id: "XRange", displayName: "X範囲", group: "極座標変換（描画位置）",
                get: { d.xRange }, set: { d.xRange = $0 }
            ),
            .animation(
                id: "ZRange", displayName: "Z範囲", group: "極座標変換（描画位置）",
                get: { d.zRange }, set: { d.zRange = $0 }
            ),
            .boolean(
                id: "IsClockwise", displayName: "時計回り", group: "極座標変換（描画位置）",
                get: { d.isClockwise }, set: { d.isClockwise = $0 }
            ),
            .boolean(
                id: "IsSyncRotation", displayName: "回転を同期", group: "極座標変換（描画位置）",
                get: { d.isSyncRotation }, set: { d.isSyncRotation = $0 }
            )
        ]
    }
}
