import UIKit
import AudioToolbox

/// Completion tone + haptic feedback, gated by the user's settings.
enum Feedback {

    /// Soft system chime ("Bloom") — calm enough for the museal mood.
    private static let completionSound: SystemSoundID = 1321

    /// Celebrate a completed session.
    static func sessionCompleted(tone: Bool, haptics: Bool) {
        if tone { AudioServicesPlaySystemSound(completionSound) }
        if haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    /// Light tap for primary interactions (start / pause / resume).
    static func tap(_ enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
