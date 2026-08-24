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

public enum DefaultKhorosComponent: String, CaseIterable, Codable, Sendable {
  case athena
  case objectiveBoard = "objective-board"
  case library
  case warehouse
  case marketplace
}

public enum DefaultKhorosLayout {
  public static let athena = Coordinate(x: 0, y: -2)
  public static let objectiveBoard = Coordinate(x: 1, y: -2)
  public static let library = Coordinate(x: -2, y: 2)
  public static let warehouse = Coordinate(x: 2, y: 2)
  public static let marketplace = Coordinate(x: 0, y: 2)
  public static let warehouseDirectory = Coordinate(x: 1, y: 0)
}

public struct WorldTemplateComponentDefinition: Codable, Equatable, Sendable {
  public let key: String
  public let packageID: String
  public let packageVersion: String
  public let packageSource: String
  public let inventoryName: String
  public let coordinate: Coordinate
  public let ownedObjectKeys: [String]
  public let pickupLockReason: String?

  public init(
    key: String,
    packageID: String,
    packageVersion: String,
    packageSource: String,
    inventoryName: String,
    coordinate: Coordinate,
    ownedObjectKeys: [String] = [],
    pickupLockReason: String? = "template_anchor"
  ) throws {
    guard Self.validIdentifier(key), Self.validIdentifier(packageID),
      !packageVersion.isEmpty, packageVersion.count <= 64,
      packageSource.hasPrefix("builtin:"), packageSource.count <= 256,
      !inventoryName.isEmpty, inventoryName.count <= 128,
      !inventoryName.contains(where: \.isNewline),
      ownedObjectKeys.allSatisfy(Self.validIdentifier),
      Set(ownedObjectKeys).count == ownedObjectKeys.count,
      pickupLockReason.map({ Self.validIdentifier($0) }) != false
    else {
      throw MikroKhorosError.runtime(
        "world_template.component_invalid",
        "the world-template component definition is invalid",
        details: ["component": key]
      )
    }
    self.key = key
    self.packageID = packageID
    self.packageVersion = packageVersion
    self.packageSource = packageSource
    self.inventoryName = inventoryName
    self.coordinate = coordinate
    self.ownedObjectKeys = ownedObjectKeys
    self.pickupLockReason = pickupLockReason
  }

  private static func validIdentifier(_ value: String) -> Bool {
    !value.isEmpty && value.count <= 128
      && !value.contains(where: { $0.isWhitespace || $0.isNewline })
  }
}

public struct WorldTemplateDefinition: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schema: Int
  public let id: String
  public let version: String
  public let displayName: String
  public let summary: String
  public let contentHash: String
  public let components: [WorldTemplateComponentDefinition]

  public init(
    schema: Int = Self.currentSchemaVersion,
    id: String,
    version: String,
    displayName: String,
    summary: String,
    components: [WorldTemplateComponentDefinition]
  ) throws {
    guard schema == Self.currentSchemaVersion,
      !id.isEmpty, id.count <= 128,
      !id.contains(where: { $0.isWhitespace || $0.isNewline }),
      !version.isEmpty, version.count <= 64,
      !displayName.isEmpty, displayName.count <= 128,
      !summary.isEmpty, summary.count <= 512,
      !displayName.contains(where: \.isNewline),
      !summary.contains(where: \.isNewline),
      !components.isEmpty,
      Set(components.map(\.key)).count == components.count,
      Set(components.map(\.coordinate)).count == components.count
    else {
      throw MikroKhorosError.runtime(
        "world_template.component_invalid",
        "the world-template definition is invalid",
        details: ["template": id]
      )
    }
    self.schema = schema
    self.id = id
    self.version = version
    self.displayName = displayName
    self.summary = summary
    self.components = components
    let canonical =
      ([id, version, displayName, summary]
      + components.flatMap {
        [
          $0.key, $0.packageID, $0.packageVersion, $0.packageSource,
          $0.inventoryName, $0.coordinate.description,
          $0.ownedObjectKeys.joined(separator: ","), $0.pickupLockReason ?? "",
        ]
      }).joined(separator: "\u{0}")
    contentHash = SHA256Digest.hex(Data(canonical.utf8))
  }

  private enum CodingKeys: String, CodingKey {
    case schema, id, version, displayName, summary, contentHash, components
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedHash = try container.decode(String.self, forKey: .contentHash)
    try self.init(
      schema: container.decode(Int.self, forKey: .schema),
      id: container.decode(String.self, forKey: .id),
      version: container.decode(String.self, forKey: .version),
      displayName: container.decode(String.self, forKey: .displayName),
      summary: container.decode(String.self, forKey: .summary),
      components: container.decode([WorldTemplateComponentDefinition].self, forKey: .components)
    )
    guard decodedHash == contentHash else {
      throw MikroKhorosError.runtime(
        "world_template.component_invalid",
        "the world-template content hash is invalid",
        details: ["template": id]
      )
    }
  }
}

public struct WorldTemplateComponentRecord: Codable, Equatable, Sendable {
  public let componentKey: String
  public let inventoryObjectID: String
  public let inventoryRevision: Int
  public let deploymentID: String
  public let rootObjectID: String
  public let ownedObjectIDs: [String]
  public let requestedCoordinate: Coordinate
  public let actualCoordinate: Coordinate
  public let active: Bool

  public init(
    componentKey: String,
    record: ObjectDeploymentRecord,
    active: Bool = true
  ) {
    self.componentKey = componentKey
    inventoryObjectID = record.snapshot.lineage.inventoryObjectID
    inventoryRevision = record.snapshot.lineage.inventoryRevision
    deploymentID = record.snapshot.lineage.deploymentID
    rootObjectID = record.snapshot.objectID
    ownedObjectIDs = record.snapshot.ownedObjects.map(\.objectID)
    requestedCoordinate = record.requestedCoordinate
    actualCoordinate = record.actualCoordinate
    self.active = active
  }
}

public struct WorldTemplateApplicationRecord: Codable, Equatable, Sendable {
  public let id: String
  public let templateID: String
  public let templateVersion: String
  public let templateContentHash: String
  public let appliedAt: Date
  public let deployments: [ObjectDeploymentRecord]
  public var inactiveRootObjectIDs: Set<String>?

  public init(
    id: String = InventoryIdentity.make(),
    definition: WorldTemplateDefinition,
    deployments: [ObjectDeploymentRecord],
    appliedAt: Date = Date()
  ) {
    self.id = id
    templateID = definition.id
    templateVersion = definition.version
    templateContentHash = definition.contentHash
    self.appliedAt = appliedAt
    self.deployments = deployments
    inactiveRootObjectIDs = nil
  }

  public init(
    id: String,
    templateID: String,
    templateVersion: String,
    templateContentHash: String,
    appliedAt: Date,
    deployments: [ObjectDeploymentRecord],
    inactiveRootObjectIDs: Set<String>? = nil
  ) {
    self.id = id
    self.templateID = templateID
    self.templateVersion = templateVersion
    self.templateContentHash = templateContentHash
    self.appliedAt = appliedAt
    self.deployments = deployments
    self.inactiveRootObjectIDs = inactiveRootObjectIDs
  }

  public var components: [WorldTemplateComponentRecord] {
    var latest: [String: WorldTemplateComponentRecord] = [:]
    var order: [String] = []
    for deployment in deployments {
      guard let lineage = deployment.snapshot.lineage.worldTemplate else { continue }
      if latest[lineage.componentKey] == nil { order.append(lineage.componentKey) }
      latest[lineage.componentKey] = WorldTemplateComponentRecord(
        componentKey: lineage.componentKey,
        record: deployment,
        active: !(inactiveRootObjectIDs ?? []).contains(deployment.snapshot.objectID)
      )
    }
    return order.compactMap { latest[$0] }
  }

  public mutating func markInactive(rootObjectIDs: Set<String>) {
    let known = Set(deployments.map(\.snapshot.objectID))
    let matched = rootObjectIDs.intersection(known)
    guard !matched.isEmpty else { return }
    inactiveRootObjectIDs = (inactiveRootObjectIDs ?? []).union(matched)
  }
}

public struct WorldTemplateRepairRecord: Codable, Equatable, Sendable {
  public let applicationID: String
  public let repairedAt: Date
  public let deployments: [ObjectDeploymentRecord]

  public init(
    applicationID: String,
    deployments: [ObjectDeploymentRecord],
    repairedAt: Date = Date()
  ) {
    self.applicationID = applicationID
    self.repairedAt = repairedAt
    self.deployments = deployments
  }
}

public struct WorldTemplatePlannedComponent: Equatable, Sendable {
  public let definition: WorldTemplateComponentDefinition
  public let inventoryObjectID: String?
  public let existingObjectID: String?
  public let actualCoordinate: Coordinate
  public let collisionObjectID: String?

  public var requiresDeployment: Bool { existingObjectID == nil }
}

public struct WorldTemplatePlan: Equatable, Sendable {
  public let definition: WorldTemplateDefinition
  public let worldID: String
  public let applicationID: String
  public let packagesToInstall: [String]
  public let packagesToReactivate: [String]
  public let foldersToCreate: [String]
  public let sourcesToCreate: [String]
  public let components: [WorldTemplatePlannedComponent]
  public let inventoryFingerprint: String
  public let worldFingerprint: String

  public var confirmationRequired: Bool {
    !packagesToInstall.isEmpty || !packagesToReactivate.isEmpty
      || !foldersToCreate.isEmpty || !sourcesToCreate.isEmpty
  }

  public var collisions: [WorldTemplatePlannedComponent] {
    components.filter {
      $0.collisionObjectID != nil
        && $0.actualCoordinate == $0.definition.coordinate
    }
  }
}

public struct WorldTemplateRuntimeApplyResult: Equatable, Sendable {
  public let application: WorldTemplateApplicationRecord
  public let deployedObjectIDs: [String]
  public let repaired: Bool

  public init(
    application: WorldTemplateApplicationRecord,
    deployedObjectIDs: [String],
    repaired: Bool
  ) {
    self.application = application
    self.deployedObjectIDs = deployedObjectIDs
    self.repaired = repaired
  }
}

public final class WorldTemplateCatalog: @unchecked Sendable {
  public let definitions: [WorldTemplateDefinition]

  public init(definitions: [WorldTemplateDefinition]) throws {
    guard Set(definitions.map(\.id)).count == definitions.count else {
      throw MikroKhorosError.runtime(
        "world_template.component_invalid",
        "the world-template catalog contains duplicate identifiers"
      )
    }
    self.definitions = definitions.sorted { $0.id < $1.id }
  }

  public static func installedCLI() -> WorldTemplateCatalog {
    try! WorldTemplateCatalog(definitions: [.defaultKhoros])
  }

  public func resolve(_ id: String) throws -> WorldTemplateDefinition {
    guard let result = definitions.first(where: { $0.id == id }) else {
      throw MikroKhorosError.runtime(
        "world_template.not_found",
        "the requested world template is not available",
        details: ["template": id],
        suggestions: ["run `khoros world template list`"]
      )
    }
    return result
  }
}

public struct WorldTemplateApplyResult: Equatable, Sendable {
  public let plan: WorldTemplatePlan
  public let installedPackages: [String]
  public let reactivatedPackages: [String]
  public let createdFolders: [String]
  public let createdInventoryObjectIDs: [String]
  public let runtime: WorldTemplateRuntimeApplyResult
}

public final class WorldTemplateService: @unchecked Sendable {
  public let catalog: WorldTemplateCatalog

  public init(catalog: WorldTemplateCatalog = .installedCLI()) {
    self.catalog = catalog
  }

  public func preflight(
    templateID: String,
    inventory: InventoryStore,
    runtime: WorldRuntime,
    autoAdapt: Bool = false
  ) throws -> WorldTemplatePlan {
    let definition = try catalog.resolve(templateID)
    let matchingApplications = runtime.document.templateApplications.filter {
      $0.templateID == definition.id
    }
    guard matchingApplications.count <= 1 else {
      throw MikroKhorosError.runtime(
        "world_template.application_corrupt",
        "the world contains more than one application of this template"
      )
    }
    if let existing = matchingApplications.first {
      guard existing.templateVersion == definition.version,
        existing.templateContentHash == definition.contentHash
      else {
        throw MikroKhorosError.runtime(
          "world_template.application_corrupt",
          "the applied template does not match the installed built-in definition"
        )
      }
    }
    let applicationID = matchingApplications.first?.id ?? InventoryIdentity.make()

    var packagesToInstall: [String] = []
    var packagesToReactivate: [String] = []
    for component in definition.components {
      let retained = inventory.document.packages.first {
        $0.manifest.id == component.packageID
          && $0.manifest.version == component.packageVersion
      }
      if let retained {
        let expected = try FirstPartyPackageCatalog.data(
          named: String(component.packageSource.dropFirst("builtin:".count))
        )
        guard retained.contentHash == SHA256Digest.hex(expected) else {
          throw MikroKhorosError.runtime(
            "world_template.component_invalid",
            "a retained facility package does not match the trusted built-in package",
            details: ["package": component.packageID]
          )
        }
        if !retained.visible { packagesToReactivate.append(component.packageSource) }
      } else {
        packagesToInstall.append(component.packageSource)
      }
    }

    var foldersToCreate: [String] = []
    if (try? inventory.resolveFolder("/Templates")) == nil {
      foldersToCreate.append("/Templates")
      foldersToCreate.append("/Templates/default-khoros")
    } else if (try? inventory.resolveFolder("/Templates/default-khoros")) == nil {
      foldersToCreate.append("/Templates/default-khoros")
    }

    var sourcesByComponent: [String: InventoryObjectRecord] = [:]
    var sourcesToCreate: [String] = []
    for component in definition.components {
      if let source = try inventory.templateSource(
        templateID: definition.id,
        templateVersion: definition.version,
        componentKey: component.key
      ) {
        guard source.packageID == component.packageID,
          source.packageVersion == component.packageVersion
        else {
          throw MikroKhorosError.runtime(
            "world_template.component_invalid",
            "a canonical template source has the wrong package identity",
            details: ["component": component.key]
          )
        }
        let readiness = try inventory.readiness(of: source)
        guard readiness.ready else {
          throw MikroKhorosError.runtime(
            "world_template.source_unready",
            "a canonical template source is not ready to deploy",
            details: [
              "component": component.key,
              "inventory_object": source.id,
            ],
            suggestions: ["inspect and complete the canonical Inventory source"]
          )
        }
        sourcesByComponent[component.key] = source
      } else {
        sourcesToCreate.append(component.inventoryName)
      }
    }

    let rootItems = runtime.harness.world.container?.items ?? []
    var existingByComponent: [String: MikroObject] = [:]
    let recordedByComponent = Dictionary(
      uniqueKeysWithValues: matchingApplications.first?.components.map {
        ($0.componentKey, $0)
      } ?? []
    )
    for recorded in recordedByComponent.values {
      if let object = runtime.harness.findObject(recorded.rootObjectID),
        object.parentSpace !== runtime.harness.world.container
      {
        throw MikroKhorosError.runtime(
          "world_template.component_invalid",
          "a template facility is outside the root world space",
          details: ["component": recorded.componentKey, "object": object.hash]
        )
      }
    }
    for item in rootItems {
      guard let lineage = item.object.lineage?.worldTemplate,
        lineage.templateID == definition.id,
        lineage.templateVersion == definition.version
      else { continue }
      guard lineage.applicationID == applicationID,
        definition.components.contains(where: { $0.key == lineage.componentKey }),
        existingByComponent[lineage.componentKey] == nil
      else {
        throw MikroKhorosError.runtime(
          "world_template.component_invalid",
          "the world contains invalid or duplicate template components"
        )
      }
      existingByComponent[lineage.componentKey] = item.object
    }
    for (componentKey, object) in existingByComponent {
      guard
        let componentDefinition = definition.components.first(where: {
          $0.key == componentKey
        }), let recorded = recordedByComponent[componentKey]
      else {
        throw MikroKhorosError.runtime(
          "world_template.component_invalid",
          "a deployed template component has no application record",
          details: ["component": componentKey]
        )
      }
      let recordedSource = inventory.allInventoryObjects(includeDeleted: true).first {
        guard let source = $0.templateSource else { return false }
        return $0.id == recorded.inventoryObjectID
          && source.templateID == definition.id
          && source.templateVersion == definition.version
          && source.componentKey == componentKey
      }
      guard let recordedSource,
        recorded.rootObjectID == object.hash,
        object.lineage?.packageID == componentDefinition.packageID,
        object.lineage?.packageVersion == componentDefinition.packageVersion,
        object.lineage?.inventoryObjectID == recordedSource.id,
        object.lockInfo?.reason == componentDefinition.pickupLockReason,
        Set(recorded.ownedObjectIDs).count == recorded.ownedObjectIDs.count,
        recorded.ownedObjectIDs.allSatisfy({ childID in
          guard let child = runtime.harness.findObject(childID) else { return false }
          return child.parentSpace === object.container
            && child.lineage == object.lineage
            && child.lockInfo != nil
        })
      else {
        throw MikroKhorosError.runtime(
          "world_template.component_invalid",
          "a deployed template component does not match its application record",
          details: ["component": componentKey]
        )
      }
    }

    var reserved = Set(rootItems.map(\.coordinate))
    var planned: [WorldTemplatePlannedComponent] = []
    for component in definition.components {
      if let existing = existingByComponent[component.key], let coordinate = existing.coordinate {
        planned.append(
          WorldTemplatePlannedComponent(
            definition: component,
            inventoryObjectID: existing.lineage?.inventoryObjectID,
            existingObjectID: existing.hash,
            actualCoordinate: coordinate,
            collisionObjectID: nil
          )
        )
        continue
      }
      let occupant = rootItems.first(where: { $0.coordinate == component.coordinate })?.object.hash
      let actual: Coordinate
      let collision: String?
      if occupant == nil && !reserved.contains(component.coordinate) {
        actual = component.coordinate
        collision = nil
      } else if autoAdapt {
        actual = nearestFreeCoordinate(around: component.coordinate, reserved: reserved)
        collision = occupant ?? "reserved"
      } else {
        actual = component.coordinate
        collision = occupant ?? "reserved"
      }
      reserved.insert(actual)
      planned.append(
        WorldTemplatePlannedComponent(
          definition: component,
          inventoryObjectID: sourcesByComponent[component.key]?.id,
          existingObjectID: nil,
          actualCoordinate: actual,
          collisionObjectID: collision
        )
      )
    }

    return WorldTemplatePlan(
      definition: definition,
      worldID: runtime.harness.world.hash,
      applicationID: applicationID,
      packagesToInstall: packagesToInstall,
      packagesToReactivate: packagesToReactivate,
      foldersToCreate: foldersToCreate,
      sourcesToCreate: sourcesToCreate,
      components: planned,
      inventoryFingerprint: try fingerprint(inventory.document),
      worldFingerprint: try fingerprint(runtime.document)
    )
  }

  @discardableResult
  public func apply(
    _ plan: WorldTemplatePlan,
    inventory: InventoryStore,
    runtime: WorldRuntime,
    autoAdapt: Bool = false
  ) throws -> WorldTemplateApplyResult {
    guard try fingerprint(inventory.document) == plan.inventoryFingerprint,
      try fingerprint(runtime.document) == plan.worldFingerprint
    else {
      throw MikroKhorosError.runtime(
        "world_template.plan_stale",
        "Inventory or world state changed after template preflight",
        suggestions: ["run the command again to compute a current plan"]
      )
    }
    guard plan.collisions.isEmpty else {
      throw MikroKhorosError.runtime(
        "world_template.placement_conflict",
        "one or more template coordinates contain unrelated world content",
        details: [
          "positions": plan.collisions.map { $0.definition.coordinate.description }
            .joined(separator: ",")
        ],
        suggestions: ["move the occupants or apply again with `--auto-adapt`"]
      )
    }

    let priorInventory = inventory.document
    var installed: [String] = []
    var reactivated: [String] = []
    var createdFolders: [String] = []
    var createdSources: [String] = []
    do {
      for source in plan.packagesToInstall {
        _ = try inventory.install(
          data: FirstPartyPackageCatalog.data(
            named: String(source.dropFirst("builtin:".count))
          )
        )
        installed.append(source)
      }
      for source in plan.packagesToReactivate {
        _ = try inventory.install(
          data: FirstPartyPackageCatalog.data(
            named: String(source.dropFirst("builtin:".count))
          )
        )
        reactivated.append(source)
      }
      for path in plan.foldersToCreate {
        _ = try inventory.createFolder(path: path)
        createdFolders.append(path)
      }
      let folder = try inventory.resolveFolder("/Templates/default-khoros")
      for component in plan.definition.components {
        guard
          try inventory.templateSource(
            templateID: plan.definition.id,
            templateVersion: plan.definition.version,
            componentKey: component.key
          ) == nil
        else { continue }
        let source = try inventory.createTemplateSource(
          packageID: component.packageID,
          version: component.packageVersion,
          name: component.inventoryName,
          folderID: folder.id,
          provenance: InventoryTemplateSourceProvenance(
            templateID: plan.definition.id,
            templateVersion: plan.definition.version,
            componentKey: component.key
          )
        )
        createdSources.append(source.id)
      }
      let refreshed = try preflight(
        templateID: plan.definition.id,
        inventory: inventory,
        runtime: runtime,
        autoAdapt: autoAdapt
      )
      let stablePlan = WorldTemplatePlan(
        definition: refreshed.definition,
        worldID: refreshed.worldID,
        applicationID: plan.applicationID,
        packagesToInstall: [],
        packagesToReactivate: [],
        foldersToCreate: [],
        sourcesToCreate: [],
        components: refreshed.components,
        inventoryFingerprint: refreshed.inventoryFingerprint,
        worldFingerprint: refreshed.worldFingerprint
      )
      let runtimeResult = try runtime.applyWorldTemplate(stablePlan)
      return WorldTemplateApplyResult(
        plan: stablePlan,
        installedPackages: installed,
        reactivatedPackages: reactivated,
        createdFolders: createdFolders,
        createdInventoryObjectIDs: createdSources,
        runtime: runtimeResult
      )
    } catch {
      try? inventory.restoreDocument(priorInventory)
      throw error
    }
  }

  private func fingerprint<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return SHA256Digest.hex(try encoder.encode(value))
  }

  private func nearestFreeCoordinate(
    around origin: Coordinate,
    reserved: Set<Coordinate>
  ) -> Coordinate {
    if !reserved.contains(origin) { return origin }
    var distance = 1
    while true {
      for offset in diamondOffsets(distance: distance) {
        let candidate = origin + offset
        if !reserved.contains(candidate) { return candidate }
      }
      distance += 1
    }
  }

  private func diamondOffsets(distance: Int) -> [Coordinate] {
    var result: [Coordinate] = []
    for index in 0..<distance {
      result.append(Coordinate(x: index, y: -distance + index))
    }
    for index in 0..<distance {
      result.append(Coordinate(x: distance - index, y: index))
    }
    for index in 0..<distance {
      result.append(Coordinate(x: -index, y: distance - index))
    }
    for index in 0..<distance {
      result.append(Coordinate(x: -distance + index, y: -index))
    }
    return result
  }
}

extension WorldTemplateDefinition {
  public static var defaultKhoros: WorldTemplateDefinition {
    try! WorldTemplateDefinition(
      id: "default-khoros",
      version: "1.0.0",
      displayName: "Default Khoros",
      summary: "The built-in collaborative facilities for a mikrokhoros world.",
      components: [
        try! WorldTemplateComponentDefinition(
          key: DefaultKhorosComponent.athena.rawValue,
          packageID: FirstPartyPackageID.athena,
          packageVersion: "1.0.0",
          packageSource: "builtin:athena",
          inventoryName: "Athena",
          coordinate: DefaultKhorosLayout.athena
        ),
        try! WorldTemplateComponentDefinition(
          key: DefaultKhorosComponent.objectiveBoard.rawValue,
          packageID: FirstPartyPackageID.objectiveBoard,
          packageVersion: "1.0.0",
          packageSource: "builtin:objective-board",
          inventoryName: "Objective Board",
          coordinate: DefaultKhorosLayout.objectiveBoard,
          ownedObjectKeys: ["index"]
        ),
        try! WorldTemplateComponentDefinition(
          key: DefaultKhorosComponent.library.rawValue,
          packageID: FirstPartyPackageID.library,
          packageVersion: "1.0.0",
          packageSource: "builtin:library",
          inventoryName: "Library",
          coordinate: DefaultKhorosLayout.library,
          ownedObjectKeys: ["catalog"]
        ),
        try! WorldTemplateComponentDefinition(
          key: DefaultKhorosComponent.warehouse.rawValue,
          packageID: FirstPartyPackageID.warehouse,
          packageVersion: "1.0.0",
          packageSource: "builtin:warehouse",
          inventoryName: "Warehouse",
          coordinate: DefaultKhorosLayout.warehouse,
          ownedObjectKeys: ["directory"]
        ),
        try! WorldTemplateComponentDefinition(
          key: DefaultKhorosComponent.marketplace.rawValue,
          packageID: FirstPartyPackageID.marketplace,
          packageVersion: "1.0.0",
          packageSource: "builtin:marketplace",
          inventoryName: "Marketplace",
          coordinate: DefaultKhorosLayout.marketplace,
          ownedObjectKeys: ["merchant"]
        ),
      ]
    )
  }
}
