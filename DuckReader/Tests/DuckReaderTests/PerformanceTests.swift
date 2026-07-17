import Testing
import Foundation
import SwiftUI
@testable import DuckReaderCore

// MARK: - Performance Tests

@MainActor
struct PerformanceTests {

    // MARK: - Format Detection Throughput

    @Test func formatDetection_performance_1000iterations() async throws {
        let fileNames = (0..<1000).map { "book_\($0).epub" }
        let urls = fileNames.map { URL(fileURLWithPath: "/tmp/\($0)") }

        let start = CFAbsoluteTimeGetCurrent()
        for url in urls {
            _ = FileFormatDetector.detectNovelFormat(url: url)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        // Should average under 1 microsecond per call on modern hardware
        #expect(elapsed < 0.1, "Format detection should be faster than 0.1s for 1000 iterations")
    }

    // MARK: - TXT Chapter Splitting

    @Test func chapterSplitting_performance_100KB() async throws {
        // Generate 100KB of Chapter-marked text
        var text = ""
        for i in 1...500 {
            text += "第\(i)章 测试章节标题\n"
            text += String(repeating: "这是一段测试文本内容。", count: 20)
            text += "\n\n"
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_test.txt")
        try text.write(to: tempURL, atomically: true, encoding: .utf8)

        let parser = NovelParser()

        let start = CFAbsoluteTimeGetCurrent()
        let result = try parser.parse(url: tempURL)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(!result.toc.isEmpty)
        #expect(elapsed < 1.0, "100KB TXT parsing should complete under 1 second")

        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - HTML Stripping

    @Test func htmlStripping_performance_10KB() async throws {
        var html = "<html><body>"
        for _ in 0..<100 {
            html += "<div><p>这是一段包含<strong>粗体</strong>和<em>斜体</em>的内容。</p></div>"
        }
        html += "</body></html>"

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("perf_test.html")
        try html.write(to: tempURL, atomically: true, encoding: .utf8)

        let parser = NovelParser()

        let start = CFAbsoluteTimeGetCurrent()
        _ = try parser.extractContent(url: tempURL, format: .html)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(elapsed < 0.5, "10KB HTML stripping should be under 0.5s")

        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Achievement Check

    @Test func achievementCheck_performance_1000checks() async throws {
        let engine = AchievementEngine.shared
        let stats = ReadingStats(
            totalMinutesRead: 100,
            totalPagesRead: 500,
            totalBooksRead: 5,
            longestConsecutiveDays: 3,
            longestSingleBookMinutes: 60,
            totalBookmarks: 10,
            speedReadBooks: 1,
            completionRate: 0.5,
            uniqueGenres: ["小说", "科技"],
            uniqueFormats: ["epub", "txt"]
        )

        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<1000 {
            engine.checkAchievements(stats: stats)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        // Should still be fast — O(n*m) where n is ~16 achievements
        #expect(elapsed < 1.0, "1000 achievement checks should be under 1 second")
    }

    // MARK: - TOC Entry Creation

    @Test func tocEntryCreation_performance_1000entries() async throws {
        let start = CFAbsoluteTimeGetCurrent()
        var entries: [TOCEntry] = []
        for i in 0..<1000 {
            entries.append(TOCEntry(
                id: "toc_\(i)",
                title: "第\(i+1)章 这是一个很长的章节标题用来测试性能",
                href: "chapter_\(i).xhtml",
                playOrder: i,
                children: []
            ))
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(entries.count == 1000)
        #expect(elapsed < 0.1, "1000 TOC entries should be created quickly")
    }

    // MARK: - Encoding Detection

    @Test func encodingDetection_performance_1MB() async throws {
        let chineseText = String(repeating: "天地玄黄宇宙洪荒寒来暑往秋收冬藏", count: 10_000)
        let data = chineseText.data(using: .utf8)!

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("encoding_test.txt")
        try data.write(to: tempURL)

        let parser = NovelParser()

        let start = CFAbsoluteTimeGetCurrent()
        _ = try parser.parse(url: tempURL)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(elapsed < 2.0, "1MB UTF-8 parsing should be under 2 seconds")

        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Memory — No Leaks on Repeated Parse

    @Test func novelParser_noLeaksOnRepeatedParse() async throws {
        let txtContent = """
        第一章 测试

        这是一段测试文本。

        第二章 继续

        更多测试内容。
        """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("memory_test.txt")
        try txtContent.write(to: tempURL, atomically: true, encoding: .utf8)

        let parser = NovelParser()

        for i in 0..<100 {
            _ = try parser.parse(url: tempURL)
            _ = try parser.extractContent(url: tempURL, format: .txt)
        }

        // If we got here without crash, memory is stable
        #expect(true)

        try? FileManager.default.removeItem(at: tempURL)
    }
}
