import Foundation
import Vision
import CoreImage
import ImageIO

// MARK: - Panel Detector (Vision-based + AI Enhanced)

/// 基于 Vision 框架的漫画面板检测器，集成 AI 增强多通道检测。
/// - 主通道：VNDetectContoursRequest（经典轮廓检测）
/// - AI 增强：Attention Saliency → OCR → Contour → Hybrid → Grid（自动降级）
/// iOS 原生实现，无需第三方依赖，利用 Neural Engine 加速。
public struct PanelDetector: PanelDetectorProtocol, Sendable {

    public init() {}

    // MARK: - AI-Enhanced Public API

    /// 使用 AI 多通道策略检测面板：Saliency → OCR → Contour → Hybrid → Grid。
    /// - Parameters:
    ///   - cgImage: 预解码的 CGImage（避免重复解码）
    ///   - useAI: 是否启用 CoreML / Neural Engine 通道（默认 true）
    /// - Returns: 带置信度和方法元数据的检测结果
    public func detectPanelsEnhanced(in cgImage: CGImage, useAI: Bool = true) async -> AIDetectionPass {
        if useAI {
            let aiDetector = AIPanelDetector()
            return await aiDetector.detectPanels(in: cgImage)
        }
        return await detectContourOnly(in: cgImage)
    }

    /// Legacy API：从原始图像数据检测面板。
    /// 新代码请优先使用 `detectPanelsEnhanced(in:)`。
    public func detectPanels(in imageData: Data) async throws -> [PanelRegion] {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return []
        }

        // 使用 AI 增强检测
        let pass = await detectPanelsEnhanced(in: cgImage)

        return pass.panels.enumerated().map { (index, rect) in
            PanelRegion(
                index: index,
                normalizedRect: NormalizedRect(
                    x: Double(rect.x),
                    y: Double(rect.y),
                    width: Double(rect.width),
                    height: Double(rect.height)
                ),
                readingOrder: index
            )
        }
    }

    // MARK: - Contour-Only Fallback

    /// 纯轮廓检测（无 AI，适用于低功耗场景或快速预览）
    private func detectContourOnly(in cgImage: CGImage) async -> AIDetectionPass {
        let start = CFAbsoluteTimeGetCurrent()
        let ciImage = CIImage(cgImage: cgImage)
        let imageSize = ciImage.extent.size

        return await withCheckedContinuation { continuation in
            let request = VNDetectContoursRequest { request, error in
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

                guard error == nil,
                      let results = request.results as? [VNContoursObservation],
                      let observation = results.first else {
                    continuation.resume(returning: AIDetectionPass(
                        panels: [],
                        confidence: 0,
                        method: .contourEnhanced,
                        processingTimeMs: elapsed
                    ))
                    return
                }

                let panels = self.extractPanelsAsRects(
                    from: observation,
                    imageWidth: imageSize.width,
                    imageHeight: imageSize.height
                )

                let result = AIDetectionPass(
                    panels: panels,
                    confidence: Float(min(1.0, Double(panels.count) / 8.0)),
                    method: .contourEnhanced,
                    processingTimeMs: elapsed
                )

                continuation.resume(returning: result)
            }

            // 增强鲁棒性参数
            request.contrastAdjustment = 1.5          // 提高对比度适应低质量扫描
            request.detectsDarkOnLight = true
            request.maximumImageDimension = 2048
            request.contrastPivot = NSNumber(value: 0.5)

            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: AIDetectionPass(
                    panels: [],
                    confidence: 0,
                    method: .contourEnhanced,
                    processingTimeMs: (CFAbsoluteTimeGetCurrent() - start) * 1000
                ))
            }
        }
    }

    // MARK: - Robustness Pre-processing

    /// 对低质量扫描件进行预处理：对比度归一化 + 自适应阈值 + 锐化。
    public func preprocessForRobustness(_ image: CGImage) -> CGImage? {
        AIPanelDetector().preprocessImage(image)
    }

    // MARK: - Vision Contour Extraction

    /// 从 Vision 轮廓观测中提取 NormalizedRect 数组。
    private func extractPanelsAsRects(
        from observation: VNContoursObservation,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> [NormalizedRect] {
        var rects: [CGRect] = []

        let contours = observation.topLevelContours

        for contour in contours {
            let boundingBox = contour.normalizedBoundingBox()

            // 面积过滤
            let area = boundingBox.width * boundingBox.height
            guard area > 0.01 else { continue }    // 太小 → 噪音
            guard area < 0.95 else { continue }    // 太大 → 整页边框

            // 宽高比过滤（放宽范围以涵盖异形面板）
            let aspectRatio = boundingBox.width / boundingBox.height
            guard aspectRatio > 0.1 && aspectRatio < 8.0 else { continue }

            // 近似矩形检查
            if isApproximatelyRectangular(contour) {
                rects.append(boundingBox)
            }
        }

        // 碎片合并：如果只检测到极少的框，尝试更宽松的重检
        if rects.count < 2 {
            rects = reExtractLooseRects(from: contours)
        }

        // 阅读顺序排序（日漫：右上 → 左下）
        rects = sortByReadingOrder(rects)

        return rects.map { rect in
            NormalizedRect(
                x: Float(rect.origin.x),
                y: Float(rect.origin.y),
                width: Float(rect.width),
                height: Float(rect.height)
            )
        }
    }

    /// 宽松模式：降低面积/宽高比阈值重新提取。
    private func reExtractLooseRects(from contours: [VNContour]) -> [CGRect] {
        var rects: [CGRect] = []
        for contour in contours {
            let bb = contour.normalizedBoundingBox()
            let area = bb.width * bb.height
            guard area > 0.005 && area < 0.98 else { continue }
            let ar = bb.width / bb.height
            guard ar > 0.05 && ar < 12.0 else { continue }
            rects.append(bb)
        }
        return rects
    }

    // MARK: - Double Page Detection

    /// 检测是否为双页（基于宽高比）。
    public func isDoublePage(_ imageData: Data) async -> Bool {
        guard let ciImage = CIImage(data: imageData) else { return false }
        let size = ciImage.extent.size

        // 横屏且宽高比 > 1.3 大概率是双页
        return size.width > size.height && (size.width / size.height) > 1.3
    }

    /// 基于 CGImage 的双页检测（避免 Data 解码开销）。
    public func isDoublePage(cgImage: CGImage) -> Bool {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        return w > h && (w / h) > 1.3
    }

    // MARK: - Shape Analysis

    /// 判断轮廓是否近似矩形。
    private func isApproximatelyRectangular(_ contour: VNContour) -> Bool {
        let points = contour.normalizedPoints
        guard points.count >= 4 else { return false }

        let boundingBox = contour.normalizedBoundingBox()
        let boundingArea = boundingBox.width * boundingBox.height

        // Shoelace 公式计算多边形面积
        let contourArea = abs(calculatePolygonArea(points))

        // 填充率 > 55% → 近似矩形（放宽以兼容圆角面板）
        let fillRatio = boundingArea > 0 ? contourArea / boundingArea : 0
        return fillRatio > 0.55
    }

    /// Shoelace 公式计算多边形面积。
    private func calculatePolygonArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }

        var area: CGFloat = 0
        let n = points.count

        for i in 0..<n {
            let j = (i + 1) % n
            area += points[i].x * points[j].y
            area -= points[j].x * points[i].y
        }

        return abs(area) / 2.0
    }

    // MARK: - Reading Order (Manga: right-top → left-bottom)

    /// 按阅读顺序排序：右上 → 左下的蛇形扫描。
    private func sortByReadingOrder(_ rects: [CGRect]) -> [CGRect] {
        guard rects.count > 1 else { return rects }

        // 按 Y 分组（同一行）
        let sortedByY = rects.sorted { $0.midY < $1.midY }

        var rows: [[CGRect]] = []
        var currentRow: [CGRect] = [sortedByY[0]]
        var lastMidY = sortedByY[0].midY

        // 行分组阈值（使用平均高度的 40% 作为 hysteresis）
        let averageHeight = sortedByY.map { $0.height }.reduce(0, +) / CGFloat(sortedByY.count)
        let rowThreshold = max(averageHeight * 0.4, 0.02)

        for rect in sortedByY.dropFirst() {
            if abs(rect.midY - lastMidY) < rowThreshold {
                currentRow.append(rect)
            } else {
                rows.append(currentRow)
                currentRow = [rect]
                lastMidY = rect.midY
            }
        }
        rows.append(currentRow)

        // 每行内：右→左（日漫默认）
        var result: [CGRect] = []
        for row in rows {
            let sortedRow = row.sorted { $0.midX > $1.midX }  // 右→左
            result.append(contentsOf: sortedRow)
        }

        return result
    }
}
