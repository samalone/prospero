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

    func run() async throws {
        let logger = Logger(label: "Prospero")

        let fluent = buildFluent(logger: logger)
        await addMigrations(to: fluent)

        if autoMigrate {
            try await fluent.migrate()
        }

        let router = Router(context: AppRequestContext.self)
        let db = fluent.db()

        // Auth configuration
        let authConfig = AuthConfiguration<ProsperoUser>(
            passkey: PasskeyConfiguration(
                relyingPartyID: ProcessInfo.processInfo.environment["WEBAUTHN_RP_ID"] ?? "localhost",
                relyingPartyName: "Prospero",
                relyingPartyOrigin: ProcessInfo.processInfo.environment["WEBAUTHN_RP_ORIGIN"]
                    ?? "http://localhost:\(port)"
            ),
            session: SessionConfiguration(
                secureCookie: ProcessInfo.processInfo.environment["DATABASE_URL"] != nil  // secure in prod
            ),
            invitations: InvitationConfiguration(),
            callbacks: AuthCallbacks(
                postLoginRedirect: { _ in "/patterns" }
            )
        )

        // Middleware (SessionMiddleware now handles masquerade detection)
        router.add(middleware: LogRequestsMiddleware(.info))
        router.add(middleware: ErrorLoggingMiddleware(logger: logger))
        router.add(middleware: SessionMiddleware<AppRequestContext>(
            db: db, config: authConfig.session
        ))
        router.add(middleware: AuthRedirectMiddleware<AppRequestContext>(
            loginPath: authConfig.loginPagePath
        ))

        if let staticPath = Bundle.module.path(forResource: "Static", ofType: nil) {
            router.add(middleware: FileMiddleware(staticPath, logger: logger))
        } else {
            logger.warning("Static resources directory not found")
        }

        // Login page (uses library component in Prospero's layout)
        router.get("/login") { request, context -> PageLayout in
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
        router.get("/invite/:token") { request, context -> PageLayout in
            let token = context.parameters.get("token") ?? ""
            return PageLayout(title: "Create Account", includeAuthScript: true) {
                RegistrationView(
                    invitationToken: token,
                    pathPrefix: authConfig.pathPrefix
                )
            }
        }

        // Auth API routes (begin-login, finish-login, etc.)
        installAuthRoutes(on: router, db: db, config: authConfig, logger: logger)

        // Redirect root to patterns
        router.get("/") { _, _ -> Response in
            .redirect(to: "/patterns")
        }

        // Authenticated routes
        let authed = router.group(context: AuthenticatedContext<AppRequestContext>.self)
        addPatternRoutes(to: authed, db: db, logger: logger)
        addForecastRoutes(to: authed, db: db, logger: logger)

        // Profile (library routes + Prospero layout)
        installProfileRoutes(on: authed, db: db) { vm, context in
            PageLayout(title: "Profile", pageContext: PageContext(from: context)) {
                ProfileView(viewModel: vm)
            }
        }

        // Admin routes (library routes + Prospero layout)
        let baseURL = ProcessInfo.processInfo.environment["BASE_URL"]
            ?? "http://localhost:\(port)"
        let admin = router.group(context: AdminContext<AppRequestContext>.self)
        installAdminRoutes(
            on: admin, db: db, logger: logger,
            config: AdminRouteConfiguration(
                baseURL: baseURL,
                invitations: authConfig.invitations ?? InvitationConfiguration()
            ),
            renderUsers: { users, context in
                PageLayout(title: "Users", pageContext: PageContext(from: context)) {
                    AdminUsersView(users: users)
                }
            },
            renderInvitations: { invitations, baseURL, context in
                PageLayout(title: "Invitations", pageContext: PageContext(from: context)) {
                    AdminInvitationsView(invitations: invitations, baseURL: baseURL)
                }
            }
        )

        var app = Application(
            router: router,
            configuration: .init(address: .hostname(hostname, port: port))
        )
        app.addServices(fluent)

        logger.info("Prospero running on http://\(hostname):\(port)")
        try await app.runService()
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
