import Foundation
import SwiftUI

// MARK: - Accessibility Configuration

/// Centralized accessibility support: VoiceOver, Dynamic Type, color-blind modes,
/// reduced motion, and high-contrast overrides.
public struct AccessibilityConfig: Equatable, Sendable {
    /// Color-blindness simulation mode.
    public var colorBlindMode: ColorBlindMode = .none
    /// Override system font size scaling.
    public var fontScaleOverride: Double? = nil
    /// High-contrast UI mode.
    public var highContrast: Bool = false
    /// Always show text labels below icons.
    public var alwaysShowLabels: Bool = false
    /// Extra spacing for touch targets (accessibility-friendly).
    public var expandedTouchTargets: Bool = false
    /// Skip animations (respects UIAccessibility.isReduceMotionEnabled).
    public var reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled
    /// Enable screen-reader-optimized descriptions.
    public var voiceOverOptimized: Bool = UIAccessibility.isVoiceOverRunning
    /// Font weight boost for readability.
    public var boldText: Bool = UIAccessibility.isBoldTextEnabled
    /// Button shapes for clarity.
    public var buttonShapes: Bool = UIAccessibility.buttonShapesEnabled

    public enum ColorBlindMode: String, Sendable, CaseIterable {
        case none
        case protanopia    // Red-blind
        case deuteranopia  // Green-blind
        case tritanopia    // Blue-blind
        case grayscale

        public var displayName: String {
            switch self {
            case .none: String(localized: "accessibility.colorBlindNone")
            case .protanopia: String(localized: "accessibility.colorBlindProtanopia")
            case .deuteranopia: String(localized: "accessibility.colorBlindDeuteranopia")
            case .tritanopia: String(localized: "accessibility.colorBlindTritanopia")
            case .grayscale: String(localized: "accessibility.colorBlindGrayscale")
            }
        }

        /// Core Image filter name for simulation.
        public var filterName: String? {
            switch self {
            case .none: return nil
            case .protanopia: return "CIColorBlindnessSimulateProtanopia"
            case .deuteranopia: return "CIColorBlindnessSimulateDeuteranopia"
            case .tritanopia: return "CIColorBlindnessSimulateTritanopia"
            case .grayscale: return "CIColorControls"
            }
        }
    }

    public static let `default` = AccessibilityConfig()
}

// MARK: - Accessibility View Modifiers

/// Applies all accessibility enhancements to a view.
public struct AccessibilityEnhancement: ViewModifier {
    let config: AccessibilityConfig

    public func body(content: Content) -> some View {
        content
            // Dynamic Type with optional override
            .dynamicTypeSize(config.fontScaleOverride.map { DynamicTypeSize.xxxLarge } ?? .large ... .accessibility5)
            // High contrast
            .contrast(config.highContrast ? 1.3 : 1.0)
            // Reduced motion
            .animation(config.reduceMotion ? .none : .default, value: config.reduceMotion)
    }
}

public extension View {
    func accessibilityEnhanced(_ config: AccessibilityConfig = .default) -> some View {
        modifier(AccessibilityEnhancement(config: config))
    }
}

// MARK: - VoiceOver Accessible Reader Wrapper

/// Adds VoiceOver accessibility to the reader view.
/// Announces: "Page X of Y", "Panel detected at [position]",
/// "Chapter: [title]", etc.
public struct VoiceOverReaderModifier: ViewModifier {
    let pageIndex: Int
    let totalPages: Int
    let chapterTitle: String?
    let hasPanels: Bool
    let panelCount: Int
    let onPageNavigate: (Bool) -> Void  // true = forward

    public func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue("\(pageIndex + 1) / \(totalPages)")
            .accessibilityAddTraits(.causesPageTurn)
            .accessibilityActions {
                // Custom actions for VoiceOver users
                Button(action: { onPageNavigate(true) }) {
                    Label(String(localized: "accessibility.nextPage"), systemImage: "arrow.right")
                }
                .accessibilityInputLabels([String(localized: "accessibility.nextPageShortcut")])

                Button(action: { onPageNavigate(false) }) {
                    Label(String(localized: "accessibility.previousPage"), systemImage: "arrow.left")
                }
                .accessibilityInputLabels([String(localized: "accessibility.prevPageShortcut")])
            }
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let chapter = chapterTitle {
            parts.append(chapter)
        }
        if hasPanels {
            parts.append(String(format: String(localized: "accessibility.panelsDetected"), panelCount))
        }
        return parts.isEmpty ? String(localized: "accessibility.comicPage") : parts.joined(separator: ". ")
    }
}

public extension View {
    func voiceOverReader(
        pageIndex: Int,
        totalPages: Int,
        chapterTitle: String? = nil,
        hasPanels: Bool = false,
        panelCount: Int = 0,
        onPageNavigate: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        modifier(VoiceOverReaderModifier(
            pageIndex: pageIndex,
            totalPages: totalPages,
            chapterTitle: chapterTitle,
            hasPanels: hasPanels,
            panelCount: panelCount,
            onPageNavigate: onPageNavigate
        ))
    }
}

// MARK: - Dynamic Font Calculator

/// Maps reading font sizes to Dynamic Type scale for consistency.
public enum DynamicFontScale: Sendable {
    /// Convert a user-set reading font size to a system DynamicTypeSize.
    public static func scale(fromFontSize fontSize: CGFloat, config: AccessibilityConfig) -> DynamicTypeSize {
        if let override = config.fontScaleOverride {
            // Map the override to the closest DynamicTypeSize
            switch override {
            case ..<1.0: return .small
            case 1.0..<1.3: return .medium
            case 1.3..<1.6: return .large
            case 1.6..<2.0: return .xLarge
            case 2.0..<2.5: return .xxLarge
            case 2.5..<3.0: return .xxxLarge
            case 3.0..<3.5: return .accessibility2
            default: return .accessibility5
            }
        }
        return .large
    }
}

// MARK: - Color Blindness Filter

/// Applies a CoreImage color-blindness simulation to an image.
public struct ColorBlindnessFilter: Sendable {
    let mode: AccessibilityConfig.ColorBlindMode

    public func apply(to image: CGImage) -> CGImage? {
        guard let filterName = mode.filterName else { return image }

        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(name: filterName) else { return image }

        filter.setValue(ciImage, forKey: kCIInputImageKey)

        if mode == .grayscale {
            filter.setValue(0.0, forKey: kCIInputSaturationKey)
        }

        guard let output = filter.outputImage else { return image }

        let ctx = CIContext()
        return ctx.createCGImage(output, from: output.extent)
    }
}

// MARK: - Accessibility Config Store

@MainActor
public final class AccessibilityStore: ObservableObject, Sendable {
    @Published public var config: AccessibilityConfig = .default
    @Published public var isGuidedAccess: Bool = UIAccessibility.isGuidedAccessEnabled

    private let defaults = UserDefaults.standard

    public nonisolated init() {
        Task { @MainActor in self.load() }
    }

    /// Detect system accessibility changes and update.
    public func refreshSystemState() {
        config.reduceMotion = UIAccessibility.isReduceMotionEnabled
        config.voiceOverOptimized = UIAccessibility.isVoiceOverRunning
        config.boldText = UIAccessibility.isBoldTextEnabled
        config.buttonShapes = UIAccessibility.buttonShapesEnabled
        isGuidedAccess = UIAccessibility.isGuidedAccessEnabled
    }

    /// Toggle high-contrast mode.
    public func toggleHighContrast() {
        config.highContrast.toggle()
        save()
    }

    /// Set color-blind mode.
    public func setColorBlindMode(_ mode: AccessibilityConfig.ColorBlindMode) {
        config.colorBlindMode = mode
        save()
    }

    // MARK: - Persistence

    private func save() {
        defaults.set(config.colorBlindMode.rawValue, forKey: "accessibility_colorBlindMode")
        defaults.set(config.highContrast, forKey: "accessibility_highContrast")
        defaults.set(config.expandedTouchTargets, forKey: "accessibility_expandedTouchTargets")
    }

    private func load() {
        if let mode = defaults.string(forKey: "accessibility_colorBlindMode"),
           let cbMode = AccessibilityConfig.ColorBlindMode(rawValue: mode) {
            config.colorBlindMode = cbMode
        }
        config.highContrast = defaults.bool(forKey: "accessibility_highContrast")
        config.expandedTouchTargets = defaults.bool(forKey: "accessibility_expandedTouchTargets")
    }
}

// MARK: - Accessibility Enhancements (v2.2)
// Reading rhythm guide, Korean/Traditional Chinese locale, E-ink mode

extension AccessibilitySupport {
    /// Reading rhythm: gentle haptic pulses at configurable intervals
    /// to help maintain reading pace.
    public enum ReadingRhythmInterval: TimeInterval, CaseIterable {
        case off = 0
        case slow = 10
        case medium = 5
        case fast = 2

        public var label: String {
            switch self {
            case .off:    String(localized: "a11y.rhythm.off")
            case .slow:   String(localized: "a11y.rhythm.slow")
            case .medium: String(localized: "a11y.rhythm.medium")
            case .fast:   String(localized: "a11y.rhythm.fast")
            }
        }
    }

    /// Check if e-ink optimization is enabled and provide the appropriate preset.
    public static func eInkReadingPreset() -> ReadingPreset {
        ReadingPreset(
            theme: .light, fontSize: 16, fontName: nil,
            lineSpacing: 1.5, paragraphSpacing: 8,
            scrollDirection: .horizontal, pageLayout: .auto, panelMode: .off,
            autoHideControls: false, pageTurnAnimation: .none, tapZoneScheme: .leftRight,
            ttsVoice: nil, ttsRate: 1.0,
            reduceMotion: true, highContrast: true, eInkOptimized: true, verticalText: false,
            lastModified: Date(), label: "E-Ink"
        )
    }
}
