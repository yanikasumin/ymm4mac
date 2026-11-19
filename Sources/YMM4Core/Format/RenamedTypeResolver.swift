import Foundation

/// 本家 `RenamedTypeResolver` の再現。
///
/// $type のアセンブリ修飾名を受け取り、改名・移行先の名前に解決する。
/// 規則は本家コードそのままで、(1) コミュニティエフェクト11件の
/// 名前空間・アセンブリ移行、(2) OutlineLiteEffect → OutlineEffect の
/// 本家リネーム1件、の2種類だけが存在する。
public enum RenamedTypeResolver {
    private static let communityEffects = [
        "Binarization", "CircularBlur", "ColorCorrection", "ColorShift",
        "InnerOutline", "LongShadow", "Ripple", "SpiralTransform",
        "StripeGlitchNoise", "ThreeDimensional", "Wave",
    ]
    private static let communityEffectNamespace = "YukkuriMovieMaker.Plugin.Community.Effect.Video"
    private static let communityEffectAssembly = "YukkuriMovieMaker.Plugin.Community"
    private static let ymmVideoEffectNamespace = "YukkuriMovieMaker.Project.Effects"
    private static let ymmAssembly = "YukkuriMovieMaker"
    /// 移行対象のクラス名（名前空間を除いた部分）の集合。
    private static let communityClassNames: Set<String> = Set(
        communityEffects.map { "\($0)Effect" }
    )

    public static func resolveTypeName(_ assemblyQualifiedName: String) -> String {
        // 変更されるのは「完全名が YukkuriMovieMaker.Project.Effects.
        // 配下の特定クラスで、アセンブリ部が YukkuriMovieMaker」の
        // 場合だけ。それ以外は入力をそのまま返すため、完全名の接頭辞と
        // クラス名の集合照合で早期に振り分ける（従来は全入力に対して
        // split と文字列補間による総当たり照合をしていた。FE-R1-031
        // の詳細計測で構築側の支配項の一つと特定。結果は従来と同一）。
        guard let commaIndex = assemblyQualifiedName.firstIndex(of: ",") else {
            return assemblyQualifiedName
        }
        let fullName = assemblyQualifiedName[..<commaIndex]
        let namespacePrefix = "\(ymmVideoEffectNamespace)."
        guard fullName.hasPrefix(namespacePrefix) else {
            return assemblyQualifiedName
        }
        let className = fullName.dropFirst(namespacePrefix.count)
        let isOutlineLite = className == "OutlineLiteEffect"
        guard isOutlineLite || communityClassNames.contains(String(className)) else {
            return assemblyQualifiedName
        }
        // アセンブリ部の照合。範囲（1つ目と2つ目の "," の間）と
        // トリム規則は従来の parts[1] と同一。
        let rest = assemblyQualifiedName[assemblyQualifiedName.index(after: commaIndex)...]
        let assemblyPart = rest.prefix(while: { $0 != "," })
        guard String(assemblyPart).trimmingCharacters(in: .whitespaces) == ymmAssembly else {
            return assemblyQualifiedName
        }
        if isOutlineLite {
            return "\(ymmVideoEffectNamespace).OutlineEffect, \(ymmAssembly)"
        }
        let name = className.dropLast("Effect".count)
        return "\(communityEffectNamespace).\(name).\(name)Effect, \(communityEffectAssembly)"
    }
}
