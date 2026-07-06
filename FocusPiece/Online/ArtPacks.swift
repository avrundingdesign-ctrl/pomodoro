import Foundation

/// Ein käufliches Bilder-Paket. Die enthaltenen Werke landen nach dem Kauf
/// GESPERRT in der Sammlung — enthüllt wird weiterhin nur durch Fokus.
/// Bilder werden wie die Basis-Sammlung gebündelt (Scripts/fetch_artworks.sh);
/// fehlt eine Datei, greift der Platzhalter aus ArtworkImage.
struct ArtPack: Identifiable, Equatable {
    let id: String
    let name: String
    let tagline: String
    let priceCoins: Int
    let accentHex: UInt          // Farbwelt der Paket-Karte im Store
    let artworks: [Artwork]

    static let catalog: [ArtPack] = [
        ArtPack(
            id: "pack_japan",
            name: "Japanische Meister",
            tagline: "Holzschnitte von Hokusai & Hiroshige — Stille, Regen und Reisewege des alten Japan.",
            priceCoins: 180,
            accentHex: 0x4A6B8A,
            artworks: [
                Artwork(id: "jp_shono", title: "Regenschauer über Shōno", artist: "Utagawa Hiroshige", year: "1833",
                        assetName: "Hiroshige-53-Stations-Hoeido-46-Shono-Edo-Tokyo-M-01",
                        collectionTag: "Edo-Periode",
                        blurb: "Reisende fliehen vor einem plötzlichen Wolkenbruch — schräge Regenlinien machen das Wetter selbst zur Hauptfigur."),
                Artwork(id: "jp_kameido", title: "Pflaumengarten in Kameido", artist: "Utagawa Hiroshige", year: "1857",
                        assetName: "De_pruimenboomgaard_te_Kameido-Rijksmuseum_RP-P-1956-743",
                        collectionTag: "Edo-Periode",
                        blurb: "Ein blühender Pflaumenbaum füllt den Vordergrund — dieses Blatt bewunderte und kopierte später van Gogh."),
                Artwork(id: "jp_ohashi", title: "Abendregen über Ōhashi", artist: "Utagawa Hiroshige", year: "1857",
                        assetName: "Hiroshige_Atake_sous_une_averse_soudaine",
                        collectionTag: "Edo-Periode",
                        blurb: "Menschen ducken sich unter Schirmen über die große Brücke, während der Regen in feinen Nadeln fällt."),
                Artwork(id: "jp_kirifuri", title: "Kirifuri-Wasserfall", artist: "Katsushika Hokusai", year: "1832",
                        assetName: "Katsushika_Hokusai,_Japanese_-_Pilgrims_at_Kirifuri_Waterfall_on_Mount_Kurokami_in_Shimotsuke_Province_-_Google_Art_Project",
                        collectionTag: "Edo-Periode",
                        blurb: "Wasser stürzt in lebendigen Strängen den Fels hinab — Hokusais Wasserfälle wirken fast abstrakt."),
            ]),
        ArtPack(
            id: "pack_licht",
            name: "Impressionisten & Licht",
            tagline: "Flirrendes Sonnenlicht, Regentage in Paris und Momente, die nur eine Sekunde dauern.",
            priceCoins: 220,
            accentHex: 0x7A8E5A,
            artworks: [
                Artwork(id: "im_parasol", title: "Frau mit Sonnenschirm", artist: "Claude Monet", year: "1875",
                        assetName: "Claude_Monet_-_Woman_with_a_Parasol_-_Madame_Monet_and_Her_Son_-_Google_Art_Project",
                        collectionTag: "Impressionismus",
                        blurb: "Camille Monet auf einer Sommerwiese, von unten gesehen — Wind, Licht und Bewegung in einem Augenblick."),
                Artwork(id: "im_galette", title: "Bal du Moulin de la Galette", artist: "Pierre-Auguste Renoir", year: "1876",
                        assetName: "Pierre-Auguste_Renoir,_Le_Moulin_de_la_Galette",
                        collectionTag: "Impressionismus",
                        blurb: "Ein Sonntagnachmittag auf dem Montmartre: Tanz, Gelächter und Sonnenflecken, die durch die Bäume fallen."),
                Artwork(id: "im_rainy", title: "Straße in Paris, Regentag", artist: "Gustave Caillebotte", year: "1877",
                        assetName: "Gustave_Caillebotte_-_Paris_Street;_Rainy_Day_-_Google_Art_Project",
                        collectionTag: "Impressionismus",
                        blurb: "Regenschirme, nasses Pflaster und die neue Weite des modernen Paris — fotografisch präzise komponiert."),
                Artwork(id: "im_ballet", title: "Die Ballettklasse", artist: "Edgar Degas", year: "1874",
                        assetName: "Edgar_Degas_-_The_Ballet_Class_-_Google_Art_Project",
                        collectionTag: "Impressionismus",
                        blurb: "Junge Tänzerinnen zwischen Anspannung und Langeweile — Degas' Blick hinter die Kulissen der Oper."),
            ]),
        ArtPack(
            id: "pack_meister",
            name: "Alte Meister",
            tagline: "Vier Ikonen aus vier Jahrhunderten — von Botticellis Venus bis Rembrandts Nachtwache.",
            priceCoins: 260,
            accentHex: 0x8A6B4A,
            artworks: [
                Artwork(id: "om_venus", title: "Die Geburt der Venus", artist: "Sandro Botticelli", year: "1485",
                        assetName: "Sandro_Botticelli_-_La_nascita_di_Venere_-_Google_Art_Project_-_edited",
                        collectionTag: "Renaissance",
                        blurb: "Venus schwebt auf einer Muschel ans Ufer — das vielleicht anmutigste Bild der italienischen Renaissance."),
                Artwork(id: "om_monalisa", title: "Mona Lisa", artist: "Leonardo da Vinci", year: "1503",
                        assetName: "Mona_Lisa,_by_Leonardo_da_Vinci,_from_C2RMF_retouched",
                        collectionTag: "Renaissance",
                        blurb: "Das berühmteste Lächeln der Kunstgeschichte — und ein Blick, der jedem Betrachter zu folgen scheint."),
                Artwork(id: "om_nachtwache", title: "Die Nachtwache", artist: "Rembrandt van Rijn", year: "1642",
                        assetName: "The_Night_Watch_-_HD",
                        collectionTag: "Goldenes Zeitalter",
                        blurb: "Eine Bürgerwehr tritt aus dem Dunkel ins Licht — Rembrandt macht aus einem Gruppenporträt ein Drama."),
                Artwork(id: "om_milkmaid", title: "Dienstmagd mit Milchkrug", artist: "Johannes Vermeer", year: "1658",
                        assetName: "Johannes_Vermeer_-_Het_melkmeisje_-_Google_Art_Project",
                        collectionTag: "Goldenes Zeitalter",
                        blurb: "Milch fließt in dünnem Strahl, das Licht fällt still durchs Fenster — Alltag, verwandelt in Andacht."),
            ]),
        ArtPack(
            id: "pack_moderne",
            name: "Aufbruch zur Moderne",
            tagline: "Farbe wird frei: Kandinskys Kompositionen, Rousseaus Traumwelten, van Goghs Blick.",
            priceCoins: 240,
            accentHex: 0x9A5A6B,
            artworks: [
                Artwork(id: "mo_komposition", title: "Komposition VII", artist: "Wassily Kandinsky", year: "1913",
                        assetName: "Vassily_Kandinsky,_1913_-_Composition_7",
                        collectionTag: "Abstraktion",
                        blurb: "Ein Wirbel aus Farbe und Form ohne Gegenstand — für Kandinsky klang Malerei wie Musik."),
                Artwork(id: "mo_gypsy", title: "Die schlafende Zigeunerin", artist: "Henri Rousseau", year: "1897",
                        assetName: "La_Bohémienne_endormie",
                        collectionTag: "Naive Kunst",
                        blurb: "Eine Schlafende in der Wüste, ein Löwe, der Mond — ein Traum, gemalt mit der Ernsthaftigkeit eines Kindes."),
                Artwork(id: "mo_selfportrait", title: "Selbstbildnis", artist: "Vincent van Gogh", year: "1889",
                        assetName: "Vincent_van_Gogh_-_Self-Portrait_-_Google_Art_Project_(454045)",
                        collectionTag: "Post-Impressionismus",
                        blurb: "Van Gogh malt sich selbst in wirbelndem Blau — wach, verletzlich und völlig gegenwärtig."),
                Artwork(id: "mo_adele", title: "Adele Bloch-Bauer I", artist: "Gustav Klimt", year: "1907",
                        assetName: "Gustav_Klimt_046",
                        collectionTag: "Wiener Secession",
                        blurb: "Die „goldene Adele“: ein Porträt, das in Ornament und Gold beinahe zur Ikone wird."),
            ]),
    ]

    static func byID(_ id: String) -> ArtPack? {
        catalog.first { $0.id == id }
    }
    /// Das Paket, aus dem ein Werk stammt (nil für die Basis-Sammlung).
    static func containing(artworkID: String) -> ArtPack? {
        catalog.first { $0.artworks.contains { $0.id == artworkID } }
    }
}
