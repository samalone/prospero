import FluentKit
import Foundation
import HummingbirdAuth

final class ProsperoUser: Model, FluentAuthUser, @unchecked Sendable {
    static let schema = "users"
    static let emailFieldKey: FieldKey = "email"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "display_name")
    var displayName: String

    @Field(key: "email")
    var email: String

    @Field(key: "is_admin")
    var isAdmin: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    required init(displayName: String, email: String) {
        self.displayName = displayName
        self.email = email
        self.isAdmin = false
    }
}
