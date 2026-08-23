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

import Foundation
import MikroKhoros

public enum WorldAgentPresenceState: String, Codable, Equatable, Sendable {
  case available
  case present
  case assignedElsewhere
}

/// A deliberately small user-agent catalog projection for one exact World.
/// Profiles, genesis equipment, credentials, and private runtime state remain absent.
public struct WorldAgentPresenceEntry: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let state: WorldAgentPresenceState
  public let visual: WorldVisualIdentitySnapshot

  public init(
    id: String,
    name: String,
    state: WorldAgentPresenceState,
    visual: WorldVisualIdentitySnapshot
  ) {
    self.id = id
    self.name = name
    self.state = state
    self.visual = visual
  }
}

public struct WorldAgentPresenceOptions: Codable, Equatable, Sendable {
  public let worldID: String
  public let agents: [WorldAgentPresenceEntry]

  public init(worldID: String, agents: [WorldAgentPresenceEntry]) {
    self.worldID = worldID
    self.agents = agents
  }
}

public struct WorldAgentAdditionResult: Codable, Equatable, Sendable {
  public let worldID: String
  public let agentID: String
  public let name: String
  public let requested: WorldCoordinateSnapshot
  public let actual: WorldCoordinateSnapshot
  public let adapted: Bool

  public init(
    worldID: String,
    agentID: String,
    name: String,
    requested: WorldCoordinateSnapshot,
    actual: WorldCoordinateSnapshot,
    adapted: Bool
  ) {
    self.worldID = worldID
    self.agentID = agentID
    self.name = name
    self.requested = requested
    self.actual = actual
    self.adapted = adapted
  }
}

public enum WorldAgentPresenceError: Error, Equatable, Sendable {
  case invalidSelector
  case unavailable
  case alreadyPresent
  case assignedElsewhere
}

/// The service mutation shared by browser presentation hosts and future
/// non-CLI surfaces for `agent add`. It preserves the exact AgentStore/World
/// assignment rules and publishes the cross-store change atomically.
public final class WorldAgentPresenceService: @unchecked Sendable {
  /// Agent selectors are user-owned persisted data. The browser receives a
  /// deterministic prefix rather than an unbounded catalog response.
  public static let maximumOptionEntries = 256

  public let layout: ProductLayout
  private let optionLimit: Int

  public init(
    layout: ProductLayout,
    optionLimit: Int = maximumOptionEntries
  ) {
    self.layout = layout
    self.optionLimit = max(1, min(optionLimit, Self.maximumOptionEntries))
  }

  public func options(worldID: String) throws -> WorldAgentPresenceOptions {
    guard InventoryIdentity.isValid(worldID) else {
      throw WorldAgentPresenceError.invalidSelector
    }

    let lock = try ProductStateLock(root: layout.canonicalRoot)
    defer { withExtendedLifetime(lock) {} }
    try ProductStateTransaction.recoverPending(root: layout.canonicalRoot)

    let configuration = try ConfigurationStore.load(from: layout.configurationURL)
    let worlds = try WorldCatalogStore(
      url: layout.catalogURL,
      maximumBytes: configuration.runtime.maximumWorldBytes
    )
    let worldRecord = try exactWorldRecord(worldID, in: worlds)
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
    let document = try WorldStore.load(
      from: layout.worldURL(for: worldRecord.id),
      maximumBytes: configuration.runtime.maximumWorldBytes
    )
    guard document.worldID == worldRecord.id, document.credit != nil else {
      throw WorldAgentPresenceError.unavailable
    }
    let runtime = try WorldRuntime(
      document: document,
      configuration: configuration,
      inventory: inventory,
      treasuryAuthority: nil
    )

    let entries = try agents.allAgents().prefix(optionLimit).map { source in
      let concrete = runtime.harness.findAgent(source.id)
      if concrete != nil,
        let assignment = source.worldAssignment,
        assignment.worldID != worldRecord.id
      {
        throw WorldAgentPresenceError.unavailable
      }
      let state: WorldAgentPresenceState
      if let assignment = source.worldAssignment, assignment.worldID != worldRecord.id {
        state = .assignedElsewhere
      } else if concrete?.isInWorld == true {
        state = .present
      } else {
        state = .available
      }
      return try WorldAgentPresenceEntry(
        id: source.id,
        name: source.name,
        state: state,
        visual: StableVisualIdentity.snapshot(for: source.id)
      )
    }
    return WorldAgentPresenceOptions(worldID: worldRecord.id, agents: entries)
  }

  public func addAgent(
    worldID: String,
    agentID: String,
    coordinate: Coordinate,
    autoAdapt: Bool
  ) throws -> WorldAgentAdditionResult {
    guard InventoryIdentity.isValid(worldID), InventoryIdentity.isValid(agentID) else {
      throw WorldAgentPresenceError.invalidSelector
    }

    let lock = try ProductStateLock(root: layout.canonicalRoot)
    defer { withExtendedLifetime(lock) {} }
    try ProductStateTransaction.recoverPending(root: layout.canonicalRoot)

    let configuration = try ConfigurationStore.load(from: layout.configurationURL)
    let worlds = try WorldCatalogStore(
      url: layout.catalogURL,
      maximumBytes: configuration.runtime.maximumWorldBytes
    )
    let worldRecord = try exactWorldRecord(worldID, in: worlds)
    let agents = try AgentStore(
      url: layout.agentURL,
      maximumBytes: configuration.runtime.maximumAgentStoreBytes
    )
    guard let source = agents.document.agents.first(where: { $0.id == agentID }) else {
      throw WorldAgentPresenceError.invalidSelector
    }
    if let assignment = source.worldAssignment, assignment.worldID != worldRecord.id {
      throw WorldAgentPresenceError.assignedElsewhere
    }
    let inventory = try InventoryStore(
      url: layout.inventoryURL,
      packageDirectory: layout.packagesDirectoryURL,
      limits: configuration.runtime,
      runtimeRegistry: .installedCLI()
    )
    let treasury = try TreasuryAuthorityStore(
      url: layout.treasuryURL,
      maximumBytes: configuration.runtime.maximumWorldBytes
    ).load()
    let worldURL = try layout.worldURL(for: worldRecord.id)
    let document = try WorldStore.load(
      from: worldURL,
      maximumBytes: configuration.runtime.maximumWorldBytes
    )
    guard document.worldID == worldRecord.id, document.credit != nil else {
      throw WorldAgentPresenceError.unavailable
    }
    let runtime = try WorldRuntime(
      document: document,
      configuration: configuration,
      inventory: inventory,
      treasuryAuthority: treasury
    )
    if runtime.harness.findAgent(source.id)?.isInWorld == true {
      throw WorldAgentPresenceError.alreadyPresent
    }

    let priorAgents = agents.document
    let priorInventory = inventory.document
    let transaction = try ProductStateTransaction.begin(
      targets: [agents.url, inventory.url, worldURL],
      affectedWorldIDs: [worldRecord.id],
      root: layout.canonicalRoot
    )
    do {
      let agent = try runtime.registerAgent(source)
      let placement = try runtime.addAgent(
        agent,
        at: coordinate,
        autoAdapt: autoAdapt
      )
      _ = try agents.assign(source.id, toWorld: worldRecord.id)
      try saveWorld(runtime, to: worldURL)
      try agents.save()
      try transaction.commit()
      return WorldAgentAdditionResult(
        worldID: worldRecord.id,
        agentID: source.id,
        name: source.name,
        requested: WorldCoordinateSnapshot(placement.requested),
        actual: WorldCoordinateSnapshot(placement.actual),
        adapted: placement.adapted
      )
    } catch {
      try? agents.restoreDocument(priorAgents, persist: false)
      try? inventory.restoreDocument(priorInventory, persist: false)
      try? transaction.rollback()
      throw error
    }
  }

  private func exactWorldRecord(
    _ worldID: String,
    in worlds: WorldCatalogStore
  ) throws -> WorldCatalogRecord {
    guard let record = worlds.document.worlds.first(where: { $0.id == worldID }) else {
      throw WorldAgentPresenceError.invalidSelector
    }
    return record
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
