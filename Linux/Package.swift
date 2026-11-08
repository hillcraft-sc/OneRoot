// swift-tools-version: 6.3
// OneRoot for Linux (#60): the GTK 4 / libadwaita app over the shared core
// (the root package's OneRootCore). Builds on Linux only — the Mac app is
// the Xcode project. See Linux/README.md.
import PackageDescription

let package = Package(
    name: "OneRootLinux",
    dependencies: [
        .package(path: ".."),
        // GTK 4 + libadwaita for Swift, chosen in phase 0 (#77). Pinned to
        // the revision tested; third-party dependencies are approved for the
        // Linux build (CLAUDE.md §3).
        .package(url: "https://github.com/makoni/swift-adwaita.git", revision: "c6b8a4ca5d89a47239b955c0174bf1849fb999ad"),
    ],
    targets: [
        // Lets GLib's main loop run Swift's main queue (see MainQueueBridge).
        .target(name: "CMainQueue"),
        // qpdf (libqpdf-dev / qpdf-devel): Combine into PDF. Approved for the
        // Linux build only (L7).
        .systemLibrary(name: "CQPDF", pkgConfig: "libqpdf", providers: [.apt(["libqpdf-dev"]), .yum(["qpdf-devel"])]),
        // Cairo's PDF surface and Pango: images and text files to PDF pages.
        .systemLibrary(name: "CPangoCairoPDF", pkgConfig: "pangocairo", providers: [.apt(["libpango1.0-dev"]), .yum(["pango-devel"])]),
        // libsecret (libsecret-1-dev / libsecret-devel): SSH passwords and
        // network share logins in the desktop keyring. Approved for the
        // Linux build only (L8).
        .systemLibrary(name: "CLibSecret", pkgConfig: "libsecret-1", providers: [.apt(["libsecret-1-dev"]), .yum(["libsecret-devel"])]),
        // poppler-glib (libpoppler-glib-dev / poppler-glib-devel): a PDF's first
        // page as a preview. Approved for the Linux build only (2026-11-07).
        .systemLibrary(name: "CPopplerGLib", pkgConfig: "poppler-glib", providers: [.apt(["libpoppler-glib-dev"]), .yum(["poppler-glib-devel"])]),
        .executableTarget(
            name: "OneRootLinux",
            dependencies: [
                "CMainQueue",
                "CPopplerGLib",
                "CQPDF",
                "CPangoCairoPDF",
                "CLibSecret",
                .product(name: "OneRootCore", package: "oneroot"),
                .product(name: "Adwaita", package: "swift-adwaita"),
            ],
            // poppler.h lives in poppler/glib on every distro; SwiftPM's
            // pkg-config pass doesn't hand that directory over on Arch.
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-Xcc", "-I/usr/include/poppler/glib"])]
        ),
        // Pure UI logic (formatting, menu models, theme CSS) without a display.
        .testTarget(
            name: "OneRootLinuxTests",
            dependencies: ["OneRootLinux"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
