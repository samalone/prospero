import Foundation

/// Maps IANA timezone names to a representative latitude/longitude and a
/// short human label. Used to pick a reference location for the calendar's
/// default day/night shading when the user has not set a home location.
///
/// Accuracy: representative city for each zone. Sunrise/sunset at the
/// representative point is within ~15 minutes of anywhere else in the same
/// zone at mid-latitudes — ample for ambient shading.
///
/// Privacy: the timezone is read from the browser via
/// `Intl.DateTimeFormat().resolvedOptions().timeZone` and forwarded to the
/// server in a cookie. No geolocation permission is requested.
enum TimezoneLocation {
    struct Place: Sendable {
        let latitude: Double
        let longitude: Double
        let label: String
    }

    /// Representative lat/lon + label for an IANA timezone name.
    /// Returns nil when the zone is unknown — callers should fall back to UTC.
    static func lookup(_ ianaName: String) -> Place? { table[ianaName] }

    /// Same as `lookup`, but guarantees a non-nil result by falling back to a
    /// neutral UTC anchor when the zone is unknown.
    static func resolve(_ ianaName: String?) -> Place {
        if let name = ianaName, let place = table[name] { return place }
        return Place(latitude: 0, longitude: 0, label: "UTC")
    }

    private static let table: [String: Place] = [
        // North America
        "America/St_Johns":     .init(latitude: 47.56, longitude: -52.71, label: "Newfoundland Time"),
        "America/Halifax":      .init(latitude: 44.65, longitude: -63.58, label: "Atlantic Time"),
        "America/New_York":     .init(latitude: 40.71, longitude: -74.01, label: "Eastern Time"),
        "America/Detroit":      .init(latitude: 42.33, longitude: -83.05, label: "Eastern Time"),
        "America/Toronto":      .init(latitude: 43.65, longitude: -79.38, label: "Eastern Time"),
        "America/Indiana/Indianapolis": .init(latitude: 39.77, longitude: -86.16, label: "Eastern Time"),
        "America/Chicago":      .init(latitude: 41.88, longitude: -87.63, label: "Central Time"),
        "America/Winnipeg":     .init(latitude: 49.90, longitude: -97.14, label: "Central Time"),
        "America/Mexico_City":  .init(latitude: 19.43, longitude: -99.13, label: "Central Time"),
        "America/Denver":       .init(latitude: 39.74, longitude: -104.99, label: "Mountain Time"),
        "America/Edmonton":     .init(latitude: 53.55, longitude: -113.49, label: "Mountain Time"),
        "America/Phoenix":      .init(latitude: 33.45, longitude: -112.07, label: "Mountain Time (Arizona)"),
        "America/Los_Angeles":  .init(latitude: 34.05, longitude: -118.24, label: "Pacific Time"),
        "America/Vancouver":    .init(latitude: 49.28, longitude: -123.12, label: "Pacific Time"),
        "America/Anchorage":    .init(latitude: 61.22, longitude: -149.90, label: "Alaska Time"),
        "Pacific/Honolulu":     .init(latitude: 21.31, longitude: -157.86, label: "Hawaii Time"),

        // South America
        "America/Bogota":       .init(latitude: 4.71, longitude: -74.07, label: "Bogotá"),
        "America/Lima":         .init(latitude: -12.05, longitude: -77.04, label: "Lima"),
        "America/Santiago":     .init(latitude: -33.45, longitude: -70.67, label: "Santiago"),
        "America/Sao_Paulo":    .init(latitude: -23.55, longitude: -46.63, label: "São Paulo"),
        "America/Argentina/Buenos_Aires": .init(latitude: -34.61, longitude: -58.38, label: "Buenos Aires"),

        // Europe
        "Atlantic/Reykjavik":   .init(latitude: 64.15, longitude: -21.94, label: "Reykjavík"),
        "Europe/Dublin":        .init(latitude: 53.35, longitude: -6.26, label: "Dublin"),
        "Europe/London":        .init(latitude: 51.51, longitude: -0.13, label: "London"),
        "Europe/Lisbon":        .init(latitude: 38.72, longitude: -9.14, label: "Lisbon"),
        "Europe/Madrid":        .init(latitude: 40.42, longitude: -3.70, label: "Madrid"),
        "Europe/Paris":         .init(latitude: 48.86, longitude: 2.35, label: "Paris"),
        "Europe/Brussels":      .init(latitude: 50.85, longitude: 4.35, label: "Brussels"),
        "Europe/Amsterdam":     .init(latitude: 52.37, longitude: 4.90, label: "Amsterdam"),
        "Europe/Berlin":        .init(latitude: 52.52, longitude: 13.41, label: "Berlin"),
        "Europe/Zurich":        .init(latitude: 47.38, longitude: 8.54, label: "Zürich"),
        "Europe/Rome":          .init(latitude: 41.90, longitude: 12.50, label: "Rome"),
        "Europe/Vienna":        .init(latitude: 48.21, longitude: 16.37, label: "Vienna"),
        "Europe/Prague":        .init(latitude: 50.08, longitude: 14.44, label: "Prague"),
        "Europe/Warsaw":        .init(latitude: 52.23, longitude: 21.01, label: "Warsaw"),
        "Europe/Stockholm":     .init(latitude: 59.33, longitude: 18.07, label: "Stockholm"),
        "Europe/Oslo":          .init(latitude: 59.91, longitude: 10.75, label: "Oslo"),
        "Europe/Copenhagen":    .init(latitude: 55.68, longitude: 12.57, label: "Copenhagen"),
        "Europe/Helsinki":      .init(latitude: 60.17, longitude: 24.94, label: "Helsinki"),
        "Europe/Athens":        .init(latitude: 37.98, longitude: 23.73, label: "Athens"),
        "Europe/Istanbul":      .init(latitude: 41.01, longitude: 28.98, label: "Istanbul"),
        "Europe/Moscow":        .init(latitude: 55.76, longitude: 37.62, label: "Moscow"),

        // Africa
        "Africa/Casablanca":    .init(latitude: 33.57, longitude: -7.59, label: "Casablanca"),
        "Africa/Lagos":         .init(latitude: 6.52, longitude: 3.38, label: "Lagos"),
        "Africa/Cairo":         .init(latitude: 30.04, longitude: 31.24, label: "Cairo"),
        "Africa/Johannesburg":  .init(latitude: -26.20, longitude: 28.05, label: "Johannesburg"),
        "Africa/Nairobi":       .init(latitude: -1.29, longitude: 36.82, label: "Nairobi"),

        // Middle East / Asia
        "Asia/Jerusalem":       .init(latitude: 31.78, longitude: 35.22, label: "Jerusalem"),
        "Asia/Beirut":          .init(latitude: 33.89, longitude: 35.50, label: "Beirut"),
        "Asia/Dubai":           .init(latitude: 25.20, longitude: 55.27, label: "Dubai"),
        "Asia/Karachi":         .init(latitude: 24.86, longitude: 67.01, label: "Karachi"),
        "Asia/Kolkata":         .init(latitude: 22.57, longitude: 88.36, label: "Kolkata"),
        "Asia/Dhaka":           .init(latitude: 23.81, longitude: 90.41, label: "Dhaka"),
        "Asia/Bangkok":         .init(latitude: 13.76, longitude: 100.50, label: "Bangkok"),
        "Asia/Jakarta":         .init(latitude: -6.21, longitude: 106.85, label: "Jakarta"),
        "Asia/Singapore":       .init(latitude: 1.35, longitude: 103.82, label: "Singapore"),
        "Asia/Kuala_Lumpur":    .init(latitude: 3.14, longitude: 101.69, label: "Kuala Lumpur"),
        "Asia/Manila":          .init(latitude: 14.60, longitude: 120.98, label: "Manila"),
        "Asia/Hong_Kong":       .init(latitude: 22.32, longitude: 114.17, label: "Hong Kong"),
        "Asia/Shanghai":        .init(latitude: 31.23, longitude: 121.47, label: "Shanghai"),
        "Asia/Taipei":          .init(latitude: 25.03, longitude: 121.57, label: "Taipei"),
        "Asia/Seoul":           .init(latitude: 37.57, longitude: 126.98, label: "Seoul"),
        "Asia/Tokyo":           .init(latitude: 35.68, longitude: 139.69, label: "Tokyo"),

        // Oceania
        "Australia/Perth":      .init(latitude: -31.95, longitude: 115.86, label: "Perth"),
        "Australia/Adelaide":   .init(latitude: -34.93, longitude: 138.60, label: "Adelaide"),
        "Australia/Brisbane":   .init(latitude: -27.47, longitude: 153.03, label: "Brisbane"),
        "Australia/Sydney":     .init(latitude: -33.87, longitude: 151.21, label: "Sydney"),
        "Australia/Melbourne":  .init(latitude: -37.81, longitude: 144.96, label: "Melbourne"),
        "Pacific/Auckland":     .init(latitude: -36.85, longitude: 174.76, label: "Auckland"),
        "Pacific/Fiji":         .init(latitude: -18.14, longitude: 178.44, label: "Fiji"),

        // UTC aliases
        "UTC":                  .init(latitude: 0, longitude: 0, label: "UTC"),
        "Etc/UTC":              .init(latitude: 0, longitude: 0, label: "UTC"),
        "Etc/GMT":              .init(latitude: 0, longitude: 0, label: "UTC"),
    ]
}
