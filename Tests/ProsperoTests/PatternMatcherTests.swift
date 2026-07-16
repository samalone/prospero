import Foundation
import Testing
@testable import Prospero

/// Build a plausible forecast slot for a given tick with all-passing
/// weather. Callers tweak individual values in their own tests.
private func passingSlot(at tick: Date) -> ForecastSlot {
    let slotEnd = tick.addingTimeInterval(3600)
    return ForecastSlot(
        tick: tick,
        temperature: PointInTime(time: tick, value: 70),
        humidity: PointInTime(time: tick, value: 50),
        windSpeed: PointInTime(time: tick, value: 10),
        cloudCover: PointInTime(time: tick, value: 10),
        precipProbability: PrecedingHour(endTime: slotEnd, value: 0),
        windGusts: PrecedingHour(endTime: slotEnd, value: 12)
    )
}

/// Regression test for the daylight-past-sunset bug.
///
/// A 2-hour `requiresDaylight` window must not be placed starting at an
/// hour whose forward interval ends after sunset, even if the starting
/// instant itself is still daylit. Before the fix, the per-hour `is_day`
/// Instant flag allowed windows to bleed into the post-sunset calendar
/// shading.
@Test func daylightWindowRespectsSunsetBoundary() {
    let tz = TimeZone(identifier: "America/New_York")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz

    // 2026-07-01 — long summer day in Rhode Island.
    let dayStart = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
    let sunrise = cal.date(bySettingHour: 5, minute: 15, second: 0, of: dayStart)!
    let sunset = cal.date(bySettingHour: 20, minute: 15, second: 0, of: dayStart)!

    // 24 all-passing slots. The daylight check must knock out the
    // 20:00 slot whose forward hour ends at 21:00 — past sunset.
    var slots: [ForecastSlot] = []
    for h in 0..<24 {
        let t = cal.date(bySettingHour: h, minute: 0, second: 0, of: dayStart)!
        slots.append(passingSlot(at: t))
    }

    let pattern = ActivityPattern(
        name: "Sailing",
        latitude: 41.777, longitude: -71.3925,
        durationHours: 2,
        requiresDaylight: true
    )

    let solar = [SolarDay(dayStart: dayStart, sunrise: sunrise, sunset: sunset)]
    let windows = PatternMatcher().findWindows(
        pattern: pattern, conditions: slots,
        solar: solar, timezone: tz
    )

    for w in windows {
        #expect(w.end <= sunset,
                "window ending at \(w.end) bleeds past sunset at \(sunset)")
        #expect(w.start >= sunrise,
                "window starting at \(w.start) begins before sunrise at \(sunrise)")
    }
    #expect(!windows.isEmpty)
}

/// Verify that preceding-hour values align with the slot they describe.
///
/// Open-Meteo's 14:00 `precipitation_probability` value describes the
/// interval [13:00, 14:00). In our typed model, that value is shifted
/// at ingestion onto the slot for 13:00, so the matcher naturally
/// evaluates the precip probability of the forward hour the slot
/// represents. This test confirms a shower during [14:00, 15:00) knocks
/// out the 14:00 slot — not the 13:00 slot as the old code would have.
@Test func precipProbabilityAlignsWithForwardHour() {
    let tz = TimeZone(identifier: "America/New_York")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let dayStart = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!

    // Slots at 13:00 and 14:00. The 14:00 slot — describing [14:00, 15:00)
    // — gets a 90% precip probability; 13:00 stays at 0.
    let slot13 = passingSlot(at: cal.date(bySettingHour: 13, minute: 0, second: 0, of: dayStart)!)
    var slot14 = passingSlot(at: cal.date(bySettingHour: 14, minute: 0, second: 0, of: dayStart)!)
    slot14 = ForecastSlot(
        tick: slot14.tick,
        temperature: slot14.temperature,
        humidity: slot14.humidity,
        windSpeed: slot14.windSpeed,
        cloudCover: slot14.cloudCover,
        precipProbability: PrecedingHour(
            endTime: slot14.tick.addingTimeInterval(3600), value: 90
        ),
        windGusts: slot14.windGusts
    )

    let pattern = ActivityPattern(
        name: "Dry activity",
        latitude: 41.777, longitude: -71.3925,
        durationHours: 1,
        precipProbabilityMax: 20
    )

    let windows = PatternMatcher().findWindows(
        pattern: pattern, conditions: [slot13, slot14],
        solar: [], timezone: tz
    )

    // Only the 13:00 slot should qualify.
    #expect(windows.count == 1)
    #expect(windows.first?.start == slot13.tick)
}

/// A tide height constraint must consider the entire slot, not just
/// the opening instant. If the height dips below the requested minimum
/// partway through the hour, the slot must fail.
@Test func tideHeightConstraintSpansWholeSlot() {
    let tz = TimeZone(identifier: "America/New_York")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let dayStart = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!

    // A 13:00 slot whose height range is 2.5..4.0 — the low end dips
    // below the pattern's 3.0 ft minimum. Old code checked only the
    // opening instant and would have passed this.
    var slot = passingSlot(at: cal.date(bySettingHour: 13, minute: 0, second: 0, of: dayStart)!)
    slot.tideHeightRange = 2.5...4.0
    slot.tideStatuses = [.rising]

    let pattern = ActivityPattern(
        name: "Deep-water only",
        latitude: 41.777, longitude: -71.3925,
        durationHours: 1,
        tideHeightMin: 3.0
    )

    let windows = PatternMatcher().findWindows(
        pattern: pattern, conditions: [slot],
        solar: [], timezone: tz
    )
    #expect(windows.isEmpty)
}

/// A `.high` tide requirement must catch an extremum that lands inside
/// the slot even if the slot's opening instant is still `.rising`.
@Test func tideStatusDetectsMidSlotExtremum() {
    let tz = TimeZone(identifier: "America/New_York")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let dayStart = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!

    var slot = passingSlot(at: cal.date(bySettingHour: 13, minute: 0, second: 0, of: dayStart)!)
    slot.tideHeightRange = 4.0...5.0
    slot.tideStatuses = [.rising, .high]  // high landed mid-slot

    let pattern = ActivityPattern(
        name: "At the top",
        latitude: 41.777, longitude: -71.3925,
        durationHours: 1,
        tideRequirement: .high
    )

    let windows = PatternMatcher().findWindows(
        pattern: pattern, conditions: [slot],
        solar: [], timezone: tz
    )
    #expect(windows.count == 1)
}

/// An air-quality `max` (clean-air) constraint must exclude hours whose
/// US AQI exceeds the limit and keep the ones below it.
@Test func airQualityMaxExcludesDirtyHours() {
    let tz = TimeZone(identifier: "America/New_York")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let dayStart = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!

    // 12:00 clean (AQI 30), 13:00 hazy (AQI 120). Max of 50 keeps only 12:00.
    var clean = passingSlot(at: cal.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart)!)
    clean.airQuality = PointInTime(time: clean.tick, value: 30)
    var dirty = passingSlot(at: cal.date(bySettingHour: 13, minute: 0, second: 0, of: dayStart)!)
    dirty.airQuality = PointInTime(time: dirty.tick, value: 120)

    let pattern = ActivityPattern(
        name: "Fresh-air run",
        latitude: 41.777, longitude: -71.3925,
        durationHours: 1,
        airQualityMax: 50
    )

    let windows = PatternMatcher().findWindows(
        pattern: pattern, conditions: [clean, dirty],
        solar: [], timezone: tz
    )
    #expect(windows.count == 1)
    #expect(windows.first?.start == clean.tick)
}

/// An air-quality `min` (bad-air) constraint selects the opposite: the
/// hours dirty enough to justify staying indoors.
@Test func airQualityMinSelectsBadAir() {
    let tz = TimeZone(identifier: "America/New_York")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let dayStart = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!

    var clean = passingSlot(at: cal.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart)!)
    clean.airQuality = PointInTime(time: clean.tick, value: 30)
    var dirty = passingSlot(at: cal.date(bySettingHour: 13, minute: 0, second: 0, of: dayStart)!)
    dirty.airQuality = PointInTime(time: dirty.tick, value: 160)

    let pattern = ActivityPattern(
        name: "Indoor workshop",
        latitude: 41.777, longitude: -71.3925,
        durationHours: 1,
        airQualityMin: 100
    )

    let windows = PatternMatcher().findWindows(
        pattern: pattern, conditions: [clean, dirty],
        solar: [], timezone: tz
    )
    #expect(windows.count == 1)
    #expect(windows.first?.start == dirty.tick)
}

/// A `min`-only air-quality constraint scores "higher AQI is better," but
/// AQI runs past the 300 scoring ceiling. The per-slot score — and thus
/// the window quality — must stay within 0…1 so downstream color mapping
/// isn't over-driven.
@Test func airQualityMinQualityStaysWithinUnitRange() {
    let tz = TimeZone(identifier: "America/New_York")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let dayStart = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!

    // AQI 450 sits well above the 300 ceiling; with min 250 the raw ramp
    // would be (450-250)/(300-250) = 4.0 without clamping.
    var slot = passingSlot(at: cal.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart)!)
    slot.airQuality = PointInTime(time: slot.tick, value: 450)

    let pattern = ActivityPattern(
        name: "Indoor workshop",
        latitude: 41.777, longitude: -71.3925,
        durationHours: 1,
        airQualityMin: 250
    )

    let windows = PatternMatcher().findWindows(
        pattern: pattern, conditions: [slot],
        solar: [], timezone: tz
    )
    #expect(windows.count == 1)
    #expect((0.0...1.0).contains(windows.first?.quality ?? -1))
}

/// When `airQualityMin` sits at or above the 300 scoring ceiling, every
/// qualifying reading is maximally "bad enough" and the AQI factor must
/// still contribute a full 1.0 to the average — not be dropped, which
/// would understate a pattern that also has other constraints.
@Test func airQualityMinAboveCeilingStillScores() {
    let tz = TimeZone(identifier: "America/New_York")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let dayStart = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!

    // passingSlot has humidity 50; with humidityMax 100 that scores 0.5.
    // Adding an above-ceiling AQI min (350, reading 400) must add a 1.0
    // term, lifting the window average to 0.75 — proof the factor counts.
    var slot = passingSlot(at: cal.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart)!)
    slot.airQuality = PointInTime(time: slot.tick, value: 400)

    let pattern = ActivityPattern(
        name: "Indoor, very bad air",
        latitude: 41.777, longitude: -71.3925,
        durationHours: 1,
        humidityMax: 100,
        airQualityMin: 350
    )

    let windows = PatternMatcher().findWindows(
        pattern: pattern, conditions: [slot],
        solar: [], timezone: tz
    )
    #expect(windows.count == 1)
    #expect(abs((windows.first?.quality ?? 0) - 0.75) < 0.0001)
}

/// Past the 7-day AQI horizon a slot carries no AQI reading. A pattern
/// that constrains air quality must treat that unknown as failing rather
/// than silently passing — we can't vouch for air we didn't fetch.
@Test func airQualityConstraintFailsWhenDataMissing() {
    let tz = TimeZone(identifier: "America/New_York")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let dayStart = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!

    // No airQuality set → nil, as for any slot beyond the AQI horizon.
    let slot = passingSlot(at: cal.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart)!)

    let constrained = ActivityPattern(
        name: "Fresh-air run",
        latitude: 41.777, longitude: -71.3925,
        durationHours: 1,
        airQualityMax: 50
    )
    #expect(PatternMatcher().findWindows(
        pattern: constrained, conditions: [slot], solar: [], timezone: tz
    ).isEmpty)

    // An unconstrained pattern is unaffected by the missing reading.
    let unconstrained = ActivityPattern(
        name: "Anytime",
        latitude: 41.777, longitude: -71.3925,
        durationHours: 1
    )
    #expect(PatternMatcher().findWindows(
        pattern: unconstrained, conditions: [slot], solar: [], timezone: tz
    ).count == 1)
}
