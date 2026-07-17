import Foundation
import ImageIO

// MARK: - Reading Engine Implementation

/// 阅读引擎的具体实现。
/// 负责管理当前打开的书籍、缓存页面、导航、面板检测和智能模式切换。
/// 设计：预加载前后 N 页，使用 NSCache 缓存最近访问的页面。
public actor ReadingEngine: ReadingEngineProtocol, Sendable {
    
    public private(set) var currentBook: Book?
    public private(set) var currentPageIndex: Int = 0
    public private(set) var totalPages: Int = 0

    /// 当前阅读模式
    public private(set) var currentMode: ReadingMode = .mangaSingle

    private let parser: ArchiveParserProtocol
    private let panelDetector: PanelDetectorProtocol?
    public let smartModeSwitcher: SmartModeSwitcher

    // Page cache
    private var pageCache = NSCache<NSNumber, PageCacheEntry>()
    private let preloadRange = 3  // 预加载前后各 3 页
    private let maxConcurrentPreloads = 3

    // MARK: - Init

    public init(
        parser: ArchiveParserProtocol = ArchiveParser(),
        panelDetector: PanelDetectorProtocol? = nil,
        smartModeSwitcher: SmartModeSwitcher = SmartModeSwitcher()
    ) {
        self.parser = parser
        self.panelDetector = panelDetector
        self.smartModeSwitcher = smartModeSwitcher
        pageCache.countLimit = 20
        pageCache.totalCostLimit = 50 * 1024 * 1024  // 50 MB
    }

    // MARK: - Open / Close

    public func open(book: Book) async throws {
        self.currentBook = book
        self.currentPageIndex = 0
        self.totalPages = try await parser.pageCount(at: book.sourceURL)

        // Clear cache for new book
        pageCache.removeAllObjects()

        // ---- Smart mode detection ----
        let detectedType = smartModeSwitcher.detectContentType(
            format: book.sourceURL.pathExtension.lowercased(),
            hasColor: true,   // refined with first-page analysis
            aspectRatio: 0.7, // placeholder, refined on first page load
            pageCount: totalPages,
            language: book.metadata.language
        )
        let device = DeviceContext(idiom: UIDevice.current.userInterfaceIdiom)
        currentMode = smartModeSwitcher.bestMode(contentType: detectedType, device: device)
    }

    public func goToPage(_ index: Int) async throws -> PageData {
        guard let book = currentBook else {
            throw EngineError.noBookOpen
        }

        let clampedIndex = max(0, min(index, totalPages - 1))
        currentPageIndex = clampedIndex

        // Check cache
        let nsIndex = NSNumber(value: clampedIndex)
        if let cached = pageCache.object(forKey: nsIndex) {
            return cached.pageData
        }

        // Load from archive
        let imageData = try await parser.extractPage(at: book.sourceURL, pageIndex: clampedIndex)

        // ---- AI-enhanced panel detection (using CGImage, avoids double decode) ----
        let panels: [PanelRegion]?
        if let detector = panelDetector as? PanelDetector,
           let source = CGImageSourceCreateWithData(imageData as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let pass = await detector.detectPanelsEnhanced(in: cgImage)
            panels = pass.panels.enumerated().map { (i, rect) in
                PanelRegion(
                    index: i,
                    normalizedRect: NormalizedRect(
                        x: Double(rect.x),
                        y: Double(rect.y),
                        width: Double(rect.width),
                        height: Double(rect.height)
                    ),
                    readingOrder: i
                )
            }
        } else {
            panels = try? await panelDetector?.detectPanels(in: imageData)
        }

        let page = PageData(
            id: clampedIndex,
            bookID: book.id,
            imageData: imageData,
            width: 0,
            height: 0,
            detectedPanels: panels
        )

        // Cache
        let entry = PageCacheEntry(pageData: page, cost: imageData.count)
        pageCache.setObject(entry, forKey: nsIndex, cost: imageData.count)

        // Preload nearby pages (limited concurrency)
        Task.detached(priority: .utility) { [weak self] in
            await self?.preloadPages(range:
                (clampedIndex - self!.preloadRange)..<(clampedIndex + self!.preloadRange)
            )
        }

        return page
    }
    
    public func nextPage() async throws -> PageData? {
        guard currentPageIndex < totalPages - 1 else { return nil }
        currentPageIndex += 1
        return try await goToPage(currentPageIndex)
    }
    
    public func previousPage() async throws -> PageData? {
        guard currentPageIndex > 0 else { return nil }
        currentPageIndex -= 1
        return try await goToPage(currentPageIndex)
    }
    
    public func close() async {
        currentBook = nil
        currentPageIndex = 0
        totalPages = 0
        pageCache.removeAllObjects()
    }

    // MARK: - Smart Mode Switching

    /// 根据设备旋转和内容类型自动切换阅读模式。
    /// - Parameter device: 新的设备上下文（orientation 变化后）
    /// - Returns: 建议的模式（可能与当前相同）
    public func suggestMode(for device: DeviceContext, contentType: DetectedContentType) -> ReadingMode? {
        smartModeSwitcher.suggestedTransition(
            currentMode: currentMode,
            newDevice: device,
            contentType: contentType
        )
    }

    /// 显式设置阅读模式并记录到学习模型。
    public func setMode(_ mode: ReadingMode, contentType: DetectedContentType) {
        currentMode = mode
        smartModeSwitcher.recordChoice(mode: mode, contentType: contentType)
    }

    /// 获取当前内容的类型检测结果。
    public func detectCurrentContentType() -> DetectedContentType? {
        guard let book = currentBook else { return nil }
        return smartModeSwitcher.detectContentType(
            format: book.sourceURL.pathExtension.lowercased(),
            hasColor: true,
            aspectRatio: 0.7,
            pageCount: totalPages,
            language: book.metadata.language
        )
    }
    
    // MARK: - Panel Detection
    
    public func detectPanels(for pageIndex: Int) async throws -> [PanelRegion] {
        guard let book = currentBook, let detector = panelDetector else {
            return []
        }
        
        let imageData = try await parser.extractPage(at: book.sourceURL, pageIndex: pageIndex)
        return try await detector.detectPanels(in: imageData)
    }
    
    // MARK: - Preloading
    
    public func preloadPages(range: Range<Int>) async {
        guard let book = currentBook else { return }
        
        let validRange = max(0, range.lowerBound)..<min(totalPages, range.upperBound)
        
        // Semaphore to limit concurrent archive reads
        await withTaskGroup(of: Void.self) { group in
            var running = 0
            for i in validRange {
                let nsIndex = NSNumber(value: i)
                if pageCache.object(forKey: nsIndex) != nil { continue }
                if running >= maxConcurrentPreloads {
                    _ = await group.next()
                    running -= 1
                }

                running += 1
                group.addTask {
                    do {
                        let data = try await self.parser.extractPage(at: book.sourceURL, pageIndex: i)
                        let page = PageData(id: i, bookID: book.id, imageData: data)
                        let entry = PageCacheEntry(pageData: page, cost: data.count)
                        self.pageCache.setObject(entry, forKey: nsIndex, cost: data.count)
                    } catch {
                        // Preload failure is non-critical
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Types

/// NSCache 条目的包装器
final class PageCacheEntry: NSObject {
    let pageData: PageData
    let cost: Int
    
    init(pageData: PageData, cost: Int) {
        self.pageData = pageData
        self.cost = cost
    }
}

enum EngineError: LocalizedError {
    case noBookOpen
    
    var errorDescription: String? {
        switch self {
        case .noBookOpen: L10n.readerNoBookOpen
        }
    }
}

// MARK: - Preview Engine (用于 SwiftUI Previews)

public actor PreviewReadingEngine: ReadingEngineProtocol {
    public var currentBook: Book?
    public var currentPageIndex: Int = 0
    public var totalPages: Int = 5
    
    public init() {}
    
    public func open(book: Book) async throws {
        self.currentBook = book
        self.totalPages = 5
    }
    
    public func goToPage(_ index: Int) async throws -> PageData {
        currentPageIndex = index
        return PageData(id: index, bookID: UUID())
    }
    
    public func nextPage() async throws -> PageData? {
        guard currentPageIndex < totalPages - 1 else { return nil }
        currentPageIndex += 1
        return PageData(id: currentPageIndex, bookID: UUID())
    }
    
    public func previousPage() async throws -> PageData? {
        guard currentPageIndex > 0 else { return nil }
        currentPageIndex -= 1
        return PageData(id: currentPageIndex, bookID: UUID())
    }
    
    public func close() async {
        currentBook = nil
    }
    
    public func detectPanels(for pageIndex: Int) async throws -> [PanelRegion] {
        [
            PanelRegion(
                index: 0,
                normalizedRect: NormalizedRect(x: 0.05, y: 0.02, width: 0.9, height: 0.3),
                readingOrder: 1
            ),
            PanelRegion(
                index: 1,
                normalizedRect: NormalizedRect(x: 0.05, y: 0.35, width: 0.45, height: 0.3),
                readingOrder: 2
            ),
            PanelRegion(
                index: 2,
                normalizedRect: NormalizedRect(x: 0.5, y: 0.35, width: 0.45, height: 0.3),
                readingOrder: 3
            ),
            PanelRegion(
                index: 3,
                normalizedRect: NormalizedRect(x: 0.05, y: 0.68, width: 0.9, height: 0.3),
                readingOrder: 4
            ),
        ]
    }
    
    public func preloadPages(range: Range<Int>) async {}
}
