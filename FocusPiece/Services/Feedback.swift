#if os(watchOS)
import WatchKit
#else
import UIKit
import AudioToolbox
#endif

/// Completion tone + haptic feedback, gated by the user's settings.
///
/// The three entry points are identical on both platforms so callers never
/// branch. What differs is underneath: iOS drives the Taptic Engine through
/// `UIFeedbackGenerator` and plays a system sound, while watchOS has neither
/// API and instead asks `WKInterfaceDevice` for one of its named haptic
/// patterns — which on the wrist is the whole point of the feature.
enum Feedback {

    #if !os(watchOS)
    /// Soft system chime ("Bloom") — calm enough for the museal mood.
    private static let completionSound: SystemSoundID = 1321
    #endif

    /// Celebrate a completed session.
    static func sessionCompleted(tone: Bool, haptics: Bool) {
        #if os(watchOS)
        // watchOS has no system-sound API, so `tone` cannot be honoured
        // separately — the haptic carries the finale on its own. `.success`
        // is the most emphatic of the calm patterns.
        if tone || haptics { WKInterfaceDevice.current().play(.success) }
        #else
        if tone { AudioServicesPlaySystemSound(completionSound) }
        if haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        #endif
    }

    /// Mark a completed focus round between breaks — softer than the finale.
    static func roundCompleted(haptics: Bool) {
        guard haptics else { return }
        #if os(watchOS)
        // `.notification` reads as "look at your wrist" rather than
        // "you're done", which is exactly what a round boundary means.
        WKInterfaceDevice.current().play(.notification)
        #else
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// Light tap for primary interactions (start / pause / resume).
    static func tap(_ enabled: Bool) {
        guard enabled else { return }
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #else
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
