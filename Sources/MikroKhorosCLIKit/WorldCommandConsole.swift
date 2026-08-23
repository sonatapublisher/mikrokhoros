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
import MikroKhorosServices

public enum WorldCommandConsolePolicy {
  /// This switch is intentionally exhaustive. A new human command cannot
  /// become browser-callable until its World-page boundary is reviewed.
  public static func allows(_ kind: CommandKind) -> Bool {
    switch kind {
    case .help, .worldTemplateStatus, .worldShow, .worldObjectList,
      .worldObjectViewList, .worldObjectMove:
      true
    case .web, .initialize, .status, .doctor, .configShow, .configPath,
      .configKeys, .configGet, .configSet, .configReset, .configValidate,
      .adapters, .agentCreate, .agentList, .agentShow, .agentConfigure,
      .agentAdd, .agentRemove, .agentProfileSet, .agentProfileClear,
      .agentRetry, .agentShell, .libraryFetch, .libraryList,
      .inventoryInstall, .inventoryPackageAvailable, .inventoryPackageList,
      .inventoryPackageShow, .inventoryPackageRemove, .inventoryCreate,
      .inventoryFolderCreate, .inventoryFolderList, .inventoryFolderShow,
      .inventoryFolderRename, .inventoryFolderMove, .inventoryFolderDelete,
      .inventoryMove, .inventoryFork, .inventoryList, .inventoryShow,
      .inventoryInterface, .inventoryConfigure, .inventoryDelete,
      .inventorySecretSet, .inventorySecretClear, .inventoryCapabilityList,
      .inventoryCapabilityGrant, .inventoryCapabilityRevoke,
      .inventoryActionList, .inventoryActionRun, .inventoryViewList,
      .inventoryViewShow, .inventoryDeploy, .inventoryCopiesList,
      .inventoryCopiesShow, .inventoryCopiesDelete, .inventoryListenEnable,
      .inventoryListenDisable, .inventoryListenList, .inventoryReportsList,
      .inventoryReportsShow, .inventoryReportsFollow,
      .inventoryRestockCreate, .inventoryRestockList, .inventoryRestockShow,
      .inventoryRestockSet, .inventoryRestockRun, .inventoryRestockDelete,
      .worldList, .worldUse, .worldCreate, .worldRename, .worldDelete,
      .worldTemplateList, .worldTemplateShow, .worldTemplateApply,
      .worldInspect, .worldExport, .worldObjectShow, .worldObjectInterface,
      .worldObjectActionList, .worldObjectActionRun, .worldObjectViewShow:
      false
    }
  }

  public static func refreshesWorld(_ kind: CommandKind) -> Bool {
    switch kind {
    case .worldObjectMove:
      true
    case .help, .web, .initialize, .status, .doctor, .configShow, .configPath,
      .configKeys, .configGet, .configSet, .configReset, .configValidate,
      .adapters, .agentCreate, .agentList, .agentShow, .agentConfigure,
      .agentAdd, .agentRemove, .agentProfileSet, .agentProfileClear,
      .agentRetry, .agentShell, .libraryFetch, .libraryList,
      .inventoryInstall, .inventoryPackageAvailable, .inventoryPackageList,
      .inventoryPackageShow, .inventoryPackageRemove, .inventoryCreate,
      .inventoryFolderCreate, .inventoryFolderList, .inventoryFolderShow,
      .inventoryFolderRename, .inventoryFolderMove, .inventoryFolderDelete,
      .inventoryMove, .inventoryFork, .inventoryList, .inventoryShow,
      .inventoryInterface, .inventoryConfigure, .inventoryDelete,
      .inventorySecretSet, .inventorySecretClear, .inventoryCapabilityList,
      .inventoryCapabilityGrant, .inventoryCapabilityRevoke,
      .inventoryActionList, .inventoryActionRun, .inventoryViewList,
      .inventoryViewShow, .inventoryDeploy, .inventoryCopiesList,
      .inventoryCopiesShow, .inventoryCopiesDelete, .inventoryListenEnable,
      .inventoryListenDisable, .inventoryListenList, .inventoryReportsList,
      .inventoryReportsShow, .inventoryReportsFollow,
      .inventoryRestockCreate, .inventoryRestockList, .inventoryRestockShow,
      .inventoryRestockSet, .inventoryRestockRun, .inventoryRestockDelete,
      .worldList, .worldUse, .worldCreate, .worldRename, .worldDelete,
      .worldTemplateList, .worldTemplateShow, .worldTemplateStatus,
      .worldTemplateApply, .worldShow, .worldInspect, .worldExport,
      .worldObjectList, .worldObjectShow, .worldObjectInterface,
      .worldObjectActionList, .worldObjectActionRun, .worldObjectViewList,
      .worldObjectViewShow:
      false
    }
  }
}

/// In-process bridge from the World host to the canonical human-command path.
/// It is deliberately finite, exact-world scoped, and noninteractive.
public final class CLIWorldCommandConsoleService: WorldCommandConsoleServing,
  @unchecked Sendable
{
  public static let maximumSourceCharacters = 4_096
  public static let maximumOutputBytes = 65_536
  public static let maximumSuggestions = 8

  private let executionLock = NSLock()
  private var executionInFlight = false

  public init() {}

  public func completions(
    for request: WorldCommandConsoleRequest
  ) async throws -> WorldCommandCompletionResult {
    guard Self.validSource(request.source, allowEmpty: true),
      try validWorld(request.worldID, in: request.layout)
    else {
      throw WorldCommandConsoleServiceError.invalidContext
    }
    return try MikroKhorosPathContext.$canonicalRootOverride.withValue(
      request.layout.canonicalRoot
    ) {
      let configuration = try ConfigurationStore.load(from: request.layout.configurationURL)
      let globals = CommandGlobalOptions(
        configurationPath: request.layout.configurationURL.path,
        worldID: request.worldID,
        outputMode: .human,
        colorMode: .never
      )
      return WorldCommandCompletionResult(
        suggestions: Self.suggestions(
          for: request.source,
          globals: globals,
          configuration: configuration
        )
      )
    }
  }

  public func execute(
    _ request: WorldCommandConsoleRequest
  ) async throws -> WorldCommandExecutionResult {
    guard beginExecution() else { throw WorldCommandConsoleServiceError.busy }
    defer { finishExecution() }

    guard Self.validSource(request.source, allowEmpty: false),
      try validWorld(request.worldID, in: request.layout)
    else {
      return Self.rejected("The command line or World context is invalid.")
    }

    let userArguments: [String]
    do {
      userArguments = try Self.userArguments(from: request.source)
    } catch {
      return Self.rejected("Enter one complete MikroKhoros command line.")
    }

    let globals: CommandGlobalOptions
    let commandArguments: [String]
    do {
      (globals, commandArguments) = try CommandParser.splitGlobals(userArguments)
    } catch {
      return Self.rejected("The command line contains an invalid global option.")
    }
    guard globals == CommandGlobalOptions() else {
      return Self.rejected(
        "The World command field supplies its configuration, World, output, and color context."
      )
    }

    let parsed: ParsedCommand
    do {
      parsed = try CommandParser.parse(commandArguments)
    } catch {
      return Self.rejected("This is not a complete MikroKhoros command.")
    }
    guard WorldCommandConsolePolicy.allows(parsed.kind) else {
      return Self.rejected(
        "This command is available from the terminal CLI or its dedicated app view.",
        displayCommand: parsed.definition.command
      )
    }
    guard !parsed.definition.mayRequestForegroundInput else {
      return Self.rejected(
        "Commands that request foreground input are unavailable in the World command field.",
        displayCommand: parsed.definition.command
      )
    }
    if parsed.kind == .worldShow,
      let query = parsed.fieldValues["world"]?.last
    {
      do {
        let configuration = try ConfigurationStore.load(from: request.layout.configurationURL)
        let catalog = try WorldCatalogStore(
          url: request.layout.catalogURL,
          maximumBytes: configuration.runtime.maximumWorldBytes
        )
        guard try catalog.resolve(query).id == request.worldID else {
          return Self.rejected(
            "The World command field cannot cross the selected World boundary.",
            displayCommand: parsed.definition.command
          )
        }
      } catch {
        return Self.rejected(
          "The selected World could not be resolved.",
          displayCommand: parsed.definition.command
        )
      }
    }

    var executableArguments = commandArguments
    if parsed.kind == .worldShow {
      executableArguments = parsed.definition.path + [request.worldID]
    }
    executableArguments =
      [
        "--config", request.layout.configurationURL.path,
        "--world", request.worldID,
        "--output", "human",
        "--color", "never",
      ] + executableArguments

    let transcript = await CommandExecutor.executeTranscript(
      arguments: executableArguments,
      layout: request.layout,
      maximumOutputBytes: Self.maximumOutputBytes
    )
    return WorldCommandExecutionResult(
      accepted: true,
      displayCommand: Self.displayCommand(parsed),
      standardOutput: transcript.standardOutput,
      standardError: transcript.standardError,
      exitStatus: transcript.exitStatus,
      outputTruncated: transcript.outputTruncated,
      refreshWorld: transcript.exitStatus == 0
        && WorldCommandConsolePolicy.refreshesWorld(parsed.kind)
    )
  }

  private func beginExecution() -> Bool {
    executionLock.lock()
    defer { executionLock.unlock() }
    guard !executionInFlight else { return false }
    executionInFlight = true
    return true
  }

  private func finishExecution() {
    executionLock.lock()
    executionInFlight = false
    executionLock.unlock()
  }

  private func validWorld(_ worldID: String, in layout: ProductLayout) throws -> Bool {
    guard InventoryIdentity.isValid(worldID) else { return false }
    let configuration = try ConfigurationStore.load(from: layout.configurationURL)
    let catalog = try WorldCatalogStore(
      url: layout.catalogURL,
      maximumBytes: configuration.runtime.maximumWorldBytes
    )
    guard catalog.allWorlds().contains(where: { $0.id == worldID }) else { return false }
    return FileManager.default.fileExists(atPath: try layout.worldURL(for: worldID).path)
  }

  private static func validSource(_ source: String, allowEmpty: Bool) -> Bool {
    let count = source.count
    guard count <= maximumSourceCharacters,
      !source.contains(where: { $0.isNewline || $0 == "\0" })
    else { return false }
    return allowEmpty || !source.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private static func userArguments(from source: String) throws -> [String] {
    let trimmed = source.trimmingCharacters(in: .whitespaces)
    guard !trimmed.hasPrefix("&"), !trimmed.hasPrefix(":"), !trimmed.isEmpty else {
      throw WorldCommandConsoleServiceError.invalidContext
    }
    var arguments = try CommandLineTokenizer.tokenize(trimmed)
    if arguments.first?.caseInsensitiveCompare("khoros") == .orderedSame {
      arguments.removeFirst()
    }
    guard !arguments.isEmpty, arguments.first?.caseInsensitiveCompare("console") != .orderedSame
    else {
      throw WorldCommandConsoleServiceError.invalidContext
    }
    return arguments
  }

  private static func rejected(
    _ message: String,
    displayCommand: String = "command rejected"
  ) -> WorldCommandExecutionResult {
    WorldCommandExecutionResult(
      accepted: false,
      displayCommand: displayCommand,
      standardOutput: "",
      standardError: """
        error:
          code: "world.command_unavailable"
          message: "\(yamlScalar(message))"
        """ + "\n",
      exitStatus: 2,
      outputTruncated: false,
      refreshWorld: false
    )
  }

  private static func yamlScalar(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
  }

  private static func displayCommand(_ parsed: ParsedCommand) -> String {
    let safeFieldIDs = Set(
      parsed.definition.fields
        .filter { $0.historyPolicy == .store }
        .map(\.id)
    )
    var values: [String: [String]] = [:]
    for (key, value) in parsed.fieldValues where safeFieldIDs.contains(key) {
      values[key] = value
    }
    let submission = InteractiveCommandSubmission(
      commandPath: parsed.definition.command,
      values: values,
      explicitFieldIDs: Set(values.keys),
      globals: CommandGlobalOptions(),
      stopsQueueOnError: false
    )
    let arguments = (try? CommandParser.arguments(for: submission)) ?? parsed.definition.path
    return arguments.map(quotedArgument).joined(separator: " ")
  }

  private static func quotedArgument(_ value: String) -> String {
    guard value.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "\\" }) else {
      return value
    }
    return "\""
      + value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      + "\""
  }

  private static func suggestions(
    for source: String,
    globals: CommandGlobalOptions,
    configuration: RuntimeConfiguration
  ) -> [WorldCommandSuggestion] {
    let partial = PartialCommandLine(source)
    let definitions = CommandCatalog.all.filter { WorldCommandConsolePolicy.allows($0.kind) }
    guard !partial.tokens.isEmpty else { return [] }
    let hasKhorosPrefix = partial.tokens.first?.caseInsensitiveCompare("khoros") == .orderedSame
    let tokens = hasKhorosPrefix ? Array(partial.tokens.dropFirst()) : partial.tokens
    guard !tokens.isEmpty else {
      return definitions.prefix(maximumSuggestions).map {
        WorldCommandSuggestion(value: "khoros \($0.command)", summary: $0.summary)
      }
    }

    let exact =
      definitions
      .filter { definition in
        guard tokens.count >= definition.path.count else { return false }
        return zip(tokens.prefix(definition.path.count), definition.path).allSatisfy {
          $0.caseInsensitiveCompare($1) == .orderedSame
        }
      }
      .sorted { $0.path.count > $1.path.count }
      .first

    if exact == nil || (exact?.path.count == tokens.count && !partial.trailingWhitespace) {
      let commandSource = tokens.joined(separator: " ").lowercased()
      let matches = definitions.filter { definition in
        let command = definition.command.lowercased()
        if command.hasPrefix(commandSource) { return true }
        let supplied = commandSource.split(separator: " ")
        let candidate = command.split(separator: " ")
        return supplied.count <= candidate.count
          && zip(supplied, candidate).allSatisfy { $1.hasPrefix($0) }
      }
      if !matches.isEmpty {
        return matches.prefix(maximumSuggestions).map {
          let prefix = hasKhorosPrefix ? "khoros " : ""
          return WorldCommandSuggestion(value: prefix + $0.command, summary: $0.summary)
        }
      }
    }

    guard let definition = exact else { return [] }
    let commandTokenCount = definition.path.count
    let suppliedArguments = Array(tokens.dropFirst(commandTokenCount))
    let activeToken = partial.trailingWhitespace ? "" : (suppliedArguments.last ?? "")
    let settledArguments =
      partial.trailingWhitespace
      ? suppliedArguments
      : Array(suppliedArguments.dropLast())

    var candidates: [(String, String)] = []
    if activeToken.hasPrefix("--") {
      for field in definition.fields {
        let spelling: String?
        switch field.syntax {
        case .option(let option), .flag(let option): spelling = option
        case .positional: spelling = nil
        }
        guard let spelling,
          spelling.lowercased().hasPrefix(activeToken.lowercased()),
          !settledArguments.contains(spelling)
        else { continue }
        candidates.append((spelling, field.interactiveHelp))
      }
    } else if let field = valueField(
      definition: definition,
      settledArguments: settledArguments,
      activeToken: activeToken,
      trailingWhitespace: partial.trailingWhitespace
    ) {
      let values = CompletionResolver.values(
        for: field.completion,
        globals: globals,
        configuration: configuration,
        source: activeToken
      )
      for value in values
      where activeToken.isEmpty
        || value.localizedCaseInsensitiveContains(activeToken)
      {
        candidates.append((value, field.label))
      }
      if activeToken.isEmpty {
        for optionField in definition.fields {
          let spelling: String?
          switch optionField.syntax {
          case .option(let option), .flag(let option): spelling = option
          case .positional: spelling = nil
          }
          guard let spelling, !suppliedArguments.contains(spelling) else { continue }
          candidates.append((spelling, optionField.interactiveHelp))
        }
      }
    }

    var seen = Set<String>()
    return candidates.compactMap { value, summary in
      let prefix = hasKhorosPrefix ? ["khoros"] : []
      var rebuilt = prefix + definition.path + settledArguments
      rebuilt.append(quotedArgument(value))
      let command = rebuilt.joined(separator: " ")
      guard seen.insert(command).inserted else { return nil }
      return WorldCommandSuggestion(
        value: command,
        summary: summary.isEmpty ? definition.summary : summary
      )
    }.prefix(maximumSuggestions).map { $0 }
  }

  private static func valueField(
    definition: CommandDefinition,
    settledArguments: [String],
    activeToken _: String,
    trailingWhitespace _: Bool
  ) -> CommandField? {
    if let option = settledArguments.last,
      let field = definition.fields.first(where: { field in
        if case .option(let spelling) = field.syntax { return spelling == option }
        return false
      })
    {
      return field
    }

    var consumedPositionals = 0
    var index = 0
    while index < settledArguments.count {
      let token = settledArguments[index]
      if let field = definition.fields.first(where: { field in
        switch field.syntax {
        case .option(let spelling), .flag(let spelling): return spelling == token
        case .positional: return false
        }
      }) {
        if case .option = field.syntax { index += 2 } else { index += 1 }
      } else {
        consumedPositionals += 1
        index += 1
      }
    }
    let positionals = definition.fields.filter {
      if case .positional = $0.syntax { return true }
      return false
    }
    guard !positionals.isEmpty else { return nil }
    return positionals[min(consumedPositionals, positionals.count - 1)]
  }
}

private struct PartialCommandLine {
  let tokens: [String]
  let trailingWhitespace: Bool

  init(_ source: String) {
    enum Quote { case single, double }
    var quote: Quote?
    var escaping = false
    var token = ""
    var values: [String] = []
    var started = false
    for character in source {
      if escaping {
        token.append(character)
        started = true
        escaping = false
        continue
      }
      if character == "\\", quote != .single {
        escaping = true
        started = true
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
          started = true
        } else if character == "\"" {
          quote = .double
          started = true
        } else if character.isWhitespace {
          if started {
            values.append(token)
            token = ""
            started = false
          }
        } else {
          token.append(character)
          started = true
        }
      }
    }
    if escaping { token.append("\\") }
    if started { values.append(token) }
    tokens = values
    trailingWhitespace = source.last?.isWhitespace == true && quote == nil && !escaping
  }
}
