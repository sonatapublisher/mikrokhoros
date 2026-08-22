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
import MikroKhoros

private struct ConsoleHistoryCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

private func rejectUnknownHistoryKeys(
  from decoder: Decoder,
  allowed: Set<String>
) throws {
  let container = try decoder.container(keyedBy: ConsoleHistoryCodingKey.self)
  guard let key = container.allKeys.first(where: { !allowed.contains($0.stringValue) }) else {
    return
  }
  throw DecodingError.dataCorrupted(
    .init(
      codingPath: decoder.codingPath + [key],
      debugDescription: "unknown console history key"
    )
  )
}

public struct ConsoleHistoryEntry: Codable, Equatable, Sendable {
  public let timestamp: Date
  public let commandPath: String
  public let values: [String: [String]]

  private enum CodingKeys: String, CodingKey {
    case timestamp, commandPath, values
  }

  public init(timestamp: Date, commandPath: String, values: [String: [String]]) {
    self.timestamp = timestamp
    self.commandPath = commandPath
    self.values = values
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownHistoryKeys(
      from: decoder,
      allowed: Set([CodingKeys.timestamp, .commandPath, .values].map(\.rawValue))
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    timestamp = try container.decode(Date.self, forKey: .timestamp)
    commandPath = try container.decode(String.self, forKey: .commandPath)
    values = try container.decode([String: [String]].self, forKey: .values)
  }
}

private struct ConsoleHistoryDocument: Codable {
  static let currentVersion = 1

  let version: Int
  var entries: [ConsoleHistoryEntry]

  private enum CodingKeys: String, CodingKey {
    case version, entries
  }

  init(version: Int, entries: [ConsoleHistoryEntry]) {
    self.version = version
    self.entries = entries
  }

  init(from decoder: Decoder) throws {
    try rejectUnknownHistoryKeys(
      from: decoder,
      allowed: Set([CodingKeys.version, .entries].map(\.rawValue))
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(Int.self, forKey: .version)
    entries = try container.decode([ConsoleHistoryEntry].self, forKey: .entries)
  }
}

public final class ConsoleHistoryStore: @unchecked Sendable {
  public static var defaultURL: URL {
    MikroKhorosPaths.root.appendingPathComponent(
      "console-history.json",
      isDirectory: false
    )
  }

  private let url: URL
  private let maximumBytes: Int
  private let maximumEntries: Int
  private let maximumInputCharacters: Int
  private let lock = NSLock()
  private var entries: [ConsoleHistoryEntry]

  public init(
    url: URL = defaultURL,
    configuration: RuntimeConfiguration
  ) throws {
    self.url = url
    maximumBytes = configuration.runtime.maximumConsoleHistoryBytes
    maximumEntries = configuration.console.maximumHistoryEntries
    maximumInputCharacters = configuration.console.maximumInputCharacters
    entries = try Self.load(
      from: url,
      maximumBytes: maximumBytes,
      maximumEntries: maximumEntries,
      maximumInputCharacters: maximumInputCharacters
    )
  }

  public func allEntries() -> [ConsoleHistoryEntry] {
    lock.withLock { entries }
  }

  public func values(commandPath: String, fieldID: String) -> [String] {
    lock.withLock {
      var seen = Set<String>()
      return entries.reversed().flatMap { entry -> [String] in
        guard entry.commandPath == commandPath else { return [] }
        return (entry.values[fieldID] ?? []).reversed().compactMap { value in
          seen.insert(value).inserted ? value : nil
        }
      }
    }
  }

  public func append(
    _ submission: InteractiveCommandSubmission,
    definition: CommandDefinition,
    timestamp: Date = Date()
  ) throws {
    let fields = Dictionary(uniqueKeysWithValues: definition.fields.map { ($0.id, $0) })
    let safeValues = submission.values.reduce(into: [String: [String]]()) { result, pair in
      guard submission.explicitFieldIDs.contains(pair.key),
        fields[pair.key]?.historyPolicy == .store
      else {
        return
      }
      let values = pair.value.filter { !$0.isEmpty }
      if !values.isEmpty { result[pair.key] = values }
    }
    let entry = ConsoleHistoryEntry(
      timestamp: timestamp,
      commandPath: definition.command,
      values: safeValues
    )
    try lock.withLock {
      let fileLock = try ConsoleHistoryMutationLock(
        url: url.appendingPathExtension("mutation-lock")
      )
      entries = try Self.load(
        from: url,
        maximumBytes: maximumBytes,
        maximumEntries: maximumEntries,
        maximumInputCharacters: maximumInputCharacters
      )
      entries.append(entry)
      if entries.count > maximumEntries {
        entries.removeFirst(entries.count - maximumEntries)
      }
      try persist()
      withExtendedLifetime(fileLock) {}
    }
  }

  private func persist() throws {
    let document = ConsoleHistoryDocument(
      version: ConsoleHistoryDocument.currentVersion,
      entries: entries
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(document)
    while data.count > maximumBytes, !entries.isEmpty {
      entries.removeFirst()
      data = try encoder.encode(
        ConsoleHistoryDocument(
          version: ConsoleHistoryDocument.currentVersion,
          entries: entries
        )
      )
    }
    guard data.count <= maximumBytes else {
      throw MikroKhorosError.configuration("console history exceeds its configured byte limit")
    }
    try AtomicFileStore.write(
      data,
      to: url,
      lockURL: url.appendingPathExtension("lock")
    )
  }

  private static func load(
    from url: URL,
    maximumBytes: Int,
    maximumEntries: Int,
    maximumInputCharacters: Int
  ) throws -> [ConsoleHistoryEntry] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    if let size = attributes[.size] as? NSNumber, size.intValue > maximumBytes {
      throw MikroKhorosError.configuration("console history exceeds its configured byte limit")
    }
    do {
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      let document = try decoder.decode(ConsoleHistoryDocument.self, from: data)
      guard document.version == ConsoleHistoryDocument.currentVersion,
        document.entries.count <= maximumEntries,
        document.entries.allSatisfy({ entry in
          guard let definition = CommandCatalog.find(path: entry.commandPath) else { return false }
          let permitted = Set(
            definition.fields.filter { $0.historyPolicy == .store }.map(\.id)
          )
          return entry.commandPath.count <= maximumInputCharacters
            && entry.values.allSatisfy { field, values in
              permitted.contains(field)
                && values.allSatisfy { $0.count <= maximumInputCharacters }
            }
        })
      else {
        throw MikroKhorosError.configuration("console history contains invalid data")
      }
      return document.entries
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.configuration("could not read console history JSON")
    }
  }
}

private final class ConsoleHistoryMutationLock {
  private let url: URL
  private var acquired = false

  init(url: URL) throws {
    self.url = url
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    for _ in 0..<100 {
      do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        acquired = true
        return
      } catch {
        Thread.sleep(forTimeInterval: 0.05)
      }
    }
    throw MikroKhorosError.persistence("console history is busy in another process")
  }

  deinit {
    if acquired { try? FileManager.default.removeItem(at: url) }
  }
}

extension NSLock {
  fileprivate func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
    lock()
    defer { unlock() }
    return try body()
  }
}
