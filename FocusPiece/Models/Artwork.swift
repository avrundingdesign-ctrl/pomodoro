import Foundation

/// A single public-domain artwork in the collection.
/// Images are bundled JPGs (see Scripts/fetch_artworks.sh); `assetName` is the
/// bundle resource base name. When the file is missing the UI shows a graceful
/// placeholder so the app still runs.
///
/// The text fields are resolved from the string catalog when the catalogue is
/// built, so the whole collection speaks the device language. That is also why
/// `Artwork` is deliberately **not** `Codable`: only `ArtworkProgress` is
/// persisted, and the wording always comes from the current translation.
struct Artwork: Identifiable, Equatable {
    let id: String
    let title: String
    /// Painter's name. Usually identical in every language, but the field is
    /// translated anyway — "Pieter Bruegel d. Ä." is "the Elder" in English.
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

    /// The persistable part of this work.
    var progress: ArtworkProgress {
        ArtworkProgress(id: id, unlocked: unlocked,
                        unlockedDate: unlockedDate, sessionMinutes: sessionMinutes)
    }

    /// A catalogue work with the user's progress applied.
    func applying(_ p: ArtworkProgress?) -> Artwork {
        guard let p else { return self }
        var copy = self
        copy.unlocked = p.unlocked
        copy.unlockedDate = p.unlockedDate
        copy.sessionMinutes = p.sessionMinutes
        return copy
    }
}

/// What a session earned for one work — the only artwork state that is stored.
///
/// Collections written before the texts were localized persisted the whole
/// `Artwork` (German title, blurb, …). Those keys are a superset of these, so
/// old payloads decode straight into this type and the wording is simply taken
/// from the catalogue again.
struct ArtworkProgress: Codable, Equatable {
    let id: String
    var unlocked: Bool = false
    var unlockedDate: Date? = nil
    var sessionMinutes: Int? = nil

    init(id: String, unlocked: Bool = false,
         unlockedDate: Date? = nil, sessionMinutes: Int? = nil) {
        self.id = id
        self.unlocked = unlocked
        self.unlockedDate = unlockedDate
        self.sessionMinutes = sessionMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        unlocked = try c.decodeIfPresent(Bool.self, forKey: .unlocked) ?? false
        unlockedDate = try c.decodeIfPresent(Date.self, forKey: .unlockedDate)
        sessionMinutes = try c.decodeIfPresent(Int.self, forKey: .sessionMinutes)
    }
}

extension Artwork {
    /// The eight Public-Domain works from the handoff (Wikimedia Commons).
    static let seedCollection: [Artwork] = [
        Artwork(id: "almond_blossom",
                title: String(localized: "Mandelblüte"),
                artist: "Vincent van Gogh", year: "1890",
                assetName: "Almond_blossom",
                collectionTag: String(localized: "Post-Impressionismus"),
                blurb: String(localized: "Ein blühender Mandelzweig vor leuchtendem Blau — gemalt als Geschenk zur Geburt von van Goghs Neffen. Ein Bild der Hoffnung und des Neubeginns.")),
        Artwork(id: "great_wave",
                title: String(localized: "Die große Welle"),
                artist: "Katsushika Hokusai", year: "1831",
                assetName: "Tsunami_by_hokusai_19th_century",
                collectionTag: String(localized: "Edo-Periode"),
                blurb: String(localized: "Eine gewaltige Welle türmt sich über kleinen Booten auf, während der Fuji in der Ferne ruht. Das wohl berühmteste japanische Kunstwerk der Welt.")),
        Artwork(id: "starry_night",
                title: String(localized: "Sternennacht"),
                artist: "Vincent van Gogh", year: "1889",
                assetName: "Van_Gogh_-_Starry_Night_-_Google_Art_Project",
                collectionTag: String(localized: "Post-Impressionismus"),
                blurb: String(localized: "Wirbelnde Sterne über einem ruhigen Dorf, gemalt aus der Erinnerung im Morgengrauen. Bewegung und Stille in einem einzigen Himmel.")),
        Artwork(id: "wanderer",
                title: String(localized: "Der Wanderer"),
                artist: "Caspar David Friedrich", year: "1818",
                assetName: "Caspar_David_Friedrich_-_Wanderer_above_the_sea_of_fog",
                collectionTag: String(localized: "Romantik"),
                blurb: String(localized: "Eine Gestalt blickt über ein Meer aus Nebel — Sinnbild der Selbstbetrachtung und der Erhabenheit der Natur.")),
        Artwork(id: "red_fuji",
                title: String(localized: "Roter Fuji"),
                artist: "Katsushika Hokusai", year: "1831",
                assetName: "Red_Fuji_southern_wind_clear_morning",
                collectionTag: String(localized: "Edo-Periode"),
                blurb: String(localized: "Der Fuji glüht im Licht eines klaren Spätsommermorgens. Aus derselben Serie wie die große Welle — Stille statt Sturm.")),
        Artwork(id: "impression_sunrise",
                title: String(localized: "Sonnenaufgang"),
                artist: "Claude Monet", year: "1872",
                assetName: "Claude_Monet,_Impression,_soleil_levant",
                collectionTag: String(localized: "Impressionismus"),
                blurb: String(localized: "Der Hafen von Le Havre im Morgendunst. Das Bild, das der gesamten Bewegung des Impressionismus ihren Namen gab.")),
        Artwork(id: "the_kiss",
                title: String(localized: "Der Kuss"),
                artist: "Gustav Klimt", year: "1908",
                assetName: "Gustav_Klimt_016",
                collectionTag: String(localized: "Wiener Secession"),
                blurb: String(localized: "Zwei Liebende, in Gold gehüllt, verschmelzen zu einer einzigen ornamentalen Form. Höhepunkt von Klimts „goldener Phase“.")),
        Artwork(id: "harvesters",
                title: String(localized: "Die Kornernte"),
                artist: String(localized: "Pieter Bruegel d. Ä."), year: "1565",
                assetName: "Pieter_Bruegel_the_Elder-_The_Harvesters_-_Google_Art_Project",
                collectionTag: String(localized: "Niederländische Renaissance"),
                blurb: String(localized: "Ein goldenes Erntefeld an einem schweren Sommertag. Eine der frühesten Landschaften, in der der Mensch Teil der Natur wird.")),
    ]
}
