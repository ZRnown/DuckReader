import Foundation
import SwiftUI

// MARK: - Reading Mode Enum

/// All supported reading modes.
public enum ReadingMode: String, CaseIterable, Sendable, Codable {
    /// Right-to-left single page (manga)
    case mangaSingle = "manga_single"
    /// Right-to-left double spread
    case mangaDouble = "manga_double"
    /// Left-to-right single page (Western comics)
    case westernSingle = "western_single"
    /// Left-to-right double spread
    case westernDouble = "western_double"
    /// Vertical continuous scroll (webtoon)
    case webtoonScroll = "webtoon_scroll"
    /// Panel-by-panel guided reading
    case panelGuide = "panel_guide"
    /// Novel mode (reflowable text)
    case novel = "novel"

    /// The base reading direction.
    public enum Direction: String, Sendable {
        case rightToLeft
        case leftToRight
        case vertical
    }

    public var direction: Direction {
        switch self {
        case .mangaSingle, .mangaDouble, .panelGuide: return .rightToLeft
        case .westernSingle, .westernDouble: return .leftToRight
        case .webtoonScroll: return .vertical
        case .novel: return .vertical
        }
    }

    public var isSpreadMode: Bool {
        self == .mangaDouble || self == .westernDouble
    }

    public var isScrollMode: Bool {
        self == .webtoonScroll || self == .novel
    }
}

// MARK: - Content Type Detection

/// Detected content type for smart mode switching.
public enum DetectedContentType: Sendable {
    case manga         // Japanese manga (B&W, panel-heavy, right-to-left)
    case westernComic  // Western comics (color, varied layouts, left-to-right)
    case webtoon       // Korean/Chinese webtoon (vertical scroll format)
    case novel         // Reflowable text (EPUB/TXT/Markdown)
    case mixed         // Could not confidently classify
}

// MARK: - Device Context

/// Current device context for mode decision.
public struct DeviceContext: Sendable {
    public let idiom: UIUserInterfaceIdiom
    public let orientation: UIDeviceOrientation
    public let screenSize: CGSize
    public let isProMotion: Bool
    public let hasLargeScreen: Bool

    public init(
        idiom: UIUserInterfaceIdiom = .phone,
        orientation: UIDeviceOrientation = .portrait,
        screenSize: CGSize = .zero,
        isProMotion: Bool = false
    ) {
        self.idiom = idiom
        self.orientation = orientation
        self.screenSize = screenSize
        self.isProMotion = isProMotion
        self.hasLargeScreen = idiom == .pad || screenSize.width >= 1024
    }

    /// Whether a double-spread mode is appropriate given the device.
    public var supportsDoubleSpread: Bool {
        if idiom == .pad { return true }
        return orientation == .landscapeLeft || orientation == .landscapeRight
    }
}

// MARK: - User Reading Habit Profile

/// Learns the user's reading preferences over time.
public struct UserReadingHabits: Codable, Sendable {
    /// Counter per mode, keyed by ReadingMode rawValue
    public var modeUsage: [String: Int] = [:]
    /// Preferred mode per content type, keyed by DetectedContentType hash
    public var contentTypePreference: [String: ReadingMode] = [:]
    /// How many sessions recorded
    public var totalSessions: Int = 0
    /// Last-used mode
    public var lastMode: ReadingMode?

    public init() {}

    public mutating func recordMode(_ mode: ReadingMode, for contentType: DetectedContentType) {
        modeUsage[mode.rawValue, default: 0] += 1
        contentTypePreference[contentType.key] = mode
        lastMode = mode
        totalSessions += 1
    }

    public func preferredMode(for contentType: DetectedContentType) -> ReadingMode? {
        contentTypePreference[contentType.key]
    }
}

private extension DetectedContentType {
    var key: String {
        switch self {
        case .manga: return "manga"
        case .westernComic: return "western"
        case .webtoon: return "webtoon"
        case .novel: return "novel"
        case .mixed: return "mixed"
        }
    }
}

// MARK: - Smart Mode Switcher

/// Intelligent mode switching engine that selects the optimal reading mode
/// based on device context, content characteristics, and learned user habits.
///
/// Decision priority:
/// 1. User override (explicit mode selection)
/// 2. Learned habit for this content type
/// 3. Content-type heuristics
/// 4. Device-context fallback
public final class SmartModeSwitcher: Sendable {

    private let habitsLock = OSAllocatedUnfairLock()
    private var _habits: UserReadingHabits
    /// Local cache keyed by content hash → detected type
    private var contentTypeCache: [Int: DetectedContentType] = [:]

    // K-nearest-neighbor classifier for content type detection
    // A simple heuristic: panel density + color distribution → type

    public var habits: UserReadingHabits {
        habitsLock.withLock { _habits }
    }

    public init(habits: UserReadingHabits = UserReadingHabits()) {
        self._habits = habits
    }

    // MARK: - Public API

    /// Determine the best reading mode for the given context.
    public func bestMode(
        contentType: DetectedContentType,
        device: DeviceContext,
        userOverride: ReadingMode? = nil
    ) -> ReadingMode {
        // 1. Honor explicit user override
        if let override = userOverride {
            return override
        }

        // 2. Check learned preference
        if let preferred = habits.preferredMode(for: contentType) {
            return adaptForDevice(preferred, device: device)
        }

        // 3. Heuristic based on content type
        let mode = defaultModeFor(contentType, device: device)

        // 4. Adapt for device constraints
        return adaptForDevice(mode, device: device)
    }

    /// Detect content type from file metadata and a sample page.
    public func detectContentType(
        format: String,
        hasColor: Bool,
        aspectRatio: CGFloat,
        pageCount: Int,
        language: String? = nil
    ) -> DetectedContentType {
        let fmt = format.lowercased()

        // Novel formats → novel
        if ["epub", "txt", "markdown", "md", "mobi"].contains(fmt) {
            return .novel
        }

        // Image-based formats → comic analysis
        let lang = language ?? ""

        // Webtoon detection: very tall strip format
        if aspectRatio < 0.45 && pageCount > 1 {
            return .webtoon
        }

        // Manga detection: Japanese/Korean origin + B&W
        if lang.hasPrefix("ja") || lang.hasPrefix("ko") || !hasColor {
            return .manga
        }

        // Western comic: color + English/European language + varied aspect
        if hasColor && (lang.hasPrefix("en") || lang.isEmpty) {
            return .westernComic
        }

        return .mixed
    }

    /// Record a mode choice to improve future predictions.
    public func recordChoice(
        mode: ReadingMode,
        contentType: DetectedContentType,
        contentHash: Int? = nil
    ) {
        habitsLock.withLock {
            _habits.recordMode(mode, for: contentType)
        }
        if let hash = contentHash {
            contentTypeCache[hash] = contentType
        }
    }

    /// Suggest an optimal mode transition (e.g., on rotation).
    public func suggestedTransition(
        currentMode: ReadingMode,
        newDevice: DeviceContext,
        contentType: DetectedContentType
    ) -> ReadingMode? {
        let candidate = bestMode(contentType: contentType, device: newDevice)

        // Only suggest if it's meaningfully different
        if candidate != currentMode && candidate.direction == currentMode.direction {
            return nil // same direction, not worth switching
        }
        return candidate != currentMode ? candidate : nil
    }

    // MARK: - Private Helpers

    private func defaultModeFor(
        _ type: DetectedContentType,
        device: DeviceContext
    ) -> ReadingMode {
        switch type {
        case .manga:
            return device.supportsDoubleSpread ? .mangaDouble : .mangaSingle
        case .westernComic:
            return device.supportsDoubleSpread ? .westernDouble : .westernSingle
        case .webtoon:
            return .webtoonScroll
        case .novel:
            return .novel
        case .mixed:
            // Fallback to single-page right-to-left (default for unknown manga)
            return .mangaSingle
        }
    }

    private func adaptForDevice(_ mode: ReadingMode, device: DeviceContext) -> ReadingMode {
        switch mode {
        case .mangaDouble, .westernDouble:
            if !device.supportsDoubleSpread {
                // Fall back to single page
                return mode == .mangaDouble ? .mangaSingle : .westernSingle
            }
            return mode
        case .mangaSingle, .westernSingle:
            // On iPad landscape, suggest double spread if the user hasn't
            // explicitly chosen single
            if device.supportsDoubleSpread && device.idiom == .pad {
                return mode == .mangaSingle ? .mangaDouble : .westernDouble
            }
            return mode
        default:
            return mode
        }
    }
}

// Note: OSAllocatedUnfairLock is available from iOS 18+ / macOS 15+, which is this project's deployment target.

// MARK: - SwiftUI Environment Integration

/// Environment key for the smart mode switcher.
public struct SmartModeSwitcherKey: EnvironmentKey {
    public static let defaultValue: SmartModeSwitcher = SmartModeSwitcher()
}

public extension EnvironmentValues {
    var smartModeSwitcher: SmartModeSwitcher {
        get { self[SmartModeSwitcherKey.self] }
        set { self[SmartModeSwitcherKey.self] = newValue }
    }
}

// MARK: - Mode Switch Analytics Event

/// Lightweight event for tracking mode switches.
public struct ModeSwitchEvent: Sendable {
    public let from: ReadingMode
    public let to: ReadingMode
    public let trigger: ModeSwitchTrigger
    public let timestamp: Date
    public let contentType: DetectedContentType

    public enum ModeSwitchTrigger: String, Sendable {
        case userExplicit   // User tapped mode button
        case deviceRotation // Device rotated
        case autoDetected   // Smart switcher changed it
        case contentChange  // Content type changed
    }
}
