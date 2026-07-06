import SwiftUI

/// Store: Bilder-Pakete gegen Münzen freischalten und Münzen nachkaufen
/// (StoreKit 2). Gekaufte Werke landen GESPERRT in der Galerie — enthüllt
/// wird weiterhin nur durch Fokus.
struct StoreView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var online: OnlineModel

    @State private var confirmPack: ArtPack?
    @State private var unlockedPackName: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    earnCard

                    sectionTitle("Bilder-Pakete")
                    VStack(spacing: 14) {
                        ForEach(ArtPack.catalog) { pack in
                            PackCard(pack: pack,
                                     owned: online.owns(pack),
                                     coins: online.coins) {
                                confirmPack = pack
                            }
                        }
                    }

                    sectionTitle("Münzen kaufen")
                    coinShop
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.Palette.paper)
        .confirmationDialog(
            confirmPack.map { "„\($0.name)“ für \($0.priceCoins) Münzen freischalten?" } ?? "",
            isPresented: Binding(get: { confirmPack != nil },
                                 set: { if !$0 { confirmPack = nil } }),
            titleVisibility: .visible
        ) {
            if let pack = confirmPack {
                Button("Für \(pack.priceCoins) Münzen freischalten") { buy(pack) }
                Button("Abbrechen", role: .cancel) {}
            }
        } message: {
            Text("Die \(confirmPack?.artworks.count ?? 4) Werke erscheinen gesperrt in deiner Galerie — enthülle sie mit Fokus-Sessions.")
        }
        .alert("Paket freigeschaltet!", isPresented: Binding(
            get: { unlockedPackName != nil },
            set: { if !$0 { unlockedPackName = nil } })
        ) {
            Button("Zur Galerie") { app.selectedTab = .gallery }
            Button("Weiter stöbern", role: .cancel) {}
        } message: {
            Text("„\(unlockedPackName ?? "")“ wartet jetzt in deiner Galerie auf die Enthüllung.")
        }
    }

    private func buy(_ pack: ArtPack) {
        if online.purchase(pack) {
            Feedback.sessionCompleted(tone: app.settings.completionTone,
                                      haptics: app.settings.haptics)
            unlockedPackName = pack.name
        }
        confirmPack = nil
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Store")
                .font(Theme.Font.serif(32))
                .tracking(-0.3)
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            HStack(spacing: 7) {
                CoinBadge(size: 22)
                Text("\(online.coins)")
                    .font(Theme.Font.sans(16, weight: .bold))
                    .foregroundStyle(Theme.Palette.ink)
                    .monospacedDigit()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Theme.Palette.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.Palette.cardBorder, lineWidth: 1))
        }
        .padding(.horizontal, 28)
        .padding(.top, 8).padding(.bottom, 16)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Theme.Font.sans(11, weight: .semibold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Palette.muted3)
            .padding(.leading, 12)
    }

    // MARK: Verdienen

    private var earnCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("So verdienst du Münzen")
                .font(Theme.Font.sans(14, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
            earnRow(icon: "clock", text: "2 Münzen je 5 Minuten Fokus — jede Runde zählt")
            earnRow(icon: "checkmark.seal", text: "+\(CoinRules.cycleBonus) Bonus für einen kompletten Zyklus")
            earnRow(icon: "sunrise", text: "+\(CoinRules.firstOfDayBonus) für die erste Runde des Tages")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
    }

    private func earnRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 20)
            Text(text)
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Palette.muted)
        }
    }

    // MARK: Münz-Shop (StoreKit)

    @ViewBuilder private var coinShop: some View {
        if online.iap.products.isEmpty {
            Text("Münz-Pakete laden gerade nicht. Im Simulator: die App über Xcode starten (StoreKit-Konfiguration ist im Scheme hinterlegt).")
                .font(Theme.Font.sans(13))
                .foregroundStyle(Theme.Palette.muted2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                        .stroke(Theme.Palette.hairline2, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
        } else {
            VStack(spacing: 10) {
                ForEach(online.iap.products) { item in
                    coinRow(item)
                }
                if let error = online.iap.lastError {
                    Text(error)
                        .font(Theme.Font.sans(12))
                        .foregroundStyle(Theme.Palette.accent)
                }
                Text("Käufe laufen über den App Store (StoreKit). Münzen sind kein echtes Geld und werden nur in FocusPiece eingelöst.")
                    .font(Theme.Font.sans(11))
                    .foregroundStyle(Theme.Palette.muted3)
                    .padding(.top, 2)
            }
        }
    }

    private func coinRow(_ item: IAPManager.CoinProduct) -> some View {
        HStack(spacing: 13) {
            CoinBadge(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.product.displayName)
                    .font(Theme.Font.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("\(item.coins) Münzen")
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(Theme.Palette.muted2)
            }
            Spacer()
            Button {
                Task { await online.iap.buy(item) }
            } label: {
                Text(item.product.displayPrice)
                    .font(Theme.Font.sans(14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Theme.Palette.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(online.iap.purchaseInFlight)
            .opacity(online.iap.purchaseInFlight ? 0.5 : 1)
        }
        .padding(13)
        .background(Theme.Palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                .stroke(Theme.Palette.hairline2, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
    }
}

// MARK: - Paket-Karte

private struct PackCard: View {
    let pack: ArtPack
    let owned: Bool
    let coins: Int
    let onBuy: () -> Void

    private var affordable: Bool { coins >= pack.priceCoins }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 2×2-Mosaik der enthaltenen Werke.
            HStack(spacing: 2) {
                ForEach(pack.artworks.prefix(4)) { artwork in
                    Color.clear
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .overlay(
                            ArtworkImage(assetName: artwork.assetName, contentMode: .fill)
                                .saturation(owned ? 1 : 0.85)
                        )
                        .clipped()
                }
            }
            .frame(height: 110)
            .overlay(
                LinearGradient(colors: [Color(hex: pack.accentHex).opacity(0),
                                        Color(hex: pack.accentHex).opacity(owned ? 0 : 0.25)],
                               startPoint: .top, endPoint: .bottom)
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(pack.name)
                        .font(Theme.Font.serif(20, weight: .medium))
                        .foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    if owned {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                            Text("Freigeschaltet")
                                .font(Theme.Font.sans(12, weight: .semibold))
                        }
                        .foregroundStyle(Theme.Palette.success)
                    }
                }
                Text(pack.tagline)
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(pack.artworks.count) Werke · \(pack.artworks.map(\.artist).uniqued().joined(separator: ", "))")
                    .font(Theme.Font.sans(11))
                    .foregroundStyle(Theme.Palette.muted3)
                    .lineLimit(1)

                if !owned {
                    Button(action: onBuy) {
                        HStack(spacing: 8) {
                            CoinBadge(size: 18)
                            Text(affordable
                                 ? "Für \(pack.priceCoins) Münzen freischalten"
                                 : "Noch \(pack.priceCoins - coins) Münzen nötig")
                                .font(Theme.Font.sans(14, weight: .semibold))
                        }
                        .foregroundStyle(affordable ? .white : Theme.Palette.muted2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(affordable ? Theme.Palette.accent : Theme.Palette.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!affordable)
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .background(Theme.Palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.artCard, style: .continuous)
                .stroke(owned ? Theme.Palette.success.opacity(0.4) : Theme.Palette.hairline2, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.artCard, style: .continuous))
    }
}

private extension Array where Element: Hashable {
    /// Reihenfolge-erhaltendes Entdoppeln (Künstlerliste der Paket-Karte).
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
