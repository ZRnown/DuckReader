import SwiftUI
import Combine

// MARK: - Platform-Specific Features (Mac / iPad)

/// Mac Catalyst and iPad-exclusive features: keyboard shortcuts,
/// multi-window support, trackpad gestures, Stage Manager awareness.
///
/// All features degrade gracefully on iPhone.

// MARK: - Keyboard Shortcut Catalog

/// Complete keyboard shortcut definitions for the reading experience.
/// Register in SwiftUI with `.keyboardShortcut()` modifiers.
public enum DuckShortcuts {

    // MARK: - Navigation

    public static let nextPage = KeyEquivalent.rightArrow
    public static let prevPage = KeyEquivalent.leftArrow
    public static let nextChapter = KeyEquivalent.downArrow
    public static let prevChapter = KeyEquivalent.upArrow
    public static let jumpToStart = KeyEquivalent("1")
    public static let jumpToEnd = KeyEquivalent("0")

    // MARK: - Tools

    public static let togglePanelMode = KeyEquivalent("p")
    public static let toggleFullscreen = KeyEquivalent("f")
    public static let toggleTTS = KeyEquivalent("s")
    public static let addBookmark = KeyEquivalent("d")
    public static let annotation = KeyEquivalent("a")
    public static let search = KeyEquivalent("l")

    // MARK: - View

    public static let zoomIn = KeyEquivalent("=")
    public static let zoomOut = KeyEquivalent("-")
    public static let zoomReset = KeyEquivalent("0")
    public static let toggleSidebar = KeyEquivalent("b")
    public static let toggleInspector = KeyEquivalent("i")

    // MARK: - Library

    public static let library = KeyEquivalent("1")
    public static let importBook = KeyEquivalent("o")
    public static let editBook = KeyEquivalent("e")

    // MARK: - Shortcut Groups

    public struct ShortcutGroup: Identifiable, Sendable {
        public let id = UUID()
        public let name: String
        public let shortcuts: [ShortcutItem]
    }

    public struct ShortcutItem: Identifiable, Sendable {
        public let id = UUID()
        public let name: String
        public let key: String
        public let modifiers: EventModifiers

        public var displayKey: String {
            var parts: [String] = []
            if modifiers.contains(.command) { parts.append("⌘") }
            if modifiers.contains(.option) { parts.append("⌥") }
            if modifiers.contains(.shift) { parts.append("⇧") }
            if modifiers.contains(.control) { parts.append("⌃") }
            parts.append(key.uppercased())
            return parts.joined()
        }
    }

    /// Catalog of all available shortcuts for the help/cheatsheet view.
    public static let catalog: [ShortcutGroup] = [
        ShortcutGroup(name: String(localized: "shortcuts.navigation"), shortcuts: [
            ShortcutItem(name: String(localized: "shortcuts.nextPage"), key: "→", modifiers: []),
            ShortcutItem(name: String(localized: "shortcuts.prevPage"), key: "←", modifiers: []),
            ShortcutItem(name: String(localized: "shortcuts.nextChapter"), key: "⌘→", modifiers: []),
            ShortcutItem(name: String(localized: "shortcuts.prevChapter"), key: "⌘←", modifiers: []),
            ShortcutItem(name: String(localized: "shortcuts.startOfBook"), key: "⌘↑", modifiers: []),
            ShortcutItem(name: String(localized: "shortcuts.endOfBook"), key: "⌘↓", modifiers: []),
        ]),
        ShortcutGroup(name: String(localized: "shortcuts.tools"), shortcuts: [
            ShortcutItem(name: String(localized: "shortcuts.panelMode"), key: "P", modifiers: [.command, .shift]),
            ShortcutItem(name: String(localized: "shortcuts.fullscreen"), key: "F", modifiers: [.command, .shift]),
            ShortcutItem(name: String(localized: "shortcuts.tts"), key: "S", modifiers: [.command, .option]),
            ShortcutItem(name: String(localized: "shortcuts.bookmark"), key: "D", modifiers: .command),
            ShortcutItem(name: String(localized: "shortcuts.search"), key: "F", modifiers: .command),
        ]),
        ShortcutGroup(name: String(localized: "shortcuts.view"), shortcuts: [
            ShortcutItem(name: String(localized: "shortcuts.zoomIn"), key: "⌘+", modifiers: []),
            ShortcutItem(name: String(localized: "shortcuts.zoomOut"), key: "⌘-", modifiers: []),
            ShortcutItem(name: String(localized: "shortcuts.sidebar"), key: "⌘B", modifiers: []),
        ]),
    ]
}

// MARK: - Multi-Window Support

/// Multi-window scene management for iPad & Mac.
/// Allows opening multiple books side-by-side.
@MainActor
public final class MultiWindowManager: ObservableObject {

    @Published public private(set) var openWindows: [WindowSession] = []

    /// Open a book in a new window.
    public func openInNewWindow(bookID: UUID, title: String) {
        #if os(iOS)
        let activity = NSUserActivity(activityType: "com.duckreader.openBook")
        activity.userInfo = ["bookID": bookID.uuidString, "title": title]
        UIApplication.shared.requestSceneSessionActivation(
            nil,
            userActivity: activity,
            options: nil
        )
        #endif
    }

    /// Register a new window session.
    public func registerWindow(_ session: WindowSession) {
        openWindows.append(session)
    }

    /// Remove a closed window session.
    public func unregisterWindow(bookID: UUID) {
        openWindows.removeAll { $0.bookID == bookID }
    }

    /// Check if a book is already open in another window.
    public func isBookOpen(bookID: UUID) -> Bool {
        openWindows.contains { $0.bookID == bookID }
    }
}

/// A reading session tied to a specific window/scene.
public struct WindowSession: Identifiable, Sendable {
    public let id: UUID
    public let bookID: UUID
    public let title: String
    public let openedAt: Date

    public init(bookID: UUID, title: String) {
        self.id = UUID()
        self.bookID = bookID
        self.title = title
        self.openedAt = Date()
    }
}

// MARK: - Trackpad & Pointer Gestures

/// Trackpad gesture configuration for iPad with Magic Keyboard / Mac.
public struct TrackpadGestures {

    /// Two-finger swipe left/right → page turn.
    public static let pageTurnSwipe: Bool = true

    /// Pinch to zoom.
    public static let pinchToZoom: Bool = true
    public static let zoomRange: ClosedRange<CGFloat> = 0.5...3.0

    /// Three-finger tap → toggle fullscreen.
    public static let threeFingerTapForFullscreen: Bool = true

    /// Trackpad scroll inertia for seamless scrolling.
    public static let scrollInertia: CGFloat = 0.95

    /// Hover effect on panels (iPad cursor).
    public static let panelHoverHighlight: Bool = true

    /// Pointer style for different reading zones.
    public enum ReadingPointerStyle: Sendable {
        case pageTurn      // Arrow with left/right indicators
        case panelZoom     // Magnifying glass
        case annotation    // Crosshair
        case textSelect    // I-beam
    }
}

// MARK: - Stage Manager Awareness

/// Adapts layout for Stage Manager on iPad.
public struct StageManagerLayout {

    /// Detect if Stage Manager is active.
    public static var isActive: Bool {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        // Stage Manager is active when the scene is in a resizeable window
        // Simple heuristic: check if the app is not fullscreen
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let screenSize = windowScene.screen.bounds.size
            let windowSize = windowScene.coordinateSpace.bounds.size
            // If window is significantly smaller than screen, Stage Manager likely active
            let widthRatio = windowSize.width / screenSize.width
            return widthRatio < 0.95
        }
        return false
        #else
        return false
        #endif
    }

    /// Adapt page layout for current window size.
    public static func adaptiveLayout(size: CGSize) -> PageLayoutMode {
        switch size.width {
        case ..<600:
            return .singlePage
        case 600..<900:
            return .singlePageWithSidebar
        default:
            return .doublePage
        }
    }

    public enum PageLayoutMode {
        case singlePage
        case singlePageWithSidebar
        case doublePage
    }
}

// MARK: - Platform Capabilities

/// Query platform-specific capabilities.
public enum PlatformCapabilities {

    /// Whether keyboard shortcuts are available (Mac / iPad with keyboard).
    public static var hasKeyboard: Bool {
        #if targetEnvironment(macCatalyst) || os(macOS)
        return true
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    /// Whether multi-window is supported.
    public static var supportsMultiWindow: Bool {
        #if os(macOS) || targetEnvironment(macCatalyst)
        return true
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    /// Whether trackpad gestures are available.
    public static var hasTrackpad: Bool {
        #if os(macOS)
        return true
        #else
        // iPad: assume Magic Keyboard or trackpad case possible
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    /// Whether drag-and-drop import is supported.
    public static var supportsDragAndDrop: Bool {
        true // All current platforms
    }

    /// Whether Live Text (OCR in images) is available.
    public static var supportsLiveText: Bool {
        if #available(iOS 16.0, macOS 13.0, *) {
            return true
        }
        return false
    }
}

// MARK: - Mac-Only: Menu Bar Extra

#if os(macOS)
/// Menu bar extra for quick access to reading stats and recent books.
@MainActor
public final class MenuBarExtraManager: ObservableObject {
    @Published public var todayReadingMinutes: Int = 0
    @Published public var streakDays: Int = 0
    @Published public var recentBooks: [String] = []

    public nonisolated init() {}
}
#endif

// MARK: - Mac-Only: Touch Bar Support

#if os(macOS) || targetEnvironment(macCatalyst)
/// Touch Bar controls for reading navigation.
/// Provide via `touchBar` in the view hierarchy.
public struct ReadingTouchBar: View {
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onBookmark: () -> Void
    let onTTS: () -> Void
    let progress: Double

    public var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
            }

            Button(action: onBookmark) {
                Image(systemName: "bookmark")
            }

            ProgressView(value: progress)
                .frame(width: 200)

            Button(action: onTTS) {
                Image(systemName: "speaker.wave.2")
            }

            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
        }
        .buttonStyle(.borderless)
    }

    public init(
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onBookmark: @escaping () -> Void,
        onTTS: @escaping () -> Void,
        progress: Double
    ) {
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onBookmark = onBookmark
        self.onTTS = onTTS
        self.progress = progress
    }
}
#endif
