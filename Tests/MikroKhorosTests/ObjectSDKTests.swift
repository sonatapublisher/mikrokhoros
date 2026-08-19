import Foundation
import XCTest

@testable import MikroKhoros

final class ObjectSDKTests: XCTestCase {
  private let lampJSON = """
    {
      "type": "lamp.object",
      "name": "lamp",
      "public": {"color": "warm"},
      "state": {"on": false, "notes": []},
      "durability": 2,
      "container": true,
      "functions": {
        "status": {
          "parameters": [],
          "action": {"kind": "get", "key": "on"}
        },
        "switch": {
          "parameters": [],
          "durability_cost": 1,
          "action": {"kind": "toggle", "key": "on"}
        },
        "note": {
          "parameters": ["text"],
          "action": {"kind": "append", "key": "notes", "argument": 0}
        }
      }
    }
    """

  func testDeclarativePackageHasPrivateStateDurabilityAndInfiniteContainer() throws {
    let registry = BundleRegistry()
    XCTAssertEqual(try registry.install(data: Data(lampJSON.utf8)), "lamp.object")
    let lamp = try registry.create("lamp.object")
    let harness = try Harness()
    let agent = try harness.createAgent()

    XCTAssertTrue(lamp.container!.contains(Coordinate(x: -999_999, y: 999_999)))
    XCTAssertEqual(
      try lamp.invoke("status", arguments: [], harness: harness, agent: agent), "false")
    XCTAssertEqual(try lamp.invoke("switch", arguments: [], harness: harness, agent: agent), "true")
    XCTAssertEqual(
      try lamp.invoke("note", arguments: ["hello"], harness: harness, agent: agent), "1")
    XCTAssertEqual(lamp.privateState["on"], .bool(true))
    XCTAssertNil(lamp.publicData["on"])
    XCTAssertEqual(lamp.durability, 1)
  }

  func testPackagesCannotUpdateInPlaceOrDeclareExecutableActions() throws {
    let registry = BundleRegistry()
    try registry.install(data: Data(lampJSON.utf8))
    XCTAssertThrowsError(try registry.install(data: Data(lampJSON.utf8)))

    let executable = """
      {"type":"x.object","functions":{"run":{"parameters":[],
      "action":{"kind":"javascript","code":"fetch('https://example.com')"}}}}
      """
    XCTAssertThrowsError(try BundleRegistry().install(data: Data(executable.utf8)))
  }

  func testSDKCapabilitiesAreExplicitGrantedAndRevocable() throws {
    let package = try ObjectPackageManifest(
      id: "example.messenger",
      displayName: "Messenger",
      objectType: "messager.object",
      runtime: .javascript,
      entryPoint: "src/index.js",
      requestedCapabilities: [.privateChildren, .broadcast, .network, .worldSystem]
    )
    let registry = ObjectInstallationRegistry()
    let installation = try registry.install(package, intoWorld: "world")

    XCTAssertThrowsError(
      try registry.require(.network, installationID: installation.id)
    )
    try registry.approve([.broadcast, .network], for: installation.id)
    XCTAssertNoThrow(try registry.require(.broadcast, installationID: installation.id))
    XCTAssertNoThrow(try registry.require(.network, installationID: installation.id))
    XCTAssertThrowsError(try registry.require(.worldSystem, installationID: installation.id))
    try registry.revoke([.network], for: installation.id)
    XCTAssertThrowsError(try registry.require(.network, installationID: installation.id))
  }

  func testInstallationCannotGrantUnrequestedAuthority() throws {
    let package = try ObjectPackageManifest(
      id: "safe.clock",
      displayName: "Clock",
      objectType: "clock.object",
      runtime: .declarative,
      requestedCapabilities: [.worldRead]
    )
    let registry = ObjectInstallationRegistry()
    XCTAssertThrowsError(
      try registry.install(package, intoWorld: "world", grants: [.userMachine])
    )
  }

  func testInvocationIdentityUsesTrustedRuntimeState() throws {
    var captured: ObjectInvocationIdentity?
    let object = try MikroObject(typeName: "identity.object", installationID: "install-1")
    try object.registerFunction(name: "who", summary: "Show trusted invocation identity.") {
      context, _ in
      captured = context.identity
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
    XCTAssertEqual(captured?.installationID, "install-1")
    XCTAssertEqual(captured?.agentID, agent.hash)
    XCTAssertEqual(captured?.worldID, harness.world.hash)
  }
}
