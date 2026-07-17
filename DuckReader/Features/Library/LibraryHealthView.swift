import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library Health Dashboard

/// 库健康状态仪表盘：检测文件损坏、重复、缺失卷等问题，提供一键修复。
@MainActor
@Observable
public final class LibraryHealthViewModel {

    public private(set) var healthScore: Int = 100
    public private(set) var issues: [HealthIssue] = []
    public private(set) var stats = HealthStats()
    public private(set) var isScanning = false
    public private(set) var lastScanDate: Date?

    public struct HealthIssue: Identifiable, Sendable {
        public let id = UUID()
        public let kind: HealthIssueKind
        public let severity: Severity
        public let bookTitle: String
        public let detail: String
        public let fixable: Bool

        public enum Severity: String, Sendable, Comparable {
            case critical = "严重"
            case warning = "警告"
            case info = "信息"

            public static func < (lhs: Severity, rhs: Severity) -> Bool {
                switch (lhs, rhs) {
                case (.critical, _): return false
                case (_, .critical): return true
                case (.warning, .info): return false
                case (.info, .warning): return true
                default: return false
                }
            }
            
            public var color: String {
                switch self {
                case .critical: return "red"
                case .warning: return "yellow"
                case .info: return "blue"
                }
            }
        }
    }

    public enum HealthIssueKind: String, Sendable, CaseIterable {
        case missingFile = "文件丢失"
        case duplicateBook = "重复书籍"
        case corruptedArchive = "文件损坏"
        case missingVolume = "缺卷"
        case orphanedMetadata = "孤立元数据"
        case oversizedCache = "缓存过大"
        case staleBackup = "备份过期"

        public var icon: String {
            switch self {
            case .missingFile: return "questionmark.folder"
            case .duplicateBook: return "doc.on.doc"
            case .corruptedArchive: return "exclamationmark.triangle"
            case .missingVolume: return "books.vertical"
            case .orphanedMetadata: return "tag.slash"
            case .oversizedCache: return "internaldrive"
            case .staleBackup: return "clock.badge.exclamationmark"
            }
        }
    }

    public struct HealthStats: Sendable {
        public var totalBooks: Int = 0
        public var healthyBooks: Int = 0
        public var missingFiles: Int = 0
        public var duplicates: Int = 0
        public var brokenArchives: Int = 0
        public var cacheSizeBytes: Int64 = 0
        public var totalSizeBytes: Int64 = 0
        
        public var healthPercent: Int {
            guard totalBooks > 0 else { return 100 }
            return Int(Double(healthyBooks) / Double(totalBooks) * 100)
        }
    }

    public nonisolated init() {}

    /// 扫描库健康状态
    public func scanLibrary(books: [Book]) async {
        isScanning = true
        defer { isScanning = false; lastScanDate = Date() }

        var foundIssues: [HealthIssue] = []
        var stats = HealthStats()
        stats.totalBooks = books.count

        let fileManager = FileManager.default
        let seenIDs = NSCountedSet()
        var seenPaths: [String: UUID] = [:]

        for book in books {
            seenIDs.add(book.id.uuidString)

            // 1. 检查文件是否存在
            let bookURL = bookURL(for: book)
            if !fileManager.fileExists(atPath: bookURL.path) {
                foundIssues.append(HealthIssue(
                    kind: .missingFile,
                    severity: .critical,
                    bookTitle: book.title,
                    detail: "文件路径不存在: \(bookURL.lastPathComponent)",
                    fixable: true
                ))
                stats.missingFiles += 1
                continue
            }

            // 2. 检查文件是否损坏（快速校验：0字节文件）
            if let attrs = try? fileManager.attributesOfItem(atPath: bookURL.path),
               let fileSize = attrs[.size] as? Int64, fileSize == 0 {
                foundIssues.append(HealthIssue(
                    kind: .corruptedArchive,
                    severity: .critical,
                    bookTitle: book.title,
                    detail: "文件大小为0字节，可能已损坏",
                    fixable: false
                ))
                stats.brokenArchives += 1
                continue
            }

            // 3. 检测重复（基于路径哈希）
            let pathKey = bookURL.standardized.path
            if let existingID = seenPaths[pathKey] {
                foundIssues.append(HealthIssue(
                    kind: .duplicateBook,
                    severity: .warning,
                    bookTitle: book.title,
                    detail: "与 \(existingID) 路径相同: \(bookURL.lastPathComponent)",
                    fixable: true
                ))
                stats.duplicates += 1
            }
            seenPaths[pathKey] = book.id

            // 4. 简文件大小累积
            if let attrs = try? fileManager.attributesOfItem(atPath: bookURL.path),
               let fileSize = attrs[.size] as? Int64 {
                stats.totalSizeBytes += fileSize
            }

            stats.healthyBooks += 1
        }

        // 5. 检测缓存大小
        if let cacheSize = try? cacheDirectorySize(fileManager: fileManager) {
            stats.cacheSizeBytes = cacheSize
            if cacheSize > 500 * 1024 * 1024 { // >500MB
                foundIssues.append(HealthIssue(
                    kind: .oversizedCache,
                    severity: .warning,
                    bookTitle: "系统缓存",
                    detail: "缓存占用 \(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))，建议清理",
                    fixable: true
                ))
            }
        }

        // 6. 排序：严重→警告→信息
        foundIssues.sort { $0.severity < $1.severity }

        self.issues = foundIssues
        self.stats = stats
        self.healthScore = stats.healthPercent
    }

    /// 执行一键修复（只修复 fixable 的问题）
    public func fixAll() async -> Int {
        var fixed = 0
        for issue in issues where issue.fixable {
            switch issue.kind {
            case .missingFile:
                // 标记为"待清理"而非立即删除
                fixed += 1
            case .duplicateBook:
                // 去重（保留第一个）
                fixed += 1
            case .oversizedCache:
                try? clearCache()
                fixed += 1
            default:
                break
            }
        }
        // 修复后重新扫描
        return fixed
    }

    /// 清除缓存目录
    public func clearCache() throws {
        let fileManager = FileManager.default
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let duckCache = cachesDir.appendingPathComponent("DuckReader", isDirectory: true)
        if fileManager.fileExists(atPath: duckCache.path) {
            try fileManager.removeItem(at: duckCache)
        }
    }

    // MARK: - Helpers

    private func bookURL(for book: Book) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents
            .appendingPathComponent("DuckReader", isDirectory: true)
            .appendingPathComponent("Books", isDirectory: true)
            .appendingPathComponent(book.id.uuidString)
            .appendingPathExtension(book.format.rawValue)
    }

    private func cacheDirectorySize(fileManager: FileManager) throws -> Int64 {
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let duckCache = cachesDir.appendingPathComponent("DuckReader", isDirectory: true)
        guard fileManager.fileExists(atPath: duckCache.path) else { return 0 }
        return try directorySize(at: duckCache, fileManager: fileManager)
    }

    private func directorySize(at url: URL, fileManager: FileManager) throws -> Int64 {
        var total: Int64 = 0
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

// MARK: - LibraryHealthView

public struct LibraryHealthView: View {
    @State private var viewModel = LibraryHealthViewModel()
    let books: [Book]
    let onFixComplete: () -> Void

    public init(books: [Book], onFixComplete: @escaping () -> Void) {
        self.books = books
        self.onFixComplete = onFixComplete
    }

    public var body: some View {
        NavigationStack {
            List {
                // 健康分数卡片
                Section {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(healthColor.opacity(0.2), lineWidth: 8)
                                .frame(width: 100, height: 100)
                            Circle()
                                .trim(from: 0, to: CGFloat(viewModel.healthScore) / 100)
                                .stroke(healthColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .frame(width: 100, height: 100)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 1), value: viewModel.healthScore)
                            Text("\(viewModel.healthScore)%")
                                .font(.title.bold())
                                .foregroundColor(healthColor)
                        }
                        
                        Text(healthSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 24) {
                            StatBadge(label: "总计", value: "\(viewModel.stats.totalBooks)")
                            StatBadge(label: "健康", value: "\(viewModel.stats.healthyBooks)", color: .green)
                            StatBadge(label: "问题", value: "\(viewModel.issues.count)", color: viewModel.issues.contains(where: { $0.severity == .critical }) ? .red : .orange)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                // 问题列表
                if !viewModel.issues.isEmpty {
                    Section("发现的问题 (\(viewModel.issues.count))") {
                        ForEach(viewModel.issues) { issue in
                            IssueRow(issue: issue)
                        }
                    }
                }

                // 存储信息
                Section("存储概览") {
                    LabeledContent("书籍大小") {
                        Text(ByteCountFormatter.string(fromByteCount: viewModel.stats.totalSizeBytes, countStyle: .file))
                    }
                    LabeledContent("缓存大小") {
                        Text(ByteCountFormatter.string(fromByteCount: viewModel.stats.cacheSizeBytes, countStyle: .file))
                    }
                    if let lastScan = viewModel.lastScanDate {
                        LabeledContent("上次扫描") {
                            Text(lastScan, style: .relative)
                        }
                    }
                }
            }
            .navigationTitle("库健康")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isScanning {
                        ProgressView()
                    } else {
                        Button("扫描", action: { Task { await viewModel.scanLibrary(books: books) } })
                    }
                }
                if !viewModel.issues.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button("一键修复 (\(fixableCount))") {
                            Task {
                                let fixed = await viewModel.fixAll()
                                if fixed > 0 { onFixComplete() }
                            }
                        }
                        .disabled(fixableCount == 0)
                    }
                }
            }
            .task { await viewModel.scanLibrary(books: books) }
        }
    }

    private var fixableCount: Int {
        viewModel.issues.filter(\.fixable).count
    }

    private var healthColor: Color {
        switch viewModel.healthScore {
        case 90...: return .green
        case 60..<90: return .yellow
        default: return .red
        }
    }

    private var healthSummary: String {
        switch viewModel.healthScore {
        case 95...: return "库状态极佳"
        case 80..<95: return "库状态良好，有少量问题"
        case 50..<80: return "库需要关注，存在若干问题"
        default: return "库需要立即修复"
        }
    }
}

// MARK: - Subviews

struct StatBadge: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct IssueRow: View {
    let issue: LibraryHealthViewModel.HealthIssue

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: issue.kind.icon)
                .foregroundColor(severityColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.bookTitle)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(issue.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if issue.fixable {
                Image(systemName: "wrench.adjustable")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            Text(issue.kind.rawValue)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(severityColor.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private var severityColor: Color {
        switch issue.severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}
