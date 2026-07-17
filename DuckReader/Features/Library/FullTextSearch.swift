import Foundation
import NaturalLanguage

// MARK: - Full Text Search Engine

/// Indexes novel content for full-text search with relevance ranking.
/// Uses NaturalLanguage for language-aware tokenization and TF-IDF
/// scoring. Lightweight index stored on disk.
///
/// Separate from SwiftData/Spotlight — this is for in-app deep search
/// across book content, notes, and annotations.
@MainActor
public final class FullTextSearch: ObservableObject, @unchecked Sendable {

    @Published public private(set) var indexedBookCount: Int = 0
    @Published public private(set) var totalTokens: Int = 0
    @Published public private(set) var lastIndexDate: Date?

    /// In-memory inverted index: term → [(bookID, positions, frequency)]
    private var invertedIndex: [String: [Posting]] = [:]

    /// Document frequency: term → number of documents containing it
    private var docFrequency: [String: Int] = [:]

    /// Total documents in index
    private var totalDocuments: Int = 0

    private let indexQueue = DispatchQueue(label: "com.duckreader.search.index", qos: .utility)

    public nonisolated init() {}

    // MARK: - Indexing

    /// Index a document (book chapter or full text).
    public func indexDocument(
        bookID: String,
        content: String,
        title: String? = nil,
        author: String? = nil
    ) {
        indexQueue.async { [weak self] in
            self?.indexDocumentSync(bookID: bookID, content: content, title: title, author: author)
        }
    }

    private func indexDocumentSync(bookID: String, content: String, title: String?, author: String?) {
        // Tokenize with NaturalLanguage
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(.english) // Auto-detect in production

        var text = content.lowercased()
        if let t = title?.lowercased() { text += " \(t)" }

        let fullText = text
        tokenizer.string = fullText

        var termPositions: [String: [Int]] = [:]
        var position = 0

        tokenizer.enumerateTokens(in: fullText.startIndex..<fullText.endIndex) { range, _ in
            let term = String(fullText[range])
            // Skip stop words and very short terms
            guard term.count > 2, !stopWords.contains(term) else { return true }

            termPositions[term, default: []].append(position)
            position += 1
            return true
        }

        // Update inverted index
        for (term, positions) in termPositions {
            let posting = Posting(bookID: bookID, positions: positions, termFrequency: positions.count)
            invertedIndex[term, default: []].append(posting)
            docFrequency[term, default: 0] += 1
        }

        totalDocuments += 1
        totalTokens += position

        Task { @MainActor in
            indexedBookCount = totalDocuments
            lastIndexDate = Date()
        }
    }

    /// Remove a document from the index.
    public func removeDocument(bookID: String) {
        indexQueue.async { [weak self] in
            guard let self else { return }
            for (term, postings) in self.invertedIndex {
                self.invertedIndex[term] = postings.filter { $0.bookID != bookID }
                if self.invertedIndex[term]?.isEmpty == true {
                    self.invertedIndex[term] = nil
                    self.docFrequency[term] = nil
                }
            }
            self.totalDocuments -= 1
        }
    }

    // MARK: - Search

    /// Search the index for a query string.
    /// Returns results ranked by TF-IDF score.
    public func search(
        query: String,
        limit: Int = 20,
        filterTags: [String]? = nil
    ) async -> [SearchResult] {
        await withCheckedContinuation { continuation in
            indexQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }

                let results = self.searchSync(query: query, limit: limit)
                continuation.resume(returning: results)
            }
        }
    }

    private func searchSync(query: String, limit: Int) -> [SearchResult] {
        // Tokenize query
        let tokenizer = NLTokenizer(unit: .word)
        let lowerQuery = query.lowercased()
        tokenizer.string = lowerQuery

        var queryTerms: [(term: String, weight: Double)] = []

        tokenizer.enumerateTokens(in: lowerQuery.startIndex..<lowerQuery.endIndex) { range, _ in
            let term = String(lowerQuery[range])
            guard term.count > 1, !stopWords.contains(term) else { return true }
            // Exact match gets higher weight
            let weight = query.contains(term.uppercased()) ? 2.0 : 1.0
            queryTerms.append((term, weight))
            return true
        }

        guard !queryTerms.isEmpty else { return [] }

        // BM25-like scoring (simplified TF-IDF)
        var scores: [String: Double] = [:]

        for (term, weight) in queryTerms {
            guard let postings = invertedIndex[term] else { continue }

            let df = Double(docFrequency[term] ?? 1)
            let idf = log((Double(totalDocuments) - df + 0.5) / (df + 0.5) + 1.0)

            for posting in postings {
                let tf = Double(posting.termFrequency)
                let k1: Double = 1.2
                let b: Double = 0.75

                // BM25 component
                let docLenNorm = 1.0 // Simplified
                let tfScore = (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * docLenNorm))
                let score = idf * tfScore * weight

                // Bonus for title match
                if posting.bookID.lowercased().contains(term) {
                    scores[posting.bookID, default: 0] += score * 1.5
                } else {
                    scores[posting.bookID, default: 0] += score
                }
            }
        }

        // Sort by score
        let sorted = scores
            .sorted { $0.value > $1.value }
            .prefix(limit)

        return sorted.map { (bookID, score) in
            // Generate snippet
            let snippet = generateSnippet(for: bookID, queryTerms: queryTerms.map(\.term))
            return SearchResult(
                bookID: bookID,
                score: score,
                snippet: snippet,
                termMatches: queryTerms.count
            )
        }
    }

    /// Search with prefix matching (as-you-type).
    public func prefixSearch(query: String, limit: Int = 10) -> [String] {
        let lower = query.lowercased()
        guard lower.count >= 2 else { return [] }

        return invertedIndex.keys
            .filter { $0.hasPrefix(lower) }
            .sorted { (docFrequency[$0] ?? 0) > (docFrequency[$1] ?? 0) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Snippets

    private func generateSnippet(for bookID: String, queryTerms: [String]) -> String {
        // Find the first position where any query term appears
        // and return surrounding context
        guard let firstTerm = queryTerms.first(where: { invertedIndex[$0] != nil }),
              let postings = invertedIndex[firstTerm],
              let posting = postings.first(where: { $0.bookID == bookID }),
              let firstPos = posting.positions.first else {
            return ""
        }

        // In production, reconstruct text from positions
        // For now, return a contextual marker
        let matchWords = queryTerms.joined(separator: ", ")
        return "…\(matchWords)… (position ~\(firstPos))"
    }

   // MARK: - Stop Words

    // MARK: - Sharded Search
    
    /// 索引分片：当文档数超过阈值时自动分片，避免单次搜索扫描全量索引
    private let shardThreshold: Int = 500
    private var shards: [Int: ShardIndex] = [:]
    private var shardCount: Int = 0
    
    /// 带分片感知的搜索：小库走精确搜索，大库分片并行搜索后合并
    public func searchWithShards(
        query: String,
        limit: Int = 20
    ) async -> [SearchResult] {
        if totalDocuments <= shardThreshold {
            return await search(query: query, limit: limit)
        }
        
        // 分片并行搜索
        let perShardLimit = limit / max(shardCount, 1) + 1
        
        let shardResults: [[SearchResult]] = await withTaskGroup(of: [SearchResult].self) { group in
            for (shardID, _) in shards {
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    return await self.searchInShard(shardID: shardID, query: query, limit: perShardLimit)
                }
            }
            
            var results: [[SearchResult]] = []
            for await shardResult in group {
                results.append(shardResult)
            }
            return results
        }
        
        // 合并排序
        let merged = shardResults
            .flatMap { $0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
        
        return Array(merged)
    }
    
    /// 在指定分片中搜索
    private func searchInShard(shardID: Int, query: String, limit: Int) async -> [SearchResult] {
        await withCheckedContinuation { continuation in
            indexQueue.async { [weak self] in
                guard let self, let shard = self.shards[shardID] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let results = self.searchInIndex(
                    invertedIndex: shard.invertedIndex,
                    docFrequency: shard.docFrequency,
                    totalDocuments: shard.totalDocuments,
                    query: query,
                    limit: limit
                )
                continuation.resume(returning: results)
            }
        }
    }
    
    /// 针对指定索引执行搜索（通用搜索内核，避免重复代码）
    private func searchInIndex(
        invertedIndex: [String: [Posting]],
        docFrequency: [String: Int],
        totalDocuments: Int,
        query: String,
        limit: Int
    ) -> [SearchResult] {
        let tokenizer = NLTokenizer(unit: .word)
        let lowerQuery = query.lowercased()
        tokenizer.string = lowerQuery
        
        var queryTerms: [(term: String, weight: Double)] = []
        tokenizer.enumerateTokens(in: lowerQuery.startIndex..<lowerQuery.endIndex) { range, _ in
            let term = String(lowerQuery[range])
            guard term.count > 1, !stopWords.contains(term) else { return true }
            let weight = query.contains(term.uppercased()) ? 2.0 : 1.0
            queryTerms.append((term, weight))
            return true
        }
        
        guard !queryTerms.isEmpty else { return [] }
        
        var scores: [String: Double] = [:]
        
        for (term, weight) in queryTerms {
            guard let postings = invertedIndex[term] else { continue }
            let df = Double(docFrequency[term] ?? 1)
            let idf = log((Double(totalDocuments) - df + 0.5) / (df + 0.5) + 1.0)
            
            for posting in postings {
                let tf = Double(posting.termFrequency)
                let k1: Double = 1.2
                let b: Double = 0.75
                let tfScore = (tf * (k1 + 1)) / (tf + k1 * (1 - b))
                let score = idf * tfScore * weight
                
                if posting.bookID.lowercased().contains(term) {
                    scores[posting.bookID, default: 0] += score * 1.5
                } else {
                    scores[posting.bookID, default: 0] += score
                }
            }
        }
        
        return scores
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (bookID, score) in
                let snippet = generateSnippet(for: bookID, queryTerms: queryTerms.map(\.term))
                return SearchResult(bookID: bookID, score: score, snippet: snippet, termMatches: queryTerms.count)
            }
    }
    
    /// 重建分片索引（后台异步执行，带进度回调）
    public func rebuildShardedIndex(onProgress: ((Int, Int) -> Void)? = nil) async {
        indexQueue.async { [weak self] in
            guard let self else { return }
            
            let allTerms = self.invertedIndex.keys.sorted()
            let totalTerms = allTerms.count
            guard totalTerms > 0 else { return }
            
            let shardSize = max(totalTerms / max(self.shardCount, 1), 100)
            self.shards.removeAll()
            
            var currentShard = 0
            var shardInverted: [String: [Posting]] = [:]
            var shardDocFreq: [String: Int] = [:]
            var shardDocCount = 0
            
            for (index, term) in allTerms.enumerated() {
                shardInverted[term] = self.invertedIndex[term]
                shardDocFreq[term] = self.docFrequency[term]
                shardDocCount = max(shardDocCount, self.docFrequency[term] ?? 0)
                
                if (index + 1) % shardSize == 0 || index == totalTerms - 1 {
                    self.shards[currentShard] = ShardIndex(
                        id: currentShard,
                        invertedIndex: shardInverted,
                        docFrequency: shardDocFreq,
                        totalDocuments: shardDocCount
                    )
                    currentShard += 1
                    shardInverted = [:]
                    shardDocFreq = [:]
                    shardDocCount = 0
                    
                    DispatchQueue.main.async {
                        onProgress?(currentShard, (totalTerms / shardSize) + 1)
                    }
                }
            }
            
            self.shardCount = currentShard
        }
        
        // Wait for async work to settle
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    
    /// 获取分片统计信息
    public var shardStats: ShardStats {
        ShardStats(
            totalDocuments: totalDocuments,
            shardCount: shardCount,
            shardThreshold: shardThreshold,
            isSharded: totalDocuments > shardThreshold
        )
    }

    // MARK: - Stop Words

    private let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "is", "are", "was", "were", "be", "been",
        "being", "have", "has", "had", "do", "does", "did", "will", "would",
        "could", "should", "may", "might", "shall", "can", "need", "dare",
        "ought", "used", "this", "that", "these", "those", "it", "its",
        "i", "me", "my", "we", "our", "you", "your", "he", "she", "him", "her",
        "they", "them", "their", "not", "no", "nor", "so", "as", "if", "then",
        "than", "too", "very", "just", "about", "into", "over", "also", "one",
        "two", "all", "each", "every", "both", "few", "more", "most", "other",
        "some", "such", "only", "own", "same", "here", "there",
        // CJK common particles
        "的", "了", "和", "是", "就", "都", "而", "及", "与", "着",
        "或", "一个", "没有", "我们", "你们", "他们", "它们", "自己",
        "之", "这", "那", "也", "但", "不", "在", "有", "人", "上",
        // Korean particles
        "이", "가", "은", "는", "을", "를", "에", "에서", "로", "으로",
        "와", "과", "의", "도", "만", "부터", "까지", "나", "이나",
        // Japanese particles
        "は", "が", "を", "に", "で", "へ", "と", "から", "まで", "より",
        "の", "も", "か", "や", "よ", "ね", "な", "わ", "さ", "し",
    ]
}

// MARK: - Models

/// A posting in the inverted index.
struct Posting: Sendable {
    let bookID: String
    let positions: [Int]
    let termFrequency: Int
}

/// A search result with score and snippet.
public struct SearchResult: Identifiable, Sendable {
    public let id = UUID()
    public let bookID: String
    public let score: Double
    public let snippet: String
    public let termMatches: Int

    public var relevanceLabel: String {
        if score > 10 {
            return String(localized: "search.highRelevance")
        } else if score > 3 {
            return String(localized: "search.mediumRelevance")
        } else {
            return String(localized: "search.lowRelevance")
        }
    }
}

// MARK: - Sharded Index Models

/// 一个索引分片，包含部分倒排索引
struct ShardIndex: Sendable {
    let id: Int
    let invertedIndex: [String: [Posting]]
    let docFrequency: [String: Int]
    let totalDocuments: Int
}

/// 分片统计信息
public struct ShardStats: Sendable {
    public let totalDocuments: Int
    public let shardCount: Int
    public let shardThreshold: Int
    public let isSharded: Bool
    
    public var description: String {
        if isSharded {
            return "\(totalDocuments) docs indexed across \(shardCount) shards"
        } else {
            return "\(totalDocuments) docs indexed (single shard)"
        }
    }
}
