import Foundation
import SwiftUI

// MARK: - Annotation Models

/// A highlight or note annotation in a book.
public struct Annotation: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let bookID: UUID
    public let chapterIndex: Int
    public let chapterTitle: String?
    public let text: String                    // The highlighted text
    public let note: String?                   // User's note on this highlight
    public let color: AnnotationColor
    public let location: AnnotationLocation     // CFI or page-position
    public let createdAt: Date
    public let updatedAt: Date

    public enum AnnotationColor: String, Codable, Sendable, CaseIterable {
        case yellow, green, blue, pink, purple, orange

        public var swiftUIColor: Color {
            switch self {
            case .yellow: .yellow.opacity(0.35)
            case .green: .green.opacity(0.3)
            case .blue: .blue.opacity(0.3)
            case .pink: .pink.opacity(0.3)
            case .purple: .purple.opacity(0.3)
            case .orange: .orange.opacity(0.35)
            }
        }

        public var displayName: String {
            switch self {
            case .yellow: String(localized: "annotation.colorYellow")
            case .green: String(localized: "annotation.colorGreen")
            case .blue: String(localized: "annotation.colorBlue")
            case .pink: String(localized: "annotation.colorPink")
            case .purple: String(localized: "annotation.colorPurple")
            case .orange: String(localized: "annotation.colorOrange")
            }
        }
    }

    public enum AnnotationLocation: Codable, Equatable, Sendable {
        case cfi(String)           // EPUB CFI
        case pageOffset(Int)       // Page number + character offset
        case normalized(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)

        public var cfiValue: String? {
            if case .cfi(let v) = self { return v }
            return nil
        }
    }

    public init(
        id: UUID = UUID(),
        bookID: UUID,
        chapterIndex: Int,
        chapterTitle: String? = nil,
        text: String,
        note: String? = nil,
        color: AnnotationColor = .yellow,
        location: AnnotationLocation,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.text = text
        self.note = note
        self.color = color
        self.location = location
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Export Format

public enum ExportFormat: String, CaseIterable, Sendable {
    case markdown = "Markdown"
    case json = "JSON"
    case csv = "CSV"
    case html = "HTML"

    public var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .json: return "json"
        case .csv: return "csv"
        case .html: return "html"
        }
    }

    public var mimeType: String {
        switch self {
        case .markdown: return "text/markdown"
        case .json: return "application/json"
        case .csv: return "text/csv"
        case .html: return "text/html"
        }
    }
}

// MARK: - Annotation Export Engine

/// Exports highlights and notes to multiple formats for integration
/// with external tools (Readwise, Notion, Obsidian, etc.).
public struct AnnotationExportEngine: Sendable {

    // MARK: - Markdown Export

    public func exportAsMarkdown(
        annotations: [Annotation],
        bookTitle: String,
        author: String? = nil
    ) -> String {
        var md = "# Highlights & Notes\n\n"
        md += "**\(bookTitle)**"
        if let author = author { md += " by *\(author)*" }
        md += "\n\n---\n\n"

        let grouped = Dictionary(grouping: annotations) { $0.chapterIndex }
        let sortedChapters = grouped.keys.sorted()

        for chapterIndex in sortedChapters {
            guard let chapterAnnotations = grouped[chapterIndex] else { continue }
            let chapterTitle = chapterAnnotations.first?.chapterTitle ?? "Chapter \(chapterIndex + 1)"
            md += "## \(chapterTitle)\n\n"

            for annotation in chapterAnnotations {
                md += "> \(annotation.text.replacingOccurrences(of: "\n", with: "\n> "))\n\n"
                if let note = annotation.note {
                    md += "**Note:** \(note)\n\n"
                }
                md += "— *\(colorTag(for: annotation.color))* | \(dateFormatter.string(from: annotation.createdAt))\n\n"
            }
        }

        return md
    }

    /// Readwise-compatible CSV format.
    public func exportAsReadwiseCSV(annotations: [Annotation], bookTitle: String) -> String {
        var csv = "Title,Author,Highlight,Note,Location,Date\n"
        for a in annotations {
            let highlight = a.text.replacingOccurrences(of: "\"", with: "\"\"")
            let note = (a.note ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let loc = locationString(a.location)
            csv += "\"\(bookTitle)\",\"\",\"\(highlight)\",\"\(note)\",\"\(loc)\",\"\(ISO8601DateFormatter().string(from: a.createdAt))\"\n"
        }
        return csv
    }

    /// JSON export (compatible with Readwise API format).
    public func exportAsJSON(annotations: [Annotation], bookTitle: String, author: String?) -> Data? {
        let export = AnnotationExport(
            title: bookTitle,
            author: author,
            highlights: annotations.map { a in
                AnnotationExportItem(
                    text: a.text,
                    note: a.note,
                    location: locationString(a.location),
                    color: a.color.rawValue,
                    createdDate: ISO8601DateFormatter().string(from: a.createdAt)
                )
            }
        )
        return try? JSONEncoder().encode(export)
    }

    /// Styled HTML export.
    public func exportAsHTML(
        annotations: [Annotation],
        bookTitle: String,
        author: String? = nil
    ) -> String {
        var html = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(bookTitle) - Highlights</title>
        <style>
        body { font-family: system-ui, -apple-system, sans-serif; max-width: 720px; margin: 0 auto; padding: 24px; color: #1a1a1a; }
        h1 { font-size: 1.6em; margin-bottom: 4px; }
        .author { color: #666; margin-bottom: 24px; }
        .highlight { background: #FFF9C4; padding: 12px; border-left: 4px solid #FFC107; margin: 12px 0; border-radius: 6px; }
        .highlight.green { background: #E8F5E9; border-left-color: #4CAF50; }
        .highlight.blue { background: #E3F2FD; border-left-color: #2196F3; }
        .highlight.pink { background: #FCE4EC; border-left-color: #E91E63; }
        .highlight-text { font-style: italic; margin-bottom: 8px; }
        .highlight-note { color: #555; font-size: 0.92em; }
        .highlight-meta { color: #999; font-size: 0.78em; margin-top: 8px; }
        hr { margin: 24px 0; border: none; border-top: 1px solid #eee; }
        </style></head><body>
        <h1>\(bookTitle)</h1>
        """
        if let author = author { html += "<p class=\"author\">\(author)</p>" }

        let grouped = Dictionary(grouping: annotations) { $0.chapterIndex }
        for chapterIndex in grouped.keys.sorted() {
            guard let list = grouped[chapterIndex] else { continue }
            html += "<h2>\(list.first?.chapterTitle ?? "Chapter \(chapterIndex+1)")</h2>"
            for a in list {
                html += "<div class=\"highlight \(a.color.rawValue)\">"
                html += "<p class=\"highlight-text\">\(a.text)</p>"
                if let note = a.note { html += "<p class=\"highlight-note\">Note: \(note)</p>" }
                html += "<p class=\"highlight-meta\">\(dateFormatter.string(from: a.createdAt))</p>"
                html += "</div>"
            }
        }
        html += "</body></html>"
        return html
    }
   
    // MARK: - Obsidian / Knowledge-Base Export
    
    /// YAML frontmatter Markdown export (Obsidian, Logseq 兼容)
    /// 包含完整元数据：作者、标签、ISBN、阅读进度、笔记数
    public func exportAsObsidianMarkdown(
        annotations: [Annotation],
        book: ObsidianBookMetadata
    ) -> String {
        var md = "---\n"
        md += "title: \"\(book.title)\"\n"
        if let author = book.author { md += "author: \"\(author)\"\n" }
        if let isbn = book.isbn { md += "isbn: \"\(isbn)\"\n" }
        if !book.tags.isEmpty {
            md += "tags: [\(book.tags.map { "\"\($0)\"" }.joined(separator: ", "))]\n"
        }
        md += "source: \"DuckReader\"\n"
        md += "created: \"\(dateFormatter.string(from: book.dateAdded))\"\n"
        if let progress = book.readingProgress {
            md += "progress: \(String(format: "%.0f", progress * 100))%\n"
        }
        md += "highlights: \(annotations.count)\n"
        md += "notes: \(annotations.filter { $0.note != nil }.count)\n"
        md += "---\n\n"
        md += "# \(book.title)\n\n"
        if let author = book.author { md += "by **\(author)**\n\n" }
        md += "---\n\n"
        
        let grouped = Dictionary(grouping: annotations) { $0.chapterIndex }
        for chapterIndex in grouped.keys.sorted() {
            guard let list = grouped[chapterIndex] else { continue }
            let chTitle = list.first?.chapterTitle ?? "Chapter \(chapterIndex + 1)"
            md += "## \(chTitle)\n\n"
            for a in list {
                md += "- [\(a.color.rawValue)] \(a.text.replacingOccurrences(of: "\n", with: " "))"
                if let note = a.note {
                    md += "\n    - 💭 \(note)"
                }
                md += "\n"
            }
            md += "\n"
        }
        return md
    }
    
    /// Readwise 标准 CSV 格式导出（可直接导入 readwise.io/bulk）
    public func exportAsReadwiseCSV(
        annotations: [Annotation],
        bookTitle: String,
        author: String?
    ) -> String {
        var csv = "Title,Author,Highlight,Note,Location,Date\n"
        let isoFormatter = ISO8601DateFormatter()
        for a in annotations {
            let highlight = a.text.replacingOccurrences(of: "\"", with: "\"\"")
            let note = (a.note ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let loc = locationString(a.location)
            let authorField = author?.replacingOccurrences(of: "\"", with: "\"\"") ?? ""
            csv += "\"\(bookTitle)\",\"\(authorField)\",\"\(highlight)\",\"\(note)\",\"\(loc)\",\"\(isoFormatter.string(from: a.createdAt))\"\n"
        }
        return csv
    }
    
    /// 整书导出：将书的元数据 + 全部标注打包为结构化 Markdown
    public func exportFullBook(
        annotations: [Annotation],
        book: ObsidianBookMetadata
    ) -> String {
        exportAsObsidianMarkdown(annotations: annotations, book: book)
    }
    
    /// 批量导出多本书为合集 Markdown（索引页 + 单页）
    public func exportBatch(
        books: [(metadata: ObsidianBookMetadata, annotations: [Annotation])],
        title: String = "DuckReader Export"
    ) -> String {
        var md = "# \(title)\n\n"
        md += "> Exported on \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))\n\n"
        md += "## Index\n\n"
        md += "| # | Book | Highlights | Notes | Progress |\n"
        md += "|---|------|------------|-------|----------|\n"
        for (i, (meta, anns)) in books.enumerated() {
            md += "| \(i + 1) | \(meta.title) | \(anns.count) | \(anns.filter { $0.note != nil }.count) | \(String(format: "%.0f%%", (meta.readingProgress ?? 0) * 100)) |\n"
        }
        md += "\n---\n\n"
        for (meta, anns) in books {
            md += exportAsObsidianMarkdown(annotations: anns, book: meta)
            md += "\n---\n\n"
        }
        return md
    }

    // MARK: - Helpers

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }

    private func colorTag(for color: Annotation.AnnotationColor) -> String {
        switch color {
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .pink: return "Pink"
        case .purple: return "Purple"
        case .orange: return "Orange"
        }
    }

    private func locationString(_ loc: Annotation.AnnotationLocation) -> String {
        switch loc {
        case .cfi(let v): return v
        case .pageOffset(let off): return "Page \(off)"
        case .normalized(let x, let y, _, _):
            return String(format: "%.1f%%, %.1f%%", x * 100, y * 100)
        }
    }
}

// MARK: - Export DTOs

// MARK: - Obsidian Metadata Model

/// 用于 Obsidian/知识库导出的书籍元数据
public struct ObsidianBookMetadata: Sendable {
    public let title: String
    public let author: String?
    public let isbn: String?
    public let tags: [String]
    public let dateAdded: Date
    public let readingProgress: Double?   // 0.0...1.0
    
    public init(
        title: String,
        author: String? = nil,
        isbn: String? = nil,
        tags: [String] = [],
        dateAdded: Date = Date(),
        readingProgress: Double? = nil
    ) {
        self.title = title
        self.author = author
        self.isbn = isbn
        self.tags = tags
        self.dateAdded = dateAdded
        self.readingProgress = readingProgress
    }
    
    /// 从 Book 模型快速构建
    public init(from book: Book) {
        self.title = book.title
        self.author = book.author
        self.isbn = book.metadata.isbn
        self.tags = book.tags.map(\.name)
        self.dateAdded = book.importedAt
        self.readingProgress = book.progress?.completionPercentage
    }
}

private struct AnnotationExport: Codable {
    let title: String
    let author: String?
    let highlights: [AnnotationExportItem]
}

private struct AnnotationExportItem: Codable {
    let text: String
    let note: String?
    let location: String
    let color: String
    let createdDate: String
}

// MARK: - Annotation Store

/// Manages annotations per book with persistence and export.
@MainActor
public final class AnnotationStore: ObservableObject, Sendable {

    @Published public private(set) var annotations: [Annotation] = []
    @Published public var selectedExportFormat: ExportFormat = .markdown

    private let storageURL: URL
    private let exportEngine = AnnotationExportEngine()

    public nonisolated init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storageURL = docs.appendingPathComponent("DuckReader/annotations.json")

        Task { @MainActor in
            self.load()
        }
    }

    // MARK: - CRUD

    public func addAnnotation(_ annotation: Annotation) {
        annotations.append(annotation)
        save()
    }

    public func updateNote(id: UUID, note: String) {
        if let i = annotations.firstIndex(where: { $0.id == id }) {
            var updated = annotations[i]
            updated = Annotation(
                id: updated.id,
                bookID: updated.bookID,
                chapterIndex: updated.chapterIndex,
                chapterTitle: updated.chapterTitle,
                text: updated.text,
                note: note,
                color: updated.color,
                location: updated.location,
                createdAt: updated.createdAt,
                updatedAt: Date()
            )
            annotations[i] = updated
            save()
        }
    }

    public func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
        save()
    }

    public func annotations(for bookID: UUID) -> [Annotation] {
        annotations.filter { $0.bookID == bookID }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Count of highlights for a book.
    public func highlightCount(for bookID: UUID) -> Int {
        annotations.filter { $0.bookID == bookID && $0.note == nil }.count
    }

    /// Count of notes for a book.
    public func noteCount(for bookID: UUID) -> Int {
        annotations.filter { $0.bookID == bookID && $0.note != nil }.count
    }

    // MARK: - Export

    /// Export annotations for a specific book.
    public func exportForBook(
        bookID: UUID,
        bookTitle: String,
        author: String? = nil,
        format: ExportFormat = .markdown
    ) -> ExportResult {
        let list = annotations(for: bookID)
        switch format {
        case .markdown:
            let md = exportEngine.exportAsMarkdown(annotations: list, bookTitle: bookTitle, author: author)
            return .text(md, mimeType: format.mimeType, fileExtension: format.fileExtension)
        case .csv:
            let csv = exportEngine.exportAsReadwiseCSV(annotations: list, bookTitle: bookTitle)
            return .text(csv, mimeType: format.mimeType, fileExtension: format.fileExtension)
        case .json:
            if let data = exportEngine.exportAsJSON(annotations: list, bookTitle: bookTitle, author: author) {
                return .data(data, mimeType: format.mimeType, fileExtension: format.fileExtension)
            }
            return .text("[]", mimeType: format.mimeType, fileExtension: format.fileExtension)
        case .html:
            let html = exportEngine.exportAsHTML(annotations: list, bookTitle: bookTitle, author: author)
            return .text(html, mimeType: format.mimeType, fileExtension: format.fileExtension)
        }
    }

    /// Export all annotations across all books.
    public func exportAll(format: ExportFormat = .markdown) -> ExportResult {
        let allAnnotations = annotations.sorted { $0.createdAt > $1.createdAt }
        switch format {
        case .markdown:
            let md = exportEngine.exportAsMarkdown(annotations: allAnnotations, bookTitle: "All Highlights")
            return .text(md, mimeType: format.mimeType, fileExtension: format.fileExtension)
        case .json:
            if let data = exportEngine.exportAsJSON(annotations: allAnnotations, bookTitle: "All Highlights", author: nil) {
                return .data(data, mimeType: format.mimeType, fileExtension: format.fileExtension)
            }
            return .text("[]", mimeType: format.mimeType, fileExtension: format.fileExtension)
        case .csv:
            let csv = exportEngine.exportAsReadwiseCSV(annotations: allAnnotations, bookTitle: "All Highlights")
            return .text(csv, mimeType: format.mimeType, fileExtension: format.fileExtension)
        case .html:
            let html = exportEngine.exportAsHTML(annotations: allAnnotations, bookTitle: "All Highlights")
            return .text(html, mimeType: format.mimeType, fileExtension: format.fileExtension)
        }
    }

    // MARK: - Persistence

    private func save() {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(annotations)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            DuckLog.error("Save failed: \(error)", category: "AnnotationStore")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            annotations = try JSONDecoder().decode([Annotation].self, from: data)
        } catch {
            DuckLog.error("Load failed: \(error)", category: "AnnotationStore")
        }
    }
}

// MARK: - Export Result

public enum ExportResult: Sendable {
    case text(String, mimeType: String, fileExtension: String)
    case data(Data, mimeType: String, fileExtension: String)

    public var fileName: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmm"
        switch self {
        case .text(_, _, let ext): return "DuckReader_Highlights_\(df.string(from: Date())).\(ext)"
        case .data(_, _, let ext): return "DuckReader_Highlights_\(df.string(from: Date())).\(ext)"
        }
    }

    public var shareData: Any {
        switch self {
        case .text(let s, _, _): return s
        case .data(let d, _, _): return d
        }
    }
}

// MARK: - Reading Card Generator Integration (v2.2)

extension AnnotationExport {
    /// Generate a shareable reading card for the ReadingCardGenerator.
    public func readingCardData(from annotation: Annotation, bookTitle: String, author: String?) -> ReadingCardGenerator.CardData {
        ReadingCardGenerator.CardData(
            bookTitle: bookTitle, author: author,
            quote: annotation.text,
            quoteAttribution: annotation.timestamp.formatted(date: .abbreviated, time: .omitted)
        )
    }
}
