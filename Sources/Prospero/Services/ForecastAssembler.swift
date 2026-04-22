import Foundation

/// Merges weather data from Open-Meteo with tide predictions from NOAA CO-OPS
/// into a unified forecast slot timeline.
struct ForecastAssembler: Sendable {

    /// Enrich forecast slots with tide status and height.
    /// If no tide data is available, tide fields remain nil.
    func assemble(
        weather: [ForecastSlot],
        tidePredictions: [TidePrediction]?,
        tideCurve: [TideCurvePoint]?
    ) -> [ForecastSlot] {
        guard let predictions = tidePredictions, !predictions.isEmpty else {
            return weather
        }

        return weather.map { slot in
            var enriched = slot
            let status = TideClient.tideStatus(at: slot.tick, predictions: predictions)
            enriched.tideStatus = PointInTime(time: slot.tick, value: status)
            if let curve = tideCurve,
               let height = TideClient.tideHeight(at: slot.tick, curve: curve) {
                enriched.tideHeight = PointInTime(time: slot.tick, value: height)
            }
            return enriched
        }
    }
}
