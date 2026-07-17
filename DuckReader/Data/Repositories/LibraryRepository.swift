import Foundation
import SwiftData

// MARK: - Library Repository

/// 图书馆数据仓库：实现 LibraryRepositoryProtocol。
/// 封装 SwiftData 操作，所有读写通过 @MainActor 保证线程安全。
@MainActor
public final class LibraryRepository: LibraryRepositoryProtocol, Sendable {
    
    private let modelContext: ModelContext
    
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Fetch
    
    public func fetchAll(sortBy: LibrarySortOption = .recentlyOpened) async throws -> [Book] {
        let descriptor = FetchDescriptor<SwiftDataBook>(
            sortBy: [sortBy.sortDescriptor]
        )
        let results = try modelContext.fetch(descriptor)
        return results.map { $0.toDomain }
    }
    
    public func fetchByTag(_ tag: Tag) async throws -> [Book] {
        // 用 predicate 过滤标签
        let tagID = tag.id
        let descriptor = FetchDescriptor<SwiftDataBook>(
            predicate: #Predicate { book in
                book.tags.contains(where: { $0.id == tagID })
            },
            sortBy: [SortDescriptor(\.title)]
        )
        let results = try modelContext.fetch(descriptor)
        return results.map { $0.toDomain }
    }
    
    public func search(query: String) async throws -> [Book] {
        let lowerQuery = query.lowercased()
        let descriptor = FetchDescriptor<SwiftDataBook>(
            predicate: #Predicate { book in
                book.title.localizedStandardContains(lowerQuery) ||
                (book.author?.localizedStandardContains(lowerQuery) ?? false) ||
                book.metadataSeries?.localizedStandardContains(lowerQuery) ?? false
            },
            sortBy: [SortDescriptor(\.title)]
        )
        let results = try modelContext.fetch(descriptor)
        return results.map { $0.toDomain }
    }
    
    // MARK: - CRUD
    
    public func add(_ book: Book) async throws {
        let existing = try await findExisting(id: book.id)
        if let existing = existing {
            existing.update(from: book)
        } else {
            let model = SwiftDataBook.from(book)
            modelContext.insert(model)
        }
        try modelContext.save()
    }
    
    public func remove(_ book: Book) async throws {
        guard let model = try await findExisting(id: book.id) else {
            return
        }
        modelContext.delete(model)
        try modelContext.save()
    }
    
    public func update(_ book: Book) async throws {
        if let model = try await findExisting(id: book.id) {
            model.update(from: book)
            try modelContext.save()
        }
    }
    
    // MARK: - Progress
    
    public func fetchProgress(for bookID: UUID) async throws -> ReadingProgress? {
        let descriptor = FetchDescriptor<SwiftDataProgress>(
            predicate: #Predicate { $0.bookID == bookID }
        )
        let results = try modelContext.fetch(descriptor)
        return results.first?.toDomain
    }
    
    public func saveProgress(_ progress: ReadingProgress, for bookID: UUID) async throws {
        let descriptor = FetchDescriptor<SwiftDataProgress>(
            predicate: #Predicate { $0.bookID == bookID }
        )
        let results = try modelContext.fetch(descriptor)
        
        if let existing = results.first {
            existing.currentPage = progress.currentPage
            existing.currentChapter = progress.currentChapter
            existing.chapterTitle = progress.chapterTitle
            existing.scrollOffset = progress.scrollOffset
            existing.lastUpdated = progress.lastUpdated
            existing.totalReadTime = progress.totalReadTime
            existing.readCount = progress.readCount
            existing.completionPercentage = progress.completionPercentage
        } else {
            let new = SwiftDataProgress.from(progress, bookID: bookID)
            modelContext.insert(new)
        }
        
        // 同步更新 Book 的 lastOpenedAt
        if let book = try await findExisting(id: bookID) {
            book.lastOpenedAt = Date()
        }
        
        try modelContext.save()
    }
    
    // MARK: - Bookmarks
    
    public func fetchBookmarks(for bookID: UUID) async throws -> [Bookmark] {
        let descriptor = FetchDescriptor<SwiftDataBookmark>(
            predicate: #Predicate { $0.bookID == bookID },
            sortBy: [SortDescriptor(\.page)]
        )
        let results = try modelContext.fetch(descriptor)
        return results.map { $0.toDomain }
    }
    
    public func saveBookmark(_ bookmark: Bookmark) async throws {
        // Check for existing
        let descriptor = FetchDescriptor<SwiftDataBookmark>(
            predicate: #Predicate { $0.id == bookmark.id }
        )
        let results = try modelContext.fetch(descriptor)
        
        if let existing = results.first {
            existing.page = bookmark.page
            existing.chapter = bookmark.chapter
            existing.title = bookmark.title
            existing.note = bookmark.note
            existing.colorRawValue = bookmark.color.rawValue
        } else {
            let model = SwiftDataBookmark.from(bookmark)
            modelContext.insert(model)
        }
        try modelContext.save()
    }
    
    public func removeBookmark(_ bookmark: Bookmark) async throws {
        let descriptor = FetchDescriptor<SwiftDataBookmark>(
            predicate: #Predicate { $0.id == bookmark.id }
        )
        if let model = try modelContext.fetch(descriptor).first {
            modelContext.delete(model)
            try modelContext.save()
        }
    }
    
    // MARK: - Private
    
    private func findExisting(id: UUID) async throws -> SwiftDataBook? {
        let descriptor = FetchDescriptor<SwiftDataBook>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }
}

// MARK: - Helpers

extension LibrarySortOption {
    var sortDescriptor: SortDescriptor<SwiftDataBook> {
        switch self {
        case .title:
            SortDescriptor(\.title)
        case .author:
            SortDescriptor(\.author, order: .forward)
        case .recentlyOpened:
            SortDescriptor(\.lastOpenedAt, order: .reverse)
        case .recentlyAdded:
            SortDescriptor(\.importedAt, order: .reverse)
        case .progress:
            SortDescriptor(\.lastOpenedAt, order: .reverse)
        }
    }
}
