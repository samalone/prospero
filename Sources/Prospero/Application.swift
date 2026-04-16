import ArgumentParser
import FluentKit
import FluentPostgresDriver
import FluentSQLiteDriver
import Foundation
import Hummingbird
import HummingbirdFluent
import Logging
import Plot

@main
struct ProsperoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prospero",
        abstract: "Reverse weather forecaster — find upcoming windows matching your activity patterns.",
        subcommands: [Serve.self, Migrate.self],
        defaultSubcommand: Serve.self
    )
}

/// Configure the Fluent database from the DATABASE_URL environment variable.
/// If DATABASE_URL is set, uses PostgreSQL; otherwise falls back to SQLite for local dev.
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
    await fluent.migrations.add(CreateActivityPatterns())
}

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the Prospero web server."
    )

    @Option(name: .shortAndLong, help: "Hostname to bind to.")
    var hostname: String = "127.0.0.1"

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

        let router = Router()
        let db = fluent.db()

        // Middleware
        router.add(middleware: LogRequestsMiddleware(.info))
        router.add(middleware: ErrorLoggingMiddleware(logger: logger))

        if let staticPath = Bundle.module.path(forResource: "Static", ofType: nil) {
            router.add(middleware: FileMiddleware(staticPath, logger: logger))
        } else {
            logger.warning("Static resources directory not found")
        }

        // Routes
        addPatternRoutes(to: router, db: db, logger: logger)
        addForecastRoutes(to: router, db: db, logger: logger)

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
