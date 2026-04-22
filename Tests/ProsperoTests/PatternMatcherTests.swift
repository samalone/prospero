import Foundation
import Testing
@testable import Prospero

@Test func basicWindowMatching() {
    // TODO: Add tests with synthetic HourlyConditions data
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
    // Sunrise 05:15, sunset 20:15 local (approximate — exact value
    // doesn't matter, only that the 19:00 and 20:00 hours straddle it).
    let sunrise = cal.date(bySettingHour: 5, minute: 15, second: 0, of: dayStart)!
    let sunset = cal.date(bySettingHour: 20, minute: 15, second: 0, of: dayStart)!

    // Build 24 hourly samples, all weather-passing, all `is_day = true`
    // at the instant (which the old matcher would have trusted). The
    // only thing that should knock out a window is the new SolarDay
    // check: the 19:00 hour covers [19:00, 20:00) — fits. The 20:00
    // hour covers [20:00, 21:00) — ends after the 20:15 sunset.
    var conditions: [HourlyConditions] = []
    for h in 0..<24 {
        let t = cal.date(bySettingHour: h, minute: 0, second: 0, of: dayStart)!
        conditions.append(HourlyConditions(
            date: t,
            temperature: 70, humidity: 50, precipProbability: 0,
            windSpeed: 10, windGusts: 12, cloudCover: 10,
            isDaylight: true
        ))
    }

    let pattern = ActivityPattern(
        name: "Sailing",
        latitude: 41.777, longitude: -71.3925,
        durationHours: 2,
        requiresDaylight: true
    )

    let solar = [SolarDay(dayStart: dayStart, sunrise: sunrise, sunset: sunset)]
    let windows = PatternMatcher().findWindows(
        pattern: pattern, conditions: conditions,
        solar: solar, timezone: tz
    )

    // Every returned window must end no later than sunset.
    for w in windows {
        #expect(w.end <= sunset,
                "window ending at \(w.end) bleeds past sunset at \(sunset)")
        #expect(w.start >= sunrise,
                "window starting at \(w.start) begins before sunrise at \(sunrise)")
    }

    // And we should get at least one window from this sunny day.
    #expect(!windows.isEmpty)
}
