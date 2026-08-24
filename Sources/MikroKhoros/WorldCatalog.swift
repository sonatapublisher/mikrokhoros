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

public struct WorldCatalogRecord: Codable, Equatable, Sendable {
  public let id: String
  public var name: String
  public let createdAt: Date
  public var updatedAt: Date

  public init(
    id: String,
    name: String,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) throws {
    guard InventoryIdentity.isValid(id) else {
      throw MikroKhorosError.persistence("the world catalog contains an invalid world id")
    }
    try Self.validateName(name)
    guard updatedAt >= createdAt else {
      throw MikroKhorosError.persistence("the world catalog contains invalid timestamps")
    }
    self.id = id
    self.name = name
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public static func validateName(_ name: String) throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      name.count <= 128,
      !name.contains(where: \.isNewline)
    else {
      throw MikroKhorosError.runtime(
        "world.name_invalid",
        "world names must be a non-empty single line of at most 128 characters"
      )
    }
  }
}

public struct WorldCatalogDocument: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public var schemaVersion: Int
  public var currentWorldID: String?
  public var worlds: [WorldCatalogRecord]

  public init(
    schemaVersion: Int = Self.currentSchemaVersion,
    currentWorldID: String? = nil,
    worlds: [WorldCatalogRecord] = []
  ) {
    self.schemaVersion = schemaVersion
    self.currentWorldID = currentWorldID
    self.worlds = worlds
  }
}

/// The user-global catalog that maps exact world identities to world documents.
public final class WorldCatalogStore: @unchecked Sendable {
  public let url: URL
  public let maximumBytes: Int
  public private(set) var document: WorldCatalogDocument

  public init(
    url: URL = WorldCatalogStore.defaultURL,
    maximumBytes: Int = RuntimeLimits.defaults.maximumWorldBytes
  ) throws {
    guard maximumBytes > 0 else {
      throw MikroKhorosError.configuration("the world byte limit must be positive")
    }
    self.url = url
    self.maximumBytes = maximumBytes
    self.document = try Self.loadDocument(from: url, maximumBytes: maximumBytes)
    try validateStorage(requireWorldFiles: false)
  }

  public static var defaultURL: URL {
    WorldStore.directoryURL.appendingPathComponent("index.json", isDirectory: false)
  }

  public var currentWorld: WorldCatalogRecord? {
    guard let id = document.currentWorldID else { return nil }
    return document.worlds.first { $0.id == id }
  }

  public func allWorlds() -> [WorldCatalogRecord] {
    document.worlds.sorted {
      if $0.createdAt == $1.createdAt { return $0.id < $1.id }
      return $0.createdAt < $1.createdAt
    }
  }

  public func resolve(_ query: String) throws -> WorldCatalogRecord {
    try HumanSelectorResolver.resolve(
      query,
      among: document.worlds,
      id: \.id,
      name: { $0.name },
      kind: "world",
      listCommand: "khoros world list"
    ).value
  }

  public func selected(_ query: String? = nil) throws -> WorldCatalogRecord {
    if let query { return try resolve(query) }
    guard let currentWorld else {
      if document.worlds.isEmpty {
        throw MikroKhorosError.runtime(
          "world.not_initialized",
          "mikrokhoros has no world",
          suggestions: ["run `khoros init` or `khoros world create`"]
        )
      }
      throw MikroKhorosError.runtime(
        "world.selection_required",
        "no current world is selected",
        suggestions: ["run `khoros world list`, then `khoros world use <world>`"]
      )
    }
    return currentWorld
  }

  @discardableResult
  public func register(
    document world: WorldDocument,
    makeCurrent: Bool = true,
    timestamp: Date = Date()
  ) throws -> WorldCatalogRecord {
    guard !document.worlds.contains(where: { $0.id == world.worldID }) else {
      throw MikroKhorosError.runtime(
        "world.identity_conflict",
        "a world with this identity already exists",
        details: ["world_id": world.worldID]
      )
    }
    let record = try WorldCatalogRecord(
      id: world.worldID,
      name: world.worldName,
      createdAt: timestamp,
      updatedAt: timestamp
    )
    document.worlds.append(record)
    if makeCurrent { document.currentWorldID = record.id }
    return record
  }

  @discardableResult
  public func use(_ query: String) throws -> WorldCatalogRecord {
    let record = try resolve(query)
    document.currentWorldID = record.id
    return record
  }

  @discardableResult
  public func rename(_ query: String, name: String, timestamp: Date = Date()) throws
    -> WorldCatalogRecord
  {
    try WorldCatalogRecord.validateName(name)
    let record = try resolve(query)
    guard let index = document.worlds.firstIndex(where: { $0.id == record.id }) else {
      throw MikroKhorosError.persistence("the resolved world disappeared from the catalog")
    }
    document.worlds[index].name = name
    document.worlds[index].updatedAt = timestamp
    return document.worlds[index]
  }

  @discardableResult
  public func remove(_ query: String) throws -> WorldCatalogRecord {
    let record = try resolve(query)
    guard let index = document.worlds.firstIndex(where: { $0.id == record.id }) else {
      throw MikroKhorosError.persistence("the resolved world disappeared from the catalog")
    }
    document.worlds.remove(at: index)
    if document.currentWorldID == record.id {
      document.currentWorldID = document.worlds.count == 1 ? document.worlds[0].id : nil
    }
    return record
  }

  public func restoreDocument(_ value: WorldCatalogDocument, persist: Bool = true) throws {
    let prior = document
    document = value
    do {
      try validateStorage(requireWorldFiles: false)
      if persist { try save() }
    } catch {
      document = prior
      throw error
    }
  }

  public func save() throws {
    try validateStorage(requireWorldFiles: false)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(document)
    guard data.count <= maximumBytes else {
      throw MikroKhorosError.persistence("the world catalog exceeds the configured byte limit")
    }
    try AtomicFileStore.write(data, to: url, lockURL: url.appendingPathExtension("lock"))
  }

  public func validateStorage(requireWorldFiles: Bool = true) throws {
    guard document.schemaVersion == WorldCatalogDocument.currentSchemaVersion else {
      throw MikroKhorosError.persistence("unsupported world-catalog schema version")
    }
    let ids = document.worlds.map(\.id)
    guard ids.allSatisfy(InventoryIdentity.isValid), Set(ids).count == ids.count else {
      throw MikroKhorosError.persistence("the world catalog contains invalid identities")
    }
    for record in document.worlds {
      _ = try WorldCatalogRecord(
        id: record.id,
        name: record.name,
        createdAt: record.createdAt,
        updatedAt: record.updatedAt
      )
      if requireWorldFiles {
        let worldURL = try WorldStore.url(for: record.id)
        guard FileManager.default.fileExists(atPath: worldURL.path) else {
          throw MikroKhorosError.persistence("the world catalog references a missing world file")
        }
      }
    }
    if let current = document.currentWorldID, !ids.contains(current) {
      throw MikroKhorosError.persistence("the world catalog selects an unknown world")
    }
  }

  private static func loadDocument(from url: URL, maximumBytes: Int) throws
    -> WorldCatalogDocument
  {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return WorldCatalogDocument()
    }
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      if let size = values.fileSize, size > maximumBytes {
        throw MikroKhorosError.persistence("the world catalog exceeds the configured byte limit")
      }
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(WorldCatalogDocument.self, from: data)
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.persistence("could not read the world-catalog JSON")
    }
  }
}
