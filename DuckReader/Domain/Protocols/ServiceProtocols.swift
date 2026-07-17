import Foundation

// MARK: - Archive Parser Protocol

/// 档案解析器协议。所有格式解析器必须遵循此协议。
/// 设计目标：流式读取、On-Device 处理、支持超大文件。
public protocol ArchiveParserProtocol: Sendable {
    /// 解析器支持的格式列表
    var supportedFormats: [BookFormat] { get }
    
    /// 从 URL 解析档案，返回 Book 元数据和页面列表
    /// - Parameter url: 本地档案或文件夹 URL
    /// - Returns: 解析后的 Book 实例（含元数据和总页数）
    /// - Throws: ArchiveParserError
    func parse(url: URL) async throws -> Book
    
    /// 流式提取指定页面的图像数据
    /// - Parameters:
    ///   - url: 档案 URL
    ///   - pageIndex: 页码 (0-based)
    /// - Returns: 该页的图像数据 (PNG/JPEG)
    /// - Throws: ArchiveParserError
    func extractPage(at url: URL, pageIndex: Int) async throws -> Data
    
    /// 提取指定页面的低分辨率缩略图（用于快速预览）
    func extractThumbnail(at url: URL, pageIndex: Int, maxSize: CGSize) async throws -> Data
    
    /// 获取档案内所有条目的文件名列表（排序后）
    func listEntries(at url: URL) async throws -> [String]
    
    /// 获取总页数
    func pageCount(at url: URL) async throws -> Int
}

// MARK: - Archive Parser Errors

public enum ArchiveParserError: LocalizedError, Sendable {
    case fileNotFound(URL)
    case unsupportedFormat(String)
    case corruptedArchive(String)
    case extractionFailed(String)
    case noImagesFound
    case partialExtraction(pageCount: Int, error: String)
    case unsupportedEncryption
    case readError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            "找不到文件: \(url.lastPathComponent)"
        case .unsupportedFormat(let ext):
            "不支持的格式: \(ext)"
        case .corruptedArchive(let detail):
            "档案损坏: \(detail)"
        case .extractionFailed(let detail):
            "解压失败: \(detail)"
        case .noImagesFound:
            "档案中未找到图片文件"
        case .partialExtraction(let count, let error):
            "部分解压成功 (\(count) 页), 但遇到错误: \(error)"
        case .unsupportedEncryption:
            "不支持加密档案"
        case .readError(let error):
            "读取错误: \(error.localizedDescription)"
        }
    }
    
    /// 优雅降级：部分成功时返回已解析的页数和错误信息
    public var partialPageCount: Int? {
        if case .partialExtraction(let count, _) = self { return count }
        return nil
    }
}

// MARK: - Reading Engine Protocol

public protocol ReadingEngineProtocol: Sendable {
    /// 当前打开的书
    var currentBook: Book? { get async }
    
    /// 当前页码
    var currentPageIndex: Int { get async }
    
    /// 总页数
    var totalPages: Int { get async }
    
    /// 打开一本书
    func open(book: Book) async throws
    
    /// 跳转到指定页
    func goToPage(_ index: Int) async throws -> PageData
    
    /// 获取下一页
    func nextPage() async throws -> PageData?
    
    /// 获取上一页
    func previousPage() async throws -> PageData?
    
    /// 关闭当前书
    func close() async
    
    /// 获取当前页的检测面板（用于逐面板阅读）
    func detectPanels(for pageIndex: Int) async throws -> [PanelRegion]
    
    /// 预加载指定范围内的页面
    func preloadPages(range: Range<Int>) async
}

// MARK: - Library Repository Protocol

public protocol LibraryRepositoryProtocol: Sendable {
    /// 获取所有图书
    func fetchAll(sortBy: LibrarySortOption) async throws -> [Book]
    
    /// 按标签筛选
    func fetchByTag(_ tag: Tag) async throws -> [Book]
    
    /// 搜索
    func search(query: String) async throws -> [Book]
    
    /// 添加图书
    func add(_ book: Book) async throws
    
    /// 删除图书
    func remove(_ book: Book) async throws
    
    /// 更新图书
    func update(_ book: Book) async throws
    
    /// 获取阅读进度
    func fetchProgress(for bookID: UUID) async throws -> ReadingProgress?
    
    /// 保存阅读进度
    func saveProgress(_ progress: ReadingProgress, for bookID: UUID) async throws
    
    /// 获取书签
    func fetchBookmarks(for bookID: UUID) async throws -> [Bookmark]
    
    /// 保存书签
    func saveBookmark(_ bookmark: Bookmark) async throws
    
    /// 删除书签
    func removeBookmark(_ bookmark: Bookmark) async throws
}

public enum LibrarySortOption: String, CaseIterable, Sendable {
    case title
    case author
    case recentlyOpened
    case recentlyAdded
    case progress
}

// MARK: - Sync Service Protocol

public protocol SyncServiceProtocol: Sendable {
    var isEnabled: Bool { get async }
    var lastSyncDate: Date? { get async }
    
    func enable() async throws
    func disable() async
    func sync() async throws
    func syncProgress(_ progress: ReadingProgress, for bookID: UUID) async throws
    func syncBookmark(_ bookmark: Bookmark) async throws
}

// MARK: - Panel Detection Protocol

public protocol PanelDetectorProtocol: Sendable {
    /// 检测图像中的漫画面板区域
    /// - Parameter imageData: 图像数据
    /// - Returns: 按阅读顺序排列的面板区域列表
    func detectPanels(in imageData: Data) async throws -> [PanelRegion]
    
    /// 检测是否为双页（跨页）图像
    func isDoublePage(_ imageData: Data) async -> Bool
}

// MARK: - Image Enhancement Protocol

public protocol ImageEnhancementProtocol: Sendable {
    /// 增强图像质量（去噪、锐化、对比度）
    func enhance(_ imageData: Data) async throws -> Data
    
    /// 智能裁白边
    func cropWhiteBorders(_ imageData: Data) async throws -> Data
    
    /// 放大低分辨率图像（超分辨率）
    func upscale(_ imageData: Data, scale: Double) async throws -> Data
}
