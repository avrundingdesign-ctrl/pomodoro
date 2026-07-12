import XCTest
@testable import FocusPiece

/// Tests for the artwork packs: catalogue integrity, purchase application,
/// refunds, and that the free works stay exactly as they were.
@MainActor
final class PackCatalogTests: XCTestCase {

    private func makeModel() -> (AppModel, UserDefaults) {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (AppModel(defaults: defaults), defaults)
    }

    // MARK: Catalogue integrity

    func test_catalog_freePackIsTheOriginalEight() {
        XCTAssertEqual(ArtworkCatalog.freePack.works, Artwork.seedCollection)
        XCTAssertNil(ArtworkCatalog.freePack.productID, "The original works stay free")
        XCTAssertTrue(Artwork.seedCollection.allSatisfy { $0.packID == ArtworkCatalog.freePackID })
    }

    func test_catalog_idsAreUniqueAcrossAllPacks() {
        let packIDs = ArtworkCatalog.packs.map(\.id)
        XCTAssertEqual(Set(packIDs).count, packIDs.count, "Pack ids must be unique")

        let workIDs = ArtworkCatalog.packs.flatMap(\.works).map(\.id)
        XCTAssertEqual(Set(workIDs).count, workIDs.count, "Work ids must be unique across packs")

        let assetNames = ArtworkCatalog.packs.flatMap(\.works).map(\.assetName)
        XCTAssertEqual(Set(assetNames).count, assetNames.count, "Asset names must be unique")
    }

    func test_catalog_paidPacksAreWellFormed() {
        XCTAssertEqual(ArtworkCatalog.paidPacks.count, 3)
        for pack in ArtworkCatalog.paidPacks {
            XCTAssertEqual(pack.works.count, 4, "\(pack.id) should hold four works")
            XCTAssertEqual(pack.productID, "com.focuspiece.app.pack.\(pack.id)")
            XCTAssertTrue(pack.works.allSatisfy { $0.packID == pack.id },
                          "Works must carry their pack's id")
            XCTAssertTrue(pack.works.allSatisfy { !$0.unlocked }, "Bought works start locked")
            XCTAssertFalse(pack.blurb.isEmpty)
            for work in pack.works {
                XCTAssertFalse(work.blurb.isEmpty, "\(work.id) needs info text for the ⓘ sheet")
                XCTAssertFalse(work.collectionTag.isEmpty)
            }
        }
    }

    func test_catalog_mapsProductIDsToPackIDs() {
        let ids = ArtworkCatalog.packIDs(forProducts: [
            "com.focuspiece.app.pack.impressionen",
            "com.focuspiece.app.pack.unknown",
        ])
        XCTAssertEqual(ids, ["impressionen"], "Unknown products are ignored")
    }

    // MARK: Backward-compatible decoding

    func test_artwork_decodesLegacyJSONWithoutPackID() throws {
        let legacy = """
        {"id":"almond_blossom","title":"Mandelblüte","artist":"Vincent van Gogh",
         "year":"1890","assetName":"Almond_blossom","collectionTag":"Post-Impressionismus",
         "blurb":"Test","unlocked":true}
        """.data(using: .utf8)!
        let art = try JSONDecoder().decode(Artwork.self, from: legacy)
        XCTAssertEqual(art.packID, ArtworkCatalog.freePackID)
        XCTAssertTrue(art.unlocked)
    }

    // MARK: Applying purchases

    func test_freshModel_ownsOnlyTheFreePack() {
        let (app, _) = makeModel()
        XCTAssertEqual(app.ownedPackIDs, [ArtworkCatalog.freePackID])
        XCTAssertEqual(app.totalCount, 8, "Shop works don't count until bought")
        XCTAssertEqual(app.purchasablePacks.map(\.id),
                       ArtworkCatalog.paidPacks.map(\.id))
    }

    func test_applyPurchasedProducts_addsPackWorksLocked() {
        let (app, _) = makeModel()
        app.applyPurchasedProducts(["com.focuspiece.app.pack.nachtstuecke"])

        XCTAssertTrue(app.ownedPackIDs.contains("nachtstuecke"))
        XCTAssertEqual(app.totalCount, 12)
        XCTAssertEqual(app.unlockedCount, 0, "New works arrive locked — focus reveals them")
        XCTAssertFalse(app.purchasablePacks.contains { $0.id == "nachtstuecke" })
    }

    func test_applyPurchasedProducts_ignoresUnknownAndIsIdempotent() {
        let (app, _) = makeModel()
        app.applyPurchasedProducts(["com.example.bogus"])
        XCTAssertEqual(app.totalCount, 8)

        app.applyPurchasedProducts(["com.focuspiece.app.pack.impressionen"])
        app.applyPurchasedProducts(["com.focuspiece.app.pack.impressionen"])
        XCTAssertEqual(app.totalCount, 12, "Re-applying must not duplicate works")
    }

    func test_purchasedPack_persistsAcrossRelaunch() {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        do {
            let app = AppModel(defaults: defaults)
            app.applyPurchasedProducts(["com.focuspiece.app.pack.goldenes_zeitalter"])
        }

        let reloaded = AppModel(defaults: defaults)
        XCTAssertTrue(reloaded.ownedPackIDs.contains("goldenes_zeitalter"))
        XCTAssertEqual(reloaded.totalCount, 12,
                       "Bought works survive a relaunch even before StoreKit answers")
    }

    func test_revocation_removesLockedWorksButKeepsRevealedOnes() {
        let (app, _) = makeModel()
        app.applyPurchasedProducts(["com.focuspiece.app.pack.impressionen"])
        let bought = app.collection.first { $0.packID == "impressionen" }!
        app.unlock(bought, minutes: 25)

        // Refund: the entitlement disappears.
        app.applyPurchasedProducts([])

        XCTAssertEqual(app.ownedPackIDs, [ArtworkCatalog.freePackID])
        XCTAssertEqual(app.totalCount, 9, "8 free + the one already revealed work")
        XCTAssertTrue(app.collection.first { $0.id == bought.id }!.unlocked)
        XCTAssertTrue(app.purchasablePacks.contains { $0.id == "impressionen" },
                      "The pack can be bought again")
    }

    func test_nextLockedArtwork_staysWithinOwnedPacks() {
        let (app, _) = makeModel()
        for art in app.collection { app.unlock(art, minutes: 25) }
        XCTAssertNil(app.nextLockedArtwork(), "Shop works must never be picked for a session")

        app.applyPurchasedProducts(["com.focuspiece.app.pack.nachtstuecke"])
        let next = app.nextLockedArtwork()
        XCTAssertEqual(next?.packID, "nachtstuecke",
                       "After buying, sessions reveal the new set")
    }
}
