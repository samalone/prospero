import FluentKit
import Hummingbird
import HummingbirdAuth

/// Detects masquerade sessions and populates the `masqueradingAs` field
/// on the request context. Runs after SessionMiddleware.
struct MasqueradeMiddleware: RouterMiddleware {
    let db: Database

    func handle(
        _ request: Request,
        context: AppRequestContext,
        next: (Request, AppRequestContext) async throws -> Response
    ) async throws -> Response {
        var context = context

        let cookieName = "prospero-session"
        if let token = request.cookies[cookieName]?.value,
           let session = try await AuthSession.query(on: db)
            .filter(\.$token == token)
            .first(),
           let realUserID = session.realUserID,
           session.masqueradeUserID != nil
        {
            // We're masquerading — context.user is already the target (set by SessionMiddleware).
            context.masqueradingAs = context.user?.displayName
            context.realUserID = realUserID
        }

        return try await next(request, context)
    }
}
