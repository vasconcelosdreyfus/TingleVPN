// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TingleVPNTray",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TingleVPNTray", targets: ["TingleVPNTray"])
    ],
    targets: [
        .executableTarget(name: "TingleVPNTray")
    ]
)
