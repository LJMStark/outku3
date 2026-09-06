// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "KiroleFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "KiroleFeature",
            targets: ["KiroleFeature"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "8.0.0"),
        // Pinned exactly: the Outlook Calendar path is written against MSAL 2.14.x
        // Objective-C APIs (MSALPublicClientApplicationConfig / MSALSilentTokenParameters).
        // Bump only together with a re-run of the Microsoft* test suites.
        .package(
            url: "https://github.com/AzureAD/microsoft-authentication-library-for-objc",
            exact: "2.14.1"
        ),
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.2"),
    ],
    targets: [
        .target(
            name: "KiroleFeature",
            dependencies: [
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
                .product(name: "GoogleSignInSwift", package: "GoogleSignIn-iOS"),
                .product(
                    name: "MSAL",
                    package: "microsoft-authentication-library-for-objc"
                ),
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "KiroleInternalBLE",
            dependencies: ["KiroleFeature"],
            swiftSettings: [
                .define("KIROLE_INTERNAL_BLE_MODULE")
            ]
        ),
        .testTarget(
            name: "KiroleFeatureTests",
            dependencies: [
                "KiroleFeature",
                "KiroleInternalBLE",
            ]
        ),
    ]
)
