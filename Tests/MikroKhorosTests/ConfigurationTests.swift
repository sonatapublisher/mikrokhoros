import Foundation
import XCTest

@testable import MikroKhoros

final class ConfigurationTests: XCTestCase {
  private func temporaryConfigurationURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("mikrokhoros-config-tests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("config.json")
  }

  func testEveryPublishedSettingCanBeChangedAndPersisted() throws {
    let url = temporaryConfigurationURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var configuration = RuntimeConfiguration.defaults

    for key in ConfigurationKey.all {
      configuration = try key.setting(key.value(in: configuration) + 1, in: configuration)
    }
    try ConfigurationStore.save(configuration, to: url)

    XCTAssertEqual(try ConfigurationStore.load(from: url), configuration)
    for key in ConfigurationKey.all {
      XCTAssertEqual(
        key.value(in: try ConfigurationStore.load(from: url)),
        key.value(in: RuntimeConfiguration.defaults) + 1
      )
    }
  }

  func testMissingConfigurationUsesDefaultsWithoutCreatingAFile() throws {
    let url = temporaryConfigurationURL()
    XCTAssertEqual(try ConfigurationStore.load(from: url), .defaults)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  func testInvalidConfigurationFailsClosed() throws {
    let url = temporaryConfigurationURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let invalid = """
      {
        "version": 1,
        "agents": { "maximumActionsPerResponse": 8 },
        "runtime": {
          "maximumActionCharacters": 40000,
          "maximumActionsPerResponse": 256,
          "maximumResponseCharacters": 32768,
          "maximumProviderResponseBytes": 4194304,
          "maximumModelFieldCharacters": 32768,
          "maximumModelInputCharacters": 65536,
          "maximumModelHistoryCharacters": 65536,
          "maximumModelHistoryMessages": 256,
          "maximumModelContextCharacters": 131072,
          "maximumBroadcastEventsPerRequest": 16,
          "minimumProtectedVerbatimWords": 12
        }
      }
      """
    try Data(invalid.utf8).write(to: url)

    XCTAssertThrowsError(try ConfigurationStore.load(from: url)) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "config.invalid")
    }
  }

  func testUnknownConfigurationKeyFailsClosed() throws {
    let url = temporaryConfigurationURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try ConfigurationStore.save(.defaults, to: url)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
    object["maximumActionCharacters"] = 1
    try JSONSerialization.data(withJSONObject: object).write(to: url)

    XCTAssertThrowsError(try ConfigurationStore.load(from: url)) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "config.invalid")
    }
  }

  func testConfiguredRuntimeCeilingBoundsAgentBatch() throws {
    let limits = try RuntimeLimits.defaults.setting(.maximumActionsPerResponse, to: 2)
    let configuration = try RuntimeConfiguration(
      agents: AgentDefaults(maximumActionsPerResponse: 5),
      runtime: limits
    )
    let runtime = try WorkspaceRuntime(configuration: configuration)
    let agent = try runtime.createAgent(name: "configured")
    try runtime.addAgent(agent)

    let turn = try runtime.run("move east\nmove east\nmove east", for: agent)

    XCTAssertEqual(agent.maximumActionsPerResponse, 5)
    XCTAssertEqual(turn.results.count, 2)
    XCTAssertEqual(agent.coordinate, Coordinate(x: 2, y: 0))
    XCTAssertTrue(
      turn.events.contains {
        guard case .warning(let warning) = $0 else { return false }
        return warning.code == "batch.action_limit" && warning.count == 1
      }
    )
  }

  func testConfiguredActionAndFieldLimitsReachTheAgentSession() throws {
    var limits = try RuntimeLimits.defaults.setting(.maximumActionCharacters, to: 4)
    limits = try limits.setting(.maximumModelFieldCharacters, to: 6)
    let harness = try Harness(limits: limits)
    let agent = try harness.createAgent(name: "long-agent-name")
    try harness.addAgent(agent)

    let turn = AgentSession(harness: harness, agent: agent).run("move east")

    XCTAssertEqual(turn.results.last?.error?.code, "command.invalid")
    XCTAssertEqual(agent.coordinate, .origin)
    XCTAssertTrue(try harness.selfState(agent).contains("…[truncated]"))
  }

  func testConfiguredProtectedOverlapWindowIsUsed() throws {
    let limits = try RuntimeLimits.defaults.setting(.minimumProtectedVerbatimWords, to: 3)

    XCTAssertThrowsError(
      try PromptSafety.validateModelOutput(
        "object (write (alpha beta gamma))",
        system: "alpha beta gamma delta",
        input: "events: []",
        limits: limits
      )
    ) { error in
      XCTAssertEqual(
        (error as? MikroKhorosError)?.issue.code,
        "model.output_instruction_leakage"
      )
    }
  }

  func testAgentActionPreferenceCanChangeAndSurvivesWorkspaceRestore() throws {
    let runtime = try WorkspaceRuntime()
    let agent = try runtime.createAgent(name: "mutable")

    try runtime.setMaximumActionsPerResponse(23, for: agent)
    let restored = try WorkspaceRuntime(document: runtime.document)
    let restoredAgent = try restored.harness.resolveAgent(agent.hash)

    XCTAssertEqual(agent.maximumActionsPerResponse, 23)
    XCTAssertEqual(restoredAgent.maximumActionsPerResponse, 23)
  }

  func testAgentPreferenceChangeReplaysAfterEarlierActions() throws {
    let runtime = try WorkspaceRuntime()
    let agent = try runtime.createAgent(name: "ordered")
    try runtime.addAgent(agent)
    _ = try runtime.run(
      "move east\nmove east\nmove east\nmove east\nmove east",
      for: agent
    )
    try runtime.setMaximumActionsPerResponse(3, for: agent)

    let restored = try WorkspaceRuntime(document: runtime.document)
    let restoredAgent = try restored.harness.resolveAgent(agent.hash)

    XCTAssertEqual(restoredAgent.coordinate, Coordinate(x: 5, y: 0))
    XCTAssertEqual(restoredAgent.maximumActionsPerResponse, 3)
  }

  func testLowerRuntimeCeilingDoesNotChangeHistoricalReplay() throws {
    let original = try WorkspaceRuntime()
    let agent = try original.createAgent(name: "historical")
    try original.addAgent(agent)
    _ = try original.run(
      "move east\nmove east\nmove east\nmove east\nmove east",
      for: agent
    )
    let lowerLimits = try RuntimeLimits.defaults.setting(.maximumActionsPerResponse, to: 2)
    let lowerConfiguration = try RuntimeConfiguration(runtime: lowerLimits)

    let restored = try WorkspaceRuntime(
      document: original.document,
      configuration: lowerConfiguration
    )
    let restoredAgent = try restored.harness.resolveAgent(agent.hash)
    let newTurn = try restored.run("move east\nmove east\nmove east", for: restoredAgent)

    XCTAssertEqual(restoredAgent.coordinate, Coordinate(x: 7, y: 0))
    XCTAssertEqual(newTurn.results.count, 2)
  }

  func testConfigurationKeyAcceptsFileAndCliSpellings() throws {
    XCTAssertEqual(
      try ConfigurationKey(argument: "agents.maximum-actions-per-response"),
      .agentMaximumActionsPerResponse
    )
    XCTAssertEqual(
      try ConfigurationKey(argument: "runtime.maximumModelContextCharacters"),
      .runtime(.maximumModelContextCharacters)
    )
    XCTAssertEqual(
      try ConfigurationKey(argument: "runtime.maximum-model-context-characters"),
      .runtime(.maximumModelContextCharacters)
    )
  }
}
