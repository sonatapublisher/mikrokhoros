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

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// An embeddable compatibility façade. The installed CLI uses `InventoryStore`;
/// both decode the same unified `ObjectPackageManifest`.
public final class ObjectPackageRegistry {
  private var packages: [String: ObjectPackageManifest] = [:]

  public init() {}

  public var types: [String] { packages.values.map(\.object.type).sorted() }

  @discardableResult
  public func install(data: Data, maximumBytes: Int = RuntimeLimits.defaults.maximumPackageBytes)
    throws -> String
  {
    guard data.count <= maximumBytes else {
      throw MikroKhorosError.objectPackage("object package exceeds the configured byte limit")
    }
    let manifest: ObjectPackageManifest
    do {
      manifest = try JSONDecoder().decode(ObjectPackageManifest.self, from: data)
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.objectPackage("object package is not valid manifest JSON")
    }
    try manifest.validateRuntimeAvailability()
    let key = Self.key(manifest.id, manifest.version)
    guard packages[key] == nil else {
      throw MikroKhorosError.objectPackage("this object package version is already installed")
    }
    packages[key] = manifest
    return manifest.id
  }

  @discardableResult
  public func install(from url: URL, maximumBytes: Int = RuntimeLimits.defaults.maximumPackageBytes)
    throws -> String
  {
    guard url.isFileURL else {
      throw MikroKhorosError.objectPackage("use the asynchronous remote package installer for URLs")
    }
    return try install(
      data: BoundedPackageFile.read(url, maximumBytes: maximumBytes),
      maximumBytes: maximumBytes
    )
  }

  @discardableResult
  public func install(path: String, maximumBytes: Int = RuntimeLimits.defaults.maximumPackageBytes)
    throws -> String
  {
    try install(from: URL(fileURLWithPath: path), maximumBytes: maximumBytes)
  }

  public func remove(_ packageID: String, version: String? = nil) throws {
    let matches = packages.keys.filter { key in
      packages[key]?.id == packageID && (version == nil || packages[key]?.version == version)
    }
    guard !matches.isEmpty else {
      throw MikroKhorosError.objectPackage("object package was not found")
    }
    for key in matches { packages.removeValue(forKey: key) }
  }

  public func create(
    _ packageOrType: String,
    version: String? = nil,
    name: String? = nil,
    hash: String? = nil
  ) throws -> DeclarativeObject {
    let matches = packages.values.filter {
      ($0.id == packageOrType || $0.object.type == packageOrType)
        && (version == nil || $0.version == version)
    }
    guard matches.count == 1, let manifest = matches.first else {
      throw MikroKhorosError.objectPackage(
        matches.isEmpty ? "object package is not installed" : "object package version is ambiguous"
      )
    }
    let root = try DeclarativeObject(manifest: manifest, name: name, hash: hash)
    var objects: [String: DeclarativeObject] = ["root": root]
    var pending = manifest.ownedObjects
    while !pending.isEmpty {
      var progressed = false
      for index in pending.indices.reversed() {
        let definition = pending[index]
        guard let parent = objects[definition.parent], let space = parent.container else {
          continue
        }
        let child = try DeclarativeObject(
          manifest: manifest,
          definition: definition.object
        )
        try space.place(child, at: definition.coordinate)
        objects[definition.id] = child
        pending.remove(at: index)
        progressed = true
      }
      guard progressed else {
        throw MikroKhorosError.objectPackage("object package owned-object graph is disconnected")
      }
    }
    return root
  }

  private static func key(_ id: String, _ version: String) -> String { "\(id)@\(version)" }
}

public final class DeclarativeObject: MikroObject {
  public private(set) var privateState: [String: JSONValue]
  public let configuration: [String: JSONValue]
  public let credentialHandles: [String: String]
  public let packageManifest: ObjectPackageManifest
  public let objectDefinition: DeclarativeObjectDefinition

  public init(
    manifest: ObjectPackageManifest,
    definition: DeclarativeObjectDefinition? = nil,
    name: String? = nil,
    configuration: [String: JSONValue] = [:],
    credentialHandles: [String: String] = [:],
    privateState: [String: JSONValue]? = nil,
    currentDurability: Int? = nil,
    capturedCapabilities: Set<ObjectCapability> = [],
    lineage: ObjectLineage? = nil,
    hash: String? = nil
  ) throws {
    try manifest.validateRuntimeAvailability()
    let definition = definition ?? manifest.object
    self.packageManifest = manifest
    self.objectDefinition = definition
    self.configuration = configuration
    self.credentialHandles = credentialHandles
    self.privateState = privateState ?? definition.state
    try super.init(
      typeName: definition.type,
      name: name ?? definition.name,
      summary: definition.summary,
      publicData: definition.publicData,
      durability: definition.durability,
      origin: .package,
      invocationAccess: definition.invocationAccess,
      capturedCapabilities: capturedCapabilities,
      lineage: lineage,
      credentialHandles: credentialHandles,
      hash: hash
    )
    if let currentDurability { restoreDurability(currentDurability) }
    if definition.container { try addContainerCapability() }
    for (functionName, function) in definition.functions {
      try registerFunction(
        name: functionName,
        summary: function.summary,
        parameters: function.parameters,
        durabilityCost: function.durabilityCost,
        audience: function.audience
      ) { context, arguments in
        let object = context.object as! DeclarativeObject
        guard arguments.count == function.parameters.count else {
          throw MikroKhorosError.function(
            "expected exactly \(function.parameters.count) argument(s), received \(arguments.count)"
          )
        }
        let broker = ObjectCapabilityBroker(granted: object.capturedCapabilities)
        for capability in function.requiredCapabilities { try broker.require(capability) }
        return try object.apply(function.action, arguments: arguments, context: context)
      }
    }
  }

  private func apply(
    _ action: DeclarativeAction,
    arguments: [String],
    context: TrustedInvocationContext
  ) throws -> String {
    switch action.kind {
    case .return:
      return action.value?.description ?? ""
    case .get:
      return (privateState[action.key!] ?? configuration[action.key!])?.description ?? "null"
    case .set:
      let index = action.argument ?? 0
      privateState[action.key!] = Self.coerce(arguments[index])
      return privateState[action.key!]!.description
    case .append:
      let index = action.argument ?? 0
      let value = Self.coerce(arguments[index])
      var array: [JSONValue]
      if let existing = privateState[action.key!] {
        guard let existingArray = existing.arrayValue else {
          throw MikroKhorosError.function("private state value is not a list")
        }
        array = existingArray
      } else {
        array = []
      }
      array.append(value)
      privateState[action.key!] = .array(array)
      return String(array.count)
    case .increment:
      let current = try numericState(action.key!)
      let amount: Double
      if let index = action.argument {
        guard let parsed = Double(arguments[index]), parsed.isFinite else {
          throw MikroKhorosError.function("increment requires a finite numeric amount")
        }
        amount = parsed
      } else {
        amount = action.amount ?? 1
      }
      let result = current + amount
      guard result.isFinite else {
        throw MikroKhorosError.function("increment result is not finite")
      }
      privateState[action.key!] = .number(result)
      return JSONValue.number(result).description
    case .toggle:
      let current: Bool
      if let existing = privateState[action.key!] {
        guard let value = existing.boolValue else {
          throw MikroKhorosError.function("toggle requires Boolean state")
        }
        current = value
      } else {
        current = false
      }
      privateState[action.key!] = .bool(!current)
      return JSONValue.bool(!current).description
    case .report:
      let body = action.value?.description ?? arguments.first ?? ""
      try context.harness.emitHumanReport(
        from: self,
        type: action.key!,
        title: name,
        body: body,
        payload: action.value ?? .null
      )
      return "report emitted"
    }
  }

  private func numericState(_ key: String) throws -> Double {
    guard let existing = privateState[key] else { return 0 }
    guard let number = existing.numberValue else {
      throw MikroKhorosError.function("increment requires numeric state")
    }
    return number
  }

  static func coerce(_ value: String) -> JSONValue {
    guard let data = value.data(using: .utf8),
      let decoded = try? JSONDecoder().decode(JSONValue.self, from: data)
    else { return .string(value) }
    return decoded
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try DeclarativeObject(
      manifest: packageManifest,
      definition: objectDefinition,
      name: name,
      configuration: configuration,
      credentialHandles: credentialHandles,
      capturedCapabilities: capturedCapabilities,
      lineage: lineage,
      hash: hash
    )
  }
}
