import Foundation
import XCTest

@testable import MikroKhoros

final class CoreTests: XCTestCase {
  private func activeAgent(
    in harness: Harness,
    name: String = "agent",
    at coordinate: Coordinate = .origin,
    coin: Decimal? = 0
  ) throws -> Agent {
    let agent = try harness.createAgent(name: name, coinBalance: coin)
    try harness.addAgent(agent, at: coordinate)
    return agent
  }

  func testAgentCreationAndWorldMembershipAreSeparate() throws {
    let harness = try Harness()
    let agent = try harness.createAgent(name: "sol")

    XCTAssertFalse(agent.isInWorld)
    XCTAssertNil(agent.hand)
    XCTAssertThrowsError(try harness.selfState(agent))

    let placement = try harness.addAgent(agent, at: Coordinate(x: 4, y: -2))
    XCTAssertEqual(placement.actual, Coordinate(x: 4, y: -2))
    XCTAssertTrue(agent.isInWorld)
    XCTAssertTrue(agent.hand is EyeObject)
    XCTAssertEqual(agent.hand?.origin, .genesis)
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

  func testLoadedAgentsBlockButEmptyHandedAgentsCanShareCells() throws {
    let harness = try Harness()
    let first = try activeAgent(in: harness, name: "first")
    let second = try harness.createAgent(name: "second")

    XCTAssertThrowsError(try harness.addAgent(second)) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "agent.add.position_occupied")
    }
    _ = try harness.addAgent(second, autoAdapt: true)
    XCTAssertNotEqual(second.coordinate, first.coordinate)

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
    XCTAssertTrue(state.contains("held: none"))
    XCTAssertTrue(state.contains("standing_on:"))
    _ = try harness.pickup(for: agent)
    state = try harness.selfState(agent)
    XCTAssertTrue(state.contains("held:"))
    XCTAssertTrue(state.contains("standing_on: none"))
  }

  func testNestedPathUsesCoordinatesNamesAndIDs() throws {
    let harness = try Harness()
    let agent = try activeAgent(in: harness)
    try harness.stowHeldObject(for: agent)
    let workshop = try createContainer(name: "Workshop")
    let chest = try createContainer(name: "Chest")
    try harness.place(workshop, at: Coordinate(x: 0, y: 1))
    try workshop.container!.place(chest, at: Coordinate(x: 3, y: -2))
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
      ["scratchpad.object", "messager.object", "calculator.object"]
    )
    try harness.closeBackpack(for: agent)
    XCTAssertEqual(agent.coordinate, .origin)
  }

  func testShopReservesConcreteItemAndRestocksNearestMerchant() throws {
    let harness = try Harness()
    let agent = try activeAgent(in: harness, coin: 10)
    try harness.stowHeldObject(for: agent)
    let item = try AppleObject(durability: 3)
    let built = try createShop(
      name: "Tool Shop",
      inventory: [PricedObject(item, price: 4)],
      autoRestock: true
    )
    try harness.place(built.shop)
    _ = try harness.enterContainer(for: agent)

    let purchase = try harness.purchase(item.hash, from: built.merchant, for: agent)
    XCTAssertEqual(agent.coin.balance, 6)
    XCTAssertEqual(item.lockInfo?.allowedAgentIDs, [agent.hash])
    XCTAssertNotNil(purchase.restocked)
    XCTAssertEqual(purchase.restocked?.maximumDurability, 3)
    agent.coordinate = item.coordinate!
    XCTAssertTrue(try harness.pickup(for: agent) === item)
    XCTAssertNil(item.lockInfo)
  }

  func testBlockedInitialPlacementLeavesAgentOutsideWorldOrAutoAdapts() throws {
    let harness = try Harness()
    let object = try MikroObject(typeName: "anchor.object")
    try harness.place(object)
    let exact = try harness.createAgent(name: "exact")
    XCTAssertThrowsError(try harness.addAgent(exact))
    XCTAssertFalse(exact.isInWorld)

    let adaptive = try harness.createAgent(name: "adaptive")
    let placement = try harness.addAgent(adaptive, autoAdapt: true)
    XCTAssertTrue(placement.adapted)
    XCTAssertEqual(placement.actual.manhattanDistance(to: .origin), 1)
  }
}
