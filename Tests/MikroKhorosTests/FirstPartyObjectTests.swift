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

final class FirstPartyObjectTests: XCTestCase {
  private struct Fixture {
    let root: URL
    let inventory: InventoryStore
  }

  private func fixture() throws -> Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-first-party-tests-\(UUID().uuidString)", isDirectory: true)
    let inventory = try InventoryStore(
      url: root.appendingPathComponent("inventory.json"),
      packageDirectory: root.appendingPathComponent("packages", isDirectory: true),
      credentialStore: FileCredentialStore(
        directory: root.appendingPathComponent("credentials", isDirectory: true)),
      runtimeRegistry: .installedCLI()
    )
    return Fixture(root: root, inventory: inventory)
  }

  private func install(
    _ name: String,
    fixture: Fixture,
    grantCapabilities: Bool = true
  ) throws -> InventoryObjectRecord {
    let result = try fixture.inventory.install(data: FirstPartyPackageCatalog.data(named: name))
    var object = try XCTUnwrap(result.inventoryObject)
    if grantCapabilities, !object.requestedCapabilities.isEmpty {
      object = try fixture.inventory.grant(
        id: object.id, capabilities: object.requestedCapabilities)
    }
    return object
  }

  func testBuiltInNativePackageRequiresItsExactRegisteredAdapter() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-untrusted-native-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let untrusted = try InventoryStore(url: root.appendingPathComponent("inventory.json"))
    XCTAssertThrowsError(
      try untrusted.install(data: FirstPartyPackageCatalog.data(named: "paper"))
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "object_package.runtime_unavailable")
    }

    let trusted = try InventoryStore(
      url: root.appendingPathComponent("trusted-inventory.json"),
      runtimeRegistry: .installedCLI()
    )
    XCTAssertNotNil(
      try trusted.install(data: FirstPartyPackageCatalog.data(named: "paper")).inventoryObject)

    let workspaceManifest = try FirstPartyPackageCatalog.manifest(named: "user-workspace")
    let mountAdd = try XCTUnwrap(
      workspaceManifest.management.actions.first { $0.id == "mount-add" }
    )
    XCTAssertEqual(mountAdd.inputDefaults["access"], .string("read-only"))
    XCTAssertEqual(mountAdd.inputDefaults["x"], .number(0))
    XCTAssertEqual(mountAdd.inputChoices["access"], ["read-only", "read-write"])
    XCTAssertEqual(
      try trusted.runtimeRegistry.externalEffects(for: workspaceManifest),
      [.userFolder]
    )
  }

  func testPrinterAndPencilComposeWithPaperThroughObjectAudienceFunctions() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let paperSource = try install("paper", fixture: fixture)
    let printerSource = try install("printer", fixture: fixture)
    let pencilSource = try install("pencil", fixture: fixture)
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    let agent = try runtime.createAgent(name: "maker")
    _ = try runtime.addAgent(agent, at: Coordinate(x: 10, y: 10))
    XCTAssertEqual(try runtime.run("drop west", for: agent).status, .success)

    let printerDeployment = try runtime.deployInventoryObject(
      printerSource.id, at: Coordinate(x: 10, y: 10))
    let paperDeployment = try runtime.deployInventoryObject(
      paperSource.id, at: Coordinate(x: 10, y: 9))
    let printer = try XCTUnwrap(
      runtime.harness.findObject(printerDeployment.snapshot.objectID) as? PrinterObject)
    let paper = try XCTUnwrap(
      runtime.harness.findObject(paperDeployment.snapshot.objectID) as? PaperObject)

    XCTAssertEqual(try runtime.run("object (print (hello))", for: agent).status, .success)
    XCTAssertEqual(paper.text, "hello")
    XCTAssertEqual(printer.durability, 99)
    XCTAssertTrue(
      runtime.document.events.contains { event in
        guard
          case .nestedInvocationReceipt(
            _, _, let sourceID, let targetID, let originalAgentID, "write", "written", 1
          ) = event
        else { return false }
        return sourceID == printer.hash && targetID == paper.hash
          && originalAgentID == agent.hash
      }
    )
    XCTAssertThrowsError(
      try paper.invoke("write", arguments: ["direct"], harness: runtime.harness, agent: agent)
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "object.target_invocation_denied")
    }

    let pencilDeployment = try runtime.deployInventoryObject(
      pencilSource.id, at: Coordinate(x: 11, y: 10))
    XCTAssertEqual(try runtime.run("move east\npickup", for: agent).status, .success)
    XCTAssertEqual(agent.primaryHeldObject?.hash, pencilDeployment.snapshot.objectID)
    XCTAssertEqual(
      try runtime.run("move north\nobject (append (-1) (0) (!))", for: agent).status, .success)
    XCTAssertEqual(paper.text, "hello!")
    XCTAssertEqual(agent.primaryHeldObject?.durability, 99)
    XCTAssertEqual(
      try runtime.moveWorldObject(
        objectID: pencilDeployment.snapshot.objectID,
        to: "world",
        at: Coordinate(x: 30, y: 30)
      ),
      Coordinate(x: 30, y: 30)
    )
    XCTAssertNil(agent.primaryHeldObject)

    let restored = try testWorldRuntime(document: runtime.document, inventory: fixture.inventory)
    XCTAssertEqual(
      (restored.harness.findObject(paper.hash) as? PaperObject)?.text,
      "hello!"
    )
    XCTAssertEqual(restored.harness.findObject(printer.hash)?.durability, 99)
    XCTAssertEqual(
      restored.harness.findObject(pencilDeployment.snapshot.objectID)?.coordinate,
      Coordinate(x: 30, y: 30)
    )
  }

  func testWorldBoundWorkspaceProjectsAndEditsHostFileWithoutReplaySideEffects() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let host = fixture.root.appendingPathComponent("host", isDirectory: true)
    try FileManager.default.createDirectory(at: host, withIntermediateDirectories: true)
    let fileURL = host.appendingPathComponent("note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let template = try install("user-workspace", fixture: fixture, grantCapabilities: false)
    let pencilSource = try install("pencil", fixture: fixture)
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    let fork = try fixture.inventory.fork(
      id: template.id,
      worldID: runtime.harness.world.hash,
      name: "Bound workspace"
    )
    _ = try fixture.inventory.grant(id: fork.id, capabilities: [.userMachine])
    _ = try fixture.inventory.runAction(
      id: fork.id,
      actionID: "mount-add",
      inputs: ["repository", host.path, "0", "0", "read-write", "false"]
    )
    let deployment = try runtime.deployInventoryObject(
      fork.id, at: Coordinate(x: 20, y: 20))
    let workspace = try XCTUnwrap(
      runtime.harness.findObject(deployment.snapshot.objectID) as? UserWorkspaceObject)
    let projectedFile = try XCTUnwrap(
      workspace.walkContents().first(where: { $0.typeName == "user-file.object" }))
    XCTAssertFalse(projectedFile.inspect().publicData.description.contains(host.path))
    XCTAssertThrowsError(
      try runtime.moveWorldObject(
        objectID: projectedFile.hash, to: "world", at: Coordinate(x: 30, y: 30))
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "object.anchored")
    }
    XCTAssertEqual(
      try runtime.moveWorldObject(
        objectID: workspace.hash, to: "world", at: Coordinate(x: 21, y: 20)),
      Coordinate(x: 21, y: 20)
    )

    let agent = try runtime.createAgent(name: "editor")
    _ = try runtime.addAgent(agent, at: Coordinate(x: 21, y: 21))
    XCTAssertEqual(
      try runtime.run("drop west\nmove north\ncontainer in\ncontainer in", for: agent).status,
      .success
    )
    XCTAssertEqual(try runtime.run("move east 10", for: agent).status, .success)
    _ = try runtime.deployInventoryObject(pencilSource.id, to: agent.hash)
    XCTAssertEqual(
      try runtime.run("backpack open\npickup\nbackpack close\nmove west 9", for: agent).status,
      .success
    )
    XCTAssertEqual(
      try runtime.run("object (append (-1) (0) (!))", for: agent).status,
      .success
    )
    XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "hello!")
    XCTAssertTrue(
      runtime.document.events.contains { event in
        if case .externalEffectReceipt(_, let objectID, "append", _, _) = event {
          return objectID == projectedFile.hash
        }
        return false
      })

    let restored = try testWorldRuntime(document: runtime.document, inventory: fixture.inventory)
    XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "hello!")
    XCTAssertNotNil(restored.harness.findObject(projectedFile.hash))
  }

  func testProjectionReconcilesLazilyAndKeepsLinksNonTraversable() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let host = fixture.root.appendingPathComponent("live", isDirectory: true)
    try FileManager.default.createDirectory(at: host, withIntermediateDirectories: true)
    let original = host.appendingPathComponent("original.txt")
    try Data("one".utf8).write(to: original)
    let link = host.appendingPathComponent("shortcut")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)

    let template = try install("user-workspace", fixture: fixture, grantCapabilities: false)
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    let fork = try fixture.inventory.fork(id: template.id, worldID: runtime.harness.world.hash)
    _ = try fixture.inventory.grant(id: fork.id, capabilities: [.userMachine])
    _ = try fixture.inventory.runAction(
      id: fork.id,
      actionID: "mount-add",
      inputs: ["live", host.path, "0", "0", "read-only", "false"]
    )
    let deployed = try runtime.deployInventoryObject(fork.id, at: Coordinate(x: 8, y: 8))
    let workspace = try XCTUnwrap(
      runtime.harness.findObject(deployed.snapshot.objectID) as? UserWorkspaceObject)
    let projectedLink = try XCTUnwrap(
      workspace.walkContents().first { $0.typeName == "filesystem-link.object" })
    XCTAssertNil(projectedLink.container)
    XCTAssertTrue(projectedLink.inspect().functions.isEmpty)
    XCTAssertFalse(projectedLink.inspect().publicData.description.contains(host.path))

    let rootFolder = try XCTUnwrap(
      workspace.walkContents().first {
        $0.typeName == "user-folder.object"
          && $0.inspect().publicData["relative_path"] == .string("")
      })
    let agent = try runtime.createAgent(name: "observer")
    _ = try runtime.addAgent(agent, at: Coordinate(x: 50, y: 50))
    agent.space = try XCTUnwrap(rootFolder.container)
    agent.coordinate = .origin
    let added = host.appendingPathComponent("added.txt")
    try Data("two".utf8).write(to: added)
    _ = try runtime.harness.renderEyeView(for: agent)
    XCTAssertTrue(workspace.walkContents().contains { $0.name == "added.txt" })

    try FileManager.default.removeItem(at: original)
    _ = try runtime.harness.renderEyeView(for: agent)
    XCTAssertFalse(workspace.walkContents().contains { $0.name == "original.txt" })

    try FileManager.default.removeItem(at: host)
    let status = try runtime.renderWorldManagementView(
      objectID: workspace.hash,
      viewID: "readiness"
    )
    XCTAssertEqual(status.objectValue?["status"], .string("degraded"))
    XCTAssertNotNil(runtime.harness.findObject(workspace.hash))
    XCTAssertThrowsError(try runtime.harness.renderEyeView(for: agent)) { error in
      XCTAssertEqual(
        (error as? MikroKhorosError)?.issue.code,
        "user_workspace.mount_unavailable"
      )
    }
  }

  func testProjectedWritesRejectReadOnlyAndNonUTF8TargetsWithoutDurabilityLoss() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let readOnlyHost = fixture.root.appendingPathComponent("readonly", isDirectory: true)
    let writableHost = fixture.root.appendingPathComponent("writable", isDirectory: true)
    try FileManager.default.createDirectory(at: readOnlyHost, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: writableHost, withIntermediateDirectories: true)
    try Data("unchanged".utf8).write(to: readOnlyHost.appendingPathComponent("note.txt"))
    try Data([0xFF, 0xFE, 0x00]).write(to: writableHost.appendingPathComponent("binary.dat"))

    let template = try install("user-workspace", fixture: fixture, grantCapabilities: false)
    let pencilSource = try install("pencil", fixture: fixture)
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    let fork = try fixture.inventory.fork(id: template.id, worldID: runtime.harness.world.hash)
    _ = try fixture.inventory.grant(id: fork.id, capabilities: [.userMachine])
    _ = try fixture.inventory.runAction(
      id: fork.id,
      actionID: "mount-add",
      inputs: ["readonly", readOnlyHost.path, "0", "0", "read-only", "false"]
    )
    _ = try fixture.inventory.runAction(
      id: fork.id,
      actionID: "mount-add",
      inputs: ["writable", writableHost.path, "1", "0", "read-write", "false"]
    )
    let workspaceDeployment = try runtime.deployInventoryObject(
      fork.id, at: Coordinate(x: 12, y: 12))
    let workspace = try XCTUnwrap(
      runtime.harness.findObject(workspaceDeployment.snapshot.objectID) as? UserWorkspaceObject)
    let readOnlyFile = try XCTUnwrap(
      workspace.walkContents().first { $0.name == "note.txt" })
    let binaryFile = try XCTUnwrap(
      workspace.walkContents().first { $0.name == "binary.dat" })
    let agent = try runtime.createAgent(name: "writer")
    _ = try runtime.addAgent(agent, at: Coordinate(x: 40, y: 40))
    let pencilDeployment = try runtime.deployInventoryObject(pencilSource.id, to: agent.hash)
    let pencil = try XCTUnwrap(
      runtime.harness.findObject(pencilDeployment.snapshot.objectID) as? PencilObject)
    _ = try XCTUnwrap(pencil.parentSpace).remove(at: try XCTUnwrap(pencil.coordinate))
    agent.holdings.select(.two)
    agent.holdings[.two] = pencil

    agent.space = try XCTUnwrap(readOnlyFile.parentSpace)
    agent.coordinate = try XCTUnwrap(readOnlyFile.coordinate) + Coordinate(x: 1, y: 0)
    XCTAssertThrowsError(
      try pencil.invoke(
        "write", arguments: ["-1", "0", "changed"], harness: runtime.harness, agent: agent)
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "file.read_only")
    }
    XCTAssertEqual(pencil.durability, 100)

    agent.space = try XCTUnwrap(binaryFile.parentSpace)
    agent.coordinate = try XCTUnwrap(binaryFile.coordinate) + Coordinate(x: 1, y: 0)
    XCTAssertThrowsError(
      try pencil.invoke(
        "write", arguments: ["-1", "0", "changed"], harness: runtime.harness, agent: agent)
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "file.encoding_unsupported")
    }
    XCTAssertEqual(pencil.durability, 100)
    XCTAssertEqual(
      try Data(contentsOf: writableHost.appendingPathComponent("binary.dat")),
      Data([0xFF, 0xFE, 0x00]))
  }
}
