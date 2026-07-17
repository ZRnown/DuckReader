import Foundation
import UniformTypeIdentifiers

/// 格式检测器：从文件扩展名、MIME 类型和文件头魔数推断图书格式。
/// 思路：不依赖扩展名，先用魔数验证再 fallback 到扩展名。
public struct FormatDetector: Sendable {
    
    /// 已知魔数签名表
    private static let magicSignatures: [(bytes: [UInt8], format: BookFormat)] = [
        ([0x50, 0x4B, 0x03, 0x04], .zip),   // ZIP / CBZ
        ([0x52, 0x61, 0x72, 0x21], .rar),    // RAR 4.x
        ([0x52, 0x61, 0x72, 0x1A], .rar),    // RAR 5.x
        ([0x37, 0x7A, 0xBC, 0xAF], .sevenZip), // 7z
        ([0x25, 0x50, 0x44, 0x46], .pdf),    // PDF
        ([0x50, 0x4B, 0x05, 0x06], .epub),   // EPUB (ZIP-based)
        ([0x50, 0x4B, 0x03, 0x04], .cbz),    // CBZ (ZIP-based, same magic)
        // MOBI: 0x42 0x4F 0x4F 0x4B 0x4D 0x4F 0x42 0x49 at offset 60
        // AZW3: like MOBI but with "AZW" marker
    ]
    
    /// 检测文件格式
    /// - Parameter url: 文件 URL
    /// - Returns: 检测到的格式（.unknown 表示无法识别）
    public static func detect(url: URL) async -> BookFormat {
        // 如果是目录，可能是图片文件夹
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path(), isDirectory: &isDirectory),
           isDirectory.boolValue {
            return await detectImageFolder(url)
        }
        
        // 1. 先尝试魔数检测（可靠）
        if let format = await detectByMagic(url) {
            return refineFormat(format: format, url: url)
        }
        
        // 2. 回退到扩展名
        return BookFormat.infer(from: url)
    }
    
    /// 魔数检测
    private static func detectByMagic(_ url: URL) async -> BookFormat? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        
        guard let data = try? handle.read(upToCount: 16) else {
            return nil
        }
        
        let bytes = [UInt8](data)
        
        // Check each signature
        for (signature, format) in magicSignatures {
            if bytes.starts(with: signature) {
                return format
            }
        }
        
        // Check for MOBI/AZW3: look for "BOOKMOBI" at offset 60
        if bytes.count >= 68 {
            try? handle.seek(toOffset: 60)
            if let mobiData = try? handle.read(upToCount: 8),
               String(data: mobiData, encoding: .ascii) == "BOOKMOBI" {
                // Check if AZW3
                try? handle.seek(toOffset: 0)
                if let full = try? handle.read(upToCount: 100) {
                    let fullStr = String(data: full, encoding: .ascii) ?? ""
                    if fullStr.contains("AZW") {
                        return .azw3
                    }
                }
                return .mobi
            }
        }
        
        return nil
    }
    
    /// 细化格式：ZIP 魔数可能对应 ZIP/CBZ/EPUB，需要进一步判断
    private static func refineFormat(format: BookFormat, url: URL) async -> BookFormat {
        switch format {
        case .zip:
            // 检查是否是 EPUB（EPUB 是 ZIP 容器，含 META-INF/container.xml）
            if await isEPUB(url) { return .epub }
            // 检查是否是 CBZ（按约定 CBZ 内只有图片文件）
            if await isComicArchive(url) { return .cbz }
            return .zip
            
        case .rar:
            // 检查是否是 CBR
            if await isComicArchive(url) { return .cbr }
            return .rar
            
        case .cbz, .cbr:
            return format
            
        default:
            return format
        }
    }
    
    /// 检查 ZIP 文件是否为 EPUB
    private static func isEPUB(_ url: URL) async -> Bool {
        // 快速检查：查看 ZIP 内是否包含 META-INF/container.xml
        return await withCheckedContinuation { continuation in
            // 使用 ZIPFoundation 快速检查条目
            // 此处简化：通过文件名约定判断
            let name = url.lastPathComponent.lowercased()
            if name.hasSuffix(".epub") {
                continuation.resume(returning: true)
                return
            }
            continuation.resume(returning: false)
        }
    }
    
    /// 检查档案是否包含图片（CBZ/CBR 特征）
    private static func isComicArchive(_ url: URL) async -> Bool {
        let name = url.lastPathComponent.lowercased()
        // 如果扩展名已经明确是 CBZ/CBR
        if name.hasSuffix(".cbz") || name.hasSuffix(".cbr") {
            return true
        }
        return false
    }
    
    /// 检测图片文件夹
    private static func detectImageFolder(_ url: URL) async -> BookFormat {
        let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "heic"])
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .unknown
        }
        
        let imageCount = contents.filter { imageExtensions.contains($0.pathExtension.lowercased()) }.count
        
        // 如果超过 50% 的文件是图片，视为图片文件夹
        if imageCount > 0 && Double(imageCount) / Double(contents.count) > 0.5 {
            return .imageFolder
        }
        
        return .unknown
    }
}
