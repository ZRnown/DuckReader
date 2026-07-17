import Foundation
import Vision
import CoreImage

// MARK: - Panel Detector (Vision-based)

/// 基于 Vision 框架的漫画面板检测器。
/// 使用 VNDetectContoursRequest 检测图像中的矩形区域（漫画面板边框）。
/// iOS 原生实现，无需第三方依赖。
public struct PanelDetector: PanelDetectorProtocol, Sendable {
    
    public init() {}
    
    /// 检测漫画面板
    /// 算法：检测轮廓 → 筛选近似矩形 → 过滤噪音 → 按阅读方向排序
    public func detectPanels(in imageData: Data) async throws -> [PanelRegion] {
        guard let ciImage = CIImage(data: imageData) else {
            return []
        }
        
        let imageSize = ciImage.extent.size
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectContoursRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let results = request.results as? [VNContoursObservation],
                      let observation = results.first else {
                    continuation.resume(returning: [])
                    return
                }
                
                let panels = self.extractPanels(
                    from: observation,
                    imageWidth: imageSize.width,
                    imageHeight: imageSize.height
                )
                
                continuation.resume(returning: panels)
            }
            
            // Configure contour detection
            request.contrastAdjustment = 1.0
            request.detectsDarkOnLight = true
            request.maximumImageDimension = 2048  // 性能优化
            
            let handler = VNImageRequestHandler(ciImage: ciImage)
            try? handler.perform([request])
        }
    }
    
    /// 检测是否为双页
    public func isDoublePage(_ imageData: Data) async -> Bool {
        guard let ciImage = CIImage(data: imageData) else { return false }
        let size = ciImage.extent.size
        
        // 横屏且宽高比 > 1.4 大概率是双页
        return size.width > size.height && (size.width / size.height) > 1.4
    }
    
    // MARK: - Private
    
    private func extractPanels(
        from observation: VNContoursObservation,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> [PanelRegion] {
        var panelRects: [CGRect] = []
        
        let contours = observation.topLevelContours
        
        for contour in contours {
            let boundingBox = contour.normalizedBoundingBox()
            
            // 过滤条件
            let area = boundingBox.width * boundingBox.height
            
            // 太小：忽略（噪音）
            guard area > 0.02 else { continue }
            
            // 太大：可能是整页边框，忽略
            guard area < 0.95 else { continue }
            
            // 太细长：可能是分隔线
            let aspectRatio = boundingBox.width / boundingBox.height
            guard aspectRatio > 0.15 && aspectRatio < 6.5 else { continue }
            
            // 近似矩形检查
            if isApproximatelyRectangular(contour) {
                panelRects.append(boundingBox)
            }
        }
        
        // 按阅读顺序排序（日漫：右上 → 左下）
        // 先按 Y 坐标分组（行），再在每组内按 X 排序
        let sorted = sortByReadingOrder(panelRects)
        
        return sorted.enumerated().map { (index, rect) in
            PanelRegion(
                index: index,
                normalizedRect: NormalizedRect(
                    x: Double(rect.origin.x),
                    y: Double(rect.origin.y),
                    width: Double(rect.width),
                    height: Double(rect.height)
                ),
                readingOrder: index
            )
        }
    }
    
    /// 判断轮廓是否近似矩形
    private func isApproximatelyRectangular(_ contour: VNContour) -> Bool {
        let points = contour.normalizedPoints
        guard points.count >= 4 else { return false }
        
        // 简化：检查轮廓的宽高比和面积与 bounding box 的关系
        let boundingBox = contour.normalizedBoundingBox()
        let boundingArea = boundingBox.width * boundingBox.height
        
        // 轮廓的实际面积（简化计算）
        let contourArea = abs(calculatePolygonArea(points))
        
        // 轮廓面积与 bounding box 面积的比例
        // 接近 1 说明形状接近矩形
        let fillRatio = boundingArea > 0 ? contourArea / boundingArea : 0
        return fillRatio > 0.6  // 60% 填充率以上视为矩形
    }
    
    /// 用 Shoelace 公式计算多边形面积
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
    
    /// 按阅读顺序排序：右上 → 左下的蛇形
    private func sortByReadingOrder(_ rects: [CGRect]) -> [CGRect] {
        guard !rects.isEmpty else { return [] }
        
        // 按 Y 分组（同一行）
        let sortedByY = rects.sorted { a, b in
            a.midY < b.midY
        }
        
        var rows: [[CGRect]] = []
        var currentRow: [CGRect] = [sortedByY[0]]
        var lastMidY = sortedByY[0].midY
        
        // Hysteresis threshold for row grouping
        let averageHeight = sortedByY.map { $0.height }.reduce(0, +) / CGFloat(sortedByY.count)
        let rowThreshold = averageHeight * 0.4
        
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
        
        // 每行内：右→左（日漫顺序）或 左→右
        var result: [CGRect] = []
        var rightToLeft = true  // 默认日漫顺序
        
        for row in rows {
            let sortedRow = rightToLeft
                ? row.sorted { $0.midX > $1.midX }  // 右→左
                : row.sorted { $0.midX < $1.midX }  // 左→右
            result.append(contentsOf: sortedRow)
        }
        
        return result
    }
}
