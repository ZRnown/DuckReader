import SwiftUI
import UIKit

// MARK: - Duck Design System
//
// Built on emilkowalski/skills design principles:
// - Spring animations over duration-based easing
// - Gesture-driven interactions with velocity handoff (interruptible)
// - Translucent materials with backdrop blur
// - Rubber-banding at boundaries
// - Haptic feedback for physicality
// - Reduced-motion awareness
// - Spatial consistency & direct manipulation

// MARK: - Spring Presets

public enum DuckSpring {
    /// Critically damped — no bounce, fluid settle. For modal reveals, navigation.
    /// Maps to: response 0.4, dampingFraction 1.0
    public static var fluid: Animation {
        .spring(response: 0.4, dampingFraction: 1.0)
    }

    /// Slightly bouncy — a touch of life. For cards, button feedback, list insertions.
    /// Maps to: response 0.35, dampingFraction 0.8
    public static var bouncy: Animation {
        .spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0)
    }

    /// Snappy interaction — immediate response, quick settle. For drag-release, toggle.
    /// Maps to: response 0.2, dampingFraction 0.85
    public static var snappy: Animation {
        .spring(response: 0.2, dampingFraction: 0.85)
    }

    /// Interactive — velocity-aware, meant for gesture handoff.
    /// Use when releasing from a drag so momentum carries into the spring.
    public static var interactive: Animation {
        .interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.15)
    }

    /// Playful overshoot — the "pop in" entrance. For achievements, badges, celebratory moments.
    /// Maps to: response 0.4, dampingFraction 0.6
    public static var playful: Animation {
        .spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)
    }

    /// Rubber-band resistance feel for overscroll.
    /// Longer response so the resistance feels deliberate.
    public static var rubberBand: Animation {
        .spring(response: 0.55, dampingFraction: 0.65)
    }
}

// MARK: - Spring Modifier (convenience)

public extension View {
    /// Apply Duck's fluid spring to all animatable changes.
    func duckFluid() -> some View {
        animation(DuckSpring.fluid, value: UUID())
    }

    /// Apply with explicit value tracking.
    func duckBouncy<V: Equatable>(value: V) -> some View {
        animation(DuckSpring.bouncy, value: value)
    }

    func duckSnappy<V: Equatable>(value: V) -> some View {
        animation(DuckSpring.snappy, value: value)
    }

    func duckInteractive<V: Equatable>(value: V) -> some View {
        animation(DuckSpring.interactive, value: value)
    }

    func duckPlayful<V: Equatable>(value: V) -> some View {
        animation(DuckSpring.playful, value: value)
    }
}

// MARK: - Reduced Motion

public struct DuckReducedMotionKey: EnvironmentKey {
    public static let defaultValue: Bool = false
}

public extension EnvironmentValues {
    var duckReducedMotion: Bool {
        get { self[DuckReducedMotionKey.self] }
        set { self[DuckReducedMotionKey.self] = newValue }
    }
}

/// Apply animation, respecting user's reduced-motion preference.
/// Falls back to a zero-duration crossfade for reduced-motion users.
public extension View {
    func duckAnimate<V: Equatable>(
        _ animation: Animation = DuckSpring.fluid,
        value: V
    ) -> some View {
        self.modifier(DuckAnimationModifier(animation: animation, value: value))
    }
}

private struct DuckAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? .linear(duration: 0.001) : animation, value: value)
    }
}

// MARK: - Material Presets

public enum DuckMaterial {
    /// Ultra-thin for top-level backgrounds — see-through but distinct.
    public static var ultraThin: Material { .ultraThinMaterial }

    /// Regular for sheets, modals — grounded separation.
    public static var regular: Material { .regularMaterial }

    /// Thick for prominent overlays — settings panels, detail sheets.
    public static var thick: Material { .thickMaterial }

    /// Chromeless — no material for floating elements that shouldn't blur.
    @ViewBuilder
    public static var chromeless: some View { EmptyView() }
}

public extension View {
    /// Apply Duck's translucent background material.
    func duckBackground(_ material: Material = DuckMaterial.ultraThin) -> some View {
        background(material)
    }

    /// Apply a glass-morphism card style.
    func duckCard() -> some View {
        self
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

// MARK: - Haptic Feedback

public enum DuckHaptic {
    /// Light tap — button press, toggle.
    public static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Medium tap — confirmation, selection.
    public static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    /// Heavy tap — major action, deletion, achievement unlock.
    public static func heavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    /// Selection changed — scroll wheel detent, picker tick.
    public static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    /// Success notification.
    public static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Error notification.
    public static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    /// Warning notification.
    public static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
}

public extension View {
    /// Trigger haptic feedback on a value change.
    func duckHaptic(_ haptic: @escaping @autoclosure () -> Void, trigger: some Equatable) -> some View {
        onChange(of: trigger) { _, _ in haptic() }
    }
}

// MARK: - Typography

public enum DuckFont {
    /// Large title — 34pt, optical size large, tight tracking (-0.5%).
    public static var largeTitle: Font {
        .system(size: 34, weight: .bold, design: .default)
            .leading(.tight)
    }

    /// Title 1 — 28pt.
    public static var title1: Font {
        .system(size: 28, weight: .bold, design: .default)
    }

    /// Title 2 — 22pt.
    public static var title2: Font {
        .system(size: 22, weight: .semibold, design: .default)
    }

    /// Title 3 — 20pt.
    public static var title3: Font {
        .system(size: 20, weight: .regular, design: .default)
    }

    /// Headline — 17pt semibold.
    public static var headline: Font {
        .system(size: 17, weight: .semibold, design: .default)
    }

    /// Body — 17pt.
    public static var body: Font {
        .system(size: 17, weight: .regular, design: .default)
    }

    /// Callout — 16pt.
    public static var callout: Font {
        .system(size: 16, weight: .regular, design: .default)
    }

    /// Subhead — 15pt.
    public static var subhead: Font {
        .system(size: 15, weight: .regular, design: .default)
    }

    /// Footnote — 13pt.
    public static var footnote: Font {
        .system(size: 13, weight: .regular, design: .default)
    }

    /// Caption 1 — 12pt.
    public static var caption1: Font {
        .system(size: 12, weight: .regular, design: .default)
    }

    /// Caption 2 — 11pt.
    public static var caption2: Font {
        .system(size: 11, weight: .regular, design: .default)
    }

    /// Monospaced for reading stats, numbers.
    public static var monoDigit: Font {
        .system(size: 17, weight: .regular, design: .monospaced)
    }

    /// Serif for novel reading body text. CJK-friendly fallback chain.
    public static var novelBody: Font {
        .custom("STSongti-SC", size: 18, relativeTo: .body)
    }

    public static var novelBodySize: CGFloat { 18 }
}

// MARK: - Color Tokens

public enum DuckColor {
    // Accent — warm amber, bookish
    public static var accent: Color {
        Color("AccentColor", bundle: .main)
    }

    // Semantic
    public static var textPrimary: Color { Color.primary }
    public static var textSecondary: Color { Color.secondary }
    public static var textTertiary: Color { Color.secondary.opacity(0.7) }

    // Background
    public static var backgroundPrimary: Color {
        Color(.systemBackground)
    }
    public static var backgroundSecondary: Color {
        Color(.systemGroupedBackground)
    }
    public static var backgroundTertiary: Color {
        Color(.secondarySystemGroupedBackground)
    }

    // Reading
    public static var readingBackgroundSepia: Color {
        Color(red: 0.976, green: 0.953, blue: 0.890)
    }
    public static var readingBackgroundDark: Color {
        Color(red: 0.129, green: 0.129, blue: 0.141)
    }
    public static var readingBackgroundLight: Color {
        Color(red: 0.965, green: 0.965, blue: 0.957)
    }

    // Achievement
    public static var achievementGold: Color {
        Color(red: 1.0, green: 0.757, blue: 0.027)
    }
    public static var achievementSilver: Color {
        Color(red: 0.725, green: 0.769, blue: 0.812)
    }
    public static var achievementBronze: Color {
        Color(red: 0.804, green: 0.498, blue: 0.196)
    }
}

// MARK: - Corner Radius Scale

public enum DuckRadius {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 24
    public static let full: CGFloat = 9999
}

// MARK: - Layout

public enum DuckLayout {
    public static let screenHPadding: CGFloat = 20
    public static let cardInnerPadding: CGFloat = 20
    public static let listRowHeight: CGFloat = 56
    public static let iconSizeSmall: CGFloat = 20
    public static let iconSizeMedium: CGFloat = 28
    public static let iconSizeLarge: CGFloat = 44
    public static let thumbnailSize: CGFloat = 72
    public static let tapTargetMin: CGFloat = 44
}

// MARK: - Rubber-Band Modifier

/// Applies rubber-band resistance when dragging past a boundary.
/// Usage: `.rubberBand(offset: $dragOffset, clamp: -50...100)`
private struct RubberBandModifier: ViewModifier {
    @Binding var offset: CGFloat
    let clamp: ClosedRange<CGFloat>

    func body(content: Content) -> some View {
        content
            .offset(y: rubberBandOffset)
            .animation(DuckSpring.rubberBand, value: rubberBandOffset)
    }

    private var rubberBandOffset: CGFloat {
        if offset < clamp.lowerBound {
            let overshoot = clamp.lowerBound - offset
            return clamp.lowerBound - rubberBand(overshoot)
        }
        if offset > clamp.upperBound {
            let overshoot = offset - clamp.upperBound
            return clamp.upperBound + rubberBand(overshoot)
        }
        return offset
    }

    /// Rubber-band function: f(x) = (1 - 1/(x*c + 1)) * maxDistance
    private func rubberBand(_ x: CGFloat) -> CGFloat {
        let c: CGFloat = 0.55
        let maxDistance: CGFloat = 80
        return (1.0 - 1.0 / (x * c + 1.0)) * maxDistance
    }
}

public extension View {
    func duckRubberBand(offset: Binding<CGFloat>, clamp: ClosedRange<CGFloat>) -> some View {
        modifier(RubberBandModifier(offset: offset, clamp: clamp))
    }
}

// MARK: - Scale-on-Press Feedback

private struct ScaleOnPressModifier: ViewModifier {
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1.0)
            .animation(DuckSpring.snappy, value: pressed)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                pressed = pressing
            }, perform: {})
    }
}

public extension View {
    /// Subtle press-down scale for tappable elements — makes them feel physical.
    func duckPressable() -> some View {
        modifier(ScaleOnPressModifier())
    }
}

// MARK: - Shimmer / Skeleton Loading

public struct DuckShimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    Color.white.opacity(0.4)
                        .rotationEffect(.degrees(15))
                        .offset(x: phase * geo.size.width * 1.5)
                        .mask(content)
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

public extension View {
    func duckShimmer() -> some View {
        modifier(DuckShimmer())
    }
}

// MARK: - Number Ticker (Animated Counter)

public struct DuckNumberTicker: View, Animatable {
    var number: Double
    private let formatter: (Double) -> String

    public init(_ number: Double, formatter: @escaping (Double) -> String = { String(format: "%.0f", $0) }) {
        self.number = number
        self.formatter = formatter
    }

    public var animatableData: Double {
        get { number }
        set { number = newValue }
    }

    public var body: some View {
        Text(formatter(number))
            .font(DuckFont.monoDigit)
            .monospacedDigit()
    }
}

// MARK: - Staggered List Entrance

public struct DuckStaggerModifier: ViewModifier {
    let index: Int
    let baseDelay: Double
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 12)
            .animation(
                DuckSpring.bouncy
                    .delay(reduceMotion ? 0 : baseDelay * Double(index)),
                value: visible
            )
            .onAppear { visible = true }
    }
}

public extension View {
    /// Staggered entrance — items cascade in one by one.
    func duckStagger(index: Int, baseDelay: Double = 0.05) -> some View {
        modifier(DuckStaggerModifier(index: index, baseDelay: baseDelay))
    }
}

// MARK: - View that observes DuckTheme changes

public class DuckTheme: ObservableObject {
    public static let shared = DuckTheme()

    @Published public var readingTheme: DuckReadingTheme = .light
    @Published public var fontSize: CGFloat = DuckFont.novelBodySize
    @Published public var lineSpacing: CGFloat = 6
}

public enum DuckReadingTheme: String, CaseIterable, Sendable {
    case light, sepia, dark

    public var backgroundColor: Color {
        switch self {
        case .light: return DuckColor.readingBackgroundLight
        case .sepia: return DuckColor.readingBackgroundSepia
        case .dark: return DuckColor.readingBackgroundDark
        }
    }

    public var textColor: Color {
        switch self {
        case .light: return .black.opacity(0.87)
        case .sepia: return Color(red: 0.267, green: 0.157, blue: 0.055)
        case .dark: return .white.opacity(0.87)
        }
    }
}
