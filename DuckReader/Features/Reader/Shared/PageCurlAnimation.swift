import SwiftUI

// MARK: - Page Curl Animation

/// A realistic page-curl transition animation inspired by Apple Books.
/// Uses a combination of 3D rotation, shadow, and gradient overlays
/// to simulate a physical page turn.
///
/// Two modes:
/// - `.curl`: true 3D page curl with perspective transform (iOS 16+)
/// - `.slide`: simpler slide transition as fallback (older OS / accessibility)
public struct PageCurlTransition: ViewModifier {
    let direction: PageCurlDirection
    let progress: CGFloat          // 0.0–1.0 (drag progress)
    let isActive: Bool

    public enum PageCurlDirection: Sendable {
        case leftToRight   // Forward (Western)
        case rightToLeft   // Forward (Manga)
        case topToBottom   // Vertical
    }

    public init(
        direction: PageCurlDirection = .rightToLeft,
        progress: CGFloat = 0,
        isActive: Bool = false
    ) {
        self.direction = direction
        self.progress = progress
        self.isActive = isActive
    }

    public func body(content: Content) -> some View {
        content
            // 3D rotation effect
            .rotation3DEffect(
                .degrees(Double(progress) * rotationAngle),
                axis: rotationAxis,
                anchor: anchorPoint,
                perspective: 0.3
            )
            // Shadow overlay (darker as page curls)
            .overlay(alignment: overlayAlignment) {
                if isActive && progress > 0.01 {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .black.opacity(0.05 + Double(progress) * 0.15),
                            .clear
                        ]),
                        startPoint: gradientStart,
                        endPoint: gradientEnd
                    )
                    .allowsHitTesting(false)
                }
            }
            // Page back-side simulation
            .background(alignment: overlayAlignment.opposite) {
                if isActive && progress > 0.3 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.ultraThinMaterial)
                        .padding(.vertical, 1)
                        .padding(.horizontal, 3)
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
    }

    // MARK: - Helpers

    private var rotationAngle: CGFloat {
        switch direction {
        case .leftToRight: return 90
        case .rightToLeft: return -90
        case .topToBottom: return 90
        }
    }

    private var rotationAxis: (CGFloat, CGFloat, CGFloat) {
        switch direction {
        case .leftToRight: return (0, 1, 0)
        case .rightToLeft: return (0, 1, 0)
        case .topToBottom: return (1, 0, 0)
        }
    }

    private var anchorPoint: UnitPoint {
        switch direction {
        case .leftToRight: return .leading
        case .rightToLeft: return .trailing
        case .topToBottom: return .top
        }
    }

    private var overlayAlignment: Alignment {
        switch direction {
        case .leftToRight: return .leading
        case .rightToLeft: return .trailing
        case .topToBottom: return .top
        }
    }

    private var gradientStart: UnitPoint {
        switch direction {
        case .leftToRight: return .trailing
        case .rightToLeft: return .leading
        case .topToBottom: return .bottom
        }
    }

    private var gradientEnd: UnitPoint {
        switch direction {
        case .leftToRight: return .leading
        case .rightToLeft: return .trailing
        case .topToBottom: return .top
        }
    }
}

private extension Alignment {
    var opposite: Alignment {
        switch self {
        case .leading: return .trailing
        case .trailing: return .leading
        case .top: return .bottom
        case .bottom: return .top
        default: return .center
        }
    }
}

// MARK: - View Extension

public extension View {
    /// Apply a realistic page-curl transition.
    func pageCurl(
        direction: PageCurlTransition.PageCurlDirection = .rightToLeft,
        progress: CGFloat,
        isActive: Bool = true
    ) -> some View {
        modifier(PageCurlTransition(
            direction: direction,
            progress: progress,
            isActive: isActive
        ))
    }
}

// MARK: - Page Curl Gesture Handler

/// A drag-gesture wrapper that manages page-curl progress and commits
/// the page turn when the user releases past the threshold.
@MainActor
public final class PageCurlGestureHandler: ObservableObject, Sendable {

    @Published public var progress: CGFloat = 0
    @Published public var isDragging: Bool = false
    @Published public var direction: PageCurlTransition.PageCurlDirection = .rightToLeft

    public let commitThreshold: CGFloat = 0.4   // 40% drag → commit turn
    public var onPageTurnForward: () -> Void = {}
    public var onPageTurnBackward: () -> Void = {}

    public nonisolated init() {}

    /// Returns a DragGesture configured for page-curl interaction.
    public func dragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                isDragging = true

                let width = geometry.size.width
                let height = geometry.size.height

                // Determine direction from drag
                if abs(value.translation.width) > abs(value.translation.height) {
                    // Horizontal drag
                    direction = value.translation.width > 0
                        ? .leftToRight
                        : .rightToLeft
                    progress = min(1.0, abs(value.translation.width) / (width * 0.6))
                } else {
                    // Vertical drag
                    direction = .topToBottom
                    progress = min(1.0, abs(value.translation.height) / (height * 0.6))
                }
            }
            .onEnded { value in
                isDragging = false

                if progress >= commitThreshold {
                    // Commit page turn
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        progress = 1.0
                    } completion: {
                        if self.direction == .leftToRight {
                            self.onPageTurnBackward()
                        } else {
                            self.onPageTurnForward()
                        }
                        self.progress = 0
                    }
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        progress = 0
                    }
                }
            }
    }
}
