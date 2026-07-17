import Foundation
import AVFoundation

// MARK: - TTS Configuration

/// Voice configuration per language.
public struct TTSVoiceConfig: Equatable, Sendable {
    public var language: String
    public var voiceIdentifier: String?
    public var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    public var pitch: Float = 1.0
    public var volume: Float = 1.0
    public var preBoundaryDelay: TimeInterval = 0.0
    public var postBoundaryDelay: TimeInterval = 0.0

    public static func englishEnhanced() -> TTSVoiceConfig {
        var c = TTSVoiceConfig(language: "en-US")
        c.rate = 0.52
        c.pitch = 1.05
        return c
    }

    public static func japaneseEnhanced() -> TTSVoiceConfig {
        var c = TTSVoiceConfig(language: "ja-JP")
        c.rate = 0.48
        c.pitch = 1.0
        c.postBoundaryDelay = 0.15
        return c
    }

    public static func chineseEnhanced() -> TTSVoiceConfig {
        var c = TTSVoiceConfig(language: "zh-CN")
        c.rate = 0.45
        c.pitch = 1.0
        return c
    }
}

// MARK: - TTS Speech Event

/// Real-time speech events for UI highlight sync.
public enum TTSSpeechEvent: Sendable {
    case started
    case willSpeakWord(String, range: NSRange)  // highlight the current word
    case paused
    case resumed
    case finished
    case cancelled
}

// MARK: - Enhanced TTS Manager

/// Enhanced TTS manager with highlight sync, multi-voice, speed presets,
/// and chapter-aware playback.
@MainActor
public final class TTSManager: NSObject, ObservableObject, Sendable {

    private let synthesizer = AVSpeechSynthesizer()

    @Published public private(set) var isSpeaking = false
    @Published public private(set) var isPaused = false
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var currentWordRange: NSRange?
    @Published public private(set) var currentLanguage: String = "en-US"

    /// Speech rate (0.0–1.0 relative to default).
    @Published public var rate: Float = AVSpeechUtteranceDefaultSpeechRate {
        didSet { applyRateChange() }
    }
    @Published public var pitch: Float = 1.0
    @Published public var volume: Float = 1.0

    /// Speed presets
    public static let speedPresets: [(String, Float)] = [
        ("0.5×", 0.35),
        ("0.75×", 0.42),
        ("1.0×", 0.5),
        ("1.25×", 0.55),
        ("1.5×", 0.58),
        ("2.0×", 0.62),
    ]

    /// Per-language voice configurations.
    @Published public var voiceConfigs: [String: TTSVoiceConfig] = [
        "en-US": .englishEnhanced(),
        "ja-JP": .japaneseEnhanced(),
        "zh-CN": .chineseEnhanced(),
        "ko-KR": TTSVoiceConfig(language: "ko-KR"),
    ]

    /// Callback for highlight sync.
    public var onSpeechEvent: ((TTSSpeechEvent) -> Void)?

    /// Chapter-based queue: remaining text split by sentences.
    private var speechQueue: [String] = []
    private var queueIndex: Int = 0
    private var currentUtteranceText: String = ""

    public override init() {
        super.init()
        synthesizer.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    // MARK: - Speak

    /// Speak a text string with auto language detection.
    public func speak(_ text: String, language: String? = nil) {
        stop()

        let detectedLang = language ?? detectLanguage(text)
        currentLanguage = detectedLang

        // Apply voice config
        let config = voiceConfigs[detectedLang] ?? TTSVoiceConfig(language: detectedLang)
        rate = config.rate
        pitch = config.pitch
        volume = config.volume

        currentUtteranceText = text
        speechQueue.removeAll()
        queueIndex = 0

        speakUtterance(text, language: detectedLang)
        onSpeechEvent?(.started)
    }

    /// Speak chapter by chapter (sentence-level queue for better pause control).
    public func speakChapter(_ text: String, language: String? = nil) {
        let detectedLang = language ?? detectLanguage(text)
        currentLanguage = detectedLang

        // Split into sentences for finer control
        speechQueue = splitIntoSentences(text)
        queueIndex = 0

        speakNextInQueue(language: detectedLang)
        onSpeechEvent?(.started)
    }

    // MARK: - Controls

    public func pause() {
        guard isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isSpeaking = false
        isPaused = true
        onSpeechEvent?(.paused)
    }

    public func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
        isSpeaking = true
        isPaused = false
        onSpeechEvent?(.resumed)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        progress = 0
        currentWordRange = nil
        speechQueue.removeAll()
        queueIndex = 0
        onSpeechEvent?(.cancelled)
    }

    /// Skip forward one sentence in chapter mode.
    public func skipForward() {
        if !speechQueue.isEmpty && queueIndex < speechQueue.count - 1 {
            synthesizer.stopSpeaking(at: .immediate)
            // Will automatically play next via delegate
        } else {
            synthesizer.stopSpeaking(at: .word)
        }
    }

    /// Skip backward one sentence.
    public func skipBackward() {
        if queueIndex > 1 {
            synthesizer.stopSpeaking(at: .immediate)
            queueIndex = max(0, queueIndex - 2)
            // Delegate will advance to next
        }
    }

    /// Set speed from preset.
    public func setSpeedPreset(_ preset: (String, Float)) {
        rate = preset.1
    }

    /// Change voice for current language.
    public func setVoice(_ identifier: String, for language: String) {
        voiceConfigs[language, default: TTSVoiceConfig(language: language)].voiceIdentifier = identifier
    }

    /// List available voices for a language.
    public func availableVoices(for language: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
    }

    /// Selected voice for the current language.
    public var currentVoice: AVSpeechSynthesisVoice? {
        if let id = voiceConfigs[currentLanguage]?.voiceIdentifier {
            return AVSpeechSynthesisVoice(identifier: id)
        }
        return AVSpeechSynthesisVoice(language: currentLanguage)
    }

    /// Current word being spoken (for UI highlight).
    public var highlightedRange: NSRange? {
        currentWordRange
    }

    // MARK: - Private

    private func speakUtterance(_ text: String, language: String) {
        let utterance = AVSpeechUtterance(string: text)

        if let voiceID = voiceConfigs[language]?.voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }

        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.volume = volume

        let config = voiceConfigs[language]
        utterance.preUtteranceDelay = config?.preBoundaryDelay ?? 0
        utterance.postUtteranceDelay = config?.postBoundaryDelay ?? 0

        synthesizer.speak(utterance)
        isSpeaking = true
        isPaused = false
    }

    private func speakNextInQueue(language: String) {
        guard queueIndex < speechQueue.count else {
            // Queue exhausted
            isSpeaking = false
            progress = 1.0
            onSpeechEvent?(.finished)
            return
        }

        let sentence = speechQueue[queueIndex]
        queueIndex += 1
        speakUtterance(sentence, language: language)
    }

    private func applyRateChange() {
        guard isSpeaking else { return }
        // AVSpeechSynthesizer doesn't support real-time rate change;
        // restart current utterance at new rate
        let text = currentUtteranceText
        stop()
        speak(text, language: currentLanguage)
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        // Split by sentence-ending punctuation
        let pattern = "(?<=[.!?。！？\n])\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [text]
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        var sentences: [String] = []
        var lastEnd = text.startIndex
        for match in matches {
            let end = Range(match.range, in: text)!.lowerBound
            let sentence = String(text[lastEnd...end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            lastEnd = Range(match.range, in: text)!.upperBound
        }
        let remainder = String(text[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty {
            sentences.append(remainder)
        }
        return sentences.isEmpty ? [text] : sentences
    }

    private func detectLanguage(_ text: String) -> String {
        for scalar in text.unicodeScalars.prefix(100) {
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF: return "zh-CN"
            case 0x3040...0x309F, 0x30A0...0x30FF: return "ja-JP"
            case 0xAC00...0xD7AF: return "ko-KR"
            default: break
            }
        }
        return "en-US"
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSManager: AVSpeechSynthesizerDelegate {
    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            // Advance to next in queue if chapter mode
            if !self.speechQueue.isEmpty {
                self.speakNextInQueue(language: self.currentLanguage)
            } else {
                self.isSpeaking = false
                self.isPaused = false
                self.progress = 1.0
                self.onSpeechEvent?(.finished)
            }
        }
    }

    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let total = utterance.speechString.count
        let prog = total > 0 ? Double(characterRange.location + characterRange.length) / Double(total) : 0

        Task { @MainActor in
            self.progress = prog
            self.currentWordRange = characterRange
            self.onSpeechEvent?(.willSpeakWord(
                (utterance.speechString as NSString).substring(with: characterRange),
                range: characterRange
            ))
        }
    }
}
