// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iphone-use",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "iphone-use", targets: ["iPhoneUse"])
    ],
    targets: [
        .executableTarget(
            name: "iPhoneUse",
            path: "Sources/iPhoneUse",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
