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

import Crypto
import Foundation
import MikroKhoros
import MikroKhorosServices

/// Marks the narrow in-process path that presents a command result to the
/// loopback browser. Terminal commands retain their complete administrative
/// output; browser-safe presentation must be selected at the output source.
enum WebPresentationContext {
  @TaskLocal static var isActive = false
}

/// Exhaustive browser placement for the live human command catalog.
///
/// The browser consumes only the neutral descriptors. Command parsing and
/// execution remain in CLIKit so MikroKhoros Web cannot acquire a
/// second command grammar or dispatch table.
public enum CLIWebCapabilityRegistry {
  public static func descriptors() -> [WebCapabilityDescriptor] {
    CommandCatalog.all.map(descriptor(for:))
  }

  public static func descriptor(
    for definition: CommandDefinition
  ) -> WebCapabilityDescriptor {
    let policy = policy(for: definition)
    let unavailableMessage = browserUnavailableMessage(for: definition.kind)
    var fields = definition.fields
      .filter {
        if definition.kind == .web { return false }
        if definition.kind == .inventorySecretSet,
          ["stdin", "from-env"].contains($0.id)
        {
          return false
        }
        if policy.interaction == .confirmation, $0.id == "yes" { return false }
        return true
      }
      .map { field in
        let projected = webField(field, for: definition.kind)
        let cardinality: WebCapabilityFieldCardinality?
        switch (definition.kind, field.id) {
        case (.agentShell, "action"):
          cardinality = .requiredRepeated
        case (.worldShow, "world"):
          cardinality = .required
        default:
          cardinality = nil
        }
        guard let cardinality else { return projected }
        return WebCapabilityField(
          id: projected.id,
          label: projected.label,
          help: projected.help,
          syntax: projected.syntax,
          cardinality: cardinality,
          completion: projected.completion,
          safeDefault: projected.safeDefault,
          historyPolicy: projected.historyPolicy
        )
      }
    if definition.kind == .inventorySecretSet {
      fields.append(
        WebCapabilityField(
          id: "credential-value",
          label: "Credential value",
          help: "Write-only value. It is cleared after submission and never returned.",
          syntax: .positional,
          cardinality: .required,
          historyPolicy: .omit
        )
      )
    }
    return WebCapabilityDescriptor(
      id: definition.kind.rawValue,
      commandKind: definition.kind.rawValue,
      canonicalPath: definition.path,
      label: definition.path.joined(separator: " "),
      summary: unavailableMessage ?? presentationSummary(for: definition),
      help: unavailableMessage ?? definition.longDescription,
      fields: fields,
      placement: policy.view,
      section: policy.section,
      scope: policy.scope,
      interaction: policy.interaction,
      enabled: unavailableMessage == nil,
      refreshTargets: policy.refreshTargets,
      successReference: "web-\(testID(definition))-success",
      failureReference: "web-\(testID(definition))-failure"
    )
  }

  static func definition(id: String) -> CommandDefinition? {
    CommandCatalog.all.first { $0.kind.rawValue == id }
  }

  /// Small browser-specific descriptions make security projections explicit
  /// without changing the command catalog or its execution semantics.
  private static func presentationSummary(for definition: CommandDefinition) -> String {
    switch definition.kind {
    case .web:
      "Show the running MikroKhoros Web host."
    case .configPath:
      "Show which configuration file is selected without exposing its host path."
    case .worldInspect:
      "Reveal the selected World's private administrative snapshot in this local session."
    case .worldExport:
      "Download the selected World's private journal and administrative state."
    default:
      definition.summary
    }
  }

  /// These command outputs contain raw administrative object snapshots. The
  /// browser host exposes only the corresponding bounded domain projections.
  private static func browserUnavailableMessage(for kind: CommandKind) -> String? {
    switch kind {
    case .inventoryCopiesShow, .worldObjectShow:
      "Unavailable in the local browser because this command exposes a raw administrative object snapshot. Use the local CLI."
    case .inventoryShow:
      "Unavailable in the local browser because this command exposes an administrative source snapshot. Use the local CLI."
    default:
      nil
    }
  }

  private static func webField(
    _ field: CommandField,
    for commandKind: CommandKind
  ) -> WebCapabilityField {
    let syntax: WebCapabilityFieldSyntax
    switch field.syntax {
    case .positional: syntax = .positional
    case .option(let spelling): syntax = .option(spelling)
    case .flag(let spelling): syntax = .flag(spelling)
    }
    let cardinality =
      WebCapabilityFieldCardinality(rawValue: field.cardinality.rawValue)
      ?? .optional
    let completion: WebCapabilityCompletion
    switch field.completion {
    case .none: completion = .none
    case .choices(let values): completion = .choices(values)
    case .filesystemPath: completion = .unavailable("file-or-url")
    case .configurationKey: completion = .catalog("configurationKey")
    case .adapterID: completion = .catalog("adapterID")
    case .agentID: completion = .catalog("agentID")
    case .inventoryID: completion = .catalog("inventoryID")
    case .inventoryFolderID: completion = .catalog("inventoryFolderID")
    case .packageID: completion = .catalog("packageID")
    case .worldObjectID: completion = .catalog("worldObjectID")
    case .merchantID: completion = .catalog("merchantID")
    case .reportID: completion = .catalog("reportID")
    case .restockRuleID: completion = .catalog("restockRuleID")
    case .worldID: completion = .catalog("worldID")
    case .worldTemplateID: completion = .catalog("worldTemplateID")
    }
    let safeDefault: String?
    if case .literal(let value) = field.defaultValue {
      safeDefault = value
    } else {
      safeDefault = nil
    }
    let label: String
    let help: String
    if commandKind == .inventoryInstall, field.id == "path-or-url" {
      label = "Trusted package source"
      help = "Use an available built-in package such as builtin:paper, or an HTTPS URL."
    } else {
      label = field.label
      help = field.interactiveHelp
    }
    return WebCapabilityField(
      id: field.id,
      label: label,
      help: help,
      syntax: syntax,
      cardinality: cardinality,
      completion: completion,
      safeDefault: safeDefault,
      historyPolicy: field.historyPolicy == .store ? .store : .omit
    )
  }

  private struct Policy {
    let view: WebView
    let section: String
    let scope: WebCapabilityScope
    let interaction: WebCapabilityInteractionMode
    let refreshTargets: [WebCapabilityRefreshTarget]
  }

  private static func policy(for definition: CommandDefinition) -> Policy {
    let view = placement(for: definition.kind)
    let interaction = interaction(for: definition)
    let scope = scope(for: definition.kind)
    let refreshTargets: [WebCapabilityRefreshTarget]
    if definition.kind == .initialize {
      refreshTargets = [.world, .agents, .inventory, .packages, .templates, .settings]
    } else if isReadOnly(definition.kind)
      || [.help, .hostStatus, .privateViewer, .download, .reportStream]
        .contains(interaction)
    {
      refreshTargets = [.none]
    } else {
      var targets = [refreshTarget(for: view)]
      if scope != .global, !targets.contains(.world) { targets.append(.world) }
      if view == .packages { targets.append(.inventory) }
      if view == .templates, definition.kind == .worldTemplateApply {
        targets.append(contentsOf: [.inventory, .world])
      }
      refreshTargets = targets
    }
    return Policy(
      view: view,
      section: section(for: definition.kind),
      scope: scope,
      interaction: interaction,
      refreshTargets: refreshTargets
    )
  }

  private static func placement(for kind: CommandKind) -> WebView {
    switch kind {
    case .help: .help
    case .web, .initialize, .status, .doctor, .configShow, .configPath, .configKeys,
      .configGet, .configSet, .configReset, .configValidate, .adapters:
      .settings
    case .agentCreate, .agentList, .agentShow, .agentConfigure, .agentAdd, .agentRemove,
      .agentProfileSet, .agentProfileClear, .agentRetry, .agentShell:
      .agentManager
    case .inventoryInstall, .inventoryPackageAvailable, .inventoryPackageList,
      .inventoryPackageShow, .inventoryPackageRemove:
      .packages
    case .inventoryCreate, .inventoryFolderCreate, .inventoryFolderList,
      .inventoryFolderShow, .inventoryFolderRename, .inventoryFolderMove,
      .inventoryFolderDelete, .inventoryMove, .inventoryFork, .inventoryList,
      .inventoryShow, .inventoryInterface, .inventoryConfigure, .inventoryDelete,
      .inventorySecretSet, .inventorySecretClear, .inventoryCapabilityList,
      .inventoryCapabilityGrant, .inventoryCapabilityRevoke, .inventoryActionList,
      .inventoryActionRun, .inventoryViewList, .inventoryViewShow, .inventoryDeploy,
      .inventoryCopiesList, .inventoryCopiesShow, .inventoryCopiesDelete,
      .inventoryListenEnable, .inventoryListenDisable, .inventoryListenList,
      .inventoryReportsList, .inventoryReportsShow, .inventoryReportsFollow,
      .inventoryRestockCreate, .inventoryRestockList, .inventoryRestockShow,
      .inventoryRestockSet, .inventoryRestockRun, .inventoryRestockDelete:
      .inventory
    case .worldTemplateList, .worldTemplateShow, .worldTemplateStatus, .worldTemplateApply:
      .templates
    case .libraryFetch, .libraryList, .worldList, .worldUse, .worldCreate, .worldRename,
      .worldDelete, .worldShow, .worldInspect, .worldExport, .worldObjectList,
      .worldObjectShow, .worldObjectInterface, .worldObjectActionList,
      .worldObjectActionRun, .worldObjectViewList, .worldObjectViewShow,
      .worldObjectMove:
      .world
    }
  }

  private static func section(for kind: CommandKind) -> String {
    switch kind {
    case .help: "Reference"
    case .web: "Host"
    case .initialize, .status: "Setup"
    case .doctor: "Diagnostics"
    case .configShow, .configPath, .configKeys, .configGet, .configSet, .configReset,
      .configValidate:
      "Configuration"
    case .adapters: "Adapters"
    case .agentCreate, .agentList, .agentShow: "Identities"
    case .agentConfigure: "Preferences"
    case .agentAdd, .agentRemove, .agentRetry: "Presence"
    case .agentProfileSet, .agentProfileClear: "Profiles"
    case .agentShell: "Controller"
    case .libraryFetch, .libraryList: "Library"
    case .inventoryInstall, .inventoryPackageAvailable, .inventoryPackageList,
      .inventoryPackageShow, .inventoryPackageRemove:
      "Package catalog"
    case .inventoryCreate, .inventoryMove, .inventoryFork, .inventoryList,
      .inventoryShow, .inventoryInterface, .inventoryDelete:
      "Sources"
    case .inventoryFolderCreate, .inventoryFolderList, .inventoryFolderShow,
      .inventoryFolderRename, .inventoryFolderMove, .inventoryFolderDelete:
      "Folders"
    case .inventoryConfigure: "Configuration"
    case .inventorySecretSet, .inventorySecretClear: "Credentials"
    case .inventoryCapabilityList, .inventoryCapabilityGrant,
      .inventoryCapabilityRevoke:
      "Capabilities"
    case .inventoryActionList, .inventoryActionRun: "Actions"
    case .inventoryViewList, .inventoryViewShow: "Views"
    case .inventoryDeploy, .inventoryCopiesList, .inventoryCopiesShow,
      .inventoryCopiesDelete:
      "Deployments and copies"
    case .inventoryListenEnable, .inventoryListenDisable, .inventoryListenList:
      "Listeners"
    case .inventoryReportsList, .inventoryReportsShow, .inventoryReportsFollow:
      "Reports"
    case .inventoryRestockCreate, .inventoryRestockList, .inventoryRestockShow,
      .inventoryRestockSet, .inventoryRestockRun, .inventoryRestockDelete:
      "Restocking"
    case .worldTemplateList, .worldTemplateShow: "Template catalog"
    case .worldTemplateStatus, .worldTemplateApply: "World application"
    case .worldList, .worldUse, .worldCreate, .worldRename, .worldDelete: "World catalog"
    case .worldShow, .worldInspect, .worldExport: "State and journal"
    case .worldObjectList, .worldObjectShow, .worldObjectInterface,
      .worldObjectActionList, .worldObjectActionRun, .worldObjectViewList,
      .worldObjectViewShow, .worldObjectMove:
      "Objects"
    }
  }

  private static func scope(for kind: CommandKind) -> WebCapabilityScope {
    switch kind {
    case .agentAdd, .libraryFetch, .libraryList, .inventoryFork, .inventoryViewShow,
      .inventoryDeploy,
      .inventoryCopiesList, .inventoryCopiesShow, .inventoryCopiesDelete,
      .inventoryListenEnable, .inventoryListenDisable, .inventoryListenList,
      .inventoryReportsList, .inventoryReportsShow, .inventoryReportsFollow,
      .inventoryRestockCreate, .inventoryRestockList, .inventoryRestockShow,
      .inventoryRestockSet, .inventoryRestockRun, .inventoryRestockDelete,
      .worldTemplateStatus, .worldTemplateApply:
      .explicitWorld
    case .agentRemove, .agentRetry, .agentShell:
      .assignmentDerived
    case .worldShow, .worldInspect, .worldExport, .worldObjectList, .worldObjectShow,
      .worldObjectInterface, .worldObjectActionList, .worldObjectActionRun,
      .worldObjectViewList, .worldObjectViewShow, .worldObjectMove:
      .selectedWorld
    case .help, .web, .initialize, .status, .doctor, .configShow, .configPath,
      .configKeys, .configGet, .configSet, .configReset, .configValidate, .adapters,
      .agentCreate, .agentList, .agentShow, .agentConfigure, .agentProfileSet,
      .agentProfileClear, .inventoryInstall, .inventoryPackageAvailable,
      .inventoryPackageList, .inventoryPackageShow, .inventoryPackageRemove,
      .inventoryCreate, .inventoryFolderCreate, .inventoryFolderList,
      .inventoryFolderShow, .inventoryFolderRename, .inventoryFolderMove,
      .inventoryFolderDelete, .inventoryMove, .inventoryList, .inventoryShow,
      .inventoryInterface, .inventoryConfigure, .inventoryDelete,
      .inventorySecretSet, .inventorySecretClear, .inventoryCapabilityList,
      .inventoryCapabilityGrant, .inventoryCapabilityRevoke, .inventoryActionList,
      .inventoryActionRun, .inventoryViewList, .worldList,
      .worldUse, .worldCreate, .worldRename, .worldDelete, .worldTemplateList,
      .worldTemplateShow:
      .global
    }
  }

  private static func interaction(
    for definition: CommandDefinition
  ) -> WebCapabilityInteractionMode {
    switch definition.kind {
    case .help: .help
    case .web: .hostStatus
    case .inventorySecretSet: .secret
    case .agentShell: .agentController
    case .inventoryReportsFollow: .reportStream
    case .worldInspect: .privateViewer
    case .worldExport: .download
    default:
      if definition.mayRequestForegroundInput {
        .confirmation
      } else if isReadOnly(definition.kind) {
        .projection
      } else {
        .form
      }
    }
  }

  private static func isReadOnly(_ kind: CommandKind) -> Bool {
    switch kind {
    case .help, .web, .status, .doctor, .configShow, .configPath, .configKeys,
      .configGet, .configValidate, .adapters, .agentList, .agentShow, .libraryList,
      .inventoryPackageAvailable, .inventoryPackageList, .inventoryPackageShow,
      .inventoryFolderList, .inventoryFolderShow, .inventoryList, .inventoryShow,
      .inventoryInterface, .inventoryCapabilityList, .inventoryActionList,
      .inventoryViewList, .inventoryViewShow, .inventoryCopiesList,
      .inventoryCopiesShow, .inventoryListenList, .inventoryReportsList,
      .inventoryReportsShow, .inventoryReportsFollow, .inventoryRestockList,
      .inventoryRestockShow, .worldList, .worldTemplateList, .worldTemplateShow,
      .worldTemplateStatus, .worldShow, .worldInspect, .worldExport,
      .worldObjectList, .worldObjectShow, .worldObjectInterface,
      .worldObjectActionList, .worldObjectViewList, .worldObjectViewShow:
      true
    case .initialize, .configSet, .configReset, .agentCreate, .agentConfigure,
      .agentAdd, .agentRemove, .agentProfileSet, .agentProfileClear, .agentRetry,
      .agentShell, .libraryFetch, .inventoryInstall, .inventoryPackageRemove,
      .inventoryCreate, .inventoryFolderCreate, .inventoryFolderRename,
      .inventoryFolderMove, .inventoryFolderDelete, .inventoryMove, .inventoryFork,
      .inventoryConfigure, .inventoryDelete, .inventorySecretSet,
      .inventorySecretClear, .inventoryCapabilityGrant, .inventoryCapabilityRevoke,
      .inventoryActionRun, .inventoryDeploy, .inventoryCopiesDelete,
      .inventoryListenEnable, .inventoryListenDisable, .inventoryRestockCreate,
      .inventoryRestockSet, .inventoryRestockRun, .inventoryRestockDelete,
      .worldUse, .worldCreate, .worldRename, .worldDelete, .worldTemplateApply,
      .worldObjectActionRun, .worldObjectMove:
      false
    }
  }

  private static func refreshTarget(
    for view: WebView
  ) -> WebCapabilityRefreshTarget {
    switch view {
    case .world: .world
    case .agentManager: .agents
    case .inventory: .inventory
    case .packages: .packages
    case .templates: .templates
    case .settings: .settings
    case .help: .none
    }
  }

  private static func testID(_ definition: CommandDefinition) -> String {
    definition.path.joined(separator: "-")
  }
}

public final class CLIWebCapabilityGateway: WebCapabilityServing,
  @unchecked Sendable
{
  public static let maximumOutputBytes = 256 * 1_024
  public static let maximumFieldCharacters = 16_384
  public static let maximumFieldValues = 64
  public static let maximumCompletionSourceCharacters = 1_024
  public static let maximumSecretBytes = 16 * 1_024
  public static let maximumPendingPlans = 128
  public static let maximumConsumedPlanMarkers = 256
  public static let maximumConcurrentReportStreams = 8
  public static let planLifetime: TimeInterval = 90

  private struct ValidatedRequest {
    let definition: CommandDefinition
    let descriptor: WebCapabilityDescriptor
    let fields: [String: [String]]
    let exactWorldID: String?
    let secret: Data?
  }

  private struct StoredPlan {
    let sessionID: String
    let expiresAt: Date
    let request: ValidatedRequest
    let stateFingerprint: String
  }

  private let stateLock = NSLock()
  private var executionInFlight = false
  private var plans: [String: StoredPlan] = [:]
  private var consumedPlans: [String: Date] = [:]
  private var activeReportStreams = 0
  private let testBeforeExecution: (@Sendable () async -> Void)?

  public init() {
    testBeforeExecution = nil
  }

  init(testBeforeExecution: @escaping @Sendable () async -> Void) {
    self.testBeforeExecution = testBeforeExecution
  }

  public func descriptors(
    in _: WebCapabilityContext
  ) throws -> [WebCapabilityDescriptor] {
    CLIWebCapabilityRegistry.descriptors()
  }

  public func completions(
    for request: WebCapabilityCompletionRequest,
    in context: WebCapabilityContext
  ) async throws -> [WebCapabilityCompletionValue] {
    guard request.source.count <= Self.maximumCompletionSourceCharacters,
      let definition = CLIWebCapabilityRegistry.definition(id: request.capabilityID),
      let field = definition.fields.first(where: { $0.id == request.fieldID })
    else { throw WebCapabilityError.invalidField(request.fieldID) }
    if field.completion == .filesystemPath { return [] }
    let configuration = try ConfigurationStore.load(from: context.layout.configurationURL)
    let worldID = try resolvedWorldID(
      request.exactWorldID,
      fields: request.fields,
      definition: definition,
      context: context,
      required: false
    )
    if field.completion == .worldID {
      return try exactWorldCompletionValues(context: context, configuration: configuration)
        .filter {
          request.source.isEmpty || $0.label.localizedCaseInsensitiveContains(request.source)
            || $0.value.hasPrefix(request.source.lowercased())
        }
        .prefix(configuration.console.maximumSuggestions)
        .map { $0 }
    }
    let globals = CommandGlobalOptions(
      configurationPath: context.layout.configurationURL.path,
      worldID: worldID,
      outputMode: .human,
      colorMode: .never
    )
    return MikroKhorosPathContext.$canonicalRootOverride.withValue(
      context.layout.canonicalRoot
    ) {
      CompletionResolver.values(
        for: field.completion,
        globals: globals,
        configuration: configuration,
        source: request.source
      )
      .filter {
        request.source.isEmpty || $0.localizedCaseInsensitiveContains(request.source)
      }
      .prefix(configuration.console.maximumSuggestions)
      .map { WebCapabilityCompletionValue(value: $0) }
    }
  }

  public func execute(
    _ request: WebCapabilityRequest,
    in context: WebCapabilityContext
  ) async throws -> WebCapabilityExecutionResult {
    guard beginExecution() else { throw WebCapabilityError.busy }
    defer { finishExecution() }
    await waitForTestExecutionReservation()
    let validated = try validate(request, context: context)
    try validateBrowserManagementPathInputs(validated, context: context)
    switch validated.descriptor.interaction {
    case .confirmation, .reportStream:
      throw WebCapabilityError.wrongInteraction
    case .secret:
      guard validated.secret?.isEmpty == false else {
        throw WebCapabilityError.secretRequired
      }
    case .agentController:
      guard validated.fields["action"]?.isEmpty == false else {
        throw WebCapabilityError.missingField("action")
      }
    case .hostStatus:
      return hostStatusResult(validated, context: context)
    case .projection, .form, .download, .privateViewer, .help:
      break
    }
    return await executeValidated(validated, context: context)
  }

  public func prepare(
    _ request: WebCapabilityRequest,
    in context: WebCapabilityContext
  ) async throws -> WebCapabilityPlan {
    let (validated, stateFingerprint) = try withLockedProductState(context: context) {
      let validated = try validate(request, context: context)
      guard validated.descriptor.interaction == .confirmation else {
        throw WebCapabilityError.wrongInteraction
      }
      guard validated.secret == nil else { throw WebCapabilityError.secretNotAllowed }
      return (validated, try WebProductStateFingerprint.capture(layout: context.layout))
    }
    let planID = randomIdentity()
    let expiresAt = Date().addingTimeInterval(Self.planLifetime)
    try stateLock.withLock {
      let now = Date()
      plans = plans.filter { $0.value.expiresAt >= now }
      guard plans.count < Self.maximumPendingPlans else {
        throw WebCapabilityError.busy
      }
      plans[planID] = StoredPlan(
        sessionID: context.sessionID,
        expiresAt: expiresAt,
        request: validated,
        stateFingerprint: stateFingerprint
      )
    }
    return WebCapabilityPlan(
      planID: planID,
      capabilityID: validated.descriptor.id,
      expiresAt: expiresAt,
      commandSummary: displayCommand(validated),
      consequenceSummary: consequenceSummary(validated)
    )
  }

  public func commit(
    _ request: WebCapabilityCommitRequest,
    in context: WebCapabilityContext
  ) async throws -> WebCapabilityExecutionResult {
    guard request.sessionID == context.sessionID else {
      throw WebCapabilityError.invalidSession
    }
    let stored = try reserveExecutionAndConsumePlan(request, sessionID: context.sessionID)
    defer { finishExecution() }
    await waitForTestExecutionReservation()
    guard stored.expiresAt >= Date() else { throw WebCapabilityError.expiredPlan }
    guard try productStateFingerprint(context: context) == stored.stateFingerprint else {
      throw WebCapabilityError.tamperedPlan
    }
    var fields = stored.request.fields
    if stored.request.definition.fields.contains(where: { $0.id == "yes" }) {
      fields["yes"] = ["true"]
    }
    let committed = ValidatedRequest(
      definition: stored.request.definition,
      descriptor: stored.request.descriptor,
      fields: fields,
      exactWorldID: stored.request.exactWorldID,
      secret: nil
    )
    try validateBrowserManagementPathInputs(committed, context: context)
    return await executeValidated(
      committed,
      context: context,
      expectedProductStateFingerprint: stored.stateFingerprint
    )
  }

  public func reportStream(
    _ request: WebCapabilityRequest,
    in context: WebCapabilityContext
  ) async throws -> AsyncThrowingStream<String, Error> {
    let validated = try validate(request, context: context)
    guard validated.descriptor.interaction == .reportStream else {
      throw WebCapabilityError.wrongInteraction
    }
    guard let listDefinition = CommandCatalog.all.first(where: { $0.kind == .inventoryReportsList })
    else { throw WebCapabilityError.unavailable }
    guard beginReportStream() else { throw WebCapabilityError.busy }
    let listDescriptor = CLIWebCapabilityRegistry.descriptor(for: listDefinition)
    let listRequest = ValidatedRequest(
      definition: listDefinition,
      descriptor: listDescriptor,
      fields: validated.fields,
      exactWorldID: validated.exactWorldID,
      secret: nil
    )
    return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task { [self] in
        defer { finishReportStream() }
        var previous: String?
        do {
          while !Task.isCancelled {
            guard self.beginExecution() else {
              try await Task.sleep(for: .milliseconds(200))
              continue
            }
            let result = await self.executeValidated(listRequest, context: context)
            self.finishExecution()
            guard result.accepted else {
              throw WebCapabilityError.unavailable
            }
            let snapshot = result.standardOutput
            if snapshot != previous {
              continuation.yield((previous == nil ? "" : "\n--- reports updated ---\n") + snapshot)
              previous = snapshot
            }
            try await Task.sleep(for: .milliseconds(500))
          }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { @Sendable _ in task.cancel() }
    }
  }

  private func validate(
    _ request: WebCapabilityRequest,
    context: WebCapabilityContext
  ) throws -> ValidatedRequest {
    guard request.sessionID == nil || request.sessionID == context.sessionID else {
      throw WebCapabilityError.invalidSession
    }
    guard let definition = CLIWebCapabilityRegistry.definition(id: request.capabilityID)
    else { throw WebCapabilityError.unknownCapability }
    let descriptor = CLIWebCapabilityRegistry.descriptor(for: definition)
    guard descriptor.enabled else { throw WebCapabilityError.unavailable }
    if definition.kind == .web, !request.fields.isEmpty {
      throw WebCapabilityError.invalidField("unknown")
    }
    if let requestedInteraction = request.interaction {
      guard requestedInteraction == descriptor.interaction else {
        throw WebCapabilityError.wrongInteraction
      }
    }
    let known = Dictionary(uniqueKeysWithValues: definition.fields.map { ($0.id, $0) })
    if definition.kind == .inventorySecretSet,
      request.fields.keys.contains(where: { ["stdin", "from-env"].contains($0) })
    {
      throw WebCapabilityError.globalOptionsRejected
    }
    if descriptor.interaction == .confirmation, request.fields["yes"] != nil {
      throw WebCapabilityError.globalOptionsRejected
    }
    guard request.fields.count <= definition.fields.count else {
      throw WebCapabilityError.invalidField("unknown")
    }
    for key in request.fields.keys where known[key] == nil {
      throw WebCapabilityError.invalidField(key)
    }
    var normalized: [String: [String]] = [:]
    for field in definition.fields {
      let values = request.fields[field.id] ?? []
      guard values.count <= Self.maximumFieldValues else {
        throw WebCapabilityError.invalidValue(field.id)
      }
      if field.cardinality != .repeated, values.count > 1 {
        throw WebCapabilityError.duplicateField(field.id)
      }
      let cleaned = try values.map { value -> String in
        guard value.count <= Self.maximumFieldCharacters,
          !value.contains("\0"),
          !containsReservedGlobalOption(value)
        else { throw WebCapabilityError.invalidValue(field.id) }
        return value
      }.filter { !$0.isEmpty }
      if field.cardinality == .required, cleaned.isEmpty {
        throw WebCapabilityError.missingField(field.id)
      }
      if case .choices(let choices) = field.completion,
        !cleaned.allSatisfy(choices.contains)
      {
        throw WebCapabilityError.invalidValue(field.id)
      }
      if case .flag = field.syntax,
        !cleaned.allSatisfy({ ["true", "false", "yes", "no", "1", "0"].contains($0.lowercased()) })
      {
        throw WebCapabilityError.invalidValue(field.id)
      }
      if !cleaned.isEmpty { normalized[field.id] = cleaned }
    }
    if definition.kind == .inventoryInstall,
      let source = normalized["path-or-url"]?.last
    {
      guard Self.isBrowserSafePackageInstallSource(source) else {
        throw WebCapabilityError.invalidValue("path-or-url")
      }
    }
    if definition.kind == .inventorySecretSet { normalized["stdin"] = ["true"] }
    let requiredWorld = descriptor.scope == .selectedWorld || descriptor.scope == .explicitWorld
    let worldID = try resolvedWorldID(
      request.exactWorldID,
      fields: normalized,
      definition: definition,
      context: context,
      required: requiredWorld
    )
    if descriptor.scope == .global, request.exactWorldID != nil {
      throw WebCapabilityError.invalidWorldContext
    }
    if descriptor.interaction != .secret, request.secret != nil {
      throw WebCapabilityError.secretNotAllowed
    }
    if let secret = request.secret, secret.count > Self.maximumSecretBytes {
      throw WebCapabilityError.invalidValue("credential-value")
    }
    return ValidatedRequest(
      definition: definition,
      descriptor: descriptor,
      fields: normalized,
      exactWorldID: worldID,
      secret: request.secret
    )
  }

  /// The browser can render a generic management contract but has no authority
  /// to supply, clear, or implicitly execute against host filesystem paths.
  /// Resolve only the bounded safe contract before allowing management input
  /// through to the CLI.
  private func validateBrowserManagementPathInputs(
    _ request: ValidatedRequest,
    context: WebCapabilityContext
  ) throws {
    switch request.definition.kind {
    case .inventoryConfigure:
      guard let sourceID = request.fields["inventory-id"]?.last else { return }
      let contract = try inventoryManagementContract(sourceID: sourceID, context: context)
      let pathFieldIDs = Set(contract.fields.lazy.filter { $0.kind == "path" }.map(\.id))
      try rejectBrowserPathAssignments(
        request.fields["set"] ?? [],
        pathFieldIDs: pathFieldIDs,
        fieldID: "set"
      )
      try rejectBrowserPathFieldNames(
        request.fields["unset"] ?? [],
        pathFieldIDs: pathFieldIDs,
        fieldID: "unset"
      )
    case .inventoryActionRun:
      guard let sourceID = request.fields["inventory-id"]?.last,
        let actionID = request.fields["action"]?.last
      else { return }
      let contract = try inventoryManagementContract(sourceID: sourceID, context: context)
      try rejectBrowserUnsafeManagementContract(contract, fieldID: "action")
      guard contract.actions.contains(where: { $0.id == actionID }) else { return }
    case .worldObjectActionRun:
      guard let worldID = request.exactWorldID,
        let objectID = request.fields["world-object-id"]?.last,
        let actionID = request.fields["action"]?.last
      else { return }
      let contract = try worldManagementContract(
        worldID: worldID,
        objectID: objectID,
        context: context
      )
      try rejectBrowserUnsafeManagementContract(contract, fieldID: "action")
      guard contract.actions.contains(where: { $0.id == actionID }) else { return }
    case .inventoryViewShow:
      guard let sourceID = request.fields["inventory-id"]?.last,
        let viewID = request.fields["view"]?.last
      else { return }
      let contract = try inventoryManagementContract(sourceID: sourceID, context: context)
      try rejectBrowserUnsafeManagementContract(contract, fieldID: "view")
      try rejectBrowserConfigurationView(
        contract.views.first(where: { $0.id == viewID }),
        fieldID: "view"
      )
    case .worldObjectViewShow:
      guard let worldID = request.exactWorldID,
        let objectID = request.fields["world-object-id"]?.last,
        let viewID = request.fields["view"]?.last
      else { return }
      let contract = try worldManagementContract(
        worldID: worldID,
        objectID: objectID,
        context: context
      )
      try rejectBrowserUnsafeManagementContract(contract, fieldID: "view")
      try rejectBrowserConfigurationView(
        contract.views.first(where: { $0.id == viewID }),
        fieldID: "view"
      )
    default:
      return
    }
  }

  private func inventoryManagementContract(
    sourceID: String,
    context: WebCapabilityContext
  ) throws -> NativeManagementContract {
    let snapshot = try WebProjectionService(layout: context.layout).inventory()
    guard let source = snapshot.sources.first(where: { $0.id == sourceID }) else {
      throw WebCapabilityError.unavailable
    }
    return source.management
  }

  private func worldManagementContract(
    worldID: String,
    objectID: String,
    context: WebCapabilityContext
  ) throws -> NativeManagementContract {
    let snapshot = try WorldProjectionService(layout: context.layout).objectSnapshot(
      world: worldID,
      object: objectID
    )
    guard let interface = snapshot.interface,
      case .object(let wrapper) = interface,
      let contract = wrapper["object"]
    else { throw WebCapabilityError.unavailable }
    let data = try JSONEncoder().encode(contract)
    do {
      return try JSONDecoder().decode(NativeManagementContract.self, from: data)
    } catch {
      throw WebCapabilityError.unavailable
    }
  }

  private func rejectBrowserPathAssignments(
    _ assignments: [String],
    pathFieldIDs: Set<String>,
    fieldID: String
  ) throws {
    for assignment in assignments {
      guard let separator = assignment.firstIndex(of: "="), separator != assignment.startIndex
      else { continue }
      let name = String(assignment[..<separator])
      if pathFieldIDs.contains(name) {
        throw WebCapabilityError.invalidValue(fieldID)
      }
    }
  }

  private func rejectBrowserPathFieldNames(
    _ fieldNames: [String],
    pathFieldIDs: Set<String>,
    fieldID: String
  ) throws {
    guard !fieldNames.contains(where: pathFieldIDs.contains) else {
      throw WebCapabilityError.invalidValue(fieldID)
    }
  }

  /// A browser must not invoke a management contract that has a path-bearing
  /// field or action, even when it omits that input. The command runtime could
  /// otherwise fill an unsafe package-declared default after gateway validation.
  private func rejectBrowserUnsafeManagementContract(
    _ contract: NativeManagementContract,
    fieldID: String
  ) throws {
    let hasPathField = contract.fields.contains { $0.kind == "path" }
    let hasPathActionInput = contract.actions.contains { action in
      action.inputTypes.values.contains("path")
    }
    guard !hasPathField, !hasPathActionInput else {
      throw WebCapabilityError.invalidValue(fieldID)
    }
  }

  private func rejectBrowserConfigurationView(
    _ view: NativeManagementView?,
    fieldID: String
  ) throws {
    guard view?.source != "configuration" else {
      throw WebCapabilityError.invalidValue(fieldID)
    }
  }

  private func containsReservedGlobalOption(_ value: String) -> Bool {
    let option =
      value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      .first.map(String.init) ?? value
    return ["--config", "--world", "--output", "--color", "--workspace"].contains(option)
  }

  /// Browser package installation accepts only package locations that stay
  /// within the browser's mediation boundary. Built-in names are resolved
  /// through the fixed first-party catalog; remote packages require an
  /// absolute HTTPS URL without credentials embedded in its authority.
  static func isBrowserSafePackageInstallSource(_ source: String) -> Bool {
    (try? ObjectPackageAcquisitionPolicy.browser.validate(source: source)) != nil
  }

  private func resolvedWorldID(
    _ supplied: String?,
    fields: [String: [String]],
    definition: CommandDefinition,
    context: WebCapabilityContext,
    required: Bool
  ) throws -> String? {
    if let supplied, let fieldWorld = fields["world"]?.last, supplied != fieldWorld {
      throw WebCapabilityError.invalidWorldContext
    }
    let candidate = supplied ?? fields["world"]?.last
    guard let candidate else {
      if required { throw WebCapabilityError.invalidWorldContext }
      return nil
    }
    guard InventoryIdentity.isValid(candidate), candidate == candidate.lowercased() else {
      throw WebCapabilityError.invalidWorldContext
    }
    let configuration = try ConfigurationStore.load(from: context.layout.configurationURL)
    let catalog = try WorldCatalogStore(
      url: context.layout.catalogURL,
      maximumBytes: configuration.runtime.maximumWorldBytes
    )
    guard catalog.document.worlds.contains(where: { $0.id == candidate }) else {
      throw WebCapabilityError.invalidWorldContext
    }
    _ = definition
    return candidate
  }

  private func executeValidated(
    _ request: ValidatedRequest,
    context: WebCapabilityContext,
    expectedProductStateFingerprint: String? = nil
  ) async -> WebCapabilityExecutionResult {
    let globals = CommandGlobalOptions(
      configurationPath: context.layout.configurationURL.path,
      worldID: request.exactWorldID,
      outputMode: .human,
      colorMode: .never
    )
    let submission = InteractiveCommandSubmission(
      commandPath: request.definition.command,
      values: request.fields,
      explicitFieldIDs: Set(request.fields.keys),
      globals: globals,
      stopsQueueOnError: false
    )
    let arguments: [String]
    do {
      arguments = try CommandParser.arguments(for: submission)
    } catch {
      return rejectedResult(request, message: "The operation fields are invalid.")
    }
    let transcript = await ObjectPackageAcquisitionContext.$policy.withValue(.browser) {
      await WebPresentationContext.$isActive.withValue(true) {
        await CommandExecutor.executeTranscript(
          arguments: arguments,
          layout: context.layout,
          maximumOutputBytes: Self.maximumOutputBytes,
          standardInput: request.secret ?? Data(),
          expectedProductStateFingerprint: expectedProductStateFingerprint
        )
      }
    }
    let bounded = Self.boundedBrowserOutput(
      stdout: browserSafeTranscript(transcript.standardOutput, context: context),
      stderr: browserSafeTranscript(transcript.standardError, context: context),
      maximumBytes: Self.maximumOutputBytes
    )
    return WebCapabilityExecutionResult(
      accepted: transcript.exitStatus == 0,
      displayCommand: displayCommand(request),
      standardOutput: bounded.stdout,
      standardError: bounded.stderr,
      exitStatus: transcript.exitStatus,
      outputTruncated: transcript.outputTruncated || bounded.truncated,
      refreshTargets: transcript.exitStatus == 0 ? request.descriptor.refreshTargets : [.none],
      category: transcript.exitStatus == 0 ? .success : .failure
    )
  }

  /// Replaces host-owned product locations before command presentation reaches
  /// the browser. Command execution still receives the exact layout out of band;
  /// the browser needs only a stable indication that a local file is selected.
  private func browserSafeTranscript(
    _ value: String,
    context: WebCapabilityContext
  ) -> String {
    let rootPath = context.layout.canonicalRoot.standardizedFileURL.path
    let configurationPath = context.layout.configurationURL.standardizedFileURL.path
    let replacements = [
      (configurationPath, "[configuration file]"),
      (rootPath, "[product root]"),
    ]
    .filter { !$0.0.isEmpty }
    .sorted { $0.0.count > $1.0.count }
    return replacements.reduce(value) { result, replacement in
      result.replacingOccurrences(of: replacement.0, with: replacement.1)
    }
  }

  static func boundedBrowserOutput(
    stdout: String,
    stderr: String,
    maximumBytes: Int
  ) -> (stdout: String, stderr: String, truncated: Bool) {
    guard maximumBytes > 0 else { return ("", "", !stdout.isEmpty || !stderr.isEmpty) }
    let output = Data(stdout.utf8)
    let error = Data(stderr.utf8)
    let half = maximumBytes / 2
    var outputLimit = min(output.count, half)
    var errorLimit = min(error.count, half)
    var remaining = maximumBytes - outputLimit - errorLimit
    let extraOutput = min(max(0, output.count - outputLimit), remaining)
    outputLimit += extraOutput
    remaining -= extraOutput
    errorLimit += min(max(0, error.count - errorLimit), remaining)
    return (
      validUTF8Prefix(output, maximumBytes: outputLimit),
      validUTF8Prefix(error, maximumBytes: errorLimit),
      output.count > outputLimit || error.count > errorLimit
    )
  }

  private static func validUTF8Prefix(_ data: Data, maximumBytes: Int) -> String {
    var count = min(data.count, maximumBytes)
    while count > 0 {
      if let value = String(data: data.prefix(count), encoding: .utf8) { return value }
      count -= 1
    }
    return ""
  }

  private func hostStatusResult(
    _ request: ValidatedRequest,
    context: WebCapabilityContext
  ) -> WebCapabilityExecutionResult {
    let address = context.hostState.address ?? "127.0.0.1"
    let port = context.hostState.port.map(String.init) ?? "assigned at launch"
    return WebCapabilityExecutionResult(
      accepted: true,
      displayCommand: "khoros web",
      standardOutput:
        "host:\n  lifecycle: \(context.hostState.lifecycle.rawValue)\n  address: \(address)\n  port: \(port)\n",
      exitStatus: 0,
      refreshTargets: [.none],
      category: .success
    )
  }

  private func rejectedResult(
    _ request: ValidatedRequest,
    message: String
  ) -> WebCapabilityExecutionResult {
    WebCapabilityExecutionResult(
      accepted: false,
      displayCommand: displayCommand(request),
      standardError: "error:\n  code: web.request_invalid\n  message: \(message)\n",
      exitStatus: 2,
      refreshTargets: [.none],
      category: .rejected
    )
  }

  private func displayCommand(_ request: ValidatedRequest) -> String {
    let safeIDs = Set(
      request.definition.fields.filter { $0.historyPolicy == .store }.map(\.id)
    )
    let safeValues = request.fields.filter { safeIDs.contains($0.key) }
    let submission = InteractiveCommandSubmission(
      commandPath: request.definition.command,
      values: safeValues,
      explicitFieldIDs: Set(safeValues.keys),
      globals: CommandGlobalOptions(
        worldID: request.definition.fields.contains(where: { $0.id == "world" })
          ? nil : request.exactWorldID
      ),
      stopsQueueOnError: false
    )
    let arguments =
      (try? CommandParser.arguments(for: submission))
      ?? request.definition.path
    return (["khoros"] + arguments).map(inertDisplayToken).joined(separator: " ")
  }

  private func consequenceSummary(_ request: ValidatedRequest) -> String {
    let target = request.exactWorldID.map { " in World \($0)" } ?? ""
    return
      "Run \(request.definition.summary.trimmingCharacters(in: .whitespacesAndNewlines))\(target)"
  }

  private func exactWorldCompletionValues(
    context: WebCapabilityContext,
    configuration: RuntimeConfiguration
  ) throws -> [WebCapabilityCompletionValue] {
    let catalog = try WorldCatalogStore(
      url: context.layout.catalogURL,
      maximumBytes: configuration.runtime.maximumWorldBytes
    )
    return catalog.document.worlds.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    .map { WebCapabilityCompletionValue(value: $0.id, label: $0.name) }
  }

  private func beginExecution() -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    guard !executionInFlight else { return false }
    executionInFlight = true
    return true
  }

  private func finishExecution() {
    stateLock.lock()
    executionInFlight = false
    stateLock.unlock()
  }

  /// Atomically reserves the single-flight slot before making a confirmation
  /// plan single-use. A busy request therefore leaves its plan retryable.
  private func reserveExecutionAndConsumePlan(
    _ request: WebCapabilityCommitRequest,
    sessionID: String
  ) throws -> StoredPlan {
    try stateLock.withLock {
      let now = Date()
      consumedPlans = consumedPlans.filter { $0.value >= now }
      guard let candidate = plans[request.planID] else {
        if consumedPlans[request.planID] != nil {
          throw WebCapabilityError.replayedPlan
        }
        throw WebCapabilityError.invalidPlan
      }
      guard candidate.sessionID == sessionID else {
        throw WebCapabilityError.invalidSession
      }
      guard !executionInFlight else { throw WebCapabilityError.busy }
      executionInFlight = true
      plans.removeValue(forKey: request.planID)
      consumedPlans[request.planID] = candidate.expiresAt
      trimConsumedPlansIfNeeded()
      return candidate
    }
  }

  private func waitForTestExecutionReservation() async {
    await testBeforeExecution?()
  }

  private func beginReportStream() -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    guard activeReportStreams < Self.maximumConcurrentReportStreams else { return false }
    activeReportStreams += 1
    return true
  }

  private func finishReportStream() {
    stateLock.lock()
    activeReportStreams = max(0, activeReportStreams - 1)
    stateLock.unlock()
  }

  private func trimConsumedPlansIfNeeded() {
    guard consumedPlans.count > Self.maximumConsumedPlanMarkers else { return }
    for key in consumedPlans.sorted(by: { $0.value < $1.value })
      .prefix(consumedPlans.count - Self.maximumConsumedPlanMarkers)
      .map(\.key)
    {
      consumedPlans.removeValue(forKey: key)
    }
  }

  private func productStateFingerprint(
    context: WebCapabilityContext
  ) throws -> String {
    try withLockedProductState(context: context) {
      try WebProductStateFingerprint.capture(layout: context.layout)
    }
  }

  private func withLockedProductState<Value>(
    context: WebCapabilityContext,
    _ body: () throws -> Value
  ) throws -> Value {
    let productLock = try ProductStateLock(root: context.layout.canonicalRoot)
    defer { withExtendedLifetime(productLock) {} }
    return try MikroKhorosPathContext.$canonicalRootOverride.withValue(
      context.layout.canonicalRoot
    ) {
      try ProductStateTransaction.recoverPending()
      return try body()
    }
  }

  private func randomIdentity() -> String {
    var generator = SystemRandomNumberGenerator()
    return (0..<16).map { _ in
      String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator))
    }
    .joined()
  }

  private func inertDisplayToken(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._/:@+="))
    guard !value.isEmpty,
      value.unicodeScalars.allSatisfy(allowed.contains)
    else { return "value_omitted" }
    return value
  }
}

/// Task-local optimistic precondition checked again after the command runtime
/// acquires the canonical product lock. This closes the prepare/commit race
/// without exposing the fingerprint or product paths to the browser.
enum WebProductStateContext {
  @TaskLocal static var expectedFingerprint: String?
}

enum WebProductStateFingerprint {
  static func capture(layout: ProductLayout) throws -> String {
    var hasher = SHA256()
    var visited = Set<String>()
    let roots = [
      layout.configurationURL,
      layout.catalogURL,
      layout.agentURL,
      layout.inventoryURL,
      layout.treasuryURL,
      layout.worldsDirectoryURL,
      layout.packagesDirectoryURL,
      layout.credentialsDirectoryURL,
    ]
    for (index, root) in roots.enumerated() {
      try update(
        root,
        logicalPath: "root-\(index)",
        hasher: &hasher,
        visited: &visited
      )
    }
    return Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()
  }

  static func validateExpected(layout: ProductLayout) throws {
    guard let expected = WebProductStateContext.expectedFingerprint else { return }
    guard try capture(layout: layout) == expected else {
      throw MikroKhorosError.runtime(
        "web.plan_changed",
        "persistent product state changed after the action was prepared"
      )
    }
  }

  private static func update(
    _ url: URL,
    logicalPath: String,
    hasher: inout SHA256,
    visited: inout Set<String>
  ) throws {
    let standardized = url.standardizedFileURL
    guard visited.insert(standardized.path).inserted else { return }
    hasher.update(data: Data("\(logicalPath)\u{0}".utf8))
    let values = try? standardized.resourceValues(forKeys: [
      .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
    ])
    if values == nil {
      hasher.update(data: Data("missing\u{0}".utf8))
      return
    }
    if values?.isSymbolicLink == true {
      let destination =
        (try? FileManager.default.destinationOfSymbolicLink(atPath: standardized.path))
        ?? "unreadable"
      hasher.update(data: Data("symlink\u{0}\(destination)\u{0}".utf8))
      return
    }
    if values?.isDirectory == true {
      hasher.update(data: Data("directory\u{0}".utf8))
      let children = try FileManager.default.contentsOfDirectory(
        at: standardized,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
        options: []
      )
      for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let name = child.lastPathComponent
        if name == "command.lock" || name.hasSuffix(".lock") { continue }
        try update(
          child,
          logicalPath: "\(logicalPath)/\(name)",
          hasher: &hasher,
          visited: &visited
        )
      }
      return
    }
    guard values?.isRegularFile == true else {
      hasher.update(data: Data("other\u{0}".utf8))
      return
    }
    hasher.update(data: Data("file\u{0}".utf8))
    let handle = try FileHandle(forReadingFrom: standardized)
    defer { try? handle.close() }
    while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    hasher.update(data: Data("\u{0}".utf8))
  }
}
