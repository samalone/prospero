import Foundation
import Plot
import PlotHTMX

struct CalendarView: Component {
    var windows: [CalendarWindow]
    var patterns: [ActivityPattern]

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f
    }()

    /// Get the local midnight for each of the next 14 days starting today.
    private var days: [Date] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        return (0..<14).compactMap {
            calendar.date(byAdding: .day, value: $0, to: startOfToday)
        }
    }

    var body: Component {
        Div {
            H1("Calendar")

            if patterns.isEmpty {
                Paragraph {
                    Text("No patterns yet. ")
                    Link("Create one", url: "/patterns/new")
                    Text(" to see its windows on the calendar.")
                }
                .class("empty-state")
            } else {
                // Legend
                Div {
                    for pattern in patterns {
                        Element(name: "span") {
                            Element(name: "span") {}
                                .class("legend-swatch")
                                .attribute(
                                    named: "style",
                                    value: "background: \(HuePlacer.goalColor(hue: pattern.hue))"
                                )
                            Text(pattern.name)
                        }
                        .class("legend-item")
                    }
                }
                .class("calendar-legend")

                // Calendar grid
                Div {
                    // Hour header
                    Div {
                        Div { Text("") }.class("calendar-day-label")
                        Div {
                            for hour in stride(from: 0, to: 24, by: 3) {
                                Element(name: "span") {
                                    let date = Calendar.current.date(
                                        bySettingHour: hour, minute: 0, second: 0, of: Date()
                                    ) ?? Date()
                                    Text(Self.timeFormatter.string(from: date))
                                }
                                .class("hour-label")
                                .attribute(named: "style",
                                           value: "left: \(Double(hour) / 24.0 * 100)%")
                            }
                        }
                        .class("calendar-hours")
                    }
                    .class("calendar-row calendar-header")

                    // Day rows
                    for day in days {
                        CalendarDayRow(day: day, windows: windows)
                    }
                }
                .class("calendar-grid")
            }
        }
    }
}

struct CalendarDayRow: Component {
    var day: Date
    var windows: [CalendarWindow]

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()

    /// Windows that overlap with this day (local time).
    private var dayWindows: [(window: CalendarWindow, startFrac: Double, endFrac: Double)] {
        let calendar = Calendar.current
        let dayStart = day
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }
        let dayDuration = dayEnd.timeIntervalSince(dayStart)

        return windows.compactMap { cw in
            // Use the full qualifying range.
            let wStart = cw.window.start
            let wEnd = cw.window.end
            // Skip if window doesn't overlap this day.
            if wEnd <= dayStart || wStart >= dayEnd { return nil }
            // Clip to day bounds.
            let clippedStart = max(wStart, dayStart)
            let clippedEnd = min(wEnd, dayEnd)
            let startFrac = clippedStart.timeIntervalSince(dayStart) / dayDuration
            let endFrac = clippedEnd.timeIntervalSince(dayStart) / dayDuration
            return (cw, startFrac, endFrac)
        }
    }

    var body: Component {
        Div {
            Div { Text(Self.dayFormatter.string(from: day)) }
                .class("calendar-day-label")

            Div {
                // Faint hour gridlines
                for hour in stride(from: 3, to: 24, by: 3) {
                    Element(name: "span") {}
                        .class("calendar-gridline")
                        .attribute(named: "style",
                                   value: "left: \(Double(hour) / 24.0 * 100)%")
                }

                // Pattern bars
                for entry in dayWindows {
                    let widthPct = (entry.endFrac - entry.startFrac) * 100
                    let leftPct = entry.startFrac * 100
                    let quality = entry.window.window.quality
                    let color = HuePlacer.goalColor(hue: entry.window.hue, quality: quality)
                    Element(name: "div") {
                        Element(name: "span") {
                            Text(entry.window.patternName)
                        }
                        .class("calendar-bar-label")
                    }
                    .class("calendar-bar")
                    .attribute(
                        named: "style",
                        value: "left: \(leftPct)%; width: \(widthPct)%; background: \(color); --goal-color: \(color)"
                    )
                    .title("\(entry.window.patternName) — \(qualityLabel(quality))")
                }
            }
            .class("calendar-day-track")
        }
        .class("calendar-row")
    }
}

private func qualityLabel(_ quality: Double) -> String {
    switch quality {
    case 0.75...: "Excellent"
    case 0.5..<0.75: "Good"
    case 0.25..<0.5: "Fair"
    default: "Marginal"
    }
}
