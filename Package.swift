// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiveAirspace",
    platforms: [.tvOS(.v17), .macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "LiveAirspaceKit", targets: ["LiveAirspaceKit"]),
        .library(name: "LiveAirspaceUI", targets: ["LiveAirspaceUI"]),
        .executable(name: "airspace-probe", targets: ["airspace-probe"]),
    ],
    targets: [
        .target(name: "LiveAirspaceKit"),
        .target(name: "LiveAirspaceUI", dependencies: ["LiveAirspaceKit"]),
        .executableTarget(name: "airspace-probe", dependencies: ["LiveAirspaceKit", "LiveAirspaceUI"]),
        .testTarget(name: "LiveAirspaceKitTests", dependencies: ["LiveAirspaceKit"]),
        .testTarget(name: "LiveAirspaceUITests", dependencies: ["LiveAirspaceKit", "LiveAirspaceUI"]),
    ],
    swiftLanguageModes: [.v5]
)
