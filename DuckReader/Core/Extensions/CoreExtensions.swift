import Foundation

// MARK: - FileManager Extensions

extension FileManager {
    /// 安全的文件复制（带错误处理和 bookmarks）
    func safeCopyItem(at srcURL: URL, to dstURL: URL) throws {
        do {
            if fileExists(atPath: dstURL.path()) {
                try removeItem(at: dstURL)
            }
            try copyItem(at: srcURL, to: dstURL)
        } catch {
            throw FileError.copyFailed(source: srcURL, destination: dstURL, underlying: error)
        }
    }
    
    /// 递归获取目录下所有文件的 URL
    func allFiles(in directory: URL, extensions: Set<String>? = nil) -> [URL] {
        guard let enumerator = enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if let exts = extensions {
                guard exts.contains(fileURL.pathExtension.lowercased()) else { continue }
            }
            files.append(fileURL)
        }
        return files
    }
    
    /// 获取文件大小（人性化字符串）
    func humanReadableSize(of url: URL) -> String {
        guard let attrs = try? attributesOfItem(atPath: url.path()),
              let size = attrs[.size] as? Int64 else {
            return "未知"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    /// App 的文档目录
    static var documentsDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    /// App 的缓存目录
    static var cachesDirectory: URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    /// DuckReader 的专用目录
    static var duckReaderDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("DuckReader", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

enum FileError: LocalizedError {
    case copyFailed(source: URL, destination: URL, underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .copyFailed(let src, let dst, let error):
            "复制失败: \(src.lastPathComponent) -> \(dst.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

// MARK: - String Extensions

extension String {
    /// 清理文件名中的非法字符
    var sanitizedFilename: String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
    }
    
    /// 截取指定长度（用于 UI 显示）
    func truncated(_ maxLength: Int, suffix: String = "…") -> String {
        count > maxLength ? String(prefix(maxLength)) + suffix : self
    }
    
    /// 是否为有效的 URL
    var isValidURL: Bool {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return false
        }
        let matches = detector.matches(in: self, range: NSRange(startIndex..., in: self))
        return matches.count == 1 && matches[0].url != nil
    }
}

// MARK: - URL Extensions

extension URL {
    /// 安全地从 URL 读取 Data（带 Security Scope 管理）
    func safeReadData() throws -> Data {
        let needsAccess = startAccessingSecurityScopedResource()
        defer { if needsAccess { stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: self)
    }
    
    /// 是否是目录
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
    
    /// 文件大小（bytes）
    var fileSize: Int64 {
        (try? resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? 0
    }
}

// MARK: - Date Extensions

extension Date {
    /// 相对时间描述（"刚刚"、"5分钟前"、"昨天"）
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    /// 格式化日期字符串
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}

// MARK: - Collection Extensions

extension Collection {
    /// 安全的下标访问
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Task Extensions

extension Task where Success == Never, Failure == Never {
    /// 非阻塞延迟（用于 UI 防抖等）
    static func sleep(seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
