// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MikroKhoros",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(name: "MikroKhoros", targets: ["MikroKhoros"]),
    .executable(name: "khoros", targets: ["MikroKhorosCLI"]),
  ],
  targets: [
    .target(name: "MikroKhoros"),
    .executableTarget(name: "MikroKhorosCLI", dependencies: ["MikroKhoros"]),
    .testTarget(name: "MikroKhorosTests", dependencies: ["MikroKhoros"]),
  ]
)
