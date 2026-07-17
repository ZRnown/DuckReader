import Foundation
import ImageIO
import CoreImage
import UniformTypeIdentifiers

// MARK: - Thumbnail Generator

/// 缩略图生成器：从图像数据生成低分辨率缩略图，适合图书馆封面和快速预览。
public enum ThumbnailGenerator: Sendable {
    
    /// 从图像数据生成缩略图
    /// - Parameters:
    ///   - data: 原始图像数据
    ///   - maxSize: 最大尺寸（保持宽高比）
    /// - Returns: JPEG 压缩的缩略图数据
    public static func generateThumbnail(from data: Data, maxSize: CGSize) async throws -> Data {
        return try await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
                throw ImageError.invalidImageData
            }
            
            let width = (properties[kCGImagePropertyPixelWidth] as? CGFloat) ?? maxSize.width * 2
            let height = (properties[kCGImagePropertyPixelHeight] as? CGFloat) ?? maxSize.height * 2
            
            // 计算缩略图目标尺寸
            let scale = min(maxSize.width / width, maxSize.height / height, 1.0)
            let targetWidth = Int(width * scale)
            let targetHeight = Int(height * scale)
            
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(targetWidth, targetHeight),
                kCGImageSourceShouldCacheImmediately: true,
            ]
            
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw ImageError.thumbnailGenerationFailed
            }
            
            // 编码为 JPEG
            guard let jpegData = CFDataCreateMutable(nil, 0) else {
                throw ImageError.encodingFailed
            }
            
            guard let destination = CGImageDestinationCreateWithData(jpegData, "public.jpeg" as CFString, 1, nil) else {
                throw ImageError.encodingFailed
            }
            
            let jpegOptions: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: 0.7
            ]
            
            CGImageDestinationAddImage(destination, thumbnail, jpegOptions as CFDictionary)
            
            guard CGImageDestinationFinalize(destination) else {
                throw ImageError.encodingFailed
            }
            
            return jpegData as Data
        }.value
    }
}

// MARK: - Image Processor

/// 图像处理器：裁剪白边、基础增强、格式转换
public enum ImageProcessor: Sendable {
    
    /// 智能裁白边
    public static func cropWhiteBorders(_ imageData: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard let ciImage = CIImage(data: imageData) else {
                throw ImageError.invalidImageData
            }
            
            // 检测白边边缘
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                throw ImageError.processingFailed
            }
            
            let width = cgImage.width
            let height = cgImage.height
            
            guard let pixelData = cgImage.dataProvider?.data,
                  let data = CFDataGetBytePtr(pixelData) else {
                return imageData // fallback: return original
            }
            
            let bytesPerPixel = cgImage.bitsPerPixel / 8
            
            // 白色阈值（接近白色视为白边）
            let threshold: UInt8 = 240
            
            // 从四个方向扫描非白像素
            var left = 0, right = width - 1, top = 0, bottom = height - 1
            
            // Scan top
            outerTop: for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * cgImage.bytesPerRow) + (x * bytesPerPixel)
                    let r = data[offset]
                    let g = data[offset + 1]
                    let b = data[offset + 2]
                    if r < threshold || g < threshold || b < threshold {
                        top = y
                        break outerTop
                    }
                }
            }
            
            // Scan bottom
            outerBottom: for y in (0..<height).reversed() {
                for x in 0..<width {
                    let offset = (y * cgImage.bytesPerRow) + (x * bytesPerPixel)
                    let r = data[offset]
                    let g = data[offset + 1]
                    let b = data[offset + 2]
                    if r < threshold || g < threshold || b < threshold {
                        bottom = y
                        break outerBottom
                    }
                }
            }
            
            // Scan left
            outerLeft: for x in 0..<width {
                for y in 0..<height {
                    let offset = (y * cgImage.bytesPerRow) + (x * bytesPerPixel)
                    let r = data[offset]
                    let g = data[offset + 1]
                    let b = data[offset + 2]
                    if r < threshold || g < threshold || b < threshold {
                        left = x
                        break outerLeft
                    }
                }
            }
            
            // Scan right
            outerRight: for x in (0..<width).reversed() {
                for y in 0..<height {
                    let offset = (y * cgImage.bytesPerRow) + (x * bytesPerPixel)
                    let r = data[offset]
                    let g = data[offset + 1]
                    let b = data[offset + 2]
                    if r < threshold || g < threshold || b < threshold {
                        right = x
                        break outerRight
                    }
                }
            }
            
            // 留一点边距
            let margin = 5
            let cropRect = CGRect(
                x: max(0, left - margin),
                y: max(0, top - margin),
                width: min(width - left, right - left + margin * 2),
                height: min(height - top, bottom - top + margin * 2)
            )
            
            guard cropRect.width > 0, cropRect.height > 0 else {
                return imageData
            }
            
            guard let croppedImage = cgImage.cropping(to: cropRect) else {
                return imageData
            }
            
            // 编码回原格式
            let outputData = CFDataCreateMutable(nil, 0)!
            guard let destination = CGImageDestinationCreateWithData(outputData, "public.jpeg" as CFString, 1, nil) else {
                return imageData
            }
            CGImageDestinationAddImage(destination, croppedImage, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            CGImageDestinationFinalize(destination)
            
            return outputData as Data
        }.value
    }
    
    /// 基础图像增强：对比度 + 锐化
    public static func enhance(_ imageData: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard let ciImage = CIImage(data: imageData) else {
                throw ImageError.invalidImageData
            }
            
            let filters = ciImage
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1.05
                ])
                .applyingFilter("CIUnsharpMask", parameters: [
                    kCIInputRadiusKey: 1.5,
                    kCIInputIntensityKey: 0.5
                ])
            
            let context = CIContext()
            guard let cgImage = context.createCGImage(filters, from: filters.extent) else {
                throw ImageError.processingFailed
            }
            
            let outputData = CFDataCreateMutable(nil, 0)!
            guard let destination = CGImageDestinationCreateWithData(outputData, "public.png" as CFString, 1, nil) else {
                throw ImageError.encodingFailed
            }
            CGImageDestinationAddImage(destination, cgImage, nil)
            CGImageDestinationFinalize(destination)
            
            return outputData as Data
        }.value
    }
}

// MARK: - Image Errors

enum ImageError: LocalizedError {
    case invalidImageData
    case thumbnailGenerationFailed
    case encodingFailed
    case processingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImageData: "无效的图像数据"
        case .thumbnailGenerationFailed: "缩略图生成失败"
        case .encodingFailed: "图像编码失败"
        case .processingFailed: "图像处理失败"
        }
    }
}
