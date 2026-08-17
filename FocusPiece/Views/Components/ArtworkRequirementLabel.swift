import Foundation

/// Display strings for a work's task.
///
/// Deliberately **not** on `ArtworkRequirement` itself. `Models/Artwork.swift`
/// is compiled into the watch target through a membership exception and is kept
/// free of `String(localized:)` so the watch bundle does not have to carry the
/// catalogue's translations. These live on the phone side, where they are used.
extension ArtworkRequirement {

    /// "4 × 25 Min" — short enough for a 166 pt gallery tile.
    ///
    /// The multiplication form dodges a plural problem the wordier phrasing
    /// would have: "1 Runden à 25 Minuten" needs a plural variation in the
    /// string catalog, "1 × 25 Min" reads correctly at every count.
    var shortLabel: String {
        String(localized: "\(rounds) × \(minutesPerRound) Min")
    }

    /// "25 Min" on its own, for a labelled row. Reuses the catalog key the
    /// settings picker already ships, so English gets "25 min" for free.
    var minutesLabel: String {
        String(localized: "\(minutesPerRound) Min")
    }
}
