import Foundation

/// 阅读进度模型。可读可写、轻量、支持 CloudKit 同步。
public struct ReadingProgress: Codable, Hashable, Sendable {
    public var currentPage: Int
    public var currentChapter: Int
    public var chapterTitle: String?
    public var scrollOffset: Double           // 0-1, 在当前页内的滚动偏移
    public var lastUpdated: Date
    public var totalReadTime: TimeInterval    // 累计阅读时长（秒）
    public var readCount: Int                 // 打开次数
    public var completionPercentage: Double   // 整体完成度 0-1
    
    public init(
        currentPage: Int = 0,
        currentChapter: Int = 0,
        chapterTitle: String? = nil,
        scrollOffset: Double = 0,
        lastUpdated: Date = Date(),
        totalReadTime: TimeInterval = 0,
        readCount: Int = 0,
        completionPercentage: Double = 0
    ) {
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

/// 书签
public struct Bookmark: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let bookID: UUID
    public var page: Int
    public var chapter: Int
    public var title: String
    public var note: String?
    public var createdAt: Date
    public var color: BookmarkColor
    
    public init(
        id: UUID = UUID(),
        bookID: UUID,
        page: Int,
        chapter: Int = 0,
        title: String = "",
        note: String? = nil,
        createdAt: Date = Date(),
        color: BookmarkColor = .yellow
    ) {
        self.id = id
        self.bookID = bookID
        self.page = page
        self.chapter = chapter
        self.title = title
        self.note = note
        self.createdAt = createdAt
        self.color = color
    }
}

public enum BookmarkColor: String, CaseIterable, Codable, Sendable {
    case red, orange, yellow, green, blue, purple
}

/// 标签
public struct Tag: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var color: String?   // hex color
    public var parentID: UUID?  // 层级标签
    
    public init(id: UUID = UUID(), name: String, color: String? = nil, parentID: UUID? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.parentID = parentID
    }
}

/// 章节（用于小说或分章漫画）
public struct Chapter: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let bookID: UUID
    public var index: Int
    public var title: String
    public var startPage: Int
    public var pageCount: Int
    public var wordCount: Int
    
    public init(
        id: UUID = UUID(),
        bookID: UUID,
        index: Int,
        title: String,
        startPage: Int = 0,
        pageCount: Int = 0,
        wordCount: Int = 0
    ) {
        self.id = id
        self.bookID = bookID
        self.index = index
        self.title = title
        self.startPage = startPage
        self.pageCount = pageCount
        self.wordCount = wordCount
    }
}

/// 单页数据（漫画图像或小说渲染页）
public struct PageData: Identifiable, Sendable {
    public let id: Int          // 页码 (0-based)
    public let bookID: UUID
    public let imageData: Data? // 漫画：已解码的图像数据
    public let textContent: String? // 小说：文本内容
    public let width: Int
    public let height: Int
    public let isDoublePage: Bool
    public let detectedPanels: [PanelRegion]?
    
    public init(
        id: Int,
        bookID: UUID,
        imageData: Data? = nil,
        textContent: String? = nil,
        width: Int = 0,
        height: Int = 0,
        isDoublePage: Bool = false,
        detectedPanels: [PanelRegion]? = nil
    ) {
        self.id = id
        self.bookID = bookID
        self.imageData = imageData
        self.textContent = textContent
        self.width = width
        self.height = height
        self.isDoublePage = isDoublePage
        self.detectedPanels = detectedPanels
    }
}

/// 面板区域（用于逐面板阅读模式）
public struct PanelRegion: Codable, Hashable, Sendable {
    public let index: Int
    public let normalizedRect: NormalizedRect   // 0-1 坐标系
    public let readingOrder: Int
    
    public init(index: Int, normalizedRect: NormalizedRect, readingOrder: Int) {
        self.index = index
        self.normalizedRect = normalizedRect
        self.readingOrder = readingOrder
    }
}

public struct NormalizedRect: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// 阅读统计
public struct ReadingStats: Codable, Hashable, Sendable {
    public var totalBooksRead: Int
    public var totalPagesRead: Int
    public var totalReadingTime: TimeInterval
    public var averageReadingSpeed: Double       // 页/分钟
    public var dailyStreak: Int                  // 连续阅读天数
    public var lastReadDate: Date?
    public var weeklyStats: [DayStats]
    public var achievements: [Achievement]
    
    public init(
        totalBooksRead: Int = 0,
        totalPagesRead: Int = 0,
        totalReadingTime: TimeInterval = 0,
        averageReadingSpeed: Double = 0,
        dailyStreak: Int = 0,
        lastReadDate: Date? = nil,
        weeklyStats: [DayStats] = [],
        achievements: [Achievement] = []
    ) {
        self.totalBooksRead = totalBooksRead
        self.totalPagesRead = totalPagesRead
        self.totalReadingTime = totalReadingTime
        self.averageReadingSpeed = averageReadingSpeed
        self.dailyStreak = dailyStreak
        self.lastReadDate = lastReadDate
        self.weeklyStats = weeklyStats
        self.achievements = achievements
    }
}

public struct DayStats: Codable, Hashable, Sendable {
    public let date: Date
    public var pagesRead: Int
    public var timeSpent: TimeInterval
}

public struct Achievement: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String
    public let iconName: String
    public var unlockedAt: Date?
    public var progress: Double  // 0-1
    
    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        iconName: String,
        unlockedAt: Date? = nil,
        progress: Double = 0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.unlockedAt = unlockedAt
        self.progress = progress
    }
}
