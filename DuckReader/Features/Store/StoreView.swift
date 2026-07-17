import SwiftUI
import StoreKit
import Observation

// MARK: - Enhanced Product IDs

/// 内购产品ID定义 — 3层结构
public enum ProductID: String, CaseIterable {
    // ---- Tier 1: Free (no IAP) ----
    // All basic reading features included

    // ---- Tier 2: Core Unlock (one-time, non-consumable) ----
    /// 核心版：解锁高级阅读模式、OPDS、元数据、备份
    case coreUnlock = "com.duckreader.core.unlock"

    // ---- Tier 3: Pro（终身买断，含全部） ----
    case lifetimePro = "com.duckreader.lifetime.pro"

    // ---- Tier 4: AI 订阅（月度/年度） ----
    case aiMonthly = "com.duckreader.ai.monthly"
    case aiYearly = "com.duckreader.ai.yearly"

    // ---- 云同步（月度） ----
    case cloudMonthly = "com.duckreader.cloud.monthly"

    // ---- 打赏 ----
    case tipSmall = "com.duckreader.tip.small"    // ¥6
    case tipMedium = "com.duckreader.tip.medium"  // ¥18
    case tipLarge = "com.duckreader.tip.large"    // ¥68

    // MARK: - Tier Groups

    public enum Tier: String, CaseIterable {
        case free
        case core
        case pro
        case ai
        case cloud

        public var displayName: String {
            switch self {
            case .free: String(localized: "store.tierFree")
            case .core: String(localized: "store.tierCore")
            case .pro: String(localized: "store.tierPro")
            case .ai: String(localized: "store.tierAI")
            case .cloud: String(localized: "store.tierCloud")
            }
        }

        public var color: Color {
            switch self {
            case .free: return .secondary
            case .core: return .blue
            case .pro: return .orange
            case .ai: return .purple
            case .cloud: return .teal
            }
        }
    }

    public var tier: Tier {
        switch self {
        case .coreUnlock: return .core
        case .lifetimePro: return .pro
        case .aiMonthly, .aiYearly: return .ai
        case .cloudMonthly: return .cloud
        case .tipSmall, .tipMedium, .tipLarge: return .free
        }
    }

    public var displayName: String {
        switch self {
        case .coreUnlock: String(localized: "store.coreUnlock")
        case .lifetimePro: String(localized: "store.lifetimePro")
        case .aiMonthly: String(localized: "store.aiMonthly")
        case .aiYearly: String(localized: "store.aiYearly")
        case .cloudMonthly: String(localized: "store.cloudMonthly")
        case .tipSmall: String(localized: "store.tipSmall")
        case .tipMedium: String(localized: "store.tipMedium")
        case .tipLarge: String(localized: "store.tipLarge")
        }
    }

    public var icon: String {
        switch self {
        case .coreUnlock: return "lock.open"
        case .lifetimePro: return "crown.fill"
        case .aiMonthly, .aiYearly: return "brain.head.profile"
        case .cloudMonthly: return "icloud"
        case .tipSmall: return "cup.and.saucer"
        case .tipMedium: return "birthday.cake"
        case .tipLarge: return "gift.fill"
        }
    }
}

// MARK: - Feature Map per Tier

/// Maps each tier to the features it unlocks.
public enum FeatureAccess: Sendable {
    public struct Feature: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let description: String
        public let icon: String
    }

    public static func features(for tier: ProductID.Tier) -> [Feature] {
        switch tier {
        case .free:
            return [
                Feature(id: "basic_reader", name: String(localized: "feature.basicReader"), description: String(localized: "feature.basicReaderDesc"), icon: "book"),
                Feature(id: "local_import", name: String(localized: "feature.localImport"), description: String(localized: "feature.localImportDesc"), icon: "square.and.arrow.down"),
                Feature(id: "manga_single", name: String(localized: "feature.mangaSingle"), description: String(localized: "feature.mangaSingleDesc"), icon: "rectangle.grid.1x2"),
                Feature(id: "basic_panels", name: String(localized: "feature.basicPanels"), description: String(localized: "feature.basicPanelsDesc"), icon: "rectangle.3.group"),
            ]
        case .core:
            return FeatureAccess.features(for: .free) + [
                Feature(id: "all_modes", name: String(localized: "feature.allModes"), description: String(localized: "feature.allModesDesc"), icon: "rectangle.split.3x1"),
                Feature(id: "opds_support", name: String(localized: "feature.opdsSupport"), description: String(localized: "feature.opdsSupportDesc"), icon: "network"),
                Feature(id: "advanced_meta", name: String(localized: "feature.advancedMeta"), description: String(localized: "feature.advancedMetaDesc"), icon: "info.circle"),
                Feature(id: "backup", name: String(localized: "feature.backup"), description: String(localized: "feature.backupDesc"), icon: "arrow.triangle.2.circlepath"),
                Feature(id: "smart_lists", name: String(localized: "feature.smartLists"), description: String(localized: "feature.smartListsDesc"), icon: "list.star"),
                Feature(id: "gesture_custom", name: String(localized: "feature.gestureCustom"), description: String(localized: "feature.gestureCustomDesc"), icon: "hand.tap"),
            ]
        case .pro:
            return FeatureAccess.features(for: .core) + [
                Feature(id: "ai_panels", name: String(localized: "feature.aiPanels"), description: String(localized: "feature.aiPanelsDesc"), icon: "sparkles"),
                Feature(id: "advanced_tts", name: String(localized: "feature.advancedTTS"), description: String(localized: "feature.advancedTTSDesc"), icon: "waveform"),
                Feature(id: "pencil", name: String(localized: "feature.pencil"), description: String(localized: "feature.pencilDesc"), icon: "applepencil"),
                Feature(id: "themes_all", name: String(localized: "feature.themesAll"), description: String(localized: "feature.themesAllDesc"), icon: "paintpalette"),
                Feature(id: "vocab", name: String(localized: "feature.vocab"), description: String(localized: "feature.vocabDesc"), icon: "character.book.closed"),
            ]
        case .ai:
            return [
                Feature(id: "ai_upscale", name: String(localized: "feature.aiUpscale"), description: String(localized: "feature.aiUpscaleDesc"), icon: "sparkle.magnifyingglass"),
                Feature(id: "ocr_translate", name: String(localized: "feature.ocrTranslate"), description: String(localized: "feature.ocrTranslateDesc"), icon: "character.bubble"),
                Feature(id: "ai_summary", name: String(localized: "feature.aiSummary"), description: String(localized: "feature.aiSummaryDesc"), icon: "doc.text.magnifyingglass"),
            ]
        case .cloud:
            return [
                Feature(id: "icloud_sync", name: String(localized: "feature.iCloudSync"), description: String(localized: "feature.iCloudSyncDesc"), icon: "icloud"),
                Feature(id: "webdav_sync", name: String(localized: "feature.webdavSync"), description: String(localized: "feature.webdavSyncDesc"), icon: "server.rack"),
                Feature(id: "cross_device", name: String(localized: "feature.crossDevice"), description: String(localized: "feature.crossDeviceDesc"), icon: "macbook.and.iphone"),
            ]
        }
    }
}

// MARK: - Store ViewModel

@MainActor
@Observable
public final class StoreViewModel: Sendable {
    public var products: [Product] = []
    public var purchasedProductIDs: Set<String> = []
    public var isLoading = false
    public var error: Error?
    public var selectedTier: ProductID.Tier?

    public var isCore: Bool {
        purchasedProductIDs.contains(ProductID.coreUnlock.rawValue)
    }

    public var isPro: Bool {
        purchasedProductIDs.contains(ProductID.lifetimePro.rawValue)
    }

    public var isAI: Bool {
        isPro || purchasedProductIDs.contains(ProductID.aiMonthly.rawValue) ||
        purchasedProductIDs.contains(ProductID.aiYearly.rawValue)
    }

    public var isCloud: Bool {
        isPro || purchasedProductIDs.contains(ProductID.cloudMonthly.rawValue)
    }

    private var updateListenerTask: Task<Void, Error>?

    public init() {}

    public func loadProducts() async {
        isLoading = true
        do {
            let productIDs = ProductID.allCases.map { $0.rawValue }
            products = try await Product.products(for: Set(productIDs))
        } catch {
            self.error = error
        }
        isLoading = false
    }

    public func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                purchasedProductIDs.insert(transaction.productID)
                await transaction.finish()
            }
        case .userCancelled: break
        case .pending: break
        @unknown default: break
        }
    }

    public func listenForTransactions() {
        updateListenerTask = Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await MainActor.run {
                        self.purchasedProductIDs.insert(transaction.productID)
                    }
                    await transaction.finish()
                }
            }
        }
    }

    public func restorePurchases() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                purchasedProductIDs.insert(transaction.productID)
            }
        }
    }
}

// MARK: - Tier Card View

struct TierCard: View {
    let tier: ProductID.Tier
    let products: [Product]
    let isPurchased: Bool
    let onPurchase: (Product) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(tier.displayName)
                    .font(.title3.bold())
                    .foregroundColor(tier.color)

                Spacer()

                if isPurchased {
                    Label(String(localized: "store.purchased"), systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.12), in: Capsule())
                }
            }

            Divider()

            ForEach(FeatureAccess.features(for: tier)) { feature in
                HStack(spacing: 12) {
                    Image(systemName: feature.icon)
                        .foregroundColor(tier.color)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.name)
                            .font(.subheadline.weight(.medium))
                        Text(feature.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if !isPurchased {
                ForEach(tierProducts, id: \.id) { product in
                    Button {
                        Task { await onPurchase(product) }
                    } label: {
                        HStack {
                            Text(product.displayName)
                            Spacer()
                            Text(product.displayPrice)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tier.color)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var tierProducts: [Product] {
        let ids: [ProductID] = {
            switch tier {
            case .core: return [.coreUnlock]
            case .pro: return [.lifetimePro]
            case .ai: return [.aiMonthly, .aiYearly]
            case .cloud: return [.cloudMonthly]
            case .free: return []
            }
        }()
        let rawIDs = Set(ids.map { $0.rawValue })
        return products.filter { rawIDs.contains($0.id) }
    }
}

// MARK: - Store View

public struct StoreView: View {
    @State private var viewModel = StoreViewModel()
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange.gradient)
                        Text(String(localized: "store.title"))
                            .font(.title.bold())
                        Text(String(localized: "store.subtitle"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)

                    // Privacy + No Ads badge
                    HStack(spacing: 16) {
                        Label(String(localized: "store.noAds"), systemImage: "nosign")
                        Label(String(localized: "store.noTracking"), systemImage: "eye.slash")
                        Label(String(localized: "store.privacyFirst"), systemImage: "hand.raised")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    // Tier Cards
                    TierCard(
                        tier: .core,
                        products: viewModel.products,
                        isPurchased: viewModel.isCore || viewModel.isPro,
                        onPurchase: { try? await viewModel.purchase($0) }
                    )

                    TierCard(
                        tier: .pro,
                        products: viewModel.products,
                        isPurchased: viewModel.isPro,
                        onPurchase: { try? await viewModel.purchase($0) }
                    )

                    TierCard(
                        tier: .ai,
                        products: viewModel.products,
                        isPurchased: viewModel.isAI,
                        onPurchase: { try? await viewModel.purchase($0) }
                    )

                    TierCard(
                        tier: .cloud,
                        products: viewModel.products,
                        isPurchased: viewModel.isCloud,
                        onPurchase: { try? await viewModel.purchase($0) }
                    )

                    // Tips
                    VStack(spacing: 12) {
                        Text(String(localized: "store.tipHeader"))
                            .font(.headline)
                        HStack(spacing: 12) {
                            ForEach([ProductID.tipSmall, .tipMedium, .tipLarge], id: \.rawValue) { tip in
                                if let product = viewModel.products.first(where: { $0.id == tip.rawValue }) {
                                    Button {
                                        Task { try? await viewModel.purchase(product) }
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: tip.icon)
                                                .font(.title2)
                                            Text(product.displayPrice)
                                                .font(.caption.bold())
                                        }
                                        .padding(12)
                                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Restore
                    Button(String(localized: "store.restorePurchases")) {
                        Task { await viewModel.restorePurchases() }
                    }
                    .font(.subheadline)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal)
            }
            .navigationTitle(Text(""))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "store.done")) { dismiss() }
                }
            }
        }
        .task {
            await viewModel.loadProducts()
            await viewModel.listenForTransactions()
        }
    }
}
