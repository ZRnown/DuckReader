import Foundation
import SwiftUI

// MARK: - Chapter Info

/// A chapter within a book, with navigation metadata.
public struct ChapterInfo: Identifiable, Equatable, Sendable {
    public let id: String              // Internal ref (e.g., EPUB spine idref)
    public let index: Int              // 0-based chapter index
    public let title: String
    public let href: String?           // EPUB internal href
    public let pageStart: Int          // First page index of this chapter
    public let pageEnd: Int            // Last page index (exclusive)
    public let estimatedReadingTime: TimeInterval  // seconds
    public let wordCount: Int?

    public var pageCount: Int {
        pageEnd - pageStart
    }

    public var readingTimeFormatted: String {
        let mins = Int(estimatedReadingTime / 60)
        if mins < 1 { return "< 1 min" }
        if mins < 60 { return "\(mins) min" }
        let h = mins / 60
        let m = mins % 60
        return "\(h)h \(m)m"
    }

    public init(
        id: String,
        index: Int,
        title: String,
        href: String? = nil,
        pageStart: Int = 0,
        pageEnd: Int = 0,
        estimatedReadingTime: TimeInterval = 0,
        wordCount: Int? = nil
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.href = href
        self.pageStart = pageStart
        self.pageEnd = pageEnd
        self.estimatedReadingTime = estimatedReadingTime
        self.wordCount = wordCount
    }
}

// MARK: - Chapter Progress

/// Reading progress per chapter.
public struct ChapterProgress: Codable, Equatable, Sendable {
    public let chapterIndex: Int
    public let chapterID: String
    public let progress: Double        // 0.0–1.0
    public let lastReadAt: Date
    public let readCount: Int          // How many times this chapter was opened

    public init(
        chapterIndex: Int,
        chapterID: String,
        progress: Double = 0,
        lastReadAt: Date = Date(),
        readCount: Int = 1
    ) {
        self.chapterIndex = chapterIndex
        self.chapterID = chapterID
        self.progress = progress
        self.lastReadAt = lastReadAt
        self.readCount = readCount
    }
}

// MARK: - Chapter Navigation Model

/// Provides optimized chapter navigation: jump, progress tracking, preloading.
/// Drives the chapter list UI and keyboard shortcut routing.
@MainActor
public final class ChapterNavigationModel: ObservableObject, Sendable {

    @Published public var chapters: [ChapterInfo] = []
    @Published public var currentChapterIndex: Int = 0
    @Published public var chapterProgress: [String: ChapterProgress] = [:]  // keyed by chapter ID
    @Published public var isChapterListVisible: Bool = false

    public var currentChapter: ChapterInfo? {
        guard currentChapterIndex >= 0, currentChapterIndex < chapters.count else { return nil }
        return chapters[currentChapterIndex]
    }

    public nonisolated init() {}

    // MARK: - Load

    public func loadChapters(_ chapters: [ChapterInfo]) {
        self.chapters = chapters
        if !chapters.isEmpty {
            currentChapterIndex = 0
        }
    }

    // MARK: - Navigation

    public func jumpToChapter(_ index: Int) -> Bool {
        guard index >= 0, index < chapters.count else { return false }
        currentChapterIndex = index
        return true
    }

    public func jumpToChapter(id: String) -> Bool {
        guard let idx = chapters.firstIndex(where: { $0.id == id }) else { return false }
        currentChapterIndex = idx
        return true
    }

    public func nextChapter() -> Bool {
        guard currentChapterIndex < chapters.count - 1 else { return false }
        currentChapterIndex += 1
        return true
    }

    public func previousChapter() -> Bool {
        guard currentChapterIndex > 0 else { return false }
        currentChapterIndex -= 1
        return true
    }

    /// Jump to chapter by title prefix match.
    public func jumpToChapter(titlePrefix: String) -> Bool {
        guard let idx = chapters.firstIndex(where: {
            $0.title.localizedCaseInsensitiveContains(titlePrefix)
        }) else { return false }
        currentChapterIndex = idx
        return true
    }

    // MARK: - Progress

    public func updateProgress(chapterID: String, progress: Double) {
        var cp = chapterProgress[chapterID] ?? ChapterProgress(
            chapterIndex: chapters.first(where: { $0.id == chapterID })?.index ?? 0,
            chapterID: chapterID,
            progress: progress
        )
        cp = ChapterProgress(
            chapterIndex: cp.chapterIndex,
            chapterID: cp.chapterID,
            progress: min(1.0, max(0, progress)),
            lastReadAt: Date(),
            readCount: cp.readCount + 1
        )
        chapterProgress[chapterID] = cp
    }

    /// Overall book progress (0.0–1.0).
    public var overallProgress: Double {
        guard !chapters.isEmpty else { return 0 }
        let totalProgress = chapterProgress.values.reduce(0.0) { $0 + $1.progress }
        return totalProgress / Double(chapters.count)
    }

    /// Next unread (or partially-read) chapter index.
    public func firstUnreadChapter() -> Int? {
        for (idx, ch) in chapters.enumerated() {
            let p = chapterProgress[ch.id]?.progress ?? 0
            if p < 1.0 { return idx }
        }
        return nil
    }

    // MARK: - Chapter List Data

    /// Formatted list of chapters with progress for UI display.
    public var chapterListItems: [ChapterListItem] {
        chapters.enumerated().map { (idx, ch) in
            let progress = chapterProgress[ch.id]?.progress ?? 0
            let isCurrent = idx == currentChapterIndex
            return ChapterListItem(
                chapter: ch,
                progress: progress,
                isCurrent: isCurrent
            )
        }
    }

    /// Search chapters by title.
    public func searchChapters(query: String) -> [ChapterListItem] {
        guard !query.isEmpty else { return chapterListItems }
        return chapterListItems.filter {
            $0.chapter.title.localizedCaseInsensitiveContains(query)
        }
    }
}

// MARK: - Chapter List Item (UI Model)

public struct ChapterListItem: Identifiable, Equatable, Sendable {
    public let chapter: ChapterInfo
    public let progress: Double
    public let isCurrent: Bool

    public var id: String { chapter.id }
}

// MARK: - Keyboard Shortcuts (iPad)

/// Keyboard shortcut definitions for chapter navigation on iPad.
public enum ChapterKeyboardShortcut: String, CaseIterable, Sendable {
    case nextChapter = "⌘→"
    case previousChapter = "⌘←"
    case toggleChapterList = "⌘L"
    case jumpToStart = "⌘↑"
    case jumpToEnd = "⌘↓"

    public var key: KeyEquivalent {
        switch self {
        case .nextChapter: return .rightArrow
        case .previousChapter: return .leftArrow
        case .toggleChapterList: return "l"
        case .jumpToStart: return .upArrow
        case .jumpToEnd: return .downArrow
        }
    }

    public var modifiers: EventModifiers {
        switch self {
        case .toggleChapterList: return .command
        default: return .command
        }
    }
}

// MARK: - Chapter List View Modifier

/// A SwiftUI view modifier that adds chapter navigation keyboard shortcuts.
public struct ChapterNavigationShortcuts: ViewModifier {
    @ObservedObject var navigation: ChapterNavigationModel

    public func body(content: Content) -> some View {
        content
            .keyboardShortcut(ChapterKeyboardShortcut.nextChapter.key, modifiers: ChapterKeyboardShortcut.nextChapter.modifiers)
            .keyboardShortcut(ChapterKeyboardShortcut.previousChapter.key, modifiers: ChapterKeyboardShortcut.previousChapter.modifiers)
            .keyboardShortcut(ChapterKeyboardShortcut.toggleChapterList.key, modifiers: ChapterKeyboardShortcut.toggleChapterList.modifiers)
            .onKeyPress(.rightArrow, modifiers: .command) {
                _ = navigation.nextChapter()
                return .handled
            }
            .onKeyPress(.leftArrow, modifiers: .command) {
                _ = navigation.previousChapter()
                return .handled
            }
    }
}

public extension View {
    func chapterNavigationShortcuts(_ model: ChapterNavigationModel) -> some View {
        modifier(ChapterNavigationShortcuts(navigation: model))
    }
}

// MARK: - Environment Key

public struct ChapterNavigationKey: EnvironmentKey {
    public static let defaultValue: ChapterNavigationModel = ChapterNavigationModel()
}

public extension EnvironmentValues {
    var chapterNavigation: ChapterNavigationModel {
        get { self[ChapterNavigationKey.self] }
        set { self[ChapterNavigationKey.self] = newValue }
    }
}
