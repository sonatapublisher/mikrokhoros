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

private func requireGenesisArguments(
  _ arguments: [String],
  minimum: Int,
  maximum: Int? = nil
) throws {
  let upper = maximum ?? minimum
  guard arguments.count >= minimum, arguments.count <= upper else {
    let expected = minimum == upper ? "exactly \(minimum)" : "between \(minimum) and \(upper)"
    throw MikroKhorosError.function(
      "expected \(expected) argument(s), received \(arguments.count)"
    )
  }
}

public final class AthenaObject: MikroObject {
  public init(
    origin: ObjectOrigin = .genesis,
    lineage: ObjectLineage? = nil,
    hash: String? = nil
  ) throws {
    try super.init(
      typeName: "athena.object",
      name: "Athena",
      summary: "The deterministic steward of the Default Khoros facilities.",
      publicData: [
        "behavior": .string("deterministic"),
        "role": .string("orientation and human-authored world-change notices"),
      ],
      origin: origin,
      invocationAccess: .surface,
      lineage: lineage,
      hash: hash
    )
    try registerFunction(name: "brief", summary: "Explain the nearby template facilities.") {
      context, arguments in
      try requireGenesisArguments(arguments, minimum: 0)
      let athena = context.object as! AthenaObject
      let applicationID = athena.lineage?.worldTemplate?.applicationID
      let places =
        context.harness.world.container?.items.compactMap { item -> String? in
          guard let component = item.object.lineage?.worldTemplate,
            component.applicationID == applicationID,
            component.componentKey != DefaultKhorosComponent.athena.rawValue
          else { return nil }
          let purpose: String
          switch component.componentKey {
          case DefaultKhorosComponent.objectiveBoard.rawValue:
            purpose = "enter to discover, register, and submit objective work"
          case DefaultKhorosComponent.library.rawValue:
            purpose = "enter to find and read sourced documents"
          case DefaultKhorosComponent.warehouse.rawValue:
            purpose = "enter to share concrete tools and resources"
          case DefaultKhorosComponent.marketplace.rawValue:
            purpose = "enter to purchase concrete objects from the merchant"
          default: return nil
          }
          return """
                - name: \(PromptSafety.yamlScalar(item.object.name, limit: 128))
                  at: \(PromptSafety.yamlScalar("\(item.coordinate)@world"))
                  purpose: \(PromptSafety.yamlScalar(purpose))
            """
        }.sorted() ?? []
      return
        ([
          "guide:",
          "  steward: \(PromptSafety.yamlScalar(athena.name))",
          "  kind: \(PromptSafety.yamlScalar("deterministic object"))",
          places.isEmpty ? "  places: []" : "  places:",
        ] + places).joined(separator: "\n")
    }
    try lock(
      authority: .system,
      owner: self.hash,
      reason: origin == .genesis ? "genesis_anchor" : "template_anchor"
    )
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try AthenaObject(origin: origin, lineage: lineage, hash: hash)
  }
}

public enum ObjectiveState: String, Codable, Sendable {
  case open
  case inProgress = "in_progress"
}

/// The append-only kinds of work an agent may submit to an objective.
///
/// A registration is represented as a record as well as projected into the
/// objective's participant set. The other kinds retain their submitted body;
/// subsequent submissions never replace an earlier record.
public enum ObjectiveRecordKind: String, Codable, Sendable {
  case registration = "register"
  case progress
  case final
  case revision

  /// Verb-form compatibility for callers that use the runtime function name.
  public static var register: Self { .registration }

  public init?(rawValue: String) {
    switch rawValue {
    case "register", "registration": self = .registration
    case "progress": self = .progress
    case "final": self = .final
    case "revision": self = .revision
    default: return nil
    }
  }
}

/// One immutable, model-visible submission to an objective.
///
/// `id` is the runtime event identity. `recordID`, `eventID`, and `text` are
/// read-only aliases that make the record convenient for journal integrations
/// and callers that use event-oriented terminology without adding duplicate
/// encoded fields.
public struct ObjectiveRecord: Codable, Equatable, Sendable {
  public static let maximumBodyCharacters = RuntimeLimits.defaults.maximumModelFieldCharacters

  public let id: String
  public let agentID: String
  public let kind: ObjectiveRecordKind
  public let body: String
  public let timestamp: Date

  public var recordID: String { id }
  public var eventID: String { id }
  public var text: String { body }

  public init(
    id: String,
    agentID: String,
    kind: ObjectiveRecordKind,
    body: String = "",
    timestamp: Date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
  ) throws {
    try Self.validate(
      id: id,
      agentID: agentID,
      kind: kind,
      body: body,
      timestamp: timestamp,
      maximumBodyCharacters: Self.maximumBodyCharacters
    )
    self.id = id
    self.agentID = agentID
    self.kind = kind
    self.body = body
    self.timestamp = timestamp
  }

  public init(
    eventID: String,
    agentID: String,
    kind: ObjectiveRecordKind,
    body: String = "",
    timestamp: Date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
  ) throws {
    try self.init(
      id: eventID,
      agentID: agentID,
      kind: kind,
      body: body,
      timestamp: timestamp
    )
  }

  private enum CodingKeys: String, CodingKey {
    case id, agentID, kind, body, timestamp
  }

  public init(from decoder: Decoder) throws {
    let keys = try decoder.container(keyedBy: ObjectiveRecordAnyCodingKey.self)
    guard
      keys.allKeys.allSatisfy({
        CodingKeys(rawValue: $0.stringValue) != nil
      })
    else {
      throw MikroKhorosError.persistence("objective record contains an unknown field")
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(String.self, forKey: .id),
      agentID: container.decode(String.self, forKey: .agentID),
      kind: container.decode(ObjectiveRecordKind.self, forKey: .kind),
      body: container.decodeIfPresent(String.self, forKey: .body) ?? "",
      timestamp: container.decode(Date.self, forKey: .timestamp)
    )
  }

  /// Validates a record against a host's active model-field limit before the
  /// runtime allocates an entropy identity or timestamp for it.
  static func validate(
    id: String,
    agentID: String,
    kind: ObjectiveRecordKind,
    body: String,
    timestamp: Date,
    maximumBodyCharacters: Int
  ) throws {
    guard !id.isEmpty, id.count <= 128,
      !id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else {
      throw MikroKhorosError.persistence("objective record identity is invalid")
    }
    guard !agentID.isEmpty, agentID.count <= 128,
      !agentID.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else {
      throw MikroKhorosError.persistence("objective record agent identity is invalid")
    }
    guard maximumBodyCharacters > 0, body.count <= maximumBodyCharacters else {
      throw MikroKhorosError.persistence("objective record body exceeds its configured limit")
    }
    guard timestamp.timeIntervalSince1970.isFinite,
      timestamp.timeIntervalSince1970 == floor(timestamp.timeIntervalSince1970)
    else {
      throw MikroKhorosError.persistence("objective record timestamp must use integral seconds")
    }
    if kind == .registration {
      guard body.isEmpty else {
        throw MikroKhorosError.persistence("objective registration records cannot contain a body")
      }
    } else {
      guard !body.isEmpty else {
        throw MikroKhorosError.persistence("objective submission body cannot be empty")
      }
    }
  }
}

private struct ObjectiveRecordAnyCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

/// Event-oriented spelling retained for world-journal integrations.
public typealias ObjectiveAgentRecord = ObjectiveRecord
public typealias ObjectiveEvent = ObjectiveRecord

/// Exact runtime identity for the shared Objective Board facility. Keeping a
/// concrete type (rather than dispatching on a package id or type-name string)
/// lets the trusted human management provider expose only this world object.
public final class ObjectiveBoardObject: MikroObject {
  public init(
    name: String = "Objective Board",
    summary: String = "A shared container where agents discover and pursue concrete objectives.",
    origin: ObjectOrigin = .native,
    lineage: ObjectLineage? = nil,
    hash: String? = nil
  ) throws {
    try super.init(
      typeName: "objective-board.object",
      name: name,
      summary: summary,
      origin: origin,
      invocationAccess: .surface,
      lineage: lineage,
      hash: hash
    )
    try addContainerCapability()
    try registerFunction(
      name: "view",
      summary: "View the objectives currently on the board."
    ) { context, arguments in
      guard arguments.isEmpty else {
        throw MikroKhorosError.function("view takes no arguments")
      }
      let objectives = context.harness.objects.compactMap { $0 as? ObjectiveObject }
      guard !objectives.isEmpty else { return "objectives: []" }
      return objectives.sorted { $0.hash < $1.hash }.map { objective in
        "- id: \(PromptSafety.yamlScalar(objective.hash))\n  title: \(PromptSafety.yamlScalar(objective.title))\n  status: \(objective.state.rawValue)"
      }.joined(separator: "\n")
    }
    try lock(
      authority: .system,
      owner: self.hash,
      reason: origin == .genesis ? "genesis_anchor" : "template_anchor"
    )
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    throw MikroKhorosError.objectPackage(
      "objective-board.object is a trusted facility and cannot be copied")
  }
}

public final class ObjectiveObject: MikroObject {
  public let title: String
  public let body: String
  public let createdAt: Date
  public private(set) var participantAgentIDs: Set<String> = []
  public private(set) var records: [ObjectiveRecord] = []

  public var state: ObjectiveState {
    return participantAgentIDs.isEmpty ? .open : .inProgress
  }

  /// The shared submissions currently attached to this objective, in append
  /// order. The returned value is a copy, so callers cannot overwrite prior
  /// records or reorder the objective's history.
  public var objectiveRecords: [ObjectiveRecord] { records }

  public func records(for agentID: String) -> [ObjectiveRecord] {
    records.filter { $0.agentID == agentID }
  }

  public init(
    title: String,
    body: String,
    createdAt: Date,
    origin: ObjectOrigin = .native,
    lineage: ObjectLineage? = nil,
    hash: String? = nil
  ) throws {
    self.title = title
    self.body = body
    self.createdAt = createdAt
    try super.init(
      typeName: "objective.object",
      name: title,
      summary: "A concrete objective posted by the human user.",
      publicData: ["status": .string(ObjectiveState.open.rawValue)],
      origin: origin,
      invocationAccess: .surface,
      lineage: lineage,
      hash: hash
    )
    try registerFunction(name: "read", summary: "Read the objective and its current state.") {
      context, arguments in
      try requireGenesisArguments(arguments, minimum: 0)
      return (context.object as! ObjectiveObject).render(limits: context.harness.limits)
    }
    try registerFunction(
      name: "register",
      summary: "Join this objective as a collaborating agent."
    ) { context, arguments in
      try requireGenesisArguments(arguments, minimum: 0)
      let objective = context.object as! ObjectiveObject
      guard !objective.participantAgentIDs.contains(context.agent.hash) else {
        return "already registered"
      }
      _ = try objective.append(
        kind: .registration,
        body: "",
        agentID: context.agent.hash,
        harness: context.harness
      )
      return "registered for objective #\(objective.hash)"
    }
    try registerFunction(
      name: "progress",
      summary: "Append a progress update to this objective.",
      parameters: ["text"]
    ) { context, arguments in
      try requireGenesisArguments(arguments, minimum: 1, maximum: 1)
      let objective = context.object as! ObjectiveObject
      try objective.requireRegistered(context.agent)
      _ = try objective.append(
        kind: .progress,
        body: arguments[0],
        agentID: context.agent.hash,
        harness: context.harness
      )
      return "submitted progress for objective #\(objective.hash)"
    }
    try registerFunction(
      name: "final",
      summary: "Append the one final submission allowed for this objective.",
      parameters: ["text"]
    ) { context, arguments in
      try requireGenesisArguments(arguments, minimum: 1, maximum: 1)
      let objective = context.object as! ObjectiveObject
      try objective.requireRegistered(context.agent)
      guard
        !objective.records.contains(where: {
          $0.agentID == context.agent.hash && $0.kind == .final
        })
      else {
        throw MikroKhorosError.runtime(
          "objective.final_already_submitted",
          "this agent has already submitted a final for the objective",
          suggestions: ["use `object (revision (text))` to append a later correction"]
        )
      }
      _ = try objective.append(
        kind: .final,
        body: arguments[0],
        agentID: context.agent.hash,
        harness: context.harness
      )
      return "submitted final for objective #\(objective.hash)"
    }
    try registerFunction(
      name: "revision",
      summary: "Append a revision after this agent has submitted a final.",
      parameters: ["text"]
    ) { context, arguments in
      try requireGenesisArguments(arguments, minimum: 1, maximum: 1)
      let objective = context.object as! ObjectiveObject
      try objective.requireRegistered(context.agent)
      guard
        objective.records.contains(where: {
          $0.agentID == context.agent.hash && $0.kind == .final
        })
      else {
        throw MikroKhorosError.runtime(
          "objective.final_required",
          "an agent must submit a final before submitting a revision",
          suggestions: ["run `object (final (text))` before revising it"]
        )
      }
      _ = try objective.append(
        kind: .revision,
        body: arguments[0],
        agentID: context.agent.hash,
        harness: context.harness
      )
      return "submitted revision for objective #\(objective.hash)"
    }
    refreshPublicState()
  }

  private func refreshPublicState() {
    setPublicData(.string(state.rawValue), forKey: "status")
    setPublicData(
      .array(participantAgentIDs.sorted().map(JSONValue.string)),
      forKey: "participants"
    )
    setPublicData(.number(Double(records.count)), forKey: "record_count")
  }

  private func render(limits: RuntimeLimits) -> String {
    let formatter = ISO8601DateFormatter()
    var lines = [
      "objective:",
      "  id: \(PromptSafety.yamlScalar(hash, limit: 128))",
      "  title: \(PromptSafety.yamlScalar(title, limit: limits.maximumModelFieldCharacters))",
      "  status: \(state.rawValue)",
      "  created_at: \(PromptSafety.yamlScalar(formatter.string(from: createdAt)))",
      "  body: \(PromptSafety.yamlScalar(body, limit: limits.maximumModelFieldCharacters))",
    ]
    if participantAgentIDs.isEmpty {
      lines.append("  participants: []")
    } else {
      lines.append("  participants:")
      for participant in participantAgentIDs.sorted() {
        lines.append("    - \(PromptSafety.yamlScalar(participant, limit: 128))")
      }
    }
    if records.isEmpty {
      lines.append("  records: []")
    } else {
      lines.append("  records:")
      for record in records {
        lines.append("    - id: \(PromptSafety.yamlScalar(record.id, limit: 128))")
        lines.append("      agent: \(PromptSafety.yamlScalar(record.agentID, limit: 128))")
        lines.append("      kind: \(PromptSafety.yamlScalar(record.kind.rawValue, limit: 32))")
        lines.append(
          "      timestamp: \(PromptSafety.yamlScalar(formatter.string(from: record.timestamp)))"
        )
        lines.append(
          "      body: \(PromptSafety.yamlScalar(record.body, limit: limits.maximumModelFieldCharacters))"
        )
      }
    }
    return lines.joined(separator: "\n")
  }

  private func requireRegistered(_ agent: Agent) throws {
    guard participantAgentIDs.contains(agent.hash) else {
      throw MikroKhorosError.runtime(
        "objective.not_registered",
        "the agent is not registered for this objective",
        suggestions: ["run `object (register)` before submitting objective work"]
      )
    }
  }

  @discardableResult
  private func append(
    kind: ObjectiveRecordKind,
    body: String,
    agentID: String,
    harness: Harness
  ) throws -> ObjectiveRecord {
    let maximumBodyCharacters = harness.limits.maximumModelFieldCharacters
    guard body.count <= maximumBodyCharacters else {
      throw MikroKhorosError.runtime(
        "objective.body_too_large",
        "the objective submission exceeds the configured model-field limit",
        details: ["limit": String(maximumBodyCharacters)]
      )
    }
    if kind == .registration {
      guard body.isEmpty else {
        throw MikroKhorosError.runtime(
          "objective.body_invalid",
          "objective registration does not accept a body"
        )
      }
    } else {
      guard !body.isEmpty else {
        throw MikroKhorosError.runtime(
          "objective.body_invalid",
          "objective submissions require non-empty text"
        )
      }
    }

    // Keep the order identical to the other runtime event producers: one
    // identity followed by one timestamp. World action entropy records both,
    // so replay receives exactly the same values before applying this append.
    let id = harness.nextRuntimeIdentity()
    let rawTimestamp = harness.runtimeDate()
    let interval = rawTimestamp.timeIntervalSince1970
    let timestamp = Date(timeIntervalSince1970: floor(interval))
    let record = try ObjectiveRecord(
      id: id,
      agentID: agentID,
      kind: kind,
      body: body,
      timestamp: timestamp
    )
    guard !records.contains(where: { $0.id == record.id }) else {
      throw MikroKhorosError.runtime(
        "objective.record_identity_conflict",
        "the objective record identity has already been used"
      )
    }
    records.append(record)
    if kind == .registration { participantAgentIDs.insert(agentID) }
    refreshPublicState()
    return record
  }

  /// Applies a previously journaled record without allocating new entropy.
  /// This is intentionally internal: agents must use the four object
  /// functions so registration and per-agent finality rules are mediated at
  /// invocation time, while the world loader can replay an immutable record
  /// if it stores objective submissions as explicit events.
  @discardableResult
  func applyPersistedRecord(
    _ record: ObjectiveRecord,
    maximumBodyCharacters: Int = ObjectiveRecord.maximumBodyCharacters
  ) throws -> Bool {
    if let existing = records.first(where: { $0.id == record.id }) {
      guard existing == record else {
        throw MikroKhorosError.persistence(
          "objective record identity has conflicting replay content"
        )
      }
      return false
    }
    guard record.agentID.count <= 128 else {
      throw MikroKhorosError.persistence("objective record agent identity is invalid")
    }
    switch record.kind {
    case .registration:
      guard !participantAgentIDs.contains(record.agentID) else {
        throw MikroKhorosError.persistence("objective registration is duplicated")
      }
    case .progress:
      guard participantAgentIDs.contains(record.agentID) else {
        throw MikroKhorosError.persistence("objective progress precedes registration")
      }
    case .final:
      guard participantAgentIDs.contains(record.agentID),
        !records.contains(where: { $0.agentID == record.agentID && $0.kind == .final })
      else {
        throw MikroKhorosError.persistence("objective final record is invalid")
      }
    case .revision:
      guard participantAgentIDs.contains(record.agentID),
        records.contains(where: { $0.agentID == record.agentID && $0.kind == .final })
      else {
        throw MikroKhorosError.persistence("objective revision precedes its agent final")
      }
    }
    try ObjectiveRecord.validate(
      id: record.id,
      agentID: record.agentID,
      kind: record.kind,
      body: record.body,
      timestamp: record.timestamp,
      maximumBodyCharacters: maximumBodyCharacters
    )
    records.append(record)
    if record.kind == .registration { participantAgentIDs.insert(record.agentID) }
    refreshPublicState()
    return true
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try ObjectiveObject(
      title: title,
      body: body,
      createdAt: createdAt,
      origin: origin,
      lineage: lineage,
      hash: hash
    )
  }
}

public final class ObjectiveIndexObject: MikroObject {
  public let boardID: String

  public init(
    boardID: String,
    origin: ObjectOrigin = .genesis,
    lineage: ObjectLineage? = nil,
    hash: String? = nil
  ) throws {
    self.boardID = boardID
    try super.init(
      typeName: "objective-index.object",
      name: "Objective Index",
      summary: "The directory inside the Objective Board.",
      origin: origin,
      invocationAccess: .surface,
      lineage: lineage,
      hash: hash
    )
    try registerFunction(name: "list", summary: "List objectives and their local positions.") {
      context, arguments in
      try requireGenesisArguments(arguments, minimum: 0)
      let index = context.object as! ObjectiveIndexObject
      let board = try context.harness.object(byHash: index.boardID)
      let objectives =
        board.container?.items.compactMap { item in
          (item.object as? ObjectiveObject).map { (item.coordinate, $0) }
        } ?? []
      guard !objectives.isEmpty else { return "objectives: []" }
      var lines = ["objectives:"]
      for (coordinate, objective) in objectives {
        lines.append("  - id: \(PromptSafety.yamlScalar(objective.hash, limit: 128))")
        lines.append(
          "    title: \(PromptSafety.yamlScalar(objective.title, limit: context.harness.limits.maximumModelFieldCharacters))"
        )
        lines.append("    status: \(objective.state.rawValue)")
        lines.append("    at: \(PromptSafety.yamlScalar(coordinate.description))")
        lines.append("    participants: \(objective.participantAgentIDs.count)")
      }
      return lines.joined(separator: "\n")
    }
    try lock(
      authority: .system,
      owner: self.hash,
      reason: origin == .genesis ? "genesis_anchor" : "template_child"
    )
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try ObjectiveIndexObject(boardID: boardID, origin: origin, lineage: lineage, hash: hash)
  }
}

public final class WarehouseDirectoryObject: MikroObject {
  public let warehouseID: String

  public init(
    warehouseID: String,
    origin: ObjectOrigin = .genesis,
    lineage: ObjectLineage? = nil,
    hash: String? = nil
  ) throws {
    self.warehouseID = warehouseID
    try super.init(
      typeName: "warehouse-directory.object",
      name: "Warehouse Directory",
      summary: "Lists the concrete objects currently stored in the shared warehouse.",
      origin: origin,
      invocationAccess: .surface,
      lineage: lineage,
      hash: hash
    )
    try registerFunction(name: "list", summary: "List stored objects and local positions.") {
      context, arguments in
      try requireGenesisArguments(arguments, minimum: 0)
      let directory = context.object as! WarehouseDirectoryObject
      let warehouse = try context.harness.object(byHash: directory.warehouseID)
      let items = warehouse.container?.items.filter { $0.object !== directory } ?? []
      guard !items.isEmpty else { return "inventory: []" }
      var lines = ["inventory:"]
      for item in items {
        lines.append("  - at: \(PromptSafety.yamlScalar(item.coordinate.description))")
        lines.append("    id: \(PromptSafety.yamlScalar(item.object.hash, limit: 128))")
        lines.append("    type: \(PromptSafety.yamlScalar(item.object.typeName, limit: 128))")
        lines.append("    name: \(PromptSafety.yamlScalar(item.object.name, limit: 128))")
      }
      return lines.joined(separator: "\n")
    }
    try lock(
      authority: .system,
      owner: self.hash,
      reason: origin == .genesis ? "genesis_anchor" : "template_child"
    )
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try WarehouseDirectoryObject(
      warehouseID: warehouseID, origin: origin, lineage: lineage, hash: hash)
  }
}

public final class LibraryDocumentObject: MikroObject {
  public let title: String
  public let sourceURL: String
  public let content: String
  public let fetchedAt: Date

  public init(
    title: String,
    sourceURL: String,
    content: String,
    fetchedAt: Date,
    origin: ObjectOrigin = .native,
    lineage: ObjectLineage? = nil,
    hash: String? = nil
  ) throws {
    self.title = title
    self.sourceURL = sourceURL
    self.content = content
    self.fetchedAt = fetchedAt
    try super.init(
      typeName: "document.object",
      name: title,
      summary: "A sourced document stored in the world library.",
      publicData: [
        "characters": .number(Double(content.count)),
        "source": .string(sourceURL),
        "trust": .string("external_untrusted"),
      ],
      origin: origin,
      invocationAccess: .surface,
      lineage: lineage,
      hash: hash
    )
    try registerFunction(name: "read", summary: "Read the first bounded document page.") {
      context, arguments in
      try requireGenesisArguments(arguments, minimum: 0)
      return try (context.object as! LibraryDocumentObject).renderPage(
        start: 0,
        requestedCount: context.harness.limits.maximumModelFieldCharacters,
        limits: context.harness.limits
      )
    }
    try registerFunction(
      name: "read_range",
      summary: "Read a bounded character range.",
      parameters: ["start", "length"]
    ) { context, arguments in
      try requireGenesisArguments(arguments, minimum: 2)
      guard let start = Int(arguments[0]), start >= 0,
        let length = Int(arguments[1]), length > 0
      else {
        throw MikroKhorosError.function(
          "document range requires a non-negative start and positive length")
      }
      return try (context.object as! LibraryDocumentObject).renderPage(
        start: start,
        requestedCount: length,
        limits: context.harness.limits
      )
    }
  }

  private func renderPage(
    start: Int,
    requestedCount: Int,
    limits: RuntimeLimits
  ) throws -> String {
    guard start <= content.count else {
      throw MikroKhorosError.runtime(
        "document.range_out_of_bounds",
        "document range starts beyond the available content",
        suggestions: ["use a start between 0 and \(content.count)"]
      )
    }
    let pageLimit = limits.maximumModelFieldCharacters
    let count = min(requestedCount, pageLimit, content.count - start)
    let lower = content.index(content.startIndex, offsetBy: start)
    let upper = content.index(lower, offsetBy: count)
    let page = String(content[lower..<upper])
    let end = start + count
    let formatter = ISO8601DateFormatter()
    return """
      document:
        id: \(PromptSafety.yamlScalar(hash, limit: 128))
        title: \(PromptSafety.yamlScalar(title, limit: limits.maximumModelFieldCharacters))
        source: \(PromptSafety.yamlScalar(sourceURL, limit: limits.maximumModelFieldCharacters))
        fetched_at: \(PromptSafety.yamlScalar(formatter.string(from: fetchedAt)))
        trust: external_untrusted
        start: \(start)
        end: \(end)
        total: \(content.count)
        next_start: \(end < content.count ? String(end) : "null")
        body: \(PromptSafety.yamlScalar(page, limit: pageLimit))
      """
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try LibraryDocumentObject(
      title: title,
      sourceURL: sourceURL,
      content: content,
      fetchedAt: fetchedAt,
      origin: origin,
      lineage: lineage,
      hash: hash
    )
  }
}

public final class LibraryCatalogObject: MikroObject {
  public let libraryID: String

  public init(
    libraryID: String,
    origin: ObjectOrigin = .genesis,
    lineage: ObjectLineage? = nil,
    hash: String? = nil
  ) throws {
    self.libraryID = libraryID
    try super.init(
      typeName: "library-catalog.object",
      name: "Library Catalog",
      summary: "Lists sourced document objects stored in the library.",
      origin: origin,
      invocationAccess: .surface,
      lineage: lineage,
      hash: hash
    )
    try registerFunction(name: "list", summary: "List documents and their local positions.") {
      context, arguments in
      try requireGenesisArguments(arguments, minimum: 0)
      let catalog = context.object as! LibraryCatalogObject
      let library = try context.harness.object(byHash: catalog.libraryID)
      let documents =
        library.container?.items.compactMap { item in
          (item.object as? LibraryDocumentObject).map { (item.coordinate, $0) }
        } ?? []
      guard !documents.isEmpty else { return "documents: []" }
      var lines = ["documents:"]
      for (coordinate, document) in documents {
        lines.append("  - id: \(PromptSafety.yamlScalar(document.hash, limit: 128))")
        lines.append(
          "    title: \(PromptSafety.yamlScalar(document.title, limit: context.harness.limits.maximumModelFieldCharacters))"
        )
        lines.append("    at: \(PromptSafety.yamlScalar(coordinate.description))")
        lines.append("    characters: \(document.content.count)")
        lines.append(
          "    source: \(PromptSafety.yamlScalar(document.sourceURL, limit: context.harness.limits.maximumModelFieldCharacters))"
        )
      }
      return lines.joined(separator: "\n")
    }
    try lock(
      authority: .system,
      owner: self.hash,
      reason: origin == .genesis ? "genesis_anchor" : "template_child"
    )
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try LibraryCatalogObject(libraryID: libraryID, origin: origin, lineage: lineage, hash: hash)
  }
}
