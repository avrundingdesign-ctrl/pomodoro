import XCTest
@testable import FocusPiece

/// Tests for the session countdown and state machine.
@MainActor
final class SessionModelTests: XCTestCase {

    private func makeSession(minutes: Int = 25, gentleStart: Bool = false) -> SessionModel {
        SessionModel(durationMinutes: minutes,
                     artwork: Artwork.seedCollection[0],
                     gentleStart: gentleStart)
    }

    func test_freshSession_isReadyWithFullClock() {
        let s = makeSession(minutes: 25)
        XCTAssertEqual(s.state, .ready)
        XCTAssertEqual(s.totalSeconds, 25 * 60)
        XCTAssertEqual(s.remainingSeconds, 25 * 60)
        XCTAssertEqual(s.timeString, "25:00")
        XCTAssertEqual(s.progress, 0, accuracy: 0.0001)
        XCTAssertEqual(s.revealedCount, 0)
        XCTAssertEqual(s.revealedLabel, "0 VON 20 TEILEN")
    }

    func test_timeString_formatsMinutesAndSeconds() {
        let s = makeSession(minutes: 1)         // 60s
        XCTAssertEqual(s.timeString, "01:00")
        s.start()
        s.tick()                                 // 59s
        XCTAssertEqual(s.timeString, "00:59")
    }

    func test_start_then_pause_then_resume_transitions() {
        let s = makeSession()
        XCTAssertEqual(s.state, .ready)
        s.start()
        XCTAssertEqual(s.state, .running)
        s.pause()
        XCTAssertEqual(s.state, .paused)
        s.start()                                // resume
        XCTAssertEqual(s.state, .running)
    }

    func test_toggle_flipsBetweenRunningAndPaused() {
        let s = makeSession()
        s.start()
        s.toggle()
        XCTAssertEqual(s.state, .paused)
        s.toggle()
        XCTAssertEqual(s.state, .running)
    }

    func test_tick_decrementsAndDrivesReveal() {
        let s = makeSession(minutes: 1)          // 60s, 1 tile per 3s
        s.start()
        // After 18 seconds → 30% → floor(0.3·20)=6 tiles
        for _ in 0..<18 { s.tick() }
        XCTAssertEqual(s.remainingSeconds, 42)
        XCTAssertEqual(s.revealedCount, 6)
    }

    func test_countdown_reachesZeroAndCompletesWithFullReveal() {
        let s = makeSession(minutes: 1)          // 60 ticks to finish
        s.start()
        for _ in 0..<60 { s.tick() }
        XCTAssertEqual(s.remainingSeconds, 0)
        XCTAssertEqual(s.state, .complete)
        XCTAssertEqual(s.revealedCount, 20, "A completed session reveals all tiles")
    }

    func test_gentleStart_delaysFirstTicks() {
        let s = makeSession(minutes: 1, gentleStart: true)
        s.start()
        s.tick()                                 // settle 1
        s.tick()                                 // settle 2
        XCTAssertEqual(s.remainingSeconds, 60, "Gentle start holds the clock for two beats")
        s.tick()                                 // now counts
        XCTAssertEqual(s.remainingSeconds, 59)
    }
}
