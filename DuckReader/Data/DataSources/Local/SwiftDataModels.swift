import Foundation
import SwiftData

// MARK: - SwiftData Models

/// SwiftData 持久化模型。
/// 这些是 @Model 类，直接映射到 SQLite。
/// 与 Domain 层的 struct 保持分离：Domain struct 用于内存传递，@Model 用于持久化。

@Model
public final class SwiftDataBook {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var author: String?
    public var coverImageData: Data?
    public var sourceURLPath: String        // URL 转为 String 存储
    public var formatRawValue: String
    public var contentTypeRawValue: String
    public var totalPages: Int
    public var fileSize: Int64
    public var importedAt: Date
    public var lastOpenedAt: Date?
    public var isFavorite: Bool
    
    // Metadata as flat properties (SwiftData 不支持嵌套 Codable 直接查询)
    public var metadataLanguage: String?
    public var metadataPublisher: String?
    public var metadataPublishedDate: Date?
    public var metadataISBN: String?
    public var metadataSeries: String?
    public var metadataSeriesIndex: Int?
    public var metadataDescription: String?
    public var metadataAutoTags: [String]   // SwiftData 支持 [String] 基础类型数组
    public var metadataAISummary: String?
    public var metadataRating: Double?
    
    // Relationships
    @Relationship(deleteRule: .cascade) public var progress: SwiftDataProgress?
    @Relationship(deleteRule: .cascade) public var bookmarks: [SwiftDataBookmark]
    @Relationship(deleteRule: .nullify) public var tags: [SwiftDataTag]
    
    public init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        coverImageData: Data? = nil,
        sourceURLPath: String,
        formatRawValue: String,
        contentTypeRawValue: String,
        totalPages: Int = 0,
        fileSize: Int64 = 0,
        importedAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverImageData = coverImageData
        self.sourceURLPath = sourceURLPath
        self.formatRawValue = formatRawValue
        self.contentTypeRawValue = contentTypeRawValue
        self.totalPages = totalPages
        self.fileSize = fileSize
        self.importedAt = importedAt
        self.lastOpenedAt = lastOpenedAt
        self.isFavorite = isFavorite
        self.metadataAutoTags = []
        self.bookmarks = []
        self.tags = []
    }
}

@Model
public final class SwiftDataProgress {
    @Attribute(.unique) public var id: UUID
    public var bookID: UUID
    public var currentPage: Int
    public var currentChapter: Int
    public var chapterTitle: String?
    public var scrollOffset: Double
    public var lastUpdated: Date
    public var totalReadTime: TimeInterval
    public var readCount: Int
    public var completionPercentage: Double
    
    @Relationship(inverse: \SwiftDataBook.progress) public var book: SwiftDataBook?
    
    public init(
        id: UUID = UUID(),
        bookID: UUID,
        currentPage: Int = 0,
        currentChapter: Int = 0,
        chapterTitle: String? = nil,
        scrollOffset: Double = 0,
        lastUpdated: Date = Date(),
        totalReadTime: TimeInterval = 0,
        readCount: Int = 0,
        completionPercentage: Double = 0
    ) {
        self.id = id
        self.bookID = bookID
        self.currentPage = currentPage
        self.currentChapter = currentChapter
        self.chapterTitle = chapterTitle
        self.scrollOffset = scrollOffset
        self.lastUpdated = lastUpdated
        self.totalReadTime = totalReadTime
        self.readCount = readCount
        self.completionPercentage = completionPercentage
    }
}

@Model
public final class SwiftDataBookmark {
    @Attribute(.unique) public var id: UUID
    public var bookID: UUID
    public var page: Int
    public var chapter: Int
    public var title: String
    public var note: String?
    public var createdAt: Date
    public var colorRawValue: String
    
    @Relationship(inverse: \SwiftDataBook.bookmarks) public var book: SwiftDataBook?
    
    public init(
        id: UUID = UUID(),
        bookID: UUID,
        page: Int,
        chapter: Int = 0,
        title: String = "",
        note: String? = nil,
        createdAt: Date = Date(),
        colorRawValue: String = "yellow"
    ) {
        self.id = id
        self.bookID = bookID
        self.page = page
        self.chapter = chapter
        self.title = title
        self.note = note
        self.createdAt = createdAt
        self.colorRawValue = colorRawValue
    }
}

@Model
public final class SwiftDataTag {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var colorHex: String?
    public var parentID: UUID?
    
    @Relationship(inverse: \SwiftDataBook.tags) public var books: [SwiftDataBook]
    
    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String? = nil,
        parentID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.parentID = parentID
        self.books = []
    }
}

// MARK: - SwiftData Stack

/// SwiftData 容器的全局管理
public final class SwiftDataStack: Sendable {
    public let container: ModelContainer
    
    public init(isStoredInMemoryOnly: Bool = false) throws {
        let schema = Schema([
            SwiftDataBook.self,
            SwiftDataProgress.self,
            SwiftDataBookmark.self,
            SwiftDataTag.self,
        ])
        
        let configuration = ModelConfiguration(
            "DuckReader",
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        
        self.container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
    
    /// 用于 SwiftUI Previews 的内存实例
    public static func preview() -> SwiftDataStack {
        try! SwiftDataStack(isStoredInMemoryOnly: true)
    }
    
    @MainActor
    public var mainContext: ModelContext {
        container.mainContext
    }
}

// MARK: - Domain ↔ SwiftData Mapping Extensions

extension SwiftDataBook {
    /// 转换为 Domain Book
    var toDomain: Book {
        Book(
            id: id,
            title: title,
            author: author,
            coverImageData: coverImageData,
            sourceURL: URL(fileURLWithPath: sourceURLPath),
            format: BookFormat(rawValue: formatRawValue) ?? .unknown,
            contentType: BookContentType(rawValue: contentTypeRawValue) ?? .comic,
            totalPages: totalPages,
            fileSize: fileSize,
            importedAt: importedAt,
            lastOpenedAt: lastOpenedAt,
            progress: progress?.toDomain,
            tags: tags.map { $0.toDomain },
            isFavorite: isFavorite,
            metadata: BookMetadata(
                language: metadataLanguage,
                publisher: metadataPublisher,
                publishedDate: metadataPublishedDate,
                isbn: metadataISBN,
                series: metadataSeries,
                seriesIndex: metadataSeriesIndex,
                descriptionText: metadataDescription,
                autoGeneratedTags: metadataAutoTags,
                aiSummary: metadataAISummary,
                rating: metadataRating
            )
        )
    }
    
    /// 从 Domain Book 更新
    func update(from book: Book) {
        self.title = book.title
        self.author = book.author
        self.coverImageData = book.coverImageData
        self.sourceURLPath = book.sourceURL.path()
        self.formatRawValue = book.format.rawValue
        self.contentTypeRawValue = book.contentType.rawValue
        self.totalPages = book.totalPages
        self.fileSize = book.fileSize
        self.importedAt = book.importedAt
        self.lastOpenedAt = book.lastOpenedAt
        self.isFavorite = book.isFavorite
        self.metadataLanguage = book.metadata.language
        self.metadataPublisher = book.metadata.publisher
        self.metadataPublishedDate = book.metadata.publishedDate
        self.metadataISBN = book.metadata.isbn
        self.metadataSeries = book.metadata.series
        self.metadataSeriesIndex = book.metadata.seriesIndex
        self.metadataDescription = book.metadata.descriptionText
        self.metadataAutoTags = book.metadata.autoGeneratedTags
        self.metadataAISummary = book.metadata.aiSummary
        self.metadataRating = book.metadata.rating
    }
    
    static func from(_ book: Book) -> SwiftDataBook {
        let model = SwiftDataBook(
            id: book.id,
            title: book.title,
            author: book.author,
            coverImageData: book.coverImageData,
            sourceURLPath: book.sourceURL.path(),
            formatRawValue: book.format.rawValue,
            contentTypeRawValue: book.contentType.rawValue,
            totalPages: book.totalPages,
            fileSize: book.fileSize,
            importedAt: book.importedAt,
            lastOpenedAt: book.lastOpenedAt,
            isFavorite: book.isFavorite
        )
        model.metadataLanguage = book.metadata.language
        model.metadataPublisher = book.metadata.publisher
        model.metadataPublishedDate = book.metadata.publishedDate
        model.metadataISBN = book.metadata.isbn
        model.metadataSeries = book.metadata.series
        model.metadataSeriesIndex = book.metadata.seriesIndex
        model.metadataDescription = book.metadata.descriptionText
        model.metadataAutoTags = book.metadata.autoGeneratedTags
        model.metadataAISummary = book.metadata.aiSummary
        model.metadataRating = book.metadata.rating
        return model
    }
}

extension SwiftDataProgress {
    var toDomain: ReadingProgress {
        ReadingProgress(
            currentPage: currentPage,
            currentChapter: currentChapter,
            chapterTitle: chapterTitle,
            scrollOffset: scrollOffset,
            lastUpdated: lastUpdated,
            totalReadTime: totalReadTime,
            readCount: readCount,
            completionPercentage: completionPercentage
        )
    }
    
    static func from(_ progress: ReadingProgress, bookID: UUID) -> SwiftDataProgress {
        SwiftDataProgress(
            bookID: bookID,
            currentPage: progress.currentPage,
            currentChapter: progress.currentChapter,
            chapterTitle: progress.chapterTitle,
            scrollOffset: progress.scrollOffset,
            lastUpdated: progress.lastUpdated,
            totalReadTime: progress.totalReadTime,
            readCount: progress.readCount,
            completionPercentage: progress.completionPercentage
        )
    }
}

extension SwiftDataBookmark {
    var toDomain: Bookmark {
        Bookmark(
            id: id,
            bookID: bookID,
            page: page,
            chapter: chapter,
            title: title,
            note: note,
            createdAt: createdAt,
            color: BookmarkColor(rawValue: colorRawValue) ?? .yellow
        )
    }
    
    static func from(_ bookmark: Bookmark) -> SwiftDataBookmark {
        SwiftDataBookmark(
            id: bookmark.id,
            bookID: bookmark.bookID,
            page: bookmark.page,
            chapter: bookmark.chapter,
            title: bookmark.title,
            note: bookmark.note,
            createdAt: bookmark.createdAt,
            colorRawValue: bookmark.color.rawValue
        )
    }
}

extension SwiftDataTag {
    var toDomain: Tag {
        Tag(id: id, name: name, color: colorHex, parentID: parentID)
    }
    
    static func from(_ tag: Tag) -> SwiftDataTag {
        SwiftDataTag(id: tag.id, name: tag.name, colorHex: tag.color, parentID: tag.parentID)
    }
}
