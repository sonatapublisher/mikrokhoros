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
    Coordinate(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
  }

  public static func - (lhs: Coordinate, rhs: Coordinate) -> Coordinate {
    Coordinate(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
  }

  public func scaled(by amount: Int) -> Coordinate {
    Coordinate(x: x * amount, y: y * amount)
  }

  public func offset(x: Int, y: Int) -> Coordinate {
    Coordinate(x: self.x + x, y: self.y + y)
  }

  public func manhattanDistance(to other: Coordinate) -> Int {
    abs(x - other.x) + abs(y - other.y)
  }

  public static func < (lhs: Coordinate, rhs: Coordinate) -> Bool {
    lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
  }

  public var description: String { "(\(x),\(y))" }
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
    guard let value = numberValue, value.rounded() == value,
      value >= Double(Int.min), value <= Double(Int.max)
    else { return nil }
    return Int(value)
  }

  var boolValue: Bool? {
    guard case .bool(let value) = self else { return nil }
    return value
  }
}

public struct InvocationContext {
  public let harness: Harness
  public let agent: Agent
  public let object: MikroObject
  public let identity: ObjectInvocationIdentity

  init(harness: Harness, agent: Agent, object: MikroObject) {
    self.harness = harness
    self.agent = agent
    self.object = object
    self.identity = ObjectInvocationIdentity(
      objectID: object.hash,
      installationID: object.installationID,
      agentID: agent.hash,
      worldID: harness.world.hash
    )
  }
}

public typealias ObjectFunctionHandler = (InvocationContext, [String]) throws -> String

public struct PublicFunction {
  public let name: String
  public let summary: String
  public let parameters: [String]
  public let durabilityCost: Int
  let handler: ObjectFunctionHandler

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
  public let installationID: String?
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

  public func place(_ object: MikroObject, at coordinate: Coordinate) throws {
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
  public func remove(at coordinate: Coordinate) throws -> MikroObject {
    guard let object = cells.removeValue(forKey: coordinate) else {
      throw MikroKhorosError.placement("coordinate \(coordinate) is empty")
    }
    object.unbind()
    return object
  }

  public func move(from source: Coordinate, to destination: Coordinate) throws {
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
  public let installationID: String?
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
    installationID: String? = nil,
    hash: String? = nil
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
    self.typeName = typeName
    self.name = resolvedName
    self.summary = summary
    self.publicData = publicData
    self.durability = durability
    self.maximumDurability = durability
    self.origin = origin
    self.invocationAccess = invocationAccess
    self.installationID = installationID
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

  public func registerFunction(
    name: String,
    summary: String,
    parameters: [String] = [],
    durabilityCost: Int = 0,
    handler: @escaping ObjectFunctionHandler
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
      handler: handler
    )
  }

  public func invoke(
    _ functionName: String,
    arguments: [String],
    harness: Harness,
    agent: Agent
  ) throws -> String {
    let normalized = functionName.lowercased()
    guard let function = functions[normalized] else {
      let names = functions.keys.sorted().joined(separator: ", ")
      throw MikroKhorosError.function(
        "unknown function; available: \(names.isEmpty ? "none" : names)"
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
      InvocationContext(harness: harness, agent: agent, object: self),
      arguments
    )
    if function.durabilityCost > 0, let durability {
      self.durability = durability - function.durabilityCost
    }
    return result
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
      installationID: installationID,
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
      installationID: installationID,
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
  public var hand: MikroObject?
  public let backpack: MikroObject
  public let coin: CoinObject
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
    coin: CoinObject,
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
    self.coin = coin
    self.maximumActionsPerResponse = maximumActionsPerResponse
  }

  public var isInBackpack: Bool { space === backpack.container }

  func setMaximumActionsPerResponse(_ value: Int) throws {
    guard value > 0 else {
      throw MikroKhorosError.command("maximum actions must be a positive integer")
    }
    maximumActionsPerResponse = value
  }

}
