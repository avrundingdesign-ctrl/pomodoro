import XCTest
@testable import FocusPiece

/// Tests for app state: collection, unlocking, settings and persistence.
@MainActor
final class AppModelTests: XCTestCase {

    /// A fresh AppModel backed by an isolated, empty UserDefaults suite.
    private func makeModel() -> (AppModel, UserDefaults) {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (AppModel(defaults: defaults), defaults)
    }

    // MARK: Seed data
    func test_seedCollection_hasEightUniqueLockedWorks() {
        let seed = Artwork.seedCollection
        XCTAssertEqual(seed.count, 8)
        XCTAssertEqual(Set(seed.map(\.id)).count, 8, "Ids must be unique")
        XCTAssertTrue(seed.allSatisfy { !$0.unlocked }, "Everything starts locked")
        XCTAssertTrue(seed.allSatisfy { $0.unlockedDate == nil && $0.sessionMinutes == nil })
    }

    func test_defaultSettings_useTwentyFiveMinutes() {
        let (app, _) = makeModel()
        XCTAssertEqual(app.settings.selectedDuration, 25)
        XCTAssertTrue(app.settings.gentleStart)
        XCTAssertFalse(app.onboardingComplete)
        XCTAssertEqual(app.unlockedCount, 0)
        XCTAssertEqual(app.totalCount, 8)
    }

    func test_attribution_formatsArtistAndYear() {
        let almond = Artwork.seedCollection.first { $0.id == "almond_blossom" }!
        XCTAssertEqual(almond.attribution, "Vincent van Gogh · 1890")
    }

    // MARK: Unlocking
    func test_unlock_setsMetadataAndCounts() {
        let (app, _) = makeModel()
        let target = app.collection[3]
        app.unlock(target, minutes: 45)

        let updated = app.collection.first { $0.id == target.id }!
        XCTAssertTrue(updated.unlocked)
        XCTAssertEqual(updated.sessionMinutes, 45)
        XCTAssertNotNil(updated.unlockedDate)
        XCTAssertEqual(app.unlockedCount, 1)
    }

    func test_nextLockedArtwork_excludesUnlocked() {
        let (app, _) = makeModel()
        // Unlock everything but one.
        for art in app.collection.dropLast() { app.unlock(art, minutes: 25) }
        let remaining = app.collection.first { !$0.unlocked }!

        let next = app.nextLockedArtwork()
        XCTAssertEqual(next?.id, remaining.id)

        app.unlock(remaining, minutes: 25)
        XCTAssertNil(app.nextLockedArtwork(), "No locked works left")
    }

    func test_totalFocusMinutesAndHours_sumAcrossCollection() {
        let (app, _) = makeModel()
        app.unlock(app.collection[0], minutes: 45)
        app.unlock(app.collection[1], minutes: 25)
        app.unlock(app.collection[2], minutes: 60)
        XCTAssertEqual(app.totalFocusMinutes, 130)
        XCTAssertEqual(app.totalFocusHours, 2)
    }

    // MARK: Persistence
    func test_state_persistsAcrossInstances() {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        do {
            let app = AppModel(defaults: defaults)
            app.finishOnboarding()
            app.settings.selectedDuration = 45
            app.settings.haptics = true
            app.unlock(app.collection[2], minutes: 45)
        }

        // A new model reading the same store must see the saved state.
        let reloaded = AppModel(defaults: defaults)
        XCTAssertTrue(reloaded.onboardingComplete)
        XCTAssertEqual(reloaded.settings.selectedDuration, 45)
        XCTAssertTrue(reloaded.settings.haptics)
        XCTAssertEqual(reloaded.unlockedCount, 1)
    }

    func test_settings_codableRoundTrip() throws {
        var s = Settings()
        s.selectedDuration = 60
        s.ambientSound = "Wald"
        s.haptics = true
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded, s)
    }
}
