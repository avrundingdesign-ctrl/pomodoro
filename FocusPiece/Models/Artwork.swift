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

    // Mutable progress state
    var unlocked: Bool = false
    var unlockedDate: Date? = nil
    var sessionMinutes: Int? = nil

    /// "Vincent van Gogh · 1890"
    var attribution: String { "\(artist) · \(year)" }
}

extension Artwork {
    /// Public-Domain works (Wikimedia Commons) — the eight from the handoff
    /// plus later additions. New entries are merged into stored collections
    /// on launch (see AppModel), so the museum can grow with updates.
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
        Artwork(id: "pearl_earring",
                title: "Das Mädchen mit dem Perlenohrring", artist: "Johannes Vermeer", year: "1665",
                assetName: "Meisje_met_de_parel",
                collectionTag: "Goldenes Zeitalter",
                blurb: "Ein Blick über die Schulter, ein Lichtpunkt auf einer Perle — Vermeers rätselhaftes Porträt wird oft die „Mona Lisa des Nordens“ genannt."),
        Artwork(id: "the_scream",
                title: "Der Schrei", artist: "Edvard Munch", year: "1893",
                assetName: "Edvard_Munch,_1893,_The_Scream,_oil,_tempera_and_pastel_on_cardboard,_91_x_73_cm,_National_Gallery_of_Norway",
                collectionTag: "Expressionismus",
                blurb: "Ein glühender Himmel, eine Gestalt, die sich die Ohren zuhält — das wohl eindringlichste Bild moderner Angst, geboren aus einem Spaziergang bei Sonnenuntergang."),
        Artwork(id: "wheat_field_cypresses",
                title: "Weizenfeld mit Zypressen", artist: "Vincent van Gogh", year: "1889",
                assetName: "Vincent_van_Gogh_-_Wheat_Field_with_Cypresses_-_Google_Art_Project",
                collectionTag: "Post-Impressionismus",
                blurb: "Wogendes Korn, wirbelnde Wolken und dunkle Zypressen unter der Sommersonne der Provence — gemalt im selben Jahr wie die Sternennacht."),
        Artwork(id: "water_lilies",
                title: "Seerosen", artist: "Claude Monet", year: "1906",
                assetName: "Claude_Monet_-_Water_Lilies_-_Google_Art_Project_(462013)",
                collectionTag: "Impressionismus",
                blurb: "Kein Ufer, kein Horizont — nur Wasser, Licht und Blüten. Monets Garten in Giverny, verwandelt in reine Betrachtung."),
    ]
}
