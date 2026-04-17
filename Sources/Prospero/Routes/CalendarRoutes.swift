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

func addCalendarRoutes(
    to router: RouterGroup<AuthedContext>,
    db: Database,
    logger: Logger
) {
    let meteoClient = OpenMeteoClient()
    let tideClient = TideClient()
    let assembler = ForecastAssembler()
    let matcher = PatternMatcher()

    router.get("/calendar") { request, context -> PageLayout in
        let userID = context.user.id!

        let patterns = try await ActivityPattern.query(on: db)
            .filter(\.$userID == userID)
            .sort(\.$name)
            .all()

        // Collect all match windows across all patterns, running the
        // heavy per-pattern work concurrently.
        var allWindows: [CalendarWindow] = []
        try await withThrowingTaskGroup(of: [CalendarWindow].self) { group in
            for pattern in patterns {
                group.addTask {
                    let weather = try await meteoClient.fetchHourlyForecast(
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
                        weather: weather,
                        tidePredictions: tidePredictions,
                        tideCurve: tideCurve
                    )
                    let windows = matcher.findWindows(
                        pattern: pattern, conditions: conditions
                    )
                    return windows.map {
                        CalendarWindow(
                            patternName: pattern.name,
                            hue: pattern.hue,
                            window: $0
                        )
                    }
                }
            }
            for try await windows in group {
                allWindows.append(contentsOf: windows)
            }
        }

        allWindows.sort { $0.window.start < $1.window.start }

        return PageLayout(title: "Calendar", pageContext: PageContext(from: context)) {
            CalendarView(
                windows: allWindows,
                patterns: patterns
            )
        }
    }
}
