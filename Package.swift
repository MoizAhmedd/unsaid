// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "unsaid",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "UnsaidApp", targets: ["UnsaidApp"])],
    targets: [
        // Logic that doesn't need a UI, unit-tested.
        .target(name: "UnsaidCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        // The menu-bar app. Built into Unsaid.app by scripts/make-app.sh.
        .executableTarget(name: "UnsaidApp", dependencies: ["UnsaidCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "UnsaidCoreTests", dependencies: ["UnsaidCore"]),
    ]
)
