import FluentKit

struct AddPrecipProbabilityMin: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("activity_patterns")
            .field("precip_probability_min", .double)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("activity_patterns")
            .deleteField("precip_probability_min")
            .update()
    }
}
