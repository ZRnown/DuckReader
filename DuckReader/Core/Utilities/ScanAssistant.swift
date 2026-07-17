import Foundation
import Vision
import VisionKit
import UIKit
import UniformTypeIdentifiers
import ZIPFoundation

// MARK: - 物理扫描助手
/// 使用系统 Vision + VisionKit 实现一次性边缘检测/矫正
/// 保存优化版 CBZ，完全离线运行，不持续耗电
@MainActor
final class ScanAssistant: NSObject, ObservableObject {
    // MARK: - Config
    struct Config {
        /// 输出 DPI
        var outputDPI: Int = 300
        /// JPEG 压缩质量 0...1
        var jpegQuality: CGFloat = 0.92
        /// 是否自动矫正透视
        var autoRectify: Bool = true
        /// 是否自动裁剪
        var autoCrop: Bool = true
        /// 边缘检测灵敏度
        var edgeSensitivity: Float = 0.5
    }

    var config: Config = Config()

    // MARK: - State
    @Published var scannedPages: [ScannedPage] = []
    @Published var isScanning: Bool = false
    @Published var currentPageIndex: Int = 0
    @Published var errorMessage: String?

    struct ScannedPage: Identifiable, Sendable {
        let id: UUID
        let image: UIImage
        let detectedEdges: [CGPoint]?
        let pageNumber: Int
    }

    // MARK: - Public API

    /// 对单张图片做透视矫正
    func rectify(_ image: UIImage) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        // Step 1: 矩形检测
        let detectedRect = await detectDocumentRect(in: cgImage)

        // Step 2: 透视矫正
        if let rect = detectedRect {
            return applyPerspectiveCorrection(to: cgImage, rectangle: rect)
        }

        // 未检测到矩形时返回原图
        return image
    }

    /// 批量矫正多张图
    func rectifyBatch(_ images: [UIImage]) async -> [UIImage] {
        var results: [UIImage] = []
        for image in images {
            if let rectified = await rectify(image) {
                results.append(rectified)
            } else {
                results.append(image)
            }
        }
        return results
    }

    /// 导出为 CBZ
    func exportToCBZ(pages: [UIImage], filename: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanAssistant_\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 写入 JPG 文件
        for (index, page) in pages.enumerated() {
            let pageURL = tempDir.appendingPathComponent(
                String(format: "page_%04d.jpg", index + 1)
            )
            guard let data = page.jpegData(compressionQuality: config.jpegQuality) else {
                throw ScanError.encodingFailed(pageIndex: index)
            }
            try data.write(to: pageURL)
        }

        // 打包为 ZIP → .cbz
        let cbzURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filename).cbz")

        // 使用 ZIPFoundation (已在项目中作为依赖)
        try packToZip(sourceDir: tempDir, outputURL: cbzURL)

        // 清理临时目录
        try? FileManager.default.removeItem(at: tempDir)

        return cbzURL
    }

    /// 预览边缘检测结果
    func previewEdges(on image: UIImage) async -> [CGPoint]? {
        guard let cgImage = image.cgImage else { return nil }
        return await detectDocumentRectCorners(in: cgImage)
    }
}

// MARK: - Private: Vision 矩形检测

private extension ScanAssistant {

    func detectDocumentRect(in cgImage: CGImage) async -> VNRectangleObservation? {
        await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, _ in
                let results = request.results as? [VNRectangleObservation]
                // 取置信度最高且角度 < 45° 的结果
                let best = results?
                    .filter { abs($0.topLeft.y - $0.bottomLeft.y) < 0.5 * cgImage.height }
                    .max(by: { $0.confidence < $1.confidence })
                continuation.resume(returning: best)
            }

            request.minimumConfidence = config.edgeSensitivity
            request.maximumObservations = 1
            request.minimumAspectRatio = 0.3

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }

    func detectDocumentRectCorners(in cgImage: CGImage) async -> [CGPoint]? {
        guard let rect = await detectDocumentRect(in: cgImage) else { return nil }
        return [
            rect.topLeft,
            rect.topRight,
            rect.bottomRight,
            rect.bottomLeft,
        ]
    }

    /// 透视矫正
    func applyPerspectiveCorrection(
        to cgImage: CGImage,
        rectangle: VNRectangleObservation
    ) -> UIImage? {
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent

        // Vision 坐标系转 CI 坐标系（左下角原点）
        let topLeft = CGPoint(
            x: rectangle.topLeft.x * extent.width,
            y: (1 - rectangle.topLeft.y) * extent.height
        )
        let topRight = CGPoint(
            x: rectangle.topRight.x * extent.width,
            y: (1 - rectangle.topRight.y) * extent.height
        )
        let bottomRight = CGPoint(
            x: rectangle.bottomRight.x * extent.width,
            y: (1 - rectangle.bottomRight.y) * extent.height
        )
        let bottomLeft = CGPoint(
            x: rectangle.bottomLeft.x * extent.width,
            y: (1 - rectangle.bottomLeft.y) * extent.height
        )

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            return nil
        }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")

        guard let output = filter.outputImage else { return nil }

        let context = CIContext(options: [
            .outputColorSpace: CGColorSpaceCreateDeviceRGB(),
            .highQualityDownsample: true,
        ])

        guard let resultCG = context.createCGImage(output, from: output.extent) else {
            return nil
        }

        // 自动裁剪黑边
        if config.autoCrop {
            return cropToContent(resultCG)
        }

        return UIImage(cgImage: resultCG)
    }

    /// 去除透视矫正后的黑边
    func cropToContent(_ cgImage: CGImage) -> UIImage {
        let width = cgImage.width
        let height = cgImage.height

        guard let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return UIImage(cgImage: cgImage)
        }

        let bytesPerRow = cgImage.bytesPerRow
        var top = 0, bottom = height - 1, left = 0, right = width - 1

        for y in 0..<height {
            let offset = y * bytesPerRow
            let r = bytes[offset], g = bytes[offset + 1], b = bytes[offset + 2]
            if r > 10 || g > 10 || b > 10 { top = y; break }
        }

        for y in (0..<height).reversed() {
            let offset = y * bytesPerRow
            let r = bytes[offset], g = bytes[offset + 1], b = bytes[offset + 2]
            if r > 10 || g > 10 || b > 10 { bottom = y; break }
        }

        for x in stride(from: 0, to: width * 4, by: 4) {
            for y in 0..<height {
                let offset = y * bytesPerRow + x
                let r = bytes[offset], g = bytes[offset + 1], b = bytes[offset + 2]
                if r > 10 || g > 10 || b > 10 { left = x / 4; break }
            }
        }

        for x in stride(from: (width - 1) * 4, through: 0, by: -4) {
            for y in 0..<height {
                let offset = y * bytesPerRow + x
                let r = bytes[offset], g = bytes[offset + 1], b = bytes[offset + 2]
                if r > 10 || g > 10 || b > 10 { right = x / 4; break }
            }
        }

        let cropRect = CGRect(
            x: max(0, left),
            y: max(0, top),
            width: max(1, right - left),
            height: max(1, bottom - top)
        )

        if let cropped = cgImage.cropping(to: cropRect) {
            return UIImage(cgImage: cropped)
        }
        return UIImage(cgImage: cgImage)
    }

    /// 打包为 ZIP/CBZ
    /// 使用 ZIPFoundation（项目已依赖，MIT license）
    func packToZip(sourceDir: URL, outputURL: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: sourceDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "jpg" || $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !files.isEmpty else {
            throw ScanError.noDocumentDetected
        }

        // ZIPFoundation: 零压缩模式（CBZ 规范 — 图片已 JPEG 压缩，ZIP 仅做容器）
        // 使用 addEntry(with:relativeTo:) 统一添加
        guard let archive = Archive(url: outputURL, accessMode: .create) else {
            throw ScanError.zipFailed
        }

        for file in files {
            try archive.addEntry(with: file.lastPathComponent, relativeTo: sourceDir)
        }
    }
}

// MARK: - Errors

enum ScanError: LocalizedError {
    case encodingFailed(pageIndex: Int)
    case zipFailed
    case noDocumentDetected

    var errorDescription: String? {
        switch self {
        case .encodingFailed(let idx): "第 \(idx + 1) 页编码失败"
        case .zipFailed: "CBZ 打包失败"
        case .noDocumentDetected: "未检测到文档边缘"
        }
    }
}

// MARK: - VNDocumentCameraViewController 封装
/// SwiftUI 中使用的 UIViewControllerRepresentable
import SwiftUI

struct DocumentCameraView: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel)
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onScan: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            onScan(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onCancel()
        }
    }
}
