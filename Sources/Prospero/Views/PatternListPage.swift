import Plot

struct PatternListPage {
    var patterns: [ActivityPattern]
    var pageContext: PageContext = PageContext()

    var html: HTML {
        PageLayout(title: "Patterns", pageContext: pageContext) {
            Div {
                H1("Activity Patterns")

                if patterns.isEmpty {
                    Paragraph {
                        Text("No patterns yet. ")
                        Link("Create one", url: mountURL("/patterns/new"))
                        Text(" to get started.")
                    }
                    .class("empty-state")
                } else {
                    Div {
                        for pattern in patterns {
                            PatternCard(pattern: pattern)
                        }
                    }
                    .class("pattern-grid")
                }
            }
        }.html
    }
}

struct PatternCard: Component {
    var pattern: ActivityPattern

    /// Tide heights are displayed to one decimal ("2.5 ft").
    private func tideFt(_ v: Double) -> String { String(format: "%.1f", v) }

    var body: Component {
        Div {
            H3 {
                Link(pattern.name, url: mountURL("/patterns/\(pattern.id?.uuidString ?? "")/forecast"))
            }

            if let location = pattern.locationName {
                Paragraph(location).class("location")
            }

            Div {
                if let min = pattern.temperatureMin, let max = pattern.temperatureMax {
                    ConstraintBadge(label: "Temp", value: "\(Int(min))–\(Int(max))°F")
                } else if let min = pattern.temperatureMin {
                    ConstraintBadge(label: "Temp", value: "≥\(Int(min))°F")
                } else if let max = pattern.temperatureMax {
                    ConstraintBadge(label: "Temp", value: "≤\(Int(max))°F")
                }

                if let max = pattern.humidityMax {
                    ConstraintBadge(label: "Humidity", value: "≤\(Int(max))%")
                }

                if let max = pattern.precipProbabilityMax {
                    ConstraintBadge(label: "Rain", value: "≤\(Int(max))%")
                }

                if let max = pattern.windSpeedMax {
                    ConstraintBadge(label: "Wind", value: "≤\(Int(max)) kn")
                } else if let min = pattern.windSpeedMin {
                    ConstraintBadge(label: "Wind", value: "≥\(Int(min)) kn")
                }

                if let max = pattern.cloudCoverMax {
                    ConstraintBadge(label: "Clouds", value: "≤\(Int(max))%")
                }

                if let min = pattern.tideHeightMin, let max = pattern.tideHeightMax {
                    ConstraintBadge(label: "Tide", value: "\(tideFt(min))–\(tideFt(max)) ft")
                } else if let min = pattern.tideHeightMin {
                    ConstraintBadge(label: "Tide", value: "≥\(tideFt(min)) ft")
                } else if let max = pattern.tideHeightMax {
                    ConstraintBadge(label: "Tide", value: "≤\(tideFt(max)) ft")
                }

                ConstraintBadge(
                    label: "Duration",
                    value: pattern.durationHours == 1 ? "1 hour" : "\(Int(pattern.durationHours)) hours"
                )
            }
            .class("constraint-badges")

            Div {
                Link("Forecast", url: mountURL("/patterns/\(pattern.id?.uuidString ?? "")/forecast"))
                    .class("button")
                Link("Edit", url: mountURL("/patterns/\(pattern.id?.uuidString ?? "")/edit"))
                    .class("button secondary")
            }
            .class("card-actions")
        }
        .class("pattern-card")
        .attribute(named: "style",
                   value: "--goal-color: \(HuePlacer.goalColor(hue: pattern.hue))")
    }
}

struct ConstraintBadge: Component {
    var label: String
    var value: String

    var body: Component {
        Element(name: "span") {
            Element(name: "strong") { Text(label) }
            Text(" \(value)")
        }
        .class("badge")
    }
}
