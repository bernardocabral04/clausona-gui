// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClausonaGUI",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClausonaGUI"),
        .executableTarget(name: "ClausonaApp", dependencies: ["ClausonaGUI"]),
        .testTarget(name: "ClausonaGUITests", dependencies: ["ClausonaGUI"]),
    ]
)
