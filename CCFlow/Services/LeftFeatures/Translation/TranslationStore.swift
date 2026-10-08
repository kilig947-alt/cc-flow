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
    @Published var text = "" {
        didSet {
            if text != oldValue {
                detectedSourceLanguage = TranslationClient.recognizedLanguage(text)
                invalidateResults()
            }
        }
    }
    @Published private(set) var detectedSourceLanguage: TranslationLanguage?
    var effectiveSourceLanguage: TranslationLanguage? { source == .auto ? detectedSourceLanguage : source }
    var effectiveTargetLanguage: TranslationLanguage {
        target == .auto ? (effectiveSourceLanguage == .zh ? .en : .zh) : target
    }
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
    private let readSecret: (TranslationProvider) -> String
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
         input: ((pid_t?) async -> TranslationInput)? = nil,
         secret: @escaping (TranslationProvider) -> String = { TranslationKeychain.read($0) }) {
        self.defaults = defaults
        readSecret = secret
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
        guard !input.isEmpty else { notice = "translation.enter_text_or_translate_a_selection_screenshot"; return }
        guard input.count <= 20_000 else { notice = "translation.source_text_is_too_long_split_it_into"; return }
        let services = configurations.filter(\.enabled)
        guard !services.isEmpty else { notice = "translation.enable_at_least_one_translation_service_in_settings"; return }
        let source = self.source
        let target = effectiveTargetLanguage
        guard source != target else { notice = "translation.source_and_target_languages_are_the_same_choose"; return }
        context = (input, source, target)
        let missingSecrets = Set(services.filter {
            $0.provider.requiresSecret && readSecret($0.provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.map(\.provider))
        // Stable partition preserves configured order within each group.
        let orderedServices = services.filter { !missingSecrets.contains($0.provider) }
            + services.filter { missingSecrets.contains($0.provider) }
        results = orderedServices.map {
            TranslationResult(provider: $0.provider,
                              expanded: $0.expandsByDefault && !missingSecrets.contains($0.provider))
        }
        for result in results where result.expanded { startTranslation(result.provider) }
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
                let secret = provider == .myMemory ? "" : readSecret(provider)
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
                notice = "translation.no_selected_text_and_the_clipboard_has_no"
            case .permissionRequired:
                presentInIsland(focusOnly: true)
                notice = "translation.cannot_read_selected_text_enable_accessibility_permission_and"
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
            notice = "translation.allow_screen_recording_in_system_settings_privacy_security"
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
                notice = AppLocalization.runtimeFormat("translation.screenshot_failed", String(describing: error.localizedDescription))
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
        notice = AppLocalization.runtimeFormat("translation.using", configuration.provider.title)
        presentInIsland(focusOnly: focusOnly)
        inputTask = Task {
            do {
                let output = try await TranslationOCRClient().recognize(data, configuration: configuration,
                    secret: configuration.provider == .system ? "" : TranslationKeychain.read(account: configuration.provider.account), target: requestedTarget)
                guard !Task.isCancelled, inputGeneration == token else { return }
                recognizing = false
                if output.text.isEmpty { notice = "translation.no_text_recognized_select_a_clearer_region" }
                else if let translation = output.translation, !translation.isEmpty {
                    text = output.text
                    imageTranslation = translation
                    notice = "translation.tencent_image_translation_completed_click_translate_to_compare"
                } else { receive(output.text, focusOnly: true) }
            } catch {
                guard !Task.isCancelled, inputGeneration == token else { return }
                recognizing = false
                notice = AppLocalization.runtimeFormat("translation.text_recognition_failed", String(describing: error.localizedDescription))
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
