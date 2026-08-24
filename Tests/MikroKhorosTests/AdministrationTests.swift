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

final class AdministrationTests: XCTestCase {
  func testQuotedObjectArgumentsDecodeCommonTextEscapes() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "writer")
    _ = try runtime.addAgent(agent)
    let turn = try runtime.run(
      "backpack open\ndrop\nmove east\npickup\n"
        + "object (write (\"first\\nsecond\\tcolumn\\rreturn\"))",
      for: agent
    )

    XCTAssertEqual(turn.status, .success)
    XCTAssertEqual(
      try XCTUnwrap(agent.primaryHeldObject as? ScratchpadObject).text,
      "first\nsecond\tcolumn\rreturn"
    )
  }

  func testAdministrativeSnapshotIncludesCompletePrivateRuntimeState() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-administration-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let worldID = InventoryIdentity.make()
    let inventory = try InventoryStore(
      url: root.appendingPathComponent("inventory.json"),
      packageDirectory: root.appendingPathComponent("packages", isDirectory: true),
      credentialStore: FileCredentialStore(
        directory: root.appendingPathComponent("credentials", isDirectory: true)
      ),
      runtimeRegistry: .installedCLI()
    )
    let runtime = try testWorldRuntime(
      document: WorldDocument(worldID: worldID, worldName: "default-khoros"),
      inventory: inventory
    )
    let templateService = WorldTemplateService()
    let templatePlan = try templateService.preflight(
      templateID: "default-khoros",
      inventory: inventory,
      runtime: runtime
    )
    _ = try templateService.apply(templatePlan, inventory: inventory, runtime: runtime)
    let agent = try runtime.createAgent(name: "sol")
    _ = try runtime.addAgent(agent)
    try runtime.attachProfile(
      AIProfile(
        name: "Codex Luna",
        adapterID: "codex",
        transport: .roleSeparatedBridge,
        model: "gpt-5.6-luna",
        endpoint: "https://127.0.0.1:9417/complete",
        credentialEnvironmentVariable: "CODEX_TEST_CREDENTIAL",
        maximumOutputTokens: 4_096,
        reasoningEffort: "high"
      ),
      to: agent
    )
    let note = "verified private scratch evidence"
    let scratchpadTurn = try runtime.run(
      "backpack open\ndrop\nmove east\npickup\nobject (write (\"\(note)\"))",
      for: agent
    )
    XCTAssertEqual(scratchpadTurn.status, .success)
    let message = try runtime.sendMessage(
      to: agent,
      body: "private messenger evidence",
      sender: "tester",
      threadID: "audit"
    )
    let objective = try runtime.postObjective(
      title: "Administrative visibility",
      body: "Verify the complete state surface."
    )
    let document = try runtime.addLibraryDocument(
      title: "Evidence source",
      sourceURL: "https://example.com/evidence",
      content: "private library evidence"
    )

    let snapshot = runtime.harness.administrativeWorldSnapshot()
    let encoded = try encodedJSON(snapshot)
    XCTAssertTrue(encoded.contains("\"schema_version\":2"))
    XCTAssertTrue(encoded.contains("\"primary_holding_number\""))
    XCTAssertTrue(encoded.contains("\"holdings\""))
    XCTAssertTrue(encoded.contains("\"wallet_object_id\""))
    XCTAssertFalse(encoded.contains("\"hand_object_id\""))
    XCTAssertFalse(encoded.contains("\"coin_object_id\""))
    XCTAssertTrue(encoded.contains(note))
    XCTAssertTrue(encoded.contains(message.body))
    XCTAssertTrue(encoded.contains(objective.body))
    XCTAssertTrue(encoded.contains(document.content))
    XCTAssertTrue(encoded.contains("CODEX_TEST_CREDENTIAL"))
    XCTAssertTrue(encoded.contains("gpt-5.6-luna"))
    for object in runtime.harness.objects {
      XCTAssertTrue(encoded.contains(object.hash), "missing object \(object.hash)")
    }

    let scratchpad = try XCTUnwrap(agent.primaryHeldObject as? ScratchpadObject)
    let objectSnapshot = try runtime.harness.administrativeSnapshot(for: scratchpad.hash)
    XCTAssertTrue(try encodedJSON(objectSnapshot).contains(note))
    let agentSnapshot = try runtime.harness.administrativeSnapshot(
      for: String(agent.hash.prefix(12))
    )
    XCTAssertTrue(try encodedJSON(agentSnapshot).contains(agent.backpack.hash))
  }

  func testHumanSelectorsResolveNamesAndPrefixesWithoutCrossingScopes() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "Builder")
    _ = try runtime.addAgent(agent)
    let eye = try XCTUnwrap(agent.primaryHeldObject)

    XCTAssertTrue(try runtime.harness.resolveAgent("builder") === agent)
    XCTAssertTrue(try runtime.harness.resolveAgent(String(agent.hash.prefix(8))) === agent)
    XCTAssertTrue(try runtime.exactWorldObject("Eye") === eye)
    XCTAssertTrue(try runtime.exactWorldObject(String(eye.hash.prefix(8))) === eye)
    XCTAssertThrowsError(try runtime.harness.resolveObject("abc")) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "selector.not_found")
    }
  }

  func testHumanSelectorReportsAmbiguousNamesWithSafeRecovery() throws {
    let first = SelectorFixture(id: "aaaaaaaa11111111", name: "same")
    let second = SelectorFixture(id: "bbbbbbbb22222222", name: "SAME")
    XCTAssertThrowsError(
      try HumanSelectorResolver.resolve(
        "same",
        among: [first, second],
        id: \.id,
        name: { $0.name },
        kind: "agent",
        listCommand: "khoros agent list"
      )
    ) { error in
      let issue = (error as? MikroKhorosError)?.issue
      XCTAssertEqual(issue?.code, "selector.ambiguous")
      XCTAssertEqual(issue?.suggestions, ["retry with one displayed unique ID prefix"])
    }
  }

  private func encodedJSON(_ value: JSONValue) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
}

private struct SelectorFixture {
  let id: String
  let name: String
}
