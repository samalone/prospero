import FluentKit

struct AddUniqueConstraintToPatterns: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("activity_patterns")
            .unique(on: "user_id", "name")
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("activity_patterns")
            .deleteUnique(on: "user_id", "name")
            .update()
    }
}
