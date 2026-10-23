// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MuxyEye",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MuxyEyeCore", targets: ["MuxyEyeCore"])
    ],
    targets: [
        .target(name: "MuxyEyeCore"),
        .testTarget(
            name: "MuxyEyeCoreTests",
            dependencies: ["MuxyEyeCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
