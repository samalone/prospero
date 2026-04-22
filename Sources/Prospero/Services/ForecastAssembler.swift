import Foundation

/// Merges weather data from Open-Meteo with tide predictions from NOAA CO-OPS
/// into a unified forecast slot timeline.
struct ForecastAssembler: Sendable {

    /// How often to sample tide status across a slot. 15 minutes gives
    /// us four samples per hour — enough to always catch a high/low
    /// extremum, since `TideClient.tideStatus` reports `.high`/`.low`
    /// for 30 minutes on either side of the event.
    private static let tideSampleStride: TimeInterval = 15 * 60

    /// Enrich forecast slots with tide status and height across each
    /// slot's forward hour.
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
            enriched.tideStatuses = Self.statuses(
                in: slot.tick, predictions: predictions
            )
            if let curve = tideCurve {
                enriched.tideHeightRange = Self.heightRange(
                    in: slot.tick, curve: curve
                )
            }
            return enriched
        }
    }

    /// Union of tide statuses across the slot `[tick, tick + 1h)`,
    /// sampled every 15 minutes.
    private static func statuses(
        in tick: Date, predictions: [TidePrediction]
    ) -> Set<TideStatus> {
        var result: Set<TideStatus> = []
        var offset: TimeInterval = 0
        while offset < 3600 {
            let sampleTime = tick.addingTimeInterval(offset)
            result.insert(TideClient.tideStatus(at: sampleTime, predictions: predictions))
            offset += tideSampleStride
        }
        return result
    }

    /// Min/max tide height across `[tick, tick + 1h)` from the 6-minute
    /// prediction curve. Returns nil if the slot falls outside the
    /// curve's coverage.
    private static func heightRange(
        in tick: Date, curve: [TideCurvePoint]
    ) -> ClosedRange<Double>? {
        let end = tick.addingTimeInterval(3600)
        var lo: Double = .infinity
        var hi: Double = -.infinity
        var found = false
        for point in curve where point.time >= tick && point.time < end {
            if point.height < lo { lo = point.height }
            if point.height > hi { hi = point.height }
            found = true
        }
        guard found else { return nil }
        return lo...hi
    }
}
