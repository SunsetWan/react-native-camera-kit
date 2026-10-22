// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NativeCameraKit",
    platforms: [.iOS(.v18)],
    products: [.library(name: "NativeCameraKit", targets: ["NativeCameraKit"])],
    targets: [
        .target(name: "NativeCameraKit", path: "NativeCameraKit/Sources/NativeCameraKit"),
        .testTarget(
            name: "NativeCameraKitTests",
            dependencies: ["NativeCameraKit"],
            path: "NativeCameraKit/Tests/NativeCameraKitTests",
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v5]
)
