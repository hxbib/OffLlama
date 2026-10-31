// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PocketCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PocketCore", targets: ["PocketCore"]),
        .executable(name: "pg-cli", targets: ["pg-cli"]),
    ],
    targets: [
        // Vendored SQLite amalgamation (public domain) so the same code builds on iOS, macOS and Linux.
        .target(
            name: "CSQLite",
            cSettings: [
                .define("SQLITE_THREADSAFE", to: "2"),
                .define("SQLITE_OMIT_LOAD_EXTENSION"),
                .define("SQLITE_DQS", to: "0"),
            ]
        ),
        .target(name: "PocketCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "pg-cli", dependencies: ["PocketCore"]),
        .testTarget(name: "PocketCoreTests", dependencies: ["PocketCore"]),
    ]
)
