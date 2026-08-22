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

private struct AgentStoreFieldKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

private let retiredAgentStoreFields: Set<String> = [
  "workspacePath",
  "coin",
  "hand",
  "initialCoinBalance",
]

private func rejectRetiredAgentStoreFields(_ decoder: Decoder) throws {
  let container = try decoder.container(keyedBy: AgentStoreFieldKey.self)
  guard container.allKeys.allSatisfy({ !retiredAgentStoreFields.contains($0.stringValue) }) else {
    throw MikroKhorosError.persistence(
      "agent-store schema 3 contains unsupported retired fields"
    )
  }
}

public struct AgentWorldAssignment: Codable, Equatable, Sendable {
  public let worldID: String
  public let assignedAt: Date

  private enum CodingKeys: String, CodingKey {
    case worldID, assignedAt
  }

  public init(worldID: String, assignedAt: Date = Date()) throws {
    guard InventoryIdentity.isValid(worldID) else {
      throw MikroKhorosError.runtime(
        "agent.world_invalid",
        "the world id must be a complete runtime-issued identity"
      )
    }
    self.worldID = worldID
    self.assignedAt = assignedAt
  }

  public init(from decoder: Decoder) throws {
    try rejectRetiredAgentStoreFields(decoder)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      worldID: container.decode(String.self, forKey: .worldID),
      assignedAt: container.decode(Date.self, forKey: .assignedAt)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(worldID, forKey: .worldID)
    try container.encode(assignedAt, forKey: .assignedAt)
  }
}

public struct UserAgentRecord: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public var maximumActionsPerResponse: Int
  public let genesis: AgentGenesisIDs
  public var profile: AIProfile?
  public var worldAssignment: AgentWorldAssignment?
  public let createdAt: Date
  public var updatedAt: Date

  private enum CodingKeys: String, CodingKey {
    case id, name, maximumActionsPerResponse, genesis, profile, worldAssignment
    case createdAt, updatedAt
  }

  public init(
    id: String = InventoryIdentity.make(),
    name: String,
    maximumActionsPerResponse: Int,
    genesis: AgentGenesisIDs = AgentGenesisIDs(),
    profile: AIProfile? = nil,
    worldAssignment: AgentWorldAssignment? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) throws {
    guard InventoryIdentity.isValid(id) else {
      throw MikroKhorosError.runtime("agent.identity_invalid", "the agent id is invalid")
    }
    guard !name.isEmpty, name.count <= 128, !name.contains(where: { $0.isNewline }) else {
      throw MikroKhorosError.runtime(
        "agent.name_invalid",
        "agent names must be a non-empty single line of at most 128 characters"
      )
    }
    guard maximumActionsPerResponse > 0 else {
      throw MikroKhorosError.runtime(
        "agent.maximum_actions_invalid",
        "maximum actions must be a positive integer"
      )
    }
    guard updatedAt >= createdAt else {
      throw MikroKhorosError.persistence("the agent catalog contains invalid timestamps")
    }
    if let worldAssignment {
      guard worldAssignment.assignedAt >= createdAt else {
        throw MikroKhorosError.persistence("the agent world assignment has an invalid timestamp")
      }
      _ = try AgentWorldAssignment(
        worldID: worldAssignment.worldID,
        assignedAt: worldAssignment.assignedAt
      )
    }
    if let profile { try Self.validateProfile(profile) }
    self.id = id
    self.name = name
    self.maximumActionsPerResponse = maximumActionsPerResponse
    self.genesis = genesis
    self.profile = profile
    self.worldAssignment = worldAssignment
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public init(from decoder: Decoder) throws {
    try rejectRetiredAgentStoreFields(decoder)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let genesisDecoder = try container.superDecoder(forKey: .genesis)
    try rejectRetiredAgentStoreFields(genesisDecoder)
    try self.init(
      id: container.decode(String.self, forKey: .id),
      name: container.decode(String.self, forKey: .name),
      maximumActionsPerResponse: container.decode(Int.self, forKey: .maximumActionsPerResponse),
      genesis: AgentGenesisIDs(from: genesisDecoder),
      profile: container.decodeIfPresent(AIProfile.self, forKey: .profile),
      worldAssignment: container.decodeIfPresent(
        AgentWorldAssignment.self,
        forKey: .worldAssignment
      ),
      createdAt: container.decode(Date.self, forKey: .createdAt),
      updatedAt: container.decode(Date.self, forKey: .updatedAt)
    )
  }

  static func validateProfile(_ profile: AIProfile) throws {
    guard let definition = AIAdapterCatalog.definition(id: profile.adapterID) else {
      throw MikroKhorosError.profile("AI profile references an unknown adapter")
    }
    guard definition.transport == profile.transport else {
      throw MikroKhorosError.profile("AI profile transport does not match its adapter")
    }
    if definition.requiresRoleSeparatedBridge,
      profile.endpoint == nil || profile.transport != .roleSeparatedBridge
    {
      throw MikroKhorosError.profile(
        "this coding-agent adapter requires a role-separated HTTP bridge endpoint"
      )
    }
  }
}

public struct AgentStoreDocument: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 3

  public var schemaVersion: Int
  public var agents: [UserAgentRecord]

  public init(
    schemaVersion: Int = AgentStoreDocument.currentSchemaVersion,
    agents: [UserAgentRecord] = []
  ) {
    self.schemaVersion = schemaVersion
    self.agents = agents
  }

  private enum CodingKeys: String, CodingKey { case schemaVersion, agents }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let storedVersion = try container.decode(Int.self, forKey: .schemaVersion)
    guard storedVersion == Self.currentSchemaVersion else {
      throw MikroKhorosError.persistence(
        "unsupported agent-store schema version found \(storedVersion); required \(Self.currentSchemaVersion)"
      )
    }
    try rejectRetiredAgentStoreFields(decoder)
    schemaVersion = Self.currentSchemaVersion
    agents = try container.decode([UserAgentRecord].self, forKey: .agents)
  }
}

/// The user-level agent catalog. Concrete state remains inside exact worlds.
public final class AgentStore: @unchecked Sendable {
  public let url: URL
  public let maximumBytes: Int
  public private(set) var document: AgentStoreDocument
  private let identityProvider: () -> String
  private let dateProvider: () -> Date

  public init(
    url: URL = AgentStore.defaultURL,
    maximumBytes: Int = RuntimeLimits.defaults.maximumAgentStoreBytes,
    identityProvider: @escaping () -> String = InventoryIdentity.make,
    dateProvider: @escaping () -> Date = Date.init
  ) throws {
    guard maximumBytes > 0 else {
      throw MikroKhorosError.configuration("the agent-store byte limit must be positive")
    }
    self.url = url
    self.maximumBytes = maximumBytes
    self.identityProvider = identityProvider
    self.dateProvider = dateProvider
    self.document = try Self.loadDocument(from: url, maximumBytes: maximumBytes)
    try validateStorage()
  }

  public static var defaultURL: URL {
    MikroKhorosPaths.root.appendingPathComponent("agents.json", isDirectory: false)
  }

  public func allAgents() -> [UserAgentRecord] {
    document.agents.sorted { $0.id < $1.id }
  }

  public func resolve(_ query: String) throws -> UserAgentRecord {
    try HumanSelectorResolver.resolve(
      query,
      among: document.agents,
      id: \.id,
      name: { $0.name },
      kind: "agent",
      listCommand: "khoros agent list"
    ).value
  }

  @discardableResult
  public func create(
    name: String,
    maximumActionsPerResponse: Int
  ) throws -> UserAgentRecord {
    let timestamp = dateProvider()
    let record = try UserAgentRecord(
      id: identityProvider(),
      name: name,
      maximumActionsPerResponse: maximumActionsPerResponse,
      createdAt: timestamp,
      updatedAt: timestamp
    )
    guard !document.agents.contains(where: { $0.id == record.id }) else {
      throw MikroKhorosError.persistence("the agent identity provider returned a duplicate id")
    }
    document.agents.append(record)
    return record
  }

  @discardableResult
  public func assign(
    _ query: String,
    toWorld worldID: String
  ) throws -> UserAgentRecord {
    try mutate(query) { record in
      var changed = false
      if let assignment = record.worldAssignment {
        guard assignment.worldID == worldID else {
          throw MikroKhorosError.runtime(
            "agent.world_conflict",
            "the agent is already assigned to another world",
            details: ["assigned_world": assignment.worldID, "requested_world": worldID],
            suggestions: ["select the assigned world or create another agent"]
          )
        }
      } else {
        record.worldAssignment = try AgentWorldAssignment(
          worldID: worldID,
          assignedAt: dateProvider()
        )
        changed = true
      }
      if changed { record.updatedAt = dateProvider() }
    }
  }

  @discardableResult
  public func setMaximumActions(_ value: Int, for query: String) throws -> UserAgentRecord {
    guard value > 0 else {
      throw MikroKhorosError.runtime(
        "agent.maximum_actions_invalid",
        "maximum actions must be a positive integer"
      )
    }
    return try mutate(query) { record in
      record.maximumActionsPerResponse = value
      record.updatedAt = dateProvider()
    }
  }

  @discardableResult
  public func setProfile(_ profile: AIProfile?, for query: String) throws -> UserAgentRecord {
    if let profile { try UserAgentRecord.validateProfile(profile) }
    return try mutate(query) { record in
      record.profile = profile
      record.updatedAt = dateProvider()
    }
  }

  /// Clears only assignments to the deleted world; agent identities remain user-owned.
  @discardableResult
  public func clearAssignments(toWorld worldID: String) -> [String] {
    let timestamp = dateProvider()
    var changed: [String] = []
    for index in document.agents.indices
    where document.agents[index].worldAssignment?.worldID == worldID {
      document.agents[index].worldAssignment = nil
      document.agents[index].updatedAt = timestamp
      changed.append(document.agents[index].id)
    }
    return changed.sorted()
  }

  public func validateStorage() throws {
    guard document.schemaVersion == AgentStoreDocument.currentSchemaVersion else {
      throw MikroKhorosError.persistence(
        "unsupported agent-store schema version found \(document.schemaVersion); required \(AgentStoreDocument.currentSchemaVersion)"
      )
    }
    let runtimeIDs = document.agents.flatMap { record in
      [
        record.id,
        record.genesis.backpack,
        record.genesis.wallet,
        record.genesis.eye,
        record.genesis.scratchpad,
        record.genesis.messenger,
        record.genesis.calculator,
      ]
    }
    guard runtimeIDs.allSatisfy(InventoryIdentity.isValid),
      Set(runtimeIDs).count == runtimeIDs.count
    else {
      throw MikroKhorosError.persistence("the agent store contains invalid identities")
    }
    for record in document.agents {
      _ = try UserAgentRecord(
        id: record.id,
        name: record.name,
        maximumActionsPerResponse: record.maximumActionsPerResponse,
        genesis: record.genesis,
        profile: record.profile,
        worldAssignment: record.worldAssignment,
        createdAt: record.createdAt,
        updatedAt: record.updatedAt
      )
    }
  }

  public func restoreDocument(_ value: AgentStoreDocument, persist: Bool = true) throws {
    let prior = document
    document = value
    do {
      try validateStorage()
      if persist { try save() }
    } catch {
      document = prior
      throw error
    }
  }

  public func save() throws {
    try validateStorage()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(document)
    guard data.count <= maximumBytes else {
      throw MikroKhorosError.runtime(
        "agent.store_too_large",
        "the agent catalog exceeds the configured byte limit",
        details: ["limit": String(maximumBytes)]
      )
    }
    try AtomicFileStore.write(data, to: url, lockURL: url.appendingPathExtension("lock"))
  }

  private func mutate(
    _ query: String,
    body: (inout UserAgentRecord) throws -> Void
  ) throws -> UserAgentRecord {
    let resolved = try resolve(query)
    guard let index = document.agents.firstIndex(where: { $0.id == resolved.id }) else {
      throw MikroKhorosError.persistence("the resolved agent disappeared from the catalog")
    }
    try body(&document.agents[index])
    return document.agents[index]
  }

  private static func loadDocument(from url: URL, maximumBytes: Int) throws
    -> AgentStoreDocument
  {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return AgentStoreDocument()
    }
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      if let size = values.fileSize, size > maximumBytes {
        throw MikroKhorosError.persistence("the agent store exceeds the configured byte limit")
      }
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(AgentStoreDocument.self, from: data)
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.persistence("could not read the agent-store JSON")
    }
  }
}
