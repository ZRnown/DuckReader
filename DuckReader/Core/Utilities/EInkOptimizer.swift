import Foundation
import SwiftUI
import CoreImage

// MARK: - E-Ink / External Display Optimizer

/// Optimizes book pages for e-ink displays and external screens:
/// grayscale conversion, contrast enhancement, dithering, and
/// display detection.
///
/// Pure CPU/CoreImage pipeline — no GPU reliance, suitable for
/// background processing on battery.
public struct EInkOptimizer: Sendable {

    // MARK: - Presets

    public enum Preset: String, Sendable, CaseIterable {
        case kindleBasic       // 167 ppi, 16-level grayscale
        case kindlePaperwhite  // 300 ppi, Carta
        case remarkable        // 226 ppi, no backlight
        case boox              // 300 ppi, Android e-ink
        case genericEInk       // Safe defaults for any e-ink
        case highContrast      // Maximum readability for low vision
        case printerFriendly   // Optimized for B&W laser printer

        var label: String {
            switch self {
            case .kindleBasic:      "Kindle (167 ppi)"
            case .kindlePaperwhite: "Kindle Paperwhite (300 ppi)"
            case .remarkable:       "reMarkable (226 ppi)"
            case .boox:             "BOOX (300 ppi)"
            case .genericEInk:      String(localized: "eink.generic")
            case .highContrast:     String(localized: "eink.highContrast")
            case .printerFriendly:  String(localized: "eink.printerFriendly")
            }
        }
    }

    // MARK: - Optimization Options

    public struct Options: Sendable {
        public var preset: Preset
        public var gamma: Double             // 0.5–3.0, default 1.0
        public var contrast: Double          // 0.5–2.0, default 1.2
        public var sharpness: Double         // 0.0–2.0, default 0.3
        public var dithering: DitherMethod
        public var invertColors: Bool        // For dark-mode e-ink
        public var trimMargins: Bool
        public var targetDPI: Int?           // nil = auto

        public static let safeDefaults = Options(
            preset: .genericEInk,
            gamma: 1.0,
            contrast: 1.2,
            sharpness: 0.3,
            dithering: .floydSteinberg,
            invertColors: false,
            trimMargins: true,
            targetDPI: nil
        )

        public static func forPreset(_ preset: Preset) -> Options {
            switch preset {
            case .kindleBasic:
                return Options(preset: .kindleBasic, gamma: 1.0, contrast: 1.3,
                               sharpness: 0.4, dithering: .floydSteinberg,
                               invertColors: false, trimMargins: true, targetDPI: 167)
            case .kindlePaperwhite:
                return Options(preset: .kindlePaperwhite, gamma: 1.0, contrast: 1.15,
                               sharpness: 0.2, dithering: .atkinson,
                               invertColors: false, trimMargins: true, targetDPI: 300)
            case .remarkable:
                return Options(preset: .remarkable, gamma: 0.95, contrast: 1.25,
                               sharpness: 0.35, dithering: .floydSteinberg,
                               invertColors: false, trimMargins: false, targetDPI: 226)
            case .boox:
                return Options(preset: .boox, gamma: 1.0, contrast: 1.1,
                               sharpness: 0.15, dithering: .ordered,
                               invertColors: false, trimMargins: true, targetDPI: 300)
            case .genericEInk:
                return .safeDefaults
            case .highContrast:
                return Options(preset: .highContrast, gamma: 1.2, contrast: 2.0,
                               sharpness: 0.5, dithering: .none,
                               invertColors: false, trimMargins: true, targetDPI: nil)
            case .printerFriendly:
                return Options(preset: .printerFriendly, gamma: 0.9, contrast: 1.5,
                               sharpness: 0.1, dithering: .atkinson,
                               invertColors: false, trimMargins: true, targetDPI: 300)
            }
        }
    }

    public enum DitherMethod: String, Sendable, CaseIterable {
        case none
        case ordered           // Bayer ordered dithering (fast)
        case floydSteinberg    // Error diffusion (smooth, best quality)
        case atkinson          // Atkinson dithering (classic Mac look)
    }

    // MARK: - Processing

    /// Optimize a CGImage for e-ink display.
    public static func optimize(
        _ image: CGImage,
        options: Options = .safeDefaults
    ) -> CGImage? {
        let ciImage = CIImage(cgImage: image)

        // Step 1: Convert to grayscale
        guard let grayFilter = CIFilter(name: "CIColorControls") else { return image }
        grayFilter.setValue(ciImage, forKey: kCIInputImageKey)
        grayFilter.setValue(0.0, forKey: kCIInputSaturationKey) // Desaturate
        grayFilter.setValue(Float(options.contrast), forKey: kCIInputContrastKey)

        guard var output = grayFilter.outputImage else { return image }

        // Step 2: Gamma adjustment
        if abs(options.gamma - 1.0) > 0.01 {
            let gammaFilter = CIFilter(name: "CIGammaAdjust")
            gammaFilter?.setValue(output, forKey: kCIInputImageKey)
            gammaFilter?.setValue(Float(1.0 / options.gamma), forKey: "inputPower")
            if let gammaOutput = gammaFilter?.outputImage {
                output = gammaOutput
            }
        }

        // Step 3: Sharpen
        if options.sharpness > 0 {
            let sharpenFilter = CIFilter(name: "CISharpenLuminance")
            sharpenFilter?.setValue(output, forKey: kCIInputImageKey)
            sharpenFilter?.setValue(Float(options.sharpness), forKey: kCIInputSharpnessKey)
            if let sharpOutput = sharpenFilter?.outputImage {
                output = sharpOutput
            }
        }

        // Step 4: Invert if requested
        if options.invertColors {
            let invertFilter = CIFilter(name: "CIColorInvert")
            invertFilter?.setValue(output, forKey: kCIInputImageKey)
            if let invertOutput = invertFilter?.outputImage {
                output = invertOutput
            }
        }

        // Step 5: Render through CoreImage context
        let context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearGray)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.linearGray)!,
            .highQualityDownsample: true
        ])

        guard let rendered = context.createCGImage(output, from: output.extent) else {
            return image
        }

        // Step 6: Apply dithering (software — CoreImage doesn't have dither)
        if options.dithering != .none {
            return applyDithering(rendered, method: options.dithering)
        }

        return rendered
    }

    /// Optimize image data (JPEG/PNG) for e-ink.
    public static func optimizeData(
        _ data: Data,
        options: Options = .safeDefaults
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        guard let optimized = optimize(image, options: options) else {
            return nil
        }

        // Re-encode as PNG (lossless, dithering preserved)
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData, "public.png" as CFString, 1, nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, optimized, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }

    // MARK: - Dithering

    private static func applyDithering(_ image: CGImage, method: DitherMethod) -> CGImage? {
        switch method {
        case .none:
            return image
        case .ordered:
            return orderedDither(image)
        case .floydSteinberg:
            return floydSteinbergDither(image)
        case .atkinson:
            return atkinsonDither(image)
        }
    }

    /// Floyd-Steinberg error diffusion dithering.
    private static func floydSteinbergDither(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height

        guard let context = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpace(name: CGColorSpace.linearGray)!,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return image }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return image
        }

        // Allocate error buffer
        let rowBytes = context.bytesPerRow
        var errors = [Float](repeating: 0, count: width * height)

        // Floyd-Steinberg coefficients
        let fsKernel: [(dx: Int, dy: Int, weight: Float)] = [
            (1, 0, 7.0/16.0), (-1, 1, 3.0/16.0),
            (0, 1, 5.0/16.0), (1, 1, 1.0/16.0)
        ]

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * rowBytes + x
                let oldPixel = Float(data[idx]) + errors[y * width + x]
                let newPixel: UInt8 = oldPixel > 127 ? 255 : 0
                let quantError = oldPixel - Float(newPixel)

                data[idx] = newPixel

                for (dx, dy, w) in fsKernel {
                    let nx = x + dx
                    let ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    errors[ny * width + nx] += quantError * w
                }
            }
        }

        return context.makeImage()
    }

    /// Atkinson dithering (classic 1/8 pattern).
    private static func atkinsonDither(_ image: CGImage) -> CGImage? {
        // Same structure as Floyd-Steinberg but with Atkinson weights
        let width = image.width
        let height = image.height

        guard let context = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpace(name: CGColorSpace.linearGray)!,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return image }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return image
        }

        let rowBytes = context.bytesPerRow
        var errors = [Float](repeating: 0, count: width * height)

        let atkinsonKernel: [(dx: Int, dy: Int, weight: Float)] = [
            (1, 0, 1.0/8.0), (2, 0, 1.0/8.0),
            (-1, 1, 1.0/8.0), (0, 1, 1.0/8.0), (1, 1, 1.0/8.0),
            (0, 2, 1.0/8.0)
        ]

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * rowBytes + x
                let oldPixel = Float(data[idx]) + errors[y * width + x]
                let newPixel: UInt8 = oldPixel > 127 ? 255 : 0
                let quantError = oldPixel - Float(newPixel)

                data[idx] = newPixel

                for (dx, dy, w) in atkinsonKernel {
                    let nx = x + dx
                    let ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    errors[ny * width + nx] += quantError * w
                }
            }
        }

        return context.makeImage()
    }

    /// Bayer ordered dithering (4×4 matrix).
    private static func orderedDither(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height

        guard let context = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpace(name: CGColorSpace.linearGray)!,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return image }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return image
        }

        // 4×4 Bayer matrix normalized to 0–15
        let bayer4x4: [Int] = [
            0,  8,  2, 10,
            12, 4, 14,  6,
            3, 11,  1,  9,
            15, 7, 13,  5
        ]

        let rowBytes = context.bytesPerRow

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * rowBytes + x
                let threshold = (Float(bayer4x4[(y & 3) * 4 + (x & 3)]) + 0.5) / 16.0 * 255.0
                data[idx] = Float(data[idx]) > threshold ? 255 : 0
            }
        }

        return context.makeImage()
    }

    // MARK: - Display Detection

    /// Detect if an external display connected is likely an e-ink device.
    public static func detectExternalEInk() -> EInkDisplayInfo? {
        #if os(iOS)
        // On iOS, check connected screens
        let screens = UIScreen.screens
        guard screens.count > 1 else { return nil }

        for screen in screens.dropFirst() {
            // E-ink screens typically have lower max brightness
            if screen.brightness == 0 || screen.maximumFramesPerSecond <= 30 {
                return EInkDisplayInfo(
                    screen: screen,
                    isProbablyEInk: true,
                    nativeScale: screen.nativeScale
                )
            }
        }
        return nil
        #else
        return nil
        #endif
    }
}

// MARK: - E-Ink Display Info

public struct EInkDisplayInfo: Sendable {
    public let isProbablyEInk: Bool
    public let nativeScale: CGFloat
    public let screen: AnyObject? // UIScreen, but avoid UIKit import issues

    fileprivate init(screen: Any, isProbablyEInk: Bool, nativeScale: CGFloat) {
        self.screen = screen as AnyObject
        self.isProbablyEInk = isProbablyEInk
        self.nativeScale = nativeScale
    }
}
