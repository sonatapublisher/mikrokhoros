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

public enum WorldProjectionState: String, Codable, Equatable, Sendable {
  case available
  case empty
  case unavailable
}

public struct WorldPickerEntry: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let isCurrent: Bool

  public init(id: String, name: String, isCurrent: Bool) {
    self.id = id
    self.name = name
    self.isCurrent = isCurrent
  }
}

public struct WorldContainerSnapshot: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let path: String
  public let parentContainerID: String?

  public init(id: String, name: String, path: String, parentContainerID: String?) {
    self.id = id
    self.name = name
    self.path = path
    self.parentContainerID = parentContainerID
  }
}

public struct WorldCoordinateSnapshot: Codable, Equatable, Sendable {
  public let x: Int
  public let y: Int

  public init(_ coordinate: Coordinate) {
    x = coordinate.x
    y = coordinate.y
  }

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }
}

/// The bounded deterministic visual identity exposed to presentation clients.
/// Shape and color are intentionally independent so neither surface can infer
/// private runtime state or depend on process-specific hashing.
public struct WorldVisualIdentitySnapshot: Codable, Equatable, Sendable {
  public let shapeIndex: Int
  public let colorIndex: Int

  public init(shapeIndex: Int, colorIndex: Int) {
    self.shapeIndex = shapeIndex
    self.colorIndex = colorIndex
  }
}

/// The World page needs only the selected holding's visual identity. It does
/// not receive held-object selectors, names, contents, or management data.
public struct WorldHeldObjectSnapshot: Codable, Equatable, Sendable {
  public let visual: WorldVisualIdentitySnapshot

  public init(visual: WorldVisualIdentitySnapshot) {
    self.visual = visual
  }
}

public struct WorldAgentSnapshot: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let containerID: String
  public let coordinate: WorldCoordinateSnapshot
  public let path: String
  public let visual: WorldVisualIdentitySnapshot
  public let primaryHeldObject: WorldHeldObjectSnapshot?
  public let isFocused: Bool

  public init(
    id: String,
    name: String,
    containerID: String,
    coordinate: WorldCoordinateSnapshot,
    path: String,
    visual: WorldVisualIdentitySnapshot,
    primaryHeldObject: WorldHeldObjectSnapshot? = nil,
    isFocused: Bool
  ) {
    self.id = id
    self.name = name
    self.containerID = containerID
    self.coordinate = coordinate
    self.path = path
    self.visual = visual
    self.primaryHeldObject = primaryHeldObject
    self.isFocused = isFocused
  }
}

public struct WorldObjectSnapshot: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let type: String
  public let summary: String
  /// World-space objects have a coordinate. Agent-held and agent-attached
  /// objects deliberately do not: their exact structural location is exposed
  /// through `path` rather than inventing a world coordinate.
  public let coordinate: WorldCoordinateSnapshot?
  public let hasContainer: Bool
  /// Whether the exact object can be moved through the world-object move
  /// operation from its current structural location.
  public let canMove: Bool
  public let path: String
  public let visual: WorldVisualIdentitySnapshot

  public init(
    id: String,
    name: String,
    type: String,
    summary: String,
    coordinate: WorldCoordinateSnapshot?,
    hasContainer: Bool,
    canMove: Bool,
    path: String,
    visual: WorldVisualIdentitySnapshot
  ) {
    self.id = id
    self.name = name
    self.type = type
    self.summary = summary
    self.coordinate = coordinate
    self.hasContainer = hasContainer
    self.canMove = canMove
    self.path = path
    self.visual = visual
  }
}

public struct WorldReportSnapshot: Codable, Equatable, Sendable {
  public let id: String
  public let timestamp: Date
  public let worldID: String
  public let objectID: String
  public let inventoryObjectID: String
  public let inventoryRevision: Int
  public let packageID: String
  public let packageVersion: String
  public let type: String
  public let title: String
  public let body: String
  public let payload: JSONValue

  public init(_ report: ObjectReport) {
    id = report.id
    timestamp = report.timestamp
    worldID = report.worldID
    objectID = report.objectID
    inventoryObjectID = report.inventoryObjectID
    inventoryRevision = report.inventoryRevision
    packageID = report.packageID
    packageVersion = report.packageVersion
    type = report.type
    title = report.title
    body = report.body
    payload = report.payload
  }
}

/// The bounded, read-only world projection returned to the browser.
public struct WorldPageSnapshot: Codable, Equatable, Sendable {
  public let state: WorldProjectionState
  public let message: String?
  public let worlds: [WorldPickerEntry]
  public let currentWorldID: String?
  public let selectedWorldID: String?
  public let worldName: String?
  public let container: WorldContainerSnapshot?
  public let focusedAgentID: String?
  public let primaryAgents: [WorldAgentSnapshot]
  public let otherAgents: [WorldAgentSnapshot]
  public let objects: [WorldObjectSnapshot]
  public let reports: [WorldReportSnapshot]
  public let inventoryObjectCount: Int

  public init(
    state: WorldProjectionState,
    message: String? = nil,
    worlds: [WorldPickerEntry] = [],
    currentWorldID: String? = nil,
    selectedWorldID: String? = nil,
    worldName: String? = nil,
    container: WorldContainerSnapshot? = nil,
    focusedAgentID: String? = nil,
    primaryAgents: [WorldAgentSnapshot] = [],
    otherAgents: [WorldAgentSnapshot] = [],
    objects: [WorldObjectSnapshot] = [],
    reports: [WorldReportSnapshot] = [],
    inventoryObjectCount: Int = 0
  ) {
    self.state = state
    self.message = message
    self.worlds = worlds
    self.currentWorldID = currentWorldID
    self.selectedWorldID = selectedWorldID
    self.worldName = worldName
    self.container = container
    self.focusedAgentID = focusedAgentID
    self.primaryAgents = primaryAgents
    self.otherAgents = otherAgents
    self.objects = objects
    self.reports = reports
    self.inventoryObjectCount = inventoryObjectCount
  }

  public static let emptyMessage = "No world is selected."
  public static let unavailableMessage = "World data is unavailable."
}

public struct WorldObjectPageSnapshot: Codable, Equatable, Sendable {
  public let state: WorldProjectionState
  public let message: String?
  public let worldID: String?
  public let object: WorldObjectSnapshot?
  public let `interface`: JSONValue?

  public init(
    state: WorldProjectionState,
    message: String? = nil,
    worldID: String? = nil,
    object: WorldObjectSnapshot? = nil,
    interface: JSONValue? = nil
  ) {
    self.state = state
    self.message = message
    self.worldID = worldID
    self.object = object
    self.interface = interface
  }
}

public enum WorldProjectionError: Error, Equatable, Sendable {
  case invalidSelector
  case invalidVisualIdentity
  case unavailable
}

/// A pure projection service. It creates a fresh runtime from persisted data
/// for each call and never persists, synchronizes, bootstraps, or accesses
/// credential and treasury material.
public final class WorldProjectionService: @unchecked Sendable {
  /// The World page reads persisted collections whose storage limits remain
  /// configurable. Presentation projections therefore carry independent,
  /// deterministic entry ceilings.
  static let maximumWorldPickerEntries = 128
  static let maximumOtherAgentEntries = 128
  static let maximumObjectEntries = 256

  /// The World response carries retained, package-originated reports. Keep
  /// their aggregate encoded size finite independently of the stored report
  /// and World-document limits.
  static let maximumProjectedReportBytes = 256 * 1024

  public let layout: ProductLayout
  public let defaultWorldSelector: String?
  private let reportLimit: Int

  public init(
    layout: ProductLayout,
    defaultWorldSelector: String? = nil,
    reportLimit: Int = 32
  ) {
    self.layout = layout
    self.defaultWorldSelector = defaultWorldSelector
    self.reportLimit = max(1, min(reportLimit, 128))
  }

  /// Resolves the optional selector using the human catalog rules. The web
  /// transport calls ``snapshotExact`` so query selectors remain exact IDs.
  public func snapshot(
    world: String? = nil,
    container: String? = nil,
    focus: String? = nil
  ) throws -> WorldPageSnapshot {
    try snapshot(
      world: world ?? defaultWorldSelector,
      container: container,
      focus: focus,
      requireExactWorld: false
    )
  }

  public func snapshotExact(
    world: String? = nil,
    container: String? = nil,
    focus: String? = nil
  ) throws -> WorldPageSnapshot {
    try snapshot(
      world: world,
      container: container,
      focus: focus,
      requireExactWorld: true
    )
  }

  public func objectSnapshot(
    world exactWorldID: String,
    object exactObjectID: String
  ) throws -> WorldObjectPageSnapshot {
    guard InventoryIdentity.isValid(exactWorldID), InventoryIdentity.isValid(exactObjectID)
    else { throw WorldProjectionError.invalidSelector }
    do {
      return try withLockedProductState { configuration, catalog, inventory in
        guard let record = catalog.document.worlds.first(where: { $0.id == exactWorldID }) else {
          throw WorldProjectionError.invalidSelector
        }
        let worldURL = try layout.worldURL(for: record.id)
        let document = try WorldStore.load(
          from: worldURL,
          maximumBytes: configuration.runtime.maximumWorldBytes
        )
        guard document.worldID == exactWorldID, document.credit != nil else {
          throw WorldProjectionError.unavailable
        }
        let runtime = try WorldRuntime(
          document: document,
          configuration: configuration,
          inventory: inventory,
          treasuryAuthority: nil
        )
        guard let object = runtime.harness.findObject(exactObjectID),
          object !== runtime.harness.world
        else { throw WorldProjectionError.invalidSelector }
        let locations = try makeObjectLocationIndex(runtime: runtime)
        guard let location = locations.location(for: object) else {
          throw WorldProjectionError.invalidSelector
        }
        let objectDTO = try makeObjectPageSnapshot(
          object,
          location: location,
          runtime: runtime
        )
        return WorldObjectPageSnapshot(
          state: .available,
          worldID: exactWorldID,
          object: objectDTO,
          interface: try makeObjectManagementInterface(
            object,
            location: location,
            runtime: runtime
          )
        )
      }
    } catch WorldProjectionError.invalidSelector {
      throw WorldProjectionError.invalidSelector
    } catch {
      return WorldObjectPageSnapshot(
        state: .unavailable,
        message: WorldPageSnapshot.unavailableMessage,
        worldID: exactWorldID
      )
    }
  }

  public func projectWorld(
    world: String? = nil,
    container: String? = nil,
    focus: String? = nil
  ) throws -> WorldPageSnapshot {
    try snapshot(world: world, container: container, focus: focus)
  }

  public func projectObject(world: String, object: String) throws -> WorldObjectPageSnapshot {
    try objectSnapshot(world: world, object: object)
  }

  private func snapshot(
    world worldSelector: String?,
    container containerID: String?,
    focus focusID: String?,
    requireExactWorld: Bool
  ) throws -> WorldPageSnapshot {
    do {
      return try withLockedProductState { configuration, catalog, inventory in
        let worlds = Self.boundedWorldPickerEntries(
          catalog.allWorlds().map {
            WorldPickerEntry(
              id: $0.id,
              name: $0.name,
              isCurrent: catalog.document.currentWorldID == $0.id
            )
          }
        )
        guard !catalog.document.worlds.isEmpty else {
          return WorldPageSnapshot(
            state: .empty,
            message: WorldPageSnapshot.emptyMessage,
            worlds: worlds,
            currentWorldID: catalog.document.currentWorldID,
            inventoryObjectCount: inventory.allInventoryObjects().count
          )
        }

        let record: WorldCatalogRecord
        if let selector = worldSelector {
          guard !requireExactWorld || InventoryIdentity.isValid(selector) else {
            throw WorldProjectionError.invalidSelector
          }
          if requireExactWorld {
            guard let exact = catalog.document.worlds.first(where: { $0.id == selector }) else {
              throw WorldProjectionError.invalidSelector
            }
            record = exact
          } else {
            record = try catalog.resolve(selector)
          }
        } else {
          let selectedByDefault: WorldCatalogRecord?
          if requireExactWorld, let defaultWorldSelector {
            selectedByDefault = try catalog.resolve(defaultWorldSelector)
          } else {
            selectedByDefault = catalog.currentWorld
          }
          guard let current = selectedByDefault else {
            return WorldPageSnapshot(
              state: .empty,
              message: WorldPageSnapshot.emptyMessage,
              worlds: worlds,
              currentWorldID: catalog.document.currentWorldID,
              inventoryObjectCount: inventory.allInventoryObjects().count
            )
          }
          record = current
        }

        do {
          let worldURL = try layout.worldURL(for: record.id)
          let document = try WorldStore.load(
            from: worldURL,
            maximumBytes: configuration.runtime.maximumWorldBytes
          )
          guard document.worldID == record.id, document.credit != nil else {
            throw WorldProjectionError.unavailable
          }
          let runtime = try WorldRuntime(
            document: document,
            configuration: configuration,
            inventory: inventory,
            treasuryAuthority: nil
          )
          return try makeWorldSnapshot(
            runtime: runtime,
            worlds: worlds,
            currentWorldID: catalog.document.currentWorldID,
            selectedWorldID: record.id,
            containerID: containerID,
            focusID: focusID,
            inventoryObjectCount: inventory.allInventoryObjects().count
          )
        } catch WorldProjectionError.invalidSelector {
          throw WorldProjectionError.invalidSelector
        } catch {
          return WorldPageSnapshot(
            state: .unavailable,
            message: WorldPageSnapshot.unavailableMessage,
            worlds: worlds,
            currentWorldID: catalog.document.currentWorldID,
            selectedWorldID: record.id,
            worldName: record.name,
            inventoryObjectCount: inventory.allInventoryObjects().count
          )
        }
      }
    } catch WorldProjectionError.invalidSelector {
      throw WorldProjectionError.invalidSelector
    } catch {
      return WorldPageSnapshot(
        state: .unavailable,
        message: WorldPageSnapshot.unavailableMessage
      )
    }
  }

  private func withLockedProductState<Value>(
    _ body: (
      RuntimeConfiguration,
      WorldCatalogStore,
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
    let inventory = try InventoryStore(
      url: layout.inventoryURL,
      packageDirectory: layout.packagesDirectoryURL,
      limits: configuration.runtime,
      runtimeRegistry: .installedCLI()
    )
    return try body(configuration, catalog, inventory)
  }

  private func makeWorldSnapshot(
    runtime: WorldRuntime,
    worlds: [WorldPickerEntry],
    currentWorldID: String?,
    selectedWorldID: String,
    containerID requestedContainerID: String?,
    focusID requestedFocusID: String?,
    inventoryObjectCount: Int
  ) throws -> WorldPageSnapshot {
    let activeAgents = runtime.harness.activeAgents
    let activeByID = Dictionary(uniqueKeysWithValues: activeAgents.map { ($0.hash, $0) })
    var focusedAgent: Agent?
    var selectedContainer: MikroObject?

    if let requestedFocusID {
      guard InventoryIdentity.isValid(requestedFocusID) else {
        throw WorldProjectionError.invalidSelector
      }
      if let agent = activeByID[requestedFocusID] {
        focusedAgent = agent
        selectedContainer = agent.space.owner
      } else if let object = runtime.harness.findObject(requestedFocusID), object.container != nil {
        focusedAgent = nil
        selectedContainer = object
      } else {
        throw WorldProjectionError.invalidSelector
      }
    } else if let requestedContainerID {
      guard InventoryIdentity.isValid(requestedContainerID),
        let object = runtime.harness.findObject(requestedContainerID), object.container != nil
      else { throw WorldProjectionError.invalidSelector }
      focusedAgent = nil
      selectedContainer = object
    } else {
      focusedAgent = nil
      selectedContainer = runtime.harness.world
    }

    guard let selectedContainer, let selectedSpace = selectedContainer.container else {
      throw WorldProjectionError.unavailable
    }
    let selectedContainerDTO = WorldContainerSnapshot(
      id: selectedContainer.hash,
      name: selectedContainer.name,
      path: objectPath(selectedContainer, runtime: runtime),
      parentContainerID: selectedContainer.parentSpace?.owner.hash
    )

    let primary: [Agent]
    if let focusedAgent {
      let nearby =
        activeAgents
        .filter { $0.hash != focusedAgent.hash && $0.space === selectedSpace }
        .sorted {
          let leftDistance = $0.coordinate.manhattanDistance(to: focusedAgent.coordinate)
          let rightDistance = $1.coordinate.manhattanDistance(to: focusedAgent.coordinate)
          return leftDistance == rightDistance ? $0.hash < $1.hash : leftDistance < rightDistance
        }
      primary = [focusedAgent] + Array(nearby.prefix(2))
    } else {
      primary =
        activeAgents
        .filter { $0.space === selectedSpace }
        .sorted {
          let leftDistance = $0.coordinate.manhattanDistance(to: .origin)
          let rightDistance = $1.coordinate.manhattanDistance(to: .origin)
          return leftDistance == rightDistance ? $0.hash < $1.hash : leftDistance < rightDistance
        }
        .prefix(3)
        .map { $0 }
    }
    let primaryIDs = Set(primary.map(\.hash))
    let primaryDTO = try primary.map {
      try makeAgentSnapshot($0, focused: $0.hash == focusedAgent?.hash, runtime: runtime)
    }
    let otherDTO =
      try activeAgents
      .filter { !primaryIDs.contains($0.hash) }
      .sorted { $0.hash < $1.hash }
      .map { try makeAgentSnapshot($0, focused: false, runtime: runtime) }
    let objectDTO = try selectedSpace.items.map {
      try makeObjectSnapshot(
        $0.object,
        parent: selectedSpace,
        coordinate: $0.coordinate,
        runtime: runtime
      )
    }
    let reports = try Self.boundedReports(runtime.reports, limit: reportLimit)
    return WorldPageSnapshot(
      state: .available,
      worlds: worlds,
      currentWorldID: currentWorldID,
      selectedWorldID: selectedWorldID,
      worldName: runtime.document.worldName,
      container: selectedContainerDTO,
      focusedAgentID: focusedAgent?.hash,
      primaryAgents: primaryDTO,
      otherAgents: Self.boundedOtherAgentEntries(otherDTO),
      objects: Self.boundedObjectEntries(objectDTO),
      reports: reports,
      inventoryObjectCount: inventoryObjectCount
    )
  }

  /// Projects the newest report prefix that fits within a single bounded
  /// browser response segment. The result remains newest-first; an oversized
  /// report ends the prefix rather than allowing a retained payload to exceed
  /// the transport budget.
  static func boundedReports(
    _ reports: [ObjectReport],
    limit: Int,
    maximumBytes: Int = maximumProjectedReportBytes
  ) throws -> [WorldReportSnapshot] {
    guard limit > 0, maximumBytes > 0 else { return [] }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    var projected: [WorldReportSnapshot] = []
    var usedBytes = 2  // The enclosing JSON array delimiters.
    let candidates =
      reports
      .sorted {
        if $0.timestamp == $1.timestamp { return $0.id > $1.id }
        return $0.timestamp > $1.timestamp
      }
      .prefix(limit)
    for report in candidates {
      let snapshot = WorldReportSnapshot(report)
      let encodedBytes = try encoder.encode(snapshot).count
      let separatorBytes = projected.isEmpty ? 0 : 1
      guard encodedBytes <= maximumBytes - usedBytes - separatorBytes else { break }
      projected.append(snapshot)
      usedBytes += encodedBytes + separatorBytes
    }
    return projected
  }

  static func boundedWorldPickerEntries(
    _ entries: [WorldPickerEntry]
  ) -> [WorldPickerEntry] {
    Array(entries.prefix(maximumWorldPickerEntries))
  }

  static func boundedOtherAgentEntries(
    _ entries: [WorldAgentSnapshot]
  ) -> [WorldAgentSnapshot] {
    Array(entries.prefix(maximumOtherAgentEntries))
  }

  static func boundedObjectEntries(
    _ entries: [WorldObjectSnapshot]
  ) -> [WorldObjectSnapshot] {
    Array(entries.prefix(maximumObjectEntries))
  }

  private func makeAgentSnapshot(
    _ agent: Agent,
    focused: Bool,
    runtime: WorldRuntime
  ) throws -> WorldAgentSnapshot {
    let primaryHeldObject = try agent.primaryHeldObject.map {
      WorldHeldObjectSnapshot(visual: try StableVisualIdentity.snapshot(for: $0.hash))
    }
    return WorldAgentSnapshot(
      id: agent.hash,
      name: agent.name,
      containerID: agent.space.owner.hash,
      coordinate: WorldCoordinateSnapshot(agent.coordinate),
      path: runtime.harness.agentPath(agent),
      visual: try StableVisualIdentity.snapshot(for: agent.hash),
      primaryHeldObject: primaryHeldObject,
      isFocused: focused
    )
  }

  private func makeObjectSnapshot(
    _ object: MikroObject,
    parent: Space,
    coordinate: Coordinate,
    runtime: WorldRuntime
  ) throws -> WorldObjectSnapshot {
    WorldObjectSnapshot(
      id: object.hash,
      name: object.name,
      type: object.typeName,
      summary: object.summary,
      coordinate: WorldCoordinateSnapshot(coordinate),
      hasContainer: object.container != nil,
      canMove: !(object is AnchoredWorldObject),
      path: objectPath(object, parent: parent, coordinate: coordinate, runtime: runtime),
      visual: try StableVisualIdentity.snapshot(for: object.hash)
    )
  }

  /// The object endpoint can resolve every exact registered object in the
  /// selected world. Unlike the map projection, an object carried by an agent
  /// or attached to an agent is not assigned a fabricated world coordinate.
  private func makeObjectPageSnapshot(
    _ object: MikroObject,
    location: AgentLocationRecord,
    runtime: WorldRuntime
  ) throws -> WorldObjectSnapshot {
    let coordinate = object.coordinate.map(WorldCoordinateSnapshot.init)
    let path: String
    if location.owner != nil {
      // Agent-owned subtrees retain their complete canonical location even
      // when an attached container gives a nested object a local coordinate.
      // The generic Harness path loses that agent ownership root.
      path = location.locationPath.description
    } else if let parent = object.parentSpace, let objectCoordinate = object.coordinate {
      path = objectPath(object, parent: parent, coordinate: objectCoordinate, runtime: runtime)
    } else {
      path = location.locationPath.description
    }
    return WorldObjectSnapshot(
      id: object.hash,
      name: object.name,
      type: object.typeName,
      summary: object.summary,
      coordinate: coordinate,
      hasContainer: object.container != nil,
      canMove: canMove(object, location: location),
      path: path,
      visual: try StableVisualIdentity.snapshot(for: object.hash)
    )
  }

  private func makeObjectLocationIndex(runtime: WorldRuntime) throws -> ObjectLocationIndex {
    let (maximumDepth, overflow) = runtime.harness.limits.maximumObjectInvocationDepth
      .multipliedReportingOverflow(by: 64)
    guard !overflow else {
      throw WorldProjectionError.unavailable
    }
    return try ObjectLocationIndex(
      world: runtime.harness.world,
      registeredObjects: runtime.harness.objects,
      agents: runtime.harness.agents,
      maxDepth: maximumDepth
    )
  }

  private func canMove(_ object: MikroObject, location: AgentLocationRecord) -> Bool {
    guard !(object is AnchoredWorldObject) else { return false }
    if object.parentSpace != nil && object.coordinate != nil { return true }
    return location.owner?.holding != nil
  }

  /// Adapts the world runtime's object interface into the same bounded,
  /// presentation-safe contract used by the native Inventory projection.
  /// The runtime's raw interface is an internal product representation and
  /// includes fields such as declarative action implementation metadata which
  /// are not part of the web contract.
  private func makeObjectManagementInterface(
    _ object: MikroObject,
    location: AgentLocationRecord,
    runtime: WorldRuntime
  ) throws -> JSONValue {
    let raw = try runtime.worldManagementInterface(for: object.hash)
    guard case .object(let wrapper) = raw,
      let declared = wrapper["object"]
    else { throw WorldProjectionError.unavailable }
    let managementData = try JSONEncoder().encode(declared)
    let management = try JSONDecoder().decode(ObjectManagementInterface.self, from: managementData)
    let contract = WebProjectionService(layout: layout).managementContract(
      for: management
    )
    let contractData = try JSONEncoder().encode(contract)
    let contractJSON = try JSONDecoder().decode(JSONValue.self, from: contractData)
    return .object([
      "base": makeSafeObjectBaseInterface(object, location: location),
      "object": contractJSON,
    ])
  }

  /// A bounded subset of object identity and structural location for the
  /// browser. It intentionally excludes runtime state, public-data blobs,
  /// source configuration, credentials, and unbounded function metadata.
  private func makeSafeObjectBaseInterface(
    _ object: MikroObject,
    location: AgentLocationRecord
  ) -> JSONValue {
    let capabilities = object.capturedCapabilities
      .map(\.rawValue)
      .sorted()
      .prefix(32)
      .map(JSONValue.string)
    let functions = object.inspect().functions
      .prefix(64)
      .map {
        JSONValue.object([
          "name": .string(String($0.name.prefix(128))),
          "audience": .string($0.audience.rawValue),
        ])
      }
    let lineage: JSONValue
    if let objectLineage = object.lineage {
      lineage = .object([
        "package_id": .string(String(objectLineage.packageID.prefix(256))),
        "package_version": .string(String(objectLineage.packageVersion.prefix(128))),
        "inventory_object_id": .string(objectLineage.inventoryObjectID),
        "inventory_revision": .number(Double(objectLineage.inventoryRevision)),
        "deployment_id": .string(objectLineage.deploymentID),
      ])
    } else {
      lineage = .null
    }
    return .object([
      "identity": .object([
        "object_id": .string(object.hash),
        "type": .string(String(object.typeName.prefix(256))),
        "name": .string(String(object.name.prefix(256))),
        "instance_revision": .number(Double(object.instanceRevision)),
      ]),
      "location": .object([
        "container_id": object.parentSpace.map { .string($0.owner.hash) } ?? .null,
        "coordinate": object.coordinate.map { .string($0.description) } ?? .null,
        "structural_path": .string(location.locationPath.description),
        "anchored": .bool(object is AnchoredWorldObject),
      ]),
      "lineage": lineage,
      "capabilities": .array(Array(capabilities)),
      "functions": .array(functions),
    ])
  }

  private func objectPath(_ object: MikroObject, runtime: WorldRuntime) -> String {
    guard let parent = object.parentSpace, let coordinate = object.coordinate else {
      return object === runtime.harness.world ? "world" : object.hash
    }
    return objectPath(object, parent: parent, coordinate: coordinate, runtime: runtime)
  }

  private func objectPath(
    _ object: MikroObject,
    parent: Space,
    coordinate: Coordinate,
    runtime: WorldRuntime
  ) -> String {
    let parentPath = runtime.harness.spacePath(parent)
    return "\(parentPath)/\(coordinate)"
  }
}

public enum StableVisualIdentity {
  public static func snapshot(for exactHexID: String) throws -> WorldVisualIdentitySnapshot {
    guard InventoryIdentity.isValid(exactHexID), exactHexID.count == 32 else {
      throw WorldProjectionError.invalidVisualIdentity
    }
    let firstEnd = exactHexID.index(exactHexID.startIndex, offsetBy: 2)
    let secondEnd = exactHexID.index(firstEnd, offsetBy: 2)
    guard let firstByte = UInt8(String(exactHexID[..<firstEnd]), radix: 16),
      let secondByte = UInt8(String(exactHexID[firstEnd..<secondEnd]), radix: 16)
    else { throw WorldProjectionError.invalidVisualIdentity }
    return WorldVisualIdentitySnapshot(
      shapeIndex: Int(firstByte) / 32,
      colorIndex: Int(secondByte) % 12
    )
  }
}
