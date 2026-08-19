import Foundation
import MikroKhoros

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

  func requireEmpty() throws {
    guard values.isEmpty else {
      throw MikroKhorosError.command("unknown argument '\(values[0])'")
    }
  }
}

private enum CLI {
  static let help = """
    MikroKhoros — persistent multi-agent world runtime

    Usage:
      khoros [--config <file>] [--workspace <file>] <command>

    Commands:
      init
          Interactive first-agent setup.
      status
      doctor
          Validate the effective configuration and persistent workspace.
      config [show]
      config path
      config keys
      config get <key>
      config set <key> <positive-integer>
      config reset [<key>]
      config validate
      adapters
          List native providers, local servers, and OpenDesign-derived coding-agent options.
      agent create <name> [--coin <amount>|--infinite-coin] [--max-actions <n>]
          [--add] [--at <x,y>] [--auto-adapt]
      agent list
      agent show <agent-id>
      agent configure <agent-id> --max-actions <n>
      agent add <agent-id> [--at <x,y>] [--auto-adapt]
      agent remove <agent-id>
      agent profile set <agent-id> --adapter <id> --model <model>
          [--name <name>] [--endpoint <url>] [--credential-env <name>]
          [--temperature <0...2>] [--max-output-tokens <n>]
          [--reasoning <none|low|medium|high|xhigh|max>]
      agent profile clear <agent-id>
      agent retry <agent-id>
          Retry a pending notification after a provider/network failure.
      shell <agent-id> [--action <raw-action>]...
          Enter raw in-world actions manually; without --action, opens an interactive shell.
      message send <agent-id> --body <text> [--sender <name>] [--thread <id>]
          [--priority <!|!!|!!!>]
      message orient <agent-id>
          Send the built-in "meet Athena" request through the agent's Messenger.
      coin grant <agent-id> <amount|infinite>
      objective post --title <text> --body <text>
      objective list
      library fetch <https-url> [--title <text>]
      library list
      world show
      world inspect [<agent-or-object-id>]
          Read the complete live administrative state, including object-private state.
      world export
          Read the complete event journal and model histories as JSON.

    Per-user files:
      config: \(ConfigurationStore.defaultURL.path)
      workspace: \(WorkspaceStore.defaultURL.path)
    """

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
    return """
      agent:
        id: \(scalar(agent.hash))
        name: \(scalar(agent.name))
        in_world: \(agent.isInWorld)
        position: \(agent.isInWorld ? scalar(harness.agentPath(agent)) : "null")
        held: \(agent.hand.map { scalar("\($0.typeName)#\($0.hash)") } ?? "null")
        coin: \(scalar(formatAmount(agent.coin.balance)))
        ai_profile: \(scalar(profile))
        pending_notifications: \(agent.pendingBroadcasts.count)
        maximum_actions: \(agent.maximumActionsPerResponse)
        effective_maximum_actions: \(min(
          agent.maximumActionsPerResponse,
          harness.limits.maximumActionsPerResponse
        ))
      """
  }

  static func prompt(_ label: String, default defaultValue: String? = nil) -> String {
    let suffix = defaultValue.map { " [\($0)]" } ?? ""
    print("\(label)\(suffix): ", terminator: "")
    let value = readLine(strippingNewline: true) ?? ""
    return value.isEmpty ? (defaultValue ?? "") : value
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

@main
private enum MikroKhorosCommand {
  static func main() async {
    do {
      var arguments = Arguments(Array(CommandLine.arguments.dropFirst()))
      if arguments.flag("--help") || arguments.flag("-h") {
        try arguments.requireEmpty()
        print(CLI.help)
        return
      }
      let workspacePath = try arguments.value(for: "--workspace")
      let configurationPath = try arguments.value(for: "--config")
      let workspaceURL =
        workspacePath.map { URL(fileURLWithPath: $0) }
        ?? WorkspaceStore.defaultURL
      let configurationURL =
        configurationPath.map { URL(fileURLWithPath: $0) }
        ?? ConfigurationStore.defaultURL
      guard let command = arguments.pop() else {
        print(CLI.help)
        return
      }
      if command == "adapters" {
        try arguments.requireEmpty()
        printAdapters()
        return
      }
      if command == "config" {
        try configurationCommand(&arguments, url: configurationURL)
        return
      }

      let configuration = try ConfigurationStore.load(from: configurationURL)
      let runtime = try WorkspaceRuntime(
        document: WorkspaceStore.load(from: workspaceURL),
        configuration: configuration
      )
      switch command {
      case "init":
        try arguments.requireEmpty()
        try initialize(runtime: runtime)
        try WorkspaceStore.save(runtime.document, to: workspaceURL)
        try await handleReadyAgents(runtime: runtime, workspaceURL: workspaceURL)
      case "status":
        try arguments.requireEmpty()
        print("configuration: \(CLI.scalar(configurationURL.path))")
        print("workspace: \(CLI.scalar(workspaceURL.path))")
        print("world: \(CLI.scalar(runtime.harness.world.hash))")
        print("agents: \(runtime.harness.agents.count)")
        print("active_agents: \(runtime.harness.activeAgents.count)")
        print("events: \(runtime.document.events.count)")
      case "doctor":
        try arguments.requireEmpty()
        try doctor(
          runtime: runtime,
          configurationURL: configurationURL,
          workspaceURL: workspaceURL
        )
      case "agent":
        try await agentCommand(&arguments, runtime: runtime, workspaceURL: workspaceURL)
      case "shell":
        try shellCommand(&arguments, runtime: runtime, workspaceURL: workspaceURL)
      case "message":
        try await messageCommand(&arguments, runtime: runtime, workspaceURL: workspaceURL)
      case "coin":
        try coinCommand(&arguments, runtime: runtime, workspaceURL: workspaceURL)
      case "objective":
        try await objectiveCommand(&arguments, runtime: runtime, workspaceURL: workspaceURL)
      case "library":
        try await libraryCommand(&arguments, runtime: runtime, workspaceURL: workspaceURL)
      case "world":
        try worldCommand(&arguments, runtime: runtime)
      default:
        throw MikroKhorosError.command("unknown command '\(command)'")
      }
    } catch {
      writeError(error)
      exit(1)
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
      let value = try CLI.integer(
        arguments.require("configuration value"),
        label: key.path
      )
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
  }

  private static func doctor(
    runtime: WorkspaceRuntime,
    configurationURL: URL,
    workspaceURL: URL
  ) throws {
    try runtime.configuration.validate()
    let configurationExists = FileManager.default.fileExists(atPath: configurationURL.path)
    let workspaceExists = FileManager.default.fileExists(atPath: workspaceURL.path)
    var warnings: [String] = []
    if !configurationExists {
      warnings.append("configuration file is absent; built-in defaults are effective")
    }
    if !workspaceExists {
      warnings.append("workspace file is absent; no persistent world has been saved")
    }
    print("status: ok")
    print("configuration:")
    print("  path: \(CLI.scalar(configurationURL.path))")
    print("  source: \(configurationExists ? "file" : "defaults")")
    print("workspace:")
    print("  path: \(CLI.scalar(workspaceURL.path))")
    print("  source: \(workspaceExists ? "file" : "new")")
    print("  agents: \(runtime.document.agents.count)")
    print("  events: \(runtime.document.events.count)")
    if warnings.isEmpty {
      print("warnings: []")
    } else {
      print("warnings:")
      for warning in warnings { print("  - \(CLI.scalar(warning))") }
    }
  }

  private static func initialize(runtime: WorkspaceRuntime) throws {
    guard runtime.harness.agents.isEmpty else {
      throw MikroKhorosError.command("workspace is already initialized")
    }
    print("MikroKhoros first-agent setup. Leave adapter blank to attach AI later.")
    let name = CLI.prompt("Agent name", default: "agent")
    let coinText = CLI.prompt("Initial coin (number or infinite)", default: "0")
    let coin =
      coinText.lowercased() == "infinite"
      ? nil : try CLI.decimal(coinText, label: "coin")
    let agent = try runtime.createAgent(name: name, coinBalance: coin)
    let placement = try runtime.addAgent(agent)
    let adapterID = CLI.prompt("AI adapter id (optional)")
    if !adapterID.isEmpty {
      guard let definition = AIAdapterCatalog.definition(id: adapterID) else {
        throw MikroKhorosError.profile("unknown AI adapter id")
      }
      let model = CLI.prompt("Model")
      let endpoint = CLI.prompt(
        "Endpoint (optional)", default: definition.defaultEndpoint ?? ""
      )
      let credential = CLI.prompt(
        "Credential environment variable (optional)",
        default: definition.defaultCredentialEnvironmentVariable ?? ""
      )
      let profile = try AIProfile(
        name: "\(definition.name) profile",
        adapterID: adapterID,
        transport: definition.transport,
        model: model,
        endpoint: endpoint.isEmpty ? nil : endpoint,
        credentialEnvironmentVariable: credential.isEmpty ? nil : credential
      )
      try runtime.attachProfile(profile, to: agent)
    }
    print("created: \(CLI.scalar(agent.hash))")
    print("position: \(CLI.scalar("\(placement.actual)@world"))")
    print("held: \(CLI.scalar("eye.object#\(agent.hand!.hash)"))")
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
    runtime: WorkspaceRuntime,
    workspaceURL: URL
  ) async throws {
    let operation = try arguments.require("agent operation")
    switch operation {
    case "create":
      let name = try arguments.require("agent name")
      let coinText = try arguments.value(for: "--coin")
      let infinite = arguments.flag("--infinite-coin")
      guard !(coinText != nil && infinite) else {
        throw MikroKhorosError.command("choose --coin or --infinite-coin, not both")
      }
      let coin: Decimal? =
        infinite
        ? nil
        : try coinText.map {
          try CLI.decimal($0, label: "coin")
        } ?? 0
      let maximum = try arguments.value(for: "--max-actions").map {
        try CLI.integer($0, label: "maximum actions")
      }
      let shouldAdd = arguments.flag("--add")
      let coordinate = try arguments.value(for: "--at").map(CLI.coordinate) ?? .origin
      let autoAdapt = arguments.flag("--auto-adapt")
      try arguments.requireEmpty()
      let agent = try runtime.createAgent(
        name: name, coinBalance: coin, maximumActionsPerResponse: maximum
      )
      if shouldAdd {
        _ = try runtime.addAgent(agent, at: coordinate, autoAdapt: autoAdapt)
      }
      try WorkspaceStore.save(runtime.document, to: workspaceURL)
      print(CLI.agentSummary(agent, harness: runtime.harness))
      if shouldAdd {
        try await handleReadyAgents(runtime: runtime, workspaceURL: workspaceURL)
      }
    case "list":
      try arguments.requireEmpty()
      if runtime.harness.agents.isEmpty {
        print("agents: []")
        return
      }
      print("agents:")
      for agent in runtime.harness.agents {
        print("  - id: \(CLI.scalar(agent.hash))")
        print("    name: \(CLI.scalar(agent.name))")
        print("    in_world: \(agent.isInWorld)")
        print("    profile: \(agent.aiProfile.map { CLI.scalar($0.adapterID) } ?? "null")")
      }
    case "show":
      let agent = try runtime.harness.resolveAgent(arguments.require("agent id"))
      try arguments.requireEmpty()
      print(CLI.agentSummary(agent, harness: runtime.harness))
    case "configure":
      let agent = try runtime.harness.resolveAgent(arguments.require("agent id"))
      guard let value = try arguments.value(for: "--max-actions") else {
        throw MikroKhorosError.command("agent configure requires --max-actions")
      }
      let maximum = try CLI.integer(value, label: "maximum actions")
      try arguments.requireEmpty()
      try runtime.setMaximumActionsPerResponse(maximum, for: agent)
      try WorkspaceStore.save(runtime.document, to: workspaceURL)
      print(CLI.agentSummary(agent, harness: runtime.harness))
    case "add":
      let agent = try runtime.harness.resolveAgent(arguments.require("agent id"))
      let coordinate = try arguments.value(for: "--at").map(CLI.coordinate) ?? .origin
      let autoAdapt = arguments.flag("--auto-adapt")
      try arguments.requireEmpty()
      let placement = try runtime.addAgent(agent, at: coordinate, autoAdapt: autoAdapt)
      try WorkspaceStore.save(runtime.document, to: workspaceURL)
      print("requested: \(CLI.scalar(placement.requested.description))")
      print("actual: \(CLI.scalar(placement.actual.description))")
      print("adapted: \(placement.adapted)")
      try await handleReadyAgents(runtime: runtime, workspaceURL: workspaceURL)
    case "remove":
      let agent = try runtime.harness.resolveAgent(arguments.require("agent id"))
      try arguments.requireEmpty()
      try runtime.removeAgent(agent)
      try WorkspaceStore.save(runtime.document, to: workspaceURL)
      print("removed_from_world: \(CLI.scalar(agent.hash))")
      try await handleReadyAgents(runtime: runtime, workspaceURL: workspaceURL)
    case "profile":
      try await profileCommand(&arguments, runtime: runtime, workspaceURL: workspaceURL)
    case "retry":
      let agent = try runtime.harness.resolveAgent(arguments.require("agent id"))
      try arguments.requireEmpty()
      if let turn = try await runtime.handlePendingRequest(for: agent) {
        try WorkspaceStore.save(runtime.document, to: workspaceURL)
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
    runtime: WorkspaceRuntime,
    workspaceURL: URL
  ) async throws {
    let operation = try arguments.require("profile operation")
    let agent = try runtime.harness.resolveAgent(arguments.require("agent id"))
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
      try runtime.attachProfile(profile, to: agent)
      try WorkspaceStore.save(runtime.document, to: workspaceURL)
      print("profile: \(CLI.scalar(profile.id))")
      print("adapter: \(CLI.scalar(profile.adapterID))")
      print("latest_unread_queued: \(!agent.pendingBroadcasts.isEmpty)")
      if agent.isInWorld, !agent.pendingBroadcasts.isEmpty,
        let turn = try await runtime.handlePendingRequest(for: agent)
      {
        try WorkspaceStore.save(runtime.document, to: workspaceURL)
        print(turn.text)
      }
    case "clear":
      try arguments.requireEmpty()
      try runtime.detachProfile(from: agent)
      try WorkspaceStore.save(runtime.document, to: workspaceURL)
      print("profile: null")
    default:
      throw MikroKhorosError.command("profile operation must be set or clear")
    }
  }

  private static func shellCommand(
    _ arguments: inout Arguments,
    runtime: WorkspaceRuntime,
    workspaceURL: URL
  ) throws {
    let agent = try runtime.harness.resolveAgent(arguments.require("agent id"))
    var actions: [String] = []
    while let action = try arguments.value(for: "--action") { actions.append(action) }
    try arguments.requireEmpty()
    if !actions.isEmpty {
      let turn = try runtime.run(actions.joined(separator: "\n"), for: agent)
      try WorkspaceStore.save(runtime.document, to: workspaceURL)
      print(turn.text)
      return
    }
    print("Enter raw in-world actions. Use :quit to close the human shell.")
    while let action = readLine(strippingNewline: true) {
      if action == ":quit" || action == ":exit" { break }
      let turn = try runtime.run(action, for: agent)
      try WorkspaceStore.save(runtime.document, to: workspaceURL)
      print(turn.text)
    }
  }

  private static func messageCommand(
    _ arguments: inout Arguments,
    runtime: WorkspaceRuntime,
    workspaceURL: URL
  ) async throws {
    let operation = try arguments.require("message operation")
    let agent = try runtime.harness.resolveAgent(arguments.require("agent id"))
    let body: String
    switch operation {
    case "send":
      guard let submitted = try arguments.value(for: "--body") else {
        throw MikroKhorosError.command("message send requires --body")
      }
      body = submitted
    case "orient":
      body =
        "Meet Athena, learn what is available in the genesis district, and choose the next useful action."
    default:
      throw MikroKhorosError.command("message operation must be send or orient")
    }
    let sender = try arguments.value(for: "--sender") ?? "user"
    let thread = try arguments.value(for: "--thread") ?? "#1"
    let priorityText = try arguments.value(for: "--priority")
    let priority = try priorityText.map(BroadcastPriority.parse)
    try arguments.requireEmpty()
    let message = try runtime.sendMessage(
      to: agent,
      body: body,
      sender: sender,
      threadID: thread,
      priority: priority
    )
    try WorkspaceStore.save(runtime.document, to: workspaceURL)
    print("message: \(CLI.scalar(message.id))")
    print("recipient: \(CLI.scalar(agent.hash))")
    print("thread: \(CLI.scalar(thread))")
    print("notification_queued: \(agent.aiProfile != nil && !agent.pendingBroadcasts.isEmpty)")
    if agent.aiProfile != nil, agent.isInWorld,
      let turn = try await runtime.handlePendingRequest(for: agent)
    {
      try WorkspaceStore.save(runtime.document, to: workspaceURL)
      print(turn.text)
    }
  }

  private static func coinCommand(
    _ arguments: inout Arguments,
    runtime: WorkspaceRuntime,
    workspaceURL: URL
  ) throws {
    guard try arguments.require("coin operation") == "grant" else {
      throw MikroKhorosError.command("coin operation must be grant")
    }
    let agent = try runtime.harness.resolveAgent(arguments.require("agent id"))
    let value = try arguments.require("coin amount")
    try arguments.requireEmpty()
    let amount =
      value.lowercased() == "infinite"
      ? nil : try CLI.decimal(value, label: "coin grant")
    try runtime.grantCoin(amount, to: agent)
    try WorkspaceStore.save(runtime.document, to: workspaceURL)
    print("balance: \(CLI.scalar(formatAmount(agent.coin.balance)))")
  }

  private static func objectiveCommand(
    _ arguments: inout Arguments,
    runtime: WorkspaceRuntime,
    workspaceURL: URL
  ) async throws {
    let operation = try arguments.require("objective operation")
    switch operation {
    case "post":
      guard let title = try arguments.value(for: "--title"),
        let body = try arguments.value(for: "--body")
      else {
        throw MikroKhorosError.command("objective post requires --title and --body")
      }
      try arguments.requireEmpty()
      let objective = try runtime.postObjective(title: title, body: body)
      try WorkspaceStore.save(runtime.document, to: workspaceURL)
      print("objective:")
      print("  id: \(CLI.scalar(objective.hash))")
      print("  title: \(CLI.scalar(objective.title))")
      print("  status: \(objective.state.rawValue)")
      print("  position: \(CLI.scalar(objective.coordinate?.description ?? "unknown"))")
      try await handleReadyAgents(runtime: runtime, workspaceURL: workspaceURL)
    case "list":
      try arguments.requireEmpty()
      if runtime.objectives.isEmpty {
        print("objectives: []")
      } else {
        print("objectives:")
        for objective in runtime.objectives {
          print("  - id: \(CLI.scalar(objective.hash))")
          print("    title: \(CLI.scalar(objective.title))")
          print("    status: \(objective.state.rawValue)")
          print("    participants: \(objective.participantAgentIDs.count)")
        }
      }
    default:
      throw MikroKhorosError.command("objective operation must be post or list")
    }
  }

  private static func libraryCommand(
    _ arguments: inout Arguments,
    runtime: WorkspaceRuntime,
    workspaceURL: URL
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
      try WorkspaceStore.save(runtime.document, to: workspaceURL)
      print("document:")
      print("  id: \(CLI.scalar(document.hash))")
      print("  title: \(CLI.scalar(document.title))")
      print("  source: \(CLI.scalar(document.sourceURL))")
      print("  characters: \(document.content.count)")
      print("  position: \(CLI.scalar(document.coordinate?.description ?? "unknown"))")
      try await handleReadyAgents(runtime: runtime, workspaceURL: workspaceURL)
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

  private static func handleReadyAgents(
    runtime: WorkspaceRuntime,
    workspaceURL: URL
  ) async throws {
    for agent in runtime.harness.activeAgents
    where agent.aiProfile != nil && !agent.pendingBroadcasts.isEmpty {
      guard let turn = try await runtime.handlePendingRequest(for: agent) else { continue }
      try WorkspaceStore.save(runtime.document, to: workspaceURL)
      print("agent_turn: \(CLI.scalar(agent.hash))")
      print(turn.text)
    }
  }

  private static func worldCommand(
    _ arguments: inout Arguments,
    runtime: WorkspaceRuntime
  ) throws {
    switch try arguments.require("world operation") {
    case "show":
      try arguments.requireEmpty()
      print("world:")
      print("  id: \(CLI.scalar(runtime.harness.world.hash))")
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
          print("      loaded: \(agent.hand != nil)")
        }
      }
    case "inspect":
      let query = arguments.pop()
      try arguments.requireEmpty()
      let snapshot =
        try query.map(runtime.harness.administrativeSnapshot(for:))
        ?? runtime.harness.administrativeWorldSnapshot()
      print(try JSONOutput.render(snapshot))
    case "export":
      try arguments.requireEmpty()
      print(try JSONOutput.render(runtime.document))
    default:
      throw MikroKhorosError.command("world operation must be show, inspect, or export")
    }
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
      "  code: \(CLI.scalar(issue.code))",
      "  message: \(CLI.scalar(issue.message))",
    ]
    if !issue.suggestions.isEmpty {
      lines.append("  try:")
      for suggestion in issue.suggestions { lines.append("    - \(CLI.scalar(suggestion))") }
    }
    let data = Data((lines.joined(separator: "\n") + "\n").utf8)
    FileHandle.standardError.write(data)
  }
}
