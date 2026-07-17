import Foundation
import SwiftUI
import Combine

// MARK: - Enhanced Metadata

/// Full metadata for a book, extending BookMetadata.
public struct EnhancedMetadata: Codable, Equatable, Sendable {
    public var title: String = ""
    public var author: String?
    public var publisher: String?
    public var publishDate: Date?
    public var language: String?
    public var isbn: String?
    public var tags: [String] = []
    public var series: String?
    public var seriesIndex: Double?    // e.g. 3.0 = volume 3
    public var summary: String?
    public var coverURL: URL?
    public var pageCount: Int?
    public var fileSize: Int64?
    public var format: String?
    public var rating: Double?         // 0-5
    public var calibreID: Int?
    public var identifiers: [String: String] = [:]  // e.g. ["goodreads": "12345"]

    public var displayAuthor: String {
        author ?? String(localized: "metadata.unknownAuthor")
    }

    public var displaySeries: String? {
        guard let series = series else { return nil }
        if let idx = seriesIndex {
            return "\(series) #\(String(format: "%.1f", idx))"
        }
        return series
    }

    public var formattedFileSize: String {
        guard let size = fileSize else { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    public init() {}
}

// MARK: - Metadata Fetcher

/// Fetches metadata from network sources (Google Books, OpenLibrary, etc.)
public struct MetadataFetcher: Sendable {

    /// Fetch metadata by ISBN.
    public func fetchByISBN(_ isbn: String) async throws -> EnhancedMetadata? {
        // Google Books API
        let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=isbn:\(isbn)")!
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]],
              let volumeInfo = items.first?["volumeInfo"] as? [String: Any] else {
            return nil
        }

        var meta = EnhancedMetadata()
        meta.title = volumeInfo["title"] as? String ?? ""
        meta.author = (volumeInfo["authors"] as? [String])?.first
        meta.publisher = volumeInfo["publisher"] as? String
        meta.language = volumeInfo["language"] as? String
        meta.isbn = isbn
        meta.summary = volumeInfo["description"] as? String
        meta.pageCount = volumeInfo["pageCount"] as? Int

        if let imageLinks = volumeInfo["imageLinks"] as? [String: String],
           let thumbnail = imageLinks["thumbnail"] ?? imageLinks["smallThumbnail"] {
            meta.coverURL = URL(string: thumbnail.replacingOccurrences(of: "http://", with: "https://"))
        }

        if let identifiers = volumeInfo["industryIdentifiers"] as? [[String: String]] {
            for id in identifiers {
                if let type = id["type"], let value = id["identifier"] {
                    meta.identifiers[type.lowercased()] = value
                }
            }
        }

        return meta
    }

    /// Fetch metadata by title + author.
    public func fetchByTitle(_ title: String, author: String? = nil) async throws -> EnhancedMetadata? {
        var query = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        if let author = author {
            query += "+inauthor:" + (author.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? author)
        }
        let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=\(query)&maxResults=1")!
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]],
              let volumeInfo = items.first?["volumeInfo"] as? [String: Any] else {
            return nil
        }

        var meta = EnhancedMetadata()
        meta.title = volumeInfo["title"] as? String ?? title
        meta.author = (volumeInfo["authors"] as? [String])?.first
        meta.publisher = volumeInfo["publisher"] as? String
        meta.summary = volumeInfo["description"] as? String
        return meta
    }

    /// Search for cover image URL by ISBN/title.
    public func fetchCoverURL(isbn: String? = nil, title: String? = nil) async -> URL? {
        if let isbn = isbn {
            // OpenLibrary covers
            return URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg")
        }
        return nil
    }
}

// MARK: - Metadata Store

/// Local metadata database that persists alongside the library.
@MainActor
public final class MetadataStore: ObservableObject, Sendable {

    @Published public private(set) var metadata: [UUID: EnhancedMetadata] = [:]
    @Published public var sortOrder: MetadataSortOrder = .title
    @Published public var filterTags: Set<String> = []
    @Published public var filterSeries: String?

    public enum MetadataSortOrder: String, CaseIterable, Sendable {
        case title, author, dateAdded, lastRead, series, rating

        public var displayName: String {
            switch self {
            case .title: String(localized: "metadata.sortTitle")
            case .author: String(localized: "metadata.sortAuthor")
            case .dateAdded: String(localized: "metadata.sortDateAdded")
            case .lastRead: String(localized: "metadata.sortLastRead")
            case .series: String(localized: "metadata.sortSeries")
            case .rating: String(localized: "metadata.sortRating")
            }
        }
    }

    private let storageURL: URL
    private let fetcher = MetadataFetcher()

    public nonisolated init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storageURL = docs.appendingPathComponent("DuckReader/enhanced_metadata.json")
        Task { @MainActor in self.load() }
    }

    // MARK: - Access

    public subscript(bookID: UUID) -> EnhancedMetadata {
        get { metadata[bookID] ?? EnhancedMetadata() }
        set {
            metadata[bookID] = newValue
            save()
        }
    }

    public func metadata(for bookID: UUID) -> EnhancedMetadata {
        metadata[bookID] ?? EnhancedMetadata()
    }

    // MARK: - Auto-fetch

    public func autoFetch(for bookID: UUID, book: Book) async {
        var meta = metadata[bookID] ?? EnhancedMetadata()
        meta.title = book.title
        meta.author = book.author

        // Try ISBN first
        if let isbn = meta.isbn, let fetched = try? await fetcher.fetchByISBN(isbn) {
            merge(&meta, with: fetched)
        } else {
            // Try title + author
            if let fetched = try? await fetcher.fetchByTitle(book.title, author: book.author) {
                merge(&meta, with: fetched)
            }
        }

        metadata[bookID] = meta
        save()
    }

    /// Auto-fetch for all books that lack metadata.
    public func autoFetchAll(books: [Book]) async {
        for book in books where metadata[book.id]?.summary == nil {
            await autoFetch(for: book.id, book: book)
        }
    }

    // MARK: - Batch Edit

    public func batchSetTag(_ tag: String, for bookIDs: Set<UUID>) {
        for id in bookIDs {
            var meta = metadata[id] ?? EnhancedMetadata()
            if !meta.tags.contains(tag) {
                meta.tags.append(tag)
                metadata[id] = meta
            }
        }
        save()
    }

    public func batchSetSeries(_ series: String, for bookIDs: Set<UUID>) {
        for id in bookIDs {
            var meta = metadata[id] ?? EnhancedMetadata()
            meta.series = series
            metadata[id] = meta
        }
        save()
    }

    public func batchSetAuthor(_ author: String, for bookIDs: Set<UUID>) {
        for id in bookIDs {
            var meta = metadata[id] ?? EnhancedMetadata()
            meta.author = author
            metadata[id] = meta
        }
        save()
    }

    // MARK: - Query

    /// All unique tags across the library.
    public var allTags: [String] {
        Array(Set(metadata.values.flatMap { $0.tags })).sorted()
    }

    /// All unique series.
    public var allSeries: [String] {
        metadata.values.compactMap { $0.series }.uniqued().sorted()
    }

    /// Filtered and sorted book IDs.
    public func filteredBookIDs(sortBy: MetadataSortOrder = .title) -> [UUID] {
        var result = Array(metadata.keys)

        // Tag filter
        if !filterTags.isEmpty {
            result = result.filter { id in
                let tags = Set(metadata[id]?.tags ?? [])
                return !filterTags.isDisjoint(with: tags)
            }
        }

        // Series filter
        if let series = filterSeries {
            result = result.filter { metadata[$0]?.series == series }
        }

        // Sort
        switch sortBy {
        case .title:
            result.sort { (metadata[$0]?.title ?? "") < (metadata[$1]?.title ?? "") }
        case .author:
            result.sort { (metadata[$0]?.author ?? "") < (metadata[$1]?.author ?? "") }
        case .series:
            result.sort {
                let s1 = metadata[$0]?.series ?? ""
                let s2 = metadata[$1]?.series ?? ""
                if s1 == s2 {
                    return (metadata[$0]?.seriesIndex ?? 0) < (metadata[$1]?.seriesIndex ?? 0)
                }
                return s1 < s2
            }
        case .rating:
            result.sort { (metadata[$0]?.rating ?? 0) > (metadata[$1]?.rating ?? 0) }
        default:
            break
        }

        return result
    }

    /// Group books by series.
    public var seriesGroups: [(series: String, count: Int, books: [UUID])] {
        var groups: [String: [UUID]] = [:]
        for (id, meta) in metadata {
            if let series = meta.series {
                groups[series, default: []].append(id)
            }
        }
        return groups.map { (series: $0.key, count: $0.value.count, books: $0.value) }
            .sorted { $0.series < $1.series }
    }

    // MARK: - Private

    private func merge(_ target: inout EnhancedMetadata, with source: EnhancedMetadata) {
        if target.summary == nil { target.summary = source.summary }
        if target.publisher == nil { target.publisher = source.publisher }
        if target.pageCount == nil { target.pageCount = source.pageCount }
        if target.coverURL == nil { target.coverURL = source.coverURL }
        if target.isbn == nil { target.isbn = source.isbn }
        for (k, v) in source.identifiers where target.identifiers[k] == nil {
            target.identifiers[k] = v
        }
    }

    private func save() {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[MetadataStore] Save failed: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            metadata = try JSONDecoder().decode([UUID: EnhancedMetadata].self, from: data)
        } catch {
            print("[MetadataStore] Load failed: \(error)")
        }
    }
}

// MARK: - Array Uniqued

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
