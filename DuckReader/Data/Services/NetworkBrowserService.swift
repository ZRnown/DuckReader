import Foundation
import Network
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Network Browser Service

/// Discovers SMB, WebDAV, and Bonjour services on the local network.
/// Provides a unified file browser for NAS / shared drives.
@MainActor
public final class NetworkBrowserService: ObservableObject {
    public static let shared = NetworkBrowserService()

    @Published public private(set) var discoveredServices: [NetworkService] = []
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var error: String?

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.duckreader.network")

    public init() {}

    // MARK: - Bonjour / mDNS Discovery

    /// Start scanning for network services.
    public func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        discoveredServices.removeAll()
        error = nil

        // SMB (_smb._tcp)
        scanService(type: "_smb._tcp.", domain: "local.", name: "SMB")
        // WebDAV / HTTP (_http._tcp) — NAS often use this
        scanService(type: "_http._tcp.", domain: "local.", name: "HTTP")
        // FTP (_ftp._tcp)
        scanService(type: "_ftp._tcp.", domain: "local.", name: "FTP")
    }

    private func scanService(type: String, domain: String, name: String) {
        let params = NWParameters()
        params.includePeerToPeer = true

        let descriptor = NWBrowser.Descriptor.bonjour(type: type, domain: domain)
        let browser = NWBrowser(for: descriptor, using: params)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .failed(let err):
                    self?.error = err.localizedDescription
                    self?.isScanning = false
                case .ready:
                    self?.isScanning = true
                case .cancelled:
                    self?.isScanning = false
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                for result in results {
                    let service = NetworkService(
                        name: result.endpoint.debugDescription
                            .replacingOccurrences(of: "::", with: "")
                            .replacingOccurrences(of: "\"", with: ""),
                        type: NetworkServiceType.from(bonjourType: type),
                        endpoint: result.endpoint,
                        host: self?.extractHost(from: result.endpoint)
                    )

                    // Deduplicate
                    if !(self?.discoveredServices.contains(where: { $0.name == service.name }) ?? false) {
                        self?.discoveredServices.append(service)
                    }
                }
            }
        }

        browser.start(queue: queue)
    }

    /// Stop scanning.
    public func stopScanning() {
        browser?.cancel()
        browser = nil
        isScanning = false
    }

    // MARK: - Manual Connection

    /// Connect to a manually specified server by IP/hostname.
    public func connectManual(host: String, port: Int, scheme: String = "smb") -> NetworkService {
        let service = NetworkService(
            name: host,
            type: scheme == "webdav" ? .webdav : .smb,
            endpoint: nil,
            host: host,
            port: port
        )
        return service
    }

    /// Test reachability of a host.
    public func testReachability(host: String, port: Int) async -> Bool {
        let hostEndpoint = NWEndpoint.Host(host)
        let portEndpoint = NWEndpoint.Port(rawValue: UInt16(port))!

        return await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: hostEndpoint,
                port: portEndpoint,
                using: .tcp
            )

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.cancel()
                    continuation.resume(returning: true)
                case .failed:
                    connection.cancel()
                    continuation.resume(returning: false)
                default:
                    break
                }
            }

            connection.start(queue: .global())
        }
    }

    // MARK: - Helpers

    private func extractHost(from endpoint: NWEndpoint) -> String? {
        if case .service(let name, let type, let domain, _) = endpoint {
            return "\(name).\(type)\(domain)"
        }
        if case .hostPort(let host, _) = endpoint {
            return "\(host)"
        }
        return nil
    }
}

// MARK: - Network Service Model

public struct NetworkService: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let type: NetworkServiceType
    public let endpoint: NWEndpoint?
    public let host: String?
    public let port: Int

    public init(name: String, type: NetworkServiceType, endpoint: NWEndpoint?, host: String?, port: Int = 445) {
        self.name = name
        self.type = type
        self.endpoint = endpoint
        self.host = host
        self.port = port
    }

    public var connectionURL: URL? {
        guard let host else { return nil }
        switch type {
        case .smb:
            return URL(string: "smb://\(host):\(port)")
        case .webdav:
            return URL(string: "http://\(host):\(port)")
        case .ftp:
            return URL(string: "ftp://\(host):\(port)")
        case .upnp, .unknown:
            return nil
        }
    }

    public var displayType: String {
        type.displayName
    }

    public var iconName: String {
        switch type {
        case .smb: return "externaldrive.connected.to.line.below"
        case .webdav: return "network"
        case .ftp: return "arrow.up.arrow.down"
        case .upnp: return "antenna.radiowaves.left.and.right"
        case .unknown: return "questionmark.circle"
        }
    }
}

public enum NetworkServiceType: Sendable {
    case smb
    case webdav
    case ftp
    case upnp
    case unknown

    public static func from(bonjourType: String) -> NetworkServiceType {
        if bonjourType.contains("_smb") { return .smb }
        if bonjourType.contains("_http") { return .webdav }
        if bonjourType.contains("_ftp") { return .ftp }
        if bonjourType.contains("_upnp") { return .upnp }
        return .unknown
    }

    public var displayName: String {
        switch self {
        case .smb: return "SMB"
        case .webdav: return "WebDAV / HTTP"
        case .ftp: return "FTP"
        case .upnp: return "UPnP / DLNA"
        case .unknown: return "未知"
        }
    }
}

// MARK: - SMB File Browser

/// Lightweight SMB-compatible file lister.
/// For full SMB protocol support, integrate `AMSMB2` or use `libsmbclient` bridged from C.
public final class SMBFileBrowser: ObservableObject {
    @Published public private(set) var files: [RemoteFile] = []
    @Published public private(set) var currentPath: String = "/"
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var error: String?

    private var config: WebDAVSyncService.WebDAVConfig?

    public init() {}

    /// Connect with SMB credentials.
    /// For full SMB: integrate AMSMB2; for now, SMB shares often also expose WebDAV.
    public func connect(host: String, share: String, username: String, password: String) {
        let baseURL = "http://\(host)/\(share)"
        self.config = WebDAVSyncService.WebDAVConfig(
            serverURL: baseURL,
            username: username,
            password: password
        )
    }

    /// List files at a path.
    public func listFiles(path: String = "/") async throws {
        guard let config else { throw WebDAVError.notConfigured }
        isLoading = true
        defer { isLoading = false }
        currentPath = path

        let service = WebDAVSyncService.shared
        service.configure(config: config)
        let remoteFiles = try await service.listRemoteBooks()

        self.files = remoteFiles.map { rf in
            RemoteFile(
                name: rf.name,
                path: rf.path,
                isDirectory: !rf.name.contains("."),
                size: 0
            )
        }.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Download a file to local storage.
    public func downloadFile(remotePath: String) async throws -> URL {
        let data = try await WebDAVSyncService.shared.downloadBook(remoteName: remotePath)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent((remotePath as NSString).lastPathComponent)
        try data.write(to: tempURL)
        return tempURL
    }
}

public struct RemoteFile: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64
}
