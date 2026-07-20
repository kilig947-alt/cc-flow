import XCTest
@testable import CC_FLOW

final class LeftFeaturePageStateCacheTests: XCTestCase {
    func testExpandedCacheKeyUsesFeatureIdentity() {
        let first = CustomAreaWebViewCache.Key.expanded(featureID: "feature-a")
        let second = CustomAreaWebViewCache.Key.expanded(featureID: "feature-b")
        let sameAsFirst = CustomAreaWebViewCache.Key.expanded(featureID: "feature-a")

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, sameAsFirst)
    }

    func testActiveFeatureClickRequestsReentry() {
        XCTAssertTrue(LeftFeatureReentryRequest.shouldReenter(
            selectedFeatureID: "newsnow",
            activeFeatureID: "newsnow"
        ))
    }

    func testInactiveFeatureClickOnlySelects() {
        XCTAssertFalse(LeftFeatureReentryRequest.shouldReenter(
            selectedFeatureID: "newsnow",
            activeFeatureID: "mineradio"
        ))
        XCTAssertFalse(LeftFeatureReentryRequest.shouldReenter(
            selectedFeatureID: "newsnow",
            activeFeatureID: nil
        ))
    }

    func testReentryGenerationIsConsumedOncePerFeature() {
        let cache = CustomAreaWebViewCache.shared
        let key = CustomAreaWebViewCache.Key.expanded(featureID: "newsnow")
        cache.clearAll()

        XCTAssertTrue(cache.consumeEntryReload(for: key, generation: 1))
        XCTAssertFalse(cache.consumeEntryReload(for: key, generation: 1))
        XCTAssertTrue(cache.consumeEntryReload(for: key, generation: 2))
    }
}
