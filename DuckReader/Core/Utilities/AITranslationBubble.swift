import Foundation
import Vision
import Translation
import UIKit

// MARK: - AI 翻译气泡引擎
/// 轻量级漫画对话翻译 —— Vision OCR + Translation 框架，零外部依赖
/// 仅在用户触发时运行，单页处理 <1s (iPhone 13+)，电量影响微乎其微
@MainActor
final class AITranslationBubble: ObservableObject {

    // MARK: - Configuration
    struct Config {
        /// 支持的翻译语言对
        var sourceLanguage: Locale.Language = .japanese
        var targetLanguage: Locale.Language = .chineseSimplified
        /// OCR 最小置信度阈值
        var minimumOCRConfidence: Float = 0.5
        /// 是否仅 WiFi 下载离线模型
        var wifiOnlyModelDownload: Bool = true
        /// 翻译结果在气泡内的最大字号
        var maxFontSize: CGFloat = 14
        /// 翻译结果在气泡内的最小字号
        var minFontSize: CGFloat = 10
        /// 翻译叠加层的透明度
        var overlayAlpha: CGFloat = 0.92
    }

    // MARK: - State
    @Published var isTranslating: Bool = false
    @Published var translatedBubbles: [TranslatedBubble] = []
    @Published var isModelReady: Bool = false
    @Published var errorMessage: String?

    var config: Config = Config()
    private let ocrQueue = DispatchQueue(label: "ai.translation.ocr", qos: .userInitiated)

    /// 面板检测器引用（复用已有面板数据辅助气泡定位）
    weak var panelDetector: AIPanelDetector?

    // MARK: - Types
    struct TranslatedBubble: Identifiable, Sendable {
        let id: UUID
        let boundingBox: CGRect          // 归一化坐标 0...1
        let originalText: String
        let translatedText: String
        let confidence: Float
    }

    enum TranslationError: LocalizedError {
        case ocrFailed
        case translationTimeout
        case modelNotAvailable(Locale.Language)
        case emptyRegion

        var errorDescription: String? {
            switch self {
            case .ocrFailed: "OCR 识别失败，请重试"
            case .translationTimeout: "翻译超时，请检查网络或下载离线模型"
            case .modelNotAvailable(let lang): "\(lang) 的离线模型不可用，请连接 WiFi 下载"
            case .emptyRegion: "未检测到文字区域"
            }
        }
    }

    // MARK: - Public API

    /// 翻译整页所有检测到的气泡
    func translatePage(_ cgImage: CGImage, panels: [PanelRegion]) async throws {
        isTranslating = true
        errorMessage = nil
        translatedBubbles = []

        defer { isTranslating = false }

        // Step 1: 用 Vision 做 OCR 扫描全页
        let ocrResults = try await runOCR(on: cgImage)

        guard !ocrResults.isEmpty else {
            throw TranslationError.emptyRegion
        }

        // Step 2: 将 OCR 结果与面板/气泡区域匹配
        let bubbles = matchOCRToBubbles(ocrResults, panels: panels)

        // Step 3: 批量翻译
        let translated = try await translateBatch(bubbles)

        translatedBubbles = translated
    }

    /// 翻译指定区域（用户点击单个气泡）
    func translateRegion(_ cgImage: CGImage, region: CGRect) async throws -> TranslatedBubble? {
        isTranslating = true
        errorMessage = nil
        defer { isTranslating = false }

        // 裁剪到指定区域做 OCR
        guard let cropped = cgImage.cropping(to: region) else {
            throw TranslationError.ocrFailed
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = recognitionLanguages(for: config.sourceLanguage)
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.01

        let handler = VNImageRequestHandler(cgImage: cropped, options: [:])
        try handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else {
            return nil
        }

        let fullText = observations
            .compactMap { $0.topCandidates(1).first }
            .filter { $0.confidence > config.minimumOCRConfidence }
            .map { $0.string }
            .joined(separator: " ")

        guard !fullText.isEmpty else { return nil }

        let translated = try await translate(text: fullText)

        return TranslatedBubble(
            id: UUID(),
            boundingBox: region,
            originalText: fullText,
            translatedText: translated,
            confidence: observations.first?.topCandidates(1).first?.confidence ?? 0
        )
    }

    /// 检查 & 预热翻译模型
    func prepareModels() async {
        let availability = LanguageAvailability()
        let status = await availability.status(from: config.sourceLanguage, to: config.targetLanguage)

        switch status {
        case .installed:
            isModelReady = true
        case .supported:
            // 尝试下载
            do {
                try await availability.download(.translation, from: config.sourceLanguage, to: config.targetLanguage)
                isModelReady = true
            } catch {
                errorMessage = "翻译模型下载失败: \(error.localizedDescription)"
                isModelReady = false
            }
        case .unsupported:
            errorMessage = "不支持的语言对"
            isModelReady = false
        @unknown default:
            isModelReady = false
        }
    }
}

// MARK: - Private Implementation

private extension AITranslationBubble {

    /// 全页 OCR
    func runOCR(on cgImage: CGImage) async throws -> [VNRecognizedTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let results = (request.results as? [VNRecognizedTextObservation]) ?? []
                continuation.resume(returning: results)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = recognitionLanguages(for: config.sourceLanguage)
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.008

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 将 OCR 结果匹配到气泡区域
    func matchOCRToBubbles(
        _ observations: [VNRecognizedTextObservation],
        panels: [PanelRegion]
    ) -> [(text: String, box: CGRect, confidence: Float)] {
        var bubbles: [(text: String, box: CGRect, confidence: Float)] = []

        for obs in observations {
            guard let candidate = obs.topCandidates(1).first,
                  candidate.confidence > config.minimumOCRConfidence else {
                continue
            }

            let normBox = obs.boundingBox // 已在归一化坐标

            // 检查是否落在已知面板内
            let inPanel = panels.contains { panel in
                normBox.midX >= panel.normalizedRect.minX &&
                normBox.midX <= panel.normalizedRect.maxX &&
                normBox.midY >= panel.normalizedRect.minY &&
                normBox.midY <= panel.normalizedRect.maxY
            }

            if inPanel || panels.isEmpty {
                bubbles.append((candidate.string, normBox, candidate.confidence))
            }
        }

        return bubbles
    }

    /// 批量翻译
    func translateBatch(
        _ bubbles: [(text: String, box: CGRect, confidence: Float)]
    ) async throws -> [TranslatedBubble] {
        guard !bubbles.isEmpty else { return [] }

        var results: [TranslatedBubble] = []

        // 用 TaskGroup 并发翻译
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, bubble) in bubbles.enumerated() {
                group.addTask { [weak self] in
                    guard let self else { return (index, bubble.text) }
                    let translated = try await self.translate(text: bubble.text)
                    return (index, translated)
                }
            }

            var translatedMap = [Int: String]()
            var groupErrors: [Error] = []

            for try await (index, text) in group {
                translatedMap[index] = text
            }

            // 按原顺序排列
            for (index, bubble) in bubbles.enumerated() {
                let translated = translatedMap[index] ?? bubble.text
                results.append(TranslatedBubble(
                    id: UUID(),
                    boundingBox: bubble.box,
                    originalText: bubble.text,
                    translatedText: translated,
                    confidence: bubble.confidence
                ))
            }

            if !groupErrors.isEmpty, results.isEmpty {
                throw TranslationError.translationTimeout
            }
        }

        return results
    }

    /// 单条翻译
    func translate(text: String) async throws -> String {
        let session = TranslationSession(
            sourceLanguage: config.sourceLanguage,
            targetLanguage: config.targetLanguage
        )

        let response = try await session.translate(text)
        return response.targetText
    }

    /// Vision 语言代码映射
    func recognitionLanguages(for language: Locale.Language) -> [String] {
        // Vision 的 recognitionLanguages 使用 ISO 639-1/2
        switch language.languageCode?.identifier {
        case "ja": return ["ja", "en"]
        case "zh": return ["zh-Hans", "zh-Hant"]
        case "ko": return ["ko", "en"]
        case "en": return ["en"]
        default:   return ["ja", "en", "zh-Hans"]
        }
    }
}

// MARK: - 翻译叠加层渲染器
/// 将翻译结果渲染为叠加在漫画页面上的 SwiftUI View Builder
struct TranslationOverlayRenderer {
    /// 生成叠加层 CAShapeLayer（可在 CALayer 上直接合成）
    static func render(
        bubbles: [AITranslationBubble.TranslatedBubble],
        imageSize: CGSize,
        maxFontSize: CGFloat = 14,
        minFontSize: CGFloat = 10
    ) -> [CALayer] {
        bubbles.map { bubble in
            let layer = CALayer()
            let rect = CGRect(
                x: bubble.boundingBox.origin.x * imageSize.width,
                y: (1 - bubble.boundingBox.origin.y - bubble.boundingBox.height) * imageSize.height,
                width: bubble.boundingBox.width * imageSize.width,
                height: bubble.boundingBox.height * imageSize.height
            )

            // 半透明背景
            let bgLayer = CALayer()
            bgLayer.frame = rect.insetBy(dx: -4, dy: -2)
            bgLayer.backgroundColor = UIColor.black.withAlphaComponent(0.75).cgColor
            bgLayer.cornerRadius = 6
            layer.addSublayer(bgLayer)

            // 文字层
            let textLayer = CATextLayer()
            textLayer.string = bubble.translatedText
            textLayer.fontSize = calculateFontSize(
                for: bubble.translatedText,
                in: rect.size,
                max: maxFontSize,
                min: minFontSize
            )
            textLayer.foregroundColor = UIColor.white.cgColor
            textLayer.alignmentMode = .center
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.frame = rect
            textLayer.isWrapped = true
            layer.addSublayer(textLayer)

            return layer
        }
    }
}

private func calculateFontSize(
    for text: String,
    in size: CGSize,
    max: CGFloat,
    min: CGFloat
) -> CGFloat {
    var fontSize = max
    let constraint = CGSize(width: size.width - 8, height: .greatestFiniteMagnitude)

    while fontSize > min {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fontSize)]
        let bounding = (text as NSString).boundingRect(
            with: constraint,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        if bounding.height <= size.height { break }
        fontSize -= 1
    }

    return fontSize
}
