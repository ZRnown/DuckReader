import SwiftUI
import Observation
import Combine

// MARK: - Novel Reader ViewModel (Enhanced)

@MainActor
@Observable
public final class NovelReaderViewModel: Sendable {
    public var book: Book?
    public var chapters: [Chapter] = []
    public var currentChapterIndex: Int = 0
    public var currentChapterContent: String = ""
    public var isLoading = false
    public var error: Error?

    // MARK: Display Settings (enhanced)
    public var fontSize: CGFloat = 18
    public var lineSpacing: CGFloat = 8
    public var fontFamily: NovelFontFamily = .system
    public var theme: NovelTheme = .paper
    public var isVerticalText: Bool = false

    // NEW: Fine-grained typography
    public var paragraphSpacing: CGFloat = 8
    public var firstLineIndent: CGFloat = 2
    public var marginHorizontal: CGFloat = 24
    public var textAlignment: NovelTextAlignment = .justify

    // NEW: Style engine & theme store
    public var styleConfig: NovelStyleConfig = .default
    public let themeStore = ReadingThemeStore()
    public let fontManager = FontManager()
    public let vocabularyManager = VocabularyManager()
    public let chapterNav = ChapterNavigationModel()

    // NEW: Eye-care
    public var isEyeCareMode: Bool = false
    public var colorTemperature: Double = 0.5  // 0=cool, 1=warm

    // TTS
    public var ttsManager = TTSManager()
    public var isTTSActive = false

    // Controls
    public var isControlsVisible = true
    public var showChapterList = false
    public var showSettings = false
    public var showVocabulary = false
    public var selectedWord: String? = nil

    private let repository: LibraryRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()

    public init(repository: LibraryRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Reading

    public func openBook(_ book: Book) async {
        self.book = book
        isLoading = true

        if let progress = try? await repository.fetchProgress(for: book.id) {
            currentChapterIndex = progress.currentChapter
        }

        // Parse chapters
        chapters = [
            Chapter(bookID: book.id, index: 0, title: L10n.readerChapter(1), startPage: 0, pageCount: 1),
            Chapter(bookID: book.id, index: 1, title: L10n.readerChapter(2), startPage: 1, pageCount: 1),
        ]

        // Load into chapter navigator
        let chapterInfos = chapters.map { ch in
            ChapterInfo(
                id: ch.id,
                index: ch.index,
                title: ch.title,
                pageStart: ch.startPage,
                pageEnd: ch.startPage + ch.pageCount
            )
        }
        chapterNav.loadChapters(chapterInfos)

        // Detect content type & set defaults
        let contentType = SmartModeSwitcher().detectContentType(
            format: book.sourceURL.pathExtension.lowercased(),
            hasColor: false,
            aspectRatio: 0.7,
            pageCount: chapters.count,
            language: book.metadata.language
        )

        // Apply sensible defaults based on content
        switch contentType {
        case .manga, .westernComic:
            isVerticalText = false
        case .novel:
            isVerticalText = false
        default:
            break
        }

        await loadChapter(currentChapterIndex)
        isLoading = false

        // Auto-switch theme based on time
        themeStore.autoSwitchIfNeeded()
    }

    private func loadChapter(_ index: Int) async {
        guard index < chapters.count else { return }
        currentChapterIndex = index
        chapterNav.jumpToChapter(index)

        // Load content from parser
        currentChapterContent = String(localized: "reader.placeholderContent \(index + 1)")

        // Update progress
        if let book = book {
            chapterNav.updateProgress(chapterID: chapters[index].id, progress: 0)
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

    // MARK: - Enhanced Theme

    public var effectiveBackgroundColor: Color {
        if isEyeCareMode {
            return Color(
                red: 0.92 - 0.1 * colorTemperature,
                green: 0.88 - 0.1 * colorTemperature,
                blue: 0.80 - 0.2 * colorTemperature
            )
        }
        return theme.backgroundColor
    }

    public var effectiveTextColor: Color {
        if isEyeCareMode {
            return Color(
                red: 0.2 + 0.1 * colorTemperature,
                green: 0.15 + 0.05 * colorTemperature,
                blue: 0.1
            )
        }
        return theme.textColor
    }

    // MARK: - CSS Generation

    /// Generate the injected CSS for the current style config.
    public func generateReaderCSS() -> String {
        var config = NovelStyleConfig.default
        config.fontSize = fontSize
        config.lineHeight = lineSpacing / fontSize + 1.2
        config.paragraphSpacing = paragraphSpacing
        config.firstLineIndent = firstLineIndent
        config.marginLeft = marginHorizontal
        config.marginRight = marginHorizontal

        let engine = NovelStyleEngine(config: config)
        return engine.generateCSS()
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

    // MARK: - Vocabulary Lookup

    public func lookupWord(_ word: String) {
        selectedWord = word
        // Add to vocabulary if definition found
        if let def = vocabularyManager.lookupInSystemDictionary(word) {
            vocabularyManager.addEntry(
                word: word,
                definition: def,
                context: nil,
                sourceBookID: book?.id,
                sourceChapter: chapters[safe: currentChapterIndex]?.title,
                language: book?.metadata.language ?? "unknown"
            )
        }
    }
}

// MARK: - Novel Text Alignment

public enum NovelTextAlignment: String, CaseIterable, Sendable {
    case left, justify, center

    public var displayName: String {
        switch self {
        case .left: String(localized: "reader.alignLeft")
        case .justify: String(localized: "reader.alignJustify")
        case .center: String(localized: "reader.alignCenter")
        }
    }
}

// MARK: - Enums (existing, kept for compatibility)

public enum NovelFontFamily: String, CaseIterable, Sendable {
    case system, songti, heiti, kaiti, serif

    public var displayName: String {
        switch self {
        case .system: String(localized: "font.system")
        case .songti: String(localized: "font.songti")
        case .heiti: String(localized: "font.heiti")
        case .kaiti: String(localized: "font.kaiti")
        case .serif: String(localized: "font.serif")
        }
    }

    public var cssFontFamily: String {
        switch self {
        case .system: return "system-ui, -apple-system, sans-serif"
        case .songti: return "\"Songti SC\", \"SimSun\", serif"
        case .heiti: return "\"Heiti SC\", \"SimHei\", sans-serif"
        case .kaiti: return "\"Kaiti SC\", \"KaiTi\", serif"
        case .serif: return "Georgia, \"Times New Roman\", serif"
        }
    }
}

public enum NovelTheme: String, CaseIterable, Sendable {
    case paper, dark, sepia, green

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

// MARK: - Novel Reader View (Enhanced)

public struct NovelReaderView: View {
    @State private var viewModel: NovelReaderViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: NovelReaderViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack {
            viewModel.effectiveBackgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if viewModel.isControlsVisible {
                    chapterHeader
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ScrollView {
                    Text(viewModel.currentChapterContent)
                        .font(.system(size: viewModel.fontSize))
                        .lineSpacing(viewModel.lineSpacing)
                        .kerning(0.3)
                        .foregroundColor(viewModel.effectiveTextColor)
                        .padding(.horizontal, viewModel.marginHorizontal)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(viewModel.textAlignment == .center ? .center :
                            viewModel.textAlignment == .justify ? .leading : .leading)
                        .textSelection(.enabled)
                        .contextMenu {
                            // Lookup / Vocabulary
                            Button {
                                // Placeholder — in WKWebView mode, use JS bridge
                            } label: {
                                Label(String(localized: "reader.lookupWord"), systemImage: "character.book.closed")
                            }
                        }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            let width = UIScreen.main.bounds.width
                            if value.location.x < width * 0.25 {
                                // Tap left → previous
                                Task { await viewModel.goToPreviousChapter() }
                            } else if value.location.x > width * 0.75 {
                                // Tap right → next
                                Task { await viewModel.goToNextChapter() }
                            } else {
                                // Center tap → toggle controls
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.isControlsVisible.toggle()
                                }
                            }
                        }
                )

                if viewModel.isControlsVisible {
                    bottomControls
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Overlays
            if viewModel.showChapterList {
                chapterListView
            }

            if viewModel.showSettings {
                settingsView
            }

            if viewModel.showVocabulary {
                vocabularyView
            }

            if let word = viewModel.selectedWord {
                wordDefinitionOverlay(word)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .chapterNavigationShortcuts(viewModel.chapterNav)
    }

    // MARK: - Chapter Header

    private var chapterHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.chapters[safe: viewModel.currentChapterIndex]?.title ?? "")
                    .font(.subheadline.weight(.medium))
                if viewModel.chapterNav.chapterProgress.values.contains(where: { $0.progress > 0 }) {
                    ProgressView(value: viewModel.chapterNav.overallProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 80)
                        .tint(viewModel.theme.textColor)
                }
            }

            Spacer()

            HStack(spacing: 16) {
                // Settings
                Button {
                    viewModel.showSettings.toggle()
                } label: {
                    Image(systemName: "textformat.size")
                }

                // Chapter List
                Button {
                    viewModel.showChapterList.toggle()
                } label: {
                    Image(systemName: "list.bullet")
                }
            }
        }
        .foregroundColor(viewModel.effectiveTextColor)
        .padding(.horizontal)
        .padding(.top, 44)
        .padding(.bottom, 8)
        .background(viewModel.effectiveBackgroundColor)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 32) {
            // Previous
            Button {
                Task { await viewModel.goToPreviousChapter() }
            } label: {
                Label(L10n.readerPrevChapter, systemImage: "chevron.left.2")
                    .labelStyle(.iconOnly)
            }

            // Progress indicator
            Text("\(viewModel.currentChapterIndex + 1) / \(viewModel.chapters.count)")
                .font(.caption)
                .monospacedDigit()

            // TTS
            Button {
                viewModel.toggleTTS()
            } label: {
                Image(systemName: viewModel.ttsManager.isSpeaking ? "pause.circle.fill" : "play.circle")
                    .font(.title2)
            }

            // Vocabulary
            Button {
                viewModel.showVocabulary.toggle()
            } label: {
                Image(systemName: "character.book.closed")
            }

            // Next
            Button {
                Task { await viewModel.goToNextChapter() }
            } label: {
                Label(L10n.readerNextChapter, systemImage: "chevron.right.2")
                    .labelStyle(.iconOnly)
            }
        }
        .foregroundColor(viewModel.effectiveTextColor)
        .padding(.vertical, 12)
        .padding(.horizontal, 24)
        .background(viewModel.effectiveBackgroundColor)
    }

    // MARK: - Chapter List

    private var chapterListView: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { viewModel.showChapterList = false }

            VStack(alignment: .leading) {
                Text(L10n.readerContents)
                    .font(.headline)
                    .padding()

                List(viewModel.chapterNav.chapterListItems) { item in
                    Button {
                        viewModel.showChapterList = false
                        Task { await viewModel.loadChapter(item.chapter.index) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.chapter.title)
                                    .foregroundColor(item.isCurrent ? .accentColor : .primary)
                                ProgressView(value: item.progress)
                                    .progressViewStyle(.linear)
                                    .frame(width: 60)
                                    .opacity(item.progress > 0 ? 1 : 0)
                            }
                            Spacer()
                            if item.isCurrent {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                            if item.progress >= 1.0 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .frame(width: 300)
            .background(.regularMaterial)
        }
    }

    // MARK: - Settings Overlay

    private var settingsView: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { viewModel.showSettings = false }

            VStack(spacing: 0) {
                // Handle
                Capsule()
                    .fill(.secondary)
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Text(String(localized: "settings.reading"))
                    .font(.headline)
                    .padding(.bottom, 12)

                // Font size slider
                VStack(alignment: .leading, spacing: 4) {
                    Label(L10n.readerFontSize, systemImage: "textformat.size")
                        .font(.caption)
                    Slider(value: $viewModel.fontSize, in: 12...32, step: 1)
                }
                .padding(.horizontal)

                // Line spacing slider
                VStack(alignment: .leading, spacing: 4) {
                    Label(String(localized: "reader.lineSpacing"), systemImage: "line.3.horizontal")
                        .font(.caption)
                    Slider(value: $viewModel.lineSpacing, in: 2...24, step: 1)
                }
                .padding(.horizontal)

                // Margin slider
                VStack(alignment: .leading, spacing: 4) {
                    Label(String(localized: "reader.margin"), systemImage: "arrow.left.and.right")
                        .font(.caption)
                    Slider(value: $viewModel.marginHorizontal, in: 8...60, step: 2)
                }
                .padding(.horizontal)

                // Paragraph spacing
                VStack(alignment: .leading, spacing: 4) {
                    Label(String(localized: "reader.paragraphSpacing"), systemImage: "text.paragraph")
                        .font(.caption)
                    Slider(value: $viewModel.paragraphSpacing, in: 0...24, step: 1)
                }
                .padding(.horizontal)

                // Theme picker
                Picker(L10n.readerTheme, selection: $viewModel.theme) {
                    ForEach(NovelTheme.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Eye care toggle
                Toggle(String(localized: "reader.eyeCare"), isOn: $viewModel.isEyeCareMode)
                    .padding(.horizontal)
                    .padding(.top, 4)

                if viewModel.isEyeCareMode {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(String(localized: "reader.colorTemperature"), systemImage: "thermometer.sun")
                            .font(.caption)
                        Slider(value: $viewModel.colorTemperature, in: 0...1)
                    }
                    .padding(.horizontal)
                }

                // Font family
                Picker(String(localized: "settings.font"), selection: $viewModel.fontFamily) {
                    ForEach(NovelFontFamily.allCases, id: \.self) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)

                // Text alignment
                Picker(String(localized: "reader.alignment"), selection: $viewModel.textAlignment) {
                    ForEach(NovelTextAlignment.allCases, id: \.self) { a in
                        Text(a.displayName).tag(a)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Spacer()
                    .frame(height: 16)
            }
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Vocabulary View

    private var vocabularyView: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { viewModel.showVocabulary = false }

            VStack(alignment: .leading) {
                Text(String(localized: "reader.vocabulary"))
                    .font(.headline)
                    .padding()

                if viewModel.vocabularyManager.filteredEntries.isEmpty {
                    ContentUnavailableView(
                        String(localized: "reader.noVocabulary"),
                        systemImage: "character.book.closed",
                        description: Text(String(localized: "reader.noVocabularyHint"))
                    )
                } else {
                    List(viewModel.vocabularyManager.filteredEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.word)
                                .font(.headline)
                            if let def = entry.definition {
                                Text(def)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            if let ctx = entry.context {
                                Text(ctx)
                                    .font(.caption)
                                    .italic()
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.vocabularyManager.removeEntry(id: entry.id)
                            } label: {
                                Label(String(localized: "reader.delete"), systemImage: "trash")
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(width: 300)
            .background(.regularMaterial)
        }
    }

    // MARK: - Word Definition Overlay

    private func wordDefinitionOverlay(_ word: String) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Text(word)
                    .font(.title3.weight(.bold))
                if let def = viewModel.vocabularyManager.lookupInSystemDictionary(word) {
                    Text(def)
                        .font(.body)
                        .multilineTextAlignment(.center)
                } else {
                    Text(String(localized: "reader.noDefinition"))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 24) {
                    Button(String(localized: "reader.addToVocabulary")) {
                        viewModel.lookupWord(word)
                        viewModel.selectedWord = nil
                    }
                    .buttonStyle(.borderedProminent)

                    Button(String(localized: "reader.dismiss")) {
                        viewModel.selectedWord = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(24)
        }
    }
}

// MARK: - Preview

#Preview {
    NovelReaderView(
        viewModel: NovelReaderViewModel(repository: PreviewLibraryRepository())
    )
}
