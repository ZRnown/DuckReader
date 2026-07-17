import Foundation

// MARK: - Book → Module Input Adapters

extension Book {

    var seriesInput: SeriesManager.SeriesBookInput {
        SeriesManager.SeriesBookInput(
            id: id,
            title: title,
            metadataSeriesName: seriesName,
            metadataVolume: seriesVolume,
            format: format.rawValue,
            coverURL: coverURL,
            progress: Double(currentPage) / Double(max(totalPages, 1)),
            lastReadDate: lastOpenedAt,
            pubDate: nil
        )
    }

    var readingCandidateInput: ContinueReadingSmart.ReadingCandidateInput {
        ContinueReadingSmart.ReadingCandidateInput(
            id: id,
            title: title,
            author: author,
            seriesName: seriesName,
            seriesVolume: seriesVolume,
            coverURL: coverURL,
            progress: Double(currentPage) / Double(max(totalPages, 1)),
            totalPages: totalPages,
            lastOpenedDate: lastOpenedAt
        )
    }

    var batchBookItem: BatchOperations.BookItem {
        BatchOperations.BookItem(
            id: id,
            title: title,
            filePath: filePath,
            fileHash: nil,
            fileSize: nil,
            format: format.rawValue,
            pageCount: totalPages,
            seriesName: seriesName,
            seriesVolume: seriesVolume,
            tags: tags.map(\.name)
        )
    }
}

// MARK: - LibraryViewModel Extensions

extension LibraryViewModel {

    // ── FullTextSearch ──

    func rebuildSearchIndex(for books: [Book]) {
        for book in books {
            let text = [book.title, book.author].compactMap { $0 }.joined(separator: " ")
            guard !text.isEmpty else { continue }
            fullTextSearch.indexDocument(
                bookID: book.id.uuidString,
                content: text,
                title: book.title,
                author: book.author
            )
        }
    }

    func fullTextResults(query: String, books: [Book]) async -> [Book] {
        guard !query.isEmpty else { return books }
        // Use BM25 full-text search for ranked results
        let results = await fullTextSearch.search(query: query, limit: 50)
        let bookIDSet = Set(results.map(\.bookID))
        let bookMap = Dictionary(uniqueKeysWithValues: books.map { ($0.id.uuidString, $0) })
        let ranked = results.compactMap { bookMap[$0.bookID] }

        // Fallback: title/author match for books not in index
        let lowercased = query.lowercased()
        let fallback = books.filter { book in
            !bookIDSet.contains(book.id.uuidString) &&
            (book.title.lowercased().contains(lowercased) ||
             (book.author?.lowercased().contains(lowercased) ?? false))
        }
        return ranked + fallback
    }

    // ── Series Detection ──

    func refreshDetectedSeries() {
        let inputs = books.map(\.seriesInput)
        let groups = seriesManager.detectSeries(from: inputs)
        detectedSeries = Dictionary(uniqueKeysWithValues: groups.map { group in
            let groupIDs = Set(group.volumes.map(\.id))
            return (group.name, books.filter { groupIDs.contains($0.id) })
        })
    }

    // ── Continue Reading ──

    func refreshContinueReading() {
        let candidates = books
            .filter { !$0.isFinished && $0.currentPage > 0 }
            .map(\.readingCandidateInput)
        let ranked = continueReading.rank(candidates)
        if let top = ranked.first, let book = books.first(where: { $0.id == top.id }) {
            recommendedNext = book
        } else {
            recommendedNext = nil
        }
    }

    // ── Batch Operations ──

    func runDedup() async {
        let items = books.map(\.batchBookItem)
        let groups = await batchOps.scanDuplicates(books: items)
        guard !groups.isEmpty else { return }
        let removedIDs = groups.flatMap { $0.items.dropFirst().map(\.id) }
        books.removeAll { removedIDs.contains($0.id) }
        await batchOps.removeDuplicates(groups)
    }

    func runIntegrityCheck() async -> [BatchOperations.IntegrityIssue] {
        let items = books.map(\.batchBookItem)
        return await batchOps.integrityCheck(books: items)
    }

    /// 转换为 Obsidian 导出所需元数据
    func obsidianMetadata() -> [ObsidianBookMetadata] {
        books.map { ObsidianBookMetadata(from: $0) }
    }
}
