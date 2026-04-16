import Foundation
import Plot

struct ForecastResultsPage {
    var pattern: ActivityPattern
    var windows: [MatchWindow]

    var html: HTML {
        PageLayout(title: "\(pattern.name) Forecast") {
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
                Paragraph("\(windows.count) matching \(windows.count == 1 ? "window" : "windows") found:")
                    .class("result-count")

                Div {
                    for window in windows {
                        WindowCard(window: window, pattern: pattern)
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
                    value: "\(Int(window.summary.windSpeedMin))–\(Int(window.summary.windSpeedMax)) mph"
                )
                ConditionRow(
                    label: "Cloud Cover",
                    value: "≤\(Int(window.summary.cloudCoverMax))%"
                )
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
