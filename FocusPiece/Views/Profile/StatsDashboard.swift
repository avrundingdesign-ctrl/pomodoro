import SwiftUI
import Charts

/// Umfangreiches Statistik-Dashboard — identisch für das eigene Profil und
/// (kompakt) für Freunde. Rechnet nichts selbst: alles kommt aus UserStats.
struct StatsDashboard: View {
    let stats: UserStats
    /// Kompakt (Freunde-Profil): Kennzahlen + Woche + Heatmap.
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            kpiGrid

            card("Diese Woche") {
                weekChart
            }
            card("Letzte 12 Wochen") {
                HeatmapView(days: stats.heatmap)
            }
            if !compact {
                card("Tagesprofil") {
                    hourChart
                    if let peak = stats.peakHour {
                        Text("Deine produktivste Zeit: \(peak):00–\(peak + 1):00 Uhr")
                            .font(Theme.Font.sans(12))
                            .foregroundStyle(Theme.Palette.muted2)
                            .padding(.top, 8)
                    }
                }
                card("Wochentage") {
                    weekdayChart
                }
            }
        }
    }

    // MARK: Kennzahlen

    private var kpiGrid: some View {
        let items: [(String, String)] = [
            (stats.totalHoursLabel, "Fokus gesamt"),
            ("\(stats.totalRounds)", "Runden"),
            ("\(stats.activeDays)", "Aktive Tage"),
            ("\(stats.currentStreak)", "Tage Serie"),
            ("\(stats.bestStreak)", "Beste Serie"),
            ("\(stats.avgRoundMinutes) Min", "Ø Runde"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                   GridItem(.flexible(), spacing: 12),
                                   GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(items, id: \.1) { value, caption in
                VStack(alignment: .leading, spacing: 3) {
                    Text(value)
                        .font(Theme.Font.serif(21, weight: .medium))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(caption)
                        .font(Theme.Font.sans(11))
                        .foregroundStyle(Theme.Palette.muted2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.Palette.hairline2, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: Charts

    private static let weekdayShort = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    private var weekChart: some View {
        Chart(stats.last7Days) { day in
            BarMark(
                x: .value("Tag", Self.dayLabel(day.date)),
                y: .value("Minuten", day.minutes)
            )
            .foregroundStyle(Calendar.current.isDateInToday(day.date)
                             ? Theme.Palette.accent : Theme.Palette.accent.opacity(0.45))
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(Theme.Palette.hairline)
                AxisValueLabel().font(Theme.Font.sans(10)).foregroundStyle(Theme.Palette.muted3)
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(Theme.Font.sans(10)).foregroundStyle(Theme.Palette.muted3)
            }
        }
        .frame(height: 140)
    }

    private var hourChart: some View {
        Chart(Array(stats.hourRounds.enumerated()), id: \.offset) { hour, rounds in
            BarMark(
                x: .value("Stunde", hour),
                y: .value("Runden", rounds)
            )
            .foregroundStyle(hour == stats.peakHour
                             ? Theme.Palette.accent : Theme.Palette.accent.opacity(0.4))
            .cornerRadius(2)
        }
        .chartXScale(domain: 0...24)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 24]) { _ in
                AxisGridLine().foregroundStyle(Theme.Palette.hairline)
                AxisValueLabel().font(Theme.Font.sans(10)).foregroundStyle(Theme.Palette.muted3)
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 100)
    }

    private var weekdayChart: some View {
        Chart(Array(stats.weekdayMinutes.enumerated()), id: \.offset) { idx, minutes in
            BarMark(
                x: .value("Tag", Self.weekdayShort[idx]),
                y: .value("Minuten", minutes)
            )
            .foregroundStyle(Theme.Palette.accent.opacity(0.55))
            .cornerRadius(4)
        }
        .chartXScale(domain: Self.weekdayShort)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(Theme.Font.sans(10)).foregroundStyle(Theme.Palette.muted3)
            }
        }
        .frame(height: 100)
    }

    private static func dayLabel(_ date: Date) -> String {
        let idx = (Calendar.current.component(.weekday, from: date) + 5) % 7
        return weekdayShort[idx]
    }

    // MARK: Karten-Rahmen

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.Font.sans(11, weight: .semibold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.muted3)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                .stroke(Theme.Palette.hairline2, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
    }
}

// MARK: - Heatmap

/// 12-Wochen-Aktivitätsraster (GitHub-Stil): Spalten = Wochen, Zeilen = Mo–So.
struct HeatmapView: View {
    let days: [DayLoad]

    var body: some View {
        let columns = weekColumns()
        HStack(alignment: .top, spacing: 4) {
            // Zeilen-Legende
            VStack(spacing: 4) {
                ForEach(["Mo", "", "Mi", "", "Fr", "", "So"], id: \.self) { label in
                    Text(label)
                        .font(Theme.Font.sans(8))
                        .foregroundStyle(Theme.Palette.muted3)
                        .frame(width: 16, height: 12)
                }
            }
            ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 4) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color(for: day))
                            .frame(height: 12)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Tage in Montag-ausgerichtete Wochenspalten legen (führende Lücken = nil).
    private func weekColumns() -> [[DayLoad?]] {
        guard let first = days.first else { return [] }
        let leading = (Calendar.current.component(.weekday, from: first.date) + 5) % 7
        var cells: [DayLoad?] = Array(repeating: nil, count: leading)
        cells.append(contentsOf: days.map { Optional($0) })
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private func color(for day: DayLoad?) -> Color {
        guard let day else { return .clear }
        guard day.minutes > 0 else { return Theme.Palette.surface2 }
        let intensity = min(1.0, Double(day.minutes) / 100.0)
        return Theme.Palette.accent.opacity(0.25 + intensity * 0.7)
    }
}

// MARK: - Achievements

/// Erfolge-Raster: verdiente in Farbe, offene gedimmt mit Schloss.
struct AchievementsGrid: View {
    let stats: UserStats
    /// Nur verdiente zeigen (Freunde-Profil).
    var earnedOnly: Bool = false

    var body: some View {
        let earned = Set(Achievement.earned(by: stats).map(\.id))
        let shown = earnedOnly ? Achievement.all.filter { earned.contains($0.id) } : Achievement.all
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(shown) { achievement in
                let isEarned = earned.contains(achievement.id)
                HStack(spacing: 11) {
                    Image(systemName: isEarned ? achievement.icon : "lock")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(isEarned ? Theme.Palette.accent : Theme.Palette.muted3Soft)
                        .frame(width: 36, height: 36)
                        .background(Theme.Palette.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(achievement.title)
                            .font(Theme.Font.sans(13, weight: .semibold))
                            .foregroundStyle(isEarned ? Theme.Palette.ink : Theme.Palette.muted3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(achievement.subtitle)
                            .font(Theme.Font.sans(10))
                            .foregroundStyle(Theme.Palette.muted3)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Theme.Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.Palette.hairline2, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(isEarned ? 1 : 0.75)
            }
        }
    }
}
