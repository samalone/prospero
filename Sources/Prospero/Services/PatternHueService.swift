import FluentKit
import Foundation

/// Recomputes hues for a user's patterns to maximize visual distinction
/// while preserving any user-fixed hues.
struct PatternHueService: Sendable {
    let db: Database

    /// Recompute hues for all of a user's patterns. Fixed hues are preserved;
    /// unfixed hues are placed to maximize angular distance.
    func recomputeHues(userID: UUID) async throws {
        let patterns = try await ActivityPattern.query(on: db)
            .filter(\.$userID == userID)
            .sort(\.$createdAt, .ascending)
            .all()

        let fixed = patterns.filter { $0.isHueFixed }
        let unfixed = patterns.filter { !$0.isHueFixed }

        guard !unfixed.isEmpty else { return }

        let fixedAngles = fixed.map(\.hue)
        let newPositions = HuePlacer.placePoints(
            fixedAngles: fixedAngles,
            n: unfixed.count
        )

        // Preserve stability: assign new positions to existing patterns
        // to minimize visual shift.
        let previousHues = unfixed.map(\.hue)
        let assigned = HuePlacer.assignStable(
            previousHues: previousHues,
            newPositions: newPositions
        )

        for (pattern, hue) in zip(unfixed, assigned) {
            pattern.hue = hue
            try await pattern.save(on: db)
        }
    }
}
