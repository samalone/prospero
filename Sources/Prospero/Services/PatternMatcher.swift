import Foundation

/// A time window that matches an activity pattern's constraints.
struct MatchWindow: Sendable {
    /// Start of the full qualifying range.
    var start: Date
    /// End of the full qualifying range (exclusive).
    var end: Date
    /// Start of the best-scoring sub-window within the qualifying range.
    var bestStart: Date
    /// End of the best-scoring sub-window (exclusive).
    var bestEnd: Date
    /// Number of contiguous qualifying hours in the full range.
    var hours: Int
    /// Quality score 0.0–1.0 (1.0 = ideal center of all constraint ranges).
    var quality: Double
    /// Summary conditions across the best sub-window.
    var summary: ConditionsSummary
}

/// Aggregated conditions across a match window.
struct ConditionsSummary: Sendable {
    var tempMin: Double
    var tempMax: Double
    var humidityMax: Double
    var precipProbabilityMax: Double
    var windSpeedMin: Double
    var windSpeedMax: Double
    var cloudCoverMax: Double
    var tideStatuses: Set<TideStatus>
    var tideHeightMin: Double?
    var tideHeightMax: Double?
}

/// Groups contiguous qualifying hours into match windows.
struct PatternMatcher: Sendable {

    /// Find all windows in the forecast that satisfy the pattern's constraints.
    ///
    /// Returns non-overlapping windows of at least `pattern.durationHours` length,
    /// grouped by contiguous qualifying hour ranges.
    ///
    /// `solar` is consulted for `requiresDaylight`: each candidate hour must
    /// fall entirely between sunrise and sunset on the matching local date.
    /// `timezone` is the pattern's local zone — used for "hour of day" and
    /// "which solar day" lookups. Both are read from `Forecast` on the
    /// calling side so they travel with the data they describe.
    func findWindows(
        pattern: ActivityPattern,
        conditions: [ForecastSlot],
        solar: [SolarDay],
        timezone: TimeZone
    ) -> [MatchWindow] {
        let requiredHours = max(1, Int(ceil(pattern.durationHours)))

        // Index solar days by local calendar date so a 3 AM hour looks up
        // the previous midnight's entry, not the next one.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let solarByDay: [Date: SolarDay] = Dictionary(
            uniqueKeysWithValues: solar.map { (calendar.startOfDay(for: $0.dayStart), $0) }
        )

        // Step 1: Mark each slot as qualifying or not.
        let qualifying = conditions.map { slot in
            passesConstraints(
                slot: slot, pattern: pattern,
                calendar: calendar, solarByDay: solarByDay
            )
        }

        // Step 2: Find contiguous ranges of qualifying slots.
        let ranges = findContiguousRanges(qualifying)

        // Step 3: For each range long enough, produce the best window.
        var windows: [MatchWindow] = []
        for range in ranges where range.count >= requiredHours {
            let slice = Array(conditions[range])

            // Find the best-scoring sub-window of the required length.
            var bestStart = 0
            var bestQuality = -1.0
            for offset in 0...(slice.count - requiredHours) {
                let subSlice = Array(slice[offset..<(offset + requiredHours)])
                let q = qualityScore(slots: subSlice, pattern: pattern)
                if q > bestQuality {
                    bestQuality = q
                    bestStart = offset
                }
            }

            let windowSlice = Array(slice[bestStart..<(bestStart + requiredHours)])

            let fullStart = conditions[range.lowerBound].tick
            let fullEnd = conditions[range.upperBound - 1].tick.addingTimeInterval(3600)
            let bestStartDate = conditions[range.lowerBound + bestStart].tick
            let bestEndDate = conditions[range.lowerBound + bestStart + requiredHours - 1].tick
                .addingTimeInterval(3600)

            windows.append(MatchWindow(
                start: fullStart,
                end: fullEnd,
                bestStart: bestStartDate,
                bestEnd: bestEndDate,
                hours: slice.count,
                quality: bestQuality,
                summary: summarize(windowSlice)
            ))
        }

        return windows.sorted { $0.start < $1.start }
    }

    // MARK: - Constraint Checking

    private func passesConstraints(
        slot: ForecastSlot,
        pattern: ActivityPattern,
        calendar: Calendar,
        solarByDay: [Date: SolarDay]
    ) -> Bool {
        // Daylight: the full forward hour [slot.tick, slot.tick + 1h) must
        // fall inside [sunrise, sunset] for the pattern's local day. Using
        // `SolarDay` bounds — not the per-hour `is_day` Instant — so the
        // window never bleeds past sunset into the calendar's dusk shading.
        if pattern.requiresDaylight {
            let slotEnd = slot.tick.addingTimeInterval(3600)
            let dayKey = calendar.startOfDay(for: slot.tick)
            guard let day = solarByDay[dayKey] else { return false }
            if slot.tick < day.sunrise || slotEnd > day.sunset {
                return false
            }
        }

        let hourOfDay = calendar.component(.hour, from: slot.tick)

        if let earliest = pattern.earliestHour, hourOfDay < earliest {
            return false
        }
        if let latest = pattern.latestHour, hourOfDay >= latest {
            return false
        }

        // Instant weather constraints — evaluated at the slot's start tick.
        if let min = pattern.temperatureMin, slot.temperature.value < min {
            return false
        }
        if let max = pattern.temperatureMax, slot.temperature.value > max {
            return false
        }
        if let max = pattern.humidityMax, slot.humidity.value > max {
            return false
        }
        if let min = pattern.windSpeedMin, slot.windSpeed.value < min {
            return false
        }
        if let max = pattern.windSpeedMax, slot.windSpeed.value > max {
            return false
        }
        if let max = pattern.cloudCoverMax, slot.cloudCover.value > max {
            return false
        }

        // Preceding-hour constraints — the slot's precipProbability
        // already describes [slot.tick, slot.tick + 1h) because values
        // were shifted at ingestion.
        if let min = pattern.precipProbabilityMin,
           slot.precipProbability.value < min {
            return false
        }
        if let max = pattern.precipProbabilityMax,
           slot.precipProbability.value > max {
            return false
        }

        // Tide height: the entire slot must stay inside the allowed
        // band. `tideHeightRange` is min..max across the slot's hour,
        // so we check both ends against the pattern's bounds.
        if pattern.tideHeightMin != nil || pattern.tideHeightMax != nil {
            guard let range = slot.tideHeightRange else { return false }
            if let minHeight = pattern.tideHeightMin, range.lowerBound < minHeight {
                return false
            }
            if let maxHeight = pattern.tideHeightMax, range.upperBound > maxHeight {
                return false
            }
        }

        // Tide status: `tideStatuses` is the set of statuses observed
        // across the slot. `.rising`/`.falling` demand the slot is
        // *uniformly* that direction — no moment drifts into a high,
        // low, or the opposite direction. `.high`/`.low` demand an
        // extreme lands inside the slot (at least one sample registers
        // it). `.notLow` excludes any moment near a low.
        let statuses = slot.tideStatuses ?? [.unknown]
        switch pattern.tideRequirement {
        case .any:
            break
        case .rising:
            if statuses != [.rising] { return false }
        case .falling:
            if statuses != [.falling] { return false }
        case .high:
            if !statuses.contains(.high) { return false }
        case .low:
            if !statuses.contains(.low) { return false }
        case .notLow:
            if statuses.contains(.low) { return false }
        }

        return true
    }

    // MARK: - Quality Scoring

    /// Compute a 0.0–1.0 quality score based on how far conditions are from
    /// constraint boundaries. Higher = more comfortable margin.
    private func qualityScore(
        slots: [ForecastSlot],
        pattern: ActivityPattern
    ) -> Double {
        var scores: [Double] = []

        for slot in slots {
            // Temperature: score based on distance from boundaries.
            if let tempMin = pattern.temperatureMin, let tempMax = pattern.temperatureMax {
                let range = tempMax - tempMin
                if range > 0 {
                    let center = (tempMin + tempMax) / 2
                    let dist = abs(slot.temperature.value - center) / (range / 2)
                    scores.append(Swift.max(0, 1.0 - dist))
                }
            }

            // Humidity: lower is better (relative to max).
            if let humMax = pattern.humidityMax, humMax > 0 {
                scores.append(Swift.max(0, 1.0 - slot.humidity.value / humMax))
            }

            // Precipitation:
            //  - min + max: center of range is best (user wants a specific band).
            //  - max only: lower is better (default: drier is nicer).
            //  - min only: higher is better (e.g. "work inside when it rains").
            let precip = slot.precipProbability.value
            if let precipMin = pattern.precipProbabilityMin,
               let precipMax = pattern.precipProbabilityMax {
                let range = precipMax - precipMin
                if range > 0 {
                    let center = (precipMin + precipMax) / 2
                    let dist = abs(precip - center) / (range / 2)
                    scores.append(Swift.max(0, 1.0 - dist))
                }
            } else if let precipMax = pattern.precipProbabilityMax, precipMax > 0 {
                scores.append(Swift.max(0, 1.0 - precip / precipMax))
            } else if let precipMin = pattern.precipProbabilityMin, precipMin < 100 {
                // Higher is better; scale so precipMin → 0, 100 → 1.
                scores.append(
                    Swift.max(0, (precip - precipMin) / (100 - precipMin))
                )
            }

            // Wind: center of range is best.
            if let windMin = pattern.windSpeedMin, let windMax = pattern.windSpeedMax {
                let range = windMax - windMin
                if range > 0 {
                    let center = (windMin + windMax) / 2
                    let dist = abs(slot.windSpeed.value - center) / (range / 2)
                    scores.append(Swift.max(0, 1.0 - dist))
                }
            } else if let windMax = pattern.windSpeedMax, windMax > 0 {
                scores.append(Swift.max(0, 1.0 - slot.windSpeed.value / windMax))
            }

            // Cloud cover: lower is better.
            if let cloudMax = pattern.cloudCoverMax, cloudMax > 0 {
                scores.append(Swift.max(0, 1.0 - slot.cloudCover.value / cloudMax))
            }
        }

        guard !scores.isEmpty else { return 1.0 }
        return scores.reduce(0, +) / Double(scores.count)
    }

    // MARK: - Helpers

    private func findContiguousRanges(_ qualifying: [Bool]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start: Int?

        for i in qualifying.indices {
            if qualifying[i] {
                if start == nil { start = i }
            } else {
                if let s = start {
                    ranges.append(s..<i)
                    start = nil
                }
            }
        }
        if let s = start {
            ranges.append(s..<qualifying.count)
        }

        return ranges
    }

    private func summarize(_ slots: [ForecastSlot]) -> ConditionsSummary {
        let temps = slots.map(\.temperature.value)
        let hums = slots.map(\.humidity.value)
        let precips = slots.map(\.precipProbability.value)
        let winds = slots.map(\.windSpeed.value)
        let clouds = slots.map(\.cloudCover.value)
        let tideStatuses = slots.compactMap(\.tideStatuses).reduce(into: Set<TideStatus>()) {
            $0.formUnion($1)
        }
        let heightLows = slots.compactMap { $0.tideHeightRange?.lowerBound }
        let heightHighs = slots.compactMap { $0.tideHeightRange?.upperBound }
        return ConditionsSummary(
            tempMin: temps.min() ?? 0,
            tempMax: temps.max() ?? 0,
            humidityMax: hums.max() ?? 0,
            precipProbabilityMax: precips.max() ?? 0,
            windSpeedMin: winds.min() ?? 0,
            windSpeedMax: winds.max() ?? 0,
            cloudCoverMax: clouds.max() ?? 0,
            tideStatuses: tideStatuses,
            tideHeightMin: heightLows.min(),
            tideHeightMax: heightHighs.max()
        )
    }
}
