import XCTest
import PreviewCore
import YMM4Core
import YMM4GPU

/// 素材の利用可否の状態→表示の対応（Issue #70 段階4）と、
/// プレビュー側・書き出し側が同じ台帳を参照することの固定。
final class MediaAvailabilityPresentationTests: XCTestCase {
    private func failure(
        _ kind: MediaAvailabilityFailureKind
    ) -> MediaAvailabilityFailure {
        MediaAvailabilityFailure(kind: kind, detail: "test", occurredAt: Date())
    }

    /// 状態→通知の対応: 未試行・利用可は通知なし、読み込み中は
    /// 警告なしの通知、失敗は種別ごとの案内文言つき。
    func testNoticeMapping() {
        XCTAssertNil(MediaAvailabilityPresentation.notice(
            for: .notAttempted, fileName: "a.mkv"
        ))
        XCTAssertNil(MediaAvailabilityPresentation.notice(
            for: .available, fileName: "a.mkv"
        ))
        let loading = MediaAvailabilityPresentation.notice(
            for: .loading, fileName: "a.mkv"
        )
        XCTAssertEqual(loading?.state, .loading)
        XCTAssertFalse(loading?.state.isFailed ?? true)

        for kind in [
            MediaAvailabilityFailureKind.fileNotFound,
            .unsupportedOrDecodeFailed, .ffmpegUnavailable, .midStreamFailure,
        ] {
            let notice = MediaAvailabilityPresentation.notice(
                for: .failed(failure(kind)), fileName: "a.mkv"
            )
            XCTAssertEqual(notice?.state, .failed(kind))
            XCTAssertEqual(
                notice?.message,
                MediaAvailabilityPresentation.guidanceMessage(for: kind)
            )
            XCTAssertFalse(notice?.message.isEmpty ?? true)
        }
    }

    /// 案内文言: ファイルなしは再指定、FFmpeg 未設定は用意すれば
    /// 開ける旨を含む。
    func testGuidanceMessages() {
        XCTAssertTrue(MediaAvailabilityPresentation
            .guidanceMessage(for: .fileNotFound).contains("再指定"))
        XCTAssertTrue(MediaAvailabilityPresentation
            .guidanceMessage(for: .ffmpegUnavailable).contains("FFmpeg"))
    }

    /// 台帳から通知表を作る: 失敗したアイテムだけが残り、
    /// ファイル名はパスから取り出される。
    func testNoticesFromRegistry() {
        let registry = MediaAvailabilityRegistry()
        let failedKey = MediaMaterialKey(filePath: "/proj/movie.mkv")
        let okKey = MediaMaterialKey(filePath: "/proj/song.wav")
        registry.markFailed(
            for: failedKey, failure: failure(.fileNotFound)
        )
        registry.markAvailable(for: okKey)
        let failedItem = VideoItem()
        let okItem = AudioItem()
        let notices = MediaAvailabilityPresentation.notices(
            materialKeys: [
                ObjectIdentifier(failedItem): failedKey,
                ObjectIdentifier(okItem): okKey,
            ],
            registry: registry
        )
        XCTAssertEqual(notices.count, 1)
        let notice = notices[ObjectIdentifier(failedItem)]
        XCTAssertEqual(notice?.fileName, "movie.mkv")
        XCTAssertEqual(notice?.state, .failed(.fileNotFound))
    }

    /// プレビューの集約文: 失敗が無ければ出さず、読み込み中だけ
    /// でも出さない。全て途中失敗なら再生中の失敗の文言になる。
    func testPreviewBanner() {
        typealias Notice = MediaAvailabilityPresentation.Notice
        let item = VideoItem()
        let id = ObjectIdentifier(item)
        XCTAssertNil(MediaAvailabilityPresentation.previewBanner(notices: [:]))
        XCTAssertNil(MediaAvailabilityPresentation.previewBanner(notices: [
            id: Notice(state: .loading, fileName: "a.mkv", message: ""),
        ]))
        let generic = MediaAvailabilityPresentation.previewBanner(notices: [
            id: Notice(
                state: .failed(.unsupportedOrDecodeFailed),
                fileName: "a.mkv", message: "x"
            ),
        ])
        XCTAssertTrue(generic?.contains("読み込めない素材があります") ?? false)
        let midStream = MediaAvailabilityPresentation.previewBanner(notices: [
            id: Notice(
                state: .failed(.midStreamFailure),
                fileName: "a.mkv", message: "x"
            ),
        ])
        XCTAssertTrue(midStream?.contains("再生中に") ?? false)
    }

    /// アイテム→素材パスの対応: 台帳対象（映像・音声・カスタム
    /// 音声）だけが返り、空パスと対象外種別は nil。
    func testMaterialPath() {
        let video = VideoItem()
        video.filePath = "movie.mkv"
        XCTAssertEqual(
            MediaAvailabilityPresentation.materialPath(for: video), "movie.mkv"
        )
        let emptyVideo = VideoItem()
        emptyVideo.filePath = ""
        XCTAssertNil(MediaAvailabilityPresentation.materialPath(for: emptyVideo))
        let voice = VoiceItem()
        voice.hatsuon = "voice.wav"
        XCTAssertEqual(
            MediaAvailabilityPresentation.materialPath(for: voice), "voice.wav"
        )
        let text = TextItem()
        XCTAssertNil(MediaAvailabilityPresentation.materialPath(for: text))
    }

    /// 所有の一本化: プレビュー（PreviewBox）と書き出し
    /// （TimelineExporter）に同じ基盤を渡すと、両者は同じ
    /// インスタンス・同じ台帳を参照する。
    func testPreviewAndExportShareTheSameRegistry() throws {
        let support = FFmpegMediaSupport()
        let timeline = Timeline()
        timeline.videoInfo = VideoInfo(fps: 30, hz: 48_000, width: 320, height: 180)
        let box = PreviewBox(
            key: PreviewBox.SessionKey(
                url: URL(fileURLWithPath: "/tmp/project.ymmp"), timelineIndex: 0
            ),
            timeline: timeline, baseDirectory: nil, mediaSupport: support
        )
        XCTAssertTrue(box.mediaSupport === support)

        let exporter: TimelineExporter
        do {
            exporter = try TimelineExporter(
                timeline: timeline, timelines: [timeline],
                baseDirectory: nil, mediaSupport: support
            )
        } catch let error as MetalInitializationError {
            throw XCTSkip("Metal を初期化できない環境のため省略: \(error.userMessage)")
        }
        XCTAssertTrue(exporter.mediaSupport === support)
        XCTAssertTrue(box.mediaSupport.registry === exporter.mediaSupport.registry)
        exporter.dispose()
        box.dispose()
    }
}
