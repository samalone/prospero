import Foundation

/// Assigns hue angles (0..<360) to a set of items on a color wheel,
/// maximizing angular distance between items while respecting any
/// user-pinned hues.
///
/// Ported from Life Balance's `HuePlacer`.
enum HuePlacer {

    /// Place `n` new points on a 360° circle so that they maximize the minimum
    /// angular distance from each other and from the given fixed points.
    ///
    /// - Parameters:
    ///   - fixedAngles: Hue angles (0..<360) that are pinned by the user.
    ///   - n: How many additional hues to place.
    /// - Returns: `n` new hue angles in sorted order.
    static func placePoints(fixedAngles: [Double], n: Int) -> [Double] {
        guard n > 0 else { return [] }

        // No fixed points: space evenly starting from 0.
        if fixedAngles.isEmpty {
            let spacing = 360.0 / Double(n)
            return (0..<n).map { Double($0) * spacing }
        }

        let sorted = fixedAngles.sorted()
        let m = sorted.count

        // Compute gaps between consecutive fixed points (wrapping around).
        let gaps = (0..<m).map { i -> Double in
            let next = (i + 1) % m
            var gap = sorted[next] - sorted[i]
            if gap <= 0 { gap += 360.0 }
            return gap
        }

        // How many new points fit across all gaps with minimum spacing d?
        func capacity(_ d: Double) -> Int {
            gaps.reduce(0) { total, g in
                total + max(0, Int(g / d) - 1)
            }
        }

        // Binary search for the maximum minimum spacing that fits all n points.
        var lo = 0.0
        var hi = 360.0 / Double(m + n)

        for _ in 0..<100 {
            let mid = (lo + hi) / 2.0
            if capacity(mid) >= n {
                lo = mid
            } else {
                hi = mid
            }
        }

        let dStar = lo

        // Compute how many points go in each gap.
        var counts = gaps.map { g in max(0, Int(g / dStar) - 1) }
        var total = counts.reduce(0, +)

        // Remove extras from the gaps where removal hurts least.
        while total > n {
            var bestIdx = -1
            var bestSpacing = -1.0
            for i in 0..<m where counts[i] > 0 {
                let spacingAfterRemoval = gaps[i] / Double(counts[i])
                if spacingAfterRemoval > bestSpacing {
                    bestSpacing = spacingAfterRemoval
                    bestIdx = i
                }
            }
            counts[bestIdx] -= 1
            total -= 1
        }

        // Place points evenly within each gap.
        var result: [Double] = []
        result.reserveCapacity(n)

        for i in 0..<m where counts[i] > 0 {
            let k = counts[i]
            let spacing = gaps[i] / Double(k + 1)
            for j in 1...k {
                var angle = sorted[i] + Double(j) * spacing
                if angle >= 360.0 { angle -= 360.0 }
                result.append(angle)
            }
        }

        result.sort()
        return result
    }

    /// Reassign `newPositions` to items with existing `previousHues` to minimize
    /// total angular displacement. Both arrays must have the same length.
    ///
    /// Because both lie on a circle, optimal assignment preserves circular
    /// order, so we only need to test N rotations rather than N! permutations.
    static func assignStable(
        previousHues: [Double],
        newPositions: [Double]
    ) -> [Double] {
        let n = previousHues.count
        guard n > 0, newPositions.count == n else {
            return newPositions
        }
        if n == 1 {
            return newPositions
        }

        let indexed = previousHues.enumerated()
            .sorted { $0.element < $1.element }
        let sortedPositions = newPositions.sorted()

        var bestRotation = 0
        var bestCost = Double.infinity

        for k in 0..<n {
            var cost = 0.0
            for i in 0..<n {
                let pos = sortedPositions[(i + k) % n]
                cost += angularDistance(indexed[i].element, pos)
            }
            if cost < bestCost {
                bestCost = cost
                bestRotation = k
            }
        }

        var result = Array(repeating: 0.0, count: n)
        for i in 0..<n {
            let originalIndex = indexed[i].offset
            result[originalIndex] = sortedPositions[(i + bestRotation) % n]
        }
        return result
    }

    /// Shortest angular distance on a 360° circle.
    private static func angularDistance(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(diff, 360 - diff)
    }

    /// Render a hue angle as an OKLCH color suitable for goal UI elements.
    static func goalColor(hue: Double) -> String {
        "oklch(65% 0.18 \(String(format: "%.1f", hue)))"
    }

    /// A darker variant for accents.
    static func goalColorDark(hue: Double) -> String {
        "oklch(50% 0.18 \(String(format: "%.1f", hue)))"
    }

    /// A lighter variant for backgrounds.
    static func goalColorLight(hue: Double) -> String {
        "oklch(92% 0.06 \(String(format: "%.1f", hue)))"
    }

    /// Render a hue with chroma scaled by quality (0.0–1.0).
    ///
    /// Marginal matches get near-zero chroma (nearly grey), while
    /// excellent matches get full chroma (vibrant). The ramp is
    /// quadratic so that the perceptible difference between Fair/Good/
    /// Excellent is more pronounced. Lightness is held high enough (85%)
    /// that plain black text reads clearly across all quality levels.
    static func goalColor(hue: Double, quality: Double) -> String {
        let clamped = max(0.0, min(1.0, quality))
        // Quadratic ramp: marginal approaches 0.01, excellent reaches 0.18.
        let chroma = 0.01 + (0.18 - 0.01) * (clamped * clamped)
        let lightness = 85.0
        return "oklch(\(String(format: "%.0f", lightness))% \(String(format: "%.3f", chroma)) \(String(format: "%.1f", hue)))"
    }
}
