// swift-tools-version: 6.1
// Copyright © 2026 MikroKhoros contributors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
  dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.3.1")
  ],
  targets: [
    .target(name: "MikroKhoros", dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
    .target(name: "MikroKhorosCLIKit", dependencies: ["MikroKhoros"]),
    .executableTarget(name: "MikroKhorosCLI", dependencies: ["MikroKhorosCLIKit"]),
    .testTarget(
      name: "MikroKhorosTests",
      dependencies: [
        "MikroKhoros",
        "MikroKhorosCLIKit",
        .product(name: "Crypto", package: "swift-crypto"),
      ]
    ),
  ]
)
