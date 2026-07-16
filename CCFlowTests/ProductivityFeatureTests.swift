import XCTest
@testable import CC_FLOW

final class ProductivityFeatureTests: XCTestCase {
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

    @MainActor
    func testNaturalSearchOnlyMatchesCardMetadata() {
        let service = LocalFileIndexService.shared
        service.query = "a-value-that-does-not-exist-in-card-metadata"
        XCTAssertTrue(service.results.isEmpty)
        service.query = ""
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
}
