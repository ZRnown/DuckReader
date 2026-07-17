import SwiftUI
import CoreText

// MARK: - CJK Vertical Text Renderer

/// Renders Chinese/Japanese/Korean text in traditional vertical layout.
/// Handles: right-to-left columns, top-to-bottom flow, proper punctuation
/// rotation, ruby/furigana annotations (basic), and mixed horizontal text segments.
///
/// This is a SwiftUI-native implementation using CoreText for glyph layout.
/// For full CJK typesetting, consider integrating CoreText's
/// `kCTVerticalFormsAttributeName` at the CTFramesetter level.

// MARK: - Vertical Layout Configuration

public struct CJKVerticalConfig: Sendable {
    /// Column width in points (character cell size).
    public var columnWidth: CGFloat = 24

    /// Line height (character advance in vertical direction).
    public var lineHeight: CGFloat = 28

    /// Gap between columns.
    public var columnGap: CGFloat = 12

    /// Font size for body text.
    public var fontSize: CGFloat = 18

    /// Font for body text (use CJK-capable font).
    public var fontName: String = "STSongti-SC"

    /// Whether to use vertical punctuation (rotated brackets, etc.).
    public var rotatePunctuation: Bool = true

    /// Number of columns per screen.
    public var columnsPerScreen: Int = 0  // 0 = auto-calculate

    public static let `default` = CJKVerticalConfig()
}

// MARK: - Vertical Text View

/// A SwiftUI view that renders text in CJK vertical layout.
/// The view calculates columns based on available width and renders
/// each column as a rotated View.
@MainActor
public struct CJKVerticalTextView: View {
    let text: String
    let config: CJKVerticalConfig

    @State private var columns: [String] = []
    @State private var totalColumns: Int = 0
    @State private var containerSize: CGSize = .zero

    public init(text: String, config: CJKVerticalConfig = .default) {
        self.text = text
        self.config = config
    }

    public var body: some View {
        GeometryReader { geometry in
            let _ = Task { @MainActor in
                containerSize = geometry.size
                columns = layoutColumns(text: text, config: config, containerSize: geometry.size)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: config.columnGap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                        VerticalColumnView(
                            text: column,
                            config: config
                        )
                        .frame(width: config.columnWidth)
                        .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, geometry.safeAreaInsets.top + 16)
            }
            .defaultScrollAnchor(.trailing)
            .scrollClipDisabled()
        }
    }

    /// Break text into vertical columns.
    private func layoutColumns(text: String, config: CJKVerticalConfig, containerSize: CGSize) -> [String] {
        let maxLinesPerColumn = Int((containerSize.height - 32) / config.lineHeight)
        guard maxLinesPerColumn > 0 else { return [text] }

        let chars = Array(text)
        var columns: [String] = []
        var currentColumn: [Character] = []
        var lineCount = 0

        for char in chars {
            // Handle newlines as explicit column breaks
            if char == "\n" {
                if !currentColumn.isEmpty {
                    columns.append(String(currentColumn))
                    currentColumn = []
                }
                columns.append("") // Empty column for paragraph break
                lineCount = 0
                continue
            }

            currentColumn.append(char)

            // CJK character always advances one line
            if isCJKCharacter(char) || char.isPunctuation || char == " " {
                lineCount += 1
            } else if char.isASCII && char.isLetter {
                // Latin letters in vertical: rotated sideways
                // Each letter gets a line (simplified; ideally letters stack in one line)
                lineCount += 1
            }

            if lineCount >= maxLinesPerColumn {
                columns.append(String(currentColumn))
                currentColumn = []
                lineCount = 0
            }
        }

        if !currentColumn.isEmpty {
            columns.append(String(currentColumn))
        }

        return columns
    }

    private func isCJKCharacter(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value) ||   // CJK Unified
               (0x3400...0x4DBF).contains(scalar.value) ||   // CJK Extension A
               (0x3040...0x309F).contains(scalar.value) ||   // Hiragana
               (0x30A0...0x30FF).contains(scalar.value) ||   // Katakana
               (0xAC00...0xD7AF).contains(scalar.value) ||   // Hangul
               (0x3000...0x303F).contains(scalar.value)      // CJK Symbols/Punctuation
    }
}

// MARK: - Single Vertical Column

private struct VerticalColumnView: View {
    let text: String
    let config: CJKVerticalConfig

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, char in
                Text(String(char))
                    .font(.custom(config.fontName, size: config.fontSize))
                    .frame(width: config.columnWidth, height: config.lineHeight)
                    .rotationEffect(shouldRotate(char) ? .degrees(90) : .zero)
                    .id("\(index)")
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Rotate punctuation marks that should appear sideways in vertical text.
    private func shouldRotate(_ char: Character) -> Bool {
        guard config.rotatePunctuation else { return false }
        let rotateSet: Set<Character> = [
            "(", ")", "（", "）", "[", "]", "【", "】",
            "「", "」", "『", "』", "〈", "〉", "《", "》",
            "“", "”", "‘", "’",
        ]
        return rotateSet.contains(char)
    }
}

// MARK: - Horizontal CJK Reader (Simple, non-vertical fallback)

/// Standard horizontal CJK reader with proper line-height and kerning.
/// Used as the default until user enables vertical mode.
public struct CJKHorizontalReaderView: View {
    let text: String
    let config: CJKVerticalConfig

    @State private var fontSize: CGFloat

    public init(text: String, config: CJKVerticalConfig = .default) {
        self.text = text
        self.config = config
        self._fontSize = State(initialValue: config.fontSize)
    }

    public var body: some View {
        ScrollView {
            Text(text)
                .font(.custom(config.fontName, size: fontSize))
                .lineSpacing(config.lineHeight - fontSize)
                .tracking(0.5)  // Slight tracking for CJK readability
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let newSize = config.fontSize * value
                    fontSize = min(max(newSize, 12), 36)
                }
        )
    }
}

// MARK: - Ruby / Furigana Annotation (Basic)

/// Attaches reading annotation above CJK characters.
/// For full ruby support, CoreText's `kCTRubyAnnotation` is recommended.
/// This is a simplified SwiftUI overlay approach.
public struct RubyAnnotation: View {
    let base: String
    let ruby: String
    let config: CJKVerticalConfig

    public init(base: String, ruby: String, config: CJKVerticalConfig = .default) {
        self.base = base
        self.ruby = ruby
        self.config = config
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Ruby text (small, above)
            Text(ruby)
                .font(.custom(config.fontName, size: config.fontSize * 0.5))
                .foregroundStyle(.secondary)

            // Base text
            Text(base)
                .font(.custom(config.fontName, size: config.fontSize))
        }
        .fixedSize()
    }
}

// MARK: - CoreText Vertical Rendering (Advanced)

/// CoreText-based vertical layout for production use.
/// Uses `kCTVerticalFormsAttributeName` for proper glyph rotation.
public final class CTVerticalRenderer {
    public static func renderVertical(
        text: String,
        font: CTFont,
        containerSize: CGSize,
        config: CJKVerticalConfig
    ) -> [CGImage?] {
        let attributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .verticalGlyphForm: true,  // Key for vertical rendering
            ]
        )

        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)

        // Create path for vertical columns
        var columnFrames: [CTFrame] = []
        var currentX: CGFloat = 0
        let columnWidth: CGFloat = config.columnWidth
        let columnHeight: CGFloat = containerSize.height

        while currentX + columnWidth <= containerSize.width {
            let columnRect = CGRect(
                x: containerSize.width - currentX - columnWidth, // right-to-left
                y: 0,
                width: columnWidth,
                height: columnHeight
            )

            let path = CGPath(rect: columnRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
            columnFrames.append(frame)

            currentX += columnWidth + config.columnGap
        }

        // Render to CGImage array
        return columnFrames.map { frame in
            let renderer = UIGraphicsImageRenderer(size: containerSize)
            return renderer.image { ctx in
                // Flip context for CoreText coordinate system
                ctx.cgContext.translateBy(x: 0, y: containerSize.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, ctx.cgContext)
            }.cgImage
        }
    }
}
