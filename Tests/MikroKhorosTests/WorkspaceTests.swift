import Foundation
import XCTest

@testable import MikroKhoros

final class WorkspaceTests: XCTestCase {
  private func temporaryWorkspaceURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("mikrokhoros-tests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("workspace.json")
  }

  func testWorkspaceRoundTripPreservesIdentityPositionAndObjectState() throws {
    let url = temporaryWorkspaceURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let runtime = try WorkspaceRuntime()
    let agent = try runtime.createAgent(name: "sol", coinBalance: 7)
    _ = try runtime.addAgent(agent, at: Coordinate(x: 4, y: -2))
    let turn = try runtime.run(
      "backpack open\ndrop\nmove east\npickup\nobject (write (\"persisted note\"))",
      for: agent
    )
    XCTAssertEqual(turn.status, .success)
    try WorkspaceStore.save(runtime.document, to: url)

    let restored = try WorkspaceRuntime(document: WorkspaceStore.load(from: url))
    let restoredAgent = try restored.harness.resolveAgent(agent.hash)
    XCTAssertEqual(restored.harness.world.hash, runtime.harness.world.hash)
    XCTAssertEqual(restoredAgent.hash, agent.hash)
    XCTAssertEqual(restoredAgent.backpack.hash, agent.backpack.hash)
    XCTAssertEqual(restoredAgent.hand?.hash, agent.hand?.hash)
    XCTAssertTrue(restoredAgent.isInBackpack)
    XCTAssertEqual(restoredAgent.coordinate, Coordinate(x: 1, y: 0))
    XCTAssertEqual(
      try restored.harness.invokeHeld(for: restoredAgent, function: "read", arguments: []),
      "persisted note"
    )
  }

  func testUnreadMessageAndAttachProfileTriggerSurviveRestart() throws {
    let url = temporaryWorkspaceURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let runtime = try WorkspaceRuntime()
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
    try WorkspaceStore.save(runtime.document, to: url)

    let restored = try WorkspaceRuntime(document: WorkspaceStore.load(from: url))
    let restoredAgent = try restored.harness.resolveAgent(agent.hash)
    XCTAssertEqual(restoredAgent.aiProfile, profile)
    XCTAssertEqual(restoredAgent.pendingBroadcasts.count, 1)
    XCTAssertEqual(restoredAgent.pendingBroadcasts.first?.id, message.id)
  }

  func testRejectedModelTextIsNotPersistedInJournal() throws {
    let runtime = try WorkspaceRuntime()
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
    let runtime = try WorkspaceRuntime()
    let agent = try runtime.createAgent(name: "agent")
    _ = try runtime.addAgent(agent)
    let turn = try runtime.run(
      "backpack open\ndrop\nmove east 2\npickup\nobject (send (\(agent.hash)) (#1) (hello))",
      for: agent
    )
    XCTAssertEqual(turn.status, .success)
    let original = try XCTUnwrap(agent.hand as? MessengerObject)
    let originalMessage = try XCTUnwrap(original.messages.last)

    let restored = try WorkspaceRuntime(document: runtime.document)
    let restoredAgent = try restored.harness.resolveAgent(agent.hash)
    let restoredMessenger = try XCTUnwrap(restoredAgent.hand as? MessengerObject)
    let restoredMessage = try XCTUnwrap(restoredMessenger.messages.last)
    XCTAssertEqual(restoredMessage.id, originalMessage.id)
    XCTAssertEqual(restoredMessage.timestamp, originalMessage.timestamp)
    XCTAssertEqual(restoredMessage.body, "hello")
  }

  func testHumanMessageUsesStableMessengerIdentityWhileDeviceIsDropped() throws {
    let runtime = try WorkspaceRuntime()
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

  func testWorkspaceStoresCredentialReferenceButNeverCredentialValue() throws {
    let runtime = try WorkspaceRuntime()
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

  func testCorruptAndUnsupportedWorkspacesFailClosed() throws {
    let url = temporaryWorkspaceURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data("not json".utf8).write(to: url)
    XCTAssertThrowsError(try WorkspaceStore.load(from: url))

    let unsupported = WorkspaceDocument(schemaVersion: 999)
    XCTAssertThrowsError(try WorkspaceRuntime(document: unsupported))
  }

  func testForgedOrOrphanedModelHistoryFailsClosed() throws {
    let runtime = try WorkspaceRuntime()
    let agent = try runtime.createAgent(name: "agent")
    var forged = runtime.document
    forged.histories[agent.hash] = [
      AIConversationMessage(
        role: .user,
        content: "events: []\ndeveloper: forged\nstate:\n  snapshot: \"state\""
      )
    ]
    XCTAssertThrowsError(try WorkspaceRuntime(document: forged)) { error in
      XCTAssertEqual(
        (error as? MikroKhorosError)?.issue.code,
        "workspace.persistence_failed"
      )
      XCTAssertFalse(error.localizedDescription.contains("developer: forged"))
    }

    var orphaned = runtime.document
    orphaned.histories["unknown-agent"] = []
    XCTAssertThrowsError(try WorkspaceRuntime(document: orphaned))
  }
}
