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
import MikroKhorosServices

#if os(Windows)
  import WinSDK
#elseif canImport(Darwin)
  import Darwin
#else
  import Glibc
#endif

private struct Arguments {
  private(set) var values: [String]

  init(_ values: [String]) { self.values = values }

  var isEmpty: Bool { values.isEmpty }

  mutating func pop() -> String? {
    guard !values.isEmpty else { return nil }
    return values.removeFirst()
  }

  mutating func require(_ label: String) throws -> String {
    guard let value = pop() else { throw MikroKhorosError.command("missing \(label)") }
    return value
  }

  mutating func value(for option: String) throws -> String? {
    guard let index = values.firstIndex(of: option) else { return nil }
    guard index + 1 < values.count else {
      throw MikroKhorosError.command("\(option) requires a value")
    }
    values.remove(at: index)
    return values.remove(at: index)
  }

  mutating func flag(_ option: String) -> Bool {
    guard let index = values.firstIndex(of: option) else { return false }
    values.remove(at: index)
    return true
  }

  mutating func repeatedValues(for option: String) throws -> [String] {
    var result: [String] = []
    while let value = try value(for: option) { result.append(value) }
    return result
  }

  mutating func takeRemaining() -> [String] {
    let result = values
    values.removeAll()
    return result
  }

  func requireEmpty() throws {
    guard values.isEmpty else {
      throw MikroKhorosError.command("unknown argument '\(values[0])'")
    }
  }
}

private enum CLI {
  static func coordinate(_ source: String) throws -> Coordinate {
    let parts = source.split(separator: ",", omittingEmptySubsequences: false)
    guard parts.count == 2, let x = Int(parts[0]), let y = Int(parts[1]) else {
      throw MikroKhorosError.command("coordinate must use x,y integer syntax")
    }
    return Coordinate(x: x, y: y)
  }

  static func decimal(_ source: String, label: String) throws -> Decimal {
    guard
      let value = Decimal(
        string: source,
        locale: Locale(identifier: "en_US_POSIX")
      ), value >= 0
    else {
      throw MikroKhorosError.command("\(label) must be a non-negative number")
    }
    return value
  }

  static func integer(_ source: String, label: String) throws -> Int {
    guard let value = Int(source), value > 0 else {
      throw MikroKhorosError.command("\(label) must be a positive integer")
    }
    return value
  }

  static func scalar(_ value: String) -> String {
    let escaped =
      value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\r", with: "\\r")
    return "\"\(escaped)\""
  }

  static func agentSummary(_ agent: Agent, harness: Harness) -> String {
    let profile: String
    if let value = agent.aiProfile {
      profile = "\(value.adapterID)/\(value.model)"
    } else {
      profile = "none"
    }
    let walletID = agent.wallet.hash
    let walletBalance = CLI.scalar(formatWalletBalance(walletID: walletID, harness: harness))
    let walletMode = CLI.scalar(formatWalletMode(walletID: walletID, harness: harness))
    let walletDebt = CLI.scalar(formatWalletDebt(walletID: walletID, harness: harness))
    let holdings = Self.holdingsSummary(for: agent)
    return """
      agent:
        id: \(scalar(agent.hash))
        name: \(scalar(agent.name))
        world_id: \(scalar(harness.world.hash))
        in_world: \(agent.isInWorld)
        position: \(agent.isInWorld ? scalar(harness.agentPath(agent)) : "null")
        holding_1: \(holdings.slot1)
        holding_2: \(holdings.slot2)
        holding_3: \(holdings.slot3)
        holding_4: \(holdings.slot4)
        primary_holding: \(holdings.primary)
        wallet_id: \(scalar(walletID))
        wallet_balance: \(walletBalance)
        wallet_mode: \(walletMode)
        wallet_debt: \(walletDebt)
        ai_profile: \(scalar(profile))
        pending_notifications: \(agent.pendingBroadcasts.count)
        maximum_actions: \(agent.maximumActionsPerResponse)
        effective_maximum_actions: \(min(
          agent.maximumActionsPerResponse,
          harness.limits.maximumActionsPerResponse
        ))
      """
  }

  static func userAgentSummary(
    _ record: UserAgentRecord,
    activeAgent: Agent? = nil,
    harness: Harness? = nil
  ) -> String {
    if let activeAgent, let harness {
      return agentSummary(activeAgent, harness: harness)
    }
    let profile = record.profile.map { "\($0.adapterID)/\($0.model)" } ?? "none"
    return """
      agent:
        id: \(scalar(record.id))
        name: \(scalar(record.name))
        world_id: \(record.worldAssignment.map { scalar($0.worldID) } ?? "null")
        in_world: false
        position: null
        holding_1: null
        holding_2: null
        holding_3: null
        holding_4: null
        primary_holding: null
        wallet_id: null
        wallet_balance: null
        wallet_mode: null
        wallet_debt: null
        ai_profile: \(scalar(profile))
        pending_notifications: 0
        maximum_actions: \(record.maximumActionsPerResponse)
      """
  }

  private static func holdingsSummary(for agent: Agent) -> (
    slot1: String, slot2: String, slot3: String, slot4: String, primary: String
  ) {
    let slots = Array(
      [HoldingNumber.one, .two, .three, .four].map { index in
        agent.holdings[index].map { scalar("\($0.typeName)#\($0.hash)") } ?? "null"
      })
    return (
      slot1: slots[0],
      slot2: slots[1],
      slot3: slots[2],
      slot4: slots[3],
      primary: scalar(String(agent.primaryHoldingNumber.rawValue))
    )
  }

  private static func formatWalletBalance(walletID: String, harness: Harness) -> String {
    guard let service = harness.creditService else { return "unavailable" }
    do {
      return scalar(try service.balance(for: walletID).decimalText)
    } catch {
      return "unavailable"
    }
  }

  private static func formatWalletMode(walletID: String, harness: Harness) -> String {
    guard let service = harness.creditService else { return "unavailable" }
    do {
      return scalar(try service.mode(for: walletID).rawValue)
    } catch {
      return "unavailable"
    }
  }

  private static func formatWalletDebt(walletID: String, harness: Harness) -> String {
    guard let service = harness.creditService else { return "unavailable" }
    do {
      let balance = try service.balance(for: walletID)
      let debt: String
      if balance.minorUnits >= 0 {
        debt = "0.00"
      } else {
        debt = try CreditBalance(minorUnits: -balance.minorUnits).decimalText
      }
      return scalar(debt)
    } catch {
      return "unavailable"
    }
  }

  static func prompt(_ label: String, default defaultValue: String? = nil) -> String {
    let suffix = defaultValue.map { " [\($0)]" } ?? ""
    let value = (try? CommandRuntimeIO.readLine(prompt: "\(label)\(suffix): ")) ?? ""
    return value.isEmpty ? (defaultValue ?? "") : value
  }

  static func boolean(_ source: String, label: String) throws -> Bool {
    switch source.lowercased() {
    case "true", "yes", "1": return true
    case "false", "no", "0": return false
    default: throw MikroKhorosError.command("\(label) must be true or false")
    }
  }
}

private enum JSONOutput {
  static func render<Value: Encodable>(_ value: Value) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    guard let text = String(data: data, encoding: .utf8) else {
      throw MikroKhorosError.command("could not encode administrative output")
    }
    return text
  }
}

private struct CommandReportedFailure: Error {}

public enum KhorosCommandRunner {
  public static func main(webHost: (any KhorosWebServing)? = nil) async {
    let result = await CommandExecutor.execute(
      arguments: Array(CommandLine.arguments.dropFirst()),
      webHost: webHost
    )
    // A command may temporarily own process-global terminal signal sources.
    // The executor has already completed all deferred restoration at this
    // boundary, so terminate explicitly for both success and failure instead
    // of leaving process lifetime to the cooperative-concurrency runtime.
    exit(Int32(result))
  }

  @discardableResult
  public static func execute(
    arguments rawArguments: [String],
    io: any CommandIO = StandardCommandIO.shared,
    webHost: (any KhorosWebServing)? = nil
  ) async -> Int {
    await CommandExecutor.execute(arguments: rawArguments, io: io, webHost: webHost)
  }
}

extension CommandExecutor {
  static func executeResolved(
    arguments rawArguments: [String],
    io: any CommandIO,
    webHost: (any KhorosWebServing)?
  ) async -> Int {
    await CommandRuntimeIO.$current.withValue(io) {
      do {
        let (globals, consoleArguments) = try CommandParser.splitGlobals(rawArguments)
        if consoleArguments == ["console"] {
          guard io.isInteractive else {
            throw MikroKhorosError.runtime(
              "console.tty_required",
              "the interactive console requires terminal input and output"
            )
          }
          return await InteractiveConsole.run(initialGlobals: globals, io: io, webHost: webHost)
        }
        if rawArguments.isEmpty {
          if io.isInteractive {
            return await InteractiveConsole.run(initialGlobals: globals, io: io, webHost: webHost)
          }
          print(CommandCatalog.renderHelp())
          return 0
        }

        if let last = consoleArguments.last, last == "--help" || last == "-h" {
          print(CommandCatalog.renderHelp(path: Array(consoleArguments.dropLast())))
          return 0
        }
        let parsed = try CommandParser.parse(rawArguments)
        if parsed.kind == .help {
          let topics = parsed.fieldValues["topic"] ?? []
          let includeAll = parsed.fieldValues["all"]?.last == "true"
          print(CommandCatalog.renderHelp(path: topics, includeAll: includeAll))
          return 0
        }
        var arguments = Arguments(parsed.commandArguments)
        _ = arguments.pop()
        let worldQuery = parsed.globals.worldID
        let configurationPath = parsed.globals.configurationPath
        let configurationURL =
          configurationPath.map { URL(fileURLWithPath: $0) }
          ?? ConfigurationStore.defaultURL
        if parsed.kind == .web {
          let explicitPort = try arguments.value(for: "--port")
          let useAvailablePort = arguments.flag("--available-port")
          try arguments.requireEmpty()
          guard parsed.globals.outputMode == nil, parsed.globals.colorMode == nil else {
            throw MikroKhorosError.command("--output and --color are not supported by web")
          }
          guard explicitPort == nil || !useAvailablePort else {
            throw MikroKhorosError.command(
              "choose either --port or --available-port, not both"
            )
          }
          let portSelection: WebPortSelection
          if let explicitPort {
            guard let port = Int(explicitPort), (1...65_535).contains(port) else {
              throw MikroKhorosError.command("--port must be an integer from 1 through 65535")
            }
            portSelection = .explicit(port)
          } else if useAvailablePort {
            portSelection = .available
          } else {
            portSelection = .stable
          }
          guard let webHost else {
            throw MikroKhorosError.runtime(
              "web.host_unavailable",
              "the local web host is unavailable"
            )
          }
          let request = WebLaunchRequest(
            canonicalRoot: MikroKhorosPaths.root,
            configurationURL: configurationPath.map { URL(fileURLWithPath: $0) },
            worldSelector: worldQuery,
            portSelection: portSelection
          )
          do {
            try await webHost.serve(request) { launchURL in
              print(launchURL.absoluteString)
              if let port = launchURL.port {
                print("web: ready on http://127.0.0.1:\(port)/")
              }
              print("web: open the launch link above; stop with Ctrl-C")
            }
          } catch let error as WebServingError {
            throw webServingFailure(error)
          }
          return 0
        }
        if CommandExecutor.route(for: parsed.kind) == .adapters {
          try arguments.requireEmpty()
          printAdapters()
          return 0
        }
        switch CommandExecutor.route(for: parsed.kind) {
        case .configuration:
          let stateLock = try ProductStateLock()
          try ProductStateTransaction.recoverPending()
          try WebProductStateFingerprint.validateExpected(
            layout: ProductLayout(
              canonicalRoot: MikroKhorosPaths.root,
              configurationURL: configurationURL
            )
          )
          try configurationCommand(&arguments, url: configurationURL)
          withExtendedLifetime(stateLock) {}
          return 0
        case .runtime:
          break
        case .help, .web, .adapters:
          preconditionFailure("immediate commands return before runtime loading")
        }

        let followsReports = parsed.kind == .inventoryReportsFollow
        var stateLock: ProductStateLock? = try ProductStateLock()
        try ProductStateTransaction.recoverPending()
        try WebProductStateFingerprint.validateExpected(
          layout: ProductLayout(
            canonicalRoot: MikroKhorosPaths.root,
            configurationURL: configurationURL
          )
        )
        let configuration = try ConfigurationStore.load(from: configurationURL)
        let agents = try AgentStore(
          maximumBytes: configuration.runtime.maximumAgentStoreBytes
        )
        let inventory = try InventoryStore(
          limits: configuration.runtime,
          runtimeRegistry: .installedCLI()
        )
        let worlds = try WorldCatalogStore(
          maximumBytes: configuration.runtime.maximumWorldBytes
        )
        let treasuryAuthority = try resolveTreasuryAuthority(
          configuration: configuration,
          agents: agents,
          worlds: worlds
        )
        if parsed.kind == .worldTemplateList || parsed.kind == .worldTemplateShow {
          try worldTemplateCatalogCommand(&arguments)
          withExtendedLifetime(stateLock) {}
          return 0
        }
        if [.worldList, .worldUse, .worldRename, .worldDelete]
          .contains(parsed.kind)
        {
          try worldCatalogCommand(
            &arguments,
            kind: parsed.kind,
            worlds: worlds,
            agents: agents,
            inventory: inventory,
            configuration: configuration,
            treasuryAuthority: treasuryAuthority
          )
          withExtendedLifetime(stateLock) {}
          return 0
        }
        if parsed.kind == .worldCreate {
          try worldCreateCommand(
            &arguments,
            worldQuery: worldQuery,
            layout: ProductLayout(
              canonicalRoot: MikroKhorosPaths.root,
              configurationURL: configurationURL
            ),
            worlds: worlds,
            configuration: configuration,
            inventory: inventory,
            treasuryAuthority: treasuryAuthority
          )
          withExtendedLifetime(stateLock) {}
          return 0
        }
        if parsed.kind == .initialize {
          try initializeDefaultKhoros(
            &arguments,
            worldQuery: worldQuery,
            configurationURL: configurationURL,
            worlds: worlds,
            configuration: configuration,
            agents: agents,
            inventory: inventory,
            treasuryAuthority: treasuryAuthority
          )
          withExtendedLifetime(stateLock) {}
          return 0
        }
        if worlds.currentWorld == nil, worldQuery == nil, parsed.kind == .status {
          try arguments.requireEmpty()
          print("configuration: \(CLI.scalar(configurationURL.path))")
          print("product_root: \(CLI.scalar(MikroKhorosPaths.root.path))")
          print("world_catalog: \(CLI.scalar(worlds.url.path))")
          print("world: null")
          print(
            "state: \(worlds.document.worlds.isEmpty ? "not_initialized" : "selection_required")"
          )
          print("worlds: \(worlds.document.worlds.count)")
          print("agents: \(agents.allAgents().count)")
          print("inventory_objects: \(inventory.allInventoryObjects().count)")
          withExtendedLifetime(stateLock) {}
          return 0
        }
        if worlds.currentWorld == nil, worldQuery == nil, parsed.kind == .doctor {
          try arguments.requireEmpty()
          try doctorWithoutSelectedWorld(
            agents: agents,
            inventory: inventory,
            configuration: configuration,
            configurationURL: configurationURL,
            worlds: worlds,
            treasuryAuthority: treasuryAuthority
          )
          withExtendedLifetime(stateLock) {}
          return 0
        }
        let commandWorldQuery = parsed.fieldValues["world"]?.last ?? worldQuery
        let assignedWorldID = try assignedWorldID(for: parsed, agents: agents)
        if let assignedWorldID, let commandWorldQuery {
          let requested = try worlds.resolve(commandWorldQuery)
          guard requested.id == assignedWorldID else {
            throw MikroKhorosError.runtime(
              "agent.world_mismatch",
              "the agent is assigned to a different world",
              details: [
                "assigned_world": assignedWorldID,
                "requested_world": requested.id,
              ],
              suggestions: ["remove --world or select the assigned world"]
            )
          }
        }
        let selectedWorld: WorldCatalogRecord?
        if let assignedWorldID {
          selectedWorld = try worlds.resolve(assignedWorldID)
        } else if commandRequiresWorld(parsed.kind) || commandWorldQuery != nil
          || worlds.currentWorld != nil
        {
          selectedWorld = try worlds.selected(commandWorldQuery)
        } else {
          selectedWorld = nil
        }
        let worldURL = try selectedWorld.map { try WorldStore.url(for: $0.id) }
        let worldDocument =
          try worldURL.map {
            try WorldStore.load(
              from: $0,
              maximumBytes: configuration.runtime.maximumWorldBytes
            )
          } ?? WorldDocument()
        try rejectLegacyWorldSchema(
          document: worldDocument,
          operation: "loading selected world"
        )
        let runtime = try WorldRuntime(
          document: worldDocument,
          configuration: configuration,
          inventory: inventory,
          treasuryAuthority: treasuryAuthority
        )
        let concreteWorldURL =
          worldURL
          ?? WorldStore.directoryURL
          .appendingPathComponent("unselected.json", isDirectory: false)
        if !followsReports && parsed.kind != .doctor {
          try synchronizeAgentCatalog(
            agents,
            runtime: runtime
          )
        }
        if followsReports { stateLock = nil }
        switch parsed.kind {
        case .initialize:
          preconditionFailure("init returns before ordinary runtime dispatch")
        case .status:
          try arguments.requireEmpty()
          print("configuration: \(CLI.scalar(configurationURL.path))")
          print("product_root: \(CLI.scalar(MikroKhorosPaths.root.path))")
          print("world_catalog: \(CLI.scalar(worlds.url.path))")
          print("world_file: \(CLI.scalar(concreteWorldURL.path))")
          print("world: \(CLI.scalar(runtime.harness.world.hash))")
          print("world_name: \(CLI.scalar(runtime.document.worldName))")
          print("template_applications: \(runtime.document.templateApplications.count)")
          print(
            "healthy_templates: \(runtime.document.templateApplications.filter { application in application.components.count == WorldTemplateDefinition.defaultKhoros.components.count && application.components.allSatisfy { runtime.harness.findObject($0.rootObjectID) != nil } }.count)"
          )
          print("agents: \(agents.allAgents().count)")
          print("world_agents: \(runtime.harness.agents.count)")
          print("active_agents: \(runtime.harness.activeAgents.count)")
          print("inventory_objects: \(inventory.allInventoryObjects().count)")
          print("events: \(runtime.document.events.count)")
        case .doctor:
          try arguments.requireEmpty()
          try doctor(
            runtime: runtime,
            agents: agents,
            inventory: inventory,
            configurationURL: configurationURL,
            worldURL: concreteWorldURL,
            worlds: worlds,
            treasuryAuthority: treasuryAuthority
          )
        case .agentCreate, .agentList, .agentShow, .agentConfigure, .agentAdd, .agentRemove,
          .agentProfileSet, .agentProfileClear, .agentRetry:
          try await agentCommand(
            &arguments,
            runtime: runtime,
            agents: agents,
            worldURL: concreteWorldURL,
            worldQuery: worldQuery
          )
        case .agentShell:
          try shellCommand(
            &arguments,
            runtime: runtime,
            worldURL: concreteWorldURL,
            presentation: PresentationEnvironment.resolve(
              globals: parsed.globals,
              configuration: configuration,
              isInteractive: CommandRuntimeIO.active.isInteractive
            )
          )
        case .libraryFetch, .libraryList:
          try await libraryCommand(&arguments, runtime: runtime, worldURL: concreteWorldURL)
        case .inventoryInstall, .inventoryPackageList, .inventoryPackageShow,
          .inventoryPackageAvailable, .inventoryPackageRemove, .inventoryCreate,
          .inventoryFolderCreate, .inventoryFolderList, .inventoryFolderShow,
          .inventoryFolderRename, .inventoryFolderMove, .inventoryFolderDelete,
          .inventoryMove, .inventoryFork, .inventoryList, .inventoryShow,
          .inventoryInterface, .inventoryConfigure, .inventoryDelete, .inventorySecretSet,
          .inventorySecretClear, .inventoryCapabilityList, .inventoryCapabilityGrant,
          .inventoryCapabilityRevoke, .inventoryActionList, .inventoryActionRun,
          .inventoryViewList, .inventoryViewShow, .inventoryDeploy, .inventoryCopiesList,
          .inventoryCopiesShow, .inventoryCopiesDelete, .inventoryListenEnable,
          .inventoryListenDisable, .inventoryListenList, .inventoryReportsList,
          .inventoryReportsShow, .inventoryReportsFollow, .inventoryRestockCreate,
          .inventoryRestockList, .inventoryRestockShow, .inventoryRestockSet,
          .inventoryRestockRun, .inventoryRestockDelete:
          try await inventoryCommand(
            &arguments,
            inventory: inventory,
            runtime: runtime,
            worldURL: concreteWorldURL,
            worldFilter: worldQuery,
            treasuryAuthority: treasuryAuthority
          )
        case .worldTemplateStatus, .worldTemplateApply:
          try worldTemplateCommand(
            &arguments,
            inventory: inventory,
            runtime: runtime,
            worldURL: concreteWorldURL,
            worldQuery: worldQuery
          )
        case .worldShow, .worldInspect, .worldExport:
          try worldCommand(&arguments, runtime: runtime)
        case .worldObjectList, .worldObjectShow, .worldObjectInterface,
          .worldObjectActionList, .worldObjectActionRun, .worldObjectViewList,
          .worldObjectViewShow, .worldObjectMove:
          try worldObjectCommand(
            &arguments,
            inventory: inventory,
            runtime: runtime,
            worldURL: concreteWorldURL
          )
        case .worldList, .worldUse, .worldCreate, .worldRename, .worldDelete,
          .worldTemplateList, .worldTemplateShow:
          preconditionFailure("world setup command returns before ordinary runtime dispatch")
        case .help, .adapters, .configShow, .configPath, .configKeys, .configGet,
          .configSet, .configReset, .configValidate:
          preconditionFailure("command was handled before runtime loading")
        case .web:
          preconditionFailure("web returns before runtime loading")
        }
        withExtendedLifetime(stateLock) {}
        return 0
      } catch {
        if error is CommandReportedFailure {
          return 1
        } else if error is CancellationError {
          writeError(
            MikroKhorosError.runtime(
              "command.cancelled",
              "the running command was cancelled"
            )
          )
        } else {
          writeError(error)
        }
        return 1
      }
    }
  }

  private static func webServingFailure(_ error: WebServingError) -> MikroKhorosError {
    switch error {
    case .alreadyRunning:
      return .runtime(
        "web.host_already_running",
        "this mikrokhoros web host is already running",
        suggestions: ["use the launch URL printed by the running host"]
      )
    case .invalidPort:
      return .runtime(
        "web.port_invalid",
        "the selected web port is invalid",
        suggestions: [
          "use `khoros web --port <1-65535>`",
          "use `khoros web --available-port` to let the operating system choose",
        ]
      )
    case .portUnavailable(let port, let listener):
      let message: String
      let suggestions: [String]
      switch listener {
      case .mikroKhoros:
        message =
          "port \(port) is already used by a local service that identifies as mikrokhoros Web"
        suggestions = [
          "return to the terminal that started the existing host and use its launch URL",
          "use `khoros web --available-port` to start a separate host",
          "use `khoros web --port <another-port>` to choose another stable address",
        ]
      case .other:
        message = "port \(port) is unavailable, usually because another local service is using it"
        suggestions = [
          "use `khoros web --available-port` to let the operating system choose",
          "use `khoros web --port <another-port>` to choose another stable address",
        ]
      }
      return .runtime(
        "web.port_unavailable",
        message,
        details: [
          "address": "127.0.0.1",
          "listener": listener.rawValue,
          "port": String(port),
        ],
        suggestions: suggestions
      )
    case .bindFailed:
      return .runtime(
        "web.bind_failed",
        "the local web host could not bind its loopback listener",
        suggestions: [
          "use `khoros web --available-port`",
          "check local networking and try again",
        ]
      )
    }
  }

  private static func resolveTreasuryAuthority(
    configuration: RuntimeConfiguration,
    agents: AgentStore,
    worlds: WorldCatalogStore
  ) throws -> TreasuryAuthorityState {
    let treasuryAuthorityStore = try TreasuryAuthorityStore(
      maximumBytes: configuration.runtime.maximumWorldBytes
    )
    do {
      return try treasuryAuthorityStore.load()
    } catch {
      guard (error as? MikroKhorosError)?.issue.code == "treasury.authority_not_found" else {
        throw error
      }
      return try treasuryAuthorityStore.bootstrap(
        confirmNoExistingEconomy: agents.allAgents().isEmpty && worlds.document.worlds.isEmpty
      )
    }
  }

  private static func rejectLegacyWorldSchema(document: WorldDocument, operation: String) throws {
    guard document.schemaVersion == WorldDocument.currentSchemaVersion else {
      throw MikroKhorosError.runtime(
        "world.legacy_world_schema",
        "unsupported world schema found \(document.schemaVersion); required \(WorldDocument.currentSchemaVersion)",
        details: [
          "operation": operation,
          "world_id": document.worldID,
        ]
      )
    }
  }

  private static func configurationCommand(
    _ arguments: inout Arguments,
    url: URL
  ) throws {
    let operation = arguments.pop() ?? "show"
    switch operation {
    case "show":
      try arguments.requireEmpty()
      printConfiguration(try ConfigurationStore.load(from: url), url: url)
    case "path", "file":
      try arguments.requireEmpty()
      print(url.path)
    case "keys":
      try arguments.requireEmpty()
      print("keys:")
      for key in ConfigurationKey.all {
        print("  - \(CLI.scalar(key.path))")
      }
    case "get":
      let key = try ConfigurationKey(argument: arguments.require("configuration key"))
      try arguments.requireEmpty()
      let configuration = try ConfigurationStore.load(from: url)
      print("key: \(CLI.scalar(key.path))")
      print("value: \(key.value(in: configuration))")
    case "set":
      let key = try ConfigurationKey(argument: arguments.require("configuration key"))
      let value = try arguments.require("configuration value")
      try arguments.requireEmpty()
      let changed = try key.setting(value, in: ConfigurationStore.load(from: url))
      try ConfigurationStore.save(changed, to: url)
      print("updated: \(CLI.scalar(key.path))")
      print("value: \(key.value(in: changed))")
      print("applies: next_invocation")
    case "reset":
      let key = try arguments.pop().map(ConfigurationKey.init(argument:))
      try arguments.requireEmpty()
      let changed: RuntimeConfiguration
      if let key {
        changed = try key.resetting(in: ConfigurationStore.load(from: url))
      } else {
        changed = .defaults
      }
      try ConfigurationStore.save(changed, to: url)
      if let key {
        print("reset: \(CLI.scalar(key.path))")
        print("value: \(key.value(in: changed))")
      } else {
        print("reset: all")
      }
      print("applies: next_invocation")
    case "validate":
      try arguments.requireEmpty()
      let configuration = try ConfigurationStore.load(from: url)
      try configuration.validate()
      print("status: ok")
      print("configuration: \(CLI.scalar(url.path))")
      print("source: \(FileManager.default.fileExists(atPath: url.path) ? "file" : "defaults")")
    default:
      throw MikroKhorosError.command("unknown config operation '\(operation)'")
    }
  }

  private static func printConfiguration(
    _ configuration: RuntimeConfiguration,
    url: URL
  ) {
    print("configuration:")
    print("  path: \(CLI.scalar(url.path))")
    print(
      "  source: \(FileManager.default.fileExists(atPath: url.path) ? "file" : "defaults")"
    )
    print("  version: \(configuration.version)")
    print("  agents:")
    print(
      "    maximumActionsPerResponse: \(configuration.agents.maximumActionsPerResponse)"
    )
    print("  runtime:")
    for key in RuntimeLimitKey.allCases {
      print("    \(key.rawValue): \(configuration.runtime.value(for: key))")
    }
    print("  console:")
    for key in ConsoleConfigurationKey.allCases {
      print("    \(key.rawValue): \(configuration.console.value(for: key))")
    }
    print("  presentation:")
    for key in PresentationConfigurationKey.allCases {
      print("    \(key.rawValue): \(CLI.scalar(configuration.presentation.value(for: key)))")
    }
  }

  private static func doctor(
    runtime: WorldRuntime,
    agents: AgentStore,
    inventory: InventoryStore,
    configurationURL: URL,
    worldURL: URL,
    worlds: WorldCatalogStore,
    treasuryAuthority: TreasuryAuthorityState
  ) throws {
    try runtime.configuration.validate()
    try agents.validateStorage()
    try inventory.validateStorage()
    var warnings = try validateWorldCatalog(
      worlds: worlds,
      agents: agents,
      inventory: inventory,
      configuration: runtime.configuration,
      treasuryAuthority: treasuryAuthority
    )
    try runtime.validateInventoryArtifacts()
    let templateWarnings = try runtime.validateWorldTemplates()
    let configurationExists = FileManager.default.fileExists(atPath: configurationURL.path)
    let worldExists = FileManager.default.fileExists(atPath: worldURL.path)
    if !configurationExists {
      warnings.append("configuration file is absent; built-in defaults are effective")
    }
    guard worldExists else {
      throw MikroKhorosError.persistence("the selected world file is absent")
    }
    warnings.append(contentsOf: templateWarnings)
    let catalogRecords = Dictionary(
      uniqueKeysWithValues: agents.allAgents().map { ($0.id, $0) }
    )
    var missingCatalogRecords = 0
    for snapshot in runtime.document.agents {
      guard let source = catalogRecords[snapshot.id] else {
        missingCatalogRecords += 1
        continue
      }
      guard source.name == snapshot.name, source.genesis == snapshot.genesis,
        source.worldAssignment?.worldID == runtime.harness.world.hash
      else {
        throw MikroKhorosError.persistence(
          "the agent catalog conflicts with the selected world"
        )
      }
    }
    if missingCatalogRecords > 0 {
      warnings.append(
        "\(missingCatalogRecords) world agent(s) await user-catalog migration"
      )
    }
    let worldAgentIDs = Set(runtime.document.agents.map(\.id))
    if catalogRecords.values.contains(where: {
      $0.worldAssignment?.worldID == runtime.harness.world.hash
        && !worldAgentIDs.contains($0.id)
    }) {
      warnings.append("an agent assignment has no concrete snapshot in this world")
    }
    let catalogWorldIDs = Set(worlds.document.worlds.map(\.id))
    let unavailableBindings = inventory.allInventoryObjects(includeDeleted: true).filter {
      $0.worldBinding.map { !catalogWorldIDs.contains($0.worldID) } ?? false
    }.count
    if unavailableBindings > 0 {
      warnings.append(
        "\(unavailableBindings) world-bound Inventory source(s) reference deleted worlds")
    }
    let externalEffectReceiptCount = runtime.document.events.filter { event in
      if case .externalEffectReceipt = event { return true }
      return false
    }.count
    let nestedInvocationReceiptCount = runtime.document.events.filter { event in
      if case .nestedInvocationReceipt = event { return true }
      return false
    }.count
    print("status: ok")
    print("product_root: \(CLI.scalar(MikroKhorosPaths.root.path))")
    print("configuration:")
    print("  path: \(CLI.scalar(configurationURL.path))")
    print("  source: \(configurationExists ? "file" : "defaults")")
    print("world_catalog:")
    print("  path: \(CLI.scalar(worlds.url.path))")
    print("  worlds: \(worlds.document.worlds.count)")
    print("  current_world: \(worlds.document.currentWorldID.map(CLI.scalar) ?? "null")")
    print("world:")
    print("  file: \(CLI.scalar(worldURL.path))")
    print("  world_id: \(CLI.scalar(runtime.harness.world.hash))")
    print("  world_name: \(CLI.scalar(runtime.document.worldName))")
    print("  template_applications: \(runtime.document.templateApplications.count)")
    print("  agents: \(runtime.document.agents.count)")
    print("  events: \(runtime.document.events.count)")
    print("inventory:")
    print("  path: \(CLI.scalar(inventory.url.path))")
    print("  packages: \(inventory.installedPackages.count)")
    print("  folders: \(inventory.allInventoryFolders().count)")
    print("  objects: \(inventory.allInventoryObjects(includeDeleted: true).count)")
    print(
      "  world_bound_sources: \(inventory.allInventoryObjects(includeDeleted: true).filter { $0.worldBinding != nil }.count)"
    )
    print(
      "  adapter_backed_objects: \(runtime.harness.objects.filter { $0 is RuntimeAdapterObject }.count)"
    )
    print("  external_effect_receipts: \(externalEffectReceiptCount)")
    print("  nested_invocation_receipts: \(nestedInvocationReceiptCount)")
    print("  listeners: \(runtime.listeners.count)")
    print("  reports: \(runtime.reports.count)")
    print("  restock_rules: \(runtime.restockRules.count)")
    print("agent_catalog:")
    print("  path: \(CLI.scalar(agents.url.path))")
    print("  agents: \(agents.allAgents().count)")
    if warnings.isEmpty {
      print("warnings: []")
    } else {
      print("warnings:")
      for warning in warnings { print("  - \(CLI.scalar(warning))") }
    }
  }

  private static func doctorWithoutSelectedWorld(
    agents: AgentStore,
    inventory: InventoryStore,
    configuration: RuntimeConfiguration,
    configurationURL: URL,
    worlds: WorldCatalogStore,
    treasuryAuthority: TreasuryAuthorityState
  ) throws {
    try configuration.validate()
    try agents.validateStorage()
    try inventory.validateStorage()
    var warnings = try validateWorldCatalog(
      worlds: worlds,
      agents: agents,
      inventory: inventory,
      configuration: configuration,
      treasuryAuthority: treasuryAuthority
    )
    if !FileManager.default.fileExists(atPath: configurationURL.path) {
      warnings.append("configuration file is absent; built-in defaults are effective")
    }
    if worlds.document.worlds.isEmpty {
      warnings.append("no world exists; run `khoros init` or `khoros world create`")
    } else {
      warnings.append("no current world is selected; run `khoros world use <world>`")
    }
    print("status: ok")
    print("product_root: \(CLI.scalar(MikroKhorosPaths.root.path))")
    print("configuration:")
    print("  path: \(CLI.scalar(configurationURL.path))")
    print(
      "  source: \(FileManager.default.fileExists(atPath: configurationURL.path) ? "file" : "defaults")"
    )
    print("world_catalog:")
    print("  path: \(CLI.scalar(worlds.url.path))")
    print("  worlds: \(worlds.document.worlds.count)")
    print("  current_world: null")
    print("agent_catalog:")
    print("  path: \(CLI.scalar(agents.url.path))")
    print("  agents: \(agents.allAgents().count)")
    print("inventory:")
    print("  path: \(CLI.scalar(inventory.url.path))")
    print("  packages: \(inventory.installedPackages.count)")
    print("  objects: \(inventory.allInventoryObjects(includeDeleted: true).count)")
    if warnings.isEmpty {
      print("warnings: []")
    } else {
      print("warnings:")
      for warning in warnings { print("  - \(CLI.scalar(warning))") }
    }
  }

  /// Validates every managed world and all global references without relying on
  /// the human current-world selection.
  private static func validateWorldCatalog(
    worlds: WorldCatalogStore,
    agents: AgentStore,
    inventory: InventoryStore,
    configuration: RuntimeConfiguration,
    treasuryAuthority: TreasuryAuthorityState
  ) throws -> [String] {
    try worlds.validateStorage()
    let catalogWorldIDs = Set(worlds.document.worlds.map(\.id))
    guard
      agents.allAgents().allSatisfy({ record in
        record.worldAssignment.map { catalogWorldIDs.contains($0.worldID) } ?? true
      })
    else {
      throw MikroKhorosError.persistence("an agent assignment references an unknown world")
    }
    let concreteReferenceWorldIDs = Set(
      inventory.document.worldReferences.keys.filter(InventoryIdentity.isValid)
    )
    guard concreteReferenceWorldIDs.isSubset(of: catalogWorldIDs) else {
      throw MikroKhorosError.persistence("Inventory retention references an unknown world")
    }

    let agentRecords = Dictionary(uniqueKeysWithValues: agents.allAgents().map { ($0.id, $0) })
    var warnings: [String] = []
    for record in worlds.allWorlds() {
      let worldURL = try WorldStore.url(for: record.id)
      let document = try WorldStore.load(
        from: worldURL,
        maximumBytes: configuration.runtime.maximumWorldBytes
      )
      guard document.worldID == record.id, document.worldName == record.name else {
        throw MikroKhorosError.persistence(
          "world catalog metadata conflicts with its world document"
        )
      }
      let runtime = try WorldRuntime(
        document: document,
        configuration: configuration,
        inventory: inventory,
        treasuryAuthority: treasuryAuthority
      )
      try runtime.validateInventoryArtifacts()
      for warning in try runtime.validateWorldTemplates() {
        warnings.append("\(record.name) (\(record.id.prefix(8))): \(warning)")
      }
      for snapshot in document.agents {
        guard let source = agentRecords[snapshot.id] else {
          warnings.append(
            "\(record.name) has an agent snapshot awaiting user-catalog migration"
          )
          continue
        }
        guard source.worldAssignment?.worldID == record.id else {
          throw MikroKhorosError.persistence(
            "an agent catalog record conflicts with its concrete world snapshot"
          )
        }
      }
    }

    let manager = FileManager.default
    if manager.fileExists(atPath: WorldStore.directoryURL.path) {
      let expectedNames = Set(worlds.document.worlds.map { "\($0.id).json" })
        .union(["index.json"])
      let actualNames = try manager.contentsOfDirectory(atPath: WorldStore.directoryURL.path)
        .filter { $0.hasSuffix(".json") }
      let orphaned = actualNames.filter { !expectedNames.contains($0) }.sorted()
      if !orphaned.isEmpty {
        warnings.append("orphaned world files: \(orphaned.joined(separator: ", "))")
      }
    }
    return warnings
  }

  private static func worldTemplateCatalogCommand(
    _ arguments: inout Arguments
  ) throws {
    guard arguments.pop() == "template" else {
      throw MikroKhorosError.command("missing world template operation")
    }
    let operation = try arguments.require("world template operation")
    let catalog = WorldTemplateCatalog.installedCLI()
    switch operation {
    case "list":
      try arguments.requireEmpty()
      print("templates:")
      for definition in catalog.definitions {
        print("  - id: \(CLI.scalar(definition.id))")
        print("    version: \(CLI.scalar(definition.version))")
        print("    name: \(CLI.scalar(definition.displayName))")
        print("    components: \(definition.components.count)")
      }
    case "show":
      let definition = try catalog.resolve(arguments.require("template id"))
      try arguments.requireEmpty()
      printWorldTemplateDefinition(definition)
    default:
      throw MikroKhorosError.command("unknown world template operation '\(operation)'")
    }
  }

  private static func worldCatalogCommand(
    _ arguments: inout Arguments,
    kind: CommandKind,
    worlds: WorldCatalogStore,
    agents: AgentStore,
    inventory: InventoryStore,
    configuration: RuntimeConfiguration,
    treasuryAuthority: TreasuryAuthorityState
  ) throws {
    let expectedOperation: String
    switch kind {
    case .worldList: expectedOperation = "list"
    case .worldUse: expectedOperation = "use"
    case .worldRename: expectedOperation = "rename"
    case .worldDelete: expectedOperation = "delete"
    default: preconditionFailure("worldCatalogCommand received a non-catalog command")
    }
    guard arguments.pop() == expectedOperation else {
      throw MikroKhorosError.command("missing world \(expectedOperation) operation")
    }
    switch kind {
    case .worldList:
      _ = arguments.flag("--all")
      try arguments.requireEmpty()
      let records = worlds.allWorlds()
      print("product_root: \(CLI.scalar(MikroKhorosPaths.root.path))")
      print("current_world: \(worlds.document.currentWorldID.map(CLI.scalar) ?? "null")")
      if records.isEmpty {
        print("worlds: []")
      } else {
        print("worlds:")
        for record in records {
          let url = try WorldStore.url(for: record.id)
          let document = try WorldStore.load(
            from: url,
            maximumBytes: configuration.runtime.maximumWorldBytes
          )
          try rejectLegacyWorldSchema(
            document: document,
            operation: "world list validation"
          )
          let runtime = try WorldRuntime(
            document: document,
            configuration: configuration,
            inventory: inventory,
            treasuryAuthority: treasuryAuthority
          )
          let templateHealth: String
          if document.templateApplications.isEmpty {
            templateHealth = "bare"
          } else {
            templateHealth =
              try runtime.validateWorldTemplates().isEmpty
              ? "healthy" : "degraded"
          }
          print("  - id: \(CLI.scalar(record.id))")
          print("    name: \(CLI.scalar(record.name))")
          print("    current: \(worlds.document.currentWorldID == record.id)")
          print("    agents: \(document.agents.count)")
          print("    template_applications: \(document.templateApplications.count)")
          print("    template_health: \(templateHealth)")
          print("    file: \(CLI.scalar(url.path))")
        }
      }
    case .worldUse:
      let record = try worlds.use(arguments.require("world"))
      try arguments.requireEmpty()
      try worlds.save()
      print("world:")
      print("  id: \(CLI.scalar(record.id))")
      print("  name: \(CLI.scalar(record.name))")
      print("  current: true")
    case .worldRename:
      let query = try arguments.require("world")
      let name = try arguments.require("world name")
      try arguments.requireEmpty()
      let record = try worlds.resolve(query)
      let worldURL = try WorldStore.url(for: record.id)
      var document = try WorldStore.load(
        from: worldURL,
        maximumBytes: configuration.runtime.maximumWorldBytes
      )
      let priorCatalog = worlds.document
      let transaction = try ProductStateTransaction.begin(
        targets: [worlds.url, worldURL],
        affectedWorldIDs: [record.id]
      )
      do {
        document.worldName = name
        _ = try worlds.rename(record.id, name: name)
        try WorldStore.save(
          document,
          to: worldURL,
          maximumBytes: configuration.runtime.maximumWorldBytes
        )
        try worlds.save()
        try transaction.commit()
        print("world:")
        print("  id: \(CLI.scalar(record.id))")
        print("  name: \(CLI.scalar(name))")
        print("  status: renamed")
      } catch {
        try? worlds.restoreDocument(priorCatalog, persist: false)
        try? transaction.rollback()
        throw error
      }
    case .worldDelete:
      let record = try worlds.resolve(arguments.require("world"))
      let yes = arguments.flag("--yes")
      try arguments.requireEmpty()
      try requireConfirmation(yes: yes, question: "Delete world '\(record.name)'?")
      let worldURL = try WorldStore.url(for: record.id)
      let priorCatalog = worlds.document
      let priorAgents = agents.document
      let priorInventory = inventory.document
      let transaction = try ProductStateTransaction.begin(
        targets: [worlds.url, worldURL, agents.url, inventory.url],
        affectedWorldIDs: [record.id]
      )
      do {
        let clearedAgents = agents.clearAssignments(toWorld: record.id)
        inventory.removeWorldReferences(for: record.id)
        _ = try worlds.remove(record.id)
        try agents.save()
        // Credential versions remain intact until the cross-store deletion is
        // committed, so rollback can restore every referenced artifact.
        try inventory.save(garbageCollectCredentials: false)
        try worlds.save()
        if FileManager.default.fileExists(atPath: worldURL.path) {
          try FileManager.default.removeItem(at: worldURL)
        }
        try transaction.commit()
        inventory.garbageCollectUnreferencedCredentials()
        print("world:")
        print("  id: \(CLI.scalar(record.id))")
        print("  name: \(CLI.scalar(record.name))")
        print("  status: deleted")
        print("  cleared_agent_assignments: \(clearedAgents.count)")
        print("  recoverable: false")
        print("current_world: \(worlds.document.currentWorldID.map(CLI.scalar) ?? "null")")
      } catch {
        try? worlds.restoreDocument(priorCatalog, persist: false)
        try? agents.restoreDocument(priorAgents, persist: false)
        try? inventory.restoreDocument(priorInventory, persist: false)
        try? transaction.rollback()
        throw error
      }
    default:
      preconditionFailure("worldCatalogCommand received a non-catalog command")
    }
  }

  private static func worldCreateCommand(
    _ arguments: inout Arguments,
    worldQuery: String?,
    layout: ProductLayout,
    worlds: WorldCatalogStore,
    configuration: RuntimeConfiguration,
    inventory: InventoryStore,
    treasuryAuthority: TreasuryAuthorityState
  ) throws {
    guard arguments.pop() == "create" else {
      throw MikroKhorosError.command("missing world create operation")
    }
    guard worldQuery == nil else {
      throw MikroKhorosError.runtime(
        "world_template.world_required",
        "world creation issues its own world identity and does not accept --world",
        suggestions: ["remove --world from the command"]
      )
    }
    let suppliedName = try arguments.value(for: "--name")
    let templateID = try arguments.value(for: "--template")
    let yes = arguments.flag("--yes")
    try arguments.requireEmpty()
    let definition = try templateID.map { try WorldTemplateCatalog.installedCLI().resolve($0) }
    let name = suppliedName ?? definition?.id ?? "world"
    if templateID == nil {
      let created = try WorldCreationService(layout: layout).createBareWorldAssumingLocked(
        name: name,
        configuration: configuration,
        worlds: worlds,
        inventory: inventory,
        treasuryAuthority: treasuryAuthority
      )
      let worldURL = try layout.worldURL(for: created.id)
      print("world:")
      print("  id: \(CLI.scalar(created.id))")
      print("  name: \(CLI.scalar(created.name))")
      print("  file: \(CLI.scalar(worldURL.path))")
      print("  template: null")
      print("  status: created")
      print("  current: true")
      return
    }
    let document = WorldDocument(worldName: name)
    let worldURL = try WorldStore.url(for: document.worldID)
    let runtime = try WorldRuntime(
      document: document,
      configuration: configuration,
      inventory: inventory,
      treasuryAuthority: treasuryAuthority
    )
    let service = WorldTemplateService()
    let plan = try templateID.map {
      try service.preflight(templateID: $0, inventory: inventory, runtime: runtime)
    }
    if let plan { try confirmTemplateInventory(plan, yes: yes) }
    let priorInventory = inventory.document
    let priorCatalog = worlds.document
    let transaction = try ProductStateTransaction.begin(
      targets: [inventory.url, worlds.url, worldURL],
      affectedWorldIDs: [document.worldID]
    )
    do {
      let result = try plan.map { try service.apply($0, inventory: inventory, runtime: runtime) }
      try saveWorld(runtime)
      _ = try worlds.register(document: runtime.document)
      try worlds.save()
      try transaction.commit()
      if let result {
        printTemplateApplication(result, runtime: runtime, worldStatus: "created")
      } else {
        print("world:")
        print("  id: \(CLI.scalar(runtime.harness.world.hash))")
        print("  name: \(CLI.scalar(name))")
        print("  file: \(CLI.scalar(worldURL.path))")
        print("  template: null")
        print("  status: created")
        print("  current: true")
      }
    } catch {
      try? inventory.restoreDocument(priorInventory)
      try? worlds.restoreDocument(priorCatalog, persist: false)
      try? transaction.rollback()
      throw error
    }
  }

  private static func worldTemplateCommand(
    _ arguments: inout Arguments,
    inventory: InventoryStore,
    runtime: WorldRuntime,
    worldURL: URL,
    worldQuery: String?
  ) throws {
    guard arguments.pop() == "template" else {
      throw MikroKhorosError.command("missing world template operation")
    }
    let operation = try arguments.require("world template operation")
    _ = worldQuery
    let service = WorldTemplateService()
    switch operation {
    case "status":
      let templateID = arguments.pop() ?? "default-khoros"
      try arguments.requireEmpty()
      let plan = try service.preflight(
        templateID: templateID,
        inventory: inventory,
        runtime: runtime
      )
      printWorldTemplatePlan(plan, dryRun: false)
    case "apply":
      let templateID = try arguments.require("template id")
      let autoAdapt = arguments.flag("--auto-adapt")
      let dryRun = arguments.flag("--dry-run")
      let yes = arguments.flag("--yes")
      try arguments.requireEmpty()
      let plan = try service.preflight(
        templateID: templateID,
        inventory: inventory,
        runtime: runtime,
        autoAdapt: autoAdapt
      )
      if dryRun {
        printWorldTemplatePlan(plan, dryRun: true)
        return
      }
      try confirmTemplateInventory(plan, yes: yes)
      let priorInventory = inventory.document
      let transaction = try ProductStateTransaction.begin(
        targets: [inventory.url, worldURL],
        affectedWorldIDs: [runtime.harness.world.hash]
      )
      do {
        let result = try service.apply(
          plan,
          inventory: inventory,
          runtime: runtime,
          autoAdapt: autoAdapt
        )
        if !result.runtime.deployedObjectIDs.isEmpty {
          try saveWorld(runtime)
        }
        try transaction.commit()
        printTemplateApplication(
          result,
          runtime: runtime,
          worldStatus: "existing"
        )
      } catch {
        try? inventory.restoreDocument(priorInventory)
        try? transaction.rollback()
        throw error
      }
    default:
      throw MikroKhorosError.command("unknown world template operation '\(operation)'")
    }
  }

  private static func initializeDefaultKhoros(
    _ arguments: inout Arguments,
    worldQuery: String?,
    configurationURL: URL,
    worlds: WorldCatalogStore,
    configuration: RuntimeConfiguration,
    agents: AgentStore,
    inventory: InventoryStore,
    treasuryAuthority: TreasuryAuthorityState
  ) throws {
    try arguments.requireEmpty()
    let selected = try worldQuery.map(worlds.resolve) ?? worlds.currentWorld
    if selected == nil, worldQuery != nil {
      throw MikroKhorosError.runtime(
        "world.not_initialized",
        "--world cannot select a world before one exists",
        suggestions: ["run `khoros init` without --world"]
      )
    }
    let worldExisted = selected != nil
    let initialDocument =
      try selected.map {
        try WorldStore.load(
          from: WorldStore.url(for: $0.id),
          maximumBytes: configuration.runtime.maximumWorldBytes
        )
      } ?? WorldDocument(worldName: "default-khoros")
    let worldURL = try WorldStore.url(for: initialDocument.worldID)
    let priorInventory = inventory.document
    let priorAgents = agents.document
    let priorCatalog = worlds.document
    let inventoryExisted = FileManager.default.fileExists(atPath: inventory.url.path)
    let agentStoreExisted = FileManager.default.fileExists(atPath: agents.url.path)
    let configurationExisted = FileManager.default.fileExists(atPath: configurationURL.path)
    let transaction = try ProductStateTransaction.begin(
      targets: [configurationURL, inventory.url, agents.url, worlds.url, worldURL],
      affectedWorldIDs: [initialDocument.worldID]
    )
    let service = WorldTemplateService()
    let prepared: (runtime: WorldRuntime, plan: WorldTemplatePlan, prior: WorldDocument)
    do {
      let document = initialDocument
      let originalDocument = document
      try rejectLegacyWorldSchema(document: document, operation: "initialize default world")
      let runtime = try WorldRuntime(
        document: document,
        configuration: configuration,
        inventory: inventory,
        treasuryAuthority: treasuryAuthority
      )
      if worldExisted {
        try synchronizeAgentCatalog(agents, runtime: runtime)
      }
      prepared = (
        runtime,
        try service.preflight(
          templateID: "default-khoros",
          inventory: inventory,
          runtime: runtime
        ),
        originalDocument
      )
    } catch {
      try? inventory.restoreDocument(priorInventory)
      try? agents.restoreDocument(priorAgents)
      try? worlds.restoreDocument(priorCatalog, persist: false)
      if !inventoryExisted { try? FileManager.default.removeItem(at: inventory.url) }
      if !agentStoreExisted { try? FileManager.default.removeItem(at: agents.url) }
      try? transaction.rollback()
      throw error
    }
    let runtime = prepared.runtime
    let plan = prepared.plan
    if !plan.collisions.isEmpty {
      try? inventory.restoreDocument(priorInventory)
      try? agents.restoreDocument(priorAgents)
      try? worlds.restoreDocument(priorCatalog, persist: false)
      if !inventoryExisted { try? FileManager.default.removeItem(at: inventory.url) }
      if !agentStoreExisted { try? FileManager.default.removeItem(at: agents.url) }
      try? transaction.rollback()
      throw MikroKhorosError.runtime(
        "world_template.placement_conflict",
        "default-khoros cannot be initialized because a landmark position is occupied",
        details: [
          "positions": plan.collisions.map { $0.definition.coordinate.description }
            .joined(separator: ",")
        ],
        suggestions: [
          "move the occupants, then run `khoros init` again",
          "use explicit `world template apply default-khoros --auto-adapt` if adaptation is intended",
        ]
      )
    }
    let createsAgent = runtime.document.agents.isEmpty
    if createsAgent, runtime.harness.world.container?.object(at: .origin) != nil {
      try? inventory.restoreDocument(priorInventory)
      try? agents.restoreDocument(priorAgents)
      try? worlds.restoreDocument(priorCatalog, persist: false)
      if !inventoryExisted { try? FileManager.default.removeItem(at: inventory.url) }
      if !agentStoreExisted { try? FileManager.default.removeItem(at: agents.url) }
      try? transaction.rollback()
      throw MikroKhorosError.runtime(
        "placement.occupied",
        "the default agent origin is occupied",
        details: ["position": Coordinate.origin.description],
        suggestions: [
          "move the occupant, then run `khoros init` again",
          "create and add an agent explicitly at another coordinate",
        ]
      )
    }

    let priorWorld = prepared.prior
    do {
      // `init` is an explicit product mutation, so it is also the point where an
      // older in-memory configuration migration becomes durable.
      try ConfigurationStore.save(configuration, to: configurationURL)
      let templateResult = try service.apply(plan, inventory: inventory, runtime: runtime)
      var createdAgent: Agent?
      if createsAgent {
        let source = try agents.create(
          name: "agent",
          maximumActionsPerResponse: configuration.agents.maximumActionsPerResponse
        )
        let agent = try runtime.registerAgent(source)
        _ = try runtime.addAgent(agent, at: .origin)
        _ = try agents.assign(
          source.id,
          toWorld: runtime.harness.world.hash
        )
        createdAgent = agent
      }
      if runtime.document != priorWorld || !worldExisted {
        try saveWorld(runtime)
      }
      if !worldExisted {
        _ = try worlds.register(document: runtime.document)
        try worlds.save()
      }
      if agents.document != priorAgents { try agents.save() }
      try transaction.commit()
      print("initialization:")
      print("  configuration: \(configurationExisted ? "existing" : "created")")
      print(
        "  inventory: \(templateResult.createdInventoryObjectIDs.isEmpty ? "existing" : "created")")
      print("  world: \(worldExisted ? "existing" : "created")")
      print(
        "  template: \(templateResult.runtime.deployedObjectIDs.isEmpty ? "existing" : (templateResult.runtime.repaired ? "repaired" : "created"))"
      )
      print("  agent: \(createdAgent == nil ? "skipped" : "created")")
      print("product_root: \(CLI.scalar(MikroKhorosPaths.root.path))")
      print("world_file: \(CLI.scalar(worldURL.path))")
      print("world:")
      print("  id: \(CLI.scalar(runtime.harness.world.hash))")
      print("  name: \(CLI.scalar(runtime.document.worldName))")
      print("inventory:")
      print("  packages:")
      for component in templateResult.plan.definition.components {
        let status =
          templateResult.installedPackages.contains(component.packageSource)
          ? "created" : "existing"
        print("    - id: \(CLI.scalar(component.packageID))")
        print("      version: \(CLI.scalar(component.packageVersion))")
        print("      status: \(status)")
      }
      print("  canonical_sources:")
      for definition in templateResult.plan.definition.components {
        guard
          let source = try inventory.templateSource(
            templateID: templateResult.plan.definition.id,
            templateVersion: templateResult.plan.definition.version,
            componentKey: definition.key
          )
        else {
          throw MikroKhorosError.runtime(
            "world_template.source_missing",
            "a canonical source disappeared before initialization output"
          )
        }
        let status =
          templateResult.createdInventoryObjectIDs.contains(
            source.id
          ) ? "created" : "existing"
        print("    - component: \(CLI.scalar(definition.key))")
        print("      inventory_object_id: \(CLI.scalar(source.id))")
        print("      revision: \(source.revision)")
        print("      status: \(status)")
      }
      print("components:")
      for component in templateResult.runtime.application.components {
        let deployed = templateResult.runtime.deployedObjectIDs.contains(component.rootObjectID)
        let status =
          deployed
          ? (templateResult.runtime.repaired ? "repaired" : "created") : "existing"
        print("  - key: \(CLI.scalar(component.componentKey))")
        print("    object_id: \(CLI.scalar(component.rootObjectID))")
        print("    position: \(CLI.scalar(component.actualCoordinate.description))")
        print("    status: \(status)")
      }
      if let createdAgent {
        print("agent:")
        print("  status: created")
        print("  id: \(CLI.scalar(createdAgent.hash))")
        print("  position: \(CLI.scalar(Coordinate.origin.description))")
        print("  holding_1_eye_id: \(CLI.scalar(createdAgent.holdings[.one]!.hash))")
        print("  profile: null")
      } else {
        print("agent:")
        print("  status: skipped")
      }
    } catch {
      try? inventory.restoreDocument(priorInventory)
      try? agents.restoreDocument(priorAgents)
      try? worlds.restoreDocument(priorCatalog, persist: false)
      if !inventoryExisted { try? FileManager.default.removeItem(at: inventory.url) }
      if !agentStoreExisted { try? FileManager.default.removeItem(at: agents.url) }
      if !configurationExisted { try? FileManager.default.removeItem(at: configurationURL) }
      if !worldExisted { try? FileManager.default.removeItem(at: worldURL) }
      try? transaction.rollback()
      throw error
    }
  }

  private static func confirmTemplateInventory(
    _ plan: WorldTemplatePlan,
    yes: Bool
  ) throws {
    guard plan.confirmationRequired, !yes else { return }
    guard isInteractiveInput else {
      throw MikroKhorosError.runtime(
        "world_template.confirmation_required",
        "template setup requires approval for the listed Inventory additions",
        suggestions: ["repeat the command with --yes"]
      )
    }
    print("\(plan.definition.id) requires these Inventory additions:")
    if !plan.packagesToInstall.isEmpty || !plan.packagesToReactivate.isEmpty {
      print("")
      print("  Packages:")
      for source in plan.packagesToInstall + plan.packagesToReactivate {
        let component = plan.definition.components.first { $0.packageSource == source }
        let label = component.map { "\($0.packageID)@\($0.packageVersion)" } ?? source
        print("    - \(label)")
      }
    }
    if !plan.sourcesToCreate.isEmpty {
      print("")
      print("  Canonical sources:")
      for source in plan.sourcesToCreate { print("    - \(source)") }
    }
    if !plan.foldersToCreate.isEmpty {
      print("")
      print("  Folders:")
      for folder in plan.foldersToCreate { print("    - \(folder)") }
    }
    guard
      try CommandRuntimeIO.readLine(
        prompt: "\nAdd these items to Inventory and continue? [y/N]: "
      )?.lowercased() == "y"
    else {
      throw MikroKhorosError.runtime("command.cancelled", "operation cancelled")
    }
  }

  private static func printWorldTemplateDefinition(_ definition: WorldTemplateDefinition) {
    print("template:")
    print("  id: \(CLI.scalar(definition.id))")
    print("  version: \(CLI.scalar(definition.version))")
    print("  name: \(CLI.scalar(definition.displayName))")
    print("  summary: \(CLI.scalar(definition.summary))")
    print("  content_hash: \(CLI.scalar(definition.contentHash))")
    print("  components:")
    for component in definition.components {
      print("    - key: \(CLI.scalar(component.key))")
      print("      package: \(CLI.scalar("\(component.packageID)@\(component.packageVersion)"))")
      print("      inventory_source: \(CLI.scalar(component.inventoryName))")
      print("      position: \(CLI.scalar(component.coordinate.description))")
      print(
        "      children: [\(component.ownedObjectKeys.map(CLI.scalar).joined(separator: ", "))]")
      print("      pickup_lock: \(component.pickupLockReason.map(CLI.scalar) ?? "null")")
    }
  }

  private static func printWorldTemplatePlan(_ plan: WorldTemplatePlan, dryRun: Bool) {
    print("template_plan:")
    print("  dry_run: \(dryRun)")
    print("  template: \(CLI.scalar(plan.definition.id))")
    print("  version: \(CLI.scalar(plan.definition.version))")
    print("  world_id: \(CLI.scalar(plan.worldID))")
    print("  confirmation_required: \(plan.confirmationRequired)")
    print(
      "  packages_to_install: [\(plan.packagesToInstall.map(CLI.scalar).joined(separator: ", "))]")
    print(
      "  packages_to_reactivate: [\(plan.packagesToReactivate.map(CLI.scalar).joined(separator: ", "))]"
    )
    print("  folders_to_create: [\(plan.foldersToCreate.map(CLI.scalar).joined(separator: ", "))]")
    print(
      "  canonical_sources_to_create: [\(plan.sourcesToCreate.map(CLI.scalar).joined(separator: ", "))]"
    )
    print("  components:")
    for component in plan.components {
      print("    - key: \(CLI.scalar(component.definition.key))")
      print("      status: \(component.requiresDeployment ? "missing" : "present")")
      print("      inventory_object_id: \(component.inventoryObjectID.map(CLI.scalar) ?? "null")")
      print("      object_id: \(component.existingObjectID.map(CLI.scalar) ?? "null")")
      print("      requested: \(CLI.scalar(component.definition.coordinate.description))")
      print("      actual: \(CLI.scalar(component.actualCoordinate.description))")
      print("      collision: \(component.collisionObjectID.map(CLI.scalar) ?? "null")")
    }
  }

  private static func printTemplateApplication(
    _ result: WorldTemplateApplyResult,
    runtime: WorldRuntime,
    worldStatus: String
  ) {
    print("world:")
    print("  id: \(CLI.scalar(runtime.harness.world.hash))")
    print("  name: \(CLI.scalar(runtime.document.worldName))")
    print(
      "  file: \(CLI.scalar((try? WorldStore.url(for: runtime.harness.world.hash).path) ?? ""))")
    print("  status: \(worldStatus)")
    print("template:")
    print("  id: \(CLI.scalar(result.runtime.application.templateID))")
    print("  version: \(CLI.scalar(result.runtime.application.templateVersion))")
    print("  application_id: \(CLI.scalar(result.runtime.application.id))")
    print(
      "  status: \(result.runtime.deployedObjectIDs.isEmpty ? "existing" : (result.runtime.repaired ? "repaired" : "applied"))"
    )
    print("components:")
    for component in result.runtime.application.components {
      print("  - key: \(CLI.scalar(component.componentKey))")
      print("    inventory_object_id: \(CLI.scalar(component.inventoryObjectID))")
      print("    deployment_id: \(CLI.scalar(component.deploymentID))")
      print("    object_id: \(CLI.scalar(component.rootObjectID))")
      print("    requested: \(CLI.scalar(component.requestedCoordinate.description))")
      print("    actual: \(CLI.scalar(component.actualCoordinate.description))")
    }
  }

  private static func printAdapters() {
    print("adapters:")
    for availability in AIAdapterCatalog.detect() {
      let item = availability.definition
      print("  - id: \(CLI.scalar(item.id))")
      print("    name: \(CLI.scalar(item.name))")
      print("    category: \(item.category.rawValue)")
      print("    transport: \(item.transport.rawValue)")
      print("    detected: \(availability.isDetected)")
      if let executable = availability.detectedExecutable {
        print("    executable: \(CLI.scalar(executable))")
      }
      print("    bridge_required: \(item.requiresRoleSeparatedBridge)")
    }
  }

  private static func agentCommand(
    _ arguments: inout Arguments,
    runtime: WorldRuntime,
    agents: AgentStore,
    worldURL: URL,
    worldQuery: String?
  ) async throws {
    let operation = try arguments.require("agent operation")
    switch operation {
    case "create":
      let name = try arguments.require("agent name")
      let maximum = try arguments.value(for: "--max-actions").map {
        try CLI.integer($0, label: "maximum actions")
      }
      try arguments.requireEmpty()
      let source = try agents.create(
        name: name,
        maximumActionsPerResponse:
          maximum ?? runtime.configuration.agents.maximumActionsPerResponse
      )
      try agents.save()
      print(CLI.userAgentSummary(source))
    case "list":
      try arguments.requireEmpty()
      let records = agents.allAgents()
      if records.isEmpty {
        print("agents: []")
        return
      }
      print("agents:")
      for source in records {
        let active = runtime.harness.findAgent(source.id)
        print("  - id: \(CLI.scalar(source.id))")
        print("    name: \(CLI.scalar(source.name))")
        print(
          "    world_id: \(source.worldAssignment.map { CLI.scalar($0.worldID) } ?? "null")"
        )
        print("    active_in_selected_world: \(active?.isInWorld == true)")
        print("    profile: \(source.profile.map { CLI.scalar($0.adapterID) } ?? "null")")
      }
    case "show":
      let source = try agents.resolve(arguments.require("agent id"))
      try arguments.requireEmpty()
      print(
        CLI.userAgentSummary(
          source,
          activeAgent: runtime.harness.findAgent(source.id),
          harness: runtime.harness
        )
      )
    case "configure":
      let query = try arguments.require("agent id")
      guard let value = try arguments.value(for: "--max-actions") else {
        throw MikroKhorosError.command("agent configure requires --max-actions")
      }
      let maximum = try CLI.integer(value, label: "maximum actions")
      try arguments.requireEmpty()
      let source = try agents.setMaximumActions(maximum, for: query)
      if let agent = runtime.harness.findAgent(source.id) {
        try runtime.setMaximumActionsPerResponse(maximum, for: agent)
        try saveWorld(runtime)
      }
      try agents.save()
      print(
        CLI.userAgentSummary(
          source,
          activeAgent: runtime.harness.findAgent(source.id),
          harness: runtime.harness
        )
      )
    case "add":
      let targetWorld = try requireWorldTarget(worldQuery, runtime: runtime)
      let source = try agents.resolve(arguments.require("agent id"))
      let coordinate = try arguments.value(for: "--at").map(CLI.coordinate) ?? .origin
      let autoAdapt = arguments.flag("--auto-adapt")
      try arguments.requireEmpty()
      if let assignment = source.worldAssignment, assignment.worldID != targetWorld {
        throw MikroKhorosError.runtime(
          "agent.world_conflict",
          "the agent is already assigned to another world",
          details: [
            "assigned_world": assignment.worldID,
            "requested_world": targetWorld,
          ],
          suggestions: ["select the assigned world or create another agent"]
        )
      }
      let agent = try runtime.registerAgent(source)
      let placement = try runtime.addAgent(agent, at: coordinate, autoAdapt: autoAdapt)
      _ = try agents.assign(source.id, toWorld: targetWorld)
      try saveWorld(runtime)
      try agents.save()
      print("world: \(CLI.scalar(targetWorld))")
      print("requested: \(CLI.scalar(placement.requested.description))")
      print("actual: \(CLI.scalar(placement.actual.description))")
      print("adapted: \(placement.adapted)")
      try await handleReadyAgents(runtime: runtime, worldURL: worldURL)
    case "remove":
      let targetWorld = try requireWorldTarget(worldQuery, runtime: runtime)
      let source = try agents.resolve(arguments.require("agent id"))
      try arguments.requireEmpty()
      guard source.worldAssignment?.worldID == targetWorld else {
        throw MikroKhorosError.runtime(
          "agent.world_mismatch",
          "the agent is not assigned to the requested world",
          details: ["requested_world": targetWorld]
        )
      }
      let agent = try runtime.harness.resolveAgent(source.id)
      try runtime.removeAgent(agent)
      try saveWorld(runtime)
      print("world: \(CLI.scalar(targetWorld))")
      print("removed_from_world: \(CLI.scalar(agent.hash))")
      try await handleReadyAgents(runtime: runtime, worldURL: worldURL)
    case "profile":
      try await profileCommand(
        &arguments,
        runtime: runtime,
        agents: agents,
        worldURL: worldURL
      )
    case "retry":
      let agent = try runtime.harness.resolveAgent(arguments.require("agent id"))
      try arguments.requireEmpty()
      if let turn = try await runtime.handlePendingRequest(for: agent) {
        try saveWorld(runtime)
        print(turn.text)
      } else {
        print("events: []")
        print("status: no_unread_notification")
      }
    default:
      throw MikroKhorosError.command("unknown agent operation '\(operation)'")
    }
  }

  private static func profileCommand(
    _ arguments: inout Arguments,
    runtime: WorldRuntime,
    agents: AgentStore,
    worldURL: URL
  ) async throws {
    let operation = try arguments.require("profile operation")
    let source = try agents.resolve(arguments.require("agent id"))
    let agent = runtime.harness.findAgent(source.id)
    if let assignment = source.worldAssignment, agent == nil {
      throw MikroKhorosError.runtime(
        "agent.world_mismatch",
        "the assigned agent is not present in its world",
        details: ["assigned_world": assignment.worldID],
        suggestions: ["run `khoros world show \(assignment.worldID)` to inspect that world"]
      )
    }
    switch operation {
    case "set":
      guard let adapterID = try arguments.value(for: "--adapter"),
        let model = try arguments.value(for: "--model")
      else {
        throw MikroKhorosError.command("profile set requires --adapter and --model")
      }
      guard let definition = AIAdapterCatalog.definition(id: adapterID) else {
        throw MikroKhorosError.profile("unknown AI adapter id")
      }
      let name = try arguments.value(for: "--name") ?? "\(definition.name) profile"
      let endpoint = try arguments.value(for: "--endpoint") ?? definition.defaultEndpoint
      let credential =
        try arguments.value(for: "--credential-env")
        ?? definition.defaultCredentialEnvironmentVariable
      let temperature = try arguments.value(for: "--temperature").map {
        guard let value = Double($0) else {
          throw MikroKhorosError.command("temperature must be a number")
        }
        return value
      }
      let maximum = try arguments.value(for: "--max-output-tokens").map {
        try CLI.integer($0, label: "maximum output tokens")
      }
      let reasoning = try arguments.value(for: "--reasoning")
      try arguments.requireEmpty()
      let profile = try AIProfile(
        name: name,
        adapterID: adapterID,
        transport: definition.transport,
        model: model,
        endpoint: endpoint,
        credentialEnvironmentVariable: credential,
        temperature: temperature,
        maximumOutputTokens: maximum,
        reasoningEffort: reasoning
      )
      _ = try agents.setProfile(profile, for: source.id)
      if let agent {
        try runtime.attachProfile(profile, to: agent)
        try saveWorld(runtime)
      }
      try agents.save()
      print("profile: \(CLI.scalar(profile.id))")
      print("adapter: \(CLI.scalar(profile.adapterID))")
      print("latest_unread_queued: \(agent.map { !$0.pendingBroadcasts.isEmpty } ?? false)")
      if let agent, agent.isInWorld, !agent.pendingBroadcasts.isEmpty,
        let turn = try await runtime.handlePendingRequest(for: agent)
      {
        try saveWorld(runtime)
        print(turn.text)
      }
    case "clear":
      try arguments.requireEmpty()
      _ = try agents.setProfile(nil, for: source.id)
      if let agent {
        try runtime.detachProfile(from: agent)
        try saveWorld(runtime)
      }
      try agents.save()
      print("profile: null")
    default:
      throw MikroKhorosError.command("profile operation must be set or clear")
    }
  }

  private static func shellCommand(
    _ arguments: inout Arguments,
    runtime: WorldRuntime,
    worldURL: URL,
    presentation: PresentationEnvironment
  ) throws {
    let agent = try runtime.harness.resolveAgent(arguments.require("agent id"))
    var actions: [String] = []
    while let action = try arguments.value(for: "--action") { actions.append(action) }
    try arguments.requireEmpty()
    if !actions.isEmpty {
      let turn = try runtime.run(actions.joined(separator: "\n"), for: agent)
      try saveWorld(runtime)
      print(turn.text)
      if turn.status == .error { throw CommandReportedFailure() }
      return
    }
    if CommandRuntimeIO.active === StandardCommandIO.shared {
      try InteractiveAgentShell.run(
        agent: agent,
        runtime: runtime,
        worldURL: worldURL,
        color: presentation.colorEnabled
      )
      return
    }
    print("Enter raw in-world actions. Use :quit to close the human shell.")
    while let action = try CommandRuntimeIO.readLine() {
      if action == ":quit" || action == ":exit" { break }
      let turn = try runtime.run(action, for: agent)
      try saveWorld(runtime)
      print(turn.text)
    }
  }

  private static func libraryCommand(
    _ arguments: inout Arguments,
    runtime: WorldRuntime,
    worldURL: URL
  ) async throws {
    let operation = try arguments.require("library operation")
    switch operation {
    case "fetch":
      let source = try arguments.require("document URL")
      let requestedTitle = try arguments.value(for: "--title")
      try arguments.requireEmpty()
      let fetched = try await LibraryDocumentFetcher.fetch(
        source,
        maximumBytes: runtime.configuration.runtime.maximumProviderResponseBytes
      )
      let document = try runtime.addLibraryDocument(
        title: requestedTitle ?? fetched.title,
        sourceURL: fetched.sourceURL,
        content: fetched.content
      )
      try saveWorld(runtime)
      print("document:")
      print("  id: \(CLI.scalar(document.hash))")
      print("  title: \(CLI.scalar(document.title))")
      print("  source: \(CLI.scalar(document.sourceURL))")
      print("  characters: \(document.content.count)")
      print("  position: \(CLI.scalar(document.coordinate?.description ?? "unknown"))")
      try await handleReadyAgents(runtime: runtime, worldURL: worldURL)
    case "list":
      try arguments.requireEmpty()
      if runtime.libraryDocuments.isEmpty {
        print("documents: []")
      } else {
        print("documents:")
        for document in runtime.libraryDocuments {
          print("  - id: \(CLI.scalar(document.hash))")
          print("    title: \(CLI.scalar(document.title))")
          print("    source: \(CLI.scalar(document.sourceURL))")
          print("    characters: \(document.content.count)")
        }
      }
    default:
      throw MikroKhorosError.command("library operation must be fetch or list")
    }
  }

  private static func inventoryCommand(
    _ arguments: inout Arguments,
    inventory: InventoryStore,
    runtime: WorldRuntime,
    worldURL: URL,
    worldFilter: String?,
    treasuryAuthority: TreasuryAuthorityState
  ) async throws {
    let operation = try arguments.require("inventory operation")
    switch operation {
    case "install":
      let source = try arguments.require("object package path or URL")
      try arguments.requireEmpty()
      let result = try await inventory.install(from: source)
      print("package:")
      print("  id: \(CLI.scalar(result.package.manifest.id))")
      print("  version: \(CLI.scalar(result.package.manifest.version))")
      print("  runtime: \(result.package.manifest.runtime.rawValue)")
      print("  status: installed")
      print("installation:")
      print("  behavior: \(result.package.manifest.installation.onInstall.rawValue)")
      print(
        "  inventory_object_id: \(result.inventoryObject.map { CLI.scalar($0.id) } ?? "null")"
      )
    case "package":
      try inventoryPackageCommand(&arguments, inventory: inventory)
    case "folder":
      try inventoryFolderCommand(&arguments, inventory: inventory)
    case "create":
      let packageID = try arguments.require("package id")
      let version = try arguments.value(for: "--version")
      let name = try arguments.value(for: "--name")
      try arguments.requireEmpty()
      let object = try inventory.create(packageID: packageID, version: version, name: name)
      try printInventoryObject(object, inventory: inventory, runtime: runtime)
    case "move":
      let object = try inventory.resolve(arguments.require("Inventory object id"))
      guard let folder = try arguments.value(for: "--folder") else {
        throw MikroKhorosError.command("inventory move requires --folder")
      }
      try arguments.requireEmpty()
      let moved = try inventory.moveInventoryObject(object.id, toFolder: folder)
      try printInventoryObject(moved, inventory: inventory, runtime: runtime)
    case "fork":
      let object = try inventory.resolve(arguments.require("Inventory object id"))
      let name = try arguments.value(for: "--name")
      let folder = try arguments.value(for: "--folder")
      try arguments.requireEmpty()
      guard worldFilter != nil else {
        throw MikroKhorosError.runtime(
          "inventory.fork_world_required",
          "forking an Inventory source requires an explicit --world id",
          details: ["selected_world": runtime.harness.world.hash],
          suggestions: ["repeat the command with --world \(runtime.harness.world.hash)"]
        )
      }
      let fork = try inventory.fork(
        id: object.id,
        worldID: runtime.harness.world.hash,
        name: name,
        folder: folder
      )
      try printInventoryObject(fork, inventory: inventory, runtime: runtime)
    case "list":
      let packageID = try arguments.value(for: "--package")
      let folderQuery = try arguments.value(for: "--folder")
      let recursive = arguments.flag("--recursive")
      let includeDeleted = arguments.flag("--all")
      try arguments.requireEmpty()
      let folder = try folderQuery.map(inventory.resolveFolder)
      let folderIDs: Set<String>? = folder.map { selected in
        var ids = Set([selected.id])
        if recursive {
          ids.formUnion(inventory.childFolders(of: selected.id, recursive: true).map(\.id))
        }
        return ids
      }
      let objects = inventory.allInventoryObjects(includeDeleted: includeDeleted).filter { object in
        (packageID == nil || object.packageID == packageID)
          && (folderIDs == nil || folderIDs!.contains(object.folderID))
          && (worldFilter == nil || object.worldBinding?.worldID == runtime.harness.world.hash)
      }
      if objects.isEmpty {
        print("inventory_objects: []")
      } else {
        print("inventory_objects:")
        for object in objects {
          let readiness = try inventory.readiness(of: object)
          print("  - id: \(CLI.scalar(object.id))")
          print("    name: \(CLI.scalar(object.name))")
          print("    package: \(CLI.scalar("\(object.packageID)@\(object.packageVersion)"))")
          print("    revision: \(object.revision)")
          print("    folder: \(CLI.scalar(inventory.folderPath(for: object.folderID)))")
          print("    world: \(object.worldBinding.map { CLI.scalar($0.worldID) } ?? "null")")
          print("    ready: \(readiness.ready)")
          print("    deleted: \(object.deleted)")
        }
      }
    case "show":
      let object = try inventory.resolve(
        arguments.require("Inventory object id"),
        includeDeleted: true
      )
      try arguments.requireEmpty()
      try printInventoryObject(object, inventory: inventory, runtime: runtime)
    case "interface":
      let object = try inventory.resolve(arguments.require("Inventory object id"))
      try arguments.requireEmpty()
      print(try JSONOutput.render(runtime.managementInterface(for: object.id)))
    case "configure":
      try inventoryConfigureCommand(&arguments, inventory: inventory, runtime: runtime)
    case "secret":
      try inventorySecretCommand(&arguments, inventory: inventory, runtime: runtime)
    case "capability":
      try inventoryCapabilityCommand(&arguments, inventory: inventory, runtime: runtime)
    case "delete":
      let object = try inventory.resolve(arguments.require("Inventory object id"))
      let yes = arguments.flag("--yes")
      try arguments.requireEmpty()
      guard
        !runtime.restockRules.values.contains(where: {
          $0.inventoryObjectID == object.id
        })
      else {
        throw MikroKhorosError.runtime(
          "inventory.object_has_restock_rules",
          "restock rules in the selected world still reference this Inventory object",
          suggestions: ["delete the dependent restock rules first"]
        )
      }
      try requireConfirmation(
        yes: yes,
        question: "Delete Inventory object \(object.id)?"
      )
      let deleted = try inventory.delete(id: object.id)
      print("deleted_inventory_object: \(CLI.scalar(deleted.id))")
      print("world_copies_changed: false")
    case "action":
      try inventoryActionCommand(&arguments, inventory: inventory)
    case "view":
      try inventoryViewCommand(
        &arguments,
        inventory: inventory,
        runtime: runtime
      )
    case "deploy":
      let source = try inventory.resolve(arguments.require("Inventory object id"))
      let destination = try arguments.value(for: "--to") ?? "world"
      let coordinate = try arguments.value(for: "--at").map(CLI.coordinate) ?? .origin
      let autoAdapt = arguments.flag("--auto-adapt")
      try arguments.requireEmpty()
      let deployment = try runtime.deployInventoryObject(
        source.id,
        to: destination,
        at: coordinate,
        autoAdapt: autoAdapt
      )
      try saveWorld(runtime)
      printDeployment(
        deployment,
        source: source,
        folderPath: inventory.folderPath(for: source.folderID),
        worldID: runtime.harness.world.hash
      )
    case "copies":
      try inventoryCopiesCommand(
        &arguments,
        inventory: inventory,
        runtime: runtime,
        worldURL: worldURL
      )
    case "listen":
      try inventoryListenCommand(
        &arguments,
        inventory: inventory,
        runtime: runtime,
        worldURL: worldURL
      )
    case "reports":
      try await inventoryReportsCommand(
        &arguments,
        inventory: inventory,
        runtime: runtime,
        worldURL: worldURL,
        treasuryAuthority: treasuryAuthority
      )
    case "restock":
      try inventoryRestockCommand(
        &arguments,
        inventory: inventory,
        runtime: runtime,
        worldURL: worldURL
      )
    default:
      throw MikroKhorosError.command("unknown inventory operation '\(operation)'")
    }
  }

  private static func inventoryPackageCommand(
    _ arguments: inout Arguments,
    inventory: InventoryStore
  ) throws {
    switch try arguments.require("package operation") {
    case "available":
      try arguments.requireEmpty()
      print("packages:")
      for package in FirstPartyPackageCatalog.available {
        print("  - id: \(CLI.scalar(package.id))")
        print("    version: \(CLI.scalar(package.version))")
        print("    runtime: \(package.runtime.rawValue)")
        print(
          "    source: \(CLI.scalar("builtin:\(package.id.replacingOccurrences(of: "org.mikrokhoros.", with: ""))"))"
        )
      }
    case "list":
      try arguments.requireEmpty()
      if inventory.installedPackages.isEmpty {
        print("packages: []")
      } else {
        print("packages:")
        for package in inventory.installedPackages {
          print("  - id: \(CLI.scalar(package.manifest.id))")
          print("    version: \(CLI.scalar(package.manifest.version))")
          print("    runtime: \(package.manifest.runtime.rawValue)")
          print("    available: true")
        }
      }
    case "show":
      let id = try arguments.require("package id")
      let version = try arguments.value(for: "--version")
      try arguments.requireEmpty()
      print(try JSONOutput.render(inventory.package(id: id, version: version).manifest))
    case "remove":
      let id = try arguments.require("package id")
      let version = try arguments.value(for: "--version")
      let yes = arguments.flag("--yes")
      try arguments.requireEmpty()
      try requireConfirmation(
        yes: yes,
        question: "Remove package \(id)\(version.map { "@\($0)" } ?? "") from the catalog?"
      )
      try inventory.removePackage(id: id, version: version)
      print("removed_package: \(CLI.scalar(id))")
      print("version: \(version.map(CLI.scalar) ?? "selected")")
      print("existing_objects_changed: false")
    default:
      throw MikroKhorosError.command("package operation must be available, list, show, or remove")
    }
  }

  private static func inventoryFolderCommand(
    _ arguments: inout Arguments,
    inventory: InventoryStore
  ) throws {
    switch try arguments.require("folder operation") {
    case "create":
      let folder = try inventory.createFolder(path: arguments.require("folder path"))
      try arguments.requireEmpty()
      printInventoryFolder(folder, inventory: inventory)
    case "list":
      let query = arguments.values.first.map { $0.hasPrefix("--") ? nil : $0 } ?? nil
      if query != nil { _ = arguments.pop() }
      let folder = try inventory.resolveFolder(query ?? "/")
      let recursive = arguments.flag("--recursive")
      try arguments.requireEmpty()
      print("folder: \(CLI.scalar(inventory.folderPath(for: folder.id)))")
      let folders = inventory.childFolders(of: folder.id, recursive: recursive)
      let objects = inventory.inventoryObjects(inFolder: folder.id, recursive: recursive)
      if folders.isEmpty {
        print("folders: []")
      } else {
        print("folders:")
        for child in folders {
          print("  - id: \(CLI.scalar(child.id))")
          print("    path: \(CLI.scalar(inventory.folderPath(for: child.id)))")
        }
      }
      if objects.isEmpty {
        print("inventory_objects: []")
      } else {
        print("inventory_objects:")
        for object in objects {
          print("  - id: \(CLI.scalar(object.id))")
          print("    name: \(CLI.scalar(object.name))")
        }
      }
    case "show":
      let folder = try inventory.resolveFolder(arguments.require("folder"))
      try arguments.requireEmpty()
      printInventoryFolder(folder, inventory: inventory)
    case "rename":
      let folder = try arguments.require("folder")
      let name = try arguments.require("folder name")
      try arguments.requireEmpty()
      printInventoryFolder(try inventory.renameFolder(folder, to: name), inventory: inventory)
    case "move":
      let folder = try arguments.require("folder")
      guard let parent = try arguments.value(for: "--to") else {
        throw MikroKhorosError.command("inventory folder move requires --to")
      }
      try arguments.requireEmpty()
      printInventoryFolder(try inventory.moveFolder(folder, to: parent), inventory: inventory)
    case "delete":
      let folder = try inventory.resolveFolder(arguments.require("folder"))
      let yes = arguments.flag("--yes")
      try arguments.requireEmpty()
      try requireConfirmation(yes: yes, question: "Delete Inventory folder \(folder.id)?")
      _ = try inventory.deleteFolder(folder.id)
      print("deleted_folder: \(CLI.scalar(folder.id))")
    default:
      throw MikroKhorosError.command(
        "folder operation must be create, list, show, rename, move, or delete")
    }
  }

  private static func printInventoryFolder(
    _ folder: InventoryFolderRecord,
    inventory: InventoryStore
  ) {
    print("folder:")
    print("  id: \(CLI.scalar(folder.id))")
    print("  path: \(CLI.scalar(inventory.folderPath(for: folder.id)))")
    print("  parent_id: \(folder.parentID.map(CLI.scalar) ?? "null")")
    print("  child_folders: \(inventory.childFolders(of: folder.id).count)")
    print("  inventory_objects: \(inventory.inventoryObjects(inFolder: folder.id).count)")
    print("  created_at: \(CLI.scalar(ISO8601DateFormatter().string(from: folder.createdAt)))")
    print("  updated_at: \(CLI.scalar(ISO8601DateFormatter().string(from: folder.updatedAt)))")
  }

  private static func inventoryConfigureCommand(
    _ arguments: inout Arguments,
    inventory: InventoryStore,
    runtime: WorldRuntime
  ) throws {
    let object = try inventory.resolve(arguments.require("Inventory object id"))
    let assignments = try arguments.repeatedValues(for: "--set")
    let unsets = Set(try arguments.repeatedValues(for: "--unset"))
    try arguments.requireEmpty()
    guard !assignments.isEmpty || !unsets.isEmpty else {
      throw MikroKhorosError.command("configure requires --set or --unset")
    }
    let package = try inventory.package(contentHash: object.packageHash)
    var values: [String: JSONValue] = [:]
    for assignment in assignments {
      let (fieldID, raw) = try splitAssignment(assignment)
      guard let field = package.manifest.management.fields.first(where: { $0.id == fieldID }) else {
        throw MikroKhorosError.runtime(
          "inventory.field_unknown",
          "the configuration field is not declared by this package",
          details: ["field": fieldID]
        )
      }
      values[fieldID] = try managementValue(raw, field: field)
    }
    let updated = try inventory.configure(id: object.id, setting: values, unsetting: unsets)
    try printInventoryObject(updated, inventory: inventory, runtime: runtime)
  }

  private static func inventorySecretCommand(
    _ arguments: inout Arguments,
    inventory: InventoryStore,
    runtime: WorldRuntime
  ) throws {
    let operation = try arguments.require("secret operation")
    let object = try inventory.resolve(arguments.require("Inventory object id"))
    let field = try arguments.require("secret field")
    switch operation {
    case "set":
      let fromStdin = arguments.flag("--stdin")
      let environmentName = try arguments.value(for: "--from-env")
      guard !(fromStdin && environmentName != nil) else {
        throw MikroKhorosError.command("choose --stdin or --from-env, not both")
      }
      try arguments.requireEmpty()
      let data: Data
      if fromStdin {
        data = trimmedSecretData(try CommandRuntimeIO.active.readStandardInputToEnd())
      } else if let environmentName {
        guard let value = ProcessInfo.processInfo.environment[environmentName] else {
          throw MikroKhorosError.runtime(
            "inventory.secret_environment_missing",
            "the selected environment variable is not set",
            details: ["environment_variable": environmentName]
          )
        }
        data = Data(value.utf8)
      } else {
        data = Data(try readHiddenSecret(prompt: "Secret: ").utf8)
      }
      let updated = try inventory.setSecret(id: object.id, fieldID: field, value: data)
      print("inventory_object_id: \(CLI.scalar(updated.id))")
      print("field: \(CLI.scalar(field))")
      print("present: true")
      print("revision: \(updated.revision)")
    case "clear":
      try arguments.requireEmpty()
      let updated = try inventory.clearSecret(id: object.id, fieldID: field)
      print("inventory_object_id: \(CLI.scalar(updated.id))")
      print("field: \(CLI.scalar(field))")
      print("present: false")
      print("revision: \(updated.revision)")
    default:
      throw MikroKhorosError.command("secret operation must be set or clear")
    }
  }

  private static func inventoryCapabilityCommand(
    _ arguments: inout Arguments,
    inventory: InventoryStore,
    runtime: WorldRuntime
  ) throws {
    let operation = try arguments.require("capability operation")
    let object = try inventory.resolve(arguments.require("Inventory object id"))
    switch operation {
    case "list":
      try arguments.requireEmpty()
      printCapabilities(object)
    case "grant", "revoke":
      let raw = arguments.takeRemaining()
      guard !raw.isEmpty else {
        throw MikroKhorosError.command("at least one capability is required")
      }
      let capabilities = try Set(
        raw.map { value in
          guard let capability = ObjectCapability(rawValue: value) else {
            throw MikroKhorosError.command("unknown object capability '\(value)'")
          }
          return capability
        })
      let updated =
        operation == "grant"
        ? try inventory.grant(id: object.id, capabilities: capabilities)
        : try inventory.revoke(id: object.id, capabilities: capabilities)
      printCapabilities(updated)
      print("revision: \(updated.revision)")
    default:
      throw MikroKhorosError.command("capability operation must be list, grant, or revoke")
    }
  }

  private static func inventoryActionCommand(
    _ arguments: inout Arguments,
    inventory: InventoryStore
  ) throws {
    let operation = try arguments.require("action operation")
    let object = try inventory.resolve(arguments.require("Inventory object id"))
    let package = try inventory.package(contentHash: object.packageHash)
    switch operation {
    case "list":
      try arguments.requireEmpty()
      let actions = package.manifest.management.actions.filter { $0.scope.acceptsInventory }
      if actions.isEmpty {
        print("actions: []")
      } else {
        print("actions:")
        for action in actions {
          print("  - id: \(CLI.scalar(action.id))")
          print("    summary: \(CLI.scalar(action.summary))")
          print("    inputs:")
          for parameter in action.parameters {
            print("      - id: \(CLI.scalar(parameter))")
            print("        type: \((action.inputTypes[parameter] ?? .text).rawValue)")
            let defaultValue =
              action.inputDefaults[parameter].map(managementInputText).map(CLI.scalar) ?? "null"
            print("        default: \(defaultValue)")
            let choices = action.inputChoices[parameter] ?? []
            print("        choices: \(CLI.scalar(choices.joined(separator: ",")))")
          }
          print("    mutating: \(action.mutating)")
        }
      }
    case "run":
      let actionID = try arguments.require("action id")
      let assignments = try arguments.repeatedValues(for: "--input")
      try arguments.requireEmpty()
      guard
        let action = package.manifest.management.actions.first(where: {
          $0.id == actionID && $0.scope.acceptsInventory
        })
      else {
        throw MikroKhorosError.runtime(
          "inventory.action_unknown",
          "the package does not declare this management action",
          details: ["action": actionID]
        )
      }
      let submitted = try resolveManagementInputs(assignments, action: action)
      let result = try inventory.runAction(
        id: object.id,
        actionID: actionID,
        inputs: action.parameters.map { submitted[$0]! }
      )
      print("inventory_object_id: \(CLI.scalar(result.0.id))")
      print("action: \(CLI.scalar(actionID))")
      print("revision: \(result.0.revision)")
      print("result: \(try inlineJSON(result.1))")
    default:
      throw MikroKhorosError.command("action operation must be list or run")
    }
  }

  private static func inventoryViewCommand(
    _ arguments: inout Arguments,
    inventory: InventoryStore,
    runtime: WorldRuntime
  ) throws {
    let operation = try arguments.require("view operation")
    let object = try inventory.resolve(arguments.require("Inventory object id"))
    let package = try inventory.package(contentHash: object.packageHash)
    switch operation {
    case "list":
      try arguments.requireEmpty()
      let views = package.manifest.management.views.filter { $0.scope.acceptsInventory }
      if views.isEmpty {
        print("views: []")
      } else {
        print("views:")
        for view in views {
          print("  - id: \(CLI.scalar(view.id))")
          print("    summary: \(CLI.scalar(view.summary))")
          print("    source: \(view.source)")
          print("    world_object_scope: \(view.worldObjectScope)")
        }
      }
    case "show":
      let viewID = try arguments.require("view id")
      let selected = try arguments.value(for: "--object").map(runtime.harness.resolveObject)
      try arguments.requireEmpty()
      print(
        try JSONOutput.render(
          inventory.renderView(id: object.id, viewID: viewID, worldObject: selected)
        )
      )
    default:
      throw MikroKhorosError.command("view operation must be list or show")
    }
  }

  private static func inventoryCopiesCommand(
    _ arguments: inout Arguments,
    inventory: InventoryStore,
    runtime: WorldRuntime,
    worldURL: URL
  ) throws {
    let operation = try arguments.require("copies operation")
    switch operation {
    case "list":
      let source = try inventory.resolve(arguments.require("Inventory object id"))
      let deploymentID = try arguments.value(for: "--deployment").map {
        try runtime.resolveDeploymentID($0, inventoryID: source.id)
      }
      let listened = arguments.flag("--listened")
      try arguments.requireEmpty()
      let objects = runtime.copies(
        inventoryID: source.id,
        deploymentID: deploymentID,
        listenedOnly: listened
      )
      if objects.isEmpty {
        print("copies: []")
      } else {
        print("copies:")
        for object in objects {
          print("  - object_id: \(CLI.scalar(object.hash))")
          print("    deployment_id: \(CLI.scalar(object.lineage!.deploymentID))")
          print("    source_revision: \(object.lineage!.inventoryRevision)")
          print("    listened: \(runtime.listeners.contains(object.hash))")
          print("    location: \(CLI.scalar(objectLocation(object, harness: runtime.harness)))")
        }
      }
    case "show":
      let query = try arguments.require("world object id")
      try arguments.requireEmpty()
      let object = try runtime.harness.resolveObject(query)
      guard object.lineage != nil else {
        throw MikroKhorosError.runtime(
          "inventory.copy_not_found",
          "the selected object is not an Inventory-backed world copy"
        )
      }
      var snapshot = try runtime.harness.administrativeSnapshot(for: object.hash)
      if case .object(var values) = snapshot {
        values["listener_enabled"] = .bool(runtime.listeners.contains(object.hash))
        values["report_count"] = .number(
          Double(runtime.reports.filter { $0.objectID == object.hash }.count)
        )
        if let lineage = object.lineage,
          let source = inventory.allInventoryObjects(includeDeleted: true).first(where: {
            $0.id == lineage.inventoryObjectID
          })
        {
          values["inventory_source"] = inventorySourceValue(
            source,
            folderPath: inventory.folderPath(for: source.folderID)
          )
        }
        snapshot = .object(values)
      }
      print(try JSONOutput.render(snapshot))
    case "delete":
      let source = try inventory.resolve(arguments.require("Inventory object id"))
      let objectIDs = Set(try arguments.repeatedValues(for: "--object"))
      let deploymentIDs = Set(
        try arguments.repeatedValues(for: "--deployment").map {
          try runtime.resolveDeploymentID($0, inventoryID: source.id)
        }
      )
      let all = arguments.flag("--all")
      let recursive = arguments.flag("--recursive")
      let dryRun = arguments.flag("--dry-run")
      let yes = arguments.flag("--yes")
      try arguments.requireEmpty()
      let selectedFamilies =
        (objectIDs.isEmpty ? 0 : 1) + (deploymentIDs.isEmpty ? 0 : 1)
        + (all ? 1 : 0)
      guard selectedFamilies == 1 else {
        throw MikroKhorosError.command(
          "choose exactly one deletion scope: --object, --deployment, or --all"
        )
      }
      let scope: WorldCopyDeleteScope =
        all
        ? .all
        : (!objectIDs.isEmpty ? .objects(objectIDs) : .deployments(deploymentIDs))
      let preview = try runtime.previewCopyDeletion(
        inventoryID: source.id,
        scope: scope,
        recursive: recursive
      )
      printDeletionPreview(preview)
      guard !dryRun else {
        print("status: dry_run")
        return
      }
      try requireConfirmation(
        yes: yes,
        question: "Delete \(preview.affectedObjectIDs.count) concrete world object(s)?"
      )
      _ = try runtime.deleteCopies(
        inventoryID: source.id,
        scope: scope,
        recursive: recursive
      )
      try saveWorld(runtime)
      print("status: deleted")
    default:
      throw MikroKhorosError.command("copies operation must be list, show, or delete")
    }
  }

  private static func inventoryListenCommand(
    _ arguments: inout Arguments,
    inventory: InventoryStore,
    runtime: WorldRuntime,
    worldURL: URL
  ) throws {
    let operation = try arguments.require("listener operation")
    switch operation {
    case "enable", "disable":
      let query = try arguments.require("world object id")
      try arguments.requireEmpty()
      try runtime.setListener(operation == "enable", objectQuery: query)
      try saveWorld(runtime)
      let object = try runtime.harness.resolveObject(query)
      print("object_id: \(CLI.scalar(object.hash))")
      print("listener_enabled: \(operation == "enable")")
    case "list":
      let inventoryID = try arguments.value(for: "--inventory").map {
        try inventory.resolve($0).id
      }
      try arguments.requireEmpty()
      let objects = runtime.listeners.compactMap(runtime.harness.findObject).filter {
        inventoryID == nil || $0.lineage?.inventoryObjectID == inventoryID
      }.sorted { $0.hash < $1.hash }
      if objects.isEmpty {
        print("listeners: []")
      } else {
        print("listeners:")
        for object in objects {
          print("  - object_id: \(CLI.scalar(object.hash))")
          print("    inventory_object_id: \(CLI.scalar(object.lineage!.inventoryObjectID))")
          print("    package: \(CLI.scalar(object.lineage!.packageID))")
        }
      }
    default:
      throw MikroKhorosError.command("listener operation must be enable, disable, or list")
    }
  }

  private static func inventoryReportsCommand(
    _ arguments: inout Arguments,
    inventory: InventoryStore,
    runtime: WorldRuntime,
    worldURL: URL,
    treasuryAuthority: TreasuryAuthorityState
  ) async throws {
    let operation = try arguments.require("reports operation")
    switch operation {
    case "show":
      let report = try runtime.resolveReport(arguments.require("report id"))
      try arguments.requireEmpty()
      print(try JSONOutput.render(report))
    case "list", "follow":
      let inventoryID = try arguments.value(for: "--inventory").map {
        try inventory.resolve($0).id
      }
      let objectID = try arguments.value(for: "--object").map {
        try runtime.exactWorldObject($0).hash
      }
      let type = try arguments.value(for: "--type")
      let limit =
        try arguments.value(for: "--limit").map {
          try CLI.integer($0, label: "report limit")
        } ?? 100
      try arguments.requireEmpty()
      func matches(_ report: ObjectReport) -> Bool {
        (inventoryID == nil || report.inventoryObjectID == inventoryID)
          && (objectID == nil || report.objectID == objectID)
          && (type == nil || report.type == type)
      }
      let initial = Array(runtime.reports.filter(matches).suffix(limit))
      guard operation == "follow" else {
        printReportList(initial)
        return
      }
      for report in initial { print(try JSONOutput.render(report)) }
      var seen = Set(initial.map(\.id))
      while !Task.isCancelled {
        try await Task.sleep(for: .milliseconds(500))
        let document = try WorldStore.load(
          from: worldURL,
          maximumBytes: runtime.configuration.runtime.maximumWorldBytes
        )
        let latest = try WorldRuntime(
          document: document,
          configuration: runtime.configuration,
          inventory: inventory,
          treasuryAuthority: treasuryAuthority
        )
        for report in latest.reports where matches(report) && !seen.contains(report.id) {
          print(try JSONOutput.render(report))
          _ = fflush(nil)
          seen.insert(report.id)
        }
      }
    default:
      throw MikroKhorosError.command("reports operation must be list, show, or follow")
    }
  }

  private static func inventoryRestockCommand(
    _ arguments: inout Arguments,
    inventory: InventoryStore,
    runtime: WorldRuntime,
    worldURL: URL
  ) throws {
    let operation = try arguments.require("restock operation")
    switch operation {
    case "create":
      let inventoryID = try inventory.resolve(arguments.require("Inventory object id")).id
      guard let merchant = try arguments.value(for: "--merchant"),
        let priceText = try arguments.value(for: "--price")
      else {
        throw MikroKhorosError.command("restock create requires --merchant and --price")
      }
      let price = try CLI.decimal(priceText, label: "price")
      let coordinate = try arguments.value(for: "--at").map(CLI.coordinate) ?? .origin
      let autoAdapt = arguments.flag("--auto-adapt")
      try arguments.requireEmpty()
      let rule = try runtime.createRestockRule(
        inventoryID: inventoryID,
        merchantQuery: merchant,
        price: price,
        at: coordinate,
        autoAdapt: autoAdapt
      )
      try saveWorld(runtime)
      printRestockRule(rule)
    case "list":
      let inventoryID = try arguments.value(for: "--inventory").map {
        try inventory.resolve($0).id
      }
      let merchantID = try arguments.value(for: "--merchant").map {
        try runtime.exactWorldObject($0).hash
      }
      try arguments.requireEmpty()
      let rules = runtime.restockRules.values.filter {
        (inventoryID == nil || $0.inventoryObjectID == inventoryID)
          && (merchantID == nil || $0.merchantID == merchantID)
      }.sorted { $0.id < $1.id }
      if rules.isEmpty {
        print("restock_rules: []")
      } else {
        print("restock_rules:")
        for rule in rules {
          print("  - id: \(CLI.scalar(rule.id))")
          print("    inventory_object_id: \(CLI.scalar(rule.inventoryObjectID))")
          print("    merchant_id: \(CLI.scalar(rule.merchantID))")
          print("    price: \(CLI.scalar(formatAmount(rule.price)))")
          print("    enabled: \(rule.enabled)")
          print("    copies_created: \(rule.createdObjectIDs.count)")
        }
      }
    case "show":
      let rule = try runtime.resolveRestockRule(arguments.require("restock rule id"))
      try arguments.requireEmpty()
      printRestockRule(rule)
    case "set":
      let query = try arguments.require("restock rule id")
      let price = try arguments.value(for: "--price").map {
        try CLI.decimal($0, label: "price")
      }
      let enabled = try arguments.value(for: "--enabled").map {
        try CLI.boolean($0, label: "enabled")
      }
      guard price != nil || enabled != nil else {
        throw MikroKhorosError.command("restock set requires --price or --enabled")
      }
      try arguments.requireEmpty()
      let rule = try runtime.updateRestockRule(query, price: price, enabled: enabled)
      try saveWorld(runtime)
      printRestockRule(rule)
    case "run":
      let query = try arguments.require("restock rule id")
      let count =
        try arguments.value(for: "--count").map {
          try CLI.integer($0, label: "restock count")
        } ?? 1
      try arguments.requireEmpty()
      let before = try runtime.resolveRestockRule(query).createdObjectIDs.count
      let rule = try runtime.runRestockRule(query, count: count)
      try saveWorld(runtime)
      printRestockRule(rule)
      print("created_now: \(rule.createdObjectIDs.count - before)")
    case "delete":
      let query = try arguments.require("restock rule id")
      let yes = arguments.flag("--yes")
      try arguments.requireEmpty()
      let rule = try runtime.resolveRestockRule(query)
      try requireConfirmation(yes: yes, question: "Delete restock rule \(rule.id)?")
      try runtime.deleteRestockRule(rule.id)
      try saveWorld(runtime)
      print("deleted_restock_rule: \(CLI.scalar(rule.id))")
      print("existing_stock_changed: false")
    default:
      throw MikroKhorosError.command(
        "restock operation must be create, list, show, set, run, or delete"
      )
    }
  }

  private static func printInventoryObject(
    _ object: InventoryObjectRecord,
    inventory: InventoryStore,
    runtime: WorldRuntime
  ) throws {
    let package = try inventory.package(contentHash: object.packageHash)
    let readiness = try inventory.readiness(of: object)
    let copies = runtime.copies(inventoryID: object.id)
    let restock = runtime.restockRules.values.filter { $0.inventoryObjectID == object.id }
    let listenerCount = copies.filter { runtime.listeners.contains($0.hash) }.count
    let reportCount = runtime.reports.filter { $0.inventoryObjectID == object.id }.count
    let configuration: JSONValue
    if WebPresentationContext.isActive {
      let redacted = inventory.redactedConfiguration(of: object, manifest: package.manifest)
      let fieldIDs = Set(package.manifest.management.fields.map(\.id)).union(redacted.keys).sorted()
      configuration = .object(
        Dictionary(
          uniqueKeysWithValues: fieldIDs.map { fieldID in
            (fieldID, .object(["present": .bool(redacted[fieldID] != nil)]))
          }
        )
      )
    } else {
      configuration = .object(
        inventory.redactedConfiguration(of: object, manifest: package.manifest)
      )
    }
    let bindingStatus: JSONValue =
      object.worldBinding.map { binding in
        let available =
          (try? WorldStore.url(for: binding.worldID)).map {
            FileManager.default.fileExists(atPath: $0.path)
          } ?? false
        return .string(available ? "available" : "unavailable")
      } ?? .null
    print(
      try JSONOutput.render(
        JSONValue.object([
          "id": .string(object.id),
          "name": .string(object.name),
          "package": .object([
            "id": .string(object.packageID),
            "version": .string(object.packageVersion),
            "content_hash": .string(object.packageHash),
            "runtime": .string(package.manifest.runtime.rawValue),
          ]),
          "revision": .number(Double(object.revision)),
          "folder": .object([
            "id": .string(object.folderID),
            "path": .string(inventory.folderPath(for: object.folderID)),
          ]),
          "fork": object.forkProvenance.map { provenance in
            .object([
              "parent_inventory_object_id": .string(provenance.parentInventoryObjectID),
              "parent_revision": .number(Double(provenance.parentRevision)),
              "forked_at": .string(
                ISO8601DateFormatter().string(from: provenance.forkedAt)),
            ])
          } ?? .null,
          "world_binding": object.worldBinding.map { .string($0.worldID) } ?? .null,
          "world_binding_status": bindingStatus,
          "template_source": object.templateSource.map { source in
            .object([
              "template_id": .string(source.templateID),
              "template_version": .string(source.templateVersion),
              "component": .string(source.componentKey),
              "created_at": .string(
                ISO8601DateFormatter().string(from: source.createdAt)
              ),
            ])
          } ?? .null,
          "deleted": .bool(object.deleted),
          "ready": .bool(readiness.ready),
          "missing": .object([
            "configuration": .array(readiness.missingConfiguration.map(JSONValue.string)),
            "credentials": .array(readiness.missingCredentials.map(JSONValue.string)),
            "capabilities": .array(
              readiness.missingCapabilities.map(\.rawValue).map(JSONValue.string)
            ),
          ]),
          "configuration": configuration,
          "requested_capabilities": .array(
            object.requestedCapabilities.map(\.rawValue).sorted().map(JSONValue.string)
          ),
          "granted_capabilities": .array(
            object.grantedCapabilities.map(\.rawValue).sorted().map(JSONValue.string)
          ),
          "selected_world": .object([
            "copy_count": .number(Double(copies.count)),
            "restock_rule_count": .number(Double(restock.count)),
            "listener_count": .number(Double(listenerCount)),
            "report_count": .number(Double(reportCount)),
          ]),
          "created_at": .string(ISO8601DateFormatter().string(from: object.createdAt)),
          "updated_at": .string(ISO8601DateFormatter().string(from: object.updatedAt)),
        ])
      )
    )
  }

  private static func printCapabilities(_ object: InventoryObjectRecord) {
    print("inventory_object_id: \(CLI.scalar(object.id))")
    print("requested:")
    for capability in object.requestedCapabilities.sorted(by: { $0.rawValue < $1.rawValue }) {
      print("  - \(CLI.scalar(capability.rawValue))")
    }
    print("granted:")
    for capability in object.grantedCapabilities.sorted(by: { $0.rawValue < $1.rawValue }) {
      print("  - \(CLI.scalar(capability.rawValue))")
    }
    print("missing:")
    for capability in object.requestedCapabilities.subtracting(object.grantedCapabilities)
      .sorted(by: { $0.rawValue < $1.rawValue })
    {
      print("  - \(CLI.scalar(capability.rawValue))")
    }
  }

  private static func printDeployment(
    _ deployment: ObjectDeploymentRecord,
    source: InventoryObjectRecord,
    folderPath: String,
    worldID: String
  ) {
    let lineage = deployment.snapshot.lineage
    print("deployment:")
    print("  inventory_object_id: \(CLI.scalar(lineage.inventoryObjectID))")
    print("  source_revision: \(lineage.inventoryRevision)")
    print("  inventory_folder: \(CLI.scalar(folderPath))")
    let worldBinding = source.worldBinding.map { CLI.scalar($0.worldID) } ?? "null"
    let forkParent =
      source.forkProvenance.map { CLI.scalar($0.parentInventoryObjectID) } ?? "null"
    let forkRevision = source.forkProvenance.map { String($0.parentRevision) } ?? "null"
    print("  world_binding: \(worldBinding)")
    print("  fork_parent: \(forkParent)")
    print("  fork_parent_revision: \(forkRevision)")
    print("  package_id: \(CLI.scalar(lineage.packageID))")
    print("  package_version: \(CLI.scalar(lineage.packageVersion))")
    print("  package_content_hash: \(CLI.scalar(lineage.packageHash))")
    print("  deployment_id: \(CLI.scalar(lineage.deploymentID))")
    print("  object_id: \(CLI.scalar(deployment.snapshot.objectID))")
    print("  world_id: \(CLI.scalar(worldID))")
    print("  destination_object_id: \(CLI.scalar(deployment.destinationObjectID))")
    print("  requested: \(CLI.scalar(deployment.requestedCoordinate.description))")
    print("  actual: \(CLI.scalar(deployment.actualCoordinate.description))")
    print("  adapted: \(deployment.adapted)")
  }

  private static func inventorySourceValue(
    _ source: InventoryObjectRecord,
    folderPath: String
  ) -> JSONValue {
    .object([
      "id": .string(source.id),
      "folder_id": .string(source.folderID),
      "folder_path": .string(folderPath),
      "world_binding": source.worldBinding.map { .string($0.worldID) } ?? .null,
      "fork": source.forkProvenance.map { provenance in
        .object([
          "parent_inventory_object_id": .string(provenance.parentInventoryObjectID),
          "parent_revision": .number(Double(provenance.parentRevision)),
          "forked_at": .string(ISO8601DateFormatter().string(from: provenance.forkedAt)),
        ])
      } ?? .null,
    ])
  }

  private static func printDeletionPreview(_ preview: WorldCopyDeletionPreview) {
    print("deletion_preview:")
    print("  roots:")
    for id in preview.rootObjectIDs { print("    - \(CLI.scalar(id))") }
    print("  affected:")
    for id in preview.affectedObjectIDs { print("    - \(CLI.scalar(id))") }
  }

  private static func printRestockRule(_ rule: RestockRule) {
    print("restock_rule:")
    print("  id: \(CLI.scalar(rule.id))")
    print("  inventory_object_id: \(CLI.scalar(rule.inventoryObjectID))")
    print("  merchant_id: \(CLI.scalar(rule.merchantID))")
    print("  price: \(CLI.scalar(formatAmount(rule.price)))")
    print("  enabled: \(rule.enabled)")
    print("  requested: \(CLI.scalar(rule.requestedCoordinate.description))")
    print("  auto_adapt: \(rule.autoAdapt)")
    print("  created_objects:")
    for stock in rule.createdObjects {
      print("    - object_id: \(CLI.scalar(stock.objectID))")
      print("      creation_price: \(CLI.scalar(formatAmount(stock.price)))")
    }
  }

  private static func printReportList(_ reports: [ObjectReport]) {
    if reports.isEmpty {
      print("reports: []")
      return
    }
    print("reports:")
    for report in reports {
      print("  - id: \(CLI.scalar(report.id))")
      print("    timestamp: \(CLI.scalar(ISO8601DateFormatter().string(from: report.timestamp)))")
      print("    inventory_object_id: \(CLI.scalar(report.inventoryObjectID))")
      print("    object_id: \(CLI.scalar(report.objectID))")
      print("    type: \(CLI.scalar(report.type))")
      print("    title: \(CLI.scalar(report.title))")
    }
  }

  private static func objectLocation(_ object: MikroObject, harness: Harness) -> String {
    if let pair = harness.agents.lazy.compactMap({ agent in
      HoldingNumber.allCases.first(where: { agent.holdings[$0] === object }).map { (agent, $0) }
    }).first {
      return "holding \(pair.1.rawValue) of agent #\(pair.0.hash)"
    }
    if let space = object.parentSpace, let coordinate = object.coordinate {
      return "\(coordinate)@\(harness.spacePath(space))"
    }
    return "detached"
  }

  private static func encodableJSON<Value: Encodable>(_ value: Value) throws -> JSONValue {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try JSONDecoder().decode(JSONValue.self, from: encoder.encode(value))
  }

  private static func inlineJSON(_ value: JSONValue) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let result = String(data: data, encoding: .utf8) else {
      throw MikroKhorosError.command("could not encode structured output")
    }
    return result
  }

  private static func splitAssignment(_ value: String) throws -> (String, String) {
    guard let separator = value.firstIndex(of: "="), separator != value.startIndex else {
      throw MikroKhorosError.command("assignment must use field=value syntax")
    }
    return (
      String(value[..<separator]),
      String(value[value.index(after: separator)...])
    )
  }

  private static func resolveManagementInputs(
    _ assignments: [String],
    action: ManagementAction
  ) throws -> [String: String] {
    var submitted = Dictionary(
      uniqueKeysWithValues: action.inputDefaults.map { key, value in
        (key, managementInputText(value))
      })
    var explicit = Set<String>()
    let parameters = Set(action.parameters)
    for assignment in assignments {
      let (key, value) = try splitAssignment(assignment)
      guard parameters.contains(key) else {
        throw MikroKhorosError.command("management action input '\(key)' is unknown")
      }
      guard explicit.insert(key).inserted else {
        throw MikroKhorosError.command("management action input '\(key)' is repeated")
      }
      submitted[key] = value
    }
    guard Set(submitted.keys) == parameters else {
      let missing = action.parameters.filter { submitted[$0] == nil }
      throw MikroKhorosError.command(
        "management action inputs are missing: \(missing.joined(separator: ", "))"
      )
    }
    return submitted
  }

  private static func managementInputText(_ value: JSONValue) -> String {
    switch value {
    case .string(let text): return text
    case .number(let number):
      return number.rounded() == number ? String(Int(number)) : String(number)
    case .bool(let value): return value ? "true" : "false"
    case .null: return ""
    case .array, .object: return value.description
    }
  }

  private static func managementValue(_ raw: String, field: ManagementField) throws
    -> JSONValue
  {
    switch field.kind {
    case .text, .choice, .url, .path:
      return .string(raw)
    case .secret:
      throw MikroKhorosError.command("secret fields require the secret command")
    case .integer:
      guard let value = Int(raw) else {
        throw MikroKhorosError.command("\(field.id) must be an integer")
      }
      return .number(Double(value))
    case .decimal:
      guard let value = Double(raw), value.isFinite else {
        throw MikroKhorosError.command("\(field.id) must be a finite decimal")
      }
      return .number(value)
    case .boolean:
      return .bool(try CLI.boolean(raw, label: field.id))
    }
  }

  private static func requireConfirmation(yes: Bool, question: String) throws {
    if yes { return }
    guard isInteractiveInput else {
      throw MikroKhorosError.runtime(
        "command.confirmation_required",
        "non-interactive execution requires --yes"
      )
    }
    guard try CommandRuntimeIO.readLine(prompt: "\(question) [y/N]: ")?.lowercased() == "y" else {
      throw MikroKhorosError.runtime("command.cancelled", "operation cancelled")
    }
  }

  private static var isInteractiveInput: Bool {
    CommandRuntimeIO.active.isInteractive
  }

  private static func readHiddenSecret(prompt: String) throws -> String {
    guard isInteractiveInput else {
      throw MikroKhorosError.runtime(
        "inventory.secret_input_required",
        "non-interactive secret entry requires --stdin or --from-env"
      )
    }
    do {
      return try CommandRuntimeIO.readLine(prompt: prompt, hidden: true) ?? ""
    } catch {
      throw MikroKhorosError.command("could not configure hidden terminal input")
    }
  }

  private static func trimmedSecretData(_ input: Data) -> Data {
    var result = input
    if result.last == 0x0a { result.removeLast() }
    if result.last == 0x0d { result.removeLast() }
    return result
  }

  private static func assignedWorldID(
    for command: ParsedCommand,
    agents: AgentStore
  ) throws -> String? {
    switch command.kind {
    case .agentShow, .agentConfigure, .agentAdd, .agentRemove, .agentProfileSet,
      .agentProfileClear, .agentRetry, .agentShell:
      guard let selector = command.fieldValues["agent-id"]?.last else { return nil }
      return try agents.resolve(selector).worldAssignment?.worldID
    case .help, .web, .initialize, .status, .doctor, .configShow, .configPath, .configKeys,
      .configGet, .configSet, .configReset, .configValidate, .adapters, .agentCreate,
      .agentList, .libraryFetch, .libraryList,
      .inventoryInstall, .inventoryPackageAvailable, .inventoryPackageList,
      .inventoryPackageShow, .inventoryPackageRemove, .inventoryCreate,
      .inventoryFolderCreate, .inventoryFolderList, .inventoryFolderShow,
      .inventoryFolderRename, .inventoryFolderMove, .inventoryFolderDelete,
      .inventoryMove, .inventoryFork, .inventoryList, .inventoryShow,
      .inventoryInterface, .inventoryConfigure, .inventoryDelete, .inventorySecretSet,
      .inventorySecretClear, .inventoryCapabilityList, .inventoryCapabilityGrant,
      .inventoryCapabilityRevoke, .inventoryActionList, .inventoryActionRun,
      .inventoryViewList, .inventoryViewShow, .inventoryDeploy, .inventoryCopiesList,
      .inventoryCopiesShow, .inventoryCopiesDelete, .inventoryListenEnable,
      .inventoryListenDisable, .inventoryListenList, .inventoryReportsList,
      .inventoryReportsShow, .inventoryReportsFollow, .inventoryRestockCreate,
      .inventoryRestockList, .inventoryRestockShow, .inventoryRestockSet,
      .inventoryRestockRun, .inventoryRestockDelete, .worldList, .worldUse,
      .worldCreate, .worldRename, .worldDelete, .worldTemplateList,
      .worldTemplateShow, .worldTemplateStatus, .worldTemplateApply, .worldShow,
      .worldInspect, .worldExport, .worldObjectList, .worldObjectShow,
      .worldObjectInterface, .worldObjectActionList, .worldObjectActionRun,
      .worldObjectViewList, .worldObjectViewShow, .worldObjectMove:
      return nil
    }
  }

  private static func commandRequiresWorld(_ kind: CommandKind) -> Bool {
    switch kind {
    case .agentAdd, .agentRemove, .agentRetry, .agentShell, .libraryFetch, .libraryList,
      .inventoryFork, .inventoryDeploy, .inventoryCopiesList, .inventoryCopiesShow,
      .inventoryCopiesDelete, .inventoryListenEnable, .inventoryListenDisable,
      .inventoryListenList, .inventoryReportsList, .inventoryReportsShow,
      .inventoryReportsFollow, .inventoryRestockCreate, .inventoryRestockList,
      .inventoryRestockShow, .inventoryRestockSet, .inventoryRestockRun,
      .inventoryRestockDelete, .worldTemplateStatus, .worldTemplateApply,
      .worldShow, .worldInspect, .worldExport, .worldObjectList, .worldObjectShow,
      .worldObjectInterface, .worldObjectActionList, .worldObjectActionRun,
      .worldObjectViewList, .worldObjectViewShow, .worldObjectMove:
      true
    case .help, .web, .initialize, .status, .doctor, .configShow, .configPath, .configKeys,
      .configGet, .configSet, .configReset, .configValidate, .adapters,
      .agentCreate, .agentList, .agentShow, .agentConfigure, .agentProfileSet,
      .agentProfileClear, .inventoryInstall, .inventoryPackageAvailable,
      .inventoryPackageList, .inventoryPackageShow, .inventoryPackageRemove,
      .inventoryCreate, .inventoryFolderCreate, .inventoryFolderList,
      .inventoryFolderShow, .inventoryFolderRename, .inventoryFolderMove,
      .inventoryFolderDelete, .inventoryMove, .inventoryList, .inventoryShow,
      .inventoryInterface, .inventoryConfigure, .inventoryDelete,
      .inventorySecretSet, .inventorySecretClear, .inventoryCapabilityList,
      .inventoryCapabilityGrant, .inventoryCapabilityRevoke, .inventoryActionList,
      .inventoryActionRun, .inventoryViewList, .inventoryViewShow, .worldCreate,
      .worldList, .worldUse, .worldRename, .worldDelete,
      .worldTemplateList, .worldTemplateShow:
      false
    }
  }

  private static func requireWorldTarget(
    _ query: String?,
    runtime: WorldRuntime
  ) throws -> String {
    guard let query else { return runtime.harness.world.hash }
    let matchesIdentity =
      query == runtime.harness.world.hash
      || (query.count >= 4 && runtime.harness.world.hash.hasPrefix(query))
    let matchesName = runtime.document.worldName.caseInsensitiveCompare(query) == .orderedSame
    guard matchesIdentity || matchesName else {
      throw MikroKhorosError.runtime(
        "selector.not_found",
        "the selected world does not match the active world",
        suggestions: ["run `khoros world list` and select the intended world"]
      )
    }
    return runtime.harness.world.hash
  }

  private static func synchronizeAgentCatalog(
    _ agents: AgentStore,
    runtime: WorldRuntime
  ) throws {
    let original = agents.document
    var nextDocument = original
    let now = Date()
    for snapshot in runtime.document.agents {
      guard let agent = runtime.harness.findAgent(snapshot.id) else {
        throw MikroKhorosError.persistence(
          "the world contains an agent snapshot that was not reconstructed"
        )
      }
      let nextRecord: UserAgentRecord
      if let index = nextDocument.agents.firstIndex(where: { $0.id == snapshot.id }) {
        var record = nextDocument.agents[index]
        if let assignment = record.worldAssignment {
          guard assignment.worldID == runtime.harness.world.hash else {
            throw MikroKhorosError.persistence(
              "an agent identity is assigned to conflicting worlds")
          }
        } else {
          record.worldAssignment = try AgentWorldAssignment(
            worldID: runtime.harness.world.hash,
            assignedAt: now
          )
          record.updatedAt = now
        }
        nextDocument.agents[index] = record
        nextRecord = record
      } else {
        let assignment = try AgentWorldAssignment(
          worldID: runtime.harness.world.hash,
          assignedAt: now
        )
        nextRecord = try UserAgentRecord(
          id: snapshot.id,
          name: snapshot.name,
          maximumActionsPerResponse: snapshot.maximumActionsPerResponse,
          genesis: snapshot.genesis,
          profile: agent.aiProfile ?? snapshot.initialProfile,
          worldAssignment: assignment,
          createdAt: now,
          updatedAt: now
        )
        nextDocument.agents.append(nextRecord)
      }
      let source = nextRecord
      try runtime.synchronizeAgent(source)
    }
    if nextDocument != original { try agents.restoreDocument(nextDocument) }
  }

  private static func saveWorld(_ runtime: WorldRuntime) throws {
    let url = try WorldStore.url(for: runtime.harness.world.hash)
    let references = runtime.activeInventoryArtifactReferences
    if let inventory = runtime.inventory {
      let retained = inventory.worldReferences(for: runtime.harness.world.hash)
        .union(references)
      try inventory.synchronizeWorldReferences(
        worldID: runtime.harness.world.hash,
        credentialHandles: retained.credentialHandles,
        packageHashes: retained.packageHashes
      )
    }
    try WorldStore.save(
      runtime.document,
      to: url,
      maximumBytes: runtime.configuration.runtime.maximumWorldBytes
    )
    if let inventory = runtime.inventory {
      try inventory.synchronizeWorldReferences(
        worldID: runtime.harness.world.hash,
        credentialHandles: references.credentialHandles,
        packageHashes: references.packageHashes
      )
    }
  }

  private static func handleReadyAgents(
    runtime: WorldRuntime,
    worldURL: URL
  ) async throws {
    for agent in runtime.harness.activeAgents
    where agent.aiProfile != nil && !agent.pendingBroadcasts.isEmpty {
      guard let turn = try await runtime.handlePendingRequest(for: agent) else { continue }
      try saveWorld(runtime)
      print("agent_turn: \(CLI.scalar(agent.hash))")
      print(turn.text)
    }
  }

  private static func worldCommand(
    _ arguments: inout Arguments,
    runtime: WorldRuntime
  ) throws {
    switch try arguments.require("world operation") {
    case "show":
      _ = arguments.pop()
      try arguments.requireEmpty()
      print("world:")
      print("  id: \(CLI.scalar(runtime.harness.world.hash))")
      print("  name: \(CLI.scalar(runtime.document.worldName))")
      if runtime.document.templateApplications.isEmpty {
        print("  templates: []")
      } else {
        print("  templates:")
        for application in runtime.document.templateApplications {
          let definition = try WorldTemplateCatalog.installedCLI().resolve(
            application.templateID
          )
          let active = application.components.filter {
            runtime.harness.findObject($0.rootObjectID) != nil
          }.count
          print("    - id: \(CLI.scalar(application.templateID))")
          print("      version: \(CLI.scalar(application.templateVersion))")
          print("      application_id: \(CLI.scalar(application.id))")
          print("      status: \(active == definition.components.count ? "healthy" : "degraded")")
          print("      active_components: \(active)")
          print("      expected_components: \(definition.components.count)")
        }
      }
      if runtime.harness.world.container!.items.isEmpty {
        print("  objects: []")
      } else {
        print("  objects:")
        for item in runtime.harness.world.container!.items {
          print("    - position: \(CLI.scalar(item.coordinate.description))")
          print("      id: \(CLI.scalar(item.object.hash))")
          print("      type: \(CLI.scalar(item.object.typeName))")
          print("      name: \(CLI.scalar(item.object.name))")
        }
      }
      if runtime.harness.activeAgents.isEmpty {
        print("  agents: []")
      } else {
        print("  agents:")
        for agent in runtime.harness.activeAgents {
          print("    - id: \(CLI.scalar(agent.hash))")
          print("      name: \(CLI.scalar(agent.name))")
          print("      position: \(CLI.scalar(runtime.harness.agentPath(agent)))")
          print("      occupied_holdings: \(agent.holdings.occupiedRoots.count)")
        }
      }
    case "inspect":
      let query = arguments.pop()
      try arguments.requireEmpty()
      let snapshot: JSONValue
      if let query {
        snapshot = try runtime.harness.administrativeSnapshot(for: query)
      } else {
        snapshot = runtime.administrativeWorldSnapshot()
      }
      print(try JSONOutput.render(snapshot))
    case "export":
      try arguments.requireEmpty()
      print(try JSONOutput.render(runtime.document))
    default:
      throw MikroKhorosError.command("world operation must be show, inspect, or export")
    }
  }

  private static func worldObjectCommand(
    _ arguments: inout Arguments,
    inventory: InventoryStore,
    runtime: WorldRuntime,
    worldURL: URL
  ) throws {
    guard try arguments.require("world operation") == "object" else {
      throw MikroKhorosError.command("world object command is required")
    }
    switch try arguments.require("world object operation") {
    case "list":
      let container = try arguments.value(for: "--container").map { query in
        query == "world"
          ? runtime.harness.world.hash : try runtime.harness.resolveObject(query).hash
      }
      let type = try arguments.value(for: "--type")
      let package = try arguments.value(for: "--package")
      let inventoryID = try arguments.value(for: "--inventory").map {
        try inventory.resolve($0).id
      }
      let deployment = try arguments.value(for: "--deployment").map {
        try runtime.resolveDeploymentID($0, inventoryID: inventoryID)
      }
      try arguments.requireEmpty()
      let objects = runtime.concreteObjects(
        containerID: container,
        type: type,
        packageID: package,
        inventoryID: inventoryID,
        deploymentID: deployment
      )
      if objects.isEmpty {
        print("objects: []")
      } else {
        print("objects:")
        for object in objects {
          print("  - id: \(CLI.scalar(object.hash))")
          print("    type: \(CLI.scalar(object.typeName))")
          print("    name: \(CLI.scalar(object.name))")
          print("    location: \(CLI.scalar(objectLocation(object, harness: runtime.harness)))")
          print("    instance_revision: \(object.instanceRevision)")
          print(
            "    inventory: \(object.lineage.map { CLI.scalar($0.inventoryObjectID) } ?? "null")")
        }
      }
    case "show":
      let object = try runtime.exactWorldObject(arguments.require("world object id"))
      try arguments.requireEmpty()
      var values: [String: JSONValue] = [
        "administrative": try runtime.harness.administrativeSnapshot(for: object.hash),
        "management": try runtime.worldManagementInterface(for: object.hash),
      ]
      if let stateful = object as? RuntimeAdapterObject {
        values["adapter"] = .object([
          "id": .string(stateful.runtimeAdapterID),
          "version": .string(stateful.runtimeAdapterVersion),
          "state": .object(stateful.runtimeAdapterState),
        ])
      }
      print(try JSONOutput.render(JSONValue.object(values)))
    case "interface":
      let id = try runtime.exactWorldObject(arguments.require("world object id")).hash
      try arguments.requireEmpty()
      print(try JSONOutput.render(runtime.worldManagementInterface(for: id)))
    case "action":
      try worldObjectActionCommand(&arguments, runtime: runtime)
    case "view":
      try worldObjectViewCommand(&arguments, runtime: runtime)
    case "move":
      let object = try runtime.exactWorldObject(arguments.require("world object id"))
      guard let destination = try arguments.value(for: "--to") else {
        throw MikroKhorosError.command("world object move requires --to")
      }
      let coordinate = try arguments.value(for: "--at").map(CLI.coordinate) ?? .origin
      let autoAdapt = arguments.flag("--auto-adapt")
      try arguments.requireEmpty()
      let actual = try runtime.moveWorldObject(
        objectID: object.hash,
        to: destination,
        at: coordinate,
        autoAdapt: autoAdapt
      )
      try saveWorld(runtime)
      print("object_id: \(CLI.scalar(object.hash))")
      print("destination: \(CLI.scalar(destination))")
      print("coordinate: \(CLI.scalar(actual.description))")
      print("adapted: \(actual != coordinate)")
    default:
      throw MikroKhorosError.command(
        "world object operation must be list, show, interface, action, view, or move")
    }
  }

  private static func worldObjectActionCommand(
    _ arguments: inout Arguments,
    runtime: WorldRuntime,
  ) throws {
    let operation = try arguments.require("world object action operation")
    let object = try runtime.exactWorldObject(arguments.require("world object id"))
    let management = try worldManagementDescriptor(from: runtime, objectID: object.hash)
    switch operation {
    case "list":
      try arguments.requireEmpty()
      let actions = management.actions.filter { $0.scope.acceptsWorld }
      if actions.isEmpty {
        print("actions: []")
      } else {
        print("actions:")
        for action in actions {
          print("  - id: \(CLI.scalar(action.id))")
          print("    summary: \(CLI.scalar(action.summary))")
          print("    mutating: \(action.mutating)")
          print("    inputs:")
          for parameter in action.parameters {
            print("      - id: \(CLI.scalar(parameter))")
            print("        type: \((action.inputTypes[parameter] ?? .text).rawValue)")
            let defaultValue =
              action.inputDefaults[parameter].map(managementInputText).map(CLI.scalar) ?? "null"
            print("        default: \(defaultValue)")
            let choices = action.inputChoices[parameter] ?? []
            print("        choices: \(CLI.scalar(choices.joined(separator: ",")))")
          }
        }
      }
    case "run":
      let actionID = try arguments.require("world object action id")
      let assignments = try arguments.repeatedValues(for: "--input")
      try arguments.requireEmpty()
      guard
        let action = management.actions.first(where: {
          $0.id == actionID && $0.scope.acceptsWorld
        })
      else {
        throw MikroKhorosError.runtime(
          "object.management_action_unknown", "the selected object does not declare this action")
      }
      let submitted = try resolveManagementInputs(assignments, action: action)
      let result = try runtime.runWorldManagementAction(
        objectID: object.hash,
        actionID: actionID,
        inputs: action.parameters.map { submitted[$0]! }
      )
      try saveWorld(runtime)
      print("object_id: \(CLI.scalar(object.hash))")
      print("action: \(CLI.scalar(actionID))")
      print("instance_revision: \(object.instanceRevision)")
      print("result: \(try inlineJSON(result))")
    default:
      throw MikroKhorosError.command("world object action operation must be list or run")
    }
  }

  private static func worldObjectViewCommand(
    _ arguments: inout Arguments,
    runtime: WorldRuntime
  ) throws {
    let operation = try arguments.require("world object view operation")
    let object = try runtime.exactWorldObject(arguments.require("world object id"))
    let management = try worldManagementDescriptor(from: runtime, objectID: object.hash)
    switch operation {
    case "list":
      try arguments.requireEmpty()
      let views = management.views.filter { $0.scope.acceptsWorld }
      if views.isEmpty {
        print("views: []")
      } else {
        print("views:")
        for view in views {
          print("  - id: \(CLI.scalar(view.id))")
          print("    summary: \(CLI.scalar(view.summary))")
        }
      }
    case "show":
      let viewID = try arguments.require("world object view id")
      try arguments.requireEmpty()
      print(
        try JSONOutput.render(
          runtime.renderWorldManagementView(objectID: object.hash, viewID: viewID)))
    default:
      throw MikroKhorosError.command("world object view operation must be list or show")
    }
  }

  private static func worldManagementDescriptor(
    from runtime: WorldRuntime,
    objectID: String
  ) throws -> ObjectManagementInterface {
    // TODO(runtime-management-provider): switch to a typed native management-provider API
    // when runtime exposes it (for example, runtime.worldManagementDescriptor(for:)).
    // That API should avoid package-type dispatch and provide scope-aware action/view
    // declarations directly for concrete world objects.
    let interface = try runtime.worldManagementInterface(for: objectID)
    guard case .object(let root) = interface,
      let object = root["object"],
      case .object(let objectContract) = object
    else {
      throw MikroKhorosError.runtime(
        "object.management_interface_unavailable",
        "the selected object does not expose a management contract"
      )
    }
    let data = try JSONEncoder().encode(objectContract)
    return try JSONDecoder().decode(ObjectManagementInterface.self, from: data)
  }

  private static func writeError(_ error: Error) {
    let issue: RuntimeIssue
    if let known = error as? MikroKhorosError {
      issue = known.issue
    } else {
      issue = RuntimeIssue(code: "cli.failed", message: "command failed")
    }
    var lines = [
      "error:",
      "  code: \(CLI.scalar(String(issue.code.prefix(128))))",
      "  message: \(CLI.scalar(String(issue.message.prefix(1_024))))",
    ]
    if issue.details.isEmpty {
      lines.append("  details: {}")
    } else {
      lines.append("  details:")
      for key in issue.details.keys.sorted() {
        lines.append(
          "    \(CLI.scalar(String(key.prefix(128)))): "
            + CLI.scalar(String(issue.details[key]!.prefix(2_048)))
        )
      }
    }
    if !issue.suggestions.isEmpty {
      lines.append("  try:")
      for suggestion in issue.suggestions.prefix(16) {
        lines.append("    - \(CLI.scalar(String(suggestion.prefix(1_024))))")
      }
    }
    CommandRuntimeIO.writeError(lines.joined(separator: "\n") + "\n")
  }
}
