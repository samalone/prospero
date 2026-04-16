import Foundation
import Hummingbird
import HummingbirdAuth

struct AppRequestContext: AuthRequestContextProtocol, RequestContext {
    typealias User = ProsperoUser

    var coreContext: CoreRequestContextStorage
    var user: ProsperoUser?
    var flashMessages: [FlashMessage] = []
    var masqueradingAs: String?
    var realUserID: UUID?

    init(source: ApplicationRequestContextSource) {
        self.coreContext = .init(source: source)
    }
}
