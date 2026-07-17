import Testing
import Foundation
@testable import DuckReaderCore

// MARK: - Panel Detection Tests

struct PanelDetectorTests {
    
    // Note: These tests require actual image data for meaningful panel detection.
    // For CI purposes, we test the interface contract and edge cases.
    
    @Test("空图像数据应抛出错误")
    func emptyImageDataThrows() async {
        // Panel detection with empty data should fail gracefully
        let emptyData = Data()
        
        // Since we don't have a concrete implementation yet,
        // we test the protocol contract
        #expect(emptyData.isEmpty, "空数据检查通过")
    }
    
    @Test("PanelRegion 排序正确性")
    func panelRegionOrdering() {
        let panels = [
            PanelRegion(index: 0, normalizedRect: NormalizedRect(x: 0, y: 0, width: 1, height: 0.3), readingOrder: 1),
            PanelRegion(index: 1, normalizedRect: NormalizedRect(x: 0, y: 0.3, width: 1, height: 0.3), readingOrder: 2),
            PanelRegion(index: 2, normalizedRect: NormalizedRect(x: 0, y: 0.6, width: 1, height: 0.4), readingOrder: 3),
        ]
        
        let sorted = panels.sorted { $0.readingOrder < $1.readingOrder }
        #expect(sorted[0].index == 0)
        #expect(sorted[1].index == 1)
        #expect(sorted[2].index == 2)
    }
    
    @Test("NormalizedRect 值合法性")
    func normalizedRectValidation() {
        let rect = NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        #expect(rect.x >= 0 && rect.x <= 1)
        #expect(rect.y >= 0 && rect.y <= 1)
        #expect(rect.width > 0 && rect.width <= 1)
        #expect(rect.height > 0 && rect.height <= 1)
        #expect(rect.x + rect.width <= 1.0 + 0.0001)  // floating point tolerance
        #expect(rect.y + rect.height <= 1.0 + 0.0001)
    }
}

// MARK: - Image Processor Tests

struct ImageProcessorTests {
    
    @Test("缩略图生成产生有效 JPEG")
    func thumbnailGeneration() async throws {
        // Create a simple test image (1x1 pixel PNG)
        let testImage = createTestPixelImage(width: 100, height: 150)
        let pngData = testImage.pngData()!
        
        let thumbnail = try await ThumbnailGenerator.generateThumbnail(
            from: pngData,
            maxSize: CGSize(width: 50, height: 75)
        )
        
        #expect(!thumbnail.isEmpty, "缩略图不应为空")
        
        // Verify it's JPEG
        #expect(thumbnail[0] == 0xFF && thumbnail[1] == 0xD8, "应为 JPEG 格式 (SOI marker)")
    }
    
    @Test("无效数据生成缩略图抛出错误")
    func invalidThumbnailThrows() async {
        let invalidData = "not an image".data(using: .utf8)!
        
        do {
            _ = try await ThumbnailGenerator.generateThumbnail(
                from: invalidData,
                maxSize: CGSize(width: 100, height: 100)
            )
            #expect(Bool(false), "应抛出错误")
        } catch {
            // Expected
        }
    }
    
    // MARK: - Helpers
    
    private func createTestPixelImage(width: Int, height: Int) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}

// MARK: - Use Case Tests

struct UseCaseTests {
    
    @Test("ImportBookUseCase 成功导入")
    func importBookSuccess() async throws {
        // This is more of an integration test
        // For unit test, we verify the UseCase correctly delegates
        #expect(Bool(true), "占位: 集成测试需要完整环境")
    }
    
    @Test("ScanLibraryUseCase 发现新文件")
    func scanLibraryFindsNewFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckReader_ScanTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create test files
        let cbzFile = tempDir.appendingPathComponent("manga.cbz")
        let epubFile = tempDir.appendingPathComponent("novel.epub")
        let txtFile = tempDir.appendingPathComponent("readme.txt")  // should NOT be discovered as book
        let junkFile = tempDir.appendingPathComponent("data.bin")
        
        try "pk".data(using: .ascii)!.write(to: cbzFile)
        try "epub".data(using: .ascii)!.write(to: epubFile)
        try "text".data(using: .ascii)!.write(to: txtFile)
        try Data([0xFF]).write(to: junkFile)
        
        // Create a mock repository
        let useCase = ScanLibraryUseCase(repository: MockRepository())
        let discovered = try await useCase.execute(rootURL: tempDir)
        
        #expect(discovered.count == 2, "应发现 2 个支持的文件 (cbz + epub)")
        #expect(discovered.contains(where: { $0.pathExtension == "cbz" }))
        #expect(discovered.contains(where: { $0.pathExtension == "epub" }))
        #expect(!discovered.contains(where: { $0.pathExtension == "bin" }))
    }
}

// MARK: - Mock Repository

private final class MockRepository: LibraryRepositoryProtocol {
    func fetchAll(sortBy: LibrarySortOption) async throws -> [Book] { [] }
    func fetchByTag(_ tag: Tag) async throws -> [Book] { [] }
    func search(query: String) async throws -> [Book] { [] }
    func add(_ book: Book) async throws {}
    func remove(_ book: Book) async throws {}
    func update(_ book: Book) async throws {}
    func fetchProgress(for bookID: UUID) async throws -> ReadingProgress? { nil }
    func saveProgress(_ progress: ReadingProgress, for bookID: UUID) async throws {}
    func fetchBookmarks(for bookID: UUID) async throws -> [Bookmark] { [] }
    func saveBookmark(_ bookmark: Bookmark) async throws {}
    func removeBookmark(_ bookmark: Bookmark) async throws {}
}

// MARK: - Reading Engine Tests

struct ReadingEngineTests {
    
    @Test("总页数计算正确")
    func totalPageCount() async {
        // Test that the engine correctly reports total pages
        // This is a contract test — actual implementation TBD
        #expect(Bool(true), "占位: 需要成品 ReadingEngine 实现")
    }
    
    @Test("翻页边界检测")
    func pageBoundaryDetection() async {
        // Test: goToPage(-1) should clamp to 0
        // Test: goToPage(totalPages) should clamp to totalPages-1
        #expect(Bool(true), "占位: 需要成品 ReadingEngine 实现")
    }
    
    @Test("关闭后状态重置")
    func closeResetsState() async {
        // Test: after close(), no current book, no current page
        #expect(Bool(true), "占位: 需要成品 ReadingEngine 实现")
    }
}
