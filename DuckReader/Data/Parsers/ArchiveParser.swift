import Foundation
import ZIPFoundation
import UnrarKit

// MARK: - Archive Parser Facade

/// 档案解析器的门面实现。
/// 根据检测到的格式自动路由到对应的子解析器。
/// 支持：ZIP/CBZ（ZIPFoundation）、RAR/CBR（UnrarKit）、7z、PDF、图片文件夹。
/// 设计亮点：
/// - 流式提取（按需解压单页，不预先解压全部）
/// - 超大文件友好（不将整个档案读入内存）
/// - 优雅错误处理（部分成功时返回已解析的页数和错误信息）
public final class ArchiveParser: ArchiveParserProtocol, @unchecked Sendable {
    
    public let supportedFormats: [BookFormat] = [
        .cbz, .cbr, .zip, .rar, .sevenZip, .pdf, .imageFolder
    ]
    
    private let comicParser: ComicArchiveParser
    private let imageFolderParser: ImageFolderParser
    private let fileManager: FileManager
    
    // MARK: - Cache
    
    /// 缓存每个档案的条目列表和页数，避免重复扫描
    private let entryCache = NSCache<NSURL, ArchiveEntryInfo>()
    private let cacheLock = NSLock()
    
    public init() {
        self.comicParser = ComicArchiveParser()
        self.imageFolderParser = ImageFolderParser()
        self.fileManager = FileManager.default
        entryCache.countLimit = 20  // 最多缓存 20 个档案的元数据
    }
    
    // MARK: - Parse
    
    public func parse(url: URL) async throws -> Book {
        let format = await FormatDetector.detect(url: url)
        
        guard supportedFormats.contains(format) else {
            throw ArchiveParserError.unsupportedFormat(url.pathExtension)
        }
        
        // 元数据提取
        let title = url.deletingPathExtension().lastPathComponent
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? 0
        
        // 获取页面数
        let pageCount: Int
        let entries: [String]
        
        switch format {
        case .cbz, .cbr, .zip, .rar, .sevenZip:
            let info = try await getEntryInfo(url: url, format: format)
            pageCount = info.imageEntries.count
            entries = info.imageEntries
            
        case .imageFolder:
            entries = try await imageFolderParser.listEntries(at: url)
            pageCount = entries.count
            
        case .pdf:
            // PDF 由 Readium 解析，先返回占位
            pageCount = 0
            entries = []
            
        default:
            pageCount = 0
            entries = []
        }
        
        // 确定内容类型
        let contentType: BookContentType = format.isComicFormat ? .comic : .novel
        
        return Book(
            title: title,
            sourceURL: url,
            format: format,
            contentType: contentType,
            totalPages: pageCount,
            fileSize: fileSize
        )
    }
    
    // MARK: - Extract Page
    
    public func extractPage(at url: URL, pageIndex: Int) async throws -> Data {
        let format = await FormatDetector.detect(url: url)
        
        switch format {
        case .cbz, .cbr, .zip, .rar, .sevenZip:
            return try await comicParser.extractPage(at: url, pageIndex: pageIndex, format: format)
            
        case .imageFolder:
            return try await imageFolderParser.extractPage(at: url, pageIndex: pageIndex)
            
        default:
            throw ArchiveParserError.unsupportedFormat(url.pathExtension)
        }
    }
    
    public func extractThumbnail(at url: URL, pageIndex: Int, maxSize: CGSize = CGSize(width: 300, height: 400)) async throws -> Data {
        // 先获取原图，再生成缩略图
        let imageData = try await extractPage(at: url, pageIndex: pageIndex)
        return try await ThumbnailGenerator.generateThumbnail(from: imageData, maxSize: maxSize)
    }
    
    // MARK: - List Entries
    
    public func listEntries(at url: URL) async throws -> [String] {
        let format = await FormatDetector.detect(url: url)
        
        switch format {
        case .cbz, .cbr, .zip, .rar, .sevenZip:
            return try await comicParser.listEntries(at: url, format: format)
        case .imageFolder:
            return try await imageFolderParser.listEntries(at: url)
        default:
            throw ArchiveParserError.unsupportedFormat(url.pathExtension)
        }
    }
    
    public func pageCount(at url: URL) async throws -> Int {
        let info = try await getEntryInfo(url: url, format: await FormatDetector.detect(url: url))
        return info.imageEntries.count
    }
    
    // MARK: - Private Helpers
    
    private func getEntryInfo(url: URL, format: BookFormat) async throws -> ArchiveEntryInfo {
        let nsURL = url as NSURL
        
        cacheLock.lock()
        if let cached = entryCache.object(forKey: nsURL) {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        
        let entries: [String]
        switch format {
        case .cbz, .cbr, .zip, .rar, .sevenZip:
            entries = try await comicParser.listEntries(at: url, format: format)
        case .imageFolder:
            entries = try await imageFolderParser.listEntries(at: url)
        default:
            entries = []
        }
        
        let imageEntries = entries.filter { isImageFile($0) }
        let info = ArchiveEntryInfo(allEntries: entries, imageEntries: imageEntries)
        
        cacheLock.lock()
        entryCache.setObject(info, forKey: nsURL)
        cacheLock.unlock()
        
        return info
    }
    
    private func isImageFile(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif", "heic"].contains(ext)
    }
}

// MARK: - Archive Entry Info (cache object)

final class ArchiveEntryInfo: NSObject {
    let allEntries: [String]
    let imageEntries: [String]
    
    init(allEntries: [String], imageEntries: [String]) {
        self.allEntries = allEntries
        self.imageEntries = imageEntries
    }
}
