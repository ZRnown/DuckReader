// MARK: - Widget Data Bridge
//
// Called from the main app to write widget-relevant data to shared UserDefaults
// (App Group: group.com.duckreader).
// Widgets read this on their timeline refresh.

import Foundation
import WidgetKit

@MainActor
public final class WidgetDataBridge {
    public static let shared = WidgetDataBridge()

    private let defaults = UserDefaults(suiteName: "group.com.duckreader")!

    private init() {}

    /// Update all widget data from current app state.
    public func refresh(progress: ReadingProgress?, stats: ReadingStats, level: AchievementEngine.ReaderLevel) {
        if let progress {
            defaults.set(progress.book.title, forKey: "currentBook")
            defaults.set(progress.book.author, forKey: "currentBookAuthor")
            defaults.set(progress.progress, forKey: "currentProgress")
        } else {
            defaults.removeObject(forKey: "currentBook")
            defaults.removeObject(forKey: "currentBookAuthor")
            defaults.set(0.0, forKey: "currentProgress")
        }

        defaults.set(stats.totalMinutesRead, forKey: "totalMinutes")
        defaults.set(stats.totalPagesRead, forKey: "totalPages")
        defaults.set(stats.totalBooksRead, forKey: "totalBooks")
        defaults.set(stats.longestConsecutiveDays, forKey: "currentStreak")
        defaults.set(level.title, forKey: "readerLevel")

        let engine = ReadingStatsEngine.shared
        defaults.set(engine.todayMinutes, forKey: "todayMinutes")

        // Trigger widget reload
        WidgetCenter.shared.reloadTimelines(ofKind: "com.duckreader.widget.progress")
        WidgetCenter.shared.reloadTimelines(ofKind: "com.duckreader.widget.lock")
    }
}
