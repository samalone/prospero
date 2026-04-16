import Foundation
import HummingbirdAuth

/// View model carrying user/session info for the page layout.
struct PageContext: Sendable {
    var userName: String?
    var isAdmin: Bool
    var isLoggedIn: Bool
    var flashMessages: [FlashMessage]
    var masqueradingAs: String?
    var csrfToken: String?

    init(
        userName: String? = nil,
        isAdmin: Bool = false,
        isLoggedIn: Bool = false,
        flashMessages: [FlashMessage] = [],
        masqueradingAs: String? = nil,
        csrfToken: String? = nil
    ) {
        self.userName = userName
        self.isAdmin = isAdmin
        self.isLoggedIn = isLoggedIn
        self.flashMessages = flashMessages
        self.masqueradingAs = masqueradingAs
        self.csrfToken = csrfToken
    }

    /// Build from the base app context.
    init(from context: AppRequestContext) {
        self.userName = context.user?.displayName
        self.isAdmin = context.realUserID != nil || (context.user?.isAdmin ?? false)
        self.isLoggedIn = context.user != nil
        self.flashMessages = context.flashMessages
        self.masqueradingAs = context.masqueradingAs
        self.csrfToken = context.csrfToken
    }

    /// Build from an authenticated context.
    init(from context: AuthenticatedContext<AppRequestContext>) {
        self.userName = context.user.displayName
        self.isAdmin = context.realUserID != nil || context.user.isAdmin
        self.isLoggedIn = true
        self.flashMessages = context.flashMessages
        self.masqueradingAs = context.masqueradingAs
        self.csrfToken = context.csrfToken
    }

    /// Build from an admin context.
    init(from context: AdminContext<AppRequestContext>) {
        self.userName = context.user.displayName
        self.isAdmin = true
        self.isLoggedIn = true
        self.flashMessages = context.flashMessages
        self.masqueradingAs = context.masqueradingAs
        self.csrfToken = context.csrfToken
    }
}
