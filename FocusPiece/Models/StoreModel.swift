import Foundation
import StoreKit

/// StoreKit 2 storefront for the non-consumable artwork packs.
///
/// What Apple expects from a paid-content flow and where it lives here:
/// - localized prices from the App Store  → `products` / `Product.displayPrice`
/// - an explicit "Restore purchases" path → `restorePurchases()` (paywall & settings)
/// - handling deferred purchases          → `PurchaseOutcome.pending` (Ask to Buy)
/// - honoring refunds/revocations         → `refreshEntitlements()` skips revoked
/// - reacting to out-of-app transactions  → `Transaction.updates` listener
@MainActor
final class StoreModel: ObservableObject {

    enum PurchaseOutcome { case success, pending, cancelled, failed }

    /// Store products in catalogue order; empty until loaded.
    @Published private(set) var products: [Product] = []
    /// Verified, unrevoked non-consumable purchases.
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoadingProducts = false
    /// True when the App Store returned nothing (offline, missing setup).
    @Published private(set) var productsUnavailable = false
    /// Product id with a purchase in flight — drives button spinners.
    @Published private(set) var busyProductID: String?

    private var updatesTask: Task<Void, Never>?

    deinit { updatesTask?.cancel() }

    /// Call once at launch: listen for transaction updates, load products,
    /// and read the locally cached entitlements.
    func start() async {
        listenForTransactions()
        await refreshProducts()
        await refreshEntitlements()
    }

    func refreshProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: ArtworkCatalog.allProductIDs)
            products = ArtworkCatalog.allProductIDs.compactMap { id in
                loaded.first { $0.id == id }
            }
            productsUnavailable = products.isEmpty
        } catch {
            productsUnavailable = true
        }
    }

    func product(for pack: ArtworkPack) -> Product? {
        guard let id = pack.productID else { return nil }
        return products.first { $0.id == id }
    }

    @discardableResult
    func purchase(_ product: Product) async -> PurchaseOutcome {
        busyProductID = product.id
        defer { busyProductID = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return .failed }
                await transaction.finish()
                purchasedProductIDs.insert(transaction.productID)
                return .success
            case .pending:          // Ask to Buy / SCA — completes via Transaction.updates.
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    /// Re-sync with the App Store account. Required UI for non-consumables.
    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    /// Read the (locally cached) current entitlements — works offline.
    func refreshEntitlements() async {
        var owned = Set<String>()
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil else { continue }
            owned.insert(transaction.productID)
        }
        purchasedProductIDs = owned
    }

    /// Deferred approvals, purchases on other devices, refunds.
    private func listenForTransactions() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
    }
}
