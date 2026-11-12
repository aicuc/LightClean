// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "LightClean", platforms: [.macOS(.v14)], products: [.executable(name: "LightClean", targets: ["LightClean"])], targets: [.executableTarget(name: "LightClean")])
