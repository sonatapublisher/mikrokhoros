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

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if os(Windows)
  import WinSDK
#endif

#if os(Linux)
  import Glibc
#elseif canImport(Darwin)
  import Darwin
#endif

public struct InstalledObjectPackage: Codable, Equatable, Sendable {
  public let manifest: ObjectPackageManifest
  public let contentHash: String
  public var visible: Bool
  public let installedAt: Date

  public init(
    manifest: ObjectPackageManifest,
    contentHash: String,
    visible: Bool = true,
    installedAt: Date = Date()
  ) {
    self.manifest = manifest
    self.contentHash = contentHash
    self.visible = visible
    self.installedAt = installedAt
  }
}

public enum InventoryFolderIdentity {
  public static let rootID = String(repeating: "0", count: 32)
}

public struct InventoryFolderRecord: Codable, Equatable, Sendable {
  public let id: String
  public var name: String
  public var parentID: String?
  public let createdAt: Date
  public var updatedAt: Date

  public init(
    id: String = InventoryIdentity.make(),
    name: String,
    parentID: String?,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.parentID = parentID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public static func root(createdAt: Date = Date()) -> InventoryFolderRecord {
    InventoryFolderRecord(
      id: InventoryFolderIdentity.rootID,
      name: "Inventory",
      parentID: nil,
      createdAt: createdAt,
      updatedAt: createdAt
    )
  }
}

public struct InventoryForkProvenance: Codable, Equatable, Sendable {
  public let parentInventoryObjectID: String
  public let parentRevision: Int
  public let forkedAt: Date

  public init(parentInventoryObjectID: String, parentRevision: Int, forkedAt: Date = Date()) {
    self.parentInventoryObjectID = parentInventoryObjectID
    self.parentRevision = parentRevision
    self.forkedAt = forkedAt
  }
}

public struct InventoryWorldBinding: Codable, Equatable, Sendable {
  public let worldID: String

  public init(worldID: String) {
    self.worldID = worldID
  }
}

public struct InventoryTemplateSourceProvenance: Codable, Equatable, Sendable {
  public let templateID: String
  public let templateVersion: String
  public let componentKey: String
  public let createdAt: Date

  public init(
    templateID: String,
    templateVersion: String,
    componentKey: String,
    createdAt: Date = Date()
  ) {
    self.templateID = templateID
    self.templateVersion = templateVersion
    self.componentKey = componentKey
    self.createdAt = createdAt
  }
}

public struct InventoryObjectRecord: Codable, Equatable, Sendable {
  public let id: String
  public var name: String
  public let packageID: String
  public let packageVersion: String
  public let packageHash: String
  public var revision: Int
  public var configuration: [String: JSONValue]
  public var credentialHandles: [String: String]
  public let requestedCapabilities: Set<ObjectCapability>
  public var grantedCapabilities: Set<ObjectCapability>
  public var managementState: [String: JSONValue]
  public var folderID: String
  public let forkProvenance: InventoryForkProvenance?
  public let worldBinding: InventoryWorldBinding?
  public let templateSource: InventoryTemplateSourceProvenance?
  public let createdAt: Date
  public var updatedAt: Date
  public var deleted: Bool

  public init(
    id: String = InventoryIdentity.make(),
    name: String,
    packageID: String,
    packageVersion: String,
    packageHash: String,
    revision: Int = 1,
    configuration: [String: JSONValue] = [:],
    credentialHandles: [String: String] = [:],
    requestedCapabilities: Set<ObjectCapability> = [],
    grantedCapabilities: Set<ObjectCapability> = [],
    managementState: [String: JSONValue] = [:],
    folderID: String = InventoryFolderIdentity.rootID,
    forkProvenance: InventoryForkProvenance? = nil,
    worldBinding: InventoryWorldBinding? = nil,
    templateSource: InventoryTemplateSourceProvenance? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    deleted: Bool = false
  ) {
    self.id = id
    self.name = name
    self.packageID = packageID
    self.packageVersion = packageVersion
    self.packageHash = packageHash
    self.revision = revision
    self.configuration = configuration
    self.credentialHandles = credentialHandles
    self.requestedCapabilities = requestedCapabilities
    self.grantedCapabilities = grantedCapabilities
    self.managementState = managementState
    self.folderID = folderID
    self.forkProvenance = forkProvenance
    self.worldBinding = worldBinding
    self.templateSource = templateSource
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.deleted = deleted
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, packageID, packageVersion, packageHash, revision, configuration
    case credentialHandles, requestedCapabilities, grantedCapabilities, managementState
    case folderID, forkProvenance, worldBinding, templateSource, createdAt, updatedAt, deleted
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(String.self, forKey: .id),
      name: try container.decode(String.self, forKey: .name),
      packageID: try container.decode(String.self, forKey: .packageID),
      packageVersion: try container.decode(String.self, forKey: .packageVersion),
      packageHash: try container.decode(String.self, forKey: .packageHash),
      revision: try container.decode(Int.self, forKey: .revision),
      configuration: try container.decode([String: JSONValue].self, forKey: .configuration),
      credentialHandles: try container.decode([String: String].self, forKey: .credentialHandles),
      requestedCapabilities: try container.decode(
        Set<ObjectCapability>.self, forKey: .requestedCapabilities),
      grantedCapabilities: try container.decode(
        Set<ObjectCapability>.self, forKey: .grantedCapabilities),
      managementState: try container.decode([String: JSONValue].self, forKey: .managementState),
      folderID: try container.decodeIfPresent(String.self, forKey: .folderID)
        ?? InventoryFolderIdentity.rootID,
      forkProvenance: try container.decodeIfPresent(
        InventoryForkProvenance.self, forKey: .forkProvenance),
      worldBinding: try container.decodeIfPresent(
        InventoryWorldBinding.self, forKey: .worldBinding),
      templateSource: try container.decodeIfPresent(
        InventoryTemplateSourceProvenance.self, forKey: .templateSource),
      createdAt: try container.decode(Date.self, forKey: .createdAt),
      updatedAt: try container.decode(Date.self, forKey: .updatedAt),
      deleted: try container.decode(Bool.self, forKey: .deleted)
    )
  }
}

public struct InventoryDocument: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 4

  public var schemaVersion: Int
  public var packages: [InstalledObjectPackage]
  public var folders: [InventoryFolderRecord]
  public var objects: [InventoryObjectRecord]
  public var worldReferences: [String: WorldArtifactReferences]

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, packages, folders, objects, worldReferences
  }

  private enum RetiredCodingKeys: String, CodingKey {
    case workspaceReferences
  }

  public init(
    schemaVersion: Int = Self.currentSchemaVersion,
    packages: [InstalledObjectPackage] = [],
    folders: [InventoryFolderRecord] = [.root()],
    objects: [InventoryObjectRecord] = [],
    worldReferences: [String: WorldArtifactReferences] = [:]
  ) {
    self.schemaVersion = schemaVersion
    self.packages = packages
    self.folders = folders
    self.objects = objects
    self.worldReferences = worldReferences
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let storedVersion = try container.decode(Int.self, forKey: .schemaVersion)
    guard (1...Self.currentSchemaVersion).contains(storedVersion) else {
      throw MikroKhorosError.persistence("unsupported Inventory schema version")
    }
    let retiredContainer = try decoder.container(keyedBy: RetiredCodingKeys.self)
    guard !retiredContainer.contains(.workspaceReferences) else {
      throw MikroKhorosError.persistence(
        "Inventory document contains retired workspace references"
      )
    }
    let worldReferences =
      try container.decodeIfPresent(
        [String: WorldArtifactReferences].self,
        forKey: .worldReferences
      ) ?? [:]
    try Self.validateWorldReferenceIdentities(worldReferences)
    self.init(
      schemaVersion: Self.currentSchemaVersion,
      packages: try container.decode([InstalledObjectPackage].self, forKey: .packages),
      folders: try container.decodeIfPresent([InventoryFolderRecord].self, forKey: .folders)
        ?? [.root()],
      objects: try container.decode([InventoryObjectRecord].self, forKey: .objects),
      worldReferences: worldReferences
    )
  }

  fileprivate static func validateWorldReferenceIdentities(
    _ worldReferences: [String: WorldArtifactReferences]
  ) throws {
    guard worldReferences.keys.allSatisfy(InventoryIdentity.isValid) else {
      throw MikroKhorosError.persistence("Inventory contains invalid world references")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(packages, forKey: .packages)
    try container.encode(folders, forKey: .folders)
    try container.encode(objects, forKey: .objects)
    try container.encode(worldReferences, forKey: .worldReferences)
  }
}

public struct WorldArtifactReferences: Codable, Equatable, Sendable {
  public let credentialHandles: Set<String>
  public let packageHashes: Set<String>

  public init(credentialHandles: Set<String>, packageHashes: Set<String>) {
    self.credentialHandles = credentialHandles
    self.packageHashes = packageHashes
  }

  public static let empty = WorldArtifactReferences(
    credentialHandles: [],
    packageHashes: []
  )

  public func union(_ other: WorldArtifactReferences) -> WorldArtifactReferences {
    WorldArtifactReferences(
      credentialHandles: credentialHandles.union(other.credentialHandles),
      packageHashes: packageHashes.union(other.packageHashes)
    )
  }
}

public struct InventoryReadiness: Equatable, Sendable {
  public let ready: Bool
  public let missingConfiguration: [String]
  public let missingCredentials: [String]
  public let missingCapabilities: [ObjectCapability]

  public init(
    missingConfiguration: [String],
    missingCredentials: [String],
    missingCapabilities: [ObjectCapability]
  ) {
    self.missingConfiguration = missingConfiguration.sorted()
    self.missingCredentials = missingCredentials.sorted()
    self.missingCapabilities = missingCapabilities.sorted { $0.rawValue < $1.rawValue }
    ready =
      self.missingConfiguration.isEmpty && self.missingCredentials.isEmpty
      && self.missingCapabilities.isEmpty
  }
}

public struct PackageInstallationResult: Equatable, Sendable {
  public let package: InstalledObjectPackage
  public let inventoryObject: InventoryObjectRecord?
}

public struct ObjectDeploymentSnapshot: Codable, Equatable, Sendable {
  public let manifest: ObjectPackageManifest
  public let runtimeAdapterID: String
  public let runtimeAdapterVersion: String
  public let objectID: String
  public let name: String
  public let configuration: [String: JSONValue]
  public let credentialHandles: [String: String]
  public let privateState: [String: JSONValue]
  public let currentDurability: Int?
  public let instanceRevision: Int
  public let pickupLock: ObjectLock?
  public let capturedCapabilities: Set<ObjectCapability>
  public let lineage: ObjectLineage
  public let ownedObjects: [OwnedObjectDeploymentSnapshot]

  public init(
    manifest: ObjectPackageManifest,
    runtimeAdapterID: String? = nil,
    runtimeAdapterVersion: String? = nil,
    objectID: String,
    name: String,
    configuration: [String: JSONValue],
    credentialHandles: [String: String],
    privateState: [String: JSONValue],
    currentDurability: Int?,
    instanceRevision: Int = 1,
    pickupLock: ObjectLock? = nil,
    capturedCapabilities: Set<ObjectCapability>,
    lineage: ObjectLineage,
    ownedObjects: [OwnedObjectDeploymentSnapshot] = []
  ) {
    self.manifest = manifest
    self.runtimeAdapterID = runtimeAdapterID ?? ObjectRuntimeRegistry.declarativeAdapterID
    self.runtimeAdapterVersion =
      runtimeAdapterVersion
      ?? ObjectRuntimeRegistry.declarativeAdapterVersion
    self.objectID = objectID
    self.name = name
    self.configuration = configuration
    self.credentialHandles = credentialHandles
    self.privateState = privateState
    self.currentDurability = currentDurability
    self.instanceRevision = instanceRevision
    self.pickupLock = pickupLock
    self.capturedCapabilities = capturedCapabilities
    self.lineage = lineage
    self.ownedObjects = ownedObjects
  }

  private enum CodingKeys: String, CodingKey {
    case manifest, runtimeAdapterID, runtimeAdapterVersion, objectID, name, configuration
    case credentialHandles, privateState, currentDurability, instanceRevision, pickupLock
    case capturedCapabilities, lineage, ownedObjects
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let manifest = try container.decode(ObjectPackageManifest.self, forKey: .manifest)
    self.init(
      manifest: manifest,
      runtimeAdapterID: try container.decodeIfPresent(String.self, forKey: .runtimeAdapterID)
        ?? ObjectRuntimeRegistry.declarativeAdapterID,
      runtimeAdapterVersion: try container.decodeIfPresent(
        String.self, forKey: .runtimeAdapterVersion
      ) ?? ObjectRuntimeRegistry.declarativeAdapterVersion,
      objectID: try container.decode(String.self, forKey: .objectID),
      name: try container.decode(String.self, forKey: .name),
      configuration: try container.decode([String: JSONValue].self, forKey: .configuration),
      credentialHandles: try container.decode([String: String].self, forKey: .credentialHandles),
      privateState: try container.decode([String: JSONValue].self, forKey: .privateState),
      currentDurability: try container.decodeIfPresent(Int.self, forKey: .currentDurability),
      instanceRevision: try container.decodeIfPresent(Int.self, forKey: .instanceRevision) ?? 1,
      pickupLock: try container.decodeIfPresent(ObjectLock.self, forKey: .pickupLock),
      capturedCapabilities: try container.decode(
        Set<ObjectCapability>.self, forKey: .capturedCapabilities),
      lineage: try container.decode(ObjectLineage.self, forKey: .lineage),
      ownedObjects: try container.decodeIfPresent(
        [OwnedObjectDeploymentSnapshot].self, forKey: .ownedObjects) ?? []
    )
  }
}

public struct OwnedObjectDeploymentSnapshot: Codable, Equatable, Sendable {
  public let localID: String
  public let objectID: String
  public let parentObjectID: String
  public let coordinate: Coordinate
  public let definition: DeclarativeObjectDefinition
  public let privateState: [String: JSONValue]
  public let currentDurability: Int?
  public let pickupLock: ObjectLock?

  public init(
    localID: String,
    objectID: String,
    parentObjectID: String,
    coordinate: Coordinate,
    definition: DeclarativeObjectDefinition,
    privateState: [String: JSONValue],
    currentDurability: Int?,
    pickupLock: ObjectLock? = nil
  ) {
    self.localID = localID
    self.objectID = objectID
    self.parentObjectID = parentObjectID
    self.coordinate = coordinate
    self.definition = definition
    self.privateState = privateState
    self.currentDurability = currentDurability
    self.pickupLock = pickupLock
  }
}

public struct ObjectDeploymentRecord: Codable, Equatable, Sendable {
  public let snapshot: ObjectDeploymentSnapshot
  public let destinationObjectID: String
  public let requestedCoordinate: Coordinate
  public let actualCoordinate: Coordinate
  public let adapted: Bool

  public init(
    snapshot: ObjectDeploymentSnapshot,
    destinationObjectID: String,
    requestedCoordinate: Coordinate,
    actualCoordinate: Coordinate,
    adapted: Bool
  ) {
    self.snapshot = snapshot
    self.destinationObjectID = destinationObjectID
    self.requestedCoordinate = requestedCoordinate
    self.actualCoordinate = actualCoordinate
    self.adapted = adapted
  }
}

public struct HumanObjectReportDraft: Equatable, Sendable {
  public let type: String
  public let title: String
  public let body: String
  public let payload: JSONValue

  public init(type: String, title: String, body: String, payload: JSONValue = .null) {
    self.type = type
    self.title = title
    self.body = body
    self.payload = payload
  }
}

public struct ObjectReport: Codable, Equatable, Sendable {
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

  public init(
    id: String = InventoryIdentity.make(),
    timestamp: Date = Date(),
    worldID: String,
    objectID: String,
    lineage: ObjectLineage,
    type: String,
    title: String,
    body: String,
    payload: JSONValue
  ) {
    self.id = id
    self.timestamp = timestamp
    self.worldID = worldID
    self.objectID = objectID
    inventoryObjectID = lineage.inventoryObjectID
    inventoryRevision = lineage.inventoryRevision
    packageID = lineage.packageID
    packageVersion = lineage.packageVersion
    self.type = type
    self.title = title
    self.body = body
    self.payload = payload
  }
}

public struct RestockRule: Codable, Equatable, Sendable {
  public let id: String
  public let inventoryObjectID: String
  public let merchantID: String
  public var price: Decimal
  public var enabled: Bool
  public let requestedCoordinate: Coordinate
  public let autoAdapt: Bool
  public var createdObjects: [RestockStockRecord]

  public var createdObjectIDs: [String] { createdObjects.map(\.objectID) }

  public init(
    id: String = InventoryIdentity.make(),
    inventoryObjectID: String,
    merchantID: String,
    price: Decimal,
    enabled: Bool = true,
    requestedCoordinate: Coordinate = .origin,
    autoAdapt: Bool = true,
    createdObjects: [RestockStockRecord] = []
  ) {
    self.id = id
    self.inventoryObjectID = inventoryObjectID
    self.merchantID = merchantID
    self.price = price
    self.enabled = enabled
    self.requestedCoordinate = requestedCoordinate
    self.autoAdapt = autoAdapt
    self.createdObjects = createdObjects
  }
}

public struct RestockStockRecord: Codable, Equatable, Sendable {
  public let objectID: String
  public let price: Decimal

  public init(objectID: String, price: Decimal) {
    self.objectID = objectID
    self.price = price
  }
}

public enum WorldCopyDeleteScope: Equatable, Sendable {
  case objects(Set<String>)
  case deployments(Set<String>)
  case all
}

public struct WorldCopyDeletionPreview: Equatable, Sendable {
  public let rootObjectIDs: [String]
  public let affectedObjectIDs: [String]

  public init(rootObjectIDs: [String], affectedObjectIDs: [String]) {
    self.rootObjectIDs = rootObjectIDs.sorted()
    self.affectedObjectIDs = affectedObjectIDs.sorted()
  }
}

public struct InventoryRestockPlan {
  public let object: MikroObject
  public let coordinate: Coordinate
  public let price: Decimal
  let commit: () -> Void

  public init(
    object: MikroObject,
    coordinate: Coordinate,
    price: Decimal,
    commit: @escaping () -> Void
  ) {
    self.object = object
    self.coordinate = coordinate
    self.price = price
    self.commit = commit
  }
}

public protocol CredentialStore: Sendable {
  func put(_ secret: Data) throws -> String
  func read(handle: String) throws -> Data
  func contains(handle: String) -> Bool
  func remove(handle: String) throws
  func garbageCollect(retaining handles: Set<String>) throws
}

public final class FileCredentialStore: CredentialStore, @unchecked Sendable {
  public let directory: URL

  public init(directory: URL = FileCredentialStore.defaultDirectory) {
    self.directory = directory
  }

  public static var defaultDirectory: URL {
    MikroKhorosPaths.root
      .appendingPathComponent("credentials", isDirectory: true)
  }

  public func put(_ secret: Data) throws -> String {
    let handle = InventoryIdentity.make()
    try put(secret, handle: handle)
    return handle
  }

  /// Writes a credential under a caller-selected opaque handle. This is used
  /// when a product transaction must include both the credential file and a
  /// document that refers to it in one recoverable commit.
  func put(_ secret: Data, handle: String) throws {
    guard !secret.isEmpty else {
      throw MikroKhorosError.runtime(
        "inventory.secret_empty",
        "the secret value cannot be empty"
      )
    }
    guard InventoryIdentity.isValid(handle) else {
      throw MikroKhorosError.persistence("credential handle is invalid")
    }
    let url = credentialURL(handle: handle)
    do {
      try AtomicFileStore.write(
        secret,
        to: url,
        lockURL: directory.appendingPathComponent("credential-store.lock", isDirectory: true)
      )
    } catch {
      throw MikroKhorosError.persistence("could not save the credential version")
    }
  }

  func credentialURL(handle: String) -> URL {
    directory.appendingPathComponent(handle, isDirectory: false)
  }

  public func read(handle: String) throws -> Data {
    guard InventoryIdentity.isValid(handle) else {
      throw MikroKhorosError.persistence("credential handle is invalid")
    }
    do {
      return try Data(
        contentsOf: credentialURL(handle: handle),
        options: [.mappedIfSafe]
      )
    } catch {
      throw MikroKhorosError.runtime(
        "inventory.credential_unavailable",
        "a required credential version is unavailable",
        details: ["handle": handle]
      )
    }
  }

  public func contains(handle: String) -> Bool {
    InventoryIdentity.isValid(handle)
      && FileManager.default.fileExists(
        atPath: credentialURL(handle: handle).path
      )
  }

  public func remove(handle: String) throws {
    guard InventoryIdentity.isValid(handle) else { return }
    let url = credentialURL(handle: handle)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do { try FileManager.default.removeItem(at: url) } catch {
      throw MikroKhorosError.persistence("could not remove the credential version")
    }
  }

  public func garbageCollect(retaining handles: Set<String>) throws {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    for url in try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    where InventoryIdentity.isValid(url.lastPathComponent)
      && !handles.contains(url.lastPathComponent)
    {
      try FileManager.default.removeItem(at: url)
    }
  }
}

public final class InventoryStore: @unchecked Sendable {
  public let url: URL
  public let packageDirectory: URL
  public let credentialStore: any CredentialStore
  public let limits: RuntimeLimits
  public let runtimeRegistry: ObjectRuntimeRegistry
  public private(set) var document: InventoryDocument
  private var transientReferences: [String: WorldArtifactReferences] = [:]

  public init(
    url: URL = InventoryStore.defaultURL,
    packageDirectory: URL? = nil,
    credentialStore: (any CredentialStore)? = nil,
    limits: RuntimeLimits = .defaults,
    runtimeRegistry: ObjectRuntimeRegistry = .declarativeOnly()
  ) throws {
    try limits.validate()
    self.url = url
    self.packageDirectory =
      packageDirectory
      ?? url.deletingLastPathComponent().appendingPathComponent("packages", isDirectory: true)
    self.credentialStore =
      credentialStore
      ?? FileCredentialStore(
        directory: url.deletingLastPathComponent()
          .appendingPathComponent("credentials", isDirectory: true)
      )
    self.limits = limits
    self.runtimeRegistry = runtimeRegistry
    self.document = try Self.loadDocument(from: url, maximumBytes: limits.maximumInventoryBytes)
    try validateDocument()
  }

  public static var defaultURL: URL {
    MikroKhorosPaths.root
      .appendingPathComponent("inventory.json", isDirectory: false)
  }

  public var installedPackages: [InstalledObjectPackage] {
    document.packages.filter(\.visible).sorted {
      if $0.manifest.id != $1.manifest.id { return $0.manifest.id < $1.manifest.id }
      return Self.compareVersions($0.manifest.version, $1.manifest.version) == .orderedDescending
    }
  }

  public func allInventoryObjects(includeDeleted: Bool = false) -> [InventoryObjectRecord] {
    document.objects.filter { includeDeleted || !$0.deleted }.sorted { $0.id < $1.id }
  }

  public func templateSource(
    templateID: String,
    templateVersion: String,
    componentKey: String,
    includeDeleted: Bool = false
  ) throws -> InventoryObjectRecord? {
    let matches = document.objects.filter { object in
      (includeDeleted || !object.deleted)
        && object.templateSource?.templateID == templateID
        && object.templateSource?.templateVersion == templateVersion
        && object.templateSource?.componentKey == componentKey
    }
    guard matches.count <= 1 else {
      throw MikroKhorosError.runtime(
        "world_template.application_corrupt",
        "Inventory contains more than one canonical source for a template component",
        details: ["template": templateID, "component": componentKey],
        suggestions: ["run `khoros doctor` and repair the Inventory document"]
      )
    }
    return matches.first
  }

  public func allInventoryFolders() -> [InventoryFolderRecord] {
    document.folders.sorted { folderPath(for: $0.id) < folderPath(for: $1.id) }
  }

  public func resolveFolder(_ query: String) throws -> InventoryFolderRecord {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.isEmpty || normalized == "/" || normalized == "Inventory" {
      return try rootFolder()
    }

    let identityMatches = document.folders.filter {
      $0.id == normalized || (normalized.count >= 4 && $0.id.hasPrefix(normalized))
    }
    if identityMatches.count == 1, let folder = identityMatches.first { return folder }
    if identityMatches.count > 1 {
      throw MikroKhorosError.runtime(
        "inventory.folder_ambiguous",
        "the Inventory folder id prefix is ambiguous",
        suggestions: ["use the complete Inventory folder id"]
      )
    }

    var components = normalized.split(separator: "/").map(String.init)
    if components.first == "Inventory" { components.removeFirst() }
    var current = try rootFolder()
    for component in components {
      let matches = document.folders.filter {
        $0.parentID == current.id && $0.name == component
      }
      guard let next = matches.first else {
        throw MikroKhorosError.runtime(
          "inventory.folder_not_found",
          "the Inventory folder does not exist",
          details: ["folder": normalized]
        )
      }
      current = next
    }
    return current
  }

  public func folderPath(for folderID: String) -> String {
    guard folderID != InventoryFolderIdentity.rootID else { return "/" }
    var names: [String] = []
    var currentID: String? = folderID
    var visited: Set<String> = []
    while let id = currentID, id != InventoryFolderIdentity.rootID,
      let folder = document.folders.first(where: { $0.id == id }), !visited.contains(id)
    {
      visited.insert(id)
      names.append(folder.name)
      currentID = folder.parentID
    }
    return names.reversed().joined(separator: "/")
  }

  public func childFolders(of folderID: String, recursive: Bool = false)
    -> [InventoryFolderRecord]
  {
    if !recursive {
      return document.folders.filter { $0.parentID == folderID }.sorted { $0.name < $1.name }
    }
    let descendants = descendantFolderIDs(of: folderID)
    return document.folders.filter { descendants.contains($0.id) }.sorted {
      folderPath(for: $0.id) < folderPath(for: $1.id)
    }
  }

  public func inventoryObjects(
    inFolder folderID: String,
    recursive: Bool = false,
    includeDeleted: Bool = false
  ) -> [InventoryObjectRecord] {
    var included = Set([folderID])
    if recursive { included.formUnion(descendantFolderIDs(of: folderID)) }
    return document.objects.filter {
      included.contains($0.folderID) && (includeDeleted || !$0.deleted)
    }.sorted { $0.id < $1.id }
  }

  @discardableResult
  public func createFolder(path: String) throws -> InventoryFolderRecord {
    let components = try Self.inventoryPathComponents(path)
    guard let name = components.last else {
      throw MikroKhorosError.runtime(
        "inventory.folder_root_exists",
        "the root Inventory folder already exists"
      )
    }
    guard document.folders.count < limits.maximumInventoryFolders else {
      throw MikroKhorosError.runtime(
        "inventory.folder_limit",
        "the Inventory folder limit has been reached",
        details: ["limit": String(limits.maximumInventoryFolders)]
      )
    }
    let parentPath = components.dropLast().joined(separator: "/")
    let parent = try resolveFolder(parentPath.isEmpty ? "/" : parentPath)
    try Self.validateFolderName(name)
    guard !document.folders.contains(where: { $0.parentID == parent.id && $0.name == name }) else {
      throw MikroKhorosError.runtime(
        "inventory.folder_exists",
        "an Inventory folder with this name already exists under the selected parent"
      )
    }
    let folder = InventoryFolderRecord(name: name, parentID: parent.id)
    document.folders.append(folder)
    do { try save() } catch {
      document.folders.removeAll { $0.id == folder.id }
      throw error
    }
    return folder
  }

  @discardableResult
  public func renameFolder(_ query: String, to name: String) throws -> InventoryFolderRecord {
    let folder = try resolveFolder(query)
    guard folder.id != InventoryFolderIdentity.rootID else {
      throw MikroKhorosError.runtime(
        "inventory.folder_root_immutable",
        "the root Inventory folder cannot be renamed"
      )
    }
    try Self.validateFolderName(name)
    guard
      !document.folders.contains(where: {
        $0.id != folder.id && $0.parentID == folder.parentID && $0.name == name
      })
    else {
      throw MikroKhorosError.runtime(
        "inventory.folder_exists",
        "an Inventory folder with this name already exists under the selected parent"
      )
    }
    return try mutateFolder(folder.id) {
      $0.name = name
      $0.updatedAt = Date()
    }
  }

  @discardableResult
  public func moveFolder(_ query: String, to parentQuery: String) throws
    -> InventoryFolderRecord
  {
    let folder = try resolveFolder(query)
    let parent = try resolveFolder(parentQuery)
    guard folder.id != InventoryFolderIdentity.rootID else {
      throw MikroKhorosError.runtime(
        "inventory.folder_root_immutable",
        "the root Inventory folder cannot be moved"
      )
    }
    guard folder.id != parent.id, !descendantFolderIDs(of: folder.id).contains(parent.id) else {
      throw MikroKhorosError.runtime(
        "inventory.folder_cycle",
        "moving this Inventory folder would create a cycle"
      )
    }
    guard
      !document.folders.contains(where: {
        $0.id != folder.id && $0.parentID == parent.id && $0.name == folder.name
      })
    else {
      throw MikroKhorosError.runtime(
        "inventory.folder_exists",
        "an Inventory folder with this name already exists under the selected parent"
      )
    }
    return try mutateFolder(folder.id) {
      $0.parentID = parent.id
      $0.updatedAt = Date()
    }
  }

  @discardableResult
  public func deleteFolder(_ query: String) throws -> InventoryFolderRecord {
    let folder = try resolveFolder(query)
    guard folder.id != InventoryFolderIdentity.rootID else {
      throw MikroKhorosError.runtime(
        "inventory.folder_root_immutable",
        "the root Inventory folder cannot be deleted"
      )
    }
    guard !document.folders.contains(where: { $0.parentID == folder.id }),
      !document.objects.contains(where: { $0.folderID == folder.id })
    else {
      throw MikroKhorosError.runtime(
        "inventory.folder_not_empty",
        "the Inventory folder must be empty before it can be deleted",
        suggestions: ["move its folders and Inventory objects first"]
      )
    }
    document.folders.removeAll { $0.id == folder.id }
    do { try save() } catch {
      document.folders.append(folder)
      throw error
    }
    return folder
  }

  @discardableResult
  public func moveInventoryObject(_ id: String, toFolder query: String) throws
    -> InventoryObjectRecord
  {
    let folder = try resolveFolder(query)
    let current = try resolve(id)
    guard let index = document.objects.firstIndex(where: { $0.id == current.id }) else {
      throw MikroKhorosError.runtime(
        "inventory.object_not_found", "the Inventory object does not exist")
    }
    guard document.objects[index].folderID != folder.id else { return document.objects[index] }
    let prior = document.objects[index]
    document.objects[index].folderID = folder.id
    document.objects[index].updatedAt = Date()
    do { try save() } catch {
      document.objects[index] = prior
      throw error
    }
    return document.objects[index]
  }

  @discardableResult
  public func fork(
    id: String,
    worldID: String,
    name: String? = nil,
    folder query: String? = nil
  ) throws -> InventoryObjectRecord {
    let parent = try resolve(id)
    let package = try package(contentHash: parent.packageHash)
    guard package.manifest.installation.additionalInventoryObjects == .allow else {
      throw MikroKhorosError.runtime(
        "inventory.additional_objects_denied",
        "this package does not permit additional Inventory objects"
      )
    }
    guard InventoryIdentity.isValid(worldID) else {
      throw MikroKhorosError.runtime(
        "world.id_invalid",
        "the selected world identity is invalid"
      )
    }
    let destinationFolder = try query.map(resolveFolder) ?? resolveFolder(parent.folderID)
    let resolvedName = name ?? "\(parent.name) fork"
    try Self.validateInventoryName(resolvedName)
    let fork = InventoryObjectRecord(
      name: resolvedName,
      packageID: parent.packageID,
      packageVersion: parent.packageVersion,
      packageHash: parent.packageHash,
      configuration: parent.configuration,
      requestedCapabilities: parent.requestedCapabilities,
      grantedCapabilities: parent.grantedCapabilities,
      managementState: parent.managementState,
      folderID: destinationFolder.id,
      forkProvenance: InventoryForkProvenance(
        parentInventoryObjectID: parent.id,
        parentRevision: parent.revision
      ),
      worldBinding: InventoryWorldBinding(worldID: worldID)
    )
    document.objects.append(fork)
    do { try save() } catch {
      document.objects.removeAll { $0.id == fork.id }
      throw error
    }
    return fork
  }

  public func package(
    id: String,
    version: String? = nil,
    includeHidden: Bool = false
  ) throws -> InstalledObjectPackage {
    var matches = document.packages.filter {
      $0.manifest.id == id && (includeHidden || $0.visible)
        && (version == nil || $0.manifest.version == version)
    }
    guard !matches.isEmpty else {
      throw MikroKhorosError.runtime(
        "object_package.not_found",
        "the object package is not installed",
        details: ["package": id]
      )
    }
    matches.sort {
      Self.compareVersions($0.manifest.version, $1.manifest.version) == .orderedDescending
    }
    return matches[0]
  }

  public func package(contentHash: String) throws -> InstalledObjectPackage {
    guard let package = document.packages.first(where: { $0.contentHash == contentHash }) else {
      throw MikroKhorosError.runtime(
        "object_package.content_unavailable",
        "the retained package content is unavailable",
        details: ["content_hash": contentHash]
      )
    }
    return package
  }

  public func resolve(_ query: String, includeDeleted: Bool = false) throws
    -> InventoryObjectRecord
  {
    try HumanSelectorResolver.resolve(
      query,
      among: document.objects.filter { includeDeleted || !$0.deleted },
      id: \.id,
      name: { $0.name },
      kind: "Inventory object",
      listCommand: "khoros inventory list"
    ).value
  }

  @discardableResult
  public func install(data: Data) throws -> PackageInstallationResult {
    guard data.count <= limits.maximumPackageBytes else {
      throw MikroKhorosError.runtime(
        "object_package.too_large",
        "the object package exceeds the configured byte limit",
        details: ["limit": String(limits.maximumPackageBytes)]
      )
    }
    let manifest: ObjectPackageManifest
    do { manifest = try JSONDecoder().decode(ObjectPackageManifest.self, from: data) } catch let
      error as MikroKhorosError
    {
      throw error
    } catch {
      throw MikroKhorosError.objectPackage("object package is not valid manifest JSON")
    }
    try runtimeRegistry.validate(manifest)
    let hash = SHA256Digest.hex(data)
    if let existingIndex = document.packages.firstIndex(where: {
      $0.manifest.id == manifest.id && $0.manifest.version == manifest.version
    }) {
      guard document.packages[existingIndex].contentHash == hash else {
        throw MikroKhorosError.runtime(
          "object_package.version_collision",
          "this package id and version are already retained with different content",
          suggestions: ["publish changed package content under a new semantic version"]
        )
      }
      guard !document.packages[existingIndex].visible else {
        throw MikroKhorosError.runtime(
          "object_package.already_installed",
          "this object package version is already installed"
        )
      }
      document.packages[existingIndex].visible = true
      do { try save() } catch {
        document.packages[existingIndex].visible = false
        throw error
      }
      return PackageInstallationResult(
        package: document.packages[existingIndex],
        inventoryObject: nil
      )
    }

    let prior = document
    let package = InstalledObjectPackage(manifest: manifest, contentHash: hash)
    document.packages.append(package)
    var created: InventoryObjectRecord?
    if manifest.installation.onInstall == .createInventoryObject {
      created = try makeInventoryObject(package: package, name: manifest.displayName)
      document.objects.append(created!)
    }

    let packageURL = packageDirectory.appendingPathComponent("\(hash).json")
    let existed = FileManager.default.fileExists(atPath: packageURL.path)
    do {
      try FileManager.default.createDirectory(
        at: packageDirectory,
        withIntermediateDirectories: true
      )
      if !existed { try data.write(to: packageURL, options: [.atomic]) }
      try save()
    } catch {
      document = prior
      if !existed { try? FileManager.default.removeItem(at: packageURL) }
      throw error
    }
    return PackageInstallationResult(package: package, inventoryObject: created)
  }

  @discardableResult
  public func install(from source: String) async throws -> PackageInstallationResult {
    if source.hasPrefix("builtin:") {
      return try install(data: FirstPartyPackageCatalog.data(named: String(source.dropFirst(8))))
    }
    if let remote = URL(string: source), let scheme = remote.scheme?.lowercased(),
      scheme == "https" || scheme == "http"
    {
      let data = try await ObjectPackageDownloader.download(
        remote,
        maximumBytes: limits.maximumPackageBytes
      )
      return try install(data: data)
    }
    let fileURL = URL(fileURLWithPath: source)
    return try install(
      data: BoundedPackageFile.read(fileURL, maximumBytes: limits.maximumPackageBytes)
    )
  }

  public func removePackage(id: String, version: String? = nil) throws {
    let candidates = document.packages.indices.filter {
      document.packages[$0].manifest.id == id && document.packages[$0].visible
        && (version == nil || document.packages[$0].manifest.version == version)
    }
    guard !candidates.isEmpty else {
      throw MikroKhorosError.runtime(
        "object_package.not_found",
        "the object package is not installed"
      )
    }
    guard version != nil || candidates.count == 1 else {
      throw MikroKhorosError.runtime(
        "object_package.version_required",
        "more than one package version is installed",
        suggestions: ["select a package version explicitly"]
      )
    }
    for index in candidates { document.packages[index].visible = false }
    do { try save() } catch {
      for index in candidates { document.packages[index].visible = true }
      throw error
    }
  }

  @discardableResult
  public func create(packageID: String, version: String? = nil, name: String? = nil) throws
    -> InventoryObjectRecord
  {
    let package = try package(id: packageID, version: version)
    guard package.manifest.installation.additionalInventoryObjects == .allow else {
      throw MikroKhorosError.runtime(
        "inventory.additional_objects_denied",
        "this package does not permit additional Inventory objects"
      )
    }
    let object = try makeInventoryObject(
      package: package,
      name: name ?? package.manifest.displayName
    )
    document.objects.append(object)
    do { try save() } catch {
      document.objects.removeAll { $0.id == object.id }
      throw error
    }
    return object
  }

  @discardableResult
  public func createTemplateSource(
    packageID: String,
    version: String,
    name: String,
    folderID: String,
    provenance: InventoryTemplateSourceProvenance
  ) throws -> InventoryObjectRecord {
    if let existing = try templateSource(
      templateID: provenance.templateID,
      templateVersion: provenance.templateVersion,
      componentKey: provenance.componentKey
    ) {
      return existing
    }
    let package = try package(id: packageID, version: version)
    guard document.folders.contains(where: { $0.id == folderID }) else {
      throw MikroKhorosError.runtime(
        "inventory.folder_not_found",
        "the canonical template-source folder does not exist"
      )
    }
    var object = try makeInventoryObject(package: package, name: name)
    object.folderID = folderID
    object = InventoryObjectRecord(
      id: object.id,
      name: object.name,
      packageID: object.packageID,
      packageVersion: object.packageVersion,
      packageHash: object.packageHash,
      revision: object.revision,
      configuration: object.configuration,
      credentialHandles: object.credentialHandles,
      requestedCapabilities: object.requestedCapabilities,
      grantedCapabilities: object.grantedCapabilities,
      managementState: object.managementState,
      folderID: folderID,
      templateSource: provenance,
      createdAt: object.createdAt,
      updatedAt: object.updatedAt
    )
    document.objects.append(object)
    do { try save() } catch {
      document.objects.removeAll { $0.id == object.id }
      throw error
    }
    return object
  }

  public func restoreDocument(_ value: InventoryDocument, persist: Bool = true) throws {
    let prior = document
    document = value
    do {
      try validateDocument()
      if persist { try save() }
    } catch {
      document = prior
      throw error
    }
  }

  @discardableResult
  public func configure(
    id: String,
    setting values: [String: JSONValue],
    unsetting fields: Set<String> = []
  ) throws -> InventoryObjectRecord {
    let current = try resolve(id)
    let package = try package(contentHash: current.packageHash)
    var next = current.configuration
    for fieldID in values.keys {
      guard let field = package.manifest.management.fields.first(where: { $0.id == fieldID }) else {
        throw MikroKhorosError.runtime(
          "inventory.field_unknown",
          "the configuration field is not declared by this package",
          details: ["field": fieldID]
        )
      }
      guard field.kind != .secret else {
        throw MikroKhorosError.runtime(
          "inventory.secret_requires_secret_command",
          "secret fields must be assigned through the secret command",
          details: ["field": fieldID]
        )
      }
      next[fieldID] = try validatedInventoryValue(values[fieldID]!, for: field)
    }
    for fieldID in fields {
      guard let field = package.manifest.management.fields.first(where: { $0.id == fieldID }) else {
        throw MikroKhorosError.runtime(
          "inventory.field_unknown",
          "the configuration field is not declared by this package",
          details: ["field": fieldID]
        )
      }
      guard field.kind != .secret else {
        throw MikroKhorosError.runtime(
          "inventory.secret_requires_secret_command",
          "secret fields must be cleared through the secret command",
          details: ["field": fieldID]
        )
      }
      next.removeValue(forKey: fieldID)
    }
    try validateKnownConfiguration(next, manifest: package.manifest)
    return try mutate(id) { object in
      object.configuration = next
      object.revision += 1
      object.updatedAt = Date()
    }
  }

  @discardableResult
  public func setSecret(id: String, fieldID: String, value: Data) throws
    -> InventoryObjectRecord
  {
    let current = try resolve(id)
    let package = try package(contentHash: current.packageHash)
    guard let field = package.manifest.management.fields.first(where: { $0.id == fieldID }),
      field.kind == .secret
    else {
      throw MikroKhorosError.runtime(
        "inventory.secret_field_unknown",
        "the package does not declare this secret field",
        details: ["field": fieldID]
      )
    }
    guard let secretText = String(data: value, encoding: .utf8) else {
      throw MikroKhorosError.runtime(
        "inventory.secret_invalid",
        "secret fields require UTF-8 text"
      )
    }
    _ = try validatedManagementValue(.string(secretText), for: field)
    let handle = try credentialStore.put(value)
    do {
      return try mutate(id) { object in
        object.credentialHandles[fieldID] = handle
        object.revision += 1
        object.updatedAt = Date()
      }
    } catch {
      try? credentialStore.remove(handle: handle)
      throw error
    }
  }

  @discardableResult
  public func clearSecret(id: String, fieldID: String) throws -> InventoryObjectRecord {
    let current = try resolve(id)
    let package = try package(contentHash: current.packageHash)
    guard
      package.manifest.management.fields.contains(where: {
        $0.id == fieldID && $0.kind == .secret
      })
    else {
      throw MikroKhorosError.runtime(
        "inventory.secret_field_unknown",
        "the package does not declare this secret field",
        details: ["field": fieldID]
      )
    }
    return try mutate(id) { object in
      object.credentialHandles.removeValue(forKey: fieldID)
      object.revision += 1
      object.updatedAt = Date()
    }
  }

  @discardableResult
  public func grant(id: String, capabilities: Set<ObjectCapability>) throws
    -> InventoryObjectRecord
  {
    let current = try resolve(id)
    guard capabilities.isSubset(of: current.requestedCapabilities) else {
      let invalid = capabilities.subtracting(current.requestedCapabilities)
        .map(\.rawValue).sorted().joined(separator: ",")
      throw MikroKhorosError.runtime(
        "inventory.capability_not_requested",
        "the package did not request one or more capabilities",
        details: ["capabilities": invalid]
      )
    }
    return try mutate(id) { object in
      object.grantedCapabilities.formUnion(capabilities)
      object.revision += 1
      object.updatedAt = Date()
    }
  }

  @discardableResult
  public func revoke(id: String, capabilities: Set<ObjectCapability>) throws
    -> InventoryObjectRecord
  {
    _ = try resolve(id)
    return try mutate(id) { object in
      object.grantedCapabilities.subtract(capabilities)
      object.revision += 1
      object.updatedAt = Date()
    }
  }

  public func readiness(of record: InventoryObjectRecord) throws -> InventoryReadiness {
    let package = try package(contentHash: record.packageHash)
    let missingConfiguration = package.manifest.management.fields.filter {
      $0.required && $0.kind != .secret && record.configuration[$0.id] == nil
    }.map(\.id)
    let missingCredentials = package.manifest.management.fields.filter {
      $0.required && $0.kind == .secret
        && (record.credentialHandles[$0.id].map(credentialStore.contains(handle:)) != true)
    }.map(\.id)
    let missingCapabilities = record.requestedCapabilities
      .subtracting(record.grantedCapabilities).map { $0 }
    return InventoryReadiness(
      missingConfiguration: missingConfiguration,
      missingCredentials: missingCredentials,
      missingCapabilities: missingCapabilities
    )
  }

  public func requireReady(_ record: InventoryObjectRecord) throws {
    let status = try readiness(of: record)
    guard status.ready else {
      throw MikroKhorosError.runtime(
        "inventory.object_not_ready",
        "the Inventory object is not ready to create a world copy",
        details: [
          "configuration": status.missingConfiguration.joined(separator: ","),
          "credentials": status.missingCredentials.joined(separator: ","),
          "capabilities": status.missingCapabilities.map(\.rawValue).joined(separator: ","),
        ],
        suggestions: ["complete the missing fields, credentials, and capability grants"]
      )
    }
  }

  @discardableResult
  public func runAction(id: String, actionID: String, inputs: [String]) throws
    -> (InventoryObjectRecord, JSONValue)
  {
    let current = try resolve(id)
    let package = try package(contentHash: current.packageHash)
    guard let action = package.manifest.management.actions.first(where: { $0.id == actionID })
    else {
      throw MikroKhorosError.runtime(
        "inventory.action_unknown",
        "the package does not declare this management action",
        details: ["action": actionID]
      )
    }
    guard action.scope.acceptsInventory else {
      throw MikroKhorosError.runtime(
        "inventory.action_scope_denied",
        "this management action is available only on a concrete world object"
      )
    }
    guard inputs.count == action.parameters.count else {
      throw MikroKhorosError.runtime(
        "inventory.action_input_invalid",
        "the management action received the wrong number of inputs"
      )
    }
    for (index, parameter) in action.parameters.enumerated() {
      try Self.validateManagementInput(
        inputs[index],
        type: action.inputTypes[parameter] ?? .text,
        choices: action.inputChoices[parameter] ?? [],
        maximumCharacters: limits.maximumModelFieldCharacters,
        parameter: parameter
      )
    }
    let broker = ObjectCapabilityBroker(granted: current.grantedCapabilities)
    for capability in action.requiredCapabilities { try broker.require(capability) }
    if package.manifest.runtime == .nativeSwift {
      let adapter = try runtimeRegistry.adapter(for: package.manifest)
      guard action.scope.acceptsInventory else {
        throw MikroKhorosError.runtime(
          "inventory.action_scope_denied",
          "this management action is available only on a concrete world object"
        )
      }
      var updatedRecord = current
      let output = try adapter.runInventoryAction(
        action,
        inputs: inputs,
        record: &updatedRecord,
        limits: limits
      )
      try Self.validateStructuredResult(
        output,
        contract: action.result,
        code: "inventory.action_result_invalid"
      )
      guard action.mutating else { return (current, output) }
      let updated = try mutate(id) { object in
        object.managementState = updatedRecord.managementState
        object.revision += 1
        object.updatedAt = Date()
      }
      return (updated, output)
    }
    var nextState = current.managementState
    let output = try Self.applyManagementAction(
      action.action,
      inputs: inputs,
      configuration: current.configuration,
      state: &nextState
    )
    try Self.validateStructuredResult(
      output,
      contract: action.result,
      code: "inventory.action_result_invalid"
    )
    guard action.mutating else { return (current, output) }
    let updated = try mutate(id) { object in
      object.managementState = nextState
      object.revision += 1
      object.updatedAt = Date()
    }
    return (updated, output)
  }

  public func renderView(id: String, viewID: String, worldObject: MikroObject? = nil) throws
    -> JSONValue
  {
    let object = try resolve(id)
    let package = try package(contentHash: object.packageHash)
    guard let view = package.manifest.management.views.first(where: { $0.id == viewID }) else {
      throw MikroKhorosError.runtime(
        "inventory.view_unknown",
        "the package does not declare this management view",
        details: ["view": viewID]
      )
    }
    guard view.scope.acceptsInventory else {
      throw MikroKhorosError.runtime(
        "inventory.view_scope_denied",
        "this management view is available only on a concrete world object"
      )
    }
    guard worldObject == nil || view.worldObjectScope else {
      throw MikroKhorosError.runtime(
        "inventory.view_object_scope_denied",
        "this management view does not accept a world-object scope"
      )
    }
    if package.manifest.runtime == .nativeSwift {
      guard worldObject == nil else {
        throw MikroKhorosError.runtime(
          "inventory.view_object_scope_denied",
          "use the concrete world-object view interface for this runtime"
        )
      }
      let output = try runtimeRegistry.adapter(for: package.manifest).renderInventoryView(
        view,
        record: object,
        limits: limits
      )
      try Self.validateStructuredResult(
        output,
        contract: view.result,
        code: "inventory.view_result_invalid"
      )
      return output
    }
    let output: JSONValue
    switch view.source {
    case "configuration":
      output = .object(redactedConfiguration(of: object, manifest: package.manifest))
    case "state":
      if let declarative = worldObject as? DeclarativeObject {
        guard declarative.lineage?.inventoryObjectID == object.id else {
          throw MikroKhorosError.runtime(
            "inventory.view_object_mismatch",
            "the selected world object does not descend from this Inventory object"
          )
        }
        output = .object(declarative.privateState)
      } else {
        output = .object(object.managementState)
      }
    default:
      let status = try readiness(of: object)
      output = .object([
        "inventory_object_id": .string(object.id),
        "name": .string(object.name),
        "revision": .number(Double(object.revision)),
        "ready": .bool(status.ready),
      ])
    }
    try Self.validateStructuredResult(
      output,
      contract: view.result,
      code: "inventory.view_result_invalid"
    )
    return output
  }

  public func redactedConfiguration(
    of object: InventoryObjectRecord,
    manifest: ObjectPackageManifest? = nil
  ) -> [String: JSONValue] {
    var result = object.configuration
    let fields =
      manifest?.management.fields
      ?? (try? package(contentHash: object.packageHash).manifest.management.fields) ?? []
    for field in fields where field.kind == .secret {
      result[field.id] = .object([
        "present": .bool(
          object.credentialHandles[field.id].map(credentialStore.contains(handle:)) == true)
      ])
    }
    return result
  }

  public func delete(id: String) throws -> InventoryObjectRecord {
    _ = try resolve(id)
    return try mutate(id) { object in
      object.deleted = true
      object.credentialHandles = [:]
      object.revision += 1
      object.updatedAt = Date()
    }
  }

  public func setRuntimeReferences(
    owner: String,
    credentialHandles: Set<String>,
    packageHashes: Set<String>
  ) {
    transientReferences[owner] = WorldArtifactReferences(
      credentialHandles: credentialHandles,
      packageHashes: packageHashes
    )
  }

  public func synchronizeWorldReferences(
    worldID: String,
    credentialHandles: Set<String>,
    packageHashes: Set<String>
  ) throws {
    guard InventoryIdentity.isValid(worldID) else {
      throw MikroKhorosError.persistence("Inventory received an invalid world reference")
    }
    let previous = document.worldReferences[worldID]
    document.worldReferences[worldID] = WorldArtifactReferences(
      credentialHandles: credentialHandles,
      packageHashes: packageHashes
    )
    do {
      try save()
    } catch {
      document.worldReferences[worldID] = previous
      throw error
    }
  }

  public func worldReferences(for worldID: String) -> WorldArtifactReferences {
    document.worldReferences[worldID] ?? .empty
  }

  public func removeWorldReferences(for worldID: String) {
    document.worldReferences.removeValue(forKey: worldID)
  }

  public func validateStorage() throws {
    try validateDocument()
    for package in document.packages {
      let url = packageDirectory.appendingPathComponent("\(package.contentHash).json")
      guard FileManager.default.fileExists(atPath: url.path) else {
        throw MikroKhorosError.persistence("retained object package content is missing")
      }
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      guard values.fileSize.map({ $0 <= limits.maximumPackageBytes }) != false else {
        throw MikroKhorosError.persistence("retained object package exceeds the configured limit")
      }
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      guard SHA256Digest.hex(data) == package.contentHash,
        try JSONDecoder().decode(ObjectPackageManifest.self, from: data) == package.manifest
      else {
        throw MikroKhorosError.persistence("retained object package content failed validation")
      }
    }
    for object in document.objects {
      for handle in object.credentialHandles.values where !credentialStore.contains(handle: handle)
      {
        throw MikroKhorosError.persistence("Inventory references an unavailable credential version")
      }
    }
    for references in document.worldReferences.values {
      guard references.credentialHandles.allSatisfy(credentialStore.contains(handle:)) else {
        throw MikroKhorosError.persistence(
          "a world references an unavailable credential version"
        )
      }
      guard
        references.packageHashes.allSatisfy({ hash in
          document.packages.contains(where: { $0.contentHash == hash })
        })
      else {
        throw MikroKhorosError.persistence("a world references unavailable package content")
      }
    }
    for references in document.worldReferences.values {
      guard references.credentialHandles.allSatisfy(InventoryIdentity.isValid),
        references.packageHashes.allSatisfy({ hash in
          hash.count == 64 && hash.allSatisfy(\.isHexDigit)
        })
      else {
        throw MikroKhorosError.persistence("Inventory contains invalid world references")
      }
    }
  }

  public func save(garbageCollectCredentials: Bool = true) throws {
    try saveDocument()
    guard garbageCollectCredentials else { return }
    garbageCollectUnreferencedCredentials()
  }

  public func garbageCollectUnreferencedCredentials() {
    let retainedCredentials = Set(
      document.objects.filter { !$0.deleted }.flatMap {
        $0.credentialHandles.values
      }
    )
    .union(document.worldReferences.values.flatMap(\.credentialHandles))
    .union(transientReferences.values.flatMap(\.credentialHandles))
    try? credentialStore.garbageCollect(retaining: retainedCredentials)
  }

  private func saveDocument() throws {
    try validateDocument()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(document)
    guard data.count <= limits.maximumInventoryBytes else {
      throw MikroKhorosError.runtime(
        "inventory.store_too_large",
        "the Inventory document exceeds the configured byte limit",
        details: ["limit": String(limits.maximumInventoryBytes)]
      )
    }
    try AtomicFileStore.write(data, to: url, lockURL: url.appendingPathExtension("lock"))
  }

  private func makeInventoryObject(
    package: InstalledObjectPackage,
    name: String
  ) throws -> InventoryObjectRecord {
    try Self.validateInventoryName(name)
    var defaults: [String: JSONValue] = [:]
    for field in package.manifest.management.fields where field.kind != .secret {
      if let value = field.defaultValue { defaults[field.id] = value }
    }
    let managementState: [String: JSONValue]
    if package.manifest.runtime == .nativeSwift {
      managementState = try runtimeRegistry.adapter(for: package.manifest)
        .makeDefaultManagementState(manifest: package.manifest)
    } else {
      managementState = package.manifest.object.state
    }
    return InventoryObjectRecord(
      name: name,
      packageID: package.manifest.id,
      packageVersion: package.manifest.version,
      packageHash: package.contentHash,
      configuration: defaults,
      requestedCapabilities: package.manifest.requestedCapabilities,
      managementState: managementState
    )
  }

  private func validateKnownConfiguration(
    _ configuration: [String: JSONValue],
    manifest: ObjectPackageManifest
  ) throws {
    for (key, value) in configuration {
      guard let field = manifest.management.fields.first(where: { $0.id == key }),
        field.kind != .secret
      else {
        throw MikroKhorosError.runtime(
          "inventory.field_unknown",
          "the configuration contains an undeclared field",
          details: ["field": key]
        )
      }
      _ = try validatedInventoryValue(value, for: field)
    }
  }

  private func validatedInventoryValue(_ value: JSONValue, for field: ManagementField) throws
    -> JSONValue
  {
    let validated = try validatedManagementValue(value, for: field)
    switch field.kind {
    case .url:
      guard let raw = validated.stringValue, let url = URL(string: raw),
        let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme)
      else {
        throw MikroKhorosError.runtime(
          "inventory.configuration_invalid",
          "the field requires an HTTP or HTTPS URL",
          details: ["field": field.id]
        )
      }
    case .path:
      guard let raw = validated.stringValue, !raw.isEmpty, !raw.contains("\0") else {
        throw MikroKhorosError.runtime(
          "inventory.configuration_invalid",
          "the field requires a valid filesystem path",
          details: ["field": field.id]
        )
      }
    default: break
    }
    return validated
  }

  private func mutate(
    _ id: String,
    change: (inout InventoryObjectRecord) throws -> Void
  ) throws -> InventoryObjectRecord {
    guard let index = document.objects.firstIndex(where: { $0.id == id && !$0.deleted }) else {
      throw MikroKhorosError.runtime(
        "inventory.object_not_found",
        "the Inventory object does not exist"
      )
    }
    let prior = document.objects[index]
    do {
      try change(&document.objects[index])
      try save()
      return document.objects[index]
    } catch {
      document.objects[index] = prior
      throw error
    }
  }

  private func mutateFolder(
    _ id: String,
    change: (inout InventoryFolderRecord) throws -> Void
  ) throws -> InventoryFolderRecord {
    guard let index = document.folders.firstIndex(where: { $0.id == id }) else {
      throw MikroKhorosError.runtime(
        "inventory.folder_not_found",
        "the Inventory folder does not exist"
      )
    }
    let prior = document.folders[index]
    do {
      try change(&document.folders[index])
      try save()
      return document.folders[index]
    } catch {
      document.folders[index] = prior
      throw error
    }
  }

  private func rootFolder() throws -> InventoryFolderRecord {
    guard
      let root = document.folders.first(where: { $0.id == InventoryFolderIdentity.rootID })
    else {
      throw MikroKhorosError.persistence("Inventory root folder is missing")
    }
    return root
  }

  private func descendantFolderIDs(of folderID: String) -> Set<String> {
    var result: Set<String> = []
    var frontier = [folderID]
    while let parentID = frontier.popLast() {
      let children = document.folders.filter { $0.parentID == parentID }.map(\.id)
      for child in children where result.insert(child).inserted { frontier.append(child) }
    }
    return result
  }

  private static func inventoryPathComponents(_ path: String) throws -> [String] {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    var components = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    if components.first == "Inventory" { components.removeFirst() }
    guard !components.isEmpty else { return [] }
    for component in components { try validateFolderName(component) }
    return components
  }

  private static func validateFolderName(_ name: String) throws {
    guard !name.isEmpty, name.count <= 128,
      !name.contains(where: { $0.isNewline || $0 == "/" || $0 == "\\" }),
      name != ".", name != ".."
    else {
      throw MikroKhorosError.runtime(
        "inventory.folder_name_invalid",
        "Inventory folder names must be a single path segment of at most 128 characters"
      )
    }
  }

  private static func validateInventoryName(_ name: String) throws {
    guard !name.isEmpty, name.count <= 128, !name.contains(where: \.isNewline) else {
      throw MikroKhorosError.runtime(
        "inventory.name_invalid",
        "Inventory object names must be a non-empty single line of at most 128 characters"
      )
    }
  }

  private func validateDocument() throws {
    guard document.schemaVersion == InventoryDocument.currentSchemaVersion else {
      throw MikroKhorosError.persistence("unsupported Inventory schema version")
    }
    try InventoryDocument.validateWorldReferenceIdentities(document.worldReferences)
    let packageKeys = document.packages.map { "\($0.manifest.id)@\($0.manifest.version)" }
    guard Set(packageKeys).count == packageKeys.count else {
      throw MikroKhorosError.persistence("Inventory contains duplicate package versions")
    }
    do {
      for package in document.packages { try runtimeRegistry.validate(package.manifest) }
    } catch {
      throw MikroKhorosError.persistence("Inventory contains a package with no trusted runtime")
    }
    let objectIDs = document.objects.map(\.id)
    guard Set(objectIDs).count == objectIDs.count else {
      throw MikroKhorosError.persistence("Inventory contains duplicate object identities")
    }
    guard document.folders.count <= limits.maximumInventoryFolders else {
      throw MikroKhorosError.persistence("Inventory contains too many folders")
    }
    let folderIDs = document.folders.map(\.id)
    guard Set(folderIDs).count == folderIDs.count,
      let root = document.folders.first(where: { $0.id == InventoryFolderIdentity.rootID }),
      root.parentID == nil,
      document.folders.filter({ $0.parentID == nil }).count == 1
    else {
      throw MikroKhorosError.persistence("Inventory contains an invalid root folder")
    }
    for folder in document.folders where folder.id != InventoryFolderIdentity.rootID {
      guard InventoryIdentity.isValid(folder.id), let parentID = folder.parentID,
        document.folders.contains(where: { $0.id == parentID })
      else {
        throw MikroKhorosError.persistence("Inventory contains invalid folder lineage")
      }
      do { try Self.validateFolderName(folder.name) } catch {
        throw MikroKhorosError.persistence("Inventory contains an invalid folder name")
      }
      var visited = Set([folder.id])
      var ancestorID: String? = parentID
      while let id = ancestorID {
        guard visited.insert(id).inserted,
          let ancestor = document.folders.first(where: { $0.id == id })
        else {
          throw MikroKhorosError.persistence("Inventory contains a folder cycle")
        }
        ancestorID = ancestor.parentID
      }
    }
    let siblingKeys = document.folders.compactMap { folder -> String? in
      guard let parentID = folder.parentID else { return nil }
      return "\(parentID)\u{0}\(folder.name)"
    }
    guard Set(siblingKeys).count == siblingKeys.count else {
      throw MikroKhorosError.persistence("Inventory contains duplicate sibling folder names")
    }
    for object in document.objects {
      guard InventoryIdentity.isValid(object.id), object.revision > 0,
        !object.name.isEmpty, object.name.count <= 128,
        !object.name.contains(where: \.isNewline),
        document.folders.contains(where: { $0.id == object.folderID }),
        let package = document.packages.first(where: { $0.contentHash == object.packageHash }),
        package.manifest.id == object.packageID,
        package.manifest.version == object.packageVersion,
        object.grantedCapabilities.isSubset(of: object.requestedCapabilities),
        object.requestedCapabilities == package.manifest.requestedCapabilities
      else {
        throw MikroKhorosError.persistence("Inventory contains invalid package lineage")
      }
      if let provenance = object.forkProvenance {
        guard InventoryIdentity.isValid(provenance.parentInventoryObjectID),
          provenance.parentRevision > 0
        else {
          throw MikroKhorosError.persistence("Inventory contains invalid fork provenance")
        }
      }
      if let binding = object.worldBinding {
        guard InventoryIdentity.isValid(binding.worldID) else {
          throw MikroKhorosError.persistence("Inventory contains an invalid world binding")
        }
      }
      if let source = object.templateSource {
        guard !source.templateID.isEmpty, source.templateID.count <= 128,
          !source.templateVersion.isEmpty, source.templateVersion.count <= 64,
          !source.componentKey.isEmpty, source.componentKey.count <= 128,
          !source.templateID.contains(where: { $0.isWhitespace || $0.isNewline }),
          !source.componentKey.contains(where: { $0.isWhitespace || $0.isNewline })
        else {
          throw MikroKhorosError.persistence(
            "Inventory contains invalid template-source provenance"
          )
        }
      }
      try validateKnownConfiguration(object.configuration, manifest: package.manifest)
      let secretFields = Set(
        package.manifest.management.fields.filter { $0.kind == .secret }.map(\.id))
      guard Set(object.credentialHandles.keys).isSubset(of: secretFields),
        object.credentialHandles.values.allSatisfy(InventoryIdentity.isValid)
      else {
        throw MikroKhorosError.persistence("Inventory contains invalid credential handles")
      }
    }
    let activeTemplateKeys = document.objects.compactMap { object -> String? in
      guard !object.deleted, let source = object.templateSource else { return nil }
      return "\(source.templateID)\u{0}\(source.templateVersion)\u{0}\(source.componentKey)"
    }
    guard Set(activeTemplateKeys).count == activeTemplateKeys.count else {
      throw MikroKhorosError.persistence(
        "Inventory contains duplicate canonical template sources"
      )
    }
  }

  private static func loadDocument(from url: URL, maximumBytes: Int) throws -> InventoryDocument {
    guard FileManager.default.fileExists(atPath: url.path) else { return InventoryDocument() }
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      if let size = values.fileSize, size > maximumBytes {
        throw MikroKhorosError.runtime(
          "inventory.store_too_large",
          "the Inventory document exceeds the configured byte limit",
          details: ["limit": String(maximumBytes)]
        )
      }
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(
        InventoryDocument.self,
        from: Data(contentsOf: url, options: [.mappedIfSafe])
      )
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.persistence("could not read the Inventory document")
    }
  }

  private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let left = try! ObjectPackageSemanticVersion(lhs)
    let right = try! ObjectPackageSemanticVersion(rhs)
    if left < right { return .orderedAscending }
    if right < left { return .orderedDescending }
    return .orderedSame
  }

  private static func applyManagementAction(
    _ action: DeclarativeAction,
    inputs: [String],
    configuration: [String: JSONValue],
    state: inout [String: JSONValue]
  ) throws -> JSONValue {
    switch action.kind {
    case .return:
      return action.value ?? .null
    case .get:
      return state[action.key!] ?? configuration[action.key!] ?? .null
    case .set:
      let value = DeclarativeObject.coerce(inputs[action.argument ?? 0])
      state[action.key!] = value
      return value
    case .append:
      var values = state[action.key!]?.arrayValue ?? []
      values.append(DeclarativeObject.coerce(inputs[action.argument ?? 0]))
      state[action.key!] = .array(values)
      return .number(Double(values.count))
    case .increment:
      let current = state[action.key!]?.numberValue ?? 0
      let amount: Double
      if let index = action.argument {
        guard let parsed = Double(inputs[index]), parsed.isFinite else {
          throw MikroKhorosError.runtime(
            "inventory.action_input_invalid",
            "the management action requires a finite number"
          )
        }
        amount = parsed
      } else {
        amount = action.amount ?? 1
      }
      guard (current + amount).isFinite else {
        throw MikroKhorosError.runtime(
          "inventory.action_result_invalid",
          "the management action produced a non-finite number"
        )
      }
      state[action.key!] = .number(current + amount)
      return state[action.key!]!
    case .toggle:
      let value = !(state[action.key!]?.boolValue ?? false)
      state[action.key!] = .bool(value)
      return .bool(value)
    case .report:
      throw MikroKhorosError.runtime(
        "inventory.action_invalid",
        "Inventory management actions cannot emit world-object reports"
      )
    }
  }

  private static func validateManagementInput(
    _ raw: String,
    type: ManagementFieldKind,
    choices: [String],
    maximumCharacters: Int,
    parameter: String
  ) throws {
    guard raw.count <= maximumCharacters else {
      throw MikroKhorosError.runtime(
        "inventory.action_input_invalid",
        "the management action input exceeds the configured field limit",
        details: ["input": parameter, "limit": String(maximumCharacters)]
      )
    }
    let valid: Bool
    switch type {
    case .text:
      valid = true
    case .url:
      valid =
        URL(string: raw).flatMap(\.scheme).map {
          ["http", "https"].contains($0.lowercased())
        } == true
    case .path:
      valid = !raw.isEmpty && !raw.contains("\0")
    case .choice:
      valid = choices.contains(raw)
    case .secret:
      valid = false
    case .integer:
      valid = Int(raw) != nil
    case .decimal:
      valid = Double(raw).map(\.isFinite) == true
    case .boolean:
      valid = ["true", "false", "1", "0", "yes", "no"].contains(raw.lowercased())
    }
    guard valid else {
      throw MikroKhorosError.runtime(
        "inventory.action_input_invalid",
        "the management action input does not match its declared type",
        details: ["input": parameter, "type": type.rawValue]
      )
    }
  }

  private static func validateStructuredResult(
    _ output: JSONValue,
    contract: [String: ManagementFieldKind],
    code: String
  ) throws {
    guard !contract.isEmpty else { return }
    guard case .object(let values) = output,
      Set(values.keys) == Set(contract.keys),
      contract.allSatisfy({ key, kind in
        guard let value = values[key] else { return false }
        switch (kind, value) {
        case (.integer, .number(let number)):
          return number.isFinite && number.rounded() == number
        case (.decimal, .number(let number)):
          return number.isFinite
        case (.boolean, .bool):
          return true
        case (.text, .string), (.choice, .string), (.url, .string), (.path, .string):
          return true
        default:
          return false
        }
      })
    else {
      throw MikroKhorosError.runtime(
        code, "the structured result does not match its declared contract")
    }
  }
}

enum BoundedPackageFile {
  static func read(_ url: URL, maximumBytes: Int) throws -> Data {
    guard maximumBytes > 0 else {
      throw MikroKhorosError.configuration("maximum-package-bytes must be positive")
    }
    let handle: FileHandle
    do {
      handle = try FileHandle(forReadingFrom: url)
    } catch {
      throw MikroKhorosError.runtime(
        "object_package.read_failed",
        "the local object package could not be opened"
      )
    }
    defer { try? handle.close() }
    var data = Data()
    data.reserveCapacity(min(maximumBytes, 64 * 1_024))
    do {
      while true {
        let remaining = maximumBytes - data.count
        let requestCount =
          remaining == Int.max ? 64 * 1_024 : min(64 * 1_024, remaining + 1)
        guard let chunk = try handle.read(upToCount: requestCount), !chunk.isEmpty else {
          return data
        }
        guard chunk.count <= remaining else {
          throw MikroKhorosError.runtime(
            "object_package.too_large",
            "the object package exceeds the configured byte limit",
            details: ["limit": String(maximumBytes)]
          )
        }
        data.append(chunk)
      }
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.runtime(
        "object_package.read_failed",
        "the local object package could not be read"
      )
    }
  }
}

public enum ObjectPackageDownloader {
  public static func download(_ url: URL, maximumBytes: Int) async throws -> Data {
    guard maximumBytes > 0 else {
      throw MikroKhorosError.configuration("maximum-package-bytes must be positive")
    }
    try validate(url)
    return try await BoundedPackageDownload(url: url, maximumBytes: maximumBytes).start()
  }

  fileprivate static func validate(_ url: URL) throws {
    let scheme = url.scheme?.lowercased()
    if scheme == "https" { return }
    if scheme == "http", let host = url.host?.lowercased(),
      host == "localhost" || host == "127.0.0.1" || host == "::1"
    {
      return
    }
    throw MikroKhorosError.runtime(
      "object_package.url_rejected",
      "remote packages require HTTPS; plaintext HTTP is limited to loopback development",
      suggestions: ["use an HTTPS URL or a loopback development server"]
    )
  }
}

private final class BoundedPackageDownload: NSObject, URLSessionDataDelegate,
  URLSessionTaskDelegate, @unchecked Sendable
{
  private let url: URL
  private let maximumBytes: Int
  private let lock = NSLock()
  private var data = Data()
  private var continuation: CheckedContinuation<Data, Error>?
  private var session: URLSession?

  init(url: URL, maximumBytes: Int) {
    self.url = url
    self.maximumBytes = maximumBytes
  }

  func start() async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      lock.lock()
      self.continuation = continuation
      lock.unlock()
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 60
      configuration.timeoutIntervalForResource = 60
      let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
      self.session = session
      session.dataTask(with: url).resume()
    }
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
    else {
      completionHandler(.cancel)
      finish(
        throwing: MikroKhorosError.runtime(
          "object_package.download_failed",
          "the package server returned an unsuccessful response"
        )
      )
      return
    }
    guard
      response.expectedContentLength < 0
        || response.expectedContentLength <= Int64(maximumBytes)
    else {
      completionHandler(.cancel)
      finish(throwing: tooLargeError)
      return
    }
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
    lock.lock()
    let exceeds = data.count > maximumBytes - chunk.count
    if !exceeds { data.append(chunk) }
    lock.unlock()
    if exceeds {
      dataTask.cancel()
      finish(throwing: tooLargeError)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    do {
      guard let redirected = request.url else {
        throw MikroKhorosError.runtime(
          "object_package.url_rejected",
          "the package redirect has no valid destination"
        )
      }
      try ObjectPackageDownloader.validate(redirected)
      completionHandler(request)
    } catch {
      completionHandler(nil)
      finish(throwing: error)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    if let error {
      finish(throwing: error)
    } else {
      lock.lock()
      let result = data
      lock.unlock()
      finish(returning: result)
    }
  }

  private var tooLargeError: MikroKhorosError {
    MikroKhorosError.runtime(
      "object_package.too_large",
      "the object package exceeds the configured byte limit",
      details: ["limit": String(maximumBytes)]
    )
  }

  private func finish(returning data: Data) {
    lock.lock()
    let continuation = self.continuation
    self.continuation = nil
    let session = self.session
    self.session = nil
    lock.unlock()
    session?.finishTasksAndInvalidate()
    continuation?.resume(returning: data)
  }

  private func finish(throwing error: Error) {
    lock.lock()
    let continuation = self.continuation
    self.continuation = nil
    let session = self.session
    self.session = nil
    lock.unlock()
    session?.invalidateAndCancel()
    continuation?.resume(throwing: error)
  }
}

public enum InventoryIdentity {
  public static func make() -> String {
    UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
  }

  public static func isValid(_ value: String) -> Bool {
    value.count == 32 && value.allSatisfy { $0.isHexDigit }
  }
}

public final class ProductStateLock {
  private let url: URL
  private var acquired = false

  public init(root: URL = MikroKhorosPaths.root) throws {
    url = root.appendingPathComponent("command.lock", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for _ in 0..<600 {
      do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(
          to: url.appendingPathComponent("owner", isDirectory: false),
          options: [.atomic]
        )
        acquired = true
        return
      } catch {
        if Self.removeAbandonedLock(at: url) { continue }
        Thread.sleep(forTimeInterval: 0.05)
      }
    }
    throw MikroKhorosError.persistence(
      "another khoros process is still using persistent product state"
    )
  }

  deinit {
    if acquired { try? FileManager.default.removeItem(at: url) }
  }

  private static func removeAbandonedLock(at url: URL) -> Bool {
    let ownerURL = url.appendingPathComponent("owner", isDirectory: false)
    guard let data = try? Data(contentsOf: ownerURL),
      let text = String(data: data, encoding: .utf8),
      let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
      pid > 0,
      !processIsRunning(pid)
    else { return false }
    do {
      try FileManager.default.removeItem(at: url)
      return true
    } catch {
      return false
    }
  }

  private static func processIsRunning(_ pid: Int32) -> Bool {
    #if os(Windows)
      let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, DWORD(pid))
      guard let process else { return false }
      defer { CloseHandle(process) }
      var code: DWORD = 0
      return GetExitCodeProcess(process, &code) && code == STILL_ACTIVE
    #else
      if kill(pid, 0) == 0 { return true }
      return errno == EPERM
    #endif
  }
}

public enum AtomicFileStore {
  public static func write(_ data: Data, to url: URL, lockURL: URL) throws {
    let manager = FileManager.default
    let directory = url.deletingLastPathComponent()
    do {
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
      try withLock(lockURL) {
        let temporary = directory.appendingPathComponent(
          ".\(url.lastPathComponent).\(InventoryIdentity.make()).tmp",
          isDirectory: false
        )
        defer { try? manager.removeItem(at: temporary) }
        try data.write(to: temporary, options: [])
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize()
        try handle.close()
        #if !os(Windows)
          try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        #endif
        if manager.fileExists(atPath: url.path) {
          #if os(Windows)
            try replaceWindowsFile(temporary, at: url)
          #elseif os(Linux)
            try replaceLinuxFile(temporary, at: url)
          #else
            _ = try manager.replaceItemAt(url, withItemAt: temporary)
          #endif
        } else {
          try manager.moveItem(at: temporary, to: url)
        }
      }
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.persistence("could not atomically write persistent state")
    }
  }

  #if os(Windows)
    private static func replaceWindowsFile(_ source: URL, at destination: URL) throws {
      let didReplace = source.path.withCString(encodedAs: UTF16.self) { sourcePath in
        destination.path.withCString(encodedAs: UTF16.self) { destinationPath in
          MoveFileExW(
            sourcePath,
            destinationPath,
            DWORD(MOVEFILE_REPLACE_EXISTING) | DWORD(MOVEFILE_WRITE_THROUGH)
          )
        }
      }
      guard didReplace else {
        throw MikroKhorosError.persistence("could not atomically write persistent state")
      }
    }
  #endif

  #if os(Linux)
    private static func replaceLinuxFile(_ source: URL, at destination: URL) throws {
      let didReplace = source.path.withCString { sourcePath in
        destination.path.withCString { destinationPath in
          rename(sourcePath, destinationPath) == 0
        }
      }
      guard didReplace else {
        throw MikroKhorosError.persistence("could not atomically write persistent state")
      }
    }
  #endif

  private static func withLock<T>(_ url: URL, body: () throws -> T) throws -> T {
    let manager = FileManager.default
    var acquired = false
    for _ in 0..<100 {
      do {
        try manager.createDirectory(at: url, withIntermediateDirectories: false)
        acquired = true
        break
      } catch {
        Thread.sleep(forTimeInterval: 0.05)
      }
    }
    guard acquired else {
      throw MikroKhorosError.persistence("persistent state is busy in another process")
    }
    defer { try? manager.removeItem(at: url) }
    return try body()
  }
}

enum SHA256Digest {
  private static let constants: [UInt32] = [
    0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5, 0x3956_c25b, 0x59f1_11f1,
    0x923f_82a4, 0xab1c_5ed5, 0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3,
    0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174, 0xe49b_69c1, 0xefbe_4786,
    0x0fc1_9dc6, 0x240c_a1cc, 0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
    0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7, 0xc6e0_0bf3, 0xd5a7_9147,
    0x06ca_6351, 0x1429_2967, 0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13,
    0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85, 0xa2bf_e8a1, 0xa81a_664b,
    0xc24b_8b70, 0xc76c_51a3, 0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
    0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5, 0x391c_0cb3, 0x4ed8_aa4a,
    0x5b9c_ca4f, 0x682e_6ff3, 0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208,
    0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2,
  ]

  static func hex(_ data: Data) -> String {
    var message = [UInt8](data)
    let bitLength = UInt64(message.count) * 8
    message.append(0x80)
    while message.count % 64 != 56 { message.append(0) }
    message.append(contentsOf: withUnsafeBytes(of: bitLength.bigEndian, Array.init))
    var hash: [UInt32] = [
      0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a,
      0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19,
    ]
    for start in stride(from: 0, to: message.count, by: 64) {
      var words = [UInt32](repeating: 0, count: 64)
      for index in 0..<16 {
        let offset = start + index * 4
        words[index] =
          UInt32(message[offset]) << 24 | UInt32(message[offset + 1]) << 16
          | UInt32(message[offset + 2]) << 8 | UInt32(message[offset + 3])
      }
      for index in 16..<64 {
        let s0 =
          rotate(words[index - 15], 7) ^ rotate(words[index - 15], 18)
          ^ (words[index - 15] >> 3)
        let s1 =
          rotate(words[index - 2], 17) ^ rotate(words[index - 2], 19)
          ^ (words[index - 2] >> 10)
        words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
      }
      var a = hash[0]
      var b = hash[1]
      var c = hash[2]
      var d = hash[3]
      var e = hash[4]
      var f = hash[5]
      var g = hash[6]
      var h = hash[7]
      for index in 0..<64 {
        let s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
        let choice = (e & f) ^ ((~e) & g)
        let t1 = h &+ s1 &+ choice &+ constants[index] &+ words[index]
        let s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
        let majority = (a & b) ^ (a & c) ^ (b & c)
        let t2 = s0 &+ majority
        h = g
        g = f
        f = e
        e = d &+ t1
        d = c
        c = b
        b = a
        a = t1 &+ t2
      }
      hash[0] &+= a
      hash[1] &+= b
      hash[2] &+= c
      hash[3] &+= d
      hash[4] &+= e
      hash[5] &+= f
      hash[6] &+= g
      hash[7] &+= h
    }
    return hash.map { String(format: "%08x", $0) }.joined()
  }

  private static func rotate(_ value: UInt32, _ amount: UInt32) -> UInt32 {
    (value >> amount) | (value << (32 - amount))
  }
}
