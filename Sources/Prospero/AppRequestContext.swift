import Foundation
import Hummingbird
import HummingbirdAuth

struct AppRequestContext: AuthRequestContextProtocol, RequestContext {
    typealias User = ProsperoUser

    var coreContext: CoreRequestContextStorage
    var user: ProsperoUser?
    var flashMessages: [FlashMessage] = []

    /// When masquerading, this is the display name of the target user.
    /// Non-nil means we're viewing the app as someone else.
    var masqueradingAs: String?

    /// The real admin user ID (set during masquerade).
    var realUserID: UUID?

    init(source: ApplicationRequestContextSource) {
        self.coreContext = .init(source: source)
    }
}
