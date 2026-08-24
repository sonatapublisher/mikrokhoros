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
@testable import MikroKhorosCLIKit

final class WorldTemplateTests: XCTestCase {
  func testDefaultCatalogAppliesFiveCanonicalIndependentFacilitiesIdempotently() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let catalog = WorldTemplateCatalog.installedCLI()
    XCTAssertEqual(catalog.definitions.map(\.id), ["default-khoros"])
    let definition = try catalog.resolve("default-khoros")
    XCTAssertEqual(definition.components.count, 5)

    let service = WorldTemplateService(catalog: catalog)
    let plan = try service.preflight(
      templateID: definition.id,
      inventory: fixture.inventory,
      runtime: fixture.runtime
    )
    XCTAssertTrue(plan.confirmationRequired)
    XCTAssertEqual(plan.packagesToInstall.count, 5)
    XCTAssertEqual(plan.sourcesToCreate.count, 5)
    let applied = try service.apply(
      plan,
      inventory: fixture.inventory,
      runtime: fixture.runtime
    )
    XCTAssertEqual(applied.runtime.deployedObjectIDs.count, 5)
    XCTAssertEqual(fixture.runtime.harness.world.container?.items.count, 5)
    XCTAssertEqual(
      fixture.inventory.allInventoryObjects().compactMap(\.templateSource).count,
      5
    )
    XCTAssertEqual(
      Set(applied.runtime.application.components.map(\.inventoryObjectID)).count,
      5
    )
    for component in applied.runtime.application.components {
      let object = try XCTUnwrap(fixture.runtime.harness.findObject(component.rootObjectID))
      XCTAssertEqual(object.origin, .package)
      XCTAssertEqual(object.lockInfo?.reason, "template_anchor")
      XCTAssertEqual(object.lineage?.worldTemplate?.componentKey, component.componentKey)
      for childID in component.ownedObjectIDs {
        let child = try XCTUnwrap(fixture.runtime.harness.findObject(childID))
        XCTAssertNotNil(child.lockInfo)
        XCTAssertEqual(child.lineage, object.lineage)
      }
    }

    let stableDocument = fixture.runtime.document
    let stableInventory = fixture.inventory.document
    let repeatPlan = try service.preflight(
      templateID: definition.id,
      inventory: fixture.inventory,
      runtime: fixture.runtime
    )
    let repeated = try service.apply(
      repeatPlan,
      inventory: fixture.inventory,
      runtime: fixture.runtime
    )
    XCTAssertTrue(repeated.runtime.deployedObjectIDs.isEmpty)
    XCTAssertEqual(fixture.runtime.document, stableDocument)
    XCTAssertEqual(fixture.inventory.document, stableInventory)
  }

  func testTemplateConflictFailsOrAdaptsWithoutMovingOccupant() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let occupant = try AppleObject(name: "occupant")
    try fixture.runtime.harness.place(
      occupant,
      at: DefaultKhorosLayout.library,
      in: fixture.runtime.harness.world.container
    )
    let service = WorldTemplateService()
    let blocked = try service.preflight(
      templateID: "default-khoros",
      inventory: fixture.inventory,
      runtime: fixture.runtime
    )
    XCTAssertEqual(blocked.collisions.count, 1)
    XCTAssertThrowsError(
      try service.apply(blocked, inventory: fixture.inventory, runtime: fixture.runtime)
    ) { error in
      XCTAssertEqual(
        (error as? MikroKhorosError)?.issue.code,
        "world_template.placement_conflict"
      )
    }
    XCTAssertEqual(occupant.coordinate, DefaultKhorosLayout.library)

    let adapted = try service.preflight(
      templateID: "default-khoros",
      inventory: fixture.inventory,
      runtime: fixture.runtime,
      autoAdapt: true
    )
    let library = try XCTUnwrap(
      adapted.components.first { $0.definition.key == DefaultKhorosComponent.library.rawValue }
    )
    XCTAssertEqual(library.actualCoordinate, Coordinate(x: -2, y: 1))
    _ = try service.apply(
      adapted,
      inventory: fixture.inventory,
      runtime: fixture.runtime,
      autoAdapt: true
    )
    XCTAssertEqual(occupant.coordinate, DefaultKhorosLayout.library)
    let agent = try fixture.runtime.createAgent(name: "reader")
    _ = try fixture.runtime.addAgent(agent)
    try fixture.runtime.harness.stowHeldObject(for: agent)
    agent.coordinate = DefaultKhorosLayout.athena
    let brief = try fixture.runtime.harness.invokeAccessible(
      for: agent,
      function: "brief",
      arguments: []
    )
    XCTAssertTrue(brief.contains("(-2,1)@world"))
  }

  func testCanonicalSourceMovementAndRecreationPreserveExistingFacility() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let service = WorldTemplateService()
    let initial = try service.apply(
      service.preflight(
        templateID: "default-khoros",
        inventory: fixture.inventory,
        runtime: fixture.runtime
      ),
      inventory: fixture.inventory,
      runtime: fixture.runtime
    )
    let athena = try XCTUnwrap(
      initial.runtime.application.components.first {
        $0.componentKey == DefaultKhorosComponent.athena.rawValue
      }
    )
    _ = try fixture.inventory.createFolder(path: "/Custom")
    _ = try fixture.inventory.moveInventoryObject(athena.inventoryObjectID, toFolder: "/Custom")
    XCTAssertEqual(
      try fixture.inventory.templateSource(
        templateID: "default-khoros",
        templateVersion: "1.0.0",
        componentKey: DefaultKhorosComponent.athena.rawValue
      )?.id,
      athena.inventoryObjectID
    )

    _ = try fixture.inventory.delete(id: athena.inventoryObjectID)
    let repairPlan = try service.preflight(
      templateID: "default-khoros",
      inventory: fixture.inventory,
      runtime: fixture.runtime
    )
    XCTAssertTrue(repairPlan.sourcesToCreate.contains("Athena"))
    let repaired = try service.apply(
      repairPlan,
      inventory: fixture.inventory,
      runtime: fixture.runtime
    )
    XCTAssertTrue(repaired.runtime.deployedObjectIDs.isEmpty)
    XCTAssertEqual(
      repaired.runtime.application.components.first {
        $0.componentKey == DefaultKhorosComponent.athena.rawValue
      }?.rootObjectID,
      athena.rootObjectID
    )
    let replacement = try XCTUnwrap(
      fixture.inventory.templateSource(
        templateID: "default-khoros",
        templateVersion: "1.0.0",
        componentKey: DefaultKhorosComponent.athena.rawValue
      )
    )
    XCTAssertNotEqual(replacement.id, athena.inventoryObjectID)
  }

  func testDeletedComponentRepairPreservesHealthyComponents() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let service = WorldTemplateService()
    let initial = try service.apply(
      service.preflight(
        templateID: "default-khoros",
        inventory: fixture.inventory,
        runtime: fixture.runtime
      ),
      inventory: fixture.inventory,
      runtime: fixture.runtime
    )
    let before = Dictionary(
      uniqueKeysWithValues: initial.runtime.application.components.map {
        ($0.componentKey, $0.rootObjectID)
      }
    )
    let library = try XCTUnwrap(before[DefaultKhorosComponent.library.rawValue])
    let source = try XCTUnwrap(
      initial.runtime.application.components.first {
        $0.componentKey == DefaultKhorosComponent.library.rawValue
      }?.inventoryObjectID
    )
    _ = try fixture.runtime.deleteCopies(
      inventoryID: source,
      scope: .objects([library]),
      recursive: true
    )
    XCTAssertEqual(
      fixture.runtime.document.templateApplications.first?.components.first {
        $0.componentKey == DefaultKhorosComponent.library.rawValue
      }?.active,
      false
    )
    XCTAssertEqual(try fixture.runtime.validateWorldTemplates().count, 1)
    let repaired = try service.apply(
      service.preflight(
        templateID: "default-khoros",
        inventory: fixture.inventory,
        runtime: fixture.runtime
      ),
      inventory: fixture.inventory,
      runtime: fixture.runtime
    )
    XCTAssertEqual(repaired.runtime.deployedObjectIDs.count, 1)
    let after = Dictionary(
      uniqueKeysWithValues: repaired.runtime.application.components.map {
        ($0.componentKey, $0.rootObjectID)
      }
    )
    XCTAssertNotEqual(after[DefaultKhorosComponent.library.rawValue], library)
    XCTAssertEqual(
      repaired.runtime.application.components.first {
        $0.componentKey == DefaultKhorosComponent.library.rawValue
      }?.active,
      true
    )
    for component in DefaultKhorosComponent.allCases where component != .library {
      XCTAssertEqual(after[component.rawValue], before[component.rawValue])
    }
    XCTAssertTrue(try fixture.runtime.validateWorldTemplates().isEmpty)
  }

  func testPreparedProductTransactionRecoversPriorDocuments() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-transaction-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("config.json")
    let second = root.appendingPathComponent("world.json")
    let worldID = InventoryIdentity.make()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("before".utf8).write(to: first)

    var transaction: ProductStateTransaction? = try ProductStateTransaction.begin(
      targets: [first, second],
      affectedWorldIDs: [worldID],
      root: root
    )
    try Data("after".utf8).write(to: first)
    try Data("created".utf8).write(to: second)
    transaction = nil
    XCTAssertNil(transaction)

    try ProductStateTransaction.recoverPending(root: root)
    XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "before")
    XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: root.appendingPathComponent("transactions").path
      )
    )
  }

  func testInitIsNonInteractiveCompleteAndIdempotent() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-init-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let previous = ProcessInfo.processInfo.environment["MIKROKHOROS_HOME"]
    setProductHome(root.appendingPathComponent("home").path)
    defer { setProductHome(previous) }
    let configuration = root.appendingPathComponent("config.json")
    let io = TemplateCommandIO()
    let arguments = [
      "--config", configuration.path,
      "init",
    ]
    let firstStatus = await CommandExecutor.execute(arguments: arguments, io: io)
    XCTAssertEqual(firstStatus, 0)
    XCTAssertEqual(io.readCount, 0)
    let inventory = try InventoryStore(
      limits: .defaults,
      runtimeRegistry: .installedCLI()
    )
    let catalog = try WorldCatalogStore()
    let current = try XCTUnwrap(catalog.currentWorld)
    let worldURL = try WorldStore.url(for: current.id)
    let document = try WorldStore.load(
      from: worldURL,
      maximumBytes: RuntimeLimits.defaults.maximumWorldBytes
    )
    let treasuryAuthority = try TreasuryAuthorityStore(
      url: root.appendingPathComponent("home/treasury-authority.json")
    ).load()
    let runtime = try WorldRuntime(
      document: document,
      inventory: inventory,
      treasuryAuthority: treasuryAuthority
    )
    XCTAssertEqual(document.worldName, "default-khoros")
    XCTAssertEqual(document.agents.count, 1)
    XCTAssertEqual(document.templateApplications.count, 1)
    XCTAssertEqual(runtime.harness.world.container?.items.count, 5)
    let agent = try XCTUnwrap(runtime.harness.activeAgents.first)
    XCTAssertTrue(agent.primaryHeldObject is EyeObject)
    XCTAssertNil(agent.aiProfile)
    XCTAssertEqual(
      try XCTUnwrap(runtime.harness.creditService).balance(for: agent.wallet.hash).minorUnits,
      0
    )
    let messenger = try XCTUnwrap(
      runtime.harness.findObject(document.agents[0].genesis.messenger)
        as? MessengerObject
    )
    let notices = messenger.messages.filter { $0.threadID == "#athena" }
    XCTAssertEqual(notices.count, 1)
    XCTAssertFalse(notices[0].isRead)

    let beforeWorld = try Data(contentsOf: worldURL)
    let beforeCatalog = try Data(contentsOf: catalog.url)
    let beforeInventory = try Data(contentsOf: inventory.url)
    let beforeAgents = try Data(contentsOf: AgentStore.defaultURL)
    let secondStatus = await CommandExecutor.execute(arguments: arguments, io: io)
    XCTAssertEqual(secondStatus, 0)
    XCTAssertEqual(io.readCount, 0)
    XCTAssertEqual(try Data(contentsOf: worldURL), beforeWorld)
    XCTAssertEqual(try Data(contentsOf: catalog.url), beforeCatalog)
    XCTAssertEqual(try Data(contentsOf: inventory.url), beforeInventory)
    XCTAssertEqual(try Data(contentsOf: AgentStore.defaultURL), beforeAgents)
  }

  func testWorldCreationIsBareUnlessTemplateIsExplicitlyApproved() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-world-create-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let previous = ProcessInfo.processInfo.environment["MIKROKHOROS_HOME"]
    setProductHome(root.appendingPathComponent("home").path)
    defer { setProductHome(previous) }
    let io = TemplateCommandIO()

    let rejected = await CommandExecutor.execute(
      arguments: [
        "world", "create", "--template", "default-khoros",
      ],
      io: io
    )
    XCTAssertEqual(rejected, 1)
    XCTAssertEqual(io.readCount, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: WorldCatalogStore.defaultURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: InventoryStore.defaultURL.path))

    let approved = await CommandExecutor.execute(
      arguments: [
        "world", "create", "--template", "default-khoros", "--yes",
      ],
      io: io
    )
    XCTAssertEqual(approved, 0)
    var catalog = try WorldCatalogStore()
    let templatedRecord = try XCTUnwrap(catalog.currentWorld)
    let templatedDocument = try WorldStore.load(from: WorldStore.url(for: templatedRecord.id))
    XCTAssertEqual(templatedDocument.worldName, "default-khoros")
    XCTAssertEqual(templatedDocument.templateApplications.count, 1)
    XCTAssertTrue(templatedDocument.agents.isEmpty)

    let bareStatus = await CommandExecutor.execute(
      arguments: ["world", "create"],
      io: io
    )
    XCTAssertEqual(bareStatus, 0)
    catalog = try WorldCatalogStore()
    let bareRecord = try XCTUnwrap(catalog.currentWorld)
    XCTAssertNotEqual(bareRecord.id, templatedRecord.id)
    let bareDocument = try WorldStore.load(from: WorldStore.url(for: bareRecord.id))
    XCTAssertEqual(bareDocument.worldName, "world")
    XCTAssertTrue(bareDocument.templateApplications.isEmpty)
    XCTAssertTrue(bareDocument.events.isEmpty)
  }

  func testInitPlacementConflictLeavesEveryVisibleStoreUnchanged() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-init-conflict-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let previous = ProcessInfo.processInfo.environment["MIKROKHOROS_HOME"]
    setProductHome(root.appendingPathComponent("home").path)
    defer { setProductHome(previous) }
    let runtime = try testWorldRuntime()
    let blocker = try runtime.createAgent(name: "blocker")
    _ = try runtime.addAgent(blocker, at: DefaultKhorosLayout.library)
    let worldURL = try WorldStore.url(for: runtime.document.worldID)
    try WorldStore.save(runtime.document, to: worldURL)
    let catalog = try WorldCatalogStore()
    _ = try catalog.register(document: runtime.document)
    try catalog.save()
    let before = try Data(contentsOf: worldURL)

    let exitCode = await CommandExecutor.execute(
      arguments: ["init"],
      io: TemplateCommandIO()
    )
    XCTAssertEqual(exitCode, 1)
    XCTAssertEqual(try Data(contentsOf: worldURL), before)
    XCTAssertFalse(FileManager.default.fileExists(atPath: ConfigurationStore.defaultURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: InventoryStore.defaultURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: AgentStore.defaultURL.path))
  }

  private func makeFixture() throws -> (
    root: URL,
    inventory: InventoryStore,
    runtime: WorldRuntime
  ) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-world-template-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    let inventory = try InventoryStore(
      url: root.appendingPathComponent("inventory.json"),
      packageDirectory: root.appendingPathComponent("packages", isDirectory: true),
      credentialStore: FileCredentialStore(
        directory: root.appendingPathComponent("credentials", isDirectory: true)
      ),
      runtimeRegistry: .installedCLI()
    )
    return (root, inventory, try testWorldRuntime(inventory: inventory))
  }
}

private final class TemplateCommandIO: CommandIO, @unchecked Sendable {
  let isInteractive = false
  private let lock = NSLock()
  private var reads = 0

  var readCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return reads
  }

  func writeStandardOutput(_ text: String) {}
  func writeStandardError(_ text: String) {}
  func readLine(prompt: String, hidden: Bool) -> String? {
    lock.lock()
    reads += 1
    lock.unlock()
    return nil
  }
  func readStandardInputToEnd() -> Data { Data() }
}

private func setProductHome(_ value: String?) {
  #if os(Windows)
    _ = _putenv_s("MIKROKHOROS_HOME", value ?? "")
  #else
    if let value {
      setenv("MIKROKHOROS_HOME", value, 1)
    } else {
      unsetenv("MIKROKHOROS_HOME")
    }
  #endif
}
