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

final class CoreTests: XCTestCase {
  private func activeAgent(
    in harness: Harness,
    name: String = "agent",
    at coordinate: Coordinate = .origin,
  ) throws -> Agent {
    let agent = try harness.createAgent(name: name)
    try harness.addAgent(agent, at: coordinate)
    return agent
  }

  func testAgentCreationAndWorldMembershipAreSeparate() throws {
    let harness = try Harness()
    let agent = try harness.createAgent(name: "sol")

    XCTAssertFalse(agent.isInWorld)
    XCTAssertNil(agent.primaryHeldObject)
    XCTAssertThrowsError(try harness.selfState(agent))

    let placement = try harness.addAgent(agent, at: Coordinate(x: 4, y: -2))
    XCTAssertEqual(placement.actual, Coordinate(x: 4, y: -2))
    XCTAssertTrue(agent.isInWorld)
    XCTAssertTrue(agent.primaryHeldObject is EyeObject)
    XCTAssertEqual(agent.primaryHeldObject?.origin, .genesis)
  }

  func testWorldAndContainersAreInfiniteSparsePlanes() throws {
    let harness = try Harness()
    let distant = Coordinate(x: -1_000_000, y: 2_000_000)
    let workshop = try createContainer(name: "Workshop")
    let chest = try createContainer(name: "Chest")
    try harness.place(workshop, at: distant)
    try workshop.container!.place(chest, at: Coordinate(x: 3, y: -2))

    XCTAssertTrue(harness.world.container!.contains(distant))
    XCTAssertTrue(workshop.container!.contains(Coordinate(x: Int.max / 2, y: Int.min / 2)))
    XCTAssertTrue(workshop.container!.object(at: Coordinate(x: 3, y: -2)) === chest)
  }

  func testEyeIsOnlyWayToObserveFixedFiveByFiveView() throws {
    let harness = try Harness()
    let agent = try activeAgent(in: harness)
    let selfState = try harness.selfState(agent)

    XCTAssertFalse(selfState.contains("view:"))
    let view = try harness.invokeHeld(for: agent, function: "look", arguments: [])
    XCTAssertTrue(view.contains("size: \"5x5\""))
    XCTAssertTrue(view.contains("x: \"-2..2\""))
    XCTAssertTrue(view.contains("y: \"-2..2\""))
  }

  func testAgentsShareCellsWhetherHoldingsAreLoadedOrEmpty() throws {
    let harness = try Harness()
    let first = try activeAgent(in: harness, name: "first")
    let second = try harness.createAgent(name: "second")

    _ = try harness.addAgent(second, autoAdapt: true)
    XCTAssertEqual(second.coordinate, first.coordinate)

    try harness.stowHeldObject(for: first)
    try harness.stowHeldObject(for: second)
    second.coordinate = first.coordinate
    XCTAssertEqual(second.coordinate, first.coordinate)
    XCTAssertNoThrow(try harness.move(first, direction: "east"))
    XCTAssertNoThrow(try harness.move(first, direction: "west"))
  }

  func testPickupContentionIsFirstComeFirstServe() throws {
    let harness = try Harness()
    let first = try activeAgent(in: harness, name: "first")
    let second = try harness.createAgent(name: "second")
    _ = try harness.addAgent(second, at: Coordinate(x: 2, y: 0))
    try harness.stowHeldObject(for: first)
    try harness.stowHeldObject(for: second)
    second.coordinate = .origin
    let object = try MikroObject(typeName: "tool.object")
    try harness.place(object)

    let firstResult = try harness.performQueuedAction { try harness.pickup(for: first) }
    XCTAssertTrue(firstResult.1 === object)
    XCTAssertThrowsError(try harness.performQueuedAction { try harness.pickup(for: second) })
  }

  func testHeldAndStandingOnAreMutuallyExclusive() throws {
    let harness = try Harness()
    let agent = try activeAgent(in: harness)
    let surface = try MikroObject(typeName: "rug.object")
    try harness.stowHeldObject(for: agent)
    try harness.place(surface)

    var state = try harness.selfState(agent)
    XCTAssertTrue(state.contains("primary: true\n    object: none"))
    XCTAssertTrue(state.contains("standing_on:"))
    XCTAssertTrue(state.contains(surface.hash))
    _ = try harness.pickup(for: agent)
    state = try harness.selfState(agent)
    XCTAssertTrue(state.contains(surface.hash))
    XCTAssertTrue(state.contains("standing_on: none"))
  }

  func testNestedPathUsesCoordinatesNamesAndIDs() throws {
    let harness = try Harness()
    let agent = try activeAgent(in: harness)
    try harness.stowHeldObject(for: agent)
    let workshop = try createContainer(name: "Workshop")
    let chest = try createContainer(name: "Chest")
    try harness.place(workshop, at: Coordinate(x: 0, y: 1))
    try harness.place(chest, at: Coordinate(x: 3, y: -2), in: workshop.container)
    agent.coordinate = Coordinate(x: 0, y: 1)
    _ = try harness.enterContainer(for: agent)
    agent.coordinate = Coordinate(x: 3, y: -2)
    _ = try harness.enterContainer(for: agent)

    let path = harness.agentPath(agent)
    XCTAssertEqual(
      path,
      "(0,0)@world/(0,1)[\"Workshop\"#\(workshop.hash)]/(3,-2)[\"Chest\"#\(chest.hash)]"
    )
  }

  func testPickupLockHasStableErrorAndBuyerClaimClearsOnPickup() throws {
    let harness = try Harness()
    let buyer = try activeAgent(in: harness)
    try harness.stowHeldObject(for: buyer)
    let item = try MikroObject(typeName: "item.object")
    try item.claimPickup(for: "another-agent", authority: .system, owner: "merchant")
    try harness.place(item)

    XCTAssertThrowsError(try harness.pickup(for: buyer)) { error in
      let issue = (error as? MikroKhorosError)?.issue
      XCTAssertEqual(issue?.code, "pickup.locked")
      XCTAssertTrue(issue?.suggestions.first?.contains("pickup lock") == true)
    }
    try item.lock(
      ObjectLock(
        mode: .allowOnly,
        authority: .user,
        owner: "human",
        allowedAgentIDs: [buyer.hash],
        clearsOnPickup: true
      )
    )
    XCTAssertTrue(try harness.pickup(for: buyer) === item)
    XCTAssertNil(item.lockInfo)
  }

  func testActionBatchIsBoundedFailFastAndOrdered() throws {
    let harness = try Harness()
    let agent = try activeAgent(in: harness)
    let session = AgentSession(harness: harness, agent: agent)
    let turn = session.run(
      "move east\nmove nowhere\nmove south\nmove west",
      maximumActions: 3
    )

    XCTAssertEqual(agent.coordinate, Coordinate(x: 1, y: 0))
    XCTAssertEqual(turn.results.count, 2)
    XCTAssertEqual(turn.results[0].status, .success)
    XCTAssertEqual(turn.results[1].error?.code, "move.direction_unknown")
    XCTAssertTrue(
      turn.events.contains {
        if case .warning(let warning) = $0 { return warning.code == "batch.stopped" }
        return false
      })
    XCTAssertTrue(
      turn.events.contains {
        if case .warning(let warning) = $0 { return warning.code == "batch.action_limit" }
        return false
      })
    XCTAssertLessThan(turn.results[0].sequence, turn.results[1].sequence)
  }

  func testBackpackIsPrivateInfiniteContainerAndPathIsValid() throws {
    let harness = try Harness()
    let agent = try activeAgent(in: harness)
    try harness.openBackpack(for: agent)

    XCTAssertTrue(agent.space === agent.backpack.container)
    XCTAssertTrue(harness.agentPath(agent).contains("@backpack["))
    XCTAssertEqual(
      agent.backpack.container!.items.map(\.object.typeName),
      ["scratchpad.object", "messager.object", "calculator.object", "wallet.object"]
    )
    try harness.closeBackpack(for: agent)
    XCTAssertEqual(agent.coordinate, .origin)
  }

  func testShopReservesConcreteItemAndRestocksNearestMerchant() throws {
    let runtime = try testWorldRuntime()
    let harness = runtime.harness
    let agent = try runtime.createAgent(name: "buyer")
    _ = try runtime.addAgent(agent)
    let creditService = runtime.creditService
    try creditService.deposit(
      walletID: agent.wallet.hash,
      amount: try CreditAmount(minorUnits: 1_000),
      actor: .system
    )
    try harness.stowHeldObject(for: agent)
    let item = try AppleObject(durability: 3)
    let built = try createShop(
      name: "Tool Shop",
      inventory: [PricedObject(item, price: 4)],
      autoRestock: true
    )
    try harness.place(built.shop)
    _ = try harness.enterContainer(for: agent)

    let purchase = try harness.purchase(
      itemSelector: item.hash,
      walletID: agent.wallet.hash,
      from: built.merchant,
      for: agent
    )
    XCTAssertEqual(try creditService.balance(for: agent.wallet.hash).minorUnits, 600)
    XCTAssertEqual(item.lockInfo?.allowedAgentIDs, [agent.hash])
    XCTAssertNotNil(purchase.restocked)
    XCTAssertEqual(purchase.restocked?.maximumDurability, 3)
    agent.coordinate = item.coordinate!
    XCTAssertTrue(try harness.pickup(for: agent) === item)
    XCTAssertNil(item.lockInfo)
  }

  func testInitialPlacementMayShareAPlacedObjectCoordinate() throws {
    let harness = try Harness()
    let object = try MikroObject(typeName: "anchor.object")
    try harness.place(object)
    let exact = try harness.createAgent(name: "exact")
    let exactPlacement = try harness.addAgent(exact)
    XCTAssertTrue(exact.isInWorld)
    XCTAssertFalse(exactPlacement.adapted)
    XCTAssertEqual(exactPlacement.actual, .origin)

    let adaptive = try harness.createAgent(name: "adaptive")
    let placement = try harness.addAgent(adaptive, autoAdapt: true)
    XCTAssertFalse(placement.adapted)
    XCTAssertEqual(placement.actual, .origin)
  }

  func testSelectingSecondaryHoldingAllowsPickupWhenPrimaryIsOccupied() throws {
    let harness = try Harness()
    let agent = try activeAgent(in: harness)
    let item = try MikroObject(typeName: "tool.object")
    try harness.place(item)
    XCTAssertTrue(agent.primaryHeldObject is EyeObject)
    try harness.selectHolding(.two, for: agent)

    let picked = try harness.pickup(for: agent)
    XCTAssertTrue(agent.primaryHoldingNumber == .two)
    XCTAssertTrue(agent.primaryHeldObject === picked)
    XCTAssertTrue(agent.primaryHeldObject === item)
  }

  func testHoldingSelectReplayPersistsThroughReload() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "selective")
    _ = try runtime.addAgent(agent)
    let turn = try runtime.run("holding select 2", for: agent)
    XCTAssertEqual(turn.status, .success)
    XCTAssertEqual(agent.primaryHoldingNumber, .two)
    XCTAssertNil(agent.holdings[.two])

    let restored = try testWorldRuntime(document: runtime.document)
    let restoredAgent = try restored.harness.resolveAgent(agent.hash)
    XCTAssertEqual(restoredAgent.primaryHoldingNumber, .two)
    XCTAssertNil(restoredAgent.holdings[.two])
  }

  func testLoadedAgentsCanShareCurrentCoordinates() throws {
    let harness = try Harness()
    let first = try activeAgent(in: harness, name: "loaded-one")
    let second = try harness.createAgent(name: "loaded-two")
    _ = try harness.addAgent(second)

    XCTAssertEqual(first.coordinate, second.coordinate)
    XCTAssertNoThrow(try harness.move(first, direction: "east"))
    XCTAssertNoThrow(try harness.move(first, direction: "west"))
  }

  func testLoadedAgentsShareCoordinatesWithoutCollisionAfterRestore() throws {
    let runtime = try testWorldRuntime()
    let first = try runtime.createAgent(name: "loaded-one")
    let second = try runtime.createAgent(name: "loaded-two")
    _ = try runtime.addAgent(first, at: .origin)
    _ = try runtime.addAgent(second, at: .origin)
    XCTAssertEqual(first.coordinate, second.coordinate)

    let restored = try testWorldRuntime(document: runtime.document)
    let restoredFirst = try restored.harness.resolveAgent(first.hash)
    let restoredSecond = try restored.harness.resolveAgent(second.hash)
    XCTAssertEqual(restoredFirst.coordinate, restoredSecond.coordinate)
    XCTAssertNoThrow(try restored.harness.move(restoredFirst, direction: "east"))
    XCTAssertNoThrow(try restored.harness.move(restoredSecond, direction: "west"))
  }

  func testFourHoldingsFullBlocksPickupForPrimarySelection() throws {
    let harness = try Harness()
    let agent = try activeAgent(in: harness)
    agent.holdings[.two] = try MikroObject(typeName: "tool.object")
    agent.holdings[.three] = try MikroObject(typeName: "tool.object")
    agent.holdings[.four] = try MikroObject(typeName: "tool.object")
    XCTAssertEqual(agent.holdings.occupiedRoots.count, 4)
    let item = try MikroObject(typeName: "tool.object")
    try harness.place(item)

    XCTAssertThrowsError(try harness.pickup(for: agent)) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "pickup.holding_occupied")
    }
  }
}
