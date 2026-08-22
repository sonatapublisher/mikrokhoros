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

final class WorldOperationEnvelopeTests: XCTestCase {
  private func encodedEnvelope() throws -> Data {
    let envelope = WorldOperationEnvelope(
      operationID: "operation-1",
      worldID: "world-1",
      actor: "human",
      timestamp: Date(timeIntervalSince1970: 1_700_000_000),
      actionIndex: 4,
      objectMutations: [
        WorldObjectMutation(
          objectID: "object-1",
          operation: "revision",
          priorRevision: 1,
          nextRevision: 2
        )
      ],
      receipts: [WorldOperationReceipt(id: "receipt-1", kind: "message", value: "ok")],
      unread: [
        WorldUnreadRecord(
          eventID: "event-1",
          agentID: "agent-1",
          sourceID: "source-1",
          timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
      ],
      acknowledgements: [
        WorldUnreadAcknowledgement(
          agentID: "agent-1",
          eventID: "event-1",
          sourceID: "source-1"
        )
      ],
      activity: [
        ActivityRecord(
          id: "activity-1",
          timestamp: Date(timeIntervalSince1970: 1_700_000_000),
          operation: "management",
          success: true
        )
      ],
      idempotencyKey: "request-1"
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(envelope)
  }

  private func decoded(_ data: Data) throws -> WorldOperationEnvelope {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(WorldOperationEnvelope.self, from: data)
  }

  private func encodedDocument(_ document: WorldDocument = WorldDocument()) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(document)
  }

  private func decodedDocument(_ data: Data) throws -> WorldDocument {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(WorldDocument.self, from: data)
  }

  func testV1EnvelopeRoundTripsWithAllFields() throws {
    let data = try encodedEnvelope()
    let decoded = try decoded(data)
    XCTAssertEqual(decoded.schemaVersion, WorldOperationEnvelope.currentSchemaVersion)
    XCTAssertEqual(decoded.operationID, "operation-1")
    XCTAssertEqual(decoded.worldID, "world-1")
    XCTAssertEqual(decoded.actionIndex, 4)
    XCTAssertEqual(decoded.purchases.count, 0)
    XCTAssertEqual(decoded.objectMutations.count, 1)
    XCTAssertEqual(decoded.receipts.count, 1)
    XCTAssertEqual(decoded.unread.count, 1)
    XCTAssertEqual(decoded.acknowledgements.count, 1)
    XCTAssertEqual(decoded.activity.count, 1)
    XCTAssertEqual(decoded.idempotencyKey, "request-1")
  }

  func testUnknownTopLevelFieldIsRejected() throws {
    var value = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: encodedEnvelope()) as? [String: Any]
    )
    value["unexpected"] = true
    let data = try JSONSerialization.data(withJSONObject: value)
    XCTAssertThrowsError(try decoded(data))
  }

  func testUnknownNestedFieldIsRejected() throws {
    var value = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: encodedEnvelope()) as? [String: Any]
    )
    var mutations = try XCTUnwrap(value["objectMutations"] as? [[String: Any]])
    mutations[0]["unexpected"] = "rejected"
    value["objectMutations"] = mutations
    let data = try JSONSerialization.data(withJSONObject: value)
    XCTAssertThrowsError(try decoded(data))
  }

  func testSchemaVersionAndRequiredFieldsAreExact() throws {
    var value = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: encodedEnvelope()) as? [String: Any]
    )
    value["schemaVersion"] = 2
    XCTAssertThrowsError(
      try decoded(JSONSerialization.data(withJSONObject: value))
    )

    value = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: encodedEnvelope()) as? [String: Any]
    )
    value.removeValue(forKey: "receipts")
    XCTAssertThrowsError(
      try decoded(JSONSerialization.data(withJSONObject: value))
    )

    value = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: encodedEnvelope()) as? [String: Any]
    )
    value.removeValue(forKey: "purchases")
    XCTAssertThrowsError(
      try decoded(JSONSerialization.data(withJSONObject: value))
    )
  }

  func testUnknownPurchaseMutationFieldIsRejected() throws {
    let purchase: [String: Any] = [
      "recordID": "record-1",
      "payerWalletID": "wallet-1",
      "buyerAgentID": "agent-1",
      "merchantID": "merchant-1",
      "itemID": "item-1",
      "nominalAmount": 100,
      "appliedAmount": 100,
      "replacement": NSNull(),
      "receiptID": "receipt-1",
      "unreadEventID": "event-1",
    ]
    let decoder = JSONDecoder()
    XCTAssertNoThrow(
      try decoder.decode(
        WorldPurchaseMutation.self,
        from: JSONSerialization.data(withJSONObject: purchase)
      )
    )
    var unexpected = purchase
    unexpected["unsignedAuthority"] = "rejected"
    XCTAssertThrowsError(
      try decoder.decode(
        WorldPurchaseMutation.self,
        from: JSONSerialization.data(withJSONObject: unexpected)
      )
    )
  }

  func testEnvelopeActorIsAClosedRuntimeRole() throws {
    let envelope = WorldOperationEnvelope(
      operationID: "operation-1",
      worldID: "world-1",
      actor: "package-supplied-authority",
      timestamp: Date(timeIntervalSince1970: 1_700_000_000)
    )
    XCTAssertThrowsError(try JSONEncoder().encode(envelope))
  }

  func testWorldSchemaSevenRequiresVersionedFieldsAndRejectsRetiredKeys() throws {
    var value = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: encodedDocument()) as? [String: Any]
    )
    for version in [6, 8] {
      value["schemaVersion"] = version
      XCTAssertThrowsError(
        try decodedDocument(JSONSerialization.data(withJSONObject: value))
      )
    }

    value = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: encodedDocument()) as? [String: Any]
    )
    value.removeValue(forKey: "worldName")
    XCTAssertThrowsError(
      try decodedDocument(JSONSerialization.data(withJSONObject: value))
    )

    let agentRecord = WorldAgentRecord(
      id: "agent-1",
      name: "agent",
      maximumActionsPerResponse: 8,
      genesis: AgentGenesisIDs()
    )
    value = try XCTUnwrap(
      try JSONSerialization.jsonObject(
        with: encodedDocument(WorldDocument(agents: [agentRecord]))
      ) as? [String: Any]
    )
    var agents = try XCTUnwrap(value["agents"] as? [[String: Any]])
    agents[0]["initialCoinBalance"] = 1
    var genesis = try XCTUnwrap(agents[0]["genesis"] as? [String: Any])
    genesis["coin"] = 1
    genesis["hand"] = "retired"
    agents[0]["genesis"] = genesis
    value["agents"] = agents
    XCTAssertThrowsError(
      try decodedDocument(JSONSerialization.data(withJSONObject: value))
    )
  }

  func testWorldStoreRejectsNonSchemaSevenWithoutCreatingAFile() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("mikrokhoros-world-schema-(UUID().uuidString)", isDirectory: true)
    let url = directory.appendingPathComponent("world.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let legacy = WorldDocument(schemaVersion: 6)

    XCTAssertThrowsError(try WorldStore.save(legacy, to: url))
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
  }
}
