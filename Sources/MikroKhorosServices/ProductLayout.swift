// Copyright © 2026 mikrokhoros contributors.
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

import Foundation
import MikroKhoros

/// The concrete product files used by host services.
///
/// Keeping these URLs in one value is important for embedded hosts and tests:
/// the host must not silently fall back to ``MikroKhorosPaths.root``
/// after a caller selected another product root.
public struct ProductLayout: Equatable, Sendable {
  public let canonicalRoot: URL
  public let configurationURL: URL
  public let catalogURL: URL
  public let worldsDirectoryURL: URL
  public let agentURL: URL
  public let inventoryURL: URL
  public let packagesDirectoryURL: URL
  public let credentialsDirectoryURL: URL
  public let treasuryURL: URL

  public init(canonicalRoot: URL) {
    self.init(canonicalRoot: canonicalRoot, configurationURL: nil)
  }

  /// Creates a layout whose product root remains canonical while the
  /// configuration document is explicitly supplied by the caller. This is
  /// the only supported way for `--config` to affect a web host.
  public init(canonicalRoot: URL, configurationURL: URL?) {
    let root = URL(
      fileURLWithPath: canonicalRoot.standardizedFileURL.path,
      isDirectory: true
    ).standardizedFileURL
    self.canonicalRoot = root
    self.configurationURL =
      configurationURL?.standardizedFileURL
      ?? root.appendingPathComponent("config.json", isDirectory: false)
    worldsDirectoryURL = root.appendingPathComponent("worlds", isDirectory: true)
    catalogURL = worldsDirectoryURL.appendingPathComponent("index.json", isDirectory: false)
    agentURL = root.appendingPathComponent("agents.json", isDirectory: false)
    inventoryURL = root.appendingPathComponent("inventory.json", isDirectory: false)
    packagesDirectoryURL = root.appendingPathComponent("packages", isDirectory: true)
    credentialsDirectoryURL = root.appendingPathComponent("credentials", isDirectory: true)
    treasuryURL = root.appendingPathComponent("treasury-authority.json", isDirectory: false)
  }

  public init(canonicalRoot: URL, configURL: URL?) {
    self.init(canonicalRoot: canonicalRoot, configurationURL: configURL)
  }

  /// Compatibility spelling used by hosts that call the product root a URL.
  public var rootURL: URL { canonicalRoot }
  public var root: URL { canonicalRoot }

  public var configURL: URL { configurationURL }
  public var config: URL { configurationURL }
  public var catalog: URL { catalogURL }
  public var worlds: URL { worldsDirectoryURL }
  public var agent: URL { agentURL }
  public var inventory: URL { inventoryURL }
  public var packages: URL { packagesDirectoryURL }
  public var credentials: URL { credentialsDirectoryURL }
  public var treasury: URL { treasuryURL }
  public var treasuryAuthorityURL: URL { treasuryURL }
  public var worldsURL: URL { worldsDirectoryURL }
  public var agentsURL: URL { agentURL }
  public var packagesURL: URL { packagesDirectoryURL }
  public var credentialsURL: URL { credentialsDirectoryURL }

  public func worldURL(for exactWorldID: String) throws -> URL {
    guard InventoryIdentity.isValid(exactWorldID) else {
      throw MikroKhorosError.runtime(
        "world.identity_invalid",
        "the world id must be a complete runtime-issued identity"
      )
    }
    return worldsDirectoryURL.appendingPathComponent(
      "\(exactWorldID).json",
      isDirectory: false
    )
  }
}
