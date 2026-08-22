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

private final class LockedCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var stored = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }

  func increment() {
    lock.lock()
    stored += 1
    lock.unlock()
  }
}

final class ObjectSDKTests: XCTestCase {
  private func lampPackage(runtime: ObjectPackageRuntime = .declarative) throws
    -> ObjectPackageManifest
  {
    try ObjectPackageManifest(
      id: "example.lamp",
      version: "1.0.0",
      displayName: "Lamp",
      runtime: runtime,
      requestedCapabilities: [.worldRead],
      installation: PackageInstallationPolicy(
        onInstall: .registerOnly,
        additionalInventoryObjects: .allow
      ),
      object: DeclarativeObjectDefinition(
        type: "lamp.object",
        name: "lamp",
        publicData: ["color": .string("warm")],
        state: ["on": .bool(false), "notes": .array([])],
        durability: 2,
        container: true,
        functions: [
          "status": try DeclarativeFunctionDefinition(
            action: DeclarativeAction(kind: .get, key: "on")
          ),
          "switch": try DeclarativeFunctionDefinition(
            durabilityCost: 1,
            action: DeclarativeAction(kind: .toggle, key: "on")
          ),
          "note": try DeclarativeFunctionDefinition(
            parameters: ["text"],
            action: DeclarativeAction(kind: .append, key: "notes", argument: 0)
          ),
        ]
      )
    )
  }

  func testUnifiedDeclarativePackageCreatesClosedRuntimeObject() throws {
    let package = try lampPackage()
    let data = try JSONEncoder().encode(package)
    let registry = ObjectPackageRegistry()
    XCTAssertEqual(try registry.install(data: data), package.id)
    let lamp = try registry.create(package.id)
    let harness = try Harness()
    let agent = try harness.createAgent()
    try harness.place(lamp)
    _ = try harness.addAgent(agent)

    XCTAssertTrue(lamp.container!.contains(Coordinate(x: -999_999, y: 999_999)))
    XCTAssertEqual(
      try lamp.invoke("status", arguments: [], harness: harness, agent: agent), "false")
    XCTAssertEqual(try lamp.invoke("switch", arguments: [], harness: harness, agent: agent), "true")
    XCTAssertEqual(
      try lamp.invoke("note", arguments: ["hello"], harness: harness, agent: agent), "1")
    XCTAssertEqual(lamp.privateState["on"], .bool(true))
    XCTAssertNil(lamp.publicData["on"])
    XCTAssertEqual(lamp.durability, 1)
    XCTAssertThrowsError(try registry.install(data: data))
  }

  func testUnavailableRuntimeFailsAtInstallation() throws {
    let package = try lampPackage(runtime: .javascript)
    XCTAssertThrowsError(try ObjectPackageRegistry().install(data: JSONEncoder().encode(package))) {
      XCTAssertEqual(
        ($0 as? MikroKhorosError)?.issue.code,
        "object_package.runtime_unavailable"
      )
    }
  }

  func testSemanticVersionsAndOwnedObjectGraphsAreValidated() throws {
    let leaf = try DeclarativeObjectDefinition(
      type: "sensor.object",
      name: "sensor",
      state: ["samples": .number(0)]
    )
    let package = try ObjectPackageManifest(
      id: "example.graph",
      version: "1.2.3-rc.1+build.7",
      displayName: "Graph",
      object: DeclarativeObjectDefinition(
        type: "hub.object",
        name: "hub",
        container: true
      ),
      ownedObjects: [
        try DeclarativeOwnedObjectDefinition(
          id: "sensor",
          coordinate: Coordinate(x: 2, y: -1),
          object: leaf
        )
      ]
    )
    let registry = ObjectPackageRegistry()
    _ = try registry.install(data: JSONEncoder().encode(package))
    let root = try registry.create(package.id)
    XCTAssertEqual(root.container?.object(at: Coordinate(x: 2, y: -1))?.typeName, "sensor.object")

    let largeNumericVersion = try ObjectPackageSemanticVersion(
      "999999999999999999999999999999.0.0-alpha.999999999999999999999999999999"
    )
    let smallerNumericVersion = try ObjectPackageSemanticVersion("2.0.0-alpha.2")
    XCTAssertGreaterThan(largeNumericVersion, smallerNumericVersion)

    XCTAssertThrowsError(
      try ObjectPackageManifest(
        id: "example.bad-version",
        version: "01.2.3",
        displayName: "Invalid",
        object: leaf
      )
    )
    XCTAssertThrowsError(
      try ObjectPackageManifest(
        id: "example.bad-graph",
        version: "1.0.0",
        displayName: "Invalid",
        object: leaf,
        ownedObjects: [
          try DeclarativeOwnedObjectDefinition(id: "child", object: leaf)
        ]
      )
    )
  }

  func testRemotePackagePolicyRejectsPlaintextBeforeNetworkUse() async throws {
    let url = try XCTUnwrap(URL(string: "http://example.com/package.json"))
    do {
      _ = try await ObjectPackageDownloader.download(url, maximumBytes: 1024)
      XCTFail("remote plaintext URL was accepted")
    } catch let error as MikroKhorosError {
      XCTAssertEqual(error.issue.code, "object_package.url_rejected")
    }
  }

  func testPackageContentDigestMatchesSHA256() {
    XCTAssertEqual(
      SHA256Digest.hex(Data("abc".utf8)),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
  }

  func testLocalPackageReaderEnforcesLimitDuringRead() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-package-\(UUID().uuidString).json"
    )
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("abcd".utf8).write(to: url)
    XCTAssertEqual(try BoundedPackageFile.read(url, maximumBytes: 4), Data("abcd".utf8))
    XCTAssertThrowsError(try BoundedPackageFile.read(url, maximumBytes: 3)) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "object_package.too_large")
    }
  }

  func testCapabilityMediatedServicesCheckEveryProtectedOperation() throws {
    let calls = LockedCounter()
    let denied = ObjectWorldReadService(
      capabilities: ObjectCapabilityBroker(granted: [])
    ) { _ in
      calls.increment()
      return .string("private")
    }
    XCTAssertThrowsError(try denied.read("world"))
    XCTAssertEqual(calls.value, 0)

    let allowed = ObjectWorldReadService(
      capabilities: ObjectCapabilityBroker(granted: [.worldRead])
    ) { _ in
      calls.increment()
      return .string("bounded")
    }
    XCTAssertEqual(try allowed.read("world"), .string("bounded"))
    XCTAssertEqual(calls.value, 1)

    let folders = ObjectUserFolderService(
      capabilities: ObjectCapabilityBroker(granted: []),
      list: { _, _ in
        calls.increment()
        return []
      },
      read: { _, _, _ in Data() },
      write: { _, _, _ in },
      append: { _, _, _ in },
      clear: { _, _ in }
    )
    XCTAssertThrowsError(try folders.list(bindingID: "binding", relativePath: ""))
    XCTAssertEqual(calls.value, 1)
  }

  func testSchemaOneFunctionsDecodeWithAgentAudience() throws {
    let encoded = try JSONEncoder().encode(lampPackage())
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    json["schema"] = 1
    var object = try XCTUnwrap(json["object"] as? [String: Any])
    var functions = try XCTUnwrap(object["functions"] as? [String: [String: Any]])
    for key in functions.keys { functions[key]?.removeValue(forKey: "audience") }
    object["functions"] = functions
    json["object"] = object

    let decoded = try JSONDecoder().decode(
      ObjectPackageManifest.self,
      from: JSONSerialization.data(withJSONObject: json)
    )
    XCTAssertEqual(decoded.schema, ObjectPackageManifest.currentSchemaVersion)
    XCTAssertTrue(decoded.object.functions.values.allSatisfy { $0.audience == .agent })
  }

  func testInvocationIdentityUsesConcreteRuntimeValuesAndSeparateLineage() throws {
    var captured: ObjectInvocationIdentity?
    var retainedEmitter: (any ObjectReportEmitter)?
    let lineage = ObjectLineage(
      packageID: "example.identity",
      packageVersion: "1.0.0",
      packageHash: String(repeating: "a", count: 64),
      inventoryObjectID: String(repeating: "b", count: 32),
      inventoryRevision: 3,
      deploymentID: String(repeating: "c", count: 32)
    )
    let object = try MikroObject(typeName: "identity.object", lineage: lineage)
    try object.registerAgentFunction(name: "who", summary: "Show invocation identity.") {
      context, _ in
      captured = context.identity
      retainedEmitter = context.reports
      return "ok"
    }
    let harness = try Harness()
    let agent = try harness.createAgent(name: "agent")
    try harness.addAgent(agent)
    try harness.stowHeldObject(for: agent)
    try harness.place(object)
    _ = try harness.pickup(for: agent)
    _ = try harness.invokeHeld(for: agent, function: "who", arguments: [])

    XCTAssertEqual(captured?.objectID, object.hash)
    XCTAssertEqual(captured?.agentID, agent.hash)
    XCTAssertEqual(captured?.worldID, harness.world.hash)
    XCTAssertEqual(captured?.lineage, lineage)
    XCTAssertThrowsError(
      try retainedEmitter?.emit(type: "late", title: "late", body: "late", payload: .null)
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "object.context_expired")
    }
  }

  func testRelativeObjectInvocationEnforcesAudienceIdentityAndSuccessfulDurability() throws {
    let harness = try Harness()
    let agent = try harness.createAgent(name: "writer")
    try harness.addAgent(agent)
    try harness.stowHeldObject(for: agent)
    var targetIdentity: ObjectInvocationIdentity?
    var stored = ""
    let target = try MikroObject(
      typeName: "target.object",
      durability: 100,
      invocationAccess: .surface
    )
    try target.registerObjectFunction(
      name: "write",
      summary: "Replace text.",
      parameters: ["text"],
      durabilityCost: 1
    ) { context, arguments in
      targetIdentity = context.identity
      stored = arguments[0]
      return "written"
    }
    let tool = try MikroObject(
      typeName: "tool.object",
      durability: 100,
      capturedCapabilities: [.worldWrite]
    )
    try tool.registerAgentFunction(
      name: "write",
      summary: "Write east.",
      parameters: ["text"],
      durabilityCost: 1
    ) { context, arguments in
      try XCTUnwrap(context.worldWrite).invoke(
        at: Coordinate(x: 1, y: 0),
        function: "write",
        arguments: arguments
      )
    }
    try harness.place(tool, at: .origin)
    try harness.place(target, at: Coordinate(x: 1, y: 0))
    _ = try harness.pickup(for: agent)

    XCTAssertEqual(
      try harness.invokeHeld(for: agent, function: "write", arguments: ["hello"]),
      "written"
    )
    XCTAssertEqual(stored, "hello")
    XCTAssertEqual(tool.durability, 99)
    XCTAssertEqual(target.durability, 99)
    XCTAssertEqual(targetIdentity?.callingObjectID, tool.hash)
    XCTAssertEqual(targetIdentity?.targetObjectID, target.hash)
    XCTAssertEqual(targetIdentity?.originalAgentID, agent.hash)
    XCTAssertEqual(targetIdentity?.callDepth, 1)
    XCTAssertNotEqual(targetIdentity?.rootInvocationID, targetIdentity?.currentInvocationID)

    XCTAssertThrowsError(
      try target.invoke("write", arguments: ["direct"], harness: harness, agent: agent)
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "object.target_invocation_denied")
    }
    XCTAssertEqual(target.durability, 99)
  }

  func testRelativeObjectInvocationFailureLeavesBothDurabilitiesUnchanged() throws {
    let harness = try Harness()
    let agent = try harness.createAgent(name: "writer")
    try harness.addAgent(agent)
    try harness.stowHeldObject(for: agent)
    let tool = try MikroObject(
      typeName: "tool.object",
      durability: 100,
      capturedCapabilities: [.worldWrite]
    )
    try tool.registerAgentFunction(
      name: "write",
      summary: "Write east.",
      durabilityCost: 1
    ) { context, _ in
      try XCTUnwrap(context.worldWrite).invoke(
        at: Coordinate(x: 1, y: 0),
        function: "write",
        arguments: ["hello"]
      )
    }
    try harness.place(tool, at: .origin)
    _ = try harness.pickup(for: agent)
    XCTAssertThrowsError(try harness.invokeHeld(for: agent, function: "write", arguments: [])) {
      error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "object.target_missing")
    }
    XCTAssertEqual(tool.durability, 100)
  }
}
