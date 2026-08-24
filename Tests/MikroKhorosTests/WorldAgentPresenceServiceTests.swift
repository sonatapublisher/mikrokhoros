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
import MikroKhoros
import MikroKhorosServices
import XCTest

final class WorldAgentPresenceServiceTests: XCTestCase {
  func testOptionsReportExactPresenceStates() throws {
    let fixture = try presenceFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let agents = try AgentStore(
      url: fixture.layout.agentURL,
      maximumBytes: fixture.configuration.runtime.maximumAgentStoreBytes
    )
    let available = try agents.create(name: "Available", maximumActionsPerResponse: 6)
    let presentSource = try agents.create(name: "Present", maximumActionsPerResponse: 6)
    let elsewhere = try agents.create(name: "Elsewhere", maximumActionsPerResponse: 6)
    _ = try agents.assign(elsewhere.id, toWorld: fixture.otherWorldID)
    try agents.save()
    _ = try fixture.service.addAgent(
      worldID: fixture.worldID,
      agentID: presentSource.id,
      coordinate: Coordinate(x: 3, y: 2),
      autoAdapt: false
    )

    let options = try fixture.service.options(worldID: fixture.worldID)
    XCTAssertEqual(options.worldID, fixture.worldID)
    XCTAssertEqual(options.agents.count, 3)

    let byID = Dictionary(uniqueKeysWithValues: options.agents.map { ($0.id, $0.state) })
    XCTAssertEqual(byID[available.id], .available)
    XCTAssertEqual(byID[presentSource.id], .present)
    XCTAssertEqual(byID[elsewhere.id], .assignedElsewhere)
  }

  func testOptionsUseADeterministicBoundedAgentPrefix() throws {
    let fixture = try presenceFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let agents = try AgentStore(
      url: fixture.layout.agentURL,
      maximumBytes: fixture.configuration.runtime.maximumAgentStoreBytes
    )
    _ = try agents.create(name: "First", maximumActionsPerResponse: 6)
    _ = try agents.create(name: "Second", maximumActionsPerResponse: 6)
    try agents.save()
    let expectedID = try XCTUnwrap(agents.allAgents().first?.id)

    let options = try WorldAgentPresenceService(layout: fixture.layout, optionLimit: 1)
      .options(worldID: fixture.worldID)
    XCTAssertEqual(options.agents.count, 1)
    XCTAssertEqual(options.agents.map(\.id), [expectedID])
  }

  func testAddAgentPersistsAssignmentAndWorldProjection() throws {
    let fixture = try presenceFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let agents = try AgentStore(
      url: fixture.layout.agentURL,
      maximumBytes: fixture.configuration.runtime.maximumAgentStoreBytes
    )
    let source = try agents.create(name: "Adder", maximumActionsPerResponse: 6)
    try agents.save()
    let coordinate = Coordinate(x: 11, y: -4)

    let result = try fixture.service.addAgent(
      worldID: fixture.worldID,
      agentID: source.id,
      coordinate: coordinate,
      autoAdapt: false
    )
    XCTAssertEqual(result.worldID, fixture.worldID)
    XCTAssertEqual(result.agentID, source.id)
    XCTAssertEqual(result.name, source.name)
    XCTAssertEqual(result.requested, WorldCoordinateSnapshot(coordinate))
    XCTAssertEqual(result.actual, WorldCoordinateSnapshot(coordinate))
    XCTAssertFalse(result.adapted)

    let updatedAgents = try AgentStore(
      url: fixture.layout.agentURL,
      maximumBytes: fixture.configuration.runtime.maximumAgentStoreBytes
    )
    let updatedSource = try updatedAgents.resolve(source.id)
    XCTAssertEqual(updatedSource.worldAssignment?.worldID, fixture.worldID)

    let projection = try WorldProjectionService(layout: fixture.layout).snapshotExact(
      world: fixture.worldID)
    let projected = (projection.primaryAgents + projection.otherAgents).first(where: {
      $0.id == source.id
    })
    XCTAssertNotNil(projected)
    XCTAssertEqual(projected?.coordinate, WorldCoordinateSnapshot(coordinate))
  }

  func testAddAgentRejectsAlreadyPresentWithoutMutatingState() throws {
    let fixture = try presenceFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let agents = try AgentStore(
      url: fixture.layout.agentURL,
      maximumBytes: fixture.configuration.runtime.maximumAgentStoreBytes
    )
    let source = try agents.create(name: "Resident", maximumActionsPerResponse: 6)
    try agents.save()
    _ = try fixture.service.addAgent(
      worldID: fixture.worldID,
      agentID: source.id,
      coordinate: .origin,
      autoAdapt: false
    )

    let beforeFiles = try fileSnapshot(urls: [
      fixture.layout.agentURL, fixture.layout.inventoryURL, fixture.worldURL,
    ])
    XCTAssertThrowsError(
      try fixture.service.addAgent(
        worldID: fixture.worldID, agentID: source.id, coordinate: .origin, autoAdapt: false)
    ) { error in
      XCTAssertEqual(error as? WorldAgentPresenceError, .alreadyPresent)
    }
    XCTAssertEqual(
      try fileSnapshot(urls: [
        fixture.layout.agentURL, fixture.layout.inventoryURL, fixture.worldURL,
      ]), beforeFiles)
  }

  func testAddAgentRejectsAssignedElsewhereWithoutMutatingState() throws {
    let fixture = try presenceFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let agents = try AgentStore(
      url: fixture.layout.agentURL,
      maximumBytes: fixture.configuration.runtime.maximumAgentStoreBytes
    )
    let source = try agents.create(name: "Delegated", maximumActionsPerResponse: 6)
    _ = try agents.assign(source.id, toWorld: fixture.otherWorldID)
    try agents.save()
    let beforeFiles = try fileSnapshot(urls: [
      fixture.layout.agentURL, fixture.layout.inventoryURL, fixture.worldURL,
    ])

    XCTAssertThrowsError(
      try fixture.service.addAgent(
        worldID: fixture.worldID, agentID: source.id, coordinate: .origin, autoAdapt: false)
    ) { error in
      XCTAssertEqual(error as? WorldAgentPresenceError, .assignedElsewhere)
    }
    XCTAssertEqual(
      try fileSnapshot(urls: [
        fixture.layout.agentURL, fixture.layout.inventoryURL, fixture.worldURL,
      ]), beforeFiles)
  }

  private struct PresenceFixture {
    let root: URL
    let layout: ProductLayout
    let service: WorldAgentPresenceService
    let worldID: String
    let otherWorldID: String
    let worldURL: URL
    let configuration: RuntimeConfiguration
  }

  private func presenceFixture() throws -> PresenceFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-world-agent-presence-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    let layout = ProductLayout(canonicalRoot: root)
    let worldService = WorldCreationService(layout: layout)
    let primary = try worldService.createBareWorld(name: "Primary presence world")
    let secondary = try worldService.createBareWorld(name: "Secondary presence world")
    let configuration = try ConfigurationStore.load(from: layout.configurationURL)
    return PresenceFixture(
      root: root,
      layout: layout,
      service: WorldAgentPresenceService(layout: layout),
      worldID: primary.id,
      otherWorldID: secondary.id,
      worldURL: try layout.worldURL(for: primary.id),
      configuration: configuration
    )
  }

  private func fileSnapshot(urls: [URL]) throws -> [String: Data] {
    return try Dictionary(
      uniqueKeysWithValues: urls.compactMap { url in
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (url.path, try Data(contentsOf: url))
      })
  }
}
