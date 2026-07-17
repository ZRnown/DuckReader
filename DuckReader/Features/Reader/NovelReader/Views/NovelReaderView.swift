import SwiftUI
import Observation

// MARK: - Novel Reader ViewModel

@MainActor
@Observable
public final class NovelReaderViewModel: Sendable {
    public var book: Book?
    public var chapters: [Chapter] = []
    public var currentChapterIndex: Int = 0
    public var currentChapterContent: String = ""
    public var isLoading = false
    public var error: Error?
    
    // Display settings
    public var fontSize: CGFloat = 18
    public var lineSpacing: CGFloat = 8
    public var fontFamily: NovelFontFamily = .system
    public var theme: NovelTheme = .paper
    public var isVerticalText: Bool = false  // CJK 竖排
    
    // TTS
    public var ttsManager = TTSManager()
    public var isTTSActive = false
    
    // Controls
    public var isControlsVisible = true
    public var showChapterList = false
    
    private let repository: LibraryRepositoryProtocol
    
    public init(repository: LibraryRepositoryProtocol) {
        self.repository = repository
    }
    
    // MARK: - Reading
    
    public func openBook(_ book: Book) async {
        self.book = book
        isLoading = true
        
        // Load progress
        if let progress = try? await repository.fetchProgress(for: book.id) {
            currentChapterIndex = progress.currentChapter
        }
        
        // TODO: Parse EPUB chapters using EPUBParser
        // For now, placeholder chapters
        chapters = [
            Chapter(bookID: book.id, index: 0, title: L10n.readerChapter(1), startPage: 0, pageCount: 1),
            Chapter(bookID: book.id, index: 1, title: L10n.readerChapter(2), startPage: 1, pageCount: 1),
        ]
        
        await loadChapter(currentChapterIndex)
        isLoading = false
    }
    
    private func loadChapter(_ index: Int) async {
        guard index < chapters.count else { return }
        currentChapterIndex = index
        
        // TODO: Load chapter content from EPUB parser
        currentChapterContent = String(localized: "reader.placeholderContent \(index + 1)")
        
        // Save progress
        if let book = book {
            let progress = ReadingProgress(
                currentChapter: index,
                chapterTitle: chapters[index].title,
                lastUpdated: Date()
            )
            try? await repository.saveProgress(progress, for: book.id)
        }
    }
    
    public func goToNextChapter() async {
        guard currentChapterIndex < chapters.count - 1 else { return }
        await loadChapter(currentChapterIndex + 1)
    }
    
    public func goToPreviousChapter() async {
        guard currentChapterIndex > 0 else { return }
        await loadChapter(currentChapterIndex - 1)
    }
    
    // MARK: - TTS
    
    public func toggleTTS() {
        if ttsManager.isSpeaking {
            ttsManager.pause()
            isTTSActive = false
        } else {
            ttsManager.speak(currentChapterContent)
            isTTSActive = true
        }
    }
}

// MARK: - Enums

public enum NovelFontFamily: String, CaseIterable, Sendable {
    case system
    case songti
    case heiti
    case kaiti
    case serif
    
    public var displayName: String {
        switch self {
        case .system: String(localized: "font.system")
        case .songti: String(localized: "font.songti")
        case .heiti: String(localized: "font.heiti")
        case .kaiti: String(localized: "font.kaiti")
        case .serif: String(localized: "font.serif")
        }
    }
}

public enum NovelTheme: String, CaseIterable, Sendable {
    case paper
    case dark
    case sepia
    case green
    
    public var displayName: String {
        switch self {
        case .paper: String(localized: "reader.themePaper")
        case .dark: L10n.readerThemeDark
        case .sepia: L10n.readerThemeSepia
        case .green: String(localized: "reader.themeGreen")
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .paper: Color(red: 0.98, green: 0.96, blue: 0.92)
        case .dark: Color(red: 0.12, green: 0.12, blue: 0.14)
        case .sepia: Color(red: 0.92, green: 0.88, blue: 0.80)
        case .green: Color(red: 0.85, green: 0.92, blue: 0.85)
        }
    }
    
    var textColor: Color {
        switch self {
        case .paper, .sepia, .green: .primary
        case .dark: .white
        }
    }
}

// MARK: - Novel Reader View

public struct NovelReaderView: View {
    @State private var viewModel: NovelReaderViewModel
    @Environment(\.dismiss) private var dismiss
    
    public init(viewModel: NovelReaderViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        ZStack {
            // Background theme
            viewModel.theme.backgroundColor
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Chapter title
                if viewModel.isControlsVisible {
                    chapterHeader
                        .transition(.opacity)
                }
                
                // Content area
                ScrollView {
                    Text(viewModel.currentChapterContent)
                        .font(.system(size: viewModel.fontSize))
                        .lineSpacing(viewModel.lineSpacing)
                        .foregroundColor(viewModel.theme.textColor)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Bottom controls
                if viewModel.isControlsVisible {
                    bottomControls
                        .transition(.opacity)
                }
            }
            
            // Chapter list overlay
            if viewModel.showChapterList {
                chapterListView
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .gesture(
            TapGesture()
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.isControlsVisible.toggle()
                    }
                }
        )
    }
    
    // MARK: - Chapter Header
    
    private var chapterHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(viewModel.theme.textColor)
            }
            
            Spacer()
            
            Text(viewModel.chapters[safe: viewModel.currentChapterIndex]?.title ?? "")
                .font(.headline)
                .foregroundColor(viewModel.theme.textColor)
            
            Spacer()
            
            Menu {
                // Font size
                Picker(L10n.readerFontSize, selection: $viewModel.fontSize) {
                    Text(String(localized: "reader.fontSizeSmall")).tag(CGFloat(14))
                    Text(String(localized: "reader.fontSizeMedium")).tag(CGFloat(18))
                    Text(String(localized: "reader.fontSizeLarge")).tag(CGFloat(22))
                    Text(String(localized: "reader.fontSizeExtraLarge")).tag(CGFloat(26))
                }
                
                // Theme
                Picker(L10n.readerTheme, selection: $viewModel.theme) {
                    ForEach(NovelTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                
                Divider()
                
                // TTS
                Button {
                    viewModel.toggleTTS()
                } label: {
                    Label(
                        viewModel.ttsManager.isSpeaking ? L10n.readerTTSPause : L10n.readerTTSPlay,
                        systemImage: viewModel.ttsManager.isSpeaking ? "stop.circle" : "play.circle"
                    )
                }
            } label: {
                Image(systemName: "textformat.size")
                    .foregroundColor(viewModel.theme.textColor)
            }
        }
        .padding(.horizontal)
        .padding(.top, 44)
        .padding(.bottom, 8)
        .background(viewModel.theme.backgroundColor)
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        HStack(spacing: 24) {
            Button {
                Task { await viewModel.goToPreviousChapter() }
            } label: {
                Image(systemName: "chevron.left.2")
            }
            
            Button {
                viewModel.showChapterList.toggle()
            } label: {
                Image(systemName: "list.bullet")
            }
            
            Button {
                Task { await viewModel.goToNextChapter() }
            } label: {
                Image(systemName: "chevron.right.2")
            }
        }
        .font(.title3)
        .foregroundColor(viewModel.theme.textColor)
        .padding(.vertical, 12)
        .background(viewModel.theme.backgroundColor)
    }
    
    // MARK: - Chapter List
    
    private var chapterListView: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.showChapterList = false
                }
            
            VStack(alignment: .leading) {
                Text(L10n.readerContents)
                    .font(.headline)
                    .padding()
                
                List(viewModel.chapters) { chapter in
                    Button {
                        Task { await viewModel.loadChapter(chapter.index) }
                        viewModel.showChapterList = false
                    } label: {
                        HStack {
                            Text(chapter.title)
                            Spacer()
                            if chapter.index == viewModel.currentChapterIndex {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .frame(width: 280)
            .background(.regularMaterial)
        }
    }
}

// MARK: - Preview

#Preview {
    NovelReaderView(
        viewModel: NovelReaderViewModel(repository: PreviewLibraryRepository())
    )
}
