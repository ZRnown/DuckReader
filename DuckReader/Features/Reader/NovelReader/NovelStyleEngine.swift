import Foundation
import SwiftUI

// MARK: - Novel Style Configuration

/// Fine-grained typography and layout configuration for novel reading.
/// Customizable via CSS injection into the EPUB/HTML renderer.
public struct NovelStyleConfig: Codable, Equatable, Sendable {

    // MARK: Font
    public var fontFamily: String = "system-ui"
    public var fontSize: CGFloat = 16
    public var fontWeight: FontWeight = .regular
    public var customFontURL: URL? = nil

    // MARK: Spacing
    public var lineHeight: CGFloat = 1.6          // multiplier
    public var paragraphSpacing: CGFloat = 8      // points
    public var firstLineIndent: CGFloat = 2       // em units
    public var letterSpacing: CGFloat = 0         // points
    public var wordSpacing: CGFloat = 0           // points

    // MARK: Margins
    public var marginTop: CGFloat = 16
    public var marginBottom: CGFloat = 16
    public var marginLeft: CGFloat = 20
    public var marginRight: CGFloat = 20

    // MARK: Columns
    public var columnCount: Int = 1              // 1 = standard, 2 = dual-column (iPad)
    public var columnGap: CGFloat = 24

    // MARK: Alignment
    public var textAlign: TextAlignment = .justify
    public var verticalAlign: VerticalAlignment = .top

    // MARK: Hyphenation
    public var hyphenationEnabled: Bool = true
    public var hyphenationLocale: String = "en"

    // MARK: Orphans & Widows
    public var orphans: Int = 2
    public var widows: Int = 2

    // MARK: Image Handling
    public var maxImageWidth: ImageConstraint = .percent(100)
    public var imageFilter: ImageFilter = .none

    public enum FontWeight: String, Codable, Sendable {
        case thin, extraLight, light, regular, medium, semibold, bold, extraBold, black
    }

    public enum TextAlignment: String, Codable, Sendable {
        case left, right, center, justify
    }

    public enum VerticalAlignment: String, Codable, Sendable {
        case top, center
    }

    public enum ImageConstraint: Codable, Equatable, Sendable {
        case percent(CGFloat)
        case pixels(Int)
        case none
    }

    public enum ImageFilter: String, Codable, Sendable {
        case none
        case sepia
        case grayscale
        case nightMode
    }

    // MARK: Presets

    public static let `default` = NovelStyleConfig()

    public static let comfortable: NovelStyleConfig = {
        var c = NovelStyleConfig()
        c.fontSize = 18
        c.lineHeight = 1.8
        c.paragraphSpacing = 12
        c.firstLineIndent = 2.5
        return c
    }()

    public static let compact: NovelStyleConfig = {
        var c = NovelStyleConfig()
        c.fontSize = 14
        c.lineHeight = 1.4
        c.marginLeft = 12
        c.marginRight = 12
        return c
    }()

    public static let kindleClassic: NovelStyleConfig = {
        var c = NovelStyleConfig()
        c.fontFamily = "Palatino, serif"
        c.fontSize = 15
        c.lineHeight = 1.5
        c.firstLineIndent = 1.5
        c.textAlign = .justify
        c.hyphenationEnabled = true
        return c
    }()
}

// MARK: - CSS Injection Engine

/// Generates CSS from NovelStyleConfig for injection into EPUB/HTML content.
/// Supports @font-face for custom fonts and `:root`-scoped custom properties.
public struct NovelStyleEngine: Sendable {

    public let config: NovelStyleConfig

    public init(config: NovelStyleConfig = .default) {
        self.config = config
    }

    // MARK: - CSS Generation

    /// Generate the complete CSS string for injection.
    public func generateCSS() -> String {
        var css = """
        /* DuckReader Novel Styles — injected by NovelStyleEngine */
        :root {
            --dr-font-family: \(cssFontFamily());
            --dr-font-size: \(config.fontSize)px;
            --dr-line-height: \(config.lineHeight);
            --dr-paragraph-spacing: \(config.paragraphSpacing)px;
            --dr-first-indent: \(config.firstLineIndent)em;
            --dr-letter-spacing: \(config.letterSpacing)px;
            --dr-word-spacing: \(config.wordSpacing)px;
            --dr-margin-top: \(config.marginTop)px;
            --dr-margin-bottom: \(config.marginBottom)px;
            --dr-margin-left: \(config.marginLeft)px;
            --dr-margin-right: \(config.marginRight)px;
            --dr-text-align: \(cssTextAlign());
            --dr-column-count: \(config.columnCount);
            --dr-column-gap: \(config.columnGap)px;
            --dr-orphans: \(config.orphans);
            --dr-widows: \(config.widows);
        }

        /* ---- Base body ---- */
        body {
            font-family: var(--dr-font-family);
            font-size: var(--dr-font-size);
            line-height: var(--dr-line-height);
            letter-spacing: var(--dr-letter-spacing);
            word-spacing: var(--dr-word-spacing);
            text-align: \(cssTextAlign());
            margin: var(--dr-margin-top) var(--dr-margin-right) var(--dr-margin-bottom) var(--dr-margin-left);
            column-count: var(--dr-column-count);
            column-gap: var(--dr-column-gap);
            orphans: var(--dr-orphans);
            widows: var(--dr-widows);
            \(cssHyphenation())
        }

        /* ---- Paragraphs ---- */
        p {
            text-indent: var(--dr-first-indent);
            margin-bottom: var(--dr-paragraph-spacing);
        }

        /* Remove indent on first paragraph after heading */
        h1 + p, h2 + p, h3 + p, h4 + p, h5 + p, h6 + p,
        hr + p, blockquote + p, .no-indent {
            text-indent: 0;
        }

        /* ---- Headings ---- */
        h1 { font-size: calc(var(--dr-font-size) * 2.0); }
        h2 { font-size: calc(var(--dr-font-size) * 1.6); }
        h3 { font-size: calc(var(--dr-font-size) * 1.35); }
        h4 { font-size: calc(var(--dr-font-size) * 1.15); }

        /* ---- Images ---- */
        img {
            max-width: \(cssImageMaxWidth());
            height: auto;
            display: block;
            margin: \(config.paragraphSpacing)px auto;
            \(cssImageFilter())
        }

        /* ---- Blockquote ---- */
        blockquote {
            margin-left: 1.5em;
            padding-left: 1em;
            border-left: 3px solid var(--dr-accent-color, #888);
            font-style: italic;
            color: var(--dr-secondary-text, #555);
        }

        /* ---- Code / pre ---- */
        pre, code {
            font-family: "SF Mono", "Menlo", "Consolas", monospace;
            font-size: calc(var(--dr-font-size) * 0.88);
        }

        /* ---- Links ---- */
        a {
            color: var(--dr-accent-color, #007AFF);
        }
        """

        // Append @font-face if custom font registered
        if let fontURL = config.customFontURL {
            css += "\n\n/* ---- Custom Font ---- */\n"
            css += generateFontFaceCSS(from: fontURL)
        }

        return css
    }

    /// Generate a minimal CSS string for a specific reading theme overlay.
    public func generateThemeOverlayCSS(theme: ReadingTheme) -> String {
        """
        /* DuckReader Theme Overlay: \(theme.name) */
        :root {
            --dr-bg-color: \(theme.backgroundColorHex);
            --dr-text-color: \(theme.textColorHex);
            --dr-accent-color: \(theme.accentColorHex);
            --dr-secondary-text: \(theme.secondaryTextColorHex);
        }
        body {
            background-color: var(--dr-bg-color) !important;
            color: var(--dr-text-color) !important;
        }
        a { color: var(--dr-accent-color) !important; }
        img { \(cssImageFilter(for: theme.imageFilter)) }
        """
    }

    // MARK: - CSS Helpers

    private func cssFontFamily() -> String {
        if let url = config.customFontURL {
            let name = url.deletingPathExtension().lastPathComponent
            return "\"\(name)\", \(config.fontFamily)"
        }
        return config.fontFamily
    }

    private func cssTextAlign() -> String {
        switch config.textAlign {
        case .left: return "left"
        case .right: return "right"
        case .center: return "center"
        case .justify: return "justify"
        }
    }

    private func cssHyphenation() -> String {
        guard config.hyphenationEnabled else { return "" }
        return """
        -webkit-hyphens: auto;
        -moz-hyphens: auto;
        -ms-hyphens: auto;
        hyphens: auto;
        hyphenate-limit-chars: 6 3 2;
        """
    }

    private func cssImageMaxWidth() -> String {
        switch config.maxImageWidth {
        case .percent(let p): return "\(p)%"
        case .pixels(let px): return "\(px)px"
        case .none: return "none"
        }
    }

    private func cssImageFilter() -> String {
        switch config.imageFilter {
        case .none: return ""
        case .sepia: return "filter: sepia(0.8);"
        case .grayscale: return "filter: grayscale(1);"
        case .nightMode: return "filter: brightness(0.7) sepia(0.3);"
        }
    }

    private func cssImageFilter(for filter: ReadingTheme.ImageFilter) -> String {
        switch filter {
        case .none: return ""
        case .sepia: return "filter: sepia(0.8) !important;"
        case .grayscale: return "filter: grayscale(1) !important;"
        case .nightMode: return "filter: brightness(0.7) sepia(0.3) !important;"
        }
    }

    private func generateFontFaceCSS(from url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased()
        let format: String = {
            switch ext {
            case "ttf": return "truetype"
            case "otf": return "opentype"
            case "woff": return "woff"
            case "woff2": return "woff2"
            default: return "truetype"
            }
        }()
        return """
        @font-face {
            font-family: "\(name)";
            src: url("\(url.absoluteString)") format("\(format)");
            font-display: swap;
        }
        """
    }
}

// MARK: - Reading Theme Definition

/// A named reading theme with precise color definitions.
public struct ReadingTheme: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let backgroundColorHex: String
    public let textColorHex: String
    public let accentColorHex: String
    public let secondaryTextColorHex: String
    public let imageFilter: ImageFilter
    public let brightness: Double       // 0.0–1.0 (device brightness)
    public let colorTemperature: Double // Kelvin-ish value (warm/cool)

    public enum ImageFilter: String, Codable, Sendable {
        case none, sepia, grayscale, nightMode
    }

    // MARK: Built-in Themes

    public static let light = ReadingTheme(
        id: "light",
        name: "Light",
        backgroundColorHex: "#FFFFFF",
        textColorHex: "#1A1A1A",
        accentColorHex: "#007AFF",
        secondaryTextColorHex: "#6E6E6E",
        imageFilter: .none,
        brightness: 1.0,
        colorTemperature: 6500
    )

    public static let sepia = ReadingTheme(
        id: "sepia",
        name: "Sepia",
        backgroundColorHex: "#F4ECD8",
        textColorHex: "#5B4636",
        accentColorHex: "#8B5E3C",
        secondaryTextColorHex: "#8C7A6B",
        imageFilter: .sepia,
        brightness: 0.85,
        colorTemperature: 3500
    )

    public static let dark = ReadingTheme(
        id: "dark",
        name: "Dark",
        backgroundColorHex: "#1C1C1E",
        textColorHex: "#E5E5E5",
        accentColorHex: "#0A84FF",
        secondaryTextColorHex: "#98989E",
        imageFilter: .nightMode,
        brightness: 0.4,
        colorTemperature: 5500
    )

    public static let amoled = ReadingTheme(
        id: "amoled",
        name: "AMOLED Black",
        backgroundColorHex: "#000000",
        textColorHex: "#CCCCCC",
        accentColorHex: "#3B82F6",
        secondaryTextColorHex: "#777777",
        imageFilter: .nightMode,
        brightness: 0.3,
        colorTemperature: 6000
    )

    public static let paperWhite = ReadingTheme(
        id: "paper_white",
        name: "Paper White",
        backgroundColorHex: "#F5F5F0",
        textColorHex: "#2D2D2D",
        accentColorHex: "#555555",
        secondaryTextColorHex: "#888888",
        imageFilter: .none,
        brightness: 0.8,
        colorTemperature: 5500
    )

    public static let nightBlue = ReadingTheme(
        id: "night_blue",
        name: "Night Blue",
        backgroundColorHex: "#0B1A2E",
        textColorHex: "#B8C7D9",
        accentColorHex: "#5B9BD5",
        secondaryTextColorHex: "#6B7B8D",
        imageFilter: .nightMode,
        brightness: 0.25,
        colorTemperature: 4800
    )

    public static let allBuiltIn: [ReadingTheme] = [
        .light, .sepia, .dark, .amoled, .paperWhite, .nightBlue
    ]
}

// MARK: - Reading Theme Store

/// Manages reading theme selection, custom themes, and auto-switching rules.
@MainActor
public final class ReadingThemeStore: ObservableObject, Sendable {
    @Published public var currentTheme: ReadingTheme = .light
    @Published public var customThemes: [ReadingTheme] = []
    @Published public var autoSwitchEnabled: Bool = false
    @Published public var dayTheme: ReadingTheme = .light
    @Published public var nightTheme: ReadingTheme = .dark
    @Published public var nightStartHour: Int = 21  // 9 PM
    @Published public var nightEndHour: Int = 7      // 7 AM

    public nonisolated init() {}

    public func setTheme(_ theme: ReadingTheme) {
        currentTheme = theme
    }

    public func addCustomTheme(_ theme: ReadingTheme) {
        customThemes.append(theme)
    }

    public func removeCustomTheme(id: String) {
        customThemes.removeAll { $0.id == id }
    }

    public func autoSwitchIfNeeded() {
        guard autoSwitchEnabled else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= nightStartHour || hour < nightEndHour {
            if currentTheme.id != nightTheme.id {
                currentTheme = nightTheme
            }
        } else {
            if currentTheme.id != dayTheme.id {
                currentTheme = dayTheme
            }
        }
    }
}
