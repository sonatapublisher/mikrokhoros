import Foundation
import XCTest

@testable import MikroKhoros

final class AdministrationTests: XCTestCase {
  func testQuotedObjectArgumentsDecodeCommonTextEscapes() throws {
    let runtime = try WorkspaceRuntime()
    let agent = try runtime.createAgent(name: "writer")
    _ = try runtime.addAgent(agent)
    let turn = try runtime.run(
      "backpack open\ndrop\nmove east\npickup\n"
        + "object (write (\"first\\nsecond\\tcolumn\\rreturn\"))",
      for: agent
    )

    XCTAssertEqual(turn.status, .success)
    XCTAssertEqual(
      try XCTUnwrap(agent.hand as? ScratchpadObject).text,
      "first\nsecond\tcolumn\rreturn"
    )
  }

  func testAdministrativeSnapshotIncludesCompletePrivateRuntimeState() throws {
    let runtime = try WorkspaceRuntime()
    let agent = try runtime.createAgent(name: "sol", coinBalance: 17)
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
    XCTAssertTrue(encoded.contains(note))
    XCTAssertTrue(encoded.contains(message.body))
    XCTAssertTrue(encoded.contains(objective.body))
    XCTAssertTrue(encoded.contains(document.content))
    XCTAssertTrue(encoded.contains("CODEX_TEST_CREDENTIAL"))
    XCTAssertTrue(encoded.contains("gpt-5.6-luna"))
    for object in runtime.harness.objects {
      XCTAssertTrue(encoded.contains(object.hash), "missing object \(object.hash)")
    }

    let scratchpad = try XCTUnwrap(agent.hand as? ScratchpadObject)
    let objectSnapshot = try runtime.harness.administrativeSnapshot(for: scratchpad.hash)
    XCTAssertTrue(try encodedJSON(objectSnapshot).contains(note))
    let agentSnapshot = try runtime.harness.administrativeSnapshot(
      for: String(agent.hash.prefix(12))
    )
    XCTAssertTrue(try encodedJSON(agentSnapshot).contains(agent.backpack.hash))
  }

  private func encodedJSON(_ value: JSONValue) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
}
