import Foundation
import SwiftUI
import PencilKit

// MARK: - Pencil Canvas View

/// A SwiftUI wrapper around PencilKit's PKCanvasView for iPad annotation.
/// Supports drawing, highlighting, and erasing on book pages.
@MainActor
public struct PencilCanvas: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    let toolPicker: PKToolPicker
    let isActive: Bool

    public init(canvasView: Binding<PKCanvasView>, toolPicker: PKToolPicker, isActive: Bool = true) {
        self._canvasView = canvasView
        self.toolPicker = toolPicker
        self.isActive = isActive
    }

    public func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.isOpaque = false
        canvasView.backgroundColor = .clear
        canvasView.tool = PKInkingTool(.pen, color: .systemYellow, width: 3)

        if isActive, let window = canvasView.window {
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            canvasView.becomeFirstResponder()
        }

        return canvasView
    }

    public func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if isActive {
            toolPicker.setVisible(true, forFirstResponder: uiView)
            uiView.becomeFirstResponder()
        } else {
            uiView.resignFirstResponder()
            toolPicker.setVisible(false, forFirstResponder: uiView)
        }
    }
}

// MARK: - Pencil Annotation Manager

/// Manages PencilKit annotations per page, with Undo/Redo, layer export,
/// and integration with the AnnotationStore.
@MainActor
public final class PencilAnnotationManager: ObservableObject, Sendable {

    @Published public var currentPageIndex: Int = 0
    @Published public var isPencilActive: Bool = false
    @Published public var selectedTool: PencilToolType = .pen
    @Published public var strokeColor: UIColor = .systemYellow
    @Published public var strokeWidth: CGFloat = 3

    /// Per-page canvas drawings, keyed by page index.
    @Published public private(set) var drawings: [Int: PKDrawing] = [:]

    /// Undo/Redo stacks per page.
    private var undoStacks: [Int: [PKDrawing]] = [:]
    private var redoStacks: [Int: [PKDrawing]] = [:]

    public let toolPicker = PKToolPicker()

    public enum PencilToolType: String, CaseIterable, Sendable {
        case pen, marker, pencil, eraser, lasso

        public var displayName: String {
            switch self {
            case .pen: String(localized: "pencil.pen")
            case .marker: String(localized: "pencil.marker")
            case .pencil: String(localized: "pencil.pencil")
            case .eraser: String(localized: "pencil.eraser")
            case .lasso: String(localized: "pencil.lasso")
            }
        }

        public var systemImage: String {
            switch self {
            case .pen: return "pencil.tip"
            case .marker: return "highlighter"
            case .pencil: return "pencil"
            case .eraser: return "eraser"
            case .lasso: return "lasso"
            }
        }

        public func inkType() -> PKInkingTool.InkType {
            switch self {
            case .pen: return .pen
            case .marker: return .marker
            case .pencil: return .pencil
            default: return .pen
            }
        }
    }

    public nonisolated init() {}

    // MARK: - Tool Management

    public func selectTool(_ type: PencilToolType) {
        selectedTool = type

        switch type {
        case .pen, .marker, .pencil:
            let ink = PKInkingTool(type.inkType(), color: strokeColor, width: strokeWidth)
            toolPicker.selectedTool = ink
        case .eraser:
            toolPicker.selectedTool = PKEraserTool(.vector)
        case .lasso:
            toolPicker.selectedTool = PKLassoTool()
        }
    }

    /// Activate the Pencil canvas on a canvas view.
    public func activate(on canvasView: PKCanvasView) {
        isPencilActive = true
        selectTool(selectedTool)

        // Restore drawing for current page
        if let drawing = drawings[currentPageIndex] {
            canvasView.drawing = drawing
        } else {
            canvasView.drawing = PKDrawing()
        }

        canvasView.becomeFirstResponder()
    }

    /// Deactivate and save current drawing.
    public func deactivate(canvasView: PKCanvasView) {
        saveDrawing(canvasView.drawing, for: currentPageIndex)
        isPencilActive = false
        canvasView.resignFirstResponder()
    }

    // MARK: - Drawing Persistence

    public func saveDrawing(_ drawing: PKDrawing, for pageIndex: Int) {
        // Push current to undo stack before replacing
        if let current = drawings[pageIndex] {
            undoStacks[pageIndex, default: []].append(current)
            redoStacks[pageIndex] = []  // Clear redo on new action
        }
        drawings[pageIndex] = drawing
    }

    public func clearDrawing(for pageIndex: Int) {
        saveDrawing(PKDrawing(), for: pageIndex)
    }

    public func drawing(for pageIndex: Int) -> PKDrawing {
        drawings[pageIndex] ?? PKDrawing()
    }

    /// Check if a page has annotations.
    public func hasAnnotations(for pageIndex: Int) -> Bool {
        guard let drawing = drawings[pageIndex] else { return false }
        return !drawing.strokes.isEmpty
    }

    // MARK: - Undo / Redo

    public func undo(for pageIndex: Int) {
        guard var stack = undoStacks[pageIndex], !stack.isEmpty else { return }
        if let current = drawings[pageIndex] {
            redoStacks[pageIndex, default: []].append(current)
        }
        drawings[pageIndex] = stack.removeLast()
        undoStacks[pageIndex] = stack
    }

    public func redo(for pageIndex: Int) {
        guard var stack = redoStacks[pageIndex], !stack.isEmpty else { return }
        if let current = drawings[pageIndex] {
            undoStacks[pageIndex, default: []].append(current)
        }
        drawings[pageIndex] = stack.removeLast()
        redoStacks[pageIndex] = stack
    }

    public var canUndo: Bool {
        (undoStacks[currentPageIndex]?.count ?? 0) > 0
    }

    public var canRedo: Bool {
        (redoStacks[currentPageIndex]?.count ?? 0) > 0
    }

    // MARK: - Export

    /// Export the drawing as a PNG image (for sharing/saving).
    public func exportDrawingAsImage(for pageIndex: Int, backgroundImage: UIImage? = nil) -> UIImage? {
        guard let drawing = drawings[pageIndex], !drawing.strokes.isEmpty else { return nil }

        let bounds: CGRect
        if let bg = backgroundImage {
            bounds = CGRect(origin: .zero, size: bg.size)
        } else {
            bounds = drawing.bounds
        }

        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { ctx in
            if let bg = backgroundImage {
                bg.draw(in: bounds)
            }
            drawing.image(from: bounds, scale: UIScreen.main.scale).draw(in: bounds)
        }
    }
}

// MARK: - Environment Key

public struct PencilAnnotationKey: EnvironmentKey {
    public static let defaultValue: PencilAnnotationManager = PencilAnnotationManager()
}

public extension EnvironmentValues {
    var pencilAnnotation: PencilAnnotationManager {
        get { self[PencilAnnotationKey.self] }
        set { self[PencilAnnotationKey.self] = newValue }
    }
}
