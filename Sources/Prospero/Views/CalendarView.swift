import Foundation
import Plot
import PlotHTMX

struct CalendarView: Component {
    var windows: [CalendarWindow]
    var patterns: [ActivityPattern]
    /// Per-pattern sunrise/sunset keyed by local midnight. Used to supply
    /// each match bar with its own location's day/night boundaries — the
    /// track's background shading switches to these when the bar is
    /// hovered, focused, or tapped.
    var solarByPattern: [String: PatternSolar] = [:]
    /// Solar times for the reference location (browser timezone mapped to
    /// a representative city). Used as the default track shading when no
    /// bar is focused, so the calendar still has a day/night orientation
    /// cue without silently attributing one pattern's sun to another's.
    var referenceSolar: [Date: (sunrise: Date, sunset: Date)] = [:]
    /// Human label for the reference location, shown in the caption above
    /// the grid so the user knows whose sun the default shading represents.
    var referenceLocationLabel: String = "UTC"
    /// Whether the reference location is the result of a timezone → city
    /// mapping (true) rather than an exact location (false). When true, the
    /// caption includes an "approximate" qualifier.
    var referenceLocationIsApproximate: Bool = false

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

    /// Caption text shown when no bar is focused. JS reuses this value to
    /// restore the caption after a hover/focus ends, so we compute it
    /// once in Swift instead of re-deriving in JS.
    private var defaultLabelText: String {
        referenceLocationIsApproximate
            ? "\(referenceLocationLabel) (approximate)"
            : referenceLocationLabel
    }

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
                    Link("Create one", url: mountURL("/patterns/new"))
                    Text(" to see its windows on the calendar.")
                }
                .class("empty-state")
            } else {
                // Legend — each entry links to that pattern's editor.
                Div {
                    for pattern in patterns {
                        Element(name: "a") {
                            Element(name: "span") {}
                                .class("legend-swatch")
                                .attribute(
                                    named: "style",
                                    value: "background: \(HuePlacer.goalColor(hue: pattern.hue))"
                                )
                            Text(pattern.name)
                        }
                        .class("legend-item")
                        .attribute(
                            named: "href",
                            value: mountURL("/patterns/\(pattern.id?.uuidString ?? "")/edit")
                        )
                    }
                }
                .class("calendar-legend")

                // Caption: whose sunrise/sunset powers the default shading.
                // The label updates to a pattern's own location while that
                // pattern's bar is hovered/focused/tapped (see calendar.js).
                Div {
                    Element(name: "span") { Text("Daylight: ") }
                        .class("calendar-shading-label-prefix")
                    Element(name: "span") {
                        Text(defaultLabelText)
                    }
                    .class("calendar-shading-label-value")
                    .attribute(named: "data-default-label", value: defaultLabelText)
                }
                .class("calendar-shading-caption")
                .id("calendar-shading-caption")

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
                        CalendarDayRow(
                            day: day,
                            windows: windows,
                            solarByPattern: solarByPattern,
                            referenceSolar: referenceSolar[day]
                        )
                    }
                }
                .class("calendar-grid")
                .id("calendar-content")
                .hxGet(mountURL("/calendar"))
                // Poll while the tab is active; `refresh` is dispatched by
                // calendar.js when the page becomes visible again after the
                // device was asleep (iOS pauses the polling timer, so the
                // poll alone leaves stale data on return — see calendar.js).
                .hxTrigger("every 1800s, refresh")
                .hxSwap(.outerHTML)
                .hxSelect("#calendar-content")
            }
        }
    }
}

/// One window's position within a day, precomputed once per render.
typealias DayEntry = (window: CalendarWindow, startFrac: Double, endFrac: Double)

/// Assign each pattern a stacking row within a day such that patterns
/// whose windows overlap in time end up on different rows. All windows
/// of a single pattern stay on the same row, so a pattern's color reads
/// consistently across the day.
///
/// Greedy first-fit on patterns ordered by earliest window start —
/// minimal rows for N patterns, deterministic placement between renders.
///
/// Returns: (rowForPattern, rowCount). `rowCount >= 1` even when empty
/// so the day still reserves a visual row.
private func assignPatternRows(
    _ entries: [DayEntry]
) -> (rowForPattern: [String: Int], rowCount: Int) {
    let grouped = Dictionary(grouping: entries) { $0.window.patternName }
    // Patterns sorted by their earliest window on this day (ties broken
    // by name for determinism).
    let orderedPatterns = grouped.keys.sorted { a, b in
        let aStart = grouped[a]?.map(\.startFrac).min() ?? 0
        let bStart = grouped[b]?.map(\.startFrac).min() ?? 0
        if aStart != bStart { return aStart < bStart }
        return a < b
    }

    // rows[i] = intervals already placed in row i.
    var rows: [[(start: Double, end: Double)]] = []
    var rowForPattern: [String: Int] = [:]

    for name in orderedPatterns {
        guard let intervals = grouped[name]?.map({ ($0.startFrac, $0.endFrac) }) else {
            continue
        }
        var placed = false
        for i in 0..<rows.count {
            let overlaps = intervals.contains { a in
                rows[i].contains { b in a.0 < b.end && b.start < a.1 }
            }
            if !overlaps {
                rows[i].append(contentsOf: intervals.map { (start: $0.0, end: $0.1) })
                rowForPattern[name] = i
                placed = true
                break
            }
        }
        if !placed {
            rows.append(intervals.map { (start: $0.0, end: $0.1) })
            rowForPattern[name] = rows.count - 1
        }
    }

    return (rowForPattern, max(rows.count, 1))
}

struct CalendarDayRow: Component {
    var day: Date
    var windows: [CalendarWindow]
    var solarByPattern: [String: PatternSolar] = [:]
    /// Sunrise/sunset for the reference location on this day. Used to
    /// compute the track's default day/night shading. Nil → no shading.
    var referenceSolar: (sunrise: Date, sunset: Date)?

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()

    /// Fraction of the day (0…1) that a timestamp sits at, measured from
    /// this row's local midnight. Uses the day's real length (via the
    /// calendar) so DST-transition days (23 or 25 hours) line up with the
    /// bar positions in `dayWindows`, which measure the same way. Clamped
    /// because patterns near the poles can produce sunrise/sunset outside
    /// the day's window.
    private func dayFraction(_ t: Date) -> Double {
        let calendar = Calendar.current
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)
            ?? day.addingTimeInterval(86_400)
        let dayDuration = nextDay.timeIntervalSince(day)
        return max(0, min(1, t.timeIntervalSince(day) / dayDuration))
    }

    /// Percentages (0-100) suitable for writing into CSS custom properties
    /// that the track/gradient rules consume.
    private func solarPercentages(_ solar: (sunrise: Date, sunset: Date))
        -> (sunrise: Double, sunset: Double)
    {
        (dayFraction(solar.sunrise) * 100, dayFraction(solar.sunset) * 100)
    }

    /// Windows that overlap with this day (local time).
    private var dayWindows: [DayEntry] {
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
        let entries = dayWindows
        let (rowForPattern, rowCount) = assignPatternRows(entries)

        // Default shading percentages come from the reference location.
        // Writing them as CSS custom properties on the track lets a single
        // gradient rule in styles.css handle both the default state and
        // the hover/focus override (calendar.js swaps in per-bar values).
        let trackStyle: String = {
            guard let solar = referenceSolar else {
                return ""
            }
            let pct = solarPercentages(solar)
            return String(
                format: "--sunrise-default: %.3f; --sunset-default: %.3f;",
                pct.sunrise, pct.sunset
            )
        }()

        return Div {
            Div { Text(Self.dayFormatter.string(from: day)) }
                .class("calendar-day-label")

            Div {
                for rowIdx in 0..<rowCount {
                    Div {
                        // Faint hour gridlines — repeated per track so the
                        // time axis reads correctly on each one.
                        for hour in stride(from: 3, to: 24, by: 3) {
                            Element(name: "span") {}
                                .class("calendar-gridline")
                                .attribute(named: "style",
                                           value: "left: \(Double(hour) / 24.0 * 100)%")
                        }

                        // Pattern bars assigned to this row.
                        for entry in entries where rowForPattern[entry.window.patternName] == rowIdx {
                            let widthPct = (entry.endFrac - entry.startFrac) * 100
                            let leftPct = entry.startFrac * 100
                            let quality = entry.window.window.quality
                            let color = HuePlacer.goalColor(hue: entry.window.hue, quality: quality)
                            // Three-way card anchoring: left-align near the left
                            // edge, right-align near the right edge, center in
                            // between.
                            let cardAnchor: String = entry.startFrac < 0.2
                                ? "left"
                                : (entry.startFrac >= 0.65 ? "right" : "center")

                            // Pattern's own sunrise/sunset for this day, if
                            // known, expressed as % of day. When the bar is
                            // hovered/focused/tapped, calendar.js copies
                            // these onto the track so the day/night band
                            // reflects this match's real location. Empty
                            // strings are sentinel values — JS skips the
                            // override and the reference shading stays put.
                            let patternSolar = solarByPattern[entry.window.patternName]?.byDay[day]
                            let sunrisePct = patternSolar.map {
                                String(format: "%.3f", dayFraction($0.sunrise) * 100)
                            } ?? ""
                            let sunsetPct = patternSolar.map {
                                String(format: "%.3f", dayFraction($0.sunset) * 100)
                            } ?? ""

                            Element(name: "div") {
                                Element(name: "span") {
                                    Text(entry.window.patternName)
                                }
                                .class("calendar-bar-label")

                                CalendarInfoCard(entry: entry, quality: quality)
                            }
                            .class("calendar-bar card-anchor-\(cardAnchor)")
                            .attribute(named: "tabindex", value: "0")
                            .attribute(named: "data-location-label", value: entry.window.patternName)
                            .attribute(named: "data-sunrise", value: sunrisePct)
                            .attribute(named: "data-sunset", value: sunsetPct)
                            .attribute(
                                named: "style",
                                value: "left: \(leftPct)%; width: \(widthPct)%; background: \(color); --goal-color: \(color)"
                            )
                        }
                    }
                    .class("calendar-day-track")
                    .attribute(named: "style", value: trackStyle)
                }
            }
            .class("calendar-day-tracks")
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

struct CalendarInfoCard: Component {
    var entry: (window: CalendarWindow, startFrac: Double, endFrac: Double)
    var quality: Double

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: Component {
        let w = entry.window.window
        let s = w.summary
        let showsBest = w.start != w.bestStart || w.end != w.bestEnd

        return Div {
            Div {
                Element(name: "strong") { Text(entry.window.patternName) }
                Text(" — \(qualityLabel(quality))")
            }
            .class("info-card-header")

            Paragraph {
                Text("\(Self.timeFormatter.string(from: w.start)) – \(Self.timeFormatter.string(from: w.end))")
            }
            .class("info-card-time")

            if showsBest {
                Paragraph {
                    Text("Best: \(Self.timeFormatter.string(from: w.bestStart)) – \(Self.timeFormatter.string(from: w.bestEnd))")
                }
                .class("info-card-best")
            }

            Div {
                infoRow("Temp", "\(Int(s.tempMin))–\(Int(s.tempMax))°F")
                infoRow("Humidity", "≤\(Int(s.humidityMax))%")
                infoRow("Rain", "≤\(Int(s.precipProbabilityMax))%")
                infoRow("Wind", "\(Int(s.windSpeedMin))–\(Int(s.windSpeedMax)) kn")
                infoRow("Clouds", "≤\(Int(s.cloudCoverMax))%")
                if let lo = s.tideHeightMin, let hi = s.tideHeightMax {
                    infoRow("Tide", "\(String(format: "%.1f", lo))–\(String(format: "%.1f", hi)) ft")
                }
            }
            .class("info-card-conditions")
        }
        .class("calendar-info-card")
    }

    @ComponentBuilder
    private func infoRow(_ label: String, _ value: String) -> Component {
        Div {
            Element(name: "span") { Text(label) }.class("info-card-label")
            Element(name: "span") { Text(value) }.class("info-card-value")
        }
        .class("info-card-row")
    }
}
