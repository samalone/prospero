import FluentKit
import Foundation
import Hummingbird
import HummingbirdAuth
import Logging
import Plot

/// A match window tagged with its pattern, for calendar rendering.
struct CalendarWindow: Sendable {
    var patternName: String
    var hue: Double
    var window: MatchWindow
}

/// One pattern's per-day sunrise/sunset, keyed by local midnight.
///
/// The calendar shades each day's nighttime hours based on the first
/// pattern assigned to that row's track; we precompute the lookup here
/// so the view doesn't have to.
struct PatternSolar: Sendable {
    var patternName: String
    /// Key: local midnight of the day. Value: (sunrise, sunset).
    var byDay: [Date: (sunrise: Date, sunset: Date)]
}

func addCalendarRoutes(
    to router: RouterGroup<AuthedContext>,
    db: Database,
    logger: Logger,
    meteoClient: OpenMeteoClient,
    tideClient: TideClient
) {
    let assembler = ForecastAssembler()
    let matcher = PatternMatcher()

    router.get("/calendar") { request, context -> PageLayout in
        let userID = context.user.id!

        let patterns = try await ActivityPattern.query(on: db)
            .filter(\.$userID == userID)
            .sort(\.$name)
            .all()

        struct PatternResult: Sendable {
            var windows: [CalendarWindow]
            var solar: PatternSolar
        }

        // Collect all match windows + per-pattern solar days concurrently.
        var allWindows: [CalendarWindow] = []
        var solarByPattern: [String: PatternSolar] = [:]

        try await withThrowingTaskGroup(of: PatternResult.self) { group in
            for pattern in patterns {
                group.addTask {
                    let forecast = try await meteoClient.fetchForecast(
                        latitude: pattern.latitude,
                        longitude: pattern.longitude
                    )

                    var tidePredictions: [TidePrediction]?
                    var tideCurve: [TideCurvePoint]?
                    if let station = pattern.tideStation, !station.isEmpty {
                        do {
                            async let preds = tideClient.fetchPredictions(station: station)
                            async let curve = tideClient.fetchTideCurve(station: station)
                            tidePredictions = try await preds
                            tideCurve = try await curve
                        } catch {
                            logger.warning("Tide fetch failed for \(pattern.name): \(error)")
                        }
                    }

                    let conditions = assembler.assemble(
                        weather: forecast.hourly,
                        tidePredictions: tidePredictions,
                        tideCurve: tideCurve
                    )
                    let windows = matcher.findWindows(
                        pattern: pattern, conditions: conditions,
                        solar: forecast.solar, timezone: forecast.timezone
                    )
                    let wrapped = windows.map {
                        CalendarWindow(
                            patternName: pattern.name,
                            hue: pattern.hue,
                            window: $0
                        )
                    }

                    var byDay: [Date: (sunrise: Date, sunset: Date)] = [:]
                    for d in forecast.solar {
                        byDay[d.dayStart] = (d.sunrise, d.sunset)
                    }

                    return PatternResult(
                        windows: wrapped,
                        solar: PatternSolar(patternName: pattern.name, byDay: byDay)
                    )
                }
            }
            for try await r in group {
                allWindows.append(contentsOf: r.windows)
                solarByPattern[r.solar.patternName] = r.solar
            }
        }

        allWindows.sort { $0.window.start < $1.window.start }

        return PageLayout(title: "Calendar", pageContext: PageContext(from: context)) {
            CalendarView(
                windows: allWindows,
                patterns: patterns,
                solarByPattern: solarByPattern
            )
        }
    }
}
