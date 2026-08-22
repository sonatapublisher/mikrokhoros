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

final class HoldingsLocationTests: XCTestCase {
  private func activeAgent(
    in harness: Harness,
    name: String = "agent",
    at coordinate: Coordinate = .origin
  ) throws -> Agent {
    let agent = try harness.createAgent(name: name)
    try harness.addAgent(agent, at: coordinate)
    return agent
  }

  private func shuffle<T>(_ values: [T]) -> [T] {
    var result = values
    result.shuffle()
    return result
  }

  func testHoldingNumberValidationAndComparable() {
    XCTAssertEqual(HoldingNumber.one.rawValue, 1)
    XCTAssertEqual(HoldingNumber.two.rawValue, 2)
    XCTAssertEqual(HoldingNumber.three.rawValue, 3)
    XCTAssertEqual(HoldingNumber.four.rawValue, 4)

    XCTAssertThrowsError(try HoldingNumber(0))
    XCTAssertThrowsError(try HoldingNumber(5))

    let unsorted = [HoldingNumber.four, HoldingNumber.one, HoldingNumber.three, HoldingNumber.two]
    XCTAssertEqual(unsorted.sorted(), [.one, .two, .three, .four])
  }

  func testAgentHoldingsTracksFourSlotsWithPrimarySelection() throws {
    let first = try MikroObject(typeName: "first.object")
    let second = try MikroObject(typeName: "second.object")
    let third = try MikroObject(typeName: "third.object")
    let eye = try EyeObject(name: "agent-eye")
    var holdings = try AgentHoldings(eye: eye, primaryHoldingNumber: .two)

    XCTAssertEqual(holdings.primaryHoldingNumber, .two)
    XCTAssertTrue(holdings[.one] === eye)
    XCTAssertNil(holdings[.two])
    XCTAssertEqual(holdings.occupiedRoots.map(\.hash).sorted(), [eye.hash])

    holdings.select(.three)
    XCTAssertEqual(holdings.primaryHoldingNumber, .three)
    try holdings.putPrimary(first)
    XCTAssertTrue(holdings.primaryHeldObject === first)
    XCTAssertThrowsError(try holdings.putPrimary(first))
    XCTAssertEqual(holdings.occupiedRoots.count, 2)
    XCTAssertNotNil(holdings.removePrimary())
    XCTAssertNil(holdings.primaryHeldObject)
    holdings[.one] = second
    holdings[.four] = third
    XCTAssertEqual(holdings.occupiedRoots.count, 2)

    var independentCopy = holdings
    independentCopy.select(.two)
    XCTAssertEqual(independentCopy.primaryHoldingNumber, .two)
    XCTAssertEqual(holdings.primaryHoldingNumber, .three)
  }

  func testObjectLocationIndexTracksWorldHeldBackpackAndDetachedOwnership() throws {
    let harness = try Harness()
    let active = try activeAgent(in: harness, name: "active")
    let inactive = try harness.createAgent(name: "inactive")

    let workshop = try createContainer(name: "workshop")
    let drawer = try createContainer(name: "drawer")
    let drawerKey = try MikroObject(typeName: "tool.object")
    try workshop.container!.place(drawer, at: Coordinate(x: 1, y: 0))
    try drawer.container!.place(drawerKey, at: Coordinate(x: 0, y: 0))
    try harness.place(workshop, at: Coordinate(x: 2, y: 0))

    let heldRoot = try createContainer(name: "held-root")
    let heldKey = try MikroObject(typeName: "gem.object")
    try heldRoot.container!.place(heldKey, at: Coordinate(x: -1, y: 0))
    active.coordinate = Coordinate(x: 5, y: 0)
    try harness.place(heldRoot, at: active.coordinate)
    try harness.selectHolding(.two, for: active)
    try harness.pickup(for: active)

    let backpackItem = try createContainer(name: "backpack-item")
    let backpackLeaf = try MikroObject(typeName: "backpack-leaf.object")
    try backpackItem.container!.place(backpackLeaf, at: Coordinate(x: 0, y: 0))
    try active.backpack.container!.place(
      backpackItem,
      at: Coordinate(x: 9, y: 0)
    )

    let index = try ObjectLocationIndex(
      world: harness.world,
      registeredObjects: harness.objects + [backpackItem, backpackLeaf],
      agents: harness.agents
    )

    XCTAssertEqual(index.currentOwner(of: heldRoot.hash), .agent(id: active.hash, holding: .two))
    XCTAssertEqual(index.currentOwner(of: heldKey.hash), .agent(id: active.hash, holding: .two))
    XCTAssertEqual(index.currentOwner(of: backpackItem.hash), .agent(id: active.hash, holding: nil))
    XCTAssertEqual(index.currentOwner(of: backpackLeaf.hash), .agent(id: active.hash, holding: nil))
    XCTAssertEqual(index.currentOwner(of: workshop.hash), nil)
    XCTAssertEqual(index.currentOwner(of: inactive.wallet), .agent(id: inactive.hash, holding: nil))

    let heldPath = try XCTUnwrap(index.location(for: heldRoot.hash))
    XCTAssertTrue(heldPath.locationPath.description.contains("agent:\(active.hash):holding:2"))

    let backpackItemPath = try XCTUnwrap(index.location(for: backpackItem.hash))
    XCTAssertTrue(
      backpackItemPath.locationPath.description.contains("agent:\(active.hash):attachment:backpack")
    )
  }

  func testCreateAgentRegistersAndOwnsEveryInitialHoldingTree() throws {
    let harness = try Harness()
    let heldContainer = try createContainer(name: "initial-held-container")
    let heldLeaf = try MikroObject(typeName: "initial-held-leaf.object")
    try heldContainer.container!.place(heldLeaf, at: .origin)
    let holdings = try AgentHoldings(
      slot2: heldContainer,
      primaryHoldingNumber: .one
    )

    let agent = try harness.createAgent(name: "initial-holder", holdings: holdings)

    XCTAssertTrue(harness.findObject(heldContainer.hash) === heldContainer)
    XCTAssertTrue(harness.findObject(heldLeaf.hash) === heldLeaf)
    XCTAssertEqual(
      try harness.currentOwner(of: heldLeaf),
      .agent(id: agent.hash, holding: .two)
    )
    XCTAssertNoThrow(try harness.addAgent(agent))
    XCTAssertTrue(agent.holdings[.one] is EyeObject)
    XCTAssertTrue(agent.holdings[.two] === heldContainer)
  }

  func testCreateAgentRejectsAnInitialHoldingAlreadyPlacedInTheWorld() throws {
    let harness = try Harness()
    let placed = try MikroObject(typeName: "already-placed.object")
    try harness.place(placed)
    let holdings = try AgentHoldings(slot2: placed)

    XCTAssertThrowsError(try harness.createAgent(name: "invalid-holder", holdings: holdings))
  }

  func testWalletReadAuthorityRequiresLiveAndSignedBearerToAgree() throws {
    let harness = try Harness()
    let service = try CreditService(
      worldID: harness.world.hash,
      authorityState: testTreasuryAuthorityState
    )
    try harness.setCreditService(service)
    let issuer = try harness.createAgent(name: "issuer")
    let other = try harness.createAgent(name: "other")

    let wallet = try XCTUnwrap(
      try issuer.backpack.container!.remove(at: Coordinate(x: 4, y: 0)) as? WalletObject
    )
    try other.backpack.container!.place(wallet, at: Coordinate(x: 5, y: 0))

    XCTAssertEqual(try harness.currentOwner(of: wallet)?.agentID, other.hash)
    XCTAssertEqual(service.custodyOwner(for: wallet.hash), issuer.hash)
    XCTAssertThrowsError(try harness.requireWalletOwner(other, wallet)) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "wallet.owner_denied")
    }
  }

  func testDirectInvocationCannotBypassAnotherAgentsPropertyRights() throws {
    let harness = try Harness()
    let owner = try activeAgent(in: harness, name: "owner")
    let intruder = try activeAgent(
      in: harness,
      name: "intruder",
      at: Coordinate(x: 3, y: 0)
    )
    let scratchpad = try XCTUnwrap(
      owner.backpack.walkContents().compactMap { $0 as? ScratchpadObject }.first
    )
    let missing = try ScratchpadObject(name: "missing")

    func failure(_ object: ScratchpadObject) -> RuntimeIssue? {
      do {
        _ = try object.invoke("write", arguments: ["stolen"], harness: harness, agent: intruder)
        XCTFail("expected direct invocation to fail")
        return nil
      } catch let error as MikroKhorosError {
        return error.issue
      } catch {
        XCTFail("unexpected error: \(error)")
        return nil
      }
    }

    let privateFailure = failure(scratchpad)
    let missingFailure = failure(missing)
    XCTAssertEqual(privateFailure?.code, "object.unavailable")
    XCTAssertEqual(privateFailure?.code, missingFailure?.code)
    XCTAssertEqual(privateFailure?.message, missingFailure?.message)
    XCTAssertEqual(scratchpad.text, "")
  }

  func testObjectLocationIndexRejectsAHashImpostorInTheGraph() throws {
    let harness = try Harness()
    let canonical = try MikroObject(typeName: "canonical.object")
    try harness.place(canonical, at: Coordinate(x: 2, y: 0))
    let impostor = try MikroObject(typeName: "impostor.object", hash: canonical.hash)
    _ = try harness.world.container!.remove(at: Coordinate(x: 2, y: 0))
    try harness.world.container!.place(impostor, at: Coordinate(x: 2, y: 0))

    XCTAssertThrowsError(
      try ObjectLocationIndex(
        world: harness.world,
        registeredObjects: harness.objects,
        agents: harness.agents
      )
    )
  }

  func testGenesisWalletAndContainingSubtreeCannotBeRemovedWithoutCreditService() throws {
    let harness = try Harness()
    let agent = try harness.createAgent(name: "wallet-owner")
    let container = try createContainer(name: "wallet-container")
    try harness.place(container, at: Coordinate(x: 2, y: 0))
    try harness.moveObject(agent.wallet, to: .origin, in: container.container)

    XCTAssertThrowsError(try harness.removeObject(agent.wallet))
    XCTAssertThrowsError(try harness.removeObject(agent.backpack))
    XCTAssertThrowsError(try harness.removeObject(container))
    XCTAssertTrue(harness.findObject(agent.wallet.hash) === agent.wallet)
    XCTAssertTrue(harness.findObject(agent.backpack.hash) === agent.backpack)
    XCTAssertTrue(container.container?.object(at: .origin) === agent.wallet)
    XCTAssertTrue(harness.world.container?.object(at: Coordinate(x: 2, y: 0)) === container)
  }

  func testOccupiedContainerCannotBePickedUpMovedOrSummoned() throws {
    let harness = try Harness()
    let occupant = try activeAgent(in: harness, name: "occupant")
    let mover = try activeAgent(
      in: harness,
      name: "mover",
      at: Coordinate(x: 4, y: 0)
    )
    let container = try createContainer(name: "occupied-container")
    try harness.place(container, at: occupant.coordinate)
    _ = try harness.enterContainer(for: occupant)

    mover.coordinate = .origin
    try harness.selectHolding(.two, for: mover)
    XCTAssertThrowsError(try harness.pickup(for: mover)) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "container.occupied_by_agent")
    }
    XCTAssertTrue(harness.world.container?.object(at: .origin) === container)
    XCTAssertNil(mover.primaryHeldObject)

    XCTAssertThrowsError(
      try harness.moveObject(container, to: Coordinate(x: 8, y: 0), in: harness.world.container)
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "container.occupied_by_agent")
    }
    XCTAssertTrue(harness.world.container?.object(at: .origin) === container)

    mover.knownHashes.insert(container.hash)
    mover.coordinate = Coordinate(x: 4, y: 0)
    XCTAssertThrowsError(try harness.summon(container.hash, for: mover)) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "container.occupied_by_agent")
    }
    XCTAssertTrue(harness.world.container?.object(at: .origin) === container)
  }

  func testPlaceRejectsHeldAttachmentAndForeignSpaceRootsWithoutGraphCorruption() throws {
    let harness = try Harness()
    let agent = try activeAgent(in: harness, name: "holder")
    let object = try MikroObject(typeName: "held-root.object")
    try harness.place(object, at: agent.coordinate)
    try harness.selectHolding(.two, for: agent)
    _ = try harness.pickup(for: agent)

    XCTAssertThrowsError(try harness.place(object, at: Coordinate(x: 2, y: 0)))
    XCTAssertTrue(agent.primaryHeldObject === object)

    try harness.selectHolding(.one, for: agent)
    XCTAssertThrowsError(try harness.place(object, at: Coordinate(x: 3, y: 0)))
    XCTAssertTrue(agent.holdings[.two] === object)
    XCTAssertThrowsError(try harness.place(agent.backpack, at: Coordinate(x: 4, y: 0)))
    XCTAssertNil(agent.backpack.parentSpace)

    let foreignHarness = try Harness()
    let detached = try MikroObject(typeName: "detached.object")
    XCTAssertThrowsError(
      try harness.place(detached, at: .origin, in: foreignHarness.world.container)
    )
    XCTAssertNil(detached.parentSpace)
    XCTAssertNil(harness.findObject(detached.hash))
    XCTAssertNoThrow(try harness.currentOwner(of: object))
  }

  func testCoordinateBoundaryActionsFailWithoutMutationOrTrap() throws {
    let harness = try Harness()
    let agent = try activeAgent(
      in: harness,
      name: "boundary-agent",
      at: Coordinate(x: Int.max, y: Int.min)
    )

    XCTAssertThrowsError(try harness.move(agent, direction: "east")) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "coordinate.overflow")
    }
    XCTAssertEqual(agent.coordinate, Coordinate(x: Int.max, y: Int.min))

    let object = try MikroObject(typeName: "boundary.object")
    try harness.place(object, at: agent.coordinate)
    try harness.selectHolding(.two, for: agent)
    _ = try harness.pickup(for: agent)
    XCTAssertThrowsError(try harness.drop(for: agent, delta: Coordinate(x: 1, y: 0))) {
      error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "coordinate.overflow")
    }
    XCTAssertTrue(agent.primaryHeldObject === object)
    XCTAssertNil(agent.space.object(at: Coordinate(x: Int.max, y: Int.min)))

    XCTAssertEqual(
      Coordinate(x: Int.min, y: Int.min).manhattanDistance(
        to: Coordinate(x: Int.max, y: Int.max)
      ),
      Int.max
    )
    XCTAssertEqual(
      Coordinate(x: Int.max, y: Int.min) + Coordinate(x: 1, y: -1),
      Coordinate(x: Int.max, y: Int.min)
    )
  }

  func testSummonUsesSameSafeErrorForMissingAndOtherOwnedObjects() throws {
    let harness = try Harness()
    let first = try activeAgent(in: harness, name: "first")
    let second = try activeAgent(
      in: harness,
      name: "second",
      at: Coordinate(x: 3, y: 0)
    )
    let privateObject = try MikroObject(typeName: "private.object")
    try harness.place(privateObject, at: second.coordinate)
    try harness.selectHolding(.two, for: second)
    _ = try harness.pickup(for: second)
    first.knownHashes.insert(privateObject.hash)

    var codes: [String] = []
    for target in [privateObject.hash, "missing-exact-object-id"] {
      XCTAssertThrowsError(try harness.summon(target, for: first)) { error in
        codes.append((error as? MikroKhorosError)?.issue.code ?? "")
      }
    }
    XCTAssertEqual(codes, ["object.unavailable", "object.unavailable"])
  }

  func testPortalInsideOtherAgentPropertyCannotBeUsedAsTeleportDestination() throws {
    let harness = try Harness()
    let traveler = try activeAgent(in: harness, name: "traveler")
    let owner = try activeAgent(
      in: harness,
      name: "portal-owner",
      at: Coordinate(x: 4, y: 0)
    )
    let pair = try createPortalPair()
    let privateContainer = try createContainer(name: "private-portal-container")
    try privateContainer.container!.place(pair.portal, at: .origin)
    try harness.place(privateContainer, at: owner.coordinate)
    try harness.selectHolding(.two, for: owner)
    _ = try harness.pickup(for: owner)

    try harness.place(pair.key, at: traveler.coordinate)
    try harness.selectHolding(.two, for: traveler)
    _ = try harness.pickup(for: traveler)

    XCTAssertThrowsError(
      try harness.invokeAccessible(for: traveler, function: "use", arguments: [])
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "object.unavailable")
    }
    XCTAssertTrue(traveler.primaryHeldObject === pair.key)
  }

  func testPortalInsideOwnHeldPropertyCannotStrandAgent() throws {
    let harness = try Harness()
    let traveler = try activeAgent(in: harness, name: "traveler")
    let pair = try createPortalPair(keyDurability: 2)
    let carriedPortal = try createContainer(name: "carried-portal")
    try carriedPortal.container!.place(pair.portal, at: .origin)
    try harness.place(carriedPortal, at: traveler.coordinate)
    try harness.selectHolding(.two, for: traveler)
    _ = try harness.pickup(for: traveler)

    try harness.place(pair.key, at: traveler.coordinate)
    try harness.selectHolding(.three, for: traveler)
    _ = try harness.pickup(for: traveler)
    let originalSpace = traveler.space
    let originalCoordinate = traveler.coordinate

    XCTAssertThrowsError(
      try harness.invokeAccessible(for: traveler, function: "use", arguments: [])
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "teleport.destination_carried")
    }
    XCTAssertTrue(traveler.primaryHeldObject === pair.key)
    XCTAssertEqual(pair.key.durability, 2)
    XCTAssertTrue(traveler.space === originalSpace)
    XCTAssertEqual(traveler.coordinate, originalCoordinate)
  }

  func testOwnerlessNestedPortalRemainsUsableWithOtherHoldingsLoaded() throws {
    let harness = try Harness()
    let traveler = try activeAgent(in: harness, name: "traveler")
    let pair = try createPortalPair(keyDurability: 2)
    let destination = try createContainer(name: "portal-room")
    try destination.container!.place(pair.portal, at: Coordinate(x: 1, y: 1))
    try harness.place(destination, at: Coordinate(x: 8, y: 0))

    for (slot, type) in [(HoldingNumber.three, "tool-three.object"), (.four, "tool-four.object")] {
      let object = try MikroObject(typeName: type)
      try harness.place(object, at: traveler.coordinate)
      try harness.selectHolding(slot, for: traveler)
      _ = try harness.pickup(for: traveler)
    }
    try harness.place(pair.key, at: traveler.coordinate)
    try harness.selectHolding(.two, for: traveler)
    _ = try harness.pickup(for: traveler)

    _ = try harness.invokeAccessible(for: traveler, function: "use", arguments: [])

    XCTAssertTrue(traveler.space === destination.container)
    XCTAssertEqual(traveler.coordinate, Coordinate(x: 1, y: 1))
    XCTAssertNil(traveler.holdings[.two])
    XCTAssertNotNil(traveler.holdings[.three])
    XCTAssertNotNil(traveler.holdings[.four])
    XCTAssertEqual(pair.key.durability, 1)
  }

  func testFailedSummonNeverStowsOrConsumesTheSummoner() throws {
    let harness = try Harness()
    let agent = try activeAgent(in: harness, name: "summoner-agent")
    let summoner = try SummonerObject(durability: 3)
    try harness.place(summoner, at: agent.coordinate)
    try harness.selectHolding(.two, for: agent)
    _ = try harness.pickup(for: agent)

    XCTAssertThrowsError(
      try harness.invokeAccessible(for: agent, function: "summon", arguments: ["missing"])
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "object.unavailable")
    }
    XCTAssertTrue(agent.primaryHeldObject === summoner)
    XCTAssertEqual(summoner.durability, 3)

    let target = try MikroObject(typeName: "summon-target.object")
    try target.lock(authority: .user, owner: "human", reason: "test")
    try harness.place(target, at: Coordinate(x: 5, y: 0))
    agent.knownHashes.insert(target.hash)
    XCTAssertThrowsError(
      try harness.invokeAccessible(for: agent, function: "summon", arguments: [target.hash])
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "summon.locked")
    }
    XCTAssertTrue(agent.primaryHeldObject === summoner)
    XCTAssertEqual(summoner.durability, 3)
    XCTAssertTrue(harness.world.container?.object(at: Coordinate(x: 5, y: 0)) === target)
  }

  func testOwnedBearerMessengerCanSendToTheHumanInbox() throws {
    let harness = try Harness()
    let issuer = try activeAgent(in: harness, name: "messenger-issuer")
    let bearer = try activeAgent(
      in: harness,
      name: "messenger-bearer",
      at: Coordinate(x: 6, y: 0)
    )
    let messenger = try harness.messenger(for: issuer)
    try harness.moveObject(messenger, to: bearer.coordinate, in: bearer.space)
    try harness.selectHolding(.two, for: bearer)
    _ = try harness.pickup(for: bearer)

    let message = try harness.sendMessage(
      from: bearer,
      using: messenger,
      to: "human",
      threadID: "#1",
      body: "Please add credit to the Wallet I am carrying."
    )

    XCTAssertEqual(message.senderAgentID, bearer.hash)
    XCTAssertEqual(try harness.humanInbox(for: bearer).map(\.id), [message.id])
  }

  func testObjectLocationIndexDetectsOrphanAndDuplicate() throws {
    let harness = try Harness()
    _ = try activeAgent(in: harness)

    let orphan = try MikroObject(typeName: "orphan.object")
    let withOrphan = harness.objects + [orphan]
    XCTAssertThrowsError(
      try ObjectLocationIndex(
        world: harness.world,
        registeredObjects: withOrphan,
        agents: harness.agents
      )
    ) { error in
      XCTAssertEqual(error as? ObjectLocationIndexError, .orphanedObjects([orphan.hash]))
    }

    let duplicate = try MikroObject(typeName: "world.object")
    try harness.place(duplicate, at: Coordinate(x: 7, y: 0))
    let closureAgent = [duplicate, nil, nil, nil]
    XCTAssertThrowsError(
      try ObjectLocationIndex(
        world: harness.world,
        registeredObjects: harness.objects,
        agents: harness.agents,
        holdingRoots: { _ in closureAgent }
      )
    ) { error in
      guard let locationError = error as? ObjectLocationIndexError else {
        return XCTFail("expected an object-location error")
      }
      switch locationError {
      case .ambiguousOwner(let objectHash, ownerA: _, ownerB: _, existingPath: _, incomingPath: _):
        XCTAssertEqual(objectHash, duplicate.hash)
      case .duplicateObjectPlacement(
        let objectHash, existingOwner: _, incomingOwner: _, existingPath: _, incomingPath: _):
        XCTAssertEqual(objectHash, duplicate.hash)
      default:
        XCTFail("expected duplicate/ambiguous ownership error")
      }
    }
  }

  func testObjectLocationIndexDetectsDepthLimitAndAmbiguousOwnership() throws {
    let depthHarness = try Harness()
    _ = try activeAgent(in: depthHarness, name: "first")
    _ = try activeAgent(in: depthHarness, name: "second", at: Coordinate(x: 1, y: 0))

    let chainHead = try createContainer(name: "chain-0")
    var current = chainHead
    for index in 1...8 {
      let next = try createContainer(name: "chain-\(index)")
      try current.container!.place(next, at: Coordinate(x: index, y: 0))
      current = next
    }
    try depthHarness.place(chainHead, at: Coordinate(x: 11, y: 0))

    XCTAssertThrowsError(
      try ObjectLocationIndex(
        world: depthHarness.world,
        registeredObjects: depthHarness.objects,
        agents: depthHarness.agents,
        maxDepth: 4
      )
    ) { error in
      guard let locationError = error as? ObjectLocationIndexError,
        case .depthExceeded(let objectHash, let limit) = locationError
      else {
        return XCTFail("expected depth limit error")
      }
      XCTAssertEqual(limit, 4)
      XCTAssertFalse(objectHash.isEmpty)
    }

    let ambiguousHarness = try Harness()
    let firstOwner = try activeAgent(in: ambiguousHarness, name: "first-owner")
    let secondOwner = try activeAgent(
      in: ambiguousHarness, name: "second-owner", at: Coordinate(x: 2, y: 0))
    let conflict = try MikroObject(typeName: "conflict.object")
    XCTAssertThrowsError(
      try ObjectLocationIndex(
        world: ambiguousHarness.world,
        registeredObjects: ambiguousHarness.objects + [conflict],
        agents: [firstOwner, secondOwner],
        holdingRoots: { agent in
          if agent === firstOwner {
            return [conflict, nil, nil, nil]
          }
          return [conflict, nil, nil, nil]
        },
        maxDepth: 256
      )
    ) { error in
      guard let locationError = error as? ObjectLocationIndexError else {
        return XCTFail("expected an object-location error")
      }
      switch locationError {
      case .ambiguousOwner(let objectHash, ownerA: _, ownerB: _, existingPath: _, incomingPath: _):
        XCTAssertEqual(objectHash, conflict.hash)
      case .duplicateObjectPlacement(
        let objectHash, existingOwner: _, incomingOwner: _, existingPath: _, incomingPath: _):
        XCTAssertEqual(objectHash, conflict.hash)
      default:
        XCTFail("expected ambiguous or duplicate ownership error")
      }
    }
  }

  func testObjectLocationIndexDeterministicPathsAndCommitmentMaterials() throws {
    let harness = try Harness()
    let one = try activeAgent(in: harness, name: "one")
    let two = try activeAgent(in: harness, name: "two", at: Coordinate(x: 1, y: 0))
    let sharedWorld = try createContainer(name: "shared")
    let sharedWorldChild = try createContainer(name: "shared-child")
    try sharedWorld.container!.place(sharedWorldChild, at: Coordinate(x: 1, y: 0))
    let sharedWorldLeaf = try MikroObject(typeName: "shared-leaf.object")
    try sharedWorldChild.container!.place(sharedWorldLeaf, at: Coordinate(x: 0, y: 0))
    try harness.place(sharedWorld, at: Coordinate(x: 3, y: 3))

    one.coordinate = Coordinate(x: -1, y: 0)
    let activeHoldRoot = try createContainer(name: "active-hold-root")
    let activeHoldLeaf = try MikroObject(typeName: "active-held-leaf.object")
    try activeHoldRoot.container!.place(activeHoldLeaf, at: .origin)
    try harness.place(activeHoldRoot, at: one.coordinate)
    try harness.selectHolding(.two, for: one)
    try harness.pickup(for: one)

    let twoBackpackItem = try createContainer(name: "two-pack")
    let twoLeaf = try MikroObject(typeName: "two-pack-leaf.object")
    try twoBackpackItem.container!.place(twoLeaf, at: .origin)
    try two.backpack.container!.place(twoBackpackItem, at: Coordinate(x: 9, y: 0))

    let allObjects = harness.objects + [twoBackpackItem, twoLeaf]
    let shuffledObjects = shuffle(allObjects)
    let shuffledAgents = shuffle(harness.agents)
    let firstIndex = try ObjectLocationIndex(
      world: harness.world,
      registeredObjects: allObjects,
      agents: harness.agents
    )
    let secondIndex = try ObjectLocationIndex(
      world: harness.world,
      registeredObjects: shuffledObjects,
      agents: shuffledAgents,
      holdingRoots: { agent in HoldingNumber.allCases.map { agent.holdings[$0] } },
      maxDepth: 1024
    )

    XCTAssertEqual(
      firstIndex.commitmentMaterial(domain: "mikro.location"),
      secondIndex.commitmentMaterial(domain: "mikro.location")
    )
    XCTAssertNotEqual(
      firstIndex.commitmentMaterial(domain: "A"),
      firstIndex.commitmentMaterial(domain: "B")
    )

    let oneHeldPath = try XCTUnwrap(secondIndex.location(for: activeHoldLeaf.hash))
    XCTAssertTrue(oneHeldPath.parentPath.description.contains("agent:\(one.hash):holding:2"))
    let twoBackpackPath = try XCTUnwrap(secondIndex.location(for: twoLeaf.hash))
    XCTAssertTrue(
      twoBackpackPath.parentPath.description.contains("agent:\(two.hash):attachment:backpack"))
  }
}
