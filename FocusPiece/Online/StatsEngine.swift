import Foundation

/// Fokus-Minuten eines einzelnen Tages — Baustein für Charts & Heatmap.
struct DayLoad: Identifiable, Equatable {
    let date: Date
    var minutes: Int
    var id: Date { date }
}

/// Alle abgeleiteten Kennzahlen eines Nutzers. Wird ausschließlich aus der
/// Runden-Historie berechnet — identisch für das eigene Profil (echte
/// Historie) und Demo-Profile (generierte Historie).
struct UserStats: Equatable {
    var totalMinutes = 0
    var totalRounds = 0
    var activeDays = 0
    var currentStreak = 0
    var bestStreak = 0
    var worksUnlocked = 0
    var earlyRounds = 0          // vor 8 Uhr
    var lateRounds = 0           // ab 22 Uhr
    var avgRoundMinutes = 0
    var bestDayMinutes = 0
    var last7Days: [DayLoad] = []                              // ältester zuerst
    var heatmap: [DayLoad] = []                                // 12 Wochen, tageweise
    var weekdayMinutes: [Int] = Array(repeating: 0, count: 7)  // Mo … So
    var hourRounds: [Int] = Array(repeating: 0, count: 24)

    var totalHoursLabel: String {
        let h = Double(totalMinutes) / 60.0
        if totalMinutes < 60 { return "\(totalMinutes) Min" }
        let text = h.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(h)) : String(format: "%.1f", h).replacingOccurrences(of: ".", with: ",")
        return "\(text) Std"
    }
    /// Produktivste Stunde (nil solange keine Runde existiert).
    var peakHour: Int? {
        guard totalRounds > 0, let maxValue = hourRounds.max(), maxValue > 0 else { return nil }
        return hourRounds.firstIndex(of: maxValue)
    }
}

enum StatsEngine {

    static let heatmapDays = 84  // 12 Wochen

    static func stats(records: [FocusSessionRecord],
                      worksUnlocked: Int,
                      calendar: Calendar = .current,
                      now: Date = Date()) -> UserStats {
        var s = UserStats()
        s.worksUnlocked = worksUnlocked
        guard !records.isEmpty else {
            s.last7Days = emptySeries(days: 7, calendar: calendar, now: now)
            s.heatmap = emptySeries(days: heatmapDays, calendar: calendar, now: now)
            return s
        }

        var minutesPerDay: [Date: Int] = [:]
        for r in records {
            s.totalMinutes += r.minutes
            s.totalRounds += 1
            let hour = calendar.component(.hour, from: r.date)
            if hour < 8 { s.earlyRounds += 1 }
            if hour >= 22 { s.lateRounds += 1 }
            s.hourRounds[hour] += 1
            // Calendar.weekday: 1 = Sonntag → 0 = Montag umrechnen.
            let weekday = (calendar.component(.weekday, from: r.date) + 5) % 7
            s.weekdayMinutes[weekday] += r.minutes
            minutesPerDay[calendar.startOfDay(for: r.date), default: 0] += r.minutes
        }
        s.activeDays = minutesPerDay.count
        s.avgRoundMinutes = s.totalMinutes / max(1, s.totalRounds)
        s.bestDayMinutes = minutesPerDay.values.max() ?? 0

        // Serien: streak, der heute oder gestern zuletzt aktiv war, "lebt" noch.
        let days = Set(minutesPerDay.keys)
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
           days.contains(yesterday) {
            cursor = yesterday
        }
        while days.contains(cursor) {
            s.currentStreak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        s.bestStreak = bestRun(in: days, calendar: calendar)

        s.last7Days = series(days: 7, minutesPerDay: minutesPerDay, calendar: calendar, now: now)
        s.heatmap = series(days: heatmapDays, minutesPerDay: minutesPerDay, calendar: calendar, now: now)
        return s
    }

    /// Längste zusammenhängende Tagesfolge in der gesamten Historie.
    private static func bestRun(in days: Set<Date>, calendar: Calendar) -> Int {
        var best = 0
        for day in days {
            // Nur an Serien-Anfängen zählen — O(n) statt O(n²).
            if let prev = calendar.date(byAdding: .day, value: -1, to: day), days.contains(prev) { continue }
            var run = 0
            var cursor = day
            while days.contains(cursor) {
                run += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            best = max(best, run)
        }
        return best
    }

    private static func series(days: Int, minutesPerDay: [Date: Int],
                               calendar: Calendar, now: Date) -> [DayLoad] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayLoad(date: date, minutes: minutesPerDay[date] ?? 0)
        }
    }

    private static func emptySeries(days: Int, calendar: Calendar, now: Date) -> [DayLoad] {
        series(days: days, minutesPerDay: [:], calendar: calendar, now: now)
    }
}
