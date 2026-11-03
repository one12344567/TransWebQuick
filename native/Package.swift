// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PressTrans", platforms: [.macOS(.v14)],
    products: [.executable(name: "PressTrans", targets: ["PressTrans"])],
    targets: [
        .target(name: "PressTransCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "PressTrans", dependencies: ["PressTransCore"]),
        .executableTarget(name: "PressTransChecks", dependencies: ["PressTransCore"], path: "Tests/PressTransCoreTests")
    ], swiftLanguageModes: [.v5]
)
