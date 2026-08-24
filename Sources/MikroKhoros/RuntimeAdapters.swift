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

public enum ObjectExternalEffect: String, Codable, CaseIterable, Sendable {
  case userFolder = "user-folder"
  case network
  case userMachine = "user-machine"
}

public struct WorldObjectManagementContext: @unchecked Sendable {
  public let worldID: String
  public let objectID: String
  public let lineage: ObjectLineage
  public let instanceRevision: Int
  public let capabilities: ObjectCapabilityBroker
  public let object: MikroObject
  public let userFolders: ObjectUserFolderService?
  let harness: Harness

  init(object: MikroObject, harness: Harness) throws {
    guard let lineage = object.lineage else {
      throw MikroKhorosError.runtime(
        "object.management_unavailable", "the selected object has no package lineage")
    }
    worldID = harness.world.hash
    objectID = object.hash
    self.lineage = lineage
    instanceRevision = object.instanceRevision
    capabilities = ObjectCapabilityBroker(granted: object.capturedCapabilities)
    self.object = object
    userFolders = (object as? ObjectUserFolderServiceProviding)?.makeObjectUserFolderService()
    self.harness = harness
  }

  public func recordMutation() throws {
    try harness.notifyObjectStateChanged(object)
  }
}

public protocol ObjectRuntimeAdapter: Sendable {
  var id: String { get }
  var version: String { get }
  var packageIDs: Set<String> { get }

  func validate(manifest: ObjectPackageManifest) throws
  func externalEffects(for manifest: ObjectPackageManifest) throws -> Set<ObjectExternalEffect>
  func makeDefaultManagementState(manifest: ObjectPackageManifest) throws -> [String: JSONValue]
  func runInventoryAction(
    _ action: ManagementAction,
    inputs: [String],
    record: inout InventoryObjectRecord,
    limits: RuntimeLimits
  ) throws -> JSONValue
  func renderInventoryView(
    _ view: ManagementView,
    record: InventoryObjectRecord,
    limits: RuntimeLimits
  ) throws -> JSONValue
  func captureDeploymentState(
    record: InventoryObjectRecord,
    limits: RuntimeLimits
  ) throws -> [String: JSONValue]
  func instantiate(
    snapshot: ObjectDeploymentSnapshot,
    limits: RuntimeLimits,
    replaying: Bool
  ) throws -> MikroObject
  func runWorldAction(
    _ action: ManagementAction,
    inputs: [String],
    context: WorldObjectManagementContext,
    limits: RuntimeLimits
  ) throws -> JSONValue
  func renderWorldView(
    _ view: ManagementView,
    context: WorldObjectManagementContext,
    limits: RuntimeLimits
  ) throws -> JSONValue
}

public final class ObjectRuntimeRegistry: @unchecked Sendable {
  public static let declarativeAdapterID = "org.mikrokhoros.runtime.declarative"
  public static let declarativeAdapterVersion = "1"

  private var adaptersByPackage: [String: any ObjectRuntimeAdapter] = [:]
  private let lock = NSLock()

  public init(adapters: [any ObjectRuntimeAdapter] = []) throws {
    for adapter in adapters { try register(adapter) }
  }

  public static func declarativeOnly() -> ObjectRuntimeRegistry {
    try! ObjectRuntimeRegistry()
  }

  public static func installedCLI() -> ObjectRuntimeRegistry {
    try! ObjectRuntimeRegistry(adapters: [FirstPartyObjectRuntimeAdapter()])
  }

  public func register(_ adapter: any ObjectRuntimeAdapter) throws {
    guard !adapter.id.isEmpty, !adapter.version.isEmpty, !adapter.packageIDs.isEmpty else {
      throw MikroKhorosError.objectPackage("runtime adapter identity is invalid")
    }
    lock.lock()
    defer { lock.unlock() }
    for packageID in adapter.packageIDs {
      guard adaptersByPackage[packageID] == nil else {
        throw MikroKhorosError.objectPackage(
          "a runtime adapter is already registered for \(packageID)"
        )
      }
    }
    for packageID in adapter.packageIDs { adaptersByPackage[packageID] = adapter }
  }

  public func validate(_ manifest: ObjectPackageManifest) throws {
    switch manifest.runtime {
    case .declarative:
      return
    case .nativeSwift:
      let adapter = try adapter(for: manifest)
      try adapter.validate(manifest: manifest)
    case .javascript:
      throw unavailable(manifest)
    }
  }

  public func adapter(for manifest: ObjectPackageManifest) throws -> any ObjectRuntimeAdapter {
    lock.lock()
    let adapter = adaptersByPackage[manifest.id]
    lock.unlock()
    guard manifest.runtime == .nativeSwift, let adapter else { throw unavailable(manifest) }
    return adapter
  }

  public func adapterIdentity(for manifest: ObjectPackageManifest) throws -> (String, String) {
    if manifest.runtime == .declarative {
      return (Self.declarativeAdapterID, Self.declarativeAdapterVersion)
    }
    let adapter = try adapter(for: manifest)
    return (adapter.id, adapter.version)
  }

  public func externalEffects(
    for manifest: ObjectPackageManifest
  ) throws -> Set<ObjectExternalEffect> {
    guard manifest.runtime == .nativeSwift else { return [] }
    return try adapter(for: manifest).externalEffects(for: manifest)
  }

  private func unavailable(_ manifest: ObjectPackageManifest) -> MikroKhorosError {
    MikroKhorosError.runtime(
      "object_package.runtime_unavailable",
      "this object package has no trusted runtime adapter in the current host",
      details: ["package": manifest.id, "runtime": manifest.runtime.rawValue],
      suggestions: ["use a supported package or register its exact adapter in the embedding host"]
    )
  }
}
