import Plot

struct PatternFormPage {
    var pattern: ActivityPattern?
    var pageContext: PageContext = PageContext()
    var isEditing: Bool { pattern != nil }

    var html: HTML {
        PageLayout(title: isEditing ? "Edit Pattern" : "New Pattern", pageContext: pageContext) {
            H1(isEditing ? "Edit Pattern" : "New Pattern")

            Element(name: "form") {
                // Name
                FormField(label: "Activity Name", name: "name", type: "text",
                          value: pattern?.name, placeholder: "e.g., Fiberglassing", required: true)

                // Location
                Element(name: "fieldset") {
                    Element(name: "legend") { Text("Location") }

                    FormField(label: "Location Name", name: "location_name", type: "text",
                              value: pattern?.locationName, placeholder: "e.g., Edgewood Yacht Club")

                    Div {
                        FormField(label: "Latitude", name: "latitude", type: "number",
                                  value: pattern.map { String($0.latitude) },
                                  placeholder: "41.777", required: true,
                                  step: "0.0001")
                        FormField(label: "Longitude", name: "longitude", type: "number",
                                  value: pattern.map { String($0.longitude) },
                                  placeholder: "-71.393", required: true,
                                  step: "0.0001")
                    }
                    .class("form-row")

                    FormField(label: "NOAA Tide Station", name: "tide_station", type: "text",
                              value: pattern?.tideStation, placeholder: "e.g., 8453767 (optional)")
                }

                // Duration
                FormField(label: "Required Duration (hours)", name: "duration_hours", type: "number",
                          value: pattern.map { String($0.durationHours) } ?? "4",
                          required: true, step: "0.5", min: "1", max: "24")

                // Weather Constraints
                Element(name: "fieldset") {
                    Element(name: "legend") { Text("Weather Constraints") }
                    Paragraph("Leave blank for no constraint.").class("help-text")

                    Div {
                        FormField(label: "Min Temp (°F)", name: "temperature_min", type: "number",
                                  value: pattern?.temperatureMin.map { String(Int($0)) },
                                  placeholder: "50")
                        FormField(label: "Max Temp (°F)", name: "temperature_max", type: "number",
                                  value: pattern?.temperatureMax.map { String(Int($0)) },
                                  placeholder: "85")
                    }
                    .class("form-row")

                    FormField(label: "Max Humidity (%)", name: "humidity_max", type: "number",
                              value: pattern?.humidityMax.map { String(Int($0)) },
                              placeholder: "70", max: "100")

                    FormField(label: "Max Precipitation Probability (%)", name: "precip_probability_max",
                              type: "number",
                              value: pattern?.precipProbabilityMax.map { String(Int($0)) },
                              placeholder: "20", max: "100")

                    Div {
                        FormField(label: "Min Wind (kn)", name: "wind_speed_min", type: "number",
                                  value: pattern?.windSpeedMin.map { String(Int($0)) },
                                  placeholder: "5")
                        FormField(label: "Max Wind (kn)", name: "wind_speed_max", type: "number",
                                  value: pattern?.windSpeedMax.map { String(Int($0)) },
                                  placeholder: "15")
                    }
                    .class("form-row")

                    FormField(label: "Max Cloud Cover (%)", name: "cloud_cover_max", type: "number",
                              value: pattern?.cloudCoverMax.map { String(Int($0)) },
                              placeholder: "50", max: "100")
                }

                // Scheduling
                Element(name: "fieldset") {
                    Element(name: "legend") { Text("Scheduling Constraints") }

                    Div {
                        Element(name: "label") {
                            Node.input(
                                .name("requires_daylight"),
                                .value("true")
                            )
                            .attribute(named: "type", value: "checkbox")
                            .checked(pattern?.requiresDaylight ?? true)
                            Text(" Daylight required")
                        }
                    }
                    .class("checkbox-field")

                    Div {
                        FormField(label: "Earliest Hour", name: "earliest_hour", type: "number",
                                  value: pattern?.earliestHour.map { String($0) },
                                  placeholder: "8", min: "0", max: "23")
                        FormField(label: "Latest Hour", name: "latest_hour", type: "number",
                                  value: pattern?.latestHour.map { String($0) },
                                  placeholder: "18", min: "0", max: "23")
                    }
                    .class("form-row")

                    Div {
                        Element(name: "label") {
                            Text("Tide Requirement")
                        }
                        Element(name: "select") {
                            for req in TideRequirement.allCases {
                                Element(name: "option") {
                                    Text(req.rawValue.capitalized)
                                }
                                .attribute(named: "value", value: req.rawValue)
                                .conditionalAttribute(
                                    pattern?.tideRequirement == req,
                                    named: "selected",
                                    value: "selected"
                                )
                            }
                        }
                        .attribute(named: "name", value: "tide_requirement")
                    }
                    .class("form-field")

                    FormField(label: "Min Tide Height (ft MLLW)", name: "tide_height_min",
                              type: "number",
                              value: pattern?.tideHeightMin.map { String(format: "%.1f", $0) },
                              placeholder: "e.g., 4.0", step: "0.1")
                }

                Div {
                    Element(name: "button") {
                        Text(isEditing ? "Update Pattern" : "Create Pattern")
                    }
                    .type("submit")
                    .class("button primary")
                }
                .class("form-actions")
            }
            .attribute(named: "method", value: "POST")
            .attribute(
                named: "action",
                value: isEditing ? "/patterns/\(pattern!.id!.uuidString)" : "/patterns"
            )
        }.html
    }
}

/// A labeled form field component.
struct FormField: Component {
    var label: String
    var name: String
    var type: String
    var value: String?
    var placeholder: String?
    var required: Bool = false
    var step: String?
    var min: String?
    var max: String?

    var body: Component {
        Div {
            Element(name: "label") {
                Text(label)
            }
            .attribute(named: "for", value: name)

            Node.input(
                .name(name),
                .id(name)
            )
            .attribute(named: "type", value: type)
            .conditionalAttribute(value != nil, named: "value", value: value ?? "")
            .conditionalAttribute(placeholder != nil, named: "placeholder", value: placeholder ?? "")
            .conditionalAttribute(required, named: "required", value: "required")
            .conditionalAttribute(step != nil, named: "step", value: step ?? "")
            .conditionalAttribute(min != nil, named: "min", value: min ?? "")
            .conditionalAttribute(max != nil, named: "max", value: max ?? "")
        }
        .class("form-field")
    }
}
