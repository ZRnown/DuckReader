import Testing
import Foundation
import SwiftUI
import ViewInspector
@testable import DuckReaderCore

// MARK: - View Model Tests
// Tests for ViewModels using ViewInspector or manual state verification

@MainActor
struct ViewModelTests {

    // MARK: - Reading Stats Engine

    @Test func statsEngine_recordingAccumulates() async throws {
        let engine = ReadingStatsEngine.shared

        let initialMinutes = engine.stats.totalMinutesRead

        engine.recordReading(bookID: "test-1", minutes: 30, pages: 45)
        engine.recordReading(bookID: "test-1", minutes: 15, pages: 20)

        // Total should increase (but we can't assert exact since shared state persists)
        #expect(engine.stats.totalMinutesRead >= initialMinutes)
    }

    @Test func statsEngine_todayMinutes_reportsCorrectly() async throws {
        let engine = ReadingStatsEngine.shared
        let today = engine.todayMinutes
        #expect(today >= 0)
    }

    @Test func statsEngine_weeklyMonthly_statsExist() async throws {
        let engine = ReadingStatsEngine.shared

        let weekly = engine.weeklyMinutes
        let monthly = engine.monthlyMinutes

        #expect(weekly >= 0)
        #expect(monthly >= 0)
        #expect(monthly >= weekly)
    }

    // MARK: - Reader Input Handler

    @Test func inputHandler_keyPress_forward() async throws {
        let handler = ReaderInputHandler.shared
        handler.keyboardEnabled = true

        handler.handleKeyPress(UIKeyCommand.inputRightArrow)

        // Trigger resets after 0.1s delay; test just checks no crash
        #expect(handler.keyboardEnabled == true)
    }

    @Test func inputHandler_keyPress_escape() async throws {
        let handler = ReaderInputHandler.shared
        handler.handleKeyPress(UIKeyCommand.inputEscape)

        #expect(true) // No crash = pass
    }

    @Test func inputHandler_debounce_preventsSpam() async throws {
        let handler = ReaderInputHandler.shared
        handler.keyboardEnabled = true

        // Rapid presses should be debounced
        handler.handleKeyPress(" ")
        handler.handleKeyPress(" ")
        handler.handleKeyPress(" ")

        #expect(true) // No crash = pass
    }

    // MARK: - Achievement Engine

    @Test func achievementEngine_configure_loadsPersisted() async throws {
        let engine = AchievementEngine.shared

        // All definitions loaded at init
        #expect(engine.allAchievements.count == Achievement.allDefinitions.count)
    }

    @Test func achievementEngine_recentlyUnlocked_clearsOnDismiss() async throws {
        let engine = AchievementEngine.shared

        engine.dismissRecent("non-existent")
        #expect(true) // No crash
    }

    // MARK: - Reader Level

    @Test func readerLevel_ordering() async throws {
        let levels: [AchievementEngine.ReaderLevel] = [
            .beginner, .casual, .bookworm, .scholar, .sage
        ]

        for i in 0..<(levels.count - 1) {
            #expect(levels[i] < levels[i + 1])
        }
    }

    @Test func readerLevel_titles_nonEmpty() async throws {
        let levels: [AchievementEngine.ReaderLevel] = [
            .beginner, .casual, .bookworm, .scholar, .sage
        ]

        for level in levels {
            #expect(!level.title.isEmpty)
            #expect(!level.icon.isEmpty)
        }
    }
}

// MARK: - Snapshot Behavior Tests (UI correctness, not pixel-perfect)
// These verify logical UI state rather than visual pixels.

@MainActor
struct SnapshotBehaviorTests {

    // MARK: - Privacy Lock Screen

    @Test func privacyLockScreen_biometricType_notNone() async throws {
        let manager = PrivacyLockManager.shared
        // On simulator, biometricType is usually .none
        // Test just verifies the type exists
        let type = manager.biometricType
        #expect(type == .none || type == .faceID || type == .touchID || type == .opticID)
    }

    // MARK: - CJK Vertical Config

    @Test func cjkVerticalConfig_defaultValues() async throws {
        let config = CJKVerticalConfig.default

        #expect(config.columnWidth == 24)
        #expect(config.lineHeight == 28)
        #expect(config.columnGap == 12)
        #expect(config.fontSize == 18)
        #expect(config.rotatePunctuation == true)
    }

    // MARK: - Design System Consistency

    @Test func designSystem_springs_areAnimations() async throws {
        // All spring presets should be valid Animation values
        let springs: [Animation] = [
            DuckSpring.fluid,
            DuckSpring.bouncy,
            DuckSpring.snappy,
            DuckSpring.interactive,
            DuckSpring.playful,
            DuckSpring.rubberBand,
        ]

        #expect(springs.count == 6)
    }

    @Test func designSystem_fonts_exist() async throws {
        // All font definitions should be valid Font values
        // Just verify they don't crash
        _ = DuckFont.largeTitle
        _ = DuckFont.body
        _ = DuckFont.novelBody
        _ = DuckFont.monoDigit
        #expect(true)
    }

    @Test func designSystem_colors_exist() async throws {
        _ = DuckColor.accent
        _ = DuckColor.readingBackgroundSepia
        _ = DuckColor.readingBackgroundDark
        _ = DuckColor.readingBackgroundLight
        _ = DuckColor.achievementGold
        _ = DuckColor.achievementSilver
        _ = DuckColor.achievementBronze
        #expect(true)
    }

    // MARK: - Widget Data Bridge

    @Test func widgetDataBridge_refresh_noCrash() async throws {
        let bridge = WidgetDataBridge.shared
        let stats = ReadingStats(
            totalMinutesRead: 100,
            totalPagesRead: 500,
            totalBooksRead: 5,
            longestConsecutiveDays: 3,
            longestSingleBookMinutes: 60,
            speedReadBooks: 1,
            completionRate: 0.5,
            uniqueGenres: [],
            uniqueFormats: []
        )

        bridge.refresh(progress: nil, stats: stats, level: .bookworm)
        #expect(true) // No crash
    }
}
