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
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(name: "AgentCore", dependencies: ["SwiftSoup"]),
        // Fixture'lar #filePath ile okunur (Bundle.module'a gerek yok).
        .testTarget(name: "AgentCoreTests", dependencies: ["AgentCore"], exclude: ["Fixtures"]),
    ]
)
