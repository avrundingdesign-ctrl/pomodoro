import XCTest

/// 20 click-by-click workflow tests covering the real things a user does:
/// onboarding, running / pausing / resuming / aborting / restarting a session,
/// completing and collecting, browsing the gallery, and editing settings.
final class FocusPieceUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // Launch hooks
    private let reset = "-uitestReset"
    private let onboarded = "-uitestOnboarded"
    private let unlockOne = "-uitestUnlockOne"
    /// A session that completes in well under a second.
    private var fastSession: [String: String] {
        ["UITEST_SESSION_SECONDS": "2", "UITEST_TICK_INTERVAL": "0.1"]
    }

    /// From the immersive session screen, step back to the gallery (tab bar).
    private func leaveSessionToGallery(_ app: XCUIApplication) {
        let back = app.buttons["session.back"]
        if back.waitForExistence(timeout: 5) { back.tap() }
        require(app.staticTexts["gallery.count"], "Gallery should appear after leaving session")
    }

    // MARK: - Onboarding (1–4)

    func test_01_onboarding_welcomeShowsAndAdvances() {
        let app = XCUIApplication.launch(arguments: [reset])
        require(app.staticTexts["Aus Konzentration wird ein Meisterwerk."], "Welcome headline")
        require(app.buttons["onboarding.next"]).tap()
        require(app.staticTexts["Drei ruhige Schritte"], "Second onboarding screen")
    }

    func test_02_onboarding_fullFlowReachesReadySession() {
        let app = XCUIApplication.launch(arguments: [reset])
        require(app.buttons["onboarding.next"]).tap()   // 1 → 2
        require(app.buttons["onboarding.next"]).tap()   // 2 → 3
        require(app.buttons["onboarding.start"]).tap()  // 3 → session
        require(app.buttons["session.begin"], "Ready session after onboarding")
        XCTAssertEqual(app.staticTexts["session.timer"].label, "25:00")
    }

    func test_03_onboarding_selectingDurationCarriesToSession() {
        let app = XCUIApplication.launch(arguments: [reset])
        require(app.buttons["onboarding.next"]).tap()
        require(app.buttons["onboarding.next"]).tap()
        require(app.buttons["duration.45"], "45-minute chip").tap()
        require(app.buttons["onboarding.start"]).tap()
        XCTAssertEqual(app.staticTexts["session.timer"].label, "45:00",
                       "Chosen duration should drive the session clock")
    }

    func test_04_onboarding_explainsThreeSteps() {
        let app = XCUIApplication.launch(arguments: [reset])
        require(app.buttons["onboarding.next"]).tap()
        require(app.staticTexts["Setze deine Zeit"])
        require(app.staticTexts["Bleib im Bild"])
        require(app.staticTexts["Sammle Meisterwerke"])
    }

    // MARK: - Running a session (5–7, 10)

    func test_05_session_startRunsTheTimer() {
        let app = XCUIApplication.launch(arguments: [reset, onboarded])
        require(app.buttons["session.begin"]).tap()
        require(app.buttons["session.toggle"], "Pause control appears while running")
        XCTAssertTrue(app.staticTexts["session.status"].label.contains("FOKUS LÄUFT"))
    }

    func test_06_session_pauseShowsPausedState() {
        let app = XCUIApplication.launch(arguments: [reset, onboarded])
        require(app.buttons["session.begin"]).tap()
        require(app.buttons["session.toggle"]).tap()   // pause
        XCTAssertTrue(app.staticTexts["session.status"].label.contains("PAUSIERT"))
    }

    func test_07_session_resumeAfterPause() {
        let app = XCUIApplication.launch(arguments: [reset, onboarded])
        require(app.buttons["session.begin"]).tap()
        require(app.buttons["session.toggle"]).tap()   // pause
        require(app.buttons["session.toggle"]).tap()   // resume
        XCTAssertTrue(app.staticTexts["session.status"].label.contains("FOKUS LÄUFT"))
    }

    func test_10_session_timerCountsDown() {
        let app = XCUIApplication.launch(arguments: [reset, onboarded],
                                         environment: ["UITEST_TICK_INTERVAL": "0.1"])
        require(app.buttons["session.begin"]).tap()
        let timer = app.staticTexts["session.timer"]
        XCTAssertTrue(waitForLabelChange(timer, from: "25:00"),
                      "The clock should visibly count down from 25:00")
    }

    // MARK: - Aborting a session (8–9)

    func test_08_session_closeButtonAbortsToGallery() {
        let app = XCUIApplication.launch(arguments: [reset, onboarded])
        require(app.buttons["session.begin"]).tap()
        require(app.buttons["session.close"], "Close control").tap()
        require(app.staticTexts["gallery.count"], "Closing returns to the gallery")
    }

    func test_09_session_backButtonAbortsToGallery() {
        let app = XCUIApplication.launch(arguments: [reset, onboarded])
        require(app.buttons["session.begin"]).tap()
        require(app.buttons["session.back"], "Back control").tap()
        require(app.staticTexts["gallery.count"], "Back returns to the gallery")
    }

    // MARK: - Completing & collecting (11–13)

    func test_11_session_completesAndShowsReveal() {
        let app = XCUIApplication.launch(arguments: [reset, onboarded], environment: fastSession)
        require(app.buttons["session.begin"]).tap()
        require(app.staticTexts["completion.title"], "Completion screen after the countdown", timeout: 12)
        require(app.buttons["completion.save"], "Save-to-gallery action")
    }

    func test_12_completion_saveAddsWorkToGallery() {
        let app = XCUIApplication.launch(arguments: [reset, onboarded], environment: fastSession)
        require(app.buttons["session.begin"]).tap()
        require(app.buttons["completion.save"], "Completion save button", timeout: 12).tap()
        let count = require(app.staticTexts["gallery.count"], "Gallery after saving")
        XCTAssertEqual(count.label, "1 von 8 Werken enthüllt",
                       "Saving a completed work unlocks exactly one")
    }

    func test_13_restart_afterCompletionGivesFreshReadySession() {
        let app = XCUIApplication.launch(arguments: [reset, onboarded], environment: fastSession)
        require(app.buttons["session.begin"]).tap()
        require(app.buttons["completion.save"], timeout: 12).tap()   // back on gallery
        require(app.buttons["tab.focus"]).tap()
        require(app.buttons["session.begin"], "Re-entering Fokus starts a fresh ready session")
    }

    // MARK: - Gallery (14–17)

    func test_14_tabBar_switchesBetweenSections() {
        let app = XCUIApplication.launch(arguments: [reset, onboarded])
        leaveSessionToGallery(app)
        require(app.buttons["tab.settings"]).tap()
        require(app.staticTexts["settings.title"], "Settings section")
        require(app.buttons["tab.gallery"]).tap()
        require(app.staticTexts["gallery.count"], "Gallery section")
        require(app.buttons["tab.focus"]).tap()
        require(app.buttons["session.begin"], "Focus section")
    }

    func test_15_gallery_showsProgressCounters() {
        let app = XCUIApplication.launch(arguments: [reset, onboarded])
        leaveSessionToGallery(app)
        XCTAssertEqual(app.staticTexts["gallery.count"].label, "0 von 8 Werken enthüllt")
        require(app.staticTexts["gallery.hours"], "Focus-hours stat")
    }

    func test_16_gallery_lockedWorksAreNotTappable() {
        let app = XCUIApplication.launch(arguments: [reset, onboarded])
        leaveSessionToGallery(app)
        // A fresh collection is entirely locked: nothing is exposed as a tappable tile…
        let unlocked = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'gallery.tile.unlocked'"))
        XCTAssertEqual(unlocked.count, 0, "Nothing unlocked yet, so nothing tappable")
        // …and the counter confirms 0 of 8 revealed.
        XCTAssertEqual(app.staticTexts["gallery.count"].label, "0 von 8 Werken enthüllt")
    }

    func test_17_gallery_openUnlockedWorkDetailAndBack() {
        let app = XCUIApplication.launch(arguments: [reset, onboarded, unlockOne])
        leaveSessionToGallery(app)
        let tile = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'gallery.tile.unlocked'"))
            .firstMatch
        require(tile, "An unlocked tile to open").tap()
        require(app.staticTexts["detail.title"], "Work detail screen")
        require(app.buttons["detail.back"]).tap()
        require(app.staticTexts["gallery.count"], "Back returns to the gallery")
    }

    // MARK: - Settings: editing (18–20)

    func test_18_settings_toggleFlipsState() {
        let app = XCUIApplication.launch(arguments: [reset, onboarded])
        leaveSessionToGallery(app)
        require(app.buttons["tab.settings"]).tap()
        let haptics = require(app.buttons["settings.toggle.haptics"], "Haptics toggle")
        XCTAssertEqual(haptics.value as? String, "off", "Haptics defaults off")
        haptics.tap()
        XCTAssertEqual(haptics.value as? String, "on", "Toggle flips on")
    }

    func test_19_settings_changeDefaultDurationAppliesToNextSession() {
        let app = XCUIApplication.launch(arguments: [reset, onboarded])
        leaveSessionToGallery(app)
        require(app.buttons["tab.settings"]).tap()
        require(app.buttons["settings.duration"], "Default-duration row").tap()
        require(app.buttons["45 Min"], "Duration option in the menu").tap()
        require(app.staticTexts["45 Min"], "Row reflects the new value")
        require(app.buttons["tab.focus"]).tap()
        XCTAssertEqual(app.staticTexts["session.timer"].label, "45:00",
                       "The edited default duration drives the next session")
    }

    func test_20_settings_toggleStatePersistsAcrossRelaunch() {
        let app = XCUIApplication.launch(arguments: [reset, onboarded])
        leaveSessionToGallery(app)
        require(app.buttons["tab.settings"]).tap()
        require(app.buttons["settings.toggle.haptics"]).tap()   // turn on
        app.terminate()

        // Relaunch WITHOUT reset — the saved setting must survive.
        let relaunched = XCUIApplication.launch(arguments: [onboarded])
        leaveSessionToGallery(relaunched)
        require(relaunched.buttons["tab.settings"]).tap()
        XCTAssertEqual(relaunched.buttons["settings.toggle.haptics"].value as? String, "on",
                       "Toggle state persisted across relaunch")
    }
}
