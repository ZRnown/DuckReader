import Foundation
import SwiftUI

// MARK: - Gesture Zone Definition

/// A configurable tap zone on the reading surface.
public struct GestureZone: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var rect: ZoneRect             // Normalized (0–1) relative to view bounds
    public var action: GestureAction
    public var gestureType: GestureType
    public var isEnabled: Bool = true

    public enum ZoneRect: Codable, Equatable, Sendable {
        /// Left third (0–0.33 width)
        case left
        /// Right third (0.67–1.0 width)
        case right
        /// Center third (0.33–0.67 width)
        case center
        /// Top half
        case top
        /// Bottom half
        case bottom
        /// Custom normalized rect
        case custom(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)

        public var normalizedRect: CGRect {
            switch self {
            case .left:   return CGRect(x: 0, y: 0, width: 0.3, height: 1)
            case .right:  return CGRect(x: 0.7, y: 0, width: 0.3, height: 1)
            case .center: return CGRect(x: 0.3, y: 0, width: 0.4, height: 1)
            case .top:    return CGRect(x: 0, y: 0, width: 1, height: 0.5)
            case .bottom: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
            case .custom(let x, let y, let w, let h):
                return CGRect(x: x, y: y, width: w, height: h)
            }
        }
    }

    public enum GestureType: String, Codable, Sendable, CaseIterable {
        case tap
        case doubleTap
        case longPress
        case swipeLeft
        case swipeRight
        case swipeUp
        case swipeDown
        case pinch

        public var displayName: String {
            switch self {
            case .tap: String(localized: "gesture.tap")
            case .doubleTap: String(localized: "gesture.doubleTap")
            case .longPress: String(localized: "gesture.longPress")
            case .swipeLeft: String(localized: "gesture.swipeLeft")
            case .swipeRight: String(localized: "gesture.swipeRight")
            case .swipeUp: String(localized: "gesture.swipeUp")
            case .swipeDown: String(localized: "gesture.swipeDown")
            case .pinch: String(localized: "gesture.pinch")
            }
        }
    }

    public enum GestureAction: String, Codable, Sendable, CaseIterable {
        case nextPage
        case previousPage
        case toggleControls
        case toggleChapterList
        case toggleSettings
        case toggleBookmark
        case toggleTTS
        case zoomIn
        case zoomOut
        case none

        public var displayName: String {
            switch self {
            case .nextPage: L10n.readerNextPage
            case .previousPage: L10n.readerPrevPage
            case .toggleControls: String(localized: "gesture.toggleControls")
            case .toggleChapterList: String(localized: "gesture.toggleChapterList")
            case .toggleSettings: String(localized: "gesture.toggleSettings")
            case .toggleBookmark: String(localized: "gesture.toggleBookmark")
            case .toggleTTS: String(localized: "gesture.toggleTTS")
            case .zoomIn: String(localized: "gesture.zoomIn")
            case .zoomOut: String(localized: "gesture.zoomOut")
            case .none: String(localized: "gesture.none")
            }
        }
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        rect: ZoneRect,
        action: GestureAction,
        gestureType: GestureType,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.rect = rect
        self.action = action
        self.gestureType = gestureType
        self.isEnabled = isEnabled
    }
}

// MARK: - Gesture Preset

/// Pre-built gesture configurations for common reading styles.
public enum GesturePreset: String, CaseIterable, Sendable {
    case mangaClassic      // L→prev  R→next  C→menu
    case westernClassic    // L→next  R→prev  C→menu
    case webtoon           // T→menu  swipe→next/prev
    case novel             // L/R→page  center→menu
    case kindleStyle       // wide center zone, tiny edge zones
    case minimal           // only tap anywhere → next

    public var zones: [GestureZone] {
        switch self {
        case .mangaClassic:
            return [
                GestureZone(id: "manga_left", name: "Prev Page", rect: .left, action: .previousPage, gestureType: .tap),
                GestureZone(id: "manga_center", name: "Menu", rect: .center, action: .toggleControls, gestureType: .tap),
                GestureZone(id: "manga_right", name: "Next Page", rect: .right, action: .nextPage, gestureType: .tap),
                GestureZone(id: "manga_swipe_l", name: "Next Page", rect: .center, action: .nextPage, gestureType: .swipeLeft),
                GestureZone(id: "manga_swipe_r", name: "Prev Page", rect: .center, action: .previousPage, gestureType: .swipeRight),
            ]

        case .westernClassic:
            return [
                GestureZone(id: "west_left", name: "Next Page", rect: .left, action: .nextPage, gestureType: .tap),
                GestureZone(id: "west_center", name: "Menu", rect: .center, action: .toggleControls, gestureType: .tap),
                GestureZone(id: "west_right", name: "Prev Page", rect: .right, action: .previousPage, gestureType: .tap),
            ]

        case .webtoon:
            return [
                GestureZone(id: "wt_top", name: "Menu", rect: .top, action: .toggleControls, gestureType: .tap),
                GestureZone(id: "wt_bottom", name: "Next", rect: .bottom, action: .nextPage, gestureType: .tap),
                GestureZone(id: "wt_swipe", name: "Next/Prev", rect: .center, action: .nextPage, gestureType: .swipeUp),
                GestureZone(id: "wt_swipe_d", name: "Prev", rect: .center, action: .previousPage, gestureType: .swipeDown),
            ]

        case .novel:
            return [
                GestureZone(id: "nov_left", name: "Prev", rect: .left, action: .previousPage, gestureType: .tap),
                GestureZone(id: "nov_right", name: "Next", rect: .right, action: .nextPage, gestureType: .tap),
                GestureZone(id: "nov_center", name: "Menu", rect: .center, action: .toggleControls, gestureType: .tap),
                GestureZone(id: "nov_long", name: "Bookmark", rect: .center, action: .toggleBookmark, gestureType: .longPress),
            ]

        case .kindleStyle:
            return [
                GestureZone(id: "k_left", name: "Prev", rect: .custom(x: 0, y: 0, width: 0.2, height: 1), action: .previousPage, gestureType: .tap),
                GestureZone(id: "k_center", name: "Menu", rect: .custom(x: 0.2, y: 0, width: 0.6, height: 1), action: .toggleControls, gestureType: .tap),
                GestureZone(id: "k_right", name: "Next", rect: .custom(x: 0.8, y: 0, width: 0.2, height: 1), action: .nextPage, gestureType: .tap),
            ]

        case .minimal:
            return [
                GestureZone(id: "min_any", name: "Next", rect: .custom(x: 0, y: 0, width: 1, height: 1), action: .nextPage, gestureType: .tap),
            ]
        }
    }

    public var displayName: String {
        switch self {
        case .mangaClassic: String(localized: "gesture.presetManga")
        case .westernClassic: String(localized: "gesture.presetWestern")
        case .webtoon: String(localized: "gesture.presetWebtoon")
        case .novel: String(localized: "gesture.presetNovel")
        case .kindleStyle: String(localized: "gesture.presetKindle")
        case .minimal: String(localized: "gesture.presetMinimal")
        }
    }
}

// MARK: - Gesture Customization Store

/// Persists user-customized gesture zones.
@MainActor
public final class GestureCustomizationStore: ObservableObject, Sendable {

    @Published public var zones: [GestureZone] = GesturePreset.mangaClassic.zones
    @Published public var activePreset: GesturePreset = .mangaClassic
    @Published public var sensitivity: CGFloat = 1.0  // 0.5–2.0 multiplier for gesture thresholds

    private let storageURL: URL

    public nonisolated init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storageURL = docs.appendingPathComponent("DuckReader/gesture_zones.json")

        Task { @MainActor in
            self.load()
        }
    }

    // MARK: - Presets

    public func applyPreset(_ preset: GesturePreset) {
        zones = preset.zones
        activePreset = preset
        save()
    }

    // MARK: - Zone CRUD

    public func addZone(_ zone: GestureZone) {
        zones.append(zone)
        save()
    }

    public func updateZone(_ zone: GestureZone) {
        if let i = zones.firstIndex(where: { $0.id == zone.id }) {
            zones[i] = zone
            save()
        }
    }

    public func removeZone(id: String) {
        zones.removeAll { $0.id == id }
        save()
    }

    public func resetToPreset() {
        zones = activePreset.zones
        save()
    }

    // MARK: - Hit Testing

    /// Find the best-matching gesture zone for a tap at a given normalized location.
    /// Returns the action if a matching enabled zone is found.
    public func matchZone(at point: CGPoint, gestureType: GestureZone.GestureType = .tap) -> GestureZone.GestureAction? {
        // Zones checked in order; first match wins
        for zone in zones where zone.isEnabled && zone.gestureType == gestureType {
            let rect = zone.rect.normalizedRect
            if rect.contains(point) {
                return zone.action
            }
        }
        return nil
    }

    /// Match for swipe direction.
    public func matchSwipe(direction: GestureZone.GestureType) -> GestureZone.GestureAction? {
        zones.first(where: { $0.isEnabled && $0.gestureType == direction })?.action
    }

    // MARK: - Persistence

    private func save() {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(zones)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[GestureStore] Save failed: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            zones = try JSONDecoder().decode([GestureZone].self, from: data)
        } catch {
            print("[GestureStore] Load failed: \(error)")
        }
    }
}

// MARK: - Environment Key

public struct GestureCustomizationKey: EnvironmentKey {
    public static let defaultValue: GestureCustomizationStore = GestureCustomizationStore()
}

public extension EnvironmentValues {
    var gestureCustomization: GestureCustomizationStore {
        get { self[GestureCustomizationKey.self] }
        set { self[GestureCustomizationKey.self] = newValue }
    }
}
