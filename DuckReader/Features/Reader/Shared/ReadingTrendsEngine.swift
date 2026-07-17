import Foundation
import SwiftUI
import Charts

// MARK: - 阅读趋势与统计增强引擎
/// 基于本地计算的阅读统计，Widget + Swift Charts 可视化
/// 纯本地计算，零网络消耗
@MainActor
final class ReadingTrendsEngine: ObservableObject {
    // MARK: - Types
    struct DailyReadingRecord: Codable, Sendable {
        let date: Date
        let pagesRead: Int
        let timeSpentSeconds: TimeInterval
        let genres: [String]
        let completionRate: Double  // 0...1
    }

    struct WeeklySummary: Codable, Sendable {
        let weekStartDate: Date
        let totalPages: Int
        let totalTimeHours: Double
        let topGenre: String
        let booksCompleted: Int
        let streakDays: Int
        let averageSessionMin: Double
    }

    struct ReadingHeatmapData: Identifiable, Sendable {
        let id: String  // "YYYY-MM-DD"
        let date: Date
        let pagesCount: Int
        let intensity: Double  // 0...1 热力值
    }

    struct GenrePreference: Identifiable, Sendable {
        let id: String
        let genre: String
        let percentage: Double
        let totalPages: Int
    }

    struct DuckRecommendation: Identifiable, Sendable {
        let id: UUID
        let title: String
        let reason: String
        let suggestedBookID: String?
    }

    // MARK: - State
    @Published var weeklySummary: WeeklySummary?
    @Published var heatmap: [ReadingHeatmapData] = []
    @Published var genrePreferences: [GenrePreference] = []
    @Published var dailyRecords: [DailyReadingRecord] = []
    @Published var currentStreak: Int = 0
    @Published var duckRecommendations: [DuckRecommendation] = []

    private let calendar = Calendar.current
    private let maxHeatmapDays = 90  // 展示最近90天热力图

    // MARK: - Public API

    /// 记录单日阅读
    func recordDaily(pages: Int, timeSpent: TimeInterval, genres: [String], completionRate: Double) {
        let today = calendar.startOfDay(for: Date())
        let record = DailyReadingRecord(
            date: today,
            pagesRead: pages,
            timeSpentSeconds: timeSpent,
            genres: genres,
            completionRate: completionRate
        )
        dailyRecords.append(record)
        recompute()
    }

    /// 从持久化数据加载
    func loadFromHistory(_ records: [DailyReadingRecord]) {
        dailyRecords = records
        recompute()
    }

    /// 生成今日 Widget 文本
    func widgetSummaryText() -> String {
        let summary = weeklySummary
        let today = dailyRecords.last

        var lines: [String] = []

        if let today {
            lines.append("今日已读 \(today.pagesRead) 页")
            let min = Int(today.timeSpentSeconds / 60)
            lines.append("阅读 \(min) 分钟")
        }

        if let summary {
            lines.append("本周共 \(summary.totalPages) 页")
            if summary.streakDays > 1 {
                lines.append("连续 \(summary.streakDays) 天阅读")
            }
        }

        return lines.joined(separator: " | ")
    }

    /// Widget 推荐 — 基于近期阅读习惯
    func generateDuckRecommendations() -> [DuckRecommendation] {
        var recs: [DuckRecommendation] = []

        // 推荐1: 基于 streak
        if currentStreak >= 3 {
            recs.append(DuckRecommendation(
                id: UUID(),
                title: "继续你的阅读长跑",
                reason: "已连续阅读 \(currentStreak) 天，保持下去！",
                suggestedBookID: nil
            ))
        }

        // 推荐2: 基于 genre
        if let topGenre = genrePreferences.first {
            recs.append(DuckRecommendation(
                id: UUID(),
                title: "发现更多 \(topGenre.genre) 作品",
                reason: "你最近最爱读 \(topGenre.genre)，占总阅读量的 \(Int(topGenre.percentage * 100))%",
                suggestedBookID: nil
            ))
        }

        // 推荐3: 低完成率提醒
        if let lastRecord = dailyRecords.last, lastRecord.completionRate < 0.3 {
            recs.append(DuckRecommendation(
                id: UUID(),
                title: "想换一本试试？",
                reason: "最近阅读完成率较低，也许可以试试别的书",
                suggestedBookID: nil
            ))
        }

        duckRecommendations = recs
        return recs
    }
}

// MARK: - Private Computation

private extension ReadingTrendsEngine {

    func recompute() {
        computeWeeklySummary()
        computeHeatmap()
        computeGenrePreferences()
        computeStreak()
    }

    func computeWeeklySummary() {
        let now = Date()
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else {
            return
        }

        let weekRecords = dailyRecords.filter { $0.date >= weekStart }

        let totalPages = weekRecords.reduce(0) { $0 + $1.pagesRead }
        let totalTime = weekRecords.reduce(0.0) { $0 + $1.timeSpentSeconds }
        let booksCompleted = weekRecords.filter { $0.completionRate >= 1.0 }.count

        // 热门 genre
        var genreCounter: [String: Int] = [:]
        for record in weekRecords {
            for genre in record.genres {
                genreCounter[genre, default: 0] += 1
            }
        }
        let topGenre = genreCounter.max(by: { $0.value < $1.value })?.key ?? "未分类"

        weeklySummary = WeeklySummary(
            weekStartDate: weekStart,
            totalPages: totalPages,
            totalTimeHours: totalTime / 3600,
            topGenre: topGenre,
            booksCompleted: booksCompleted,
            streakDays: currentStreak,
            averageSessionMin: weekRecords.isEmpty ? 0 : totalTime / Double(weekRecords.count) / 60
        )
    }

    func computeHeatmap() {
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -(maxHeatmapDays - 1), to: today)!

        // 聚合每日阅读量
        var pageCounts: [String: Int] = [:]
        for record in dailyRecords {
            let key = dateString(record.date)
            pageCounts[key, default: 0] += record.pagesRead
        }

        let maxPages = Double(pageCounts.values.max() ?? 1)

        // 生成热力图数据
        var date = startDate
        var heatmapData: [ReadingHeatmapData] = []

        while date <= today {
            let key = dateString(date)
            let pages = pageCounts[key] ?? 0
            heatmapData.append(ReadingHeatmapData(
                id: key,
                date: date,
                pagesCount: pages,
                intensity: maxPages > 0 ? Double(pages) / maxPages : 0
            ))
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }

        heatmap = heatmapData
    }

    func computeGenrePreferences() {
        var genrePages: [String: Int] = [:]
        var totalPages = 0

        for record in dailyRecords {
            for genre in record.genres {
                genrePages[genre, default: 0] += record.pagesRead
            }
            totalPages += record.pagesRead
        }

        genrePreferences = genrePages
            .map { GenrePreference(
                id: $0.key,
                genre: $0.key,
                percentage: totalPages > 0 ? Double($0.value) / Double(totalPages) : 0,
                totalPages: $0.value
            )}
            .sorted { $0.totalPages > $1.totalPages }
    }

    func computeStreak() {
        let today = calendar.startOfDay(for: Date())
        var streak = 0
        var date = today

        let dateSet = Set(dailyRecords.map { calendar.startOfDay(for: $0.date) })

        while dateSet.contains(date) {
            streak += 1
            date = calendar.date(byAdding: .day, value: -1, to: date)!
        }

        currentStreak = streak
    }

    func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Swift Charts Views

/// 阅读热力图 Swift Charts View
struct ReadingHeatmapView: View {
    @ObservedObject var engine: ReadingTrendsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("阅读热力图")
                .font(.headline)

            Chart(engine.heatmap) { day in
                RectangleMark(
                    x: .value("日期", day.date, unit: .day),
                    y: .value("页数", day.pagesCount)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.1),
                            Color.orange.opacity(day.intensity * 0.9 + 0.1),
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisTick()
                }
            }
            .frame(height: 160)
        }
    }
}

/// 阅读流派分布饼图
struct GenreDistributionView: View {
    @ObservedObject var engine: ReadingTrendsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("阅读偏好")
                .font(.headline)

            Chart(engine.genrePreferences) { pref in
                SectorMark(
                    angle: .value("占比", pref.totalPages),
                    innerRadius: .ratio(0.5),
                    angularInset: 1
                )
                .foregroundStyle(by: .value("类型", pref.genre))
            }
            .frame(height: 200)
        }
    }
}

/// 阅读周卡小视图（Widget 用）
struct WeeklyReadingCard: View {
    let summary: ReadingTrendsEngine.WeeklySummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                Text("本周阅读")
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            if let summary {
                Text("\(summary.totalPages) 页")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(String(format: "%.1f 小时", summary.totalTimeHours))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if summary.streakDays > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text("连续 \(summary.streakDays) 天")
                            .font(.caption2)
                    }
                }
            } else {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
