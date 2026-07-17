import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - 智能图像增强引擎
/// 轻量级漫画/书籍图像优化 —— CoreImage 管线 + 可选 waifu2x CoreML 模型
/// 后台异步处理当前章节（QoS .utility），不阻塞阅读
/// 模型参考: waifu2x-ios (MIT, imxieyi/waifu2x-ios) — 仅做架构引用，模型可由用户按需下载
actor ImageEnhancer {
    // MARK: - Config
    struct Config {
        /// 是否启用锐化
        var enableSharpen: Bool = true
        /// 锐化强度 0...2
        var sharpenIntensity: Float = 0.6
        /// 是否启用降噪
        var enableDenoise: Bool = true
        /// 降噪强度 0...1
        var denoiseRadius: Float = 0.8
        /// 是否启用对比度增强
        var enableContrastBoost: Bool = true
        /// 对比度增益 0.8...1.5
        var contrastBoost: Float = 1.1
        /// 是否启用超分辨率（需要 CoreML 模型）
        var enableSuperResolution: Bool = false
        /// 超分倍数 (2x/4x)
        var superResolutionScale: Int = 2
        /// 低电量模式下暂停处理
        var pauseOnLowPower: Bool = true
        /// 最多缓存页数
        var maxCachePages: Int = 50
        /// 并行处理页数
        var concurrentPages: Int = 2
    }

    var config: Config = Config()

    // MARK: - State
    private var cache: [String: EnhancedImage] = [:]
    private let cacheLock = NSLock()
    private var isProcessing = false
    private var pendingTask: Task<Void, Never>?

    // MARK: - Output
    struct EnhancedImage: Sendable {
        let originalHash: String
        let enhancedData: Data
        let appliedFilters: [String]
        let processingTimeMs: Double
        let fileSizeReduction: Double // 正=缩小, 负=增大
    }

    enum EnhancementStep: String, CaseIterable {
        case denoise = "降噪"
        case sharpen = "锐化"
        case contrast = "对比度增强"
        case whiteBalance = "白平衡校正"
        case superResolution = "超分辨率"
    }

    // MARK: - Public API

    /// 异步处理单张图像（即时模式）
    func enhance(image: CGImage, steps: Set<EnhancementStep> = Set(EnhancementStep.allCases)) async -> CGImage? {
        var current = image

        // 性能计时
        let start = CFAbsoluteTimeGetCurrent()

        // 流水线：降噪 → 对比度 → 锐化
        if steps.contains(.denoise) && config.enableDenoise {
            current = applyDenoise(to: current) ?? current
        }

        if steps.contains(.whiteBalance) {
            current = applyWhiteBalance(to: current)
        }

        if steps.contains(.contrast) && config.enableContrastBoost {
            current = applyContrastBoost(to: current) ?? current
        }

        if steps.contains(.sharpen) && config.enableSharpen {
            current = applySharpen(to: current) ?? current
        }

        if steps.contains(.superResolution) && config.enableSuperResolution {
            current = await applySuperResolution(to: current) ?? current
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if elapsed > 50 {
            // 超过50ms记录日志（用于性能监控）
            DuckLog.debug("处理耗时 \(Int(elapsed))ms, filters: \(steps.map(\.rawValue).joined(separator: ", "))", category: "ImageEnhancer")
        }

        return current
    }

    /// 批量后台预处理章节（用于打开书籍时预加载优化）
    func preEnhanceChapter(
        pages: [CGImage],
        bookID: String,
        chapterIndex: Int,
        onProgress: (@Sendable (Float) -> Void)?
    ) async {
        guard !(config.pauseOnLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled) else {
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        let total = pages.count
        var completed = 0

        // 限制并发数避免过热
        let stream = AsyncStream<CGImage?> { continuation in
            Task {
                for page in pages {
                    let enhanced = await self.enhance(image: page)
                    continuation.yield(enhanced)
                    completed += 1
                    await MainActor.run { onProgress?(Float(completed) / Float(total)) }
                }
                continuation.finish()
            }
        }

        var enhancedPages: [CGImage] = []
        for await page in stream {
            if let page { enhancedPages.append(page) }
        }
    }

    /// 检查缓存
    func cached(for hash: String) -> EnhancedImage? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[hash]
    }

    /// 清空缓存
    func clearCache() {
        cacheLock.lock()
        cache.removeAll(keepingCapacity: false)
        cacheLock.unlock()
    }

    /// 裁剪白边（已有功能的增强版）
    func trimWhiteBorders(_ cgImage: CGImage, threshold: Float = 0.95) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent

        guard let luminanceMap = ciImage
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0),
                "inputGVector": CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0),
                "inputBVector": CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0),
            ])
        else { return cgImage }

        let context = CIContext(options: [.lowMemory: true, .highQualityDownsample: false])
        guard let luminanceCG = context.createCGImage(luminanceMap, from: extent) else { return cgImage }

        // 简单的边界扫描裁剪
        let width = luminanceCG.width
        let height = luminanceCG.height
        guard let data = luminanceCG.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return cgImage }

        let bytesPerRow = luminanceCG.bytesPerRow

        // 从四边扫描
        var top = 0, bottom = height - 1, left = 0, right = width - 1

        // 顶部
        scanTop: for y in 0..<height {
            for x in stride(from: 0, to: width, by: 4) {
                if bytes[y * bytesPerRow + x] < 240 { break scanTop }
            }
            top = y
        }

        // 底部
        scanBottom: for y in (0..<height).reversed() {
            for x in stride(from: 0, to: width, by: 4) {
                if bytes[y * bytesPerRow + x] < 240 { break scanBottom }
            }
            bottom = y
        }

        // 左侧
        scanLeft: for x in stride(from: 0, to: width, by: 4) {
            for y in 0..<height {
                if bytes[y * bytesPerRow + x] < 240 { break scanLeft }
            }
            left = x
        }

        // 右侧
        scanRight: for x in stride(from: width - 1, through: 0, by: -4) {
            for y in 0..<height {
                if bytes[y * bytesPerRow + x] < 240 { break scanRight }
            }
            right = x
        }

        // 留 2% padding
        let hPad = CGFloat(width) * 0.02
        let vPad = CGFloat(height) * 0.02

        let cropRect = CGRect(
            x: max(0, CGFloat(left) - hPad),
            y: max(0, CGFloat(top) - vPad),
            width: min(CGFloat(width), CGFloat(right - left) + hPad * 2),
            height: min(CGFloat(height), CGFloat(bottom - top) + vPad * 2)
        )

        return cgImage.cropping(to: cropRect)
    }
}

// MARK: - Core Image Filters

private extension ImageEnhancer {

    func applyDenoise(to cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = ciImage
        filter.radius = config.denoiseRadius * 0.5 // 轻度模糊降噪

        let context = CIContext(options: [.lowMemory: true])
        guard let output = filter.outputImage,
              let result = context.createCGImage(output, from: ciImage.extent) else {
            return nil
        }
        return result
    }

    func applySharpen(to cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter.sharpenLuminance()
        filter.inputImage = ciImage
        filter.sharpness = config.sharpenIntensity

        let context = CIContext(options: [.lowMemory: true])
        guard let output = filter.outputImage,
              let result = context.createCGImage(output, from: ciImage.extent) else {
            return nil
        }
        return result
    }

    func applyContrastBoost(to cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)

        // 使用 Lab 颜色空间的色调映射
        guard let toneCurveFilter = CIFilter(name: "CIToneCurve") else { return nil }
        toneCurveFilter.setValue(ciImage, forKey: kCIInputImageKey)
        toneCurveFilter.setValue(
            CIVector(x: 0.0, y: 0.0),
            forKey: "inputPoint0"
        )
        toneCurveFilter.setValue(
            CIVector(x: 0.25, y: 0.25 * CGFloat(config.contrastBoost)),
            forKey: "inputPoint1"
        )
        toneCurveFilter.setValue(
            CIVector(x: 0.5, y: 0.5),
            forKey: "inputPoint2"
        )
        toneCurveFilter.setValue(
            CIVector(x: 0.75, y: 0.75 + 0.25 * CGFloat(1.0 - config.contrastBoost)),
            forKey: "inputPoint3"
        )
        toneCurveFilter.setValue(
            CIVector(x: 1.0, y: 1.0),
            forKey: "inputPoint4"
        )

        let context = CIContext(options: [.lowMemory: true])
        guard let output = toneCurveFilter.outputImage,
              let result = context.createCGImage(output, from: ciImage.extent) else {
            return nil
        }
        return result
    }

    func applyWhiteBalance(to cgImage: CGImage) -> CGImage {
        // 漫画/书籍页面的白平衡校正：轻度色温调整
        let ciImage = CIImage(cgImage: cgImage)

        guard let colorMatrixFilter = CIFilter(name: "CIColorMatrix") else { return cgImage }
        colorMatrixFilter.setValue(ciImage, forKey: kCIInputImageKey)
        // 轻微提升 R/B 通道使白色更纯净
        colorMatrixFilter.setValue(CIVector(x: 1.02, y: 0, z: 0, w: 0), forKey: "inputRVector")
        colorMatrixFilter.setValue(CIVector(x: 0, y: 1.0, z: 0, w: 0), forKey: "inputGVector")
        colorMatrixFilter.setValue(CIVector(x: 0, y: 0, z: 1.02, w: 0), forKey: "inputBVector")

        let context = CIContext(options: [.lowMemory: true])
        return context.createCGImage(colorMatrixFilter.outputImage!, from: ciImage.extent) ?? cgImage
    }

    /// 超分辨率（框架预留，实际使用时集成 waifu2x-ios CoreML 模型）
    /// 参考: https://github.com/imxieyi/waifu2x-ios (MIT License)
    func applySuperResolution(to cgImage: CGImage) async -> CGImage? {
        // waifu2x-ios 提供 CoreML 模型，集成方式：
        //
        // 1. 添加 waifu2x-ios 为 Swift Package 依赖:
        //    .package(url: "https://github.com/imxieyi/waifu2x-ios", from: "1.3.0")
        //
        // 2. 在 Package.swift 中添加:
        //    .product(name: "Waifu2x", package: "waifu2x-ios")
        //
        // 3. 使用示例:
        //    let waifu2x = Waifu2x(model: .anime_noise3_scale2x)
        //    let result = try await waifu2x.upscale(cgImage)
        //    return result
        //
        // 模型大小: anime_noise3_scale2x ≈ 8MB, photo模型 ≈ 12MB
        // 推理速度: iPhone 13+ GPU ≈ 200-400ms/张

        return cgImage // 默认不启用，由用户通过 config 开启
    }
}

// MARK: - 低电量模式感知

extension ImageEnhancer {
    /// 监听低电量模式变化
    func startPowerMonitoring() {
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handlePowerStateChange()
            }
        }
    }

    private func handlePowerStateChange() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled && config.pauseOnLowPower {
            // 暂停后台处理
            pendingTask?.cancel()
            isProcessing = false
        }
    }

    /// 低电量时降级：只用最轻量的滤波
    func lowPowerEnhance(image: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        let filter = CIFilter.sharpenLuminance()
        filter.inputImage = ciImage
        filter.sharpness = 0.3 // 极轻锐化

        let context = CIContext(options: [.lowMemory: true])
        return filter.outputImage.flatMap { context.createCGImage($0, from: ciImage.extent) }
    }
}
