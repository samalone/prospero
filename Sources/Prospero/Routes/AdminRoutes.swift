import FluentKit
import Foundation
import Hummingbird
import HummingbirdAuth
import Logging
import Plot

typealias AdminCtx = AdminContext<AppRequestContext>

func addAdminRoutes(
    to router: RouterGroup<AdminCtx>,
    db: Database,
    logger: Logger,
    baseURL: String
) {
    // User management
    router.get("/admin/users") { _, context -> HTML in
        let users = try await ProsperoUser.query(on: db)
            .sort(\.$createdAt, .ascending)
            .all()

        let viewModels = users.map { user in
            AdminUserViewModel(
                id: user.id!,
                displayName: user.displayName,
                email: user.email,
                isAdmin: user.isAdmin,
                createdAt: user.createdAt
            )
        }

        return AdminUsersPage(
            users: viewModels,
            pageContext: PageContext(
                userName: context.user.displayName,
                isAdmin: true,
                isLoggedIn: true,
                flashMessages: context.flashMessages
            )
        ).html
    }

    router.post("/admin/users/:id/role") { request, context -> Response in
        struct RoleInput: Decodable { var role: String }

        guard let id = context.parameters.get("id", as: UUID.self),
              let user = try await ProsperoUser.find(id, on: db) else {
            throw HTTPError(.notFound)
        }

        // Prevent self-demotion
        guard id != context.user.id else {
            throw HTTPError(.badRequest, message: "Cannot change your own role")
        }

        let input = try await URLEncodedFormDecoder().decode(
            RoleInput.self, from: request, context: context
        )
        user.isAdmin = input.role == "admin"
        try await user.save(on: db)

        return .redirect(to: "/admin/users", type: .normal)
    }

    // Invitation management
    router.get("/admin/invitations") { _, context -> HTML in
        let invitations = try await Invitation.query(on: db)
            .sort(\.$createdAt, .descending)
            .all()

        let viewModels = invitations.map { inv in
            AdminInvitationViewModel(
                id: inv.id!,
                email: inv.email,
                token: inv.token,
                expiresAt: inv.expiresAt,
                createdAt: inv.createdAt,
                isConsumed: inv.consumedAt != nil
            )
        }

        return AdminInvitationsPage(
            invitations: viewModels,
            baseURL: baseURL,
            pageContext: PageContext(
                userName: context.user.displayName,
                isAdmin: true,
                isLoggedIn: true,
                flashMessages: context.flashMessages
            )
        ).html
    }

    router.post("/admin/invitations") { request, context -> Response in
        struct InviteInput: Decodable {
            var email: String?
            var expires_days: Int?
        }

        let input = try await URLEncodedFormDecoder().decode(
            InviteInput.self, from: request, context: context
        )

        let invitationService = InvitationService(
            db: db, logger: logger,
            config: InvitationConfiguration(
                tokenTTL: TimeInterval(input.expires_days ?? 7) * 86400
            )
        )

        _ = try await invitationService.createInvitation(
            email: input.email?.nilIfEmpty,
            invitedByID: context.user.id
        )

        return .redirect(to: "/admin/invitations", type: .normal)
    }

    router.post("/admin/invitations/:id/delete") { _, context -> Response in
        guard let id = context.parameters.get("id", as: UUID.self),
              let invitation = try await Invitation.find(id, on: db) else {
            throw HTTPError(.notFound)
        }
        guard invitation.consumedAt == nil else {
            throw HTTPError(.badRequest, message: "Cannot delete a consumed invitation")
        }
        try await invitation.delete(on: db)
        return .redirect(to: "/admin/invitations", type: .normal)
    }

    // Masquerade — view the app as another user
    router.post("/admin/users/:id/masquerade") { request, context -> Response in
        guard let targetID = context.parameters.get("id", as: UUID.self),
              let _ = try await ProsperoUser.find(targetID, on: db) else {
            throw HTTPError(.notFound)
        }

        let adminID = context.user.id!

        // Find the admin's current session by cookie token.
        let cookieName = "prospero-session"
        guard let token = request.cookies[cookieName]?.value,
              let session = try await AuthSession.query(on: db)
                .filter(\.$token == token)
                .first()
        else {
            throw HTTPError(.unauthorized)
        }

        session.masqueradeUserID = targetID
        session.realUserID = adminID
        try await session.save(on: db)

        return .redirect(to: "/patterns", type: .normal)
    }

    router.post("/admin/masquerade/end") { request, context -> Response in
        let cookieName = "prospero-session"
        guard let token = request.cookies[cookieName]?.value,
              let session = try await AuthSession.query(on: db)
                .filter(\.$token == token)
                .first(),
              session.realUserID != nil
        else {
            throw HTTPError(.badRequest, message: "Not masquerading")
        }

        session.masqueradeUserID = nil
        session.realUserID = nil
        try await session.save(on: db)

        return .redirect(to: "/admin/users", type: .normal)
    }
}
