import Vapor
import Leaf
import FluentPostgresDriver
import Fluent
import FluentKit

// configures your application
public func configure(_ app: Application) throws {
    app.views.use(.leaf)
    app.leaf.cache.isEnabled = app.environment.isRelease
    app.leaf.tags["isEven"] = IsEvenTag()
    app.leaf.tags["dateFormat"] = DateFormatTag()
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    guard let databaseUrlString = Environment.get("DATABASE_URL") else { throw Abort(.internalServerError) }
    guard let databaseUrl = URL(string: databaseUrlString) else { throw Abort(.internalServerError) }
    
    var tlsConfig: TLSConfiguration = .makeClientConfiguration()
    if Environment.get("should_override_default_transport_config") == "true" {
        tlsConfig.certificateVerification = .none
    }
    
    let nioSSLContext = try NIOSSLContext(configuration: tlsConfig)
    var postgresConfig = try SQLPostgresConfiguration(url: databaseUrl)
    postgresConfig.coreConfiguration.tls = .require(nioSSLContext)

    app.databases.use(
        .postgres(
            configuration: postgresConfig
        ),
        as: .psql
    )

    // register routes
    try routes(app)
}
