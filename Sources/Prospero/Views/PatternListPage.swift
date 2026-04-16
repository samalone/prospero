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
                        Link("Create one", url: "/patterns/new")
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

    var body: Component {
        Div {
            H3 {
                Link(pattern.name, url: "/patterns/\(pattern.id?.uuidString ?? "")/forecast")
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

                if let min = pattern.tideHeightMin {
                    ConstraintBadge(label: "Tide", value: "≥\(String(format: "%.1f", min)) ft")
                }

                ConstraintBadge(
                    label: "Duration",
                    value: pattern.durationHours == 1 ? "1 hour" : "\(Int(pattern.durationHours)) hours"
                )
            }
            .class("constraint-badges")

            Div {
                Link("Forecast", url: "/patterns/\(pattern.id?.uuidString ?? "")/forecast")
                    .class("button")
                Link("Edit", url: "/patterns/\(pattern.id?.uuidString ?? "")/edit")
                    .class("button secondary")
            }
            .class("card-actions")
        }
        .class("pattern-card")
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
