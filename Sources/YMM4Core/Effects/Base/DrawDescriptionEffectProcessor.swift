import Foundation

/// 描画パラメータ変換のみで完結するエフェクトの処理器の基盤。
///
/// 本家では該当エフェクトの `CreateEffect` が null を返し、処理器基底の
/// `Output` は「生成物が無ければ入力そのもの」になる（素通し）。入力の
/// 所有権は移らず（IMG-03）、`ClearInput` は入力を破棄しない。
/// 変換は `update` が返す `DrawDescription` の書き換えだけで行う。
open class DrawDescriptionEffectProcessor: VideoEffectProcessor {
    /// 現在の入力（借用。破棄しない）。
    public private(set) var input: ImageReference?

    public init() {}

    /// 出力は入力そのもの（素通し）。
    public var output: ImageReference? { input }

    public func setInput(_ image: ImageReference?) {
        input = image
    }

    public func clearInput() {
        input = nil
    }

    /// 描画変換を行う。基底は無変換。具象処理器が差し替える。
    @discardableResult
    open func update(_ description: EffectDescription) throws -> DrawDescription {
        description.drawDescription
    }

    public func dispose() {
        input = nil
    }
}

/// エフェクト説明から評価文脈（アイテム内フレーム・長さ・FPS）を取る共通形。
/// 本家の各処理器は `effectDescription.ItemPosition.Frame` 等を直接読む。
extension EffectDescription {
    /// アイテム内位置（フレーム）。
    var itemFrame: Int { itemDescription.itemPosition.frame }
    /// アイテムの長さ（フレーム）。
    var itemDurationFrames: Int { itemDescription.itemDuration.frame }
    /// フレームレート。
    var fps: Int { itemDescription.fps }
}
