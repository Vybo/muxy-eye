// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MuxyEye",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MuxyEyeCore", targets: ["MuxyEyeCore"]),
        .executable(name: "muxy-eye-hook", targets: ["MuxyEyeHook"]),
        .executable(name: "MuxyEye", targets: ["MuxyEyeApp"])
    ],
    targets: [
        .target(name: "MuxyEyeCore"),
        .executableTarget(name: "MuxyEyeHook", dependencies: ["MuxyEyeCore"]),
        .executableTarget(name: "MuxyEyeApp", dependencies: ["MuxyEyeCore"]),
        .testTarget(
            name: "MuxyEyeCoreTests",
            dependencies: ["MuxyEyeCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
