import Foundation

/// Checks the App Store for a newer version via Apple's iTunes Lookup API
/// and surfaces a one-time-per-version prompt with a link to update.
///
/// No server of our own: the lookup endpoint reflects whatever is live on
/// the App Store, so this works the moment a new version is approved.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Update: Identifiable {
        let version: String
        let storeURL: URL
        var id: String { version }
    }

    @Published private(set) var available: Update?

    private let bundleID = "com.focuspiece.app"
    private let defaults = UserDefaults.standard
    private static let dismissedVersionKey = "fp.updateDismissedVersion"

    /// Call once at launch. Fails silently — offline, throttled, or not yet
    /// listed are all indistinguishable from "no update", and none of them
    /// should interrupt the user.
    func check() async {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier.lowercased() ?? "us"),
        ]
        guard let url = components.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(LookupResponse.self, from: data)
            guard let entry = response.results.first,
                  let storeURL = URL(string: entry.trackViewUrl),
                  Self.isNewer(entry.version, than: Self.installedVersion),
                  defaults.string(forKey: Self.dismissedVersionKey) != entry.version
            else { return }
            available = Update(version: entry.version, storeURL: storeURL)
        } catch {
            // Offline, rate-limited, or not yet listed — try again next launch.
        }
    }

    /// Remembers the version so the prompt doesn't return until a newer one ships.
    func dismiss(_ update: Update) {
        defaults.set(update.version, forKey: Self.dismissedVersionKey)
        available = nil
    }

    private static var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Numeric per-component comparison — "1.10" must outrank "1.9".
    private static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").map { Int($0) ?? 0 }
        let l = local.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    private struct LookupResponse: Decodable {
        let results: [Entry]
        struct Entry: Decodable {
            let version: String
            let trackViewUrl: String
        }
    }
}
