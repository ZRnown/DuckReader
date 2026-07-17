// MARK: - Localized String Catalog (zh-Hans + en + ja)
// Keys match `Localizable.xcstrings`. Use `L10n.key` for user-facing strings.

import Foundation

public enum L10n {

    // General
    public static let appName = String(localized: "app.name")
    public static let appPro = String(localized: "app.pro")
    public static let ok = String(localized: "general.ok")
    public static let cancel = String(localized: "general.cancel")
    public static let done = String(localized: "general.done")
    public static let delete = String(localized: "general.delete")
    public static let edit = String(localized: "general.edit")
    public static let save = String(localized: "general.save")
    public static let close = String(localized: "general.close")
    public static let search = String(localized: "general.search")
    public static let loading = String(localized: "general.loading")
    public static let retry = String(localized: "general.retry")
    public static let next = String(localized: "general.next")
    public static let back = String(localized: "general.back")
    public static let confirm = String(localized: "general.confirm")
    public static let share = String(localized: "general.share")
    public static let select = String(localized: "general.select")
    public static let selectAll = String(localized: "general.selectAll")
    public static let importFiles = String(localized: "general.import")
    public static let exportFiles = String(localized: "general.export")
    public static let refresh = String(localized: "general.refresh")
    public static let error = String(localized: "general.error")
    public static let success = String(localized: "general.success")
    public static let noResults = String(localized: "general.noResults")

    // Library
    public static let libraryTitle = String(localized: "library.title")
    public static let librarySearch = String(localized: "library.searchPrompt")
    public static let libraryImport = String(localized: "library.importFiles")
    public static let libraryNoBooks = String(localized: "library.noBooks")
    public static let libraryAddFirst = String(localized: "library.addFirstBook")
    public static let librarySortTitle = String(localized: "library.sortByTitle")
    public static let librarySortAuthor = String(localized: "library.sortByAuthor")
    public static let librarySortRecent = String(localized: "library.sortByRecent")
    public static let libraryGridView = String(localized: "library.gridView")
    public static let libraryListView = String(localized: "library.listView")
    public static let libraryDeleteConfirm = String(localized: "library.deleteConfirm")
    public static let libraryDeleteTitle = String(localized: "library.deleteTitle")

    // Reader
    public static let readerContents = String(localized: "reader.contents")
    public static let readerBookmarks = String(localized: "reader.bookmarks")
    public static let readerAddBookmark = String(localized: "reader.addBookmark")
    public static let readerBookmarkAdded = String(localized: "reader.bookmarkAdded")
    public static let readerFontSize = String(localized: "reader.fontSize")
    public static let readerLineSpacing = String(localized: "reader.lineSpacing")
    public static let readerMargin = String(localized: "reader.margin")
    public static let readerFont = String(localized: "reader.font")
    public static let readerTheme = String(localized: "reader.theme")
    public static let readerThemeLight = String(localized: "reader.themeLight")
    public static let readerThemeDark = String(localized: "reader.themeDark")
    public static let readerThemeSepia = String(localized: "reader.themeSepia")
    public static let readerProgress = String(localized: "reader.progress")
    public static let readerZoom = String(localized: "reader.zoom")
    public static let readerFitWidth = String(localized: "reader.fitToWidth")
    public static let readerFitHeight = String(localized: "reader.fitToHeight")
    public static let readerDirection = String(localized: "reader.direction")
    public static let readerDirectionLTR = String(localized: "reader.directionLTR")
    public static let readerDirectionRTL = String(localized: "reader.directionRTL")
    public static let readerDirectionVert = String(localized: "reader.directionVertical")
    public static let readerTTSPlay = String(localized: "reader.ttsPlay")
    public static let readerTTSPause = String(localized: "reader.ttsPause")
    public static let readerTTSSpeed = String(localized: "reader.ttsSpeed")

    // Reader formatted strings
    public static func readerChapter(_ n: Int) -> String { String(localized: "reader.chapter \(n)") }
    public static func readerPage(_ n: Int) -> String { String(localized: "reader.page \(n)") }
    public static func readerPagesRemaining(_ n: Int) -> String { String(localized: "reader.pagesRemaining \(n)") }
    public static func readerTimeRemaining(_ n: Int) -> String { String(localized: "reader.timeRemaining \(n)") }

    // Settings
    public static let settingsTitle = String(localized: "settings.title")
    public static let settingsDisplay = String(localized: "settings.display")
    public static let settingsSync = String(localized: "settings.sync")
    public static let settingsPrivacy = String(localized: "settings.privacy")
    public static let settingsAbout = String(localized: "settings.about")
    public static let settingsLockApp = String(localized: "settings.lockApp")
    public static let settingsEnableLock = String(localized: "settings.enableLock")
    public static let settingsFaceID = String(localized: "settings.faceID")
    public static let settingsCloudSync = String(localized: "settings.cloudSync")
    public static let settingsWebDAV = String(localized: "settings.webdav")
    public static let settingsStorage = String(localized: "settings.storage")
    public static let settingsCacheSize = String(localized: "settings.cacheSize")
    public static let settingsClearCache = String(localized: "settings.clearCache")
    public static let settingsLanguage = String(localized: "settings.language")
    public static let settingsVersion = String(localized: "settings.version")

    // Stats
    public static let statsTotalReading = String(localized: "stats.totalReading")
    public static let statsToday = String(localized: "stats.todayReading")
    public static let statsWeek = String(localized: "stats.weeklyReading")
    public static let statsStreak = String(localized: "stats.streak")
    public static let statsBooksRead = String(localized: "stats.booksRead")
    public static let statsTotalPages = String(localized: "stats.totalPages")
    public static let statsTotalBookmarks = String(localized: "stats.totalBookmarks")
    public static let statsMinUnit = String(localized: "stats.minutes")
    public static let statsPageUnit = String(localized: "stats.pages")
    public static let statsDayUnit = String(localized: "stats.days")
    public static let statsBookUnit = String(localized: "stats.books")
    public static let statsBookmarkUnit = String(localized: "stats.bookmarks")

    // Achievements
    public static let achievementTitle = String(localized: "achievement.title")
    public static let achievementUnlocked = String(localized: "achievement.unlocked")
    public static let achievementLocked = String(localized: "achievement.locked")

    // Store
    public static let storeTitle = String(localized: "store.title")
    public static let storeUnlockPro = String(localized: "store.unlockPro")
    public static let storeRestore = String(localized: "store.restore")
    public static let storeFeatureSync = String(localized: "store.featureSync")
    public static let storeFeatureLock = String(localized: "store.featureLock")
    public static let storeFeatureAchieve = String(localized: "store.featureAchievement")
    public static let storeFeatureNetwork = String(localized: "store.featureNetwork")
    public static let storeFeatureStats = String(localized: "store.featureStats")
    public static let storeFeatureTTS = String(localized: "store.featureTTSSpeed")
    public static let storeFeatureFormats = String(localized: "store.featureFormats")

    // Privacy
    public static let privacyLockScreen = String(localized: "privacy.lockScreen")
    public static let privacyUnlockPrompt = String(localized: "privacy.unlockPrompt")
    public static let privacyUnlockPasscode = String(localized: "privacy.unlockPasscode")
    public static let privacyFaceIDReason = String(localized: "privacy.faceIDReason")

    // Network
    public static let networkBrowsing = String(localized: "network.browsing")
    public static let networkNoServices = String(localized: "network.noServices")
    public static let networkSMB = String(localized: "network.smbServer")
    public static let networkWebDAV = String(localized: "network.webdavServer")

    // Sync
    public static let syncUploading = String(localized: "sync.uploading")
    public static let syncDownloading = String(localized: "sync.downloading")
    public static let syncSynced = String(localized: "sync.synced")
    public static let syncFailed = String(localized: "sync.failed")
    public static let syncNotConfigured = String(localized: "sync.notConfigured")

    // Import
    public static let importScanning = String(localized: "import.scanning")
    public static let importSuccess = String(localized: "import.success")
    public static let importFailed = String(localized: "import.failed")
    public static let importUnsupported = String(localized: "import.unsupported")

    // Format labels
    public static let formatPDF = String(localized: "format.pdf")
    public static let formatEPUB = String(localized: "format.epub")
    public static let formatComic = String(localized: "format.comic")
    public static let formatTXT = String(localized: "format.txt")

    // Library (extra)
    public static let librarySortProgress = String(localized: "library.sortByProgress")
    public static let librarySortRecentAdded = String(localized: "library.sortByRecentAdded")
    public static let libraryRecentlyAdded = String(localized: "library.recentlyAdded")
    public static let libraryProgress = String(localized: "library.progress")

    // Privacy (extra)
    public static let privacyLocked = String(localized: "privacy.locked")
    public static let privacyUseBiometric = String(localized: "privacy.useBiometric")
    public static let privacyUsePasscode = String(localized: "privacy.usePasscode")
    public static let privacyAuthError = String(localized: "privacy.authError")
    public static let privacyBiometricPassword = String(localized: "privacy.biometricPassword")
    public static let privacyBiometricFaceID = String(localized: "privacy.biometricFaceID")
    public static let privacyBiometricTouchID = String(localized: "privacy.biometricTouchID")
    public static let privacyBiometricOpticID = String(localized: "privacy.biometricOpticID")
    public static let privacyUnlockBook = String(localized: "privacy.unlockBook")

    // Store (extra)
    public static let storeLifetimePurchase = String(localized: "store.lifetimePurchase")
    public static let storeLoadingPrice = String(localized: "store.loadingPrice")
    public static let storeNoProducts = String(localized: "store.noProducts")
    public static let storeTipCoffee = String(localized: "store.tipCoffee")
    public static let storeAgreement = String(localized: "store.agreement")
    public static let storeUserAgreement = String(localized: "store.userAgreement")
    public static let storePrivacyPolicy = String(localized: "store.privacyPolicy")
    public static let storeVerificationFailed = String(localized: "store.verificationFailed")
    public static let storeFeatureUnlimitedFormats = String(localized: "store.featureUnlimitedFormats")
    public static let storeFeatureUnlimitedFormatsDesc = String(localized: "store.featureUnlimitedFormatsDesc")
    public static let storeFeatureAIEnhance = String(localized: "store.featureAIEnhance")
    public static let storeFeatureAIEnhanceDesc = String(localized: "store.featureAIEnhanceDesc")
    public static let storeFeaturePanelByPanel = String(localized: "store.featurePanelByPanel")
    public static let storeFeaturePanelByPanelDesc = String(localized: "store.featurePanelByPanelDesc")
    public static let storeFeatureCloudSyncDesc = String(localized: "store.featureCloudSyncDesc")
    public static let storeFeatureTTSDesc = String(localized: "store.featureTTSDesc")
    public static let storeFeatureStatsDesc = String(localized: "store.featureStatsDesc")
    public static let storeFeatureFormatsDesc = String(localized: "store.featureFormatsDesc")

    // Format labels (extra)
    public static let formatRAR = String(localized: "format.rar")
    public static let formatZIP = String(localized: "format.zip")
    public static let formatCBZ = String(localized: "format.cbz")
    public static let formatMOBI = String(localized: "format.mobi")
    public static let formatAZW3 = String(localized: "format.azw3")
    public static let formatMD = String(localized: "format.md")
    public static let formatHTML = String(localized: "format.html")

    // Dashboard
    public static let dashTitle = String(localized: "dash.title")
    public static let dashTotalReading = String(localized: "dash.totalReading")
    public static let dashToday = String(localized: "dash.today")
    public static let dashWeek = String(localized: "dash.week")
    public static let dashStreak = String(localized: "dash.streak")
    public static let dashBooksRead = String(localized: "dash.booksRead")
    public static let dashTotalPages = String(localized: "dash.totalPages")
    public static let dashTotalBookmarks = String(localized: "dash.totalBookmarks")
    public static let dashAchievements = String(localized: "dash.achievements")
    public static let dashMinUnit = String(localized: "dash.minUnit")

    // Colors
    public static let colorBlue = String(localized: "color.blue")
    public static let colorPurple = String(localized: "color.purple")
    public static let colorGreen = String(localized: "color.green")
    public static let colorOrange = String(localized: "color.orange")
    public static let colorPink = String(localized: "color.pink")
    public static let colorTeal = String(localized: "color.teal")

    // App Icon options
    public static let iconDefault = String(localized: "icon.default")
    public static let iconDark = String(localized: "icon.dark")
    public static let iconClassic = String(localized: "icon.classic")
    public static let iconMinimal = String(localized: "icon.minimal")

    // Privacy settings extras
    public static let privacyLockImmediate = String(localized: "privacy.lockImmediate")
    public static let privacyLock1Min = String(localized: "privacy.lock1Min")
    public static let privacyLock5Min = String(localized: "privacy.lock5Min")
    public static let privacyLock15Min = String(localized: "privacy.lock15Min")
    public static let privacyUnknownError = String(localized: "privacy.unknownError")

    // Sync extras
    public static let syncSMB = String(localized: "sync.smbNAS")

    // Settings extras
    public static let settingsAppearance = String(localized: "settings.appearance")
    public static let settingsDefaultReading = String(localized: "settings.defaultReading")
    public static let settingsAccentColor = String(localized: "settings.accentColor")
    public static let settingsAppIcon = String(localized: "settings.appIcon")
    public static let settingsComicMode = String(localized: "settings.comicMode")
    public static let settingsAutoEnhance = String(localized: "settings.autoEnhance")
    public static let settingsAutoCropBorders = String(localized: "settings.autoCropBorders")
    public static let settingsPrivacyLockFaceID = String(localized: "settings.privacyLockFaceID")
    public static let settingsLockTimeout = String(localized: "settings.lockTimeout")
    public static let settingsEnableCloudSync = String(localized: "settings.enableCloudSync")
    public static let settingsSyncMethod = String(localized: "settings.syncMethod")
    public static let settingsCache = String(localized: "settings.cache")
    public static let settingsPrivacyPolicy = String(localized: "settings.privacyPolicy")
    public static let settingsUserAgreement = String(localized: "settings.userAgreement")
    public static let settingsLicenses = String(localized: "settings.licenses")

    // Fonts
    public static let fontSystem = String(localized: "font.system")
    public static let fontSongti = String(localized: "font.songti")
    public static let fontHeiti = String(localized: "font.heiti")
    public static let fontKaiti = String(localized: "font.kaiti")
    public static let fontSerif = String(localized: "font.serif")

    // Reader themes (extra)
    public static let readerThemePaper = String(localized: "reader.themePaper")
    public static let readerThemeGreen = String(localized: "reader.themeGreen")
    public static let readerFontSizeSmall = String(localized: "reader.fontSizeSmall")
    public static let readerFontSizeMedium = String(localized: "reader.fontSizeMedium")
    public static let readerFontSizeLarge = String(localized: "reader.fontSizeLarge")
    public static let readerFontSizeExtraLarge = String(localized: "reader.fontSizeExtraLarge")

    // Reader modes
    public static let readerModeSingle = String(localized: "reader.modeSinglePage")
    public static let readerModeDouble = String(localized: "reader.modeDoublePage")
    public static let readerModePanel = String(localized: "reader.modePanelByPanel")
    public static let readerModeScroll = String(localized: "reader.modeVerticalScroll")
    public static let readerDirectionRTLManga = String(localized: "reader.directionRTLManga")
    public static let readerDirectionLTRComic = String(localized: "reader.directionLTRComic")
    public static let readerDirectionVerticalWebtoon = String(localized: "reader.directionVerticalScroll")
    public static let readerFitBoth = String(localized: "reader.fitBoth")
    public static let readerGamepad = String(localized: "reader.gamepad")
    public static let readerNoBookOpen = String(localized: "reader.noBookOpen")
    public static let readerExitPanel = String(localized: "reader.exitPanelByPanel")
    public static let readerCannotLoadPage = String(localized: "reader.cannotLoadPage")
    public static let readerCannotLoadPanel = String(localized: "reader.cannotLoadPanel")
    public static let readerPanelCropFailed = String(localized: "reader.panelCropFailed")

    // Reader placeholder
    public static let readerPlaceholderContent = String(localized: "reader.placeholderContent")
}
