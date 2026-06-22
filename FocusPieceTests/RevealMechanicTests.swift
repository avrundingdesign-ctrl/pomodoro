import XCTest
@testable import FocusPiece

/// Tests for the core reveal mechanic — the heart of FocusPiece.
@MainActor
final class RevealMechanicTests: XCTestCase {

    func test_revealOrder_isValidPermutationOf0to19() {
        let order = SessionModel.revealOrder
        XCTAssertEqual(order.count, 20)
        XCTAssertEqual(Set(order), Set(0..<20), "Order must contain every tile index 0…19 exactly once")
        // Exact sequence from the spec.
        XCTAssertEqual(order, [7, 14, 2, 11, 18, 5, 9, 0, 16, 3, 12, 19, 6, 1, 15, 8, 17, 4, 13, 10])
    }

    func test_revealedCount_mapsProgressByFloorTimes20() {
        XCTAssertEqual(SessionModel.revealedCount(progress: 0.0, isComplete: false), 0)
        XCTAssertEqual(SessionModel.revealedCount(progress: 0.05, isComplete: false), 1)   // floor(1.0)
        XCTAssertEqual(SessionModel.revealedCount(progress: 0.26, isComplete: false), 5)   // "Fokus läuft" ~26%
        XCTAssertEqual(SessionModel.revealedCount(progress: 0.45, isComplete: false), 9)   // 9 of 20
        XCTAssertEqual(SessionModel.revealedCount(progress: 0.75, isComplete: false), 15)  // "Fast geschafft"
        XCTAssertEqual(SessionModel.revealedCount(progress: 0.99, isComplete: false), 19)
        XCTAssertEqual(SessionModel.revealedCount(progress: 1.0, isComplete: false), 20)
    }

    func test_revealedCount_clampsAndCompletes() {
        XCTAssertEqual(SessionModel.revealedCount(progress: -1, isComplete: false), 0, "Never negative")
        XCTAssertEqual(SessionModel.revealedCount(progress: 2, isComplete: false), 20, "Never above 20")
        XCTAssertEqual(SessionModel.revealedCount(progress: 0.0, isComplete: true), 20, "Completion reveals all")
    }

    func test_revealedTiles_areFirstNOfOrder() {
        XCTAssertEqual(SessionModel.revealedTiles(count: 0), [])
        XCTAssertEqual(SessionModel.revealedTiles(count: 3), [7, 14, 2])
        XCTAssertEqual(SessionModel.revealedTiles(count: 9), Set([7, 14, 2, 11, 18, 5, 9, 0, 16]))
        XCTAssertEqual(SessionModel.revealedTiles(count: 20), Set(0..<20))
    }
}
