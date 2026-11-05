import ProjectDescription

let mgVersion = Environment.mgVersion.getString(default: "0.0.0")
let sparklePublicKey = Environment.sparklePublicKey.getString(default: "")

// An empty SUPublicEDKey is invalid, and Sparkle then refuses to start.
var appInfoPlist: [String: Plist.Value] = [
    "LSMinimumSystemVersion": "14.0",
    "CFBundleDisplayName": "MediaGrabber",
    "NSHumanReadableCopyright": "MIT",
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "ATSApplicationFontsPath": ".",
    "CFBundleIconFile": "AppIcon",
    "CFBundleURLTypes": [
        [
            "CFBundleURLName": "MediaGrabber",
            "CFBundleTypeRole": "Editor",
            "CFBundleURLSchemes": ["mediagrabber"]
        ]
    ],
    "SUFeedURL": "https://mshardul.github.io/Tools/media-grabber/appcast.xml",
    "SUEnableAutomaticChecks": true,
    "SUAutomaticallyUpdate": false,
    "NSServices": [
        [
            "NSMenuItem": ["default": "Download with MediaGrabber"],
            "NSMessage": "downloadWithMediaGrabber",
            "NSPortName": "MediaGrabber",
            "NSSendTypes": [
                "public.utf8-plain-text",
                "public.url",
                "NSStringPboardType"
            ]
        ]
    ]
]
if !sparklePublicKey.isEmpty {
    appInfoPlist["SUPublicEDKey"] = .string(sparklePublicKey)
}

let project = Project(
    name: "MediaGrabber",
    options: .options(
        automaticSchemesOptions: .enabled(),
        developmentRegion: "en"
    ),
    packages: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.7.1")
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "MACOSX_DEPLOYMENT_TARGET": "14.0",
            "MARKETING_VERSION": .string(mgVersion),
            "CURRENT_PROJECT_VERSION": .string(mgVersion)
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
            infoPlist: .extendingDefault(with: appInfoPlist),
            sources: ["Sources/App/**"],
            resources: [
                "PRIVACY.md",
                "Resources/Fonts/**",
                "Resources/AppIcon.icns",
                "Resources/Tools/**",
                "Resources/Shield/**",
                "Resources/NOTICES.md"
            ],
            dependencies: [
                .target(name: "GrabberKit"),
                .target(name: "ShareExtension"),
                .package(product: "Sparkle")
            ],
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "-",
                "CODE_SIGN_STYLE": "Manual",
                "ENABLE_HARDENED_RUNTIME": "NO",
                "ENABLE_APP_SANDBOX": "NO"
            ])
        ),
        .target(
            name: "ShareExtension",
            destinations: .macOS,
            product: .appExtension,
            bundleId: "app.mediagrabber.mac.share",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "MediaGrabber",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.share-services",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).ShareViewController",
                    "NSExtensionAttributes": [
                        "NSExtensionActivationRule": [
                            "NSExtensionActivationSupportsWebURLWithMaxCount": 1,
                            "NSExtensionActivationSupportsText": true
                        ]
                    ]
                ]
            ]),
            sources: ["Sources/ShareExtension/**"],
            dependencies: [.target(name: "GrabberKit")],
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "-",
                "CODE_SIGN_STYLE": "Manual",
                "ENABLE_HARDENED_RUNTIME": "NO",
                "ENABLE_APP_SANDBOX": "YES",
                "CODE_SIGN_ENTITLEMENTS": "Sources/ShareExtension/ShareExtension.entitlements"
            ])
        ),
        .target(
            name: "GrabberKit",
            destinations: .macOS,
            product: .framework,
            bundleId: "app.mediagrabber.mac.kit",
            deploymentTargets: .macOS("14.0"),
            sources: ["Sources/GrabberKit/**"],
            resources: [.folderReference(path: "Resources/YtDlpPlugins")],
            dependencies: []
        ),
        .target(
            name: "TestSupport",
            destinations: .macOS,
            product: .framework,
            bundleId: "app.mediagrabber.mac.testsupport",
            deploymentTargets: .macOS("14.0"),
            sources: ["Tests/TestSupport/**"],
            resources: ["Tests/GrabberKitTests/Fixtures/**"],
            dependencies: [.target(name: "GrabberKit")]
        ),
        .target(
            name: "GrabberKitTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "app.mediagrabber.mac.kit.tests",
            deploymentTargets: .macOS("14.0"),
            sources: ["Tests/GrabberKitTests/**"],
            resources: ["Tests/GrabberKitTests/Fixtures/**"],
            dependencies: [.target(name: "GrabberKit"), .target(name: "TestSupport")]
        ),
        .target(
            name: "AppUnitTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "app.mediagrabber.mac.tests",
            deploymentTargets: .macOS("14.0"),
            sources: ["Tests/AppUnitTests/**"],
            dependencies: [.target(name: "MediaGrabber"), .target(name: "TestSupport")]
        )
    ],
    schemes: [
        .scheme(
            name: "MediaGrabber-Workspace",
            shared: true,
            buildAction: .buildAction(targets: ["MediaGrabber", "GrabberKit"]),
            testAction: .targets(
                ["GrabberKitTests", "AppUnitTests"],
                options: .options(
                    coverage: true,
                    codeCoverageTargets: ["GrabberKit", "MediaGrabber"]
                )
            )
        )
    ]
)
