import FluentKit
import Foundation

/// Creates a seed pattern for a newly-registered user so the calendar
/// and pattern list aren't empty on first visit.
///
/// Location defaults mirror the new-pattern form (Edgewood Yacht Club,
/// NOAA station 8453767) so a brand-new user sees the same starting
/// point whether they use the seed or add their own pattern.
enum StarterPatternService {
    /// Install a blue "Sailing" pattern for the given user.
    /// Hue is fixed so later-added patterns don't shift it away from blue.
    static func installSailing(userID: UUID, db: Database) async throws {
        let sailing = ActivityPattern(
            name: "Sailing",
            latitude: 41.777,
            longitude: -71.3925,
            locationName: "Edgewood Yacht Club",
            tideStation: "8453767",
            durationHours: 2,
            precipProbabilityMax: 15,
            windSpeedMin: 5,
            windSpeedMax: 15,
            requiresDaylight: true,
            hue: 240,
            isHueFixed: true
        )
        sailing.userID = userID
        try await sailing.save(on: db)
    }
}
