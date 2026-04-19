import FluentKit

struct AddTideHeightMax: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("activity_patterns")
            .field("tide_height_max", .double)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("activity_patterns")
            .deleteField("tide_height_max")
            .update()
    }
}
