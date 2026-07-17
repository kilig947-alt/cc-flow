import XCTest
import Network
import Combine
@testable import CC_FLOW

final class ProductivityFeatureTests: XCTestCase {
    func testDownloadNotificationsOnlyTriggerAtStartAndCompletion() {
        XCTAssertEqual(ProductivityProactiveEventCenter.downloadTransitions(previousState: nil, newState: "in_progress"), [.downloadStarted])
        XCTAssertEqual(ProductivityProactiveEventCenter.downloadTransitions(previousState: "in_progress", newState: "in_progress"), [])
        XCTAssertEqual(ProductivityProactiveEventCenter.downloadTransitions(previousState: "in_progress", newState: "complete"), [.downloadCompleted])
        XCTAssertEqual(ProductivityProactiveEventCenter.downloadTransitions(previousState: "complete", newState: "complete"), [])
        XCTAssertEqual(ProductivityProactiveEventCenter.downloadTransitions(previousState: "complete", newState: "in_progress"), [])
        XCTAssertEqual(ProductivityProactiveEventCenter.downloadTransitions(previousState: nil, newState: "complete"), [.downloadStarted, .downloadCompleted])
    }

    func testMailNotificationsRequireBaselineAndOnlyCountNewIDs() {
        XCTAssertEqual(ProductivityProactiveEventCenter.newMailCount(previousIDs: [], currentIDs: ["a"], hasBaseline: false), 0)
        XCTAssertEqual(ProductivityProactiveEventCenter.newMailCount(previousIDs: ["a"], currentIDs: ["a", "b", "c"], hasBaseline: true), 2)
        XCTAssertEqual(ProductivityProactiveEventCenter.newMailCount(previousIDs: ["a"], currentIDs: ["a"], hasBaseline: true), 0)
    }

    @MainActor
    func testProactiveEventsPublishImmediatelyAndConsumeOnce() async throws {
        let center = ProductivityProactiveEventCenter(shouldAcceptEvent: { _ in true })
        center.publish(targetFeatureID: LeftFeature.downloadMonitorID, kind: .downloadStarted, summary: "A")
        let event = try XCTUnwrap(center.latestEvent)
        XCTAssertEqual(event.targetFeatureID, LeftFeature.downloadMonitorID)
        XCTAssertEqual(event.kind, .downloadStarted)
        XCTAssertEqual(event.summary, "A")
        XCTAssertEqual(event.count, 1)
        XCTAssertTrue(center.consume(event.sequence))
        XCTAssertFalse(center.consume(event.sequence))
    }

    @MainActor
    func testSameFeatureEventsRemainSeparateAndOrdered() async throws {
        let center = ProductivityProactiveEventCenter(shouldAcceptEvent: { _ in true })
        center.publish(targetFeatureID: LeftFeature.downloadMonitorID, kind: .downloadStarted, summary: "A")
        center.publish(targetFeatureID: LeftFeature.downloadMonitorID, kind: .downloadCompleted, summary: "B")

        XCTAssertEqual(center.pendingEvents.map(\.kind), [.downloadStarted, .downloadCompleted])
        XCTAssertEqual(center.pendingEvents.map(\.summary), ["A", "B"])
        XCTAssertEqual(center.pendingEvents.map(\.count), [1, 1])
        XCTAssertLessThan(center.pendingEvents[0].sequence, center.pendingEvents[1].sequence)
        let first = try XCTUnwrap(center.nextEvent)
        XCTAssertTrue(center.consume(first.sequence))
        XCTAssertEqual(center.nextEvent?.kind, .downloadCompleted)
    }

    @MainActor
    func testProactiveEventsAreRejectedAtPublishTimeWhenPolicyBlocksThem() async {
        let center = ProductivityProactiveEventCenter(shouldAcceptEvent: { $0 != LeftFeature.mailAssistantID })
        center.publish(targetFeatureID: LeftFeature.mailAssistantID, kind: .mailReceived, summary: "muted")
        XCTAssertTrue(center.pendingEvents.isEmpty)
    }

    @MainActor
    func testQueueChangeSignalObservesCommittedEvent() async {
        let center = ProductivityProactiveEventCenter(shouldAcceptEvent: { _ in true })
        var observedEvent: ProductivityProactiveEvent?
        let cancellable = center.queueDidChange.sink {
            observedEvent = center.nextEvent
        }

        center.publish(
            targetFeatureID: LeftFeature.browserResourcesID,
            kind: .browserResourceSaved,
            summary: "saved"
        )

        XCTAssertEqual(observedEvent?.kind, .browserResourceSaved)
        XCTAssertEqual(observedEvent?.summary, "saved")
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testQueueSubscriptionImmediatelyObservesEventPublishedBeforeSubscription() async {
        let center = ProductivityProactiveEventCenter(shouldAcceptEvent: { _ in true })
        center.publish(
            targetFeatureID: LeftFeature.browserResourcesID,
            kind: .browserResourceSaved,
            summary: "saved-before-subscription"
        )

        var observedEvent: ProductivityProactiveEvent?
        let cancellable = center.queueDidChange.prepend(()).sink {
            observedEvent = center.nextEvent
        }

        XCTAssertEqual(observedEvent?.summary, "saved-before-subscription")
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testQueueSignalCanDrainConsecutiveDownloadEventsWithoutRevival() async {
        let center = ProductivityProactiveEventCenter(shouldAcceptEvent: { _ in true })
        var deliveredKinds: [ProductivityProactiveEventKind] = []
        let cancellable = center.queueDidChange.sink {
            guard let event = center.nextEvent else { return }
            deliveredKinds.append(event.kind)
            XCTAssertTrue(center.consume(event.sequence))
        }

        center.publish(targetFeatureID: LeftFeature.downloadMonitorID, kind: .downloadStarted, summary: "start")
        center.publish(targetFeatureID: LeftFeature.downloadMonitorID, kind: .downloadCompleted, summary: "complete")

        XCTAssertEqual(deliveredKinds, [.downloadStarted, .downloadCompleted])
        XCTAssertTrue(center.pendingEvents.isEmpty)
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testImmediateQueueRetainsNewestHundredEventsInFIFOOrder() async {
        let center = ProductivityProactiveEventCenter(shouldAcceptEvent: { _ in true })

        for index in 0..<105 {
            center.publish(
                targetFeatureID: LeftFeature.browserResourcesID,
                kind: .browserResourceSaved,
                summary: "event-\(index)"
            )
        }

        XCTAssertEqual(center.pendingEvents.count, 100)
        XCTAssertEqual(center.pendingEvents.first?.summary, "event-5")
        XCTAssertEqual(center.pendingEvents.last?.summary, "event-104")
        XCTAssertEqual(center.pendingEvents.map(\.sequence), Array(6...105))
    }

    func testBrowserResourceDecodesLegacyRecordWithoutFavicon() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","url":"https://example.com/page","title":"Example","browser":"Chrome","savedAt":0}
        """
        let resource = try JSONDecoder().decode(BrowserResource.self, from: Data(json.utf8))
        XCTAssertEqual(resource.url.absoluteString, "https://example.com/page")
        XCTAssertNil(resource.iconID)
    }

    func testLocalAIProviderProducesVersionedNonExecutableResult() {
        let request = AIProviderRequest(task: .fileCard, filename: "notes.pdf", path: "/tmp/notes.pdf",
            fileType: "pdf", ocrText: nil, query: nil, title: nil, snippet: nil)
        let response = AIProviderService.localResponse(for: request)
        XCTAssertEqual(response.version, 1)
        XCTAssertTrue(response.tags.contains("文档"))
        XCTAssertFalse(response.suggestion?.contains("rm ") == true)
    }

    func testAIResponseDecoderRejectsUnknownVersion() {
        let data = Data(#"{"version":2,"summary":"x","tags":[],"suggestion":null}"#.utf8)
        XCTAssertThrowsError(try AIProviderService.decodeResponse(from: data))
    }

    func testMailVerificationCodeExtractionUsesBoundedNumericToken() {
        XCTAssertEqual(MailAssistantService.firstCode(in: "Your code is 483921"), "483921")
        XCTAssertEqual(MailAssistantService.firstCode(in: "验证码：1024，请勿分享"), "1024")
        XCTAssertNil(MailAssistantService.firstCode(in: "Order 123 contains no standalone four digit token"))
    }

    @MainActor
    func testBrowserResourceRejectsNonWebSchemes() {
        let service = BrowserResourceService.shared
        let originalCount = service.resources.count
        service.inputURL = "file:///etc/passwd"
        service.saveCurrentInput()
        XCTAssertEqual(service.resources.count, originalCount)
    }

    func testBrowserBridgeRejectsNonLoopbackPeers() {
        XCTAssertTrue(BrowserBridgeService.isLoopback(.hostPort(host: "127.0.0.1", port: 43128)))
        XCTAssertTrue(BrowserBridgeService.isLoopback(.hostPort(host: "::1", port: 43128)))
        XCTAssertFalse(BrowserBridgeService.isLoopback(.hostPort(host: "192.168.1.8", port: 43128)))
    }

    func testBrowserExtensionTargetsUseExpectedAppsAndManagementPages() {
        XCTAssertEqual(BrowserExtensionTarget.chrome.bundleIdentifier, "com.google.Chrome")
        XCTAssertEqual(BrowserExtensionTarget.chrome.extensionManagementURL?.absoluteString, "chrome://extensions/")
        XCTAssertEqual(BrowserExtensionTarget.edge.bundleIdentifier, "com.microsoft.edgemac")
        XCTAssertEqual(BrowserExtensionTarget.edge.extensionManagementURL?.absoluteString, "edge://extensions/")
        XCTAssertEqual(BrowserExtensionTarget.safari.bundleIdentifier, "com.apple.Safari")
        XCTAssertNil(BrowserExtensionTarget.safari.extensionManagementURL)
    }

    @MainActor
    func testNaturalSearchOnlyMatchesCardMetadata() {
        let service = LocalFileIndexService.shared
        service.query = "a-value-that-does-not-exist-in-card-metadata"
        XCTAssertTrue(service.results.isEmpty)
        service.query = ""
    }

    func testFileWatchRejectsCardsOutsideAuthorizedFolders() {
        let authorized = URL(fileURLWithPath: "/Users/test/Documents")
        XCTAssertTrue(LocalFileIndexService.isAuthorized(URL(fileURLWithPath: "/Users/test/Documents/a.pdf"), roots: [authorized]))
        XCTAssertFalse(LocalFileIndexService.isAuthorized(URL(fileURLWithPath: "/Users/test/Documents-old/a.pdf"), roots: [authorized]))
        XCTAssertFalse(LocalFileIndexService.isAuthorized(URL(fileURLWithPath: "/Users/test/Desktop/a.pdf"), roots: [authorized]))
    }

    func testCalendarActionableRemindersOnlyIncludesOverdueAndToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_720_008_000)
        let reminders = [
            ReminderAgendaItem(id: "past", title: "past", dueDate: now.addingTimeInterval(-86_400), priority: 0),
            ReminderAgendaItem(id: "today", title: "today", dueDate: now.addingTimeInterval(60), priority: 0),
            ReminderAgendaItem(id: "future", title: "future", dueDate: now.addingTimeInterval(172_800), priority: 0),
            ReminderAgendaItem(id: "none", title: "none", dueDate: nil, priority: 0)
        ]
        XCTAssertEqual(CalendarService.actionableReminders(reminders, now: now, calendar: calendar).map(\.id), ["past", "today"])
    }

    func testRemovedDefaultFolderDoesNotReturnOnNextInitialization() {
        let home = URL(fileURLWithPath: "/Users/test")
        let folders = LocalFileIndexService.initialFolders(home: home,
            removedDefaultPaths: [home.appendingPathComponent("Downloads").path], saved: [])
        XCTAssertFalse(folders.contains(home.appendingPathComponent("Downloads")))
        XCTAssertFalse(folders.contains(home.appendingPathComponent("Desktop")))
    }

    func testFileWatchDefaultsToDownloadsAndDocumentsAsPendingAuthorization() {
        let home = URL(fileURLWithPath: "/Users/test")
        XCTAssertEqual(LocalFileIndexService.defaultFolders(home: home).map(\.lastPathComponent), ["Downloads", "Documents"])
        XCTAssertEqual(
            LocalFileIndexService.pendingDefaults(home: home, removedDefaultPaths: [], authorized: []).map(\.lastPathComponent),
            ["Downloads", "Documents"]
        )
    }

    func testFileWatchPendingDefaultsRespectAuthorizationAndRemoval() {
        let home = URL(fileURLWithPath: "/Users/test")
        let downloads = home.appendingPathComponent("Downloads")
        let documents = home.appendingPathComponent("Documents")
        XCTAssertEqual(
            LocalFileIndexService.pendingDefaults(home: home, removedDefaultPaths: [], authorized: [downloads]).map(\.path),
            [documents.path]
        )
        XCTAssertEqual(
            LocalFileIndexService.pendingDefaults(home: home, removedDefaultPaths: [documents.path], authorized: []).map(\.path),
            [downloads.path]
        )
    }

    func testNaturalQueryParsesChinesePathTypeAndTagWithoutSQL() {
        let parsed = NaturalFileQuery.parse("帮我找 下载里的最近截图 PDF")
        XCTAssertEqual(parsed.tags, ["截图"])
        XCTAssertEqual(parsed.extensions, ["pdf"])
        XCTAssertEqual(parsed.pathHints, ["/downloads/"])
        XCTAssertTrue(parsed.terms.isEmpty)
    }

    func testFileActionRequiresFreshPlanAvoidsOverwriteAndCanUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("sample.png")
        try Data("image".utf8).write(to: source)
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let card = LocalFileCard(id: source.path, url: source, name: source.lastPathComponent, kind: "PNG",
            size: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate ?? .distantPast,
            tags: ["图片"], summary: "test", ocrText: "", suggestion: "建议归档")
        let plan = try FileActionExecutor.makePlan(for: card)
        let audit = try await FileActionExecutor.shared.executeConfirmed(plan)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.destination.path))
        try await FileActionExecutor.shared.undo(audit.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testFileCardPersistenceRetainsOnlySearchableMetadata() throws {
        let card = LocalFileCard(id: "/tmp/a.png", url: URL(fileURLWithPath: "/tmp/a.png"), name: "a.png",
            kind: "PNG", size: 12, modifiedAt: Date(timeIntervalSince1970: 10), tags: ["图片"],
            summary: "截图摘要", ocrText: "识别文字", suggestion: "整理建议")
        let data = try JSONEncoder().encode(card)
        let decoded = try JSONDecoder().decode(LocalFileCard.self, from: data)
        XCTAssertEqual(decoded, card)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("fileContents"))
    }
}
