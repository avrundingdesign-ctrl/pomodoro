import XCTest
@testable import FocusPiece

/// Tests for the widget snapshot: formatting, state mapping and the deep link.
@MainActor
final class WidgetStateTests: XCTestCase {

    // MARK: Frozen timer

    func test_frozenTimeString_ready_showsFullDuration() {
        var snap = WidgetSnapshot()
        snap.selectedMinutes = 25
        XCTAssertEqual(snap.frozenTimeString, "25:00")
        snap.selectedMinutes = 5
        XCTAssertEqual(snap.frozenTimeString, "05:00")
    }

    func test_frozenTimeString_paused_showsRemainder() {
        var snap = WidgetSnapshot()
        snap.phase = .paused
        snap.remainingSeconds = 754
        XCTAssertEqual(snap.frozenTimeString, "12:34")
    }

    func test_frozenTimeString_paused_withoutRemainder_fallsBackToDuration() {
        var snap = WidgetSnapshot()
        snap.phase = .paused
        snap.selectedMinutes = 40
        XCTAssertEqual(snap.frozenTimeString, "40:00")
    }

    // MARK: Focus time formatting (app vocabulary: Min / Std)

    func test_focusTimeString_usesAppVocabulary() {
        var snap = WidgetSnapshot()
        snap.totalFocusMinutes = 0
        XCTAssertEqual(snap.focusTimeString, "0 Min")
        snap.totalFocusMinutes = 45
        XCTAssertEqual(snap.focusTimeString, "45 Min")
        snap.totalFocusMinutes = 120
        XCTAssertEqual(snap.focusTimeString, "2 Std")
        snap.totalFocusMinutes = 75
        XCTAssertEqual(snap.focusTimeString, "1 Std 15 Min")
    }

    // MARK: State label

    func test_eyebrowText_mirrorsSessionStates() {
        var snap = WidgetSnapshot()
        XCTAssertEqual(snap.eyebrowText, "FOKUS")
        snap.phase = .running
        XCTAssertEqual(snap.eyebrowText, "FOKUS LÄUFT")
        snap.phase = .paused
        XCTAssertEqual(snap.eyebrowText, "PAUSIERT")
    }

    // MARK: Round trip through the shared store

    func test_widgetStore_publishThenLoad_roundTrips() {
        var snap = WidgetSnapshot()
        snap.phase = .paused
        snap.selectedMinutes = 40
        snap.remainingSeconds = 611
        snap.sessionsCompleted = 7
        snap.worksUnlocked = 4
        snap.totalFocusMinutes = 190

        WidgetStore.publish(snap)
        XCTAssertEqual(WidgetStore.load(), snap)

        // Leave a neutral snapshot behind for other tests / the simulator.
        WidgetStore.publish(WidgetSnapshot())
    }

    // MARK: Deep link (widget Start button)

    private func makeModel() -> AppModel {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppModel(defaults: defaults)
    }

    func test_deepLink_start_afterOnboarding_requestsAutoStart() {
        let app = makeModel()
        app.finishOnboarding()
        app.selectedTab = .gallery

        app.handleDeepLink(URL(string: "focuspiece://start")!)

        XCTAssertEqual(app.selectedTab, .focus)
        XCTAssertTrue(app.pendingAutoStart)
    }

    func test_deepLink_start_beforeOnboarding_onlyOpensFocusTab() {
        let app = makeModel()

        app.handleDeepLink(URL(string: "focuspiece://start")!)

        XCTAssertEqual(app.selectedTab, .focus)
        XCTAssertFalse(app.pendingAutoStart, "Onboarding must run before a session starts")
    }

    func test_deepLink_ignoresForeignURLs() {
        let app = makeModel()
        app.finishOnboarding()
        app.selectedTab = .settings

        app.handleDeepLink(URL(string: "https://example.com/start")!)
        app.handleDeepLink(URL(string: "focuspiece://something")!)

        XCTAssertEqual(app.selectedTab, .settings)
        XCTAssertFalse(app.pendingAutoStart)
    }
}
