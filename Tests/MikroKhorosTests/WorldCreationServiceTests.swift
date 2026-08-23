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
import MikroKhoros
import MikroKhorosServices
import XCTest

final class WorldCreationServiceTests: XCTestCase {
  private struct Fixture {
    let root: URL
    let layout: ProductLayout
    let service: WorldCreationService
  }

  private struct PathSnapshot: Equatable {
    let isDirectory: Bool
    let data: Data
  }

  private func fixture() -> Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-world-creation-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    let layout = ProductLayout(canonicalRoot: root)
    return Fixture(root: root, layout: layout, service: WorldCreationService(layout: layout))
  }

  private func configuration(for layout: ProductLayout) throws -> RuntimeConfiguration {
    try ConfigurationStore.load(from: layout.configurationURL)
  }

  private func inventory(for layout: ProductLayout) throws -> InventoryStore {
    let configuration = try configuration(for: layout)
    return try InventoryStore(
      url: layout.inventoryURL,
      packageDirectory: layout.packagesDirectoryURL,
      limits: configuration.runtime,
      runtimeRegistry: .installedCLI()
    )
  }

  private func catalog(for layout: ProductLayout) throws -> WorldCatalogStore {
    let configuration = try configuration(for: layout)
    return try WorldCatalogStore(
      url: layout.catalogURL,
      maximumBytes: configuration.runtime.maximumWorldBytes
    )
  }

  private func snapshotTree(at root: URL) throws -> [String: PathSnapshot]? {
    let manager = FileManager.default
    guard manager.fileExists(atPath: root.path) else { return nil }
    let normalizedRoot = root.standardizedFileURL.path
    var result: [String: PathSnapshot] = [:]
    guard
      let enumerator = manager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: []
      )
    else {
      return result
    }
    while let value = enumerator.nextObject() as? URL {
      let url = value.standardizedFileURL
      let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
      let path = url.path
      let relativePath: String
      if path.hasPrefix(normalizedRoot + "/") {
        relativePath = String(path.dropFirst(normalizedRoot.count + 1))
      } else {
        relativePath = url.lastPathComponent
      }
      let isDirectory = resourceValues.isDirectory == true
      result[relativePath] = PathSnapshot(
        isDirectory: isDirectory,
        data: isDirectory ? Data() : try Data(contentsOf: url, options: [.mappedIfSafe])
      )
    }
    return result
  }

  private func assertNoUnexpectedGlobalWrites(
    before: [String: PathSnapshot]?,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let after = try snapshotTree(at: MikroKhorosPaths.root)
    XCTAssertEqual(after, before, file: file, line: line)
  }

  func testInvalidNamesAreRejectedBeforeAnyProductStateIsCreated() throws {
    let names = [
      "empty": "",
      "whitespace": " \t\r ",
      "newline": "world\nname",
      "tooLong": String(repeating: "w", count: 129),
    ]
    let globalBefore = try snapshotTree(at: MikroKhorosPaths.root)

    for (label, name) in names {
      let data = fixture()
      defer { try? FileManager.default.removeItem(at: data.root) }

      XCTAssertThrowsError(try data.service.createBareWorld(name: name), label) { error in
        XCTAssertEqual(error as? WorldCreationError, .invalidName)
      }
      XCTAssertFalse(FileManager.default.fileExists(atPath: data.root.path), label)
      for url in [
        data.layout.configurationURL,
        data.layout.treasuryURL,
        data.layout.agentURL,
        data.layout.inventoryURL,
        data.layout.catalogURL,
        data.layout.worldsDirectoryURL,
      ] {
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "\(label): \(url)")
      }
    }

    try assertNoUnexpectedGlobalWrites(before: globalBefore)
  }

  func testFirstBareWorldCreationPersistsAnExactRootOnlyWorld() throws {
    let data = fixture()
    defer { try? FileManager.default.removeItem(at: data.root) }
    let globalBefore = try snapshotTree(at: MikroKhorosPaths.root)
    let name = "Research world"

    let result = try data.service.createBareWorld(name: name)
    XCTAssertEqual(result.name, name)
    XCTAssertTrue(InventoryIdentity.isValid(result.id))

    let worldURL = try data.layout.worldURL(for: result.id)
    XCTAssertEqual(
      worldURL.path,
      data.root.appendingPathComponent("worlds/\(result.id).json").path
    )
    XCTAssertTrue(FileManager.default.fileExists(atPath: worldURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: data.layout.catalogURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: data.layout.inventoryURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: data.layout.treasuryURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: data.layout.agentURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: data.layout.configurationURL.path))

    let catalog = try catalog(for: data.layout)
    let record = try XCTUnwrap(catalog.document.worlds.first(where: { $0.id == result.id }))
    XCTAssertEqual(record.name, name)
    XCTAssertEqual(catalog.document.currentWorldID, result.id)
    XCTAssertEqual(catalog.currentWorld?.id, result.id)

    let configuration = try configuration(for: data.layout)
    let document = try WorldStore.load(
      from: worldURL,
      maximumBytes: configuration.runtime.maximumWorldBytes
    )
    XCTAssertEqual(document.schemaVersion, WorldDocument.currentSchemaVersion)
    XCTAssertEqual(document.schemaVersion, 7)
    XCTAssertEqual(document.worldID, result.id)
    XCTAssertEqual(document.worldName, name)
    XCTAssertTrue(document.agents.isEmpty)
    XCTAssertTrue(document.templateApplications.isEmpty)
    XCTAssertTrue(document.events.isEmpty)
    XCTAssertTrue(document.histories.isEmpty)
    XCTAssertTrue(document.operations.isEmpty)
    XCTAssertNotNil(document.credit)
    XCTAssertEqual(document.credit?.worldID, result.id)

    let inventory = try inventory(for: data.layout)
    XCTAssertTrue(inventory.document.packages.isEmpty)
    XCTAssertTrue(inventory.document.objects.isEmpty)
    XCTAssertEqual(
      inventory.document.worldReferences,
      [result.id: WorldArtifactReferences.empty]
    )

    // Loading the saved document without a treasury signer exercises the
    // verify-only path used by projection hosts.
    let restored = try WorldRuntime(
      document: document,
      configuration: configuration,
      inventory: inventory,
      treasuryAuthority: nil
    )
    XCTAssertEqual(restored.harness.objects.map(\.hash), [result.id])
    XCTAssertTrue(restored.harness.world.container?.items.isEmpty == true)
    XCTAssertTrue(restored.harness.activeAgents.isEmpty)
    XCTAssertEqual(restored.creditService.authority, document.credit?.authority)

    let snapshot = try WorldProjectionService(layout: data.layout).snapshotExact(world: result.id)
    XCTAssertEqual(snapshot.state, .available)
    XCTAssertEqual(snapshot.currentWorldID, result.id)
    XCTAssertEqual(snapshot.selectedWorldID, result.id)
    XCTAssertEqual(snapshot.worldName, name)
    XCTAssertTrue(snapshot.primaryAgents.isEmpty)
    XCTAssertTrue(snapshot.otherAgents.isEmpty)
    XCTAssertTrue(snapshot.objects.isEmpty)
    XCTAssertEqual(snapshot.inventoryObjectCount, 0)

    let worldFiles = try FileManager.default.contentsOfDirectory(
      at: data.layout.worldsDirectoryURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    XCTAssertEqual(
      Set(worldFiles.map(\.standardizedFileURL.path)),
      Set([data.layout.catalogURL.standardizedFileURL.path, worldURL.standardizedFileURL.path])
    )
    try assertNoUnexpectedGlobalWrites(before: globalBefore)
  }

  func testRepeatedDisplayNameCreationPreservesTheFirstWorldAndTreasuryAuthority() throws {
    let data = fixture()
    defer { try? FileManager.default.removeItem(at: data.root) }
    let globalBefore = try snapshotTree(at: MikroKhorosPaths.root)
    let name = "Shared display name"

    let first = try data.service.createBareWorld(name: name)
    let firstWorldURL = try data.layout.worldURL(for: first.id)
    let firstWorldBytes = try Data(contentsOf: firstWorldURL)
    let authorityStore = try TreasuryAuthorityStore(url: data.layout.treasuryURL)
    let authorityBefore = try authorityStore.load().authority
    let treasuryCredentialURL = data.root
      .appendingPathComponent("treasury-credentials", isDirectory: true)
      .appendingPathComponent(authorityBefore.privateCredentialHandle, isDirectory: false)
    let credentialBefore = try Data(contentsOf: treasuryCredentialURL)
    let treasuryDocumentBefore = try Data(contentsOf: data.layout.treasuryURL)

    let second = try data.service.createBareWorld(name: name)
    XCTAssertEqual(second.name, name)
    XCTAssertNotEqual(second.id, first.id)
    XCTAssertEqual(try Data(contentsOf: firstWorldURL), firstWorldBytes)

    let catalog = try catalog(for: data.layout)
    XCTAssertEqual(catalog.document.currentWorldID, second.id)
    XCTAssertEqual(
      Set(catalog.document.worlds.map(\.id)),
      Set([first.id, second.id])
    )
    XCTAssertEqual(catalog.document.worlds.first(where: { $0.id == first.id })?.name, name)
    XCTAssertEqual(catalog.document.worlds.first(where: { $0.id == second.id })?.name, name)

    let authorityAfter = try authorityStore.load().authority
    XCTAssertEqual(authorityAfter.publicKey, authorityBefore.publicKey)
    XCTAssertEqual(authorityAfter.keyID, authorityBefore.keyID)
    XCTAssertEqual(
      authorityAfter.privateCredentialHandle,
      authorityBefore.privateCredentialHandle
    )
    XCTAssertEqual(try Data(contentsOf: treasuryCredentialURL), credentialBefore)
    XCTAssertEqual(try Data(contentsOf: data.layout.treasuryURL), treasuryDocumentBefore)

    let inventory = try inventory(for: data.layout)
    XCTAssertEqual(
      inventory.document.worldReferences,
      [
        first.id: WorldArtifactReferences.empty,
        second.id: WorldArtifactReferences.empty,
      ]
    )
    try assertNoUnexpectedGlobalWrites(before: globalBefore)
  }

  func testPendingProductTransactionIsRecoveredBeforeStoresLoad() throws {
    let data = fixture()
    defer { try? FileManager.default.removeItem(at: data.root) }
    let globalBefore = try snapshotTree(at: MikroKhorosPaths.root)
    try FileManager.default.createDirectory(at: data.root, withIntermediateDirectories: true)
    let target = data.root.appendingPathComponent("interrupted-state.txt", isDirectory: false)
    try Data("before".utf8).write(to: target)

    var transaction: ProductStateTransaction? = try ProductStateTransaction.begin(
      targets: [target],
      root: data.root
    )
    try Data("staged".utf8).write(to: target)
    transaction = nil
    XCTAssertNil(transaction)

    let result = try data.service.createBareWorld(name: "Recovered world")
    XCTAssertTrue(InventoryIdentity.isValid(result.id))
    XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "before")
    let transactionsURL = data.root.appendingPathComponent("transactions", isDirectory: true)
    if FileManager.default.fileExists(atPath: transactionsURL.path) {
      XCTAssertTrue(
        try FileManager.default.contentsOfDirectory(
          at: transactionsURL,
          includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles]
        ).isEmpty
      )
    }
    try assertNoUnexpectedGlobalWrites(before: globalBefore)
  }
}
