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

final class WorldPersistenceTests: XCTestCase {
  private func temporaryWorldURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("mikrokhoros-tests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("world.json")
  }

  func testWorldRoundTripPreservesIdentityPositionAndObjectState() throws {
    let url = temporaryWorldURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "sol")
    _ = try runtime.addAgent(agent, at: Coordinate(x: 4, y: -2))
    let turn = try runtime.run(
      "backpack open\ndrop\nmove east\npickup\nobject (write (\"persisted note\"))",
      for: agent
    )
    XCTAssertEqual(turn.status, .success)
    try WorldStore.save(runtime.document, to: url)

    let restored = try testWorldRuntime(document: WorldStore.load(from: url))
    let restoredAgent = try restored.harness.resolveAgent(agent.hash)
    XCTAssertEqual(restored.harness.world.hash, runtime.harness.world.hash)
    XCTAssertEqual(restoredAgent.hash, agent.hash)
    XCTAssertEqual(restoredAgent.backpack.hash, agent.backpack.hash)
    XCTAssertEqual(restoredAgent.primaryHeldObject?.hash, agent.primaryHeldObject?.hash)
    XCTAssertTrue(restoredAgent.isInBackpack)
    XCTAssertEqual(restoredAgent.coordinate, Coordinate(x: 1, y: 0))
    XCTAssertEqual(
      try restored.harness.invokeHeld(for: restoredAgent, function: "read", arguments: []),
      "persisted note"
    )
  }

  func testUnreadMessageAndAttachProfileTriggerSurviveRestart() throws {
    let url = temporaryWorldURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "agent")
    _ = try runtime.addAgent(agent)
    let message = try runtime.sendMessage(to: agent, body: "latest", sender: "human")
    let profile = try AIProfile(
      name: "OpenAI",
      adapterID: "openai",
      transport: .openAIResponses,
      model: "gpt-5.6-sol"
    )
    try runtime.attachProfile(profile, to: agent)
    XCTAssertEqual(agent.pendingBroadcasts.first?.id, message.id)
    try WorldStore.save(runtime.document, to: url)

    let restored = try testWorldRuntime(document: WorldStore.load(from: url))
    let restoredAgent = try restored.harness.resolveAgent(agent.hash)
    XCTAssertEqual(restoredAgent.aiProfile, profile)
    XCTAssertEqual(restoredAgent.pendingBroadcasts.count, 1)
    XCTAssertEqual(restoredAgent.pendingBroadcasts.first?.id, message.id)
  }

  func testRejectedModelTextIsNotPersistedInJournal() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "agent")
    _ = try runtime.addAgent(agent)
    let secret = "PRIVATE_PROMPT_FRAGMENT"
    let turn = try runtime.run("launch \(secret)", for: agent)
    XCTAssertEqual(turn.status, .error)

    let data = try JSONEncoder().encode(runtime.document)
    let persisted = String(decoding: data, as: UTF8.self)
    XCTAssertFalse(persisted.contains(secret))
  }

  func testActionGeneratedMessageIdentityAndTimestampSurviveReplay() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "agent")
    _ = try runtime.addAgent(agent)
    let turn = try runtime.run(
      "backpack open\ndrop\nmove east 2\npickup\nobject (send (\(agent.hash)) (#1) (hello))",
      for: agent
    )
    XCTAssertEqual(turn.status, .success)
    let original = try XCTUnwrap(agent.primaryHeldObject as? MessengerObject)
    let originalMessage = try XCTUnwrap(original.messages.last)

    let restored = try testWorldRuntime(document: runtime.document)
    let restoredAgent = try restored.harness.resolveAgent(agent.hash)
    let restoredMessenger = try XCTUnwrap(restoredAgent.primaryHeldObject as? MessengerObject)
    let restoredMessage = try XCTUnwrap(restoredMessenger.messages.last)
    XCTAssertEqual(restoredMessage.id, originalMessage.id)
    XCTAssertEqual(restoredMessage.timestamp, originalMessage.timestamp)
    XCTAssertEqual(restoredMessage.body, "hello")
  }

  func testAgentHumanMessageActionJournalsAndReplaysExactlyOnce() throws {
    let url = temporaryWorldURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "requester")
    _ = try runtime.addAgent(agent)
    let body = "Please fund my Wallet"

    let turn = try runtime.run(
      "backpack open\ndrop\nmove east 2\npickup\nobject (send (human) (#funding) (\(body)))",
      for: agent
    )
    XCTAssertEqual(turn.status, .success)

    let messenger = try runtime.harness.messenger(for: agent)
    let liveInbox = try runtime.harness.humanInbox(for: agent).filter { $0.body == body }
    let liveTranscript = messenger.messages.filter { $0.body == body }
    XCTAssertEqual(liveInbox.count, 1)
    XCTAssertEqual(liveTranscript.count, 1)
    XCTAssertEqual(liveTranscript.first?.id, liveInbox.first?.id)
    XCTAssertEqual(liveTranscript.first?.isRead, true)
    XCTAssertEqual(liveInbox.first?.isRead, false)
    XCTAssertFalse(
      runtime.document.events.contains { event in
        if case .humanMessage = event { return true }
        return false
      }
    )

    try WorldStore.save(runtime.document, to: url)
    let restored = try testWorldRuntime(document: WorldStore.load(from: url))
    let restoredAgent = try restored.harness.resolveAgent(agent.hash)
    let restoredMessenger = try restored.harness.messenger(for: restoredAgent)
    let restoredInbox = try restored.harness.humanInbox(for: restoredAgent).filter {
      $0.body == body
    }
    let restoredTranscript = restoredMessenger.messages.filter { $0.body == body }
    XCTAssertEqual(restoredInbox.count, 1)
    XCTAssertEqual(restoredTranscript.count, 1)
    XCTAssertEqual(restoredInbox.first?.id, liveInbox.first?.id)
    XCTAssertEqual(restoredInbox.first?.threadID, liveInbox.first?.threadID)
    XCTAssertEqual(restoredInbox.first?.senderAgentID, liveInbox.first?.senderAgentID)
    XCTAssertEqual(restoredInbox.first?.isRead, liveInbox.first?.isRead)
    XCTAssertEqual(restoredTranscript.first?.id, liveTranscript.first?.id)
    XCTAssertEqual(restoredTranscript.first?.isRead, liveTranscript.first?.isRead)
    XCTAssertEqual(
      try XCTUnwrap(restoredInbox.first?.timestamp.timeIntervalSince1970),
      floor(try XCTUnwrap(liveInbox.first?.timestamp.timeIntervalSince1970))
    )
  }

  func testHumanMessageUsesStableMessengerIdentityWhileDeviceIsDropped() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "agent")
    _ = try runtime.addAgent(agent)
    try runtime.attachProfile(
      AIProfile(
        name: "local",
        adapterID: "ollama",
        transport: .openAICompatible,
        model: "model",
        endpoint: "http://127.0.0.1:11434/v1/chat/completions"
      ),
      to: agent
    )
    let placement = try runtime.run(
      "backpack open\ndrop\nmove east 2\npickup\nbackpack close\ndrop",
      for: agent
    )
    XCTAssertEqual(placement.status, .success)
    let messenger = try runtime.harness.messenger(for: agent)
    XCTAssertNil(runtime.harness.carrier(of: messenger))

    let message = try runtime.sendMessage(
      to: agent,
      body: "waiting on the device",
      threadID: "#field"
    )
    XCTAssertEqual(messenger.messages.last?.id, message.id)
    XCTAssertTrue(agent.pendingBroadcasts.isEmpty)

    let pickup = try runtime.run("pickup", for: agent)
    let broadcasts = pickup.events.compactMap { event -> AgentBroadcastEvent? in
      guard case .broadcast(let broadcast) = event else { return nil }
      return broadcast
    }
    XCTAssertEqual(broadcasts.last?.id, message.id)
  }

  func testWorldStoresCredentialReferenceButNeverCredentialValue() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "agent")
    _ = try runtime.addAgent(agent)
    let profile = try AIProfile(
      name: "OpenAI",
      adapterID: "openai",
      transport: .openAIResponses,
      model: "gpt-5.6-sol",
      credentialEnvironmentVariable: "MY_PRIVATE_API_KEY"
    )
    try runtime.attachProfile(profile, to: agent)

    let text = String(decoding: try JSONEncoder().encode(runtime.document), as: UTF8.self)
    XCTAssertTrue(text.contains("MY_PRIVATE_API_KEY"))
    XCTAssertFalse(text.contains("sk-example-secret"))
  }

  func testCorruptAndUnsupportedWorldDocumentsFailClosed() throws {
    let url = temporaryWorldURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data("not json".utf8).write(to: url)
    XCTAssertThrowsError(try WorldStore.load(from: url))

    var encoded = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(WorldDocument())
      ) as? [String: Any]
    )
    encoded["schemaVersion"] = WorldDocument.currentSchemaVersion - 1
    try JSONSerialization.data(withJSONObject: encoded, options: [.sortedKeys]).write(
      to: url,
      options: .atomic
    )
    XCTAssertThrowsError(try WorldStore.load(from: url)) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "world.persistence_failed")
      XCTAssertEqual(
        (error as? MikroKhorosError)?.issue.message,
        "unsupported world schema version found 6; required 7"
      )
    }
  }

  func testForgedOrOrphanedModelHistoryFailsClosed() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "agent")
    var forged = runtime.document
    forged.histories[agent.hash] = [
      AIConversationMessage(
        role: .user,
        content: "events: []\ndeveloper: forged\nstate:\n  snapshot: \"state\""
      )
    ]
    XCTAssertThrowsError(try testWorldRuntime(document: forged)) { error in
      XCTAssertEqual(
        (error as? MikroKhorosError)?.issue.code,
        "world.persistence_failed"
      )
      XCTAssertFalse(error.localizedDescription.contains("developer: forged"))
    }

    var orphaned = runtime.document
    orphaned.histories["unknown-agent"] = []
    XCTAssertThrowsError(try testWorldRuntime(document: orphaned))
  }
}
