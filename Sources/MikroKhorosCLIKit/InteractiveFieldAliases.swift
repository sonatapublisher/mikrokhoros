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

public struct InteractiveFieldAliases: Equatable, Sendable {
  public let name: String
  public let help: String
  public let values: [String: String]

  public init(name: String, help: String, values: [String: String] = [:]) {
    self.name = name
    self.help = help
    self.values = values
  }

  public func displayValue(for canonicalValue: String) -> String {
    values[canonicalValue] ?? canonicalValue
  }

  public func canonicalValue(for interactiveValue: String) -> String? {
    if let canonical = values.keys.first(where: {
      $0.caseInsensitiveCompare(interactiveValue) == .orderedSame
    }) {
      return canonical
    }
    return values.first(where: {
      $0.value.caseInsensitiveCompare(interactiveValue) == .orderedSame
    })?.key
  }
}

public enum InteractiveFieldAliasCatalog {
  public static func resolve(
    command: CommandKind,
    field: CommandField
  ) -> InteractiveFieldAliases {
    if let specialized = specialized(command: command, field: field) { return specialized }

    switch field.id {
    case "action":
      return aliases("management action", "Object-defined human management action to run.")
    case "adapter":
      return aliases("AI adapter", "Provider or local adapter used for this agent profile.")
    case "agent-id":
      return aliases("agent", "Agent name, complete ID, or unique ID prefix.")
    case "agent-or-object-id":
      return aliases(
        "inspection target", "Optional agent or world-object name, complete ID, or unique prefix.")
    case "all":
      return flag(
        "scope", "Choose whether to include every item allowed by this command.",
        off: "current selection", on: "all items")
    case "at":
      return aliases("coordinate", "Local destination coordinate written as x,y.")
    case "available-port":
      return flag(
        "port selection",
        "Choose whether the operating system selects an available loopback port for this launch.",
        off: "stable or custom port",
        on: "available port"
      )
    case "auto-adapt":
      return flag(
        "occupied-coordinate behavior",
        "Choose how placement behaves when the requested coordinate is occupied.",
        off: "require exact coordinate", on: "use nearest free cell")
    case "body":
      return aliases("message body", "Text carried by the message or record.")
    case "capability":
      return aliases("capability", "Requested package capability to grant or revoke.")
    case "container":
      return aliases("container", "Container used to limit the object listing.")
    case "count":
      return aliases("copy count", "Positive number of concrete copies to create.")
    case "credential-env":
      return aliases(
        "credential environment variable",
        "Environment-variable name read only when the provider request is made.")
    case "deployment":
      return aliases("deployment", "Deployment ID used to filter or select concrete copies.")
    case "dry-run":
      return flag(
        "execution mode", "Choose whether to preview the operation or apply it.",
        off: "apply changes", on: "preview only")
    case "enabled":
      return aliases(
        "restock rule state", "Choose whether automatic restocking is enabled.",
        values: ["false": "disabled", "true": "enabled"])
    case "endpoint":
      return aliases("provider endpoint", "Optional HTTPS endpoint for the selected AI adapter.")
    case "field":
      return aliases("secret field", "Package-defined secret configuration field.")
    case "folder":
      return aliases(
        "Inventory folder", "Inventory folder path, name, complete ID, or unique prefix.")
    case "from-env":
      return aliases(
        "secret environment variable", "Read the secret from this environment variable now.")
    case "https-url":
      return aliases("document URL", "HTTPS URL of the document to add to the Library.")
    case "input":
      return aliases("action input", "Package-defined field=value input for the management action.")
    case "inventory":
      return aliases("Inventory source", "Inventory object name, complete ID, or unique prefix.")
    case "inventory-id":
      return aliases("Inventory object", "Inventory object name, complete ID, or unique prefix.")
    case "key":
      return aliases("configuration key", "Installed-product configuration key.")
    case "limit":
      return aliases("result limit", "Maximum number of matching records to return.")
    case "listened":
      return flag(
        "listener filter", "Choose whether to return only copies with an enabled listener.",
        off: "all copies", on: "listened copies only")
    case "max-actions":
      return aliases(
        "maximum actions per response", "Maximum in-world actions accepted from one model response."
      )
    case "max-output-tokens":
      return aliases("maximum output tokens", "Optional provider output-token ceiling.")
    case "merchant":
      return aliases("merchant", "Merchant object name, complete ID, or unique prefix.")
    case "model":
      return aliases("model", "Model identifier understood by the selected adapter.")
    case "name":
      return aliases("name", "Human-facing name for the new or updated record.")
    case "object":
      return aliases("world object", "Concrete world-object name, complete ID, or unique prefix.")
    case "package":
      return aliases("package filter", "Show only Inventory objects created from this package.")
    case "package-id":
      return aliases("object package", "Installed package identifier.")
    case "path":
      return aliases("path", "Path used by this command.")
    case "path-or-url":
      return aliases("package source", "Local package path, built-in source, or HTTPS URL.")
    case "price":
      return aliases("price", "Credit price assigned to newly stocked copies.")
    case "priority":
      return aliases("notification priority", "Optional !, !!, or !!! notification label.")
    case "port":
      return aliases("web port", "Exact loopback TCP port from 1 through 65535.")
    case "reasoning":
      return aliases("reasoning effort", "Reasoning-effort value supported by the selected model.")
    case "recursive":
      return flag(
        "contained items", "Choose whether the operation includes nested contents.",
        off: "selected item only", on: "include contents")
    case "report-id":
      return aliases("report", "Report complete ID or unique ID prefix.")
    case "rule-id":
      return aliases("restock rule", "Restock-rule complete ID or unique ID prefix.")
    case "sender":
      return aliases("sender name", "Human-facing sender stored with the Messenger message.")
    case "set":
      return aliases("configuration assignment", "Non-secret field=value assignment to apply.")
    case "stdin":
      return flag(
        "secret input source", "Choose whether to read the secret from standard input.",
        off: "use hidden prompt", on: "read standard input")
    case "temperature":
      return aliases("temperature", "Optional sampling temperature for the provider.")
    case "template":
      return aliases("world template", "Built-in template to apply while creating the world.")
    case "template-id":
      return aliases("world template", "Built-in world-template identifier.")
    case "thread":
      return aliases("conversation thread", "Messenger thread receiving the message.")
    case "title":
      return aliases("title", "Human-facing title for the message, objective, or document.")
    case "to":
      return aliases("destination", "Destination container, world, agent, or Inventory folder.")
    case "topic":
      return aliases("help topic", "Command or command group to explain.")
    case "type":
      return aliases("object type", "Object-type filter.")
    case "unset":
      return aliases("field to clear", "Non-secret configuration field to remove.")
    case "value":
      return aliases("configuration value", "New value for the selected configuration key.")
    case "version":
      return aliases("package version", "Semantic package version.")
    case "view":
      return aliases("management view", "Object-defined human management view to render.")
    case "world":
      return aliases("world", "World name, complete ID, or unique ID prefix.")
    case "world-object-id":
      return aliases("world object", "World-object name, complete ID, or unique ID prefix.")
    case "yes":
      return flag(
        "confirmation behavior",
        "When this operation requires confirmation, choose whether it asks you first or proceeds without another prompt.",
        off: "ask me first", on: "proceed without asking")
    default:
      preconditionFailure(
        "missing interactive aliases for \(command.rawValue).\(field.id)"
      )
    }
  }

  private static func specialized(
    command: CommandKind,
    field: CommandField
  ) -> InteractiveFieldAliases? {
    switch (command, field.id) {
    case (.agentCreate, "name"):
      aliases("agent name", "Human-facing name for the new user-owned agent.")
    case (.agentProfileSet, "name"):
      aliases("profile name", "Optional human-facing name for this AI profile.")
    case (.agentShell, "action"):
      aliases("world action", "Raw in-world action to execute as the selected agent.")
    case (.help, "all"):
      flag(
        "help scope", "Choose whether help includes every command rather than the current scope.",
        off: "current scope", on: "all commands")
    case (.inventoryCreate, "name"), (.inventoryFork, "name"):
      aliases("Inventory object name", "Optional human-facing name for the Inventory source.")
    case (.inventoryFolderCreate, "path"):
      aliases("new Inventory folder", "Hierarchical path for the folder to create.")
    case (.inventoryFolderList, "recursive"):
      flag(
        "listing depth", "Choose whether to list only direct children or all descendants.",
        off: "direct children", on: "all descendants")
    case (.inventoryFolderRename, "name"):
      aliases("new folder name", "New name inside the folder's current parent.")
    case (.inventoryFolderMove, "to"):
      aliases("new parent folder", "Inventory folder that will become the subtree's parent.")
    case (.inventoryList, "all"):
      flag(
        "record visibility", "Choose whether logically deleted lineage records are included.",
        off: "active records", on: "include deleted records")
    case (.inventoryCopiesDelete, "all"):
      flag(
        "deletion scope", "Choose whether to delete every descendant in the selected world.",
        off: "selected copies", on: "all descendants")
    case (.inventoryCopiesDelete, "recursive"):
      flag(
        "container contents",
        "Choose whether deletion includes objects inside selected containers.",
        off: "keep contents", on: "delete contents")
    case (.inventoryViewShow, "object"):
      aliases("world-object scope", "Optional concrete copy used to scope the Inventory view.")
    case (.inventoryCopiesDelete, "object"):
      aliases("copy to delete", "Concrete world-object name, complete ID, or unique prefix.")
    case (.inventoryDeploy, "to"), (.worldObjectMove, "to"):
      aliases("world destination", "Root world, container, or agent backpack destination.")
    case (.libraryFetch, "title"):
      aliases("document title", "Optional title shown for the fetched Library document.")
    case (.worldCreate, "name"):
      aliases("world name", "Optional human-facing name for the new world.")
    default:
      nil
    }
  }

  private static func aliases(
    _ name: String,
    _ help: String,
    values: [String: String] = [:]
  ) -> InteractiveFieldAliases {
    InteractiveFieldAliases(name: name, help: help, values: values)
  }

  private static func flag(
    _ name: String,
    _ help: String,
    off: String,
    on: String
  ) -> InteractiveFieldAliases {
    aliases(name, help, values: ["false": off, "true": on])
  }
}

public enum InteractiveGlobalField: String, CaseIterable, Sendable {
  case configuration
  case world
  case output
  case color

  public var cliSpelling: String {
    switch self {
    case .configuration: "--config"
    case .world: "--world"
    case .output: "--output"
    case .color: "--color"
    }
  }

  public var interactiveAliases: InteractiveFieldAliases {
    switch self {
    case .configuration:
      InteractiveFieldAliases(
        name: "configuration file",
        help: "Configuration file used by future console submissions.",
        values: ["default": "use default configuration"]
      )
    case .world:
      InteractiveFieldAliases(
        name: "world",
        help: "World name, complete ID, or unique ID prefix used as the selected world context.",
        values: ["default": "use current world"]
      )
    case .output:
      InteractiveFieldAliases(
        name: "output format",
        help: "Presentation format used by future console submissions.",
        values: [
          "default": "use product setting",
          "auto": "choose for terminal or pipe",
          "human": "human readable",
          "yaml": "YAML",
          "json": "JSON",
        ]
      )
    case .color:
      InteractiveFieldAliases(
        name: "color behavior",
        help: "ANSI color behavior used by future console submissions.",
        values: [
          "default": "use product setting",
          "auto": "detect terminal support",
          "always": "always use color",
          "never": "never use color",
        ]
      )
    }
  }

  public var canonicalChoices: [String] {
    switch self {
    case .configuration, .world:
      ["default"]
    case .output:
      ["default"] + OutputMode.allCases.map(\.rawValue)
    case .color:
      ["default"] + ColorMode.allCases.map(\.rawValue)
    }
  }
}
