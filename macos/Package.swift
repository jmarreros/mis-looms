// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MisLooms",
    // macOS 15: ScreenCaptureKit captura el micrófono directamente (captureMicrophone).
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "MisLooms", path: "Sources/MisLooms")
    ]
)
