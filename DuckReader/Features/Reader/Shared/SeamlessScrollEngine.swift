import Foundation
import SwiftUI

// MARK: - Seamless Scroll Configuration

/// Controls for seamless continuous scrolling (webtoon/novel mode).
public struct SeamlessScrollConfig: Equatable, Sendable {
    /// Gap between images in points (0 = true seamless)
    public var interPageGap: CGFloat = 0
    /// Preload pages ahead of viewport
    public var preloadAhead: Int = 3
    /// Preload pages behind viewport
    public var preloadBehind: Int = 2
    /// Snapping behavior
    public var snapBehavior: SnapBehavior = .none
    /// Deceleration rate (0 = instant stop, 1 = very floaty)
    public var decelerationRate: CGFloat = UIScrollView.DecelerationRate.normal.rawValue
    /// Show page indicator dots on the side
    public var showPageIndicator: Bool = true
    /// Double-tap to zoom
    public var doubleTapToZoom: Bool = false
    /// Pinch to zoom
    public var pinchToZoom: Bool = false

    public enum SnapBehavior: String, Sendable, CaseIterable {
        case none       // Free scroll
        case page       // Snap to each page/image
        case chapter    // Snap to chapter boundaries
    }

    public static let `default` = SeamlessScrollConfig()
    public static let webtoon = SeamlessScrollConfig(
        interPageGap: 0,
        preloadAhead: 5,
        preloadBehind: 3,
        decelerationRate: UIScrollView.DecelerationRate.fast.rawValue
    )
}

// MARK: - Seamless Scroll Engine

/// Manages seamless scrolling state, image stitching, and viewport tracking.
/// Designed to provide zero-gap reading for webtoon/comic strips.
@MainActor
public final class SeamlessScrollEngine: ObservableObject, Sendable {

    @Published public var config: SeamlessScrollConfig = .default
    @Published public var viewportPageIndex: Int = 0
    @Published public var totalPages: Int = 0
    @Published public var isScrolling: Bool = false
    @Published public var scrollOffset: CGFloat = 0

    /// Track which pages are currently loaded (for lazy loading)
    @Published public private(set) var loadedPages: Set<Int> = []

    public nonisolated init(config: SeamlessScrollConfig = .default) {
        Task { @MainActor in
            self.config = config
        }
    }

    // MARK: - Viewport Tracking

    /// Called from ScrollView when content offset changes.
    public func updateViewport(scrollOffset: CGFloat, pageHeights: [CGFloat]) {
        self.scrollOffset = scrollOffset
        guard !pageHeights.isEmpty else { return }

        var cumulative: CGFloat = 0
        for (i, height) in pageHeights.enumerated() {
            let next = cumulative + height + config.interPageGap
            if scrollOffset < next {
                if viewportPageIndex != i {
                    viewportPageIndex = i
                }
                break
            }
            cumulative = next
        }
    }

    /// Returns which page indices should be preloaded.
    public func pagesToLoad(currentPage: Int) -> Range<Int> {
        let start = max(0, currentPage - config.preloadBehind)
        let end = min(totalPages, currentPage + config.preloadAhead + 1)
        return start..<end
    }

    /// Mark page as loaded.
    public func markPageLoaded(_ index: Int) {
        loadedPages.insert(index)
    }

    /// Clear all loaded page markers.
    public func reset() {
        loadedPages.removeAll()
        viewportPageIndex = 0
        scrollOffset = 0
        isScrolling = false
    }
}

// MARK: - Seamless Scroll Reader View

/// A SwiftUI view that renders multiple pages as a continuous vertical strip.
/// Images are stitched with zero gap; preloading is managed by the engine.
public struct SeamlessScrollReaderView: View {
    @ObservedObject var engine: SeamlessScrollEngine
    let pages: [PageData]
    let onPageVisible: (Int) -> Void

    public init(
        engine: SeamlessScrollEngine,
        pages: [PageData],
        onPageVisible: @escaping (Int) -> Void = { _ in }
    ) {
        self.engine = engine
        self.pages = pages
        self.onPageVisible = onPageVisible
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: engine.config.showPageIndicator) {
                LazyVStack(spacing: engine.config.interPageGap) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        if engine.loadedPages.contains(index) || index < engine.pagesToLoad(currentPage: engine.viewportPageIndex).upperBound {
                            PageImageView(page: page)
                                .onAppear {
                                    engine.markPageLoaded(index)
                                    onPageVisible(index)
                                }
                        } else {
                            // Placeholder with same aspect to avoid layout jumps
                            Rectangle()
                                .fill(.clear)
                                .frame(height: estimatedHeight(for: page, viewportWidth: geometry.size.width))
                                .overlay {
                                    ProgressView()
                                        .opacity(0.3)
                                }
                                .onAppear {
                                    engine.markPageLoaded(index)
                                    onPageVisible(index)
                                }
                        }
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: proxy.frame(in: .named("scroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                engine.updateViewport(
                    scrollOffset: abs(offset),
                    pageHeights: pages.map { estimatedHeight(for: $0, viewportWidth: geometry.size.width) }
                )
            }
        }
    }

    private func estimatedHeight(for page: PageData, viewportWidth: CGFloat) -> CGFloat {
        // Use actual image dimensions if available, otherwise default
        if page.width > 0, page.height > 0 {
            let ratio = viewportWidth / page.width
            return page.height * ratio
        }
        return viewportWidth * 1.5  // Default portrait ratio
    }
}

// MARK: - Page Image View

private struct PageImageView: View {
    let page: PageData

    var body: some View {
        if let data = page.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    ProgressView()
                }
        }
    }
}

// MARK: - Scroll Offset Tracking

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
