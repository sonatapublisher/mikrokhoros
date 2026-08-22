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

#if os(Linux)
  import Glibc
#elseif canImport(Darwin)
  import Darwin
#endif

public enum MikroKhorosPaths {
  public static var root: URL {
    #if os(Windows)
      let override = ProcessInfo.processInfo.environment["MIKROKHOROS_HOME"]
    #else
      let override = getenv("MIKROKHOROS_HOME").map { String(cString: $0) }
    #endif
    if let value = override, !value.isEmpty {
      return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
    }
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".mikrokhoros", isDirectory: true)
  }
}

private struct ConfigurationCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

private func rejectUnknownConfigurationKeys(
  from decoder: Decoder,
  allowed: Set<String>
) throws {
  let container = try decoder.container(keyedBy: ConfigurationCodingKey.self)
  guard let unknown = container.allKeys.first(where: { !allowed.contains($0.stringValue) }) else {
    return
  }
  throw DecodingError.dataCorrupted(
    .init(
      codingPath: decoder.codingPath + [unknown],
      debugDescription: "unknown configuration key"
    )
  )
}

public enum RuntimeLimitKey: String, CaseIterable, Codable, Sendable {
  case maximumActionCharacters
  case maximumActionsPerResponse
  case maximumResponseCharacters
  case maximumProviderResponseBytes
  case maximumModelFieldCharacters
  case maximumModelInputCharacters
  case maximumModelHistoryCharacters
  case maximumModelHistoryMessages
  case maximumModelContextCharacters
  case maximumBroadcastEventsPerRequest
  case minimumProtectedVerbatimWords
  case maximumPackageBytes
  case maximumAgentStoreBytes
  case maximumInventoryBytes
  case maximumWorldBytes
  case maximumReportBytes
  case maximumRetainedReports
  case maximumConsoleHistoryBytes
  case maximumInventoryFolders
  case maximumObjectInvocationDepth
  case maximumMountsPerObject
  case maximumProjectedEntriesPerDirectory
  case maximumProjectedTreeDepth
  case maximumUserFileReadBytes
  case maximumUserFileWriteBytes

  public var cliName: String {
    switch self {
    case .maximumActionCharacters: "maximum-action-characters"
    case .maximumActionsPerResponse: "maximum-actions-per-response"
    case .maximumResponseCharacters: "maximum-response-characters"
    case .maximumProviderResponseBytes: "maximum-provider-response-bytes"
    case .maximumModelFieldCharacters: "maximum-model-field-characters"
    case .maximumModelInputCharacters: "maximum-model-input-characters"
    case .maximumModelHistoryCharacters: "maximum-model-history-characters"
    case .maximumModelHistoryMessages: "maximum-model-history-messages"
    case .maximumModelContextCharacters: "maximum-model-context-characters"
    case .maximumBroadcastEventsPerRequest: "maximum-broadcast-events-per-request"
    case .minimumProtectedVerbatimWords: "minimum-protected-verbatim-words"
    case .maximumPackageBytes: "maximum-package-bytes"
    case .maximumAgentStoreBytes: "maximum-agent-store-bytes"
    case .maximumInventoryBytes: "maximum-inventory-bytes"
    case .maximumWorldBytes: "maximum-world-bytes"
    case .maximumReportBytes: "maximum-report-bytes"
    case .maximumRetainedReports: "maximum-retained-reports"
    case .maximumConsoleHistoryBytes: "maximum-console-history-bytes"
    case .maximumInventoryFolders: "maximum-inventory-folders"
    case .maximumObjectInvocationDepth: "maximum-object-invocation-depth"
    case .maximumMountsPerObject: "maximum-mounts-per-object"
    case .maximumProjectedEntriesPerDirectory: "maximum-projected-entries-per-directory"
    case .maximumProjectedTreeDepth: "maximum-projected-tree-depth"
    case .maximumUserFileReadBytes: "maximum-user-file-read-bytes"
    case .maximumUserFileWriteBytes: "maximum-user-file-write-bytes"
    }
  }

  public init(argument: String) throws {
    let prefixes = ["runtime.", "limits."]
    let normalized =
      prefixes.first(where: { argument.hasPrefix($0) })
      .map { String(argument.dropFirst($0.count)) } ?? argument
    if normalized == "maximumWorkspaceBytes" || normalized == "maximum-workspace-bytes" {
      self = .maximumWorldBytes
      return
    }
    guard
      let key = Self.allCases.first(where: {
        $0.rawValue == normalized || $0.cliName == normalized
      })
    else {
      throw MikroKhorosError.configuration("unknown runtime limit")
    }
    self = key
  }
}

public struct AgentDefaults: Codable, Equatable, Sendable {
  public let maximumActionsPerResponse: Int

  private enum CodingKeys: String, CodingKey {
    case maximumActionsPerResponse
  }

  public init(maximumActionsPerResponse: Int = 8) throws {
    guard maximumActionsPerResponse > 0 else {
      throw MikroKhorosError.configuration(
        "agents.maximum-actions-per-response must be a positive integer"
      )
    }
    self.maximumActionsPerResponse = maximumActionsPerResponse
  }

  private init(validatedMaximumActionsPerResponse: Int) {
    maximumActionsPerResponse = validatedMaximumActionsPerResponse
  }

  public static let defaults = AgentDefaults(validatedMaximumActionsPerResponse: 8)

  public init(from decoder: Decoder) throws {
    try rejectUnknownConfigurationKeys(
      from: decoder,
      allowed: [CodingKeys.maximumActionsPerResponse.rawValue]
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      maximumActionsPerResponse: container.decode(
        Int.self,
        forKey: .maximumActionsPerResponse
      )
    )
  }
}

public struct RuntimeLimits: Codable, Equatable, Sendable {
  public private(set) var maximumActionCharacters: Int
  public private(set) var maximumActionsPerResponse: Int
  public private(set) var maximumResponseCharacters: Int
  public private(set) var maximumProviderResponseBytes: Int
  public private(set) var maximumModelFieldCharacters: Int
  public private(set) var maximumModelInputCharacters: Int
  public private(set) var maximumModelHistoryCharacters: Int
  public private(set) var maximumModelHistoryMessages: Int
  public private(set) var maximumModelContextCharacters: Int
  public private(set) var maximumBroadcastEventsPerRequest: Int
  public private(set) var minimumProtectedVerbatimWords: Int
  public private(set) var maximumPackageBytes: Int
  public private(set) var maximumAgentStoreBytes: Int
  public private(set) var maximumInventoryBytes: Int
  public private(set) var maximumWorldBytes: Int
  public private(set) var maximumReportBytes: Int
  public private(set) var maximumRetainedReports: Int
  public private(set) var maximumConsoleHistoryBytes: Int
  public private(set) var maximumInventoryFolders: Int
  public private(set) var maximumObjectInvocationDepth: Int
  public private(set) var maximumMountsPerObject: Int
  public private(set) var maximumProjectedEntriesPerDirectory: Int
  public private(set) var maximumProjectedTreeDepth: Int
  public private(set) var maximumUserFileReadBytes: Int
  public private(set) var maximumUserFileWriteBytes: Int

  public init() {
    maximumActionCharacters = 4_096
    maximumActionsPerResponse = 256
    maximumResponseCharacters = 32_768
    maximumProviderResponseBytes = 4 * 1_024 * 1_024
    maximumModelFieldCharacters = 32_768
    maximumModelInputCharacters = 65_536
    maximumModelHistoryCharacters = 65_536
    maximumModelHistoryMessages = 256
    maximumModelContextCharacters = 131_072
    maximumBroadcastEventsPerRequest = 16
    minimumProtectedVerbatimWords = 12
    maximumPackageBytes = 4 * 1_024 * 1_024
    maximumAgentStoreBytes = 16 * 1_024 * 1_024
    maximumInventoryBytes = 64 * 1_024 * 1_024
    maximumWorldBytes = 64 * 1_024 * 1_024
    maximumReportBytes = 256 * 1_024
    maximumRetainedReports = 10_000
    maximumConsoleHistoryBytes = 1_048_576
    maximumInventoryFolders = 10_000
    maximumObjectInvocationDepth = 16
    maximumMountsPerObject = 128
    maximumProjectedEntriesPerDirectory = 10_000
    maximumProjectedTreeDepth = 64
    maximumUserFileReadBytes = 1_048_576
    maximumUserFileWriteBytes = 1_048_576
  }

  public init(
    maximumActionCharacters: Int,
    maximumActionsPerResponse: Int,
    maximumResponseCharacters: Int,
    maximumProviderResponseBytes: Int,
    maximumModelFieldCharacters: Int,
    maximumModelInputCharacters: Int,
    maximumModelHistoryCharacters: Int,
    maximumModelHistoryMessages: Int,
    maximumModelContextCharacters: Int,
    maximumBroadcastEventsPerRequest: Int,
    minimumProtectedVerbatimWords: Int,
    maximumPackageBytes: Int = RuntimeLimits.defaults.maximumPackageBytes,
    maximumAgentStoreBytes: Int = RuntimeLimits.defaults.maximumAgentStoreBytes,
    maximumInventoryBytes: Int = RuntimeLimits.defaults.maximumInventoryBytes,
    maximumWorldBytes: Int = RuntimeLimits.defaults.maximumWorldBytes,
    maximumReportBytes: Int = RuntimeLimits.defaults.maximumReportBytes,
    maximumRetainedReports: Int = RuntimeLimits.defaults.maximumRetainedReports,
    maximumConsoleHistoryBytes: Int = RuntimeLimits.defaults.maximumConsoleHistoryBytes,
    maximumInventoryFolders: Int = RuntimeLimits.defaults.maximumInventoryFolders,
    maximumObjectInvocationDepth: Int = RuntimeLimits.defaults.maximumObjectInvocationDepth,
    maximumMountsPerObject: Int = RuntimeLimits.defaults.maximumMountsPerObject,
    maximumProjectedEntriesPerDirectory: Int = RuntimeLimits.defaults
      .maximumProjectedEntriesPerDirectory,
    maximumProjectedTreeDepth: Int = RuntimeLimits.defaults.maximumProjectedTreeDepth,
    maximumUserFileReadBytes: Int = RuntimeLimits.defaults.maximumUserFileReadBytes,
    maximumUserFileWriteBytes: Int = RuntimeLimits.defaults.maximumUserFileWriteBytes
  ) throws {
    self.maximumActionCharacters = maximumActionCharacters
    self.maximumActionsPerResponse = maximumActionsPerResponse
    self.maximumResponseCharacters = maximumResponseCharacters
    self.maximumProviderResponseBytes = maximumProviderResponseBytes
    self.maximumModelFieldCharacters = maximumModelFieldCharacters
    self.maximumModelInputCharacters = maximumModelInputCharacters
    self.maximumModelHistoryCharacters = maximumModelHistoryCharacters
    self.maximumModelHistoryMessages = maximumModelHistoryMessages
    self.maximumModelContextCharacters = maximumModelContextCharacters
    self.maximumBroadcastEventsPerRequest = maximumBroadcastEventsPerRequest
    self.minimumProtectedVerbatimWords = minimumProtectedVerbatimWords
    self.maximumPackageBytes = maximumPackageBytes
    self.maximumAgentStoreBytes = maximumAgentStoreBytes
    self.maximumInventoryBytes = maximumInventoryBytes
    self.maximumWorldBytes = maximumWorldBytes
    self.maximumReportBytes = maximumReportBytes
    self.maximumRetainedReports = maximumRetainedReports
    self.maximumConsoleHistoryBytes = maximumConsoleHistoryBytes
    self.maximumInventoryFolders = maximumInventoryFolders
    self.maximumObjectInvocationDepth = maximumObjectInvocationDepth
    self.maximumMountsPerObject = maximumMountsPerObject
    self.maximumProjectedEntriesPerDirectory = maximumProjectedEntriesPerDirectory
    self.maximumProjectedTreeDepth = maximumProjectedTreeDepth
    self.maximumUserFileReadBytes = maximumUserFileReadBytes
    self.maximumUserFileWriteBytes = maximumUserFileWriteBytes
    try validate()
  }

  public static let defaults = RuntimeLimits()

  static func persistenceValidation(maximumCharacters: Int) -> RuntimeLimits {
    precondition(maximumCharacters > 0)
    var limits = RuntimeLimits()
    limits.maximumActionCharacters = maximumCharacters
    limits.maximumActionsPerResponse = maximumCharacters
    limits.maximumResponseCharacters = maximumCharacters
    limits.maximumProviderResponseBytes = maximumCharacters
    limits.maximumModelFieldCharacters = maximumCharacters
    limits.maximumModelInputCharacters = maximumCharacters
    limits.maximumModelHistoryCharacters = maximumCharacters
    limits.maximumModelHistoryMessages = maximumCharacters
    limits.maximumModelContextCharacters = maximumCharacters
    limits.maximumBroadcastEventsPerRequest = maximumCharacters
    limits.minimumProtectedVerbatimWords = 1
    limits.maximumPackageBytes = maximumCharacters
    limits.maximumAgentStoreBytes = maximumCharacters
    limits.maximumInventoryBytes = maximumCharacters
    limits.maximumWorldBytes = maximumCharacters
    limits.maximumReportBytes = maximumCharacters
    limits.maximumRetainedReports = maximumCharacters
    limits.maximumConsoleHistoryBytes = maximumCharacters
    limits.maximumInventoryFolders = maximumCharacters
    limits.maximumObjectInvocationDepth = maximumCharacters
    limits.maximumMountsPerObject = maximumCharacters
    limits.maximumProjectedEntriesPerDirectory = maximumCharacters
    limits.maximumProjectedTreeDepth = maximumCharacters
    limits.maximumUserFileReadBytes = maximumCharacters
    limits.maximumUserFileWriteBytes = maximumCharacters
    return limits
  }

  public func value(for key: RuntimeLimitKey) -> Int {
    switch key {
    case .maximumActionCharacters: maximumActionCharacters
    case .maximumActionsPerResponse: maximumActionsPerResponse
    case .maximumResponseCharacters: maximumResponseCharacters
    case .maximumProviderResponseBytes: maximumProviderResponseBytes
    case .maximumModelFieldCharacters: maximumModelFieldCharacters
    case .maximumModelInputCharacters: maximumModelInputCharacters
    case .maximumModelHistoryCharacters: maximumModelHistoryCharacters
    case .maximumModelHistoryMessages: maximumModelHistoryMessages
    case .maximumModelContextCharacters: maximumModelContextCharacters
    case .maximumBroadcastEventsPerRequest: maximumBroadcastEventsPerRequest
    case .minimumProtectedVerbatimWords: minimumProtectedVerbatimWords
    case .maximumPackageBytes: maximumPackageBytes
    case .maximumAgentStoreBytes: maximumAgentStoreBytes
    case .maximumInventoryBytes: maximumInventoryBytes
    case .maximumWorldBytes: maximumWorldBytes
    case .maximumReportBytes: maximumReportBytes
    case .maximumRetainedReports: maximumRetainedReports
    case .maximumConsoleHistoryBytes: maximumConsoleHistoryBytes
    case .maximumInventoryFolders: maximumInventoryFolders
    case .maximumObjectInvocationDepth: maximumObjectInvocationDepth
    case .maximumMountsPerObject: maximumMountsPerObject
    case .maximumProjectedEntriesPerDirectory: maximumProjectedEntriesPerDirectory
    case .maximumProjectedTreeDepth: maximumProjectedTreeDepth
    case .maximumUserFileReadBytes: maximumUserFileReadBytes
    case .maximumUserFileWriteBytes: maximumUserFileWriteBytes
    }
  }

  public func setting(_ key: RuntimeLimitKey, to value: Int) throws -> RuntimeLimits {
    var copy = self
    switch key {
    case .maximumActionCharacters: copy.maximumActionCharacters = value
    case .maximumActionsPerResponse: copy.maximumActionsPerResponse = value
    case .maximumResponseCharacters: copy.maximumResponseCharacters = value
    case .maximumProviderResponseBytes: copy.maximumProviderResponseBytes = value
    case .maximumModelFieldCharacters: copy.maximumModelFieldCharacters = value
    case .maximumModelInputCharacters: copy.maximumModelInputCharacters = value
    case .maximumModelHistoryCharacters: copy.maximumModelHistoryCharacters = value
    case .maximumModelHistoryMessages: copy.maximumModelHistoryMessages = value
    case .maximumModelContextCharacters: copy.maximumModelContextCharacters = value
    case .maximumBroadcastEventsPerRequest:
      copy.maximumBroadcastEventsPerRequest = value
    case .minimumProtectedVerbatimWords: copy.minimumProtectedVerbatimWords = value
    case .maximumPackageBytes: copy.maximumPackageBytes = value
    case .maximumAgentStoreBytes: copy.maximumAgentStoreBytes = value
    case .maximumInventoryBytes: copy.maximumInventoryBytes = value
    case .maximumWorldBytes: copy.maximumWorldBytes = value
    case .maximumReportBytes: copy.maximumReportBytes = value
    case .maximumRetainedReports: copy.maximumRetainedReports = value
    case .maximumConsoleHistoryBytes: copy.maximumConsoleHistoryBytes = value
    case .maximumInventoryFolders: copy.maximumInventoryFolders = value
    case .maximumObjectInvocationDepth: copy.maximumObjectInvocationDepth = value
    case .maximumMountsPerObject: copy.maximumMountsPerObject = value
    case .maximumProjectedEntriesPerDirectory:
      copy.maximumProjectedEntriesPerDirectory = value
    case .maximumProjectedTreeDepth: copy.maximumProjectedTreeDepth = value
    case .maximumUserFileReadBytes: copy.maximumUserFileReadBytes = value
    case .maximumUserFileWriteBytes: copy.maximumUserFileWriteBytes = value
    }
    try copy.validate()
    return copy
  }

  public func resetting(_ key: RuntimeLimitKey) throws -> RuntimeLimits {
    try setting(key, to: Self.defaults.value(for: key))
  }

  public func validate() throws {
    guard RuntimeLimitKey.allCases.allSatisfy({ value(for: $0) > 0 }) else {
      throw MikroKhorosError.configuration("runtime limits must be positive integers")
    }
    guard maximumActionCharacters <= maximumResponseCharacters else {
      throw MikroKhorosError.configuration(
        "maximum-action-characters cannot exceed maximum-response-characters"
      )
    }
    guard maximumModelFieldCharacters <= maximumModelInputCharacters else {
      throw MikroKhorosError.configuration(
        "maximum-model-field-characters cannot exceed maximum-model-input-characters"
      )
    }
    guard maximumModelInputCharacters <= maximumModelContextCharacters else {
      throw MikroKhorosError.configuration(
        "maximum-model-input-characters cannot exceed maximum-model-context-characters"
      )
    }
    guard maximumObjectInvocationDepth <= Int.max / 64 else {
      throw MikroKhorosError.configuration(
        "maximum-object-invocation-depth exceeds the bounded ownership traversal range"
      )
    }
  }

  public init(from decoder: Decoder) throws {
    let legacyWorldByteKey = "maximumWorkspaceBytes"
    try rejectUnknownConfigurationKeys(
      from: decoder,
      allowed: Set(RuntimeLimitKey.allCases.map(\.rawValue)).union([legacyWorldByteKey])
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let legacyContainer = try decoder.container(keyedBy: ConfigurationCodingKey.self)
    let legacyMaximumWorldBytes = try legacyContainer.decodeIfPresent(
      Int.self,
      forKey: ConfigurationCodingKey(stringValue: legacyWorldByteKey)!
    )
    do {
      try self.init(
        maximumActionCharacters: container.decode(Int.self, forKey: .maximumActionCharacters),
        maximumActionsPerResponse: container.decode(
          Int.self, forKey: .maximumActionsPerResponse
        ),
        maximumResponseCharacters: container.decode(
          Int.self, forKey: .maximumResponseCharacters
        ),
        maximumProviderResponseBytes: container.decode(
          Int.self, forKey: .maximumProviderResponseBytes
        ),
        maximumModelFieldCharacters: container.decode(
          Int.self, forKey: .maximumModelFieldCharacters
        ),
        maximumModelInputCharacters: container.decode(
          Int.self, forKey: .maximumModelInputCharacters
        ),
        maximumModelHistoryCharacters: container.decode(
          Int.self, forKey: .maximumModelHistoryCharacters
        ),
        maximumModelHistoryMessages: container.decode(
          Int.self, forKey: .maximumModelHistoryMessages
        ),
        maximumModelContextCharacters: container.decode(
          Int.self, forKey: .maximumModelContextCharacters
        ),
        maximumBroadcastEventsPerRequest: container.decode(
          Int.self, forKey: .maximumBroadcastEventsPerRequest
        ),
        minimumProtectedVerbatimWords: container.decode(
          Int.self, forKey: .minimumProtectedVerbatimWords
        ),
        maximumPackageBytes: container.decodeIfPresent(
          Int.self, forKey: .maximumPackageBytes
        ) ?? Self.defaults.maximumPackageBytes,
        maximumAgentStoreBytes: container.decodeIfPresent(
          Int.self, forKey: .maximumAgentStoreBytes
        ) ?? Self.defaults.maximumAgentStoreBytes,
        maximumInventoryBytes: container.decodeIfPresent(
          Int.self, forKey: .maximumInventoryBytes
        ) ?? Self.defaults.maximumInventoryBytes,
        maximumWorldBytes: container.decodeIfPresent(
          Int.self, forKey: .maximumWorldBytes
        ) ?? legacyMaximumWorldBytes ?? Self.defaults.maximumWorldBytes,
        maximumReportBytes: container.decodeIfPresent(
          Int.self, forKey: .maximumReportBytes
        ) ?? Self.defaults.maximumReportBytes,
        maximumRetainedReports: container.decodeIfPresent(
          Int.self, forKey: .maximumRetainedReports
        ) ?? Self.defaults.maximumRetainedReports,
        maximumConsoleHistoryBytes: container.decodeIfPresent(
          Int.self, forKey: .maximumConsoleHistoryBytes
        ) ?? Self.defaults.maximumConsoleHistoryBytes,
        maximumInventoryFolders: container.decodeIfPresent(
          Int.self, forKey: .maximumInventoryFolders
        ) ?? Self.defaults.maximumInventoryFolders,
        maximumObjectInvocationDepth: container.decodeIfPresent(
          Int.self, forKey: .maximumObjectInvocationDepth
        ) ?? Self.defaults.maximumObjectInvocationDepth,
        maximumMountsPerObject: container.decodeIfPresent(
          Int.self, forKey: .maximumMountsPerObject
        ) ?? Self.defaults.maximumMountsPerObject,
        maximumProjectedEntriesPerDirectory: container.decodeIfPresent(
          Int.self, forKey: .maximumProjectedEntriesPerDirectory
        ) ?? Self.defaults.maximumProjectedEntriesPerDirectory,
        maximumProjectedTreeDepth: container.decodeIfPresent(
          Int.self, forKey: .maximumProjectedTreeDepth
        ) ?? Self.defaults.maximumProjectedTreeDepth,
        maximumUserFileReadBytes: container.decodeIfPresent(
          Int.self, forKey: .maximumUserFileReadBytes
        ) ?? Self.defaults.maximumUserFileReadBytes,
        maximumUserFileWriteBytes: container.decodeIfPresent(
          Int.self, forKey: .maximumUserFileWriteBytes
        ) ?? Self.defaults.maximumUserFileWriteBytes
      )
    } catch {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "invalid runtime limits")
      )
    }
  }
}

public enum ConsoleConfigurationKey: String, CaseIterable, Codable, Sendable {
  case maximumInputCharacters
  case maximumQueueDepth
  case maximumHistoryEntries
  case maximumSuggestions
  case escapeTimeoutMilliseconds

  public var cliName: String {
    switch self {
    case .maximumInputCharacters: "maximum-input-characters"
    case .maximumQueueDepth: "maximum-queue-depth"
    case .maximumHistoryEntries: "maximum-history-entries"
    case .maximumSuggestions: "maximum-suggestions"
    case .escapeTimeoutMilliseconds: "escape-timeout-milliseconds"
    }
  }

  public init(argument: String) throws {
    let normalized =
      argument.hasPrefix("console.")
      ? String(argument.dropFirst("console.".count))
      : argument
    guard
      let key = Self.allCases.first(where: {
        $0.rawValue == normalized || $0.cliName == normalized
      })
    else {
      throw MikroKhorosError.configuration("unknown console configuration key")
    }
    self = key
  }
}

public struct ConsoleConfiguration: Codable, Equatable, Sendable {
  public private(set) var maximumInputCharacters: Int
  public private(set) var maximumQueueDepth: Int
  public private(set) var maximumHistoryEntries: Int
  public private(set) var maximumSuggestions: Int
  public private(set) var escapeTimeoutMilliseconds: Int

  public init(
    maximumInputCharacters: Int = 65_536,
    maximumQueueDepth: Int = 256,
    maximumHistoryEntries: Int = 1_000,
    maximumSuggestions: Int = 12,
    escapeTimeoutMilliseconds: Int = 30
  ) throws {
    self.maximumInputCharacters = maximumInputCharacters
    self.maximumQueueDepth = maximumQueueDepth
    self.maximumHistoryEntries = maximumHistoryEntries
    self.maximumSuggestions = maximumSuggestions
    self.escapeTimeoutMilliseconds = escapeTimeoutMilliseconds
    try validate()
  }

  private init(validated: Bool) {
    maximumInputCharacters = 65_536
    maximumQueueDepth = 256
    maximumHistoryEntries = 1_000
    maximumSuggestions = 12
    escapeTimeoutMilliseconds = 30
  }

  public static let defaults = ConsoleConfiguration(validated: true)

  public func value(for key: ConsoleConfigurationKey) -> Int {
    switch key {
    case .maximumInputCharacters: maximumInputCharacters
    case .maximumQueueDepth: maximumQueueDepth
    case .maximumHistoryEntries: maximumHistoryEntries
    case .maximumSuggestions: maximumSuggestions
    case .escapeTimeoutMilliseconds: escapeTimeoutMilliseconds
    }
  }

  public func setting(_ key: ConsoleConfigurationKey, to value: Int) throws
    -> ConsoleConfiguration
  {
    var copy = self
    switch key {
    case .maximumInputCharacters: copy.maximumInputCharacters = value
    case .maximumQueueDepth: copy.maximumQueueDepth = value
    case .maximumHistoryEntries: copy.maximumHistoryEntries = value
    case .maximumSuggestions: copy.maximumSuggestions = value
    case .escapeTimeoutMilliseconds: copy.escapeTimeoutMilliseconds = value
    }
    try copy.validate()
    return copy
  }

  public func resetting(_ key: ConsoleConfigurationKey) throws -> ConsoleConfiguration {
    try setting(key, to: Self.defaults.value(for: key))
  }

  public func validate() throws {
    guard ConsoleConfigurationKey.allCases.allSatisfy({ value(for: $0) > 0 }) else {
      throw MikroKhorosError.configuration(
        "console configuration values must be positive integers"
      )
    }
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownConfigurationKeys(
      from: decoder,
      allowed: Set(ConsoleConfigurationKey.allCases.map(\.rawValue))
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        maximumInputCharacters: container.decodeIfPresent(
          Int.self, forKey: .maximumInputCharacters
        ) ?? Self.defaults.maximumInputCharacters,
        maximumQueueDepth: container.decodeIfPresent(
          Int.self, forKey: .maximumQueueDepth
        ) ?? Self.defaults.maximumQueueDepth,
        maximumHistoryEntries: container.decodeIfPresent(
          Int.self, forKey: .maximumHistoryEntries
        ) ?? Self.defaults.maximumHistoryEntries,
        maximumSuggestions: container.decodeIfPresent(
          Int.self, forKey: .maximumSuggestions
        ) ?? Self.defaults.maximumSuggestions,
        escapeTimeoutMilliseconds: container.decodeIfPresent(
          Int.self, forKey: .escapeTimeoutMilliseconds
        ) ?? Self.defaults.escapeTimeoutMilliseconds
      )
    } catch {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "invalid console configuration")
      )
    }
  }
}

public enum OutputMode: String, Codable, CaseIterable, Sendable {
  case auto
  case human
  case yaml
  case json
}

public enum ColorMode: String, Codable, CaseIterable, Sendable {
  case auto
  case always
  case never
}

public enum UnicodeMode: String, Codable, CaseIterable, Sendable {
  case auto
  case always
  case never
}

public enum PresentationConfigurationKey: String, CaseIterable, Codable, Sendable {
  case output
  case color
  case unicode

  public var path: String { "presentation.\(rawValue)" }

  public init(argument: String) throws {
    let normalized =
      argument.hasPrefix("presentation.")
      ? String(argument.dropFirst("presentation.".count)) : argument
    guard let key = Self(rawValue: normalized) else {
      throw MikroKhorosError.configuration("unknown presentation configuration key")
    }
    self = key
  }
}

public struct PresentationConfiguration: Codable, Equatable, Sendable {
  public let output: OutputMode
  public let color: ColorMode
  public let unicode: UnicodeMode

  public init(
    output: OutputMode = .auto,
    color: ColorMode = .auto,
    unicode: UnicodeMode = .auto
  ) {
    self.output = output
    self.color = color
    self.unicode = unicode
  }

  public static let defaults = PresentationConfiguration()

  public func value(for key: PresentationConfigurationKey) -> String {
    switch key {
    case .output: output.rawValue
    case .color: color.rawValue
    case .unicode: unicode.rawValue
    }
  }

  public func setting(_ key: PresentationConfigurationKey, to value: String) throws
    -> PresentationConfiguration
  {
    switch key {
    case .output:
      guard let output = OutputMode(rawValue: value) else {
        throw MikroKhorosError.configuration(
          "presentation.output must be auto, human, yaml, or json")
      }
      return PresentationConfiguration(output: output, color: color, unicode: unicode)
    case .color:
      guard let color = ColorMode(rawValue: value) else {
        throw MikroKhorosError.configuration("presentation.color must be auto, always, or never")
      }
      return PresentationConfiguration(output: output, color: color, unicode: unicode)
    case .unicode:
      guard let unicode = UnicodeMode(rawValue: value) else {
        throw MikroKhorosError.configuration("presentation.unicode must be auto, always, or never")
      }
      return PresentationConfiguration(output: output, color: color, unicode: unicode)
    }
  }

  public func resetting(_ key: PresentationConfigurationKey) throws -> PresentationConfiguration {
    try setting(key, to: Self.defaults.value(for: key))
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownConfigurationKeys(
      from: decoder,
      allowed: Set(PresentationConfigurationKey.allCases.map(\.rawValue))
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    output = try container.decodeIfPresent(OutputMode.self, forKey: .output) ?? .auto
    color = try container.decodeIfPresent(ColorMode.self, forKey: .color) ?? .auto
    unicode = try container.decodeIfPresent(UnicodeMode.self, forKey: .unicode) ?? .auto
  }
}

public struct RuntimeConfiguration: Codable, Equatable, Sendable {
  public static let currentVersion = 2

  public let version: Int
  public let agents: AgentDefaults
  public let runtime: RuntimeLimits
  public let console: ConsoleConfiguration
  public let presentation: PresentationConfiguration

  private enum CodingKeys: String, CodingKey {
    case version, agents, runtime, console, presentation
  }

  public init(
    version: Int = currentVersion,
    agents: AgentDefaults = .defaults,
    runtime: RuntimeLimits = .defaults,
    console: ConsoleConfiguration = .defaults,
    presentation: PresentationConfiguration = .defaults
  ) throws {
    guard version == Self.currentVersion else {
      throw MikroKhorosError.configuration("unsupported configuration version")
    }
    try runtime.validate()
    try console.validate()
    self.version = version
    self.agents = agents
    self.runtime = runtime
    self.console = console
    self.presentation = presentation
  }

  private init(
    validatedAgents: AgentDefaults,
    validatedRuntime: RuntimeLimits,
    validatedConsole: ConsoleConfiguration,
    validatedPresentation: PresentationConfiguration
  ) {
    version = Self.currentVersion
    agents = validatedAgents
    runtime = validatedRuntime
    console = validatedConsole
    presentation = validatedPresentation
  }

  public static let defaults = RuntimeConfiguration(
    validatedAgents: .defaults,
    validatedRuntime: .defaults,
    validatedConsole: .defaults,
    validatedPresentation: .defaults
  )

  public func validate() throws {
    guard version == Self.currentVersion else {
      throw MikroKhorosError.configuration("unsupported configuration version")
    }
    guard agents.maximumActionsPerResponse > 0 else {
      throw MikroKhorosError.configuration(
        "agents.maximum-actions-per-response must be a positive integer"
      )
    }
    try runtime.validate()
    try console.validate()
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownConfigurationKeys(
      from: decoder,
      allowed: [
        CodingKeys.version.rawValue,
        CodingKeys.agents.rawValue,
        CodingKeys.runtime.rawValue,
        CodingKeys.console.rawValue,
        CodingKeys.presentation.rawValue,
      ]
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedVersion = try container.decode(Int.self, forKey: .version)
    guard decodedVersion == 1 || decodedVersion == Self.currentVersion else {
      throw MikroKhorosError.configuration("unsupported configuration version")
    }
    try self.init(
      version: Self.currentVersion,
      agents: container.decode(AgentDefaults.self, forKey: .agents),
      runtime: container.decode(RuntimeLimits.self, forKey: .runtime),
      console: container.decodeIfPresent(ConsoleConfiguration.self, forKey: .console)
        ?? .defaults,
      presentation: container.decodeIfPresent(PresentationConfiguration.self, forKey: .presentation)
        ?? .defaults
    )
  }

  public func settingAgentMaximumActions(_ value: Int) throws -> RuntimeConfiguration {
    try RuntimeConfiguration(
      agents: AgentDefaults(maximumActionsPerResponse: value),
      runtime: runtime,
      console: console,
      presentation: presentation
    )
  }

  public func settingRuntimeLimit(
    _ key: RuntimeLimitKey,
    to value: Int
  ) throws -> RuntimeConfiguration {
    try RuntimeConfiguration(
      agents: agents,
      runtime: runtime.setting(key, to: value),
      console: console,
      presentation: presentation
    )
  }

  public func resettingRuntimeLimit(_ key: RuntimeLimitKey) throws -> RuntimeConfiguration {
    try RuntimeConfiguration(
      agents: agents,
      runtime: runtime.resetting(key),
      console: console,
      presentation: presentation
    )
  }

  public func resettingAgentMaximumActions() throws -> RuntimeConfiguration {
    try settingAgentMaximumActions(AgentDefaults.defaults.maximumActionsPerResponse)
  }

  public func settingConsoleValue(
    _ key: ConsoleConfigurationKey,
    to value: Int
  ) throws -> RuntimeConfiguration {
    try RuntimeConfiguration(
      agents: agents,
      runtime: runtime,
      console: console.setting(key, to: value),
      presentation: presentation
    )
  }

  public func resettingConsoleValue(
    _ key: ConsoleConfigurationKey
  ) throws -> RuntimeConfiguration {
    try RuntimeConfiguration(
      agents: agents,
      runtime: runtime,
      console: console.resetting(key),
      presentation: presentation
    )
  }

  public func settingPresentationValue(
    _ key: PresentationConfigurationKey,
    to value: String
  ) throws -> RuntimeConfiguration {
    try RuntimeConfiguration(
      agents: agents,
      runtime: runtime,
      console: console,
      presentation: presentation.setting(key, to: value)
    )
  }

  public func resettingPresentationValue(
    _ key: PresentationConfigurationKey
  ) throws -> RuntimeConfiguration {
    try RuntimeConfiguration(
      agents: agents,
      runtime: runtime,
      console: console,
      presentation: presentation.resetting(key)
    )
  }
}

public enum ConfigurationValue: Equatable, Sendable, CustomStringConvertible {
  case integer(Int)
  case text(String)

  public var description: String {
    switch self {
    case .integer(let value): String(value)
    case .text(let value): value
    }
  }
}

public enum ConfigurationKey: Equatable, Sendable {
  case agentMaximumActionsPerResponse
  case runtime(RuntimeLimitKey)
  case console(ConsoleConfigurationKey)
  case presentation(PresentationConfigurationKey)

  public static let all: [ConfigurationKey] =
    [
      .agentMaximumActionsPerResponse
    ] + RuntimeLimitKey.allCases.map(ConfigurationKey.runtime)
    + ConsoleConfigurationKey.allCases.map(ConfigurationKey.console)
    + PresentationConfigurationKey.allCases.map(ConfigurationKey.presentation)

  public init(argument: String) throws {
    let agentNames = [
      "agents.maximumActionsPerResponse",
      "agents.maximum-actions-per-response",
      "agent.maximumActionsPerResponse",
      "agent.maximum-actions-per-response",
    ]
    if agentNames.contains(argument) {
      self = .agentMaximumActionsPerResponse
    } else if argument.hasPrefix("presentation.") {
      self = .presentation(try PresentationConfigurationKey(argument: argument))
    } else if argument.hasPrefix("console.") {
      self = .console(try ConsoleConfigurationKey(argument: argument))
    } else {
      self = .runtime(try RuntimeLimitKey(argument: argument))
    }
  }

  public var path: String {
    switch self {
    case .agentMaximumActionsPerResponse:
      "agents.maximumActionsPerResponse"
    case .runtime(let key):
      "runtime.\(key.rawValue)"
    case .console(let key):
      "console.\(key.rawValue)"
    case .presentation(let key):
      key.path
    }
  }

  public func value(in configuration: RuntimeConfiguration) -> ConfigurationValue {
    switch self {
    case .agentMaximumActionsPerResponse:
      .integer(configuration.agents.maximumActionsPerResponse)
    case .runtime(let key):
      .integer(configuration.runtime.value(for: key))
    case .console(let key):
      .integer(configuration.console.value(for: key))
    case .presentation(let key):
      .text(configuration.presentation.value(for: key))
    }
  }

  public func setting(
    _ argument: String,
    in configuration: RuntimeConfiguration
  ) throws -> RuntimeConfiguration {
    switch self {
    case .agentMaximumActionsPerResponse:
      let value = try Self.integer(argument, key: path)
      return try configuration.settingAgentMaximumActions(value)
    case .runtime(let key):
      let value = try Self.integer(argument, key: path)
      return try configuration.settingRuntimeLimit(key, to: value)
    case .console(let key):
      let value = try Self.integer(argument, key: path)
      return try configuration.settingConsoleValue(key, to: value)
    case .presentation(let key):
      return try configuration.settingPresentationValue(key, to: argument)
    }
  }

  public func setting(
    _ value: Int,
    in configuration: RuntimeConfiguration
  ) throws -> RuntimeConfiguration {
    try setting(String(value), in: configuration)
  }

  public func resetting(
    in configuration: RuntimeConfiguration
  ) throws -> RuntimeConfiguration {
    switch self {
    case .agentMaximumActionsPerResponse:
      try configuration.resettingAgentMaximumActions()
    case .runtime(let key):
      try configuration.resettingRuntimeLimit(key)
    case .console(let key):
      try configuration.resettingConsoleValue(key)
    case .presentation(let key):
      try configuration.resettingPresentationValue(key)
    }
  }

  private static func integer(_ argument: String, key: String) throws -> Int {
    guard let value = Int(argument) else {
      throw MikroKhorosError.configuration("\(key) must be an integer")
    }
    return value
  }
}

public enum ConfigurationStore {
  private static let maximumBytes = 1_048_576

  public static var defaultURL: URL {
    MikroKhorosPaths.root
      .appendingPathComponent("config.json", isDirectory: false)
  }

  public static func load(from url: URL = defaultURL) throws -> RuntimeConfiguration {
    guard FileManager.default.fileExists(atPath: url.path) else { return .defaults }
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      if let size = values.fileSize, size > maximumBytes {
        throw MikroKhorosError.configuration("configuration file is too large")
      }
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      let configuration = try JSONDecoder().decode(RuntimeConfiguration.self, from: data)
      try configuration.validate()
      return configuration
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.configuration("could not read the configuration JSON")
    }
  }

  public static func save(
    _ configuration: RuntimeConfiguration,
    to url: URL = defaultURL
  ) throws {
    do {
      try configuration.validate()
      let directory = url.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      let data = try encoder.encode(configuration)
      try data.write(to: url, options: [.atomic])
      #if !os(Windows)
        try? FileManager.default.setAttributes(
          [.posixPermissions: 0o600],
          ofItemAtPath: url.path
        )
      #endif
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.configuration("could not write the configuration JSON")
    }
  }
}
