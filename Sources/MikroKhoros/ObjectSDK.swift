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

private struct ObjectPackageCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

private func rejectUnknownPackageKeys(
  from decoder: Decoder,
  allowed: Set<String>,
  context: String
) throws {
  let container = try decoder.container(keyedBy: ObjectPackageCodingKey.self)
  let unknown = container.allKeys.map(\.stringValue).filter { !allowed.contains($0) }.sorted()
  guard unknown.isEmpty else {
    throw DecodingError.dataCorrupted(
      .init(
        codingPath: decoder.codingPath,
        debugDescription: "\(context) has unknown field(s): \(unknown.joined(separator: ", "))"
      )
    )
  }
}

private func validatePackageIdentifier(_ value: String, label: String) throws {
  guard !value.isEmpty, value.count <= 128,
    value.allSatisfy({ $0.isLetter || $0.isNumber || "-._".contains($0) })
  else {
    throw MikroKhorosError.objectPackage(
      "\(label) must use 1...128 letters, numbers, dash, dot, or underscore"
    )
  }
}

private func validatePackageLine(_ value: String, label: String, limit: Int = 512) throws {
  guard !value.isEmpty, value.count <= limit, !value.contains(where: { $0.isNewline }) else {
    throw MikroKhorosError.objectPackage("\(label) must be one line of at most \(limit) characters")
  }
}

struct ObjectPackageSemanticVersion: Comparable {
  private enum Identifier: Equatable {
    case numeric(String)
    case text(String)
  }

  private let core: [String]
  private let prerelease: [Identifier]?

  init(_ value: String) throws {
    guard !value.isEmpty, value.count <= 128 else {
      throw MikroKhorosError.objectPackage("object package version is invalid")
    }
    let buildParts = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
    guard buildParts.count <= 2,
      buildParts.count == 1
        || Self.validIdentifiers(String(buildParts[1]), numericLeadingZero: true)
    else {
      throw MikroKhorosError.objectPackage("object package version is invalid")
    }
    let releaseParts = buildParts[0].split(
      separator: "-",
      maxSplits: 1,
      omittingEmptySubsequences: false
    )
    let numbers = releaseParts[0].split(separator: ".", omittingEmptySubsequences: false)
    guard numbers.count == 3 else {
      throw MikroKhorosError.objectPackage("object package version is invalid")
    }
    var parsedCore: [String] = []
    for number in numbers {
      let text = String(number)
      guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }),
        text == "0" || !text.hasPrefix("0")
      else {
        throw MikroKhorosError.objectPackage("object package version is invalid")
      }
      parsedCore.append(text)
    }
    core = parsedCore
    if releaseParts.count == 2 {
      let raw = String(releaseParts[1])
      guard Self.validIdentifiers(raw, numericLeadingZero: false) else {
        throw MikroKhorosError.objectPackage("object package version is invalid")
      }
      prerelease = raw.split(separator: ".").map { identifier in
        let value = String(identifier)
        if value.allSatisfy({ $0.isASCII && $0.isNumber }) {
          return .numeric(value)
        }
        return .text(value)
      }
    } else {
      prerelease = nil
    }
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.core != rhs.core {
      for index in 0..<3 where lhs.core[index] != rhs.core[index] {
        return compareNumeric(lhs.core[index], rhs.core[index]) == .orderedAscending
      }
    }
    switch (lhs.prerelease, rhs.prerelease) {
    case (nil, nil): return false
    case (.some, nil): return true
    case (nil, .some): return false
    case (.some(let left), .some(let right)):
      for index in 0..<min(left.count, right.count) {
        if left[index] == right[index] { continue }
        switch (left[index], right[index]) {
        case (.numeric(let lhs), .numeric(let rhs)):
          return compareNumeric(lhs, rhs) == .orderedAscending
        case (.numeric, .text): return true
        case (.text, .numeric): return false
        case (.text(let lhs), .text(let rhs)): return lhs < rhs
        }
      }
      return left.count < right.count
    }
  }

  private static func compareNumeric(_ lhs: String, _ rhs: String) -> ComparisonResult {
    if lhs.count != rhs.count {
      return lhs.count < rhs.count ? .orderedAscending : .orderedDescending
    }
    if lhs == rhs { return .orderedSame }
    return lhs < rhs ? .orderedAscending : .orderedDescending
  }

  private static func validIdentifiers(_ value: String, numericLeadingZero: Bool) -> Bool {
    let identifiers = value.split(separator: ".", omittingEmptySubsequences: false)
    return !identifiers.isEmpty
      && identifiers.allSatisfy { identifier in
        let text = String(identifier)
        guard !text.isEmpty,
          text.allSatisfy({ character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-")
          })
        else { return false }
        return numericLeadingZero || !text.allSatisfy(\.isNumber)
          || text == "0" || !text.hasPrefix("0")
      }
  }
}

public enum ObjectCapability: String, Codable, CaseIterable, Sendable {
  case privateChildren = "private-children"
  case broadcast
  case worldRead = "world-read"
  case worldWrite = "world-write"
  case worldSystem = "world-system"
  case network
  case userMachine = "user-machine"
}

public enum ObjectPackageRuntime: String, Codable, Sendable {
  case declarative
  case nativeSwift = "native-swift"
  case javascript
}

public enum ObjectFunctionAudience: String, Codable, CaseIterable, Sendable {
  case agent
  case object
  case both

  public var acceptsAgent: Bool { self == .agent || self == .both }
  public var acceptsObject: Bool { self == .object || self == .both }
}

public enum PackageInstallBehavior: String, Codable, Sendable {
  case createInventoryObject = "create_inventory_object"
  case registerOnly = "register_only"
}

public enum AdditionalInventoryObjects: String, Codable, Sendable {
  case allow
  case deny
}

public struct PackageInstallationPolicy: Codable, Equatable, Sendable {
  public let onInstall: PackageInstallBehavior
  public let additionalInventoryObjects: AdditionalInventoryObjects

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case onInstall = "on_install"
    case additionalInventoryObjects = "additional_inventory_objects"
  }

  public init(
    onInstall: PackageInstallBehavior = .registerOnly,
    additionalInventoryObjects: AdditionalInventoryObjects = .allow
  ) {
    self.onInstall = onInstall
    self.additionalInventoryObjects = additionalInventoryObjects
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownPackageKeys(
      from: decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "installation"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    onInstall = try container.decode(PackageInstallBehavior.self, forKey: .onInstall)
    additionalInventoryObjects = try container.decode(
      AdditionalInventoryObjects.self,
      forKey: .additionalInventoryObjects
    )
  }
}

public enum ManagementFieldKind: String, Codable, CaseIterable, Sendable {
  case text
  case integer
  case decimal
  case boolean
  case choice
  case url
  case path
  case secret
}

public struct ManagementField: Codable, Equatable, Sendable {
  public let id: String
  public let label: String
  public let summary: String
  public let kind: ManagementFieldKind
  public let required: Bool
  public let deployable: Bool
  public let defaultValue: JSONValue?
  public let choices: [String]
  public let minimum: Double?
  public let maximum: Double?
  public let minimumCharacters: Int?
  public let maximumCharacters: Int?

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, label, summary, kind, required, deployable, choices, minimum, maximum
    case defaultValue = "default"
    case minimumCharacters = "minimum_characters"
    case maximumCharacters = "maximum_characters"
  }

  public init(
    id: String,
    label: String,
    summary: String = "",
    kind: ManagementFieldKind,
    required: Bool = false,
    deployable: Bool = true,
    defaultValue: JSONValue? = nil,
    choices: [String] = [],
    minimum: Double? = nil,
    maximum: Double? = nil,
    minimumCharacters: Int? = nil,
    maximumCharacters: Int? = nil
  ) throws {
    try validatePackageIdentifier(id, label: "management field id")
    try validatePackageLine(label, label: "management field label", limit: 128)
    if !summary.isEmpty { try validatePackageLine(summary, label: "management field summary") }
    guard kind == .choice || choices.isEmpty else {
      throw MikroKhorosError.objectPackage("only choice fields may declare choices")
    }
    guard kind != .choice || !choices.isEmpty else {
      throw MikroKhorosError.objectPackage("choice fields require at least one choice")
    }
    guard kind != .secret || defaultValue == nil else {
      throw MikroKhorosError.objectPackage("secret fields cannot contain package defaults")
    }
    guard choices.allSatisfy({ !$0.isEmpty && $0.count <= 256 && !$0.contains(where: \.isNewline) })
    else {
      throw MikroKhorosError.objectPackage("field choices must be bounded single-line values")
    }
    guard minimum == nil || minimum!.isFinite,
      maximum == nil || maximum!.isFinite,
      minimum == nil || maximum == nil || minimum! <= maximum!,
      minimumCharacters == nil || minimumCharacters! >= 0,
      maximumCharacters == nil || maximumCharacters! >= 0,
      minimumCharacters == nil || maximumCharacters == nil
        || minimumCharacters! <= maximumCharacters!
    else {
      throw MikroKhorosError.objectPackage("management field constraints are invalid")
    }
    guard [.integer, .decimal].contains(kind) || (minimum == nil && maximum == nil) else {
      throw MikroKhorosError.objectPackage("only numeric fields may declare numeric bounds")
    }
    guard
      [.text, .choice, .url, .path, .secret].contains(kind)
        || (minimumCharacters == nil && maximumCharacters == nil)
    else {
      throw MikroKhorosError.objectPackage("only textual fields may declare character bounds")
    }
    self.id = id
    self.label = label
    self.summary = summary
    self.kind = kind
    self.required = required
    self.deployable = deployable
    self.defaultValue = defaultValue
    self.choices = choices
    self.minimum = minimum
    self.maximum = maximum
    self.minimumCharacters = minimumCharacters
    self.maximumCharacters = maximumCharacters
    if let defaultValue { _ = try validatedManagementValue(defaultValue, for: self) }
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownPackageKeys(
      from: decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "management field"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(String.self, forKey: .id),
      label: container.decode(String.self, forKey: .label),
      summary: container.decodeIfPresent(String.self, forKey: .summary) ?? "",
      kind: container.decode(ManagementFieldKind.self, forKey: .kind),
      required: container.decodeIfPresent(Bool.self, forKey: .required) ?? false,
      deployable: container.decodeIfPresent(Bool.self, forKey: .deployable) ?? true,
      defaultValue: container.decodeIfPresent(JSONValue.self, forKey: .defaultValue),
      choices: container.decodeIfPresent([String].self, forKey: .choices) ?? [],
      minimum: container.decodeIfPresent(Double.self, forKey: .minimum),
      maximum: container.decodeIfPresent(Double.self, forKey: .maximum),
      minimumCharacters: container.decodeIfPresent(Int.self, forKey: .minimumCharacters),
      maximumCharacters: container.decodeIfPresent(Int.self, forKey: .maximumCharacters)
    )
  }
}

public enum DeclarativeActionKind: String, Codable, Sendable {
  case `return`
  case get
  case set
  case append
  case increment
  case toggle
  case report
}

public struct DeclarativeAction: Codable, Equatable, Sendable {
  public let kind: DeclarativeActionKind
  public let key: String?
  public let argument: Int?
  public let amount: Double?
  public let value: JSONValue?

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case kind, key, argument, amount, value
  }

  public init(
    kind: DeclarativeActionKind,
    key: String? = nil,
    argument: Int? = nil,
    amount: Double? = nil,
    value: JSONValue? = nil
  ) throws {
    if kind != .return {
      guard let key else {
        throw MikroKhorosError.objectPackage("declarative action requires a key")
      }
      try validatePackageIdentifier(key, label: "declarative action key")
    }
    guard argument == nil || argument! >= 0 else {
      throw MikroKhorosError.objectPackage("declarative action argument must be non-negative")
    }
    guard amount == nil || amount!.isFinite else {
      throw MikroKhorosError.objectPackage("declarative action amount must be finite")
    }
    self.kind = kind
    self.key = key
    self.argument = argument
    self.amount = amount
    self.value = value
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownPackageKeys(
      from: decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "declarative action"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      kind: container.decode(DeclarativeActionKind.self, forKey: .kind),
      key: container.decodeIfPresent(String.self, forKey: .key),
      argument: container.decodeIfPresent(Int.self, forKey: .argument),
      amount: container.decodeIfPresent(Double.self, forKey: .amount),
      value: container.decodeIfPresent(JSONValue.self, forKey: .value)
    )
  }
}

public struct DeclarativeFunctionDefinition: Codable, Equatable, Sendable {
  public let summary: String
  public let parameters: [String]
  public let durabilityCost: Int
  public let requiredCapabilities: Set<ObjectCapability>
  public let audience: ObjectFunctionAudience
  public let action: DeclarativeAction

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case summary, parameters, audience, action
    case durabilityCost = "durability_cost"
    case requiredCapabilities = "required_capabilities"
  }

  public init(
    summary: String = "",
    parameters: [String] = [],
    durabilityCost: Int = 0,
    requiredCapabilities: Set<ObjectCapability> = [],
    audience: ObjectFunctionAudience = .agent,
    action: DeclarativeAction
  ) throws {
    if !summary.isEmpty { try validatePackageLine(summary, label: "function summary") }
    for parameter in parameters {
      try validatePackageIdentifier(parameter, label: "function parameter")
    }
    guard durabilityCost >= 0 else {
      throw MikroKhorosError.objectPackage("function durability cost must be non-negative")
    }
    if let argument = action.argument, argument >= parameters.count {
      throw MikroKhorosError.objectPackage(
        "declarative action argument is outside the parameter list")
    }
    self.summary = summary
    self.parameters = parameters
    self.durabilityCost = durabilityCost
    self.requiredCapabilities = requiredCapabilities
    self.audience = audience
    self.action = action
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownPackageKeys(
      from: decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "object function"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      summary: container.decodeIfPresent(String.self, forKey: .summary) ?? "",
      parameters: container.decodeIfPresent([String].self, forKey: .parameters) ?? [],
      durabilityCost: container.decodeIfPresent(Int.self, forKey: .durabilityCost) ?? 0,
      requiredCapabilities: container.decodeIfPresent(
        Set<ObjectCapability>.self,
        forKey: .requiredCapabilities
      ) ?? [],
      audience: container.decodeIfPresent(ObjectFunctionAudience.self, forKey: .audience)
        ?? .agent,
      action: container.decode(DeclarativeAction.self, forKey: .action)
    )
  }
}

public enum ObjectManagementScope: String, Codable, CaseIterable, Sendable {
  case inventory
  case world
  case both

  public var acceptsInventory: Bool { self == .inventory || self == .both }
  public var acceptsWorld: Bool { self == .world || self == .both }
}

public struct ManagementAction: Codable, Equatable, Sendable {
  public let id: String
  public let summary: String
  public let parameters: [String]
  public let inputTypes: [String: ManagementFieldKind]
  public let inputDefaults: [String: JSONValue]
  public let inputChoices: [String: [String]]
  public let mutating: Bool
  public let requiredCapabilities: Set<ObjectCapability>
  public let scope: ObjectManagementScope
  public let action: DeclarativeAction
  public let result: [String: ManagementFieldKind]

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, summary, parameters, mutating, scope, action, result
    case inputTypes = "input_types"
    case inputDefaults = "input_defaults"
    case inputChoices = "input_choices"
    case requiredCapabilities = "required_capabilities"
  }

  public init(
    id: String,
    summary: String = "",
    parameters: [String] = [],
    inputTypes: [String: ManagementFieldKind] = [:],
    inputDefaults: [String: JSONValue] = [:],
    inputChoices: [String: [String]] = [:],
    mutating: Bool = false,
    requiredCapabilities: Set<ObjectCapability> = [],
    scope: ObjectManagementScope = .inventory,
    action: DeclarativeAction,
    result: [String: ManagementFieldKind] = [:]
  ) throws {
    try validatePackageIdentifier(id, label: "management action id")
    if !summary.isEmpty { try validatePackageLine(summary, label: "management action summary") }
    for parameter in parameters {
      try validatePackageIdentifier(parameter, label: "management action parameter")
    }
    if let argument = action.argument, argument >= parameters.count {
      throw MikroKhorosError.objectPackage(
        "management action argument is outside the parameter list")
    }
    let parameterSet = Set(parameters)
    guard Set(inputTypes.keys).isSubset(of: parameterSet),
      Set(inputDefaults.keys).isSubset(of: parameterSet),
      Set(inputChoices.keys).isSubset(of: parameterSet)
    else {
      throw MikroKhorosError.objectPackage(
        "management input metadata references unknown parameters")
    }
    guard !inputTypes.values.contains(.secret), !result.values.contains(.secret) else {
      throw MikroKhorosError.objectPackage(
        "management action inputs and results cannot contain secret values"
      )
    }
    self.id = id
    self.summary = summary
    self.parameters = parameters
    self.inputTypes = Dictionary(
      uniqueKeysWithValues: parameters.map { ($0, inputTypes[$0] ?? .text) }
    )
    for parameter in parameters {
      _ = try ManagementField(
        id: parameter,
        label: parameter,
        kind: self.inputTypes[parameter]!,
        defaultValue: inputDefaults[parameter],
        choices: inputChoices[parameter] ?? []
      )
    }
    self.inputDefaults = inputDefaults
    self.inputChoices = inputChoices
    self.mutating = mutating
    self.requiredCapabilities = requiredCapabilities
    self.scope = scope
    self.action = action
    self.result = result
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownPackageKeys(
      from: decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "management action"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(String.self, forKey: .id),
      summary: container.decodeIfPresent(String.self, forKey: .summary) ?? "",
      parameters: container.decodeIfPresent([String].self, forKey: .parameters) ?? [],
      inputTypes: container.decodeIfPresent(
        [String: ManagementFieldKind].self,
        forKey: .inputTypes
      ) ?? [:],
      inputDefaults: container.decodeIfPresent(
        [String: JSONValue].self,
        forKey: .inputDefaults
      ) ?? [:],
      inputChoices: container.decodeIfPresent(
        [String: [String]].self,
        forKey: .inputChoices
      ) ?? [:],
      mutating: container.decodeIfPresent(Bool.self, forKey: .mutating) ?? false,
      requiredCapabilities: container.decodeIfPresent(
        Set<ObjectCapability>.self,
        forKey: .requiredCapabilities
      ) ?? [],
      scope: container.decodeIfPresent(ObjectManagementScope.self, forKey: .scope) ?? .inventory,
      action: container.decode(DeclarativeAction.self, forKey: .action),
      result: container.decodeIfPresent(
        [String: ManagementFieldKind].self,
        forKey: .result
      ) ?? [:]
    )
  }

}

public struct ManagementView: Codable, Equatable, Sendable {
  public let id: String
  public let summary: String
  public let source: String
  public let scope: ObjectManagementScope
  public let result: [String: ManagementFieldKind]

  public var worldObjectScope: Bool { scope.acceptsWorld }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, summary, source, scope, result
    case worldObjectScope = "world_object_scope"
  }

  public init(
    id: String,
    summary: String = "",
    source: String = "summary",
    worldObjectScope: Bool = false,
    scope: ObjectManagementScope? = nil,
    result: [String: ManagementFieldKind] = [:]
  ) throws {
    try validatePackageIdentifier(id, label: "management view id")
    if !summary.isEmpty { try validatePackageLine(summary, label: "management view summary") }
    guard ["summary", "configuration", "state"].contains(source) else {
      throw MikroKhorosError.objectPackage(
        "management view source must be summary, configuration, or state")
    }
    guard !result.values.contains(.secret) else {
      throw MikroKhorosError.objectPackage("management view results cannot contain secret values")
    }
    self.id = id
    self.summary = summary
    self.source = source
    self.scope = scope ?? (worldObjectScope ? .both : .inventory)
    self.result = result
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownPackageKeys(
      from: decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "management view"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(String.self, forKey: .id),
      summary: container.decodeIfPresent(String.self, forKey: .summary) ?? "",
      source: container.decodeIfPresent(String.self, forKey: .source) ?? "summary",
      worldObjectScope: container.decodeIfPresent(
        Bool.self,
        forKey: .worldObjectScope
      ) ?? false,
      scope: container.decodeIfPresent(ObjectManagementScope.self, forKey: .scope),
      result: container.decodeIfPresent(
        [String: ManagementFieldKind].self,
        forKey: .result
      ) ?? [:]
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(summary, forKey: .summary)
    try container.encode(source, forKey: .source)
    try container.encode(scope, forKey: .scope)
    try container.encode(result, forKey: .result)
  }
}

public struct ObjectReportDefinition: Codable, Equatable, Sendable {
  public let type: String
  public let summary: String
  public let maximumTitleCharacters: Int
  public let maximumBodyCharacters: Int
  public let maximumPayloadBytes: Int?
  public let payload: [String: ManagementFieldKind]

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case type, summary, payload
    case maximumTitleCharacters = "maximum_title_characters"
    case maximumBodyCharacters = "maximum_body_characters"
    case maximumPayloadBytes = "maximum_payload_bytes"
  }

  public init(
    type: String,
    summary: String = "",
    maximumTitleCharacters: Int = 256,
    maximumBodyCharacters: Int = 4_096,
    maximumPayloadBytes: Int? = nil,
    payload: [String: ManagementFieldKind] = [:]
  ) throws {
    try validatePackageIdentifier(type, label: "report type")
    if !summary.isEmpty { try validatePackageLine(summary, label: "report summary") }
    guard maximumTitleCharacters > 0, maximumBodyCharacters > 0,
      maximumPayloadBytes == nil || maximumPayloadBytes! > 0
    else { throw MikroKhorosError.objectPackage("report limits must be positive") }
    guard !payload.values.contains(.secret) else {
      throw MikroKhorosError.objectPackage("report payloads cannot contain secret values")
    }
    self.type = type
    self.summary = summary
    self.maximumTitleCharacters = maximumTitleCharacters
    self.maximumBodyCharacters = maximumBodyCharacters
    self.maximumPayloadBytes = maximumPayloadBytes
    self.payload = payload
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownPackageKeys(
      from: decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "report definition"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      type: container.decode(String.self, forKey: .type),
      summary: container.decodeIfPresent(String.self, forKey: .summary) ?? "",
      maximumTitleCharacters: container.decodeIfPresent(
        Int.self,
        forKey: .maximumTitleCharacters
      ) ?? 256,
      maximumBodyCharacters: container.decodeIfPresent(
        Int.self,
        forKey: .maximumBodyCharacters
      ) ?? 4_096,
      maximumPayloadBytes: container.decodeIfPresent(
        Int.self,
        forKey: .maximumPayloadBytes
      ),
      payload: container.decodeIfPresent(
        [String: ManagementFieldKind].self,
        forKey: .payload
      ) ?? [:]
    )
  }
}

public struct ObjectManagementInterface: Codable, Equatable, Sendable {
  public let fields: [ManagementField]
  public let actions: [ManagementAction]
  public let views: [ManagementView]
  public let reports: [ObjectReportDefinition]

  private enum CodingKeys: String, CodingKey, CaseIterable { case fields, actions, views, reports }

  public init(
    fields: [ManagementField] = [],
    actions: [ManagementAction] = [],
    views: [ManagementView] = [],
    reports: [ObjectReportDefinition] = []
  ) throws {
    guard Set(fields.map(\.id)).count == fields.count else {
      throw MikroKhorosError.objectPackage("management field ids must be unique")
    }
    guard Set(actions.map(\.id)).count == actions.count else {
      throw MikroKhorosError.objectPackage("management action ids must be unique")
    }
    guard Set(views.map(\.id)).count == views.count else {
      throw MikroKhorosError.objectPackage("management view ids must be unique")
    }
    guard Set(reports.map(\.type)).count == reports.count else {
      throw MikroKhorosError.objectPackage("report types must be unique")
    }
    self.fields = fields
    self.actions = actions
    self.views = views
    self.reports = reports
  }

  public static let empty = try! ObjectManagementInterface()

  public init(from decoder: Decoder) throws {
    try rejectUnknownPackageKeys(
      from: decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "management interface"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      fields: container.decodeIfPresent([ManagementField].self, forKey: .fields) ?? [],
      actions: container.decodeIfPresent([ManagementAction].self, forKey: .actions) ?? [],
      views: container.decodeIfPresent([ManagementView].self, forKey: .views) ?? [],
      reports: container.decodeIfPresent([ObjectReportDefinition].self, forKey: .reports) ?? []
    )
  }
}

public struct DeclarativeObjectDefinition: Codable, Equatable, Sendable {
  public let type: String
  public let name: String
  public let summary: String
  public let publicData: [String: JSONValue]
  public let state: [String: JSONValue]
  public let durability: Int?
  public let container: Bool
  public let invocationAccess: InvocationAccess
  public let functions: [String: DeclarativeFunctionDefinition]

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case type, name, summary, state, durability, container, functions
    case publicData = "public"
    case invocationAccess = "invocation_access"
  }

  public init(
    type: String,
    name: String,
    summary: String = "",
    publicData: [String: JSONValue] = [:],
    state: [String: JSONValue] = [:],
    durability: Int? = nil,
    container: Bool = false,
    invocationAccess: InvocationAccess = .held,
    functions: [String: DeclarativeFunctionDefinition] = [:]
  ) throws {
    guard type.hasSuffix(".object"), !type.contains(where: { $0.isWhitespace }), type.count <= 128
    else { throw MikroKhorosError.objectPackage("object type must be one token ending in .object") }
    try validatePackageLine(name, label: "object name", limit: 128)
    if !summary.isEmpty { try validatePackageLine(summary, label: "object summary") }
    guard durability == nil || durability! >= 0 else {
      throw MikroKhorosError.objectPackage("object durability must be non-negative")
    }
    for (id, function) in functions {
      try validatePackageIdentifier(id, label: "object function id")
      guard function.durabilityCost == 0 || durability != nil else {
        throw MikroKhorosError.objectPackage(
          "durability-consuming functions require object durability")
      }
    }
    self.type = type
    self.name = name
    self.summary = summary
    self.publicData = publicData
    self.state = state
    self.durability = durability
    self.container = container
    self.invocationAccess = invocationAccess
    self.functions = functions
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownPackageKeys(
      from: decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "object definition"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      type: container.decode(String.self, forKey: .type),
      name: container.decode(String.self, forKey: .name),
      summary: container.decodeIfPresent(String.self, forKey: .summary) ?? "",
      publicData: container.decodeIfPresent([String: JSONValue].self, forKey: .publicData) ?? [:],
      state: container.decodeIfPresent([String: JSONValue].self, forKey: .state) ?? [:],
      durability: container.decodeIfPresent(Int.self, forKey: .durability),
      container: container.decodeIfPresent(Bool.self, forKey: .container) ?? false,
      invocationAccess: container.decodeIfPresent(
        InvocationAccess.self,
        forKey: .invocationAccess
      ) ?? .held,
      functions: container.decodeIfPresent(
        [String: DeclarativeFunctionDefinition].self,
        forKey: .functions
      ) ?? [:]
    )
  }
}

/// One package-owned object placed inside the root object or another owned object.
/// The graph is flat in the manifest so it can be validated before any runtime
/// object is created.
public struct DeclarativeOwnedObjectDefinition: Codable, Equatable, Sendable {
  public let id: String
  public let parent: String
  public let coordinate: Coordinate
  public let object: DeclarativeObjectDefinition

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, parent, coordinate, object
  }

  public init(
    id: String,
    parent: String = "root",
    coordinate: Coordinate = .origin,
    object: DeclarativeObjectDefinition
  ) throws {
    try validatePackageIdentifier(id, label: "owned object id")
    guard id != "root" else {
      throw MikroKhorosError.objectPackage("owned object id root is reserved")
    }
    try validatePackageIdentifier(parent, label: "owned object parent")
    self.id = id
    self.parent = parent
    self.coordinate = coordinate
    self.object = object
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownPackageKeys(
      from: decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "owned object"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(String.self, forKey: .id),
      parent: container.decodeIfPresent(String.self, forKey: .parent) ?? "root",
      coordinate: container.decodeIfPresent(Coordinate.self, forKey: .coordinate) ?? .origin,
      object: container.decode(DeclarativeObjectDefinition.self, forKey: .object)
    )
  }
}

public struct ObjectPackageManifest: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 2

  public let schema: Int
  public let id: String
  public let version: String
  public let displayName: String
  public let runtime: ObjectPackageRuntime
  public let requestedCapabilities: Set<ObjectCapability>
  public let installation: PackageInstallationPolicy
  public let object: DeclarativeObjectDefinition
  public let ownedObjects: [DeclarativeOwnedObjectDefinition]
  public let management: ObjectManagementInterface

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schema, id, version, runtime, installation, object, management
    case displayName = "display_name"
    case requestedCapabilities = "requested_capabilities"
    case ownedObjects = "owned_objects"
  }

  public init(
    schema: Int = currentSchemaVersion,
    id: String,
    version: String,
    displayName: String,
    runtime: ObjectPackageRuntime = .declarative,
    requestedCapabilities: Set<ObjectCapability> = [],
    installation: PackageInstallationPolicy = PackageInstallationPolicy(),
    object: DeclarativeObjectDefinition,
    ownedObjects: [DeclarativeOwnedObjectDefinition] = [],
    management: ObjectManagementInterface = .empty
  ) throws {
    guard schema == 1 || schema == Self.currentSchemaVersion else {
      throw MikroKhorosError.objectPackage("unsupported object package schema")
    }
    try validatePackageIdentifier(id, label: "object package id")
    try Self.validateSemanticVersion(version)
    try validatePackageLine(displayName, label: "object package display name", limit: 128)
    let definitions = [object] + ownedObjects.map(\.object)
    guard
      definitions.flatMap({ $0.functions.values }).allSatisfy({
        $0.requiredCapabilities.isSubset(of: requestedCapabilities)
      })
    else {
      throw MikroKhorosError.objectPackage("object function requires an unrequested capability")
    }
    guard
      management.actions.allSatisfy({
        $0.requiredCapabilities.isSubset(of: requestedCapabilities)
      })
    else {
      throw MikroKhorosError.objectPackage("management action requires an unrequested capability")
    }
    try Self.validateOwnedObjects(root: object, ownedObjects: ownedObjects)
    let reportTypes = Set(management.reports.map(\.type))
    guard
      definitions.flatMap({ $0.functions.values }).allSatisfy({ function in
        function.action.kind != .report || function.action.key.map(reportTypes.contains) == true
      })
    else {
      throw MikroKhorosError.objectPackage("object function emits an undeclared report type")
    }
    guard management.actions.allSatisfy({ $0.action.kind != .report }) else {
      throw MikroKhorosError.objectPackage("management actions cannot emit world-object reports")
    }
    self.schema = Self.currentSchemaVersion
    self.id = id
    self.version = version
    self.displayName = displayName
    self.runtime = runtime
    self.requestedCapabilities = requestedCapabilities
    self.installation = installation
    self.object = object
    self.ownedObjects = ownedObjects
    self.management = management
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownPackageKeys(
      from: decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "object package"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      schema: container.decode(Int.self, forKey: .schema),
      id: container.decode(String.self, forKey: .id),
      version: container.decode(String.self, forKey: .version),
      displayName: container.decode(String.self, forKey: .displayName),
      runtime: container.decode(ObjectPackageRuntime.self, forKey: .runtime),
      requestedCapabilities: container.decodeIfPresent(
        Set<ObjectCapability>.self,
        forKey: .requestedCapabilities
      ) ?? [],
      installation: container.decode(PackageInstallationPolicy.self, forKey: .installation),
      object: container.decode(DeclarativeObjectDefinition.self, forKey: .object),
      ownedObjects: container.decodeIfPresent(
        [DeclarativeOwnedObjectDefinition].self,
        forKey: .ownedObjects
      ) ?? [],
      management: container.decodeIfPresent(
        ObjectManagementInterface.self,
        forKey: .management
      ) ?? .empty
    )
  }

  public func validateRuntimeAvailability() throws {
    guard runtime == .declarative else {
      throw MikroKhorosError.runtime(
        "object_package.runtime_unavailable",
        "this object package runtime is not available in the installed CLI",
        details: ["runtime": runtime.rawValue],
        suggestions: ["install a declarative package or use a host that registers this runtime"]
      )
    }
  }

  private static func validateSemanticVersion(_ value: String) throws {
    _ = try ObjectPackageSemanticVersion(value)
  }

  private static func validateOwnedObjects(
    root: DeclarativeObjectDefinition,
    ownedObjects: [DeclarativeOwnedObjectDefinition]
  ) throws {
    let grouped = Dictionary(grouping: ownedObjects, by: \.id)
    guard grouped.values.allSatisfy({ $0.count == 1 }) else {
      throw MikroKhorosError.objectPackage("owned object ids must be unique")
    }
    let byID = grouped.mapValues { $0[0] }
    for owned in ownedObjects {
      guard owned.parent == "root" || byID[owned.parent] != nil else {
        throw MikroKhorosError.objectPackage("owned object references an unknown parent")
      }
      let parentDefinition = owned.parent == "root" ? root : byID[owned.parent]!.object
      guard parentDefinition.container else {
        throw MikroKhorosError.objectPackage("owned object parent must have container capability")
      }
    }
    let occupied = Dictionary(grouping: ownedObjects) { "\($0.parent)@\($0.coordinate)" }
    guard occupied.values.allSatisfy({ $0.count == 1 }) else {
      throw MikroKhorosError.objectPackage("owned objects cannot share a parent coordinate")
    }
    for owned in ownedObjects {
      var seen = Set([owned.id])
      var parent = owned.parent
      while parent != "root" {
        guard !seen.contains(parent), let next = byID[parent] else {
          throw MikroKhorosError.objectPackage("owned object graph contains a cycle")
        }
        seen.insert(parent)
        parent = next.parent
      }
    }
  }
}

public struct WorldTemplateComponentLineage: Codable, Equatable, Sendable {
  public let templateID: String
  public let templateVersion: String
  public let applicationID: String
  public let componentKey: String

  public init(
    templateID: String,
    templateVersion: String,
    applicationID: String,
    componentKey: String
  ) {
    self.templateID = templateID
    self.templateVersion = templateVersion
    self.applicationID = applicationID
    self.componentKey = componentKey
  }
}

public struct ObjectLineage: Codable, Equatable, Sendable {
  public let packageID: String
  public let packageVersion: String
  public let packageHash: String
  public let inventoryObjectID: String
  public let inventoryRevision: Int
  public let deploymentID: String
  public let restockRuleID: String?
  public let worldTemplate: WorldTemplateComponentLineage?

  public init(
    packageID: String,
    packageVersion: String,
    packageHash: String,
    inventoryObjectID: String,
    inventoryRevision: Int,
    deploymentID: String,
    restockRuleID: String? = nil,
    worldTemplate: WorldTemplateComponentLineage? = nil
  ) {
    self.packageID = packageID
    self.packageVersion = packageVersion
    self.packageHash = packageHash
    self.inventoryObjectID = inventoryObjectID
    self.inventoryRevision = inventoryRevision
    self.deploymentID = deploymentID
    self.restockRuleID = restockRuleID
    self.worldTemplate = worldTemplate
  }
}

public struct ObjectInvocationIdentity: Equatable, Sendable {
  public let rootInvocationID: String
  public let currentInvocationID: String
  public let targetObjectID: String
  public let callingObjectID: String?
  public let originalAgentID: String
  public let worldID: String
  public let callDepth: Int
  public let lineage: ObjectLineage?

  public var invocationID: String { currentInvocationID }
  public var objectID: String { targetObjectID }
  public var agentID: String { originalAgentID }

  public init(
    invocationID: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
    objectID: String,
    agentID: String,
    worldID: String,
    lineage: ObjectLineage? = nil
  ) {
    self.rootInvocationID = invocationID
    self.currentInvocationID = invocationID
    self.targetObjectID = objectID
    self.callingObjectID = nil
    self.originalAgentID = agentID
    self.worldID = worldID
    self.callDepth = 0
    self.lineage = lineage
  }

  public init(
    rootInvocationID: String,
    currentInvocationID: String,
    targetObjectID: String,
    callingObjectID: String?,
    originalAgentID: String,
    worldID: String,
    callDepth: Int,
    lineage: ObjectLineage?
  ) {
    self.rootInvocationID = rootInvocationID
    self.currentInvocationID = currentInvocationID
    self.targetObjectID = targetObjectID
    self.callingObjectID = callingObjectID
    self.originalAgentID = originalAgentID
    self.worldID = worldID
    self.callDepth = callDepth
    self.lineage = lineage
  }
}

public struct ObjectRelativeInspection: Equatable, Sendable {
  public let objectID: String
  public let type: String
  public let name: String
  public let coordinate: Coordinate
  public let functions: [String]

  public init(
    objectID: String,
    type: String,
    name: String,
    coordinate: Coordinate,
    functions: [String]
  ) {
    self.objectID = objectID
    self.type = type
    self.name = name
    self.coordinate = coordinate
    self.functions = functions
  }
}

public struct ObjectCapabilityBroker: Sendable {
  public let granted: Set<ObjectCapability>

  public init(granted: Set<ObjectCapability>) { self.granted = granted }

  public func require(_ capability: ObjectCapability) throws {
    guard granted.contains(capability) else {
      throw MikroKhorosError.runtime(
        "object.capability_denied",
        "the concrete object does not have the required capability",
        details: ["capability": capability.rawValue]
      )
    }
  }
}

public struct AgentObjectContext: Sendable {
  public let identity: ObjectInvocationIdentity
  public let capabilities: ObjectCapabilityBroker
  public let state: ObjectBoundedStateService?
  public let worldRead: ObjectWorldReadService?
  public let worldWrite: ObjectWorldWriteService?
  public let worldSystem: ObjectWorldSystemService?
  public let network: ObjectNetworkClient?
  public let userFolders: ObjectUserFolderService?
  public let reports: (any ObjectReportEmitter)?

  public init(
    identity: ObjectInvocationIdentity,
    capabilities: ObjectCapabilityBroker,
    state: ObjectBoundedStateService? = nil,
    worldRead: ObjectWorldReadService? = nil,
    worldWrite: ObjectWorldWriteService? = nil,
    worldSystem: ObjectWorldSystemService? = nil,
    network: ObjectNetworkClient? = nil,
    userFolders: ObjectUserFolderService? = nil,
    reports: (any ObjectReportEmitter)? = nil
  ) {
    self.identity = identity
    self.capabilities = capabilities
    self.state = state
    self.worldRead = worldRead
    self.worldWrite = worldWrite
    self.worldSystem = worldSystem
    self.network = network
    self.userFolders = userFolders
    self.reports = reports
  }
}

public struct UserObjectContext: Sendable {
  public let inventoryObjectID: String
  public let packageID: String
  public let packageVersion: String
  public let inventoryRevision: Int
  public let capabilities: ObjectCapabilityBroker
  public let state: ObjectBoundedStateService?
  public let worldRead: ObjectWorldReadService?
  public let worldWrite: ObjectWorldWriteService?
  public let worldSystem: ObjectWorldSystemService?
  public let network: ObjectNetworkClient?
  public let userFolders: ObjectUserFolderService?

  public init(
    inventoryObjectID: String,
    packageID: String,
    packageVersion: String,
    inventoryRevision: Int,
    capabilities: ObjectCapabilityBroker,
    state: ObjectBoundedStateService? = nil,
    worldRead: ObjectWorldReadService? = nil,
    worldWrite: ObjectWorldWriteService? = nil,
    worldSystem: ObjectWorldSystemService? = nil,
    network: ObjectNetworkClient? = nil,
    userFolders: ObjectUserFolderService? = nil
  ) {
    self.inventoryObjectID = inventoryObjectID
    self.packageID = packageID
    self.packageVersion = packageVersion
    self.inventoryRevision = inventoryRevision
    self.capabilities = capabilities
    self.state = state
    self.worldRead = worldRead
    self.worldWrite = worldWrite
    self.worldSystem = worldSystem
    self.network = network
    self.userFolders = userFolders
  }
}

public struct ObjectDeploymentContext: Sendable {
  public let worldID: String
  public let lineage: ObjectLineage
  public let capabilities: ObjectCapabilityBroker
  public let state: ObjectBoundedStateService?
  public let worldRead: ObjectWorldReadService?
  public let worldWrite: ObjectWorldWriteService?
  public let worldSystem: ObjectWorldSystemService?
  public let network: ObjectNetworkClient?
  public let userFolders: ObjectUserFolderService?
  public let reports: (any ObjectReportEmitter)?

  public init(
    worldID: String,
    lineage: ObjectLineage,
    capabilities: ObjectCapabilityBroker,
    state: ObjectBoundedStateService? = nil,
    worldRead: ObjectWorldReadService? = nil,
    worldWrite: ObjectWorldWriteService? = nil,
    worldSystem: ObjectWorldSystemService? = nil,
    network: ObjectNetworkClient? = nil,
    userFolders: ObjectUserFolderService? = nil,
    reports: (any ObjectReportEmitter)? = nil
  ) {
    self.worldID = worldID
    self.lineage = lineage
    self.capabilities = capabilities
    self.state = state
    self.worldRead = worldRead
    self.worldWrite = worldWrite
    self.worldSystem = worldSystem
    self.network = network
    self.userFolders = userFolders
    self.reports = reports
  }
}

public protocol ObjectReportEmitter: Sendable {
  func emit(type: String, title: String, body: String, payload: JSONValue) throws
}

public struct ObjectBoundedStateService: Sendable {
  private let readOperation: @Sendable (String) throws -> JSONValue
  private let writeOperation: @Sendable (String, JSONValue) throws -> Void

  public init(
    read: @escaping @Sendable (String) throws -> JSONValue,
    write: @escaping @Sendable (String, JSONValue) throws -> Void
  ) {
    self.readOperation = read
    self.writeOperation = write
  }

  public func read(_ key: String) throws -> JSONValue { try readOperation(key) }

  public func write(_ key: String, value: JSONValue) throws {
    try writeOperation(key, value)
  }
}

/// Capability gates are held by the service itself, so every protected operation
/// is checked at the point where authority is exercised.
public struct ObjectWorldReadService: Sendable {
  private let capabilities: ObjectCapabilityBroker
  private let operation: @Sendable (String) throws -> JSONValue
  private let relativeInspection: (@Sendable (Coordinate) throws -> ObjectRelativeInspection)?

  public init(
    capabilities: ObjectCapabilityBroker,
    operation: @escaping @Sendable (String) throws -> JSONValue,
    inspect: (@Sendable (Coordinate) throws -> ObjectRelativeInspection)? = nil
  ) {
    self.capabilities = capabilities
    self.operation = operation
    self.relativeInspection = inspect
  }

  public func read(_ query: String) throws -> JSONValue {
    try capabilities.require(.worldRead)
    return try operation(query)
  }

  public func inspect(at delta: Coordinate) throws -> ObjectRelativeInspection {
    try capabilities.require(.worldRead)
    guard let relativeInspection else {
      throw MikroKhorosError.runtime(
        "object.world_service_unavailable",
        "relative world inspection is unavailable in this runtime context"
      )
    }
    return try relativeInspection(delta)
  }
}

public struct ObjectWorldWriteService: Sendable {
  private let capabilities: ObjectCapabilityBroker
  private let operation: @Sendable (String, JSONValue) throws -> JSONValue
  private let relativeInvocation: (@Sendable (Coordinate, String, [String]) throws -> String)?

  public init(
    capabilities: ObjectCapabilityBroker,
    operation: @escaping @Sendable (String, JSONValue) throws -> JSONValue,
    invoke: (@Sendable (Coordinate, String, [String]) throws -> String)? = nil
  ) {
    self.capabilities = capabilities
    self.operation = operation
    self.relativeInvocation = invoke
  }

  public func write(_ operationID: String, input: JSONValue) throws -> JSONValue {
    try capabilities.require(.worldWrite)
    return try operation(operationID, input)
  }

  public func invoke(
    at delta: Coordinate,
    function: String,
    arguments: [String]
  ) throws -> String {
    try capabilities.require(.worldWrite)
    guard let relativeInvocation else {
      throw MikroKhorosError.runtime(
        "object.world_service_unavailable",
        "relative object invocation is unavailable in this runtime context"
      )
    }
    return try relativeInvocation(delta, function, arguments)
  }
}

public struct ObjectWorldSystemService: Sendable {
  private let capabilities: ObjectCapabilityBroker
  private let operation: @Sendable (String, JSONValue) throws -> JSONValue

  public init(
    capabilities: ObjectCapabilityBroker,
    operation: @escaping @Sendable (String, JSONValue) throws -> JSONValue
  ) {
    self.capabilities = capabilities
    self.operation = operation
  }

  public func perform(_ operationID: String, input: JSONValue) throws -> JSONValue {
    try capabilities.require(.worldSystem)
    return try operation(operationID, input)
  }
}

public struct ObjectNetworkClient: Sendable {
  private let capabilities: ObjectCapabilityBroker
  private let request: @Sendable (URLRequest) async throws -> (Data, URLResponse)

  public init(
    capabilities: ObjectCapabilityBroker,
    request: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
  ) {
    self.capabilities = capabilities
    self.request = request
  }

  public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
    try capabilities.require(.network)
    return try await self.request(request)
  }
}

public struct ObjectUserFolderEntry: Equatable, Sendable {
  public enum Kind: String, Sendable { case directory, file, symbolicLink, unsupported }

  public let name: String
  public let kind: Kind

  public init(name: String, kind: Kind) {
    self.name = name
    self.kind = kind
  }
}

/// A capability-mediated view of folder bindings owned by one exact concrete
/// object. Callers supply only an opaque binding identity and a relative path.
public struct ObjectUserFolderService: @unchecked Sendable {
  private let capabilities: ObjectCapabilityBroker
  private let listOperation: (String, String) throws -> [ObjectUserFolderEntry]
  private let readOperation: (String, String, Range<Int>?) throws -> Data
  private let writeOperation: (String, String, Data) throws -> Void
  private let appendOperation: (String, String, Data) throws -> Void
  private let clearOperation: (String, String) throws -> Void

  public init(
    capabilities: ObjectCapabilityBroker,
    list: @escaping (String, String) throws -> [ObjectUserFolderEntry],
    read: @escaping (String, String, Range<Int>?) throws -> Data,
    write: @escaping (String, String, Data) throws -> Void,
    append: @escaping (String, String, Data) throws -> Void,
    clear: @escaping (String, String) throws -> Void
  ) {
    self.capabilities = capabilities
    self.listOperation = list
    self.readOperation = read
    self.writeOperation = write
    self.appendOperation = append
    self.clearOperation = clear
  }

  public func list(bindingID: String, relativePath: String) throws -> [ObjectUserFolderEntry] {
    try capabilities.require(.userMachine)
    return try listOperation(bindingID, relativePath)
  }

  public func read(
    bindingID: String,
    relativePath: String,
    range: Range<Int>? = nil
  ) throws -> Data {
    try capabilities.require(.userMachine)
    return try readOperation(bindingID, relativePath, range)
  }

  public func write(bindingID: String, relativePath: String, data: Data) throws {
    try capabilities.require(.userMachine)
    try writeOperation(bindingID, relativePath, data)
  }

  public func append(bindingID: String, relativePath: String, data: Data) throws {
    try capabilities.require(.userMachine)
    try appendOperation(bindingID, relativePath, data)
  }

  public func clear(bindingID: String, relativePath: String) throws {
    try capabilities.require(.userMachine)
    try clearOperation(bindingID, relativePath)
  }
}

public protocol ObjectUserFolderServiceProviding: AnyObject {
  func makeObjectUserFolderService() -> ObjectUserFolderService
}

func validatedManagementValue(_ value: JSONValue, for field: ManagementField) throws -> JSONValue {
  let valid: Bool
  switch field.kind {
  case .text, .url, .path, .secret:
    valid = value.stringValue != nil
  case .integer:
    valid = value.intValue != nil
  case .decimal:
    valid = value.numberValue != nil
  case .boolean:
    valid = value.boolValue != nil
  case .choice:
    valid = value.stringValue.map(field.choices.contains) ?? false
  }
  guard valid else {
    throw MikroKhorosError.runtime(
      "inventory.configuration_invalid",
      "the value does not match the management field type",
      details: ["field": field.id, "type": field.kind.rawValue]
    )
  }
  if let number = value.numberValue {
    guard field.minimum.map({ number >= $0 }) != false,
      field.maximum.map({ number <= $0 }) != false
    else {
      throw MikroKhorosError.runtime(
        "inventory.configuration_invalid",
        "the numeric value is outside the management field bounds",
        details: ["field": field.id]
      )
    }
  }
  if let text = value.stringValue {
    guard field.minimumCharacters.map({ text.count >= $0 }) != false,
      field.maximumCharacters.map({ text.count <= $0 }) != false
    else {
      throw MikroKhorosError.runtime(
        "inventory.configuration_invalid",
        "the text value is outside the management field character bounds",
        details: ["field": field.id]
      )
    }
  }
  return value
}
