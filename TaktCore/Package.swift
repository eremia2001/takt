// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TaktCore",
    platforms: [.macOS("15.0")],  // String-Form: .v15 erst ab PackageDescription 6.0
    products: [
        .library(name: "TaktCore", targets: ["TaktCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "TaktCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "TaktCoreTests",
            dependencies: ["TaktCore"]
        ),
    ]
)
