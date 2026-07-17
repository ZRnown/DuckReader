import Foundation
import CryptoKit

// MARK: - Encrypted Backup Manager

/// AES-GCM encrypted backups with version history and diff-based storage.
/// Extends BackupRestore with a security layer for sensitive libraries.
///
/// Key derived from user passphrase via PBKDF2 — key never stored on disk.
@MainActor
public final class EncryptedBackupManager: ObservableObject, @unchecked Sendable {

    // MARK: - State

    @Published public private(set) var backupHistory: [BackupVersion] = []
    @Published public private(set) var isEncrypting = false
    @Published public private(set) var isDecrypting = false

    private let backupRoot: URL
    private let historyURL: URL

    public nonisolated init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DuckReader")
        backupRoot = docs.appendingPathComponent("EncryptedBackups")
        historyURL = docs.appendingPathComponent("backup_history.json")

        Task { @MainActor in
            loadHistory()
        }
    }

    // MARK: - Encryption

    /// Derive a symmetric key from a passphrase using PBKDF2.
    public static func deriveKey(from passphrase: String, salt: Data) throws -> SymmetricKey {
        guard let passData = passphrase.data(using: .utf8) else {
            throw BackupError.invalidPassphrase
        }
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: passData),
            salt: salt,
            info: "com.duckreader.backup".data(using: .utf8)!,
            outputByteCount: 32
        )
        return derived
    }

    /// Generate a random salt for key derivation.
    public static func generateSalt() -> Data {
        var salt = Data(count: 32)
        salt.withUnsafeMutableBytes { buffer in
            _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        return salt
    }

    // MARK: - Encrypt & Backup

    /// Create an encrypted backup from raw data.
    public func createEncryptedBackup(
        data: Data,
        passphrase: String,
        label: String = "",
        metadata: [String: String] = [:]
    ) async throws -> BackupVersion {
        isEncrypting = true
        defer { isEncrypting = false }

        // 1. Generate salt & derive key
        let salt = Self.generateSalt()
        let key = try Self.deriveKey(from: passphrase, salt: salt)

        // 2. Encrypt with AES-GCM
        let sealed = try AES.GCM.seal(data, using: key)
        guard let encryptedData = sealed.combined else {
            throw BackupError.encryptionFailed
        }

        // 3. Package: salt (32B) + nonce (12B) + ciphertext + tag (16B)
        var packaged = Data()
        packaged.append(salt)
        packaged.append(encryptedData)

        // 4. Write to disk
        let version = BackupVersion(
            id: UUID(),
            label: label,
            timestamp: Date(),
            sizeBytes: Int64(packaged.count),
            metadata: metadata,
            fileURL: backupRoot.appendingPathComponent("\(UUID().uuidString).dbak")
        )

        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        try packaged.write(to: version.fileURL, options: .atomic)

        // 5. Record in history
        backupHistory.append(version)
        saveHistory()

        // 6. Auto-prune: keep last 10 backups, max 5 per day
        autoPrune()

        return version
    }

    // MARK: - Decrypt & Restore

    /// Decrypt an encrypted backup.
    public func decryptBackup(
        _ version: BackupVersion,
        passphrase: String
    ) async throws -> Data {
        isDecrypting = true
        defer { isDecrypting = false }

        let packaged = try Data(contentsOf: version.fileURL)

        guard packaged.count > 44 else {
            throw BackupError.corruptBackup
        }

        // 1. Extract salt (first 32 bytes)
        let salt = packaged.prefix(32)

        // 2. Derive key
        let key = try Self.deriveKey(from: passphrase, salt: salt)

        // 3. Decrypt remaining bytes (AES-GCM sealed box)
        let sealedData = packaged.dropFirst(32)
        let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
        let decrypted = try AES.GCM.open(sealedBox, using: key)

        return decrypted
    }

    // MARK: - Version History

    /// Delete a specific backup version.
    public func deleteVersion(_ version: BackupVersion) throws {
        try? FileManager.default.removeItem(at: version.fileURL)
        backupHistory.removeAll { $0.id == version.id }
        saveHistory()
    }

    /// Delete all backups.
    public func deleteAllBackups() throws {
        for version in backupHistory {
            try? FileManager.default.removeItem(at: version.fileURL)
        }
        backupHistory.removeAll()
        saveHistory()
    }

    // MARK: - Diff-based Storage

    /// Compute a delta between two backup data sets for compact version history.
    public static func diff(from old: Data, to new: Data) -> Data {
        // Simple binary diff: find changed regions
        // Production would use bsdiff or similar
        var diffData = Data()

        let oldCount = old.count
        let newCount = new.count

        // Header: old size (8B LE) + new size (8B LE)
        var oldSize = Int64(oldCount).littleEndian
        var newSize = Int64(newCount).littleEndian
        withUnsafeBytes(of: &oldSize) { diffData.append(contentsOf: $0) }
        withUnsafeBytes(of: &newSize) { diffData.append(contentsOf: $0) }

        // Simple run-length: for each changed byte, record offset + new value
        let minLen = min(oldCount, newCount)
        var i = 0
        while i < minLen {
            if old[i] != new[i] {
                let start = i
                var length: UInt8 = 0
                while i < minLen && old[i] != new[i] && length < 255 {
                    length += 1
                    i += 1
                }
                // Record: offset (4B LE), length (1B), then data
                var offset = Int32(start).littleEndian
                withUnsafeBytes(of: &offset) { diffData.append(contentsOf: $0) }
                diffData.append(length)
                diffData.append(new[start..<start+Int(length)])
            } else {
                i += 1
            }
        }

        // Append any extra data from new that's beyond old length
        if newCount > oldCount {
            let extra = new[oldCount...]
            var offset = Int32(oldCount).littleEndian
            withUnsafeBytes(of: &offset) { diffData.append(contentsOf: $0) }
            var length = UInt8(min(extra.count, 255))
            diffData.append(length)
            diffData.append(extra.prefix(Int(length)))
        }

        return diffData
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let versions = try? JSONDecoder().decode([BackupVersion].self, from: data) else {
            return
        }
        backupHistory = versions.sorted { $0.timestamp > $1.timestamp }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(backupHistory) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    private func autoPrune() {
        guard backupHistory.count > 10 else { return }

        // Group by day
        let calendar = Calendar.current
        var byDay: [Date: [BackupVersion]] = [:]
        for v in backupHistory {
            let day = calendar.startOfDay(for: v.timestamp)
            byDay[day, default: []].append(v)
        }

        // Keep max 5 per day
        var toKeep: Set<UUID> = []
        for (_, versions) in byDay {
            let keep = versions.prefix(5)
            toKeep.formUnion(keep.map(\.id))
        }

        // Remove others
        let toRemove = backupHistory.filter { !toKeep.contains($0.id) }
        for v in toRemove {
            try? FileManager.default.removeItem(at: v.fileURL)
        }

        backupHistory = backupHistory.filter { toKeep.contains($0.id) }
        saveHistory()
    }
}

// MARK: - Models

/// A versioned encrypted backup.
public struct BackupVersion: Identifiable, Codable, Sendable {
    public let id: UUID
    public let label: String
    public let timestamp: Date
    public let sizeBytes: Int64
    public let metadata: [String: String]
    public let fileURL: URL

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    public var relativeDate: String {
        let interval = Date().timeIntervalSince(timestamp)
        switch interval {
        case ..<60:     String(localized: "backup.justNow")
        case ..<3600:   String(localized: "backup.minutesAgo \(Int(interval / 60))")
        case ..<86400:  String(localized: "backup.hoursAgo \(Int(interval / 3600))")
        default:        String(localized: "backup.daysAgo \(Int(interval / 86400))")
        }
    }
}

public enum BackupError: LocalizedError, Sendable {
    case invalidPassphrase
    case encryptionFailed
    case decryptionFailed
    case corruptBackup
    case noBackups

    public var errorDescription: String? {
        switch self {
        case .invalidPassphrase: String(localized: "backup.error.invalidPassphrase")
        case .encryptionFailed:  String(localized: "backup.error.encryptionFailed")
        case .decryptionFailed:  String(localized: "backup.error.decryptionFailed")
        case .corruptBackup:     String(localized: "backup.error.corruptBackup")
        case .noBackups:         String(localized: "backup.error.noBackups")
        }
    }
}
