import Foundation
import SwiftUI

// MARK: - Reading Session

/// A single reading session record.
public struct ReadingSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public let bookID: UUID
    public let startDate: Date
    public let endDate: Date?
    public let pagesRead: Int
    public let chaptersRead: [Int]
    public let wordsRead: Int?

    public var duration: TimeInterval {
        guard let end = endDate else { return 0 }
        return end.timeIntervalSince(startDate)
    }

    public var durationFormatted: String {
        let mins = Int(duration / 60)
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60
        let m = mins % 60
        return "\(h)h \(m)m"
    }

    public init(
        id: UUID = UUID(),
        bookID: UUID,
        startDate: Date = Date(),
        endDate: Date? = nil,
        pagesRead: Int = 0,
        chaptersRead: [Int] = [],
        wordsRead: Int? = nil
    ) {
        self.id = id
        self.bookID = bookID
        self.startDate = startDate
        self.endDate = endDate
        self.pagesRead = pagesRead
        self.chaptersRead = chaptersRead
        self.wordsRead = wordsRead
    }
}

// MARK: - Reading Goal

/// A user-defined reading goal.
public struct ReadingGoal: Identifiable, Codable, Sendable {
    public let id: UUID
    public var type: GoalType
    public var target: Int
    public var current: Int
    public var period: GoalPeriod
    public var startDate: Date
    public var isActive: Bool

    public enum GoalType: String, Codable, Sendable, CaseIterable {
        case dailyMinutes = "daily_minutes"
        case dailyPages = "daily_pages"
        case weeklyBooks = "weekly_books"
        case monthlyBooks = "monthly_books"
        case custom = "custom"

        public var displayName: String {
            switch self {
            case .dailyMinutes: String(localized: "goal.dailyMinutes")
            case .dailyPages: String(localized: "goal.dailyPages")
            case .weeklyBooks: String(localized: "goal.weeklyBooks")
            case .monthlyBooks: String(localized: "goal.monthlyBooks")
            case .custom: String(localized: "goal.custom")
            }
        }

        public var unitLabel: String {
            switch self {
            case .dailyMinutes: String(localized: "goal.minutes")
            case .dailyPages: String(localized: "goal.pages")
            case .weeklyBooks, .monthlyBooks: String(localized: "goal.books")
            case .custom: ""
            }
        }
    }

    public enum GoalPeriod: String, Codable, Sendable {
        case daily, weekly, monthly
    }

    public var progress: Double {
        target > 0 ? min(1.0, Double(current) / Double(target)) : 0
    }

    public init(
        id: UUID = UUID(),
        type: GoalType = .dailyMinutes,
        target: Int = 30,
        current: Int = 0,
        period: GoalPeriod = .daily,
        startDate: Date = Date(),
        isActive: Bool = true
    ) {
        self.id = id
        self.type = type
        self.target = target
        self.current = current
        self.period = period
        self.startDate = startDate
        self.isActive = isActive
    }
}

// MARK: - Reading Stats

/// Comprehensive reading statistics.
public struct ReadingStats: Codable, Sendable {
    public var totalBooksCompleted: Int = 0
    public var totalMinutesRead: TimeInterval = 0
    public var totalPagesRead: Int = 0
    public var totalWordsRead: Int = 0
    public var currentStreak: Int = 0
    public var longestStreak: Int = 0
    public var averageSessionMinutes: Double = 0
    public var peakReadingHour: Int = 0
    public var readingSpeedWPM: Double = 0  // words per minute
    public var favoriteGenre: String = ""
    public var mostReadAuthor: String = ""

    /// Pages per day over the last 30 days: [DateString: PageCount]
    public var pagesPerDay: [String: Int] = [:]

    /// Minutes per day over the last 30 days
    public var minutesPerDay: [String: Int] = [:]

    /// Chapter completion rate
    public var chapterCompletionRate: Double = 0
}

// MARK: - Reading Stats Engine

/// Processes reading sessions into comprehensive statistics.
/// Supports heatmap data, streak tracking, and goal progress.
@MainActor
public final class ReadingStatsEngine: ObservableObject, Sendable {

    @Published public private(set) var stats: ReadingStats = ReadingStats()
    @Published public private(set) var sessions: [ReadingSession] = []
    @Published public private(set) var goals: [ReadingGoal] = []
    @Published public var activeGoal: ReadingGoal?

    private let sessionsURL: URL
    private let goalsURL: URL

    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public nonisolated init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DuckReader/Stats", isDirectory: true)
        self.sessionsURL = docs.appendingPathComponent("reading_sessions.json")
        self.goalsURL = docs.appendingPathComponent("reading_goals.json")

        Task { @MainActor in
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            self.load()
        }
    }

    // MARK: - Session Tracking

    public func startSession(bookID: UUID) -> ReadingSession {
        let session = ReadingSession(bookID: bookID, startDate: Date())
        sessions.append(session)
        return session
    }

    public func endSession(_ session: ReadingSession, pagesRead: Int = 0, wordsRead: Int? = nil) {
        if let i = sessions.firstIndex(where: { $0.id == session.id }) {
            var updated = sessions[i]
            updated = ReadingSession(
                id: updated.id,
                bookID: updated.bookID,
                startDate: updated.startDate,
                endDate: Date(),
                pagesRead: pagesRead,
                wordsRead: wordsRead
            )
            sessions[i] = updated
            recalculate()
            save()
        }
    }

    /// Quick session: record a completed reading period.
    public func recordQuickSession(
        bookID: UUID,
        duration: TimeInterval,
        pages: Int = 0,
        words: Int? = nil
    ) {
        let now = Date()
        let session = ReadingSession(
            bookID: bookID,
            startDate: now.addingTimeInterval(-duration),
            endDate: now,
            pagesRead: pages,
            wordsRead: words
        )
        sessions.append(session)
        recalculate()
        save()
    }

    // MARK: - Goal Management

    public func setGoal(_ goal: ReadingGoal) {
        if let i = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[i] = goal
        } else {
            goals.append(goal)
        }
        activeGoal = goal.isActive ? goal : nil
        save()
    }

    public func updateGoalProgress(_ type: ReadingGoal.GoalType, increment: Int = 1) {
        guard let i = goals.firstIndex(where: { $0.type == type && $0.isActive }) else { return }
        var goal = goals[i]
        goal.current += increment
        goals[i] = goal
        activeGoal = goal
        save()
    }

    public func checkGoalStreak() {
        // Update streak based on today's reading
        let today = dateFormatter.string(from: Date())
        let hasReadToday = (stats.minutesPerDay[today] ?? 0) > 0

        if hasReadToday {
            let yesterday = dateFormatter.string(from: calendar.date(byAdding: .day, value: -1, to: Date())!)
            let readYesterday = (stats.minutesPerDay[yesterday] ?? 0) > 0

            if readYesterday || stats.currentStreak == 0 {
                stats.currentStreak += 1
                stats.longestStreak = max(stats.longestStreak, stats.currentStreak)
            }
        } else {
            stats.currentStreak = 0
        }
    }

    // MARK: - Heatmap Data

    /// Data for a GitHub-style reading heatmap (last 365 days).
    public func heatmapData(days: Int = 365) -> [(date: String, count: Int, level: Int)] {
        var result: [(String, Int, Int)] = []

        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let key = dateFormatter.string(from: date)
            let count = stats.pagesPerDay[key] ?? 0

            let level: Int = {
                if count == 0 { return 0 }
                if count < 10 { return 1 }
                if count < 30 { return 2 }
                if count < 60 { return 3 }
                return 4
            }()

            result.append((date: key, count: count, level: level))
        }

        return result
    }

    /// Weekly summary: last N weeks.
    public func weeklySummary(weeks: Int = 4) -> [WeekSummary] {
        var summaries: [WeekSummary] = []
        for w in 0..<weeks {
            let endDate = calendar.date(byAdding: .weekOfYear, value: -w, to: Date())!
            let startDate = calendar.date(byAdding: .day, value: -6, to: endDate)!

            var totalMin: TimeInterval = 0
            var totalPages = 0
            var daysRead = 0

            let sessionsInWeek = sessions.filter {
                $0.startDate >= startDate && $0.startDate <= endDate
            }
            for s in sessionsInWeek {
                totalMin += s.duration
                totalPages += s.pagesRead
            }

            // Count unique days
            let days = Set(sessionsInWeek.map { dateFormatter.string(from: $0.startDate) })
            daysRead = days.count

            summaries.append(WeekSummary(
                weekStart: startDate,
                weekEnd: endDate,
                totalMinutes: totalMin / 60,
                totalPages: totalPages,
                daysRead: daysRead
            ))
        }
        return summaries
    }

    // MARK: - Recalculate

    private func recalculate() {
        let completed = sessions.filter { $0.endDate != nil }

        stats.totalMinutesRead = completed.reduce(0) { $0 + $1.duration }
        stats.totalPagesRead = completed.reduce(0) { $0 + $1.pagesRead }
        stats.totalWordsRead = completed.reduce(0) { $0 + ($1.wordsRead ?? 0) }
        stats.averageSessionMinutes = completed.isEmpty ? 0 :
            stats.totalMinutesRead / Double(completed.count) / 60

        // Pages per day
        var ppd: [String: Int] = [:]
        var mpd: [String: Int] = [:]
        var hourCounts: [Int: Int] = [:]

        for s in completed {
            let key = dateFormatter.string(from: s.startDate)
            ppd[key, default: 0] += s.pagesRead
            mpd[key, default: 0] += Int(s.duration / 60)
            let hour = calendar.component(.hour, from: s.startDate)
            hourCounts[hour, default: 0] += 1
        }

        stats.pagesPerDay = ppd
        stats.minutesPerDay = mpd
        stats.peakReadingHour = hourCounts.max(by: { $0.value < $1.value })?.key ?? 0

        // Reading speed
        if stats.totalMinutesRead > 0 && stats.totalWordsRead > 0 {
            stats.readingSpeedWPM = Double(stats.totalWordsRead) / (stats.totalMinutesRead / 60)
        }

        checkGoalStreak()
    }

    // MARK: - Persistence

    private func save() {
        do {
            try JSONEncoder().encode(sessions).write(to: sessionsURL, options: .atomic)
            try JSONEncoder().encode(goals).write(to: goalsURL, options: .atomic)
        } catch {
            DuckLog.error("Save failed: \(error)", category: "StatsEngine")
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: sessionsURL),
           let loaded = try? JSONDecoder().decode([ReadingSession].self, from: data) {
            sessions = loaded
        }
        if let data = try? Data(contentsOf: goalsURL),
           let loaded = try? JSONDecoder().decode([ReadingGoal].self, from: data) {
            goals = loaded
            activeGoal = goals.first(where: \.isActive)
        }
        recalculate()
    }
}

// MARK: - Week Summary

public struct WeekSummary: Sendable {
    public let weekStart: Date
    public let weekEnd: Date
    public let totalMinutes: Double
    public let totalPages: Int
    public let daysRead: Int

    public var averageMinutesPerDay: Double {
        daysRead > 0 ? totalMinutes / Double(daysRead) : 0
    }
}

// MARK: - Environment Key

public struct ReadingStatsKey: EnvironmentKey {
    public static let defaultValue: ReadingStatsEngine = ReadingStatsEngine()
}

public extension EnvironmentValues {
    var readingStats: ReadingStatsEngine {
        get { self[ReadingStatsKey.self] }
        set { self[ReadingStatsKey.self] = newValue }
    }
}
