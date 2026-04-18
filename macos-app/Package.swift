// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SNISpoofing",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SNISpoofing",
            path: "Sources/SNISpoofing",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
