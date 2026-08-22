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

public enum CommandKind: String, CaseIterable, Codable, Sendable {
  case help
  case initialize
  case status
  case doctor
  case configShow
  case configPath
  case configKeys
  case configGet
  case configSet
  case configReset
  case configValidate
  case adapters
  case agentCreate
  case agentList
  case agentShow
  case agentConfigure
  case agentAdd
  case agentRemove
  case agentProfileSet
  case agentProfileClear
  case agentRetry
  case agentShell
  case libraryFetch
  case libraryList
  case inventoryInstall
  case inventoryPackageAvailable
  case inventoryPackageList
  case inventoryPackageShow
  case inventoryPackageRemove
  case inventoryCreate
  case inventoryFolderCreate
  case inventoryFolderList
  case inventoryFolderShow
  case inventoryFolderRename
  case inventoryFolderMove
  case inventoryFolderDelete
  case inventoryMove
  case inventoryFork
  case inventoryList
  case inventoryShow
  case inventoryInterface
  case inventoryConfigure
  case inventoryDelete
  case inventorySecretSet
  case inventorySecretClear
  case inventoryCapabilityList
  case inventoryCapabilityGrant
  case inventoryCapabilityRevoke
  case inventoryActionList
  case inventoryActionRun
  case inventoryViewList
  case inventoryViewShow
  case inventoryDeploy
  case inventoryCopiesList
  case inventoryCopiesShow
  case inventoryCopiesDelete
  case inventoryListenEnable
  case inventoryListenDisable
  case inventoryListenList
  case inventoryReportsList
  case inventoryReportsShow
  case inventoryReportsFollow
  case inventoryRestockCreate
  case inventoryRestockList
  case inventoryRestockShow
  case inventoryRestockSet
  case inventoryRestockRun
  case inventoryRestockDelete
  case worldList
  case worldUse
  case worldCreate
  case worldRename
  case worldDelete
  case worldTemplateList
  case worldTemplateShow
  case worldTemplateStatus
  case worldTemplateApply
  case worldShow
  case worldInspect
  case worldExport
  case worldObjectList
  case worldObjectShow
  case worldObjectInterface
  case worldObjectActionList
  case worldObjectActionRun
  case worldObjectViewList
  case worldObjectViewShow
  case worldObjectMove
}

public enum CommandFieldSyntax: Equatable, Sendable {
  case positional
  case option(String)
  case flag(String)
}

public enum CommandFieldCardinality: String, Codable, Sendable {
  case required
  case optional
  case repeated
}

public enum CommandCompletion: Equatable, Sendable {
  case none
  case choices([String])
  case filesystemPath
  case configurationKey
  case adapterID
  case agentID
  case inventoryID
  case inventoryFolderID
  case packageID
  case worldObjectID
  case merchantID
  case reportID
  case restockRuleID
  case worldID
  case worldTemplateID
}

public enum CommandHistoryPolicy: String, Codable, Sendable {
  case store
  case omit
}

public enum CommandDefault: Equatable, Sendable {
  case literal(String)
  case agentMaximumActions
  case selectedWorld

  public func resolve(in context: CommandResolutionContext) -> String? {
    switch self {
    case .literal(let value): value
    case .agentMaximumActions:
      String(context.configuration.agents.maximumActionsPerResponse)
    case .selectedWorld: context.worldID
    }
  }
}

public struct CommandField: Equatable, Sendable {
  public let id: String
  public let label: String
  public let interactiveHelp: String
  public let interactiveValueAliases: [String: String]
  public let syntax: CommandFieldSyntax
  public let cardinality: CommandFieldCardinality
  public let defaultValue: CommandDefault?
  public let completion: CommandCompletion
  public let historyPolicy: CommandHistoryPolicy

  public init(
    id: String,
    label: String? = nil,
    interactiveHelp: String = "",
    interactiveValueAliases: [String: String] = [:],
    syntax: CommandFieldSyntax,
    cardinality: CommandFieldCardinality,
    defaultValue: CommandDefault? = nil,
    completion: CommandCompletion = .none,
    historyPolicy: CommandHistoryPolicy = .store
  ) {
    self.id = id
    self.label = label ?? id.replacingOccurrences(of: "-", with: " ")
    self.interactiveHelp = interactiveHelp
    self.interactiveValueAliases = interactiveValueAliases
    self.syntax = syntax
    self.cardinality = cardinality
    self.defaultValue = defaultValue
    self.completion = completion
    self.historyPolicy = historyPolicy
  }

  public var interactiveAliases: InteractiveFieldAliases {
    InteractiveFieldAliases(
      name: label,
      help: interactiveHelp,
      values: interactiveValueAliases
    )
  }

  public var cliSpelling: String {
    switch syntax {
    case .positional:
      return "<\(id)>"
    case .option(let option):
      return "\(option) <\(id)>"
    case .flag(let option):
      return option
    }
  }

  fileprivate func applying(_ aliases: InteractiveFieldAliases) -> Self {
    Self(
      id: id,
      label: aliases.name,
      interactiveHelp: aliases.help,
      interactiveValueAliases: aliases.values,
      syntax: syntax,
      cardinality: cardinality,
      defaultValue: defaultValue,
      completion: completion,
      historyPolicy: historyPolicy
    )
  }

  public static func positional(
    _ id: String,
    _ cardinality: CommandFieldCardinality = .required,
    default defaultValue: CommandDefault? = nil,
    completion: CommandCompletion = .none,
    history: CommandHistoryPolicy = .store
  ) -> Self {
    Self(
      id: id,
      syntax: .positional,
      cardinality: cardinality,
      defaultValue: defaultValue,
      completion: completion,
      historyPolicy: history
    )
  }

  public static func option(
    _ option: String,
    id: String? = nil,
    _ cardinality: CommandFieldCardinality = .optional,
    default defaultValue: CommandDefault? = nil,
    completion: CommandCompletion = .none,
    history: CommandHistoryPolicy = .store
  ) -> Self {
    Self(
      id: id ?? String(option.drop(while: { $0 == "-" })),
      syntax: .option(option),
      cardinality: cardinality,
      defaultValue: defaultValue,
      completion: completion,
      historyPolicy: history
    )
  }

  public static func flag(_ option: String, id: String? = nil) -> Self {
    Self(
      id: id ?? String(option.drop(while: { $0 == "-" })),
      syntax: .flag(option),
      cardinality: .optional,
      defaultValue: .literal("false"),
      completion: .choices(["false", "true"]),
      historyPolicy: .store
    )
  }
}

public struct CommandDefinition: Equatable, Sendable {
  public let kind: CommandKind
  public let path: [String]
  public let aliases: [[String]]
  public let summary: String
  public let longDescription: String
  public let examples: [String]
  public let fields: [CommandField]
  public let mayRequestForegroundInput: Bool
  public let requiresSelectedWorld: Bool

  public init(
    kind: CommandKind,
    path: [String],
    aliases: [[String]] = [],
    summary: String,
    longDescription: String? = nil,
    examples: [String] = [],
    fields: [CommandField] = [],
    mayRequestForegroundInput: Bool = false,
    requiresSelectedWorld: Bool = false
  ) {
    self.kind = kind
    self.path = path
    self.aliases = aliases
    self.summary = summary
    self.longDescription = longDescription ?? summary
    self.examples = examples
    self.fields = fields.map {
      $0.applying(InteractiveFieldAliasCatalog.resolve(command: kind, field: $0))
    }
    self.mayRequestForegroundInput = mayRequestForegroundInput
    self.requiresSelectedWorld = requiresSelectedWorld
  }

  public var command: String { path.joined(separator: " ") }
  public var allPaths: [[String]] { [path] + aliases }
}

public struct CommandGlobalOptions: Equatable, Codable, Sendable {
  public var configurationPath: String?
  public var worldID: String?
  public var outputMode: OutputMode?
  public var colorMode: ColorMode?

  public init(
    configurationPath: String? = nil,
    worldID: String? = nil,
    outputMode: OutputMode? = nil,
    colorMode: ColorMode? = nil
  ) {
    self.configurationPath = configurationPath
    self.worldID = worldID
    self.outputMode = outputMode
    self.colorMode = colorMode
  }

  public var arguments: [String] {
    var result: [String] = []
    if let configurationPath { result += ["--config", configurationPath] }
    if let worldID { result += ["--world", worldID] }
    if let outputMode { result += ["--output", outputMode.rawValue] }
    if let colorMode { result += ["--color", colorMode.rawValue] }
    return result
  }
}

public struct CommandResolutionContext: Sendable {
  public let configuration: RuntimeConfiguration
  public let globals: CommandGlobalOptions
  public let worldID: String?

  public init(
    configuration: RuntimeConfiguration,
    globals: CommandGlobalOptions,
    worldID: String?
  ) {
    self.configuration = configuration
    self.globals = globals
    self.worldID = worldID
  }
}

public struct InteractiveCommandSubmission: Equatable, Sendable {
  public let commandPath: String
  public let values: [String: [String]]
  public let explicitFieldIDs: Set<String>
  public let globals: CommandGlobalOptions
  public let stopsQueueOnError: Bool

  public init(
    commandPath: String,
    values: [String: [String]],
    explicitFieldIDs: Set<String> = [],
    globals: CommandGlobalOptions,
    stopsQueueOnError: Bool
  ) {
    self.commandPath = commandPath
    self.values = values
    self.explicitFieldIDs = explicitFieldIDs
    self.globals = globals
    self.stopsQueueOnError = stopsQueueOnError
  }
}

public struct ParsedCommand: Equatable, Sendable {
  public let kind: CommandKind
  public let definition: CommandDefinition
  public let globals: CommandGlobalOptions
  public let commandArguments: [String]
  public let fieldValues: [String: [String]]

  public var completeArguments: [String] { globals.arguments + commandArguments }
}

public enum ConsoleHelp {
  public static func render() -> String {
    """
    Console controls:
      :queue              Show running and pending work.
      :pause              Pause before the next queued command.
      :resume             Continue a paused queue.
      :cancel <queue-id>  Remove pending work or cancel the running command.
      :clear              Remove every pending command.
      :context            Change defaults for future submissions.
      :help               Show these controls.
      :quit               Stop input, drain the queue, and exit.
      :quit!              Clear pending work, cancel running work, and exit.

    Console keys:
      Up/Down             Select completion or recall safe history.
      Tab                 Accept the selected completion or ghost default.
      Left/Right Home/End Move within the current Unicode input.
      Backspace/Delete    Edit the current input.
      Escape              Abandon the current draft or form.
      Ctrl-C              Clear/cancel; exit from an empty idle prompt.
      Ctrl-D              Exit only while the queue is idle.

    Prefix a command path with & to pause pending FIFO work when that item fails.
    The console accepts MikroKhoros human commands, not operating-system shell syntax.
    """
  }
}

public enum CommandLineTokenizer {
  public static func tokenize(_ source: String) throws -> [String] {
    enum Quote { case single, double }
    var quote: Quote?
    var escaping = false
    var token = ""
    var tokens: [String] = []
    var tokenStarted = false

    for character in source {
      if escaping {
        token.append(character)
        tokenStarted = true
        escaping = false
        continue
      }
      if character == "\\", quote != .single {
        escaping = true
        tokenStarted = true
        continue
      }
      switch quote {
      case .single:
        if character == "'" { quote = nil } else { token.append(character) }
      case .double:
        if character == "\"" { quote = nil } else { token.append(character) }
      case nil:
        if character == "'" {
          quote = .single
          tokenStarted = true
        } else if character == "\"" {
          quote = .double
          tokenStarted = true
        } else if character.isWhitespace {
          if tokenStarted {
            tokens.append(token)
            token = ""
            tokenStarted = false
          }
        } else {
          token.append(character)
          tokenStarted = true
        }
      }
    }
    guard quote == nil else {
      throw MikroKhorosError.command("unterminated quoted value")
    }
    guard !escaping else {
      throw MikroKhorosError.command("unfinished escape at end of command")
    }
    if tokenStarted { tokens.append(token) }
    return tokens
  }
}

public enum CommandCatalog {
  public static let all: [CommandDefinition] = CommandKind.allCases.map(definition(for:))

  public static func definition(for kind: CommandKind) -> CommandDefinition {
    func id(
      _ identifier: String,
      _ cardinality: CommandFieldCardinality = .required,
      default defaultValue: CommandDefault? = nil,
      completion: CommandCompletion = .none,
      history: CommandHistoryPolicy = .store
    ) -> CommandField {
      .positional(
        identifier,
        cardinality,
        default: defaultValue,
        completion: completion,
        history: history
      )
    }
    let text = CommandCompletion.none
    let privateText = CommandHistoryPolicy.omit
    switch kind {
    case .help:
      return .init(
        kind: kind,
        path: ["help"],
        summary: "Show command help.",
        longDescription:
          "Show root, group, or command-specific help generated from the command catalog.",
        examples: ["khoros help inventory", "khoros help inventory deploy", "khoros help --all"],
        fields: [id("topic", .repeated), .flag("--all")]
      )
    case .initialize:
      return .init(
        kind: kind,
        path: ["init"],
        summary: "Create the complete default-khoros product setup without prompts."
      )
    case .status:
      return .init(kind: kind, path: ["status"], summary: "Show selected product status.")
    case .doctor:
      return .init(kind: kind, path: ["doctor"], summary: "Validate product state.")
    case .configShow:
      return .init(
        kind: kind,
        path: ["config", "show"],
        aliases: [["config"]],
        summary: "Show effective configuration."
      )
    case .configPath:
      return .init(
        kind: kind,
        path: ["config", "path"],
        aliases: [["config", "file"]],
        summary: "Print the configuration path."
      )
    case .configKeys:
      return .init(kind: kind, path: ["config", "keys"], summary: "List configuration keys.")
    case .configGet:
      return .init(
        kind: kind,
        path: ["config", "get"],
        summary: "Read one configuration value.",
        fields: [id("key", .required, completion: .configurationKey)]
      )
    case .configSet:
      return .init(
        kind: kind,
        path: ["config", "set"],
        summary: "Set one configuration value.",
        fields: [
          id("key", .required, completion: .configurationKey),
          id("value"),
        ]
      )
    case .configReset:
      return .init(
        kind: kind,
        path: ["config", "reset"],
        summary: "Reset one key or all configuration.",
        fields: [id("key", .optional, completion: .configurationKey)]
      )
    case .configValidate:
      return .init(kind: kind, path: ["config", "validate"], summary: "Validate configuration.")
    case .adapters:
      return .init(kind: kind, path: ["adapters"], summary: "List available AI adapters.")
    case .agentCreate:
      return .init(
        kind: kind,
        path: ["agent", "create"],
        summary: "Create a user-owned agent identity.",
        fields: [
          id("name"),
          .option("--max-actions", default: .agentMaximumActions),
        ]
      )
    case .agentList:
      return .init(kind: kind, path: ["agent", "list"], summary: "List user-owned agents.")
    case .agentShow:
      return .init(
        kind: kind,
        path: ["agent", "show"],
        summary: "Show one agent.",
        fields: [id("agent-id", .required, completion: .agentID)]
      )
    case .agentConfigure:
      return .init(
        kind: kind,
        path: ["agent", "configure"],
        summary: "Configure one agent.",
        fields: [
          id("agent-id", .required, completion: .agentID),
          .option("--max-actions", .required),
        ]
      )
    case .agentAdd:
      return .init(
        kind: kind,
        path: ["agent", "add"],
        summary: "Add an agent to the selected world.",
        fields: [
          id("agent-id", .required, completion: .agentID),
          .option("--at", default: .literal("0,0")),
          .flag("--auto-adapt"),
        ]
      )
    case .agentRemove:
      return .init(
        kind: kind,
        path: ["agent", "remove"],
        summary: "Remove an agent from the selected world.",
        fields: [id("agent-id", .required, completion: .agentID)]
      )
    case .agentProfileSet:
      return .init(
        kind: kind,
        path: ["agent", "profile", "set"],
        summary: "Attach or replace an AI profile.",
        fields: [
          id("agent-id", .required, completion: .agentID),
          .option("--adapter", .required, completion: .adapterID),
          .option("--model", .required),
          .option("--name"),
          .option("--endpoint", history: privateText),
          .option("--credential-env"),
          .option("--temperature"),
          .option("--max-output-tokens"),
          .option(
            "--reasoning",
            completion: .choices(["none", "low", "medium", "high", "xhigh", "max"])
          ),
        ]
      )
    case .agentProfileClear:
      return .init(
        kind: kind,
        path: ["agent", "profile", "clear"],
        summary: "Detach an AI profile.",
        fields: [id("agent-id", .required, completion: .agentID)]
      )
    case .agentRetry:
      return .init(
        kind: kind,
        path: ["agent", "retry"],
        summary: "Retry an unread agent notification.",
        fields: [id("agent-id", .required, completion: .agentID)]
      )
    case .agentShell:
      return .init(
        kind: kind,
        path: ["shell"],
        summary: "Drive one agent through its in-world action shell.",
        fields: [
          id("agent-id", .required, completion: .agentID),
          .option("--action", .repeated, history: privateText),
        ],
        mayRequestForegroundInput: true
      )
    case .libraryFetch:
      return .init(
        kind: kind,
        path: ["library", "fetch"],
        summary: "Fetch an HTTPS document into the world library.",
        fields: [
          id("https-url", .required, completion: text, history: privateText),
          .option("--title", history: privateText),
        ]
      )
    case .libraryList:
      return .init(kind: kind, path: ["library", "list"], summary: "List library documents.")
    case .inventoryInstall:
      return .init(
        kind: kind,
        path: ["inventory", "install"],
        summary: "Install an object package.",
        fields: [id("path-or-url", .required, completion: .filesystemPath, history: privateText)]
      )
    case .inventoryPackageAvailable:
      return .init(
        kind: kind,
        path: ["inventory", "package", "available"],
        summary: "List first-party object packages available to install."
      )
    case .inventoryPackageList:
      return .init(kind: kind, path: ["inventory", "package", "list"], summary: "List packages.")
    case .inventoryPackageShow:
      return .init(
        kind: kind,
        path: ["inventory", "package", "show"],
        summary: "Show one package.",
        fields: [
          id("package-id", .required, completion: .packageID),
          .option("--version"),
        ]
      )
    case .inventoryPackageRemove:
      return .init(
        kind: kind,
        path: ["inventory", "package", "remove"],
        summary: "Remove a package from the visible catalog.",
        fields: [
          id("package-id", .required, completion: .packageID),
          .option("--version"),
          .flag("--yes"),
        ],
        mayRequestForegroundInput: true
      )
    case .inventoryCreate:
      return .init(
        kind: kind,
        path: ["inventory", "create"],
        summary: "Create an Inventory object.",
        fields: [
          id("package-id", .required, completion: .packageID),
          .option("--version"),
          .option("--name"),
        ]
      )
    case .inventoryFolderCreate:
      return .init(
        kind: kind,
        path: ["inventory", "folder", "create"],
        summary: "Create one Inventory folder.",
        fields: [id("path")]
      )
    case .inventoryFolderList:
      return .init(
        kind: kind,
        path: ["inventory", "folder", "list"],
        summary: "List an Inventory folder.",
        fields: [
          id("folder", .optional, default: .literal("/"), completion: .inventoryFolderID),
          .flag("--recursive"),
        ]
      )
    case .inventoryFolderShow:
      return .init(
        kind: kind,
        path: ["inventory", "folder", "show"],
        summary: "Show one Inventory folder.",
        fields: [id("folder", .required, completion: .inventoryFolderID)]
      )
    case .inventoryFolderRename:
      return .init(
        kind: kind,
        path: ["inventory", "folder", "rename"],
        summary: "Rename one Inventory folder.",
        fields: [id("folder", .required, completion: .inventoryFolderID), id("name")]
      )
    case .inventoryFolderMove:
      return .init(
        kind: kind,
        path: ["inventory", "folder", "move"],
        summary: "Move an Inventory folder subtree.",
        fields: [
          id("folder", .required, completion: .inventoryFolderID),
          .option("--to", .required, completion: .inventoryFolderID),
        ]
      )
    case .inventoryFolderDelete:
      return .init(
        kind: kind,
        path: ["inventory", "folder", "delete"],
        summary: "Delete one empty Inventory folder.",
        fields: [
          id("folder", .required, completion: .inventoryFolderID),
          .flag("--yes"),
        ],
        mayRequestForegroundInput: true
      )
    case .inventoryMove:
      return .init(
        kind: kind,
        path: ["inventory", "move"],
        summary: "Move an Inventory source into a folder.",
        fields: [
          id("inventory-id", .required, completion: .inventoryID),
          .option("--folder", .required, completion: .inventoryFolderID),
        ]
      )
    case .inventoryFork:
      return .init(
        kind: kind,
        path: ["inventory", "fork"],
        summary: "Fork an Inventory source for the selected world.",
        fields: [
          id("inventory-id", .required, completion: .inventoryID),
          .option("--name"),
          .option("--folder", completion: .inventoryFolderID),
        ],
        requiresSelectedWorld: true
      )
    case .inventoryList:
      return .init(
        kind: kind,
        path: ["inventory", "list"],
        summary: "List Inventory objects.",
        fields: [
          .option("--package", completion: .packageID),
          .option("--folder", completion: .inventoryFolderID),
          .flag("--recursive"),
          .flag("--all"),
        ]
      )
    case .inventoryShow:
      return inventoryIDDefinition(
        kind, path: ["inventory", "show"], summary: "Show an Inventory object.")
    case .inventoryInterface:
      return inventoryIDDefinition(
        kind,
        path: ["inventory", "interface"],
        summary: "Show an object's management interface."
      )
    case .inventoryConfigure:
      return .init(
        kind: kind,
        path: ["inventory", "configure"],
        summary: "Configure an Inventory object.",
        fields: [
          id("inventory-id", .required, completion: .inventoryID),
          .option("--set", .repeated, history: privateText),
          .option("--unset", .repeated, history: privateText),
        ]
      )
    case .inventoryDelete:
      return .init(
        kind: kind,
        path: ["inventory", "delete"],
        summary: "Delete one Inventory object.",
        fields: [
          id("inventory-id", .required, completion: .inventoryID),
          .flag("--yes"),
        ],
        mayRequestForegroundInput: true
      )
    case .inventorySecretSet:
      return .init(
        kind: kind,
        path: ["inventory", "secret", "set"],
        summary: "Set an Inventory credential.",
        fields: [
          id("inventory-id", .required, completion: .inventoryID),
          id("field"),
          .flag("--stdin"),
          .option("--from-env"),
        ],
        mayRequestForegroundInput: true
      )
    case .inventorySecretClear:
      return .init(
        kind: kind,
        path: ["inventory", "secret", "clear"],
        summary: "Clear an Inventory credential reference.",
        fields: [id("inventory-id", .required, completion: .inventoryID), id("field")]
      )
    case .inventoryCapabilityList:
      return inventoryIDDefinition(
        kind,
        path: ["inventory", "capability", "list"],
        summary: "List requested and granted capabilities."
      )
    case .inventoryCapabilityGrant:
      return capabilityDefinition(kind, operation: "grant", summary: "Grant capabilities.")
    case .inventoryCapabilityRevoke:
      return capabilityDefinition(kind, operation: "revoke", summary: "Revoke capabilities.")
    case .inventoryActionList:
      return inventoryIDDefinition(
        kind,
        path: ["inventory", "action", "list"],
        summary: "List human management actions."
      )
    case .inventoryActionRun:
      return .init(
        kind: kind,
        path: ["inventory", "action", "run"],
        summary: "Run a human management action.",
        fields: [
          id("inventory-id", .required, completion: .inventoryID),
          id("action"),
          .option("--input", .repeated, history: privateText),
        ]
      )
    case .inventoryViewList:
      return inventoryIDDefinition(
        kind,
        path: ["inventory", "view", "list"],
        summary: "List human management views."
      )
    case .inventoryViewShow:
      return .init(
        kind: kind,
        path: ["inventory", "view", "show"],
        summary: "Show a human management view.",
        fields: [
          id("inventory-id", .required, completion: .inventoryID),
          id("view"),
          .option("--object", completion: .worldObjectID),
        ]
      )
    case .inventoryDeploy:
      return .init(
        kind: kind,
        path: ["inventory", "deploy"],
        summary: "Deploy a concrete object copy.",
        fields: [
          id("inventory-id", .required, completion: .inventoryID),
          .option("--to", default: .literal("world")),
          .option("--at", default: .literal("0,0")),
          .flag("--auto-adapt"),
        ]
      )
    case .inventoryCopiesList:
      return .init(
        kind: kind,
        path: ["inventory", "copies", "list"],
        summary: "List concrete descendants.",
        fields: [
          id("inventory-id", .required, completion: .inventoryID),
          .option("--deployment"),
          .flag("--listened"),
        ]
      )
    case .inventoryCopiesShow:
      return .init(
        kind: kind,
        path: ["inventory", "copies", "show"],
        summary: "Show one concrete world object.",
        fields: [id("world-object-id", .required, completion: .worldObjectID)]
      )
    case .inventoryCopiesDelete:
      return .init(
        kind: kind,
        path: ["inventory", "copies", "delete"],
        summary: "Delete selected concrete copies.",
        fields: [
          id("inventory-id", .required, completion: .inventoryID),
          .option("--object", .repeated, completion: .worldObjectID),
          .option("--deployment", .repeated),
          .flag("--all"),
          .flag("--recursive"),
          .flag("--dry-run"),
          .flag("--yes"),
        ],
        mayRequestForegroundInput: true
      )
    case .inventoryListenEnable:
      return worldObjectDefinition(
        kind, operation: "enable", summary: "Enable a human object listener.")
    case .inventoryListenDisable:
      return worldObjectDefinition(
        kind, operation: "disable", summary: "Disable a human object listener.")
    case .inventoryListenList:
      return .init(
        kind: kind,
        path: ["inventory", "listen", "list"],
        summary: "List active human listeners.",
        fields: [.option("--inventory", completion: .inventoryID)]
      )
    case .inventoryReportsList:
      return reportListDefinition(kind, operation: "list", summary: "List stored object reports.")
    case .inventoryReportsShow:
      return .init(
        kind: kind,
        path: ["inventory", "reports", "show"],
        summary: "Show one object report.",
        fields: [id("report-id", .required, completion: .reportID)]
      )
    case .inventoryReportsFollow:
      return reportListDefinition(kind, operation: "follow", summary: "Follow new object reports.")
    case .inventoryRestockCreate:
      return .init(
        kind: kind,
        path: ["inventory", "restock", "create"],
        summary: "Create an Inventory-backed restock rule.",
        fields: [
          id("inventory-id", .required, completion: .inventoryID),
          .option("--merchant", .required, completion: .merchantID),
          .option("--price", .required),
          .option("--at", default: .literal("0,0")),
          .flag("--auto-adapt"),
        ]
      )
    case .inventoryRestockList:
      return .init(
        kind: kind,
        path: ["inventory", "restock", "list"],
        summary: "List restock rules.",
        fields: [
          .option("--inventory", completion: .inventoryID),
          .option("--merchant", completion: .merchantID),
        ]
      )
    case .inventoryRestockShow:
      return restockRuleDefinition(kind, operation: "show", summary: "Show one restock rule.")
    case .inventoryRestockSet:
      return .init(
        kind: kind,
        path: ["inventory", "restock", "set"],
        summary: "Update a restock rule.",
        fields: [
          id("rule-id", .required, completion: .restockRuleID),
          .option("--price"),
          .option("--enabled", completion: .choices(["false", "true"])),
        ]
      )
    case .inventoryRestockRun:
      return .init(
        kind: kind,
        path: ["inventory", "restock", "run"],
        summary: "Run a restock rule manually.",
        fields: [
          id("rule-id", .required, completion: .restockRuleID),
          .option("--count", default: .literal("1")),
        ]
      )
    case .inventoryRestockDelete:
      return .init(
        kind: kind,
        path: ["inventory", "restock", "delete"],
        summary: "Delete a restock rule.",
        fields: [
          id("rule-id", .required, completion: .restockRuleID),
          .flag("--yes"),
        ],
        mayRequestForegroundInput: true
      )
    case .worldList:
      return .init(
        kind: kind,
        path: ["world", "list"],
        summary: "List worlds in this MikroKhoros application.",
        fields: [.flag("--all")]
      )
    case .worldUse:
      return .init(
        kind: kind,
        path: ["world", "use"],
        summary: "Select the current world.",
        fields: [id("world", .required, completion: .worldID)]
      )
    case .worldCreate:
      return .init(
        kind: kind,
        path: ["world", "create"],
        summary: "Create an independent bare or templated world.",
        fields: [
          .option("--name"),
          .option("--template", completion: .worldTemplateID),
          .flag("--yes"),
        ],
        mayRequestForegroundInput: true
      )
    case .worldRename:
      return .init(
        kind: kind,
        path: ["world", "rename"],
        summary: "Rename one world without changing its identity.",
        fields: [
          id("world", .required, completion: .worldID),
          id("name", .required),
        ]
      )
    case .worldDelete:
      return .init(
        kind: kind,
        path: ["world", "delete"],
        summary: "Delete one concrete world.",
        fields: [
          id("world", .required, completion: .worldID),
          .flag("--yes"),
        ],
        mayRequestForegroundInput: true
      )
    case .worldTemplateList:
      return .init(
        kind: kind,
        path: ["world", "template", "list"],
        summary: "List built-in world templates."
      )
    case .worldTemplateShow:
      return .init(
        kind: kind,
        path: ["world", "template", "show"],
        summary: "Show one built-in world template.",
        fields: [id("template-id", .required, completion: .worldTemplateID)]
      )
    case .worldTemplateStatus:
      return .init(
        kind: kind,
        path: ["world", "template", "status"],
        summary: "Show exact template component health in the selected world.",
        fields: [
          id(
            "template-id", .optional, default: .literal("default-khoros"),
            completion: .worldTemplateID)
        ],
        requiresSelectedWorld: true
      )
    case .worldTemplateApply:
      return .init(
        kind: kind,
        path: ["world", "template", "apply"],
        summary: "Apply or repair a built-in template in the selected world.",
        fields: [
          id("template-id", .required, completion: .worldTemplateID),
          .flag("--auto-adapt"),
          .flag("--dry-run"),
          .flag("--yes"),
        ],
        mayRequestForegroundInput: true,
        requiresSelectedWorld: true
      )
    case .worldShow:
      return .init(
        kind: kind,
        path: ["world", "show"],
        summary: "Show the selected or supplied world.",
        fields: [id("world", .optional, completion: .worldID)]
      )
    case .worldInspect:
      return .init(
        kind: kind,
        path: ["world", "inspect"],
        summary: "Inspect complete human-only world state.",
        fields: [id("agent-or-object-id", .optional, completion: .worldObjectID)]
      )
    case .worldExport:
      return .init(kind: kind, path: ["world", "export"], summary: "Export the world journal.")
    case .worldObjectList:
      return .init(
        kind: kind,
        path: ["world", "object", "list"],
        summary: "List exact concrete objects in the selected world.",
        fields: [
          .option("--container", completion: .worldObjectID),
          .option("--type"),
          .option("--package", completion: .packageID),
          .option("--inventory", completion: .inventoryID),
          .option("--deployment"),
        ]
      )
    case .worldObjectShow:
      return .init(
        kind: kind,
        path: ["world", "object", "show"],
        summary: "Show one exact world object.",
        fields: [id("world-object-id", .required, completion: .worldObjectID)]
      )
    case .worldObjectInterface:
      return .init(
        kind: kind,
        path: ["world", "object", "interface"],
        summary: "Show exact-instance management controls.",
        fields: [id("world-object-id", .required, completion: .worldObjectID)]
      )
    case .worldObjectActionList:
      return .init(
        kind: kind,
        path: ["world", "object", "action", "list"],
        summary: "List actions for one exact world object.",
        fields: [id("world-object-id", .required, completion: .worldObjectID)]
      )
    case .worldObjectActionRun:
      return .init(
        kind: kind,
        path: ["world", "object", "action", "run"],
        summary: "Run a human action on one exact world object.",
        fields: [
          id("world-object-id", .required, completion: .worldObjectID),
          id("action"),
          .option("--input", .repeated, history: privateText),
        ]
      )
    case .worldObjectViewList:
      return .init(
        kind: kind,
        path: ["world", "object", "view", "list"],
        summary: "List views for one exact world object.",
        fields: [id("world-object-id", .required, completion: .worldObjectID)]
      )
    case .worldObjectViewShow:
      return .init(
        kind: kind,
        path: ["world", "object", "view", "show"],
        summary: "Show a view for one exact world object.",
        fields: [
          id("world-object-id", .required, completion: .worldObjectID),
          id("view"),
        ]
      )
    case .worldObjectMove:
      return .init(
        kind: kind,
        path: ["world", "object", "move"],
        summary: "Move one ordinary concrete world object.",
        fields: [
          id("world-object-id", .required, completion: .worldObjectID),
          .option("--to", .required),
          .option("--at", default: .literal("0,0")),
          .flag("--auto-adapt"),
        ]
      )
    }
  }

  public static func find(path source: String) -> CommandDefinition? {
    let path = source.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    return all.first { definition in definition.allPaths.contains(path) }
  }

  public static func completions(for source: String, limit: Int) -> [CommandDefinition] {
    let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return
      all
      .compactMap { definition -> (Int, CommandDefinition)? in
        let command = definition.command.lowercased()
        if normalized.isEmpty { return (2, definition) }
        if command == normalized { return (0, definition) }
        if command.hasPrefix(normalized) { return (1, definition) }
        let segments = normalized.split(separator: " ")
        let commandSegments = command.split(separator: " ")
        guard zip(segments, commandSegments).allSatisfy({ $1.hasPrefix($0) }) else { return nil }
        return (2, definition)
      }
      .sorted {
        if $0.0 != $1.0 { return $0.0 < $1.0 }
        return $0.1.command < $1.1.command
      }
      .prefix(max(1, limit))
      .map(\.1)
  }

  public static func renderHelp(path: [String] = [], includeAll: Bool = false) -> String {
    var lines = [
      "MikroKhoros — persistent multi-agent world runtime",
      "",
      "Usage:",
      "  khoros [--config <file>] [--world <world-selector>]",
      "         [--output <auto|human|yaml|json>] [--color <auto|always|never>] <command>",
      "  khoros [global-options] console",
    ]
    if let leaf = all.first(where: { $0.path == path || $0.aliases.contains(path) }), !path.isEmpty
    {
      lines += ["", "Usage:", "  khoros \(usage(for: leaf))", "", leaf.longDescription]
      if !leaf.fields.isEmpty {
        lines += ["", "Arguments and options:"]
        for field in leaf.fields {
          let suffix = field.defaultValue == nil ? "" : " (default is resolved at submission)"
          lines.append("  \(field.cliSpelling)  \(field.cardinality)\(suffix)")
          lines.append("      Interactive: \(field.label) — \(field.interactiveHelp)")
          if !field.interactiveValueAliases.isEmpty {
            let values = field.interactiveValueAliases.sorted { $0.key < $1.key }.map {
              "\($0.value) (\($0.key))"
            }.joined(separator: ", ")
            lines.append("      Interactive values: \(values)")
          }
        }
      }
      let examples = leaf.examples.isEmpty ? ["khoros \(usage(for: leaf))"] : leaf.examples
      lines += ["", "Examples:"] + examples.map { "  \($0)" }
      lines += [
        "", "Selectors:",
        "  Runtime entities accept a complete ID, a unique prefix of at least four",
        "  characters, or a unique case-insensitive exact name in the selected scope.",
        "", "Output:",
        "  --output auto|human|yaml|json    --color auto|always|never",
      ]
      return lines.joined(separator: "\n")
    }

    let matching =
      includeAll
      ? all
      : all.filter { definition in
        path.isEmpty || definition.path.starts(with: path)
      }
    if !path.isEmpty, matching.isEmpty {
      let supplied = path.joined(separator: " ")
      let suggestions = nearestCommands(to: supplied).map(\.command).joined(separator: ", ")
      return "Unknown help topic '\(supplied)'."
        + (suggestions.isEmpty ? "" : " Try: \(suggestions)")
    }
    lines += ["", path.isEmpty ? "Command groups:" : "Commands:"]
    if path.isEmpty, !includeAll {
      let standalone = Set(["help", "init", "status", "doctor", "adapters", "console"])
      let groups = Dictionary(grouping: all, by: { $0.path.first ?? "" })
      for group in groups.keys.sorted() {
        let summary =
          standalone.contains(group)
          ? (groups[group]?.first?.summary ?? "")
          : "\(groups[group]?.count ?? 0) "
            + ((groups[group]?.count ?? 0) == 1 ? "command" : "commands")
        lines.append("  \(group.padding(toLength: 12, withPad: " ", startingAt: 0)) \(summary)")
      }
      lines += ["", "Run `khoros help <group>` or `khoros help --all` for more."]
    } else {
      for definition in matching {
        lines.append("  \(usage(for: definition))")
        lines.append("      \(definition.summary)")
      }
    }
    if path.isEmpty {
      lines += [
        "", "Global options:",
        "  --config <file>      Select configuration.",
        "  --world <selector>   Select a world by ID, unique prefix, or unique name.",
        "  --output <mode>      auto, human, yaml, or json.",
        "  --color <mode>       auto, always, or never.",
        "", "Per-user files live under ~/.mikrokhoros.",
      ]
    }
    return lines.joined(separator: "\n")
  }

  public static func nearestCommands(to source: String, limit: Int = 3) -> [CommandDefinition] {
    all.sorted {
      let left = editDistance(source.lowercased(), $0.command.lowercased())
      let right = editDistance(source.lowercased(), $1.command.lowercased())
      return left == right ? $0.command < $1.command : left < right
    }.prefix(max(0, limit)).map { $0 }
  }

  static func distance(_ left: String, _ right: String) -> Int {
    editDistance(left.lowercased(), right.lowercased())
  }

  private static func usage(for definition: CommandDefinition) -> String {
    var usage = definition.command
    for field in definition.fields {
      let value: String
      switch field.syntax {
      case .positional: value = "<\(field.id)>"
      case .option(let option): value = "\(option) <\(field.id)>"
      case .flag(let option): value = option
      }
      switch field.cardinality {
      case .required: usage += " \(value)"
      case .optional: usage += " [\(value)]"
      case .repeated: usage += " [\(value)]..."
      }
    }
    return usage
  }

  private static func editDistance(_ left: String, _ right: String) -> Int {
    let a = Array(left)
    let b = Array(right)
    var previous = Array(0...b.count)
    for (row, lhs) in a.enumerated() {
      var current = [row + 1]
      for (column, rhs) in b.enumerated() {
        current.append(
          min(
            current[column] + 1,
            previous[column + 1] + 1,
            previous[column] + (lhs == rhs ? 0 : 1)
          ))
      }
      previous = current
    }
    return previous[b.count]
  }

  private static func inventoryIDDefinition(
    _ kind: CommandKind,
    path: [String],
    summary: String
  ) -> CommandDefinition {
    .init(
      kind: kind,
      path: path,
      summary: summary,
      fields: [.positional("inventory-id", completion: .inventoryID)]
    )
  }

  private static func capabilityDefinition(
    _ kind: CommandKind,
    operation: String,
    summary: String
  ) -> CommandDefinition {
    .init(
      kind: kind,
      path: ["inventory", "capability", operation],
      summary: summary,
      fields: [
        .positional("inventory-id", completion: .inventoryID),
        .positional("capability", .repeated),
      ]
    )
  }

  private static func worldObjectDefinition(
    _ kind: CommandKind,
    operation: String,
    summary: String
  ) -> CommandDefinition {
    .init(
      kind: kind,
      path: ["inventory", "listen", operation],
      summary: summary,
      fields: [.positional("world-object-id", completion: .worldObjectID)]
    )
  }

  private static func reportListDefinition(
    _ kind: CommandKind,
    operation: String,
    summary: String
  ) -> CommandDefinition {
    .init(
      kind: kind,
      path: ["inventory", "reports", operation],
      summary: summary,
      fields: [
        .option("--inventory", completion: .inventoryID),
        .option("--object", completion: .worldObjectID),
        .option("--type"),
        .option("--limit", default: .literal("100")),
      ]
    )
  }

  private static func restockRuleDefinition(
    _ kind: CommandKind,
    operation: String,
    summary: String
  ) -> CommandDefinition {
    .init(
      kind: kind,
      path: ["inventory", "restock", operation],
      summary: summary,
      fields: [.positional("rule-id", completion: .restockRuleID)]
    )
  }
}

public enum CommandParser {
  public static func parse(_ arguments: [String]) throws -> ParsedCommand {
    let (globals, commandArguments) = try splitGlobals(arguments)
    if let removed = tombstonePrefix(for: commandArguments) {
      throw MikroKhorosError.runtime(
        removed.code,
        removed.message,
        suggestions: [
          "use world object interface <object-id>",
          "use world object action run <object-id> <action>",
          "use world object view show <object-id> <view>",
        ]
      )
    }
    let candidates = CommandCatalog.all.compactMap { definition -> ([String], CommandDefinition)? in
      definition.allPaths
        .filter { commandArguments.starts(with: $0) }
        .max(by: { $0.count < $1.count })
        .map { ($0, definition) }
    }
    guard let match = candidates.max(by: { $0.0.count < $1.0.count }) else {
      let command = commandArguments.joined(separator: " ")
      let recognized = longestRecognizedPrefix(commandArguments)
      let nearby = CommandCatalog.nearestCommands(to: command)
        .map(\.command).joined(separator: ", ")
      var message = command.isEmpty ? "missing command" : "unknown command '\(command)'"
      if !recognized.isEmpty { message += "; recognized prefix: '\(recognized)'" }
      if !nearby.isEmpty { message += "; did you mean: \(nearby)?" }
      throw MikroKhorosError.command(
        message
      )
    }
    let fieldValues = try parseFieldValues(
      Array(commandArguments.dropFirst(match.0.count)),
      definition: match.1
    )
    return ParsedCommand(
      kind: match.1.kind,
      definition: match.1,
      globals: globals,
      commandArguments: commandArguments,
      fieldValues: fieldValues
    )
  }

  private static func parseFieldValues(
    _ arguments: [String],
    definition: CommandDefinition
  ) throws -> [String: [String]] {
    let optionFields = Dictionary(
      uniqueKeysWithValues: definition.fields.compactMap { field -> (String, CommandField)? in
        switch field.syntax {
        case .option(let option), .flag(let option): (option, field)
        case .positional: nil
        }
      }
    )
    var values: [String: [String]] = [:]
    var positionalValues: [String] = []
    var index = 0
    while index < arguments.count {
      let token = arguments[index]
      guard let field = optionFields[token] else {
        if token.hasPrefix("--") {
          let known = optionFields.keys.min {
            CommandCatalog.distance(token, $0) < CommandCatalog.distance(token, $1)
          }
          let suggestion = known.map { "; did you mean '\($0)'?" } ?? ""
          throw MikroKhorosError.command("unknown argument '\(token)'\(suggestion)")
        }
        positionalValues.append(token)
        index += 1
        continue
      }
      if field.cardinality != .repeated, values[field.id] != nil {
        throw MikroKhorosError.command("duplicate argument '\(token)'")
      }
      switch field.syntax {
      case .flag:
        values[field.id, default: []].append("true")
        index += 1
      case .option:
        guard index + 1 < arguments.count else {
          throw MikroKhorosError.command("\(token) requires a value")
        }
        values[field.id, default: []].append(arguments[index + 1])
        index += 2
      case .positional:
        preconditionFailure("positional fields are not option lookup entries")
      }
    }

    var positionalIndex = 0
    let positionalFields = definition.fields.filter {
      if case .positional = $0.syntax { return true }
      return false
    }
    for field in positionalFields {
      if field.cardinality == .repeated {
        let remaining = Array(positionalValues.dropFirst(positionalIndex))
        if !remaining.isEmpty { values[field.id] = remaining }
        positionalIndex = positionalValues.count
      } else if positionalIndex < positionalValues.count {
        values[field.id] = [positionalValues[positionalIndex]]
        positionalIndex += 1
      }
    }
    if positionalIndex < positionalValues.count {
      throw MikroKhorosError.command(
        "unknown argument '\(positionalValues[positionalIndex])'"
      )
    }
    for field in definition.fields where field.cardinality == .required {
      guard values[field.id]?.isEmpty == false else {
        let label: String
        switch field.syntax {
        case .positional: label = field.label
        case .option(let option), .flag(let option): label = option
        }
        throw MikroKhorosError.command("missing \(label)")
      }
    }
    for field in definition.fields {
      guard case .choices(let choices) = field.completion,
        let supplied = values[field.id]
      else {
        continue
      }
      guard supplied.allSatisfy(choices.contains) else {
        throw MikroKhorosError.command(
          "\(field.label) must be one of \(choices.joined(separator: ", "))"
        )
      }
    }
    return values
  }

  public static func arguments(
    for submission: InteractiveCommandSubmission
  ) throws -> [String] {
    guard let definition = CommandCatalog.find(path: submission.commandPath) else {
      return submission.globals.arguments
        + submission.commandPath.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
    var arguments = submission.globals.arguments + definition.path
    for field in definition.fields {
      let values = submission.values[field.id] ?? []
      switch field.syntax {
      case .positional:
        arguments += values.filter { !$0.isEmpty }
      case .option(let option):
        for value in values where !value.isEmpty { arguments += [option, value] }
      case .flag(let option):
        guard let raw = values.last, !raw.isEmpty else { continue }
        switch raw.lowercased() {
        case "true", "yes", "1": arguments.append(option)
        case "false", "no", "0": break
        default: arguments += [option, raw]
        }
      }
    }
    return arguments
  }

  private static func isTruthy(_ value: String?) -> Bool {
    guard let value else { return false }
    return ["true", "yes", "1"].contains(value.lowercased())
  }

  public static func splitGlobals(
    _ arguments: [String]
  ) throws -> (CommandGlobalOptions, [String]) {
    var globals = CommandGlobalOptions()
    var remaining: [String] = []
    var index = 0
    while index < arguments.count {
      let value = arguments[index]
      let pair: (String, String?)
      if let separator = value.firstIndex(of: "="), value.hasPrefix("--") {
        pair = (String(value[..<separator]), String(value[value.index(after: separator)...]))
      } else {
        pair = (value, nil)
      }
      if pair.0 == "--workspace" {
        throw MikroKhorosError.runtime(
          "cli.option_removed",
          "--workspace is no longer supported",
          suggestions: [
            "create a schema-7 world with `khoros world create`",
            "select a world with `--world <world>` or `khoros world use <world>`",
          ]
        )
      }
      if ["--config", "--world", "--output", "--color"].contains(pair.0) {
        let supplied: String
        if let inline = pair.1 {
          guard !inline.isEmpty else {
            throw MikroKhorosError.command("\(pair.0) requires a value")
          }
          supplied = inline
        } else {
          guard index + 1 < arguments.count else {
            throw MikroKhorosError.command("\(pair.0) requires a value")
          }
          supplied = arguments[index + 1]
        }
        switch pair.0 {
        case "--config": globals.configurationPath = supplied
        case "--world": globals.worldID = supplied
        case "--output":
          guard let mode = OutputMode(rawValue: supplied) else {
            throw MikroKhorosError.command("--output must be auto, human, yaml, or json")
          }
          globals.outputMode = mode
        case "--color":
          guard let mode = ColorMode(rawValue: supplied) else {
            throw MikroKhorosError.command("--color must be auto, always, or never")
          }
          globals.colorMode = mode
        default: break
        }
        index += pair.1 == nil ? 2 : 1
      } else {
        remaining.append(value)
        index += 1
      }
    }
    return (globals, remaining)
  }

  private static func tombstonePrefix(
    for arguments: [String]
  ) -> (code: String, message: String)? {
    let removed: [([String], String)] = [
      (
        "message send".split(separator: " ").map(String.init),
        "message send is no longer supported; use world-object APIs in `world object action`, "
          + "`world object view`, and `world object interface`"
      ),
      (
        "message orient".split(separator: " ").map(String.init),
        "message orient is no longer supported; use world-object APIs in `world object action`, "
          + "`world object view`, and `world object interface`"
      ),
      (
        "coin grant".split(separator: " ").map(String.init),
        "coin grant is no longer supported; use world-object APIs in `world object action`, "
          + "`world object view`, and `world object interface`"
      ),
      (
        "objective post".split(separator: " ").map(String.init),
        "objective post is no longer supported; use world-object APIs in `world object action`, "
          + "`world object view`, and `world object interface`"
      ),
      (
        "objective list".split(separator: " ").map(String.init),
        "objective list is no longer supported; use world-object APIs in `world object action`, "
          + "`world object view`, and `world object interface`"
      ),
    ]
    return removed.first(where: { arguments.starts(with: $0.0) }).map {
      ("command.removed", "\($0.1)")
    }
  }

  private static func longestRecognizedPrefix(_ arguments: [String]) -> String {
    var best: [String] = []
    for definition in CommandCatalog.all {
      for path in definition.allPaths {
        var matched: [String] = []
        for (supplied, expected) in zip(arguments, path) {
          guard supplied == expected else { break }
          matched.append(supplied)
        }
        if matched.count > best.count { best = matched }
      }
    }
    return best.joined(separator: " ")
  }
}
