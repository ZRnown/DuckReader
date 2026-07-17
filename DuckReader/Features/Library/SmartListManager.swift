import Foundation
import SwiftUI

// MARK: - Smart List Definition

/// A dynamic filter-based smart shelf that auto-updates as books are added/read.
public struct SmartList: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var icon: String
    public var rules: [SmartListRule]
    public var matchMode: MatchMode       // all / any
    public var sortOrder: SmartListSortOrder
    public var isPinned: Bool = false

    public enum MatchMode: String, Codable, Sendable, CaseIterable {
        case all = "all"
        case any = "any"

        public var displayName: String {
            switch self {
            case .all: String(localized: "smartlist.matchAll")
            case .any: String(localized: "smartlist.matchAny")
            }
        }
    }

    public enum SmartListSortOrder: String, Codable, Sendable, CaseIterable {
        case title, author, dateAdded, lastRead, progress, random

        public var displayName: String {
            switch self {
            case .title: String(localized: "smartlist.sortTitle")
            case .author: String(localized: "smartlist.sortAuthor")
            case .dateAdded: String(localized: "smartlist.sortDateAdded")
            case .lastRead: String(localized: "smartlist.sortLastRead")
            case .progress: String(localized: "smartlist.sortProgress")
            case .random: String(localized: "smartlist.sortRandom")
            }
        }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "books.vertical",
        rules: [SmartListRule] = [],
        matchMode: MatchMode = .all,
        sortOrder: SmartListSortOrder = .title,
        isPinned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.rules = rules
        self.matchMode = matchMode
        self.sortOrder = sortOrder
        self.isPinned = isPinned
    }
}

// MARK: - Smart List Rule

/// A single filter criterion for a smart list.
public struct SmartListRule: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var field: RuleField
    public var op: RuleOperator
    public var value: String

    public enum RuleField: String, Codable, Sendable, CaseIterable {
        case title = "title"
        case author = "author"
        case tag = "tag"
        case series = "series"
        case format = "format"
        case language = "language"
        case readingProgress = "readingProgress"
        case isCompleted = "isCompleted"
        case hasAnnotations = "hasAnnotations"
        case dateAdded = "dateAdded"
        case lastOpened = "lastOpened"
        case pageCount = "pageCount"
        case rating = "rating"

        public var displayName: String {
            switch self {
            case .title: return String(localized: "smartlist.fieldTitle")
            case .author: return String(localized: "smartlist.fieldAuthor")
            case .tag: return String(localized: "smartlist.fieldTag")
            case .series: return String(localized: "smartlist.fieldSeries")
            case .format: return String(localized: "smartlist.fieldFormat")
            case .language: return String(localized: "smartlist.fieldLanguage")
            case .readingProgress: return String(localized: "smartlist.fieldProgress")
            case .isCompleted: return String(localized: "smartlist.fieldCompleted")
            case .hasAnnotations: return String(localized: "smartlist.fieldAnnotations")
            case .dateAdded: return String(localized: "smartlist.fieldDateAdded")
            case .lastOpened: return String(localized: "smartlist.fieldLastOpened")
            case .pageCount: return String(localized: "smartlist.fieldPageCount")
            case .rating: return String(localized: "smartlist.fieldRating")
            }
        }
    }

    public enum RuleOperator: String, Codable, Sendable, CaseIterable {
        case equals, contains, startsWith, endsWith
        case greaterThan, lessThan
        case isTrue, isFalse
        case inLast   // time-based: "7d", "30d"

        public var displayName: String {
            switch self {
            case .equals: return "="
            case .contains: return String(localized: "smartlist.opContains")
            case .startsWith: return String(localized: "smartlist.opStartsWith")
            case .endsWith: return String(localized: "smartlist.opEndsWith")
            case .greaterThan: return ">"
            case .lessThan: return "<"
            case .isTrue: return String(localized: "smartlist.opTrue")
            case .isFalse: return String(localized: "smartlist.opFalse")
            case .inLast: return String(localized: "smartlist.opInLast")
            }
        }
    }

    public init(
        id: UUID = UUID(),
        field: RuleField,
        op: RuleOperator,
        value: String = ""
    ) {
        self.id = id
        self.field = field
        self.op = op
        self.value = value
    }
}

// MARK: - Smart List Evaluator

/// Evaluates smart list rules against book metadata and reading progress.
public struct SmartListEvaluator: Sendable {

    /// Evaluate whether a book matches the smart list rules.
    public func evaluate(
        book: Book,
        metadata: EnhancedMetadata?,
        progress: ReadingProgress?,
        annotations: [Annotation],
        rules: [SmartListRule],
        matchMode: SmartList.MatchMode
    ) -> Bool {
        guard !rules.isEmpty else { return true }

        let results = rules.map { evaluateRule($0, book: book, metadata: metadata, progress: progress, annotations: annotations) }

        switch matchMode {
        case .all: return results.allSatisfy { $0 }
        case .any: return results.contains(true)
        }
    }

    private func evaluateRule(
        _ rule: SmartListRule,
        book: Book,
        metadata: EnhancedMetadata?,
        progress: ReadingProgress?,
        annotations: [Annotation]
    ) -> Bool {
        switch rule.field {
        case .title:
            return stringMatch(book.title, op: rule.op, value: rule.value)
        case .author:
            return stringMatch(book.author ?? "", op: rule.op, value: rule.value)
        case .tag:
            let tags = metadata?.tags ?? []
            return stringMatch(tags.joined(separator: ","), op: rule.op, value: rule.value)
        case .series:
            return stringMatch(metadata?.series ?? "", op: rule.op, value: rule.value)
        case .format:
            return stringMatch(book.sourceURL.pathExtension, op: rule.op, value: rule.value)
        case .language:
            return stringMatch(book.metadata.language ?? "", op: rule.op, value: rule.value)
        case .readingProgress:
            return numericMatch(Double(progress?.overallProgress ?? 0), op: rule.op, value: Double(rule.value) ?? 0)
        case .isCompleted:
            let completed = (progress?.isFinished ?? false)
            switch rule.op {
            case .isTrue: return completed
            case .isFalse: return !completed
            default: return false
            }
        case .hasAnnotations:
            let hasAnns = !annotations.isEmpty
            switch rule.op {
            case .isTrue: return hasAnns
            case .isFalse: return !hasAnns
            default: return false
            }
        case .dateAdded:
            return dateMatch(book.dateAdded ?? Date.distantPast, op: rule.op, value: rule.value)
        case .lastOpened:
            return dateMatch(progress?.lastUpdated ?? Date.distantPast, op: rule.op, value: rule.value)
        case .pageCount:
            return numericMatch(Double(metadata?.pageCount ?? 0), op: rule.op, value: Double(rule.value) ?? 0)
        case .rating:
            return numericMatch(metadata?.rating ?? 0, op: rule.op, value: Double(rule.value) ?? 0)
        }
    }

    private func stringMatch(_ field: String, op: SmartListRule.RuleOperator, value: String) -> Bool {
        switch op {
        case .equals: return field.caseInsensitiveCompare(value) == .orderedSame
        case .contains: return field.localizedCaseInsensitiveContains(value)
        case .startsWith: return field.localizedCaseInsensitiveHasPrefix(value)
        case .endsWith: return field.localizedCaseInsensitiveHasSuffix(value)
        default: return false
        }
    }

    private func numericMatch(_ field: Double, op: SmartListRule.RuleOperator, value: Double) -> Bool {
        switch op {
        case .equals: return abs(field - value) < 0.01
        case .greaterThan: return field > value
        case .lessThan: return field < value
        default: return false
        }
    }

    private func dateMatch(_ field: Date, op: SmartListRule.RuleOperator, value: String) -> Bool {
        if op == .inLast {
            // Parse "7d", "30d", "1w", "1m"
            var interval: TimeInterval = 0
            if value.hasSuffix("d"), let d = Double(value.dropLast()) {
                interval = d * 86400
            } else if value.hasSuffix("w"), let w = Double(value.dropLast()) {
                interval = w * 604800
            } else if value.hasSuffix("m"), let m = Double(value.dropLast()) {
                interval = m * 2592000
            }
            return Date().timeIntervalSince(field) <= interval
        }
        return false
    }
}

// MARK: - String Helpers

extension String {
    func localizedCaseInsensitiveHasPrefix(_ prefix: String) -> Bool {
        range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
    }
    func localizedCaseInsensitiveHasSuffix(_ suffix: String) -> Bool {
        range(of: suffix, options: [.caseInsensitive, .backwards, .anchored]) != nil
    }
}

// MARK: - Smart List Store

@MainActor
public final class SmartListStore: ObservableObject, Sendable {

    @Published public private(set) var lists: [SmartList] = []

    private let storageURL: URL
    private let evaluator = SmartListEvaluator()

    public nonisolated init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storageURL = docs.appendingPathComponent("DuckReader/smart_lists.json")
        Task { @MainActor in self.load() }
    }

    // MARK: - CRUD

    public func addList(_ list: SmartList) {
        lists.append(list)
        save()
    }

    public func updateList(_ list: SmartList) {
        if let i = lists.firstIndex(where: { $0.id == list.id }) {
            lists[i] = list
            save()
        }
    }

    public func removeList(id: UUID) {
        lists.removeAll { $0.id == id }
        save()
    }

    /// Reorder lists (e.g., after drag-and-drop).
    public func reorder(from source: IndexSet, to destination: Int) {
        lists.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Built-in Templates

    public func createBuiltInLists() {
        if lists.isEmpty {
            lists = [
                SmartList(
                    name: String(localized: "smartlist.continueReading"),
                    icon: "book.fill",
                    rules: [
                        SmartListRule(field: .readingProgress, op: .greaterThan, value: "0"),
                        SmartListRule(field: .isCompleted, op: .isFalse, value: ""),
                    ],
                    matchMode: .all,
                    sortOrder: .lastRead,
                    isPinned: true
                ),
                SmartList(
                    name: String(localized: "smartlist.recentlyAdded"),
                    icon: "star.fill",
                    rules: [SmartListRule(field: .dateAdded, op: .inLast, value: "30d")],
                    matchMode: .all,
                    sortOrder: .dateAdded,
                    isPinned: true
                ),
                SmartList(
                    name: String(localized: "smartlist.unread"),
                    icon: "book.closed.fill",
                    rules: [SmartListRule(field: .readingProgress, op: .equals, value: "0")],
                    matchMode: .all,
                    sortOrder: .dateAdded
                ),
                SmartList(
                    name: String(localized: "smartlist.completed"),
                    icon: "checkmark.circle.fill",
                    rules: [SmartListRule(field: .isCompleted, op: .isTrue, value: "")],
                    matchMode: .all,
                    sortOrder: .lastRead
                ),
            ]
            save()
        }
    }

    // MARK: - Evaluate

    public func evaluateBooks(
        _ books: [Book],
        metadataStore: MetadataStore,
        progressMap: [UUID: ReadingProgress],
        annotationStore: AnnotationStore,
        for list: SmartList
    ) -> [Book] {
        books.filter { book in
            let meta = metadataStore.metadata[book.id]
            let progress = progressMap[book.id]
            let annotations = annotationStore.annotations(for: book.id)
            return evaluator.evaluate(
                book: book,
                metadata: meta,
                progress: progress,
                annotations: annotations,
                rules: list.rules,
                matchMode: list.matchMode
            )
        }
    }

    // MARK: - Persistence

    private func save() {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(lists)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            DuckLog.error("Save failed: \(error)", category: "SmartListStore")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let loaded = try? JSONDecoder().decode([SmartList].self, from: data) else {
            return
        }
        lists = loaded
    }
}
