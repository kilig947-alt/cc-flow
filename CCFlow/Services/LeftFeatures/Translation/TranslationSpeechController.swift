import AVFoundation
import Combine
import Foundation

@MainActor
final class TranslationSpeechController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = TranslationSpeechController()
    @Published private(set) var activeID: String?
    @Published private(set) var isPlaying = false
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "tflow.speech.enabled")
            if !enabled { stop() }
        }
    }
    @Published var voiceID: String {
        didSet { UserDefaults.standard.set(voiceID, forKey: "tflow.speech.voiceID") }
    }
    @Published var rate: Double {
        didSet { UserDefaults.standard.set(rate, forKey: "tflow.speech.rate") }
    }
    let voices = AVSpeechSynthesisVoice.speechVoices().sorted { ($0.language, $0.name) < ($1.language, $1.name) }
    private let synthesizer = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?

    private override init() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: "tflow.speech.enabled") as? Bool ?? true
        voiceID = defaults.string(forKey: "tflow.speech.voiceID") ?? ""
        rate = min(0.65, max(0.3, defaults.object(forKey: "tflow.speech.rate") as? Double ?? 0.5))
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ text: String, id: String) {
        guard enabled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if activeID == id { stop(); return }
        stop()
        let value = AVSpeechUtterance(string: text)
        let language = TranslationClient.detectedLanguage(text)
        value.voice = AVSpeechSynthesisVoice(identifier: voiceID)
            ?? AVSpeechSynthesisVoice(language: language == .zh ? "zh-CN" : language.rawValue)
        value.rate = Float(rate)
        utterance = value
        activeID = id
        synthesizer.speak(value)
    }

    func stop() {
        utterance = nil
        activeID = nil
        isPlaying = false
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utterance.map(ObjectIdentifier.init) == identity else { return }
            self.isPlaying = true
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish(utterance)
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish(utterance)
    }
    nonisolated private func finish(_ utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.utterance.map(ObjectIdentifier.init) == identity else { return }
            self.utterance = nil
            self.activeID = nil
            self.isPlaying = false
        }
    }
}
