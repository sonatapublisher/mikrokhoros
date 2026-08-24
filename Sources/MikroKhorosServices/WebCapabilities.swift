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
import MikroKhoros

/// The stable top-level mikrokhoros Web surfaces. These values are deliberately
/// independent of any particular transport (HTML, terminal, or a native host).
public enum WebView: String, CaseIterable, Codable, Sendable {
  case world
  case agentManager
  case inventory
  case packages
  case templates
  case settings
  case help
}

extension WebView {
  /// The five persistent browser routes. Settings and Help are also
  /// descriptor placements, but are not world-page routes.
  public static var primary: [WebView] {
    [.world, .agentManager, .inventory, .packages, .templates]
  }
}

/// How a command receives its world context.
public enum WebCapabilityScope: String, Codable, Sendable {
  case global
  case selectedWorld
  case explicitWorld
  case assignmentDerived
}

/// The interaction contract a host must honor for a capability.
public enum WebCapabilityInteractionMode: String, Codable, Sendable {
  case projection
  case form
  case confirmation
  case secret
  case agentController
  case reportStream
  case download
  case privateViewer
  case hostStatus
  case help
}

public enum WebCapabilityHistoryPolicy: String, Codable, Sendable {
  case store
  case omit
}

/// Field syntax without importing the CLI command model into the service
/// target.  The option/flag spelling is retained because it is part of the
/// generated command description, not executable input supplied by a browser.
public enum WebCapabilityFieldSyntax: Equatable, Codable, Sendable {
  case positional
  case option(String)
  case flag(String)

  private enum CodingKeys: String, CodingKey {
    case kind
    case spelling
  }

  private enum Kind: String, Codable {
    case positional
    case option
    case flag
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .positional:
      self = .positional
    case .option:
      self = .option(try container.decode(String.self, forKey: .spelling))
    case .flag:
      self = .flag(try container.decode(String.self, forKey: .spelling))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .positional:
      try container.encode(Kind.positional, forKey: .kind)
    case .option(let spelling):
      try container.encode(Kind.option, forKey: .kind)
      try container.encode(spelling, forKey: .spelling)
    case .flag(let spelling):
      try container.encode(Kind.flag, forKey: .kind)
      try container.encode(spelling, forKey: .spelling)
    }
  }

  public var spelling: String? {
    switch self {
    case .positional: nil
    case .option(let spelling), .flag(let spelling): spelling
    }
  }
}

public enum WebCapabilityFieldCardinality: String, Codable, Sendable {
  case required
  case optional
  case repeated
  case requiredRepeated
}

/// Safe, catalog-derived completion metadata. Dynamic providers are named but
/// never expanded by this DTO into paths, environment values, credentials, or
/// private history.
public enum WebCapabilityCompletion: Equatable, Codable, Sendable {
  case none
  case choices([String])
  case catalog(String)
  case unavailable(String)

  private enum CodingKeys: String, CodingKey {
    case kind
    case values
    case name
  }

  private enum Kind: String, Codable {
    case none
    case choices
    case catalog
    case unavailable
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .none:
      self = .none
    case .choices:
      self = .choices(try container.decode([String].self, forKey: .values))
    case .catalog:
      self = .catalog(try container.decode(String.self, forKey: .name))
    case .unavailable:
      self = .unavailable(try container.decode(String.self, forKey: .name))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .none:
      try container.encode(Kind.none, forKey: .kind)
    case .choices(let values):
      try container.encode(Kind.choices, forKey: .kind)
      try container.encode(values, forKey: .values)
    case .catalog(let name):
      try container.encode(Kind.catalog, forKey: .kind)
      try container.encode(name, forKey: .name)
    case .unavailable(let name):
      try container.encode(Kind.unavailable, forKey: .kind)
      try container.encode(name, forKey: .name)
    }
  }

  public var canonicalKind: String {
    switch self {
    case .none: "none"
    case .choices: "choices"
    case .catalog(let name), .unavailable(let name): name
    }
  }

  public var isSafe: Bool {
    switch self {
    case .none, .choices, .catalog: true
    case .unavailable: false
    }
  }
}

public struct WebCapabilityField: Codable, Equatable, Sendable {
  public let id: String
  public let label: String
  public let help: String
  public let syntax: WebCapabilityFieldSyntax
  public let cardinality: WebCapabilityFieldCardinality
  public let completion: WebCapabilityCompletion
  public let safeDefault: String?
  public let historyPolicy: WebCapabilityHistoryPolicy

  public init(
    id: String,
    label: String,
    help: String = "",
    syntax: WebCapabilityFieldSyntax,
    cardinality: WebCapabilityFieldCardinality,
    completion: WebCapabilityCompletion = .none,
    safeDefault: String? = nil,
    historyPolicy: WebCapabilityHistoryPolicy = .store
  ) {
    self.id = id
    self.label = label
    self.help = help
    self.syntax = syntax
    self.cardinality = cardinality
    self.completion = completion
    self.safeDefault = historyPolicy == .store ? safeDefault : nil
    self.historyPolicy = historyPolicy
  }

  public var isPrivate: Bool { historyPolicy == .omit }
  public var isSecret: Bool { historyPolicy == .omit && completion == .none }
}

/// A complete, transport-neutral description of one live command leaf.
public struct WebCapabilityDescriptor: Codable, Equatable, Sendable {
  public let id: String
  public let commandKind: String
  public let canonicalPath: [String]
  public let label: String
  public let summary: String
  public let help: String
  public let fields: [WebCapabilityField]
  public let placement: WebView
  public let section: String
  public let scope: WebCapabilityScope
  public let interaction: WebCapabilityInteractionMode
  public let enabled: Bool
  public let refreshTargets: [WebCapabilityRefreshTarget]
  public let successReference: String
  public let failureReference: String

  public init(
    id: String,
    commandKind: String,
    canonicalPath: [String],
    label: String,
    summary: String,
    help: String,
    fields: [WebCapabilityField],
    placement: WebView,
    section: String,
    scope: WebCapabilityScope,
    interaction: WebCapabilityInteractionMode,
    enabled: Bool = true,
    refreshTargets: [WebCapabilityRefreshTarget] = [.none],
    successReference: String = "command.success",
    failureReference: String = "command.failure"
  ) {
    self.id = id
    self.commandKind = commandKind
    self.canonicalPath = canonicalPath
    self.label = label
    self.summary = summary
    self.help = help
    self.fields = fields
    self.placement = placement
    self.section = section
    self.scope = scope
    self.interaction = interaction
    self.enabled = enabled
    var unique = Set(refreshTargets)
    if unique.count > 1 { unique.remove(.none) }
    self.refreshTargets = WebCapabilityRefreshTarget.allCases.filter(unique.contains)
    self.successReference = successReference
    self.failureReference = failureReference
  }

  public var syntax: String { canonicalPath.joined(separator: " ") }
  public var successTestID: String { successReference }
  public var failureTestID: String { failureReference }
  public var privateFieldIDs: Set<String> {
    Set(fields.filter(\.isPrivate).map(\.id))
  }
}

public enum WebCapabilityResultCategory: String, Codable, Sendable {
  case success
  case failure
  case rejected
  case busy
  case unavailable
  case prepared
}

public enum WebCapabilityRefreshTarget: String, Codable, CaseIterable, Sendable {
  case world
  case agents
  case inventory
  case packages
  case templates
  case settings
  case none
}

/// Typed request values. There is intentionally no raw argv or browser-global
/// option member here; the gateway supplies trusted globals and exact layout.
public struct WebCapabilityRequest: Codable, Equatable, Sendable {
  public let capabilityID: String
  public let fields: [String: [String]]
  public let exactWorldID: String?
  public let sessionID: String?
  public let secret: Data?
  public let interaction: WebCapabilityInteractionMode?

  public init(
    capabilityID: String,
    fields: [String: [String]] = [:],
    exactWorldID: String? = nil,
    sessionID: String? = nil,
    secret: Data? = nil,
    interaction: WebCapabilityInteractionMode? = nil
  ) {
    self.capabilityID = capabilityID
    self.fields = fields
    self.exactWorldID = exactWorldID
    self.sessionID = sessionID
    self.secret = secret
    self.interaction = interaction
  }

  public init(
    commandID: String,
    values: [String: [String]] = [:],
    exactWorldID: String? = nil,
    sessionID: String? = nil,
    secret: Data? = nil,
    interaction: WebCapabilityInteractionMode? = nil
  ) {
    self.init(
      capabilityID: commandID,
      fields: values,
      exactWorldID: exactWorldID,
      sessionID: sessionID,
      secret: secret,
      interaction: interaction
    )
  }

  public var values: [String: [String]] { fields }
  public var secretBytes: Data? { secret }
}

public struct WebCapabilityExecutionResult: Codable, Equatable, Sendable {
  public let accepted: Bool
  public let displayCommand: String
  public let standardOutput: String
  public let standardError: String
  public let exitStatus: Int
  public let outputTruncated: Bool
  public let refreshTargets: [WebCapabilityRefreshTarget]
  public let category: WebCapabilityResultCategory

  public init(
    accepted: Bool,
    displayCommand: String,
    standardOutput: String = "",
    standardError: String = "",
    exitStatus: Int,
    outputTruncated: Bool = false,
    refreshTargets: [WebCapabilityRefreshTarget] = [.none],
    category: WebCapabilityResultCategory
  ) {
    self.accepted = accepted
    self.displayCommand = displayCommand
    self.standardOutput = standardOutput
    self.standardError = standardError
    self.exitStatus = exitStatus
    self.outputTruncated = outputTruncated
    var unique = Set(refreshTargets)
    if unique.count > 1 { unique.remove(.none) }
    self.refreshTargets = WebCapabilityRefreshTarget.allCases.filter(unique.contains)
    self.category = category
  }

  public var stdout: String { standardOutput }
  public var stderr: String { standardError }
  public var status: Int { exitStatus }
  public var truncated: Bool { outputTruncated }
  public var refreshTargetSet: Set<WebCapabilityRefreshTarget> {
    Set(refreshTargets)
  }
}

public struct WebCapabilityPlan: Codable, Equatable, Sendable {
  public let planID: String
  public let capabilityID: String
  public let expiresAt: Date
  public let commandSummary: String
  public let consequenceSummary: String

  public init(
    planID: String,
    capabilityID: String,
    expiresAt: Date,
    commandSummary: String,
    consequenceSummary: String
  ) {
    self.planID = planID
    self.capabilityID = capabilityID
    self.expiresAt = expiresAt
    self.commandSummary = commandSummary
    self.consequenceSummary = consequenceSummary
  }
}

public struct WebCapabilityCommitRequest: Codable, Equatable, Sendable {
  public let planID: String
  public let sessionID: String

  public init(
    planID: String,
    sessionID: String
  ) {
    self.planID = planID
    self.sessionID = sessionID
  }
}

/// Host lifecycle state is a small neutral projection. A web host may enrich
/// it with a loopback port, while a stopped/embedded host can leave those
/// values absent. No executable callback or listener is represented here.
public enum WebHostLifecycle: String, Codable, Sendable {
  case stopped
  case starting
  case running
  case unavailable
}

public struct WebHostState: Codable, Equatable, Sendable {
  public let lifecycle: WebHostLifecycle
  public let address: String?
  public let port: Int?

  public init(
    lifecycle: WebHostLifecycle,
    address: String? = nil,
    port: Int? = nil
  ) {
    self.lifecycle = lifecycle
    self.address = address
    self.port = port
  }
}

/// Trusted host context supplied out-of-band from browser JSON. This keeps the
/// product layout, session binding, and listener state under native host control.
public struct WebCapabilityContext: Equatable, Sendable {
  public let layout: ProductLayout
  public let sessionID: String
  public let hostState: WebHostState

  public init(
    layout: ProductLayout,
    sessionID: String,
    hostState: WebHostState
  ) {
    self.layout = layout
    self.sessionID = sessionID
    self.hostState = hostState
  }
}

public struct WebCapabilityCompletionRequest: Equatable, Sendable {
  public let capabilityID: String
  public let fieldID: String
  public let source: String
  public let fields: [String: [String]]
  public let exactWorldID: String?

  public init(
    capabilityID: String,
    fieldID: String,
    source: String = "",
    fields: [String: [String]] = [:],
    exactWorldID: String? = nil
  ) {
    self.capabilityID = capabilityID
    self.fieldID = fieldID
    self.source = source
    self.fields = fields
    self.exactWorldID = exactWorldID
  }
}

public struct WebCapabilityCompletionValue: Codable, Equatable, Sendable {
  public let value: String
  public let label: String

  public init(value: String, label: String? = nil) {
    self.value = value
    self.label = label ?? value
  }
}

public enum WebCapabilityError: Error, Equatable, Sendable {
  case unknownCapability
  case invalidField(String)
  case missingField(String)
  case duplicateField(String)
  case invalidValue(String)
  case invalidWorldContext
  case globalOptionsRejected
  case wrongInteraction
  case unavailable
  case busy
  case secretRequired
  case secretNotAllowed
  case invalidSession
  case expiredPlan
  case replayedPlan
  case tamperedPlan
  case invalidPlan
}

/// Service-layer boundary consumed by mikrokhoros Web and future native hosts. Implementations
/// may use the CLI command catalog internally, but this protocol does not
/// expose CLI types or process execution to its callers.
public protocol WebCapabilityServing: Sendable {
  func descriptors(
    in context: WebCapabilityContext
  ) throws -> [WebCapabilityDescriptor]
  func completions(
    for request: WebCapabilityCompletionRequest,
    in context: WebCapabilityContext
  ) async throws -> [WebCapabilityCompletionValue]
  func execute(
    _ request: WebCapabilityRequest,
    in context: WebCapabilityContext
  ) async throws -> WebCapabilityExecutionResult
  func prepare(
    _ request: WebCapabilityRequest,
    in context: WebCapabilityContext
  ) async throws -> WebCapabilityPlan
  func commit(
    _ request: WebCapabilityCommitRequest,
    in context: WebCapabilityContext
  ) async throws -> WebCapabilityExecutionResult
  func reportStream(
    _ request: WebCapabilityRequest,
    in context: WebCapabilityContext
  ) async throws -> AsyncThrowingStream<String, Error>
}
