import Foundation

/// A time window that matches an activity pattern's constraints.
struct MatchWindow: Sendable {
    /// Start of the qualifying window.
    var start: Date
    /// End of the qualifying window (exclusive).
    var end: Date
    /// Number of contiguous qualifying hours.
    var hours: Int
    /// Quality score 0.0–1.0 (1.0 = ideal center of all constraint ranges).
    var quality: Double
    /// Summary conditions across the window (min/max/avg).
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
    func findWindows(
        pattern: ActivityPattern,
        conditions: [HourlyConditions]
    ) -> [MatchWindow] {
        let requiredHours = max(1, Int(ceil(pattern.durationHours)))

        // Step 1: Mark each hour as qualifying or not.
        let qualifying = conditions.map { hour in
            passesConstraints(hour: hour, pattern: pattern)
        }

        // Step 2: Find contiguous ranges of qualifying hours.
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
                let q = qualityScore(hours: subSlice, pattern: pattern)
                if q > bestQuality {
                    bestQuality = q
                    bestStart = offset
                }
            }

            let windowSlice = Array(slice[bestStart..<(bestStart + requiredHours)])

            windows.append(MatchWindow(
                start: conditions[range.lowerBound + bestStart].date,
                end: conditions[range.lowerBound + bestStart + requiredHours - 1].date
                    .addingTimeInterval(3600),
                hours: slice.count, // Full qualifying range
                quality: bestQuality,
                summary: summarize(windowSlice)
            ))
        }

        return windows.sorted { $0.start < $1.start }
    }

    // MARK: - Constraint Checking

    private func passesConstraints(
        hour: HourlyConditions,
        pattern: ActivityPattern
    ) -> Bool {
        // Scheduling constraints
        if pattern.requiresDaylight && !hour.isDaylight {
            return false
        }

        let calendar = Calendar.current
        let hourOfDay = calendar.component(.hour, from: hour.date)

        if let earliest = pattern.earliestHour, hourOfDay < earliest {
            return false
        }
        if let latest = pattern.latestHour, hourOfDay >= latest {
            return false
        }

        // Weather constraints
        if let min = pattern.temperatureMin, hour.temperature < min {
            return false
        }
        if let max = pattern.temperatureMax, hour.temperature > max {
            return false
        }
        if let max = pattern.humidityMax, hour.humidity > max {
            return false
        }
        if let max = pattern.precipProbabilityMax, hour.precipProbability > max {
            return false
        }
        if let min = pattern.windSpeedMin, hour.windSpeed < min {
            return false
        }
        if let max = pattern.windSpeedMax, hour.windSpeed > max {
            return false
        }
        if let max = pattern.cloudCoverMax, hour.cloudCover > max {
            return false
        }

        // Tide height constraint
        if let minHeight = pattern.tideHeightMin {
            guard let height = hour.tideHeight, height >= minHeight else {
                return false
            }
        }

        // Tide status constraint
        switch pattern.tideRequirement {
        case .any:
            break
        case .rising:
            if hour.tideStatus != .rising { return false }
        case .falling:
            if hour.tideStatus != .falling { return false }
        case .high:
            if hour.tideStatus != .high { return false }
        case .low:
            if hour.tideStatus != .low { return false }
        case .notLow:
            if hour.tideStatus == .low { return false }
        }

        return true
    }

    // MARK: - Quality Scoring

    /// Compute a 0.0–1.0 quality score based on how far conditions are from
    /// constraint boundaries. Higher = more comfortable margin.
    private func qualityScore(
        hours: [HourlyConditions],
        pattern: ActivityPattern
    ) -> Double {
        var scores: [Double] = []

        for hour in hours {
            // Temperature: score based on distance from boundaries.
            if let tempMin = pattern.temperatureMin, let tempMax = pattern.temperatureMax {
                let range = tempMax - tempMin
                if range > 0 {
                    let center = (tempMin + tempMax) / 2
                    let dist = abs(hour.temperature - center) / (range / 2)
                    scores.append(Swift.max(0, 1.0 - dist))
                }
            }

            // Humidity: lower is better (relative to max).
            if let humMax = pattern.humidityMax, humMax > 0 {
                scores.append(Swift.max(0, 1.0 - hour.humidity / humMax))
            }

            // Precipitation: lower is better.
            if let precipMax = pattern.precipProbabilityMax, precipMax > 0 {
                scores.append(Swift.max(0, 1.0 - hour.precipProbability / precipMax))
            }

            // Wind: center of range is best.
            if let windMin = pattern.windSpeedMin, let windMax = pattern.windSpeedMax {
                let range = windMax - windMin
                if range > 0 {
                    let center = (windMin + windMax) / 2
                    let dist = abs(hour.windSpeed - center) / (range / 2)
                    scores.append(Swift.max(0, 1.0 - dist))
                }
            } else if let windMax = pattern.windSpeedMax, windMax > 0 {
                scores.append(Swift.max(0, 1.0 - hour.windSpeed / windMax))
            }

            // Cloud cover: lower is better.
            if let cloudMax = pattern.cloudCoverMax, cloudMax > 0 {
                scores.append(Swift.max(0, 1.0 - hour.cloudCover / cloudMax))
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

    private func summarize(_ hours: [HourlyConditions]) -> ConditionsSummary {
        ConditionsSummary(
            tempMin: hours.map(\.temperature).min() ?? 0,
            tempMax: hours.map(\.temperature).max() ?? 0,
            humidityMax: hours.map(\.humidity).max() ?? 0,
            precipProbabilityMax: hours.map(\.precipProbability).max() ?? 0,
            windSpeedMin: hours.map(\.windSpeed).min() ?? 0,
            windSpeedMax: hours.map(\.windSpeed).max() ?? 0,
            cloudCoverMax: hours.map(\.cloudCover).max() ?? 0,
            tideStatuses: Set(hours.map(\.tideStatus)),
            tideHeightMin: hours.compactMap(\.tideHeight).min(),
            tideHeightMax: hours.compactMap(\.tideHeight).max()
        )
    }
}
