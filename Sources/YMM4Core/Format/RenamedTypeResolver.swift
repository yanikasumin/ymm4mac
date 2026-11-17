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

    public static func resolveTypeName(_ assemblyQualifiedName: String) -> String {
        let parts = assemblyQualifiedName.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return assemblyQualifiedName }
        let fullName = String(parts[0])
        let assembly = parts[1].trimmingCharacters(in: .whitespaces)
        guard assembly == ymmAssembly else { return assemblyQualifiedName }
        for name in communityEffects
        where fullName == "\(ymmVideoEffectNamespace).\(name)Effect" {
            return "\(communityEffectNamespace).\(name).\(name)Effect, \(communityEffectAssembly)"
        }
        if fullName == "\(ymmVideoEffectNamespace).OutlineLiteEffect" {
            return "\(ymmVideoEffectNamespace).OutlineEffect, \(ymmAssembly)"
        }
        return assemblyQualifiedName
    }
}
