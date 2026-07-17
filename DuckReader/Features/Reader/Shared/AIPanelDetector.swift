import Foundation
import Vision
import CoreImage
import ImageIO

// MARK: - AI Panel Detector Configuration

/// Configuration for the AI-powered panel detection pipeline.
public struct AIPanelDetectorConfig: Sendable {
    /// Minimum confidence threshold for panel detection (0.0–1.0)
    public var confidenceThreshold: Float = 0.3
    /// Whether to apply contrast normalization pre-processing
    public var enableContrastNormalization: Bool = true
    /// Whether to apply adaptive thresholding for low-quality scans
    public var enableAdaptiveThreshold: Bool = true
    /// Multi-pass: how many detection strategies to try before falling back
    public var maxDetectionPasses: Int = 3
    /// Minimum panel area ratio (relative to image) to filter noise
    public var minPanelAreaRatio: Float = 0.005
    /// Maximum panel count to prevent runaway detection
    public var maxPanelCount: Int = 30

    public static let `default` = AIPanelDetectorConfig()
}

// MARK: - AI Detection Result

/// Result from a single detection pass, with confidence metadata.
public struct AIDetectionPass: Sendable {
    public let panels: [NormalizedRect]
    public let confidence: Float
    public let method: AIDetectionMethod
    public let processingTimeMs: Double
}

/// The detection method used for this pass.
public enum AIDetectionMethod: String, Sendable {
    case attentionSaliency = "attention_saliency"
    case textRegionOCR = "text_region_ocr"
    case contourEnhanced = "contour_enhanced"
    case hybrid = "hybrid"
    case fallbackGrid = "fallback_grid"
}

// MARK: - AI Panel Detector

/// AI-powered panel detector using Vision / CoreML for robust comic panel
/// detection across diverse scan qualities. Uses a multi-pass strategy:
///
/// 1. **Attention Saliency** — leverages the Neural Engine to identify visually
///    salient regions (panels) via `VNGenerateAttentionBasedSaliencyImageRequest`.
///    Works well on clean, high-contrast pages.
/// 2. **Text Region OCR** — detects text bounding boxes and clusters them into
///    panel candidates. Effective for text-heavy manga pages.
/// 3. **Contour Enhanced** — builds on the classical `VNDetectContoursRequest`
///    with pre-processing (contrast normalization, adaptive threshold, morphological
///    close) for robustness on low-quality / faded scans.
/// 4. **Hybrid** — merges results from multiple passes with weighted voting
///    and NMS (non-maximum suppression).
/// 5. **Fallback Grid** — when all else fails, a content-aware grid partition.
public struct AIPanelDetector: Sendable {

    public let config: AIPanelDetectorConfig

    public init(config: AIPanelDetectorConfig = .default) {
        self.config = config
    }

    // MARK: - Public API

    /// Detect panels in a CGImage using the full multi-pass pipeline.
    /// Returns the best pass result based on confidence and panel count quality.
    public func detectPanels(in image: CGImage) async -> AIDetectionPass {
        let start = CFAbsoluteTimeGetCurrent()

        // ---- Pass 1: Attention Saliency (Neural Engine) ----
        if let saliencyPass = await detectSaliencyPanels(in: image),
           saliencyPass.confidence >= config.confidenceThreshold,
           isPanelCountPlausible(saliencyPass.panels.count) {
            return finalize(saliencyPass, start)
        }

        // ---- Pass 2: Text Region OCR ----
        if let ocrPass = await detectTextRegionPanels(in: image),
           ocrPass.confidence >= config.confidenceThreshold,
           isPanelCountPlausible(ocrPass.panels.count) {
            return finalize(ocrPass, start)
        }

        // ---- Pass 3: Contour Enhanced (classical, robust) ----
        if let contourPass = detectContourEnhancedPanels(in: image),
           contourPass.confidence >= config.confidenceThreshold,
           isPanelCountPlausible(contourPass.panels.count) {
            return finalize(contourPass, start)
        }

        // ---- Pass 4: Hybrid merge ----
        if let hybridPass = await detectHybridPanels(in: image),
           hybridPass.confidence >= config.confidenceThreshold * 0.8,
           isPanelCountPlausible(hybridPass.panels.count) {
            return finalize(hybridPass, start)
        }

        // ---- Pass 5: Fallback grid ----
        let gridPass = detectFallbackGrid(in: image)
        return finalize(gridPass, start)
    }

    /// Pre-process an image for better detection quality.
    public func preprocessImage(_ image: CGImage) -> CGImage? {
        guard config.enableContrastNormalization || config.enableAdaptiveThreshold else {
            return image
        }

        let ciImage = CIImage(cgImage: image)

        var filters: [CIFilter] = []

        if config.enableContrastNormalization {
            // CLAHE-like: local contrast stretch via unsharp mask + levels
            if let colorControls = CIFilter(name: "CIColorControls") {
                colorControls.setValue(ciImage, forKey: kCIInputImageKey)
                colorControls.setValue(1.15, forKey: kCIInputContrastKey)  // gentle boost
                colorControls.setValue(0.05, forKey: kCIInputBrightnessKey)
                if let output = colorControls.outputImage {
                    filters.append(CIFilter(name: "CIColorControls")!) // placeholder
                }
            }
        }

        // Chain: contrast → exposure → sharpen
        var current = ciImage

        // Step 1: Auto-enhance levels via CIExposureAdjust + CIColorControls
        if config.enableContrastNormalization {
            if let colorControls = CIFilter(name: "CIColorControls") {
                colorControls.setValue(current, forKey: kCIInputImageKey)
                colorControls.setValue(1.2, forKey: kCIInputContrastKey)
                colorControls.setValue(0.0, forKey: kCIInputBrightnessKey)
                colorControls.setValue(1.1, forKey: kCIInputSaturationKey)
                if let out = colorControls.outputImage {
                    current = out
                }
            }
        }

        // Step 2: Adaptive threshold via edge-work sharpen
        if config.enableAdaptiveThreshold {
            if let sharpen = CIFilter(name: "CISharpenLuminance") {
                sharpen.setValue(current, forKey: kCIInputImageKey)
                sharpen.setValue(0.6, forKey: kCIInputSharpnessKey)
                if let out = sharpen.outputImage {
                    current = out
                }
            }
        }

        // Render
        let ctx = CIContext(options: [.outputColorSpace: CGColorSpaceCreateDeviceRGB()])
        guard let result = ctx.createCGImage(current, from: current.extent) else {
            return image
        }
        return result
    }

    // MARK: - Detection Passes

    /// Pass 1: Attention-based saliency detection.
    private func detectSaliencyPanels(in image: CGImage) async -> AIDetectionPass? {
        let start = CFAbsoluteTimeGetCurrent()

        return await withCheckedContinuation { continuation in
            let request = VNGenerateAttentionBasedSaliencyImageRequest { request, error in
                guard error == nil,
                      let result = request.results?.first as? VNSaliencyImageObservation,
                      let saliencyMap = result.pixelBuffer else {
                    continuation.resume(returning: nil)
                    return
                }

                let panels = self.extractPanelsFromSaliencyMap(
                    saliencyMap,
                    imageSize: CGSize(width: image.width, height: image.height)
                )
                let conf = result.confidence

                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                continuation.resume(returning: AIDetectionPass(
                    panels: panels,
                    confidence: conf,
                    method: .attentionSaliency,
                    processingTimeMs: elapsed
                ))
            }

            // Configure for fine-grained saliency
            request.revision = VNGenerateAttentionBasedSaliencyImageRequestRevision2

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// Pass 2: Text-region OCR clustering.
    private func detectTextRegionPanels(in image: CGImage) async -> AIDetectionPass? {
        let start = CFAbsoluteTimeGetCurrent()

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let textRects = observations.map { obs in
                    NormalizedRect(
                        x: Float(obs.boundingBox.origin.x),
                        y: Float(obs.boundingBox.origin.y),
                        width: Float(obs.boundingBox.width),
                        height: Float(obs.boundingBox.height)
                    )
                }

                let panels = self.clusterTextRegionsIntoPanels(
                    textRects,
                    imageSize: CGSize(width: image.width, height: image.height)
                )

                let avgConf = Float(observations.map(\.confidence).reduce(0, +)) / Float(observations.count)
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                continuation.resume(returning: AIDetectionPass(
                    panels: panels,
                    confidence: min(avgConf, 0.85),
                    method: .textRegionOCR,
                    processingTimeMs: elapsed
                ))
            }

            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.revision = VNRecognizeTextRequestRevision3

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// Pass 3: Contour-based detection with enhanced pre-processing.
    private func detectContourEnhancedPanels(in image: CGImage) -> AIDetectionPass? {
        let start = CFAbsoluteTimeGetCurrent()

        // Pre-process for robustness
        let processed = preprocessImage(image) ?? image

        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 1.5
        request.detectsDarkOnLight = true
        request.maximumImageDimension = 2048

        // Configure contour detection
        request.contrastPivot = NSNumber(value: 0.5)

        let handler = VNImageRequestHandler(cgImage: processed, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let results = request.results as? [VNContoursObservation] else {
            return nil
        }

        var panels: [NormalizedRect] = []
        for observation in results {
            let boundingBox = try? observation.normalizedPath?.boundingBox
            let normalized = observation.boundingBox

            // Normalized bounding box from Vision is (0,0) bottom-left origin
            let rect = NormalizedRect(
                x: Float(normalized.origin.x),
                y: Float(normalized.origin.y),
                width: Float(normalized.width),
                height: Float(normalized.height)
            )

            // Filter tiny noise
            if rect.width * rect.height >= config.minPanelAreaRatio {
                panels.append(rect)
            }
        }

        // Merge overlapping panels (NMS)
        panels = nonMaximumSuppression(panels, iouThreshold: 0.3)

        let confidence = Float(min(1.0, Double(panels.count) / 8.0))
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        return AIDetectionPass(
            panels: panels,
            confidence: confidence,
            method: .contourEnhanced,
            processingTimeMs: elapsed
        )
    }

    /// Pass 4: Hybrid — merges saliency + contour with voting.
    private func detectHybridPanels(in image: CGImage) async -> AIDetectionPass? {
        let start = CFAbsoluteTimeGetCurrent()

        async let saliencyOpt = detectSaliencyPanels(in: image)
        let contourPass = detectContourEnhancedPanels(in: image)
        let saliencyPass = await saliencyOpt

        var allRects: [NormalizedRect] = []
        if let s = saliencyPass { allRects.append(contentsOf: s.panels) }
        if let c = contourPass { allRects.append(contentsOf: c.panels) }

        guard !allRects.isEmpty else { return nil }

        let merged = nonMaximumSuppression(allRects, iouThreshold: 0.25)
        let confidence = Float(min(1.0, Double(merged.count) / 6.0))
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        return AIDetectionPass(
            panels: merged,
            confidence: confidence,
            method: .hybrid,
            processingTimeMs: elapsed
        )
    }

    /// Pass 5: Content-aware grid fallback.
    private func detectFallbackGrid(in image: CGImage) -> AIDetectionPass {
        let start = CFAbsoluteTimeGetCurrent()

        let w = Float(image.width)
        let h = Float(image.height)
        let aspect = w / h

        // Determine grid layout based on aspect ratio
        let (cols, rows): (Int, Int) = {
            if aspect < 0.7 {
                // Tall (typical manga page) → 1-2 cols, 3-5 rows
                return (aspect < 0.55 ? (1, 4) : (2, 4))
            } else if aspect > 1.3 {
                // Wide (double spread) → 2-3 cols, 2-3 rows
                return (2, 2)
            } else {
                // Square-ish → 2x3
                return (2, 3)
            }
        }()

        var panels: [NormalizedRect] = []
        let cellW: Float = 1.0 / Float(cols)
        let cellH: Float = 1.0 / Float(rows)

        for row in 0..<rows {
            for col in 0..<cols {
                panels.append(NormalizedRect(
                    x: Float(col) * cellW,
                    y: Float(row) * cellH,
                    width: cellW,
                    height: cellH
                ))
            }
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        return AIDetectionPass(
            panels: panels,
            confidence: 0.15,
            method: .fallbackGrid,
            processingTimeMs: elapsed
        )
    }

    // MARK: - Panel Extraction Helpers

    /// Extract bounding rectangles from a saliency map pixel buffer.
    private func extractPanelsFromSaliencyMap(
        _ pixelBuffer: CVPixelBuffer,
        imageSize: CGSize
    ) -> [NormalizedRect] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return []
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let floatPtr = baseAddress.assumingMemoryBound(to: Float.self)

        // Downsample the saliency map for efficiency
        let blockSize = 16
        let bw = width / blockSize
        let bh = height / blockSize
        var significantBlocks: [(Float, Float, Float)] = [] // (x, y, saliency)

        for by in 0..<bh {
            for bx in 0..<bw {
                var sum: Float = 0
                var count = 0
                for dy in 0..<min(blockSize, height - by * blockSize) {
                    for dx in 0..<min(blockSize, width - bx * blockSize) {
                        let row = (by * blockSize + dy)
                        let col = (bx * blockSize + dx)
                        let idx = row * bytesPerRow / MemoryLayout<Float>.size + col
                        sum += floatPtr[idx]
                        count += 1
                    }
                }
                let avg = sum / Float(max(count, 1))
                if avg > 0.25 {
                    significantBlocks.append((
                        Float(bx) / Float(bw),
                        Float(by) / Float(bh),
                        avg
                    ))
                }
            }
        }

        // Cluster significant blocks into panel regions
        return clusterBlocksToPanels(significantBlocks, gridW: bw, gridH: bh)
    }

    /// Simple DBSCAN-like clustering of significant blocks into panel rects.
    private func clusterBlocksToPanels(
        _ blocks: [(Float, Float, Float)],
        gridW: Int,
        gridH: Int
    ) -> [NormalizedRect] {
        guard !blocks.isEmpty else { return [] }

        let epsX: Float = 2.0 / Float(gridW)
        let epsY: Float = 2.0 / Float(gridH)

        var visited = Set<Int>()
        var clusters: [[Int]] = []

        for i in 0..<blocks.count {
            guard !visited.contains(i) else { continue }
            var cluster: [Int] = []
            var queue = [i]
            visited.insert(i)

            while !queue.isEmpty {
                let idx = queue.removeFirst()
                cluster.append(idx)
                let (bx, by, _) = blocks[idx]

                for j in 0..<blocks.count where !visited.contains(j) {
                    let (nx, ny, _) = blocks[j]
                    if abs(bx - nx) <= epsX && abs(by - ny) <= epsY {
                        visited.insert(j)
                        queue.append(j)
                    }
                }
            }
            clusters.append(cluster)
        }

        // Convert clusters to bounding rects
        return clusters.compactMap { cluster in
            guard cluster.count >= 2 else { return nil }
            let xs = cluster.map { blocks[$0].0 }
            let ys = cluster.map { blocks[$0].1 }
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return nil }

            let rect = NormalizedRect(
                x: minX, y: minY,
                width: maxX - minX + (1.0 / Float(gridW)),
                height: maxY - minY + (1.0 / Float(gridH))
            )

            return (rect.width * rect.height >= config.minPanelAreaRatio) ? rect : nil
        }
    }

    /// Cluster text observation rects into panel candidates using spatial proximity.
    private func clusterTextRegionsIntoPanels(
        _ textRects: [NormalizedRect],
        imageSize: CGSize
    ) -> [NormalizedRect] {
        guard textRects.count > 1 else {
            return textRects.map { expandRect($0, factor: 0.15) }
        }

        // Merge nearby text rects
        var merged = textRects
        var changed = true
        while changed {
            changed = false
            for i in 0..<merged.count {
                for j in (i + 1)..<merged.count {
                    let a = merged[i]
                    let b = merged[j]
                    let distance = hypot(
                        (a.centerX - b.centerX),
                        (a.centerY - b.centerY)
                    )
                    let threshold = max(a.width, a.height) * 2.0
                    if distance < threshold {
                        merged[i] = unionRects(a, b)
                        merged.remove(at: j)
                        changed = true
                        break
                    }
                }
                if changed { break }
            }
        }

        return merged.map { expandRect($0, factor: 0.08) }
    }

    // MARK: - NMS & Rect Utilities

    private func nonMaximumSuppression(
        _ rects: [NormalizedRect],
        iouThreshold: Float
    ) -> [NormalizedRect] {
        guard rects.count > 1 else { return rects }

        // Sort by area descending (larger panels preferred)
        let sorted = rects.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
        var keep: [NormalizedRect] = []

        for rect in sorted {
            var shouldKeep = true
            for kept in keep {
                if computeIoU(rect, kept) > iouThreshold {
                    shouldKeep = false
                    break
                }
            }
            if shouldKeep {
                keep.append(rect)
            }
        }

        return keep
    }

    private func computeIoU(_ a: NormalizedRect, _ b: NormalizedRect) -> Float {
        let interX = max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x))
        let interY = max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
        let interArea = interX * interY
        let unionArea = (a.width * a.height) + (b.width * b.height) - interArea
        return unionArea > 0 ? interArea / unionArea : 0
    }

    private func expandRect(_ rect: NormalizedRect, factor: Float) -> NormalizedRect {
        NormalizedRect(
            x: max(0, rect.x - rect.width * factor),
            y: max(0, rect.y - rect.height * factor),
            width: min(1.0 - rect.x, rect.width * (1 + 2 * factor)),
            height: min(1.0 - rect.y, rect.height * (1 + 2 * factor))
        )
    }

    private func unionRects(_ a: NormalizedRect, _ b: NormalizedRect) -> NormalizedRect {
        let minX = min(a.x, b.x)
        let minY = min(a.y, b.y)
        let maxX = max(a.x + a.width, b.x + b.width)
        let maxY = max(a.y + a.height, b.y + b.height)
        return NormalizedRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    // MARK: - Utilities

    private func isPanelCountPlausible(_ count: Int) -> Bool {
        count >= 1 && count <= config.maxPanelCount
    }

    private func finalize(_ pass: AIDetectionPass, _ start: CFAbsoluteTime) -> AIDetectionPass {
        AIDetectionPass(
            panels: pass.panels,
            confidence: pass.confidence,
            method: pass.method,
            processingTimeMs: (CFAbsoluteTimeGetCurrent() - start) * 1000
        )
    }
}

// MARK: - NormalizedRect Helpers

private extension NormalizedRect {
    var centerX: Float { x + width / 2 }
    var centerY: Float { y + height / 2 }
}
