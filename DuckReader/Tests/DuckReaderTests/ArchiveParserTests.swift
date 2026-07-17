import Testing
import Foundation
@testable import DuckReaderCore

// MARK: - Format Detector Tests

struct FormatDetectorTests {
    
    @Test("检测 CBZ 格式 (ZIP-based)")
    func detectCBZFormat() async throws {
        // Create a test CBZ file (ZIP with images)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckReader_Test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create a simple ZIP with a .cbz extension
        let testFile = tempDir.appendingPathComponent("test.cbz")
        
        // Write minimal ZIP data (PK header)
        let zipHeader = Data([0x50, 0x4B, 0x03, 0x04])
        try zipHeader.write(to: testFile)
        
        let format = await FormatDetector.detect(url: testFile)
        #expect(format == .cbz, "应检测为 CBZ 格式")
    }
    
    @Test("检测 RAR 格式")
    func detectRARFormat() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckReader_Test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let testFile = tempDir.appendingPathComponent("test.cbr")
        let rarHeader = Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00])
        try rarHeader.write(to: testFile)
        
        let format = await FormatDetector.detect(url: testFile)
        #expect(format == .cbr, "应检测为 CBR 格式")
    }
    
    @Test("检测 PDF 格式")
    func detectPDFFormat() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckReader_Test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let testFile = tempDir.appendingPathComponent("test.pdf")
        let pdfHeader = Data([0x25, 0x50, 0x44, 0x46])
        try pdfHeader.write(to: testFile)
        
        let format = await FormatDetector.detect(url: testFile)
        #expect(format == .pdf, "应检测为 PDF 格式")
    }
    
    @Test("检测 7z 格式")
    func detect7zFormat() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckReader_Test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let testFile = tempDir.appendingPathComponent("test.7z")
        let header7z = Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])
        try header7z.write(to: testFile)
        
        let format = await FormatDetector.detect(url: testFile)
        #expect(format == .sevenZip, "应检测为 7z 格式")
    }
    
    @Test("未知扩展名回退到魔数检测")
    func unknownExtensionFallback() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckReader_Test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // File with .dat extension but ZIP magic bytes
        let testFile = tempDir.appendingPathComponent("test.dat")
        let zipHeader = Data([0x50, 0x4B, 0x03, 0x04])
        try zipHeader.write(to: testFile)
        
        let format = await FormatDetector.detect(url: testFile)
        #expect(format == .cbz || format == .zip, "应通过魔数检测为 ZIP 类型")
    }
    
    @Test("MOBI 格式检测 (BOOKMOBI 签名)")
    func detectMOBIFormat() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckReader_Test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let testFile = tempDir.appendingPathComponent("test.mobi")
        // Create data with BOOKMOBI at offset 60
        var data = Data(repeating: 0, count: 68)
        let mobiSignature = "BOOKMOBI".data(using: .ascii)!
        data.replaceSubrange(60..<68, with: mobiSignature)
        try data.write(to: testFile)
        
        let format = await FormatDetector.detect(url: testFile)
        #expect(format == .mobi, "应检测为 MOBI 格式")
    }
}

// MARK: - Book Model Tests

struct BookModelTests {
    
    @Test("Book 进度百分比计算")
    func progressPercentageCalculation() {
        let progress = ReadingProgress(currentPage: 50)
        let book = Book(
            title: "Test",
            sourceURL: URL(fileURLWithPath: "/test"),
            format: .cbz,
            contentType: .comic,
            totalPages: 100,
            progress: progress
        )
        
        #expect(book.progressPercentage == 0.5, "50/100 应为 50%")
    }
    
    @Test("Book 未读状态检测")
    func unreadDetection() {
        let bookNoProgress = Book(
            title: "Test",
            sourceURL: URL(fileURLWithPath: "/test"),
            format: .cbz,
            contentType: .comic
        )
        #expect(bookNoProgress.isUnread, "无进度应视为未读")
        
        let bookWithProgress = Book(
            title: "Test",
            sourceURL: URL(fileURLWithPath: "/test"),
            format: .cbz,
            contentType: .comic,
            totalPages: 100,
            progress: ReadingProgress(currentPage: 50)
        )
        #expect(!bookWithProgress.isUnread, "有进度不应视为未读")
    }
    
    @Test("Book 已完成状态检测")
    func finishedDetection() {
        let unfinished = Book(
            title: "Test",
            sourceURL: URL(fileURLWithPath: "/test"),
            format: .cbz,
            contentType: .comic,
            totalPages: 100,
            progress: ReadingProgress(currentPage: 50)
        )
        #expect(!unfinished.isFinished, "读到一半不应算完成")
        
        let finished = Book(
            title: "Test",
            sourceURL: URL(fileURLWithPath: "/test"),
            format: .cbz,
            contentType: .comic,
            totalPages: 100,
            progress: ReadingProgress(currentPage: 99)
        )
        #expect(finished.isFinished, "读到最后一页应算完成")
    }
    
    @Test("BookFormat 从扩展名推断")
    func formatInference() {
        #expect(BookFormat.infer(from: URL(fileURLWithPath: "comic.cbz")) == .cbz)
        #expect(BookFormat.infer(from: URL(fileURLWithPath: "comic.cbr")) == .cbr)
        #expect(BookFormat.infer(from: URL(fileURLWithPath: "book.epub")) == .epub)
        #expect(BookFormat.infer(from: URL(fileURLWithPath: "novel.txt")) == .txt)
        #expect(BookFormat.infer(from: URL(fileURLWithPath: "doc.docx")) == .unknown)
    }
}

// MARK: - Archive Parser Tests

struct ArchiveParserTests {
    
    @Test("ArchiveParser 列出有效 ZIP 中的图片条目")
    func listZIPEntries() async throws {
        // Create a temp CBZ (ZIP with image files)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckReader_Test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let parser = ArchiveParser()
        let testURL = tempDir.appendingPathComponent("test.cbz")
        
        // Create a real ZIP with test image file entries
        // For unit test, we create a minimal valid ZIP
        try await createTestZIP(at: testURL, entries: [
            "page_001.jpg",
            "page_002.png",
            "page_003.jpg",
            "readme.txt",  // non-image, should be filtered
        ])
        
        let entries = try await parser.listEntries(at: testURL)
        #expect(entries.count == 3, "应过滤掉非图片文件")
        #expect(entries.contains("page_001.jpg"))
        #expect(entries.contains("page_002.png"))
        #expect(!entries.contains("readme.txt"), "非图片文件应被排除")
    }
    
    @Test("ArchiveParser 正确处理不存在的文件")
    func fileNotFoundError() async {
        let parser = ArchiveParser()
        let nonExistent = URL(fileURLWithPath: "/nonexistent/file.cbz")
        
        do {
            _ = try await parser.parse(url: nonExistent)
            #expect(Bool(false), "应抛出错误")
        } catch let error as ArchiveParserError {
            if case .fileNotFound = error {
                // Expected
            } else {
                #expect(Bool(false), "应为 fileNotFound 错误")
            }
        } catch {
            // Also acceptable if FileManager throws
        }
    }
    
    @Test("ArchiveParser 解析后返回正确的 Book 元数据")
    func parseMetadata() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckReader_Test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let parser = ArchiveParser()
        let testURL = tempDir.appendingPathComponent("MyManga.cbz")
        
        try await createTestZIP(at: testURL, entries: [
            "01.jpg", "02.jpg", "03.jpg", "04.jpg", "05.jpg"
        ])
        
        let book = try await parser.parse(url: testURL)
        
        #expect(book.title == "MyManga", "书名应从文件名提取")
        #expect(book.format == .cbz)
        #expect(book.contentType == .comic)
        #expect(book.totalPages == 5)
    }
    
    // MARK: - Helpers
    
    /// 创建包含指定条目名的测试 ZIP 文件
    private func createTestZIP(at url: URL, entries: [String]) async throws {
        // Use system zip command to create a test archive
        let tempWorkDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckReader_Test_Work_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempWorkDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempWorkDir) }
        
        // Create dummy files
        for entry in entries {
            let fileURL = tempWorkDir.appendingPathComponent(entry)
            // Create parent directories if needed
            let parent = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            // Write minimal content
            try "test".data(using: .utf8)!.write(to: fileURL)
        }
        
        // Zip the directory
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-j", url.path] + entries.map { tempWorkDir.appendingPathComponent($0).path }
        process.currentDirectoryURL = tempWorkDir
        
        try process.run()
        process.waitUntilExit()
        
        // If zip failed, create a minimal valid ZIP manually
        if process.terminationStatus != 0 {
            try await createMinimalZIPManual(at: url, entries: entries)
        }
    }
    
    /// Fallback: create minimal ZIP in pure Swift (for CI without `zip` binary)
    private func createMinimalZIPManual(at url: URL, entries: [String]) async throws {
        // A minimal ZIP file structure (can be expanded for proper CI support)
        var data = Data()
        // Local file header signature
        data.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])
        // ... minimal fields (for testing, the signature alone may be sufficient
        // for FormatDetector but not for actual ZIPFoundation extraction)
        
        // For proper testing, install zip binary or use ZIPFoundation to create archives
        // This is a known limitation of unit test environment
        try data.write(to: url)
    }
}

// MARK: - Library Repository Tests

struct LibraryRepositoryTests {
    
    @Test("添加并查询 Book")
    func addAndFetchBook() async throws {
        let stack = try SwiftDataStack(isStoredInMemoryOnly: true)
        let repository = LibraryRepository(modelContext: stack.mainContext)
        
        let book = Book(
            title: "测试漫画",
            author: "测试作者",
            sourceURL: URL(fileURLWithPath: "/test/test.cbz"),
            format: .cbz,
            contentType: .comic,
            totalPages: 42
        )
        
        try await repository.add(book)
        
        let books = try await repository.fetchAll(sortBy: .title)
        #expect(books.count == 1)
        #expect(books[0].title == "测试漫画")
        #expect(books[0].author == "测试作者")
        #expect(books[0].totalPages == 42)
    }
    
    @Test("删除 Book")
    func deleteBook() async throws {
        let stack = try SwiftDataStack(isStoredInMemoryOnly: true)
        let repository = LibraryRepository(modelContext: stack.mainContext)
        
        let book = Book(
            title: "待删除",
            sourceURL: URL(fileURLWithPath: "/test/delete.cbz"),
            format: .cbz,
            contentType: .comic
        )
        
        try await repository.add(book)
        var books = try await repository.fetchAll()
        #expect(books.count == 1)
        
        try await repository.remove(book)
        books = try await repository.fetchAll()
        #expect(books.isEmpty)
    }
    
    @Test("搜索图书")
    func searchBooks() async throws {
        let stack = try SwiftDataStack(isStoredInMemoryOnly: true)
        let repository = LibraryRepository(modelContext: stack.mainContext)
        
        let book1 = Book(title: "海贼王", sourceURL: URL(fileURLWithPath: "/one_piece.cbz"), format: .cbz, contentType: .comic)
        let book2 = Book(title: "火影忍者", sourceURL: URL(fileURLWithPath: "/naruto.cbz"), format: .cbz, contentType: .comic)
        let book3 = Book(title: "轻小说入门", sourceURL: URL(fileURLWithPath: "/novel.epub"), format: .epub, contentType: .novel)
        
        try await repository.add(book1)
        try await repository.add(book2)
        try await repository.add(book3)
        
        let results = try await repository.search(query: "海贼")
        #expect(results.count == 1)
        #expect(results[0].title == "海贼王")
        
        let allResults = try await repository.search(query: "")
        #expect(allResults.count == 3)
    }
    
    @Test("保存和恢复阅读进度")
    func saveAndFetchProgress() async throws {
        let stack = try SwiftDataStack(isStoredInMemoryOnly: true)
        let repository = LibraryRepository(modelContext: stack.mainContext)
        
        let bookID = UUID()
        let book = Book(
            id: bookID,
            title: "进度测试",
            sourceURL: URL(fileURLWithPath: "/progress.cbz"),
            format: .cbz,
            contentType: .comic,
            totalPages: 100
        )
        try await repository.add(book)
        
        let progress = ReadingProgress(
            currentPage: 42,
            currentChapter: 3,
            chapterTitle: "第3话",
            lastUpdated: Date(),
            completionPercentage: 0.42
        )
        try await repository.saveProgress(progress, for: bookID)
        
        let fetched = try await repository.fetchProgress(for: bookID)
        #expect(fetched != nil)
        #expect(fetched?.currentPage == 42)
        #expect(fetched?.currentChapter == 3)
        #expect(fetched?.completionPercentage == 0.42)
    }
    
    @Test("书签 CRUD")
    func bookmarkCRUD() async throws {
        let stack = try SwiftDataStack(isStoredInMemoryOnly: true)
        let repository = LibraryRepository(modelContext: stack.mainContext)
        
        let bookID = UUID()
        let bookmark = Bookmark(
            bookID: bookID,
            page: 10,
            chapter: 1,
            title: "精彩片段",
            note: "这里的打斗很好看"
        )
        
        try await repository.saveBookmark(bookmark)
        
        let bookmarks = try await repository.fetchBookmarks(for: bookID)
        #expect(bookmarks.count == 1)
        #expect(bookmarks[0].title == "精彩片段")
        #expect(bookmarks[0].note == "这里的打斗很好看")
        
        try await repository.removeBookmark(bookmark)
        let afterDelete = try await repository.fetchBookmarks(for: bookID)
        #expect(afterDelete.isEmpty)
    }
}
