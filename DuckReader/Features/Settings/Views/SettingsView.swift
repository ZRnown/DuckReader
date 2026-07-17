import SwiftUI
import Observation

// MARK: - Settings ViewModel

@MainActor
@Observable
public final class SettingsViewModel: Sendable {
    // Appearance
    public var accentColor: AccentColorOption = .blue
    public var appIcon: AppIconOption = .default
    public var libraryGridColumns: Int = 3
    
    // Reading defaults
    public var defaultReadingMode: ComicReadingMode = .singlePage
    public var defaultReadingDirection: ReadingDirection = .rightToLeft
    public var defaultNovelFontSize: CGFloat = 18
    public var defaultNovelTheme: NovelTheme = .paper
    public var enableAutoEnhance: Bool = false
    public var enableAutoCropBorders: Bool = true
    
    // Privacy & Security
    public var isPrivacyLockEnabled: Bool = false
    public var privacyLockTimeout: PrivacyLockTimeout = .immediate
    
    // Sync
    public var isCloudSyncEnabled: Bool = false
    public var syncProvider: SyncProvider = .icloud
    
    // E-Ink
    public var eInkEnabled: Bool = false
    public var eInkPreset: EInkOptimizer.Preset = .kindleBasic
    public var eInkOptions = EInkOptimizer.Options.safeDefaults
    
    // Calibre
    public var calibreEnabled: Bool = false
    public let calibreIntegration = CalibreIntegration()
    public var discoveredServers: [CalibreIntegration.CalibreServer] {
        calibreIntegration.discoveredServers
    }
    public var calibreSyncState: CalibreIntegration.CalibreSyncState {
        calibreIntegration.syncState
    }
    
    // Cache
    public var cacheSize: String = "0 MB"
    public var isClearingCache: Bool = false
    
    // About
    public var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    public var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    // MARK: - Actions
    
    public func toggleCalibreDiscovery() {
        if calibreEnabled {
            calibreIntegration.startDiscovery()
        } else {
            calibreIntegration.stopDiscovery()
        }
    }
    
    public func connectToCalibre(_ server: CalibreIntegration.CalibreServer) async {
        do {
            try await calibreIntegration.connect(to: server)
        } catch {
            print("[Calibre] Connect failed: \(error)")
        }
    }
    
    public func syncCalibreMetadata() async {
        do {
            try await calibreIntegration.syncAllMetadata()
        } catch {
            print("[Calibre] Sync failed: \(error)")
        }
    }
    
    public func clearCache() async {
        isClearingCache = true
        defer { isClearingCache = false }
        
        let cacheDir = FileManager.default.temporaryDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: nil
        ) {
            for url in contents where url.lastPathComponent.hasPrefix("DuckReader_") {
                try? FileManager.default.removeItem(at: url)
            }
        }
        
        cacheSize = "0 MB"
    }
    
    public func calculateCacheSize() async {
        let cacheDir = FileManager.default.temporaryDirectory
        let prefix = "DuckReader_"
        var total: Int64 = 0
        
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for url in contents where url.lastPathComponent.hasPrefix(prefix) {
                total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            }
        }
        
        cacheSize = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}

// MARK: - Enums

public enum AccentColorOption: String, CaseIterable, Sendable {
    case blue
    case purple
    case green
    case orange
    case pink
    case teal
    
    public var displayName: String {
        switch self {
        case .blue: String(localized: "color.blue")
        case .purple: String(localized: "color.purple")
        case .green: String(localized: "color.green")
        case .orange: String(localized: "color.orange")
        case .pink: String(localized: "color.pink")
        case .teal: String(localized: "color.teal")
        }
    }
    
    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .teal: .teal
        }
    }
}

public enum AppIconOption: String, CaseIterable, Sendable {
    case `default`
    case dark
    case classic
    case minimal
    
    public var displayName: String {
        switch self {
        case .default: String(localized: "icon.default")
        case .dark: String(localized: "icon.dark")
        case .classic: String(localized: "icon.classic")
        case .minimal: String(localized: "icon.minimal")
        }
    }
}

public enum PrivacyLockTimeout: String, CaseIterable, Sendable {
    case immediate
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    
    public var displayName: String {
        switch self {
        case .immediate: String(localized: "privacy.lockImmediate")
        case .oneMinute: String(localized: "privacy.lock1Min")
        case .fiveMinutes: String(localized: "privacy.lock5Min")
        case .fifteenMinutes: String(localized: "privacy.lock15Min")
        }
    }
    
    var seconds: TimeInterval {
        switch self {
        case .immediate: 0
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        }
    }
}

public enum SyncProvider: String, CaseIterable, Sendable {
    case icloud
    case webdav
    case smb
    
    public var displayName: String {
        switch self {
        case .icloud: "iCloud"
        case .webdav: "WebDAV"
        case .smb: String(localized: "sync.smbNAS")
        }
    }
}

// MARK: - Settings View

public struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                // MARK: Appearance
                Section(String(localized: "settings.appearance")) {
                    Picker(String(localized: "settings.accentColor"), selection: $viewModel.accentColor) {
                        ForEach(AccentColorOption.allCases, id: \.self) { option in
                            HStack {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 16, height: 16)
                                Text(option.displayName)
                            }
                            .tag(option)
                        }
                    }
                    
                    Picker(String(localized: "settings.appIcon"), selection: $viewModel.appIcon) {
                        ForEach(AppIconOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }
                
                // MARK: Reading Defaults
                Section(String(localized: "settings.defaultReading")) {
                    Picker(String(localized: "settings.comicMode"), selection: $viewModel.defaultReadingMode) {
                        ForEach(ComicReadingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    
                    Picker(L10n.readerDirection, selection: $viewModel.defaultReadingDirection) {
                        ForEach(ReadingDirection.allCases, id: \.self) { dir in
                            Text(dir.displayName).tag(dir)
                        }
                    }
                    
                    Toggle(String(localized: "settings.autoEnhance"), isOn: $viewModel.enableAutoEnhance)
                    Toggle(String(localized: "settings.autoCropBorders"), isOn: $viewModel.enableAutoCropBorders)
                }
                
                // MARK: E-Ink Optimization
                Section {
                    Toggle("E-Ink Optimization", isOn: $viewModel.eInkEnabled)
                    
                    if viewModel.eInkEnabled {
                        Picker("Device Preset", selection: $viewModel.eInkPreset) {
                            ForEach(EInkOptimizer.Preset.allCases, id: \.rawValue) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        
                        Picker("Dithering", selection: Binding(
                            get: { viewModel.eInkOptions.dithering },
                            set: { viewModel.eInkOptions.dithering = $0 }
                        )) {
                            ForEach(EInkOptimizer.DitherMethod.allCases, id: \.rawValue) { method in
                                Text(method.rawValue.capitalized).tag(method)
                            }
                        }
                    }
                }
                
                // MARK: Privacy
                Section(L10n.settingsPrivacy) {
                    Toggle(String(localized: "settings.privacyLockFaceID"), isOn: $viewModel.isPrivacyLockEnabled)
                    
                    if viewModel.isPrivacyLockEnabled {
                        Picker(String(localized: "settings.lockTimeout"), selection: $viewModel.privacyLockTimeout) {
                            ForEach(PrivacyLockTimeout.allCases, id: \.self) { timeout in
                                Text(timeout.displayName).tag(timeout)
                            }
                        }
                    }
                }
                
                // MARK: Sync
                Section(L10n.settingsCloudSync) {
                    Toggle(String(localized: "settings.enableCloudSync"), isOn: $viewModel.isCloudSyncEnabled)
                    
                    if viewModel.isCloudSyncEnabled {
                        Picker(String(localized: "settings.syncMethod"), selection: $viewModel.syncProvider) {
                            ForEach(SyncProvider.allCases, id: \.self) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                    }
                }
                
                // MARK: Calibre
                Section {
                    Toggle("Calibre Integration", isOn: $viewModel.calibreEnabled)
                        .onChange(of: viewModel.calibreEnabled) { _, _ in
                            viewModel.toggleCalibreDiscovery()
                        }
                    
                    if viewModel.calibreEnabled && !viewModel.discoveredServers.isEmpty {
                        ForEach(viewModel.discoveredServers) { server in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.name)
                                        .font(.subheadline)
                                    Text("\(server.host):\(server.port)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Connect") {
                                    Task { await viewModel.connectToCalibre(server) }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    
                    if viewModel.calibreSyncState != .idle {
                        HStack {
                            Text(viewModel.calibreSyncState.rawValue.capitalized)
                                .foregroundColor(viewModel.calibreSyncState == .connected ? .green : .secondary)
                            Spacer()
                            if viewModel.calibreSyncState == .connected {
                                Button("Sync Metadata") {
                                    Task { await viewModel.syncCalibreMetadata() }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                } header: {
                    Text("Calibre")
                }
                
                // MARK: Cache
                Section(String(localized: "settings.cache")) {
                    HStack {
                        Text(L10n.settingsCacheSize)
                        Spacer()
                        Text(viewModel.cacheSize)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(role: .destructive) {
                        Task { await viewModel.clearCache() }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isClearingCache {
                                ProgressView()
                            } else {
                                Text(L10n.settingsClearCache)
                            }
                            Spacer()
                        }
                    }
                }
                
                // MARK: About
                Section(L10n.settingsAbout) {
                    HStack {
                        Text(L10n.settingsVersion)
                        Spacer()
                        Text("\(viewModel.appVersion) (\(viewModel.buildNumber))")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(String(localized: "settings.privacyPolicy"), destination: URL(string: "https://duckreader.app/privacy")!)
                    Link(String(localized: "settings.userAgreement"), destination: URL(string: "https://duckreader.app/terms")!)
                    Link(String(localized: "settings.licenses"), destination: URL(string: "https://duckreader.app/licenses")!)
                }
            }
            .navigationTitle(L10n.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.done) { dismiss() }
                }
            }
            .task {
                await viewModel.calculateCacheSize()
            }
        }
    }
}

#Preview {
    SettingsView()
}
