import Foundation

// MARK: - Import Book Use Case

/// 导入图书用例：从文件 URL 解析图书并加入图书馆
public struct ImportBookUseCase: Sendable {
    private let parser: ArchiveParserProtocol
    private let repository: LibraryRepositoryProtocol
    
    public init(parser: ArchiveParserProtocol, repository: LibraryRepositoryProtocol) {
        self.parser = parser
        self.repository = repository
    }
    
    /// 执行导入
    /// - Parameter url: 档案文件或文件夹的 URL
    /// - Returns: 导入后的 Book 实例
    /// - Throws: ArchiveParserError 或持久化错误
    public func execute(url: URL) async throws -> Book {
        // 1. 安全检查：确保文件可访问
        guard FileManager.default.fileExists(atPath: url.path()) else {
            throw ArchiveParserError.fileNotFound(url)
        }
        
        // 2. 获取安全范围书签（用于沙盒外访问）
        let securedURL = try await acquireSecurityScope(for: url)
        defer { securedURL.stopAccessingSecurityScopedResource() }
        
        // 3. 解析档案
        let book = try await parser.parse(url: securedURL)
        
        // 4. 持久化到数据库
        try await repository.add(book)
        
        return book
    }
    
    /// 批量导入目录下的所有支持文件
    public func executeBatch(directoryURL: URL) async throws -> [Book] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        
        var importedBooks: [Book] = []
        var errors: [Error] = []
        
        // 并行导入（限制并发数以避免 I/O 瓶颈）
        await withTaskGroup(of: Result<Book, Error>.self) { group in
            for url in contents {
                let format = BookFormat.infer(from: url)
                guard format != .unknown else { continue }
                
                group.addTask {
                    do {
                        return try await self.execute(url: url)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            
            for await result in group {
                switch result {
                case .success(let book):
                    importedBooks.append(book)
                case .failure(let error):
                    errors.append(error)
                }
            }
        }
        
        if importedBooks.isEmpty && !errors.isEmpty {
            throw errors.first!
        }
        
        return importedBooks
    }
    
    private func acquireSecurityScope(for url: URL) async throws -> URL {
        let needsAccess = url.startAccessingSecurityScopedResource()
        if needsAccess {
            return url
        }
        // 如果是沙盒内文件，直接返回
        return url
    }
}

// MARK: - Open Book Use Case

/// 打开图书用例：初始化阅读引擎并记录阅读会话
public struct OpenBookUseCase: Sendable {
    private let engine: ReadingEngineProtocol
    private let repository: LibraryRepositoryProtocol
    
    public init(engine: ReadingEngineProtocol, repository: LibraryRepositoryProtocol) {
        self.engine = engine
        self.repository = repository
    }
    
    public func execute(book: Book) async throws -> ReadingSession {
        // 1. 打开阅读引擎
        try await engine.open(book: book)
        
        // 2. 加载阅读进度
        let progress = try await repository.fetchProgress(for: book.id)
        
        // 3. 恢复上次阅读位置
        let startPage = progress?.currentPage ?? 0
        let page = try await engine.goToPage(startPage)
        
        // 4. 记录会话开始
        let session = ReadingSession(
            book: book,
            startPage: startPage,
            progress: progress,
            firstPage: page
        )
        
        return session
    }
}

/// 阅读会话：封装打开一本书后的状态
public struct ReadingSession: Sendable {
    public let book: Book
    public let startPage: Int
    public let progress: ReadingProgress?
    public let firstPage: PageData
}

// MARK: - Scan Library Use Case

/// 扫描图书馆文件夹，自动发现新书
public struct ScanLibraryUseCase: Sendable {
    private let repository: LibraryRepositoryProtocol
    
    public init(repository: LibraryRepositoryProtocol) {
        self.repository = repository
    }
    
    /// 扫描指定目录及其子目录，返回新发现的文件 URL 列表
    public func execute(rootURL: URL) async throws -> [URL] {
        let existingBooks = try await repository.fetchAll(sortBy: .recentlyAdded)
        let existingPaths = Set(existingBooks.map { $0.sourceURL.path() })
        
        var newFiles: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        
        let supportedExtensions = Set(BookFormat.allCases.compactMap { format -> String? in
            switch format {
            case .cbz: return "cbz"
            case .cbr: return "cbr"
            case .zip: return "zip"
            case .rar: return "rar"
            case .sevenZip: return "7z"
            case .pdf: return "pdf"
            case .epub: return "epub"
            case .txt: return "txt"
            case .markdown: return "md"
            case .html: return "html"
            case .mobi: return "mobi"
            case .azw3: return "azw3"
            default: return nil
            }
        })
        
        while let fileURL = enumerator?.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }
            guard !existingPaths.contains(fileURL.path()) else { continue }
            newFiles.append(fileURL)
        }
        
        return newFiles
    }
}
