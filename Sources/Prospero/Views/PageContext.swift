import FluentKit
import HummingbirdAuth
import Hummingbird

/// View model carrying user/session info for the page layout.
struct PageContext: Sendable {
    var userName: String?
    var isAdmin: Bool
    var isLoggedIn: Bool
    var flashMessages: [FlashMessage]
    var masqueradingAs: String?

    init(
        userName: String? = nil,
        isAdmin: Bool = false,
        isLoggedIn: Bool = false,
        flashMessages: [FlashMessage] = [],
        masqueradingAs: String? = nil
    ) {
        self.userName = userName
        self.isAdmin = isAdmin
        self.isLoggedIn = isLoggedIn
        self.flashMessages = flashMessages
        self.masqueradingAs = masqueradingAs
    }

    /// Build from the base app context.
    init(from context: AppRequestContext) {
        self.userName = context.user?.displayName
        self.isAdmin = context.realUserID != nil || (context.user?.isAdmin ?? false)
        self.isLoggedIn = context.user != nil
        self.flashMessages = context.flashMessages
        self.masqueradingAs = context.masqueradingAs
    }

    /// Build from an authenticated context + the original request.
    /// Checks the session for masquerade state.
    static func from(
        _ context: AuthenticatedContext<AppRequestContext>,
        request: Request,
        db: Database
    ) async -> PageContext {
        var pc = PageContext(
            userName: context.user.displayName,
            isAdmin: context.user.isAdmin,
            isLoggedIn: true,
            flashMessages: context.flashMessages
        )

        // Check for masquerade state in the session.
        let cookieName = "prospero-session"
        if let token = request.cookies[cookieName]?.value,
           let session = try? await AuthSession.query(on: db)
            .filter(\.$token == token)
            .first(),
           session.realUserID != nil,
           session.masqueradeUserID != nil
        {
            pc.masqueradingAs = context.user.displayName
            pc.isAdmin = true  // Real user is admin if they could masquerade
        }

        return pc
    }
}
