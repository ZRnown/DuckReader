import Foundation
import SwiftUI

// MARK: - Duck 个性化引擎
/// 成就皮肤、阅读小动画、弹性 Duck 元素
/// 纯 UI 层叠加，不影响性能，增加用户情感连接
@MainActor
final class DuckPersonalization: ObservableObject {
    // MARK: - Config
    struct Config {
        /// 是否启用阅读动画
        var enableReadingAnimations: Bool = true
        /// 是否在翻页时显示 Duck
        var showDuckOnPageTurn: Bool = true
        /// 是否显示成就弹窗
        var showAchievementPopup: Bool = true
    }

    var config: Config = Config()

    // MARK: - Types

    /// Duck 皮肤/外观
    enum DuckSkin: String, CaseIterable, Codable, Sendable {
        // 默认系列
        case classic = "经典黄鸭"
        case readingNerd = "书虫鸭"       // 戴眼镜
        case nightOwl = "夜猫鸭"         // 深色
        case mangaHero = "热血鸭"        // 漫画风
        case detective = "侦探鸭"        // 侦探帽+烟斗
        case chef = "大厨鸭"           // 厨师帽

        // 成就解锁系列
        case goldenDuck = "金色传说鸭"   // 阅读100本
        case spaceDuck = "太空鸭"        // 科幻/奇幻成就
        case samurai = "武士鸭"         // 日漫成就
        case ninja = "忍者鸭"          // 连续阅读30天
        case scholar = "进士鸭"         // 阅读100小时

        var isPremium: Bool {
            switch self {
            case .goldenDuck, .spaceDuck, .samurai, .ninja, .scholar: return true
            default: return false
            }
        }

        var emoji: String {
            switch self {
            case .classic:     return "\u{1F986}"  // 🦆
            case .readingNerd: return "\u{1F913}"  // 🤓
            case .nightOwl:    return "\u{1F989}"  // 🦉
            case .mangaHero:   return "\u{1F4A5}"  // 💥
            case .detective:   return "\u{1F575}"  // 🕵️
            case .chef:        return "\u{1F468}\u{200D}\u{1F373}"  // 👨‍🍳
            case .goldenDuck:  return "\u{2B50}"  // ⭐
            case .spaceDuck:   return "\u{1F680}"  // 🚀
            case .samurai:     return "\u{2694}"   // ⚔️
            case .ninja:       return "\u{1F977}"  // 🥷
            case .scholar:     return "\u{1F393}"  // 🎓
            }
        }
    }

    /// 阅读成就
    enum Achievement: String, CaseIterable, Codable, Sendable {
        case firstBook = "第一本书"
        case tenBooks = "小小书虫"
        case fiftyBooks = "博览群鸭"
        case hundredBooks = "鸭霸天下"
        case tenHours = "沉浸读者"
        case hundredHours = "学海无涯"
        case sevenDayStreak = "一周全勤"
        case thirtyDayStreak = "自律达人"
        case manhuaLover = "漫画迷"
        case novelMaster = "小说家"
        case nightReader = "暗夜读者"       // 凌晨0-5点阅读
        case speedReader = "一目十行"        // 阅读速度快
        case collector = "藏书家"            // 库里有50+本

        var skinReward: DuckSkin? {
            switch self {
            case .hundredBooks:        return .goldenDuck
            case .thirtyDayStreak:     return .ninja
            case .hundredHours:        return .scholar
            case .manhuaLover:         return .samurai
            default:                   return nil
            }
        }
    }

    struct AchievementState: Codable, Sendable {
        let achievement: Achievement
        var progress: Double  // 0...1
        var unlockedAt: Date?
        var isNew: Bool       // 新解锁未查看

        var isUnlocked: Bool { progress >= 1.0 }
    }

    struct DuckAnimation {
        enum AnimationType: Sendable {
            case bounce          // 弹跳
            case flip            // 翻滚（翻页用）
            case wiggle          // 摇摆（加载）
            case celebrate       // 庆祝（成就解锁）
            case sleep           // 打盹（长时间没翻页）
            case peek            // 探头（章节结束）
            case cheerWithConfetti // 撒花
        }
    }

    // MARK: - State
    @Published var activeSkin: DuckSkin = .classic
    @Published var availableSkins: [DuckSkin] = [.classic, .readingNerd, .nightOwl, .mangaHero, .detective, .chef]
    @Published var achievements: [Achievement: AchievementState] = [:]
    @Published var showAchievement: Achievement?
    @Published var duckAnimation: DuckAnimation.AnimationType?
    @Published var duckPosition: CGPoint = .zero

    // MARK: - Public API

    /// 初始化所有成就（从持久化数据加载）
    func loadAchievements(_ states: [Achievement: AchievementState]) {
        achievements = states
    }

    /// 更新成就进度
    func updateProgress(_ achievement: Achievement, progress: Double) {
        var state = achievements[achievement] ?? AchievementState(
            achievement: achievement,
            progress: 0,
            unlockedAt: nil,
            isNew: false
        )

        let wasLocked = !state.isUnlocked
        state.progress = min(1.0, progress)

        if wasLocked && state.isUnlocked {
            state.unlockedAt = Date()
            state.isNew = true

            // 解锁皮肤
            if let skin = achievement.skinReward, !availableSkins.contains(skin) {
                availableSkins.append(skin)
            }

            // 弹窗
            if config.showAchievementPopup {
                showAchievement = achievement
                duckAnimation = .celebrate
            }
        }

        achievements[achievement] = state
    }

    /// 标记成就已查看
    func markAchievementSeen(_ achievement: Achievement) {
        achievements[achievement]?.isNew = false
        showAchievement = nil
    }

    /// 切换皮肤
    func selectSkin(_ skin: DuckSkin) {
        guard availableSkins.contains(skin) else { return }
        activeSkin = skin
    }

    /// 触发 Duck 动画
    func triggerAnimation(_ animation: DuckAnimation.AnimationType) {
        guard config.enableReadingAnimations else { return }
        duckAnimation = animation

        // 动画完成后自动清除
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            duckAnimation = nil
        }
    }

    /// 翻页时 — 选哪种动画
    func pageTurnAnimation(direction: Int) -> DuckAnimation.AnimationType {
        config.showDuckOnPageTurn ? .flip : .bounce
    }
}

// MARK: - SwiftUI Duck 视图

/// 可复用的 Duck 角色视图
struct DuckAvatarView: View {
    @ObservedObject var personalization: DuckPersonalization
    let size: CGFloat

    var body: some View {
        ZStack {
            // 底图 - Duck 皮肤
            Text(personalization.activeSkin.emoji)
                .font(.system(size: size * 0.6))
                .accessibilityLabel("Duck 阅读助手")

            // 动画叠加
            if let animation = personalization.duckAnimation {
                animationOverlay(for: animation)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: personalization.activeSkin)
    }

    @ViewBuilder
    private func animationOverlay(for animation: DuckPersonalization.DuckAnimation.AnimationType) -> some View {
        switch animation {
        case .bounce:
            EmptyView()  // 用 modifier 处理
        case .flip:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: size * 0.3))
                .foregroundColor(.orange)
        case .wiggle:
            Image(systemName: "ellipsis")
                .font(.system(size: size * 0.3))
                .foregroundColor(.secondary)
        case .celebrate:
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.4))
                .foregroundColor(.yellow)
        case .sleep:
            Text("\u{1F4A4}")
                .font(.system(size: size * 0.3))
        case .peek:
            Image(systemName: "eyes")
                .font(.system(size: size * 0.25))
        case .cheerWithConfetti:
            Image(systemName: "party.popper")
                .font(.system(size: size * 0.35))
        }
    }
}

/// 成就解锁弹窗
struct AchievementUnlockView: View {
    let achievement: DuckPersonalization.Achievement
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0

    var body: some View {
        VStack(spacing: 12) {
            Text("\u{1F389}")
                .font(.system(size: 40))

            Text("成就解锁！")
                .font(.headline)
                .fontWeight(.bold)

            Text(achievement.rawValue)
                .font(.title3)
                .multilineTextAlignment(.center)

            if let skin = achievement.skinReward {
                HStack(spacing: 4) {
                    Text(skin.emoji)
                    Text("新皮肤: \(skin.rawValue)")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.yellow.opacity(0.2))
                .clipShape(Capsule())
            }

            Button("太棒了") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(24)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 10)
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}

/// Duck 皮肤选择器
struct DuckSkinPicker: View {
    @ObservedObject var personalization: DuckPersonalization
    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(personalization.availableSkins, id: \.rawValue) { skin in
                VStack(spacing: 6) {
                    Text(skin.emoji)
                        .font(.system(size: 36))
                        .frame(width: 60, height: 60)
                        .background(
                            personalization.activeSkin == skin
                                ? Color.orange.opacity(0.2)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    personalization.activeSkin == skin
                                        ? Color.orange
                                        : Color.clear,
                                    lineWidth: 2
                                )
                        )

                    Text(skin.rawValue)
                        .font(.caption2)
                        .lineLimit(1)

                    if skin.isPremium {
                        Text("PRO")
                            .font(.system(size: 8))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
                .onTapGesture {
                    personalization.selectSkin(skin)
                }
            }
        }
    }
}
