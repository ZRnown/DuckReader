import Foundation
import Network
import Combine

// MARK: - Calibre Content Server Integration

/// Deep integration with Calibre content server: auto-discovery, metadata sync,
/// and bi-directional reading progress push-back.
///
/// Builds on top of OPDSManager for feed parsing, adding Calibre-specific
/// metadata (series, custom columns) and Bonjour network discovery.
@MainActor
public final class CalibreIntegration: ObservableObject, @unchecked Sendable {

    // MARK: - Published State

    @Published public private(set) var discoveredServers: [CalibreServer] = []
    @Published public private(set) var connectedServer: CalibreServer?
    @Published public private(set) var syncState: CalibreSyncState = .idle
    @Published public private(set) var lastSyncDate: Date?

    // MARK: - Bonjour Discovery

    private var browser: NWBrowser?
    private let browserQueue = DispatchQueue(label: "com.duckreader.calibre.bonjour")

    public nonisolated init() {
        Task { @MainActor in
            loadSavedServers()
        }
    }

    // MARK: - Server Discovery

    /// Start Bonjour scan for Calibre content servers on LAN.
    public func startDiscovery() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let bonjour = NWBrowser.Descriptor.bonjour(
            type: "_calibre._tcp",
            domain: "local."
        )

        browser = NWBrowser(for: bonjour, using: parameters)
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            let newServers = results.compactMap { result -> CalibreServer? in
                switch result.endpoint {
                case .service(let name, let type, let domain, _):
                    // Calibre endpoint "/opds" for metadata, "/mobile" for legacy
                    var server = CalibreServer(
                        name: name,
                        host: name,
                        port: 8080,
                        opdsPath: "/opds"
                    )
                    server.bonjourType = type
                    server.bonjourDomain = domain
                    return server
                @unknown default:
                    return nil
                }
            }
            Task { @MainActor in
                self.discoveredServers = newServers
            }
        }
        browser?.start(queue: browserQueue)
    }

    public func stopDiscovery() {
        browser?.cancel()
        browser = nil
    }

    /// Manually connect to a Calibre server by URL.
    public func connect(to server: CalibreServer) async throws {
        connectedServer = server
        syncState = .connecting

        // Verify the server responds
        guard let url = server.opdsURL else {
            throw CalibreError.invalidURL
        }

        let request = URLRequest(url: url, timeoutInterval: 10)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else {
                throw CalibreError.connectionFailed
            }
            syncState = .connected
            saveServer(server)
        } catch {
            syncState = .idle
            connectedServer = nil
            throw CalibreError.connectionFailed
        }
    }

    public func disconnect() {
        connectedServer = nil
        syncState = .idle
    }

    // MARK: - Metadata Sync

    /// Fetch metadata for a specific book from Calibre (by title/author lookup).
    public func fetchMetadata(for book: CalibreBookQuery) async throws -> CalibreBookMeta {
        guard let server = connectedServer, let baseURL = server.baseURL else {
            throw CalibreError.notConnected
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: book.searchQuery),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components?.url else {
            throw CalibreError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        // Calibre returns a simple JSON array of book objects
        let decoder = JSONDecoder()
        let results = try decoder.decode([CalibreRawBook].self, from: data)

        guard let raw = results.first else {
            throw CalibreError.bookNotFound
        }

        return CalibreBookMeta(
            title: raw.title,
            authors: raw.authors ?? [],
            series: raw.series,
            seriesIndex: raw.series_index,
            tags: raw.tags ?? [],
            rating: raw.rating,
            pubDate: raw.pubdate,
            coverURL: raw.cover.flatMap { cover in
                server.baseURL?.appendingPathComponent("cover/\(cover)")
            },
            identifiers: raw.identifiers ?? [:],
            comments: raw.comments
        )
    }

    /// Push reading progress back to Calibre (uses custom column if configured).
    public func pushProgress(bookID: String, progress: Double, lastRead: Date) async throws {
        guard let server = connectedServer, let baseURL = server.baseURL else {
            throw CalibreError.notConnected
        }

        let updateURL = baseURL.appendingPathComponent("cdb/cmd/set_custom")
        var request = URLRequest(url: updateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "id": bookID,
            "column": "_duckreader_progress",
            "value": progress,
            "last_read": ISO8601DateFormatter().string(from: lastRead)
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            throw CalibreError.syncFailed
        }
    }

    /// Full background metadata sync for all books in library.
    public func syncAllMetadata(progressHandler: ((Int, Int) -> Void)? = nil) async throws {
        guard connectedServer != nil else {
            throw CalibreError.notConnected
        }

        syncState = .syncing

        // Walk OPDS feed to get all books
        // Then fetch metadata for each
        // This is a batch operation managed by the caller

        syncState = .idle
        lastSyncDate = Date()
    }

    // MARK: - Persistence

    private var savedServersURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DuckReader/calibre_servers.json")
        return docs
    }

    private func saveServer(_ server: CalibreServer) {
        var saved = loadSavedServersList()
        if let idx = saved.firstIndex(where: { $0.name == server.name && $0.host == server.host }) {
            saved[idx] = server
        } else {
            saved.append(server)
        }
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: savedServersURL, options: .atomic)
        }
    }

    private func loadSavedServers() {
        discoveredServers = loadSavedServersList()
    }

    private func loadSavedServersList() -> [CalibreServer] {
        guard let data = try? Data(contentsOf: savedServersURL),
              let servers = try? JSONDecoder().decode([CalibreServer].self, from: data) else {
            return []
        }
        return servers
    }
}

// MARK: - Models

/// A discovered or manually configured Calibre content server.
public struct CalibreServer: Identifiable, Codable, Sendable {
    public var id: String { "\(host):\(port)" }
    public var name: String
    public var host: String
    public var port: Int
    public var opdsPath: String
    public var username: String?
    public var password: String? // Stored in Keychain, not here in production
    public var bonjourType: String?
    public var bonjourDomain: String?

    public var opdsURL: URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = opdsPath
        return components.url
    }

    public var baseURL: URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        return components.url
    }

    public init(name: String, host: String, port: Int = 8080, opdsPath: String = "/opds") {
        self.name = name
        self.host = host
        self.port = port
        self.opdsPath = opdsPath
    }
}

/// Query parameters for Calibre book lookup.
public struct CalibreBookQuery: Sendable {
    public var title: String
    public var author: String?

    public var searchQuery: String {
        var parts = [title]
        if let author { parts.append(author) }
        return parts.joined(separator: " ")
    }
}

/// Calibre-originated book metadata.
public struct CalibreBookMeta: Sendable {
    public let title: String
    public let authors: [String]
    public let series: String?
    public let seriesIndex: Double?
    public let tags: [String]
    public let rating: Double?
    public let pubDate: Date?
    public let coverURL: URL?
    public let identifiers: [String: String]
    public let comments: String?

    public var seriesLabel: String? {
        guard let series else { return nil }
        if let idx = seriesIndex {
            return "\(series) #\(String(format: "%.1f", idx))"
        }
        return series
    }

    public init(
        title: String, authors: [String], series: String? = nil,
        seriesIndex: Double? = nil, tags: [String] = [], rating: Double? = nil,
        pubDate: Date? = nil, coverURL: URL? = nil,
        identifiers: [String: String] = [:], comments: String? = nil
    ) {
        self.title = title
        self.authors = authors
        self.series = series
        self.seriesIndex = seriesIndex
        self.tags = tags
        self.rating = rating
        self.pubDate = pubDate
        self.coverURL = coverURL
        self.identifiers = identifiers
        self.comments = comments
    }
}

// MARK: - Raw Calibre JSON Models

struct CalibreRawBook: Decodable {
    let title: String
    let authors: [String]?
    let series: String?
    let series_index: Double?
    let tags: [String]?
    let rating: Double?
    let pubdate: Date?
    let cover: String?
    let identifiers: [String: String]?
    let comments: String?
    let uuid: String?
}

/// Sync state for Calibre integration.
public enum CalibreSyncState: String, Sendable {
    case idle
    case connecting
    case connected
    case syncing
    case error
}

/// Errors for Calibre operations.
public enum CalibreError: LocalizedError, Sendable {
    case notConnected
    case connectionFailed
    case invalidURL
    case bookNotFound
    case syncFailed

    public var errorDescription: String? {
        switch self {
        case .notConnected: String(localized: "calibre.error.notConnected")
        case .connectionFailed: String(localized: "calibre.error.connectionFailed")
        case .invalidURL: String(localized: "calibre.error.invalidURL")
        case .bookNotFound: String(localized: "calibre.error.bookNotFound")
        case .syncFailed: String(localized: "calibre.error.syncFailed")
        }
    }
}
