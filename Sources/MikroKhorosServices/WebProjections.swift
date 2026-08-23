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

/// Bounded, domain-native read models for MikroKhoros Web. These snapshots
/// are deliberately independent of the human CLI renderer: a host reads the
/// canonical stores and receives only public product metadata.
public final class WebProjectionService: @unchecked Sendable {
  public let layout: ProductLayout

  private let maximumAgents: Int
  private let maximumSources: Int
  private let maximumPackages: Int
  private let maximumTemplates: Int
  private let maximumFields: Int
  private let maximumComponents: Int
  private let maximumEquipment: Int

  /// Nested management metadata receives explicit, conservative ceilings. A
  /// package manifest is untrusted input, so an otherwise small inventory
  /// projection must not be made arbitrarily large by one declared interface.
  private static let maximumManagementParameters = 32
  private static let maximumManagementChoices = 64
  private static let maximumManagementCapabilities = 32
  private static let maximumManagementResults = 32
  /// An agent runtime itself constrains this queue, but projections retain an
  /// independent cap so a malformed persisted document cannot turn an agent
  /// list request into an unbounded response.
  private static let maximumUnreadNotifications = 64
  private static let maximumMetadataCharacters = 512
  private static let maximumDefaultCharacters = 512
  private static let maximumReportTitleCharacters = 8_192
  private static let maximumReportBodyCharacters = 1_048_576
  private static let maximumReportPayloadBytes = 1_048_576

  public init(
    layout: ProductLayout,
    maximumAgents: Int = 256,
    maximumSources: Int = 512,
    maximumPackages: Int = 256,
    maximumTemplates: Int = 64,
    maximumFields: Int = 64,
    maximumComponents: Int = 128,
    maximumEquipment: Int = 4
  ) {
    self.layout = layout
    self.maximumAgents = Self.clamped(maximumAgents, upper: 512)
    self.maximumSources = Self.clamped(maximumSources, upper: 1_024)
    self.maximumPackages = Self.clamped(maximumPackages, upper: 512)
    self.maximumTemplates = Self.clamped(maximumTemplates, upper: 128)
    self.maximumFields = Self.clamped(maximumFields, upper: 128)
    self.maximumComponents = Self.clamped(maximumComponents, upper: 256)
    self.maximumEquipment = Self.clamped(maximumEquipment, upper: 4)
  }

  public func agents() throws -> NativeAgentManagerSnapshot {
    try withLockedProductState { configuration, catalog, agentStore, inventory in
      let worldNames = Dictionary(
        uniqueKeysWithValues: catalog.allWorlds().map { ($0.id, $0.name) })
      let sourceAgents = Array(agentStore.allAgents().prefix(maximumAgents))
      let presences = try activePresences(
        for: sourceAgents,
        worldNames: worldNames,
        configuration: configuration,
        inventory: inventory
      )
      let rows = try sourceAgents.map { source in
        let presence = presences[source.id]
        return NativeAgentRow(
          id: source.id,
          name: source.name,
          maximumActionsPerResponse: source.maximumActionsPerResponse,
          hasProfile: source.profile != nil,
          worldAssignment: source.worldAssignment.map {
            NativeAgentAssignment(
              worldID: $0.worldID,
              assignedAt: $0.assignedAt,
              worldName: worldNames[$0.worldID]
            )
          },
          activePresence: presence,
          notifications: presence?.notifications ?? .none,
          visual: try StableVisualIdentity.snapshot(for: source.id),
          createdAt: source.createdAt,
          updatedAt: source.updatedAt
        )
      }
      return NativeAgentManagerSnapshot(agents: rows, count: agentStore.allAgents().count)
    }
  }

  public func inventory() throws -> NativeInventorySnapshot {
    try withLockedProductState { _, _, _, inventory in
      let allSources = inventory.allInventoryObjects()
      let sources = Array(allSources.prefix(maximumSources))
      let sourceCounts = Dictionary(grouping: allSources, by: \.folderID)
        .mapValues(\.count)
      let folders = inventory.allInventoryFolders().prefix(maximumSources).map {
        NativeInventoryFolderRow(
          id: $0.id,
          name: $0.name,
          parentID: $0.parentID,
          sourceCount: sourceCounts[$0.id, default: 0]
        )
      }
      let readinessByID = try Dictionary(
        uniqueKeysWithValues: allSources.map { source in
          (source.id, try inventory.readiness(of: source))
        }
      )
      let readySourceCount = readinessByID.values.lazy.filter(\.ready).count
      let rows = try sources.map { source -> NativeInventorySourceRow in
        guard let readiness = readinessByID[source.id] else {
          throw MikroKhorosError.persistence("Inventory source readiness disappeared")
        }
        let package = try inventory.package(contentHash: source.packageHash).manifest
        return NativeInventorySourceRow(
          id: source.id,
          name: source.name,
          folderID: source.folderID,
          packageID: source.packageID,
          packageVersion: source.packageVersion,
          packageHash: source.packageHash,
          revision: source.revision,
          configurationFieldIDs: source.configuration.keys.sorted().prefix(maximumFields).map {
            $0
          },
          credentialFieldIDs: source.credentialHandles.keys.sorted().prefix(maximumFields).map {
            $0
          },
          requestedCapabilityIDs: source.requestedCapabilities.map(\.rawValue).sorted(),
          grantedCapabilityIDs: source.grantedCapabilities.map(\.rawValue).sorted(),
          readiness: NativeInventoryReadiness(
            isReady: readiness.ready,
            missingConfigurationFieldIDs: Array(
              readiness.missingConfiguration.prefix(maximumFields)),
            missingCredentialFieldIDs: Array(readiness.missingCredentials.prefix(maximumFields)),
            missingCapabilityIDs: readiness.missingCapabilities.map(\.rawValue).sorted()
          ),
          management: managementContract(for: package.management),
          worldBindingID: source.worldBinding?.worldID,
          forkProvenance: source.forkProvenance.map {
            NativeInventoryForkProvenance(
              parentSourceID: $0.parentInventoryObjectID,
              parentRevision: $0.parentRevision,
              forkedAt: $0.forkedAt
            )
          },
          templateSource: source.templateSource.map {
            NativeTemplateSourceReference(
              templateID: $0.templateID,
              templateVersion: $0.templateVersion,
              componentKey: $0.componentKey
            )
          },
          visual: try StableVisualIdentity.snapshot(for: source.id),
          updatedAt: source.updatedAt
        )
      }
      return NativeInventorySnapshot(
        folders: Array(folders),
        sources: rows,
        counts: NativeInventoryCounts(
          folders: inventory.allInventoryFolders().count,
          sources: allSources.count,
          readySources: readySourceCount
        )
      )
    }
  }

  public func packages() throws -> NativePackagesSnapshot {
    try withLockedProductState { _, _, _, inventory in
      let retained = Array(
        inventory.document.packages.sorted {
          if $0.manifest.id != $1.manifest.id { return $0.manifest.id < $1.manifest.id }
          if $0.manifest.version != $1.manifest.version {
            return $0.manifest.version < $1.manifest.version
          }
          return $0.contentHash < $1.contentHash
        }.prefix(maximumPackages))
      let allSources = inventory.allInventoryObjects(includeDeleted: true)
      let activeSources = inventory.allInventoryObjects()
      let retainedRows = retained.map { package in
        NativeRetainedPackageRow(
          id: package.manifest.id,
          version: package.manifest.version,
          contentHash: package.contentHash,
          displayName: boundedMetadata(package.manifest.displayName),
          summary: boundedMetadata(package.manifest.object.summary),
          runtime: package.manifest.runtime.rawValue,
          visible: package.visible,
          installedAt: package.installedAt,
          sourceCount: activeSources.filter { $0.packageHash == package.contentHash }.count,
          retainedSourceCount: allSources.filter { $0.packageHash == package.contentHash }.count,
          management: managementSummary(for: package.manifest.management)
        )
      }
      let installedVisible = Set(
        inventory.document.packages.filter(\.visible).map {
          "\($0.manifest.id)\u{0}\($0.manifest.version)"
        }
      )
      let availableManifests = uniqueAvailableManifests(
        FirstPartyPackageCatalog.available
          + inventory.document.packages.filter(\.visible).map(\.manifest)
      )
      let availableRows = availableManifests.prefix(maximumPackages).map { manifest in
        NativeAvailablePackageRow(
          id: manifest.id,
          version: manifest.version,
          displayName: boundedMetadata(manifest.displayName),
          summary: boundedMetadata(manifest.object.summary),
          runtime: manifest.runtime.rawValue,
          requestedCapabilityIDs: Array(
            manifest.requestedCapabilities.map(\.rawValue).sorted().prefix(
              Self.maximumManagementCapabilities
            )
          ),
          isInstalled: installedVisible.contains("\(manifest.id)\u{0}\(manifest.version)"),
          management: managementSummary(for: manifest.management)
        )
      }
      return NativePackagesSnapshot(
        packages: Array(availableRows),
        retainedPackages: retainedRows,
        counts: NativePackageCounts(
          available: availableManifests.count,
          retained: inventory.document.packages.count
        )
      )
    }
  }

  public func templates() throws -> NativeTemplatesSnapshot {
    try withLockedProductState { _, _, _, _ in
      let definitions = Array(
        WorldTemplateCatalog.installedCLI().definitions.prefix(maximumTemplates))
      let rows = definitions.map { definition in
        let components = definition.components.prefix(maximumComponents).map {
          NativeTemplateComponentRow(
            key: $0.key,
            packageID: $0.packageID,
            packageVersion: $0.packageVersion,
            inventoryName: $0.inventoryName,
            requestedCoordinate: WorldCoordinateSnapshot($0.coordinate),
            ownedObjectKeys: Array($0.ownedObjectKeys.prefix(maximumComponents))
          )
        }
        let placements = templatePlacements(for: definition)
        return NativeTemplateRow(
          id: definition.id,
          version: definition.version,
          displayName: boundedMetadata(definition.displayName),
          summary: boundedMetadata(definition.summary),
          contentHash: definition.contentHash,
          trusted: true,
          components: components,
          placements: placements
        )
      }
      return NativeTemplatesSnapshot(
        templates: rows, count: WorldTemplateCatalog.installedCLI().definitions.count)
    }
  }

  public func settings() throws -> NativeSettingsSnapshot {
    try withLockedProductState { configuration, catalog, agentStore, inventory in
      let settingRows = Dictionary(grouping: ConfigurationKey.all, by: settingsGroupID)
      let order = ["agents", "runtime", "console", "presentation"]
      let groups = order.compactMap { id -> NativeSettingsGroup? in
        guard let keys = settingRows[id] else { return nil }
        return NativeSettingsGroup(
          id: id,
          label: settingsGroupLabel(id),
          settings: keys.sorted { $0.path < $1.path }.prefix(maximumFields).map {
            NativeSettingRow(
              key: $0.path, label: $0.path, value: $0.value(in: configuration).description)
          }
        )
      }
      let adapters = AIAdapterCatalog.detect().sorted { $0.definition.id < $1.definition.id }
        .prefix(
          maximumPackages
        ).map {
          NativeAdapterRow(
            id: $0.definition.id,
            label: $0.definition.name,
            declared: true,
            detected: $0.isDetected
          )
        }
      return NativeSettingsSnapshot(
        groups: groups,
        currentWorld: catalog.currentWorld.map { NativeCurrentWorld(id: $0.id, name: $0.name) },
        status: NativeSettingsStatus(
          state: "ready",
          hasCurrentWorld: catalog.currentWorld != nil
        ),
        counts: NativeProductCounts(
          worlds: catalog.allWorlds().count,
          agents: agentStore.allAgents().count,
          inventorySources: inventory.allInventoryObjects().count,
          packages: inventory.document.packages.count,
          templates: WorldTemplateCatalog.installedCLI().definitions.count
        ),
        adapters: adapters
      )
    }
  }

  private func activePresences(
    for sources: [UserAgentRecord],
    worldNames: [String: String],
    configuration: RuntimeConfiguration,
    inventory: InventoryStore
  ) throws -> [String: NativeAgentPresence] {
    let sourceWorlds = Set(sources.compactMap(\.worldAssignment?.worldID))
    let boundedWorlds = Array(sourceWorlds.sorted().prefix(maximumAgents))
    var result: [String: NativeAgentPresence] = [:]
    for worldID in boundedWorlds {
      guard
        let worldDocument = try? WorldStore.load(
          from: layout.worldURL(for: worldID),
          maximumBytes: configuration.runtime.maximumWorldBytes
        ), worldDocument.worldID == worldID, worldDocument.credit != nil,
        let runtime = try? WorldRuntime(
          document: worldDocument,
          configuration: configuration,
          inventory: inventory,
          treasuryAuthority: nil
        )
      else { continue }
      for agent in runtime.harness.agents where result[agent.hash] == nil {
        guard let source = sources.first(where: { $0.id == agent.hash }) else { continue }
        let equipment = try agent.holdings.occupiedRoots.prefix(maximumEquipment).map {
          NativeAgentEquipment(
            id: $0.hash,
            name: $0.name,
            visual: try StableVisualIdentity.snapshot(for: $0.hash)
          )
        }
        result[agent.hash] = NativeAgentPresence(
          isActive: agent.isInWorld,
          worldID: worldID,
          worldName: worldNames[worldID],
          containerID: agent.space.owner.hash,
          coordinate: WorldCoordinateSnapshot(agent.coordinate),
          equipment: equipment,
          equipmentCount: agent.holdings.occupiedRoots.count,
          lifecycle: try lifecycleObjects(for: source, runtime: runtime),
          holdings: try holdingSlots(for: agent),
          primaryHoldingID: agent.primaryHeldObject?.hash,
          notifications: notificationSummary(for: agent)
        )
      }
    }
    return result
  }

  /// Produces the bounded, host-safe representation of a declared management
  /// interface. World-object projections share this exact contract so an
  /// browser surface never serializes declarative action implementations,
  /// source configuration, or unbounded package metadata.
  func managementContract(
    for management: ObjectManagementInterface
  ) -> NativeManagementContract {
    NativeManagementContract(
      fields: management.fields.prefix(maximumFields).map {
        NativeManagementField(
          id: $0.id,
          label: boundedMetadata($0.label),
          summary: boundedMetadata($0.summary),
          kind: $0.kind.rawValue,
          required: $0.required,
          deployable: $0.deployable,
          defaultValue: safeDefault($0.defaultValue, kind: $0.kind),
          choices: boundedChoices($0.choices),
          minimum: $0.minimum,
          maximum: $0.maximum,
          minimumCharacters: $0.minimumCharacters,
          maximumCharacters: $0.maximumCharacters
        )
      },
      actions: management.actions.prefix(maximumFields).map {
        let parameters = Array($0.parameters.prefix(Self.maximumManagementParameters))
        return NativeManagementAction(
          id: $0.id,
          summary: boundedMetadata($0.summary),
          parameters: parameters,
          inputTypes: boundedKinds(
            parameters: parameters,
            kinds: $0.inputTypes
          ),
          inputDefaults: safeInputDefaults(
            parameters: parameters,
            kinds: $0.inputTypes,
            defaults: $0.inputDefaults
          ),
          inputChoices: boundedInputChoices(
            parameters: parameters,
            choices: $0.inputChoices
          ),
          mutating: $0.mutating,
          requiredCapabilityIDs: Array(
            $0.requiredCapabilities.map(\.rawValue).sorted().prefix(
              Self.maximumManagementCapabilities
            )
          ),
          scope: $0.scope.rawValue,
          result: boundedKinds($0.result)
        )
      },
      views: management.views.prefix(maximumFields).map {
        NativeManagementView(
          id: $0.id,
          summary: boundedMetadata($0.summary),
          source: boundedMetadata($0.source),
          scope: $0.scope.rawValue,
          result: boundedKinds($0.result)
        )
      },
      reports: management.reports.prefix(maximumFields).map {
        NativeManagementReport(
          type: $0.type,
          summary: boundedMetadata($0.summary),
          maximumTitleCharacters: min(
            $0.maximumTitleCharacters,
            Self.maximumReportTitleCharacters
          ),
          maximumBodyCharacters: min(
            $0.maximumBodyCharacters,
            Self.maximumReportBodyCharacters
          ),
          maximumPayloadBytes: $0.maximumPayloadBytes.map {
            min($0, Self.maximumReportPayloadBytes)
          },
          payload: boundedKinds($0.payload)
        )
      }
    )
  }

  /// Metadata defaults are declaration data, not source configuration. The
  /// UI may use only simple bounded defaults that cannot reveal a filesystem
  /// path or a secret. Actual configuration and credential contents are never
  /// projected.
  private func safeDefault(
    _ value: JSONValue?,
    kind: ManagementFieldKind
  ) -> JSONValue? {
    guard kind != .secret, kind != .path, let value else { return nil }
    switch value {
    case .string(let text):
      guard text.count <= Self.maximumDefaultCharacters else { return nil }
      return .string(text)
    case .number(let number) where number.isFinite:
      return .number(number)
    case .bool(let flag):
      return .bool(flag)
    case .array, .object, .null:
      return nil
    default:
      return nil
    }
  }

  private func safeInputDefaults(
    parameters: [String],
    kinds: [String: ManagementFieldKind],
    defaults: [String: JSONValue]
  ) -> [String: JSONValue] {
    Dictionary(
      uniqueKeysWithValues: parameters.compactMap { parameter in
        guard let kind = kinds[parameter],
          let value = safeDefault(defaults[parameter], kind: kind)
        else { return nil }
        return (parameter, value)
      }
    )
  }

  private func boundedInputChoices(
    parameters: [String],
    choices: [String: [String]]
  ) -> [String: [String]] {
    Dictionary(
      uniqueKeysWithValues: parameters.compactMap { parameter in
        guard let values = choices[parameter] else { return nil }
        return (parameter, boundedChoices(values))
      }
    )
  }

  private func boundedChoices(_ values: [String]) -> [String] {
    values.prefix(Self.maximumManagementChoices).map {
      boundedMetadata($0, limit: 256)
    }
  }

  private func boundedKinds(
    parameters: [String],
    kinds: [String: ManagementFieldKind]
  ) -> [String: String] {
    Dictionary(
      uniqueKeysWithValues: parameters.compactMap { parameter in
        kinds[parameter].map { (parameter, $0.rawValue) }
      }
    )
  }

  private func boundedKinds(_ kinds: [String: ManagementFieldKind]) -> [String: String] {
    Dictionary(
      uniqueKeysWithValues: kinds.keys.sorted().prefix(Self.maximumManagementResults).compactMap {
        guard let kind = kinds[$0], kind != .secret else { return nil }
        return ($0, kind.rawValue)
      }
    )
  }

  private func boundedMetadata(_ value: String, limit: Int? = nil) -> String {
    String(value.prefix(limit ?? Self.maximumMetadataCharacters))
  }

  private func lifecycleObjects(
    for source: UserAgentRecord,
    runtime: WorldRuntime
  ) throws -> [NativeAgentLifecycleObject] {
    let roles = [
      ("backpack", "Backpack", source.genesis.backpack),
      ("wallet", "Wallet", source.genesis.wallet),
      ("eye", "Eye", source.genesis.eye),
      ("scratchpad", "Scratchpad", source.genesis.scratchpad),
      ("messenger", "Messenger", source.genesis.messenger),
      ("calculator", "Calculator", source.genesis.calculator),
    ]
    return try roles.compactMap { role, label, id in
      guard let object = runtime.harness.findObject(id) else { return nil }
      return NativeAgentLifecycleObject(
        role: role,
        label: label,
        id: object.hash,
        name: object.name,
        visual: try StableVisualIdentity.snapshot(for: object.hash)
      )
    }
  }

  private func holdingSlots(for agent: Agent) throws -> [NativeAgentHoldingSlot] {
    try HoldingNumber.allCases.map { holdingNumber in
      let object = agent.holdings[holdingNumber]
      return NativeAgentHoldingSlot(
        slot: holdingNumber.rawValue,
        objectID: object?.hash,
        name: object?.name,
        visual: try object.map { try StableVisualIdentity.snapshot(for: $0.hash) }
      )
    }
  }

  /// The browser only learns that bounded work is waiting for an active
  /// agent. Notification title, body, sender, priority, source identity, and
  /// all AI-profile details remain inside the world runtime.
  private func notificationSummary(for agent: Agent) -> NativeAgentNotificationSummary {
    let unreadCount = min(agent.pendingBroadcasts.count, Self.maximumUnreadNotifications)
    return NativeAgentNotificationSummary(
      unreadCount: unreadCount,
      canRetry: agent.isInWorld && agent.aiProfile != nil && unreadCount > 0
    )
  }

  private func managementSummary(
    for management: ObjectManagementInterface
  ) -> NativeManagementSummary {
    NativeManagementSummary(
      fieldCount: min(management.fields.count, maximumFields),
      actionCount: min(management.actions.count, maximumFields),
      viewCount: min(management.views.count, maximumFields)
    )
  }

  private func templatePlacements(
    for definition: WorldTemplateDefinition
  ) -> [NativeTemplatePlacementRow] {
    let allRows = definition.components.prefix(maximumComponents).flatMap { component in
      var rows = [
        NativeTemplatePlacementRow(
          componentKey: component.key,
          kind: "root",
          id: "root",
          displayName: component.inventoryName,
          parentID: nil,
          requestedCoordinate: WorldCoordinateSnapshot(component.coordinate)
        )
      ]
      let manifest = try? FirstPartyPackageCatalog.manifest(named: component.packageID)
      let definitions =
        manifest?.ownedObjects.filter { component.ownedObjectKeys.contains($0.id) }
        ?? []
      rows += definitions.prefix(maximumComponents).map {
        NativeTemplatePlacementRow(
          componentKey: component.key,
          kind: "owned",
          id: $0.id,
          displayName: $0.object.name,
          parentID: $0.parent,
          requestedCoordinate: WorldCoordinateSnapshot($0.coordinate)
        )
      }
      let known = Set(definitions.map(\.id))
      rows += component.ownedObjectKeys.filter { !known.contains($0) }.prefix(maximumComponents).map
      {
        NativeTemplatePlacementRow(
          componentKey: component.key,
          kind: "owned",
          id: $0,
          displayName: $0,
          parentID: "root",
          requestedCoordinate: nil
        )
      }
      return Array(rows.prefix(maximumComponents))
    }
    return Array(allRows.prefix(maximumComponents))
  }

  private func uniqueAvailableManifests(
    _ manifests: [ObjectPackageManifest]
  ) -> [ObjectPackageManifest] {
    var unique: [String: ObjectPackageManifest] = [:]
    for manifest in manifests {
      let key = "\(manifest.id)\u{0}\(manifest.version)"
      unique[key] = manifest
    }
    return unique.values.sorted {
      if $0.displayName != $1.displayName { return $0.displayName < $1.displayName }
      if $0.id != $1.id { return $0.id < $1.id }
      return $0.version < $1.version
    }
  }

  private func withLockedProductState<Value>(
    _ body: (
      RuntimeConfiguration,
      WorldCatalogStore,
      AgentStore,
      InventoryStore
    ) throws -> Value
  ) throws -> Value {
    let lock = try ProductStateLock(root: layout.canonicalRoot)
    defer { withExtendedLifetime(lock) {} }
    try ProductStateTransaction.recoverPending(root: layout.canonicalRoot)
    let configuration = try ConfigurationStore.load(from: layout.configurationURL)
    let catalog = try WorldCatalogStore(
      url: layout.catalogURL,
      maximumBytes: configuration.runtime.maximumWorldBytes
    )
    let agentStore = try AgentStore(
      url: layout.agentURL,
      maximumBytes: configuration.runtime.maximumAgentStoreBytes
    )
    let inventory = try InventoryStore(
      url: layout.inventoryURL,
      packageDirectory: layout.packagesDirectoryURL,
      limits: configuration.runtime,
      runtimeRegistry: .installedCLI()
    )
    return try body(configuration, catalog, agentStore, inventory)
  }

  private func settingsGroupID(for key: ConfigurationKey) -> String {
    switch key {
    case .agentMaximumActionsPerResponse: "agents"
    case .runtime: "runtime"
    case .console: "console"
    case .presentation: "presentation"
    }
  }

  private func settingsGroupLabel(_ id: String) -> String {
    switch id {
    case "agents": "Agents"
    case "runtime": "Runtime"
    case "console": "Console"
    default: "Presentation"
    }
  }

  private static func clamped(_ value: Int, upper: Int) -> Int {
    max(1, min(value, upper))
  }
}

public struct NativeAgentManagerSnapshot: Codable, Equatable, Sendable {
  public let agents: [NativeAgentRow]
  public let count: Int
}

public struct NativeAgentRow: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let maximumActionsPerResponse: Int
  public let hasProfile: Bool
  public let worldAssignment: NativeAgentAssignment?
  public let activePresence: NativeAgentPresence?
  /// Safe queue state for an explicit `agentRetry` control. This does not
  /// expose an event's content, source, sender, priority, or profile.
  public let notifications: NativeAgentNotificationSummary
  public let visual: WorldVisualIdentitySnapshot
  public let createdAt: Date
  public let updatedAt: Date
}

public struct NativeAgentAssignment: Codable, Equatable, Sendable {
  public let worldID: String
  public let assignedAt: Date
  public let worldName: String?
}

public struct NativeAgentPresence: Codable, Equatable, Sendable {
  public let isActive: Bool
  public let worldID: String
  public let worldName: String?
  public let containerID: String
  public let coordinate: WorldCoordinateSnapshot
  public let equipment: [NativeAgentEquipment]
  public let equipmentCount: Int
  public let lifecycle: [NativeAgentLifecycleObject]
  public let holdings: [NativeAgentHoldingSlot]
  public let primaryHoldingID: String?
  public let notifications: NativeAgentNotificationSummary
}

/// A content-free, bounded notification queue summary. `canRetry` means the
/// exact active runtime agent has an attached profile and unread work queued;
/// hosts still invoke the canonical agent retry capability rather than
/// interpreting or acknowledging queue entries themselves.
public struct NativeAgentNotificationSummary: Codable, Equatable, Sendable {
  public let unreadCount: Int
  public let canRetry: Bool

  public static let none = NativeAgentNotificationSummary(unreadCount: 0, canRetry: false)
}

public struct NativeAgentEquipment: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let visual: WorldVisualIdentitySnapshot
}

/// The six safe, user-visible lifecycle objects created with an agent. A
/// lifecycle entry is emitted only when the exact object exists in the loaded
/// canonical world runtime; no messages, notes, wallet balances, or state are
/// included.
public struct NativeAgentLifecycleObject: Codable, Equatable, Sendable {
  public let role: String
  public let label: String
  public let id: String
  public let name: String
  public let visual: WorldVisualIdentitySnapshot
}

/// All four holding slots are represented to distinguish an empty slot from
/// a loaded but non-primary slot. Object content and state remain private.
public struct NativeAgentHoldingSlot: Codable, Equatable, Sendable {
  public let slot: Int
  public let objectID: String?
  public let name: String?
  public let visual: WorldVisualIdentitySnapshot?
}

public struct NativeInventorySnapshot: Codable, Equatable, Sendable {
  public let folders: [NativeInventoryFolderRow]
  public let sources: [NativeInventorySourceRow]
  public let counts: NativeInventoryCounts
}

public struct NativeInventoryFolderRow: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let parentID: String?
  public let sourceCount: Int
}

public struct NativeInventorySourceRow: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let folderID: String
  public let packageID: String
  public let packageVersion: String
  public let packageHash: String
  public let revision: Int
  public let configurationFieldIDs: [String]
  public let credentialFieldIDs: [String]
  public let requestedCapabilityIDs: [String]
  public let grantedCapabilityIDs: [String]
  public let readiness: NativeInventoryReadiness
  public let management: NativeManagementContract
  public let worldBindingID: String?
  /// Immutable source fork lineage. Source configuration, credentials, and
  /// management state are intentionally excluded.
  public let forkProvenance: NativeInventoryForkProvenance?
  public let templateSource: NativeTemplateSourceReference?
  public let visual: WorldVisualIdentitySnapshot
  public let updatedAt: Date
}

/// Canonical provenance for a world-bound Inventory fork. The parent remains
/// an exact Inventory source identity; this projection never infers lineage
/// from package names, folders, or display labels.
public struct NativeInventoryForkProvenance: Codable, Equatable, Sendable {
  public let parentSourceID: String
  public let parentRevision: Int
  public let forkedAt: Date
}

public struct NativeInventoryReadiness: Codable, Equatable, Sendable {
  public let isReady: Bool
  public let missingConfigurationFieldIDs: [String]
  public let missingCredentialFieldIDs: [String]
  public let missingCapabilityIDs: [String]
}

public struct NativeTemplateSourceReference: Codable, Equatable, Sendable {
  public let templateID: String
  public let templateVersion: String
  public let componentKey: String
}

public struct NativeInventoryCounts: Codable, Equatable, Sendable {
  public let folders: Int
  public let sources: Int
  public let readySources: Int
}

public struct NativeManagementContract: Codable, Equatable, Sendable {
  public let fields: [NativeManagementField]
  public let actions: [NativeManagementAction]
  public let views: [NativeManagementView]
  public let reports: [NativeManagementReport]
}

public struct NativeManagementField: Codable, Equatable, Sendable {
  public let id: String
  public let label: String
  public let summary: String
  public let kind: String
  public let required: Bool
  public let deployable: Bool
  /// A bounded package-declared default. This is never the inventory source's
  /// configured value and is omitted for secret and path fields.
  public let defaultValue: JSONValue?
  public let choices: [String]
  public let minimum: Double?
  public let maximum: Double?
  public let minimumCharacters: Int?
  public let maximumCharacters: Int?
}

public struct NativeManagementAction: Codable, Equatable, Sendable {
  public let id: String
  public let summary: String
  /// Declaration order is preserved so hosts can render a predictable typed
  /// form without interpreting a command string.
  public let parameters: [String]
  public let inputTypes: [String: String]
  /// Safe package-declared defaults only. Source configuration is excluded.
  public let inputDefaults: [String: JSONValue]
  public let inputChoices: [String: [String]]
  public let mutating: Bool
  public let requiredCapabilityIDs: [String]
  public let scope: String
  public let result: [String: String]
}

public struct NativeManagementView: Codable, Equatable, Sendable {
  public let id: String
  public let summary: String
  public let source: String
  public let scope: String
  public let result: [String: String]
}

public struct NativeManagementReport: Codable, Equatable, Sendable {
  public let type: String
  public let summary: String
  public let maximumTitleCharacters: Int
  public let maximumBodyCharacters: Int
  public let maximumPayloadBytes: Int?
  public let payload: [String: String]
}

public struct NativePackagesSnapshot: Codable, Equatable, Sendable {
  public let packages: [NativeAvailablePackageRow]
  public let retainedPackages: [NativeRetainedPackageRow]
  public let counts: NativePackageCounts
}

public struct NativeAvailablePackageRow: Codable, Equatable, Sendable {
  public let id: String
  public let version: String
  public let displayName: String
  public let summary: String
  public let runtime: String
  public let requestedCapabilityIDs: [String]
  public let isInstalled: Bool
  public let management: NativeManagementSummary
}

public struct NativeRetainedPackageRow: Codable, Equatable, Sendable {
  public let id: String
  public let version: String
  public let contentHash: String
  public let displayName: String
  public let summary: String
  public let runtime: String
  public let visible: Bool
  public let installedAt: Date
  public let sourceCount: Int
  public let retainedSourceCount: Int
  public let management: NativeManagementSummary
}

public struct NativeManagementSummary: Codable, Equatable, Sendable {
  public let fieldCount: Int
  public let actionCount: Int
  public let viewCount: Int
}

public struct NativePackageCounts: Codable, Equatable, Sendable {
  public let available: Int
  public let retained: Int
}

public struct NativeTemplatesSnapshot: Codable, Equatable, Sendable {
  public let templates: [NativeTemplateRow]
  public let count: Int
}

public struct NativeTemplateRow: Codable, Equatable, Sendable {
  public let id: String
  public let version: String
  public let displayName: String
  public let summary: String
  public let contentHash: String
  public let trusted: Bool
  public let components: [NativeTemplateComponentRow]
  public let placements: [NativeTemplatePlacementRow]
}

public struct NativeTemplateComponentRow: Codable, Equatable, Sendable {
  public let key: String
  public let packageID: String
  public let packageVersion: String
  public let inventoryName: String
  public let requestedCoordinate: WorldCoordinateSnapshot
  public let ownedObjectKeys: [String]
}

public struct NativeTemplatePlacementRow: Codable, Equatable, Sendable {
  public let componentKey: String
  public let kind: String
  public let id: String
  public let displayName: String
  public let parentID: String?
  public let requestedCoordinate: WorldCoordinateSnapshot?
}

public struct NativeSettingsSnapshot: Codable, Equatable, Sendable {
  public let groups: [NativeSettingsGroup]
  public let currentWorld: NativeCurrentWorld?
  public let status: NativeSettingsStatus
  public let counts: NativeProductCounts
  public let adapters: [NativeAdapterRow]
}

/// A bounded host-facing health summary. It exposes neither transport paths
/// nor diagnostics; detailed host output remains an explicit command result.
public struct NativeSettingsStatus: Codable, Equatable, Sendable {
  public let state: String
  public let hasCurrentWorld: Bool
}

public struct NativeSettingsGroup: Codable, Equatable, Sendable {
  public let id: String
  public let label: String
  public let settings: [NativeSettingRow]
}

public struct NativeSettingRow: Codable, Equatable, Sendable {
  public let key: String
  public let label: String
  public let value: String
}

public struct NativeCurrentWorld: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
}

public struct NativeProductCounts: Codable, Equatable, Sendable {
  public let worlds: Int
  public let agents: Int
  public let inventorySources: Int
  public let packages: Int
  public let templates: Int
}

public struct NativeAdapterRow: Codable, Equatable, Sendable {
  public let id: String
  public let label: String
  public let declared: Bool
  public let detected: Bool
}
