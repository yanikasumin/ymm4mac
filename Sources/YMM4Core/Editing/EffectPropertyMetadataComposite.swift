import Foundation

/// 複合プロパティの記述子構築（FXMETA-COMP）。
///
/// 本家で入れ子の専用エディタを使う複合プロパティ18件を、記述子体系へ
/// 1層だけ足した `.object` / `.collection` で対象化する。対象は
/// FXMETA で対象外として記録した18件（台帳の FXMETA 節）:
/// ブラシ7件（Shadow / InnerShadow / FillBackground / FillForeground /
/// FrameLine の Brush、Outline の StrokeBrush、DisplacementMap の
/// Brush)、Transform 3件（DisplacementMap / NoiseColorShift /
/// NoiseDisplacementMap)、NoiseParameter 3件（Noise / NoiseColorShift /
/// NoiseDisplacementMap)、MosaicParameter、Mask の ShapeParameter、
/// Gradient の Stops、MeshDeformation の Points、MotionTracking の Path。
///
/// 型付きモデル（`Brush` / `MosaicParameter` / 各値型）には型付きの
/// 子記述子を付け、生保持（`PreservedObject`）には保存 JSON の
/// フィールドから汎用に生成した子記述子を付ける。表示名は対象の
/// プロパティ名・フィールド名そのまま（従来方針どおり、根拠の無い
/// 文言は作らない）。子記述子のグループは親のグループを引き継ぐ。
public extension EffectPropertyMetadata {

    // MARK: - ブラシ（型付き）

    /// 型付き `Brush?` プロパティの複合記述子。子は現在のパラメータ型の
    /// フィールドから生成する。パラメータ型そのものの切替は対象外。
    /// ブラシが未設定（nil）の間は子を持たない。
    static func brushDescriptor(
        id: String, displayName: String, group: String,
        get: @escaping () -> Brush?
    ) -> PropertyDescriptor {
        .object(id: id, displayName: displayName, group: group) {
            guard let brush = get() else { return [] }
            return brushParameterChildren(of: brush, group: group)
        }
    }

    /// ブラシパラメータ型ごとの子記述子（保存形式のキー順）。
    private static func brushParameterChildren(
        of brush: Brush, group: String
    ) -> [PropertyDescriptor] {
        switch brush.parameter {
        case .solidColor(let parameter):
            return [
                .color(
                    id: "Color", displayName: "Color", group: group,
                    get: { parameter.color }, set: { parameter.color = $0 }
                ),
            ]
        case .linearGradient(let parameter):
            return [
                gradientStopsCollection(
                    group: group,
                    get: { parameter.stops }, set: { parameter.stops = $0 }
                ),
                .enumeration(
                    id: "CoordinateMode", displayName: "CoordinateMode", group: group,
                    options: brushCoordinateModeOptions,
                    get: { parameter.coordinateMode }, set: { parameter.coordinateMode = $0 }
                ),
                .animation(
                    id: "Size", displayName: "Size", group: group,
                    get: { parameter.size }, set: { parameter.size = $0 }
                ),
                .animation(
                    id: "Offset", displayName: "Offset", group: group,
                    get: { parameter.offset }, set: { parameter.offset = $0 }
                ),
                .animation(
                    id: "Angle", displayName: "Angle", group: group,
                    get: { parameter.angle }, set: { parameter.angle = $0 }
                ),
                .enumeration(
                    id: "ExtendMode", displayName: "ExtendMode", group: group,
                    options: extendModeOptions,
                    get: { parameter.extendMode }, set: { parameter.extendMode = $0 }
                ),
            ]
        case .radialGradient(let parameter):
            return [
                gradientStopsCollection(
                    group: group,
                    get: { parameter.stops }, set: { parameter.stops = $0 }
                ),
                .animation(
                    id: "CenterX", displayName: "CenterX", group: group,
                    get: { parameter.centerX }, set: { parameter.centerX = $0 }
                ),
                .animation(
                    id: "CenterY", displayName: "CenterY", group: group,
                    get: { parameter.centerY }, set: { parameter.centerY = $0 }
                ),
                .animation(
                    id: "OriginX", displayName: "OriginX", group: group,
                    get: { parameter.originX }, set: { parameter.originX = $0 }
                ),
                .animation(
                    id: "OriginY", displayName: "OriginY", group: group,
                    get: { parameter.originY }, set: { parameter.originY = $0 }
                ),
                .animation(
                    id: "RadiusX", displayName: "RadiusX", group: group,
                    get: { parameter.radiusX }, set: { parameter.radiusX = $0 }
                ),
                .animation(
                    id: "RadiusY", displayName: "RadiusY", group: group,
                    get: { parameter.radiusY }, set: { parameter.radiusY = $0 }
                ),
                .animation(
                    id: "Zoom", displayName: "Zoom", group: group,
                    get: { parameter.zoom }, set: { parameter.zoom = $0 }
                ),
                .animation(
                    id: "Angle", displayName: "Angle", group: group,
                    get: { parameter.angle }, set: { parameter.angle = $0 }
                ),
                .animation(
                    id: "Aspect", displayName: "Aspect", group: group,
                    get: { parameter.aspect }, set: { parameter.aspect = $0 }
                ),
                .enumeration(
                    id: "ExtendMode", displayName: "ExtendMode", group: group,
                    options: extendModeOptions,
                    get: { parameter.extendMode }, set: { parameter.extendMode = $0 }
                ),
                .boolean(
                    id: "IsInverted", displayName: "IsInverted", group: group,
                    get: { parameter.isInverted }, set: { parameter.isInverted = $0 }
                ),
            ]
        case .checkered(let parameter):
            return [
                .color(
                    id: "Color1", displayName: "Color1", group: group,
                    get: { parameter.color1 }, set: { parameter.color1 = $0 }
                ),
                .color(
                    id: "Color2", displayName: "Color2", group: group,
                    get: { parameter.color2 }, set: { parameter.color2 = $0 }
                ),
                .animation(
                    id: "Size", displayName: "Size", group: group,
                    get: { parameter.size }, set: { parameter.size = $0 }
                ),
                drawingTransformDescriptor(
                    group: group,
                    get: { parameter.drawing }, set: { parameter.drawing = $0 }
                ),
            ]
        case .dot(let parameter):
            return [
                .color(
                    id: "Foreground", displayName: "Foreground", group: group,
                    get: { parameter.foreground }, set: { parameter.foreground = $0 }
                ),
                .color(
                    id: "Background", displayName: "Background", group: group,
                    get: { parameter.background }, set: { parameter.background = $0 }
                ),
                .animation(
                    id: "Radius", displayName: "Radius", group: group,
                    get: { parameter.radius }, set: { parameter.radius = $0 }
                ),
                .animation(
                    id: "Span", displayName: "Span", group: group,
                    get: { parameter.span }, set: { parameter.span = $0 }
                ),
                .animation(
                    id: "Zoom", displayName: "Zoom", group: group,
                    get: { parameter.zoom }, set: { parameter.zoom = $0 }
                ),
                drawingTransformDescriptor(
                    group: group,
                    get: { parameter.drawing }, set: { parameter.drawing = $0 }
                ),
            ]
        case .stripe(let parameter):
            return [
                .color(
                    id: "Color1", displayName: "Color1", group: group,
                    get: { parameter.color1 }, set: { parameter.color1 = $0 }
                ),
                .animation(
                    id: "Width1", displayName: "Width1", group: group,
                    get: { parameter.width1 }, set: { parameter.width1 = $0 }
                ),
                .color(
                    id: "Color2", displayName: "Color2", group: group,
                    get: { parameter.color2 }, set: { parameter.color2 = $0 }
                ),
                .animation(
                    id: "Width2", displayName: "Width2", group: group,
                    get: { parameter.width2 }, set: { parameter.width2 = $0 }
                ),
                .animation(
                    id: "Offset", displayName: "Offset", group: group,
                    get: { parameter.offset }, set: { parameter.offset = $0 }
                ),
                .animation(
                    id: "Zoom", displayName: "Zoom", group: group,
                    get: { parameter.zoom }, set: { parameter.zoom = $0 }
                ),
                .animation(
                    id: "Angle", displayName: "Angle", group: group,
                    get: { parameter.angle }, set: { parameter.angle = $0 }
                ),
            ]
        case .gridLine(let parameter):
            return [
                .color(
                    id: "StrokeColor", displayName: "StrokeColor", group: group,
                    get: { parameter.strokeColor }, set: { parameter.strokeColor = $0 }
                ),
                .color(
                    id: "BackgroundColor", displayName: "BackgroundColor", group: group,
                    get: { parameter.backgroundColor }, set: { parameter.backgroundColor = $0 }
                ),
                .animation(
                    id: "Thickness", displayName: "Thickness", group: group,
                    get: { parameter.thickness }, set: { parameter.thickness = $0 }
                ),
                .animation(
                    id: "Width", displayName: "Width", group: group,
                    get: { parameter.width }, set: { parameter.width = $0 }
                ),
                .animation(
                    id: "Height", displayName: "Height", group: group,
                    get: { parameter.height }, set: { parameter.height = $0 }
                ),
                .animation(
                    id: "Zoom", displayName: "Zoom", group: group,
                    get: { parameter.zoom }, set: { parameter.zoom = $0 }
                ),
                drawingTransformDescriptor(
                    group: group,
                    get: { parameter.drawing }, set: { parameter.drawing = $0 }
                ),
            ]
        case .bitmap(let parameter):
            return [
                .text(
                    id: "FilePath", displayName: "FilePath", group: group,
                    get: { parameter.filePath ?? "" }, set: { parameter.filePath = $0 }
                ),
                .number(
                    id: "PlaybackRate", displayName: "PlaybackRate", group: group,
                    get: { parameter.playbackRate }, set: { parameter.playbackRate = $0 }
                ),
                // 本家 TimeSpan。FXMETA の TextureEffect と同じく秒の数値で読み書きする。
                .number(
                    id: "ContentOffset", displayName: "ContentOffset", group: group,
                    get: { parameter.contentOffset.seconds },
                    set: { parameter.contentOffset = TimeSpanValue(seconds: $0) }
                ),
                .enumeration(
                    id: "ExtendModeX", displayName: "ExtendModeX", group: group,
                    options: extendModeOptions,
                    get: { parameter.extendModeX }, set: { parameter.extendModeX = $0 }
                ),
                .enumeration(
                    id: "ExtendModeY", displayName: "ExtendModeY", group: group,
                    options: extendModeOptions,
                    get: { parameter.extendModeY }, set: { parameter.extendModeY = $0 }
                ),
                .animation(
                    id: "Zoom", displayName: "Zoom", group: group,
                    get: { parameter.zoom }, set: { parameter.zoom = $0 }
                ),
                drawingTransformDescriptor(
                    group: group,
                    get: { parameter.drawing }, set: { parameter.drawing = $0 }
                ),
            ]
        case .noise(let parameter):
            var children: [PropertyDescriptor] = [
                .enumeration(
                    id: "NoiseType", displayName: "NoiseType", group: group,
                    options: noiseTypeOptions,
                    get: { parameter.noiseType }, set: { parameter.noiseType = $0 }
                ),
            ]
            if parameter.noiseParameter != nil {
                children.append(preservedDescriptor(
                    id: "NoiseParameter", displayName: "NoiseParameter", group: group,
                    get: { parameter.noiseParameter }, set: { parameter.noiseParameter = $0 }
                ))
            }
            children += [
                .color(
                    id: "Color1", displayName: "Color1", group: group,
                    get: { parameter.color1 }, set: { parameter.color1 = $0 }
                ),
                .color(
                    id: "Color2", displayName: "Color2", group: group,
                    get: { parameter.color2 }, set: { parameter.color2 = $0 }
                ),
                .boolean(
                    id: "IsColor", displayName: "IsColor", group: group,
                    get: { parameter.isColor }, set: { parameter.isColor = $0 }
                ),
                .boolean(
                    id: "IsUniqueSeed", displayName: "IsUniqueSeed", group: group,
                    get: { parameter.isUniqueSeed }, set: { parameter.isUniqueSeed = $0 }
                ),
            ]
            return children
        case .gradientMesh(let parameter):
            return [
                .integer(
                    id: "HorizontalCount", displayName: "HorizontalCount", group: group,
                    get: { parameter.horizontalCount }, set: { parameter.horizontalCount = $0 }
                ),
                .integer(
                    id: "VerticalCount", displayName: "VerticalCount", group: group,
                    get: { parameter.verticalCount }, set: { parameter.verticalCount = $0 }
                ),
                .enumeration(
                    id: "CoordinateMode", displayName: "CoordinateMode", group: group,
                    options: brushCoordinateModeOptions,
                    get: { parameter.coordinateMode }, set: { parameter.coordinateMode = $0 }
                ),
                .animation(
                    id: "Width", displayName: "Width", group: group,
                    get: { parameter.width }, set: { parameter.width = $0 }
                ),
                .animation(
                    id: "Height", displayName: "Height", group: group,
                    get: { parameter.height }, set: { parameter.height = $0 }
                ),
                .boolean(
                    id: "ExtendOutside", displayName: "ExtendOutside", group: group,
                    get: { parameter.extendOutside }, set: { parameter.extendOutside = $0 }
                ),
                .collection(
                    id: "Points", displayName: "Points", group: group,
                    count: { parameter.points.count },
                    elements: { index in
                        guard parameter.points.indices.contains(index) else { return [] }
                        return gradientMeshPointChildren(
                            of: parameter.points[index], group: group
                        )
                    },
                    insert: { parameter.points.append(GradientMeshPointValue()) },
                    remove: { index in
                        guard parameter.points.indices.contains(index) else { return }
                        parameter.points.remove(at: index)
                    }
                ),
                .animation(
                    id: "Zoom", displayName: "Zoom", group: group,
                    get: { parameter.zoom }, set: { parameter.zoom = $0 }
                ),
                drawingTransformDescriptor(
                    group: group,
                    get: { parameter.drawing }, set: { parameter.drawing = $0 }
                ),
            ]
        case .preserved:
            // 型付き化していないパラメータ型は子を持たない（値は保持される）。
            return []
        }
    }

    /// グラデーションメッシュの格子点1件の子記述子（保存形式のキー順）。
    private static func gradientMeshPointChildren(
        of point: GradientMeshPointValue, group: String
    ) -> [PropertyDescriptor] {
        [
            .animation(
                id: "X", displayName: "X", group: group,
                get: { point.x }, set: { point.x = $0 }
            ),
            .animation(
                id: "Y", displayName: "Y", group: group,
                get: { point.y }, set: { point.y = $0 }
            ),
            .animation(
                id: "LeftHandleX", displayName: "LeftHandleX", group: group,
                get: { point.leftHandleX }, set: { point.leftHandleX = $0 }
            ),
            .animation(
                id: "LeftHandleY", displayName: "LeftHandleY", group: group,
                get: { point.leftHandleY }, set: { point.leftHandleY = $0 }
            ),
            .animation(
                id: "RightHandleX", displayName: "RightHandleX", group: group,
                get: { point.rightHandleX }, set: { point.rightHandleX = $0 }
            ),
            .animation(
                id: "RightHandleY", displayName: "RightHandleY", group: group,
                get: { point.rightHandleY }, set: { point.rightHandleY = $0 }
            ),
            .animation(
                id: "UpHandleX", displayName: "UpHandleX", group: group,
                get: { point.upHandleX }, set: { point.upHandleX = $0 }
            ),
            .animation(
                id: "UpHandleY", displayName: "UpHandleY", group: group,
                get: { point.upHandleY }, set: { point.upHandleY = $0 }
            ),
            .animation(
                id: "DownHandleX", displayName: "DownHandleX", group: group,
                get: { point.downHandleX }, set: { point.downHandleX = $0 }
            ),
            .animation(
                id: "DownHandleY", displayName: "DownHandleY", group: group,
                get: { point.downHandleY }, set: { point.downHandleY = $0 }
            ),
            .boolean(
                id: "IsLeftHandleCustom", displayName: "IsLeftHandleCustom", group: group,
                get: { point.isLeftHandleCustom }, set: { point.isLeftHandleCustom = $0 }
            ),
            .boolean(
                id: "IsRightHandleCustom", displayName: "IsRightHandleCustom", group: group,
                get: { point.isRightHandleCustom }, set: { point.isRightHandleCustom = $0 }
            ),
            .boolean(
                id: "IsUpHandleCustom", displayName: "IsUpHandleCustom", group: group,
                get: { point.isUpHandleCustom }, set: { point.isUpHandleCustom = $0 }
            ),
            .boolean(
                id: "IsDownHandleCustom", displayName: "IsDownHandleCustom", group: group,
                get: { point.isDownHandleCustom }, set: { point.isDownHandleCustom = $0 }
            ),
            .color(
                id: "Color", displayName: "Color", group: group,
                get: { point.color }, set: { point.color = $0 }
            ),
            .boolean(
                id: "IsSelected", displayName: "IsSelected", group: group,
                get: { point.isSelected }, set: { point.isSelected = $0 }
            ),
        ]
    }

    /// パターン系ブラシ共通の配置変換（保存形式ではパラメータ本体へ
    /// インラインに並ぶが、モデル上の入れ子構造どおり `.object` で表す）。
    private static func drawingTransformDescriptor(
        group: String,
        get: @escaping () -> BrushDrawingTransform,
        set: @escaping (BrushDrawingTransform) -> Void
    ) -> PropertyDescriptor {
        .object(id: "Drawing", displayName: "Drawing", group: group) {
            [
                .animation(
                    id: "X", displayName: "X", group: group,
                    get: { get().x },
                    set: { var drawing = get(); drawing.x = $0; set(drawing) }
                ),
                .animation(
                    id: "Y", displayName: "Y", group: group,
                    get: { get().y },
                    set: { var drawing = get(); drawing.y = $0; set(drawing) }
                ),
                .animation(
                    id: "Angle", displayName: "Angle", group: group,
                    get: { get().angle },
                    set: { var drawing = get(); drawing.angle = $0; set(drawing) }
                ),
                .animation(
                    id: "Aspect", displayName: "Aspect", group: group,
                    get: { get().aspect },
                    set: { var drawing = get(); drawing.aspect = $0; set(drawing) }
                ),
                .boolean(
                    id: "IsInverted", displayName: "IsInverted", group: group,
                    get: { get().isInverted },
                    set: { var drawing = get(); drawing.isInverted = $0; set(drawing) }
                ),
            ]
        }
    }

    /// ブラシ座標モードの選択肢。表示名の根拠は取れないためメンバ名そのまま。
    private static let brushCoordinateModeOptions = [
        PropertyEnumOption(value: "Pixel", displayName: "Pixel"),
        PropertyEnumOption(value: "Relative", displayName: "Relative"),
    ]

    // MARK: - グラデーションの色停止点列

    /// `GradientStopValue` の列の複合記述子（Gradient の Stops と
    /// グラデーションブラシの Stops で共用）。要素は Offset（0〜1）と
    /// Color。追加はモデルの既定値（Offset 0・透明）の要素を末尾へ足す。
    static func gradientStopsCollection(
        group: String,
        get: @escaping () -> [GradientStopValue],
        set: @escaping ([GradientStopValue]) -> Void
    ) -> PropertyDescriptor {
        .collection(
            id: "Stops", displayName: "Stops", group: group,
            count: { get().count },
            elements: { index in
                guard get().indices.contains(index) else { return [] }
                return [
                    .number(
                        id: "Offset", displayName: "Offset", group: group, range: 0...1,
                        get: {
                            get().indices.contains(index) ? get()[index].offset : 0
                        },
                        set: { value in
                            var stops = get()
                            guard stops.indices.contains(index) else { return }
                            stops[index].offset = value
                            set(stops)
                        }
                    ),
                    .color(
                        id: "Color", displayName: "Color", group: group,
                        get: {
                            get().indices.contains(index) ? get()[index].color : .transparent
                        },
                        set: { value in
                            var stops = get()
                            guard stops.indices.contains(index) else { return }
                            stops[index].color = value
                            set(stops)
                        }
                    ),
                ]
            },
            insert: { set(get() + [GradientStopValue()]) },
            remove: { index in
                var stops = get()
                guard stops.indices.contains(index) else { return }
                stops.remove(at: index)
                set(stops)
            }
        )
    }

    // MARK: - モザイクパラメータ（型付き）

    /// `MosaicParameter?` の複合記述子。型付き（sized）は Size のみを
    /// 子に持ち、それ以外の $type は生保持として汎用子記述子を付ける。
    /// パラメータが未設定（nil）の間は子を持たない。
    static func mosaicParameterDescriptor(
        _ definition: MosaicEffectDefinition
    ) -> PropertyDescriptor {
        .object(id: "MosaicParameter", displayName: "MosaicParameter", group: "モザイク") {
            guard let parameter = definition.mosaicParameter else { return [] }
            switch parameter {
            case .sized(let sized):
                return [
                    .animation(
                        id: "Size", displayName: "Size", group: "モザイク",
                        get: { sized.size }, set: { sized.size = $0 }
                    ),
                ]
            case .preserved:
                return rawObjectChildren(
                    group: "モザイク",
                    readRoot: {
                        guard let current = definition.mosaicParameter,
                              case .preserved(let object) = current else { return nil }
                        return object.value
                    },
                    writeRoot: {
                        definition.mosaicParameter = .preserved(PreservedObject($0))
                    }
                )
            }
        }
    }

    // MARK: - メッシュ変形の点列

    /// `MeshDeformationPointValue` の列の複合記述子。要素は X / Y
    /// （アニメーション付き）と IsSelected。追加はモデルの既定値の
    /// 要素を末尾へ足す。
    static func meshPointsCollection(
        _ definition: MeshDeformationEffectDefinition
    ) -> PropertyDescriptor {
        let group = "メッシュ変形"
        return .collection(
            id: "Points", displayName: "Points", group: group,
            count: { definition.points.count },
            elements: { index in
                guard definition.points.indices.contains(index) else { return [] }
                return [
                    .animation(
                        id: "X", displayName: "X", group: group,
                        get: {
                            definition.points.indices.contains(index)
                                ? definition.points[index].x
                                : Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
                        },
                        set: { value in
                            guard definition.points.indices.contains(index) else { return }
                            definition.points[index].x = value
                        }
                    ),
                    .animation(
                        id: "Y", displayName: "Y", group: group,
                        get: {
                            definition.points.indices.contains(index)
                                ? definition.points[index].y
                                : Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
                        },
                        set: { value in
                            guard definition.points.indices.contains(index) else { return }
                            definition.points[index].y = value
                        }
                    ),
                    .boolean(
                        id: "IsSelected", displayName: "IsSelected", group: group,
                        get: {
                            definition.points.indices.contains(index)
                                ? definition.points[index].isSelected : false
                        },
                        set: { value in
                            guard definition.points.indices.contains(index) else { return }
                            definition.points[index].isSelected = value
                        }
                    ),
                ]
            },
            insert: { definition.points.append(MeshDeformationPointValue()) },
            remove: { index in
                guard definition.points.indices.contains(index) else { return }
                definition.points.remove(at: index)
            }
        )
    }

    // MARK: - モーショントラッキングのパス

    /// `MotionTrackingPathValue` の複合記述子。子は保存形式のキー順
    /// （Target / Rects / AlgorithmName）。`IsEditing` は保存対象外の
    /// 実行時状態のため子にしない。
    static func motionTrackingPathDescriptor(
        _ definition: MotionTrackingEffectDefinition
    ) -> PropertyDescriptor {
        let group = "モーショントラッキング"
        return .object(id: "Path", displayName: "Path", group: group) {
            [
                .enumeration(
                    id: "Target", displayName: "Target", group: group,
                    options: motionTrackingTargetOptions,
                    get: { definition.path.target }, set: { definition.path.target = $0 }
                ),
                .collection(
                    id: "Rects", displayName: "Rects", group: group,
                    count: { definition.path.rects.count },
                    elements: { index in
                        guard definition.path.rects.indices.contains(index) else { return [] }
                        return motionTrackingRectChildren(of: definition, index: index, group: group)
                    },
                    insert: { definition.path.rects.append(MotionTrackingRectValue()) },
                    remove: { index in
                        guard definition.path.rects.indices.contains(index) else { return }
                        definition.path.rects.remove(at: index)
                    }
                ),
                .text(
                    id: "AlgorithmName", displayName: "AlgorithmName", group: group,
                    get: { definition.path.algorithmName },
                    set: { definition.path.algorithmName = $0 }
                ),
            ]
        }
    }

    /// トラッキング矩形1件の子記述子（保存形式のキー順）。
    private static func motionTrackingRectChildren(
        of definition: MotionTrackingEffectDefinition, index: Int, group: String
    ) -> [PropertyDescriptor] {
        func number(
            id: String, keyPath: WritableKeyPath<MotionTrackingRectValue, Double>, fallback: Double
        ) -> PropertyDescriptor {
            .number(
                id: id, displayName: id, group: group,
                get: {
                    definition.path.rects.indices.contains(index)
                        ? definition.path.rects[index][keyPath: keyPath] : fallback
                },
                set: { value in
                    guard definition.path.rects.indices.contains(index) else { return }
                    definition.path.rects[index][keyPath: keyPath] = value
                }
            )
        }
        return [
            number(id: "Top", keyPath: \.top, fallback: -50),
            number(id: "Bottom", keyPath: \.bottom, fallback: 50),
            number(id: "Left", keyPath: \.left, fallback: -50),
            number(id: "Right", keyPath: \.right, fallback: 50),
            .boolean(
                id: "IsTracking", displayName: "IsTracking", group: group,
                get: {
                    definition.path.rects.indices.contains(index)
                        ? definition.path.rects[index].isTracking : false
                },
                set: { value in
                    guard definition.path.rects.indices.contains(index) else { return }
                    definition.path.rects[index].isTracking = value
                }
            ),
        ]
    }

    /// トラッキング対象の選択肢。表示名の根拠は取れないためメンバ名そのまま。
    private static let motionTrackingTargetOptions = [
        PropertyEnumOption(value: "Background", displayName: "Background"),
        PropertyEnumOption(value: "CurrentItem", displayName: "CurrentItem"),
    ]

    // MARK: - 生保持（PreservedObject）の汎用子記述子

    /// 生保持 `PreservedObject?` プロパティの複合記述子。子は保存 JSON
    /// のフィールドから汎用に生成する（`rawObjectChildren`）。
    /// 対象が未設定（nil）の間は子を持たない。
    static func preservedDescriptor(
        id: String, displayName: String, group: String,
        get: @escaping () -> PreservedObject?,
        set: @escaping (PreservedObject?) -> Void
    ) -> PropertyDescriptor {
        .object(id: id, displayName: displayName, group: group) {
            rawObjectChildren(
                group: group,
                readRoot: { get()?.value },
                writeRoot: { set(PreservedObject($0)) }
            )
        }
    }

    /// 生保持オブジェクトの子記述子を現在の JSON から生成する。
    ///
    /// フィールドの置き場は形状で決める: 値が `{Type, Parameter}` 形
    /// （本家 `Plugin.Brush.Brush` の保存形式）なら Parameter オブジェクト
    /// のフィールド、それ以外（Transform / NoiseParameter /
    /// ShapeParameter 等、多態パラメータが $type 付きで直接保存される
    /// 形）ならオブジェクト自身のフィールドを使う。根拠は実ファイルと
    /// 本家の保存形式: NoiseParameter は $type 直下にフィールドを持ち
    /// （実プロジェクト2件で実測）、ブラシは Parameter の中にある。
    /// `$type` は型判別子であり編集対象にしない。
    private static func rawObjectChildren(
        group: String,
        readRoot: @escaping () -> JSONValue?,
        writeRoot: @escaping (JSONValue) -> Void
    ) -> [PropertyDescriptor] {
        guard let root = readRoot(), root.objectFields != nil else { return [] }
        let basePath: [String]
        if let parameter = root.field("Parameter"), parameter.objectFields != nil {
            basePath = ["Parameter"]
        } else {
            basePath = []
        }
        return rawNodeChildren(
            path: basePath, group: group, depth: 0,
            readRoot: readRoot, writeRoot: writeRoot
        )
    }

    /// 生保持オブジェクト内の1ノード（オブジェクト）の子記述子。
    /// 値の形状で種別を決める: 数値→number、真偽→boolean、文字列→text
    /// （`#AARRGGBB` 形式は color)、`Values` キーを持つオブジェクト→
    /// animation（本家 `Animation` の保存形式。読み書きは定義層の
    /// 既存コーデックを使う）、それ以外のオブジェクト→object で再帰
    /// （深さ上限3)。配列と null は汎用の子で表現できないため子に
    /// しない（値そのものは保持され、書き戻しで失われない）。
    /// 読み書きは都度ルートから辿り、触っていないフィールドは
    /// そのまま残る。
    private static func rawNodeChildren(
        path: [String], group: String, depth: Int,
        readRoot: @escaping () -> JSONValue?,
        writeRoot: @escaping (JSONValue) -> Void
    ) -> [PropertyDescriptor] {
        guard let root = readRoot(),
              let node = rawValue(at: path, in: root),
              let fields = node.objectFields else { return [] }
        var result: [PropertyDescriptor] = []
        for (key, value) in fields where key != "$type" {
            let fieldPath = path + [key]
            func writeField(_ newValue: JSONValue) {
                guard var root = readRoot() else { return }
                rawReplace(at: fieldPath, with: newValue, in: &root)
                writeRoot(root)
            }
            switch value {
            case .numberLiteral:
                result.append(.number(
                    id: key, displayName: key, group: group,
                    get: { rawValue(at: fieldPath, in: readRoot())?.doubleValue ?? 0 },
                    set: { writeField(.number($0)) }
                ))
            case .bool:
                result.append(.boolean(
                    id: key, displayName: key, group: group,
                    get: { rawValue(at: fieldPath, in: readRoot())?.boolValue ?? false },
                    set: { writeField(.bool($0)) }
                ))
            case .string(let string):
                if isRawColorLiteral(string) {
                    result.append(.color(
                        id: key, displayName: key, group: group,
                        get: {
                            CodecSupport.color(
                                rawValue(at: fieldPath, in: readRoot()), default: .transparent
                            )
                        },
                        set: { writeField(.string($0.honkeString)) }
                    ))
                } else {
                    result.append(.text(
                        id: key, displayName: key, group: group,
                        get: { rawValue(at: fieldPath, in: readRoot())?.stringValue ?? "" },
                        set: { writeField(.string($0)) }
                    ))
                }
            case .object(let objectFields):
                if objectFields.contains(where: { $0.key == "Values" }) {
                    result.append(.animation(
                        id: key, displayName: key, group: group,
                        get: {
                            guard let current = rawValue(at: fieldPath, in: readRoot()) else {
                                return Animation(
                                    defaultValue: 0,
                                    minValue: -2_147_483_648, maxValue: 2_147_483_647
                                )
                            }
                            return CodecSupport.decodeLegacyAnimation(current)
                        },
                        set: { writeField(CodecSupport.encodeAnimation($0)) }
                    ))
                } else if depth < rawMaximumDepth {
                    result.append(.object(id: key, displayName: key, group: group) {
                        rawNodeChildren(
                            path: fieldPath, group: group, depth: depth + 1,
                            readRoot: readRoot, writeRoot: writeRoot
                        )
                    })
                } else {
                    result.append(.object(id: key, displayName: key, group: group) { [] })
                }
            case .array, .null:
                break
            }
        }
        return result
    }

    /// 生保持の入れ子オブジェクトの再帰上限（これより深い入れ子は
    /// 子を持たない object として表す。値は保持される）。
    private static let rawMaximumDepth = 3

    /// `#AARRGGBB` 形式の色文字列か（本家の色の保存形式）。
    private static func isRawColorLiteral(_ string: String) -> Bool {
        guard string.count == 9, string.hasPrefix("#") else { return false }
        return string.dropFirst().allSatisfy { $0.isHexDigit }
    }

    /// キー列で JSON を辿る。
    private static func rawValue(at path: [String], in root: JSONValue?) -> JSONValue? {
        var current = root
        for key in path {
            guard let next = current?.field(key) else { return nil }
            current = next
        }
        return current
    }

    /// キー列の先の値を置き換える（途中のオブジェクトが無い場合は何もしない）。
    private static func rawReplace(at path: [String], with newValue: JSONValue, in value: inout JSONValue) {
        guard let key = path.first else {
            value = newValue
            return
        }
        guard case .object(var fields) = value else { return }
        if path.count == 1 {
            if let index = fields.firstIndex(where: { $0.key == key }) {
                fields[index].value = newValue
            } else {
                fields.append((key: key, value: newValue))
            }
            value = .object(fields)
            return
        }
        guard let index = fields.firstIndex(where: { $0.key == key }) else { return }
        var child = fields[index].value
        rawReplace(at: Array(path.dropFirst()), with: newValue, in: &child)
        fields[index].value = child
        value = .object(fields)
    }
}
