// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "osaurus-spend",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "osaurus-spend", type: .dynamic, targets: ["osaurus_spend"])
    ],
    targets: [
        .target(
            name: "osaurus_spend",
            path: "Sources/osaurus_spend"
        )
    ]
)