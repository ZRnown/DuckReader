import Foundation
import SwiftUI

// MARK: - OPDS / Komga Server Configuration

/// Configuration for a self-hosted OPDS/Komga/Kavita server.
public struct OPDSConnection: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var serverURL: URL
    public var username: String?
    public var password: String?           // Stored in Keychain, not here
    public var serverType: ServerType
    public var isDefault: Bool = false
    public var lastSyncedAt: Date?
    public var isEnabled: Bool = true

    public enum ServerType: String, Codable, Sendable, CaseIterable {
        case opds = "OPDS"
        case komga = "Komga"
        case kavita = "Kavita"
        case calibreWeb = "Calibre-Web"
        case customOPDS = "Custom OPDS"

        public var displayName: String {
            switch self {
            case .opds: return "OPDS"
            case .komga: return "Komga"
            case .kavita: return "Kavita"
            case .calibreWeb: return "Calibre-Web"
            case .customOPDS: return "Custom OPDS"
            }
        }

        public var icon: String {
            switch self {
            case .opds: return "books.vertical"
            case .komga: return "character.book.closed.fill"
            case .kavita: return "book.pages"
            case .calibreWeb: return "book.fill"
            case .customOPDS: return "link"
            }
        }

        /// Default feed path for this server type.
        public var defaultPath: String {
            switch self {
            case .opds, .customOPDS: return "/opds"
            case .komga: return "/opds/v2"
            case .kavita: return "/api/opds"
            case .calibreWeb: return "/opds"
            }
        }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        serverURL: URL,
        username: String? = nil,
        password: String? = nil,
        serverType: ServerType = .opds,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.serverType = serverType
        self.isDefault = isDefault
    }

    /// Full OPDS feed URL.
    public var feedURL: URL {
        if serverURL.path.hasSuffix(serverType.defaultPath) {
            return serverURL
        }
        return serverURL.appendingPathComponent(serverType.defaultPath.dropFirst())
    }
}

// MARK: - OPDS Connection Manager

/// Manages OPDS/Komga/Kavita server connections.
@MainActor
public final class OPDSConnectionManager: ObservableObject, Sendable {

    @Published public private(set) var connections: [OPDSConnection] = []
    @Published public var isBrowsing: Bool = false
    @Published public var browseError: Error?

    private let storageURL: URL

    public nonisolated init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storageURL = docs.appendingPathComponent("DuckReader/opds_connections.json")

        Task { @MainActor in self.load() }
    }

    // MARK: - CRUD

    public func addConnection(_ connection: OPDSConnection) {
        connections.append(connection)
        save()
    }

    public func updateConnection(_ connection: OPDSConnection) {
        if let i = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[i] = connection
            save()
        }
    }

    public func removeConnection(id: UUID) {
        connections.removeAll { $0.id == id }
        save()
    }

    public func setDefault(id: UUID) {
        for i in connections.indices {
            connections[i].isDefault = (connections[i].id == id)
        }
        save()
    }

    /// Validate a connection by attempting to fetch the root feed.
    public func validateConnection(_ connection: OPDSConnection) async -> Bool {
        do {
            var request = URLRequest(url: connection.feedURL)
            request.timeoutInterval = 15

            if let user = connection.username, let pass = connection.password {
                let loginString = "\(user):\(pass)"
                let base64 = Data(loginString.utf8).base64EncodedString()
                request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
            }

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return (200...399).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    /// Test reachability and update lastSyncedAt.
    public func markSynced(id: UUID) {
        if let i = connections.firstIndex(where: { $0.id == id }) {
            connections[i].lastSyncedAt = Date()
            save()
        }
    }

    // MARK: - Persistence

    private func save() {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(connections)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            DuckLog.error("Save failed: \(error)", category: "OPDSManager")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            connections = try JSONDecoder().decode([OPDSConnection].self, from: data)
        } catch {
            DuckLog.error("Load failed: \(error)", category: "OPDSManager")
        }
    }
}

// MARK: - Environment Key

public struct OPDSConnectionManagerKey: EnvironmentKey {
    public static let defaultValue: OPDSConnectionManager = OPDSConnectionManager()
}

public extension EnvironmentValues {
    var opdsConnectionManager: OPDSConnectionManager {
        get { self[OPDSConnectionManagerKey.self] }
        set { self[OPDSConnectionManagerKey.self] = newValue }
    }
}
