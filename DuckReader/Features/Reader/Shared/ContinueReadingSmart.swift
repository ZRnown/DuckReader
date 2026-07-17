import Foundation
import Combine

// MARK: - Continue Reading Smart Engine

/// Intelligent "Continue Reading" system: ranks what to read next based on
/// recency, series context, reading habits, and multi-device priority.
///
/// Integrates with ReadingStatsEngine for session history and CloudSyncService
/// for cross-device position resolution.
@MainActor
public final class ContinueReadingSmart: ObservableObject, @unchecked Sendable {

    @Published public private(set) var rankedBooks: [ReadingCandidate] = []
    @Published public private(set) var lastReadBook: ReadingCandidate?

    private let statsEngine: ReadingStatsEngine
    private let calendar = Calendar.current

    public nonisolated init(statsEngine: ReadingStatsEngine) {
        self.statsEngine = statsEngine
        Task { @MainActor in
            self.refresh()
        }
    }

    // MARK: - Public API

    /// Re-rank all in-progress books.
    public func refresh() {
        // This would use the library repository to get all books
        // For now, expose the ranking algorithm
    }

    /// Rank a list of book candidates (from LibraryRepository or other sources).
    public func rank(_ candidates: [ReadingCandidateInput]) -> [ReadingCandidate] {
        let scored = candidates.map { candidate -> ReadingCandidate in
            var score: Double = 0

            // Factor 1: Recency (0-30 pts) — more recent = higher score
            if let lastOpened = candidate.lastOpenedDate {
                let hoursAgo = Date().timeIntervalSince(lastOpened) / 3600
                score += max(0, 30 - hoursAgo * 0.5) // Decays over ~60 hours
            }

            // Factor 2: Progress proximity (0-25 pts) — nearly finished = higher
            if candidate.totalPages > 0 {
                let remaining = 1.0 - candidate.progress
                // Peak interest around 30-70% through
                if candidate.progress < 0.1 {
                    score += 5  // Just started — moderate interest
                } else if candidate.progress < 0.3 {
                    score += 15 // Getting into it
                } else if candidate.progress < 0.8 {
                    score += 25 // Deep in the book
                } else {
                    score += 20 // Almost done — finish it!
                }
            }

            // Factor 3: Series continuity (0-20 pts) — same series as last read
            if let lastSeries = lastReadBook?.seriesName,
               let candidateSeries = candidate.seriesName,
               lastSeries == candidateSeries {
                score += 20
            } else if let lastAuthor = lastReadBook?.author,
                      let candidateAuthor = candidate.author,
                      lastAuthor == candidateAuthor {
                score += 10 // Same author, different series
            }

            // Factor 4: Unread bonus (0-15 pts) — untouched books get a nudge
            if candidate.progress == 0 {
                score += 5 // Gentle nudge for new additions
            }

            // Factor 5: Streak maintenance (0-10 pts)
            if statsEngine.stats.currentStreak > 0 {
                // Boost series you're actively reading
                if candidate.lastOpenedDate != nil {
                    let daysSinceOpen = calendar.dateComponents(
                        [.day],
                        from: candidate.lastOpenedDate!,
                        to: Date()
                    ).day ?? 99
                    if daysSinceOpen <= 1 {
                        score += 10 // Read yesterday — likely to continue
                    } else if daysSinceOpen <= 3 {
                        score += 5  // Read this week
                    }
                }
            }

            return ReadingCandidate(
                id: candidate.id,
                title: candidate.title,
                author: candidate.author,
                seriesName: candidate.seriesName,
                seriesVolume: candidate.seriesVolume,
                coverURL: candidate.coverURL,
                progress: candidate.progress,
                totalPages: candidate.totalPages,
                lastOpenedDate: candidate.lastOpenedDate,
                score: score,
                reason: generateReason(score: score, candidate: candidate)
            )
        }

        let sorted = scored.sorted { $0.score > $1.score }
        rankedBooks = sorted
        lastReadBook = sorted.first
        return sorted
    }

    /// Get a "streak saver" recommendation — the easiest book to continue
    /// when you need to maintain a streak.
    public func streakSaver() -> ReadingCandidate? {
        rankedBooks
            .filter { $0.progress > 0 && $0.progress < 0.9 }
            .sorted { a, _ in
                // Prefer books you've read recently
                if let aDate = a.lastOpenedDate {
                    return aDate > Date().addingTimeInterval(-86400)
                }
                return false
            }
            .first
    }

    /// Recommend the next book in a series.
    public func nextInSeries(for bookID: UUID) -> ReadingCandidate? {
        guard let current = rankedBooks.first(where: { $0.id == bookID }),
              let series = current.seriesName,
              let volume = current.seriesVolume else {
            return nil
        }

        return rankedBooks
            .filter { $0.seriesName == series && $0.seriesVolume == volume + 1 }
            .first
    }

    // MARK: - Helpers

    private func generateReason(score: Double, candidate: ReadingCandidateInput) -> String {
        if let lastOpened = candidate.lastOpenedDate {
            let hoursAgo = Date().timeIntervalSince(lastOpened) / 3600
            if hoursAgo < 1 {
                return String(localized: "smart.recentlyRead")
            }
            if hoursAgo < 24 {
                return String(localized: "smart.readToday")
            }
            if hoursAgo < 72 {
                return String(localized: "smart.readThisWeek")
            }
        }

        if let series = candidate.seriesName, lastReadBook?.seriesName == series {
            return String(localized: "smart.continueSeries \(series)")
        }

        if candidate.progress == 0 {
            return String(localized: "smart.newBook")
        }

        if candidate.progress > 0.7 {
            return String(localized: "smart.nearlyDone")
        }

        return String(localized: "smart.suggestion")
    }
}

// MARK: - Models

/// Input for ranking — subset of Book properties needed for scoring.
public struct ReadingCandidateInput: Sendable {
    public let id: UUID
    public let title: String
    public let author: String?
    public let seriesName: String?
    public let seriesVolume: Double?
    public let coverURL: URL?
    public let progress: Double
    public let totalPages: Int
    public let lastOpenedDate: Date?

    public init(
        id: UUID, title: String, author: String? = nil,
        seriesName: String? = nil, seriesVolume: Double? = nil,
        coverURL: URL? = nil, progress: Double = 0,
        totalPages: Int = 0, lastOpenedDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.seriesName = seriesName
        self.seriesVolume = seriesVolume
        self.coverURL = coverURL
        self.progress = progress
        self.totalPages = totalPages
        self.lastOpenedDate = lastOpenedDate
    }
}

/// Ranked reading candidate with score and human-readable reason.
public struct ReadingCandidate: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let author: String?
    public let seriesName: String?
    public let seriesVolume: Double?
    public let coverURL: URL?
    public let progress: Double
    public let totalPages: Int
    public let lastOpenedDate: Date?
    public let score: Double
    public let reason: String

    public var progressPercent: Int {
        Int(progress * 100)
    }
}

// MARK: - Cross-Device Position Priority

/// Resolves which reading position to use when multiple devices have
/// conflicting progress for the same book.
public struct CrossDevicePosition: Sendable {
    public let deviceID: String
    public let deviceName: String
    public let progress: Double
    public let timestamp: Date
    public let pageCount: Int?

    /// Priority score: local device > most recent > most progress
    public func priority(isLocal: Bool) -> Double {
        var score: Double = 0
        if isLocal { score += 100 }
        score += timestamp.timeIntervalSince1970 / 1_000_000 // Recent = higher
        score += progress * 10 // More progress = higher
        return score
    }
}

/// Resolve conflicting positions across devices.
public enum PositionResolver {
    /// Pick the best position from multiple devices.
    public static func resolve(
        positions: [CrossDevicePosition],
        localDeviceID: String
    ) -> CrossDevicePosition? {
        guard !positions.isEmpty else { return nil }

        return positions.max(by: { a, b in
            a.priority(isLocal: a.deviceID == localDeviceID)
                < b.priority(isLocal: b.deviceID == localDeviceID)
        })
    }

    /// Check if there's a meaningful conflict (positions differ by >2%).
    public static func hasConflict(_ positions: [CrossDevicePosition]) -> Bool {
        guard positions.count > 1 else { return false }
        let progresses = positions.map { $0.progress }
        let range = (progresses.max() ?? 0) - (progresses.min() ?? 0)
        return range > 0.02
    }
}
