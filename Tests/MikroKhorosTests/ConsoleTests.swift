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
import XCTest

@testable import MikroKhoros
@testable import MikroKhorosCLIKit

final class ConsoleTests: XCTestCase {
  func testCatalogIsCompleteUniqueAndGeneratesHelp() {
    let definitions = CommandCatalog.all

    XCTAssertEqual(definitions.count, CommandKind.allCases.count)
    XCTAssertEqual(Set(definitions.map(\.kind)), Set(CommandKind.allCases))
    XCTAssertEqual(Set(definitions.map(\.command)).count, definitions.count)
    for definition in definitions {
      XCTAssertEqual(CommandCatalog.definition(for: definition.kind), definition)
      XCTAssertEqual(Set(definition.fields.map(\.id)).count, definition.fields.count)
      XCTAssertFalse(definition.path.isEmpty)
      XCTAssertFalse(definition.summary.isEmpty)
      for field in definition.fields {
        XCTAssertFalse(field.label.isEmpty, "\(definition.command).\(field.id)")
        XCTAssertFalse(field.interactiveHelp.isEmpty, "\(definition.command).\(field.id)")
        let aliases = field.interactiveAliases
        let displayValues = aliases.values.values.map { $0.lowercased() }
        XCTAssertEqual(
          Set(displayValues).count,
          displayValues.count,
          "\(definition.command).\(field.id) has ambiguous interactive values"
        )
        for (canonical, display) in aliases.values {
          XCTAssertEqual(aliases.displayValue(for: canonical), display)
          XCTAssertEqual(aliases.canonicalValue(for: display), canonical)
          XCTAssertEqual(aliases.canonicalValue(for: canonical), canonical)
        }
      }
      let positionalFields = definition.fields.filter {
        if case .positional = $0.syntax { return true }
        return false
      }
      if let repeated = positionalFields.firstIndex(where: { $0.cardinality == .repeated }) {
        XCTAssertEqual(repeated, positionalFields.index(before: positionalFields.endIndex))
      }
    }
    let help = CommandCatalog.renderHelp(includeAll: true)
    XCTAssertTrue(help.contains("khoros [--config <file>]"))
    for definition in definitions { XCTAssertTrue(help.contains(definition.command)) }

    for field in InteractiveGlobalField.allCases {
      let aliases = field.interactiveAliases
      XCTAssertTrue(field.cliSpelling.hasPrefix("--"))
      XCTAssertFalse(aliases.name.isEmpty)
      XCTAssertFalse(aliases.help.isEmpty)
      for canonical in field.canonicalChoices {
        let display = aliases.displayValue(for: canonical)
        XCTAssertEqual(
          aliases.canonicalValue(for: display),
          canonical,
          "\(field.cliSpelling) cannot translate its interactive value"
        )
      }
    }
  }

  func testInteractiveAliasesPreserveCLISpellingAndTranslateHumanValues() throws {
    let definition = CommandCatalog.definition(for: .worldCreate)
    let field = try XCTUnwrap(definition.fields.last)

    XCTAssertEqual(field.syntax, .flag("--yes"))
    XCTAssertEqual(field.cliSpelling, "--yes")
    XCTAssertEqual(field.label, "confirmation behavior")
    XCTAssertEqual(field.interactiveAliases.displayValue(for: "false"), "ask me first")
    XCTAssertEqual(
      field.interactiveAliases.displayValue(for: "true"), "proceed without asking")
    XCTAssertEqual(field.interactiveAliases.canonicalValue(for: "ask me first"), "false")
    XCTAssertEqual(
      field.interactiveAliases.canonicalValue(for: "proceed without asking"), "true")
    XCTAssertEqual(
      InteractiveConsole.fieldPromptLabel(
        index: definition.fields.count - 1,
        count: definition.fields.count,
        field: field
      ),
      "3/3 confirmation behavior [optional]"
    )

    let agent = try XCTUnwrap(
      CommandCatalog.definition(for: .agentShow).fields.first(where: { $0.id == "agent-id" })
    )
    XCTAssertEqual(agent.label, "agent")
    XCTAssertTrue(agent.interactiveHelp.contains("name"))

    let placement = try XCTUnwrap(
      CommandCatalog.definition(for: .inventoryDeploy).fields.first(where: {
        $0.id == "auto-adapt"
      })
    )
    XCTAssertEqual(placement.label, "occupied-coordinate behavior")
    XCTAssertEqual(
      placement.interactiveAliases.canonicalValue(for: "use nearest free cell"),
      "true"
    )
    let price = try XCTUnwrap(
      CommandCatalog.definition(for: .inventoryRestockCreate).fields.first(where: {
        $0.id == "price"
      })
    )
    XCTAssertTrue(price.interactiveAliases.help.contains("Credit price"))

    let help = CommandCatalog.renderHelp(path: ["world", "create"])
    XCTAssertTrue(help.contains("--yes"))
    XCTAssertTrue(help.contains("Interactive: confirmation behavior"))
    XCTAssertTrue(help.contains("ask me first (false)"))
    XCTAssertTrue(help.contains("proceed without asking (true)"))
  }

  func testGuidedAndOneShotArgumentsReachTheSameParser() throws {
    let globals = CommandGlobalOptions(
      configurationPath: "/tmp/config.json",
      worldID: "abcdef0123456789"
    )
    let guided = InteractiveCommandSubmission(
      commandPath: "agent create",
      values: [
        "name": ["Sol"],
        "max-actions": ["12"],
      ],
      explicitFieldIDs: ["name", "max-actions"],
      globals: globals,
      stopsQueueOnError: false
    )
    let guidedArguments = try CommandParser.arguments(for: guided)
    let oneShotArguments =
      globals.arguments + [
        "agent", "create", "Sol", "--max-actions", "12",
      ]

    XCTAssertEqual(guidedArguments, oneShotArguments)
    XCTAssertEqual(
      try CommandParser.parse(guidedArguments), try CommandParser.parse(oneShotArguments))
  }

  func testParserRejectsRemovedCommandTombstones() {
    for oldPath in [
      ["message", "send"],
      ["message", "orient"],
      ["coin", "grant"],
      ["objective", "post"],
      ["objective", "list"],
    ] {
      XCTAssertThrowsError(try CommandParser.parse(oldPath)) { error in
        let issue = (error as? MikroKhorosError)?.issue
        XCTAssertEqual(issue?.code, "command.removed")
        XCTAssertTrue(issue?.message.contains("world object action") == true)
        XCTAssertTrue(issue?.message.contains("world object view") == true)
        XCTAssertTrue(issue?.message.contains("world object interface") == true)
      }
    }
  }

  func testNewInventoryAndWorldObjectFormsUseTheSharedParser() throws {
    let globals = CommandGlobalOptions(
      worldID: String(repeating: "a", count: 32)
    )
    let fork = InteractiveCommandSubmission(
      commandPath: "inventory fork",
      values: [
        "inventory-id": [String(repeating: "b", count: 32)],
        "name": ["Project"],
        "folder": ["projects/world-a"],
      ],
      explicitFieldIDs: ["inventory-id", "name", "folder"],
      globals: globals,
      stopsQueueOnError: false
    )
    XCTAssertEqual(
      try CommandParser.parse(CommandParser.arguments(for: fork)).kind,
      .inventoryFork
    )

    let action = InteractiveCommandSubmission(
      commandPath: "world object action run",
      values: [
        "world-object-id": [String(repeating: "c", count: 32)],
        "action": ["set-output-delta"],
        "input": ["x=1", "y=-1"],
      ],
      explicitFieldIDs: ["world-object-id", "action", "input"],
      globals: globals,
      stopsQueueOnError: true
    )
    let parsed = try CommandParser.parse(CommandParser.arguments(for: action))
    XCTAssertEqual(parsed.kind, .worldObjectActionRun)
    XCTAssertEqual(parsed.globals, globals)
  }

  func testEmptyRequiredGuidedFieldRemainsOmittedUntilExecution() throws {
    let submission = InteractiveCommandSubmission(
      commandPath: "agent show",
      values: [:],
      globals: .init(),
      stopsQueueOnError: false
    )

    XCTAssertEqual(try CommandParser.arguments(for: submission), ["agent", "show"])
    XCTAssertThrowsError(try CommandParser.parse(["agent", "show"]))
  }

  func testSharedParserRejectsInvalidChoiceWhenQueuedExecutionBegins() throws {
    let submission = InteractiveCommandSubmission(
      commandPath: "inventory restock set",
      values: ["rule-id": ["rule"], "enabled": ["sometimes"]],
      globals: .init(),
      stopsQueueOnError: false
    )
    let arguments = try CommandParser.arguments(for: submission)
    XCTAssertThrowsError(try CommandParser.parse(arguments))
  }

  func testResolvedDefaultIsCapturedBeforeConfigurationChanges() throws {
    let initial = RuntimeConfiguration.defaults
    let changed = try ConfigurationKey.agentMaximumActionsPerResponse.setting(99, in: initial)
    let defaultValue = try XCTUnwrap(
      CommandCatalog.definition(for: .agentCreate).fields.first {
        $0.id == "max-actions"
      }?.defaultValue
    )
    let captured = defaultValue.resolve(
      in: CommandResolutionContext(configuration: initial, globals: .init(), worldID: nil)
    )
    let later = defaultValue.resolve(
      in: CommandResolutionContext(configuration: changed, globals: .init(), worldID: nil)
    )
    let submission = InteractiveCommandSubmission(
      commandPath: "agent create",
      values: ["name": ["A"], "max-actions": [try XCTUnwrap(captured)]],
      globals: .init(),
      stopsQueueOnError: false
    )

    XCTAssertNotEqual(captured, later)
    XCTAssertTrue(try CommandParser.arguments(for: submission).contains(try XCTUnwrap(captured)))
  }

  func testLineEditorStateHandlesUnicodeMovementCompletionAndHistory() {
    var state = LineEditorState(text: "a界")
    XCTAssertEqual(state.apply(.left, suggestions: [], history: [], maximumCharacters: 10), .none)
    XCTAssertEqual(
      state.apply(.character("🙂"), suggestions: [], history: [], maximumCharacters: 10),
      .none
    )
    XCTAssertEqual(state.text, "a🙂界")
    XCTAssertEqual(
      state.apply(.backspace, suggestions: [], history: [], maximumCharacters: 10), .none)
    XCTAssertEqual(state.text, "a界")

    let suggestions = [LineEditorSuggestion(value: "agent create")]
    XCTAssertEqual(
      state.apply(
        .tab,
        suggestions: suggestions,
        suggestionsVisible: true,
        history: [],
        maximumCharacters: 20
      ),
      .none
    )
    XCTAssertEqual(state.text, "agent create")

    var historyState = LineEditorState()
    XCTAssertEqual(
      historyState.apply(.up, suggestions: [], history: ["status"], maximumCharacters: 20),
      .none
    )
    XCTAssertEqual(historyState.text, "status")

    XCTAssertEqual(
      historyState.apply(
        .up,
        suggestions: [
          LineEditorSuggestion(value: "status"),
          LineEditorSuggestion(value: "world show"),
        ],
        suggestionsVisible: true,
        history: ["status", "world list"],
        maximumCharacters: 20
      ),
      .none
    )
    XCTAssertEqual(historyState.text, "world list")
    XCTAssertEqual(historyState.selectedHistory, 1)

    XCTAssertEqual(
      historyState.apply(
        .down,
        suggestions: [
          LineEditorSuggestion(value: "status"),
          LineEditorSuggestion(value: "world show"),
        ],
        suggestionsVisible: true,
        history: ["status", "world list"],
        maximumCharacters: 20
      ),
      .none
    )
    XCTAssertEqual(historyState.text, "status")
    XCTAssertEqual(historyState.selectedHistory, 0)

    XCTAssertEqual(
      historyState.apply(
        .down,
        suggestions: [
          LineEditorSuggestion(value: "status"),
          LineEditorSuggestion(value: "world show"),
        ],
        suggestionsVisible: true,
        history: ["status", "world list"],
        maximumCharacters: 20
      ),
      .none
    )
    XCTAssertEqual(historyState.text, "")
    XCTAssertNil(historyState.selectedHistory)
  }

  func testLineEditorArrowsSeparateHiddenHistoryFromVisibleCompletions() {
    let suggestions = [
      LineEditorSuggestion(value: "agent show"),
      LineEditorSuggestion(value: "world show"),
    ]
    let history = ["status", "world list"]

    var historyState = LineEditorState(text: "draft")
    XCTAssertEqual(
      historyState.apply(
        .up,
        suggestions: suggestions,
        suggestionsVisible: false,
        history: history,
        maximumCharacters: 40
      ),
      .none
    )
    XCTAssertEqual(historyState.text, "status")
    XCTAssertEqual(historyState.historyDraft, "draft")

    XCTAssertEqual(
      historyState.apply(
        .down,
        suggestions: suggestions,
        suggestionsVisible: true,
        history: history,
        maximumCharacters: 40
      ),
      .none
    )
    XCTAssertEqual(historyState.text, "draft")
    XCTAssertNil(historyState.historyDraft)
    XCTAssertFalse(historyState.paletteRequested)

    var completionState = LineEditorState(text: "a")
    XCTAssertEqual(
      completionState.apply(
        .down,
        suggestions: suggestions,
        suggestionsVisible: true,
        history: history,
        maximumCharacters: 40
      ),
      .none
    )
    XCTAssertEqual(completionState.selectedSuggestion, 1)
    XCTAssertEqual(completionState.text, "a")
  }

  func testTabAcceptsVisibleCompletionAndOnlyOpensHiddenPalette() {
    let suggestions = [LineEditorSuggestion(value: "ask me first", summary: "default")]

    var guidedField = LineEditorState()
    XCTAssertEqual(
      guidedField.apply(
        .tab,
        suggestions: suggestions,
        suggestionsVisible: true,
        history: [],
        maximumCharacters: 40
      ),
      .none
    )
    XCTAssertEqual(guidedField.text, "ask me first")

    var rootPrompt = LineEditorState()
    XCTAssertEqual(
      rootPrompt.apply(
        .tab,
        suggestions: suggestions,
        suggestionsVisible: false,
        history: [],
        maximumCharacters: 40
      ),
      .none
    )
    XCTAssertEqual(rootPrompt.text, "")
    XCTAssertTrue(rootPrompt.paletteRequested)

    XCTAssertEqual(
      rootPrompt.apply(
        .tab,
        suggestions: suggestions,
        suggestionsVisible: true,
        history: [],
        maximumCharacters: 40
      ),
      .none
    )
    XCTAssertEqual(rootPrompt.text, "ask me first")
  }

  func testTokenizerSupportsQuotedCompleteCommandsWithoutShellExpansion() throws {
    XCTAssertEqual(
      try CommandLineTokenizer.tokenize(
        "world object action run 0123456789abcdef0123456789abcdef world-interface --input value"
      ),
      [
        "world", "object", "action", "run", "0123456789abcdef0123456789abcdef", "world-interface",
        "--input", "value",
      ]
    )
    XCTAssertEqual(
      try CommandLineTokenizer.tokenize("inventory configure lamp --set room\\ name=studio"),
      ["inventory", "configure", "lamp", "--set", "room name=studio"]
    )
    XCTAssertThrowsError(
      try CommandLineTokenizer.tokenize("world object action run 0123456789abcdef 'open")
    )
  }

  func testAgentCreateCatalogHasNoCoinInputs() {
    let fieldIDs = Set(CommandCatalog.definition(for: .agentCreate).fields.map(\.id))
    XCTAssertFalse(fieldIDs.contains("coin"))
    XCTAssertFalse(fieldIDs.contains("infinite-coin"))
  }

  func testTerminalCellWidthAndHorizontalLayoutRespectGraphemes() throws {
    XCTAssertEqual(TerminalCellWidth.measure("e\u{301}"), 1)
    XCTAssertEqual(TerminalCellWidth.measure("界"), 2)
    XCTAssertEqual(TerminalCellWidth.measure("👩‍💻"), 2)
    XCTAssertEqual(TerminalCellWidth.ellipsized("abcdef", fitting: 4), "abc…")

    let terminal = FakeTerminalBackend(events: [.interrupt])
    terminal.dimensions = TerminalDimensions(columns: 40, rows: 10)
    let editor = LineEditor(terminal: terminal)
    XCTAssertEqual(
      try editor.readLine(
        prompt: "khoros › ",
        maximumCharacters: 128,
        suggestions: { _ in
          [
            LineEditorSuggestion(
              value: "a very long completion name", summary: String(repeating: "x", count: 100))
          ]
        },
        showSuggestionsWhenEmpty: false
      ),
      .interrupted("")
    )
    XCTAssertEqual(terminal.frames.first?.rows.count, 1)
    XCTAssertTrue(
      terminal.frames.allSatisfy { frame in
        frame.rows.allSatisfy { TerminalCellWidth.measure(stripANSI($0)) <= 40 }
      })
  }

  func testTerminalNormalizesLogicalLineEndings() {
    XCTAssertEqual(
      SystemTerminalBackend.normalizedTerminalText("one\ntwo\r\nthree\r"),
      "one\r\ntwo\r\nthree\r"
    )
  }

  func testTerminalFrameAlwaysStartsPaintingAtColumnZero() {
    let encoded = SystemTerminalBackend.encodedFrame(
      TerminalFrame(
        rows: ["khoros › a", "  › adapters"],
        cursorRow: 0,
        cursorColumn: 10
      )
    )

    XCTAssertTrue(encoded.hasPrefix("\u{1B}[?25l\r\u{1B}[2Kkhoros › a"))
    XCTAssertTrue(encoded.contains("\r\n\u{1B}[2K  › adapters"))
  }

  func testIdleControlCExitsConsoleAndRestoresTerminal() async {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let terminal = TestTerminalBackend()
    terminal.append([.interrupt])

    let status = await InteractiveConsole.run(
      initialGlobals: CommandGlobalOptions(
        configurationPath: directory.appendingPathComponent("config.json").path
      ),
      io: StandardCommandIO.shared,
      terminal: terminal,
      historyURL: directory.appendingPathComponent("history.json")
    )

    XCTAssertEqual(status, 0)
    XCTAssertEqual(terminal.beginCount, 1)
    XCTAssertGreaterThanOrEqual(terminal.endCount, 1)
    XCTAssertTrue(terminal.capturedOutput.contains("^C"))
  }

  func testMachineOutputModesShareCanonicalPayloadAndNeverUseANSI() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let previousProductHome = ProcessInfo.processInfo.environment["MIKROKHOROS_HOME"]
    setConsoleProductHome(directory.appendingPathComponent("home").path)
    defer { setConsoleProductHome(previousProductHome) }
    let common = [
      "--config", directory.appendingPathComponent("config.json").path,
    ]
    let yamlIO = RecordingCommandIO(isInteractive: false)
    let jsonIO = RecordingCommandIO(isInteractive: false)
    let yamlStatus = await CommandExecutor.execute(
      arguments: common + ["--output", "yaml", "--color", "always", "status"],
      io: yamlIO
    )
    let jsonStatus = await CommandExecutor.execute(
      arguments: common + ["--output=json", "status"],
      io: jsonIO
    )
    XCTAssertEqual(yamlStatus, 0)
    XCTAssertEqual(jsonStatus, 0)
    XCTAssertFalse(yamlIO.output.contains("\u{1B}"))
    XCTAssertFalse(jsonIO.output.contains("\u{1B}"))
    let yamlValue = try XCTUnwrap(StructuredTextParser.parse(yamlIO.output))
    let jsonValue = try JSONDecoder().decode(JSONValue.self, from: Data(jsonIO.output.utf8))
    XCTAssertEqual(yamlValue, jsonValue)
  }

  func testHumanRendererQuotesTerminalControlsAsData() {
    let result = CommandResult(
      command: .status,
      payload: .object(["name": .string("unsafe\u{1B}[31mname\u{7}")]),
      exitStatus: 0,
      humanPresentation: HumanPresentation(title: "Status", payload: nil)
    )
    let rendered = HumanResultRenderer.render(result, color: false, fallback: "")
    XCTAssertFalse(rendered.contains("\u{1B}"))
    XCTAssertFalse(rendered.contains("\u{7}"))
    XCTAssertTrue(rendered.contains("unsafe[31mname"))
  }

  func testPresentationUnicodeModeProvidesAnASCIIOnlyFallback() throws {
    let configuration = try RuntimeConfiguration.defaults.settingPresentationValue(
      .unicode, to: "never")
    let environment = PresentationEnvironment.resolve(
      globals: CommandGlobalOptions(),
      configuration: configuration,
      isInteractive: true,
      environment: ["TERM": "xterm-256color", "LANG": "en_US.UTF-8"]
    )
    XCTAssertFalse(environment.unicodeEnabled)

    let result = CommandResult(
      command: .status,
      payload: .object(["items": .array([.null, .string("value")])]),
      exitStatus: 0,
      humanPresentation: HumanPresentation(title: "Status", payload: nil)
    )
    let rendered = HumanResultRenderer.render(
      result, color: false, unicode: environment.unicodeEnabled, fallback: "")
    XCTAssertTrue(rendered.contains("- -"))
    XCTAssertFalse(rendered.contains("•"))
    XCTAssertFalse(rendered.contains("—"))
  }

  func testLineEditorRestoresDraftAfterSerializedOutput() throws {
    let terminal = TestTerminalBackend()
    let editor = LineEditor(terminal: terminal)
    terminal.append(events(for: "sta"))
    var ticks = 0
    let interrupted = try editor.readLine(
      prompt: "khoros › ",
      maximumCharacters: 20,
      onTick: {
        ticks += 1
        return ticks > 3
      }
    )
    guard case .suspended(let saved) = interrupted else {
      return XCTFail("editor did not preserve the draft")
    }
    XCTAssertEqual(saved.text, "sta")

    terminal.append(events(for: "tus\n"))
    XCTAssertEqual(
      try editor.readLine(
        prompt: "khoros › ",
        initialState: saved,
        maximumCharacters: 20
      ),
      .submitted("status")
    )
  }

  func testForegroundPromptBrokerExcludesHiddenInputFromOutput() async throws {
    let io = ConsoleCommandIO(maximumInputCharacters: 64)
    let task = Task.detached { try io.readLine(prompt: "Secret: ", hidden: true) }
    try await waitUntil(timeout: .seconds(1)) { io.foregroundRequest() != nil }
    let request = try XCTUnwrap(io.foregroundRequest())
    XCTAssertEqual(request.prompt, "Secret: ")
    XCTAssertTrue(request.hidden)
    io.answer(requestID: request.id, value: "credential")

    let value = try await task.value
    XCTAssertEqual(value, "credential")
    XCTAssertFalse(io.drainOutput().contains("credential"))
  }

  func testHistoryPersistsOnlyExplicitSafeFields() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("console-history.json")
    let store = try ConsoleHistoryStore(url: url, configuration: .defaults)
    let definition = CommandCatalog.definition(for: .worldObjectActionRun)
    let objectID = String(repeating: "a", count: 32)
    let submission = InteractiveCommandSubmission(
      commandPath: definition.command,
      values: [
        "world-object-id": [objectID],
        "action": ["set-output-delta"],
        "input": ["x=1", "y=2"],
      ],
      explicitFieldIDs: ["world-object-id", "action", "input"],
      globals: .init(),
      stopsQueueOnError: false
    )

    try store.append(submission, definition: definition)
    let entry = try XCTUnwrap(store.allEntries().last)
    XCTAssertEqual(entry.values["world-object-id"], [objectID])
    XCTAssertEqual(entry.values["action"], ["set-output-delta"])
    XCTAssertNil(entry.values["input"])
    XCTAssertFalse(
      String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("x=1"))
    #if !os(Windows)
      let permissions = try XCTUnwrap(
        FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
      )
      XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    #endif
  }

  func testHistoryRejectsUnknownDataAndEnforcesConfiguredRetention() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("console-history.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("{\"version\":1,\"entries\":[],\"unknown\":true}".utf8).write(to: url)
    XCTAssertThrowsError(
      try ConsoleHistoryStore(url: url, configuration: .defaults)
    )

    try FileManager.default.removeItem(at: url)
    let configuration = try RuntimeConfiguration.defaults.settingConsoleValue(
      .maximumHistoryEntries,
      to: 2
    )
    let store = try ConsoleHistoryStore(url: url, configuration: configuration)
    let definition = CommandCatalog.definition(for: .agentShow)
    for id in ["first", "second", "third"] {
      try store.append(
        InteractiveCommandSubmission(
          commandPath: definition.command,
          values: ["agent-id": [id]],
          explicitFieldIDs: ["agent-id"],
          globals: .init(),
          stopsQueueOnError: false
        ),
        definition: definition
      )
    }
    XCTAssertEqual(store.allEntries().count, 2)
    XCTAssertEqual(store.allEntries().first?.values["agent-id"], ["second"])
  }

  func testHistoryByteLimitTrimsOldestEntries() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("console-history.json")
    let configuration = try RuntimeConfiguration.defaults.settingRuntimeLimit(
      .maximumConsoleHistoryBytes,
      to: 100
    )
    let store = try ConsoleHistoryStore(url: url, configuration: configuration)
    let definition = CommandCatalog.definition(for: .agentShow)
    try store.append(
      InteractiveCommandSubmission(
        commandPath: definition.command,
        values: ["agent-id": [String(repeating: "a", count: 50)]],
        explicitFieldIDs: ["agent-id"],
        globals: .init(),
        stopsQueueOnError: false
      ),
      definition: definition
    )

    XCTAssertTrue(store.allEntries().isEmpty)
    XCTAssertLessThanOrEqual(try Data(contentsOf: url).count, 100)
  }

  func testExplicitConsoleRequiresATerminalAndNoArgumentBatchPrintsHelp() async {
    let io = RecordingCommandIO(isInteractive: false)

    let explicitStatus = await CommandExecutor.execute(arguments: ["console"], io: io)
    XCTAssertEqual(explicitStatus, 1)
    XCTAssertTrue(io.error.contains("console.tty_required"))
    io.reset()
    let batchStatus = await CommandExecutor.execute(arguments: [], io: io)
    XCTAssertEqual(batchStatus, 0)
    XCTAssertTrue(io.output.contains("mikrokhoros"))
    io.reset()
    let contextualHelpStatus = await CommandExecutor.execute(
      arguments: ["--workspace", "/tmp/workspace.json", "--help"],
      io: io
    )
    XCTAssertEqual(contextualHelpStatus, 1)
    XCTAssertTrue(io.error.contains("cli.option_removed"))
    XCTAssertTrue(io.error.contains("world create"))
  }

  func testOrdinaryErrorContinuesWithTheNextQueuedCommand() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let previousProductHome = ProcessInfo.processInfo.environment["MIKROKHOROS_HOME"]
    setConsoleProductHome(directory.appendingPathComponent("home").path)
    defer { setConsoleProductHome(previousProductHome) }
    let terminal = TestTerminalBackend()
    terminal.append(events(for: "unknown\nstatus\n"))
    let globals = CommandGlobalOptions(
      configurationPath: directory.appendingPathComponent("config.json").path
    )
    let task = Task {
      await InteractiveConsole.run(
        initialGlobals: globals,
        io: StandardCommandIO.shared,
        terminal: terminal,
        historyURL: directory.appendingPathComponent("history.json")
      )
    }

    try await waitUntil(timeout: .seconds(3)) {
      terminal.capturedOutput.contains("#2  status  success")
    }
    terminal.append(events(for: ":quit\n"))
    let status = await task.value
    XCTAssertEqual(status, 0)
    let output = terminal.capturedOutput
    XCTAssertTrue(output.contains("#1  unknown  error"))
    XCTAssertTrue(output.contains("#2  status  success"))
  }

  func testGracefulQuitDrainsAPausedQueue() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let previousProductHome = ProcessInfo.processInfo.environment["MIKROKHOROS_HOME"]
    setConsoleProductHome(directory.appendingPathComponent("home").path)
    defer { setConsoleProductHome(previousProductHome) }
    let terminal = TestTerminalBackend()
    terminal.append(events(for: ":pause\nstatus\n:quit\n"))
    let task = Task {
      await InteractiveConsole.run(
        initialGlobals: CommandGlobalOptions(
          configurationPath: directory.appendingPathComponent("config.json").path
        ),
        io: StandardCommandIO.shared,
        terminal: terminal,
        historyURL: directory.appendingPathComponent("history.json")
      )
    }

    let status = await task.value
    XCTAssertEqual(status, 0)
    XCTAssertTrue(terminal.capturedOutput.contains("#1  status  success"))
  }

  func testFullQueueRetainsCompletedFormWhileControlsRemainAvailable() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let previousProductHome = ProcessInfo.processInfo.environment["MIKROKHOROS_HOME"]
    setConsoleProductHome(directory.appendingPathComponent("home").path)
    defer { setConsoleProductHome(previousProductHome) }
    let configurationURL = directory.appendingPathComponent("config.json")
    let configuration = try RuntimeConfiguration.defaults.settingConsoleValue(
      .maximumQueueDepth,
      to: 1
    )
    try ConfigurationStore.save(configuration, to: configurationURL)
    let terminal = TestTerminalBackend()
    terminal.append(events(for: ":pause\nstatus\nstatus\n"))
    let task = Task {
      await InteractiveConsole.run(
        initialGlobals: CommandGlobalOptions(
          configurationPath: configurationURL.path
        ),
        io: StandardCommandIO.shared,
        terminal: terminal,
        historyURL: directory.appendingPathComponent("history.json")
      )
    }

    try await waitUntil(timeout: .seconds(3)) {
      terminal.capturedOutput.contains("queue full › ")
    }
    terminal.append(events(for: ":clear\n:resume\n:quit\n"))
    let status = await task.value
    XCTAssertEqual(status, 0)
    let output = terminal.capturedOutput
    XCTAssertTrue(output.contains("completed form is retained"))
    XCTAssertTrue(output.contains("cleared: 1"))
    XCTAssertFalse(output.contains("#1  status  success"))
    XCTAssertTrue(output.contains("#2  status  success"))
  }

  func testBarrierPausesRetainsAndResumesFIFOQueue() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let previousProductHome = ProcessInfo.processInfo.environment["MIKROKHOROS_HOME"]
    setConsoleProductHome(directory.appendingPathComponent("home").path)
    defer { setConsoleProductHome(previousProductHome) }
    let terminal = TestTerminalBackend()
    terminal.append(events(for: "& unknown\nstatus\n"))
    let globals = CommandGlobalOptions(
      configurationPath: directory.appendingPathComponent("config.json").path
    )
    let task = Task {
      await InteractiveConsole.run(
        initialGlobals: globals,
        io: StandardCommandIO.shared,
        terminal: terminal,
        historyURL: directory.appendingPathComponent("history.json")
      )
    }

    try await waitUntil(timeout: .seconds(3)) {
      terminal.capturedOutput.contains("#1  & unknown  error")
    }
    terminal.append(events(for: ":queue\n:resume\n:quit\n"))
    let status = await task.value
    XCTAssertEqual(status, 0)
    let output = terminal.capturedOutput
    XCTAssertTrue(output.contains("barrier  #1"))
    XCTAssertTrue(output.contains("pending  #2"))
    XCTAssertTrue(output.contains("configuration"))
    XCTAssertTrue(output.contains("#2  status  success"))
    XCTAssertEqual(terminal.beginCount, 1)
    XCTAssertGreaterThanOrEqual(terminal.endCount, 1)
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-console-tests-\(UUID().uuidString)",
      isDirectory: true
    )
  }

  private func events(for source: String) -> [TerminalEvent] {
    source.map { character in character == "\n" ? .enter : .character(character) }
  }

  private func stripANSI(_ source: String) -> String {
    source.replacingOccurrences(
      of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]",
      with: "",
      options: .regularExpression
    )
  }

  private func waitUntil(
    timeout: Duration,
    condition: @escaping @Sendable () -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
      if clock.now >= deadline {
        XCTFail("timed out waiting for console output")
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}

private func setConsoleProductHome(_ value: String?) {
  #if os(Windows)
    _ = _putenv_s("MIKROKHOROS_HOME", value ?? "")
  #else
    if let value {
      setenv("MIKROKHOROS_HOME", value, 1)
    } else {
      unsetenv("MIKROKHOROS_HOME")
    }
  #endif
}

private final class RecordingCommandIO: CommandIO, @unchecked Sendable {
  private let lock = NSLock()
  let isInteractive: Bool
  private var storedOutput = ""
  private var storedError = ""

  init(isInteractive: Bool) { self.isInteractive = isInteractive }

  var output: String { lock.withTestLock { storedOutput } }
  var error: String { lock.withTestLock { storedError } }

  func writeStandardOutput(_ text: String) { lock.withTestLock { storedOutput += text } }
  func writeStandardError(_ text: String) { lock.withTestLock { storedError += text } }
  func readLine(prompt: String, hidden: Bool) -> String? { nil }
  func readStandardInputToEnd() -> Data { Data() }

  func reset() {
    lock.withTestLock {
      storedOutput = ""
      storedError = ""
    }
  }
}

private final class TestTerminalBackend: TerminalBackend, @unchecked Sendable {
  private let condition = NSCondition()
  private var events: [TerminalEvent] = []
  private var output = ""
  private var begins = 0
  private var ends = 0

  var isInteractive: Bool { true }
  var capturedOutput: String { condition.withTestCondition { output } }
  var beginCount: Int { condition.withTestCondition { begins } }
  var endCount: Int { condition.withTestCondition { ends } }

  func begin() { condition.withTestCondition { begins += 1 } }
  func end() { condition.withTestCondition { ends += 1 } }

  func readEvent(timeoutMilliseconds: Int) -> TerminalEvent? {
    condition.lock()
    defer { condition.unlock() }
    if events.isEmpty {
      _ = condition.wait(until: Date().addingTimeInterval(Double(timeoutMilliseconds) / 1_000))
    }
    return events.isEmpty ? nil : events.removeFirst()
  }

  func write(_ text: String) { condition.withTestCondition { output += text } }

  func append(_ values: [TerminalEvent]) {
    condition.withTestCondition {
      events.append(contentsOf: values)
      condition.broadcast()
    }
  }
}

extension NSLock {
  fileprivate func withTestLock<Result>(_ body: () -> Result) -> Result {
    lock()
    defer { unlock() }
    return body()
  }
}

extension NSCondition {
  fileprivate func withTestCondition<Result>(_ body: () -> Result) -> Result {
    lock()
    defer { unlock() }
    return body()
  }
}
