import SwiftUI
import YMM4Core

/// アニメーション種別の選択メニュー（本家 AnimationSlider の
/// コンテキストメニュー = AnimationSliderMenuFactory の再現）。
///
/// 構成の根拠は analysis-notes/UI-FACTS-MENUS-CONTEXT.md §5:
/// 第1段は標準10種（なし／直線移動／直線ベジェ／加減速移動／瞬間移動／
/// 移動量指定／ランダム移動／反復移動／補間移動／補間ベジェ）、
/// 続いてイージング10グループ×8葉（mode 1–4 = 通常キーフレーム、
/// mode 5–8 = 補間キーフレーム。モード切替はこの選択が兼ねる）。
/// 本家は右クリックメニューだが、こちらは行内のメニューボタンから
/// 開く形にする（表示名は現在の種別名）。
/// 種別の書き換えは記述子の `setAnimationType` 経由（値列は保たれる）。
struct AnimationTypeMenuButton: View {
    let descriptor: PropertyDescriptor
    var onEdited: () -> Void
    /// Undo 記録（FE-UNDO-WIRING）。nil の場合は無記録。
    var editRecorder: EditRecorder? = nil
    var editTarget: EditTargetKey? = nil

    var body: some View {
        Menu {
            ForEach(Self.standardTypes, id: \.type.rawValue) { entry in
                checkButton(type: entry.type, name: entry.name)
            }
            Divider()
            ForEach(Self.easingGroups, id: \.prefix) { group in
                Menu(group.name) {
                    Section(UIStrings.AnimationTypeName.keyFrameModeNormal) {
                        ForEach(1...4, id: \.self) { mode in
                            if let type = Self.easingType(prefix: group.prefix, mode: mode) {
                                checkButton(
                                    type: type,
                                    name: Self.modeName(mode)
                                )
                            }
                        }
                    }
                    Section(UIStrings.AnimationTypeName.keyFrameModeInterpolation) {
                        ForEach(5...8, id: \.self) { mode in
                            if let type = Self.easingType(prefix: group.prefix, mode: mode) {
                                checkButton(
                                    type: type,
                                    name: Self.modeName(mode)
                                )
                            }
                        }
                    }
                }
            }
        } label: {
            Text(Self.name(of: currentType))
                .font(.caption)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 110, alignment: .leading)
        .help("アニメーション種別")
    }

    private var currentType: AnimationType {
        descriptor.animationValue?.animationType ?? .none
    }

    @ViewBuilder
    private func checkButton(type: AnimationType, name: String) -> some View {
        Button {
            let old = currentType
            descriptor.setAnimationType(type)
            // 種別だけを記録する。値列の正規化は種別変更と対の操作
            // として別単位（FE-R14-001）であり、現行の setter は
            // 種別の差し替えのみを行うため往復は対称である。
            if let editRecorder, let editTarget {
                editRecorder.recordValueChange(
                    target: EditTargetKey(
                        object: editTarget.object, key: editTarget.key + "#type"),
                    oldValue: old, newValue: type,
                    apply: { descriptor.setAnimationType($0) })
            }
            onEdited()
        } label: {
            if currentType == type {
                Label(name, systemImage: "checkmark")
            } else {
                Text(name)
            }
        }
    }

    // MARK: - 種別表

    static let standardTypes: [(type: AnimationType, name: String)] = [
        (.none, UIStrings.AnimationTypeName.none),
        (.linear, UIStrings.AnimationTypeName.linear),
        (.linearBezier, UIStrings.AnimationTypeName.linearBezier),
        (.accelerationDeceleration, UIStrings.AnimationTypeName.acceleration),
        (.instant, UIStrings.AnimationTypeName.instant),
        (.movementAmount, UIStrings.AnimationTypeName.movementAmount),
        (.random, UIStrings.AnimationTypeName.random),
        (.repetitive, UIStrings.AnimationTypeName.repetitive),
        (.interpolation, UIStrings.AnimationTypeName.interpolation),
        (.interpolationBezier, UIStrings.AnimationTypeName.interpolationBezier),
    ]

    /// イージンググループ（Prefix は AnimationType 値の上位桁。
    /// 並びは本家 FirstEasingGroups → SecondEasingGroups の順）。
    static let easingGroups: [(name: String, prefix: Int)] = [
        ("Sine", 104), ("Quad", 100), ("Cubic", 101), ("Quart", 102),
        ("Quint", 103), ("Expo", 106), ("Circ", 105), ("Back", 107),
        ("Elastic", 108), ("Bounce", 109),
    ]

    static func easingType(prefix: Int, mode: Int) -> AnimationType? {
        AnimationType(rawValue: prefix * 100 + mode)
    }

    static func modeName(_ mode: Int) -> String {
        switch mode % 4 {
        case 1: return UIStrings.AnimationTypeName.modeIn
        case 2: return UIStrings.AnimationTypeName.modeOut
        case 3: return UIStrings.AnimationTypeName.modeInOut
        default: return UIStrings.AnimationTypeName.modeOutIn
        }
    }

    /// 現在の種別の表示名（標準種別はその名前、イージングは
    /// 「グループ名 モード」の合成、補間側はその旨を付す）。
    static func name(of type: AnimationType) -> String {
        if let standard = standardTypes.first(where: { $0.type == type }) {
            return standard.name
        }
        let raw = type.rawValue
        let prefix = raw / 100
        let mode = raw % 100
        if let group = easingGroups.first(where: { $0.prefix == prefix }),
           (1...8).contains(mode) {
            let base = "\(group.name) \(modeName(mode))"
            return mode > 4
                ? "\(base)（\(UIStrings.AnimationTypeName.keyFrameModeInterpolation)）"
                : base
        }
        return "\(type)"
    }
}
