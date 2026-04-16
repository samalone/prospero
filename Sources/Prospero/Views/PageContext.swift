import HummingbirdAuth

/// View model carrying user/session info for the page layout.
struct PageContext: Sendable {
    var userName: String?
    var isAdmin: Bool
    var isLoggedIn: Bool
    var flashMessages: [FlashMessage]

    init(
        userName: String? = nil,
        isAdmin: Bool = false,
        isLoggedIn: Bool = false,
        flashMessages: [FlashMessage] = []
    ) {
        self.userName = userName
        self.isAdmin = isAdmin
        self.isLoggedIn = isLoggedIn
        self.flashMessages = flashMessages
    }

    /// Build from the base app context (user may or may not be present).
    init(from context: AppRequestContext) {
        self.userName = context.user?.displayName
        self.isAdmin = context.user?.isAdmin ?? false
        self.isLoggedIn = context.user != nil
        self.flashMessages = context.flashMessages
    }

    /// Build from an authenticated context (user is always present).
    init(from context: AuthenticatedContext<AppRequestContext>) {
        self.userName = context.user.displayName
        self.isAdmin = context.user.isAdmin
        self.isLoggedIn = true
        self.flashMessages = context.flashMessages
    }
}
