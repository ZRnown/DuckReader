// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DuckReader",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "DuckReaderCore",
            targets: ["DuckReaderCore"]
        ),
    ],
    dependencies: [
        // Readium Swift Toolkit — BSD-3-Clause, commercial-friendly
        .package(url: "https://github.com/readium/swift-toolkit.git", from: "3.0.0"),
        
        // ZIPFoundation — MIT license, for ZIP/CBZ handling
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        
        // UnrarKit — for RAR/CBR extraction (built on unrar-lib, free for non-WinRAR use)
        .package(url: "https://github.com/abbeycode/UnrarKit.git", from: "3.0.0"),
        
        // LZMA SDK wrapper (SwiftPM-compatible) for 7z support
        // Note: 7z support may require a custom build of libarchive or LZMA SDK
        // .package(url: "https://github.com/yourorg/SwiftLZMA.git", from: "1.0.0"),
        
        // KeychainAccess — MIT, for secure credential storage
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        
        // Nuke — MIT, high-performance image loading & caching
        .package(url: "https://github.com/kean/Nuke.git", from: "12.0.0"),
        
        // SwiftSoup — MIT, HTML parsing for novel formats
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
        
        // ViewInspector — for SwiftUI View testing (test-only, MIT)
        .package(url: "https://github.com/nalexn/ViewInspector.git", from: "0.10.0"),
    ],
    targets: [
        .target(
            name: "DuckReaderCore",
            dependencies: [
                .product(name: "ReadiumShared", package: "swift-toolkit"),
                .product(name: "ReadiumNavigator", package: "swift-toolkit"),
                .product(name: "ReadiumOPDS", package: "swift-toolkit"),
                .product(name: "ReadiumStreamer", package: "swift-toolkit"),
                "ZIPFoundation",
                "UnrarKit",
                "KeychainAccess",
                "Nuke",
                "SwiftSoup",
            ],
            path: ".",
            sources: [
                "Domain/",
                "Data/",
                "Core/",
                "Features/",
            ],
            resources: [
                .process("Resources/"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "DuckReaderWidgets",
            dependencies: [],
            path: "Widgets",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "DuckReaderTests",
            dependencies: [
                "DuckReaderCore",
                "ViewInspector",
            ],
            path: "Tests/DuckReaderTests"
        ),
        .testTarget(
            name: "DuckReaderUITests",
            dependencies: ["DuckReaderCore"],
            path: "Tests/DuckReaderUITests"
        ),
    ],
    swiftLanguageVersions: [.v6]
)
