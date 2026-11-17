import XCTest
@testable import YMM4Core

// 合成系テストの共有フェイク（エフェクト対の供給元）。
//
// W1（構造整理）で、CompositeGroupTests に私用定義されていた
// StubEffectProvider をここへ集約した。

/// アイテム／グループごとのエフェクト対を辞書で差し込む供給元。
/// グループ解決の呼び出しを記録する。
final class StubEffectProvider: EffectPairProvider {
    var ownPairs: [ObjectIdentifier: [EffectPair]] = [:]
    var groupDefinitions: [ObjectIdentifier: [any VideoEffectDefinition]] = [:]
    private(set) var groupCalls: [(group: GroupItem, childIndex: Int, childCount: Int)] = []

    func ownEffectPairs(for item: BaseItem & VideoItemProperties) -> [EffectPair] {
        ownPairs[ObjectIdentifier(item)] ?? []
    }

    func groupEffectPairs(for group: GroupItem, childIndex: Int, childCount: Int) -> [EffectPair] {
        groupCalls.append((group, childIndex, childCount))
        return (groupDefinitions[ObjectIdentifier(group)] ?? []).map {
            EffectPair(timeSource: group, definition: $0, groupIndex: childIndex, groupCount: childCount)
        }
    }

    func faceEffectPairs(for faceItem: BaseItem) -> [EffectPair] { [] }
}
