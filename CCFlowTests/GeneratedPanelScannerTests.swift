import Combine
import XCTest
@testable import CC_FLOW

@MainActor
final class GeneratedPanelScannerTests: XCTestCase {
    private var temporaryRoot: URL!
    private var scanner: GeneratedPanelScanner!
    private var importedCandidates: [GeneratedPanelScanner.Candidate] = []
    private var bookmarkedURLs: [URL] = []
    private var cancellables = Set<AnyCancellable>()

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("GeneratedPanelScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        importedCandidates = []
        bookmarkedURLs = []
        scanner = GeneratedPanelScanner(
            rootURL: temporaryRoot,
            registeredAreasProvider: { [] },
            candidateImporter: { [weak self] candidate in
                self?.importedCandidates.append(candidate)
            },
            bookmarkSaver: { [weak self] url in
                self?.bookmarkedURLs.append(url)
                return true
            }
        )
    }

    override func tearDownWithError() throws {
        scanner.stop()
        try? FileManager.default.removeItem(at: temporaryRoot)
        scanner = nil
        temporaryRoot = nil
        cancellables.removeAll()
    }

    func testCandidateUsesDefaultsWithoutManifest() throws {
        let directory = try makePanelDirectory(name: "weather-card")

        let candidate = try scanner.candidate(for: directory)

        XCTAssertEqual(candidate.directoryURL, directory.standardizedFileURL)
        XCTAssertEqual(candidate.name, "weather-card")
        XCTAssertEqual(candidate.entryPointRelativePath, "index.html")
        XCTAssertNil(candidate.iconName)
        XCTAssertFalse(candidate.allowsNetworkAccess)
    }

    func testCandidateMapsManifestMetadata() throws {
        let directory = try makePanelDirectory(name: "metrics")
        try write(
            """
            {
              "id": "metrics",
              "name": "系统指标",
              "entryPoint": "pages/dashboard.html",
              "icon": "gauge.with.dots.needle.67percent",
              "allowsNetworkAccess": true
            }
            """,
            to: directory.appendingPathComponent("cc-flow-panel.json")
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("pages"),
            withIntermediateDirectories: true
        )
        try write("<html></html>", to: directory.appendingPathComponent("pages/dashboard.html"))

        let candidate = try scanner.candidate(for: directory)

        XCTAssertEqual(candidate.name, "系统指标")
        XCTAssertEqual(candidate.entryPointRelativePath, "pages/dashboard.html")
        XCTAssertEqual(candidate.iconName, "gauge.with.dots.needle.67percent")
        XCTAssertTrue(candidate.allowsNetworkAccess)
    }

    func testCandidateAcceptsV2PluginManifest() throws {
        let directory = try makePanelDirectory(name: "plugin")
        try write(
            #"{"manifestVersion":2,"id":"com.example.plugin","name":"Plugin","version":"1.0.0","entryPoint":"index.html","sdkVersion":"^1.0","capabilities":["system.metrics.read"]}"#,
            to: directory.appendingPathComponent("cc-flow-panel.json")
        )

        XCTAssertNoThrow(try scanner.candidate(for: directory))
    }

    func testCandidateRejectsUnknownV2Capability() throws {
        let directory = try makePanelDirectory(name: "unknown-capability")
        try write(
            #"{"manifestVersion":2,"id":"com.example.plugin","version":"1.0.0","sdkVersion":"^1.0","capabilities":["shell.execute"]}"#,
            to: directory.appendingPathComponent("cc-flow-panel.json")
        )

        XCTAssertThrowsError(try scanner.candidate(for: directory)) { error in
            guard case .invalidPluginManifest(let message) = error as? GeneratedPanelScanner.ValidationError else {
                return XCTFail("Expected invalidPluginManifest, got \(error)")
            }
            XCTAssertTrue(message.contains("shell.execute"))
        }
    }

    func testCandidateRequiresExplicitV2Capabilities() throws {
        let directory = try makePanelDirectory(name: "missing-capabilities")
        try write(
            #"{"manifestVersion":2,"id":"com.example.plugin","version":"1.0.0","sdkVersion":"^1.0"}"#,
            to: directory.appendingPathComponent("cc-flow-panel.json")
        )

        XCTAssertThrowsError(try scanner.candidate(for: directory)) { error in
            guard case .invalidPluginManifest(let message) = error as? GeneratedPanelScanner.ValidationError else {
                return XCTFail("Expected invalidPluginManifest, got \(error)")
            }
            XCTAssertTrue(message.contains("capabilities"))
        }
    }

    func testCandidateRejectsMissingEntryPoint() throws {
        let directory = temporaryRoot.appendingPathComponent("incomplete", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        XCTAssertThrowsError(try scanner.candidate(for: directory)) { error in
            XCTAssertEqual(error as? GeneratedPanelScanner.ValidationError, .missingEntryPoint("index.html"))
        }
    }

    func testCandidateRejectsAbsoluteEntryPoint() throws {
        let directory = try makePanelDirectory(name: "absolute")
        try write(
            "{\"entryPoint\":\"/tmp/panel.html\"}",
            to: directory.appendingPathComponent("cc-flow-panel.json")
        )

        XCTAssertThrowsError(try scanner.candidate(for: directory)) { error in
            XCTAssertEqual(error as? GeneratedPanelScanner.ValidationError, .invalidEntryPoint("/tmp/panel.html"))
        }
    }

    func testCandidateRejectsEntryPointTraversal() throws {
        let directory = try makePanelDirectory(name: "traversal")
        try write("<html></html>", to: temporaryRoot.appendingPathComponent("outside.html"))
        try write(
            "{\"entryPoint\":\"../outside.html\"}",
            to: directory.appendingPathComponent("cc-flow-panel.json")
        )

        XCTAssertThrowsError(try scanner.candidate(for: directory)) { error in
            XCTAssertEqual(error as? GeneratedPanelScanner.ValidationError, .invalidEntryPoint("../outside.html"))
        }
    }

    func testCandidateReportsMalformedManifest() throws {
        let directory = try makePanelDirectory(name: "malformed")
        try write("{not-json}", to: directory.appendingPathComponent("cc-flow-panel.json"))

        XCTAssertThrowsError(try scanner.candidate(for: directory)) { error in
            guard case .malformedManifest = error as? GeneratedPanelScanner.ValidationError else {
                return XCTFail("Expected malformedManifest, got \(error)")
            }
        }
    }

    func testScanImportsValidPanelOnlyOnce() throws {
        _ = try makePanelDirectory(name: "generated")

        scanner.scanNow()
        scanner.scanNow()

        XCTAssertEqual(importedCandidates.map(\.name), ["generated"])
        XCTAssertEqual(scanner.lastResult.importedNames, [])
    }

    func testManualImportUsesBookmarkSaverAndImportsCandidate() throws {
        let directory = try makePanelDirectory(name: "external")

        let result = scanner.importSelectedDirectory(directory)

        XCTAssertEqual(result.importedNames, ["external"])
        XCTAssertEqual(bookmarkedURLs, [directory.standardizedFileURL])
        XCTAssertEqual(importedCandidates.map(\.name), ["external"])
    }

    func testChildDirectoryWatcherImportsEntryPointWrittenLater() throws {
        scanner.start()
        let directory = temporaryRoot.appendingPathComponent("slow-panel", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let imported = expectation(description: "slow panel imported")
        scanner.$lastResult
            .dropFirst()
            .sink { result in
                if result.importedNames.contains("slow-panel") {
                    imported.fulfill()
                }
            }
            .store(in: &cancellables)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            try? Data("<html></html>".utf8)
                .write(to: directory.appendingPathComponent("index.html"), options: .atomic)
        }

        wait(for: [imported], timeout: 4)
        XCTAssertEqual(importedCandidates.map(\.name), ["slow-panel"])
    }

    func testCandidateRejectsSymlinkedEntryOutsidePanel() throws {
        let directory = try makePanelDirectory(name: "symlink")
        let outside = temporaryRoot.appendingPathComponent("outside-linked.html")
        try write("<html></html>", to: outside)
        let linkedEntry = directory.appendingPathComponent("linked.html")
        try FileManager.default.createSymbolicLink(at: linkedEntry, withDestinationURL: outside)
        try write(
            "{\"entryPoint\":\"linked.html\"}",
            to: directory.appendingPathComponent("cc-flow-panel.json")
        )

        XCTAssertThrowsError(try scanner.candidate(for: directory)) { error in
            XCTAssertEqual(error as? GeneratedPanelScanner.ValidationError, .invalidEntryPoint("linked.html"))
        }
    }

    private func makePanelDirectory(name: String) throws -> URL {
        let directory = temporaryRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write("<html></html>", to: directory.appendingPathComponent("index.html"))
        return directory
    }

    private func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url, options: .atomic)
    }
}
