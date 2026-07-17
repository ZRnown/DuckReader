import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Widget Bundle

@main
struct DuckReaderWidgets: WidgetBundle {
    var body: some Widget {
        // Home Screen: medium & large
        ReadingProgressWidget()
        // Lock Screen: inline, circular, rectangular
        ReadingStatsLockWidget()
        // Dynamic Island: live activity for reading session
        if #available(iOSApplicationExtension 16.1, *) {
            ReadingSessionActivity()
        }
    }
}

// MARK: - Home Screen Widget — Reading Progress

struct ReadingProgressWidget: Widget {
    let kind = "com.duckreader.widget.progress"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ReadingProgressIntent.self,
            provider: ReadingProgressProvider()
        ) { entry in
            ReadingProgressWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("阅读进度")
        .description("显示当前阅读进度和连续天数")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Timeline Provider

struct ReadingProgressEntry: TimelineEntry {
    let date: Date
    let currentBook: String?
    let currentBookAuthor: String?
    let progress: Double
    let todayMinutes: Int
    let streak: Int
    let totalBooks: Int
    let readerLevel: String
}

struct ReadingProgressProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ReadingProgressEntry {
        ReadingProgressEntry(
            date: Date(),
            currentBook: "三体",
            currentBookAuthor: "刘慈欣",
            progress: 0.42,
            todayMinutes: 25,
            streak: 7,
            totalBooks: 12,
            readerLevel: "资深书友"
        )
    }

    func snapshot(for configuration: ReadingProgressIntent, in context: Context) async -> ReadingProgressEntry {
        fetchEntry()
    }

    func timeline(for configuration: ReadingProgressIntent, in context: Context) async -> Timeline<ReadingProgressEntry> {
        let entry = fetchEntry()
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
    }

    private func fetchEntry() -> ReadingProgressEntry {
        let defaults = UserDefaults(suiteName: "group.com.duckreader")

        return ReadingProgressEntry(
            date: Date(),
            currentBook: defaults?.string(forKey: "currentBook"),
            currentBookAuthor: defaults?.string(forKey: "currentBookAuthor"),
            progress: defaults?.double(forKey: "currentProgress") ?? 0,
            todayMinutes: defaults?.integer(forKey: "todayMinutes") ?? 0,
            streak: defaults?.integer(forKey: "currentStreak") ?? 0,
            totalBooks: defaults?.integer(forKey: "totalBooks") ?? 0,
            readerLevel: defaults?.string(forKey: "readerLevel") ?? "萌新读者"
        )
    }
}

// MARK: - Home Screen Widget View

struct ReadingProgressWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ReadingProgressEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        default:
            mediumView
        }
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            // Book cover placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(.orange.gradient.opacity(0.3))
                .overlay(
                    Image(systemName: "book.closed.fill")
                        .font(.title)
                        .foregroundStyle(.orange)
                )
                .frame(width: 72, height: 108)

            VStack(alignment: .leading, spacing: 8) {
                if let book = entry.currentBook {
                    Text(book)
                        .font(.headline)
                        .lineLimit(2)
                    if let author = entry.currentBookAuthor {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.quaternary)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.orange.gradient)
                                .frame(width: geo.size.width * entry.progress)
                        }
                    }
                    .frame(height: 6)
                    Text("\(Int(entry.progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("还没有在读的书")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Spacer(minLength: 0)

                // Stats row
                HStack(spacing: 12) {
                    Label("\(entry.todayMinutes)m", systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Label("\(entry.streak)d", systemImage: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Spacer()
                    Text(entry.readerLevel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(.orange)
                Text("哎鸭阅读器")
                    .font(.headline)
                Spacer()
                Text(entry.readerLevel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            Divider()

            if let book = entry.currentBook {
                // Current book
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.orange.gradient.opacity(0.2))
                        .frame(width: 56, height: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book).font(.subheadline.bold())
                        if let author = entry.currentBookAuthor {
                            Text(author).font(.caption).foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.orange.gradient)
                                    .frame(width: geo.size.width * entry.progress)
                            }
                        }
                        .frame(height: 5)
                        Text("\(Int(entry.progress * 100))% 已读")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            // Stats grid
            HStack(spacing: 0) {
                StatCell(title: "今日", value: "\(entry.todayMinutes)", unit: "分钟", color: .blue)
                Divider().frame(height: 40)
                StatCell(title: "连续", value: "\(entry.streak)", unit: "天", color: .orange)
                Divider().frame(height: 40)
                StatCell(title: "读过", value: "\(entry.totalBooks)", unit: "本", color: .green)
            }
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
    }
}

private struct StatCell: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(color)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Reading Progress Intent

struct ReadingProgressIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "阅读进度"
    static var description: IntentDescription = "显示当前阅读进度和统计"
}

// MARK: - Lock Screen Widgets

struct ReadingStatsLockWidget: Widget {
    let kind = "com.duckreader.widget.lock"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: ReadingProgressProvider()
        ) { entry in
            ReadingStatsLockEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("阅读统计")
        .description("锁屏显示今日阅读分钟")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}

struct ReadingStatsLockEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: ReadingProgressEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("阅读 \(entry.todayMinutes)分钟", systemImage: "book")
        case .accessoryCircular:
            Gauge(value: min(Double(entry.todayMinutes) / 60.0, 1.0)) {
                Image(systemName: "book.fill")
            } currentValueLabel: {
                Text("\(entry.todayMinutes)")
                    .font(.system(.caption, design: .rounded).bold())
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.orange)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "book.fill").foregroundStyle(.orange).font(.caption2)
                    Text("今日阅读").font(.caption2)
                }
                Text("\(entry.todayMinutes) 分钟")
                    .font(.headline.bold())
                if entry.streak > 0 {
                    Label("\(entry.streak)天", systemImage: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        default:
            Text("")
        }
    }
}

// MARK: - Dynamic Island / Live Activity — Reading Session

@available(iOSApplicationExtension 16.1, *)
struct ReadingSessionActivity: Widget {
    let kind = "com.duckreader.activity.session"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingSessionAttributes.self) { context in
            // Lock Screen banner
            VStack {
                HStack {
                    Image(systemName: "book.fill")
                    Text(context.attributes.bookTitle)
                        .font(.headline)
                    Spacer()
                    Text("\(context.state.currentPage)")
                        .font(.caption.monospacedDigit())
                    Text("/")
                        .font(.caption)
                    Text("\(context.state.totalPages)")
                        .font(.caption.monospacedDigit())
                }
                .padding(.horizontal)
                ProgressView(value: context.state.progress)
                    .tint(.orange)
                    .padding(.horizontal)
            }
            .padding(.vertical, 12)
            .activityBackgroundTint(.black.opacity(0.2))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "book.fill")
                        .foregroundStyle(.orange)
                        .font(.title3)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.currentPage) / \(context.state.totalPages)")
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.bookTitle)
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress)
                        .tint(.orange)
                }
            } compactLeading: {
                Image(systemName: "book.fill")
                    .foregroundStyle(.orange)
                    .font(.caption2)
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%")
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "book.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Reading Session Activity Attributes

@available(iOS 16.1, *)
public struct ReadingSessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currentPage: Int
        var totalPages: Int
        var progress: Double
    }

    var bookTitle: String
    var bookID: String
}
