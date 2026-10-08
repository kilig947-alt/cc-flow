import XCTest
import Sparkle
@testable import CC_FLOW

final class UpdateManagerTests: XCTestCase {
    func testSilentUpdateCheckIntervalMatchesTenMinuteIdlePolicy() {
        XCTAssertEqual(UpdateManager.silentCheckInterval, 10 * 60)
    }

    func testHasActiveSessionsReturnsTrueWhenAnySessionIsProcessing() {
        let sessions = [
            SessionState(sessionId: "idle", cwd: "/tmp/idle", phase: .idle),
            SessionState(sessionId: "processing", cwd: "/tmp/processing", phase: .processing)
        ]

        XCTAssertTrue(UpdateManager.hasActiveSessions(in: sessions))
    }

    func testHasActiveSessionsIgnoresWaitingAndEndedSessions() {
        let sessions = [
            SessionState(sessionId: "waiting", cwd: "/tmp/waiting", phase: .waitingForInput),
            SessionState(sessionId: "ended", cwd: "/tmp/ended", phase: .ended)
        ]

        XCTAssertFalse(UpdateManager.hasActiveSessions(in: sessions))
    }

    func testTruncatedHttpsFeedURLIsRejected() {
        XCTAssertFalse(UpdateManager.isValidFeedURL("https:"))
    }

    func testPublishedGitHubFeedURLIsAccepted() {
        XCTAssertTrue(
            UpdateManager.isValidFeedURL(
                "https://github.com/kilig947-alt/cc-flow/releases/latest/download/appcast.xml"
            )
        )
    }

    func testNoUpdateErrorMapsToUpToDateState() {
        let error = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.noUpdateError.rawValue),
            userInfo: [
                SPUNoUpdateFoundReasonKey: NSNumber(value: SPUNoUpdateFoundReason.onLatestVersion.rawValue)
            ]
        )

        XCTAssertEqual(
            UpdateManager.terminalState(forUpdateCycleError: error),
            .upToDate
        )
    }

    func testCompatibilityNoUpdateErrorMapsToActionableErrorState() {
        let error = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.noUpdateError.rawValue),
            userInfo: [
                SPUNoUpdateFoundReasonKey: NSNumber(value: SPUNoUpdateFoundReason.systemIsTooOld.rawValue)
            ]
        )

        XCTAssertEqual(
            UpdateManager.terminalState(forUpdateCycleError: error),
            .error(message: AppLocalization.runtimeString("update.your_system_version_is_too_old_to_install"))
        )
    }

    func testUnexpectedSparkleErrorPreservesLocalizedMessage() {
        let error = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.downloadError.rawValue),
            userInfo: [NSLocalizedDescriptionKey: "下载失败"]
        )

        XCTAssertEqual(
            UpdateManager.terminalState(forUpdateCycleError: error),
            .error(message: "下载失败")
        )
    }

    func testAppcast404ErrorMapsToActionableErrorState() {
        let error = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.downloadError.rawValue),
            userInfo: [
                NSLocalizedDescriptionKey: "获取升级信息时出现错误，请稍后再试",
                NSUnderlyingErrorKey: NSError(
                    domain: SUSparkleErrorDomain,
                    code: Int(SUError.downloadError.rawValue),
                    userInfo: [
                        NSLocalizedDescriptionKey: "A network error occurred while downloading https://github.com/kilig947-alt/cc-flow/releases/latest/download/appcast.xml. not found (404)"
                    ]
                )
            ]
        )

        XCTAssertEqual(
            UpdateManager.terminalState(forUpdateCycleError: error),
            .error(message: AppLocalization.runtimeString("update.update_feed_unavailable_published_appcast_xml_not_found"))
        )
    }

    func testOfflineUpdateFeedErrorMapsToActionableErrorState() {
        let error = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.downloadError.rawValue),
            userInfo: [
                NSLocalizedDescriptionKey: "获取升级信息时出现错误，请稍后再试",
                NSUnderlyingErrorKey: NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorNotConnectedToInternet,
                    userInfo: [
                        NSLocalizedDescriptionKey: "The Internet connection appears to be offline."
                    ]
                )
            ]
        )

        XCTAssertEqual(
            UpdateManager.terminalState(forUpdateCycleError: error),
            .error(message: AppLocalization.runtimeString("update.network_unavailable_check_your_connection_and_try_again"))
        )
    }
}
