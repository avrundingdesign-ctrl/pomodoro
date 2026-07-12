import Foundation

/// A single public-domain artwork in the collection.
/// Images are bundled JPGs (see Scripts/fetch_artworks.sh); `assetName` is the
/// bundle resource base name. When the file is missing the UI shows a graceful
/// placeholder so the app still runs.
struct Artwork: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let artist: String
    let year: String
    let assetName: String        // e.g. "Almond_blossom" (bundled <assetName>.jpg)
    let collectionTag: String    // museal "Sammlung" tag, shown in detail
    let blurb: String            // short description for the detail screen
    /// The set this work belongs to (see ArtworkCatalog); the original eight
    /// works form the free "klassiker" pack.
    var packID: String = "klassiker"

    // Mutable progress state
    var unlocked: Bool = false
    var unlockedDate: Date? = nil
    var sessionMinutes: Int? = nil

    /// "Vincent van Gogh · 1890"
    var attribution: String { "\(artist) · \(year)" }
}

extension Artwork {
    /// Collections persisted before packs existed have no `packID`; decode
    /// those as members of the free pack instead of failing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        artist = try c.decode(String.self, forKey: .artist)
        year = try c.decode(String.self, forKey: .year)
        assetName = try c.decode(String.self, forKey: .assetName)
        collectionTag = try c.decode(String.self, forKey: .collectionTag)
        blurb = try c.decode(String.self, forKey: .blurb)
        packID = try c.decodeIfPresent(String.self, forKey: .packID) ?? ArtworkCatalog.freePackID
        unlocked = try c.decodeIfPresent(Bool.self, forKey: .unlocked) ?? false
        unlockedDate = try c.decodeIfPresent(Date.self, forKey: .unlockedDate)
        sessionMinutes = try c.decodeIfPresent(Int.self, forKey: .sessionMinutes)
    }
}

extension Artwork {
    /// The eight Public-Domain works from the handoff (Wikimedia Commons).
    static let seedCollection: [Artwork] = [
        Artwork(id: "almond_blossom",
                title: "Mandelblüte", artist: "Vincent van Gogh", year: "1890",
                assetName: "Almond_blossom",
                collectionTag: "Post-Impressionismus",
                blurb: "Ein blühender Mandelzweig vor leuchtendem Blau — gemalt als Geschenk zur Geburt von van Goghs Neffen. Ein Bild der Hoffnung und des Neubeginns."),
        Artwork(id: "great_wave",
                title: "Die große Welle", artist: "Katsushika Hokusai", year: "1831",
                assetName: "Tsunami_by_hokusai_19th_century",
                collectionTag: "Edo-Periode",
                blurb: "Eine gewaltige Welle türmt sich über kleinen Booten auf, während der Fuji in der Ferne ruht. Das wohl berühmteste japanische Kunstwerk der Welt."),
        Artwork(id: "starry_night",
                title: "Sternennacht", artist: "Vincent van Gogh", year: "1889",
                assetName: "Van_Gogh_-_Starry_Night_-_Google_Art_Project",
                collectionTag: "Post-Impressionismus",
                blurb: "Wirbelnde Sterne über einem ruhigen Dorf, gemalt aus der Erinnerung im Morgengrauen. Bewegung und Stille in einem einzigen Himmel."),
        Artwork(id: "wanderer",
                title: "Der Wanderer", artist: "Caspar David Friedrich", year: "1818",
                assetName: "Caspar_David_Friedrich_-_Wanderer_above_the_sea_of_fog",
                collectionTag: "Romantik",
                blurb: "Eine Gestalt blickt über ein Meer aus Nebel — Sinnbild der Selbstbetrachtung und der Erhabenheit der Natur."),
        Artwork(id: "red_fuji",
                title: "Roter Fuji", artist: "Katsushika Hokusai", year: "1831",
                assetName: "Red_Fuji_southern_wind_clear_morning",
                collectionTag: "Edo-Periode",
                blurb: "Der Fuji glüht im Licht eines klaren Spätsommermorgens. Aus derselben Serie wie die große Welle — Stille statt Sturm."),
        Artwork(id: "impression_sunrise",
                title: "Sonnenaufgang", artist: "Claude Monet", year: "1872",
                assetName: "Claude_Monet,_Impression,_soleil_levant",
                collectionTag: "Impressionismus",
                blurb: "Der Hafen von Le Havre im Morgendunst. Das Bild, das der gesamten Bewegung des Impressionismus ihren Namen gab."),
        Artwork(id: "the_kiss",
                title: "Der Kuss", artist: "Gustav Klimt", year: "1908",
                assetName: "Gustav_Klimt_016",
                collectionTag: "Wiener Secession",
                blurb: "Zwei Liebende, in Gold gehüllt, verschmelzen zu einer einzigen ornamentalen Form. Höhepunkt von Klimts „goldener Phase“."),
        Artwork(id: "harvesters",
                title: "Die Kornernte", artist: "Pieter Bruegel d. Ä.", year: "1565",
                assetName: "Pieter_Bruegel_the_Elder-_The_Harvesters_-_Google_Art_Project",
                collectionTag: "Niederländische Renaissance",
                blurb: "Ein goldenes Erntefeld an einem schweren Sommertag. Eine der frühesten Landschaften, in der der Mensch Teil der Natur wird."),
    ]
}
