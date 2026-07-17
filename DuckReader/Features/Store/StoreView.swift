import SwiftUI
import StoreKit
import Observation

// MARK: - Store Manager

/// 内购管理器：处理一次性买断和可选订阅。
/// Freemium 模式：基础本地阅读免费，高级功能一次性买断 ¥68-98。
@MainActor
@Observable
public final class StoreManager: Sendable {
    
    // MARK: - Product IDs
    
    public enum ProductID: String, CaseIterable {
        // 一次性买断
        case lifetimePro = "com.duckreader.lifetime.pro"
        
        // 可选订阅
        case aiMonthly = "com.duckreader.ai.monthly"
        case aiYearly = "com.duckreader.ai.yearly"
        
        // 打赏/咖啡
        case tipSmall = "com.duckreader.tip.small"    // ¥6
        case tipMedium = "com.duckreader.tip.medium"  // ¥18
        case tipLarge = "com.duckreader.tip.large"    // ¥68
        
        // 云同步订阅（可选，自建后端用户）
        case cloudMonthly = "com.duckreader.cloud.monthly"
    }
    
    @Published public private(set) var products: [Product] = []
    @Published public private(set) var purchasedProductIDs: Set<String> = []
    @Published public var isLoading = false
    @Published public var error: Error?
    
    public var isPro: Bool {
        purchasedProductIDs.contains(ProductID.lifetimePro.rawValue)
    }
    
    public var hasAIAccess: Bool {
        isPro || purchasedProductIDs.contains(ProductID.aiMonthly.rawValue) ||
        purchasedProductIDs.contains(ProductID.aiYearly.rawValue)
    }
    
    public var hasCloudSync: Bool {
        isPro || purchasedProductIDs.contains(ProductID.cloudMonthly.rawValue)
    }
    
    // MARK: - Init
    
    public init() {
        Task {
            await loadProducts()
            await listenForTransactions()
        }
    }
    
    // MARK: - Load Products
    
    public func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let productIDs = ProductID.allCases.map { $0.rawValue }
            products = try await Product.products(for: Set(productIDs))
            
            // Sort: lifetime first, then subscriptions, then tips
            products.sort { a, b in
                let orderA = productOrder(a.id)
                let orderB = productOrder(b.id)
                return orderA < orderB
            }
        } catch {
            self.error = error
        }
    }
    
    private func productOrder(_ id: String) -> Int {
        if id.contains("lifetime") { return 0 }
        if id.contains("ai") { return 1 }
        if id.contains("cloud") { return 2 }
        if id.contains("tip") { return 3 }
        return 4
    }
    
    // MARK: - Purchase
    
    public func purchase(_ product: Product) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await handlePurchased(transaction)
                
            case .userCancelled:
                break
                
            case .pending:
                // 等待家长审批等
                break
                
            @unknown default:
                break
            }
        } catch {
            self.error = error
        }
    }
    
    // MARK: - Restore Purchases
    
    public func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await AppStore.sync()
        } catch {
            self.error = error
        }
    }
    
    // MARK: - Private
    
    private func listenForTransactions() async {
        for await verification in Transaction.updates {
            guard let transaction = try? checkVerified(verification) else {
                continue
            }
            await handlePurchased(transaction)
        }
    }
    
    private func handlePurchased(_ transaction: Transaction) async {
        purchasedProductIDs.insert(transaction.productID)
        await transaction.finish()
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

enum StoreError: LocalizedError {
    case failedVerification
    
    var errorDescription: String? {
        switch self {
        case .failedVerification: L10n.storeVerificationFailed
        }
    }
}

// MARK: - Store View (Paywall)

public struct StoreView: View {
    @State private var storeManager: StoreManager
    @Environment(\.dismiss) private var dismiss
    
    public init(storeManager: StoreManager) {
        self._storeManager = State(initialValue: storeManager)
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.yellow)
                        
                        Text(L10n.storeUnlockPro)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text(L10n.storeLifetimePurchase)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 32)
                    
                    // Feature list
                    VStack(alignment: .leading, spacing: 16) {
                        FeatureRow(icon: "infinity", title: L10n.storeFeatureUnlimitedFormats, description: L10n.storeFeatureUnlimitedFormatsDesc)
                        FeatureRow(icon: "wand.and.stars", title: L10n.storeFeatureAIEnhance, description: L10n.storeFeatureAIEnhanceDesc)
                        FeatureRow(icon: "rectangle.split.3x3", title: L10n.storeFeaturePanelByPanel, description: L10n.storeFeaturePanelByPanelDesc)
                        FeatureRow(icon: "icloud", title: L10n.storeFeatureSync, description: L10n.storeFeatureCloudSyncDesc)
                        FeatureRow(icon: "text.bubble", title: L10n.storeFeatureTTS, description: L10n.storeFeatureTTSDesc)
                        FeatureRow(icon: "chart.bar", title: L10n.storeFeatureStats, description: L10n.storeFeatureStatsDesc)
                    }
                    .padding(.horizontal, 24)
                    
                    Divider()
                    
                    // Pricing
                    if storeManager.isLoading {
                        ProgressView(L10n.storeLoadingPrice)
                    } else if storeManager.products.isEmpty {
                        Text(L10n.storeNoProducts)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 12) {
                            // Lifetime
                            ForEach(storeManager.products.filter { $0.id.contains("lifetime") }) { product in
                                PurchaseButton(
                                    product: product,
                                    isHighlighted: true,
                                    action: { Task { await storeManager.purchase(product) } }
                                )
                            }
                            
                            // Subscriptions
                            ForEach(storeManager.products.filter { !$0.id.contains("lifetime") && !$0.id.contains("tip") }) { product in
                                PurchaseButton(
                                    product: product,
                                    isHighlighted: false,
                                    action: { Task { await storeManager.purchase(product) } }
                                )
                            }
                        }
                        
                        // Tips
                        if !storeManager.products.filter({ $0.id.contains("tip") }).isEmpty {
                            Text(L10n.storeTipCoffee)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.top, 16)
                            
                            HStack(spacing: 8) {
                                ForEach(storeManager.products.filter { $0.id.contains("tip") }) { product in
                                    TipButton(product: product) {
                                        Task { await storeManager.purchase(product) }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Restore
                    Button(L10n.storeRestore) {
                        Task { await storeManager.restorePurchases() }
                    }
                    .font(.subheadline)
                    .padding(.bottom, 32)
                    
                    // Legal
                    VStack(spacing: 4) {
                        Text(L10n.storeAgreement)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 4) {
                            Link(L10n.storeUserAgreement, destination: URL(string: "https://duckreader.app/terms")!)
                            Text("·")
                            Link(L10n.storePrivacyPolicy, destination: URL(string: "https://duckreader.app/privacy")!)
                        }
                        .font(.caption2)
                    }
                    .padding(.bottom)
                }
            }
            .navigationTitle(L10n.storeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.close) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Subviews

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 32)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct PurchaseButton: View {
    let product: Product
    let isHighlighted: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    Text(product.displayName)
                        .font(.headline)
                    Text(product.description)
                        .font(.caption)
                }
                
                Spacer()
                
                Text(product.displayPrice)
                    .font(.title3)
                    .fontWeight(.bold)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHighlighted ? Color.accentColor : Color(.systemGray6))
            )
            .foregroundColor(isHighlighted ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

private struct TipButton: View {
    let product: Product
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(emojiForPrice(product.displayPrice))
                    .font(.title)
                Text(product.displayPrice)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
    }
    
    private func emojiForPrice(_ price: String) -> String {
        if price.contains("6") { return "☕️" }
        if price.contains("18") { return "🍰" }
        if price.contains("68") { return "🍕" }
        return "❤️"
    }
}

#Preview {
    StoreView(storeManager: StoreManager())
}
