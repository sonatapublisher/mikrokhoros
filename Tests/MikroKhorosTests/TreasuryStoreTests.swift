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

final class TreasuryStoreTests: XCTestCase {
  private final class MemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var values: [String: Data] = [:]

    func put(_ secret: Data) throws -> String {
      let handle = InventoryIdentity.make()
      values[handle] = secret
      return handle
    }

    func read(handle: String) throws -> Data {
      guard InventoryIdentity.isValid(handle), let value = values[handle] else {
        throw MikroKhorosError.runtime(
          "inventory.credential_unavailable",
          "a required credential version is unavailable"
        )
      }
      return value
    }

    func contains(handle: String) -> Bool {
      InventoryIdentity.isValid(handle) && values[handle] != nil
    }

    func remove(handle: String) throws {
      values[handle] = nil
    }

    func garbageCollect(retaining handles: Set<String>) throws {
      for key in values.keys where !handles.contains(key) {
        values.removeValue(forKey: key)
      }
    }

    func overwrite(handle: String, with data: Data) {
      values[handle] = data
    }

    var handleCount: Int { values.count }
  }

  private func fixture() throws -> (
    store: TreasuryAuthorityStore,
    credentialStore: MemoryCredentialStore,
    root: URL
  ) {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("mikrokhoros-treasury-tests-\(UUID().uuidString)", isDirectory: true)
    let credentialStore = MemoryCredentialStore()
    let store = try TreasuryAuthorityStore(
      url: root.appendingPathComponent("treasury-authority.json", isDirectory: false),
      credentialStore: credentialStore
    )
    return (store: store, credentialStore: credentialStore, root: root)
  }

  private func tempRootFixture() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "mikrokhoros-treasury-temp-tests-\(UUID().uuidString)", isDirectory: true)
  }

  func testBootstrapCreatesNewAuthorityAndSigner() throws {
    let data = try fixture()
    defer { try? FileManager.default.removeItem(at: data.root) }
    let loaded = try data.store.bootstrap(confirmNoExistingEconomy: true)
    XCTAssertNotNil(loaded.signer)
    XCTAssertEqual(loaded.retainedCredentialHandle, loaded.authority.privateCredentialHandle)
    XCTAssertTrue(InventoryIdentity.isValid(loaded.retainedCredentialHandle))
    XCTAssertTrue(data.credentialStore.contains(handle: loaded.retainedCredentialHandle))
    XCTAssertTrue(FileManager.default.fileExists(atPath: data.store.url.path))
  }

  func testFileBackedBootstrapCommitsCredentialAndAuthorityTogether() throws {
    let root = tempRootFixture()
    let credentialDirectory = root.appendingPathComponent("credentials", isDirectory: true)
    let credentials = FileCredentialStore(directory: credentialDirectory)
    let store = try TreasuryAuthorityStore(
      url: root.appendingPathComponent("treasury-authority.json", isDirectory: false),
      credentialStore: credentials
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let state = try store.bootstrap(confirmNoExistingEconomy: true)

    XCTAssertNotNil(state.signer)
    XCTAssertTrue(credentials.contains(handle: state.retainedCredentialHandle))
    XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path))
    let pendingTransactions =
      (try? FileManager.default.contentsOfDirectory(
        at: root.appendingPathComponent("transactions", isDirectory: true),
        includingPropertiesForKeys: nil
      )) ?? []
    XCTAssertTrue(pendingTransactions.isEmpty)
  }

  func testPreparedCredentialAndAuthorityCommitRecoversToPriorAll() throws {
    let root = tempRootFixture()
    let credentialDirectory = root.appendingPathComponent("credentials", isDirectory: true)
    let credentials = FileCredentialStore(directory: credentialDirectory)
    let authorityURL = root.appendingPathComponent("treasury-authority.json", isDirectory: false)
    let handle = InventoryIdentity.make()
    let transaction = try ProductStateTransaction.begin(
      targets: [credentials.credentialURL(handle: handle), authorityURL],
      root: root
    )
    _ = transaction
    defer { try? FileManager.default.removeItem(at: root) }

    try credentials.put(Data("private-key".utf8), handle: handle)
    try AtomicFileStore.write(
      Data("authority".utf8),
      to: authorityURL,
      lockURL: authorityURL.appendingPathExtension("lock")
    )

    try ProductStateTransaction.recoverPending(root: root)

    XCTAssertFalse(credentials.contains(handle: handle))
    XCTAssertFalse(FileManager.default.fileExists(atPath: authorityURL.path))
  }

  func testBootstrapRequiresExplicitNoExistingEconomyConfirmation() throws {
    let data = try fixture()
    defer { try? FileManager.default.removeItem(at: data.root) }
    XCTAssertThrowsError(try data.store.bootstrap(confirmNoExistingEconomy: false)) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "treasury.bootstrap_denied")
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: data.store.url.path))
    XCTAssertEqual(data.credentialStore.handleCount, 0)
  }

  func testLoadReturnsSignerWhenCredentialMatches() throws {
    let data = try fixture()
    defer { try? FileManager.default.removeItem(at: data.root) }
    _ = try data.store.bootstrap(confirmNoExistingEconomy: true)
    let loaded = try data.store.load()
    XCTAssertNotNil(loaded.signer)
    XCTAssertEqual(loaded.retainedCredentialHandle, loaded.authority.privateCredentialHandle)
  }

  func testLoadFallsBackToVerifyOnlyWhenCredentialMissing() throws {
    let data = try fixture()
    defer { try? FileManager.default.removeItem(at: data.root) }
    let bootstrap = try data.store.bootstrap(confirmNoExistingEconomy: true)
    try data.credentialStore.remove(handle: bootstrap.retainedCredentialHandle)
    let loaded = try data.store.load()
    XCTAssertNil(loaded.signer)
    XCTAssertEqual(loaded.authority.keyID, bootstrap.authority.keyID)
    XCTAssertEqual(loaded.pinMatches, true)
  }

  func testLoadFallsBackToVerifyOnlyWhenCredentialMismatchesAuthority() throws {
    let data = try fixture()
    defer { try? FileManager.default.removeItem(at: data.root) }
    let bootstrap = try data.store.bootstrap(confirmNoExistingEconomy: true)
    data.credentialStore.overwrite(
      handle: bootstrap.retainedCredentialHandle, with: Data("bad".utf8))
    let loaded = try data.store.load()
    XCTAssertNil(loaded.signer)
    XCTAssertEqual(loaded.authority.keyID, bootstrap.authority.keyID)
    XCTAssertEqual(loaded.pinMatches, true)
  }

  func testBootstrapDoesNotRotateExistingAuthorityDocument() throws {
    let data = try fixture()
    defer { try? FileManager.default.removeItem(at: data.root) }
    let first = try data.store.bootstrap(confirmNoExistingEconomy: true)
    let second = try data.store.bootstrap(confirmNoExistingEconomy: true)
    XCTAssertEqual(first.authority.keyID, second.authority.keyID)
    XCTAssertEqual(
      first.authority.privateCredentialHandle,
      second.authority.privateCredentialHandle
    )
    XCTAssertEqual(first.retainedCredentialHandle, second.retainedCredentialHandle)
  }

  func testPinMismatchFallsBackToVerifyOnly() throws {
    let data = try fixture()
    defer { try? FileManager.default.removeItem(at: data.root) }
    let bootstrap = try data.store.bootstrap(confirmNoExistingEconomy: true)

    let correctPin = TreasuryAuthorityPin(
      keyID: bootstrap.authority.keyID,
      publicKey: bootstrap.authority.publicKey
    )
    XCTAssertNotNil(try data.store.load(pin: correctPin).signer)

    let wrongPin = TreasuryAuthorityPin(
      keyID: "bad-\(bootstrap.authority.keyID)",
      publicKey: Data(repeating: 0x00, count: 1)
    )
    let mismatched = try data.store.load(pin: wrongPin)
    XCTAssertNil(mismatched.signer)
    XCTAssertFalse(mismatched.pinMatches)
    XCTAssertEqual(mismatched.authority.keyID, bootstrap.authority.keyID)
  }

  func testBootstrapRollsBackStagedCredentialOnWriteFailure() throws {
    let root = tempRootFixture()
    let credentialDirectory = root.appendingPathComponent("credentials", isDirectory: true)
    let store = try TreasuryAuthorityStore(
      url: root.appendingPathComponent("treasury-authority.json", isDirectory: false),
      credentialStore: FileCredentialStore(directory: credentialDirectory),
      maximumBytes: 1
    )
    defer { try? FileManager.default.removeItem(at: root) }
    XCTAssertThrowsError(try store.bootstrap(confirmNoExistingEconomy: true))
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: credentialDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )) ?? []
    XCTAssertTrue(files.isEmpty)
  }
}
