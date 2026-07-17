import Foundation
import Combine
import SwiftData
import SwiftUI

// MARK: - Achievement System

/// Tracks reading milestones and awards achievements.
/// Design: each achievement is a simple condition-checked unlock.
/// Persists via SwiftData + syncs via CloudKit.
@MainActor
public final class AchievementEngine: ObservableObject {
    public static let shared = AchievementEngine()

    @Published public private(set) var allAchievements: [Achievement] = []
    @Published public private(set) var recentlyUnlocked: [Achievement] = []
    @Published public private(set) var readerLevel: ReaderLevel = .beginner

    private var modelContext: ModelContext?

    public enum ReaderLevel: Int, Comparable, Sendable {
        case beginner = 0       // < 10h
        case casual = 1         // 10-50h
        case bookworm = 2       // 50-200h
        case scholar = 3        // 200-500h
        case sage = 4           // 500h+

        public var title: String {
            switch self {
            case .beginner: return "萌新读者"
            case .casual: return "闲暇书虫"
            case .bookworm: return "资深书友"
            case .scholar: return "博览学者"
            case .sage: return "阅读仙人"
            }
        }

        public var icon: String {
            switch self {
            case .beginner: return "book"
            case .casual: return "book.fill"
            case .bookworm: return "books.vertical"
            case .scholar: return "books.vertical.fill"
            case .sage: return "sparkles"
            }
        }

        public static func < (lhs: ReaderLevel, rhs: ReaderLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private init() {
        allAchievements = Achievement.allDefinitions
    }

    // MARK: - Setup

    public func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Check & Unlock

    public func checkAchievements(stats: ReadingStats) {
        for definition in allAchievements {
            guard !definition.isUnlocked else { continue }

            if evaluateUnlock(definition, stats: stats) {
                unlock(definition.id, stats: stats)
            }
        }

        updateReaderLevel(stats.totalMinutesRead)
    }

    private func unlock(_ id: String, stats: ReadingStats) {
        guard let idx = allAchievements.firstIndex(where: { $0.id == id }) else { return }
        var achievement = allAchievements[idx]
        achievement.isUnlocked = true
        achievement.unlockedAt = Date()
        allAchievements[idx] = achievement
        recentlyUnlocked.append(achievement)

        DuckHaptic.success()

        // Persist
        if let context = modelContext {
            let record = AchievementRecord(
                id: id,
                name: achievement.name,
                unlockedAt: Date()
            )
            context.insert(record)
            try? context.save()
        }

        // Cloud sync
        Task {
            try? await CloudSyncService.shared.saveAchievement(
                id: id,
                name: achievement.name,
                unlockedAt: Date()
            )
        }
    }

    // MARK: - Condition Evaluation

    private func evaluateUnlock(_ definition: Achievement, stats: ReadingStats) -> Bool {
        switch definition.condition {
        case .totalBooks(let count):
            return stats.totalBooksRead >= count

        case .totalMinutes(let minutes):
            return stats.totalMinutesRead >= minutes

        case .totalPages(let pages):
            return stats.totalPagesRead >= pages

        case .consecutiveDays(let days):
            return stats.longestConsecutiveDays >= days

        case .genres(let count):
            return stats.uniqueGenres >= count

        case .bookmarks(let count):
            return stats.totalBookmarks >= count

        case .singleBookMinutes(let minutes):
            return stats.longestSingleBookMinutes >= minutes

        case .speedReads(let count):
            return stats.speedReadBooks >= count

        case .multiFormat(let count):
            return stats.uniqueFormats >= count

        case .completionRate(let rate):
            return stats.completionRate >= rate

        case .custom:
            return false
        }
    }

    private func updateReaderLevel(_ totalMinutes: Int) {
        let newLevel: ReaderLevel
        switch totalMinutes {
        case 0..<600:        newLevel = .beginner   // < 10h
        case 600..<3000:    newLevel = .casual     // 10-50h
        case 3000..<12000:  newLevel = .bookworm   // 50-200h
        case 12000..<30000: newLevel = .scholar    // 200-500h
        default:            newLevel = .sage       // 500h+
        }

        if newLevel > readerLevel {
            readerLevel = newLevel
            DuckHaptic.heavy()
        }
    }

    /// Dismiss a recently-unlocked notification.
    public func dismissRecent(_ id: String) {
        recentlyUnlocked.removeAll { $0.id == id }
    }

    /// Load persisted achievements from SwiftData.
    public func loadFromStore() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<AchievementRecord>()
        if let records = try? context.fetch(descriptor) {
            for record in records {
                if let idx = allAchievements.firstIndex(where: { $0.id == record.id }) {
                    var ach = allAchievements[idx]
                    ach.isUnlocked = true
                    ach.unlockedAt = record.unlockedAt
                    allAchievements[idx] = ach
                }
            }
        }
    }
}

// MARK: - Achievement Model

public struct Achievement: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let icon: String
    public let tier: AchievementTier
    public let condition: AchievementCondition
    public var isUnlocked: Bool
    public var unlockedAt: Date?

    public init(id: String, name: String, description: String, icon: String, tier: AchievementTier, condition: AchievementCondition, isUnlocked: Bool = false, unlockedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.tier = tier
        self.condition = condition
        self.isUnlocked = isUnlocked
        self.unlockedAt = unlockedAt
    }
}

public enum AchievementTier: Sendable {
    case bronze
    case silver
    case gold
    case platinum

    public var color: Color {
        switch self {
        case .bronze: return DuckColor.achievementBronze
        case .silver: return DuckColor.achievementSilver
        case .gold: return DuckColor.achievementGold
        case .platinum: return .purple
        }
    }

    public var name: String {
        switch self {
        case .bronze: return "铜"
        case .silver: return "银"
        case .gold: return "金"
        case .platinum: return "铂金"
        }
    }

    public var starsNeeded: Int {
        switch self {
        case .bronze: return 1
        case .silver: return 3
        case .gold: return 5
        case .platinum: return 10
        }
    }
}

public enum AchievementCondition: Sendable {
    case totalBooks(Int)
    case totalMinutes(Int)
    case totalPages(Int)
    case consecutiveDays(Int)
    case genres(Int)
    case bookmarks(Int)
    case singleBookMinutes(Int)
    case speedReads(Int)
    case multiFormat(Int)
    case completionRate(Double)
    case custom
}

// MARK: - All Achievement Definitions

public extension Achievement {
    static let allDefinitions: [Achievement] = [
        // Bronze — Getting Started
        Achievement(
            id: "first_book",
            name: "初次邂逅",
            description: "导入第一本书",
            icon: "book.closed",
            tier: .bronze,
            condition: .totalBooks(1)
        ),
        Achievement(
            id: "first_hour",
            name: "一小时后",
            description: "累计阅读 1 小时",
            icon: "clock",
            tier: .bronze,
            condition: .totalMinutes(60)
        ),
        Achievement(
            id: "first_bookmark",
            name: "留下印记",
            description: "添加第一个书签",
            icon: "bookmark",
            tier: .bronze,
            condition: .bookmarks(1)
        ),
        Achievement(
            id: "three_formats",
            name: "不拘一格",
            description: "阅读 3 种不同格式的书",
            icon: "doc.richtext",
            tier: .bronze,
            condition: .multiFormat(3)
        ),

        // Silver — Regular Reader
        Achievement(
            id: "five_books",
            name: "五车之富",
            description: "累计读完 5 本书",
            icon: "books.vertical",
            tier: .silver,
            condition: .totalBooks(5)
        ),
        Achievement(
            id: "ten_hours",
            name: "十时有约",
            description: "累计阅读 10 小时",
            icon: "clock.fill",
            tier: .silver,
            condition: .totalMinutes(600)
        ),
        Achievement(
            id: "seven_days",
            name: "七日坚持",
            description: "连续 7 天阅读",
            icon: "calendar.badge.checkmark",
            tier: .silver,
            condition: .consecutiveDays(7)
        ),
        Achievement(
            id: "thousand_pages",
            name: "千页之约",
            description: "累计阅读 1000 页",
            icon: "text.book.closed",
            tier: .silver,
            condition: .totalPages(1000)
        ),

        // Gold — Devoted Reader
        Achievement(
            id: "twenty_books",
            name: "满架琳琅",
            description: "累计读完 20 本书",
            icon: "books.vertical.fill",
            tier: .gold,
            condition: .totalBooks(20)
        ),
        Achievement(
            id: "fifty_hours",
            name: "半百光阴",
            description: "累计阅读 50 小时",
            icon: "gauge.with.dots.needle.50percent",
            tier: .gold,
            condition: .totalMinutes(3000)
        ),
        Achievement(
            id: "thirty_days",
            name: "月月如斯",
            description: "连续 30 天阅读",
            icon: "flame",
            tier: .gold,
            condition: .consecutiveDays(30)
        ),
        Achievement(
            id: "ten_genres",
            name: "十方博览",
            description: "阅读 10 种不同分类",
            icon: "tray.full",
            tier: .gold,
            condition: .genres(10)
        ),

        // Platinum — Reading Sage
        Achievement(
            id: "fifty_books",
            name: "汗牛充栋",
            description: "累计读完 50 本书",
            icon: "building.columns.fill",
            tier: .platinum,
            condition: .totalBooks(50)
        ),
        Achievement(
            id: "two_hundred_hours",
            name: "日月同辉",
            description: "累计阅读 200 小时",
            icon: "sun.max",
            tier: .platinum,
            condition: .totalMinutes(12000)
        ),
        Achievement(
            id: "hundred_days",
            name: "百日维新",
            description: "连续 100 天阅读",
            icon: "star.circle",
            tier: .platinum,
            condition: .consecutiveDays(100)
        ),
        Achievement(
            id: "complete_five",
            name: "善始善终",
            description: "完整读完 5 本书（100% 进度）",
            icon: "flag.checkered",
            tier: .platinum,
            condition: .completionRate(1.0)
        ),
    ]
}

// MARK: - SwiftData Model

@Model
public final class AchievementRecord {
    public var id: String
    public var name: String
    public var unlockedAt: Date

    public init(id: String, name: String, unlockedAt: Date) {
        self.id = id
        self.name = name
        self.unlockedAt = unlockedAt
    }
}
