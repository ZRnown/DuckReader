import Foundation

// MARK: - Progress Sync Conflict Resolver

/// Three-way merge for conflicting reading positions across devices.
/// Provides both automatic resolution (timestamp + heuristic) and
/// manual resolution with a preview UI model.
///
/// Used by CloudSyncService to handle multi-device position conflicts.
public struct ProgressSyncResolver: Sendable {

    // MARK: - Conflict Detection

    /// Check if two positions are meaningfully different (>2% progress or >5 pages).
    public static func hasConflict(
        local: SyncPosition,
        remote: SyncPosition,
        tolerancePages: Int = 5,
        toleranceProgress: Double = 0.02
    ) -> Bool {
        guard let localPages = local.totalPages, let remotePages = remote.totalPages,
              localPages > 0, remotePages > 0 else {
            // Fall back to progress comparison
            return abs(local.progress - remote.progress) > toleranceProgress
        }

        let localPage = Int(local.progress * Double(localPages))
        let remotePage = Int(remote.progress * Double(remotePages))

        return abs(localPage - remotePage) > tolerancePages
    }

    /// Detect conflicts across multiple device positions.
    public static func detectConflicts(
        positions: [SyncPosition],
        localDeviceID: String
    ) -> [SyncConflict] {
        guard positions.count > 1 else { return [] }

        var conflicts: [SyncConflict] = []
        let local = positions.first(where: { $0.deviceID == localDeviceID })
        let remotes = positions.filter { $0.deviceID != localDeviceID }

        for remote in remotes {
            if let local, hasConflict(local: local, remote: remote) {
                conflicts.append(SyncConflict(
                    localPosition: local,
                    remotePosition: remote
                ))
            }
        }

        // Also check remote-vs-remote conflicts
        for i in 0..<remotes.count {
            for j in (i+1)..<remotes.count {
                if hasConflict(local: remotes[i], remote: remotes[j]) {
                    conflicts.append(SyncConflict(
                        localPosition: remotes[i],
                        remotePosition: remotes[j]
                    ))
                }
            }
        }

        return conflicts
    }

    // MARK: - Auto-Resolution

    /// Automatically resolve a conflict using timestamp + progress heuristics.
    /// Returns the winning position or nil if manual resolution is needed.
    public static func autoResolve(
        conflict: SyncConflict,
        localDeviceID: String,
        strategy: ResolutionStrategy = .smart
    ) -> SyncPosition? {
        switch strategy {
        case .localWins:
            if conflict.localPosition.deviceID == localDeviceID {
                return conflict.localPosition
            }
            return conflict.remotePosition

        case .remoteWins:
            if conflict.remotePosition.deviceID != localDeviceID {
                return conflict.remotePosition
            }
            return conflict.localPosition

        case .mostRecent:
            return conflict.localPosition.timestamp > conflict.remotePosition.timestamp
                ? conflict.localPosition
                : conflict.remotePosition

        case .mostProgress:
            return conflict.localPosition.progress > conflict.remotePosition.progress
                ? conflict.localPosition
                : conflict.remotePosition

        case .smart:
            return smartResolve(conflict: conflict, localDeviceID: localDeviceID)
        }
    }

    /// Smart resolution: prefer local if recent, otherwise most progress, otherwise manual.
    private static func smartResolve(
        conflict: SyncConflict,
        localDeviceID: String
    ) -> SyncPosition? {
        let a = conflict.localPosition
        let b = conflict.remotePosition

        // If one is significantly more recent (>1 hour gap), take the recent one
        let timeGap = abs(a.timestamp.timeIntervalSince(b.timestamp))
        if timeGap > 3600 {
            return a.timestamp > b.timestamp ? a : b
        }

        // If one has significantly more progress (>10%), take the advanced one
        if abs(a.progress - b.progress) > 0.1 {
            return a.progress > b.progress ? a : b
        }

        // Same device wins its own position
        if a.deviceID == localDeviceID {
            return a
        }
        if b.deviceID == localDeviceID {
            return b
        }

        // Default to most recent
        return a.timestamp > b.timestamp ? a : b
    }

    // MARK: - Three-Way Merge

    /// Perform a three-way merge: base (last synced), local, remote.
    public static func threeWayMerge(
        base: SyncPosition?,
        local: SyncPosition,
        remote: SyncPosition,
        localDeviceID: String
    ) -> ThreeWayMergeResult {
        guard let base else {
            // No base — first sync, just take winner
            if let resolved = autoResolve(
                conflict: SyncConflict(localPosition: local, remotePosition: remote),
                localDeviceID: localDeviceID
            ) {
                return .autoResolved(resolved)
            }
            return .needsManualResolution(local, remote)
        }

        // Check if only one side changed
        let localChangedFromBase = hasConflict(local: local, remote: base)
        let remoteChangedFromBase = hasConflict(local: remote, remote: base)

        switch (localChangedFromBase, remoteChangedFromBase) {
        case (false, false):
            return .noChange
        case (true, false):
            return .autoResolved(local)
        case (false, true):
            return .autoResolved(remote)
        case (true, true):
            // Both changed — true conflict
            let localDeltaFromBase = local.progress - base.progress
            let remoteDeltaFromBase = remote.progress - base.progress

            // If both moved forward, take the farther one
            if localDeltaFromBase > 0 && remoteDeltaFromBase > 0 {
                return .autoResolved(localDeltaFromBase > remoteDeltaFromBase ? local : remote)
            }

            // Otherwise manual resolution
            return .needsManualResolution(local, remote)
        }
    }
}

// MARK: - Models

/// A reading position from one device.
public struct SyncPosition: Sendable {
    public let deviceID: String
    public let deviceName: String
    public let progress: Double        // 0.0–1.0
    public let totalPages: Int?
    public let currentPage: Int?
    public let timestamp: Date
    public let bookID: String

    public var progressPercent: Int {
        Int(progress * 100)
    }

    public var estimatedPage: Int? {
        guard let total = totalPages, total > 0 else { return nil }
        return Int(progress * Double(total))
    }

    public var timestampRelative: String {
        let interval = Date().timeIntervalSince(timestamp)
        switch interval {
        case ..<60:     return String(localized: "sync.justNow")
        case ..<3600:   return String(localized: "sync.minutesAgo \(Int(interval / 60))")
        case ..<86400:  return String(localized: "sync.hoursAgo \(Int(interval / 3600))")
        default:        return String(localized: "sync.daysAgo \(Int(interval / 86400))")
        }
    }

    public init(
        deviceID: String, deviceName: String,
        progress: Double, totalPages: Int? = nil,
        currentPage: Int? = nil, timestamp: Date = Date(),
        bookID: String = ""
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.progress = progress
        self.totalPages = totalPages
        self.currentPage = currentPage
        self.timestamp = timestamp
        self.bookID = bookID
    }
}

/// A detected conflict between two positions.
public struct SyncConflict: Sendable, Identifiable {
    public let id = UUID()
    public let localPosition: SyncPosition
    public let remotePosition: SyncPosition

    public var progressDiff: Double {
        abs(localPosition.progress - remotePosition.progress)
    }

    public var timeDiff: TimeInterval {
        abs(localPosition.timestamp.timeIntervalSince(remotePosition.timestamp))
    }

    public var summary: String {
        let localPct = localPosition.progressPercent
        let remotePct = remotePosition.progressPercent
        return String(localized: "sync.conflictSummary \(localPct)% \(remotePct)%")
    }
}

/// Resolution strategies.
public enum ResolutionStrategy: String, Sendable, CaseIterable {
    case smart          // Heuristic: recent + progress-aware
    case localWins      // Always take local device
    case remoteWins     // Always take remote
    case mostRecent     // Timestamp only
    case mostProgress   // Highest progress wins

    public var label: String {
        switch self {
        case .smart:        String(localized: "sync.strategy.smart")
        case .localWins:    String(localized: "sync.strategy.localWins")
        case .remoteWins:   String(localized: "sync.strategy.remoteWins")
        case .mostRecent:   String(localized: "sync.strategy.mostRecent")
        case .mostProgress: String(localized: "sync.strategy.mostProgress")
        }
    }
}

/// Result of a three-way merge.
public enum ThreeWayMergeResult: Sendable {
    case noChange
    case autoResolved(SyncPosition)
    case needsManualResolution(SyncPosition, SyncPosition)
}

// MARK: - Conflict UI Model

/// View model for a manual conflict resolution UI.
@MainActor
public final class ConflictResolutionViewModel: ObservableObject {

    @Published public var conflicts: [SyncConflict] = []
    @Published public var resolvedPositions: [UUID: SyncPosition] = [:]
    @Published public var resolutionStrategy: ResolutionStrategy = .smart

    public var conflictCount: Int { conflicts.count }
    public var resolvedCount: Int { resolvedPositions.count }

    public func resolveAllWithStrategy(_ strategy: ResolutionStrategy) {
        for conflict in conflicts {
            if let resolved = ProgressSyncResolver.autoResolve(
                conflict: conflict,
                localDeviceID: "", // caller provides
                strategy: strategy
            ) {
                resolvedPositions[conflict.id] = resolved
            }
        }
    }

    public func resolve(_ conflict: SyncConflict, pick position: SyncPosition) {
        resolvedPositions[conflict.id] = position
    }

    public func skip(_ conflict: SyncConflict) {
        // Keep local position unchanged
        resolvedPositions[conflict.id] = conflict.localPosition
    }
}
