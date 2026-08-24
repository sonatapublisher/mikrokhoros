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

final class InventoryTests: XCTestCase {
  private struct Fixture {
    let root: URL
    let inventory: InventoryStore
  }

  private func fixture() throws -> Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-inventory-tests-\(UUID().uuidString)",
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
    return Fixture(root: root, inventory: inventory)
  }

  private func package(
    version: String = "1.0.0",
    onInstall: PackageInstallBehavior = .createInventoryObject,
    additional: AdditionalInventoryObjects = .allow
  ) throws -> ObjectPackageManifest {
    let fields = [
      try ManagementField(
        id: "label",
        label: "Label",
        kind: .text,
        required: true,
        defaultValue: .string("revision-a")
      ),
      try ManagementField(
        id: "endpoint",
        label: "Endpoint",
        kind: .url,
        defaultValue: .string("https://example.com")
      ),
      try ManagementField(
        id: "folder",
        label: "Folder",
        kind: .path,
        defaultValue: .string("/tmp")
      ),
      try ManagementField(
        id: "mode",
        label: "Mode",
        kind: .choice,
        defaultValue: .string("normal"),
        choices: ["normal", "quiet"]
      ),
      try ManagementField(
        id: "api_key",
        label: "API key",
        kind: .secret,
        required: true
      ),
    ]
    return try ObjectPackageManifest(
      id: "example.sensor",
      version: version,
      displayName: "Sensor",
      requestedCapabilities: [.network],
      installation: PackageInstallationPolicy(
        onInstall: onInstall,
        additionalInventoryObjects: additional
      ),
      object: DeclarativeObjectDefinition(
        type: "sensor.object",
        name: "sensor",
        state: ["count": .number(0)],
        durability: 100,
        functions: [
          "label": try DeclarativeFunctionDefinition(
            action: DeclarativeAction(kind: .get, key: "label")
          ),
          "emit": try DeclarativeFunctionDefinition(
            action: DeclarativeAction(
              kind: .report,
              key: "status",
              value: .object(["ok": .bool(true)])
            )
          ),
        ]
      ),
      management: ObjectManagementInterface(
        fields: fields,
        actions: [
          try ManagementAction(
            id: "increment",
            parameters: ["amount"],
            mutating: true,
            action: DeclarativeAction(kind: .increment, key: "count", argument: 0)
          )
        ],
        views: [try ManagementView(id: "dashboard", source: "state")],
        reports: [try ObjectReportDefinition(type: "status")]
      )
    )
  }

  private func installedReadyObject(_ fixture: Fixture) throws -> InventoryObjectRecord {
    let result = try fixture.inventory.install(data: JSONEncoder().encode(package()))
    let object = try XCTUnwrap(result.inventoryObject)
    _ = try fixture.inventory.setSecret(
      id: object.id,
      fieldID: "api_key",
      value: Data("top-secret-value".utf8)
    )
    return try fixture.inventory.grant(id: object.id, capabilities: [.network])
  }

  func testPackageSelectedInstallationBehaviorAndUserLevelRegistry() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let created = try fixture.inventory.install(data: JSONEncoder().encode(package()))
    XCTAssertNotNil(created.inventoryObject)
    XCTAssertEqual(fixture.inventory.document.packages.count, 1)
    XCTAssertEqual(fixture.inventory.document.objects.count, 1)

    let registerOnly = try package(
      version: "2.0.0",
      onInstall: .registerOnly,
      additional: .deny
    )
    let registered = try fixture.inventory.install(data: JSONEncoder().encode(registerOnly))
    XCTAssertNil(registered.inventoryObject)
    XCTAssertThrowsError(
      try fixture.inventory.create(packageID: registerOnly.id, version: registerOnly.version)
    )
    let encoded = String(
      decoding: try JSONEncoder().encode(fixture.inventory.document), as: UTF8.self)
    XCTAssertFalse(encoded.contains("worldID"))
    XCTAssertFalse(encoded.contains("world_id"))
  }

  func testInventoryRevisionAndWorldCopyAreIndependent() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let sourceA = try installedReadyObject(fixture)
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    let deployedA = try runtime.deployInventoryObject(sourceA.id, at: Coordinate(x: 5, y: 5))
    let objectA = try XCTUnwrap(
      runtime.harness.findObject(deployedA.snapshot.objectID) as? DeclarativeObject
    )
    XCTAssertEqual(objectA.configuration["label"], .string("revision-a"))
    XCTAssertEqual(objectA.lineage?.inventoryRevision, sourceA.revision)

    let sourceB = try fixture.inventory.configure(
      id: sourceA.id,
      setting: ["label": .string("revision-b")]
    )
    _ = try fixture.inventory.revoke(id: sourceA.id, capabilities: [.network])
    XCTAssertEqual(objectA.configuration["label"], .string("revision-a"))
    XCTAssertEqual(objectA.capturedCapabilities, [.network])
    _ = try fixture.inventory.grant(id: sourceA.id, capabilities: [.network])
    let deployedB = try runtime.deployInventoryObject(sourceA.id, at: Coordinate(x: 6, y: 5))
    let objectB = try XCTUnwrap(
      runtime.harness.findObject(deployedB.snapshot.objectID) as? DeclarativeObject
    )
    XCTAssertEqual(objectB.configuration["label"], .string("revision-b"))
    XCTAssertGreaterThan(objectB.lineage!.inventoryRevision, sourceB.revision)
    XCTAssertNotEqual(objectA.hash, objectB.hash)
    XCTAssertNotEqual(objectA.lineage?.deploymentID, objectB.lineage?.deploymentID)
  }

  func testHiddenPackageContentRemainsAvailableToExistingInventoryObjects() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try installedReadyObject(fixture)
    try fixture.inventory.removePackage(id: source.packageID, version: source.packageVersion)
    XCTAssertTrue(fixture.inventory.installedPackages.isEmpty)

    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    let deployment = try runtime.deployInventoryObject(
      source.id,
      at: Coordinate(x: 5, y: 5)
    )
    XCTAssertNotNil(runtime.harness.findObject(deployment.snapshot.objectID))
  }

  func testConfigurationMutationValidatesCompleteResultBeforeCommit() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try installedReadyObject(fixture)
    XCTAssertThrowsError(
      try fixture.inventory.configure(
        id: source.id,
        setting: ["label": .string("candidate"), "mode": .string("undeclared")]
      )
    )
    let unchanged = try fixture.inventory.resolve(source.id)
    XCTAssertEqual(unchanged.revision, source.revision)
    XCTAssertEqual(unchanged.configuration, source.configuration)
  }

  func testConfigurationMutationReplacesExistingPersistentInventory() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try installedReadyObject(fixture)
    let configured = try fixture.inventory.configure(
      id: source.id,
      setting: ["label": .string("revision-b")]
    )

    let reloaded = try InventoryStore(
      url: fixture.root.appendingPathComponent("inventory.json"),
      packageDirectory: fixture.root.appendingPathComponent("packages", isDirectory: true),
      credentialStore: FileCredentialStore(
        directory: fixture.root.appendingPathComponent("credentials", isDirectory: true)
      )
    )
    let persisted = try reloaded.resolve(source.id)
    XCTAssertEqual(persisted.revision, configured.revision)
    XCTAssertEqual(persisted.configuration["label"], .string("revision-b"))
  }

  func testDeploymentDestinationsAndDeterministicAdaptation() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try installedReadyObject(fixture)
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    try applyDefaultKhoros(to: runtime, inventory: fixture.inventory)
    let occupied = Coordinate(x: 9, y: 9)
    _ = try runtime.deployInventoryObject(source.id, at: occupied)
    XCTAssertThrowsError(try runtime.deployInventoryObject(source.id, at: occupied))
    let adapted = try runtime.deployInventoryObject(
      source.id,
      at: occupied,
      autoAdapt: true
    )
    XCTAssertEqual(adapted.actualCoordinate, Coordinate(x: 9, y: 8))
    XCTAssertTrue(adapted.adapted)

    let marketplaceID = try runtime.defaultKhorosFacility(.marketplace).hash
    let nested = try runtime.deployInventoryObject(
      source.id,
      to: marketplaceID,
      at: Coordinate(x: 10, y: 10)
    )
    XCTAssertTrue(
      runtime.harness.findObject(nested.snapshot.objectID)?.parentSpace?.owner
        === runtime.harness.findObject(marketplaceID)
    )

    let agent = try runtime.createAgent(name: "carrier")
    _ = try runtime.addAgent(agent, at: Coordinate(x: 20, y: 20))
    let eye = agent.primaryHeldObject
    let carried = try runtime.deployInventoryObject(source.id, to: agent.hash)
    XCTAssertTrue(
      runtime.harness.findObject(carried.snapshot.objectID)?.parentSpace?.owner === agent.backpack
    )
    XCTAssertTrue(agent.primaryHeldObject === eye)
    XCTAssertTrue(eye is EyeObject)
  }

  func testListenersDeliverOnlyDeclaredReportsForExactCopy() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try installedReadyObject(fixture)
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    let first = try runtime.deployInventoryObject(source.id, at: Coordinate(x: 5, y: 5))
    let second = try runtime.deployInventoryObject(source.id, at: Coordinate(x: 6, y: 5))
    let firstObject = try XCTUnwrap(runtime.harness.findObject(first.snapshot.objectID))
    let secondObject = try XCTUnwrap(runtime.harness.findObject(second.snapshot.objectID))
    let agent = try runtime.createAgent(name: "agent")
    _ = try runtime.addAgent(agent, at: Coordinate(x: 20, y: 20))

    _ = try firstObject.invoke("emit", arguments: [], harness: runtime.harness, agent: agent)
    XCTAssertTrue(runtime.reports.isEmpty)
    try runtime.setListener(true, objectQuery: firstObject.hash)
    try firstObject.registerAgentFunction(
      name: "sdk-report",
      summary: "Emit through the constrained package context."
    ) { context, _ in
      try context.reports?.emit(
        type: "status",
        title: "SDK report",
        body: "structured data",
        payload: .object(["ok": .bool(true)])
      )
      return "reported"
    }
    _ = try firstObject.invoke("emit", arguments: [], harness: runtime.harness, agent: agent)
    _ = try firstObject.invoke("sdk-report", arguments: [], harness: runtime.harness, agent: agent)
    _ = try secondObject.invoke("emit", arguments: [], harness: runtime.harness, agent: agent)
    XCTAssertEqual(runtime.reports.count, 2)
    XCTAssertEqual(runtime.reports[0].objectID, firstObject.hash)
    XCTAssertEqual(runtime.reports[0].inventoryObjectID, source.id)
    XCTAssertEqual(runtime.reports[1].title, "SDK report")
    try runtime.setListener(false, objectQuery: firstObject.hash)
    _ = try firstObject.invoke("emit", arguments: [], harness: runtime.harness, agent: agent)
    XCTAssertEqual(runtime.reports.count, 2)
  }

  func testDeploymentDeletionAndReportsReplayWithoutCurrentInventoryState() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try installedReadyObject(fixture)
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    let first = try runtime.deployInventoryObject(source.id, at: Coordinate(x: 5, y: 5))
    let second = try runtime.deployInventoryObject(source.id, at: Coordinate(x: 6, y: 5))
    try runtime.setListener(true, objectQuery: second.snapshot.objectID)
    _ = try fixture.inventory.delete(id: source.id)
    let preview = try runtime.deleteCopies(
      inventoryID: source.id,
      scope: .objects([first.snapshot.objectID])
    )
    XCTAssertEqual(preview.affectedObjectIDs, [first.snapshot.objectID])

    let restored = try testWorldRuntime(document: runtime.document, inventory: fixture.inventory)
    XCTAssertNil(restored.harness.findObject(first.snapshot.objectID))
    XCTAssertNotNil(restored.harness.findObject(second.snapshot.objectID))
    XCTAssertTrue(restored.listeners.contains(second.snapshot.objectID))
    XCTAssertEqual(
      restored.harness.findObject(second.snapshot.objectID)?.lineage,
      second.snapshot.lineage
    )
  }

  func testRestockingUsesCurrentInventoryRevisionAndPreservesPurchasedCopy() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try installedReadyObject(fixture)
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    try applyDefaultKhoros(to: runtime, inventory: fixture.inventory)
    let merchant = try XCTUnwrap(
      try runtime.defaultKhorosFacility(.marketplace).container?.object(at: .origin)
        as? MerchantObject
    )
    let rule = try runtime.createRestockRule(
      inventoryID: source.id,
      merchantQuery: merchant.hash,
      price: 2,
      autoAdapt: true
    )
    let initialID = try XCTUnwrap(rule.createdObjectIDs.first)
    let initial = try XCTUnwrap(runtime.harness.findObject(initialID))
    let initialRevision = try XCTUnwrap(initial.lineage?.inventoryRevision)
    _ = try fixture.inventory.configure(
      id: source.id,
      setting: ["label": .string("latest")]
    )

    let manual = try runtime.runRestockRule(rule.id)
    let manualID = manual.createdObjectIDs.last!
    XCTAssertGreaterThan(
      try XCTUnwrap(runtime.harness.findObject(manualID)?.lineage?.inventoryRevision),
      initialRevision
    )
    let buyer = try runtime.createAgent(name: "buyer")
    _ = try runtime.addAgent(buyer, at: Coordinate(x: 20, y: 20))
    let creditService = try XCTUnwrap(runtime.harness.creditService)
    try creditService.deposit(
      walletID: buyer.wallet.hash,
      amount: try CreditAmount.parse("10"),
      actor: .system
    )
    let purchasedLocation = initial.coordinate
    let purchase = try runtime.harness.purchase(
      itemSelector: initialID,
      walletID: buyer.wallet.hash,
      from: merchant,
      for: buyer
    )
    XCTAssertEqual(purchase.item.hash, initialID)
    XCTAssertEqual(purchase.item.coordinate, purchasedLocation)
    XCTAssertEqual(purchase.item.lockInfo?.mode, .allowOnly)
    let automatic = try XCTUnwrap(purchase.restocked)
    XCTAssertNotEqual(automatic.hash, initialID)
    XCTAssertEqual(
      automatic.lineage?.inventoryRevision,
      try fixture.inventory.resolve(source.id).revision
    )
  }

  func testSecretsRemainWriteOnlyAcrossInventoryAndWorldPersistence() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try installedReadyObject(fixture)
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    _ = try runtime.deployInventoryObject(source.id, at: Coordinate(x: 5, y: 5))
    let inventoryText = String(
      decoding: try JSONEncoder().encode(fixture.inventory.document),
      as: UTF8.self
    )
    let worldText = String(decoding: try JSONEncoder().encode(runtime.document), as: UTF8.self)
    XCTAssertFalse(inventoryText.contains("top-secret-value"))
    XCTAssertFalse(worldText.contains("top-secret-value"))
    let administrativeText = String(
      decoding: try JSONEncoder().encode(runtime.harness.administrativeWorldSnapshot()),
      as: UTF8.self
    )
    XCTAssertFalse(administrativeText.contains("top-secret-value"))
  }

  func testOwnedObjectGraphAndConcreteIDsReplayFromDeploymentSnapshot() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let manifest = try ObjectPackageManifest(
      id: "example.graph",
      version: "1.0.0",
      displayName: "Graph",
      installation: PackageInstallationPolicy(onInstall: .createInventoryObject),
      object: DeclarativeObjectDefinition(
        type: "cabinet.object",
        name: "cabinet",
        container: true
      ),
      ownedObjects: [
        try DeclarativeOwnedObjectDefinition(
          id: "drawer",
          coordinate: Coordinate(x: 1, y: 0),
          object: DeclarativeObjectDefinition(
            type: "drawer.object",
            name: "drawer",
            container: true
          )
        ),
        try DeclarativeOwnedObjectDefinition(
          id: "note",
          parent: "drawer",
          coordinate: Coordinate(x: -2, y: 3),
          object: DeclarativeObjectDefinition(type: "note.object", name: "note")
        ),
      ]
    )
    let source = try XCTUnwrap(
      fixture.inventory.install(data: JSONEncoder().encode(manifest)).inventoryObject
    )
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    let deployment = try runtime.deployInventoryObject(
      source.id,
      at: Coordinate(x: 8, y: 8)
    )
    XCTAssertEqual(deployment.snapshot.ownedObjects.count, 2)
    XCTAssertEqual(Set(deployment.snapshot.ownedObjects.map(\.objectID)).count, 2)
    let root = try XCTUnwrap(runtime.harness.findObject(deployment.snapshot.objectID))
    let drawer = try XCTUnwrap(root.container?.object(at: Coordinate(x: 1, y: 0)))
    let note = try XCTUnwrap(drawer.container?.object(at: Coordinate(x: -2, y: 3)))
    XCTAssertEqual(note.lineage, deployment.snapshot.lineage)

    let restored = try testWorldRuntime(document: runtime.document, inventory: fixture.inventory)
    XCTAssertEqual(restored.harness.findObject(note.hash)?.hash, note.hash)
    XCTAssertEqual(restored.harness.findObject(note.hash)?.lineage, note.lineage)
    XCTAssertThrowsError(
      try restored.previewCopyDeletion(
        inventoryID: source.id,
        scope: .objects([root.hash])
      )
    )
    let preview = try restored.previewCopyDeletion(
      inventoryID: source.id,
      scope: .objects([root.hash]),
      recursive: true
    )
    XCTAssertEqual(Set(preview.affectedObjectIDs), [root.hash, drawer.hash, note.hash])
  }

  func testCredentialVersionsRemainForCopiesThenCollectAfterDeletion() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try installedReadyObject(fixture)
    let originalHandle = try XCTUnwrap(source.credentialHandles["api_key"])
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    let deployment = try runtime.deployInventoryObject(source.id, at: Coordinate(x: 5, y: 5))
    var references = runtime.activeInventoryArtifactReferences
    try fixture.inventory.synchronizeWorldReferences(
      worldID: runtime.harness.world.hash,
      credentialHandles: references.credentialHandles,
      packageHashes: references.packageHashes
    )
    _ = try fixture.inventory.setSecret(
      id: source.id,
      fieldID: "api_key",
      value: Data("replacement".utf8)
    )
    XCTAssertTrue(fixture.inventory.credentialStore.contains(handle: originalHandle))

    _ = try runtime.deleteCopies(
      inventoryID: source.id,
      scope: .objects([deployment.snapshot.objectID])
    )
    references = runtime.activeInventoryArtifactReferences
    try fixture.inventory.synchronizeWorldReferences(
      worldID: runtime.harness.world.hash,
      credentialHandles: references.credentialHandles,
      packageHashes: references.packageHashes
    )
    XCTAssertFalse(fixture.inventory.credentialStore.contains(handle: originalHandle))
  }

  func testCredentialCollectionCanBeDeferredUntilWorldDeletionCommits() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try installedReadyObject(fixture)
    let originalHandle = try XCTUnwrap(source.credentialHandles["api_key"])
    let worldID = InventoryIdentity.make()
    try fixture.inventory.synchronizeWorldReferences(
      worldID: worldID,
      credentialHandles: [originalHandle],
      packageHashes: []
    )
    _ = try fixture.inventory.setSecret(
      id: source.id,
      fieldID: "api_key",
      value: Data("replacement".utf8)
    )

    fixture.inventory.removeWorldReferences(for: worldID)
    try fixture.inventory.save(garbageCollectCredentials: false)
    XCTAssertTrue(fixture.inventory.credentialStore.contains(handle: originalHandle))

    fixture.inventory.garbageCollectUnreferencedCredentials()
    XCTAssertFalse(fixture.inventory.credentialStore.contains(handle: originalHandle))
  }

  func testRestockPriceChangesApplyOnlyToFutureStockAcrossReplay() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try installedReadyObject(fixture)
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    try applyDefaultKhoros(to: runtime, inventory: fixture.inventory)
    let merchant = try XCTUnwrap(
      try runtime.defaultKhorosFacility(.marketplace).container?.object(at: .origin)
        as? MerchantObject
    )
    let rule = try runtime.createRestockRule(
      inventoryID: source.id,
      merchantQuery: merchant.hash,
      price: 2,
      autoAdapt: true
    )
    let firstID = try XCTUnwrap(rule.createdObjectIDs.first)
    _ = try runtime.updateRestockRule(rule.id, price: 7)
    let updated = try runtime.runRestockRule(rule.id)
    let secondID = try XCTUnwrap(updated.createdObjectIDs.last)
    XCTAssertEqual(merchant.prices[firstID], 2)
    XCTAssertEqual(merchant.prices[secondID], 7)

    let restored = try testWorldRuntime(document: runtime.document, inventory: fixture.inventory)
    let restoredMerchant = try XCTUnwrap(
      try restored.defaultKhorosFacility(.marketplace).container?.object(at: .origin)
        as? MerchantObject
    )
    XCTAssertEqual(restoredMerchant.prices[firstID], 2)
    XCTAssertEqual(restoredMerchant.prices[secondID], 7)
  }

  func testRestockPricesUseCanonicalPositiveCreditBounds() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try installedReadyObject(fixture)
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    try applyDefaultKhoros(to: runtime, inventory: fixture.inventory)
    let merchant = try XCTUnwrap(
      try runtime.defaultKhorosFacility(.marketplace).container?.object(at: .origin)
        as? MerchantObject
    )

    XCTAssertThrowsError(
      try runtime.createRestockRule(
        inventoryID: source.id,
        merchantQuery: merchant.hash,
        price: 0
      )
    )
    XCTAssertThrowsError(
      try runtime.createRestockRule(
        inventoryID: source.id,
        merchantQuery: merchant.hash,
        price: Decimal(string: "1.001")!
      )
    )

    let rule = try runtime.createRestockRule(
      inventoryID: source.id,
      merchantQuery: merchant.hash,
      price: Decimal(string: "0.01")!
    )
    let maximum = Decimal(string: "92233720368547758.07")!
    let updated = try runtime.updateRestockRule(rule.id, price: maximum)
    XCTAssertEqual(updated.price, maximum)
    XCTAssertThrowsError(try runtime.updateRestockRule(rule.id, price: 0))
    XCTAssertThrowsError(
      try runtime.updateRestockRule(rule.id, price: Decimal(string: "2.345")!)
    )

    let restored = try testWorldRuntime(document: runtime.document, inventory: fixture.inventory)
    XCTAssertEqual(try restored.resolveRestockRule(rule.id).price, maximum)
  }

  func testPurchaseEnvelopeReloadsOnceAndLaterPickupUsesSelectedSlot() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let purchase = try persistedPurchase(in: fixture)

    XCTAssertEqual(
      try purchase.runtime.creditService.balance(for: purchase.walletID).minorUnits,
      100
    )
    let purchaseEnvelope = try XCTUnwrap(
      purchase.runtime.document.operations.first(where: { !$0.purchases.isEmpty })
    )
    XCTAssertEqual(purchaseEnvelope.purchases.count, 1)
    XCTAssertEqual(purchaseEnvelope.receipts.count, 1)
    XCTAssertEqual(purchaseEnvelope.unread.count, 1)
    XCTAssertEqual(purchaseEnvelope.purchases[0].replacement?.objectID, purchase.replacementID)

    let restored = try testWorldRuntime(
      document: purchase.runtime.document,
      inventory: fixture.inventory
    )
    XCTAssertEqual(try restored.creditService.balance(for: purchase.walletID).minorUnits, 100)
    let restoredItem = try XCTUnwrap(restored.harness.findObject(purchase.itemID))
    XCTAssertEqual(restoredItem.lockInfo?.allowedAgentIDs, [purchase.buyerID])
    XCTAssertEqual(restoredItem.lockInfo?.clearsOnPickup, true)

    let buyer = try restored.harness.resolveAgent(purchase.buyerID)
    let pickupTurn = try restored.run("move east\npickup", for: buyer)
    XCTAssertTrue(pickupTurn.results.allSatisfy { $0.status == .success })
    XCTAssertEqual(buyer.primaryHoldingNumber, try HoldingNumber(2))
    XCTAssertEqual(buyer.primaryHeldObject?.hash, purchase.itemID)
    XCTAssertNil(restoredItem.lockInfo)

    let pickedUp = try testWorldRuntime(
      document: restored.document,
      inventory: fixture.inventory
    )
    let pickedUpBuyer = try pickedUp.harness.resolveAgent(purchase.buyerID)
    XCTAssertEqual(pickedUpBuyer.primaryHoldingNumber, try HoldingNumber(2))
    XCTAssertEqual(pickedUpBuyer.primaryHeldObject?.hash, purchase.itemID)
    XCTAssertEqual(try pickedUp.creditService.balance(for: purchase.walletID).minorUnits, 100)
  }

  func testMaximumPurchaseAmountPersistsBoundedNotificationAndRestockAtomically() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try installedReadyObject(fixture)
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    try applyDefaultKhoros(to: runtime, inventory: fixture.inventory)
    let merchant = try XCTUnwrap(
      try runtime.defaultKhorosFacility(.marketplace).container?.object(at: .origin)
        as? MerchantObject
    )
    let maximum = Decimal(string: "92233720368547758.07")!
    let rule = try runtime.createRestockRule(
      inventoryID: source.id,
      merchantQuery: merchant.hash,
      price: maximum,
      at: Coordinate(x: 1, y: 0),
      autoAdapt: true
    )
    let itemID = try XCTUnwrap(rule.createdObjectIDs.first)
    let buyer = try runtime.createAgent(name: "maximum-buyer")
    _ = try runtime.addAgent(buyer, at: DefaultKhorosLayout.marketplace)
    try runtime.deposit(try CreditAmount.parse("92233720368547758.07"), to: buyer.wallet)

    let turn = try runtime.run(
      "holding select 2\ncontainer in\nobject (buy (\(itemID)) (\(buyer.wallet.hash)))",
      for: buyer
    )
    XCTAssertTrue(turn.results.allSatisfy { $0.status == .success })

    let envelope = try XCTUnwrap(
      runtime.document.operations.first(where: { !$0.purchases.isEmpty })
    )
    let purchase = try XCTUnwrap(envelope.purchases.first)
    XCTAssertEqual(purchase.nominalAmount.minorUnits, Int64.max)
    XCTAssertEqual(purchase.appliedAmount.minorUnits, Int64.max)
    XCTAssertEqual(envelope.receipts.count, 1)
    XCTAssertEqual(envelope.unread.count, 1)
    XCTAssertTrue(
      envelope.unread[0].body.contains(
        "wallet_id: \(PromptSafety.yamlScalar(buyer.wallet.hash, limit: 128))"
      )
    )
    XCTAssertTrue(envelope.unread[0].body.contains("nominal_amount:"))
    XCTAssertTrue(envelope.unread[0].body.contains("applied_amount:"))
    XCTAssertLessThanOrEqual(
      envelope.unread[0].body.count,
      AgentBroadcastEvent.maximumBodyCharacters
    )
    let replacementID = try XCTUnwrap(purchase.replacement?.objectID)
    XCTAssertEqual(
      try runtime.creditService.balance(for: buyer.wallet.hash).minorUnits,
      0
    )

    let worldURL = fixture.root.appendingPathComponent("world.json")
    try WorldStore.save(runtime.document, to: worldURL)
    let restored = try testWorldRuntime(
      document: WorldStore.load(from: worldURL),
      inventory: fixture.inventory
    )
    XCTAssertEqual(
      try restored.creditService.balance(for: buyer.wallet.hash).minorUnits,
      0
    )
    XCTAssertNotNil(restored.harness.findObject(replacementID))
    XCTAssertEqual(
      restored.harness.findObject(itemID)?.lockInfo?.allowedAgentIDs,
      [buyer.hash]
    )
    let restoredWallet = try XCTUnwrap(
      restored.harness.findObject(buyer.wallet.hash) as? WalletObject
    )
    XCTAssertEqual(
      restoredWallet.unreadEvent(eventID: envelope.unread[0].eventID),
      envelope.unread[0].event
    )
  }

  func testHandedOffWalletBearerCanPurchaseAndIssuerCannot() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try installedReadyObject(fixture)
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    try applyDefaultKhoros(to: runtime, inventory: fixture.inventory)
    let marketplace = try runtime.defaultKhorosFacility(.marketplace)
    let merchant = try XCTUnwrap(
      marketplace.container?.object(at: .origin) as? MerchantObject
    )
    let rule = try runtime.createRestockRule(
      inventoryID: source.id,
      merchantQuery: merchant.hash,
      price: 2,
      at: Coordinate(x: 1, y: 0),
      autoAdapt: true
    )
    let itemID = try XCTUnwrap(rule.createdObjectIDs.first)
    let issuer = try runtime.createAgent(name: "issuer")
    _ = try runtime.addAgent(issuer, at: Coordinate(x: 10, y: 10))
    let buyer = try runtime.createAgent(name: "buyer")
    _ = try runtime.addAgent(buyer, at: DefaultKhorosLayout.marketplace)
    try runtime.deposit(try CreditAmount.parse("3"), to: issuer.wallet)
    _ = try runtime.moveWorldObject(
      objectID: issuer.wallet.hash,
      to: buyer.backpack.hash,
      at: Coordinate(x: 10, y: 0)
    )

    XCTAssertEqual(
      runtime.creditService.registration(for: issuer.wallet.hash)?.agentID,
      issuer.hash
    )
    XCTAssertEqual(runtime.creditService.custodyOwner(for: issuer.wallet.hash), buyer.hash)
    XCTAssertEqual(try runtime.harness.currentOwner(of: issuer.wallet)?.agentID, buyer.hash)
    XCTAssertThrowsError(
      try runtime.harness.purchase(
        itemSelector: itemID,
        walletID: issuer.wallet.hash,
        from: merchant,
        for: issuer
      )
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "wallet.owner_denied")
    }

    let turn = try runtime.run(
      "holding select 2\ncontainer in\nobject (buy (\(itemID)) (\(issuer.wallet.hash)))",
      for: buyer
    )
    XCTAssertTrue(turn.results.allSatisfy { $0.status == .success })
    let envelope = try XCTUnwrap(
      runtime.document.operations.first(where: { !$0.purchases.isEmpty })
    )
    XCTAssertEqual(envelope.purchases[0].payerWalletID, issuer.wallet.hash)
    XCTAssertEqual(envelope.purchases[0].buyerAgentID, buyer.hash)
    XCTAssertEqual(envelope.unread.first?.agentID, buyer.hash)
    let replacementID = try XCTUnwrap(envelope.purchases[0].replacement?.objectID)

    let restored = try testWorldRuntime(
      document: runtime.document,
      inventory: fixture.inventory
    )
    let restoredIssuer = try restored.harness.resolveAgent(issuer.hash)
    let restoredBuyer = try restored.harness.resolveAgent(buyer.hash)
    let restoredWallet = try XCTUnwrap(
      restored.harness.findObject(issuer.wallet.hash) as? WalletObject
    )
    XCTAssertEqual(
      restored.creditService.registration(for: restoredWallet.hash)?.agentID,
      issuer.hash
    )
    XCTAssertEqual(restored.creditService.custodyOwner(for: restoredWallet.hash), buyer.hash)
    XCTAssertEqual(try restored.harness.currentOwner(of: restoredWallet)?.agentID, buyer.hash)
    XCTAssertNoThrow(try restored.harness.requireWalletOwner(restoredBuyer, restoredWallet))
    XCTAssertEqual(try restored.creditService.balance(for: restoredWallet.hash).minorUnits, 100)
    XCTAssertEqual(
      restored.harness.findObject(itemID)?.lockInfo?.allowedAgentIDs,
      [buyer.hash]
    )
    XCTAssertEqual(
      restoredWallet.unreadEvent(eventID: envelope.purchases[0].unreadEventID),
      envelope.unread[0].event
    )
    let restoredMerchant = try XCTUnwrap(
      try restored.defaultKhorosFacility(.marketplace).container?.object(at: .origin)
        as? MerchantObject
    )
    XCTAssertThrowsError(
      try restored.harness.purchase(
        itemSelector: replacementID,
        walletID: restoredWallet.hash,
        from: restoredMerchant,
        for: restoredIssuer
      )
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "wallet.owner_denied")
    }
    XCTAssertEqual(try restored.creditService.balance(for: restoredWallet.hash).minorUnits, 100)
  }

  func testPersistentRuntimeRejectsNonInventoryAutoRestockBeforeMutation() throws {
    let runtime = try testWorldRuntime()
    let buyer = try runtime.createAgent(name: "buyer")
    _ = try runtime.addAgent(buyer)
    try runtime.deposit(try CreditAmount.parse("5"), to: buyer.wallet)
    try runtime.harness.stowHeldObject(for: buyer)
    let item = try AppleObject(durability: 3)
    let shop = try createShop(
      name: "Transient Shop",
      inventory: [PricedObject(item, price: 2)],
      autoRestock: true
    )
    try runtime.harness.place(shop.shop)
    _ = try runtime.harness.enterContainer(for: buyer)
    let balanceBefore = try runtime.creditService.balance(for: buyer.wallet.hash)
    let lockBefore = item.lockInfo

    let turn = try runtime.run(
      "object (buy (\(item.hash)) (\(buyer.wallet.hash)))",
      for: buyer
    )
    XCTAssertEqual(turn.status, .error)
    XCTAssertEqual(turn.results.first?.error?.code, "purchase.restock_not_durable")
    XCTAssertEqual(try runtime.creditService.balance(for: buyer.wallet.hash), balanceBefore)
    XCTAssertEqual(item.lockInfo, lockBefore)
    XCTAssertEqual(shop.merchant.prices.keys.sorted(), [item.hash])
  }

  func testPurchaseEnvelopeRejectsMissingPiecesAndRequiresUnsignedBuyAction() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let purchase = try persistedPurchase(in: fixture)
    let document = purchase.runtime.document
    let envelope = try XCTUnwrap(document.operations.first(where: { !$0.purchases.isEmpty }))

    let malformed = [
      copy(envelope, signedCreditRecords: []),
      copy(envelope, purchases: []),
      copy(envelope, receipts: []),
      copy(envelope, unread: []),
    ]
    for invalidEnvelope in malformed {
      XCTAssertThrowsError(
        try testWorldRuntime(
          document: replacing(envelope, with: invalidEnvelope, in: document),
          inventory: fixture.inventory
        )
      )
    }

    var missingDeployment = document
    missingDeployment.events.removeAll { event in
      guard case .objectDeployed(let deployment) = event else { return false }
      return deployment.snapshot.objectID == purchase.replacementID
    }
    XCTAssertThrowsError(
      try testWorldRuntime(document: missingDeployment, inventory: fixture.inventory)
    )

    var missingRestockCommit = document
    missingRestockCommit.events.removeAll { event in
      guard case .restockRuleUpdated(let rule) = event else { return false }
      return rule.createdObjectIDs.contains(purchase.replacementID)
    }
    XCTAssertThrowsError(
      try testWorldRuntime(document: missingRestockCommit, inventory: fixture.inventory)
    )

    var withoutActions = document
    withoutActions.events.removeAll { event in
      guard case .actions(let operationID, _, _, _, _, _, _) = event else { return false }
      return operationID == envelope.operationID
    }
    XCTAssertThrowsError(
      try testWorldRuntime(document: withoutActions, inventory: fixture.inventory)
    )

    var replacedBuy = document
    replacedBuy.events = replacedBuy.events.map { event in
      guard
        case .actions(
          let operationID,
          let agentID,
          let commands,
          let actionIndexes,
          let drainedBroadcasts,
          let generatedIDs,
          let generatedDates
        ) = event, operationID == envelope.operationID,
        let commandOffset = actionIndexes.firstIndex(of: envelope.actionIndex)
      else {
        return event
      }
      var rewrittenCommands = commands
      rewrittenCommands[commandOffset] = "holding select 1"
      return .actions(
        operationID: operationID,
        agentID: agentID,
        commands: rewrittenCommands,
        actionIndexes: actionIndexes,
        drainedBroadcasts: drainedBroadcasts,
        generatedIDs: generatedIDs,
        generatedDates: generatedDates
      )
    }
    XCTAssertThrowsError(
      try testWorldRuntime(document: replacedBuy, inventory: fixture.inventory)
    )

    var duplicateOperation = document
    duplicateOperation.operations.append(envelope)
    XCTAssertThrowsError(
      try testWorldRuntime(document: duplicateOperation, inventory: fixture.inventory)
    )

    var duplicateEvent = document
    duplicateEvent.events.append(.operationEnvelope(envelope))
    XCTAssertThrowsError(
      try testWorldRuntime(document: duplicateEvent, inventory: fixture.inventory)
    )

    var duplicate = document
    duplicate.operations.append(envelope)
    duplicate.events.append(.operationEnvelope(envelope))
    XCTAssertThrowsError(
      try testWorldRuntime(document: duplicate, inventory: fixture.inventory)
    )
  }

  private func persistedPurchase(in fixture: Fixture) throws -> (
    runtime: WorldRuntime,
    buyerID: String,
    walletID: String,
    itemID: String,
    replacementID: String
  ) {
    let source = try installedReadyObject(fixture)
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    try applyDefaultKhoros(to: runtime, inventory: fixture.inventory)
    let marketplace = try runtime.defaultKhorosFacility(.marketplace)
    let merchant = try XCTUnwrap(
      marketplace.container?.object(at: .origin) as? MerchantObject
    )
    let rule = try runtime.createRestockRule(
      inventoryID: source.id,
      merchantQuery: merchant.hash,
      price: 2,
      at: Coordinate(x: 1, y: 0),
      autoAdapt: true
    )
    let itemID = try XCTUnwrap(rule.createdObjectIDs.first)
    let buyer = try runtime.createAgent(name: "buyer")
    _ = try runtime.addAgent(buyer, at: DefaultKhorosLayout.marketplace)
    try runtime.deposit(try CreditAmount.parse("3"), to: buyer.wallet)
    let turn = try runtime.run(
      "holding select 2\ncontainer in\nobject (buy (\(itemID)) (\(buyer.wallet.hash)))",
      for: buyer
    )
    XCTAssertTrue(turn.results.allSatisfy { $0.status == .success })
    let purchaseEnvelope = try XCTUnwrap(
      runtime.document.operations.first(where: { !$0.purchases.isEmpty })
    )
    let replacementID = try XCTUnwrap(purchaseEnvelope.purchases.first?.replacement?.objectID)
    return (runtime, buyer.hash, buyer.wallet.hash, itemID, replacementID)
  }

  private func copy(
    _ envelope: WorldOperationEnvelope,
    signedCreditRecords: [SignedCreditRecord]? = nil,
    purchases: [WorldPurchaseMutation]? = nil,
    receipts: [WorldOperationReceipt]? = nil,
    unread: [WorldUnreadRecord]? = nil
  ) -> WorldOperationEnvelope {
    WorldOperationEnvelope(
      operationID: envelope.operationID,
      worldID: envelope.worldID,
      actor: envelope.actor,
      timestamp: envelope.timestamp,
      actionIndex: envelope.actionIndex,
      signedCreditRecords: signedCreditRecords ?? envelope.signedCreditRecords,
      purchases: purchases ?? envelope.purchases,
      objectMutations: envelope.objectMutations,
      receipts: receipts ?? envelope.receipts,
      unread: unread ?? envelope.unread,
      acknowledgements: envelope.acknowledgements,
      activity: envelope.activity,
      idempotencyKey: envelope.idempotencyKey
    )
  }

  private func replacing(
    _ oldEnvelope: WorldOperationEnvelope,
    with newEnvelope: WorldOperationEnvelope,
    in document: WorldDocument
  ) -> WorldDocument {
    var result = document
    result.operations = result.operations.map { $0 == oldEnvelope ? newEnvelope : $0 }
    result.events = result.events.map { event in
      guard case .operationEnvelope(let envelope) = event, envelope == oldEnvelope else {
        return event
      }
      return .operationEnvelope(newEnvelope)
    }
    return result
  }

  func testInventoryFoldersOrganizeSourcesWithoutChangingTheirRevision() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try installedReadyObject(fixture)
    let projects = try fixture.inventory.createFolder(path: "projects")
    let worldA = try fixture.inventory.createFolder(path: "projects/world-a")
    let originalRevision = source.revision

    let moved = try fixture.inventory.moveInventoryObject(source.id, toFolder: worldA.id)
    XCTAssertEqual(moved.folderID, worldA.id)
    XCTAssertEqual(moved.revision, originalRevision)
    XCTAssertEqual(fixture.inventory.folderPath(for: worldA.id), "projects/world-a")
    XCTAssertEqual(
      fixture.inventory.inventoryObjects(inFolder: projects.id, recursive: true).map(\.id),
      [source.id]
    )

    let renamed = try fixture.inventory.renameFolder(worldA.id, to: "primary")
    XCTAssertEqual(fixture.inventory.folderPath(for: renamed.id), "projects/primary")
    XCTAssertThrowsError(try fixture.inventory.deleteFolder(projects.id)) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "inventory.folder_not_empty")
    }
    _ = try fixture.inventory.moveInventoryObject(source.id, toFolder: "/")
    _ = try fixture.inventory.deleteFolder(renamed.id)
    _ = try fixture.inventory.deleteFolder(projects.id)
    XCTAssertEqual(
      fixture.inventory.allInventoryFolders().map(\.id), [InventoryFolderIdentity.rootID])
  }

  func testInventoryFolderRejectsCyclesCollisionsAndRootMutation() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let a = try fixture.inventory.createFolder(path: "a")
    let b = try fixture.inventory.createFolder(path: "a/b")
    _ = try fixture.inventory.createFolder(path: "other")
    XCTAssertThrowsError(try fixture.inventory.moveFolder(a.id, to: b.id)) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "inventory.folder_cycle")
    }
    XCTAssertThrowsError(try fixture.inventory.renameFolder("/", to: "root")) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "inventory.folder_root_immutable")
    }
    _ = try fixture.inventory.createFolder(path: "other/b")
    XCTAssertThrowsError(try fixture.inventory.moveFolder(b.id, to: "other")) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "inventory.folder_exists")
    }
  }

  func testForkCopiesNonSecretStateAndBindsExactWorld() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let parent = try installedReadyObject(fixture)
    let folder = try fixture.inventory.createFolder(path: "world-sources")
    let runtime = try testWorldRuntime(inventory: fixture.inventory)
    let fork = try fixture.inventory.fork(
      id: parent.id,
      worldID: runtime.harness.world.hash,
      name: "World sensor",
      folder: folder.id
    )

    XCTAssertEqual(fork.revision, 1)
    XCTAssertEqual(fork.configuration, parent.configuration)
    XCTAssertEqual(fork.managementState, parent.managementState)
    XCTAssertEqual(fork.grantedCapabilities, parent.grantedCapabilities)
    XCTAssertTrue(fork.credentialHandles.isEmpty)
    XCTAssertEqual(fork.folderID, folder.id)
    XCTAssertEqual(fork.worldBinding?.worldID, runtime.harness.world.hash)
    XCTAssertEqual(fork.forkProvenance?.parentInventoryObjectID, parent.id)
    XCTAssertEqual(fork.forkProvenance?.parentRevision, parent.revision)

    _ = try fixture.inventory.configure(
      id: fork.id,
      setting: ["label": .string("fork-only")]
    )
    XCTAssertEqual(try fixture.inventory.resolve(parent.id).configuration, parent.configuration)
  }

  func testWorldBoundSourceRejectsAnotherWorldForDeploymentAndRestocking() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let parent = try installedReadyObject(fixture)
    let selected = try testWorldRuntime(inventory: fixture.inventory)
    let other = try testWorldRuntime(inventory: fixture.inventory)
    try applyDefaultKhoros(to: other, inventory: fixture.inventory)
    let fork = try fixture.inventory.fork(
      id: parent.id,
      worldID: selected.harness.world.hash
    )

    XCTAssertThrowsError(try other.deployInventoryObject(fork.id)) { error in
      XCTAssertEqual(
        (error as? MikroKhorosError)?.issue.code,
        "inventory.world_binding_mismatch"
      )
    }
    let merchant = try XCTUnwrap(
      try other.defaultKhorosFacility(.marketplace).container?.object(at: .origin)
        as? MerchantObject)
    XCTAssertThrowsError(
      try other.createRestockRule(
        inventoryID: fork.id,
        merchantQuery: merchant.hash,
        price: 1
      )
    ) { error in
      XCTAssertEqual(
        (error as? MikroKhorosError)?.issue.code,
        "inventory.world_binding_mismatch"
      )
    }
  }

  func testSchemaOneInventoryMigratesObjectsIntoPermanentRootFolder() throws {
    let fixture = try fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let source = try installedReadyObject(fixture)
    var encoded =
      try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.inventory.url))
      as! [String: Any]
    encoded["schemaVersion"] = 1
    encoded.removeValue(forKey: "folders")
    var objects = encoded["objects"] as! [[String: Any]]
    objects[0].removeValue(forKey: "folderID")
    encoded["objects"] = objects
    try JSONSerialization.data(withJSONObject: encoded).write(
      to: fixture.inventory.url, options: .atomic)

    let migrated = try InventoryStore(
      url: fixture.inventory.url,
      packageDirectory: fixture.inventory.packageDirectory,
      credentialStore: fixture.inventory.credentialStore
    )
    XCTAssertEqual(migrated.document.schemaVersion, InventoryDocument.currentSchemaVersion)
    XCTAssertEqual(migrated.document.folders.map(\.id), [InventoryFolderIdentity.rootID])
    XCTAssertEqual(try migrated.resolve(source.id).folderID, InventoryFolderIdentity.rootID)
  }
}

private func applyDefaultKhoros(
  to runtime: WorldRuntime,
  inventory: InventoryStore
) throws {
  let service = WorldTemplateService()
  let plan = try service.preflight(
    templateID: "default-khoros",
    inventory: inventory,
    runtime: runtime
  )
  _ = try service.apply(plan, inventory: inventory, runtime: runtime)
}
