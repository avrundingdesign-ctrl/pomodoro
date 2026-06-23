import Foundation

/// Reads launch arguments / environment so UI tests can drive the app
/// deterministically. Has no effect in normal runs.
enum LaunchConfig {
    private static var args: [String] { ProcessInfo.processInfo.arguments }
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    /// Wipe persisted state on launch (fresh onboarding + locked collection).
    static var reset: Bool { args.contains("-uitestReset") }
    /// Start already past onboarding (jump straight to the tabs).
    static var startOnboarded: Bool { args.contains("-uitestOnboarded") }
    /// Pre-unlock one artwork so the gallery has a tappable work.
    static var unlockOne: Bool { args.contains("-uitestUnlockOne") }

    /// Override a session's total length (seconds) so completion is reachable
    /// in a UI test. e.g. UITEST_SESSION_SECONDS=3
    static var sessionSeconds: Int? { env["UITEST_SESSION_SECONDS"].flatMap(Int.init) }
    /// Override the countdown tick interval (seconds). e.g. UITEST_TICK_INTERVAL=0.1
    static var tickInterval: Double? { env["UITEST_TICK_INTERVAL"].flatMap(Double.init) }
}
