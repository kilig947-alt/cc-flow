import XCTest
@testable import CC_FLOW

final class ProductivityFeatureTests: XCTestCase {
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
}
