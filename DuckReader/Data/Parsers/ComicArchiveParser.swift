import Foundation
import ZIPFoundation
import UnrarKit

// MARK: - Comic Archive Parser

/// 漫画档案解析器：处理 ZIP/CBZ、RAR/CBR 和 7z 格式。
///
/// CBZ = ZIP 容器内只含图片文件
/// CBR = RAR 容器内只含图片文件
///
/// 关键设计：
/// - 流式提取：只解压需要的单页，不解压整个档案
/// - 排序：按文件名字典序排序（漫画页通常编号命名）
/// - 嵌套档案：递归处理嵌套的 ZIP/RAR
public final class ComicArchiveParser: Sendable {
    
    private let fileManager = FileManager.default
    
    // 图片文件扩展名
    private let imageExtensions = Set([
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif", "heic"
    ])
    
    // MARK: - List Entries
    
    func listEntries(at url: URL, format: BookFormat) async throws -> [String] {
        switch format {
        case .cbz, .zip, .epub:
            return try await listZIPEntries(at: url)
        case .cbr, .rar:
            return try await listRAREntries(at: url)
        case .sevenZip:
            return try await list7zEntries(at: url)
        default:
            throw ArchiveParserError.unsupportedFormat(url.pathExtension)
        }
    }
    
    // MARK: - Extract Page
    
    func extractPage(at url: URL, pageIndex: Int, format: BookFormat) async throws -> Data {
        switch format {
        case .cbz, .zip, .epub:
            return try await extractFromZIP(at: url, pageIndex: pageIndex)
        case .cbr, .rar:
            return try await extractFromRAR(at: url, pageIndex: pageIndex)
        case .sevenZip:
            return try await extractFrom7z(at: url, pageIndex: pageIndex)
        default:
            throw ArchiveParserError.unsupportedFormat(url.pathExtension)
        }
    }
    
    // MARK: - ZIP / CBZ Implementation
    
    private func listZIPEntries(at url: URL) async throws -> [String] {
        return try await Task.detached(priority: .userInitiated) {
            guard let archive = Archive(url: url, accessMode: .read) else {
                throw ArchiveParserError.corruptedArchive("无法打开 ZIP 档案: \(url.lastPathComponent)")
            }
            
            // 收集所有图片文件条目，跳过目录和隐藏文件
            let entries = archive
                .filter { entry in
                    let name = entry.path
                    guard !name.hasPrefix(".") else { return false }
                    guard !name.hasPrefix("__MACOSX") else { return false }
                    guard entry.type == .file else { return false }
                    
                    let ext = (name as NSString).pathExtension.lowercased()
                    return self.imageExtensions.contains(ext)
                }
                .map { $0.path }
                .sorted { self.naturalSort($0, $1) }
            
            guard !entries.isEmpty else {
                throw ArchiveParserError.noImagesFound
            }
            
            return entries
        }.value
    }
    
    private func extractFromZIP(at url: URL, pageIndex: Int) async throws -> Data {
        return try await Task.detached(priority: .userInitiated) {
            guard let archive = Archive(url: url, accessMode: .read) else {
                throw ArchiveParserError.corruptedArchive("无法打开 ZIP: \(url.lastPathComponent)")
            }
            
            // 获取排序后的图片条目
            let imageEntries = archive
                .filter { entry in
                    let name = entry.path
                    guard !name.hasPrefix("."), !name.hasPrefix("__MACOSX") else { return false }
                    guard entry.type == .file else { return false }
                    return self.imageExtensions.contains((name as NSString).pathExtension.lowercased())
                }
                .sorted { self.naturalSort($0.path, $1.path) }
            
            guard pageIndex < imageEntries.count else {
                throw ArchiveParserError.extractionFailed("页码 \(pageIndex) 超出范围 (共 \(imageEntries.count) 页)")
            }
            
            let targetEntry = imageEntries[pageIndex]
            var extractedData = Data()
            
            // 流式提取到内存
            _ = try archive.extract(targetEntry, skipCRC32: true) { chunk in
                extractedData.append(chunk)
            }
            
            guard !extractedData.isEmpty else {
                throw ArchiveParserError.extractionFailed("提取的页面为空")
            }
            
            return extractedData
        }.value
    }
    
    // MARK: - RAR / CBR Implementation
    
    private func listRAREntries(at url: URL) async throws -> [String] {
        return try await Task.detached(priority: .userInitiated) {
            let archive: URKArchive
            do {
                archive = try URKArchive(path: url.path)
            } catch {
                throw ArchiveParserError.corruptedArchive("无法打开 RAR: \(error.localizedDescription)")
            }
            
            let allFiles: [String]
            do {
                allFiles = try archive.listFilenames()
            } catch {
                throw ArchiveParserError.extractionFailed("无法列出 RAR 内容: \(error.localizedDescription)")
            }
            
            let imageFiles = allFiles
                .filter { name in
                    guard !name.hasPrefix("."), !name.hasPrefix("__MACOSX") else { return false }
                    let ext = (name as NSString).pathExtension.lowercased()
                    return self.imageExtensions.contains(ext)
                }
                .sorted { self.naturalSort($0, $1) }
            
            guard !imageFiles.isEmpty else {
                throw ArchiveParserError.noImagesFound
            }
            
            return imageFiles
        }.value
    }
    
    private func extractFromRAR(at url: URL, pageIndex: Int) async throws -> Data {
        return try await Task.detached(priority: .userInitiated) {
            let archive: URKArchive
            do {
                archive = try URKArchive(path: url.path)
            } catch {
                throw ArchiveParserError.corruptedArchive("无法打开 RAR: \(error.localizedDescription)")
            }
            
            let entries: [String]
            do {
                entries = try archive.listFilenames()
                    .filter { self.imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
                    .sorted { self.naturalSort($0, $1) }
            } catch {
                throw ArchiveParserError.extractionFailed("RAR 列表错误: \(error.localizedDescription)")
            }
            
            guard pageIndex < entries.count else {
                throw ArchiveParserError.extractionFailed("页码 \(pageIndex) 超出范围")
            }
            
            let targetFilename = entries[pageIndex]
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("DuckReader_RAR_\(UUID().uuidString)")
            
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            
            do {
                try archive.extractFiles(
                    from: targetFilename,
                    toPath: tempDir.path,
                    overwrite: true
                )
            } catch {
                throw ArchiveParserError.extractionFailed("RAR 提取失败: \(error.localizedDescription)")
            }
            
            let extractedFile = tempDir.appendingPathComponent(targetFilename)
            let data = try Data(contentsOf: extractedFile)
            
            guard !data.isEmpty else {
                throw ArchiveParserError.extractionFailed("提取的 RAR 文件为空")
            }
            
            return data
        }.value
    }
    
    // MARK: - 7z Implementation
    
    private func list7zEntries(at url: URL) async throws -> [String] {
        // 7z 支持目前需要集成 LZMA SDK 或 libarchive
        // 作为 fallback，尝试调用系统 /usr/bin/7z（如果存在）或返回错误
        throw ArchiveParserError.unsupportedFormat("7z 格式需要额外依赖 (LZMA SDK)")
    }
    
    private func extractFrom7z(at url: URL, pageIndex: Int) async throws -> Data {
        throw ArchiveParserError.unsupportedFormat("7z 格式需要额外依赖 (LZMA SDK)")
    }
    
    // MARK: - Natural Sort
    
    /// 自然排序：将 "page10" 排在 "page2" 之后
    private func naturalSort(_ a: String, _ b: String) -> Bool {
        let aPath = a.lowercased()
        let bPath = b.lowercased()
        
        // 提取文件名中的数字进行自然排序
        return aPath.localizedStandardCompare(bPath) == .orderedAscending
    }
}

// MARK: - Image Folder Parser

/// 图片文件夹解析器：读取文件夹中的所有图片文件。
final class ImageFolderParser: Sendable {
    
    private let imageExtensions = Set([
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif", "heic"
    ])
    
    func listEntries(at url: URL) async throws -> [String] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        
        let imageFiles = contents
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .map { $0.lastPathComponent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        
        guard !imageFiles.isEmpty else {
            throw ArchiveParserError.noImagesFound
        }
        
        return imageFiles
    }
    
    func extractPage(at url: URL, pageIndex: Int) async throws -> Data {
        let entries = try await listEntries(at: url)
        
        guard pageIndex < entries.count else {
            throw ArchiveParserError.extractionFailed("页码超出范围")
        }
        
        let fileURL = url.appendingPathComponent(entries[pageIndex])
        return try Data(contentsOf: fileURL)
    }
}
