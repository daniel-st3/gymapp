// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LittleLift",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v14)],
    products: [.library(name: "WorkoutCore", targets: ["WorkoutCore"])],
    targets: [
        .target(name: "WorkoutCore", path: "Sources/WorkoutCore"),
        .testTarget(name: "WorkoutCoreTests", dependencies: ["WorkoutCore"], path: "Tests/WorkoutCoreTests")
    ]
)
