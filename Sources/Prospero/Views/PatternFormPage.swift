import HummingbirdAuthViews
import Plot

struct PatternFormPage {
    var pattern: ActivityPattern?
    var pageContext: PageContext = PageContext()
    var isEditing: Bool { pattern != nil }

    var html: HTML {
        PageLayout(
            title: isEditing ? "Edit Pattern" : "New Pattern",
            pageContext: pageContext,
            includeMapScript: true,
            includeRangeSliderScript: true
        ) {
            H1(isEditing ? "Edit Pattern" : "New Pattern")

            Element(name: "form") {
                // CSRF token shared by both the primary submit (create or
                // update) and the "Delete Pattern" button's formaction
                // override — all three POSTs run through CSRFMiddleware.
                CSRFField(pageContext.csrfToken)

                // Name
                FormField(label: "Activity Name", name: "name", type: "text",
                          value: pattern?.name, placeholder: "e.g., Fiberglassing", required: true)

                // Location
                Element(name: "fieldset") {
                    Element(name: "legend") { Text("Location") }

                    FormField(label: "Location Name", name: "location_name", type: "text",
                              value: pattern?.locationName ?? "Edgewood Yacht Club")

                    Paragraph("Click the map to pick a location, or a blue pin to select a NOAA tide station. The fields below update automatically.")
                        .class("help-text")

                    // Map container — pattern-map.js picks it up by id.
                    // Initial lat/lng/station come from the form inputs
                    // below so defaults and existing pattern values stay
                    // consistent with what the map shows.
                    Div {}
                        .id("pattern-map")
                        .class("pattern-map")
                        .attribute(named: "data-stations-url",
                                   value: mountURL("/patterns/tide-stations.json"))

                    Div {
                        FormField(label: "Latitude", name: "latitude", type: "number",
                                  value: pattern.map { String($0.latitude) } ?? "41.777",
                                  required: true, step: "0.0001")
                        FormField(label: "Longitude", name: "longitude", type: "number",
                                  value: pattern.map { String($0.longitude) } ?? "-71.3925",
                                  required: true, step: "0.0001")
                    }
                    .class("form-row")

                    FormField(label: "NOAA Tide Station", name: "tide_station", type: "text",
                              value: pattern?.tideStation ?? "8453767")
                }

                // Duration — single-value slider (always has a value).
                RangeSliderField(
                    title: "Required Duration",
                    lowName: "duration_hours",
                    lowValue: pattern.map { String($0.durationHours) } ?? "4",
                    min: 0.5, max: 12, step: 0.5,
                    unit: " hr", mode: "value",
                    labelValue: "{value}{unit}"
                )

                // Weather Constraints — dual/single-ended sliders with
                // "no limit" endpoints. Leftmost thumb at min or rightmost
                // at max submits empty (nil) to the backend.
                Element(name: "fieldset") {
                    Element(name: "legend") { Text("Weather Constraints") }
                    Paragraph("Drag a thumb to the track's end to remove that limit.")
                        .class("help-text")

                    RangeSliderField(
                        title: "Temperature",
                        lowName: "temperature_min", highName: "temperature_max",
                        lowValue: pattern?.temperatureMin.map { String(Int($0)) },
                        highValue: pattern?.temperatureMax.map { String(Int($0)) },
                        min: 20, max: 100, step: 1,
                        unit: "°F",
                        labelAny: "Any temperature",
                        labelBelow: "Below {high}{unit}",
                        labelAbove: "Above {low}{unit}",
                        labelBetween: "{low}–{high}{unit}",
                        colorScheme: "temperature"
                    )

                    RangeSliderField(
                        title: "Humidity",
                        highName: "humidity_max",
                        highValue: pattern?.humidityMax.map { String(Int($0)) },
                        min: 0, max: 100, step: 5,
                        unit: "%",
                        labelAny: "Any humidity",
                        labelBelow: "Below {high}{unit}"
                    )

                    RangeSliderField(
                        title: "Rain probability",
                        lowName: "precip_probability_min",
                        highName: "precip_probability_max",
                        lowValue: pattern?.precipProbabilityMin.map { String(Int($0)) },
                        highValue: pattern?.precipProbabilityMax.map { String(Int($0)) },
                        min: 0, max: 100, step: 5,
                        unit: "%",
                        labelAny: "Any rain probability",
                        labelBelow: "Below {high}{unit}",
                        labelAbove: "Above {low}{unit}",
                        labelBetween: "{low}–{high}{unit}"
                    )

                    RangeSliderField(
                        title: "Wind speed",
                        lowName: "wind_speed_min", highName: "wind_speed_max",
                        lowValue: pattern?.windSpeedMin.map { String(Int($0)) },
                        highValue: pattern?.windSpeedMax.map { String(Int($0)) },
                        min: 0, max: 40, step: 1,
                        unit: " kn",
                        labelAny: "Any wind",
                        labelBelow: "Below {high}{unit}",
                        labelAbove: "Above {low}{unit}",
                        labelBetween: "{low}–{high}{unit}",
                        colorScheme: "wind"
                    )

                    RangeSliderField(
                        title: "Cloud cover",
                        highName: "cloud_cover_max",
                        highValue: pattern?.cloudCoverMax.map { String(Int($0)) },
                        min: 0, max: 100, step: 5,
                        unit: "%",
                        labelAny: "Any cloud cover",
                        labelBelow: "Below {high}{unit}"
                    )
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

                    // Time of day — dual slider, 12-hour clock.
                    RangeSliderField(
                        title: "Time of day",
                        lowName: "earliest_hour", highName: "latest_hour",
                        lowValue: pattern?.earliestHour.map { String($0) },
                        highValue: pattern?.latestHour.map { String($0) },
                        min: 0, max: 23, step: 1,
                        format: "hour12",
                        labelAny: "Any time of day",
                        labelBelow: "Before {high}",
                        labelAbove: "After {low}",
                        labelBetween: "{low} – {high}"
                    )

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

                    RangeSliderField(
                        title: "Tide height",
                        lowName: "tide_height_min", highName: "tide_height_max",
                        lowValue: pattern?.tideHeightMin.map { String(format: "%.1f", $0) },
                        highValue: pattern?.tideHeightMax.map { String(format: "%.1f", $0) },
                        min: 0, max: 8, step: 0.5,
                        unit: " ft",
                        labelAny: "Any tide height",
                        labelBelow: "Below {high}{unit}",
                        labelAbove: "Above {low}{unit}",
                        labelBetween: "{low}–{high}{unit}"
                    )
                }

                // Color picker. Leaving "Lock this color" unchecked lets
                // Prospero auto-assign a color that contrasts with your
                // other patterns (whether new or existing).
                Element(name: "fieldset") {
                    Element(name: "legend") { Text("Color") }
                    Paragraph("Drag the slider to pick a color, or leave \"Lock this color\" unchecked and Prospero will auto-assign one that contrasts with your other patterns.")
                        .class("help-text")

                    Div {
                        Node.input(
                            .type(.range),
                            .name("hue"),
                            .id("hue"),
                            .attribute(named: "min", value: "0"),
                            .attribute(named: "max", value: "359"),
                            .attribute(named: "step", value: "1"),
                            .value(String(format: "%.0f", pattern?.hue ?? 0))
                        )
                        .class("hue-slider")
                        .attribute(named: "oninput",
                                   value: "this.nextElementSibling.style.background = 'oklch(65% 0.18 ' + this.value + ')'; document.getElementById('is_hue_fixed').checked = true;")

                        Element(name: "span") {}
                            .class("hue-swatch")
                            .attribute(named: "style",
                                       value: "background: oklch(65% 0.18 \(String(format: "%.0f", pattern?.hue ?? 0)))")
                    }
                    .class("hue-picker")

                    Div {
                        Element(name: "label") {
                            Node.input(
                                .type(.checkbox),
                                .name("is_hue_fixed"),
                                .id("is_hue_fixed"),
                                .value("true")
                            )
                            .checked(pattern?.isHueFixed ?? false)
                            Text(" Lock this color")
                        }
                    }
                    .class("checkbox-field")
                }

                Div {
                    Element(name: "button") {
                        Text(isEditing ? "Update Pattern" : "Create Pattern")
                    }
                    .type("submit")
                    .class("button primary")

                    // Delete uses formaction to override the outer form's
                    // action without needing a nested form. `formnovalidate`
                    // lets delete work even if other fields are blank or
                    // invalid. A confirm() catches accidental clicks.
                    if isEditing, let id = pattern?.id?.uuidString {
                        Element(name: "button") { Text("Delete Pattern") }
                            .type("submit")
                            .class("button danger")
                            .attribute(named: "formaction",
                                       value: mountURL("/patterns/\(id)/delete"))
                            .attribute(named: "formnovalidate", value: "formnovalidate")
                            .attribute(
                                named: "onclick",
                                value: "return confirm('Delete this pattern? This can\\'t be undone.')"
                            )
                    }
                }
                .class("form-actions")
            }
            .attribute(named: "method", value: "POST")
            .attribute(
                named: "action",
                value: mountURL(isEditing ? "/patterns/\(pattern!.id!.uuidString)" : "/patterns")
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

/// A slider-driven form field backed by one or two hidden inputs.
///
/// The `range-slider.js` component picks this up by class, reads the
/// bounds / labels / input IDs from data attributes, and renders a
/// touch-friendly track with one or two thumbs. The hidden inputs
/// carry the values back to the server under their existing names;
/// empty string still means "no limit" just like the old text inputs.
///
/// Modes:
/// - `mode: "range"` (default) — endpoint positions mean "no limit."
///   Combine `lowName` and/or `highName` for dual / single-ended use.
/// - `mode: "value"` — always submits a value; used for duration etc.
struct RangeSliderField: Component {
    var title: String
    var lowName: String? = nil
    var highName: String? = nil
    var lowValue: String? = nil
    var highValue: String? = nil
    var min: Double
    var max: Double
    var step: Double = 1
    var unit: String = ""
    var mode: String = "range"
    /// Optional client-side format hint (e.g. `"hour12"` for AM/PM).
    var format: String = ""
    var labelAny: String = "Any"
    var labelBelow: String = "Below {high}{unit}"
    var labelAbove: String = "Above {low}{unit}"
    var labelBetween: String = "{low}–{high}{unit}"
    var labelValue: String = "{value}{unit}"
    /// Semantic color scheme name (applied as `range-slider--<name>`
    /// + `range-slider--gradient`). Empty = plain primary-blue fill.
    var colorScheme: String = ""

    /// Format a Double the way JS's parseFloat wants — no trailing `.0`.
    private func fmt(_ d: Double) -> String {
        if d == d.rounded() { return String(Int(d)) }
        return String(d)
    }

    var body: Component {
        // Pre-compute strings that would otherwise require ternaries or
        // fallbacks inside the @ComponentBuilder closure.
        let sliderClass = colorScheme.isEmpty
            ? "range-slider"
            : "range-slider range-slider--gradient range-slider--\(colorScheme)"

        return Div {
            Element(name: "label") { Text(title) }
                .class("range-slider-title")

            // Hidden inputs the slider writes into. The form submit
            // sends these under their familiar names.
            if let name = lowName {
                Node.input(.name(name), .id(name), .value(lowValue ?? ""))
                    .attribute(named: "type", value: "hidden")
            }
            if let name = highName {
                Node.input(.name(name), .id(name), .value(highValue ?? ""))
                    .attribute(named: "type", value: "hidden")
            }

            Div {}
                .class(sliderClass)
                .attribute(named: "data-min", value: fmt(min))
                .attribute(named: "data-max", value: fmt(max))
                .attribute(named: "data-step", value: fmt(step))
                .attribute(named: "data-unit", value: unit)
                .attribute(named: "data-mode", value: mode)
                .conditionalAttribute(!format.isEmpty,
                                      named: "data-format", value: format)
                .conditionalAttribute(lowName != nil,
                                      named: "data-low-input", value: lowName ?? "")
                .conditionalAttribute(highName != nil,
                                      named: "data-high-input", value: highName ?? "")
                .attribute(named: "data-label-any", value: labelAny)
                .attribute(named: "data-label-below", value: labelBelow)
                .attribute(named: "data-label-above", value: labelAbove)
                .attribute(named: "data-label-between", value: labelBetween)
                .attribute(named: "data-label-value", value: labelValue)
        }
        .class("form-field range-slider-field")
    }
}
