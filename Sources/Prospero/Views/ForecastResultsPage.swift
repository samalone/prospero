import Foundation
import Plot

struct ForecastResultsPage {
    var pattern: ActivityPattern
    var windows: [MatchWindow]
    var sortByQuality: Bool = false
    var hasTideData: Bool = false
    var pageContext: PageContext = PageContext()

    private var patternID: String {
        pattern.id?.uuidString ?? ""
    }

    var html: HTML {
        PageLayout(title: "\(pattern.name) Forecast", pageContext: pageContext) {
            H1 {
                Text("\(pattern.name)")
            }

            if let location = pattern.locationName {
                Paragraph(location).class("subtitle")
            }

            Paragraph {
                Text("Looking for \(Int(pattern.durationHours))-hour windows in the next 14 days.")
            }
            .class("help-text")

            if windows.isEmpty {
                Div {
                    H3("No matching windows found")
                    Paragraph("No upcoming time periods meet all your constraints. Try relaxing some of them.")
                }
                .class("empty-state")
            } else {
                Div {
                    Paragraph("\(windows.count) matching \(windows.count == 1 ? "window" : "windows") found")
                        .class("result-count")

                    Div {
                        Element(name: "span") { Text("Sort by: ") }.class("sort-label")
                        Link("Date", url: "/patterns/\(patternID)/forecast?sort=date")
                            .class(sortByQuality ? "sort-option" : "sort-option active")
                        Link("Quality", url: "/patterns/\(patternID)/forecast?sort=quality")
                            .class(sortByQuality ? "sort-option active" : "sort-option")
                    }
                    .class("sort-controls")
                }
                .class("results-header")

                Div {
                    for window in windows {
                        WindowCard(window: window, pattern: pattern, hasTideData: hasTideData)
                    }
                }
                .class("window-list")
            }

            Div {
                Link("Back to Patterns", url: "/patterns").class("button secondary")
            }
            .class("page-actions")
        }.html
    }
}

struct WindowCard: Component {
    var window: MatchWindow
    var pattern: ActivityPattern
    var hasTideData: Bool = false

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var body: Component {
        Div {
            Div {
                H3(Self.dayFormatter.string(from: window.start))

                Paragraph {
                    Text("\(Self.timeFormatter.string(from: window.start)) – \(Self.timeFormatter.string(from: window.end))")
                }
                .class("window-time")

                QualityIndicator(quality: window.quality)
            }
            .class("window-header")

            Div {
                ConditionRow(
                    label: "Temperature",
                    value: "\(Int(window.summary.tempMin))–\(Int(window.summary.tempMax))°F"
                )
                ConditionRow(
                    label: "Humidity",
                    value: "≤\(Int(window.summary.humidityMax))%"
                )
                ConditionRow(
                    label: "Precipitation",
                    value: "≤\(Int(window.summary.precipProbabilityMax))%"
                )
                ConditionRow(
                    label: "Wind",
                    value: "\(Int(window.summary.windSpeedMin))–\(Int(window.summary.windSpeedMax)) kn"
                )
                ConditionRow(
                    label: "Cloud Cover",
                    value: "≤\(Int(window.summary.cloudCoverMax))%"
                )
                if hasTideData {
                    if let lo = window.summary.tideHeightMin,
                       let hi = window.summary.tideHeightMax {
                        ConditionRow(
                            label: "Tide",
                            value: "\(String(format: "%.1f", lo))–\(String(format: "%.1f", hi)) ft \(formatTideStatuses(window.summary.tideStatuses))"
                        )
                    } else {
                        ConditionRow(
                            label: "Tide",
                            value: formatTideStatuses(window.summary.tideStatuses)
                        )
                    }
                }
            }
            .class("window-conditions")
        }
        .class("window-card")
    }
}

struct QualityIndicator: Component {
    var quality: Double

    var body: Component {
        let label: String
        let cssClass: String
        switch quality {
        case 0.75...:
            label = "Excellent"
            cssClass = "quality-excellent"
        case 0.5..<0.75:
            label = "Good"
            cssClass = "quality-good"
        case 0.25..<0.5:
            label = "Fair"
            cssClass = "quality-fair"
        default:
            label = "Marginal"
            cssClass = "quality-marginal"
        }

        return Element(name: "span") {
            Text(label)
        }
        .class("quality-badge \(cssClass)")
    }
}

struct ConditionRow: Component {
    var label: String
    var value: String

    var body: Component {
        Div {
            Element(name: "span") { Text(label) }.class("condition-label")
            Element(name: "span") { Text(value) }.class("condition-value")
        }
        .class("condition-row")
    }
}

/// Format a set of tide statuses into a human-readable summary.
private func formatTideStatuses(_ statuses: Set<TideStatus>) -> String {
    let ordered: [TideStatus] = [.rising, .high, .falling, .low]
    let present = ordered.filter { statuses.contains($0) }
    if present.isEmpty { return "N/A" }
    return present.map { $0.rawValue.capitalized }.joined(separator: " \u{2192} ")
}
