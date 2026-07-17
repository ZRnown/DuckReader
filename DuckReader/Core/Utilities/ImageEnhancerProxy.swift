import Foundation
import SwiftUI

/// ObservableObject wrapper around the ImageEnhancer actor,
/// making it usable in SwiftUI's @StateObject / @EnvironmentObject.
@MainActor
public final class ImageEnhancerProxy: ObservableObject {
    private let enhancer = ImageEnhancer()

    @Published public var isEnabled: Bool = false
    @Published public private(set) var isProcessing: Bool = false

    public nonisolated init() {}

    public func enhance(data: Data, enableNoiseReduction: Bool = true, enableContrast: Bool = true) async -> Data? {
        isProcessing = true
        defer { isProcessing = false }
        guard isEnabled else { return data }

        let uiImage: UIImage
        if let img = UIImage(data: data) {
            uiImage = img
        } else {
            return data
        }

        guard let cgImage = uiImage.cgImage else { return data }

        let enhanced = await enhancer.applyEnhancements(
            to: cgImage,
            noiseReduction: enableNoiseReduction ? .medium : nil,
            contrast: enableContrast ? 1.2 : nil
        )

        guard let enhanced else { return data }
        return UIImage(cgImage: enhanced).pngData()
    }
}

// MARK: - Environment Key

public struct ImageEnhancerKey: EnvironmentKey {
    public static let defaultValue = ImageEnhancerProxy()
}

public extension EnvironmentValues {
    var imageEnhancer: ImageEnhancerProxy {
        get { self[ImageEnhancerKey.self] }
        set { self[ImageEnhancerKey.self] = newValue }
    }
}
