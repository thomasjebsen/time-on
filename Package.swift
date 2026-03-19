// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TimeOn",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "TimeOn",
            path: "Sources/TimeOn",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("IOKit"),
                .linkedFramework("UserNotifications"),
            ]
        ),
    ]
)
