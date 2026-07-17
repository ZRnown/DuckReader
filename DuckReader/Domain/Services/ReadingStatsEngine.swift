import Foundation
import Combine
import SwiftData

// MARK: - Reading Stats Engine

/// Aggregates reading statistics across all books.
/// Drives achievements, reading streaks, and the stats dashboard.
/// Updates via publisher so UI reacts in real-time.
@MainActor
public final class ReadingStatsEngine: ObservableObject {
    public static let shared = ReadingStatsEngine()

    @Published public private(set) var stats = ReadingStats()
    @Published public private(set) var dailyHistory: [Date: DailyReadingEntry] = [:]

    private var modelContext: ModelContext?
    private let defaults = UserDefaults(suiteName: "group.com.duckreader")!

    public init() {}

    // MARK: - Configuration

    public func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadHistory()
    }

    // MARK: - Recording

    /// Record a reading session. Call on app background or periodic save.
    public func recordReading(bookID: String, minutes: Int, pages: Int, completed: Bool = false) {
        let today = Calendar.current.startOfDay(for: Date())

        var entry = dailyHistory[today] ?? DailyReadingEntry(date: today)
        entry.minutesRead += minutes
        entry.pagesRead += pages
        entry.booksReadToday = completed ? entry.booksReadToday + 1 : entry.booksReadToday
        dailyHistory[today] = entry

        // Persist
        saveHistory()

        // Recompute stats
        recomputeStats()

        // Check achievements
        AchievementEngine.shared.checkAchievements(stats: stats)
    }

    /// Record a bookmark creation.
    public func recordBookmark() {
        stats.totalBookmarks += 1
    }

    /// Record that a book's format was detected.
    public func recordFormat(_ format: String) {
        stats.uniqueFormats.insert(format)
    }

    /// Record that a genre was detected.
    public func recordGenre(_ genre: String) {
        stats.uniqueGenres.insert(genre)
    }

    // MARK: - Public Computed Properties

    /// Current reading streak (consecutive days).
    public var currentStreak: Int {
        var streak = 0
        let calendar = Calendar.current
        var date = calendar.startOfDay(for: Date())

        while true {
            if let entry = dailyHistory[date], entry.minutesRead > 0 {
                streak += 1
                date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            } else {
                break
            }
        }
        return streak
    }

    /// Whether the user read today.
    public var readToday: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return (dailyHistory[today]?.minutesRead ?? 0) > 0
    }

    /// Today's reading minutes.
    public var todayMinutes: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return dailyHistory[today]?.minutesRead ?? 0
    }

    /// This week's reading minutes.
    public var weeklyMinutes: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: today) else { return 0 }

        return dailyHistory
            .filter { $0.key >= weekStart && $0.key <= today }
            .map { $0.value.minutesRead }
            .reduce(0, +)
    }

    /// This month's reading minutes.
    public var monthlyMinutes: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) else {
            return 0
        }

        return dailyHistory
            .filter { $0.key >= monthStart && $0.key <= today }
            .map { $0.value.minutesRead }
            .reduce(0, +)
    }

    // MARK: - Private

    private func recomputeStats() {
        let entries = Array(dailyHistory.values)

        stats.totalMinutesRead = entries.map(\.minutesRead).reduce(0, +)
        stats.totalPagesRead = entries.map(\.pagesRead).reduce(0, +)
        stats.totalBooksRead = entries.map(\.booksReadToday).reduce(0, +)
        stats.longestConsecutiveDays = currentStreak

        // Find longest single-book session
        stats.longestSingleBookMinutes = entries.map(\.minutesRead).max() ?? 0

        // Completion rate from SwiftData
        recomputeCompletionStats()
    }

    private func recomputeCompletionStats() {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<BookEntity>()
        if let books = try? context.fetch(descriptor) {
            let completed = books.filter { $0.progress >= 1.0 }
            stats.completionRate = books.isEmpty ? 0 : Double(completed.count) / Double(books.count)

            // Speed reads (books finished in < 1 day since first open)
            stats.speedReadBooks = books.filter { book in
                guard let addedAt = book.addedAt, let finishedAt = book.lastOpenedAt else { return false }
                return book.progress >= 1.0 && finishedAt.timeIntervalSince(addedAt) < 86_400
            }.count
        }
    }

    // MARK: - Persistence

    private let historyKey = "readingDailyHistory"

    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(dailyHistory) {
            defaults.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() {
        guard let data = defaults.data(forKey: historyKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        dailyHistory = (try? decoder.decode([Date: DailyReadingEntry].self, from: data)) ?? [:]
        recomputeStats()
    }
}

// MARK: - Reading Stats

public struct ReadingStats: Sendable {
    public var totalMinutesRead: Int = 0
    public var totalPagesRead: Int = 0
    public var totalBooksRead: Int = 0
    public var longestConsecutiveDays: Int = 0
    public var longestSingleBookMinutes: Int = 0
    public var totalBookmarks: Int = 0
    public var speedReadBooks: Int = 0
    public var completionRate: Double = 0
    public var uniqueGenres: Set<String> = []
    public var uniqueFormats: Set<String> = []
}

public struct DailyReadingEntry: Codable, Sendable {
    public let date: Date
    public var minutesRead: Int = 0
    public var pagesRead: Int = 0
    public var booksReadToday: Int = 0

    public init(date: Date) {
        self.date = date
    }
}
