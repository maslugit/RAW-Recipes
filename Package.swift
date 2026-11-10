// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RAWRecipes",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "RAWRecipes",
            path: "Sources/RAWRecipes",
            resources: [.copy("Resources/Fonts"), .copy("Resources/AppIcon.icns")],
            linkerSettings: [
                .linkedFramework("ImageCaptureCore"),
                .linkedFramework("CoreImage"),
            ]
        )
    ]
)
