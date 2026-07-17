import Foundation
import SwiftUI
import ImageIO

// MARK: - Double Page Merge Engine

/// Detects and merges adjacent pages that form a double-page spread.
/// Handles both pre-merged spreads and split spreads across archives.
public struct DoublePageMergeEngine: Sendable {

    /// Configuration for merge detection.
    public struct MergeConfig: Sendable {
        /// Maximum aspect ratio (width/height) for a single page before it's
        /// considered a double spread that should occupy full width.
        public var singlePageMaxAspect: CGFloat = 0.75
        /// When merging, whether to place left page to the left (Western)
        /// or right page to the right (manga — right-to-left order).
        public var readingDirection: ReadingMode.Direction = .rightToLeft
        /// Minimum gap between pages to render (points).
        public var splitGap: CGFloat = 2
        /// Whether to show a thin divider line between merged pages.
        public var showDivider: Bool = true
        /// Divider color.
        public var dividerColor: Color = .gray.opacity(0.3)

        public static let `default` = MergeConfig()
    }

    // MARK: - Detection

    /// Determine whether a single page image is a double-page spread.
    /// Returns true if the aspect ratio exceeds the threshold.
    public func isDoubleSpread(imageData: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = props[kCGImagePropertyPixelHeight] as? CGFloat else {
            return false
        }
        return width > height && (width / height) > 1.35
    }

    /// Determine whether a CGImage is a double-page spread.
    public func isDoubleSpread(cgImage: CGImage) -> Bool {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        return w > h && (w / h) > 1.35
    }

    // MARK: - Merge Planning

    /// Given a list of page data, produce a merge plan: which pages to show
    /// side-by-side as spreads.
    public func buildMergePlan(pages: [PageData]) -> [SpreadLayout] {
        var spreads: [SpreadLayout] = []
        var i = 0

        while i < pages.count {
            let page = pages[i]

            // Check if current page is a double-spread (standalone)
            if let data = page.imageData, isDoubleSpread(imageData: data) {
                spreads.append(.standalone(index: i, isSpread: true))
                i += 1
                continue
            }

            // Try to pair with next page
            if i + 1 < pages.count {
                let next = pages[i + 1]
                // Only pair if neither is a spread on its own
                let thisIsSpread = page.imageData.map { isDoubleSpread(imageData: $0) } ?? false
                let nextIsSpread = next.imageData.map { isDoubleSpread(imageData: $0) } ?? false

                if !thisIsSpread && !nextIsSpread {
                    spreads.append(.paired(left: i, right: i + 1))
                    i += 2
                    continue
                }
            }

            spreads.append(.standalone(index: i, isSpread: false))
            i += 1
        }

        return spreads
    }
}

// MARK: - Spread Layout

/// Describes how pages are arranged in a spread.
public enum SpreadLayout: Equatable, Sendable {
    /// Single page displayed alone.
    case standalone(index: Int, isSpread: Bool)
    /// Two adjacent pages paired together: (leftIndex, rightIndex).
    case paired(left: Int, right: Int)

    public var indices: [Int] {
        switch self {
        case .standalone(let i, _): return [i]
        case .paired(let l, let r): return [l, r]
        }
    }
}

// MARK: - Double Page Spread View

/// Renders a spread layout: either a single page or two pages side-by-side.
public struct DoublePageSpreadView: View {
    let layout: SpreadLayout
    let pages: [PageData]
    let config: DoublePageMergeEngine.MergeConfig
    let onTapLeft: () -> Void
    let onTapRight: () -> Void

    public init(
        layout: SpreadLayout,
        pages: [PageData],
        config: DoublePageMergeEngine.MergeConfig = .default,
        onTapLeft: @escaping () -> Void = {},
        onTapRight: @escaping () -> Void = {}
    ) {
        self.layout = layout
        self.pages = pages
        self.config = config
        self.onTapLeft = onTapLeft
        self.onTapRight = onTapRight
    }

    public var body: some View {
        switch layout {
        case .standalone(let index, _):
            singlePageView(pages[safe: index])
                .onTapGesture { onTapLeft() }

        case .paired(let left, let right):
            HStack(spacing: config.splitGap) {
                singlePageView(pages[safe: left])
                    .onTapGesture { onTapLeft() }

                if config.showDivider {
                    Rectangle()
                        .fill(config.dividerColor)
                        .frame(width: 1)
                }

                singlePageView(pages[safe: right])
                    .onTapGesture { onTapRight() }
            }
        }
    }

    @ViewBuilder
    private func singlePageView(_ page: PageData?) -> some View {
        if let page = page, let data = page.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipped()
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay { ProgressView() }
        }
    }
}

// Note: Array subscript(safe:) is defined in Core/Extensions/CoreExtensions.swift
