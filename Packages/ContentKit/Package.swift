// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ContentKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "ContentKit", targets: ["ContentKit"])],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "ContentKit",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "ContentKitTests", dependencies: ["ContentKit"]),
    ]
)
