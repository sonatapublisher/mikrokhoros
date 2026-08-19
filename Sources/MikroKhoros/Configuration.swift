import Foundation

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
    }
  }

  public init(argument: String) throws {
    let prefixes = ["runtime.", "limits."]
    let normalized =
      prefixes.first(where: { argument.hasPrefix($0) })
      .map { String(argument.dropFirst($0.count)) } ?? argument
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
    minimumProtectedVerbatimWords: Int
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
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownConfigurationKeys(
      from: decoder,
      allowed: Set(RuntimeLimitKey.allCases.map(\.rawValue))
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
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
        )
      )
    } catch {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "invalid runtime limits")
      )
    }
  }
}

public struct RuntimeConfiguration: Codable, Equatable, Sendable {
  public static let currentVersion = 1

  public let version: Int
  public let agents: AgentDefaults
  public let runtime: RuntimeLimits

  private enum CodingKeys: String, CodingKey {
    case version, agents, runtime
  }

  public init(
    version: Int = currentVersion,
    agents: AgentDefaults = .defaults,
    runtime: RuntimeLimits = .defaults
  ) throws {
    guard version == Self.currentVersion else {
      throw MikroKhorosError.configuration("unsupported configuration version")
    }
    try runtime.validate()
    self.version = version
    self.agents = agents
    self.runtime = runtime
  }

  private init(validatedAgents: AgentDefaults, validatedRuntime: RuntimeLimits) {
    version = Self.currentVersion
    agents = validatedAgents
    runtime = validatedRuntime
  }

  public static let defaults = RuntimeConfiguration(
    validatedAgents: .defaults,
    validatedRuntime: .defaults
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
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownConfigurationKeys(
      from: decoder,
      allowed: [
        CodingKeys.version.rawValue,
        CodingKeys.agents.rawValue,
        CodingKeys.runtime.rawValue,
      ]
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      version: container.decode(Int.self, forKey: .version),
      agents: container.decode(AgentDefaults.self, forKey: .agents),
      runtime: container.decode(RuntimeLimits.self, forKey: .runtime)
    )
  }

  public func settingAgentMaximumActions(_ value: Int) throws -> RuntimeConfiguration {
    try RuntimeConfiguration(
      agents: AgentDefaults(maximumActionsPerResponse: value),
      runtime: runtime
    )
  }

  public func settingRuntimeLimit(
    _ key: RuntimeLimitKey,
    to value: Int
  ) throws -> RuntimeConfiguration {
    try RuntimeConfiguration(agents: agents, runtime: runtime.setting(key, to: value))
  }

  public func resettingRuntimeLimit(_ key: RuntimeLimitKey) throws -> RuntimeConfiguration {
    try RuntimeConfiguration(agents: agents, runtime: runtime.resetting(key))
  }

  public func resettingAgentMaximumActions() throws -> RuntimeConfiguration {
    try settingAgentMaximumActions(AgentDefaults.defaults.maximumActionsPerResponse)
  }
}

public enum ConfigurationKey: Equatable, Sendable {
  case agentMaximumActionsPerResponse
  case runtime(RuntimeLimitKey)

  public static let all: [ConfigurationKey] =
    [
      .agentMaximumActionsPerResponse
    ] + RuntimeLimitKey.allCases.map(ConfigurationKey.runtime)

  public init(argument: String) throws {
    let agentNames = [
      "agents.maximumActionsPerResponse",
      "agents.maximum-actions-per-response",
      "agent.maximumActionsPerResponse",
      "agent.maximum-actions-per-response",
    ]
    if agentNames.contains(argument) {
      self = .agentMaximumActionsPerResponse
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
    }
  }

  public func value(in configuration: RuntimeConfiguration) -> Int {
    switch self {
    case .agentMaximumActionsPerResponse:
      configuration.agents.maximumActionsPerResponse
    case .runtime(let key):
      configuration.runtime.value(for: key)
    }
  }

  public func setting(
    _ value: Int,
    in configuration: RuntimeConfiguration
  ) throws -> RuntimeConfiguration {
    switch self {
    case .agentMaximumActionsPerResponse:
      try configuration.settingAgentMaximumActions(value)
    case .runtime(let key):
      try configuration.settingRuntimeLimit(key, to: value)
    }
  }

  public func resetting(
    in configuration: RuntimeConfiguration
  ) throws -> RuntimeConfiguration {
    switch self {
    case .agentMaximumActionsPerResponse:
      try configuration.resettingAgentMaximumActions()
    case .runtime(let key):
      try configuration.resettingRuntimeLimit(key)
    }
  }
}

public enum ConfigurationStore {
  private static let maximumBytes = 1_048_576

  public static var defaultURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".mikrokhoros", isDirectory: true)
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
