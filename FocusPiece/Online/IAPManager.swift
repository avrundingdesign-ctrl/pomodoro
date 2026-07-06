import Foundation
import StoreKit

/// StoreKit-2-Anbindung für Münz-Käufe (Consumables). Im Simulator/Debug
/// laufen echte Kauf-Flows über die FocusPiece.storekit-Konfiguration; in
/// Produktion kommen dieselben Produkt-IDs aus App Store Connect.
@MainActor
final class IAPManager: ObservableObject {

    struct CoinProduct: Identifiable {
        let product: Product
        let coins: Int
        var id: String { product.id }
    }

    @Published private(set) var products: [CoinProduct] = []
    @Published private(set) var purchaseInFlight = false
    @Published var lastError: String?

    /// Wird nach erfolgreichem, verifiziertem Kauf mit (Münzen, Produktname)
    /// aufgerufen — das OnlineModel schreibt sie der Wallet gut.
    var onCoinsPurchased: ((Int, String) -> Void)?

    /// Produkt-ID → enthaltene Münzen. Muss mit FocusPiece.storekit und
    /// App Store Connect übereinstimmen.
    static let productCoins: [String: Int] = [
        "com.focuspiece.coins.small": 300,
        "com.focuspiece.coins.medium": 800,
        "com.focuspiece.coins.large": 2000,
    ]

    /// Bereits gutgeschriebene Transaktions-IDs — schützt davor, dass ein Kauf
    /// über buy() UND Transaction.updates doppelt gutgeschrieben wird.
    private var grantedTransactionIDs: Set<UInt64> = []
    private var updatesTask: Task<Void, Never>?

    init() {
        // Unfertige Transaktionen (Unterbrechungen, Ask to Buy) einsammeln.
        updatesTask = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                await self?.grant(update)
            }
        }
        Task { await self.loadProducts() }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        do {
            let store = try await Product.products(for: Set(Self.productCoins.keys))
            products = store
                .compactMap { p in Self.productCoins[p.id].map { CoinProduct(product: p, coins: $0) } }
                .sorted { $0.coins < $1.coins }
        } catch {
            // Ohne StoreKit-Konfiguration (z. B. CI) bleibt der Store leer;
            // die UI zeigt dann einen Hinweis statt der Kauf-Knöpfe.
            products = []
        }
    }

    func buy(_ item: CoinProduct) async {
        guard !purchaseInFlight else { return }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            let result = try await item.product.purchase()
            switch result {
            case .success(let verification):
                await grant(verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = "Der Kauf konnte nicht abgeschlossen werden."
        }
    }

    /// Einziger Gutschrift-Pfad: verifizieren, deduplizieren, gutschreiben, abschließen.
    private func grant(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        if let coins = Self.productCoins[transaction.productID],
           transaction.revocationDate == nil,
           !grantedTransactionIDs.contains(transaction.id) {
            grantedTransactionIDs.insert(transaction.id)
            onCoinsPurchased?(coins, transaction.productID)
        }
        await transaction.finish()
    }
}
