// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Mend",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Mend", targets: ["Mend"]),
    ],
    targets: [
        .executableTarget(
            name: "Mend",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "MendTests",
            dependencies: ["Mend"]
        ),
    ]
)
