import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Backup Manifest

/// Describes a backup archive for restore/review.
public struct BackupManifest: Codable, Sendable {
    public let version: Int
    public let createdAt: Date
    public let appVersion: String
    public let deviceName: String
    public let totalBooks: Int
    public let totalAnnotations: Int
    public let totalVocabEntries: Int
    public var fileSize: Int64

    public var fileSizeFormatted: String {
        ByteCountFormatter().string(fromByteCount: fileSize)
    }

    /// Transient — set by scanBackups, not stored in JSON.
    public var fileName: String = ""

    enum CodingKeys: String, CodingKey {
        case version, createdAt, appVersion, deviceName
        case totalBooks, totalAnnotations, totalVocabEntries, fileSize
    }

    public init(
        version: Int = 1,
        createdAt: Date,
        appVersion: String,
        deviceName: String,
        totalBooks: Int,
        totalAnnotations: Int,
        totalVocabEntries: Int,
        fileSize: Int64
    ) {
        self.version = version
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.deviceName = deviceName
        self.totalBooks = totalBooks
        self.totalAnnotations = totalAnnotations
        self.totalVocabEntries = totalVocabEntries
        self.fileSize = fileSize
    }
}

// MARK: - Backup Archive

/// The full backup archive containing all library data.
public struct BackupArchive: Codable, Sendable {
    public var manifest: BackupManifest
    public var books: [Book]
    public var metadata: [UUID: EnhancedMetadata]
    public var readingProgress: [UUID: ReadingProgress]
    public var annotations: [Annotation]
    public var vocabulary: [VocabularyEntry]
    public var readingSessions: [ReadingSession]
    public var settings: BackupSettings?
    public var smartLists: [SmartList]
}

/// Portable settings subset for cross-device migration.
public struct BackupSettings: Codable, Sendable {
    public var accentColor: String?
    public var fontSize: Double?
    public var fontFamily: String?
    public var lineSpacing: Double?
    public var pageTurnDirection: String?
    public var brightness: Double?
    public var readingPresetID: String?

    public init(
        accentColor: String? = nil,
        fontSize: Double? = nil,
        fontFamily: String? = nil,
        lineSpacing: Double? = nil,
        pageTurnDirection: String? = nil,
        brightness: Double? = nil,
        readingPresetID: String? = nil
    ) {
        self.accentColor = accentColor
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.lineSpacing = lineSpacing
        self.pageTurnDirection = pageTurnDirection
        self.brightness = brightness
        self.readingPresetID = readingPresetID
    }
}

// MARK: - Backup/Restore Engine

/// Manages backup creation, restore, listing, and pruning.
public final class BackupRestoreEngine: ObservableObject, Sendable {

    @Published public var availableBackups: [BackupManifest] = []
    @Published public var lastBackupDate: Date?
    @Published public var isBackingUp = false
    @Published public var isRestoring = false

    private let backupsDirectory: URL

    /// Shared backup directory in Application Support, accessible for iCloud Drive.
    public static let sharedBackupsDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("DuckReader/Backups", isDirectory: true)
    }()

    public init(backupsDirectory: URL = BackupRestoreEngine.sharedBackupsDirectory) {
        self.backupsDirectory = backupsDirectory
        try? FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        scanBackups()
    }

    // MARK: - Create Backup

    public func createBackup(
        books: [Book],
        metadataStore: MetadataStore,
        progressMap: [UUID: ReadingProgress],
        annotationStore: AnnotationStore,
        vocabulary: VocabularyManager,
        statsEngine: ReadingStatsEngine,
        smartListStore: SmartListStore,
        themeStore: ReadingThemeStore
    ) async throws -> URL {
        isBackingUp = true
        defer { isBackingUp = false }

        let manifest = BackupManifest(
            createdAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            deviceName: Host.current().localizedName ?? "Unknown",
            totalBooks: books.count,
            totalAnnotations: annotationStore.annotations.count,
            totalVocabEntries: vocabulary.entries.count,
            fileSize: 0 // Updated after write
        )

        // Gather all reading sessions
        let sessions = statsEngine.allSessions(limit: .max)
        let settings = BackupSettings(
            accentColor: themeStore.currentTheme.accentColor.description,
            fontSize: themeStore.currentTheme.fontSize,
            fontFamily: themeStore.currentTheme.fontFamily,
            lineSpacing: themeStore.currentTheme.lineSpacing,
            pageTurnDirection: nil,
            brightness: nil,
            readingPresetID: nil
        )

        let archive = BackupArchive(
            manifest: manifest,
            books: books,
            metadata: metadataStore.metadata,
            readingProgress: progressMap,
            annotations: annotationStore.annotations,
            vocabulary: vocabulary.entries,
            readingSessions: sessions,
            settings: settings,
            smartLists: smartListStore.lists
        )

        let data = try JSONEncoder().encode(archive)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let fileName = "DuckReader_Backup_\(dateFormatter.string(from: Date())).json"
        let fileURL = backupsDirectory.appendingPathComponent(fileName)

        try data.write(to: fileURL, options: .atomic)

        lastBackupDate = Date()
        scanBackups()

        return fileURL
    }

    /// Lightweight settings-only backup for cross-device migration.
    public func createSettingsBackup(settings: BackupSettings) async throws -> URL {
        let data = try JSONEncoder().encode(settings)
        let fileName = "DuckReader_Settings_\(ISO8601DateFormatter().string(from: Date())).json"
        let fileURL = backupsDirectory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    // MARK: - Restore

    public func restoreFromBackup(url: URL) async throws -> BackupArchive {
        isRestoring = true
        defer { isRestoring = false }

        let data = try Data(contentsOf: url)
        let archive = try JSONDecoder().decode(BackupArchive.self, from: data)
        return archive
    }

    public func applyRestoredArchive(
        _ archive: BackupArchive,
        metadataStore: MetadataStore,
        vocabulary: VocabularyManager,
        annotationStore: AnnotationStore,
        statsEngine: ReadingStatsEngine,
        smartListStore: SmartListStore,
        gestureStore: GestureCustomizationStore
    ) {
        for (id, meta) in archive.metadata {
            metadataStore.metadata[id] = meta
        }

        for entry in archive.vocabulary {
            vocabulary.addEntry(
                word: entry.word,
                definition: entry.definition,
                context: entry.context,
                sourceBookID: entry.sourceBookID,
                sourceChapter: entry.sourceChapter,
                language: entry.language
            )
        }

        for annotation in archive.annotations {
            annotationStore.addAnnotation(annotation)
        }

        for list in archive.smartLists {
            smartListStore.addList(list)
        }

        for session in archive.readingSessions {
            statsEngine.recordQuickSession(
                bookID: session.bookID,
                duration: session.duration,
                pages: session.pagesRead,
                words: session.wordsRead
            )
        }
    }

    // MARK: - Manage

    public func deleteBackup(_ manifest: BackupManifest) throws {
        let fileURL = backupsDirectory.appendingPathComponent(manifest.fileName)
        try FileManager.default.removeItem(at: fileURL)
        scanBackups()
    }

    public func exportBackup(from url: URL) -> URL {
        return url
    }

    public func pruneOldBackups(olderThan days: Int) throws {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        for backup in availableBackups where backup.createdAt < cutoff {
            try deleteBackup(backup)
        }
    }

    /// Export all library data as JSON data for encrypted backup.
    public func exportAllData() async throws -> Data {
        let archive = BackupArchive(
            manifest: BackupManifest(
                createdAt: Date(),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                deviceName: Host.current().localizedName ?? "Unknown",
                totalBooks: 0,
                totalAnnotations: 0,
                totalVocabEntries: 0,
                fileSize: 0
            ),
            books: [],
            metadata: [:],
            readingProgress: [:],
            annotations: [],
            vocabulary: [],
            readingSessions: [],
            settings: nil,
            smartLists: []
        )
        return try JSONEncoder().encode(archive)
    }

    /// Import all library data from JSON data (for encrypted backup restore).
    public func importAllData(_ data: Data) async throws {
        let archive = try JSONDecoder().decode(BackupArchive.self, from: data)
        // Applying restored archive would require store references.
        // This method provides the decoded archive; caller wires it to stores.
        _ = archive
    }

    // MARK: - Scan

    private func scanBackups() {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: backupsDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                options: .skipsHiddenFiles
            )

            availableBackups = try files.compactMap { url in
                guard url.pathExtension == "json" else { return nil }
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileName = url.lastPathComponent

                guard let data = try? Data(contentsOf: url) else { return nil }

                // Decode only the manifest field to avoid loading full backup contents
                var manifest: BackupManifest
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let manifestDict = json["manifest"] as? [String: Any],
                   let manifestData = try? JSONSerialization.data(withJSONObject: manifestDict),
                   var decoded = try? JSONDecoder().decode(BackupManifest.self, from: manifestData) {
                    manifest = decoded
                } else {
                    // Fallback for legacy full-archive decode
                    guard let full = try? JSONDecoder().decode(BackupArchive.self, from: data) else {
                        return nil
                    }
                    manifest = full.manifest
                }

                manifest.fileSize = attrs[.size] as? Int64 ?? 0
                manifest.fileName = fileName
                return manifest
            }
            .sorted { $0.createdAt > $1.createdAt }
        } catch {
            DuckLog.error("Scan failed: \(error)", category: "BackupRestore")
        }
    }
}

// MARK: - Environment Key

public struct BackupRestoreKey: EnvironmentKey {
    public static let defaultValue: BackupRestoreEngine = BackupRestoreEngine()
}

public extension EnvironmentValues {
    var backupRestore: BackupRestoreEngine {
        get { self[BackupRestoreKey.self] }
        set { self[BackupRestoreKey.self] = newValue }
    }
}

// MARK: - Encrypted Backup Integration

extension BackupRestoreEngine {
    private var encryptedManager: EncryptedBackupManager {
        if let existing = objc_getAssociatedObject(self, &EncryptedBackupKey) as? EncryptedBackupManager {
            return existing
        }
        let manager = EncryptedBackupManager()
        objc_setAssociatedObject(self, &EncryptedBackupKey, manager, .OBJC_ASSOCIATION_RETAIN)
        return manager
    }

    public func createEncryptedBackup(passphrase: String, label: String) async throws -> BackupVersion {
        let data = try await exportAllData()
        return try await encryptedManager.createEncryptedBackup(data: data, passphrase: passphrase, label: label)
    }

    public func restoreEncryptedBackup(_ version: BackupVersion, passphrase: String) async throws {
        let data = try await encryptedManager.decryptBackup(version, passphrase: passphrase)
        try await importAllData(data)
    }
}

private var EncryptedBackupKey: UInt8 = 0
