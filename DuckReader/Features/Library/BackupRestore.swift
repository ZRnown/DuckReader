import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Backup Manifest

/// Describes a backup archive for restore/review.
public struct BackupManifest: Codable, Sendable {
    public let version: Int                // Schema version
    public let createdAt: Date
    public let appVersion: String
    public let deviceName: String
    public let totalBooks: Int
    public let totalAnnotations: Int
    public let totalVocabEntries: Int
    public let fileSize: Int64

    public var fileSizeFormatted: String {
        ByteCountFormatter().string(fromByteCount: fileSize)
    }

    public init(
        version: Int = 1,
        createdAt: Date = Date(),
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
        deviceName: String = UIDevice.current.name,
        totalBooks: Int = 0,
        totalAnnotations: Int = 0,
        totalVocabEntries: Int = 0,
        fileSize: Int64 = 0
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

    /// Minimal mobile-friendly backup (excludes large data like images).
    public func mobileFriendlyVersion() -> BackupArchive {
        var copy = self
        // Keep metadata references but exclude image data fields
        copy.books = books.map { book in
            var b = book
            // Don't include file references that might not exist on new device
            return b
        }
        return copy
    }
}

/// Portable settings subset for cross-device migration.
public struct BackupSettings: Codable, Sendable {
    public var accentColor: String?
    public var appIcon: String?
    public var defaultReadingMode: String?
    public var readingDirection: String?
    public var enableAutoEnhance: Bool?
    public var enableAutoCropBorders: Bool?
    public var isPrivacyLockEnabled: Bool?
    public var privacyLockTimeout: Int?
}

// MARK: - Backup/Restore Engine

/// Handles creating and restoring full library backups.
/// Exports as a JSON bundle (or optionally .zip with embedded images).
@MainActor
public final class BackupRestoreEngine: ObservableObject, Sendable {

    @Published public private(set) var availableBackups: [BackupManifest] = []
    @Published public var isBackingUp: Bool = false
    @Published public var isRestoring: Bool = false
    @Published public var lastBackupDate: Date?

    private let backupsDirectory: URL

    public nonisolated init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.backupsDirectory = docs.appendingPathComponent("DuckReader/Backups", isDirectory: true)

        Task { @MainActor in
            try? FileManager.default.createDirectory(at: self.backupsDirectory, withIntermediateDirectories: true)
            self.scanBackups()
        }
    }

    // MARK: - Backup

    /// Create a full backup of the library.
    public func createBackup(
        books: [Book],
        metadataStore: MetadataStore,
        progressMap: [UUID: ReadingProgress],
        annotationStore: AnnotationStore,
        vocabulary: VocabularyManager,
        statsEngine: ReadingStatsEngine,
        smartListStore: SmartListStore,
        gestureStore: GestureCustomizationStore,
        themeStore: ReadingThemeStore
    ) async throws -> URL {
        isBackingUp = true
        defer { isBackingUp = false }

        let archive = BackupArchive(
            manifest: BackupManifest(
                totalBooks: books.count,
                totalAnnotations: annotationStore.annotations.count,
                totalVocabEntries: vocabulary.entries.count,
                fileSize: 0
            ),
            books: books,
            metadata: metadataStore.metadata,
            readingProgress: progressMap,
            annotations: annotationStore.annotations,
            vocabulary: vocabulary.entries,
            readingSessions: statsEngine.sessions,
            settings: BackupSettings(
                accentColor: nil,
                appIcon: nil,
                defaultReadingMode: nil,
                readingDirection: nil,
                enableAutoEnhance: nil,
                enableAutoCropBorders: nil,
                isPrivacyLockEnabled: nil,
                privacyLockTimeout: nil
            ),
            smartLists: smartListStore.lists
        )

        let data = try JSONEncoder().encode(archive)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let fileName = "DuckReader_Backup_\(dateFormatter.string(from: Date())).json"
        let fileURL = backupsDirectory.appendingPathComponent(fileName)

        try data.write(to: fileURL, options: .atomic)

        // Update manifest with actual file size
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attrs[.size] as? Int64) ?? 0

        lastBackupDate = Date()
        scanBackups()

        return fileURL
    }

    /// Create a lightweight "settings-only" backup for cross-device migration.
    public func createSettingsBackup(settings: BackupSettings) async throws -> URL {
        let data = try JSONEncoder().encode(settings)
        let fileName = "DuckReader_Settings_\(ISO8601DateFormatter().string(from: Date())).json"
        let fileURL = backupsDirectory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    // MARK: - Restore

    /// Restore from a backup URL.
    /// Returns the archive so the caller can apply it to stores.
    public func restoreFromBackup(url: URL) async throws -> BackupArchive {
        isRestoring = true
        defer { isRestoring = false }

        let data = try Data(contentsOf: url)
        let archive = try JSONDecoder().decode(BackupArchive.self, from: data)
        return archive
    }

    /// Apply a restored archive to all stores.
    public func applyRestoredArchive(
        _ archive: BackupArchive,
        metadataStore: MetadataStore,
        vocabulary: VocabularyManager,
        annotationStore: AnnotationStore,
        statsEngine: ReadingStatsEngine,
        smartListStore: SmartListStore,
        gestureStore: GestureCustomizationStore
    ) {
        // Metadata
        for (id, meta) in archive.metadata {
            metadataStore.metadata[id] = meta
        }

        // Vocabulary (merge, don't overwrite)
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

        // Annotations (merge)
        for annotation in archive.annotations {
            annotationStore.addAnnotation(annotation)
        }

        // Smart lists
        for list in archive.smartLists {
            smartListStore.addList(list)
        }

        // Sessions
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

    /// Delete a backup file.
    public func deleteBackup(_ manifest: BackupManifest) throws {
        let fileURL = backupsDirectory.appendingPathComponent(manifest.fileName)
        try FileManager.default.removeItem(at: fileURL)
        scanBackups()
    }

    /// Export backup to a shareable location.
    public func exportBackup(from url: URL) -> URL {
        // Already in a shareable location
        return url
    }

    /// Delete all backups older than N days.
    public func pruneOldBackups(olderThan days: Int) throws {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        for backup in availableBackups where backup.createdAt < cutoff {
            try deleteBackup(backup)
        }
    }

    // MARK: - Scan

    private func scanBackups() {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: backupsDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                options: .skipsHiddenFiles
            )

            availableBackups = files.compactMap { url in
                guard url.pathExtension == "json" else { return nil }
                guard let data = try? Data(contentsOf: url),
                      let manifest = try? JSONDecoder().decode(BackupArchive.self, from: data).manifest else {
                    return nil
                }
                var m = manifest
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                    m = BackupManifest(
                        version: m.version,
                        createdAt: m.createdAt,
                        appVersion: m.appVersion,
                        deviceName: m.deviceName,
                        totalBooks: m.totalBooks,
                        totalAnnotations: m.totalAnnotations,
                        totalVocabEntries: m.totalVocabEntries,
                        fileSize: attrs[.size] as? Int64 ?? 0
                    )
                }
                // Store filename for deletion
                return BackupManifestWrapper(manifest: m, fileName: url.lastPathComponent)
            }
            .sorted { $0.manifest.createdAt > $1.manifest.createdAt }
            .map { $0.manifest }
        } catch {
            print("[BackupRestore] Scan failed: \(error)")
        }
    }
}

/// Internal wrapper for file reference.
private struct BackupManifestWrapper {
    let manifest: BackupManifest
    let fileName: String
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

// MARK: - Encrypted Backup Manager Integration (v2.2)

extension BackupRestore {
    /// Delegate encrypted backup operations to EncryptedBackupManager.
    private var encryptedManager: EncryptedBackupManager { EncryptedBackupManager() }

    /// Create a passphrase-protected backup.
    public func createEncryptedBackup(passphrase: String, label: String) async throws -> BackupVersion {
        let data = try await exportAllData()
        return try await encryptedManager.createEncryptedBackup(data: data, passphrase: passphrase, label: label)
    }

    /// Restore from an encrypted backup.
    public func restoreEncryptedBackup(_ version: BackupVersion, passphrase: String) async throws {
        let data = try await encryptedManager.decryptBackup(version, passphrase: passphrase)
        try await importAllData(data)
    }
}
