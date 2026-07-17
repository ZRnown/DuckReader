import SwiftUI
import Observation
import UniformTypeIdentifiers

// MARK: - Library ViewModel

@MainActor
@Observable
public final class LibraryViewModel: Sendable {
    public var books: [Book] = []
    public var isLoading = false
    public var error: Error?
    public var searchQuery = ""
    public var selectedSort: LibrarySortOption = .recentlyOpened
    public var selectedTag: Tag?
    public var isImporting = false
    public var importProgress: Double = 0  // 0-1
    public var recommendedNext: Book?
    public var detectedSeries: [String: [Book]] = [:]
    public var seriesNames: [String] { Array(detectedSeries.keys).sorted() }
    
    private let repository: LibraryRepositoryProtocol
    private let parser: ArchiveParserProtocol
    private let statsEngine: ReadingStatsEngine?
    private let achievementEngine: AchievementEngine?
    public let fullTextSearch = FullTextSearch()
    public let continueReading = ContinueReadingSmart()
    public let seriesManager = SeriesManager()
    public let batchOps: BatchOperations
    
    public init(
        repository: LibraryRepositoryProtocol,
        parser: ArchiveParserProtocol,
        statsEngine: ReadingStatsEngine? = nil,
        achievementEngine: AchievementEngine? = nil
    ) {
        self.repository = repository
        self.parser = parser
        self.statsEngine = statsEngine
        self.achievementEngine = achievementEngine
        self.batchOps = BatchOperations()
    }
    
    // MARK: - Data Loading
    
    public func loadBooks() async {
        isLoading = true
        error = nil
        
        do {
            if !searchQuery.isEmpty {
                books = await fullTextResults(query: searchQuery, books: books)
                // Fallback to repository search if no local results
                if books.isEmpty {
                    books = try await repository.search(query: searchQuery)
                }
            } else if let tag = selectedTag {
                books = try await repository.fetchByTag(tag)
            } else {
                books = try await repository.fetchAll(sortBy: selectedSort)
            }
            
            // Refresh smart features after load
            if searchQuery.isEmpty {
                rebuildSearchIndex(for: books)
                refreshDetectedSeries()
                refreshContinueReading()
            }
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    // MARK: - Import
    
    public func importBook(from url: URL) async {
        isImporting = true
        error = nil
        importProgress = 0
        
        let importUseCase = ImportBookUseCase(
            parser: parser,
            repository: repository
        )
        
        do {
            let book = try await importUseCase.execute(url: url)
            books.insert(book, at: 0)
            importProgress = 1.0
        } catch {
            self.error = error
        }
        
        isImporting = false
    }
    
    public func importBatch(from directoryURL: URL) async {
        isImporting = true
        error = nil
        
        let importUseCase = ImportBookUseCase(
            parser: parser,
            repository: repository
        )
        
        do {
            let imported = try await importUseCase.executeBatch(directoryURL: directoryURL)
            books.insert(contentsOf: imported, at: 0)
        } catch {
            self.error = error
        }
        
        isImporting = false
    }
    
    // MARK: - Actions
    
    public func deleteBook(_ book: Book) async {
        do {
            try await repository.remove(book)
            books.removeAll { $0.id == book.id }
        } catch {
            self.error = error
        }
    }
    
    public func toggleFavorite(_ book: Book) async {
        var updated = book
        updated.isFavorite.toggle()
        do {
            try await repository.update(updated)
            if let index = books.firstIndex(where: { $0.id == book.id }) {
                books[index] = updated
            }
        } catch {
            self.error = error
        }
    }
    
    public func refresh() async {
        await loadBooks()
    }
}

// MARK: - Library View

public struct LibraryView: View {
    @State private var viewModel: LibraryViewModel
    @State private var showFileImporter = false
    @State private var showSettings = false
    @State private var showHealth = false
    
    public init(viewModel: LibraryViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.books.isEmpty {
                    LoadingView(message: L10n.loading)
                } else if let error = viewModel.error {
                    ErrorView(error: error) {
                        Task { await viewModel.loadBooks() }
                    }
                } else if viewModel.books.isEmpty {
                    EmptyLibraryView()
                } else {
                    bookGrid
                }
                
                // Smart recommendations
                if let recommended = viewModel.recommendedNext {
                    recommendedNextRow(book: recommended)
                }
                
                bookGrid
            }
            .navigationTitle(L10n.appName)
            .searchable(text: $viewModel.searchQuery)
            .onChange(of: viewModel.searchQuery) { _, newValue in
                // Debounce: wait 300ms of inactivity before searching
                let query = newValue
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard viewModel.searchQuery == query else { return }
                    await viewModel.loadBooks()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    batchMenu
                }
                ToolbarItem(placement: .topBarLeading) {
                    sortMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showHealth = true }) {
                        Image(systemName: "heart.text.square")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if viewModel.isImporting {
                        HStack {
                            ProgressView()
                            Text(L10n.importScanning)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: supportedTypes,
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showHealth) {
                LibraryHealthView(books: viewModel.books, onFixComplete: {
                    Task { await viewModel.loadBooks() }
                })
            }
        }
        .task {
            await viewModel.loadBooks()
        }
    }
    
    // MARK: - Book Grid
    
    private var bookGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 16)
                ],
                spacing: 20
            ) {
                ForEach(viewModel.books) { book in
                    BookGridCell(book: book) {
                        Task { await viewModel.toggleFavorite(book) }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteBook(book) }
                        } label: {
                            Label(L10n.delete, systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
    
    // MARK: - Sort Menu
    
    private var sortMenu: some View {
        Menu {
            ForEach(LibrarySortOption.allCases, id: \.self) { option in
                Button {
                    viewModel.selectedSort = option
                    Task { await viewModel.loadBooks() }
                } label: {
                    Label(option.displayName, systemImage: option.iconName)
                }
            }
        } label: {
            Label(L10n.librarySortTitle, systemImage: "arrow.up.arrow.down")
        }
    }
    
    // MARK: - Import
    
    private var supportedTypes: [UTType] {
        [
            .zip,
            .init(filenameExtension: "cbz") ?? .zip,
            .init(filenameExtension: "cbr") ?? .data,
            .init(filenameExtension: "rar") ?? .data,
            .init(filenameExtension: "7z") ?? .data,
            .pdf,
            .epub,
            .plainText,
            .init(filenameExtension: "mobi") ?? .data,
            .init(filenameExtension: "azw3") ?? .data,
        ]
    }
    
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                for url in urls {
                    await viewModel.importBook(from: url)
                }
            }
        case .failure(let error):
            viewModel.error = error
        }
    }
}

// MARK: - Book Grid Cell

public struct BookGridCell: View {
    let book: Book
    let onFavoriteTap: () -> Void
    
    public init(book: Book, onFavoriteTap: @escaping () -> Void = {}) {
        self.book = book
        self.onFavoriteTap = onFavoriteTap
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover
            coverView
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if let author = book.author {
                    Text(author)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Progress
                if book.totalPages > 0 && !book.isUnread {
                    ProgressView(value: book.progressPercentage)
                        .tint(.accentColor)
                        .scaleEffect(x: 1, y: 0.5)
                }
            }
        }
        .frame(width: 150)
    }
    
    private var coverView: some View {
        ZStack(alignment: .topTrailing) {
            CachedAsyncImage(imageData: book.coverImageData)
                .frame(width: 150, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            
            // Favorite button
            Button(action: onFavoriteTap) {
                Image(systemName: book.isFavorite ? "heart.fill" : "heart")
                    .font(.caption)
                    .foregroundColor(book.isFavorite ? .red : .white)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding(4)
        }
    }
}

// MARK: - Helpers

extension LibrarySortOption {
    var displayName: String {
        switch self {
        case .title: L10n.librarySortTitle
        case .author: L10n.librarySortAuthor
        case .recentlyOpened: L10n.librarySortRecent
        case .recentlyAdded: L10n.libraryRecentlyAdded
        case .progress: L10n.libraryProgress
        }
    }
    
    var iconName: String {
        switch self {
        case .title: "textformat.abc"
        case .author: "person"
        case .recentlyOpened: "clock"
        case .recentlyAdded: "plus.circle"
        case .progress: "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - Batch & Recommendations

extension LibraryView {

    private func recommendedNextRow(book: Book) -> some View {
        HStack {
            Image(systemName: "book.pages.fill")
                .foregroundColor(.accentColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.libraryContinueReading)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(book.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            Spacer()
            if book.totalPages > 0 {
                Text("\(Int(Double(book.currentPage) / Double(book.totalPages) * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    private var batchMenu: some View {
        Menu {
            Button {
                Task { await viewModel.runDedup() }
            } label: {
                Label("Deduplicate Books", systemImage: "rectangle.on.rectangle.slash")
            }

            Button {
                Task {
                    let issues = await viewModel.runIntegrityCheck()
                    if !issues.isEmpty {
                        DuckLog.debug("Found \(issues.count) issues", category: "BatchOps")
                    }
                }
            } label: {
                Label("Integrity Check", systemImage: "checkmark.shield")
            }

            if !viewModel.seriesNames.isEmpty {
                Divider()
                Text("Series").font(.caption)
                ForEach(viewModel.seriesNames, id: \.self) { name in
                    Button {
                        if let books = viewModel.detectedSeries[name] {
                            viewModel.books = books
                        }
                    } label: {
                        Label(name, systemImage: "books.vertical")
                    }
                }
                Button {
                    viewModel.refreshDetectedSeries()
                } label: {
                    Label("Show All Books", systemImage: "list.bullet")
                }
            }
        } label: {
            Label("Batch", systemImage: "wrench.and.screwdriver")
        }
    }
}

// MARK: - Preview

#Preview {
    LibraryView(
        viewModel: LibraryViewModel(
            repository: PreviewLibraryRepository(),
            parser: ArchiveParser()
        )
    )
}

/// 预览用的假仓库
private final class PreviewLibraryRepository: LibraryRepositoryProtocol {
    func fetchAll(sortBy: LibrarySortOption) async throws -> [Book] {
        [
            Book(title: "海贼王 第1100话", sourceURL: URL(fileURLWithPath: "/"), format: .cbz, contentType: .comic, totalPages: 19),
            Book(title: "示例轻小说", author: "作者名", sourceURL: URL(fileURLWithPath: "/"), format: .epub, contentType: .novel, totalPages: 200),
        ]
    }
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
