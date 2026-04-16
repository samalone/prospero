import Hummingbird
import HummingbirdAuth

struct AppRequestContext: AuthRequestContextProtocol, RequestContext {
    typealias User = ProsperoUser

    var coreContext: CoreRequestContextStorage
    var user: ProsperoUser?
    var flashMessages: [FlashMessage] = []

    init(source: ApplicationRequestContextSource) {
        self.coreContext = .init(source: source)
    }
}
