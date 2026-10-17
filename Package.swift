// swift-tools-version: 6.2
import PackageDescription

// ToolHUDKit holds the logic that doesn't need AppKit (slots, the lens catalog, HUD geometry,
// sync encryption), so `swift test` covers it. The app is built by build_app.sh.
let package = Package(
    name: "ToolHUD",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "ToolHUDKit"),
        .executableTarget(name: "ToolHUD", dependencies: ["ToolHUDKit"]),
        .testTarget(name: "ToolHUDKitTests", dependencies: ["ToolHUDKit"]),
    ]
)
