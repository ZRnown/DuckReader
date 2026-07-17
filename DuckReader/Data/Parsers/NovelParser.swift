import Foundation
import ZIPFoundation
import SwiftSoup

// MARK: - Novel Format Parser

/// Parses EPUB, MOBI, TXT, Markdown, and HTML novel formats into `Book` domain models.
/// Uses Readium for EPUB rendering at the UI layer; this parser handles metadata
/// extraction, TOC parsing, and content pre-processing for import and library display.
public final class NovelParser: Sendable {

    public enum NovelParserError: LocalizedError {
        case invalidFile
        case unsupportedFormat
        case missingMetadata
        case parseFailure(String)
        case encodingDetectionFailed

        public var errorDescription: String? {
            switch self {
            case .invalidFile: return "文件无效或已损坏"
            case .unsupportedFormat: return "不支持的格式"
            case .missingMetadata: return "缺少元数据"
            case .parseFailure(let detail): return "解析失败: \(detail)"
            case .encodingDetectionFailed: return "编码检测失败"
            }
        }
    }

    public init() {}

    // MARK: - Public Entry Point

    /// Parse a novel file at the given URL and return extracted metadata + TOC.
    /// - Parameter url: Local file URL of the novel
    /// - Returns: A tuple of (NovelMetadata, [TOCEntry])
    public func parse(url: URL) throws -> NovelParseResult {
        let format = FileFormatDetector.detectNovelFormat(url: url)

        return switch format {
        case .epub:
            try parseEPUB(url: url)
        case .mobi, .azw, .azw3:
            try parseMOBI(url: url)
        case .txt:
            try parseTXT(url: url)
        case .markdown:
            try parseMarkdown(url: url)
        case .html:
            try parseHTML(url: url)
        case .unknown:
            throw NovelParserError.unsupportedFormat
        }
    }

    /// Extract plain text of all chapters for the reading engine.
    public func extractContent(url: URL, format: NovelFileFormat) throws -> [ChapterContent] {
        return switch format {
        case .epub:
            try extractEPUBContent(url: url)
        case .mobi, .azw, .azw3:
            try extractMOBIContent(url: url)
        case .txt:
            try extractTXTContent(url: url)
        case .markdown:
            try extractMarkdownContent(url: url)
        case .html:
            try extractHTMLContent(url: url)
        case .unknown:
            throw NovelParserError.unsupportedFormat
        }
    }

    // MARK: - EPUB Parsing

    private func parseEPUB(url: URL) throws -> NovelParseResult {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw NovelParserError.invalidFile
        }

        // Find container.xml to locate OPF
        guard let containerEntry = archive["META-INF/container.xml"],
              let containerData = try? readEntry(archive: archive, entry: containerEntry),
              let containerStr = String(data: containerData, encoding: .utf8) else {
            throw NovelParserError.parseFailure("无法读取 container.xml")
        }

        let opfPath = try extractOPFPath(from: containerStr)
        var metadata = NovelMetadata()
        var toc: [TOCEntry] = []
        var spine: [String] = []

        // Parse OPF
        if let opfEntry = archive[opfPath] ?? findEntry(archive: archive, containing: opfPath.components(separatedBy: "/").last ?? opfPath),
           let opfData = try? readEntry(archive: archive, entry: opfEntry),
           let opfStr = String(data: opfData, encoding: .utf8) {
            metadata = try parseOPFMetadata(opfStr)
            spine = try parseOPFSpine(opfStr)
        }

        // Parse NCX for TOC
        if let ncxPath = metadata.tocHref ?? findNCXPath(in: archive),
           let ncxEntry = archive[ncxPath] ?? findEntry(archive: archive, containing: ncxPath.components(separatedBy: "/").last ?? ncxPath),
           let ncxData = try? readEntry(archive: archive, entry: ncxEntry),
           let ncxStr = String(data: ncxData, encoding: .utf8) {
            toc = try parseNCX(ncxStr)
        }

        // Fallback TOC from spine
        if toc.isEmpty {
            toc = spine.enumerated().map { idx, href in
                TOCEntry(
                    id: "spine_\(idx)",
                    title: "第\(idx + 1)章",
                    href: href,
                    playOrder: idx,
                    children: []
                )
            }
        }

        metadata.chapterCount = toc.isEmpty ? spine.count : toc.count

        // Attempt cover image extraction
        let coverPath = try? extractCoverImage(archive: archive, metadata: metadata, opfBase: opfPath)

        return NovelParseResult(metadata: metadata, toc: toc, coverPath: coverPath)
    }

    private func extractEPUBContent(url: URL) throws -> [ChapterContent] {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw NovelParserError.invalidFile
        }
        var chapters: [ChapterContent] = []

        guard let containerEntry = archive["META-INF/container.xml"],
              let containerData = try? readEntry(archive: archive, entry: containerEntry),
              let containerStr = String(data: containerData, encoding: .utf8) else {
            throw NovelParserError.parseFailure("无法读取 container.xml")
        }

        let opfPath = try extractOPFPath(from: containerStr)
        let basePath = (opfPath as NSString).deletingLastPathComponent

        var spine: [String] = []
        if let opfEntry = findEntry(archive: archive, containing: opfPath.components(separatedBy: "/").last ?? opfPath),
           let opfData = try? readEntry(archive: archive, entry: opfEntry),
           let opfStr = String(data: opfData, encoding: .utf8) {
            spine = try parseOPFSpine(opfStr)
        }

        for (idx, href) in spine.enumerated() {
            let fullPath = basePath.isEmpty ? href : "\(basePath)/\(href)"
            guard let entry = archive[fullPath] ?? findEntry(archive: archive, containing: href),
                  let data = try? readEntry(archive: archive, entry: entry) else {
                continue
            }

            let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? ""
            let plainText = stripHTML(html)

            chapters.append(ChapterContent(
                index: idx,
                title: "第\(idx + 1)章",
                plainText: plainText,
                html: html
            ))
        }

        return chapters
    }

    // MARK: - MOBI Parsing

    private func parseMOBI(url: URL) throws -> NovelParseResult {
        let data = try Data(contentsOf: url)
        let header = try parseMOBIHeader(data)

        var metadata = NovelMetadata()
        metadata.title = header.title
        metadata.author = header.author
        metadata.language = header.language ?? "zh"
        metadata.publisher = header.publisher
        metadata.format = header.isAZW3 ? .azw3 : .mobi

        let tocCount = estimateMOBIChapterCount(data)
        metadata.chapterCount = tocCount

        let toc = (0..<tocCount).map { i in
            TOCEntry(
                id: "mobi_\(i)",
                title: "第\(i + 1)章",
                href: "chapter_\(i)",
                playOrder: i,
                children: []
            )
        }

        return NovelParseResult(metadata: metadata, toc: toc, coverPath: nil)
    }

    private func extractMOBIContent(url: URL) throws -> [ChapterContent] {
        let data = try Data(contentsOf: url)
        let records = try extractMOBIRecords(data)
        var chapters: [ChapterContent] = []

        for (idx, text) in records.enumerated() {
            let cleaned = stripHTML(text)
            guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            chapters.append(ChapterContent(
                index: idx,
                title: "第\(idx + 1)章",
                plainText: cleaned,
                html: text
            ))
        }

        return chapters
    }

    // MARK: - TXT Parsing

    private func parseTXT(url: URL) throws -> NovelParseResult {
        let data = try Data(contentsOf: url)
        let encoding = detectTextEncoding(data)
        guard let text = String(data: data, encoding: encoding) else {
            throw NovelParserError.encodingDetectionFailed
        }

        let fileName = url.deletingPathExtension().lastPathComponent
        let chapters = splitTXTIntoChapters(text)

        var metadata = NovelMetadata()
        metadata.title = fileName
        metadata.format = .txt
        metadata.chapterCount = chapters.count

        let toc = chapters.enumerated().map { i, title in
            TOCEntry(
                id: "txt_\(i)",
                title: title,
                href: "chapter_\(i)",
                playOrder: i,
                children: []
            )
        }

        return NovelParseResult(metadata: metadata, toc: toc, coverPath: nil)
    }

    private func extractTXTContent(url: URL) throws -> [ChapterContent] {
        let data = try Data(contentsOf: url)
        let encoding = detectTextEncoding(data)
        guard let fullText = String(data: data, encoding: encoding) else {
            throw NovelParserError.encodingDetectionFailed
        }

        let chapterSplits = splitTXTIntoChapters(fullText)
        var chapters: [ChapterContent] = []

        var currentIdx = 0
        for title in chapterSplits {
            guard let range = fullText.range(of: title) else { continue }
            let start = range.upperBound
            let end = currentIdx + 1 < chapterSplits.count
                ? fullText.range(of: chapterSplits[currentIdx + 1])?.lowerBound ?? fullText.endIndex
                : fullText.endIndex
            let content = String(fullText[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)

            chapters.append(ChapterContent(
                index: currentIdx,
                title: title,
                plainText: content,
                html: nil
            ))
            currentIdx += 1
        }

        if chapters.isEmpty {
            chapters.append(ChapterContent(
                index: 0,
                title: "全文",
                plainText: fullText,
                html: nil
            ))
        }

        return chapters
    }

    // MARK: - Markdown Parsing

    private func parseMarkdown(url: URL) throws -> NovelParseResult {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .gb_18030_2000) else {
            throw NovelParserError.encodingDetectionFailed
        }

        let fileName = url.deletingPathExtension().lastPathComponent
        let headings = extractMarkdownHeadings(text)

        var metadata = NovelMetadata()
        metadata.title = headings.first ?? fileName
        metadata.format = .markdown
        metadata.chapterCount = max(1, headings.count)

        let toc = headings.enumerated().map { i, title in
            TOCEntry(
                id: "md_\(i)",
                title: title,
                href: "chapter_\(i)",
                playOrder: i,
                children: []
            )
        }

        if toc.isEmpty {
            return NovelParseResult(metadata: metadata, toc: [
                TOCEntry(id: "md_0", title: fileName, href: "chapter_0", playOrder: 0, children: [])
            ], coverPath: nil)
        }

        return NovelParseResult(metadata: metadata, toc: toc, coverPath: nil)
    }

    private func extractMarkdownContent(url: URL) throws -> [ChapterContent] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .gb_18030_2000) else {
            throw NovelParserError.encodingDetectionFailed
        }

        let headings = extractMarkdownHeadings(text)
        var chapters: [ChapterContent] = []

        if headings.isEmpty {
            chapters.append(ChapterContent(index: 0, title: "全文", plainText: text, html: nil))
        } else {
            var remaining = text
            for (i, heading) in headings.enumerated() {
                guard let headingRange = remaining.range(of: heading) else { continue }
                let contentStart = headingRange.upperBound
                let contentEnd: String.Index
                if i + 1 < headings.count, let nextRange = remaining.range(of: headings[i + 1]) {
                    contentEnd = nextRange.lowerBound
                } else {
                    contentEnd = remaining.endIndex
                }
                let content = String(remaining[contentStart..<contentEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                chapters.append(ChapterContent(index: i, title: heading, plainText: content, html: nil))
                remaining = String(remaining[contentEnd...])
            }
        }

        return chapters
    }

    // MARK: - HTML Parsing

    private func parseHTML(url: URL) throws -> NovelParseResult {
        let data = try Data(contentsOf: url)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .gb_18030_2000) else {
            throw NovelParserError.encodingDetectionFailed
        }

        let doc = try SwiftSoup.parse(html)
        let title = try doc.title()
        let bodyText = try doc.body()?.text() ?? html

        let fileName = url.deletingPathExtension().lastPathComponent
        var metadata = NovelMetadata()
        metadata.title = title.isEmpty ? fileName : title
        metadata.format = .html
        metadata.chapterCount = 1

        return NovelParseResult(metadata: metadata, toc: [
            TOCEntry(id: "html_0", title: title.isEmpty ? fileName : title, href: "body", playOrder: 0, children: [])
        ], coverPath: nil)
    }

    private func extractHTMLContent(url: URL) throws -> [ChapterContent] {
        let data = try Data(contentsOf: url)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .gb_18030_2000) else {
            throw NovelParserError.encodingDetectionFailed
        }

        let doc = try SwiftSoup.parse(html)
        let title = try doc.title()
        let plainText = try doc.body()?.text() ?? stripHTML(html)

        return [ChapterContent(index: 0, title: title, plainText: plainText, html: html)]
    }

    // MARK: - EPUB Helpers

    private func extractOPFPath(from containerXML: String) throws -> String {
        // Simple regex-based extraction: <rootfile full-path="..." media-type="application/oebps-package+xml"/>
        let pattern = #"full-path="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: containerXML, range: NSRange(containerXML.startIndex..., in: containerXML)),
              let range = Range(match.range(at: 1), in: containerXML) else {
            throw NovelParserError.parseFailure("container.xml 中找不到 OPF 路径")
        }
        return String(containerXML[range])
    }

    private func parseOPFMetadata(_ opf: String) throws -> NovelMetadata {
        var metadata = NovelMetadata()
        metadata.format = .epub

        // dc:title
        if let title = extractXMLTag(opf, tag: "dc:title") {
            metadata.title = title
        }
        // dc:creator
        if let author = extractXMLTag(opf, tag: "dc:creator") {
            metadata.author = author
        }
        // dc:language
        if let lang = extractXMLTag(opf, tag: "dc:language") {
            metadata.language = lang
        }
        // dc:publisher
        if let pub = extractXMLTag(opf, tag: "dc:publisher") {
            metadata.publisher = pub
        }
        // dc:description
        if let desc = extractXMLTag(opf, tag: "dc:description") {
            metadata.bookDescription = desc
        }
        // dc:identifier
        if let id = extractXMLTag(opf, tag: "dc:identifier") {
            metadata.identifier = id
        }
        // meta cover
        if let coverID = extractXMLAttribute(opf, tag: "meta", attrName: "name", attrValue: "cover", targetAttr: "content") {
            metadata.coverID = coverID
        }

        return metadata
    }

    private func parseOPFSpine(_ opf: String) throws -> [String] {
        var spine: [String] = []
        let pattern = #"<itemref[^>]*idref="([^"]+)"[^>]*/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return spine }
        let matches = regex.matches(in: opf, range: NSRange(opf.startIndex..., in: opf))
        for match in matches {
            if let range = Range(match.range(at: 1), in: opf) {
                let idref = String(opf[range])
                // Look up href in manifest
                let hrefPattern = #"id="\#(idref)"[^>]*href="([^"]+)""#
                if let hrefRegex = try? NSRegularExpression(pattern: hrefPattern),
                   let hrefMatch = hrefRegex.firstMatch(in: opf, range: NSRange(opf.startIndex..., in: opf)),
                   let hrefRange = Range(hrefMatch.range(at: 1), in: opf) {
                    spine.append(String(opf[hrefRange]))
                }
            }
        }
        return spine
    }

    private func parseNCX(_ ncx: String) throws -> [TOCEntry] {
        var entries: [TOCEntry] = []
        let pattern = #"<navPoint[^>]*id="([^"]*)"[^>]*playOrder="([^"]*)"[^>]*>.*?<text>([^<]+)</text>.*?<content[^>]*src="([^"]*)".*?</navPoint>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return entries
        }

        let matches = regex.matches(in: ncx, range: NSRange(ncx.startIndex..., in: ncx))
        for match in matches {
            guard let idRange = Range(match.range(at: 1), in: ncx),
                  let orderRange = Range(match.range(at: 2), in: ncx),
                  let titleRange = Range(match.range(at: 3), in: ncx),
                  let srcRange = Range(match.range(at: 4), in: ncx),
                  let order = Int(String(ncx[orderRange])) else { continue }

            entries.append(TOCEntry(
                id: String(ncx[idRange]),
                title: String(ncx[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                href: String(ncx[srcRange]),
                playOrder: order,
                children: []
            ))
        }
        return entries.sorted { $0.playOrder < $1.playOrder }
    }

    private func findNCXPath(in archive: Archive) -> String? {
        for entry in archive {
            if entry.path.hasSuffix(".ncx") {
                return entry.path
            }
        }
        return nil
    }

    private func extractCoverImage(archive: Archive, metadata: NovelMetadata, opfBase: String) throws -> String? {
        let basePath = (opfBase as NSString).deletingPathLastComponent
        let coverNames = ["cover.jpg", "cover.jpeg", "cover.png", "cover.gif",
                          "coverpage.jpg", "coverpage.jpeg", "coverpage.png",
                          "titlepage.jpg", "titlepage.png",
                          "image_cover.jpg", "image_cover.jpeg", "image_cover.png"]

        // First try from manifest cover-id
        if let coverID = metadata.coverID {
            if let opfEntry = findEntry(archive: archive, containing: (opfBase as NSString).lastPathComponent),
               let opfData = try? readEntry(archive: archive, entry: opfEntry),
               let opfStr = String(data: opfData, encoding: .utf8) {
                let manifestPattern = #"id="\#(coverID)"[^>]*href="([^"]+)"[^>]*media-type="image/([^"]+)""#
                if let regex = try? NSRegularExpression(pattern: manifestPattern),
                   let match = regex.firstMatch(in: opfStr, range: NSRange(opfStr.startIndex..., in: opfStr)),
                   let hrefRange = Range(match.range(at: 1), in: opfStr) {
                    let coverHref = String(opfStr[hrefRange])
                    let fullPath = basePath.isEmpty ? coverHref : "\(basePath)/\(coverHref)"
                    if archive[fullPath] != nil || findEntry(archive: archive, containing: coverHref) != nil {
                        return fullPath
                    }
                }
            }
        }

        // Fallback: scan for common cover filenames
        for entry in archive {
            let fileName = (entry.path as NSString).lastPathComponent.lowercased()
            if coverNames.contains(fileName) {
                return entry.path
            }
            if fileName.contains("cover") && (fileName.hasSuffix(".jpg") || fileName.hasSuffix(".jpeg") || fileName.hasSuffix(".png")) {
                return entry.path
            }
        }

        return nil
    }

    // MARK: - MOBI Helpers

    private struct MOBIHeader {
        let title: String
        let author: String
        let language: String?
        let publisher: String?
        let isAZW3: Bool
    }

    private func parseMOBIHeader(_ data: Data) throws -> MOBIHeader {
        // PalmDOC header at offset 0: 2 bytes compression, 2 bytes unused, 4 bytes text length
        // MOBI header starts at offset 16 after PDB header (name + attributes + version + dates)
        // PDB name: 32 bytes at offset 0
        let pdbNameEnd = min(32, data.count)
        let pdbNameData = data[0..<pdbNameEnd]
        let dbName = String(data: pdbNameData, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(["\0"])) ?? "Unknown"

        // Check for "BOOKMOBI" identifier at offset 60
        var isAZW3 = false
        let mobiOffset = 16 + 32 + 4 + 4 + 4 + 4 + 4 + 2  // PDB header full size: 78 bytes typically
        if data.count > mobiOffset + 8 {
            let identData = data[mobiOffset..<min(mobiOffset + 8, data.count)]
            if let ident = String(data: identData, encoding: .ascii) {
                isAZW3 = ident.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ident.contains("MOBI") == false
            }
        }

        // Try to extract title from record 1 (text record offset 0)
        var title = dbName
        var author = ""
        var language: String? = nil
        var publisher: String? = nil

        // EXTH header parsing (after MOBI header, variable offset)
        if data.count > mobiOffset + 100 {
            // Full name offset in MOBI header: offset 84 from PDB start (title offset)
            let titleOffsetLoc = 84
            if data.count > titleOffsetLoc + 4 {
                let titleOffset = Int(data[titleOffsetLoc..<titleOffsetLoc+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                if titleOffset > 0, data.count > titleOffset + 100 {
                    let titleLen = Int(data[titleOffset..<titleOffset+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                    if titleLen > 0, data.count > titleOffset + 4 + titleLen {
                        title = String(data: data[titleOffset+4..<titleOffset+4+titleLen], encoding: .utf8)?
                            .trimmingCharacters(in: CharacterSet(["\0"])) ?? dbName
                    }
                }
            }
        }

        return MOBIHeader(title: title, author: author, language: language, publisher: publisher, isAZW3: isAZW3)
    }

    private func estimateMOBIChapterCount(_ data: Data) -> Int {
        // Conservative estimate based on file size: ~1 chapter per 10KB
        return max(1, data.count / 10_000)
    }

    private func extractMOBIRecords(_ data: Data) throws -> [String] {
        // PDB record count at offset 76
        guard data.count > 80 else { throw NovelParserError.invalidFile }
        let recordCount = Int(data[76..<78].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })

        // Record offsets table starts at 78, each entry is 4+4=8 bytes
        var records: [String] = []
        var offsets: [Int] = []

        for i in 0..<recordCount {
            let loc = 78 + i * 8
            guard data.count > loc + 4 else { break }
            let offset = Int(data[loc..<loc+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            offsets.append(offset)
        }

        for i in 0..<(offsets.count - 1) {
            let start = offsets[i]
            let end = offsets[i + 1]
            guard start < end, data.count > end else { continue }

            if i == 0 { continue } // Skip PDB header record

            if let text = String(data: data[start..<end], encoding: .utf8) ??
                          String(data: data[start..<end], encoding: .gb_18030_2000) {
                records.append(text)
            }
        }

        return records
    }

    // MARK: - TXT Helpers

    private func detectTextEncoding(_ data: Data) -> String.Encoding {
        // BOM detection
        if data.count >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
            return .utf8
        }
        if data.count >= 2 && data[0] == 0xFF && data[1] == 0xFE {
            return .utf16LittleEndian
        }
        if data.count >= 2 && data[0] == 0xFE && data[1] == 0xFF {
            return .utf16BigEndian
        }

        // Try UTF-8 first, then GBK (common for Chinese novels)
        if String(data: data, encoding: .utf8) != nil {
            return .utf8
        }
        if String(data: data, encoding: .gb_18030_2000) != nil {
            return .gb_18030_2000
        }

        return .utf8
    }

    private func splitTXTIntoChapters(_ text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var chapters: [String] = []
        var lastTitle = ""

        let patterns: [NSRegularExpression] = [
            try! NSRegularExpression(pattern: #"^(第[零一二三四五六七八九十百千万0-9]+[章节回卷部集篇])"#),
            try! NSRegularExpression(pattern: #"^(Chapter\s*\d+)"#, options: .caseInsensitive),
            try! NSRegularExpression(pattern: #"^(序言|楔子|前言|引子|尾声|后记|番外|附录|跋)"#),
            try! NSRegularExpression(pattern: #"^(Volume\s*\d+|Part\s*\d+)"#, options: .caseInsensitive),
        ]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for pattern in patterns {
                if pattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                    if !lastTitle.isEmpty {
                        chapters.append(lastTitle)
                    }
                    lastTitle = trimmed
                    break
                }
            }
        }
        if !lastTitle.isEmpty {
            chapters.append(lastTitle)
        }

        return chapters
    }

    private func extractMarkdownHeadings(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"^#{1,6}\s+(.+)$"#, options: .anchorsMatchLines)
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: - XML Helpers

    private func extractXMLTag(_ xml: String, tag: String) -> String? {
        let pattern = #"<\#(tag)[^>]*>([^<]*)</\#(tag)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractXMLAttribute(_ xml: String, tag: String, attrName: String, attrValue: String, targetAttr: String) -> String? {
        let pattern = #"<\#(tag)[^>]*\#(attrName)="\#(attrValue)"[^>]*\#(targetAttr)="([^"]+)"[^>]*/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[range])
    }

    // MARK: - HTML Utility

    private func stripHTML(_ html: String) -> String {
        guard let doc = try? SwiftSoup.parse(html),
              let text = try? doc.text() else {
            // Fallback regex strip
            let pattern = try! NSRegularExpression(pattern: "<[^>]+>")
            return pattern.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "")
        }
        return text
    }

    // MARK: - Archive Helpers

    private func readEntry(archive: Archive, entry: Entry) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }

    private func findEntry(archive: Archive, containing name: String) -> Entry? {
        for entry in archive {
            if entry.path.contains(name) {
                return entry
            }
        }
        return nil
    }
}

// MARK: - Novel File Format Detection

public enum NovelFileFormat: Sendable {
    case epub
    case mobi
    case azw
    case azw3
    case txt
    case markdown
    case html
    case unknown
}

public enum FileFormatDetector {
    public static func detectNovelFormat(url: URL) -> NovelFileFormat {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "epub": return .epub
        case "mobi": return .mobi
        case "azw": return .azw
        case "azw3": return .azw3
        case "txt", "text": return .txt
        case "md", "markdown": return .markdown
        case "html", "htm", "xhtml": return .html
        default:
            // Try magic bytes
            guard let data = try? Data(contentsOf: url) else { return .unknown }
            return detectByMagic(data)
        }
    }

    private static func detectByMagic(_ data: Data) -> NovelFileFormat {
        guard data.count >= 4 else { return .unknown }

        // ZIP magic (EPUB is ZIP)
        if data[0] == 0x50 && data[1] == 0x4B {
            return .epub
        }
        // MOBI magic
        if data.count >= 68 {
            let magic = data[60..<68]
            if let str = String(data: magic, encoding: .ascii), str == "BOOKMOBI" {
                return .mobi
            }
        }
        // HTML detection
        if let head = String(data: data.prefix(256), encoding: .utf8) ??
                      String(data: data.prefix(256), encoding: .ascii) {
            if head.lowercased().contains("<!doctype html") || head.lowercased().contains("<html") {
                return .html
            }
        }
        // Default to TXT
        if String(data: data, encoding: .utf8) != nil || String(data: data, encoding: .gb_18030_2000) != nil {
            return .txt
        }

        return .unknown
    }
}

// MARK: - Parse Result Types

public struct NovelMetadata: Sendable {
    public var title: String = ""
    public var author: String = ""
    public var language: String = "zh"
    public var publisher: String?
    public var bookDescription: String?
    public var identifier: String?
    public var coverID: String?
    public var tocHref: String?
    public var chapterCount: Int = 1
    public var format: NovelFileFormat = .unknown
}

public struct TOCEntry: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let href: String
    public let playOrder: Int
    public var children: [TOCEntry]
}

public struct NovelParseResult: Sendable {
    public let metadata: NovelMetadata
    public let toc: [TOCEntry]
    public let coverPath: String?
}

public struct ChapterContent: Sendable {
    public let index: Int
    public let title: String
    public let plainText: String
    public let html: String?
}
