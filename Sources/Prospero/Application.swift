import ArgumentParser
import FluentKit
import FluentPostgresDriver
import FluentSQLiteDriver
import Foundation
import Hummingbird
import HummingbirdAuth
import HummingbirdAuthViews
import HummingbirdFluent
import Logging
import Plot

@main
struct ProsperoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prospero",
        abstract: "Reverse weather forecaster — find upcoming windows matching your activity patterns.",
        subcommands: [Serve.self, Migrate.self, Invite.self],
        defaultSubcommand: Serve.self
    )
}

/// Configure the Fluent database from the DATABASE_URL environment variable.
func buildFluent(logger: Logger) -> Fluent {
    let fluent = Fluent(logger: logger)

    if let databaseURL = ProcessInfo.processInfo.environment["DATABASE_URL"] {
        try! fluent.databases.use(.postgres(url: databaseURL), as: .psql)
        logger.info("Using PostgreSQL database")
    } else {
        let dataDir = ProcessInfo.processInfo.environment["DATA_DIR"] ?? "."
        try! FileManager.default.createDirectory(
            atPath: dataDir, withIntermediateDirectories: true
        )
        fluent.databases.use(
            .sqlite(.file("\(dataDir)/prospero.sqlite")),
            as: .sqlite
        )
        logger.info("Using SQLite database at \(dataDir)/prospero.sqlite")
    }

    return fluent
}

func addMigrations(to fluent: Fluent) async {
    // App tables first (users must exist before auth FK references)
    await fluent.migrations.add(CreateUsers())
    await fluent.migrations.add(CreateActivityPatterns())
    await fluent.migrations.add(AddTideHeightMin())
    await fluent.migrations.add(AddUserToPatterns())
    // Auth library tables
    await addAuthMigrations(to: fluent, userTable: ProsperoUser.schema)
}

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the Prospero web server."
    )

    @Option(name: .shortAndLong, help: "Hostname to bind to.")
    var hostname: String = "localhost"

    @Option(name: .shortAndLong, help: "Port to listen on.")
    var port: Int = 8080

    @Flag(help: "Run pending migrations before starting.")
    var autoMigrate: Bool = false

    @Option(
        name: .long,
        help: """
            Mount path under which to serve the app, e.g. '/prospero' for \
            path-based routing behind a shared reverse proxy. Use '/' for \
            root-mounted. Environment: PROSPERO_BASE_PATH.
            """
    )
    var basePath: String = ProcessInfo.processInfo.environment["PROSPERO_BASE_PATH"] ?? "/"

    func run() async throws {
        let logger = Logger(label: "Prospero")

        // Normalize and publish the mount path so AppRequestContext can read it.
        let mountPath = normalizeMountPath(basePath)
        setenv("PROSPERO_BASE_PATH", mountPath, 1)
        if !mountPath.isEmpty {
            logger.info("Serving under mount path \(mountPath)")
        }

        let fluent = buildFluent(logger: logger)
        await addMigrations(to: fluent)

        if autoMigrate {
            try await fluent.migrate()
        }

        let router = Router(context: AppRequestContext.self)
        let db = fluent.db()

        // Auth configuration. The session cookie is scoped to the mount
        // path (or "/" at root) so it doesn't leak to sibling apps on the
        // same domain when we share an ingress. `pathPrefix` and
        // `loginPagePath` carry the mount path so library code that reads
        // them (e.g. AuthRedirectMiddleware) produces full-path URLs.
        let authConfig = AuthConfiguration<ProsperoUser>(
            passkey: PasskeyConfiguration(
                relyingPartyID: ProcessInfo.processInfo.environment["WEBAUTHN_RP_ID"] ?? "localhost",
                relyingPartyName: "Prospero",
                relyingPartyOrigin: ProcessInfo.processInfo.environment["WEBAUTHN_RP_ORIGIN"]
                    ?? "http://localhost:\(port)"
            ),
            session: SessionConfiguration(
                cookiePath: mountPath.isEmpty ? "/" : mountPath,
                secureCookie: ProcessInfo.processInfo.environment["DATABASE_URL"] != nil  // secure in prod
            ),
            invitations: InvitationConfiguration(),
            pathPrefix: "\(mountPath)/auth",
            loginPagePath: "\(mountPath)/login",
            invitePagePath: "\(mountPath)/invite",
            callbacks: AuthCallbacks(
                postLoginRedirect: { _ in "\(mountPath)/patterns" },
                postLogoutRedirect: "\(mountPath)/login"
            )
        )

        // Middleware (SessionMiddleware now handles masquerade detection).
        // These are router-level so they run for every request, including
        // health checks and static files.
        router.add(middleware: LogRequestsMiddleware(.info))
        router.add(middleware: ErrorLoggingMiddleware(logger: logger))
        router.add(middleware: SessionMiddleware<AppRequestContext>(
            db: db, config: authConfig.session
        ))
        router.add(middleware: AuthRedirectMiddleware<AppRequestContext>(
            loginPath: authConfig.loginPagePath
        ))

        // Static files live under the mount path too; FileMiddleware strips
        // the prefix before resolving against disk.
        if let staticPath = Bundle.module.path(forResource: "Static", ofType: nil) {
            router.add(middleware: FileMiddleware(
                staticPath,
                urlBasePath: mountPath.isEmpty ? nil : mountPath,
                logger: logger
            ))
        } else {
            logger.warning("Static resources directory not found")
        }

        // Liveness/readiness probe — cheap, no auth, no DB roundtrip.
        // Public path (not under mountPath) so probes don't care about prefix.
        router.get("/healthz") { _, _ -> Response in
            Response(status: .ok, body: .init(byteBuffer: .init(string: "ok")))
        }

        // Every app route (including the auth ceremony endpoints and the
        // public login/invite pages) lives under `app`. For mountPath "",
        // this group is a zero-length prefix and routes land at the root.
        let app = router.group(RouterPath(mountPath))

        // Login page (uses library component in Prospero's layout)
        app.get("/login") { request, context -> PageLayout in
            let returnURL = request.uri.queryParameters.get("return")
            return PageLayout(title: "Sign In", includeAuthScript: true) {
                LoginView(
                    errorMessage: context.flashMessages.first(where: { $0.level == .error })?.text,
                    returnURL: returnURL,
                    pathPrefix: authConfig.pathPrefix
                )
            }
        }

        // Invitation/registration page
        app.get("/invite/:token") { request, context -> PageLayout in
            let token = context.parameters.get("token") ?? ""
            return PageLayout(title: "Create Account", includeAuthScript: true) {
                RegistrationView(
                    invitationToken: token,
                    pathPrefix: authConfig.pathPrefix
                )
            }
        }

        // Auth API routes (begin-login, finish-login, etc.)
        installAuthRoutes(on: app, db: db, config: authConfig, logger: logger)

        // Mount-root → patterns
        app.get("/") { _, _ -> Response in
            .redirect(to: "\(mountPath)/patterns")
        }

        // Authenticated routes
        let authed = app.group(context: AuthenticatedContext<AppRequestContext>.self)
        addPatternRoutes(to: authed, db: db, logger: logger)
        addForecastRoutes(to: authed, db: db, logger: logger)
        addCalendarRoutes(to: authed, db: db, logger: logger)

        // Profile (library routes + Prospero layout)
        installProfileRoutes(on: authed, db: db) { vm, context in
            PageLayout(title: "Profile", pageContext: PageContext(from: context)) {
                ProfileView(viewModel: vm)
            }
        }

        // Admin routes (library routes + Prospero layout)
        let baseURL = ProcessInfo.processInfo.environment["BASE_URL"]
            ?? "http://localhost:\(port)\(mountPath)"
        let admin = app.group(context: AdminContext<AppRequestContext>.self)
        installAdminRoutes(
            on: admin, db: db, logger: logger,
            config: AdminRouteConfiguration(
                baseURL: baseURL,
                invitations: authConfig.invitations ?? InvitationConfiguration()
            ),
            renderUsers: { users, context in
                PageLayout(title: "Users", pageContext: PageContext(from: context)) {
                    AdminUsersView(users: users, csrfToken: context.csrfToken)
                }
            },
            renderInvitations: { invitations, baseURL, context in
                PageLayout(title: "Invitations", pageContext: PageContext(from: context)) {
                    AdminInvitationsView(invitations: invitations, baseURL: baseURL,
                                         csrfToken: context.csrfToken)
                }
            }
        )

        var service = Application(
            router: router,
            configuration: .init(address: .hostname(hostname, port: port))
        )
        service.addServices(fluent)

        logger.info("Prospero running on http://\(hostname):\(port)\(mountPath)")
        try await service.runService()
    }
}

struct Migrate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run pending database migrations."
    )

    @Flag(help: "Revert the last batch of migrations.")
    var revert: Bool = false

    func run() async throws {
        let logger = Logger(label: "Prospero")

        let fluent = buildFluent(logger: logger)
        await addMigrations(to: fluent)

        if revert {
            try await fluent.revert()
            logger.info("Migrations reverted.")
        } else {
            try await fluent.migrate()
            logger.info("Migrations complete.")
        }

        try await fluent.shutdown()
    }
}

struct Invite: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate an invitation URL for a new user."
    )

    @Option(name: .shortAndLong, help: "Pre-fill the invitee's email address.")
    var email: String?

    @Option(name: .long, help: "Invitation expiration in days.")
    var expiresDays: Int = 7

    @Option(name: .long, help: "Base URL for the invite link.")
    var baseURL: String = "http://localhost:8080"

    func run() async throws {
        let logger = Logger(label: "Prospero")

        let fluent = buildFluent(logger: logger)
        await addMigrations(to: fluent)

        do {
            try await fluent.migrate()

            let db = fluent.db()
            let invitationService = InvitationService(
                db: db, logger: logger,
                config: InvitationConfiguration(
                    tokenTTL: TimeInterval(expiresDays) * 86400
                )
            )

            let invitation = try await invitationService.createInvitation(
                email: email
            )

            let url = "\(baseURL)/invite/\(invitation.token)"
            print("")
            print("Invitation created!")
            if let email {
                print("  Email: \(email)")
            }
            print("  Expires: \(expiresDays) days")
            print("  URL: \(url)")
            print("")
        } catch {
            try await fluent.shutdown()
            throw error
        }

        try await fluent.shutdown()
    }
}
