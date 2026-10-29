// swift-tools-version: 6.0
import PackageDescription

// Saf Swift: Apple'a özel framework (SwiftUI, SwiftData, Security...) import edilmez,
// böylece Windows'ta `swift test` ile test edilebilir.
let package = Package(
    name: "AgentCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AgentCore", targets: ["AgentCore"]),
    ],
    targets: [
        .target(name: "AgentCore"),
        .testTarget(name: "AgentCoreTests", dependencies: ["AgentCore"]),
    ]
)
