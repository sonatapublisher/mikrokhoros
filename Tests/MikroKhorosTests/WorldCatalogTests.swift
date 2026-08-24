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

final class WorldCatalogTests: XCTestCase {
  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-world-catalog-tests-\(UUID().uuidString)",
      isDirectory: true
    )
  }

  func testCatalogSelectsListsRenamesAndRemovesExactWorlds() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WorldCatalogStore(url: root.appendingPathComponent("index.json"))
    let first = WorldDocument(
      worldID: "11111111111111111111111111111111",
      worldName: "First"
    )
    let second = WorldDocument(
      worldID: "22222222222222222222222222222222",
      worldName: "Second"
    )

    _ = try store.register(document: first)
    XCTAssertEqual(store.currentWorld?.id, first.worldID)
    _ = try store.register(document: second)
    XCTAssertEqual(store.currentWorld?.id, second.worldID)
    XCTAssertEqual(try store.use("First").id, first.worldID)
    XCTAssertEqual(try store.rename(first.worldID, name: "Primary").name, "Primary")
    XCTAssertEqual(try store.resolve("1111").id, first.worldID)

    _ = try store.remove(first.worldID)
    XCTAssertEqual(store.currentWorld?.id, second.worldID)
    XCTAssertEqual(store.allWorlds().map(\.id), [second.worldID])
  }

  func testAgentAssignmentRejectsLegacyWorkspacePath() throws {
    let assignment = try AgentWorldAssignment(
      worldID: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      assignedAt: Date(timeIntervalSince1970: 10)
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoder.encode(assignment)) as? [String: Any]
    )
    object["workspacePath"] = "/tmp/former-world.json"
    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    XCTAssertThrowsError(try decoder.decode(AgentWorldAssignment.self, from: legacyData)) {
      error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "world.persistence_failed")
      XCTAssertEqual(
        (error as? MikroKhorosError)?.issue.message,
        "agent-store schema 3 contains unsupported retired fields"
      )
    }
  }

  func testInventoryRejectsLegacyWorkspaceReferenceKey() throws {
    let source = """
        {
          "schemaVersion": 3,
          "packages": [],
          "folders": [{
            "id": "00000000000000000000000000000000",
            "name": "Inventory",
            "parentID": null,
            "createdAt": "1970-01-01T00:00:00Z",
            "updatedAt": "1970-01-01T00:00:00Z"
          }],
          "objects": [],
          "workspaceReferences": {}
        }
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    XCTAssertThrowsError(try decoder.decode(InventoryDocument.self, from: Data(source.utf8))) {
      error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "world.persistence_failed")
      XCTAssertEqual(
        (error as? MikroKhorosError)?.issue.message,
        "Inventory document contains retired workspace references"
      )
    }
  }

  func testInventoryRejectsPathHashedWorldReference() throws {
    let legacyKey = String(repeating: "a", count: 64)
    let document = InventoryDocument(
      worldReferences: [legacyKey: .empty]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    XCTAssertThrowsError(
      try decoder.decode(InventoryDocument.self, from: encoder.encode(document))
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "world.persistence_failed")
      XCTAssertEqual(
        (error as? MikroKhorosError)?.issue.message,
        "Inventory contains invalid world references"
      )
    }
  }

  func testWorldStoreDoesNotCreateMissingStateDuringLoad() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("missing.json")

    XCTAssertThrowsError(try WorldStore.load(from: url)) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "world.not_found")
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
  }

  func testWorldNamesRejectWhitespaceOnlyValues() throws {
    XCTAssertThrowsError(
      try WorldCatalogRecord(id: InventoryIdentity.make(), name: "   ")
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "world.name_invalid")
    }
    XCTAssertThrowsError(
      try testWorldRuntime(document: WorldDocument(worldName: "\t "))
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "world.name_invalid")
    }
  }
}
