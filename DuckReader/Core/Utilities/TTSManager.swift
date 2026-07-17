import Foundation
import AVFoundation

// MARK: - TTS Manager

/// 文本朗读管理器。使用 AVSpeechSynthesizer 提供离线 TTS。
/// 支持中文、日文、英文语音。
@MainActor
public final class TTSManager: NSObject, ObservableObject, Sendable {
    
    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    
    @Published public private(set) var isSpeaking = false
    @Published public private(set) var progress: Double = 0  // 0-1
    @Published public var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    @Published public var pitch: Float = 1.0
    @Published public var volume: Float = 1.0
    
    public override init() {
        super.init()
        synthesizer.delegate = self
        
        // 配置音频会话（允许后台播放）
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }
    
    /// 朗读文本
    public func speak(_ text: String, language: String? = nil) {
        stop()
        
        let utterance = AVSpeechUtterance(string: text)
        
        // 自动检测或使用指定语言
        if let lang = language {
            utterance.voice = AVSpeechSynthesisVoice(language: lang)
        } else {
            // 根据文本内容检测语言
            let detectedLang = detectLanguage(text)
            utterance.voice = AVSpeechSynthesisVoice(language: detectedLang)
        }
        
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.volume = volume
        
        currentUtterance = utterance
        isSpeaking = true
        progress = 0
        
        synthesizer.speak(utterance)
    }
    
    /// 暂停
    public func pause() {
        synthesizer.pauseSpeaking(at: .immediate)
        isSpeaking = false
    }
    
    /// 继续
    public func resume() {
        synthesizer.continueSpeaking()
        isSpeaking = true
    }
    
    /// 停止
    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        progress = 0
    }
    
    /// 跳到下一句
    public func skipForward() {
        synthesizer.stopSpeaking(at: .word)
    }
    
    // MARK: - Private
    
    private func detectLanguage(_ text: String) -> String {
        // 简单检测：如果包含 CJK 字符则返回中文
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF:  // CJK Unified
                return "zh-CN"
            case 0x3040...0x309F:  // Hiragana
                return "ja-JP"
            case 0x30A0...0x30FF:  // Katakana
                return "ja-JP"
            case 0xAC00...0xD7AF:  // Hangul
                return "ko-KR"
            default:
                break
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
            self.isSpeaking = false
            self.progress = 1.0
        }
    }
    
    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let total = utterance.speechString.count
        guard total > 0 else { return }
        let prog = Double(characterRange.location + characterRange.length) / Double(total)
        
        Task { @MainActor in
            self.progress = prog
        }
    }
}
