import XCTest
@testable import CC_FLOW

final class MusicPlayerApplicationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "MusicPlayerApplicationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testMapsKnownDisplayNamesAndBundleIdentifiers() {
        XCTAssertEqual(MusicPlayerApplication.from(source: "Spotify"), .spotify)
        XCTAssertEqual(MusicPlayerApplication.from(source: "Apple Music"), .appleMusic)
        XCTAssertEqual(MusicPlayerApplication.from(source: "Music"), .appleMusic)
        XCTAssertEqual(MusicPlayerApplication.from(source: "iTunes"), .appleMusic)
        XCTAssertEqual(MusicPlayerApplication.from(source: "网易云音乐"), .neteaseMusic)
        XCTAssertEqual(MusicPlayerApplication.from(source: "com.netease.163music.mac"), .neteaseMusic)
        XCTAssertEqual(MusicPlayerApplication.from(source: "QQ音乐"), .qqMusic)
        XCTAssertEqual(MusicPlayerApplication.from(source: "QQ Music"), .qqMusic)
        XCTAssertEqual(MusicPlayerApplication.from(source: "com.tencent.QQMusicMac"), .qqMusic)
    }

    func testUnknownSourceDoesNotOverwriteRememberedPlayer() {
        let store = MusicPlayerApplicationStore(defaults: defaults)
        store.record(source: "Spotify")
        store.record(source: "Safari")

        XCTAssertEqual(store.rememberedApplication, .spotify)
    }

    func testRememberedPlayerPersistsAcrossStoreInstances() {
        MusicPlayerApplicationStore(defaults: defaults).record(source: "网易云音乐")

        let restoredStore = MusicPlayerApplicationStore(defaults: defaults)
        XCTAssertEqual(restoredStore.rememberedApplication, .neteaseMusic)
    }

    func testPrefersRememberedInstalledPlayer() {
        let store = MusicPlayerApplicationStore(defaults: defaults)
        store.record(source: "Spotify")

        let preferred = store.preferredApplication { application in
            application == .spotify || application == .appleMusic
        }

        XCTAssertEqual(preferred, .spotify)
    }

    func testFallsBackToAppleMusicWhenRememberedPlayerIsUnavailable() {
        let store = MusicPlayerApplicationStore(defaults: defaults)
        store.record(source: "Spotify")

        let preferred = store.preferredApplication { $0 == .appleMusic }

        XCTAssertEqual(preferred, .appleMusic)
    }

    func testReturnsNilWhenNeitherRememberedPlayerNorAppleMusicIsAvailable() {
        let store = MusicPlayerApplicationStore(defaults: defaults)
        store.record(source: "Spotify")

        XCTAssertNil(store.preferredApplication { _ in false })
    }
}
