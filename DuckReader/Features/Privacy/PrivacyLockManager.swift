import Foundation
import LocalAuthentication
import SwiftUI
import Combine

// MARK: - Privacy Lock Manager

/// Manages biometric (FaceID/TouchID) and passcode authentication
/// for app-level privacy lock and individual book lock.
@MainActor
public final class PrivacyLockManager: ObservableObject {
    public static let shared = PrivacyLockManager()

    private let context = LAContext()
    private let defaults = UserDefaults(suiteName: "group.com.duckreader")!

    @Published public private(set) var isLocked: Bool = true
    @Published public private(set) var isAppLockEnabled: Bool = false
    @Published public private(set) var lockedBooks: Set<String> = []
    @Published public private(set) var authError: String?

    /// Biometric type available on this device.
    public var biometricType: BiometricType {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    public enum BiometricType: Sendable {
        case none
        case faceID
        case touchID
        case opticID

        public var displayName: String {
            switch self {
            case .none: return L10n.privacyBiometricPassword
            case .faceID: return L10n.privacyBiometricFaceID
            case .touchID: return L10n.privacyBiometricTouchID
            case .opticID: return L10n.privacyBiometricOpticID
            }
        }

        public var iconName: String {
            switch self {
            case .none: return "lock"
            case .faceID: return "faceid"
            case .touchID: return "touchid"
            case .opticID: return "opticid"
            }
        }
    }

    private init() {
        isAppLockEnabled = defaults.bool(forKey: "appLockEnabled")
        if let data = defaults.data(forKey: "lockedBooks"),
           let books = try? JSONDecoder().decode([String].self, from: data) {
            lockedBooks = Set(books)
        }

        // Lock on init if enabled
        if isAppLockEnabled {
            isLocked = true
        } else {
            isLocked = false
        }
    }

    // MARK: - App-Level Lock

    /// Toggle app-level privacy lock.
    public func setAppLock(enabled: Bool) {
        isAppLockEnabled = enabled
        defaults.set(enabled, forKey: "appLockEnabled")

        if !enabled {
            isLocked = false
        }
    }

    /// Authenticate for app unlock (FaceID/TouchID).
    /// - Returns: true if unlock successful.
    public func authenticate(reason: String = L10n.privacyFaceIDReason) async -> Bool {
        authError = nil

        // If biometrics not available, just unlock
        guard biometricType != .none else {
            isLocked = false
            return true
        }

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Fall back to device passcode
            return await authenticateWithPasscode(reason: reason)
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            isLocked = !success
            return success
        } catch {
            authError = error.localizedDescription
            return false
        }
    }

    /// Fallback: authenticate with device passcode.
    public func authenticateWithPasscode(reason: String = L10n.privacyUnlockPrompt) async -> Bool {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authError = String(format: L10n.privacyAuthError, error?.localizedDescription ?? L10n.privacyUnknownError)
            return false
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            isLocked = !success
            return success
        } catch {
            authError = error.localizedDescription
            return false
        }
    }

    /// Lock the app (call on scene phase change to background).
    public func lockApp() {
        if isAppLockEnabled {
            isLocked = true
        }
    }

    // MARK: - Per-Book Lock

    /// Lock/unlock a specific book with biometrics.
    public func toggleBookLock(bookID: String) {
        if lockedBooks.contains(bookID) {
            lockedBooks.remove(bookID)
        } else {
            lockedBooks.insert(bookID)
        }
        persistLockedBooks()
    }

    /// Check if a book is locked.
    public func isBookLocked(bookID: String) -> Bool {
        lockedBooks.contains(bookID)
    }

    /// Authenticate to unlock a specific book.
    public func unlockBook(bookID: String) async -> Bool {
        let success = await authenticate(reason: L10n.privacyUnlockBook)
        if success {
            lockedBooks.remove(bookID)
            persistLockedBooks()
        }
        return success
    }

    private func persistLockedBooks() {
        if let data = try? JSONEncoder().encode(Array(lockedBooks)) {
            defaults.set(data, forKey: "lockedBooks")
        }
    }

    /// Check whether any lock is active.
    public var anyLockActive: Bool {
        isAppLockEnabled && isLocked
    }
}

// MARK: - Privacy Lock Screen View

/// Full-screen lock overlay. Displayed when app is locked.
public struct PrivacyLockScreenView: View {
    @StateObject private var lockManager = PrivacyLockManager.shared
    @State private var unlockButtonScale: CGFloat = 1

    public init() {}

    public var body: some View {
        ZStack {
            // Material background with blur
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // App icon
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange.gradient)

                Text(L10n.privacyLockScreen)
                    .font(DuckFont.largeTitle)

                Text(L10n.privacyLocked)
                    .font(DuckFont.subhead)
                    .foregroundStyle(.secondary)

                Spacer()

                // Unlock button with scale-on-press
                Button {
                    DuckHaptic.medium()
                    Task {
                        _ = await lockManager.authenticate()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: lockManager.biometricType.iconName)
                            .font(.title2)
                        Text(String(format: L10n.privacyUseBiometric, lockManager.biometricType.displayName))
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.orange.gradient)
                    )
                }
                .duckPressable()
                .scaleEffect(unlockButtonScale)
                .onAppear {
                    withAnimation(DuckSpring.playful.delay(0.3)) {
                        unlockButtonScale = 1
                    }
                }

                if let error = lockManager.authError {
                    Text(error)
                        .font(DuckFont.caption1)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(DuckSpring.bouncy, value: lockManager.authError)
                }

                // Passcode fallback
                Button(L10n.privacyUsePasscode) {
                    Task {
                        _ = await lockManager.authenticateWithPasscode()
                    }
                }
                .font(DuckFont.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 12)

                Spacer()
                    .frame(height: 60)
            }
            .padding()
        }
    }
}

// MARK: - Book Lock Badge

public struct BookLockBadge: View {
    let isLocked: Bool
    @State private var scale: CGFloat = 1

    public init(isLocked: Bool) {
        self.isLocked = isLocked
    }

    public var body: some View {
        if isLocked {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(6)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(.black.opacity(0.3)))
                )
                .scaleEffect(scale)
                .onTapGesture {
                    withAnimation(DuckSpring.snappy) {
                        scale = 0.8
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(DuckSpring.bouncy) {
                            scale = 1
                        }
                    }
                    DuckHaptic.light()
                }
        }
    }
}
