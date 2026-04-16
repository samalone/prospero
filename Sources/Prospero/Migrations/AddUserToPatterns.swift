import FluentKit

struct AddUserToPatterns: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("activity_patterns")
            .field("user_id", .uuid, .references("users", "id", onDelete: .cascade))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("activity_patterns")
            .deleteField("user_id")
            .update()
    }
}
