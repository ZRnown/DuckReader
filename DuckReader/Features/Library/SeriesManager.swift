import Foundation
import Combine

// MARK: - Series Manager

/// Deep series/volume management: auto-detect series from files/metadata,
/// track completeness, manage reading order, and group across formats.
///
/// Builds on SmartListManager's series grouping with advanced detection
/// and completeness tracking.
@MainActor
public final class SeriesManager: ObservableObject, @unchecked Sendable {

    @Published public private(set) var series: [SeriesGroup] = []
    @Published public private(set) var incompleteSeries: [SeriesGroup] = []

    // MARK: - Series Detection

    /// Configuration for series name detection from file names.
    public struct DetectionConfig: Sendable {
        /// Patterns that indicate a volume number separator.
        public var volumeSeparators: [String] = [
            "vol", "volume", "v", "第", "巻", "권", "tome", "band", "part",
            "book", "issue", "#", "ep", "episode", "ch", "chapter"
        ]

        /// Patterns for extracting series name (everything before volume indicator).
        /// Uses regex with named groups: (?<series>...) followed by (?<volume>...)
        public var regexPatterns: [String] = [
            #"^(?<series>.+?)\s+(?:vol\.?|volume)\s*\.?\s*(?<volume>\d+)"#,
            #"^(?<series>.+?)\s+(?:第|巻|권)\s*(?<volume>\d+)"#,
            #"^(?<series>.+?)\s+[vV](?<volume>\d+)"#,
            #"^(?<series>.+?)\s+#(?<volume>\d+)"#,
            #"^(?<series>.+?)\s+(?:tome|band|part|book|issue|ep|episode)\s*\.?\s*(?<volume>\d+)"#,
            #"^(?<series>.+?)\s+\((?<volume>\d+)\)"#,
            #"^(?<series>.+?)\s+\[(?<volume>\d+)\]"#,
            #"^(?<series>.+?)\s+-\s+(?<volume>\d+)"#,
            #"^(?<series>.+?)\s+(?<volume>\d{1,3})$"#,
        ]

        /// Minimum number of books to form a series.
        public var minBooksForSeries: Int = 2

        /// Fuzzy match threshold for series name grouping (Levenshtein distance ratio).
        public var fuzzyThreshold: Double = 0.85

        public init() {}
    }

    public var config: DetectionConfig = .init()

    // MARK: - Detection

    /// Auto-detect series from a list of books using file name patterns + metadata.
    public func detectSeries(from books: [SeriesBookInput]) -> [SeriesGroup] {
        var groups: [String: [SeriesBookInput]] = [:]

        // Phase 1: Use explicit metadata series name (highest confidence)
        for book in books {
            if let explicitSeries = book.metadataSeriesName {
                groups[explicitSeries, default: []].append(book)
            }
        }

        // Phase 2: Parse file names for implicit series
        let ungrouped = books.filter { $0.metadataSeriesName == nil }
        for book in ungrouped {
            if let (seriesName, _) = parseSeriesInfo(from: book.title) {
                // Check fuzzy match against existing groups
                if let matchKey = findFuzzyMatch(seriesName, in: Array(groups.keys)) {
                    groups[matchKey, default: []].append(book)
                } else {
                    groups[seriesName, default: []].append(book)
                }
            }
        }

        // Phase 3: Filter — only groups with ≥ minBooks
        let validGroups = groups
            .filter { $0.value.count >= config.minBooksForSeries }
            .map { (name, books) -> SeriesGroup in
                buildSeriesGroup(name: name, books: books)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        // Split into complete vs incomplete
        self.series = validGroups
        self.incompleteSeries = validGroups.filter { !$0.isComplete }

        return validGroups
    }

    // MARK: - Completeness Analysis

    /// For a series with known total volumes, calculate what's missing.
    public func completenessReport(for series: SeriesGroup) -> SeriesCompletenessReport {
        let volumes = series.volumes.compactMap(\.volumeNumber).sorted()
        guard volumes.count > 1 else {
            return SeriesCompletenessReport(
                seriesName: series.name,
                ownedCount: series.volumes.count,
                knownTotal: series.expectedTotalVolumes,
                missing: [],
                isComplete: false
            )
        }

        let minVol = volumes.first!
        let maxVol = series.expectedTotalVolumes.map { max($0, volumes.last!) } ?? volumes.last!

        let ownedSet = Set(volumes)
        let missing = stride(from: minVol, through: maxVol, by: 1)
            .filter { !ownedSet.contains($0) }
            .map { Double($0) }

        return SeriesCompletenessReport(
            seriesName: series.name,
            ownedCount: series.volumes.count,
            knownTotal: max(series.expectedTotalVolumes ?? maxVol, maxVol),
            missing: missing,
            isComplete: missing.isEmpty
        )
    }

    // MARK: - Reading Order

    /// Sort volumes by a specific order.
    public func sortedVolumes(_ volumes: [SeriesVolume], order: ReadingOrder) -> [SeriesVolume] {
        switch order {
        case .canonical:
            return volumes.sorted { ($0.volumeNumber ?? 0) < ($1.volumeNumber ?? 0) }
        case .publication:
            return volumes.sorted { ($0.pubDate ?? .distantPast) < ($1.pubDate ?? .distantPast) }
        case .chronological:
            return volumes.sorted { ($0.chronologicalOrder ?? $0.volumeNumber ?? 0) < ($1.chronologicalOrder ?? $1.volumeNumber ?? 0) }
        case .lastRead:
            return volumes.sorted { ($0.lastReadDate ?? .distantPast) > ($1.lastReadDate ?? .distantPast) }
        }
    }

    // MARK: - Format-Agnostic Grouping

    /// Group volumes across different formats (CBZ + EPUB of the same series).
    public func mergeFormatGroups(_ groups: [SeriesGroup]) -> [SeriesGroup] {
        var merged: [String: SeriesGroup] = [:]

        for group in groups {
            let key = group.name.lowercased()
            if var existing = merged[key] {
                var allVolumes = existing.volumes + group.volumes
                // Deduplicate by volume number
                var seen: Set<Double> = []
                allVolumes.removeAll { vol in
                    guard let num = vol.volumeNumber else { return false }
                    if seen.contains(num) { return true }
                    seen.insert(num)
                    return false
                }
                existing.volumes = allVolumes
                existing.formats.insert(group.primaryFormat)
                merged[key] = existing
            } else {
                merged[key] = group
            }
        }

        return Array(merged.values).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Helpers

    private func parseSeriesInfo(from title: String) -> (series: String, volume: Double)? {
        for pattern in config.regexPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(title.startIndex..<title.endIndex, in: title)
            if let match = regex.firstMatch(in: title, options: [], range: range) {
                let seriesRange = match.range(withName: "series")
                let volumeRange = match.range(withName: "volume")

                if seriesRange.location != NSNotFound,
                   volumeRange.location != NSNotFound,
                   let seriesRange = Range(seriesRange, in: title),
                   let volumeRange = Range(volumeRange, in: title) {
                    let seriesName = String(title[seriesRange]).trimmingCharacters(in: .whitespaces)
                    let volumeStr = String(title[volumeRange])
                    if let volume = Double(volumeStr) {
                        return (seriesName, volume)
                    }
                }
            }
        }
        return nil
    }

    private func findFuzzyMatch(_ candidate: String, in keys: [String]) -> String? {
        let lower = candidate.lowercased()
        // Simple prefix/substring match (production would use Levenshtein)
        for key in keys {
            let keyLower = key.lowercased()
            if keyLower == lower { return key }
            if keyLower.contains(lower) || lower.contains(keyLower) { return key }
        }
        return nil
    }

    private func buildSeriesGroup(name: String, books: [SeriesBookInput]) -> SeriesGroup {
        let volumes: [SeriesVolume] = books.map { book in
            let (_, parsedVolume) = parseSeriesInfo(from: book.title) ?? (nil, nil)

            return SeriesVolume(
                id: book.id,
                title: book.title,
                volumeNumber: book.metadataVolume ?? parsedVolume,
                format: book.format,
                coverURL: book.coverURL,
                progress: book.progress,
                lastReadDate: book.lastReadDate,
                pubDate: book.pubDate
            )
        }

        let allVolumeNums = volumes.compactMap(\.volumeNumber).sorted()
        let isComplete: Bool = {
            guard allVolumeNums.count > 1 else { return true }
            // A series is "complete" if volumes are consecutive from first to last owned
            let expected = stride(from: allVolumeNums.first!, through: allVolumeNums.last!, by: 1)
            return Set(allVolumeNums) == Set(expected)
        }()

        let formats = Set(books.compactMap(\.format))

        return SeriesGroup(
            name: name,
            volumes: volumes,
            primaryFormat: formats.first ?? "unknown",
            formats: formats,
            isComplete: isComplete,
            totalOwnedVolumes: volumes.count,
            expectedTotalVolumes: allVolumeNums.count > 1 ? allVolumeNums.last : nil,
            coverURL: books.first(where: { $0.coverURL != nil })?.coverURL
        )
    }
}

// MARK: - Models

/// A detected series with its volumes.
public struct SeriesGroup: Identifiable, Sendable {
    public let id = UUID()
    public var name: String
    public var volumes: [SeriesVolume]
    public var primaryFormat: String
    public var formats: Set<String>
    public var isComplete: Bool
    public var totalOwnedVolumes: Int
    public var expectedTotalVolumes: Double?
    public var coverURL: URL?

    /// Missing volume numbers (if any).
    public var missingVolumes: [Double] {
        let owned = Set(volumes.compactMap(\.volumeNumber))
        guard let maxVol = expectedTotalVolumes, maxVol > 0 else { return [] }
        return stride(from: 1, through: maxVol, by: 1)
            .filter { !owned.contains(Double($0)) }
            .map { Double($0) }
    }

    public var completenessPercent: Double {
        guard let total = expectedTotalVolumes, total > 0 else { return 1.0 }
        return min(1.0, Double(volumes.count) / total)
    }

    public var nextVolume: Double? {
        missingVolumes.sorted().first
    }
}

/// A single volume within a series.
public struct SeriesVolume: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let volumeNumber: Double?
    public let format: String?
    public let coverURL: URL?
    public let progress: Double
    public let lastReadDate: Date?
    public let pubDate: Date?
    public var chronologicalOrder: Double?

    public var volumeLabel: String {
        if let num = volumeNumber {
            return "Vol. \(String(format: "%g", num))"
        }
        return title
    }
}

/// Completeness analysis for a series.
public struct SeriesCompletenessReport: Sendable {
    public let seriesName: String
    public let ownedCount: Int
    public let knownTotal: Double?
    public let missing: [Double]
    public let isComplete: Bool

    public var missingLabels: [String] {
        missing.map { "Vol. \(String(format: "%g", $0))" }
    }

    public var summary: String {
        if isComplete {
            return String(localized: "series.complete \(ownedCount)")
        } else {
            let label = knownTotal.map { "/\(Int($0))" } ?? ""
            return String(localized: "series.missing \(ownedCount)\(label) \(missing.count)")
        }
    }
}

/// Reading order options.
public enum ReadingOrder: String, Sendable, CaseIterable {
    case canonical      // By volume number
    case publication    // By publication date
    case chronological  // By story chronology
    case lastRead       // By most recently read

    public var label: String {
        switch self {
        case .canonical:     String(localized: "series.order.canonical")
        case .publication:   String(localized: "series.order.publication")
        case .chronological: String(localized: "series.order.chronological")
        case .lastRead:      String(localized: "series.order.lastRead")
        }
    }
}

/// Lightweight book input for series detection.
public struct SeriesBookInput: Sendable {
    public let id: UUID
    public let title: String
    public let metadataSeriesName: String?
    public let metadataVolume: Double?
    public let format: String?
    public let coverURL: URL?
    public let progress: Double
    public let lastReadDate: Date?
    public let pubDate: Date?

    public init(
        id: UUID, title: String,
        metadataSeriesName: String? = nil,
        metadataVolume: Double? = nil,
        format: String? = nil,
        coverURL: URL? = nil,
        progress: Double = 0,
        lastReadDate: Date? = nil,
        pubDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.metadataSeriesName = metadataSeriesName
        self.metadataVolume = metadataVolume
        self.format = format
        self.coverURL = coverURL
        self.progress = progress
        self.lastReadDate = lastReadDate
        self.pubDate = pubDate
    }
}
