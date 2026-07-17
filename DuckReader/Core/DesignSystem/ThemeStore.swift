import SwiftUI

// MARK: - App Theme Definition

/// A named visual theme for the app.
public struct AppTheme: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let accentColor: Color
    public let secondaryColor: Color
    public let backgroundColor: Color
    public let surfaceColor: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let isPremium: Bool

    public init(
        id: String,
        name: String,
        accent: Color,
        secondary: Color,
        background: Color,
        surface: Color,
        textPrimary: Color,
        textSecondary: Color,
        isPremium: Bool = false
    ) {
        self.id = id
        self.name = name
        self.accentColor = accent
        self.secondaryColor = secondary
        self.backgroundColor = background
        self.surfaceColor = surface
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.isPremium = isPremium
    }

    // MARK: - Built-in Themes

    public static let duckOrange = AppTheme(
        id: "duck_orange", name: "Duck Orange",
        accent: Color(red: 0.96, green: 0.56, blue: 0.19),
        secondary: Color(red: 0.94, green: 0.42, blue: 0.12),
        background: .white, surface: Color(uiColor: .systemGray6),
        textPrimary: .primary, textSecondary: .secondary
    )

    public static let oceanBlue = AppTheme(
        id: "ocean_blue", name: "Ocean Blue",
        accent: Color(red: 0.0, green: 0.48, blue: 1.0),
        secondary: Color(red: 0.0, green: 0.35, blue: 0.8),
        background: .white, surface: Color(uiColor: .systemGray6),
        textPrimary: .primary, textSecondary: .secondary
    )

    public static let forestGreen = AppTheme(
        id: "forest_green", name: "Forest Green",
        accent: Color(red: 0.2, green: 0.68, blue: 0.32),
        secondary: Color(red: 0.13, green: 0.52, blue: 0.22),
        background: .white, surface: Color(uiColor: .systemGray6),
        textPrimary: .primary, textSecondary: .secondary
    )

    public static let cherryRose = AppTheme(
        id: "cherry_rose", name: "Cherry Rose",
        accent: Color(red: 0.88, green: 0.18, blue: 0.35),
        secondary: Color(red: 0.71, green: 0.11, blue: 0.24),
        background: .white, surface: Color(uiColor: .systemGray6),
        textPrimary: .primary, textSecondary: .secondary
    )

    public static let midnightPurple = AppTheme(
        id: "midnight_purple", name: "Midnight Purple",
        accent: Color(red: 0.55, green: 0.18, blue: 0.85),
        secondary: Color(red: 0.40, green: 0.11, blue: 0.65),
        background: Color(uiColor: .systemBackground), surface: Color(uiColor: .systemGray6),
        textPrimary: .primary, textSecondary: .secondary
    )

    public static let sunsetGold = AppTheme(
        id: "sunset_gold", name: "Sunset Gold",
        accent: Color(red: 0.93, green: 0.62, blue: 0.0),
        secondary: Color(red: 0.75, green: 0.48, blue: 0.0),
        background: .white, surface: Color(uiColor: .systemGray6),
        textPrimary: .primary, textSecondary: .secondary
    )

    public static let darkNeon = AppTheme(
        id: "dark_neon", name: "Neon Dark",
        accent: Color(red: 0.0, green: 0.9, blue: 0.8),
        secondary: Color(red: 0.0, green: 0.7, blue: 0.6),
        background: Color(red: 0.08, green: 0.08, blue: 0.10),
        surface: Color(red: 0.14, green: 0.14, blue: 0.16),
        textPrimary: .white, textSecondary: .gray,
        isPremium: true
    )

    public static let sakuraPink = AppTheme(
        id: "sakura_pink", name: "Sakura",
        accent: Color(red: 1.0, green: 0.65, blue: 0.75),
        secondary: Color(red: 0.9, green: 0.45, blue: 0.55),
        background: Color(red: 1.0, green: 0.97, blue: 0.98),
        surface: Color(red: 0.99, green: 0.95, blue: 0.96),
        textPrimary: Color(red: 0.3, green: 0.1, blue: 0.15),
        textSecondary: Color(red: 0.5, green: 0.3, blue: 0.35),
        isPremium: true
    )

    public static let allThemes: [AppTheme] = [
        .duckOrange, .oceanBlue, .forestGreen, .cherryRose,
        .midnightPurple, .sunsetGold, .darkNeon, .sakuraPink
    ]
}

// MARK: - App Icon Definition

/// Catalog of all app icons available.
public struct AppIcon: Identifiable, Equatable, Sendable {
    public let id: String          // Asset catalog name (e.g. "AppIcon-Dark")
    public let name: String
    public let preview: String     // SFSymbol for preview
    public let isPremium: Bool
    public let isDefault: Bool

    public init(
        id: String,
        name: String,
        preview: String = "app.fill",
        isPremium: Bool = false,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.preview = preview
        self.isPremium = isPremium
        self.isDefault = isDefault
    }

    public static let allIcons: [AppIcon] = [
        AppIcon(id: "AppIcon", name: String(localized: "icon.default"), preview: "app.fill", isDefault: true),
        AppIcon(id: "AppIcon-Dark", name: String(localized: "icon.dark"), preview: "moon.fill"),
        AppIcon(id: "AppIcon-Orange", name: String(localized: "icon.orange"), preview: "sun.max.fill"),
        AppIcon(id: "AppIcon-Blue", name: String(localized: "icon.blue"), preview: "drop.fill"),
        AppIcon(id: "AppIcon-Green", name: String(localized: "icon.green"), preview: "leaf.fill"),
        AppIcon(id: "AppIcon-Purple", name: String(localized: "icon.purple"), preview: "sparkles", isPremium: true),
        AppIcon(id: "AppIcon-Gold", name: String(localized: "icon.gold"), preview: "star.fill", isPremium: true),
        AppIcon(id: "AppIcon-Mono", name: String(localized: "icon.mono"), preview: "circle.fill", isPremium: true),
    ]
}

// MARK: - Theme Store

@MainActor
public final class ThemeStore: ObservableObject, Sendable {
    @Published public var currentTheme: AppTheme = .duckOrange
    @Published public var currentIcon: AppIcon = AppIcon.allIcons[0]
    @Published public var isPremiumUnlocked: Bool = false

    private let defaults = UserDefaults.standard

    public nonisolated init() {
        Task { @MainActor in self.load() }
    }

    public func setTheme(_ theme: AppTheme) {
        guard !theme.isPremium || isPremiumUnlocked else { return }
        currentTheme = theme
        save()
    }

    public func setIcon(_ icon: AppIcon) async {
        guard !icon.isPremium || isPremiumUnlocked else { return }
        guard UIApplication.shared.supportsAlternateIcons else { return }

        let iconName = icon.isDefault ? nil : icon.id
        do {
            try await UIApplication.shared.setAlternateIconName(iconName)
            currentIcon = icon
            save()
        } catch {
            print("[ThemeStore] Failed to set icon: \(error)")
        }
    }

    public func unlockPremium(_ unlocked: Bool) {
        isPremiumUnlocked = unlocked
        save()
    }

    public var availableThemes: [AppTheme] {
        AppTheme.allThemes.filter { !$0.isPremium || isPremiumUnlocked }
    }

    public var availableIcons: [AppIcon] {
        AppIcon.allIcons.filter { !$0.isPremium || isPremiumUnlocked }
    }

    // MARK: - Persistence

    private func save() {
        defaults.set(currentTheme.id, forKey: "app_theme_id")
        defaults.set(currentIcon.id, forKey: "app_icon_id")
        defaults.set(isPremiumUnlocked, forKey: "app_premium_unlocked")
    }

    private func load() {
        if let themeID = defaults.string(forKey: "app_theme_id"),
           let theme = AppTheme.allThemes.first(where: { $0.id == themeID }) {
            currentTheme = theme
        }
        if let iconID = defaults.string(forKey: "app_icon_id"),
           let icon = AppIcon.allIcons.first(where: { $0.id == iconID }) {
            currentIcon = icon
        }
        isPremiumUnlocked = defaults.bool(forKey: "app_premium_unlocked")
    }
}

// MARK: - App Icon Picker View

public struct AppIconPicker: View {
    @ObservedObject var themeStore: ThemeStore
    let columns = [GridItem(.adaptive(minimum: 80), spacing: 16)]

    public init(themeStore: ThemeStore) {
        self.themeStore = themeStore
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(themeStore.availableIcons) { icon in
                Button {
                    Task { await themeStore.setIcon(icon) }
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(.quaternary)
                                .frame(width: 64, height: 64)

                            Image(systemName: icon.preview)
                                .font(.title)
                                .foregroundColor(themeStore.currentTheme.accentColor)
                        }
                        .overlay(alignment: .topTrailing) {
                            if icon.isPremium {
                                Image(systemName: "crown.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .offset(x: 6, y: -4)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(themeStore.currentIcon.id == icon.id ? themeStore.currentTheme.accentColor : .clear, lineWidth: 2.5)
                        )

                        Text(icon.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Theme Color Picker View

public struct ThemeColorPicker: View {
    @ObservedObject var themeStore: ThemeStore

    public init(themeStore: ThemeStore) {
        self.themeStore = themeStore
    }

    public var body: some View {
        HStack(spacing: 16) {
            ForEach(themeStore.availableThemes) { theme in
                Button {
                    themeStore.setTheme(theme)
                } label: {
                    ZStack {
                        Circle()
                            .fill(theme.accentColor.gradient)
                            .frame(width: 36, height: 36)

                        if themeStore.currentTheme.id == theme.id {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }

                        if theme.isPremium {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.orange)
                                .offset(x: 8, y: -14)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Environment Key

public struct ThemeStoreKey: EnvironmentKey {
    public static let defaultValue: ThemeStore = ThemeStore()
}

public extension EnvironmentValues {
    var themeStore: ThemeStore {
        get { self[ThemeStoreKey.self] }
        set { self[ThemeStoreKey.self] = newValue }
    }
}
