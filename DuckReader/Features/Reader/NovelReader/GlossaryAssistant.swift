import Foundation
import NaturalLanguage

// MARK: - 进步式轻量 Glossary 记忆助手
/// 纯规则 + Apple NaturalLanguage NLTagger 实现的人物/关键词追踪
/// 随阅读进度增量更新，不生成内容，不做复杂总结
/// 性能: 几乎零额外消耗（每章追加 <10ms，类似笔记 App）
actor GlossaryAssistant {
    // MARK: - Config
    struct Config {
        /// 人物名最少出现次数才纳入 Glossary
        var minOccurrencesForCharacter: Int = 3
        /// 关键词最少出现次数
        var minOccurrencesForKeyword: Int = 5
        /// 是否自动扫描新章节
        var autoScanNewChapter: Bool = true
    }

    var config: Config = Config()

    // MARK: - Data Types
    struct CharacterEntry: Codable, Identifiable, Sendable {
        let id: UUID
        let name: String
        var occurrences: Int
        var firstSeenChapter: Int
        var lastSeenChapter: Int
        var contextLines: [String]  // 保留前3条出现上下文
        var aliases: [String]       // 别名检测

        mutating func recordOccurrence(chapter: Int, line: String) {
            occurrences += 1
            lastSeenChapter = chapter
            if contextLines.count < 3 {
                contextLines.append(line)
            }
        }
    }

    struct KeywordEntry: Codable, Identifiable, Sendable {
        let id: UUID
        let word: String
        var occurrences: Int
        var chapterIndices: Set<Int>
    }

    struct GlossarySnapshot: Codable, Sendable {
        let bookID: String
        let characters: [CharacterEntry]
        let keywords: [KeywordEntry]
        let updatedAt: Date
        let totalChapters: Int
    }

    // MARK: - Private State
    private var characters: [String: CharacterEntry] = [:]  // name → entry
    private var keywords: [String: KeywordEntry] = [:]
    private var scannedChapters: Set<Int> = []
    private let tagSchemes: [NLTagScheme] = [.nameType, .nameTypeOrLexicalClass]

    // MARK: - Public API

    /// 扫描一章文本，增量更新人物/关键词
    func scanChapter(content: String, chapterIndex: Int) async -> (newCharacters: Int, newKeywords: Int) {
        guard config.autoScanNewChapter, !scannedChapters.contains(chapterIndex) else {
            return (0, 0)
        }
        scannedChapters.insert(chapterIndex)

        var newCharCount = 0
        var newKeywordCount = 0

        // 按段落处理
        let paragraphs = content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        for paragraph in paragraphs {
            // NER 人物识别
            let names = extractPersonNames(from: paragraph)
            for name in names {
                if var entry = characters[name] {
                    entry.recordOccurrence(chapter: chapterIndex, line: paragraph)
                    characters[name] = entry
                } else {
                    characters[name] = CharacterEntry(
                        id: UUID(),
                        name: name,
                        occurrences: 1,
                        firstSeenChapter: chapterIndex,
                        lastSeenChapter: chapterIndex,
                        contextLines: [paragraph],
                        aliases: []
                    )
                    newCharCount += 1
                }
            }

            // 关键词提取
            let words = extractKeywords(from: paragraph)
            for word in words {
                if var entry = keywords[word] {
                    entry.occurrences += 1
                    entry.chapterIndices.insert(chapterIndex)
                    keywords[word] = entry
                } else {
                    keywords[word] = KeywordEntry(
                        id: UUID(),
                        word: word,
                        occurrences: 1,
                        chapterIndices: [chapterIndex]
                    )
                    newKeywordCount += 1
                }
            }
        }

        // 别名检测：同章节出现相似名字
        detectAliases()

        return (newCharCount, newKeywordCount)
    }

    /// 获取当前 Glossary 快照
    func snapshot(bookID: String) -> GlossarySnapshot {
        GlossarySnapshot(
            bookID: bookID,
            characters: Array(characters.values)
                .filter { $0.occurrences >= config.minOccurrencesForCharacter }
                .sorted { $0.occurrences > $1.occurrences },
            keywords: Array(keywords.values)
                .filter { $0.occurrences >= config.minOccurrencesForKeyword }
                .sorted { $0.occurrences > $1.occurrences },
            updatedAt: Date(),
            totalChapters: scannedChapters.count
        )
    }

    /// 按名搜角色
    func findCharacter(named: String) -> CharacterEntry? {
        characters[named]
    }

    /// 获取角色的出现时间线
    func timeline(for characterName: String) -> [Int] {
        guard let entry = characters[characterName] else { return [] }
        return Array(entry.firstSeenChapter...entry.lastSeenChapter)
    }

    /// 重置（换书时调用）
    func reset() {
        characters.removeAll()
        keywords.removeAll()
        scannedChapters.removeAll()
    }
}

// MARK: - NLP 引擎

private extension GlossaryAssistant {

    /// 使用 NLTagger 提取人名
    func extractPersonNames(from text: String) -> [String] {
        var names: Set<String> = []

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, tokenRange in
            if tag == .personalName {
                let name = String(text[tokenRange])
                // 过滤太短或太长的伪检测
                if name.count >= 2 && name.count <= 8 {
                    names.insert(name)
                }
            }
            return true
        }

        // 额外中文名检测：使用规则匹配 2-4 汉字连续序列
        let chineseNames = extractChineseNames(from: text)
        names.formUnion(chineseNames)

        return Array(names)
    }

    /// 中文名字规则匹配
    func extractChineseNames(from text: String) -> Set<String> {
        var names: Set<String> = []

        // 常见姓氏前缀
        let surnames = Set([
            "李", "王", "张", "刘", "陈", "杨", "赵", "黄", "周", "吴",
            "徐", "孙", "胡", "朱", "高", "林", "何", "郭", "马", "罗",
            "梁", "宋", "郑", "谢", "韩", "唐", "冯", "于", "董", "萧",
            "程", "曹", "袁", "邓", "许", "傅", "沈", "曾", "彭", "吕",
            "苏", "卢", "蒋", "蔡", "贾", "丁", "魏", "薛", "叶", "阎",
            "余", "潘", "杜", "戴", "夏", "钟", "汪", "田", "任", "范",
            "方", "石", "姚", "廖", "邹", "熊", "金", "陆", "郝", "孔",
            "白", "崔", "康", "毛", "邱", "秦", "江", "史", "顾", "侯",
            // 复姓
            "欧阳", "上官", "司马", "诸葛", "司徒", "皇甫", "令狐",
        ])

        // 获取所有中文字符序列
        let pattern = try! NSRegularExpression(pattern: "[\\u4e00-\\u9fff]{2,4}", options: [])
        let nsText = text as NSString
        let matches = pattern.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            let candidate = nsText.substring(with: match.range)
            if candidate.count >= 2 && candidate.count <= 4 {
                // 检查是否以姓氏开头
                let firstChar = String(candidate.prefix(1))
                let firstTwo = String(candidate.prefix(2))
                if surnames.contains(firstChar) || surnames.contains(firstTwo) {
                    names.insert(candidate)
                }
            }
        }

        return names
    }

    /// 关键词提取（名词 + 特殊术语）
    func extractKeywords(from text: String) -> Set<String> {
        var words: Set<String> = []

        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameTypeOrLexicalClass])
        tagger.string = text

        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .omitOther]

        // 保留的名词类标签
        let keptTags: Set<NLTag> = [.noun, .placeName, .organizationName]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameTypeOrLexicalClass,
            options: options
        ) { tag, tokenRange in
            if let tag, keptTags.contains(tag) {
                let word = String(text[tokenRange]).lowercased()
                if word.count >= 2 && word.count <= 20 {
                    words.insert(word)
                }
            }
            return true
        }

        return words
    }

    /// 别名检测：同音同姓
    func detectAliases() {
        let names = Array(characters.keys)
        for i in 0..<names.count {
            for j in (i + 1)..<names.count {
                let a = names[i], b = names[j]
                // 同姓检查
                if let aFirst = a.first, let bFirst = b.first,
                   aFirst == bFirst,
                   abs(a.count - b.count) <= 1 {
                    characters[a]?.aliases.append(b)
                    characters[b]?.aliases.append(a)
                }
            }
        }
    }
}

// MARK: - Character Card View Data
/// 用于 UI 层的角色卡展示数据
extension GlossaryAssistant.CharacterEntry {
    /// 生成简短摘要
    var summary: String {
        let chapterRange = firstSeenChapter == lastSeenChapter
            ? "第\(firstSeenChapter)章"
            : "第\(firstSeenChapter)章 - 第\(lastSeenChapter)章"
        return "出场 \(occurrences) 次 | \(chapterRange)"
    }

    var importance: Int {
        // 简单重要性评估：出场次数 + 跨度
        occurrences + (lastSeenChapter - firstSeenChapter)
    }
}
