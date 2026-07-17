import Foundation
import Combine

// MARK: - Reading Presets

/// Per-book and per-series reading presets: font, theme, scroll direction,
/// panel mode, and more — all syncable across devices.
///
/// Extends GestureCustomization + NovelStyleEngine into a unified preset system.
@MainActor
public final class ReadingPresets: ObservableObject, @unchecked Sendable {

    @Published public private(set) var presets: [UUID: ReadingPreset] = [:]  // bookID → preset
    @Published public private(set) var seriesPresets: [String: ReadingPreset] = [:]  // seriesName → preset
    @Published public private(set) var defaultPreset: ReadingPreset = .defaultComfort

    private let storageURL: URL

    public nonisolated init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DuckReader")
        storageURL = docs.appendingPathComponent("reading_presets.json")

        Task { @MainActor in
            load()
        }
    }

    // MARK: - Preset CRUD

    /// Get the effective preset for a book (per-book > per-series > default).
    public func preset(for bookID: UUID, seriesName: String? = nil, format: BookFormat = .comic) -> ReadingPreset {
        if let bookPreset = presets[bookID] {
            return bookPreset
        }
        if let series = seriesName, let seriesPreset = seriesPresets[series] {
            return seriesPreset
        }
        return defaultPreset.withFormatDefaults(format)
    }

    /// Save a preset for a specific book.
    public func setPreset(_ preset: ReadingPreset, for bookID: UUID) {
        presets[bookID] = preset
        scheduleSave()
    }

    /// Save a preset for an entire series.
    public func setSeriesPreset(_ preset: ReadingPreset, for seriesName: String) {
        seriesPresets[seriesName] = preset
        scheduleSave()
    }

    /// Update default preset.
    public func setDefaultPreset(_ preset: ReadingPreset) {
        defaultPreset = preset
        scheduleSave()
    }

    /// Remove per-book preset (falls back to series or default).
    public func removePreset(for bookID: UUID) {
        presets[bookID] = nil
        scheduleSave()
    }

    /// Remove series preset.
    public func removeSeriesPreset(for seriesName: String) {
        seriesPresets[seriesName] = nil
        scheduleSave()
    }

    // MARK: - Quick Preset Templates

    public static let presetTemplates: [ReadingPreset] = [
        .defaultComfort,
        .speedReader,
        .nightOwl,
        .mangaPurist,
        .novelClassic,
        .accessibilityLarge,
        .minimalist
    ]

    // MARK: - Cloud Sync

    /// Export all presets for cloud sync (JSON).
    public func exportPresets() -> Data? {
        let container = PresetSyncContainer(
            presets: presets.mapKeys { $0.uuidString },
            seriesPresets: seriesPresets,
            defaultPreset: defaultPreset
        )
        return try? JSONEncoder().encode(container)
    }

    /// Import presets from cloud sync.
    public func importPresets(from data: Data) {
        guard let container = try? JSONDecoder().decode(PresetSyncContainer.self, from: data) else {
            return
        }
        // Merge strategy: newer timestamp wins for conflicts
        let importedBookIDs = container.presets.compactMapKeys { UUID(uuidString: $0) }
        presets.merge(importedBookIDs) { existing, incoming in
            incoming.lastModified > existing.lastModified ? incoming : existing
        }
        seriesPresets.merge(container.seriesPresets) { existing, incoming in
            incoming.lastModified > existing.lastModified ? incoming : existing
        }
        if container.defaultPreset.lastModified > defaultPreset.lastModified {
            defaultPreset = container.defaultPreset
        }
        scheduleSave()
    }

    // MARK: - Persistence

    private var saveWorkItem: DispatchWorkItem?

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.save()
        }
        saveWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func save() {
        let container = PresetSyncContainer(
            presets: presets.mapKeys { $0.uuidString },
            seriesPresets: seriesPresets,
            defaultPreset: defaultPreset
        )
        if let data = try? JSONEncoder().encode(container) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let container = try? JSONDecoder().decode(PresetSyncContainer.self, from: data) else {
            return
        }
        presets = container.presets.compactMapKeys { UUID(uuidString: $0) }
        seriesPresets = container.seriesPresets
        if container.defaultPreset.lastModified > defaultPreset.lastModified {
            defaultPreset = container.defaultPreset
        }
    }
}

// MARK: - Preset Model

/// A complete reading experience preset.
public struct ReadingPreset: Codable, Sendable {
    // MARK: Visual
    public var theme: PresetTheme
    public var fontSize: Double              // pt
    public var fontName: String?             // nil = system default
    public var lineSpacing: Double           // multiplier
    public var paragraphSpacing: Double      // pt

    // MARK: Layout
    public var scrollDirection: ScrollDirection
    public var pageLayout: PageLayout
    public var panelMode: PanelMode

    // MARK: Behavior
    public var autoHideControls: Bool
    public var pageTurnAnimation: PageTurnStyle
    public var tapZoneScheme: TapZoneScheme

    // MARK: Audio
    public var ttsVoice: String?
    public var ttsRate: Double               // 0.5–2.0

    // MARK: Advanced
    public var reduceMotion: Bool
    public var highContrast: Bool
    public var eInkOptimized: Bool           // For external e-ink displays
    public var verticalText: Bool            // CJK vertical layout

    // MARK: Meta
    public var lastModified: Date
    public var label: String                 // Human-readable preset name

    // MARK: - Sub-types

    public enum PresetTheme: String, Codable, Sendable, CaseIterable {
        case system, light, dark, sepia, cream, green, custom
    }

    public enum ScrollDirection: String, Codable, Sendable {
        case horizontal, vertical
    }

    public enum PageLayout: String, Codable, Sendable {
        case single, doubleSpread, auto
    }

    public enum PanelMode: String, Codable, Sendable {
        case off, guided, autoDetect
    }

    public enum PageTurnStyle: String, Codable, Sendable {
        case slide, curl, none
    }

    public enum TapZoneScheme: String, Codable, Sendable {
        case leftRight, manga, webtoon, custom
    }

    // MARK: - Templates

    public static let defaultComfort = ReadingPreset(
        theme: .system, fontSize: 16, fontName: nil,
        lineSpacing: 1.5, paragraphSpacing: 8,
        scrollDirection: .horizontal, pageLayout: .auto, panelMode: .autoDetect,
        autoHideControls: true, pageTurnAnimation: .slide, tapZoneScheme: .leftRight,
        ttsVoice: nil, ttsRate: 1.0,
        reduceMotion: false, highContrast: false, eInkOptimized: false, verticalText: false,
        lastModified: Date(), label: "Comfort"
    )

    public static let speedReader = ReadingPreset(
        theme: .light, fontSize: 14, fontName: nil,
        lineSpacing: 1.2, paragraphSpacing: 4,
        scrollDirection: .vertical, pageLayout: .single, panelMode: .off,
        autoHideControls: true, pageTurnAnimation: .none, tapZoneScheme: .webtoon,
        ttsVoice: nil, ttsRate: 1.5,
        reduceMotion: true, highContrast: false, eInkOptimized: false, verticalText: false,
        lastModified: Date(), label: "Speed Reader"
    )

    public static let nightOwl = ReadingPreset(
        theme: .dark, fontSize: 16, fontName: nil,
        lineSpacing: 1.6, paragraphSpacing: 8,
        scrollDirection: .horizontal, pageLayout: .auto, panelMode: .autoDetect,
        autoHideControls: true, pageTurnAnimation: .slide, tapZoneScheme: .leftRight,
        ttsVoice: nil, ttsRate: 1.0,
        reduceMotion: false, highContrast: false, eInkOptimized: false, verticalText: false,
        lastModified: Date(), label: "Night Owl"
    )

    public static let mangaPurist = ReadingPreset(
        theme: .dark, fontSize: 14, fontName: nil,
        lineSpacing: 1.3, paragraphSpacing: 4,
        scrollDirection: .horizontal, pageLayout: .doubleSpread, panelMode: .guided,
        autoHideControls: true, pageTurnAnimation: .curl, tapZoneScheme: .manga,
        ttsVoice: nil, ttsRate: 1.0,
        reduceMotion: false, highContrast: false, eInkOptimized: false, verticalText: false,
        lastModified: Date(), label: "Manga Purist"
    )

    public static let novelClassic = ReadingPreset(
        theme: .sepia, fontSize: 18, fontName: "Georgia",
        lineSpacing: 1.8, paragraphSpacing: 12,
        scrollDirection: .vertical, pageLayout: .single, panelMode: .off,
        autoHideControls: false, pageTurnAnimation: .slide, tapZoneScheme: .leftRight,
        ttsVoice: nil, ttsRate: 0.9,
        reduceMotion: true, highContrast: false, eInkOptimized: false, verticalText: false,
        lastModified: Date(), label: "Novel Classic"
    )

    public static let accessibilityLarge = ReadingPreset(
        theme: .system, fontSize: 24, fontName: nil,
        lineSpacing: 2.0, paragraphSpacing: 16,
        scrollDirection: .vertical, pageLayout: .single, panelMode: .off,
        autoHideControls: false, pageTurnAnimation: .none, tapZoneScheme: .leftRight,
        ttsVoice: nil, ttsRate: 0.8,
        reduceMotion: true, highContrast: true, eInkOptimized: false, verticalText: false,
        lastModified: Date(), label: "Large Print"
    )

    public static let minimalist = ReadingPreset(
        theme: .system, fontSize: 15, fontName: nil,
        lineSpacing: 1.4, paragraphSpacing: 6,
        scrollDirection: .horizontal, pageLayout: .single, panelMode: .off,
        autoHideControls: true, pageTurnAnimation: .none, tapZoneScheme: .leftRight,
        ttsVoice: nil, ttsRate: 1.0,
        reduceMotion: true, highContrast: false, eInkOptimized: false, verticalText: false,
        lastModified: Date(), label: "Minimalist"
    )

    // MARK: - Helpers

    /// Apply format-specific overrides (comic vs novel).
    public func withFormatDefaults(_ format: BookFormat) -> ReadingPreset {
        var copy = self
        switch format {
        case .comic, .manga:
            if copy.panelMode == .off {
                copy.panelMode = .autoDetect
            }
            if copy.pageLayout == .single {
                copy.pageLayout = .auto
            }
        case .novel:
            copy.panelMode = .off
            copy.pageLayout = .single
        }
        return copy
    }
}

public enum BookFormat: String, Sendable {
    case comic, manga, novel
}

// MARK: - Sync Container

/// Serializable container for cloud sync.
struct PresetSyncContainer: Codable {
    var presets: [String: ReadingPreset]
    var seriesPresets: [String: ReadingPreset]
    var defaultPreset: ReadingPreset
}

// MARK: - Dictionary Helpers

extension Dictionary {
    func mapKeys<K: Hashable>(_ transform: (Key) -> K) -> [K: Value] {
        Dictionary<K, Value>(uniqueKeysWithValues: map { (transform($0.key), $0.value) })
    }

    func compactMapKeys<K: Hashable>(_ transform: (Key) -> K?) -> [K: Value] {
        var result: [K: Value] = [:]
        for (key, value) in self {
            if let newKey = transform(key) {
                result[newKey] = value
            }
        }
        return result
    }
}
