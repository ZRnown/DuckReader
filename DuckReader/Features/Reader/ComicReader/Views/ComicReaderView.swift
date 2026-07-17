import SwiftUI
import Observation

// MARK: - Comic Reader ViewModel

@MainActor
@Observable
public final class ComicReaderViewModel: Sendable {
    public var currentBook: Book?
    public var currentPage: PageData?
    public var currentPageIndex: Int = 0
    public var totalPages: Int = 0
    public var isLoading = false
    public var error: Error?
    
    // Reader mode
    public var readingMode: ComicReadingMode = .singlePage
    public var readingDirection: ReadingDirection = .rightToLeft
    public var fitMode: ContentFitMode = .fitWidth
    
    // Panel mode
    public var isPanelMode = false
    public var currentPanels: [PanelRegion] = []
    public var currentPanelIndex = 0
    
    // Enhancement
    public var isEnhanced = false
    public var isCropBorders = false
    
    // Controls
    public var isControlsVisible = true
    
    private let engine: ReadingEngineProtocol
    private let repository: LibraryRepositoryProtocol
    
    public init(
        engine: ReadingEngineProtocol,
        repository: LibraryRepositoryProtocol
    ) {
        self.engine = engine
        self.repository = repository
    }
    
    // MARK: - Reading
    
    public func openBook(_ book: Book) async {
        isLoading = true
        error = nil
        currentBook = book
        
        do {
            try await engine.open(book: book)
            totalPages = await engine.totalPages
            
            // Restore progress
            if let progress = try? await repository.fetchProgress(for: book.id) {
                currentPageIndex = progress.currentPage
            }
            
            let page = try await engine.goToPage(currentPageIndex)
            currentPage = page
            currentPanels = page.detectedPanels ?? []
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    public func goToNextPage() async {
        guard currentPageIndex < totalPages - 1 else { return }
        
        if isPanelMode && currentPanelIndex < currentPanels.count - 1 {
            currentPanelIndex += 1
            return
        }
        
        currentPanelIndex = 0
        currentPageIndex += 1
        
        do {
            let page = try await engine.nextPage()
            currentPage = page
            currentPanels = page?.detectedPanels ?? []
            await saveProgress()
        } catch {
            self.error = error
        }
    }
    
    public func goToPreviousPage() async {
        guard currentPageIndex > 0 else { return }
        
        if isPanelMode && currentPanelIndex > 0 {
            currentPanelIndex -= 1
            return
        }
        
        currentPageIndex -= 1
        currentPanelIndex = currentPanels.isEmpty ? 0 : currentPanels.count - 1
        
        do {
            let page = try await engine.previousPage()
            currentPage = page
            currentPanels = page?.detectedPanels ?? []
            await saveProgress()
        } catch {
            self.error = error
        }
    }
    
    public func goToPage(_ index: Int) async {
        guard index >= 0, index < totalPages else { return }
        currentPageIndex = index
        currentPanelIndex = 0
        
        do {
            let page = try await engine.goToPage(index)
            currentPage = page
            currentPanels = page.detectedPanels ?? []
            await saveProgress()
        } catch {
            self.error = error
        }
    }
    
    // MARK: - Panel Detection
    
    public func togglePanelMode() async {
        isPanelMode.toggle()
        currentPanelIndex = 0
        
        if isPanelMode, currentPanels.isEmpty, let page = currentPage {
            do {
                currentPanels = try await engine.detectPanels(for: currentPageIndex)
            } catch {
                // Panel detection is non-critical; fall through gracefully
                currentPanels = []
            }
        }
    }
    
    // MARK: - Settings
    
    public func toggleReadingDirection() {
        readingDirection = readingDirection == .rightToLeft ? .leftToRight : .rightToLeft
    }
    
    public func cycleFitMode() {
        switch fitMode {
        case .fitWidth: fitMode = .fitHeight
        case .fitHeight: fitMode = .fitBoth
        case .fitBoth: fitMode = .fitWidth
        }
    }
    
    // MARK: - Progress
    
    private func saveProgress() async {
        guard let book = currentBook else { return }
        
        let progress = ReadingProgress(
            currentPage: currentPageIndex,
            lastUpdated: Date(),
            completionPercentage: totalPages > 0 ? Double(currentPageIndex) / Double(totalPages) : 0
        )
        
        try? await repository.saveProgress(progress, for: book.id)
    }
    
    public func close() async {
        await saveProgress()
        await engine.close()
        currentBook = nil
        currentPage = nil
    }
}

// MARK: - Enums

public enum ComicReadingMode: String, CaseIterable, Sendable {
    case singlePage
    case doublePage
    case panelByPanel
    case verticalScroll
    
    public var displayName: String {
        switch self {
        case .singlePage: String(localized: "reader.modeSinglePage")
        case .doublePage: String(localized: "reader.modeDoublePage")
        case .panelByPanel: String(localized: "reader.modePanelByPanel")
        case .verticalScroll: String(localized: "reader.modeVerticalScroll")
        }
    }
}

public enum ReadingDirection: String, CaseIterable, Sendable {
    case rightToLeft
    case leftToRight
    case topToBottom
    
    public var displayName: String {
        switch self {
        case .rightToLeft: String(localized: "reader.directionRTLManga")
        case .leftToRight: String(localized: "reader.directionLTRComic")
        case .topToBottom: String(localized: "reader.directionVerticalScroll")
        }
    }
}

public enum ContentFitMode: String, CaseIterable, Sendable {
    case fitWidth
    case fitHeight
    case fitBoth
    
    public var displayName: String {
        switch self {
        case .fitWidth: L10n.readerFitWidth
        case .fitHeight: L10n.readerFitHeight
        case .fitBoth: String(localized: "reader.fitBoth")
        }
    }
}

// MARK: - Comic Reader View

public struct ComicReaderView: View {
    @State private var viewModel: ComicReaderViewModel
    @Environment(\.dismiss) private var dismiss
    
    public init(viewModel: ComicReaderViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                // Main Content
                if viewModel.isLoading {
                    LoadingView(message: L10n.loading)
                        .foregroundColor(.white)
                } else if let error = viewModel.error {
                    ErrorView(error: error) {
                        if let book = viewModel.currentBook {
                            Task { await viewModel.openBook(book) }
                        }
                    }
                    .foregroundColor(.white)
                } else if let page = viewModel.currentPage {
                    pageContent(page, geometry: geometry)
                }
                
                // Controls overlay
                if viewModel.isControlsVisible {
                    readerControls
                }
            }
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
        }
        .gesture(
            TapGesture()
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.isControlsVisible.toggle()
                    }
                }
        )
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    if value.translation.width < -100 {
                        Task { await viewModel.goToNextPage() }
                    } else if value.translation.width > 100 {
                        Task { await viewModel.goToPreviousPage() }
                    }
                }
        )
    }
    
    // MARK: - Page Content
    
    @ViewBuilder
    private func pageContent(_ page: PageData, geometry: GeometryProxy) -> some View {
        if viewModel.isPanelMode && !viewModel.currentPanels.isEmpty {
            panelByPanelView(page, geometry: geometry)
        } else {
            singlePageView(page, geometry: geometry)
        }
    }
    
    private func singlePageView(_ page: PageData, geometry: GeometryProxy) -> some View {
        Group {
            if let imageData = page.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: viewModel.fitMode == .fitWidth ? .fit : .fill)
                    .frame(
                        maxWidth: geometry.size.width,
                        maxHeight: geometry.size.height
                    )
                    .clipped()
            } else {
                Text(String(localized: "reader.cannotLoadPage"))
                    .foregroundColor(.white)
            }
        }
    }
    
    private func panelByPanelView(_ page: PageData, geometry: GeometryProxy) -> some View {
        guard viewModel.currentPanelIndex < viewModel.currentPanels.count,
              let imageData = page.imageData,
              let uiImage = UIImage(data: imageData) else {
            return AnyView(Text(String(localized: "reader.cannotLoadPanel")).foregroundColor(.white))
        }
        
        let panel = viewModel.currentPanels[viewModel.currentPanelIndex]
        let imageSize = uiImage.size
        
        // Calculate crop rect from normalized coordinates
        let cropRect = CGRect(
            x: panel.normalizedRect.x * imageSize.width,
            y: panel.normalizedRect.y * imageSize.height,
            width: panel.normalizedRect.width * imageSize.width,
            height: panel.normalizedRect.height * imageSize.height
        )
        
        guard let croppedCG = uiImage.cgImage?.cropping(to: cropRect) else {
            return AnyView(Text(String(localized: "reader.panelCropFailed")).foregroundColor(.white))
        }
        
        let croppedImage = UIImage(cgImage: croppedCG)
        
        return AnyView(
            Image(uiImage: croppedImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    maxWidth: geometry.size.width,
                    maxHeight: geometry.size.height
                )
                .overlay(alignment: .bottomTrailing) {
                    Text("\(viewModel.currentPanelIndex + 1) / \(viewModel.currentPanels.count)")
                        .font(.caption2)
                        .padding(4)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(8)
                }
        )
    }
    
    // MARK: - Controls
    
    private var readerControls: some View {
        VStack {
            // Top bar
            topBar
            
            Spacer()
            
            // Bottom bar
            bottomBar
        }
        .transition(.opacity)
    }
    
    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            VStack(alignment: .center) {
                Text(viewModel.currentBook?.title ?? "")
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("\(viewModel.currentPageIndex + 1) / \(viewModel.totalPages)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            Menu {
                Button {
                    viewModel.readingMode = .singlePage
                } label: {
                    Label(ComicReadingMode.singlePage.displayName, systemImage: "rectangle")
                }
                
                Button {
                    viewModel.readingMode = .doublePage
                } label: {
                    Label(ComicReadingMode.doublePage.displayName, systemImage: "rectangle.split.2x1")
                }
                
                Button {
                    Task { await viewModel.togglePanelMode() }
                } label: {
                    Label(
                        viewModel.isPanelMode
                            ? String(localized: "reader.exitPanelByPanel")
                            : ComicReadingMode.panelByPanel.displayName,
                        systemImage: "rectangle.split.3x3"
                    )
                }
                
                Button {
                    viewModel.readingMode = .verticalScroll
                } label: {
                    Label(ComicReadingMode.verticalScroll.displayName, systemImage: "rectangle.split.1x2")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal)
        .padding(.top, 44)  // Safe area
        .background(
            LinearGradient(
                colors: [.black.opacity(0.8), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private var bottomBar: some View {
        HStack(spacing: 32) {
            // Page slider
            Slider(
                value: Binding(
                    get: { Double(viewModel.currentPageIndex) },
                    set: { newValue in
                        Task { await viewModel.goToPage(Int(newValue)) }
                    }
                ),
                in: 0...Double(max(1, viewModel.totalPages - 1)),
                step: 1
            )
            .tint(.white)
            .frame(maxWidth: 200)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Preview

#Preview {
    ComicReaderView(
        viewModel: ComicReaderViewModel(
            engine: PreviewReadingEngine(),
            repository: PreviewLibraryRepository()
        )
    )
}
