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

public enum ConsoleControl: Equatable, Sendable {
  case queue
  case pause
  case resume
  case cancel(Int)
  case clear
  case context
  case help
  case quit
  case forceQuit

  public init(source: String) throws {
    let parts = source.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard let command = parts.first else {
      throw MikroKhorosError.command("missing console control")
    }
    switch command {
    case ":queue":
      guard parts.count == 1 else { throw Self.usage(":queue") }
      self = .queue
    case ":pause":
      guard parts.count == 1 else { throw Self.usage(":pause") }
      self = .pause
    case ":resume":
      guard parts.count == 1 else { throw Self.usage(":resume") }
      self = .resume
    case ":cancel":
      guard parts.count == 2, let id = Int(parts[1]), id > 0 else {
        throw Self.usage(":cancel <queue-id>")
      }
      self = .cancel(id)
    case ":clear":
      guard parts.count == 1 else { throw Self.usage(":clear") }
      self = .clear
    case ":context":
      guard parts.count == 1 else { throw Self.usage(":context") }
      self = .context
    case ":help":
      guard parts.count == 1 else { throw Self.usage(":help") }
      self = .help
    case ":quit":
      guard parts.count == 1 else { throw Self.usage(":quit") }
      self = .quit
    case ":quit!":
      guard parts.count == 1 else { throw Self.usage(":quit!") }
      self = .forceQuit
    default:
      throw MikroKhorosError.command("unknown console control '\(command)'")
    }
  }

  private static func usage(_ value: String) -> MikroKhorosError {
    MikroKhorosError.command("usage: \(value)")
  }
}

private struct QueuedConsoleCommand: Sendable {
  let id: Int
  let submission: InteractiveCommandSubmission
  let arguments: [String]
}

public struct ConsoleQueueSnapshot: Equatable, Sendable {
  public let runningID: Int?
  public let pendingIDs: [Int]
  public let paused: Bool
  public let barrierID: Int?
  public let stopping: Bool

  public var isIdle: Bool { runningID == nil && pendingIDs.isEmpty }
}

private final class ConsoleCommandQueue: @unchecked Sendable {
  private let lock = NSLock()
  private let maximumDepth: Int
  private var nextID = 1
  private var pending: [QueuedConsoleCommand] = []
  private var running: QueuedConsoleCommand?
  private var runningTask: Task<Int, Never>?
  private var paused = false
  private var barrierID: Int?
  private var stopping = false
  private var forced = false

  init(maximumDepth: Int) { self.maximumDepth = maximumDepth }

  func enqueue(
    submission: InteractiveCommandSubmission,
    arguments: [String]
  ) -> Int? {
    lock.withConsoleLock {
      guard !stopping, pending.count + (running == nil ? 0 : 1) < maximumDepth else {
        return nil
      }
      let item = QueuedConsoleCommand(id: nextID, submission: submission, arguments: arguments)
      nextID += 1
      pending.append(item)
      return item.id
    }
  }

  func hasCapacity() -> Bool {
    lock.withConsoleLock {
      !stopping && pending.count + (running == nil ? 0 : 1) < maximumDepth
    }
  }

  func takeNext() -> QueuedConsoleCommand? {
    lock.withConsoleLock {
      guard !paused, running == nil, !pending.isEmpty else { return nil }
      let item = pending.removeFirst()
      running = item
      return item
    }
  }

  func attach(task: Task<Int, Never>, to id: Int) {
    lock.withConsoleLock {
      guard running?.id == id else {
        task.cancel()
        return
      }
      runningTask = task
    }
  }

  func finish(id: Int, status: Int) {
    lock.withConsoleLock {
      guard running?.id == id else { return }
      if status != 0, running?.submission.stopsQueueOnError == true {
        paused = true
        barrierID = id
      }
      running = nil
      runningTask = nil
    }
  }

  func pause() { lock.withConsoleLock { paused = true } }

  func resume() {
    lock.withConsoleLock {
      paused = false
      barrierID = nil
    }
  }

  func clear() -> [Int] {
    lock.withConsoleLock {
      let removed = pending.map(\.id)
      pending.removeAll()
      return removed
    }
  }

  func cancel(id: Int) -> String {
    lock.withConsoleLock {
      if let index = pending.firstIndex(where: { $0.id == id }) {
        pending.remove(at: index)
        return "pending"
      }
      if running?.id == id {
        runningTask?.cancel()
        return "running"
      }
      return "not_found"
    }
  }

  func requestGracefulStop() {
    lock.withConsoleLock {
      stopping = true
      paused = false
      barrierID = nil
    }
  }

  func forceStop() {
    lock.withConsoleLock {
      stopping = true
      forced = true
      pending.removeAll()
      runningTask?.cancel()
      paused = false
    }
  }

  func shouldWorkerExit() -> Bool {
    lock.withConsoleLock {
      forced || (stopping && running == nil && pending.isEmpty)
    }
  }

  func snapshot() -> ConsoleQueueSnapshot {
    lock.withConsoleLock {
      ConsoleQueueSnapshot(
        runningID: running?.id,
        pendingIDs: pending.map(\.id),
        paused: paused,
        barrierID: barrierID,
        stopping: stopping
      )
    }
  }
}

struct ConsoleForegroundRequest: Sendable {
  let id: Int
  let prompt: String
  let hidden: Bool
}

final class ConsoleCommandIO: CommandIO, @unchecked Sendable {
  private let condition = NSCondition()
  private var output = ""
  private var nextRequestID = 1
  private var request: ConsoleForegroundRequest?
  private var responseReady = false
  private var response: String?
  private var inputCharacterLimit: Int

  init(maximumInputCharacters: Int) {
    inputCharacterLimit = maximumInputCharacters
  }

  var isInteractive: Bool { true }

  func writeStandardOutput(_ text: String) {
    condition.withConsoleCondition {
      output += text
      condition.broadcast()
    }
  }

  func writeStandardError(_ text: String) { writeStandardOutput(text) }

  func readLine(prompt: String, hidden: Bool) throws -> String? {
    condition.lock()
    defer { condition.unlock() }
    while request != nil { condition.wait() }
    let current = ConsoleForegroundRequest(
      id: nextRequestID,
      prompt: prompt,
      hidden: hidden
    )
    nextRequestID += 1
    request = current
    responseReady = false
    response = nil
    condition.broadcast()
    while !responseReady { condition.wait() }
    let result = response
    request = nil
    response = nil
    responseReady = false
    condition.broadcast()
    return result
  }

  func readStandardInputToEnd() throws -> Data {
    Data((try readLine(prompt: "Input: ", hidden: true) ?? "").utf8)
  }

  func foregroundRequest() -> ConsoleForegroundRequest? {
    condition.withConsoleCondition { request }
  }

  func answer(requestID: Int, value: String?) {
    condition.withConsoleCondition {
      guard request?.id == requestID else { return }
      response = value
      responseReady = true
      condition.broadcast()
    }
  }

  func hasActivity() -> Bool {
    condition.withConsoleCondition { !output.isEmpty || request != nil }
  }

  func drainOutput() -> String {
    condition.withConsoleCondition {
      let result = output
      output.removeAll(keepingCapacity: true)
      return result
    }
  }

  func update(maximumInputCharacters: Int) {
    condition.withConsoleCondition { inputCharacterLimit = maximumInputCharacters }
  }

  func maximumInputCharacters() -> Int {
    condition.withConsoleCondition { inputCharacterLimit }
  }
}

public enum InteractiveConsole {
  @discardableResult
  public static func run(
    initialGlobals: CommandGlobalOptions,
    io _: any CommandIO,
    terminal suppliedTerminal: (any TerminalBackend)? = nil,
    historyURL: URL = ConsoleHistoryStore.defaultURL
  ) async -> Int {
    let terminal = suppliedTerminal ?? SystemTerminalBackend()
    guard terminal.isInteractive else {
      writeConsoleIssue(
        code: "console.tty_required",
        message: "the interactive console requires terminal input and output",
        terminal: terminal
      )
      return 1
    }
    do {
      try terminal.begin()
      defer { terminal.end() }
      return try await session(
        initialGlobals: initialGlobals,
        terminal: terminal,
        historyURL: historyURL
      )
    } catch {
      terminal.end()
      writeConsoleIssue(error: error, terminal: terminal)
      return 1
    }
  }

  private static func session(
    initialGlobals: CommandGlobalOptions,
    terminal: any TerminalBackend,
    historyURL: URL
  ) async throws -> Int {
    var globals = initialGlobals
    var configuration = try loadConfiguration(for: globals)
    (terminal as? SystemTerminalBackend)?.setEscapeTimeout(
      milliseconds: configuration.console.escapeTimeoutMilliseconds
    )
    let history = try ConsoleHistoryStore(url: historyURL, configuration: configuration)
    let queue = ConsoleCommandQueue(maximumDepth: configuration.console.maximumQueueDepth)
    let commandIO = ConsoleCommandIO(
      maximumInputCharacters: configuration.console.maximumInputCharacters
    )
    let presentation = PresentationEnvironment.resolve(
      globals: globals,
      configuration: configuration,
      isInteractive: true
    )
    let editor = LineEditor(
      terminal: terminal,
      unicodeEnabled: presentation.unicodeEnabled && terminal.capabilities.supportsUnicode
    )
    terminal.writeScrollback(
      consoleHeader(globals: globals, configuration: configuration, terminal: terminal)
    )

    let worker = Task {
      await runQueue(queue, io: commandIO)
    }

    var shouldQuit = false
    var pendingInterruptArmed = false
    while !shouldQuit {
      configuration = try loadConfiguration(for: globals)
      (terminal as? SystemTerminalBackend)?.setEscapeTimeout(
        milliseconds: configuration.console.escapeTimeoutMilliseconds
      )
      commandIO.update(
        maximumInputCharacters: configuration.console.maximumInputCharacters
      )
      let commandHistory = history.allEntries().reversed().map(\.commandPath)
      let result = try readLine(
        editor: editor,
        terminal: terminal,
        commandIO: commandIO,
        prompt: editor.prompt("khoros"),
        maximumCharacters: configuration.console.maximumInputCharacters,
        history: Array(commandHistory),
        showSuggestionsWhenEmpty: false,
        suggestions: { source in
          let isBarrier = source.hasPrefix("&")
          let lookup =
            isBarrier
            ? source.dropFirst().trimmingCharacters(in: .whitespaces)
            : source
          let prefix = isBarrier ? "& " : ""
          let catalog = CommandCatalog.completions(
            for: lookup,
            limit: configuration.console.maximumSuggestions
          ).map {
            LineEditorSuggestion(value: prefix + $0.command, summary: $0.summary)
          }
          let recalled = commandHistory.filter {
            lookup.isEmpty || $0.localizedCaseInsensitiveContains(lookup)
          }.map { LineEditorSuggestion(value: prefix + $0, summary: "history") }
          var seen = Set<String>()
          return (catalog + recalled).filter { seen.insert($0.value).inserted }
            .prefix(configuration.console.maximumSuggestions).map { $0 }
        }
      )
      switch result {
      case .cancelled:
        pendingInterruptArmed = false
      case .interrupted(let draft):
        let snapshot = queue.snapshot()
        if !draft.isEmpty {
          pendingInterruptArmed = false
        } else if let id = snapshot.runningID {
          terminal.write("cancel: \(id) (\(queue.cancel(id: id)))\n")
          pendingInterruptArmed = false
        } else if snapshot.isIdle {
          queue.requestGracefulStop()
          shouldQuit = true
        } else if snapshot.paused {
          if pendingInterruptArmed {
            _ = queue.clear()
            queue.forceStop()
            shouldQuit = true
          } else {
            terminal.write(
              "queue: \(snapshot.pendingIDs.count) pending; press Ctrl-C again to clear and exit\n"
            )
            pendingInterruptArmed = true
          }
        } else {
          terminal.write(render(snapshot: snapshot))
          pendingInterruptArmed = false
        }
      case .endOfInput:
        pendingInterruptArmed = false
        let snapshot = queue.snapshot()
        if snapshot.isIdle {
          queue.requestGracefulStop()
          shouldQuit = true
        } else {
          terminal.write(render(snapshot: snapshot))
        }
      case .suspended:
        preconditionFailure("readLine resolves suspension internally")
      case .submitted(let raw):
        pendingInterruptArmed = false
        let source = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { continue }
        if source.hasPrefix(":") {
          do {
            let control = try ConsoleControl(source: source)
            shouldQuit = try handle(
              control: control,
              globals: &globals,
              queue: queue,
              commandIO: commandIO,
              editor: editor,
              terminal: terminal,
              configuration: configuration
            )
          } catch {
            writeConsoleIssue(error: error, terminal: terminal)
          }
          continue
        }
        let barrier = source.hasPrefix("&")
        let commandPath =
          barrier
          ? source.dropFirst().trimmingCharacters(in: .whitespaces)
          : source
        guard !commandPath.isEmpty else {
          writeConsoleIssue(
            code: "console.command_required",
            message: "& must prefix a command path",
            terminal: terminal
          )
          continue
        }
        let tokens: [String]
        do {
          tokens = try CommandLineTokenizer.tokenize(commandPath)
        } catch {
          writeConsoleIssue(error: error, terminal: terminal)
          continue
        }
        let matchingDefinition = CommandCatalog.all.compactMap {
          definition -> (path: [String], definition: CommandDefinition)? in
          definition.allPaths.filter { tokens.starts(with: $0) }
            .max(by: { $0.count < $1.count }).map { ($0, definition) }
        }.max(by: { $0.path.count < $1.path.count })
        let submission: InteractiveCommandSubmission
        let arguments: [String]
        if let match = matchingDefinition, tokens.count == match.path.count {
          let definition = match.definition
          guard
            let built = try build(
              definition: definition,
              barrier: barrier,
              globals: globals,
              configuration: configuration,
              history: history,
              editor: editor,
              terminal: terminal,
              commandIO: commandIO
            )
          else {
            continue
          }
          submission = built
          arguments = try CommandParser.arguments(for: submission)
          try history.append(submission, definition: definition)
        } else {
          let directArguments = globals.arguments + tokens
          if let parsed = try? CommandParser.parse(directArguments) {
            submission = InteractiveCommandSubmission(
              commandPath: parsed.definition.command,
              values: parsed.fieldValues,
              explicitFieldIDs: Set(parsed.fieldValues.keys),
              globals: globals,
              stopsQueueOnError: barrier
            )
            try history.append(submission, definition: parsed.definition)
          } else {
            submission = InteractiveCommandSubmission(
              commandPath: tokens.joined(separator: " "),
              values: [:],
              globals: globals,
              stopsQueueOnError: barrier
            )
          }
          arguments = directArguments
        }
        var queuedID = queue.enqueue(submission: submission, arguments: arguments)
        if queuedID == nil {
          terminal.write("queue is full; the completed form is retained until space is available\n")
        }
        while queuedID == nil, !shouldQuit {
          let capacityInput = try readLine(
            editor: editor,
            terminal: terminal,
            commandIO: commandIO,
            prompt: editor.prompt("queue full"),
            maximumCharacters: configuration.console.maximumInputCharacters,
            history: [],
            suggestions: { source in
              [":queue", ":resume", ":cancel", ":clear", ":quit", ":quit!"]
                .filter { source.isEmpty || $0.hasPrefix(source) }
                .map { LineEditorSuggestion(value: $0, summary: "console control") }
            },
            returnWhen: queue.hasCapacity
          )
          switch capacityInput {
          case .submitted(let rawControl):
            let controlSource = rawControl.trimmingCharacters(in: .whitespacesAndNewlines)
            if !controlSource.isEmpty {
              guard controlSource.hasPrefix(":") else {
                writeConsoleIssue(
                  code: "console.queue_full",
                  message: "the completed form is retained; enter a console control",
                  terminal: terminal
                )
                continue
              }
              do {
                shouldQuit = try handle(
                  control: ConsoleControl(source: controlSource),
                  globals: &globals,
                  queue: queue,
                  commandIO: commandIO,
                  editor: editor,
                  terminal: terminal,
                  configuration: configuration
                )
              } catch {
                writeConsoleIssue(error: error, terminal: terminal)
              }
            }
          case .cancelled, .interrupted:
            terminal.write("queue: completed form retained\n")
          case .endOfInput:
            terminal.write(render(snapshot: queue.snapshot()))
          case .suspended:
            preconditionFailure("readLine resolves suspension internally")
          }
          if !shouldQuit {
            queuedID = queue.enqueue(submission: submission, arguments: arguments)
          }
        }
        guard !shouldQuit else { continue }
        terminal.write("queued: \(queuedID.map(String.init) ?? "accepted")\n")
      }
    }

    while !queue.shouldWorkerExit() {
      try service(commandIO: commandIO, editor: editor, terminal: terminal)
      try await Task.sleep(for: .milliseconds(25))
    }
    _ = await worker.value
    try service(commandIO: commandIO, editor: editor, terminal: terminal)
    terminal.write("console: closed\n")
    return 0
  }

  private static func runQueue(
    _ queue: ConsoleCommandQueue,
    io: ConsoleCommandIO
  ) async {
    while !queue.shouldWorkerExit() {
      guard let item = queue.takeNext() else {
        try? await Task.sleep(for: .milliseconds(25))
        continue
      }
      let clock = ContinuousClock()
      let started = clock.now
      let barrier = item.submission.stopsQueueOnError ? "& " : ""
      io.writeStandardOutput("#\(item.id)  \(barrier)\(item.submission.commandPath)  running\n")
      let task = Task {
        await CommandExecutor.execute(arguments: item.arguments, io: io)
      }
      queue.attach(task: task, to: item.id)
      let status = await task.value
      queue.finish(id: item.id, status: status)
      let duration = clock.now - started
      let milliseconds =
        duration.components.seconds * 1_000
        + duration.components.attoseconds / 1_000_000_000_000_000
      let label = status == 0 ? "success" : "error"
      io.writeStandardOutput(
        "#\(item.id)  \(barrier)\(item.submission.commandPath)  \(label)  \(milliseconds) ms\n"
      )
    }
  }

  private static func consoleHeader(
    globals: CommandGlobalOptions,
    configuration: RuntimeConfiguration,
    terminal: any TerminalBackend
  ) -> String {
    let catalog = try? WorldCatalogStore(maximumBytes: configuration.runtime.maximumWorldBytes)
    let record: WorldCatalogRecord?
    if let catalog {
      record = try? catalog.selected(globals.worldID)
    } else {
      record = nil
    }
    let presentation = PresentationEnvironment.resolve(
      globals: globals,
      configuration: configuration,
      isInteractive: true
    )
    let unicode = presentation.unicodeEnabled && terminal.capabilities.supportsUnicode
    let accent: (String) -> String = { value in
      presentation.colorEnabled && terminal.capabilities.supportsColor
        ? "\u{1B}[1;36m\(value)\u{1B}[0m" : value
    }
    let dim: (String) -> String = { value in
      presentation.colorEnabled && terminal.capabilities.supportsColor
        ? "\u{1B}[2m\(value)\u{1B}[0m" : value
    }
    let world =
      record.map {
        "\($0.name) \(unicode ? "·" : "-") \(String($0.id.prefix(8)))"
      } ?? "not initialized"
    let next = record == nil ? "khoros init" : "agent show agent"
    return """
      \(accent("MikroKhoros"))  \(dim("interactive console"))
      \(dim("product"))    \(TerminalText.escapedUntrusted(MikroKhorosPaths.root.path))
      \(dim("world"))      \(TerminalText.escapedUntrusted(world))
      \(dim("next"))       \(accent(next))
      \(dim("Type a command, press Tab to browse, or :help for controls."))

      """
  }

  private static func build(
    definition: CommandDefinition,
    barrier: Bool,
    globals: CommandGlobalOptions,
    configuration: RuntimeConfiguration,
    history: ConsoleHistoryStore,
    editor: LineEditor,
    terminal: any TerminalBackend,
    commandIO: ConsoleCommandIO
  ) throws -> InteractiveCommandSubmission? {
    var capturedGlobals = globals
    let resolvedWorldID = try selectedWorldID(globals: globals, configuration: configuration)
    if definition.requiresSelectedWorld, capturedGlobals.worldID == nil {
      let worldField = InteractiveGlobalField.world
      let result = try readLine(
        editor: editor,
        terminal: terminal,
        commandIO: commandIO,
        prompt: editor.prompt(worldField.interactiveAliases.name),
        help: worldField.interactiveAliases.help,
        maximumCharacters: configuration.console.maximumInputCharacters,
        history: [],
        suggestions: { source in
          guard let resolvedWorldID,
            source.isEmpty || resolvedWorldID.localizedCaseInsensitiveContains(source)
          else { return [] }
          return [.init(value: resolvedWorldID, summary: "current world")]
        }
      )
      switch result {
      case .cancelled, .interrupted, .endOfInput:
        return nil
      case .suspended:
        preconditionFailure("readLine resolves suspension internally")
      case .submitted(let source):
        capturedGlobals.worldID = source.isEmpty ? resolvedWorldID : source
      }
    }
    let worldID = try selectedWorldID(globals: capturedGlobals, configuration: configuration)
    let context = CommandResolutionContext(
      configuration: configuration,
      globals: capturedGlobals,
      worldID: worldID
    )
    var values: [String: [String]] = [:]
    var explicit = Set<String>()
    for (fieldIndex, field) in definition.fields.enumerated() {
      let management = try managementInterface(
        for: definition.kind,
        values: values,
        globals: capturedGlobals,
        configuration: configuration
      )
      if field.id == "input",
        let actionID = values["action"]?.first,
        let action = management?.actions.first(where: { $0.id == actionID })
      {
        var assignments: [String] = []
        for parameter in action.parameters {
          let inputType = action.inputTypes[parameter] ?? .text
          let defaultValue = action.inputDefaults[parameter].map(managementInputText)
          let choices =
            action.inputChoices[parameter]
            ?? (inputType == .boolean ? ["false", "true"] : [])
          let result = try readLine(
            editor: editor,
            terminal: terminal,
            commandIO: commandIO,
            prompt: editor.prompt(parameter),
            help: "Object-defined \(inputType.rawValue) input for \(action.id).",
            maximumCharacters: configuration.console.maximumInputCharacters,
            history: [],
            suggestions: { source in
              var values = choices.filter {
                source.isEmpty || $0.localizedCaseInsensitiveContains(source)
              }
              if source.isEmpty, let defaultValue, !values.contains(defaultValue) {
                values.insert(defaultValue, at: 0)
              }
              return values.map {
                .init(
                  value: $0,
                  summary: $0 == defaultValue ? "default" : inputType.rawValue
                )
              }
            }
          )
          switch result {
          case .cancelled, .interrupted, .endOfInput:
            return nil
          case .suspended:
            preconditionFailure("readLine resolves suspension internally")
          case .submitted(let source):
            if !source.isEmpty || defaultValue != nil {
              assignments.append("\(parameter)=\(source.isEmpty ? defaultValue! : source)")
              if !source.isEmpty {
                explicit.insert(field.id)
              }
            }
          }
        }
        if !assignments.isEmpty { values[field.id] = assignments }
        continue
      }
      let resolvedDefault = field.defaultValue?.resolve(in: context)
      var available = CompletionResolver.values(
        for: field.completion,
        globals: capturedGlobals,
        configuration: configuration
      )
      if field.id == "action" {
        available +=
          management?.actions.filter {
            definition.kind == .inventoryActionRun
              ? $0.scope.acceptsInventory : $0.scope.acceptsWorld
          }.map(\.id) ?? []
      } else if field.id == "view" {
        available +=
          management?.views.filter {
            definition.kind == .inventoryViewShow
              ? $0.scope.acceptsInventory : $0.scope.acceptsWorld
          }.map(\.id) ?? []
      }
      let effectiveDefault =
        resolvedDefault
        ?? (field.cardinality == .required && Set(available).count == 1 ? available.first : nil)
      let interactiveAliases = field.interactiveAliases
      var collected: [String] = []
      var finishedRepeatedField = false
      repeat {
        let prompt = editor.prompt(
          fieldPromptLabel(
            index: fieldIndex,
            count: definition.fields.count,
            field: field
          )
        )
        let safeHistory = history.values(commandPath: definition.command, fieldID: field.id)
        let result = try readLine(
          editor: editor,
          terminal: terminal,
          commandIO: commandIO,
          prompt: prompt,
          help: field.interactiveHelp,
          maximumCharacters: configuration.console.maximumInputCharacters,
          history: safeHistory.map(interactiveAliases.displayValue),
          suggestions: { source in
            let completionValues =
              field.completion == .filesystemPath
              ? CompletionResolver.values(
                for: field.completion,
                globals: capturedGlobals,
                configuration: configuration,
                source: source
              )
              : available
            var candidates = completionValues.filter { canonical in
              source.isEmpty
                || canonical.localizedCaseInsensitiveContains(source)
                || interactiveAliases.displayValue(for: canonical)
                  .localizedCaseInsensitiveContains(source)
            }
            candidates += safeHistory.filter { canonical in
              source.isEmpty
                || canonical.localizedCaseInsensitiveContains(source)
                || interactiveAliases.displayValue(for: canonical)
                  .localizedCaseInsensitiveContains(source)
            }
            if source.isEmpty, let effectiveDefault, !candidates.contains(effectiveDefault) {
              candidates.insert(effectiveDefault, at: 0)
            }
            var seen = Set<String>()
            return candidates.filter { seen.insert($0).inserted }
              .prefix(configuration.console.maximumSuggestions).map {
                let displayValue = interactiveAliases.displayValue(for: $0)
                let provenance: String? =
                  if $0 == effectiveDefault {
                    resolvedDefault == nil ? "only available · default" : "default"
                  } else if safeHistory.contains($0) {
                    "history"
                  } else {
                    nil
                  }
                return .init(
                  value: displayValue,
                  summary: provenance
                )
              }
          }
        )
        switch result {
        case .cancelled, .interrupted, .endOfInput:
          return nil
        case .suspended:
          preconditionFailure("readLine resolves suspension internally")
        case .submitted(let source):
          if source.isEmpty {
            if collected.isEmpty, let effectiveDefault { collected.append(effectiveDefault) }
            finishedRepeatedField = true
          } else {
            collected.append(interactiveAliases.canonicalValue(for: source) ?? source)
            explicit.insert(field.id)
          }
        }
        if field.cardinality != .repeated || finishedRepeatedField {
          break
        }
      } while true
      if !collected.isEmpty { values[field.id] = collected }
    }
    return InteractiveCommandSubmission(
      commandPath: definition.command,
      values: values,
      explicitFieldIDs: explicit,
      globals: capturedGlobals,
      stopsQueueOnError: barrier
    )
  }

  static func fieldPromptLabel(index: Int, count: Int, field: CommandField) -> String {
    let cardinality = field.cardinality == .repeated ? "repeatable" : field.cardinality.rawValue
    return "\(index + 1)/\(count) \(field.label) [\(cardinality)]"
  }

  private static func treasuryAuthority(for configuration: RuntimeConfiguration) throws
    -> TreasuryAuthorityState
  {
    let treasuryAuthorityStore = try TreasuryAuthorityStore(
      maximumBytes: configuration.runtime.maximumWorldBytes
    )
    do {
      return try treasuryAuthorityStore.load()
    } catch {
      guard (error as? MikroKhorosError)?.issue.code == "treasury.authority_not_found" else {
        throw error
      }
      let agents = try AgentStore(maximumBytes: configuration.runtime.maximumAgentStoreBytes)
      let worlds = try WorldCatalogStore(maximumBytes: configuration.runtime.maximumWorldBytes)
      return try treasuryAuthorityStore.bootstrap(
        confirmNoExistingEconomy: agents.allAgents().isEmpty && worlds.document.worlds.isEmpty
      )
    }
  }

  private static func managementInterface(
    for kind: CommandKind,
    values: [String: [String]],
    globals: CommandGlobalOptions,
    configuration: RuntimeConfiguration
  ) throws -> ObjectManagementInterface? {
    let inventoryKinds: Set<CommandKind> = [.inventoryActionRun, .inventoryViewShow]
    let worldKinds: Set<CommandKind> = [.worldObjectActionRun, .worldObjectViewShow]
    guard inventoryKinds.contains(kind) || worldKinds.contains(kind) else { return nil }
    let inventory = try InventoryStore(
      limits: configuration.runtime,
      runtimeRegistry: .installedCLI()
    )
    if inventoryKinds.contains(kind) {
      guard let id = values["inventory-id"]?.first else { return nil }
      let record = try inventory.resolve(id)
      return try inventory.package(contentHash: record.packageHash).manifest.management
    }
    guard let id = values["world-object-id"]?.first else { return nil }
    let catalog = try WorldCatalogStore(maximumBytes: configuration.runtime.maximumWorldBytes)
    let record = try catalog.selected(globals.worldID)
    let worldURL = try WorldStore.url(for: record.id)
    let document = try WorldStore.load(
      from: worldURL,
      maximumBytes: configuration.runtime.maximumWorldBytes
    )
    let treasuryAuthorityState = try treasuryAuthority(for: configuration)
    let runtime = try WorldRuntime(
      document: document,
      configuration: configuration,
      inventory: inventory,
      treasuryAuthority: treasuryAuthorityState
    )
    _ = try runtime.exactWorldObject(id)
    // TODO(runtime-management-provider): prefer a native runtime provider API when exposed.
    // Expected shape: runtime.managementProvider(for: id)? or runtime.managementDescriptor(for: id)?
    // Expected contract:
    // - accepts world object IDs without package/type dispatch
    // - exposes actions and views via scope-aware typed declarations
    // Current fallback keeps behavior for package-provided management interfaces.
    let interface = try runtime.worldManagementInterface(for: id)
    guard case .object(let root) = interface,
      let object = root["object"],
      case .object(let contract) = object
    else {
      return nil
    }
    let data = try JSONEncoder().encode(contract)
    return try JSONDecoder().decode(ObjectManagementInterface.self, from: data)
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

  private static func readLine(
    editor: LineEditor,
    terminal: any TerminalBackend,
    commandIO: ConsoleCommandIO,
    prompt: String,
    help: String? = nil,
    maximumCharacters: Int,
    history: [String],
    showSuggestionsWhenEmpty: Bool = true,
    suggestions: @escaping (String) -> [LineEditorSuggestion],
    returnWhen: @escaping () -> Bool = { false }
  ) throws -> LineEditorResult {
    var state = LineEditorState()
    while true {
      let result = try editor.readLine(
        prompt: prompt,
        initialState: state,
        help: help,
        maximumCharacters: maximumCharacters,
        history: history,
        suggestions: suggestions,
        showSuggestionsWhenEmpty: showSuggestionsWhenEmpty,
        onTick: commandIO.hasActivity
      )
      guard case .suspended(let saved) = result else { return result }
      state = saved
      try service(commandIO: commandIO, editor: editor, terminal: terminal)
      if state.text.isEmpty, returnWhen() { return .submitted("") }
    }
  }

  private static func service(
    commandIO: ConsoleCommandIO,
    editor: LineEditor,
    terminal: any TerminalBackend
  ) throws {
    let output = commandIO.drainOutput()
    if !output.isEmpty { terminal.write(output) }
    guard let request = commandIO.foregroundRequest() else { return }
    let result = try editor.readLine(
      prompt: request.prompt,
      hidden: request.hidden,
      maximumCharacters: commandIO.maximumInputCharacters()
    )
    switch result {
    case .submitted(let value): commandIO.answer(requestID: request.id, value: value)
    case .cancelled, .interrupted, .endOfInput:
      commandIO.answer(requestID: request.id, value: nil)
    case .suspended: preconditionFailure("foreground prompts cannot suspend")
    }
  }

  private static func handle(
    control: ConsoleControl,
    globals: inout CommandGlobalOptions,
    queue: ConsoleCommandQueue,
    commandIO: ConsoleCommandIO,
    editor: LineEditor,
    terminal: any TerminalBackend,
    configuration: RuntimeConfiguration
  ) throws -> Bool {
    switch control {
    case .queue:
      terminal.write(render(snapshot: queue.snapshot()))
    case .pause:
      queue.pause()
      terminal.write("queue: paused\n")
    case .resume:
      queue.resume()
      terminal.write("queue: running\n")
    case .cancel(let id):
      terminal.write("cancel: \(id) (\(queue.cancel(id: id)))\n")
    case .clear:
      terminal.write("cleared: \(queue.clear().map(String.init).joined(separator: ","))\n")
    case .context:
      let config = try contextValue(
        .configuration,
        current: globals.configurationPath,
        editor: editor,
        terminal: terminal,
        commandIO: commandIO,
        maximumCharacters: configuration.console.maximumInputCharacters
      )
      let world = try contextValue(
        .world,
        current: globals.worldID,
        editor: editor,
        terminal: terminal,
        commandIO: commandIO,
        maximumCharacters: configuration.console.maximumInputCharacters
      )
      let output = try contextValue(
        .output,
        current: globals.outputMode?.rawValue,
        editor: editor,
        terminal: terminal,
        commandIO: commandIO,
        maximumCharacters: configuration.console.maximumInputCharacters
      )
      let color = try contextValue(
        .color,
        current: globals.colorMode?.rawValue,
        editor: editor,
        terminal: terminal,
        commandIO: commandIO,
        maximumCharacters: configuration.console.maximumInputCharacters
      )
      let outputMode = try output.map {
        guard let mode = OutputMode(rawValue: $0) else {
          throw MikroKhorosError.command("output format must be auto, human, yaml, or json")
        }
        return mode
      }
      let colorMode = try color.map {
        guard let mode = ColorMode(rawValue: $0) else {
          throw MikroKhorosError.command("color behavior must be auto, always, or never")
        }
        return mode
      }
      globals = CommandGlobalOptions(
        configurationPath: config,
        worldID: world,
        outputMode: outputMode,
        colorMode: colorMode
      )
      terminal.write(render(globals: globals))
    case .help:
      terminal.write(ConsoleHelp.render() + "\n")
    case .quit:
      queue.requestGracefulStop()
      terminal.write("console: draining queue\n")
      return true
    case .forceQuit:
      queue.forceStop()
      terminal.write("console: cancelling queued work\n")
      return true
    }
    return false
  }

  private static func contextValue(
    _ field: InteractiveGlobalField,
    current: String?,
    editor: LineEditor,
    terminal: any TerminalBackend,
    commandIO: ConsoleCommandIO,
    maximumCharacters: Int
  ) throws -> String? {
    let aliases = field.interactiveAliases
    let currentCanonical = current ?? "default"
    let currentDisplay = aliases.displayValue(for: currentCanonical)
    let result = try readLine(
      editor: editor,
      terminal: terminal,
      commandIO: commandIO,
      prompt: editor.prompt("\(aliases.name) [\(currentDisplay)]"),
      help: aliases.help,
      maximumCharacters: maximumCharacters,
      history: [],
      suggestions: { source in
        field.canonicalChoices.compactMap { canonical in
          let display = aliases.displayValue(for: canonical)
          guard
            source.isEmpty
              || canonical.localizedCaseInsensitiveContains(source)
              || display.localizedCaseInsensitiveContains(source)
          else { return nil }
          return LineEditorSuggestion(
            value: display,
            summary: display == canonical ? nil : canonical
          )
        }
      }
    )
    guard case .submitted(let value) = result else { return current }
    if value.isEmpty { return current }
    let canonical = aliases.canonicalValue(for: value) ?? value
    return canonical == "default" ? nil : canonical
  }

  private static func loadConfiguration(
    for globals: CommandGlobalOptions
  ) throws -> RuntimeConfiguration {
    try ConfigurationStore.load(
      from: globals.configurationPath.map(URL.init(fileURLWithPath:))
        ?? ConfigurationStore.defaultURL
    )
  }

  private static func selectedWorldID(
    globals: CommandGlobalOptions,
    configuration: RuntimeConfiguration
  ) throws -> String? {
    let catalog = try WorldCatalogStore(maximumBytes: configuration.runtime.maximumWorldBytes)
    guard !catalog.document.worlds.isEmpty else { return nil }
    return try catalog.selected(globals.worldID).id
  }

  private static func render(snapshot: ConsoleQueueSnapshot) -> String {
    let pending = snapshot.pendingIDs.map { "#\($0)" }.joined(separator: ", ")
    return "Queue  \(snapshot.paused ? "paused" : "active")\n"
      + "  running  \(snapshot.runningID.map { "#\($0)" } ?? "none")\n"
      + "  pending  \(pending.isEmpty ? "none" : pending)\n"
      + "  barrier  \(snapshot.barrierID.map { "#\($0)" } ?? "none")\n"
  }

  private static func render(globals: CommandGlobalOptions) -> String {
    "context:\n"
      + "  config: \(yaml(globals.configurationPath ?? ConfigurationStore.defaultURL.path))\n"
      + "  product_root: \(yaml(MikroKhorosPaths.root.path))\n"
      + "  world: \(globals.worldID.map(yaml) ?? "null")\n"
  }

  private static func yaml(_ value: String) -> String {
    "\""
      + value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
      + "\""
  }

  private static func writeConsoleIssue(
    error: Error,
    terminal: any TerminalBackend
  ) {
    if let error = error as? MikroKhorosError {
      writeConsoleIssue(
        code: error.issue.code,
        message: error.issue.message,
        terminal: terminal
      )
    } else {
      writeConsoleIssue(
        code: "console.failed", message: "console operation failed", terminal: terminal)
    }
  }

  private static func writeConsoleIssue(
    code: String,
    message: String,
    terminal: any TerminalBackend
  ) {
    let boundedCode = String(code.prefix(128))
    let boundedMessage = String(message.prefix(1_024))
    terminal.write(
      "error:\n  code: \(yaml(boundedCode))\n  message: \(yaml(boundedMessage))\n  details: {}\n"
    )
  }
}

private enum CompletionResolver {
  static func values(
    for completion: CommandCompletion,
    globals: CommandGlobalOptions,
    configuration: RuntimeConfiguration,
    source: String = ""
  ) -> [String] {
    switch completion {
    case .none: return []
    case .choices(let values): return values
    case .configurationKey: return ConfigurationKey.all.map(\.path).sorted()
    case .adapterID: return AIAdapterCatalog.definitions.map(\.id).sorted()
    case .filesystemPath:
      return filesystemValues(
        source: source,
        limit: configuration.console.maximumSuggestions
      )
    case .agentID:
      let agents =
        (try? AgentStore(
          maximumBytes: configuration.runtime.maximumAgentStoreBytes
        ).allAgents()) ?? []
      return humanValues(agents, id: \.id, name: { $0.name })
    case .inventoryID:
      let objects = inventory(configuration)?.allInventoryObjects() ?? []
      return humanValues(objects, id: \.id, name: { $0.name })
    case .inventoryFolderID:
      guard let inventory = inventory(configuration) else { return [] }
      return inventory.allInventoryFolders().flatMap { folder in
        [folder.id, inventory.folderPath(for: folder.id)]
      }.sorted()
    case .packageID:
      return inventory(configuration)?.installedPackages.map { $0.manifest.id }.sorted() ?? []
    case .worldObjectID:
      guard let harness = try? runtime(globals: globals, configuration: configuration)?.harness
      else {
        return []
      }
      return humanValues(
        harness.objects.filter { $0 !== harness.world },
        id: \.hash,
        name: { $0.name }
      )
    case .merchantID:
      guard let runtime = try? runtime(globals: globals, configuration: configuration) else {
        return []
      }
      let merchants = runtime.harness.objects.filter { $0 is MerchantObject }
      return humanValues(merchants, id: \.hash, name: { $0.name })
    case .reportID:
      let reports = (try? runtime(globals: globals, configuration: configuration))?.reports ?? []
      return reports.map {
        HumanSelectorResolver.uniquePrefix(for: $0, among: reports, id: \.id)
      }.sorted()
    case .restockRuleID:
      let rules =
        (try? runtime(globals: globals, configuration: configuration)).map {
          Array($0.restockRules.values)
        } ?? []
      return rules.map {
        HumanSelectorResolver.uniquePrefix(for: $0, among: rules, id: \.id)
      }.sorted()
    case .worldID:
      guard
        let catalog = try? WorldCatalogStore(
          maximumBytes: configuration.runtime.maximumWorldBytes
        )
      else { return [] }
      return humanValues(catalog.allWorlds(), id: \.id, name: { $0.name })
    case .worldTemplateID:
      return WorldTemplateCatalog.installedCLI().definitions.map(\.id)
    }
  }

  private static func humanValues<Value>(
    _ values: [Value],
    id: (Value) -> String,
    name: (Value) -> String
  ) -> [String] {
    values.map { value in
      let candidate = name(value)
      let uniqueName =
        values.filter {
          name($0).caseInsensitiveCompare(candidate) == .orderedSame
        }.count == 1
      return uniqueName
        ? candidate
        : HumanSelectorResolver.uniquePrefix(for: value, among: values, id: id)
    }.sorted()
  }

  private static func inventory(_ configuration: RuntimeConfiguration) -> InventoryStore? {
    try? InventoryStore(limits: configuration.runtime, runtimeRegistry: .installedCLI())
  }

  private static func treasuryAuthority(for configuration: RuntimeConfiguration) throws
    -> TreasuryAuthorityState
  {
    let treasuryAuthorityStore = try TreasuryAuthorityStore(
      maximumBytes: configuration.runtime.maximumWorldBytes
    )
    do {
      return try treasuryAuthorityStore.load()
    } catch {
      guard (error as? MikroKhorosError)?.issue.code == "treasury.authority_not_found" else {
        throw error
      }
      let agents = try AgentStore(maximumBytes: configuration.runtime.maximumAgentStoreBytes)
      let worlds = try WorldCatalogStore(maximumBytes: configuration.runtime.maximumWorldBytes)
      return try treasuryAuthorityStore.bootstrap(
        confirmNoExistingEconomy: agents.allAgents().isEmpty && worlds.document.worlds.isEmpty
      )
    }
  }

  private static func runtime(
    globals: CommandGlobalOptions,
    configuration: RuntimeConfiguration
  ) throws -> WorldRuntime? {
    guard
      let inventory = inventory(configuration),
      let catalog = try? WorldCatalogStore(maximumBytes: configuration.runtime.maximumWorldBytes),
      let record = try? catalog.selected(globals.worldID),
      let url = try? WorldStore.url(for: record.id),
      let document = try? WorldStore.load(
        from: url,
        maximumBytes: configuration.runtime.maximumWorldBytes
      )
    else {
      return nil
    }
    let treasuryAuthority = try Self.treasuryAuthority(for: configuration)
    return try? WorldRuntime(
      document: document,
      configuration: configuration,
      inventory: inventory,
      treasuryAuthority: treasuryAuthority
    )
  }

  private static func filesystemValues(source: String, limit: Int) -> [String] {
    // The process directory is not application state and is not inspected until
    // the human has explicitly begun entering a filesystem value.
    guard !source.isEmpty else { return [] }
    let expanded = NSString(string: source).expandingTildeInPath
    let current = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath,
      isDirectory: true
    )
    let enteredURL = URL(fileURLWithPath: expanded, relativeTo: current).standardizedFileURL
    let directory: URL
    let prefix: String
    if source.hasSuffix("/") || source.hasSuffix("\\") {
      directory = enteredURL
      prefix = ""
    } else {
      directory = enteredURL.deletingLastPathComponent()
      prefix = enteredURL.lastPathComponent
    }
    let base: String
    if source.hasSuffix("/") || source.hasSuffix("\\") {
      base = source
    } else if let slash = source.lastIndex(where: { $0 == "/" || $0 == "\\" }) {
      base = String(source[...slash])
    } else {
      base = ""
    }
    return
      ((try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )) ?? []).filter { candidate in
        prefix.isEmpty || candidate.lastPathComponent.localizedCaseInsensitiveContains(prefix)
      }.prefix(limit).map { candidate in
        base + candidate.lastPathComponent + (candidate.hasDirectoryPath ? "/" : "")
      }.sorted()
  }
}

extension NSLock {
  fileprivate func withConsoleLock<Result>(_ body: () -> Result) -> Result {
    lock()
    defer { unlock() }
    return body()
  }
}

extension NSCondition {
  fileprivate func withConsoleCondition<Result>(_ body: () -> Result) -> Result {
    lock()
    defer { unlock() }
    return body()
  }
}
