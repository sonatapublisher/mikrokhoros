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

public struct WorldCreationResult: Codable, Equatable, Sendable {
  public let id: String
  public let name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

public enum WorldCreationError: Error, Equatable, Sendable {
  case invalidName
}

/// The typed service mutation used by browser and future presentation hosts.
/// It follows the same lock, recovery, treasury, and product-transaction boundary
/// as `khoros world create` without invoking the CLI or editing persistence files
/// from a presentation adapter.
public final class WorldCreationService: @unchecked Sendable {
  public let layout: ProductLayout

  public init(layout: ProductLayout) {
    self.layout = layout
  }

  public func createBareWorld(name: String) throws -> WorldCreationResult {
    do {
      try WorldCatalogRecord.validateName(name)
    } catch {
      throw WorldCreationError.invalidName
    }

    let lock = try ProductStateLock(root: layout.canonicalRoot)
    defer { withExtendedLifetime(lock) {} }
    try ProductStateTransaction.recoverPending(root: layout.canonicalRoot)

    let configuration = try ConfigurationStore.load(from: layout.configurationURL)
    let agents = try AgentStore(
      url: layout.agentURL,
      maximumBytes: configuration.runtime.maximumAgentStoreBytes
    )
    let inventory = try InventoryStore(
      url: layout.inventoryURL,
      packageDirectory: layout.packagesDirectoryURL,
      limits: configuration.runtime,
      runtimeRegistry: .installedCLI()
    )
    let worlds = try WorldCatalogStore(
      url: layout.catalogURL,
      maximumBytes: configuration.runtime.maximumWorldBytes
    )
    let treasuryStore = try TreasuryAuthorityStore(
      url: layout.treasuryURL,
      maximumBytes: configuration.runtime.maximumWorldBytes
    )
    let treasuryAuthority: TreasuryAuthorityState
    do {
      treasuryAuthority = try treasuryStore.load()
    } catch {
      guard (error as? MikroKhorosError)?.issue.code == "treasury.authority_not_found" else {
        throw error
      }
      treasuryAuthority = try treasuryStore.bootstrap(
        confirmNoExistingEconomy: agents.allAgents().isEmpty && worlds.document.worlds.isEmpty
      )
    }

    return try createBareWorldAssumingLocked(
      name: name,
      configuration: configuration,
      worlds: worlds,
      inventory: inventory,
      treasuryAuthority: treasuryAuthority
    )
  }

  /// The shared bare-world operation for a product host that already owns the
  /// product lock, recovered pending work, and loaded the exact stores below.
  /// Calling the public locking entry from that state would self-deadlock.
  package func createBareWorldAssumingLocked(
    name: String,
    configuration: RuntimeConfiguration,
    worlds: WorldCatalogStore,
    inventory: InventoryStore,
    treasuryAuthority: TreasuryAuthorityState
  ) throws -> WorldCreationResult {
    try WorldCatalogRecord.validateName(name)

    let document = WorldDocument(worldName: name)
    let worldURL = try layout.worldURL(for: document.worldID)
    let runtime = try WorldRuntime(
      document: document,
      configuration: configuration,
      inventory: inventory,
      treasuryAuthority: treasuryAuthority
    )
    let priorInventory = inventory.document
    let priorCatalog = worlds.document
    let transaction = try ProductStateTransaction.begin(
      targets: [inventory.url, worlds.url, worldURL],
      affectedWorldIDs: Set([document.worldID]),
      root: layout.canonicalRoot
    )
    do {
      try saveWorld(runtime, to: worldURL)
      let record = try worlds.register(document: runtime.document, makeCurrent: true)
      try worlds.save()
      try transaction.commit()
      return WorldCreationResult(id: record.id, name: record.name)
    } catch {
      try? inventory.restoreDocument(priorInventory, persist: false)
      try? worlds.restoreDocument(priorCatalog, persist: false)
      try? transaction.rollback()
      throw error
    }
  }

  private func saveWorld(_ runtime: WorldRuntime, to worldURL: URL) throws {
    let references = runtime.activeInventoryArtifactReferences
    if let inventory = runtime.inventory {
      let retained = inventory.worldReferences(for: runtime.harness.world.hash)
        .union(references)
      try inventory.synchronizeWorldReferences(
        worldID: runtime.harness.world.hash,
        credentialHandles: retained.credentialHandles,
        packageHashes: retained.packageHashes
      )
    }
    try WorldStore.save(
      runtime.document,
      to: worldURL,
      maximumBytes: runtime.configuration.runtime.maximumWorldBytes
    )
    if let inventory = runtime.inventory {
      try inventory.synchronizeWorldReferences(
        worldID: runtime.harness.world.hash,
        credentialHandles: references.credentialHandles,
        packageHashes: references.packageHashes
      )
    }
  }
}
