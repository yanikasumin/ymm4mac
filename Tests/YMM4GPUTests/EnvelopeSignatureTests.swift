import Foundation
import XCTest

@testable import YMM4GPU
import YMM4Core

/// 包絡キャッシュ署名（MetalTachieSource.envelopeSignature）の検証。
/// 署名は包絡音声を決める入力を一貫して識別しなければならず、
/// 欠落していた3件（ベジェ・音声処理モード・音声キャッシュ内容）を
/// 固定する（R22-116-02）。
final class EnvelopeSignatureTests: XCTestCase {
    private func makeVoice() -> VoiceItem {
        let voice = VoiceItem()
        voice.hatsuon = "テスト"
        return voice
    }

    /// 変更が無ければ署名は安定する。
    func testSignatureIsStableWithoutChanges() {
        let voice = makeVoice()
        XCTAssertEqual(
            MetalTachieSource.envelopeSignature(of: voice),
            MetalTachieSource.envelopeSignature(of: voice)
        )
    }

    /// ベジェだけの変更で署名が変わる（ベジェだけでもレート曲線が
    /// 変わり、包絡の入力音声が変わる）。
    func testSignatureChangesWithBezierOnlyChange() {
        let voice = makeVoice()
        let before = MetalTachieSource.envelopeSignature(of: voice)
        // 既定の制御点オフセットを持たない点列へ差し替える。
        voice.playbackRate2.bezier = BezierAnimation(
            points: [
                BezierAnimationPoint(point: BezierVector(x: 0, y: 0)),
                BezierAnimationPoint(point: BezierVector(x: 1, y: 1)),
            ],
            isQuadratic: false
        )
        XCTAssertNotEqual(
            before, MetalTachieSource.envelopeSignature(of: voice)
        )
        // 2次フラグだけの変更でも変わる。
        let cubic = MetalTachieSource.envelopeSignature(of: voice)
        voice.playbackRate2.bezier.isQuadratic = true
        XCTAssertNotEqual(
            cubic, MetalTachieSource.envelopeSignature(of: voice)
        )
    }

    /// 音声処理モードだけの変更で署名が変わる（SOLA か
    /// リサンプリングかでエフェクトチェーンの出力が変わる）。
    func testSignatureChangesWithProcessingModeOnlyChange() {
        let voice = makeVoice()
        let before = MetalTachieSource.envelopeSignature(of: voice)
        voice.playbackRateAudioProcessingMode = .sola
        XCTAssertNotEqual(
            before, MetalTachieSource.envelopeSignature(of: voice)
        )
    }

    /// 音声キャッシュの同サイズ差し替えで署名が変わる
    /// （バイト数だけの比較では検出できない）。
    func testSignatureChangesWithSameSizeVoiceCacheReplacement() {
        let voice = makeVoice()
        voice.voiceCache = Data([1, 2, 3])
        let before = MetalTachieSource.envelopeSignature(of: voice)
        voice.voiceCache = Data([4, 5, 6])
        XCTAssertNotEqual(
            before, MetalTachieSource.envelopeSignature(of: voice)
        )
    }
}
