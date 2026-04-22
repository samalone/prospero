import FluentKit
import Foundation
import Hummingbird
import Logging
import Plot

func addForecastRoutes(
    to router: RouterGroup<AuthedContext>,
    db: Database,
    logger: Logger,
    meteoClient: OpenMeteoClient,
    tideClient: TideClient
) {
    let assembler = ForecastAssembler()
    let matcher = PatternMatcher()

    router.get("/patterns/:id/forecast") { request, context -> HTML in
        guard let id = context.parameters.get("id", as: UUID.self),
              let pattern = try await ActivityPattern.query(on: db)
                .filter(\.$id == id)
                .filter(\.$userID == context.user.id!)
                .first()
        else {
            throw HTTPError(.notFound)
        }

        let sortParam = request.uri.queryParameters.get("sort") ?? "quality"
        let sortByQuality = sortParam == "quality"

        // Fetch weather data (full Forecast — we need solar + timezone
        // for the daylight and hour-of-day checks).
        let forecast = try await meteoClient.fetchForecast(
            latitude: pattern.latitude,
            longitude: pattern.longitude
        )
        let weather = forecast.hourly

        // Fetch tide data if a station is configured.
        var tidePredictions: [TidePrediction]?
        var tideCurve: [TideCurvePoint]?
        if let station = pattern.tideStation, !station.isEmpty {
            do {
                async let predsTask = tideClient.fetchPredictions(station: station)
                async let curveTask = tideClient.fetchTideCurve(station: station)
                tidePredictions = try await predsTask
                tideCurve = try await curveTask
            } catch {
                logger.warning("Tide fetch failed for station \(station): \(error)")
            }
        }

        // Merge weather + tides into unified timeline.
        let conditions = assembler.assemble(
            weather: weather,
            tidePredictions: tidePredictions,
            tideCurve: tideCurve
        )

        var windows = matcher.findWindows(
            pattern: pattern, conditions: conditions,
            solar: forecast.solar, timezone: forecast.timezone
        )
        if sortByQuality {
            windows.sort { $0.quality > $1.quality }
        }

        let pc = PageContext(from: context)
        return ForecastResultsPage(
            pattern: pattern,
            windows: windows,
            sortByQuality: sortByQuality,
            hasTideData: tidePredictions != nil,
            pageContext: pc
        ).html
    }
}
