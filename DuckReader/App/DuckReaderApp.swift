import SwiftUI
import SwiftData
import WidgetKit

// MARK: - Duck Reader App

@main
struct DuckReaderApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var swiftDataStack: SwiftDataStack?
    @State private var storeManager: StoreManager

    // Observable services — shared across the app
    @StateObject private var privacyLock = PrivacyLockManager.shared
    @StateObject private var achievementEngine = AchievementEngine.shared
    @StateObject private var statsEngine = ReadingStatsEngine.shared
    @StateObject private var cloudSync = CloudSyncService.shared
    @StateObject private var readingPresets = ReadingPresets()
    @StateObject private var translationBubble = AITranslationBubble()
    @StateObject private var scanAssistant = ScanAssistant()

    // Shared services
    private let archiveParser: ArchiveParser
    private let libraryRepository: LibraryRepository?

    init() {
        // Initialize data stack
        let stack: SwiftDataStack?
        do {
            stack = try SwiftDataStack()
        } catch {
            DuckLog.fault("Failed to initialize SwiftData: \(error.localizedDescription)", category: "App")
            stack = nil
        }
        self.swiftDataStack = stack

        // Initialize services
        let parser = ArchiveParser()
        self.archiveParser = parser

        if let stack {
            let repository = LibraryRepository(modelContext: stack.mainContext)
            self.libraryRepository = repository

            // Wire shared engines to the data store
            achievementEngine.configure(modelContext: stack.mainContext)
            statsEngine.configure(modelContext: stack.mainContext)
        } else {
            self.libraryRepository = nil
        }

        // Load persisted achievements
        // Defer to background to avoid blocking app launch
        Task.detached(priority: .low) { [achievementEngine] in
            achievementEngine.loadFromStore()
        }

        // Configure store
        self.storeManager = StoreManager()

        // Trigger background sync if privacy lock is off
        if !privacyLock.isAppLockEnabled {
            // Delay sync to avoid competing with app launch
            Task.detached(priority: .background) { [cloudSync] in
                try? await Task.sleep(for: .seconds(3))
                try? await cloudSync.sync()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let stack = swiftDataStack {
                Group {
                    if privacyLock.anyLockActive {
                        PrivacyLockScreenView()
                            .transition(.opacity)
                            .animation(DuckSpring.fluid, value: privacyLock.anyLockActive)
                    } else {
                        ContentView()
                            .environment(\.modelContext, stack.mainContext)
                            .environmentObject(achievementEngine)
                            .environmentObject(statsEngine)
                            .environmentObject(privacyLock)
                            .environmentObject(cloudSync)
                            .environmentObject(readingPresets)
                            .environmentObject(translationBubble)
                            .environmentObject(scanAssistant)
                    }
                }
                .modelContainer(stack.container)
            } else {
                SwiftDataErrorView()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // Lock app if privacy lock is enabled
                privacyLock.lockApp()

                // Trigger sync
                Task {
                    try? await cloudSync.sync()
                }

                // Refresh widget data
                WidgetDataBridge.shared.refresh(
                    progress: nil,
                    stats: statsEngine.stats,
                    level: achievementEngine.readerLevel
                )

            case .active:
                // Refresh stats when becoming active
                statsEngine.loadHistory()

            default:
                break
            }
        }
    }
}

// MARK: - Content View (Root Tab Bar)

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var statsEngine: ReadingStatsEngine
    @EnvironmentObject private var achievementEngine: AchievementEngine

    var body: some View {
        TabView {
            // Library Tab
            NavigationStack {
                LibraryView(
                    viewModel: LibraryViewModel(
                        repository: LibraryRepository(modelContext: modelContext),
                        parser: ArchiveParser(),
                        statsEngine: statsEngine,
                        achievementEngine: achievementEngine
                    )
                )
                .navigationTitle(L10n.Library.title)
            }
            .tabItem {
                Label(L10n.Library.title, systemImage: "books.vertical.fill")
            }

            // Stats Tab
            NavigationStack {
                ReadingStatsTabView(
                    statsEngine: statsEngine,
                    achievementEngine: achievementEngine
                )
                .navigationTitle(L10n.Achievements.stats)
            }
            .tabItem {
                Label(L10n.Achievements.stats, systemImage: "chart.bar.fill")
            }

            // Settings Tab
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(L10n.Settings.title, systemImage: "gearshape.fill")
            }
        }
        .tint(.orange)
    }
}

// MARK: - Reading Stats Tab View

private struct ReadingStatsTabView: View {
    @ObservedObject var statsEngine: ReadingStatsEngine
    @ObservedObject var achievementEngine: AchievementEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Reader Level Card
                readerLevelCard

                // Stats Grid
                statsGrid

                // Achievements
                achievementsSection
            }
            .padding(DuckLayout.screenHPadding)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var readerLevelCard: some View {
        VStack(spacing: 8) {
            Image(systemName: achievementEngine.readerLevel.icon)
                .font(.system(size: 48))
                .foregroundStyle(.orange.gradient)
                .padding(.bottom, 4)

            Text(achievementEngine.readerLevel.title)
                .font(DuckFont.largeTitle)

            Text("\(L10n.dashTotalReading) \(statsEngine.stats.totalMinutesRead) \(L10n.dashMinUnit)")
                .font(DuckFont.subhead)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .duckCard()
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            DuckStatCard(title: L10n.dashToday, value: "\(statsEngine.todayMinutes)", unit: L10n.dashMinUnit, icon: "clock.fill", color: .blue)
            DuckStatCard(title: L10n.dashWeek, value: "\(statsEngine.weeklyMinutes)", unit: L10n.dashMinUnit, icon: "calendar", color: .green)
            DuckStatCard(title: L10n.dashStreak, value: "\(statsEngine.currentStreak)", unit: L10n.statsDayUnit, icon: "flame.fill", color: .orange)
            DuckStatCard(title: L10n.dashBooksRead, value: "\(statsEngine.stats.totalBooksRead)", unit: L10n.statsBookUnit, icon: "checkmark.circle.fill", color: .purple)
            DuckStatCard(title: L10n.dashTotalPages, value: "\(statsEngine.stats.totalPagesRead)", unit: L10n.statsPageUnit, icon: "text.book.closed.fill", color: .teal)
            DuckStatCard(title: L10n.dashTotalBookmarks, value: "\(statsEngine.stats.totalBookmarks)", unit: L10n.statsBookmarkUnit, icon: "bookmark.fill", color: .pink)
        }
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.dashAchievements)
                .font(DuckFont.title2)
                .padding(.horizontal, 4)

            LazyVStack(spacing: 12) {
                ForEach(Array(achievementEngine.allAchievements.enumerated()), id: \.element.id) { idx, achievement in
                    AchievementRowView(achievement: achievement)
                        .duckStagger(index: idx)
                }
            }
        }
    }
}

// MARK: - Stat Card Component

private struct DuckStatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2.bold())
                Text(unit)
                    .font(DuckFont.caption1)
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(DuckFont.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .duckCard()
    }
}

// MARK: - Achievement Row Component

private struct AchievementRowView: View {
    let achievement: Achievement

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achievement.icon)
                .font(.title3)
                .foregroundStyle(achievement.isUnlocked ? achievement.tier.color : .gray.opacity(0.4))
                .frame(width: 40, height: 40)
                .background(
                    (achievement.isUnlocked ? achievement.tier.color : Color.gray.opacity(0.15))
                        .opacity(0.15),
                    in: RoundedRectangle(cornerRadius: DuckRadius.md)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.name)
                    .font(DuckFont.headline)
                Text(achievement.description)
                    .font(DuckFont.caption1)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if achievement.isUnlocked {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(achievement.tier.color)
                    .font(.title3)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.gray.opacity(0.3))
                    .font(.caption)
            }
        }
        .padding(16)
        .background(
            achievement.isUnlocked
                ? Material.ultraThinMaterial
                : Material.regularMaterial,
            in: RoundedRectangle(cornerRadius: DuckRadius.lg)
        )
    }
}

// MARK: - Preview Helper

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let stack = SwiftDataStack.preview()
        ContentView()
            .modelContainer(stack.container)
            .environmentObject(AchievementEngine.shared)
            .environmentObject(ReadingStatsEngine.shared)
            .environmentObject(PrivacyLockManager.shared)
            .environmentObject(CloudSyncService.shared)
    }
}
// MARK: - Fatal Error Fallback

private struct SwiftDataErrorView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("数据库初始化失败")
                .font(.title2).fontWeight(.semibold)
            Text("请重启应用。如果问题持续，请尝试重新安装。")
                .font(.body).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("重试") { exit(0) }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
#endif
