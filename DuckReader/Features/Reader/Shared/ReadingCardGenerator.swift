import Foundation
import SwiftUI

// MARK: - Reading Card Generator

/// Generates shareable reading cards: progress snapshots, quotes, milestones,
/// all in Duck-themed visual style. Integrates with ImageProcessor for
/// optimized output.
@MainActor
public final class ReadingCardGenerator: ObservableObject, @unchecked Sendable {

    // MARK: - Card Templates

    public enum CardTemplate: String, Sendable, CaseIterable {
        case minimal     // Clean, book-cover forward
        case progress    // Progress bar + stats
        case quote       // Quote-centric, elegant
        case milestone   // Achievement/streak celebration
        case duck        // Duck mascot themed
    }

    public enum CardSize: Sendable {
        case square        // 1080×1080 (Instagram)
        case story         // 1080×1920 (Stories/Shorts)
        case wide          // 1200×630 (Twitter/X card)
        case custom(CGSize)

        var pixelSize: CGSize {
            switch self {
            case .square: CGSize(width: 1080, height: 1080)
            case .story:  CGSize(width: 1080, height: 1920)
            case .wide:   CGSize(width: 1200, height: 630)
            case .custom(let size): size
            }
        }

        var scaleFactor: CGFloat {
            pixelSize.width / 390 // Design at iPhone width
        }
    }

    // MARK: - Card Data

    public struct CardData: Sendable {
        public var bookTitle: String
        public var author: String?
        public var seriesName: String?
        public var coverImageData: Data?
        public var progress: Double        // 0.0–1.0
        public var totalPages: Int
        public var currentPage: Int
        public var quote: String?
        public var quoteAttribution: String?
        public var streakDays: Int?
        public var achievementName: String?
        public var readingTimeMinutes: Int?

        public init(
            bookTitle: String,
            author: String? = nil,
            seriesName: String? = nil,
            coverImageData: Data? = nil,
            progress: Double = 0,
            totalPages: Int = 0,
            currentPage: Int = 0,
            quote: String? = nil,
            quoteAttribution: String? = nil,
            streakDays: Int? = nil,
            achievementName: String? = nil,
            readingTimeMinutes: Int? = nil
        ) {
            self.bookTitle = bookTitle
            self.author = author
            self.seriesName = seriesName
            self.coverImageData = coverImageData
            self.progress = progress
            self.totalPages = totalPages
            self.currentPage = currentPage
            self.quote = quote
            self.quoteAttribution = quoteAttribution
            self.streakDays = streakDays
            self.achievementName = achievementName
            self.readingTimeMinutes = readingTimeMinutes
        }
    }

    // MARK: - Generation

    /// Generate a rendering of a reading card as a SwiftUI view.
    /// The caller renders this into a UIImage using ImageRenderer.
    @ViewBuilder
    public func cardView(for data: CardData, template: CardTemplate) -> some View {
        switch template {
        case .minimal:
            MinimalCardView(data: data)
        case .progress:
            ProgressCardView(data: data)
        case .quote:
            QuoteCardView(data: data)
        case .milestone:
            MilestoneCardView(data: data)
        case .duck:
            DuckCardView(data: data)
        }
    }

    /// Generate share text for the card (platform-appropriate).
    public func shareText(for data: CardData, template: CardTemplate) -> String {
        switch template {
        case .progress:
            let pct = Int(data.progress * 100)
            return String(localized: "card.shareProgress \(data.bookTitle) \(pct)%")
        case .quote:
            if let quote = data.quote {
                return "\"\(quote)\"\n— \(data.quoteAttribution ?? data.bookTitle)"
            }
            fallthrough
        case .milestone:
            if let achievement = data.achievementName {
                return String(localized: "card.shareAchievement \(achievement) \(data.bookTitle)")
            }
            fallthrough
        case .minimal, .duck:
            let authorPart = data.author.map { " by \($0)" } ?? ""
            return String(localized: "card.shareReading \(data.bookTitle)\(authorPart)")
        }
    }

    // MARK: - Export

    /// Export card as PNG data (caller provides ImageRenderer from SwiftUI).
    public func suggestedHashtags(for template: CardTemplate) -> [String] {
        var tags = ["DuckReader", "Reading"]
        switch template {
        case .quote:
            tags.append("QuoteOfTheDay")
        case .milestone:
            tags.append("ReadingMilestone")
        case .progress:
            tags.append("CurrentlyReading")
        case .minimal, .duck:
            tags.append("BookLover")
        }
        return tags
    }
}

// MARK: - Card Views

private struct MinimalCardView: View {
    let data: ReadingCardGenerator.CardData

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.1, blue: 0.2),
                         Color(red: 0.05, green: 0.05, blue: 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 24) {
                // Cover image or placeholder
                if let coverData = data.coverImageData,
                   let uiImage = UIImage(data: coverData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 200, height: 280)
                        .cornerRadius(12)
                        .shadow(radius: 10)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .frame(width: 200, height: 280)
                        .overlay(
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                        )
                }

                VStack(spacing: 8) {
                    Text(data.bookTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    if let author = data.author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                // DuckReader watermark
                HStack(spacing: 4) {
                    Image(systemName: "books.vertical.fill")
                        .font(.caption)
                    Text("DuckReader")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.white.opacity(0.5))
            }
            .padding(40)
        }
    }
}

private struct ProgressCardView: View {
    let data: ReadingCardGenerator.CardData

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.12, blue: 0.08) // Dark green

            VStack(spacing: 32) {
                Text(data.bookTitle)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                // Progress ring
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.15), lineWidth: 12)
                        .frame(width: 160, height: 160)

                    Circle()
                        .trim(from: 0, to: CGFloat(data.progress))
                        .stroke(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 160, height: 160)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 4) {
                        Text("\(Int(data.progress * 100))%")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.white)
                        Text(String(localized: "card.complete"))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                // Stats row
                HStack(spacing: 40) {
                    StatItem(value: "\(data.currentPage)", label: String(localized: "card.page"))
                    StatItem(value: "\(data.totalPages)", label: String(localized: "card.total"))
                    if let mins = data.readingTimeMinutes {
                        StatItem(value: "\(mins)", label: String(localized: "card.min"))
                    }
                }

                // Watermark
                Label("DuckReader", systemImage: "books.vertical.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(40)
        }
    }
}

private struct QuoteCardView: View {
    let data: ReadingCardGenerator.CardData

    var body: some View {
        ZStack {
            // Warm dark gradient
            LinearGradient(
                colors: [Color(red: 0.15, green: 0.08, blue: 0.05),
                         Color(red: 0.08, green: 0.04, blue: 0.02)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 24) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange.opacity(0.6))

                Text(data.quote ?? "")
                    .font(.system(.title2, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .italic()

                Image(systemName: "quote.closing")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange.opacity(0.6))

                VStack(spacing: 4) {
                    Text("— \(data.quoteAttribution ?? data.bookTitle)")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))

                    if let author = data.author {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Label("DuckReader", systemImage: "books.vertical.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(48)
        }
    }
}

private struct MilestoneCardView: View {
    let data: ReadingCardGenerator.CardData

    var body: some View {
        ZStack {
            // Celebration gradient
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.05, blue: 0.2),
                         Color(red: 0.05, green: 0.02, blue: 0.4)],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )

            VStack(spacing: 20) {
                // Trophy/achievement icon
                Image(systemName: "trophy.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                if let achievement = data.achievementName {
                    Text(achievement)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }

                Text(data.bookTitle)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))

                if let streak = data.streakDays {
                    HStack(spacing: 4) {
                        Text("\(streak)")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.orange)
                        Text(String(localized: "card.dayStreak"))
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }

                Label("DuckReader", systemImage: "books.vertical.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(40)
        }
    }
}

private struct DuckCardView: View {
    let data: ReadingCardGenerator.CardData

    var body: some View {
        ZStack {
            // Duck yellow
            Color(red: 0.95, green: 0.85, blue: 0.3)

            VStack(spacing: 16) {
                // Duck emoji as mascot (production would use a real asset)
                Text("🦆")
                    .font(.system(size: 80))

                Text(data.bookTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color(red: 0.2, green: 0.15, blue: 0.05))
                    .multilineTextAlignment(.center)

                if let author = data.author {
                    Text("by \(author)")
                        .font(.subheadline)
                        .foregroundStyle(.brown.opacity(0.7))
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.brown.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(.brown)
                            .frame(width: geo.size.width * CGFloat(data.progress), height: 8)
                    }
                }
                .frame(height: 8)
                .padding(.horizontal, 40)

                Text("\(Int(data.progress * 100))% read")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.brown)

                Text("DuckReader")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.brown.opacity(0.6))
            }
            .padding(40)
        }
    }
}

private struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// Preview helpers
#if DEBUG
import SwiftUI

struct ReadingCardGenerator_Previews: PreviewProvider {
    static var previews: some View {
        let data = ReadingCardGenerator.CardData(
            bookTitle: "The Great Adventure",
            author: "Jane Doe",
            progress: 0.42,
            totalPages: 320,
            currentPage: 134,
            quote: "Not all those who wander are lost.",
            quoteAttribution: "Chapter 7",
            streakDays: 12,
            readingTimeMinutes: 45
        )

        ScrollView {
            VStack(spacing: 20) {
                ForEach(ReadingCardGenerator.CardTemplate.allCases, id: \.rawValue) { template in
                    ReadingCardGenerator().cardView(for: data, template: template)
                        .frame(width: 390, height: 390)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(radius: 8)
                }
            }
            .padding()
        }
        .background(.black)
    }
}
#endif
