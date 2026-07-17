import Foundation
import SwiftUI

// MARK: - Vocabulary Entry

/// A word/phrase the user has looked up or saved.
public struct VocabularyEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let word: String
    public let definition: String?
    public let context: String?           // The sentence where it was found
    public let sourceBookID: UUID?
    public let sourceChapter: String?
    public let language: String           // ISO 639-1, e.g. "ja", "zh", "en"
    public let addedAt: Date
    public let reviewCount: Int
    public let lastReviewedAt: Date?
    public let mastery: Mastery           // SRS-like rating

    public enum Mastery: Int, Codable, Sendable {
        case new = 0
        case learning = 1
        case reviewing = 2
        case mastered = 3
    }

    public init(
        id: UUID = UUID(),
        word: String,
        definition: String? = nil,
        context: String? = nil,
        sourceBookID: UUID? = nil,
        sourceChapter: String? = nil,
        language: String = "unknown",
        addedAt: Date = Date(),
        reviewCount: Int = 0,
        lastReviewedAt: Date? = nil,
        mastery: Mastery = .new
    ) {
        self.id = id
        self.word = word
        self.definition = definition
        self.context = context
        self.sourceBookID = sourceBookID
        self.sourceChapter = sourceChapter
        self.language = language
        self.addedAt = addedAt
        self.reviewCount = reviewCount
        self.lastReviewedAt = lastReviewedAt
        self.mastery = mastery
    }
}

// MARK: - Vocabulary Manager

/// Manages vocabulary lists, dictionary lookups, and flashcard review.
/// OCR-based word capture from manga, manual lookup from novels.
@MainActor
public final class VocabularyManager: ObservableObject, Sendable {

    @Published public private(set) var entries: [VocabularyEntry] = []
    @Published public var selectedLanguage: String = "all"
    @Published public var sortOrder: SortOrder = .recent

    public enum SortOrder: String, CaseIterable, Sendable {
        case recent = "最近添加"
        case alphabetical = "字母顺序"
        case mastery = "掌握度"
        case reviewDue = "待复习"
    }

    private let storageURL: URL

    public nonisolated init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storageURL = docs.appendingPathComponent("DuckReader/vocabulary.json")

        Task { @MainActor in
            self.load()
        }
    }

    // MARK: - Add / Remove

    public func addEntry(
        word: String,
        definition: String? = nil,
        context: String? = nil,
        sourceBookID: UUID? = nil,
        sourceChapter: String? = nil,
        language: String = "unknown"
    ) {
        // Dedup
        guard !entries.contains(where: { $0.word == word && $0.language == language }) else {
            return
        }

        let entry = VocabularyEntry(
            word: word,
            definition: definition,
            context: context,
            sourceBookID: sourceBookID,
            sourceChapter: sourceChapter,
            language: language
        )
        entries.append(entry)
        save()
    }

    public func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    public func updateDefinition(id: UUID, definition: String) {
        if let idx = entries.firstIndex(where: { $0.id == id }) {
            var updated = entries[idx]
            updated = VocabularyEntry(
                id: updated.id,
                word: updated.word,
                definition: definition,
                context: updated.context,
                sourceBookID: updated.sourceBookID,
                sourceChapter: updated.sourceChapter,
                language: updated.language,
                addedAt: updated.addedAt,
                reviewCount: updated.reviewCount,
                lastReviewedAt: updated.lastReviewedAt,
                mastery: updated.mastery
            )
            entries[idx] = updated
            save()
        }
    }

    // MARK: - Lookup (System Dictionary)

    /// Look up a word using the system's built-in dictionary.
    /// Returns the definition text if found.
    public func lookupInSystemDictionary(_ word: String) -> String? {
        let range = CFRangeMake(0, word.utf16.count)
        guard let definition = DCSCopyTextDefinition(nil, word as CFString, range) else {
            return nil
        }
        return definition.takeRetainedValue() as String
    }

    /// Look up a word using an external API (placeholder for future integration).
    public func lookupOnline(_ word: String, language: String = "ja") async -> String? {
        // Future: Jisho.org / Youdao / Google Translate API
        // For now, fall back to system dictionary
        return lookupInSystemDictionary(word)
    }

    // MARK: - SRS Review

    /// Mark an entry as reviewed (spaced repetition).
    public func markReviewed(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        var updated = entries[idx]

        let newMastery: VocabularyEntry.Mastery = {
            switch updated.mastery {
            case .new: return .learning
            case .learning: return updated.reviewCount >= 3 ? .reviewing : .learning
            case .reviewing: return updated.reviewCount >= 7 ? .mastered : .reviewing
            case .mastered: return .mastered
            }
        }()

        updated = VocabularyEntry(
            id: updated.id,
            word: updated.word,
            definition: updated.definition,
            context: updated.context,
            sourceBookID: updated.sourceBookID,
            sourceChapter: updated.sourceChapter,
            language: updated.language,
            addedAt: updated.addedAt,
            reviewCount: updated.reviewCount + 1,
            lastReviewedAt: Date(),
            mastery: newMastery
        )
        entries[idx] = updated
        save()
    }

    // MARK: - Query

    /// Entries filtered by selected language and sorted.
    public var filteredEntries: [VocabularyEntry] {
        var result = entries
        if selectedLanguage != "all" {
            result = result.filter { $0.language == selectedLanguage }
        }
        switch sortOrder {
        case .recent:
            result.sort { $0.addedAt > $1.addedAt }
        case .alphabetical:
            result.sort { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        case .mastery:
            result.sort { $0.mastery.rawValue > $1.mastery.rawValue }
        case .reviewDue:
            result.sort { ($0.lastReviewedAt ?? .distantPast) < ($1.lastReviewedAt ?? .distantPast) }
        }
        return result
    }

    /// Stats for the vocabulary list.
    public var stats: VocabularyStats {
        let total = entries.count
        let mastered = entries.filter { $0.mastery == .mastered }.count
        let byLanguage = Dictionary(grouping: entries, by: { $0.language }).mapValues { $0.count }
        return VocabularyStats(
            totalEntries: total,
            masteredEntries: mastered,
            learningEntries: entries.filter { $0.mastery == .learning || $0.mastery == .reviewing }.count,
            newEntries: entries.filter { $0.mastery == .new }.count,
            byLanguage: byLanguage
        )
    }

    public func entriesForBook(_ bookID: UUID) -> [VocabularyEntry] {
        entries.filter { $0.sourceBookID == bookID }
    }

    // MARK: - Export

    public func exportAsCSV() -> String {
        var csv = "Word,Definition,Context,Language,Mastery,Added At\n"
        for e in entries.sorted(by: { $0.addedAt > $1.addedAt }) {
            let def = (e.definition ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let ctx = (e.context ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\"\(e.word)\",\"\(def)\",\"\(ctx)\",\(e.language),\(e.mastery.rawValue),\(ISO8601DateFormatter().string(from: e.addedAt))\n"
        }
        return csv
    }

    public func exportAsJSON() -> Data? {
        try? JSONEncoder().encode(entries)
    }

    // MARK: - Persistence

    private func save() {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[VocabularyManager] Save failed: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            entries = try JSONDecoder().decode([VocabularyEntry].self, from: data)
        } catch {
            print("[VocabularyManager] Load failed: \(error)")
        }
    }
}

// MARK: - Stats

public struct VocabularyStats: Sendable {
    public let totalEntries: Int
    public let masteredEntries: Int
    public let learningEntries: Int
    public let newEntries: Int
    public let byLanguage: [String: Int]

    public var masteryRate: Double {
        totalEntries > 0 ? Double(masteredEntries) / Double(totalEntries) : 0
    }
}

// MARK: - Environment Key

public struct VocabularyManagerKey: EnvironmentKey {
    public static let defaultValue: VocabularyManager = VocabularyManager()
}

public extension EnvironmentValues {
    var vocabularyManager: VocabularyManager {
        get { self[VocabularyManagerKey.self] }
        set { self[VocabularyManagerKey.self] = newValue }
    }
}
