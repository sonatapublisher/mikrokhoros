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

final class NativeManagementTests: XCTestCase {
  private struct Fixture {
    let root: URL
    let inventory: InventoryStore
    let runtime: WorldRuntime
  }

  private func fixture() throws -> Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-native-management-\(UUID().uuidString)", isDirectory: true)
    let inventory = try InventoryStore(
      url: root.appendingPathComponent("inventory.json"),
      packageDirectory: root.appendingPathComponent("packages", isDirectory: true),
      credentialStore: FileCredentialStore(
        directory: root.appendingPathComponent("credentials", isDirectory: true)
      ),
      runtimeRegistry: .installedCLI()
    )
    let runtime = try testWorldRuntime(inventory: inventory)
    return Fixture(root: root, inventory: inventory, runtime: runtime)
  }

  private func defaultKhorosFixture() throws -> Fixture {
    let fixture = try self.fixture()
    let service = WorldTemplateService()
    let plan = try service.preflight(
      templateID: "default-khoros",
      inventory: fixture.inventory,
      runtime: fixture.runtime
    )
    _ = try service.apply(plan, inventory: fixture.inventory, runtime: fixture.runtime)
    return fixture
  }

  func testNativeManagementInterfaceRequiresExactRegisteredWalletOnly() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "agent")
    _ = try runtime.addAgent(agent)

    XCTAssertNotNil(try runtime.nativeManagementInterface(for: agent.wallet))
    let unregisteredWallet = try WalletObject()
    XCTAssertNil(try runtime.nativeManagementInterface(for: unregisteredWallet))
  }

  func testNativeWalletManagementActionsAndViewsCanMutateLedgerState() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "operator")
    _ = try runtime.addAgent(agent)
    let wallet = agent.wallet
    let interface = try XCTUnwrap(try runtime.nativeManagementInterface(for: wallet))

    let actionIDs = Set(interface.actions.map(\.id))
    let viewIDs = Set(interface.views.map(\.id))
    XCTAssertTrue(actionIDs.isSuperset(of: ["deposit", "deduct", "setMode"]))
    XCTAssertFalse(actionIDs.contains("transfer"))
    XCTAssertTrue(viewIDs.isSuperset(of: ["balance", "verify", "statement"]))

    let creditService = try XCTUnwrap(runtime.harness.creditService)
    let startBalance = try creditService.balance(for: wallet.hash)

    let deposit = try XCTUnwrap(
      try runtime.runNativeManagementAction("deposit", inputs: ["12.34"], on: wallet))
    let depositBalance = try XCTUnwrap(deposit.objectValue?["balance"]?.stringValue)
    XCTAssertEqual(
      depositBalance,
      try creditService.balance(for: wallet.hash).decimalText
    )
    XCTAssertGreaterThan(
      try creditService.balance(for: wallet.hash).minorUnits, startBalance.minorUnits)

    let verify = try XCTUnwrap(try runtime.renderNativeManagementView("verify", on: wallet))
    XCTAssertEqual(verify.objectValue?["verified"], .bool(true))
    XCTAssertEqual(verify.objectValue?["wallet_id"], .string(wallet.hash))

    let deduct = try XCTUnwrap(
      try runtime.runNativeManagementAction("deduct", inputs: ["1.00", "false"], on: wallet))
    let deductBalance = try XCTUnwrap(deduct.objectValue?["balance"]?.stringValue)
    XCTAssertEqual(deductBalance, try creditService.balance(for: wallet.hash).decimalText)

    let setMode = try XCTUnwrap(
      try runtime.runNativeManagementAction("setMode", inputs: ["unlimited"], on: wallet))
    XCTAssertEqual(setMode.objectValue?["mode"], .string("unlimited"))

    let statementValue = try XCTUnwrap(
      try runtime.renderNativeManagementView("statement", on: wallet)
    )
    let statement = try XCTUnwrap(statementValue.arrayValue)
    XCTAssertTrue(statement.count >= 2)
  }

  func testNativeWalletCreditOperationsReplayFromDurableEnvelopes() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "operator")
    _ = try runtime.addAgent(agent)
    let wallet = agent.wallet

    _ = try runtime.runNativeManagementAction("deposit", inputs: ["7.00", "funding"], on: wallet)
    _ = try runtime.runNativeManagementAction("deduct", inputs: ["2.00", "debit"], on: wallet)
    _ = try runtime.runNativeManagementAction(
      "setMode", inputs: ["unlimited", "policy"], on: wallet)
    let notifications = wallet.unreadEvents(limit: 16)
    XCTAssertEqual(notifications.count, 3)
    XCTAssertTrue(
      notifications.allSatisfy {
        $0.sourceID == wallet.hash && $0.sourceType == "wallet.object"
      })
    XCTAssertTrue(
      notifications.allSatisfy {
        $0.body.contains("wallet_id:")
          && $0.body.contains("transaction_id:")
          && $0.body.contains("kind:")
          && $0.body.contains("timestamp:")
          && $0.body.contains("resulting_shadow_balance:")
          && $0.body.contains("mode:")
          && $0.body.contains("signed_delta:")
          && !$0.body.contains("record_hash")
          && !$0.body.contains("signature")
      })

    XCTAssertEqual(
      runtime.document.operations.count,
      runtime.document.events.compactMap { event -> WorldOperationEnvelope? in
        guard case .operationEnvelope(let envelope) = event else { return nil }
        return envelope
      }.count
    )
    let restored = try testWorldRuntime(document: runtime.document)
    XCTAssertEqual(try restored.creditService.balance(for: wallet.hash).minorUnits, 500)
    XCTAssertEqual(try restored.creditService.mode(for: wallet.hash), .unlimited)
    XCTAssertNoThrow(try restored.creditService.verify())
    let restoredWallet = try XCTUnwrap(restored.harness.findObject(wallet.hash) as? WalletObject)
    XCTAssertEqual(
      restoredWallet.unreadEvents(limit: 16).map(\.id),
      notifications.map(\.id)
    )
  }

  func testWalletNotificationBoundsEscapedMaximumNoteAndReloads() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "operator")
    _ = try runtime.addAgent(agent)
    let wallet = agent.wallet
    let note = String(repeating: "\\", count: UnsignedCreditRecord.maxNoteLength)

    XCTAssertNoThrow(
      try runtime.runNativeManagementAction(
        "deposit",
        inputs: ["2.00", note],
        on: wallet
      )
    )
    let event = try XCTUnwrap(wallet.unreadEvents(limit: 16).last)
    XCTAssertLessThanOrEqual(event.body.count, AgentBroadcastEvent.maximumBodyCharacters)
    XCTAssertTrue(event.body.contains("wallet_id:"))
    XCTAssertTrue(event.body.contains("transaction_id:"))
    XCTAssertFalse(event.body.contains("signature"))

    let restored = try testWorldRuntime(document: runtime.document)
    let restoredWallet = try XCTUnwrap(restored.harness.findObject(wallet.hash) as? WalletObject)
    XCTAssertEqual(restoredWallet.unreadEvents(limit: 16), wallet.unreadEvents(limit: 16))
    XCTAssertEqual(
      try restored.creditService.balance(for: wallet.hash).minorUnits,
      200
    )
  }

  func testWorldLoadAcceptsInterleavedRegistrationAndCreditEnvelopes() throws {
    let runtime = try testWorldRuntime()
    let first = try runtime.createAgent(name: "first")
    _ = try runtime.addAgent(first)
    _ = try runtime.runNativeManagementAction(
      "deposit", inputs: ["3.00"], on: first.wallet
    )
    let second = try runtime.createAgent(name: "second")
    _ = try runtime.addAgent(second)

    let restored = try testWorldRuntime(document: runtime.document)
    XCTAssertEqual(try restored.creditService.balance(for: first.wallet.hash).minorUnits, 300)
    XCTAssertEqual(try restored.creditService.balance(for: second.wallet.hash).minorUnits, 0)
  }

  func testActionGranularCustodyReplayPreservesNetZeroBearerPath() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "traveler")
    _ = try runtime.addAgent(agent)

    // The wallet is first picked up from the backpack (same bearer), then
    // dropped ownerless and picked up again in the same persisted action
    // batch. The final bearer is unchanged, but both signed boundaries must
    // survive reload in their original action indexes.
    let turn = try runtime.run(
      "backpack open\nmove east 4\nholding select 2\npickup\nbackpack close\ndrop\npickup",
      for: agent
    )
    XCTAssertEqual(turn.status, .success)
    let custody = runtime.creditService.chain.filter {
      $0.unsigned.kind == .custodyChange && $0.unsigned.accounts.contains(agent.wallet.hash)
    }
    XCTAssertEqual(custody.count, 2)
    XCTAssertEqual(custody.map { $0.unsigned.actionIndex }, [5, 6])
    XCTAssertEqual(runtime.creditService.custodyOwner(for: agent.wallet.hash), agent.hash)

    let restored = try testWorldRuntime(document: runtime.document)
    XCTAssertEqual(restored.creditService.custodyOwner(for: agent.wallet.hash), agent.hash)
    XCTAssertEqual(
      try restored.harness.resolveAgent(agent.hash).wallet.hash,
      agent.wallet.hash
    )
  }

  func testReorderedCustodyEnvelopesFailClosed() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "traveler")
    _ = try runtime.addAgent(agent)
    _ = try runtime.run(
      "backpack open\nmove east 4\nholding select 2\npickup\nbackpack close\ndrop\npickup",
      for: agent
    )
    let operationID = try XCTUnwrap(
      runtime.creditService.chain.first {
        $0.unsigned.kind == .custodyChange && $0.unsigned.accounts.contains(agent.wallet.hash)
      }?.unsigned.operationID
    )
    var tampered = runtime.document
    let eventIndexes = tampered.events.indices.filter { index in
      guard case .operationEnvelope(let envelope) = tampered.events[index] else { return false }
      return envelope.operationID == operationID && [5, 6].contains(envelope.actionIndex)
    }
    let operationIndexes = tampered.operations.indices.filter { index in
      let envelope = tampered.operations[index]
      return envelope.operationID == operationID && [5, 6].contains(envelope.actionIndex)
    }
    XCTAssertEqual(eventIndexes.count, 2)
    XCTAssertEqual(operationIndexes.count, 2)
    tampered.events.swapAt(eventIndexes[0], eventIndexes[1])
    tampered.operations.swapAt(operationIndexes[0], operationIndexes[1])
    XCTAssertThrowsError(try testWorldRuntime(document: tampered))
  }

  func testWalletNotificationRemainsOnOwnerlessWalletAcrossCustodyReplay() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "operator")
    _ = try runtime.addAgent(agent)
    let wallet = agent.wallet
    _ = try runtime.runNativeManagementAction("deposit", inputs: ["4.00"], on: wallet)
    let notifications = wallet.unreadEvents(limit: 16)

    _ = try runtime.moveWorldObject(
      objectID: wallet.hash,
      to: runtime.harness.world.hash,
      at: Coordinate(x: 12, y: 12)
    )
    XCTAssertNil(runtime.creditService.custodyOwner(for: wallet.hash))

    let restored = try testWorldRuntime(document: runtime.document)
    XCTAssertNil(restored.creditService.custodyOwner(for: wallet.hash))
    let restoredWallet = try XCTUnwrap(restored.harness.findObject(wallet.hash) as? WalletObject)
    XCTAssertEqual(restoredWallet.unreadEvents(limit: 16).map(\.id), notifications.map(\.id))
  }

  func testHumanDepositAcceptsRegisteredWalletAfterBearerLeavesItOwnerless() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "operator")
    _ = try runtime.addAgent(agent)

    _ = try runtime.moveWorldObject(
      objectID: agent.wallet.hash,
      to: runtime.harness.world.hash,
      at: Coordinate(x: 14, y: 14)
    )
    XCTAssertNil(runtime.creditService.custodyOwner(for: agent.wallet.hash))

    try runtime.deposit(CreditAmount.parse("2.00"), to: agent.wallet)
    XCTAssertEqual(
      try runtime.creditService.balance(for: agent.wallet.hash).minorUnits,
      200
    )
  }

  func testCopyDeletionPreflightsEveryRootBeforeMutatingEarlierRoots() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "operator")
    _ = try runtime.addAgent(agent)

    let inventoryID = "copy-deletion-test"
    func lineage(_ deploymentID: String) -> ObjectLineage {
      ObjectLineage(
        packageID: "copy.deletion.test",
        packageVersion: "1.0.0",
        packageHash: String(repeating: "a", count: 64),
        inventoryObjectID: inventoryID,
        inventoryRevision: 1,
        deploymentID: deploymentID
      )
    }
    let first = try MikroObject(
      typeName: "copy.container",
      name: "first copy",
      summary: "first",
      lineage: lineage("first")
    )
    let second = try MikroObject(
      typeName: "copy.container",
      name: "second copy",
      summary: "second",
      lineage: lineage("second")
    )
    try first.addContainerCapability()
    try second.addContainerCapability()
    let item = try MikroObject(
      typeName: "copy.item",
      name: "priced item",
      summary: "item",
      lineage: lineage("first")
    )
    let merchant = try MerchantObject(
      shopHash: first.hash,
      prices: [item.hash: Decimal(string: "3.00")!],
      autoRestock: false,
      lineage: lineage("first")
    )
    try first.container!.place(item, at: .origin)
    try first.container!.place(merchant, at: Coordinate(x: 1, y: 0))
    try runtime.harness.place(first, at: Coordinate(x: 20, y: 20))
    try runtime.harness.place(second, at: Coordinate(x: 30, y: 30))
    try runtime.setListener(true, objectQuery: item.hash)

    // The later root contains the exact registered Wallet. Moving through the
    // runtime also records the signed custody boundary, making the snapshot
    // assertions cover the credit chain and operation journal.
    try runtime.moveWorldObject(
      objectID: agent.wallet.hash,
      to: second.hash,
      at: .origin
    )
    let pricesBefore = merchant.prices
    let listenersBefore = runtime.listeners
    let documentBefore = runtime.document
    let objectIDsBefore = Set(runtime.harness.objects.map(\.hash))

    XCTAssertThrowsError(
      try runtime.deleteCopies(
        inventoryID: inventoryID,
        scope: .all,
        recursive: true
      )
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "inventory.copy_in_use")
    }

    XCTAssertEqual(merchant.prices, pricesBefore)
    XCTAssertEqual(runtime.listeners, listenersBefore)
    XCTAssertEqual(runtime.document, documentBefore)
    XCTAssertEqual(Set(runtime.harness.objects.map(\.hash)), objectIDsBefore)
    XCTAssertNotNil(runtime.harness.findObject(first.hash))
    XCTAssertNotNil(runtime.harness.findObject(second.hash))
    XCTAssertNotNil(runtime.harness.findObject(agent.wallet.hash))
  }

  func testNativeManagementInterfaceRequiresGenesisMessengerAndCanSendOrAck() throws {
    let runtime = try testWorldRuntime()
    let sender = try runtime.createAgent(name: "sender")
    let recipient = try runtime.createAgent(name: "recipient")
    _ = try runtime.addAgent(sender)
    _ = try runtime.addAgent(recipient)

    let senderRecord = try XCTUnwrap(runtime.document.agents.first(where: { $0.id == sender.hash }))
    let recipientRecord = try XCTUnwrap(
      runtime.document.agents.first(where: { $0.id == recipient.hash }))
    let senderMessenger = try XCTUnwrap(
      runtime.harness.findObject(senderRecord.genesis.messenger) as? MessengerObject
    )
    let recipientMessenger = try XCTUnwrap(
      runtime.harness.findObject(recipientRecord.genesis.messenger) as? MessengerObject
    )
    let rogueMessenger = try MessengerObject()

    let interface = try XCTUnwrap(try runtime.nativeManagementInterface(for: senderMessenger))
    let actionIDs = Set(interface.actions.map(\.id))
    XCTAssertTrue(actionIDs.isSuperset(of: ["send", "ack"]))
    XCTAssertTrue(Set(interface.views.map(\.id)).contains("inbox"))

    let sentValue = try XCTUnwrap(
      try runtime.runNativeManagementAction(
        "send",
        inputs: [recipient.hash, "#1", "Greetings from native management"],
        on: senderMessenger
      )
    )
    let sent = try XCTUnwrap(sentValue.objectValue)
    let messageID = try XCTUnwrap(sent["message_id"]?.stringValue)

    let inboxValue = try XCTUnwrap(
      try runtime.renderNativeManagementView("inbox", on: recipientMessenger)
    )
    let inbox = try XCTUnwrap(inboxValue.arrayValue)
    XCTAssertTrue(
      inbox.contains { $0.objectValue?["id"]?.stringValue == messageID }
    )

    let acknowledgedValue = try XCTUnwrap(
      try runtime.runNativeManagementAction("ack", inputs: [messageID], on: recipientMessenger)
    )
    let acknowledged = try XCTUnwrap(acknowledgedValue.objectValue)
    XCTAssertEqual(acknowledged["acknowledged"], .bool(true))
    XCTAssertNil(acknowledged["message_id"])

    let unreadValue = try XCTUnwrap(
      try runtime.renderNativeManagementView("unread", on: recipientMessenger)
    )
    let unread = try XCTUnwrap(unreadValue.arrayValue)
    XCTAssertTrue(unread.isEmpty)

    XCTAssertNil(try runtime.nativeManagementInterface(for: rogueMessenger))
  }

  func testNativeMessengerSendAndAckReplayInWorldEventOrder() throws {
    let runtime = try testWorldRuntime()
    let sender = try runtime.createAgent(name: "sender")
    let recipient = try runtime.createAgent(name: "recipient")
    _ = try runtime.addAgent(sender)
    _ = try runtime.addAgent(recipient)

    let senderRecord = try XCTUnwrap(runtime.document.agents.first(where: { $0.id == sender.hash }))
    let recipientRecord = try XCTUnwrap(
      runtime.document.agents.first(where: { $0.id == recipient.hash })
    )
    let senderMessenger = try XCTUnwrap(
      runtime.harness.findObject(senderRecord.genesis.messenger) as? MessengerObject
    )
    let recipientMessenger = try XCTUnwrap(
      runtime.harness.findObject(recipientRecord.genesis.messenger) as? MessengerObject
    )

    let sentValue = try XCTUnwrap(
      try runtime.runNativeManagementAction(
        "send",
        inputs: [recipient.hash, "#1", "durable message"],
        on: senderMessenger
      )
    )
    let sent = try XCTUnwrap(sentValue.objectValue)
    let messageID = try XCTUnwrap(sent["message_id"]?.stringValue)
    XCTAssertTrue(
      runtime.document.events.contains {
        if case .message(_, let id, _, _, _, _, _, _) = $0 { return id == messageID }
        return false
      })
    _ = try runtime.runNativeManagementAction(
      "ack",
      inputs: [messageID],
      on: recipientMessenger
    )
    XCTAssertTrue(
      runtime.document.events.contains {
        if case .messengerAcknowledged(_, let id) = $0 { return id == messageID }
        return false
      })

    let restored = try testWorldRuntime(document: runtime.document)
    let restoredMessenger = try XCTUnwrap(
      restored.harness.findObject(recipientRecord.genesis.messenger) as? MessengerObject
    )
    XCTAssertEqual(restoredMessenger.messages.first(where: { $0.id == messageID })?.isRead, true)
  }

  func testNativeMessengerSurfacesAndAcknowledgesDurableHumanInbox() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "requester")
    _ = try runtime.addAgent(agent)
    let record = try XCTUnwrap(runtime.document.agents.first(where: { $0.id == agent.hash }))
    let messenger = try XCTUnwrap(
      runtime.harness.findObject(record.genesis.messenger) as? MessengerObject
    )

    let message = try runtime.harness.sendMessage(
      from: agent,
      using: messenger,
      to: "human",
      threadID: "#1",
      body: "Please fund this wallet"
    )
    XCTAssertEqual(
      runtime.document.events.filter { event in
        guard case .humanMessage(let agentID, let id, _, _, _, _, _, _) = event else {
          return false
        }
        return agentID == agent.hash && id == message.id
      }.count,
      1
    )
    // Human delivery has a durable source transcript as well as the separate
    // human inbox projection.  The source copy is acknowledged/read by the
    // issuing agent, while the human copy remains unread.
    XCTAssertEqual(messenger.messages.first(where: { $0.id == message.id })?.isRead, true)
    XCTAssertEqual(
      try runtime.harness.humanInbox(for: agent).first(where: { $0.id == message.id })?.isRead,
      false
    )
    let inbox = try XCTUnwrap(
      try runtime.renderNativeManagementView("inbox", on: messenger)?.arrayValue
    )
    XCTAssertTrue(inbox.contains { $0.objectValue?["id"]?.stringValue == message.id })
    let unread = try XCTUnwrap(
      try runtime.renderNativeManagementView("unread", on: messenger)?.arrayValue
    )
    XCTAssertTrue(unread.contains { $0.objectValue?["id"]?.stringValue == message.id })

    _ = try runtime.runNativeManagementAction("read", inputs: [message.id], on: messenger)
    XCTAssertTrue(
      runtime.document.events.contains {
        if case .humanInboxAcknowledged(let agentID, let messageID) = $0 {
          return agentID == agent.hash && messageID == message.id
        }
        return false
      })
    XCTAssertTrue(
      runtime.document.operations.contains {
        $0.receipts.contains {
          $0.kind == "human_inbox_acknowledgement"
            && $0.value == "human#\(agent.hash)#\(message.id)"
        }
      })
    let restored = try testWorldRuntime(document: runtime.document)
    let restoredMessenger = try XCTUnwrap(
      restored.harness.findObject(record.genesis.messenger) as? MessengerObject
    )
    XCTAssertEqual(
      restoredMessenger.messages.first(where: { $0.id == message.id })?.isRead,
      true
    )
    let restoredUnread = try XCTUnwrap(
      try restored.renderNativeManagementView("unread", on: restoredMessenger)?.arrayValue
    )
    XCTAssertFalse(restoredUnread.contains { $0.objectValue?["id"]?.stringValue == message.id })
  }

  func testNativeObjectiveBoardManagementIsExposedOnlyForDefaultKhorosBoard() throws {
    let fixture = try defaultKhorosFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let runtime = fixture.runtime

    let objectiveBoard = try XCTUnwrap(
      runtime.optionalDefaultKhorosFacility(.objectiveBoard) as? ObjectiveBoardObject
    )
    let interface = try XCTUnwrap(try runtime.nativeManagementInterface(for: objectiveBoard))
    let actionIDs = Set(interface.actions.map(\.id))
    let viewIDs = Set(interface.views.map(\.id))
    XCTAssertTrue(actionIDs.contains("post"))
    XCTAssertTrue(actionIDs.contains("ack"))
    XCTAssertTrue(viewIDs.isSuperset(of: ["objectives", "attention", "activity"]))

    let postedValue = try XCTUnwrap(
      try runtime.runNativeManagementAction(
        "post",
        inputs: ["First objective", "A shared objective"],
        on: objectiveBoard
      )
    )
    let posted = try XCTUnwrap(postedValue.objectValue)
    let objectiveID = try XCTUnwrap(posted["objective_id"]?.stringValue)
    let otherPostedValue = try XCTUnwrap(
      try runtime.runNativeManagementAction(
        "post",
        inputs: ["Second objective", "Another shared objective"],
        on: objectiveBoard
      )
    )
    let otherObjectiveID = try XCTUnwrap(
      otherPostedValue.objectValue?["objective_id"]?.stringValue
    )

    let objectivesValue = try XCTUnwrap(
      try runtime.renderNativeManagementView("objectives", on: objectiveBoard)
    )
    let objectives = try XCTUnwrap(objectivesValue.arrayValue)
    XCTAssertTrue(
      objectives.contains { $0.objectValue?["id"]?.stringValue == objectiveID }
    )
    XCTAssertTrue(
      objectives.contains { $0.objectValue?["id"]?.stringValue == otherObjectiveID }
    )

    let attentionValue = try XCTUnwrap(
      try runtime.renderNativeManagementView("attention", on: objectiveBoard)
    )
    let attention = try XCTUnwrap(attentionValue.arrayValue)
    XCTAssertTrue(
      attention.contains {
        $0.objectValue?["objective_id"]?.stringValue == objectiveID
          && $0.objectValue?["event_id"]?.stringValue == objectiveID
      }
    )
    XCTAssertTrue(
      attention.contains {
        $0.objectValue?["objective_id"]?.stringValue == otherObjectiveID
          && $0.objectValue?["event_id"]?.stringValue == otherObjectiveID
      }
    )
    let activityBeforeAcknowledgement = try XCTUnwrap(
      try runtime.renderNativeManagementView("activity", on: objectiveBoard)
    )

    let acknowledgement = try XCTUnwrap(
      try runtime.runNativeManagementAction("ack", inputs: [objectiveID], on: objectiveBoard)
    )
    XCTAssertEqual(acknowledgement.objectValue?["acknowledged"], .bool(true))
    XCTAssertTrue(
      runtime.document.events.contains {
        if case .objectiveAcknowledged(let boardID, let acknowledgedObjectiveID, let eventID) = $0 {
          return boardID == objectiveBoard.hash
            && acknowledgedObjectiveID == objectiveID
            && eventID == objectiveID
        }
        return false
      })
    let attentionAfterAcknowledgement = try XCTUnwrap(
      try runtime.renderNativeManagementView("attention", on: objectiveBoard)?.arrayValue
    )
    XCTAssertFalse(
      attentionAfterAcknowledgement.contains {
        $0.objectValue?["event_id"]?.stringValue == objectiveID
      }
    )
    XCTAssertTrue(
      attentionAfterAcknowledgement.contains {
        $0.objectValue?["event_id"]?.stringValue == otherObjectiveID
      }
    )
    XCTAssertEqual(
      try runtime.renderNativeManagementView("objectives", on: objectiveBoard),
      objectivesValue
    )
    XCTAssertEqual(
      try runtime.renderNativeManagementView("activity", on: objectiveBoard),
      activityBeforeAcknowledgement
    )
    let duplicateAcknowledgement = try XCTUnwrap(
      try runtime.runNativeManagementAction("ack", inputs: [objectiveID], on: objectiveBoard)
    )
    XCTAssertEqual(duplicateAcknowledgement.objectValue?["acknowledged"], .bool(false))

    let restored = try testWorldRuntime(document: runtime.document, inventory: fixture.inventory)
    let restoredBoard = try XCTUnwrap(
      restored.optionalDefaultKhorosFacility(.objectiveBoard) as? ObjectiveBoardObject
    )
    let restoredAttention = try XCTUnwrap(
      try restored.renderNativeManagementView("attention", on: restoredBoard)?.arrayValue
    )
    XCTAssertFalse(
      restoredAttention.contains { $0.objectValue?["event_id"]?.stringValue == objectiveID }
    )
    XCTAssertTrue(
      restoredAttention.contains { $0.objectValue?["event_id"]?.stringValue == otherObjectiveID }
    )
    XCTAssertEqual(
      try restored.renderNativeManagementView("objectives", on: restoredBoard),
      objectivesValue
    )
    XCTAssertEqual(
      try restored.renderNativeManagementView("activity", on: restoredBoard),
      activityBeforeAcknowledgement
    )
    let restoredAcknowledgement = try XCTUnwrap(
      try restored.runNativeManagementAction("ack", inputs: [objectiveID], on: restoredBoard)
    )
    XCTAssertEqual(restoredAcknowledgement.objectValue?["acknowledged"], .bool(false))

    let rogueBoard = try ObjectiveBoardObject()
    XCTAssertNil(try runtime.nativeManagementInterface(for: rogueBoard))
    XCTAssertNil(try runtime.runNativeManagementAction("post", inputs: ["x", "y"], on: rogueBoard))
    XCTAssertNil(try runtime.renderNativeManagementView("objectives", on: rogueBoard))
  }
}
