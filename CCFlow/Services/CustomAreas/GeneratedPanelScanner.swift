import Combine
import Foundation
import OSLog

/// Discovers TRAE Work Design generated panels and registers them through `CustomAreaStore`.
@MainActor
final class GeneratedPanelScanner: ObservableObject {
    static let shared = GeneratedPanelScanner()

    struct Manifest: Decodable, Equatable {
        let manifestVersion: Int?
        let id: String?
        let name: String?
        let version: String?
        let entryPoint: String?
        let icon: String?
        let sdkVersion: String?
        let capabilities: [String]?
        let allowsNetworkAccess: Bool?
    }

    struct Candidate: Equatable {
        let directoryURL: URL
        let name: String
        let entryPointRelativePath: String
        let iconName: String?
        let allowsNetworkAccess: Bool
    }

    struct ScanIssue: Identifiable, Equatable {
        let directoryName: String
        let message: String

        var id: String { "\(directoryName):\(message)" }
    }

    struct ScanResult: Equatable {
        let importedNames: [String]
        let issues: [ScanIssue]

        static let empty = ScanResult(importedNames: [], issues: [])
    }

    enum ValidationError: LocalizedError, Equatable {
        case notDirectory
        case missingEntryPoint(String)
        case invalidEntryPoint(String)
        case malformedManifest(String)
        case invalidPluginManifest(String)

        var errorDescription: String? {
            switch self {
            case .notDirectory:
                return "所选路径不是目录"
            case .missingEntryPoint(let path):
                return "缺少入口文件：\(path)"
            case .invalidEntryPoint(let path):
                return "入口文件必须位于面板目录内：\(path)"
            case .malformedManifest(let detail):
                return "cc-flow-panel.json 无法解析：\(detail)"
            case .invalidPluginManifest(let detail):
                return "插件清单无效：\(detail)"
            }
        }
    }

    @Published private(set) var lastResult: ScanResult = .empty
    @Published private(set) var isScanning = false

    private static let logger = Logger(subsystem: "ai.ccflow.app", category: "GeneratedPanelScanner")
    private let fileManager: FileManager
    private let rootURL: URL
    private let registeredAreasProvider: () -> [CustomArea]
    private let candidateImporter: (Candidate) -> Void
    private let bookmarkSaver: (URL) -> Bool
    private let queue = DispatchQueue(label: "ai.ccflow.app.generated-panel-scanner", qos: .utility)
    private var rootSource: DispatchSourceFileSystemObject?
    private var pendingDirectorySources: [String: DispatchSourceFileSystemObject] = [:]
    private var scheduledScan: DispatchWorkItem?
    private var incompleteRetryCount = 0
    private var importedPaths = Set<String>()

    init(
        rootURL: URL = BridgeRuntimePaths.customAreasDirectoryURL,
        fileManager: FileManager = .default,
        registeredAreasProvider: (() -> [CustomArea])? = nil,
        candidateImporter: ((Candidate) -> Void)? = nil,
        bookmarkSaver: ((URL) -> Bool)? = nil
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        self.registeredAreasProvider = registeredAreasProvider ?? { CustomAreaStore.shared.areas }
        self.candidateImporter = candidateImporter ?? { candidate in
            _ = CustomAreaStore.shared.addArea(
                name: candidate.name,
                directoryURL: candidate.directoryURL,
                entryPointRelativePath: candidate.entryPointRelativePath,
                defaultVariant: .traeWorkCN,
                autoDetectEntryPoint: false,
                iconName: candidate.iconName,
                allowsNetworkAccess: candidate.allowsNetworkAccess
            )
        }
        self.bookmarkSaver = bookmarkSaver ?? { SecurityScopedBookmarkStore.saveBookmark(for: $0) }
    }

    deinit {
        rootSource?.cancel()
        pendingDirectorySources.values.forEach { $0.cancel() }
        scheduledScan?.cancel()
    }

    func start() {
        guard rootSource == nil else { return }
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            lastResult = ScanResult(
                importedNames: [],
                issues: [ScanIssue(directoryName: rootURL.lastPathComponent, message: error.localizedDescription)]
            )
            return
        }

        let descriptor = open(rootURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            lastResult = ScanResult(
                importedNames: [],
                issues: [ScanIssue(directoryName: rootURL.lastPathComponent, message: "无法监听生成目录")]
            )
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self, weak source] in
            let events = source?.data ?? []
            Task { @MainActor [weak self] in
                if events.contains(.delete) || events.contains(.rename) {
                    self?.restartAfterRootReplacement()
                } else {
                    self?.scheduleScan()
                }
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        rootSource = source
        scheduleScan(delay: 0)
    }

    func stop() {
        scheduledScan?.cancel()
        scheduledScan = nil
        rootSource?.cancel()
        rootSource = nil
        pendingDirectorySources.values.forEach { $0.cancel() }
        pendingDirectorySources.removeAll()
    }

    func scanNow() {
        scheduledScan?.cancel()
        scheduledScan = nil
        incompleteRetryCount = 0
        performManagedRootScan(reportIncompleteDirectories: true)
    }

    @discardableResult
    func importSelectedDirectory(_ directoryURL: URL) -> ScanResult {
        isScanning = true
        defer { isScanning = false }

        let standardizedURL = directoryURL.standardizedFileURL
        if registeredAreasProvider().contains(where: {
            Self.canonicalPath(for: $0.directoryURL) == Self.canonicalPath(for: standardizedURL)
        }) || importedPaths.contains(Self.canonicalPath(for: standardizedURL)) {
            let result = ScanResult(
                importedNames: [],
                issues: [ScanIssue(directoryName: standardizedURL.lastPathComponent, message: "该目录已经在功能列表中")]
            )
            lastResult = result
            return result
        }

        do {
            let candidate = try candidate(for: standardizedURL)
            guard bookmarkSaver(standardizedURL) else {
                let result = ScanResult(
                    importedNames: [],
                    issues: [ScanIssue(directoryName: standardizedURL.lastPathComponent, message: "无法保存目录访问权限")]
                )
                lastResult = result
                return result
            }
            importCandidate(candidate)
            let result = ScanResult(importedNames: [candidate.name], issues: [])
            lastResult = result
            return result
        } catch {
            let result = ScanResult(
                importedNames: [],
                issues: [ScanIssue(
                    directoryName: standardizedURL.lastPathComponent,
                    message: error.localizedDescription
                )]
            )
            lastResult = result
            return result
        }
    }

    func candidate(for directoryURL: URL) throws -> Candidate {
        let directoryURL = directoryURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ValidationError.notDirectory
        }

        let manifestURL = directoryURL.appendingPathComponent("cc-flow-panel.json")
        let manifest: Manifest?
        if fileManager.fileExists(atPath: manifestURL.path) {
            do {
                manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
            } catch {
                throw ValidationError.malformedManifest(error.localizedDescription)
            }
        } else {
            manifest = nil
        }

        if manifest?.manifestVersion == 2 {
            guard let id = manifest?.id, id.range(of: #"^[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)+$"#, options: .regularExpression) != nil else {
                throw ValidationError.invalidPluginManifest("manifestVersion 2 需要稳定的反向域名 id")
            }
            guard let version = manifest?.version, !version.isEmpty else {
                throw ValidationError.invalidPluginManifest("缺少 version")
            }
            guard let sdkVersion = manifest?.sdkVersion, sdkVersion.hasPrefix("^1.") || sdkVersion.hasPrefix("1.") else {
                throw ValidationError.invalidPluginManifest("sdkVersion 必须兼容 1.x")
            }
            guard let capabilities = manifest?.capabilities else {
                throw ValidationError.invalidPluginManifest("缺少 capabilities；无权限插件请显式使用空数组")
            }
            let knownCapabilities = Set(PluginSDKCatalog.schema.methods.compactMap(\.capability))
            let unknown = Set(capabilities).subtracting(knownCapabilities)
            guard unknown.isEmpty else {
                throw ValidationError.invalidPluginManifest("未知 capabilities：\(unknown.sorted().joined(separator: "、"))")
            }
        }

        let entryPoint = manifest?.entryPoint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let relativeEntryPoint = entryPoint.flatMap { $0.isEmpty ? nil : $0 } ?? "index.html"
        guard !relativeEntryPoint.hasPrefix("/") else {
            throw ValidationError.invalidEntryPoint(relativeEntryPoint)
        }

        let resolvedDirectoryURL = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        let entryURL = directoryURL
            .appendingPathComponent(relativeEntryPoint)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let directoryPrefix = resolvedDirectoryURL.path.hasSuffix("/")
            ? resolvedDirectoryURL.path
            : resolvedDirectoryURL.path + "/"
        guard entryURL.path.hasPrefix(directoryPrefix) else {
            throw ValidationError.invalidEntryPoint(relativeEntryPoint)
        }

        let entryValues = try? entryURL.resourceValues(forKeys: [.isRegularFileKey])
        guard entryValues?.isRegularFile == true else {
            throw ValidationError.missingEntryPoint(relativeEntryPoint)
        }

        let manifestName = manifest?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = manifestName.flatMap { $0.isEmpty ? nil : $0 } ?? directoryURL.lastPathComponent
        let icon = manifest?.icon?.trimmingCharacters(in: .whitespacesAndNewlines)

        return Candidate(
            directoryURL: directoryURL,
            name: name,
            entryPointRelativePath: relativeEntryPoint,
            iconName: icon.flatMap { $0.isEmpty ? nil : $0 },
            allowsNetworkAccess: manifest?.allowsNetworkAccess ?? false
        )
    }

    private func scheduleScan(delay: TimeInterval = 0.8) {
        scheduledScan?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.performManagedRootScan(reportIncompleteDirectories: false)
            }
        }
        scheduledScan = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func restartAfterRootReplacement() {
        rootSource?.cancel()
        rootSource = nil
        pendingDirectorySources.values.forEach { $0.cancel() }
        pendingDirectorySources.removeAll()
        scheduledScan?.cancel()
        scheduledScan = nil
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            Task { @MainActor [weak self] in
                self?.start()
            }
        }
    }

    private func performManagedRootScan(reportIncompleteDirectories: Bool) {
        isScanning = true
        defer { isScanning = false }

        let registeredPaths = Set(registeredAreasProvider().map {
            Self.canonicalPath(for: $0.directoryURL)
        }).union(importedPaths)
        var importedNames: [String] = []
        var issues: [ScanIssue] = []
        var foundIncompleteDirectory = false
        var pendingDirectoryPaths = Set<String>()

        do {
            let children = try fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            for child in children {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                let path = Self.canonicalPath(for: child)
                guard !registeredPaths.contains(path) else { continue }
                pendingDirectoryPaths.insert(path)
                observePendingDirectory(child, canonicalPath: path)

                do {
                    let candidate = try candidate(for: child)
                    importCandidate(candidate)
                    importedNames.append(candidate.name)
                    pendingDirectoryPaths.remove(path)
                } catch ValidationError.missingEntryPoint(let path) {
                    // A generator commonly creates the directory first. Leave incomplete output
                    // eligible for the next filesystem event without showing a noisy auto-import error.
                    foundIncompleteDirectory = true
                    if reportIncompleteDirectories {
                        issues.append(ScanIssue(
                            directoryName: child.lastPathComponent,
                            message: ValidationError.missingEntryPoint(path).localizedDescription
                        ))
                    }
                } catch {
                    issues.append(ScanIssue(directoryName: child.lastPathComponent, message: error.localizedDescription))
                }
            }
        } catch {
            issues.append(ScanIssue(directoryName: rootURL.lastPathComponent, message: error.localizedDescription))
        }

        let result = ScanResult(importedNames: importedNames, issues: issues)
        lastResult = result
        removeStalePendingDirectoryObservers(keeping: pendingDirectoryPaths)
        if foundIncompleteDirectory, !reportIncompleteDirectories, incompleteRetryCount < 5 {
            incompleteRetryCount += 1
            scheduleScan(delay: 1.0)
        } else if !foundIncompleteDirectory {
            incompleteRetryCount = 0
        }
        if !importedNames.isEmpty {
            Self.logger.info("Imported generated panels: \(importedNames.joined(separator: ", "), privacy: .public)")
        }
    }

    private func importCandidate(_ candidate: Candidate) {
        candidateImporter(candidate)
        importedPaths.insert(Self.canonicalPath(for: candidate.directoryURL))
    }

    private func observePendingDirectory(_ directoryURL: URL, canonicalPath: String) {
        guard pendingDirectorySources[canonicalPath] == nil else { return }
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleScan()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        pendingDirectorySources[canonicalPath] = source
    }

    private func removeStalePendingDirectoryObservers(keeping paths: Set<String>) {
        for path in Array(pendingDirectorySources.keys) where !paths.contains(path) {
            pendingDirectorySources[path]?.cancel()
            pendingDirectorySources[path] = nil
        }
    }

    private static func canonicalPath(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
