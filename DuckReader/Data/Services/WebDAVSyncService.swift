import Foundation
import Combine

// MARK: - WebDAV Sync Service

/// Syncs library and reading data to a user-provided WebDAV server
/// (e.g. ownCloud, Nextcloud, NAS with WebDAV).
/// Uses a simple JSON-export / import model for portability.
@MainActor
public final class WebDAVSyncService: ObservableObject {
    public static let shared = WebDAVSyncService()

    @Published public private(set) var syncState: SyncState = .idle
    @Published public private(set) var lastSyncDate: Date?

    public enum SyncState: Sendable {
        case idle
        case syncing
        case success
        case error(String)
    }

    public struct WebDAVConfig: Codable, Sendable {
        public var serverURL: String
        public var username: String
        public var password: String
        public var remotePath: String = "/DuckReader"

        public init(serverURL: String, username: String, password: String) {
            self.serverURL = serverURL
            self.username = username
            self.password = password
        }
    }

    private var config: WebDAVConfig?

    // Sync manifest file name
    private let manifestName = "duckreader_sync.json"

    private init() {}

    // MARK: - Public API

    /// Configure with WebDAV server details.
    public func configure(config: WebDAVConfig) {
        self.config = config
    }

    /// Test connection to the WebDAV server.
    public func testConnection(config: WebDAVConfig) async throws -> Bool {
        var request = makeRequest(config: config, path: "/", method: "PROPFIND")
        request.setValue("0", forHTTPHeaderField: "Depth")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return (200...207).contains(httpResponse.statusCode)
    }

    /// Export library data as JSON and upload to WebDAV.
    public func exportLibrary(books: [BookExportData], progress: [ProgressExportData]) async throws {
        guard let config else { throw WebDAVError.notConfigured }
        syncState = .syncing
        defer { syncState = .idle }

        let manifest = SyncManifest(
            version: 1,
            exportedAt: Date(),
            books: books,
            progress: progress
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)

        try await upload(config: config, path: "/\(manifestName)", data: data)

        lastSyncDate = Date()
        syncState = .success
    }

    /// Import library data from WebDAV JSON.
    public func importLibrary() async throws -> SyncManifest {
        guard let config else { throw WebDAVError.notConfigured }
        syncState = .syncing
        defer { syncState = .idle }

        let data = try await download(config: config, path: "/\(manifestName)")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(SyncManifest.self, from: data)

        lastSyncDate = Date()
        syncState = .success
        return manifest
    }

    /// Upload a raw file (e.g., book archive) to WebDAV.
    public func uploadBook(fileURL: URL, remoteName: String) async throws {
        guard let config else { throw WebDAVError.notConfigured }

        let data = try Data(contentsOf: fileURL)
        let remotePath = "/books/\(remoteName)"

        // Ensure /books/ directory exists
        try? await createDirectory(config: config, path: "/books/")
        try await upload(config: config, path: remotePath, data: data)
    }

    /// Download a raw file from WebDAV.
    public func downloadBook(remoteName: String) async throws -> Data {
        guard let config else { throw WebDAVError.notConfigured }
        return try await download(config: config, path: "/books/\(remoteName)")
    }

    /// List all files in the WebDAV books directory.
    public func listRemoteBooks() async throws -> [WebDAVFile] {
        guard let config else { throw WebDAVError.notConfigured }
        let xmlData = try await download(config: config, path: "/books/", method: "PROPFIND")
        return try parseWebDAVListing(xmlData)
    }

    // MARK: - Private

    private func makeRequest(config: WebDAVConfig, path: String, method: String) -> URLRequest {
        let urlString = config.serverURL.hasSuffix("/")
            ? config.serverURL + (path.hasPrefix("/") ? String(path.dropFirst()) : path)
            : config.serverURL + path

        guard let url = URL(string: urlString) else {
            fatalError("Invalid WebDAV URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30

        let credentials = "\(config.username):\(config.password)"
        if let authData = credentials.data(using: .utf8) {
            request.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func upload(config: WebDAVConfig, path: String, data: Data) async throws {
        var request = makeRequest(config: config, path: path, method: "PUT")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...201).contains(httpResponse.statusCode) else {
            throw WebDAVError.uploadFailed
        }
    }

    private func download(config: WebDAVConfig, path: String, method: String = "GET") async throws -> Data {
        var request = makeRequest(config: config, path: path, method: method)
        if method == "PROPFIND" {
            request.setValue("1", forHTTPHeaderField: "Depth")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...207).contains(httpResponse.statusCode) else {
            throw WebDAVError.downloadFailed
        }
        return data
    }

    private func createDirectory(config: WebDAVConfig, path: String) async throws {
        var request = makeRequest(config: config, path: path, method: "MKCOL")
        let (_, response) = try await URLSession.shared.data(for: request)

        // 405 = already exists, which is fine
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 || httpResponse.statusCode == 405 else {
            throw WebDAVError.createFolderFailed
        }
    }

    private func parseWebDAVListing(_ xmlData: Data) throws -> [WebDAVFile] {
        // Simplified: extract hrefs from XML
        guard let xmlString = String(data: xmlData, encoding: .utf8) else {
            throw WebDAVError.parseError
        }

        let hrefPattern = try! NSRegularExpression(pattern: "<D:href>([^<]+)</D:href>")
        let matches = hrefPattern.matches(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString))

        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: xmlString) else { return nil }
            let href = String(xmlString[range]).removingPercentEncoding ?? String(xmlString[range])
            let name = (href as NSString).lastPathComponent
            guard !name.isEmpty, name != "books" else { return nil }
            return WebDAVFile(name: name, path: href)
        }
    }
}

// MARK: - Data Types

public struct SyncManifest: Codable, Sendable {
    public let version: Int
    public let exportedAt: Date
    public let books: [BookExportData]
    public let progress: [ProgressExportData]
}

public struct BookExportData: Codable, Sendable {
    public let id: String
    public let title: String
    public let author: String
    public let format: String
    public let coverHash: String?
    public let addedAt: Date
}

public struct ProgressExportData: Codable, Sendable {
    public let bookID: String
    public let chapter: Int
    public let page: Int
    public let totalPages: Int
    public let progress: Double
    public let updatedAt: Date
}

public struct WebDAVFile: Codable, Sendable, Identifiable {
    public let name: String
    public let path: String
    public var id: String { path }
}

public enum WebDAVError: LocalizedError {
    case notConfigured
    case uploadFailed
    case downloadFailed
    case createFolderFailed
    case parseError
    case connectionFailed

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "WebDAV 未配置"
        case .uploadFailed: return "上传失败"
        case .downloadFailed: return "下载失败"
        case .createFolderFailed: return "创建远程文件夹失败"
        case .parseError: return "解析服务器响应失败"
        case .connectionFailed: return "连接失败"
        }
    }
}
