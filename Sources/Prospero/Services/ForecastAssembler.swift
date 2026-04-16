import Foundation

/// Merges weather data from Open-Meteo with tide predictions from NOAA CO-OPS
/// into a unified hourly conditions timeline.
struct ForecastAssembler: Sendable {

    /// Enrich hourly weather conditions with tide status and height.
    /// If no tide data is available, tide fields remain at defaults.
    func assemble(
        weather: [HourlyConditions],
        tidePredictions: [TidePrediction]?,
        tideCurve: [TideCurvePoint]?
    ) -> [HourlyConditions] {
        guard let predictions = tidePredictions, !predictions.isEmpty else {
            return weather
        }

        return weather.map { hour in
            var enriched = hour
            enriched.tideStatus = TideClient.tideStatus(at: hour.date, predictions: predictions)
            if let curve = tideCurve {
                enriched.tideHeight = TideClient.tideHeight(at: hour.date, curve: curve)
            }
            return enriched
        }
    }
}
