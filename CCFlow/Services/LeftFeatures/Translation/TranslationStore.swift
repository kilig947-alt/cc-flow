import AppKit
import Combine
import Vision

struct TranslationResult: Identifiable {
    let provider: TranslationProvider
    var id: String { provider.rawValue }
    var text = ""
    var error: String?
    var loading = false
    var expanded = true
}

typealias TranslationOperation = (String, TranslationLanguage, TranslationLanguage, TranslationServiceConfiguration, String) async throws -> String

@MainActor
final class TranslationStore: ObservableObject {
    static let shared = TranslationStore()
    @Published var text = "" { didSet { if text != oldValue { invalidateResults() } } }
    @Published var source: TranslationLanguage = .auto { didSet { if source != oldValue { invalidateResults() } } }
    /// Auto target uses English for Chinese input and Chinese otherwise.
    @Published var target: TranslationLanguage = .auto { didSet { if target != oldValue { invalidateResults() } } }
    @Published private(set) var configurations: [TranslationServiceConfiguration]
    @Published private(set) var results: [TranslationResult] = []
    @Published private(set) var imageTranslation: String?
    @Published var notice: String?
    @Published private(set) var recognizing = false
    @Published private(set) var readingInput = false
    @Published var focusGeneration = UUID()
    @Published var showingServices = false
    private var translationTasks: [TranslationProvider: Task<Void, Never>] = [:]
    private var requestTokens: [TranslationProvider: UUID] = [:]
    private var context: (text: String, source: TranslationLanguage, target: TranslationLanguage)?
    private let translateText: TranslationOperation
    private let readInput: (pid_t?) async -> TranslationInput
    private var inputTask: Task<Void, Never>?
    private var generation = UUID()
    private var inputGeneration = UUID()
    private var captureProcess: Process?
    @Published var copyFormats: Set<TranslationCopyFormat> = [] {
        didSet { defaults.set(copyFormats.map(\.rawValue).sorted(), forKey: "tflow.translation.copyFormats") }
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, translation: TranslationOperation? = nil,
         input: ((pid_t?) async -> TranslationInput)? = nil) {
        self.defaults = defaults
        readInput = input ?? { await TranslationInputReader.shared.read(selectionFrom: $0) }
        translateText = translation ?? { text, source, target, configuration, secret in
            try await TranslationClient().translate(text, source: source, target: target, configuration: configuration, secret: secret)
        }
        let stored = defaults.data(forKey: "tflow.translation.services")
            .flatMap { try? JSONDecoder().decode([TranslationServiceConfiguration].self, from: $0) } ?? []
        configurations = TranslationServiceConfiguration.mergingPresets(into: stored)
        copyFormats = Set((defaults.stringArray(forKey: "tflow.translation.copyFormats") ?? []).compactMap(TranslationCopyFormat.init(rawValue:)))
    }

    func save(_ configuration: TranslationServiceConfiguration, secret: String) throws {
        if configuration.provider.usesChatAPI {
            _ = try TranslationClient.aiURL(base: configuration.baseURL, path: configuration.apiPath)
        }
        try TranslationKeychain.write(secret.trimmingCharacters(in: .whitespacesAndNewlines), provider: configuration.provider)
        guard let index = configurations.firstIndex(where: { $0.provider == configuration.provider }) else { return }
        configurations[index] = configuration
        defaults.set(try JSONEncoder().encode(configurations), forKey: "tflow.translation.services")
        invalidateResults()
    }

    func setServiceEnabled(_ provider: TranslationProvider, enabled: Bool) {
        guard let index = configurations.firstIndex(where: { $0.provider == provider }) else { return }
        configurations[index].enabled = enabled
        if let data = try? JSONEncoder().encode(configurations) {
            defaults.set(data, forKey: "tflow.translation.services")
        }
        invalidateResults()
    }

    func translate() {
        invalidateResults()
        notice = nil
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { notice = AppLocalization.runtimeString("输入文字，或使用选词 / 截图翻译"); return }
        guard input.count <= 20_000 else { notice = AppLocalization.runtimeString("原文过长，请分段翻译（每段最多 20,000 字符）"); return }
        let services = configurations.filter(\.enabled)
        guard !services.isEmpty else { notice = AppLocalization.runtimeString("请在服务设置中启用至少一个翻译服务"); return }
        let source = self.source
        let target = self.target == .auto
            ? ((source == .auto ? TranslationClient.detectedLanguage(input) : source) == .zh ? TranslationLanguage.en : .zh)
            : self.target
        guard source != target else { notice = "源语言与目标语言相同，请调整语言"; return }
        context = (input, source, target)
        results = services.map { TranslationResult(provider: $0.provider, expanded: $0.expandsByDefault) }
        for service in services where service.expandsByDefault { startTranslation(service.provider) }
    }

    func setDefaultExpanded(_ provider: TranslationProvider, expanded: Bool) {
        guard let index = configurations.firstIndex(where: { $0.provider == provider }) else { return }
        configurations[index].expandedByDefault = expanded
        if let data = try? JSONEncoder().encode(configurations) {
            defaults.set(data, forKey: "tflow.translation.services")
        }
        setResultExpanded(provider, expanded: expanded)
    }

    func setResultExpanded(_ provider: TranslationProvider, expanded: Bool) {
        guard let index = results.firstIndex(where: { $0.provider == provider }) else { return }
        results[index].expanded = expanded
        if expanded {
            if results[index].text.isEmpty && !results[index].loading { startTranslation(provider) }
        } else {
            translationTasks.removeValue(forKey: provider)?.cancel()
            requestTokens.removeValue(forKey: provider)
            results[index].loading = false
        }
    }

    private func startTranslation(_ provider: TranslationProvider) {
        guard let context,
              let configuration = configurations.first(where: { $0.provider == provider && $0.enabled }),
              let index = results.firstIndex(where: { $0.provider == provider }),
              results[index].expanded, !results[index].loading else { return }
        let requestGeneration = generation
        let token = UUID()
        requestTokens[provider] = token
        results[index].loading = true
        results[index].error = nil
        translationTasks[provider] = Task {
            guard !Task.isCancelled, generation == requestGeneration, requestTokens[provider] == token else { return }
            let value: String?
            let errorMessage: String?
            do {
                let secret = provider == .myMemory ? "" : TranslationKeychain.read(provider)
                value = try await translateText(context.text, context.source, context.target, configuration, secret)
                errorMessage = nil
            } catch {
                value = nil
                errorMessage = error.localizedDescription
            }
            guard !Task.isCancelled, generation == requestGeneration, requestTokens[provider] == token,
                  let resultIndex = results.firstIndex(where: { $0.provider == provider }) else { return }
            results[resultIndex].text = value ?? ""
            results[resultIndex].error = errorMessage
            results[resultIndex].loading = false
            translationTasks.removeValue(forKey: provider)
            requestTokens.removeValue(forKey: provider)
        }
    }

    func inputTranslation() {
        cancelInput()
        text = ""
        notice = nil
        presentInIsland()
    }

    func selectionTranslation() {
        // Capture the source before presentation; the non-activating Island can
        // animate while AX / Command-C still address the original application.
        startReadingInput(from: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    func clipboardTranslation() {
        startReadingInput(from: nil)
    }

    private func startReadingInput(from pid: pid_t?) {
        cancelInput()
        text = ""
        notice = nil
        readingInput = true
        presentInIsland(focusInput: false)
        let token = inputGeneration
        inputTask = Task {
            let input = await readInput(pid)
            guard !Task.isCancelled, token == inputGeneration else { return }
            readingInput = false
            switch input {
            case .text(let value): receive(value, focusOnly: true)
            case .image(let data): recognize(data, focusOnly: true)
            case .empty:
                presentInIsland(focusOnly: true)
                notice = AppLocalization.runtimeString("未获取到选词，剪贴板也没有文字或图片")
            case .permissionRequired:
                presentInIsland(focusOnly: true)
                notice = AppLocalization.runtimeString("无法读取选词：请开启辅助功能权限后返回原应用重试；也可手动复制后点击右上角剪贴板按钮。")
                requestAccessibility()
            case .cancelled: break
            }
        }
    }

    func screenshotTranslation() {
        cancelInput()
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            presentInIsland()
            notice = AppLocalization.runtimeString("请在系统设置 → 隐私与安全性 → 屏幕录制中授权，然后重试截图翻译")
            return
        }
        NotificationCenter.default.post(name: .ccFlowCollapseIsland, object: nil)
        let token = inputGeneration
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tflow-\(UUID().uuidString).png")
        inputTask = Task {
            defer { try? FileManager.default.removeItem(at: file) }
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let status = try await capture(to: file)
                guard !Task.isCancelled, inputGeneration == token else { return }
                captureProcess = nil
                // Escape is a normal cancellation, not an error and never reads stale clipboard data.
                guard status == 0, FileManager.default.fileExists(atPath: file.path) else { return }
                let data = try Data(contentsOf: file)
                recognize(data)
            } catch {
                guard !Task.isCancelled, inputGeneration == token else { return }
                presentInIsland()
                notice = AppLocalization.runtimeFormat("截图失败：%@", String(describing: error.localizedDescription))
            }
        }
    }

    private func capture(to file: URL) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-t", "png", file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        captureProcess = process
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    private func recognize(_ data: Data, focusOnly: Bool = false) {
        let token = inputGeneration
        recognizing = true
        text = ""
        let ocrSettings = TranslationOCRSettings.shared
        let configuration = ocrSettings.configuration(ocrSettings.selected)
        let requestedTarget = target
        notice = AppLocalization.runtimeFormat("正在使用 %@…", AppLocalization.runtimeString(configuration.provider.title))
        presentInIsland(focusOnly: focusOnly)
        inputTask = Task {
            do {
                let output = try await TranslationOCRClient().recognize(data, configuration: configuration,
                    secret: configuration.provider == .system ? "" : TranslationKeychain.read(account: configuration.provider.account), target: requestedTarget)
                guard !Task.isCancelled, inputGeneration == token else { return }
                recognizing = false
                if output.text.isEmpty { notice = AppLocalization.runtimeString("图片中未识别到文字，请重新框选清晰区域") }
                else if let translation = output.translation, !translation.isEmpty {
                    text = output.text
                    imageTranslation = translation
                    notice = AppLocalization.runtimeString("腾讯图片翻译已完成；点击翻译可对比已启用的文本服务。")
                } else { receive(output.text, focusOnly: true) }
            } catch {
                guard !Task.isCancelled, inputGeneration == token else { return }
                recognizing = false
                notice = AppLocalization.runtimeFormat("文字识别失败：%@", String(describing: error.localizedDescription))
            }
        }
    }

    func openServiceSettings() {
        presentInIsland(showServices: true)
    }

    private func presentInIsland(showServices: Bool = false, focusInput: Bool = true, focusOnly: Bool = false) {
        if !focusOnly { showingServices = showServices }
        if !showServices && focusInput { focusGeneration = UUID() }
        NotificationCenter.default.post(
            name: .ccFlowOpenLeftFeatureShortcut,
            object: nil,
            userInfo: ["featureID": LeftFeature.translationID, "focusInput": focusInput, "focusOnly": focusOnly]
        )
    }

    private func receive(_ value: String, focusOnly: Bool = false) {
        text = value
        presentInIsland(focusOnly: focusOnly)
        translate()
    }

    private func cancelInput() {
        inputGeneration = UUID()
        inputTask?.cancel()
        if captureProcess?.isRunning == true { captureProcess?.terminate() }
        captureProcess = nil
        recognizing = false
        readingInput = false
        invalidateResults()
    }

    private func invalidateResults() {
        imageTranslation = nil
        generation = UUID()
        for task in translationTasks.values { task.cancel() }
        translationTasks.removeAll()
        requestTokens.removeAll()
        context = nil
        results = []
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }

}
