import SwiftUI
import StoreKit

/// The shop sheet: themed artwork sets as one-time In-App purchases.
/// Bought works join the collection *locked* and are revealed through focus
/// sessions — the free eight works stay free.
struct PaywallView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: StoreModel
    @Environment(\.dismiss) private var dismiss

    @State private var message: PaywallMessage?
    @State private var restoring = false

    struct PaywallMessage: Identifiable {
        let id = UUID()
        let title: String
        let text: String
    }

    var body: some View {
        ZStack {
            Theme.Palette.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if store.productsUnavailable { unavailableNote }

                    ForEach(ArtworkCatalog.paidPacks) { pack in
                        PackCard(pack: pack,
                                 owned: app.ownedPackIDs.contains(pack.id),
                                 product: store.product(for: pack),
                                 busy: store.busyProductID == pack.productID) {
                            Task { await buy(pack) }
                        }
                    }

                    restoreButton
                    legalFooter
                }
                .padding(.horizontal, Theme.Pad.screenH)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
        }
        .alert(item: $message) { msg in
            Alert(title: Text(msg.title), message: Text(msg.text),
                  dismissButton: .default(Text("Okay")))
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NEUE WERKE").eyebrow()
                Spacer()
                CircleIconButton(systemName: "xmark") { dismiss() }
                    .accessibilityIdentifier("paywall.close")
            }
            Text("Sammlung erweitern")
                .font(Theme.Font.serif(30))
                .tracking(-0.3)
                .foregroundStyle(Theme.Palette.ink)
            Text("Kuratierte Sets aus gemeinfreien Meisterwerken. Einmal kaufen, dann wie gewohnt Werk für Werk durch Fokus enthüllen.")
                .font(Theme.Font.sans(14))
                .lineSpacing(4)
                .foregroundStyle(Theme.Palette.muted)
        }
    }

    private var unavailableNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preise konnten nicht geladen werden. Prüfe deine Verbindung — die Sets bleiben natürlich erhältlich.")
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Palette.muted)
            GhostButton(title: "Erneut laden", icon: "arrow.clockwise", height: 44) {
                Task { await store.refreshProducts() }
            }
        }
        .padding(16)
        .background(Theme.Palette.surface2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
    }

    private var restoreButton: some View {
        GhostButton(title: restoring ? "Wird wiederhergestellt…" : "Käufe wiederherstellen",
                    icon: "arrow.counterclockwise") {
            guard !restoring else { return }
            restoring = true
            Task {
                await store.restorePurchases()
                app.applyPurchasedProducts(store.purchasedProductIDs)
                restoring = false
                message = store.purchasedProductIDs.isEmpty
                    ? PaywallMessage(title: "Keine Käufe gefunden",
                                     text: "Mit dieser Apple-ID wurden noch keine Sets gekauft.")
                    : PaywallMessage(title: "Käufe wiederhergestellt",
                                     text: "Deine Sets sind wieder Teil der Sammlung.")
            }
        }
        .accessibilityIdentifier("paywall.restore")
    }

    private var legalFooter: some View {
        VStack(alignment: .center, spacing: 10) {
            Text("Einmalige Käufe — kein Abonnement. Die Abrechnung erfolgt über deine Apple-ID; Käufe lassen sich jederzeit auf Geräten mit derselben Apple-ID wiederherstellen. Bereits enthüllte Werke bleiben erhalten.")
                .font(Theme.Font.sans(12))
                .lineSpacing(3)
                .foregroundStyle(Theme.Palette.muted3)
                .multilineTextAlignment(.center)
            HStack(spacing: 18) {
                Link("Nutzungsbedingungen", destination: LegalLinks.terms)
                Link("Datenschutz", destination: LegalLinks.privacy)
            }
            .font(Theme.Font.sans(12, weight: .medium))
            .foregroundStyle(Theme.Palette.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    // MARK: Purchase flow

    private func buy(_ pack: ArtworkPack) async {
        guard let product = store.product(for: pack) else { return }
        switch await store.purchase(product) {
        case .success:
            app.applyPurchasedProducts(store.purchasedProductIDs)
            message = PaywallMessage(
                title: "Freigeschaltet",
                text: "„\(pack.title)“ gehört jetzt zu deiner Sammlung. Fokussiere, um die Werke zu enthüllen.")
        case .pending:
            message = PaywallMessage(
                title: "Kauf ausstehend",
                text: "Der Kauf wartet auf eine Bestätigung (z. B. „Bitten, um zu kaufen“). Die Werke erscheinen automatisch, sobald er genehmigt ist.")
        case .cancelled:
            break
        case .failed:
            message = PaywallMessage(
                title: "Kauf fehlgeschlagen",
                text: "Der Kauf konnte nicht abgeschlossen werden. Bitte versuch es später erneut.")
        }
    }
}

// MARK: - Pack card

private struct PackCard: View {
    let pack: ArtworkPack
    let owned: Bool
    let product: Product?
    let busy: Bool
    let onBuy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(pack.countLabel.uppercased() + " · EINMALIGER KAUF")
                    .font(Theme.Font.sans(10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Palette.muted3)
                Text(pack.title)
                    .font(Theme.Font.serif(23))
                    .foregroundStyle(Theme.Palette.ink)
                Text(pack.tagline)
                    .font(Theme.Font.serifItalic(14))
                    .foregroundStyle(Theme.Palette.artistInk)
            }

            Text(pack.blurb)
                .font(Theme.Font.sans(13.5))
                .lineSpacing(4)
                .foregroundStyle(Theme.Palette.bodySoft)

            VStack(spacing: 10) {
                ForEach(pack.works) { work in
                    HStack(spacing: 11) {
                        PackThumb(assetName: work.assetName, revealed: owned && work.unlocked)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(work.title)
                                .font(Theme.Font.sans(14, weight: .medium))
                                .foregroundStyle(Theme.Palette.ink)
                                .lineLimit(1)
                            Text(work.attribution)
                                .font(Theme.Font.sans(12))
                                .foregroundStyle(Theme.Palette.muted2)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            ctaButton
        }
        .padding(18)
        .background(Theme.Palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                .stroke(Theme.Palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
    }

    @ViewBuilder private var ctaButton: some View {
        if owned {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 14, weight: .semibold))
                Text("In deiner Sammlung").font(Theme.Font.sans(15, weight: .semibold))
            }
            .foregroundStyle(Theme.Palette.accent)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(Theme.Palette.surface2)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.primaryButton, style: .continuous))
        } else {
            Button {
                onBuy()
            } label: {
                Group {
                    if busy {
                        ProgressView().tint(.white)
                    } else if let product {
                        Text("Freischalten · \(product.displayPrice)")
                            .font(Theme.Font.sans(15, weight: .semibold))
                    } else {
                        Text("Preis wird geladen…")
                            .font(Theme.Font.sans(15, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(product == nil ? Theme.Palette.muted3Soft : Theme.Palette.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.primaryButton, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(product == nil || busy)
            .accessibilityIdentifier("paywall.buy.\(pack.id)")
        }
    }
}

/// Small veiled thumbnail — the work stays a promise until it is revealed.
private struct PackThumb: View {
    let assetName: String
    let revealed: Bool

    var body: some View {
        ZStack {
            ArtworkImage(assetName: assetName, contentMode: .fill)
            if !revealed {
                Rectangle().fill(.ultraThinMaterial)
                Theme.Palette.revealVeil
            }
        }
        .frame(width: 38, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
    }
}
