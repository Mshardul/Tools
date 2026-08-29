import ProjectDescription

let project = Project(
    name: "MediaGrabber",
    options: .options(
        automaticSchemesOptions: .enabled(),
        developmentRegion: "en"
    ),
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "MACOSX_DEPLOYMENT_TARGET": "14.0"
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release")
        ]
    ),
    targets: [
        .target(
            name: "MediaGrabber",
            destinations: .macOS,
            product: .app,
            bundleId: "app.mediagrabber.mac",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "LSMinimumSystemVersion": "14.0",
                "CFBundleDisplayName": "MediaGrabber",
                "NSHumanReadableCopyright": "MIT"
            ]),
            sources: ["Sources/App/**"],
            resources: [],
            dependencies: [.target(name: "GrabberKit")],
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "-",
                "CODE_SIGN_STYLE": "Manual",
                "ENABLE_HARDENED_RUNTIME": "NO",
                "ENABLE_APP_SANDBOX": "NO"
            ])
        ),
        .target(
            name: "GrabberKit",
            destinations: .macOS,
            product: .framework,
            bundleId: "app.mediagrabber.mac.kit",
            deploymentTargets: .macOS("14.0"),
            sources: ["Sources/GrabberKit/**"],
            dependencies: []
        ),
        .target(
            name: "GrabberKitTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "app.mediagrabber.mac.kit.tests",
            deploymentTargets: .macOS("14.0"),
            sources: ["Tests/GrabberKitTests/**"],
            resources: ["Tests/GrabberKitTests/Fixtures/**"],
            dependencies: [.target(name: "GrabberKit")]
        ),
        .target(
            name: "AppUnitTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "app.mediagrabber.mac.tests",
            deploymentTargets: .macOS("14.0"),
            sources: ["Tests/AppUnitTests/**"],
            dependencies: [.target(name: "MediaGrabber")]
        )
    ]
)
