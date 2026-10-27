// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ScreenPeek",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ScreenPeek", targets: ["ScreenPeek"])
    ],
    targets: [
        .executableTarget(
            name: "ScreenPeek",
            path: "Sources/ScreenPeek",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
