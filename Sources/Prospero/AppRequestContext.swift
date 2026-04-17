import Foundation
import Hummingbird
import HummingbirdAuth

/// The path prefix under which Prospero is mounted, normalized to either
/// `""` (root) or e.g. `"/prospero"` (leading slash, no trailing slash).
///
/// Read from the `PROSPERO_BASE_PATH` environment variable, which is set
/// by the `serve` subcommand from its `--base-path` flag. Evaluated once
/// at process start so all request contexts observe a stable value.
///
/// Use `normalizeMountPath(_:)` to keep values consistent when setting
/// the env var or comparing.
let prosperoMountPath: String = normalizeMountPath(
    ProcessInfo.processInfo.environment["PROSPERO_BASE_PATH"] ?? ""
)

/// Normalize a path prefix to either `""` or `"/foo"` (leading `/`, no
/// trailing `/`). Empty and `/` both collapse to `""`.
func normalizeMountPath(_ raw: String) -> String {
    var p = raw.trimmingCharacters(in: .whitespaces)
    if p.isEmpty || p == "/" { return "" }
    if !p.hasPrefix("/") { p = "/" + p }
    while p.hasSuffix("/") { p.removeLast() }
    return p
}

/// Prepend the configured mount path to a root-relative URL path.
///
/// - `mountURL("/patterns")` → `/patterns` when mounted at root,
///   `/prospero/patterns` when mounted at `/prospero`.
/// - `mountURL("/")` → `/` or `/prospero` respectively.
///
/// Use this in views and redirect URLs so navigation stays inside the
/// app's mount point.
func mountURL(_ path: String) -> String {
    if prosperoMountPath.isEmpty { return path }
    if path == "/" { return prosperoMountPath }
    return prosperoMountPath + path
}

struct AppRequestContext: AuthRequestContextProtocol, RequestContext {
    typealias User = ProsperoUser

    var coreContext: CoreRequestContextStorage
    var user: ProsperoUser?
    var flashMessages: [FlashMessage] = []
    var masqueradingAs: String?
    var realUserID: UUID?
    var csrfToken: String?

    /// Mount path from `prosperoMountPath`. Stable for the process lifetime.
    var mountPath: String { prosperoMountPath }

    init(source: ApplicationRequestContextSource) {
        self.coreContext = .init(source: source)
    }
}
