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

    // MARK: - カスタム音声ファイルの同一性（Issue #134）

    /// テスト用の一時ファイルを作り、パスを返す。呼び出し側で
    /// 削除すること。
    private func makeTempVoiceFile(contents: Data, modified: Date) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ymm4-envelope-test-\(UUID().uuidString).wav")
        try contents.write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: modified], ofItemAtPath: url.path
        )
        return url.path
    }

    private func setModified(_ date: Date, ofFileAtPath path: String) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: date], ofItemAtPath: path
        )
    }

    /// 同一パスのファイルを別サイズの内容へ差し替えると署名が
    /// 変わる（包絡キャッシュが再計算される条件）。
    func testSignatureChangesWhenCustomVoiceFileReplacedWithDifferentSize() throws {
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let path = try makeTempVoiceFile(contents: Data([1, 2, 3]), modified: modified)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let voice = makeVoice()
        voice.hatsuon = path
        let before = MetalTachieSource.envelopeSignature(of: voice)
        try Data([1, 2, 3, 4, 5]).write(to: URL(fileURLWithPath: path))
        try setModified(modified, ofFileAtPath: path)
        XCTAssertNotEqual(
            before, MetalTachieSource.envelopeSignature(of: voice)
        )
    }

    /// 同一パスのファイルを同サイズの内容へ差し替えても、更新時刻
    /// が変われば署名が変わる。サイズと更新時刻を元へ戻せば署名も
    /// 元へ戻る（同一性はサイズ＋更新時刻で定義される）。
    func testSignatureChangesWhenCustomVoiceFileReplacedWithSameSizeNewerMtime() throws {
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let path = try makeTempVoiceFile(contents: Data([1, 2, 3]), modified: modified)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let voice = makeVoice()
        voice.hatsuon = path
        let before = MetalTachieSource.envelopeSignature(of: voice)

        try Data([4, 5, 6]).write(to: URL(fileURLWithPath: path))
        try setModified(modified.addingTimeInterval(60), ofFileAtPath: path)
        XCTAssertNotEqual(
            before, MetalTachieSource.envelopeSignature(of: voice)
        )

        try setModified(modified, ofFileAtPath: path)
        XCTAssertEqual(
            before, MetalTachieSource.envelopeSignature(of: voice)
        )
    }

    /// ファイルに触れていなければ署名は安定する（差し替えが無い
    /// 場合は従来どおりキャッシュが効くことの回帰）。
    func testSignatureIsStableWhileCustomVoiceFileIsUntouched() throws {
        let path = try makeTempVoiceFile(
            contents: Data([1, 2, 3]),
            modified: Date(timeIntervalSince1970: 1_700_000_000)
        )
        defer { try? FileManager.default.removeItem(atPath: path) }
        let voice = makeVoice()
        voice.hatsuon = path
        XCTAssertEqual(
            MetalTachieSource.envelopeSignature(of: voice),
            MetalTachieSource.envelopeSignature(of: voice)
        )
    }

    /// ファイルの消滅と出現も署名の変化として検出できる。
    func testSignatureChangesWhenCustomVoiceFileDisappearsAndReappears() throws {
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let path = try makeTempVoiceFile(contents: Data([1, 2, 3]), modified: modified)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let voice = makeVoice()
        voice.hatsuon = path
        let present = MetalTachieSource.envelopeSignature(of: voice)

        try FileManager.default.removeItem(atPath: path)
        let missing = MetalTachieSource.envelopeSignature(of: voice)
        XCTAssertNotEqual(present, missing)
        // 不在の間は不在標識で安定する。
        XCTAssertEqual(
            missing, MetalTachieSource.envelopeSignature(of: voice)
        )
        XCTAssertEqual(
            MetalTachieSource.fileIdentityComponent(ofHatsuon: path),
            "file:missing"
        )

        // 同じパスへ作り直す（更新時刻は変える）。
        try Data([1, 2, 3]).write(to: URL(fileURLWithPath: path))
        try setModified(modified.addingTimeInterval(120), ofFileAtPath: path)
        XCTAssertNotEqual(
            missing, MetalTachieSource.envelopeSignature(of: voice)
        )
    }

    /// file URL 形式の発音でもファイル同一性が署名に入る。
    func testFileURLHatsuonAlsoCarriesFileIdentity() throws {
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let path = try makeTempVoiceFile(contents: Data([1, 2, 3]), modified: modified)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let voice = makeVoice()
        voice.hatsuon = URL(fileURLWithPath: path).absoluteString
        XCTAssertNotNil(
            MetalTachieSource.fileIdentityComponent(ofHatsuon: voice.hatsuon)
        )
        let before = MetalTachieSource.envelopeSignature(of: voice)
        try Data([9, 9]).write(to: URL(fileURLWithPath: path))
        XCTAssertNotEqual(
            before, MetalTachieSource.envelopeSignature(of: voice)
        )
    }

    /// ファイルパスでない発音（音声エンジンの声名など）では、
    /// ファイル同一性の部品は付かず、署名は従来どおりアイテム側の
    /// 入力だけで決まる。
    func testNonFileHatsuonHasNoFileIdentityComponent() {
        XCTAssertNil(
            MetalTachieSource.fileIdentityComponent(ofHatsuon: "テスト")
        )
        XCTAssertNil(
            MetalTachieSource.fileIdentityComponent(ofHatsuon: "voice.wav")
        )
        XCTAssertNil(
            MetalTachieSource.fileIdentityComponent(ofHatsuon: "")
        )
        let voice = makeVoice()
        let signature = MetalTachieSource.envelopeSignature(of: voice)
        XCTAssertFalse(signature.contains("file:"))
        XCTAssertEqual(
            signature, MetalTachieSource.envelopeSignature(of: voice)
        )
    }
}
