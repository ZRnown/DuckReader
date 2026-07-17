import Foundation
import SwiftUI
import GameController
import Combine

// MARK: - Reader Input Handler

/// Manages keyboard & gamepad input for the reader.
/// Maps physical controls to reader actions (page turn, zoom, scroll, TTS).
/// Uses GCController for gamepad; UIKeyCommand for keyboard.
@MainActor
public final class ReaderInputHandler: ObservableObject {
    public static let shared = ReaderInputHandler()

    // MARK: - Published state for gesture bridging
    @Published public var pageForwardTrigger: Bool = false
    @Published public var pageBackwardTrigger: Bool = false
    @Published public var zoomToggleTrigger: Bool = false
    @Published public var ttsToggleTrigger: Bool = false
    @Published public var bookmarkTrigger: Bool = false
    @Published public var menuTrigger: Bool = false

    // Continuous input for scrolling
    @Published public var scrollDelta: CGFloat = 0

    // MARK: - Configuration
    @Published public var keyboardEnabled: Bool = true
    @Published public var gamepadEnabled: Bool = true
    @Published public var invertPageButtons: Bool = false  // For left-handers

    private var connectedControllers: [GCController] = []
    private var debouncer: [String: Date] = [:]
    private let debounceInterval: TimeInterval = 0.15

    public init() {
        setupGamepadObservation()
    }

    // MARK: - Keyboard Support

    /// Call this from SwiftUI's `onKeyPress` or UIKit keyboard events.
    /// Returns true if the key was handled.
    @discardableResult
    public func handleKeyPress(_ key: String, modifiers: UIKeyModifierFlags = []) -> Bool {
        guard keyboardEnabled else { return false }
        guard !isDebounced(key) else { return true }

        switch key {
        // Page navigation
        case UIKeyCommand.inputRightArrow, " ":
            if debounce("forward") { return true }
            triggerForward()
            return true

        case UIKeyCommand.inputLeftArrow:
            if debounce("backward") { return true }
            triggerBackward()
            return true

        // Volume-like alternatives
        case "j", "J":
            if debounce("backward") { return true }
            triggerBackward()
            return true
        case "k", "K":
            if debounce("forward") { return true }
            triggerForward()
            return true

        // Scroll
        case UIKeyCommand.inputDownArrow:
            scrollDelta += 100
            return true
        case UIKeyCommand.inputUpArrow:
            scrollDelta -= 100
            return true

        // Zoom
        case "f", "F":
            if debounce("zoom") { return true }
            zoomToggleTrigger = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.zoomToggleTrigger = false
            }
            return true

        // TTS
        case "r", "R" where modifiers.contains(.command):
            ttsToggleTrigger = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.ttsToggleTrigger = false
            }
            return true

        // Bookmark
        case "d", "D" where modifiers.contains(.command):
            bookmarkTrigger = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.bookmarkTrigger = false
            }
            return true

        // Menu / Escape
        case UIKeyCommand.inputEscape:
            menuTrigger = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.menuTrigger = false
            }
            return true

        // Chapter jump
        case "[":
            triggerBackward()
            return true
        case "]":
            triggerForward()
            return true

        default:
            return false
        }
    }

    /// Generate UIKeyCommand array for UIKit integration.
    public static var keyCommands: [UIKeyCommand] {
        [
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(ReaderKeyHandler.handleRightArrow)),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(ReaderKeyHandler.handleLeftArrow)),
            UIKeyCommand(input: " ", modifierFlags: [], action: #selector(ReaderKeyHandler.handleSpace)),
            UIKeyCommand(input: "f", modifierFlags: [], action: #selector(ReaderKeyHandler.handleFKey)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(ReaderKeyHandler.handleEscape)),
        ]
    }

    // MARK: - Gamepad Support

    private func setupGamepadObservation() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            self?.connectGamepad(controller)
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            self?.disconnectGamepad(controller)
        }

        // Connect already-present controllers
        for controller in GCController.controllers() {
            connectGamepad(controller)
        }
    }

    private func connectGamepad(_ controller: GCController) {
        guard gamepadEnabled else { return }
        connectedControllers.append(controller)

        guard let gamepad = controller.extendedGamepad else { return }

        // D-pad: page navigation
        gamepad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerForward() }
        }
        gamepad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerBackward() }
        }
        gamepad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.scrollDelta += 100 }
        }
        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.scrollDelta -= 100 }
        }

        // Shoulder buttons: page turn
        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerForward() }
        }
        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerBackward() }
        }

        // Triggers for zoom
        gamepad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.zoomToggleTrigger = true }
        }
        gamepad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.zoomToggleTrigger = true }
        }

        // A: forward, B: backward, X: bookmark, Y: TTS
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerForward() }
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerBackward() }
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.bookmarkTrigger = true }
        }
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.ttsToggleTrigger = true }
        }
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.menuTrigger = true }
        }

        // Thumbstick for scrolling
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            self?.scrollDelta = CGFloat(y) * 200
        }

        DuckHaptic.medium()
    }

    private func disconnectGamepad(_ controller: GCController) {
        connectedControllers.removeAll { $0 == controller }
        DuckHaptic.light()
    }

    // MARK: - Private Helpers

    private func triggerForward() {
        pageForwardTrigger = true
        DuckHaptic.selection()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.pageForwardTrigger = false
        }
    }

    private func triggerBackward() {
        pageBackwardTrigger = true
        DuckHaptic.selection()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.pageBackwardTrigger = false
        }
    }

    private func debounce(_ key: String) -> Bool {
        if let last = debouncer[key], Date().timeIntervalSince(last) < debounceInterval {
            return true
        }
        debouncer[key] = Date()
        return false
    }

    private func isDebounced(_ key: String) -> Bool { false }
}

// MARK: - UIKit Keyboard Handler (for UIKeyCommand bridge)

@objc public final class ReaderKeyHandler: NSObject {
    weak var inputHandler: ReaderInputHandler?

    @objc public func handleRightArrow() {
        inputHandler?.handleKeyPress(UIKeyCommand.inputRightArrow)
    }

    @objc public func handleLeftArrow() {
        inputHandler?.handleKeyPress(UIKeyCommand.inputLeftArrow)
    }

    @objc public func handleSpace() {
        inputHandler?.handleKeyPress(" ")
    }

    @objc public func handleFKey() {
        inputHandler?.handleKeyPress("f")
    }

    @objc public func handleEscape() {
        inputHandler?.handleKeyPress(UIKeyCommand.inputEscape)
    }
}

// MARK: - Gamepad Connection Indicator

public struct GamepadConnectionIndicator: View {
    @StateObject private var handler = ReaderInputHandler.shared
    @State private var pulse = false

    public init() {}

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(GCController.controllers().isEmpty ? Color.gray : Color.green)
                .frame(width: 8, height: 8)
                .scaleEffect(pulse ? 1.5 : 1)
                .animation(
                    DuckSpring.bouncy.repeatForever(autoreverses: true),
                    value: pulse
                )

            Text(L10n.readerGamepad)
                .font(DuckFont.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            if !GCController.controllers().isEmpty { pulse = true }
        }
    }
}
