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

public struct Coordinate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
  public let x: Int
  public let y: Int

  public init(x: Int = 0, y: Int = 0) {
    self.x = x
    self.y = y
  }

  public static let origin = Coordinate()

  public static func + (lhs: Coordinate, rhs: Coordinate) -> Coordinate {
    Coordinate(
      x: saturatedAdd(lhs.x, rhs.x),
      y: saturatedAdd(lhs.y, rhs.y)
    )
  }

  public static func - (lhs: Coordinate, rhs: Coordinate) -> Coordinate {
    Coordinate(
      x: saturatedSubtract(lhs.x, rhs.x),
      y: saturatedSubtract(lhs.y, rhs.y)
    )
  }

  public func scaled(by amount: Int) -> Coordinate {
    Coordinate(
      x: Self.saturatedMultiply(x, amount),
      y: Self.saturatedMultiply(y, amount)
    )
  }

  public func offset(x: Int, y: Int) -> Coordinate {
    Coordinate(
      x: Self.saturatedAdd(self.x, x),
      y: Self.saturatedAdd(self.y, y)
    )
  }

  /// Returns an exact sum or fails instead of wrapping or trapping. Runtime
  /// mutations use this operation so an invalid boundary move is atomic.
  public func addingExactly(_ other: Coordinate) throws -> Coordinate {
    let (nextX, xOverflow) = x.addingReportingOverflow(other.x)
    let (nextY, yOverflow) = y.addingReportingOverflow(other.y)
    guard !xOverflow, !yOverflow else {
      throw MikroKhorosError.runtime(
        "coordinate.overflow",
        "the requested coordinate is outside the supported integer range"
      )
    }
    return Coordinate(x: nextX, y: nextY)
  }

  /// Returns an exact scale or fails before a caller publishes any mutation.
  public func scaledExactly(by amount: Int) throws -> Coordinate {
    let (nextX, xOverflow) = x.multipliedReportingOverflow(by: amount)
    let (nextY, yOverflow) = y.multipliedReportingOverflow(by: amount)
    guard !xOverflow, !yOverflow else {
      throw MikroKhorosError.runtime(
        "coordinate.overflow",
        "the requested coordinate is outside the supported integer range"
      )
    }
    return Coordinate(x: nextX, y: nextY)
  }

  public func manhattanDistance(to other: Coordinate) -> Int {
    let xDistance = Self.unsignedDistance(x, other.x)
    let yDistance = Self.unsignedDistance(y, other.y)
    let (total, overflow) = xDistance.addingReportingOverflow(yDistance)
    guard !overflow, total <= UInt(Int.max) else { return Int.max }
    return Int(total)
  }

  public static func < (lhs: Coordinate, rhs: Coordinate) -> Bool {
    lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
  }

  public var description: String { "(\(x),\(y))" }

  private static func saturatedAdd(_ lhs: Int, _ rhs: Int) -> Int {
    let (value, overflow) = lhs.addingReportingOverflow(rhs)
    guard overflow else { return value }
    return rhs >= 0 ? Int.max : Int.min
  }

  private static func saturatedSubtract(_ lhs: Int, _ rhs: Int) -> Int {
    let (value, overflow) = lhs.subtractingReportingOverflow(rhs)
    guard overflow else { return value }
    return rhs >= 0 ? Int.min : Int.max
  }

  private static func saturatedMultiply(_ lhs: Int, _ rhs: Int) -> Int {
    let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
    guard overflow else { return value }
    return (lhs < 0) == (rhs < 0) ? Int.max : Int.min
  }

  private static func unsignedDistance(_ lhs: Int, _ rhs: Int) -> UInt {
    if (lhs < 0) == (rhs < 0) {
      return lhs >= rhs ? UInt(lhs - rhs) : UInt(rhs - lhs)
    }
    // Opposite signs cannot overflow UInt: the widest Int distance is UInt.max.
    return lhs.magnitude + rhs.magnitude
  }
}

public enum LockAuthority: Int, CaseIterable, Comparable, Codable, Sendable {
  case agent = 10
  case system = 20
  case user = 30

  public static func < (lhs: LockAuthority, rhs: LockAuthority) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  public static func parse(_ value: String) throws -> LockAuthority {
    guard
      let authority = Self.allCases.first(where: {
        String(describing: $0).caseInsensitiveCompare(value) == .orderedSame
      })
    else {
      throw MikroKhorosError.objectLocked(
        "unknown lock authority; expected agent, user, or system"
      )
    }
    return authority
  }
}

extension LockAuthority: CustomStringConvertible {
  public var description: String {
    switch self {
    case .agent: "agent"
    case .user: "user"
    case .system: "system"
    }
  }
}

public enum PickupLockMode: String, Codable, Sendable {
  case denyAll = "deny_all"
  case allowOnly = "allow_only"
}

public struct ObjectLock: Equatable, Codable, Sendable {
  public let mode: PickupLockMode
  public let authority: LockAuthority
  public let owner: String
  public let reason: String
  public let allowedAgentIDs: Set<String>
  public let clearsOnPickup: Bool

  public init(
    mode: PickupLockMode = .denyAll,
    authority: LockAuthority,
    owner: String,
    reason: String = "",
    allowedAgentIDs: Set<String> = [],
    clearsOnPickup: Bool = false
  ) {
    self.mode = mode
    self.authority = authority
    self.owner = owner
    self.reason = reason
    self.allowedAgentIDs = allowedAgentIDs
    self.clearsOnPickup = clearsOnPickup
  }

  public func permits(agentID: String) -> Bool {
    mode == .allowOnly && allowedAgentIDs.contains(agentID)
  }
}

public enum ObjectOrigin: String, Codable, Sendable {
  case native
  case genesis
  case package
}

public enum InvocationAccess: String, Codable, Sendable {
  case held
  case surface
}

public protocol RuntimeAdapterObject: AnyObject {
  var runtimeAdapterID: String { get }
  var runtimeAdapterVersion: String { get }
  var runtimeAdapterState: [String: JSONValue] { get }
  func restoreRuntimeAdapterState(_ state: [String: JSONValue], revision: Int) throws
}

public indirect enum JSONValue: Codable, Equatable, Sendable, CustomStringConvertible {
  case string(String)
  case number(Double)
  case bool(Bool)
  case array([JSONValue])
  case object([String: JSONValue])
  case null

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }

  public var description: String {
    if case .string(let value) = self { return value }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(self),
      let text = String(data: data, encoding: .utf8)
    else { return "null" }
    return text
  }

  var objectValue: [String: JSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }

  var arrayValue: [JSONValue]? {
    guard case .array(let value) = self else { return nil }
    return value
  }

  var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  var numberValue: Double? {
    guard case .number(let value) = self else { return nil }
    return value
  }

  var intValue: Int? {
    guard let value = numberValue, value.rounded() == value else { return nil }
    return Int(exactly: value)
  }

  var boolValue: Bool? {
    guard case .bool(let value) = self else { return nil }
    return value
  }
}

struct TrustedInvocationContext: @unchecked Sendable {
  let harness: Harness
  let agent: Agent
  let object: MikroObject
  let identity: ObjectInvocationIdentity

  var userFolders: ObjectUserFolderService? {
    (object as? ObjectUserFolderServiceProviding)?.makeObjectUserFolderService()
  }

  init(harness: Harness, agent: Agent, object: MikroObject) {
    self.harness = harness
    self.agent = agent
    self.object = object
    self.identity = ObjectInvocationIdentity(
      invocationID: harness.nextRuntimeIdentity(),
      objectID: object.hash,
      agentID: agent.hash,
      worldID: harness.world.hash,
      lineage: object.lineage
    )
  }

  init(
    harness: Harness,
    agent: Agent,
    object: MikroObject,
    identity: ObjectInvocationIdentity
  ) {
    self.harness = harness
    self.agent = agent
    self.object = object
    self.identity = identity
  }

  func withPackageContext<Result>(
    _ operation: (AgentObjectContext) throws -> Result
  ) rethrows -> Result {
    let emitter = RuntimeObjectReportEmitter(harness: harness, object: object)
    let broker = ObjectCapabilityBroker(granted: object.capturedCapabilities)
    let readService = ObjectWorldReadService(
      capabilities: broker,
      operation: { _ in
        throw MikroKhorosError.runtime(
          "object.world_operation_unknown",
          "the requested world-read operation is unavailable"
        )
      },
      inspect: { delta in
        try relativeTarget(at: delta).relativeInspection()
      }
    )
    let writeService = ObjectWorldWriteService(
      capabilities: broker,
      operation: { _, _ in
        throw MikroKhorosError.runtime(
          "object.world_operation_unknown",
          "the requested world-write operation is unavailable"
        )
      },
      invoke: { delta, function, arguments in
        let target = try relativeTarget(at: delta)
        return try target.invokeFromObject(
          function,
          arguments: arguments,
          harness: harness,
          agent: agent,
          callingObject: object,
          parentIdentity: identity
        )
      }
    )
    let context = AgentObjectContext(
      identity: identity,
      capabilities: broker,
      worldRead: readService,
      worldWrite: writeService,
      userFolders: (object as? ObjectUserFolderServiceProviding)?.makeObjectUserFolderService(),
      reports: emitter
    )
    defer { emitter.deactivate() }
    return try operation(context)
  }

  private func relativeTarget(at delta: Coordinate) throws -> MikroObject {
    let space: Space
    let origin: Coordinate
    if let parentSpace = object.parentSpace, let coordinate = object.coordinate {
      space = parentSpace
      origin = coordinate
    } else if agent.primaryHeldObject === object {
      space = agent.space
      origin = agent.coordinate
    } else {
      throw MikroKhorosError.runtime(
        "object.target_space_mismatch",
        "the calling object is not placed or held in the agent's current space",
        suggestions: ["hold the tool or place the calling object in the target's container"]
      )
    }
    let targetCoordinate = try origin.addingExactly(delta)
    guard let target = space.object(at: targetCoordinate) else {
      throw MikroKhorosError.runtime(
        "object.target_missing",
        "there is no object at the requested relative coordinate",
        details: [
          "source": origin.description,
          "target": targetCoordinate.description,
        ],
        suggestions: [
          "move the calling object or target so the configured relative cell is occupied"
        ]
      )
    }
    try harness.requireAgentObjectAccess(target, for: agent)
    return target
  }
}

/// Objects backed by live external state can refresh their projected surface at
/// the ordinary interaction boundary without adding a separate watcher.
protocol LiveWorldObject: AnyObject {
  func prepareForInteraction(harness: Harness) throws
}

typealias TrustedObjectFunctionHandler = (TrustedInvocationContext, [String]) throws -> String

public typealias AgentObjectFunctionHandler = (AgentObjectContext, [String]) throws -> String

private final class RuntimeObjectReportEmitter: ObjectReportEmitter, @unchecked Sendable {
  private weak var harness: Harness?
  private weak var object: MikroObject?
  private let lock = NSLock()
  private var active = true

  init(harness: Harness, object: MikroObject) {
    self.harness = harness
    self.object = object
  }

  func emit(type: String, title: String, body: String, payload: JSONValue) throws {
    lock.lock()
    let isActive = active
    let harness = harness
    let object = object
    lock.unlock()
    guard isActive, let harness, let object else {
      throw MikroKhorosError.runtime(
        "object.context_expired",
        "the object invocation context is no longer active"
      )
    }
    try harness.emitHumanReport(
      from: object,
      type: type,
      title: title,
      body: body,
      payload: payload
    )
  }

  func deactivate() {
    lock.lock()
    active = false
    lock.unlock()
  }
}

public struct PublicFunction {
  public let name: String
  public let summary: String
  public let parameters: [String]
  public let durabilityCost: Int
  public let audience: ObjectFunctionAudience
  let handler: TrustedObjectFunctionHandler

  public var signature: String {
    let arguments = parameters.map { "<\($0)>" }.joined(separator: " ")
    return arguments.isEmpty ? name : "\(name) \(arguments)"
  }
}

public struct ObjectInspection {
  public let name: String
  public let typeName: String
  public let hash: String
  public let summary: String
  public let durability: Int?
  public let maximumDurability: Int?
  public let origin: ObjectOrigin
  public let invocationAccess: InvocationAccess
  public let lineage: ObjectLineage?
  public let capturedCapabilities: Set<ObjectCapability>
  public let publicData: [String: JSONValue]
  public let hasContainerCapability: Bool
  public let lock: ObjectLock?
  public let functions: [PublicFunction]
}

public final class Space {
  public unowned let owner: MikroObject
  private var cells: [Coordinate: MikroObject] = [:]

  init(owner: MikroObject) {
    self.owner = owner
  }

  public func contains(_ coordinate: Coordinate) -> Bool {
    true
  }

  public func object(at coordinate: Coordinate) -> MikroObject? {
    cells[coordinate]
  }

  public var items: [(coordinate: Coordinate, object: MikroObject)] {
    cells.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
  }

  func place(_ object: MikroObject, at coordinate: Coordinate) throws {
    if let occupant = cells[coordinate] {
      throw MikroKhorosError.placement(
        "coordinate \(coordinate) already contains \(occupant.name) #\(occupant.hash)"
      )
    }
    guard object.parentSpace == nil else {
      throw MikroKhorosError.placement(
        "\(object.name) is already placed at \(object.coordinate?.description ?? "unknown")"
      )
    }
    guard object !== owner else {
      throw MikroKhorosError.placement("an object cannot contain itself")
    }
    if object.container != nil, isInside(object) {
      throw MikroKhorosError.placement(
        "placing this container here would create a containment cycle"
      )
    }
    cells[coordinate] = object
    object.bind(to: self, at: coordinate)
  }

  @discardableResult
  func remove(at coordinate: Coordinate) throws -> MikroObject {
    guard let object = cells.removeValue(forKey: coordinate) else {
      throw MikroKhorosError.placement("coordinate \(coordinate) is empty")
    }
    object.unbind()
    return object
  }

  func move(from source: Coordinate, to destination: Coordinate) throws {
    if source == destination {
      guard cells[source] != nil else {
        throw MikroKhorosError.placement("coordinate \(source) is empty")
      }
      return
    }
    let object = try remove(at: source)
    do {
      try place(object, at: destination)
    } catch {
      try? place(object, at: source)
      throw error
    }
  }

  public func isInside(_ possibleAncestor: MikroObject) -> Bool {
    var current: Space? = self
    while let space = current {
      if space.owner === possibleAncestor { return true }
      current = space.owner.parentSpace
    }
    return false
  }
}

open class MikroObject {
  public let typeName: String
  public let name: String
  public let summary: String
  public let hash: String
  public private(set) var publicData: [String: JSONValue]
  public private(set) var durability: Int?
  public let maximumDurability: Int?
  public let origin: ObjectOrigin
  public let invocationAccess: InvocationAccess
  public let capturedCapabilities: Set<ObjectCapability>
  public let lineage: ObjectLineage?
  public let deploymentCredentialHandles: [String: String]
  public private(set) var instanceRevision: Int
  public private(set) var lockInfo: ObjectLock?
  public private(set) var container: Space?
  public private(set) weak var parentSpace: Space?
  public private(set) var coordinate: Coordinate?
  private var functions: [String: PublicFunction] = [:]

  public init(
    typeName: String,
    name: String? = nil,
    summary: String = "",
    publicData: [String: JSONValue] = [:],
    durability: Int? = nil,
    origin: ObjectOrigin = .native,
    invocationAccess: InvocationAccess = .held,
    capturedCapabilities: Set<ObjectCapability> = [],
    lineage: ObjectLineage? = nil,
    credentialHandles: [String: String] = [:],
    instanceRevision: Int = 1,
    hash: String? = nil,
    allowReservedNativeType: Bool = false
  ) throws {
    guard !typeName.isEmpty, typeName.count <= 128,
      !typeName.contains(where: { $0.isWhitespace || $0.isNewline })
    else {
      throw MikroKhorosError.function(
        "object type names must be 1...128 characters with no whitespace"
      )
    }
    let resolvedName = name ?? typeName.replacingOccurrences(of: ".object", with: "")
    guard !resolvedName.isEmpty, resolvedName.count <= 128,
      !resolvedName.contains(where: { $0.isNewline })
    else {
      throw MikroKhorosError.function(
        "object names must be a non-empty single line of at most 128 characters"
      )
    }
    guard summary.count <= 512, !summary.contains(where: { $0.isNewline }) else {
      throw MikroKhorosError.function(
        "object summaries must be one line of at most 512 characters"
      )
    }
    if let durability, durability < 0 {
      throw MikroKhorosError.function("durability cannot be negative")
    }
    guard instanceRevision > 0 else {
      throw MikroKhorosError.function("object instance revision must be positive")
    }
    if typeName == "wallet.object", !allowReservedNativeType {
      throw MikroKhorosError.objectPackage(
        "wallet.object is a reserved native runtime type"
      )
    }
    self.typeName = typeName
    self.name = resolvedName
    self.summary = summary
    self.publicData = publicData
    self.durability = durability
    self.maximumDurability = durability
    self.origin = origin
    self.invocationAccess = invocationAccess
    self.capturedCapabilities = capturedCapabilities
    self.lineage = lineage
    self.deploymentCredentialHandles = credentialHandles
    self.instanceRevision = instanceRevision
    self.hash = hash ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
  }

  @discardableResult
  public func addContainerCapability() throws -> Space {
    guard container == nil else {
      throw MikroKhorosError.placement("object already has container capability")
    }
    let space = Space(owner: self)
    container = space
    return space
  }

  public func setPublicData(_ value: JSONValue, forKey key: String) {
    publicData[key] = value
  }

  public func lock(
    authority: LockAuthority,
    owner: String,
    reason: String = ""
  ) throws {
    guard !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw MikroKhorosError.objectLocked("lock owner cannot be empty")
    }
    guard owner.count <= 256, !owner.contains(where: { $0.isNewline }),
      reason.count <= 512, !reason.contains(where: { $0.isNewline })
    else {
      throw MikroKhorosError.objectLocked(
        "lock owner and reason must be bounded single-line values"
      )
    }
    if let current = lockInfo {
      guard authority >= current.authority else {
        throw MikroKhorosError.objectLocked(
          "a \(authority) lock cannot replace this \(current.authority) lock"
        )
      }
      if authority == current.authority, owner != current.owner {
        throw MikroKhorosError.objectLocked(
          "an equal-authority lock belongs to a different owner"
        )
      }
    }
    lockInfo = ObjectLock(authority: authority, owner: owner, reason: reason)
  }

  public func claimPickup(
    for agentID: String,
    authority: LockAuthority,
    owner: String,
    reason: String = "purchased_claim",
    clearsOnPickup: Bool = true
  ) throws {
    guard !agentID.isEmpty else {
      throw MikroKhorosError.objectLocked("pickup claim requires an agent id")
    }
    try lock(
      ObjectLock(
        mode: .allowOnly,
        authority: authority,
        owner: owner,
        reason: reason,
        allowedAgentIDs: [agentID],
        clearsOnPickup: clearsOnPickup
      )
    )
  }

  public func lock(_ proposed: ObjectLock) throws {
    guard !proposed.owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw MikroKhorosError.objectLocked("lock owner cannot be empty")
    }
    guard proposed.owner.count <= 256,
      !proposed.owner.contains(where: { $0.isNewline }),
      proposed.reason.count <= 128,
      !proposed.reason.contains(where: { $0.isNewline })
    else {
      throw MikroKhorosError.objectLocked(
        "lock owner and reason must be bounded single-line values"
      )
    }
    if let current = lockInfo {
      guard proposed.authority >= current.authority else {
        throw MikroKhorosError.objectLocked(
          "lower authority cannot replace the current pickup lock"
        )
      }
      if proposed.authority == current.authority, proposed.owner != current.owner {
        throw MikroKhorosError.objectLocked(
          "an equal-authority lock belongs to a different owner"
        )
      }
    }
    lockInfo = proposed
  }

  func clearPickupClaimAfterSuccess(for agentID: String) {
    guard let lockInfo, lockInfo.clearsOnPickup, lockInfo.permits(agentID: agentID) else {
      return
    }
    self.lockInfo = nil
  }

  func restoreLock(_ lock: ObjectLock?) {
    lockInfo = lock
  }

  func restoreDurability(_ value: Int?) {
    durability = value
  }

  func setInstanceRevision(_ value: Int) {
    precondition(value > 0)
    instanceRevision = value
  }

  @discardableResult
  func advanceInstanceRevision() -> Int {
    instanceRevision += 1
    return instanceRevision
  }

  public func unlock(authority: LockAuthority, owner: String) throws {
    guard let current = lockInfo else { return }
    guard authority >= current.authority else {
      throw MikroKhorosError.objectLocked(
        "\(current.authority) authority is required to unlock this object"
      )
    }
    if authority == current.authority, owner != current.owner {
      throw MikroKhorosError.objectLocked("this lock belongs to a different owner")
    }
    lockInfo = nil
  }

  public var isLocked: Bool { lockInfo != nil }

  public func registerAgentFunction(
    name: String,
    summary: String,
    parameters: [String] = [],
    durabilityCost: Int = 0,
    handler: @escaping AgentObjectFunctionHandler
  ) throws {
    try registerFunction(
      name: name,
      summary: summary,
      parameters: parameters,
      durabilityCost: durabilityCost,
      audience: .agent
    ) { context, arguments in
      try context.withPackageContext { packageContext in
        try handler(packageContext, arguments)
      }
    }
  }

  public func registerObjectFunction(
    name: String,
    summary: String,
    parameters: [String] = [],
    durabilityCost: Int = 0,
    handler: @escaping AgentObjectFunctionHandler
  ) throws {
    try registerPackageFunction(
      name: name,
      summary: summary,
      parameters: parameters,
      durabilityCost: durabilityCost,
      audience: .object,
      handler: handler
    )
  }

  public func registerSharedFunction(
    name: String,
    summary: String,
    parameters: [String] = [],
    durabilityCost: Int = 0,
    handler: @escaping AgentObjectFunctionHandler
  ) throws {
    try registerPackageFunction(
      name: name,
      summary: summary,
      parameters: parameters,
      durabilityCost: durabilityCost,
      audience: .both,
      handler: handler
    )
  }

  private func registerPackageFunction(
    name: String,
    summary: String,
    parameters: [String],
    durabilityCost: Int,
    audience: ObjectFunctionAudience,
    handler: @escaping AgentObjectFunctionHandler
  ) throws {
    try registerFunction(
      name: name,
      summary: summary,
      parameters: parameters,
      durabilityCost: durabilityCost,
      audience: audience
    ) { context, arguments in
      try context.withPackageContext { packageContext in
        try handler(packageContext, arguments)
      }
    }
  }

  func registerFunction(
    name: String,
    summary: String,
    parameters: [String] = [],
    durabilityCost: Int = 0,
    audience: ObjectFunctionAudience = .agent,
    handler: @escaping TrustedObjectFunctionHandler
  ) throws {
    let normalized = name.lowercased()
    guard !normalized.isEmpty, normalized.count <= 128,
      !normalized.contains(where: { $0.isWhitespace || $0.isNewline })
    else {
      throw MikroKhorosError.function(
        "function names must be a single token of at most 128 characters"
      )
    }
    guard summary.count <= 512, !summary.contains(where: { $0.isNewline }) else {
      throw MikroKhorosError.function(
        "function summaries must be one line of at most 512 characters"
      )
    }
    guard
      parameters.allSatisfy({
        !$0.isEmpty && $0.count <= 128 && !$0.contains(where: { $0.isWhitespace || $0.isNewline })
      })
    else {
      throw MikroKhorosError.function(
        "function parameters must be single tokens of at most 128 characters"
      )
    }
    guard functions[normalized] == nil else {
      throw MikroKhorosError.function("function '\(normalized)' is already registered")
    }
    guard durabilityCost >= 0 else {
      throw MikroKhorosError.function("durability cost cannot be negative")
    }
    functions[normalized] = PublicFunction(
      name: normalized,
      summary: summary,
      parameters: parameters,
      durabilityCost: durabilityCost,
      audience: audience,
      handler: handler
    )
  }

  func invoke(
    _ functionName: String,
    arguments: [String],
    harness: Harness,
    agent: Agent
  ) throws -> String {
    try harness.validateDirectInvocation(of: self, for: agent)
    return try invoke(
      functionName,
      arguments: arguments,
      harness: harness,
      agent: agent,
      identity: ObjectInvocationIdentity(
        invocationID: harness.nextRuntimeIdentity(),
        objectID: hash,
        agentID: agent.hash,
        worldID: harness.world.hash,
        lineage: lineage
      ),
      caller: .agent
    )
  }

  func invokeFromObject(
    _ functionName: String,
    arguments: [String],
    harness: Harness,
    agent: Agent,
    callingObject: MikroObject,
    parentIdentity: ObjectInvocationIdentity
  ) throws -> String {
    let depth = parentIdentity.callDepth + 1
    guard depth <= harness.limits.maximumObjectInvocationDepth else {
      throw MikroKhorosError.runtime(
        "object.invocation_depth_exceeded",
        "the nested object invocation depth limit was reached",
        details: ["limit": String(harness.limits.maximumObjectInvocationDepth)],
        suggestions: ["remove the recursive object-call chain"]
      )
    }
    let identity = ObjectInvocationIdentity(
      rootInvocationID: parentIdentity.rootInvocationID,
      currentInvocationID: harness.nextRuntimeIdentity(),
      targetObjectID: hash,
      callingObjectID: callingObject.hash,
      originalAgentID: parentIdentity.originalAgentID,
      worldID: parentIdentity.worldID,
      callDepth: depth,
      lineage: lineage
    )
    let result = try invoke(
      functionName,
      arguments: arguments,
      harness: harness,
      agent: agent,
      identity: identity,
      caller: .object
    )
    try harness.recordNestedInvocation(
      identity: identity,
      source: callingObject,
      target: self,
      function: functionName.lowercased(),
      result: result
    )
    return result
  }

  private func invoke(
    _ functionName: String,
    arguments: [String],
    harness: Harness,
    agent: Agent,
    identity: ObjectInvocationIdentity,
    caller: ObjectFunctionAudience
  ) throws -> String {
    try (self as? LiveWorldObject)?.prepareForInteraction(harness: harness)
    let normalized = functionName.lowercased()
    guard let function = functions[normalized] else {
      let names = callableFunctionNames(for: caller).joined(separator: ", ")
      let code = caller == .object ? "object.target_function_missing" : "function.unknown"
      throw MikroKhorosError.runtime(
        code,
        "the requested function is unavailable on the target object",
        details: ["function": normalized, "available": names.isEmpty ? "none" : names],
        suggestions: ["inspect the target and choose one of its compatible functions"]
      )
    }
    let allowed =
      caller == .agent ? function.audience.acceptsAgent : function.audience.acceptsObject
    guard allowed else {
      throw MikroKhorosError.runtime(
        "object.target_invocation_denied",
        "the requested function does not accept this caller",
        details: ["function": normalized, "audience": function.audience.rawValue],
        suggestions: ["use a function whose audience accepts this caller"]
      )
    }
    if function.durabilityCost > 0 {
      guard let durability else {
        throw MikroKhorosError.function(
          "this function requires an object with durability"
        )
      }
      guard durability >= function.durabilityCost else {
        throw MikroKhorosError.function("object has no durability remaining")
      }
    }
    let result = try function.handler(
      TrustedInvocationContext(harness: harness, agent: agent, object: self, identity: identity),
      arguments
    )
    if function.durabilityCost > 0, let durability {
      self.durability = durability - function.durabilityCost
    }
    return result
  }

  func relativeInspection() -> ObjectRelativeInspection {
    ObjectRelativeInspection(
      objectID: hash,
      type: typeName,
      name: name,
      coordinate: coordinate ?? .origin,
      functions: callableFunctionNames(for: .object)
    )
  }

  private func callableFunctionNames(for caller: ObjectFunctionAudience) -> [String] {
    functions.values.filter {
      caller == .agent ? $0.audience.acceptsAgent : $0.audience.acceptsObject
    }.map(\.name).sorted()
  }

  public func inspect() -> ObjectInspection {
    ObjectInspection(
      name: name,
      typeName: typeName,
      hash: hash,
      summary: summary,
      durability: durability,
      maximumDurability: maximumDurability,
      origin: origin,
      invocationAccess: invocationAccess,
      lineage: lineage,
      capturedCapabilities: capturedCapabilities,
      publicData: publicData,
      hasContainerCapability: container != nil,
      lock: lockInfo,
      functions: functions.values.sorted { $0.name < $1.name }
    )
  }

  public func walkContents() -> [MikroObject] {
    guard let container else { return [] }
    var result: [MikroObject] = []
    for item in container.items {
      result.append(item.object)
      result.append(contentsOf: item.object.walkContents())
    }
    return result
  }

  open func freshCopy(hash: String? = nil) throws -> MikroObject {
    let copy = try MikroObject(
      typeName: typeName,
      name: name,
      summary: summary,
      publicData: publicData,
      durability: maximumDurability,
      origin: origin,
      invocationAccess: invocationAccess,
      capturedCapabilities: capturedCapabilities,
      lineage: lineage,
      credentialHandles: deploymentCredentialHandles,
      instanceRevision: instanceRevision,
      hash: hash
    )
    if container != nil { try copy.addContainerCapability() }
    return copy
  }

  func bind(to space: Space, at coordinate: Coordinate) {
    parentSpace = space
    self.coordinate = coordinate
  }

  func unbind() {
    parentSpace = nil
    coordinate = nil
  }
}

struct NavigationFrame {
  let space: Space
  let coordinate: Coordinate
}

actor AgentRequestGate {
  private var nextTicket: UInt64 = 0
  private var servingTicket: UInt64 = 0
  private var waiters: [UInt64: CheckedContinuation<Void, Never>] = [:]

  func acquire() async -> UInt64 {
    let ticket = nextTicket
    nextTicket += 1
    if ticket != servingTicket {
      await withCheckedContinuation { continuation in
        waiters[ticket] = continuation
      }
    }
    return ticket
  }

  func release(_ ticket: UInt64) {
    precondition(ticket == servingTicket, "agent request tickets must be released in order")
    servingTicket += 1
    waiters.removeValue(forKey: servingTicket)?.resume()
  }
}

public final class Agent {
  public let hash: String
  public let name: String
  public var space: Space
  public var coordinate: Coordinate
  /// The four independent carrying roots. Slot one is the default primary
  /// surface for the action language; the other slots remain carried and
  /// continue to participate in ownership and broadcast checks.
  public internal(set) var holdings: AgentHoldings
  public let backpack: MikroObject
  public let wallet: WalletObject
  public var isInWorld = false
  public var hasEnteredWorld = false
  public internal(set) var aiProfile: AIProfile?
  public private(set) var maximumActionsPerResponse: Int
  public var knownHashes: Set<String> = []
  public var pendingBroadcasts: [AgentBroadcastEvent] = []
  let requestGate = AgentRequestGate()
  var backpackReturn: NavigationFrame?

  init(
    name: String,
    worldSpace: Space,
    backpack: MikroObject,
    wallet: WalletObject,
    holdings: AgentHoldings? = nil,
    maximumActionsPerResponse: Int = 8,
    hash: String? = nil
  ) throws {
    guard maximumActionsPerResponse > 0 else {
      throw MikroKhorosError.command("maximum actions must be a positive integer")
    }
    guard backpack.container != nil else {
      throw MikroKhorosError.placement(
        "an agent's backpack must have container capability"
      )
    }
    self.hash = hash ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    self.name = name
    self.space = worldSpace
    self.coordinate = .origin
    self.backpack = backpack
    self.wallet = wallet
    self.holdings = try holdings ?? AgentHoldings()
    self.maximumActionsPerResponse = maximumActionsPerResponse
  }

  public var primaryHoldingNumber: HoldingNumber { holdings.primaryHoldingNumber }

  public var primaryHeldObject: MikroObject? { holdings.primaryHeldObject }

  public var isLoaded: Bool { !holdings.occupiedRoots.isEmpty }

  public var isInBackpack: Bool { space === backpack.container }

  func setMaximumActionsPerResponse(_ value: Int) throws {
    guard value > 0 else {
      throw MikroKhorosError.command("maximum actions must be a positive integer")
    }
    maximumActionsPerResponse = value
  }

}
