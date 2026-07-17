import Foundation
import SwiftUI
import CoreText

// MARK: - Font Descriptor

/// Metadata for a registered custom font.
public struct CustomFontDescriptor: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let familyName: String
    public let styleName: String
    public let fileName: String
    public let fileURL: URL
    public let fileSize: Int64
    public let format: FontFormat
    public let isInstalled: Bool
    public let addedAt: Date

    public init(
        id: UUID = UUID(),
        familyName: String,
        styleName: String = "Regular",
        fileName: String,
        fileURL: URL,
        fileSize: Int64 = 0,
        format: FontFormat = .truetype,
        isInstalled: Bool = false,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.familyName = familyName
        self.styleName = styleName
        self.fileName = fileName
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.format = format
        self.isInstalled = isInstalled
        self.addedAt = addedAt
    }

    public enum FontFormat: String, Codable, Sendable {
        case truetype = "ttf"
        case opentype = "otf"
        case woff = "woff"
        case woff2 = "woff2"
        case unknown
    }

    public var displayName: String {
        "\(familyName) \(styleName)"
    }

    public var fileSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

// MARK: - Font Manager

/// Manages custom font packages for novel reading.
/// Supports importing .ttf/.otf/.woff/.woff2 files, system registration,
/// and generating @font-face CSS for EPUB injection.
@MainActor
public final class FontManager: ObservableObject, Sendable {

    @Published public private(set) var importedFonts: [CustomFontDescriptor] = []
    @Published public private(set) var systemFonts: [String] = []

    private let fontsDirectory: URL
    private let fontsManifestURL: URL

    public nonisolated init() {
        let appSupport = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DuckReader/Fonts", isDirectory: true)
        self.fontsDirectory = appSupport
        self.fontsManifestURL = appSupport.appendingPathComponent("fonts_manifest.json")

        Task { @MainActor in
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            self.loadManifest()
            self.scanSystemFonts()
        }
    }

    // MARK: - Import

    /// Import a font file from a user-selected URL (e.g., from Files app).
    /// Registers it with CoreText for system-wide availability in WKWebView.
    public func importFont(from sourceURL: URL) async throws -> CustomFontDescriptor {
        let fileName = sourceURL.lastPathComponent
        let destURL = fontsDirectory.appendingPathComponent(fileName)

        // Deduplicate
        if FileManager.default.fileExists(atPath: destURL.path) {
            throw FontError.alreadyImported(fileName)
        }

        // Copy to app font storage
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        // Read metadata
        let attributes = try FileManager.default.attributesOfItem(atPath: destURL.path)
        let fileSize = (attributes[.size] as? Int64) ?? 0
        let ext = sourceURL.pathExtension.lowercased()
        let format: CustomFontDescriptor.FontFormat = {
            switch ext {
            case "ttf": return .truetype
            case "otf": return .opentype
            case "woff": return .woff
            case "woff2": return .woff2
            default: return .unknown
            }
        }()

        // Extract font family name via CoreText
        let familyName = try extractFamilyName(from: destURL)

        // Register with CoreText (makes it available system-wide)
        try registerFont(at: destURL)

        let descriptor = CustomFontDescriptor(
            familyName: familyName,
            fileName: fileName,
            fileURL: destURL,
            fileSize: fileSize,
            format: format,
            isInstalled: true
        )

        importedFonts.append(descriptor)
        saveManifest()

        return descriptor
    }

    /// Import a font font from raw Data (e.g., bundled resource, network download).
    public func importFont(data: Data, fileName: String) async throws -> CustomFontDescriptor {
        let destURL = fontsDirectory.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destURL.path) {
            throw FontError.alreadyImported(fileName)
        }

        try data.write(to: destURL, options: .atomic)

        let familyName = try extractFamilyName(from: destURL)
        try registerFont(at: destURL)

        let descriptor = CustomFontDescriptor(
            familyName: familyName,
            fileName: fileName,
            fileURL: destURL,
            fileSize: Int64(data.count),
            isInstalled: true
        )

        importedFonts.append(descriptor)
        saveManifest()

        return descriptor
    }

    // MARK: - Remove

    public func removeFont(_ descriptor: CustomFontDescriptor) throws {
        // Unregister from CoreText
        unregisterFont(at: descriptor.fileURL)

        // Delete file
        try? FileManager.default.removeItem(at: descriptor.fileURL)

        importedFonts.removeAll { $0.id == descriptor.id }
        saveManifest()
    }

    // MARK: - Query

    /// All font family names available for CSS injection (system + custom).
    public func availableFontFamilies() -> [String] {
        let custom = importedFonts.filter(\.isInstalled).map(\.familyName)
        return Array(Set(custom + systemFonts)).sorted()
    }

    /// Generate CSS @import or @font-face rules for all imported fonts.
    public func generateFontFaceCSS() -> String {
        importedFonts
            .filter(\.isInstalled)
            .map { font in
                let ext = font.fileURL.pathExtension.lowercased()
                let formatStr: String = {
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
                    font-family: "\(font.familyName)";
                    src: url("\(font.fileURL.absoluteString)") format("\(formatStr)");
                    font-display: swap;
                }
                """
            }
            .joined(separator: "\n")
    }

    // MARK: - Preview

    /// Render a preview string in the given font.
    public func preview(font: CustomFontDescriptor, text: String = "The quick brown fox jumps over the lazy dog. 天地玄黄，宇宙洪荒。") -> Font {
        if font.isInstalled {
            return Font.custom(font.familyName, size: 18)
        }
        return Font.system(size: 18)
    }

    // MARK: - Private

    private func extractFamilyName(from url: URL) throws -> String {
        guard let provider = CGDataProvider(url: url as CFURL),
              let font = CGFont(provider) else {
            throw FontError.invalidFontFile
        }
        guard let fullName = font.fullName as String?,
              !fullName.isEmpty else {
            throw FontError.missingMetadata
        }
        return font.postScriptName as String? ?? fullName
    }

    private func registerFont(at url: URL) throws {
        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
            let msg = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw FontError.registrationFailed(msg)
        }
    }

    private func unregisterFont(at url: URL) {
        var error: Unmanaged<CFError>?
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, &error)
    }

    private func scanSystemFonts() {
        // Provide a curated list of well-known CJK + Latin fonts
        let families = UIFont.familyNames.sorted()
        systemFonts = families.filter { name in
            // Filter to fonts useful for reading (exclude symbol/emoji fonts)
            !name.lowercased().contains("symbol")
            && !name.lowercased().contains("emoji")
            && !name.lowercased().contains("lastresort")
        }
    }

    // MARK: - Persistence

    private func saveManifest() {
        do {
            let data = try JSONEncoder().encode(importedFonts)
            try data.write(to: fontsManifestURL, options: .atomic)
        } catch {
            print("[FontManager] Failed to save manifest: \(error)")
        }
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: fontsManifestURL) else { return }
        do {
            importedFonts = try JSONDecoder().decode([CustomFontDescriptor].self, from: data)
        } catch {
            print("[FontManager] Failed to load manifest: \(error)")
        }
    }
}

// MARK: - Font Errors

public enum FontError: LocalizedError {
    case alreadyImported(String)
    case invalidFontFile
    case missingMetadata
    case registrationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyImported(let name):
            return "字体 \"\(name)\" 已导入"
        case .invalidFontFile:
            return "无效的字体文件"
        case .missingMetadata:
            return "字体缺少元数据"
        case .registrationFailed(let msg):
            return "字体注册失败: \(msg)"
        }
    }
}

// MARK: - Environment Key

public struct FontManagerKey: EnvironmentKey {
    public static let defaultValue: FontManager = FontManager()
}

public extension EnvironmentValues {
    var fontManager: FontManager {
        get { self[FontManagerKey.self] }
        set { self[FontManagerKey.self] = newValue }
    }
}
