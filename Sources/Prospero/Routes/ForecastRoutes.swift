import FluentKit
import Foundation
import Hummingbird
import Logging
import Plot

func addForecastRoutes(
    to router: Router<BasicRequestContext>,
    db: Database,
    logger: Logger
) {
    let meteoClient = OpenMeteoClient()
    let matcher = PatternMatcher()

    router.get("/patterns/:id/forecast") { _, context -> HTML in
        guard let id = context.parameters.get("id", as: UUID.self),
              let pattern = try await ActivityPattern.find(id, on: db) else {
            throw HTTPError(.notFound)
        }

        let conditions = try await meteoClient.fetchHourlyForecast(
            latitude: pattern.latitude,
            longitude: pattern.longitude
        )

        let windows = matcher.findWindows(pattern: pattern, conditions: conditions)

        return ForecastResultsPage(pattern: pattern, windows: windows).html
    }
}
