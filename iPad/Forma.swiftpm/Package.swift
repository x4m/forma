// swift-tools-version: 5.9
import PackageDescription
import AppleProductTypes

// An app playground: Swift Playgrounds on iPad builds and runs this project.
let package = Package(
    name: "Forma",
    platforms: [.iOS("17.0")],
    products: [
        .iOSApplication(
            name: "Forma",
            targets: ["AppModule"],
            bundleIdentifier: "local.forma.ipad",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .pencil),
            accentColor: .presetColor(.purple),
            supportedDeviceFamilies: [.pad],
            supportedInterfaceOrientations: [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight]
        )
    ],
    targets: [
        .executableTarget(name: "AppModule", path: ".", resources: [.process("Resources")])
    ],
    swiftLanguageVersions: [.v5]
)
