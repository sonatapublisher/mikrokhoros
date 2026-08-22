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
import XCTest

@testable import MikroKhoros

final class AgentStoreTests: XCTestCase {
  private func fixture(
    identity: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    maximumBytes: Int = RuntimeLimits.defaults.maximumAgentStoreBytes
  ) throws -> (root: URL, store: AgentStore) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-agent-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    let store = try AgentStore(
      url: root.appendingPathComponent("agents.json"),
      maximumBytes: maximumBytes,
      identityProvider: { identity },
      dateProvider: { Date(timeIntervalSince1970: 123) }
    )
    return (root, store)
  }

  private func encodedAgentStoreDocument() throws -> [String: Any] {
    let timestamp = Date(timeIntervalSince1970: 10)
    let assignment = try AgentWorldAssignment(
      worldID: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      assignedAt: timestamp
    )
    let record = try UserAgentRecord(
      id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      name: "Strict",
      maximumActionsPerResponse: 8,
      worldAssignment: assignment,
      createdAt: timestamp,
      updatedAt: timestamp
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: encoder.encode(AgentStoreDocument(agents: [record]))
      ) as? [String: Any]
    )
  }

  private func assertRetiredAgentStoreFieldsRejected(
    _ object: [String: Any],
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let data = try JSONSerialization.data(withJSONObject: object)
    XCTAssertThrowsError(
      try decoder.decode(AgentStoreDocument.self, from: data),
      file: file,
      line: line
    ) { error in
      XCTAssertEqual(
        (error as? MikroKhorosError)?.issue.code,
        "world.persistence_failed",
        file: file,
        line: line
      )
      XCTAssertEqual(
        (error as? MikroKhorosError)?.issue.message,
        "agent-store schema 3 contains unsupported retired fields",
        file: file,
        line: line
      )
    }
  }

  func testCreationPersistsUserIdentityOutsideEveryWorld() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let created = try fixture.store.create(
      name: "Sol",
      maximumActionsPerResponse: 12
    )
    try fixture.store.save()

    let restored = try AgentStore(url: fixture.store.url)
    let record = try restored.resolve(created.id)
    XCTAssertEqual(record.name, "Sol")
    XCTAssertEqual(record.maximumActionsPerResponse, 12)
    XCTAssertNil(record.worldAssignment)
  }

  func testWorldAssignmentRequiresOneConcreteWorld() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try fixture.store.create(
      name: "Builder",
      maximumActionsPerResponse: 8
    )
    let firstWorld = "11111111111111111111111111111111"

    let assigned = try fixture.store.assign(
      source.id,
      toWorld: firstWorld
    )
    XCTAssertEqual(assigned.worldAssignment?.worldID, firstWorld)

    XCTAssertThrowsError(
      try fixture.store.assign(
        source.id,
        toWorld: "22222222222222222222222222222222"
      )
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "agent.world_conflict")
    }
  }

  func testUserAgentRegistrationCreatesConcreteWorldSnapshot() throws {
    let profile = try AIProfile(
      name: "Local",
      adapterID: "ollama",
      transport: .openAICompatible,
      model: "test",
      endpoint: "http://127.0.0.1:11434/v1/chat/completions"
    )
    let source = try UserAgentRecord(
      id: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      name: "Researcher",
      maximumActionsPerResponse: 9,
      profile: profile
    )
    let runtime = try testWorldRuntime()

    let agent = try runtime.registerAgent(source)
    XCTAssertFalse(agent.isInWorld)
    XCTAssertEqual(agent.hash, source.id)
    XCTAssertEqual(agent.aiProfile, profile)
    XCTAssertEqual(runtime.document.agents.count, 1)
    XCTAssertEqual(runtime.document.agents[0].initialProfile, profile)

    _ = try runtime.addAgent(agent, at: Coordinate(x: 7, y: -2))
    let restored = try testWorldRuntime(document: runtime.document)
    let restoredAgent = try restored.harness.resolveAgent(source.id)
    XCTAssertEqual(restoredAgent.coordinate, Coordinate(x: 7, y: -2))
    XCTAssertEqual(restoredAgent.aiProfile, profile)
  }

  func testCatalogSettingsOverrideWorldSettingsAfterReplay() throws {
    let original = try testWorldRuntime()
    let agent = try original.createAgent(name: "Mutable")
    _ = try original.addAgent(agent)
    try original.setMaximumActionsPerResponse(4, for: agent)

    let source = try UserAgentRecord(
      id: agent.hash,
      name: agent.name,
      maximumActionsPerResponse: 17,
      genesis: original.document.agents[0].genesis
    )
    let restored = try testWorldRuntime(document: original.document)
    try restored.synchronizeAgent(source)

    XCTAssertEqual(try restored.harness.resolveAgent(agent.hash).maximumActionsPerResponse, 17)
  }

  func testConfiguredAgentStoreByteLimitIsEnforced() throws {
    let fixture = try fixture(maximumBytes: 64)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    _ = try fixture.store.create(name: "Bounded", maximumActionsPerResponse: 8)

    XCTAssertThrowsError(try fixture.store.save()) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "agent.store_too_large")
    }
  }

  func testUnassignedAgentProfileStillEnforcesAdapterBoundary() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try fixture.store.create(name: "Detached", maximumActionsPerResponse: 8)
    let profile = try AIProfile(
      name: "Codex",
      adapterID: "codex",
      transport: .roleSeparatedBridge,
      model: "gpt-5.6-sol"
    )

    XCTAssertThrowsError(try fixture.store.setProfile(profile, for: source.id)) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "ai.profile_invalid")
    }
    XCTAssertNil(try fixture.store.resolve(source.id).profile)
  }

  func testNonCurrentAgentStoreSchemasRejectLoadWithExactVersions() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)

    for version in [2, 4] {
      try JSONSerialization.data(
        withJSONObject: ["schemaVersion": version, "agents": []]
      ).write(to: fixture.store.url, options: .atomic)

      XCTAssertThrowsError(try AgentStore(url: fixture.store.url)) { error in
        XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "world.persistence_failed")
        XCTAssertEqual(
          (error as? MikroKhorosError)?.issue.message,
          "unsupported agent-store schema version found \(version); required 3"
        )
      }
    }
  }

  func testMixedSchemaThreeRejectsRetiredAgentFields() throws {
    let source = try encodedAgentStoreDocument()

    do {
      var object = source
      var agents = try XCTUnwrap(object["agents"] as? [[String: Any]])
      agents[0]["initialCoinBalance"] = 20
      object["agents"] = agents
      try assertRetiredAgentStoreFieldsRejected(object)
    }

    do {
      var object = source
      var agents = try XCTUnwrap(object["agents"] as? [[String: Any]])
      var genesis = try XCTUnwrap(agents[0]["genesis"] as? [String: Any])
      genesis["coin"] = "cccccccccccccccccccccccccccccccc"
      agents[0]["genesis"] = genesis
      object["agents"] = agents
      try assertRetiredAgentStoreFieldsRejected(object)
    }

    do {
      var object = source
      var agents = try XCTUnwrap(object["agents"] as? [[String: Any]])
      agents[0]["hand"] = "dddddddddddddddddddddddddddddddd"
      object["agents"] = agents
      try assertRetiredAgentStoreFieldsRejected(object)
    }

    do {
      var object = source
      var agents = try XCTUnwrap(object["agents"] as? [[String: Any]])
      var assignment = try XCTUnwrap(agents[0]["worldAssignment"] as? [String: Any])
      assignment["workspacePath"] = "/tmp/former-world.json"
      agents[0]["worldAssignment"] = assignment
      object["agents"] = agents
      try assertRetiredAgentStoreFieldsRejected(object)
    }
  }
}
