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
      let replacement: String
      switch key.value(in: configuration) {
      case .integer(let value): replacement = String(value + 1)
      case .text(let value):
        switch key {
        case .presentation(.output): replacement = value == "human" ? "yaml" : "human"
        case .presentation(.color), .presentation(.unicode):
          replacement = value == "always" ? "never" : "always"
        default: return XCTFail("text value belongs to a presentation key")
        }
      }
      configuration = try key.setting(replacement, in: configuration)
    }
    try ConfigurationStore.save(configuration, to: url)

    XCTAssertEqual(try ConfigurationStore.load(from: url), configuration)
    for key in ConfigurationKey.all {
      XCTAssertEqual(
        key.value(in: try ConfigurationStore.load(from: url)), key.value(in: configuration))
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

  func testObjectInvocationDepthRejectsTraversalArithmeticOverflow() throws {
    XCTAssertThrowsError(
      try RuntimeLimits.defaults.setting(.maximumObjectInvocationDepth, to: Int.max)
    ) { error in
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
    let runtime = try testWorldRuntime(configuration: configuration)
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

  func testAgentActionPreferenceCanChangeAndSurvivesWorldRestore() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "mutable")

    try runtime.setMaximumActionsPerResponse(23, for: agent)
    let restored = try testWorldRuntime(document: runtime.document)
    let restoredAgent = try restored.harness.resolveAgent(agent.hash)

    XCTAssertEqual(agent.maximumActionsPerResponse, 23)
    XCTAssertEqual(restoredAgent.maximumActionsPerResponse, 23)
  }

  func testAgentPreferenceChangeReplaysAfterEarlierActions() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "ordered")
    try runtime.addAgent(agent)
    _ = try runtime.run(
      "move east\nmove east\nmove east\nmove east\nmove east",
      for: agent
    )
    try runtime.setMaximumActionsPerResponse(3, for: agent)

    let restored = try testWorldRuntime(document: runtime.document)
    let restoredAgent = try restored.harness.resolveAgent(agent.hash)

    XCTAssertEqual(restoredAgent.coordinate, Coordinate(x: 5, y: 0))
    XCTAssertEqual(restoredAgent.maximumActionsPerResponse, 3)
  }

  func testLowerRuntimeCeilingDoesNotChangeHistoricalReplay() throws {
    let original = try testWorldRuntime()
    let agent = try original.createAgent(name: "historical")
    try original.addAgent(agent)
    _ = try original.run(
      "move east\nmove east\nmove east\nmove east\nmove east",
      for: agent
    )
    let lowerLimits = try RuntimeLimits.defaults.setting(.maximumActionsPerResponse, to: 2)
    let lowerConfiguration = try RuntimeConfiguration(runtime: lowerLimits)

    let restored = try testWorldRuntime(
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

  func testVersionOneConfigurationMigratesInMemoryAndPersistsOnlyWhenSaved() throws {
    let url = temporaryConfigurationURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try ConfigurationStore.save(.defaults, to: url)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
    object["version"] = 1
    object.removeValue(forKey: "presentation")
    let legacy = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try legacy.write(to: url)

    let migrated = try ConfigurationStore.load(from: url)
    XCTAssertEqual(migrated.version, 2)
    XCTAssertEqual(migrated.presentation, .defaults)
    XCTAssertEqual(
      (try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])?["version"]
        as? Int,
      1
    )

    try ConfigurationStore.save(migrated, to: url)
    XCTAssertEqual(
      (try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])?["version"]
        as? Int,
      2
    )
  }

  func testLegacyWorldByteLimitSpellingMigratesToWorldSetting() throws {
    let url = temporaryConfigurationURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try ConfigurationStore.save(.defaults, to: url)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
    var runtime = try XCTUnwrap(object["runtime"] as? [String: Any])
    runtime["maximumWorkspaceBytes"] = 12_345_678
    runtime.removeValue(forKey: "maximumWorldBytes")
    object["runtime"] = runtime
    try JSONSerialization.data(withJSONObject: object).write(to: url)

    let migrated = try ConfigurationStore.load(from: url)
    XCTAssertEqual(migrated.runtime.maximumWorldBytes, 12_345_678)
    XCTAssertEqual(
      try ConfigurationKey(argument: "runtime.maximum-workspace-bytes"),
      .runtime(.maximumWorldBytes)
    )

    try ConfigurationStore.save(migrated, to: url)
    let saved = try XCTUnwrap(
      (JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])?["runtime"]
        as? [String: Any]
    )
    XCTAssertEqual(saved["maximumWorldBytes"] as? Int, 12_345_678)
    XCTAssertNil(saved["maximumWorkspaceBytes"])
  }
}
