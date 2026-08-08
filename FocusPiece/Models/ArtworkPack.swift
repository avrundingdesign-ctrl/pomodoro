import Foundation

/// A themed set of artworks. The original eight works ship free; further sets
/// are one-time In-App purchases (non-consumable). Buying a set adds its works
/// to the collection *locked* — they are revealed through focus sessions, just
/// like the free ones.
struct ArtworkPack: Identifiable, Equatable {
    let id: String
    let title: String
    let tagline: String     // short italic subtitle under the title
    let blurb: String       // paywall description
    let productID: String?  // StoreKit product id; nil = free
    let works: [Artwork]

    var isFree: Bool { productID == nil }
    /// "4 Werke" / "4 works"
    var countLabel: String { String(localized: "\(works.count) Werke") }
}

/// The full catalogue: the free pack plus every purchasable set.
enum ArtworkCatalog {

    static let freePackID = "klassiker"

    // MARK: Free — the original eight
    static let freePack = ArtworkPack(
        id: freePackID,
        title: String(localized: "Klassiker"),
        tagline: String(localized: "Die Eröffnungssammlung"),
        blurb: String(localized: "Acht Meisterwerke zum Start — von der großen Welle bis zur Sternennacht."),
        productID: nil,
        works: Artwork.seedCollection)

    // MARK: Kaufbare Sets (Public Domain, Wikimedia Commons)

    static let impressionen = ArtworkPack(
        id: "impressionen",
        title: String(localized: "Impressionen"),
        tagline: String(localized: "Licht, Luft und flüchtige Momente"),
        blurb: String(localized: "Vier Hauptwerke des Impressionismus: Gärten in Giverny, ein Sonntag auf dem Montmartre, Regen über Paris und ein Sommertag im Wind."),
        productID: "com.focuspiece.app.pack.impressionen",
        works: [
            Artwork(id: "water_lilies",
                    title: String(localized: "Seerosen"), artist: "Claude Monet", year: "1906",
                    assetName: "Claude_Monet_-_Water_Lilies_-_1906,_Ryerson",
                    collectionTag: String(localized: "Impressionismus"),
                    blurb: String(localized: "Wasser, Licht und Blüten verschmelzen zu einer stillen Fläche ohne Horizont. Monets Garten in Giverny wurde sein größtes Motiv — und sein Lebenswerk."),
                    packID: "impressionen"),
            Artwork(id: "moulin_galette",
                    title: String(localized: "Tanz im Moulin de la Galette"), artist: "Pierre-Auguste Renoir", year: "1876",
                    assetName: "Pierre-Auguste_Renoir,_Le_Moulin_de_la_Galette",
                    collectionTag: String(localized: "Impressionismus"),
                    blurb: String(localized: "Ein Sonntagnachmittag auf dem Montmartre: Tanz, Gelächter und Sonnenflecken, die durch die Bäume fallen. Renoirs Hymne an das Pariser Leben."),
                    packID: "impressionen"),
            Artwork(id: "paris_rainy_day",
                    title: String(localized: "Straße in Paris an einem Regentag"), artist: "Gustave Caillebotte", year: "1877",
                    assetName: "Gustave_Caillebotte_-_Paris_Street;_Rainy_Day_-_Google_Art_Project",
                    collectionTag: String(localized: "Impressionismus"),
                    blurb: String(localized: "Regenglänzendes Pflaster, Schirme und das neue Paris der Boulevards — mit fast fotografischer Ruhe komponiert."),
                    packID: "impressionen"),
            Artwork(id: "woman_parasol",
                    title: String(localized: "Frau mit Sonnenschirm"), artist: "Claude Monet", year: "1875",
                    assetName: "Claude_Monet_-_Woman_with_a_Parasol_-_Madame_Monet_and_Her_Son_-_Google_Art_Project",
                    collectionTag: String(localized: "Impressionismus"),
                    blurb: String(localized: "Camille Monet auf einer Anhöhe, der Stoff im Sommerwind, das Gras voller Licht. Ein Augenblick, festgehalten in wenigen Minuten."),
                    packID: "impressionen"),
        ])

    static let goldenesZeitalter = ArtworkPack(
        id: "goldenes_zeitalter",
        title: String(localized: "Goldenes Zeitalter"),
        tagline: String(localized: "Stille Meister der Niederlande"),
        blurb: String(localized: "Vermeer und Rembrandt: vier Werke über Licht, Alltag und den Blick, der einen nicht mehr loslässt."),
        productID: "com.focuspiece.app.pack.goldenes_zeitalter",
        works: [
            Artwork(id: "pearl_earring",
                    title: String(localized: "Das Mädchen mit dem Perlenohrring"), artist: "Johannes Vermeer", year: "1665",
                    assetName: "1665_Girl_with_a_Pearl_Earring",
                    collectionTag: String(localized: "Goldenes Zeitalter"),
                    blurb: String(localized: "Ein Blick über die Schulter, ein Lichtpunkt auf der Perle — das „Mona Lisa des Nordens“ genannte Porträt lebt ganz vom Moment."),
                    packID: "goldenes_zeitalter"),
            Artwork(id: "milkmaid",
                    title: String(localized: "Dienstmagd mit Milchkrug"), artist: "Johannes Vermeer", year: "1658",
                    assetName: "Johannes_Vermeer_-_Het_melkmeisje_-_Google_Art_Project",
                    collectionTag: String(localized: "Goldenes Zeitalter"),
                    blurb: String(localized: "Milch fließt, Brot liegt bereit, das Fensterlicht fällt still herein. Vermeer erhebt eine Alltagsgeste zur Andacht."),
                    packID: "goldenes_zeitalter"),
            Artwork(id: "rembrandt_self",
                    title: String(localized: "Selbstbildnis"), artist: "Rembrandt van Rijn", year: "1660",
                    assetName: "Rembrandt_van_Rijn_-_Self-Portrait_-_Google_Art_Project",
                    collectionTag: String(localized: "Goldenes Zeitalter"),
                    blurb: String(localized: "Rembrandt betrachtet sich selbst ohne Schmeichelei: müde Augen, warmes Licht, große Ehrlichkeit. Eines von rund achtzig Selbstporträts."),
                    packID: "goldenes_zeitalter"),
            Artwork(id: "view_of_delft",
                    title: String(localized: "Ansicht von Delft"), artist: "Johannes Vermeer", year: "1661",
                    assetName: "Vermeer-view-of-delft",
                    collectionTag: String(localized: "Goldenes Zeitalter"),
                    blurb: String(localized: "Vermeers Heimatstadt nach einem Regenschauer: Wolken, Wasser, aufblitzende Dächer. Für Proust „das schönste Bild der Welt“."),
                    packID: "goldenes_zeitalter"),
        ])

    static let nachtstuecke = ArtworkPack(
        id: "nachtstuecke",
        title: String(localized: "Nachtstücke"),
        tagline: String(localized: "Vom Abendlicht bis zum Sternenhimmel"),
        blurb: String(localized: "Vier Nächte der Kunstgeschichte: eine Caféterrasse unter Sternen, Mondlicht am Meer, Feuerwerk über dem Fluss und die Rhône im Sternenglanz."),
        productID: "com.focuspiece.app.pack.nachtstuecke",
        works: [
            Artwork(id: "cafe_terrace",
                    title: String(localized: "Caféterrasse am Abend"), artist: "Vincent van Gogh", year: "1888",
                    assetName: "Vincent_Willem_van_Gogh_-_Cafe_Terrace_at_Night_(Yorck)",
                    collectionTag: String(localized: "Post-Impressionismus"),
                    blurb: String(localized: "Gaslicht strahlt gelb in die blaue Nacht von Arles. Ein Nachthimmel voller Sterne — gemalt ganz ohne Schwarz."),
                    packID: "nachtstuecke"),
            Artwork(id: "moonrise_sea",
                    title: String(localized: "Mondaufgang am Meer"), artist: "Caspar David Friedrich", year: "1822",
                    assetName: "Caspar_David_Friedrich_-_Mondaufgang_am_Meer_-_Google_Art_Project",
                    collectionTag: String(localized: "Romantik"),
                    blurb: String(localized: "Drei Gestalten auf einem Felsen, Segel in der Dämmerung, der Mond hinter Wolken. Sehnsucht, in Farbe gefasst."),
                    packID: "nachtstuecke"),
            Artwork(id: "nocturne_gold",
                    title: String(localized: "Nocturne in Schwarz und Gold"), artist: "James McNeill Whistler", year: "1875",
                    assetName: "Whistler_James_Nocturne_in_Black_and_Gold_The_Falling_Rocket_1875",
                    collectionTag: String(localized: "Tonalismus"),
                    blurb: String(localized: "Funken eines Feuerwerks fallen durch die Nacht über dem Themse-Ufer — Malerei an der Schwelle zur Abstraktion."),
                    packID: "nachtstuecke"),
            Artwork(id: "starry_rhone",
                    title: String(localized: "Sternennacht über der Rhône"), artist: "Vincent van Gogh", year: "1888",
                    assetName: "Starry_Night_Over_the_Rhone",
                    collectionTag: String(localized: "Post-Impressionismus"),
                    blurb: String(localized: "Gaslaternen spiegeln sich im Fluss, darüber der Große Wagen. Van Goghs erste große Sternennacht — ruhiger als ihre berühmte Schwester."),
                    packID: "nachtstuecke"),
        ])

    // MARK: Access
    static let packs: [ArtworkPack] = [freePack, impressionen, goldenesZeitalter, nachtstuecke]
    static var paidPacks: [ArtworkPack] { packs.filter { !$0.isFree } }
    static var allProductIDs: [String] { paidPacks.compactMap(\.productID) }

    static func pack(id: String) -> ArtworkPack? { packs.first { $0.id == id } }
    static func pack(productID: String) -> ArtworkPack? { packs.first { $0.productID == productID } }
    /// Map a set of StoreKit product ids to the pack ids they unlock.
    static func packIDs(forProducts productIDs: Set<String>) -> Set<String> {
        Set(productIDs.compactMap { pack(productID: $0)?.id })
    }
}
