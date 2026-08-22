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

import Crypto
import Foundation

public struct TreasuryAuthorityPin: Equatable, Sendable {
  public let keyID: String
  public let publicKey: Data

  public init(keyID: String, publicKey: Data) {
    self.keyID = keyID
    self.publicKey = publicKey
  }

  public func matches(_ authority: TreasuryAuthorityDocument) -> Bool {
    keyID == authority.keyID && publicKey == authority.publicKey
  }
}

/// Immutable authority material shared by independently-created world runtimes.
/// `CreditRecordSigner` wraps an immutable Swift Crypto private key value; all
/// mutation and persistence remains serialized by the product state lock.
public struct TreasuryAuthorityState: @unchecked Sendable {
  public let authority: TreasuryAuthorityDocument
  public let signer: CreditRecordSigner?
  public let pinMatches: Bool

  public var retainedCredentialHandle: String {
    authority.privateCredentialHandle
  }
}

public final class TreasuryAuthorityStore: @unchecked Sendable {
  public static let defaultMaximumBytes = 1_048_576
  public static var defaultURL: URL {
    MikroKhorosPaths.root
      .appendingPathComponent("treasury-authority.json", isDirectory: false)
  }
  public static var defaultCredentialDirectory: URL {
    MikroKhorosPaths.root
      .appendingPathComponent("treasury-credentials", isDirectory: true)
  }

  public let url: URL
  public let credentialStore: any CredentialStore
  public let maximumBytes: Int
  private let dateProvider: () -> Date

  /// This store mutates root-level treasury state and therefore must be invoked
  /// while the caller holds `ProductStateLock` for the full method duration.
  /// The lock is not acquired here to avoid call-site deadlocks.
  public init(
    url: URL = defaultURL,
    credentialStore: (any CredentialStore)? = nil,
    maximumBytes: Int = defaultMaximumBytes,
    dateProvider: @escaping () -> Date = Date.init
  ) throws {
    guard maximumBytes > 0 else {
      throw MikroKhorosError.configuration("the treasury authority byte limit must be positive")
    }
    self.url = url
    self.credentialStore =
      credentialStore
      ?? FileCredentialStore(
        directory: url == Self.defaultURL
          ? Self.defaultCredentialDirectory
          : url.deletingLastPathComponent()
            .appendingPathComponent("treasury-credentials", isDirectory: true)
      )
    self.maximumBytes = maximumBytes
    self.dateProvider = dateProvider
  }

  /// Loads the treasury authority document if present.
  /// `nil` signer indicates verify-only mode.
  public func load(pin: TreasuryAuthorityPin? = nil) throws -> TreasuryAuthorityState {
    let authority = try Self.loadDocument(from: url, maximumBytes: maximumBytes)
    return try resolve(authority: authority, pin: pin)
  }

  /// Loads the existing treasury authority, or creates one when absent.
  /// Creation requires explicit confirmation that no economy state references
  /// already exist.
  /// This method never rotates, replaces, or re-seeds an existing document.
  public func bootstrap(confirmNoExistingEconomy: Bool, pin: TreasuryAuthorityPin? = nil)
    throws -> TreasuryAuthorityState
  {
    if FileManager.default.fileExists(atPath: url.path) {
      return try load(pin: pin)
    }
    guard confirmNoExistingEconomy else {
      throw MikroKhorosError.runtime(
        "treasury.bootstrap_denied",
        "refusing to bootstrap treasury authority while economy references may exist",
        details: ["path": url.path]
      )
    }

    let keyPair = Curve25519.Signing.PrivateKey()
    if let fileCredentials = credentialStore as? FileCredentialStore {
      let handle = InventoryIdentity.make()
      let authority = try TreasuryAuthorityDocument(
        publicKey: keyPair.publicKey.rawRepresentation,
        privateCredentialHandle: handle,
        createdAt: dateProvider()
      )
      let credentialURL = fileCredentials.credentialURL(handle: handle)
      let transaction = try ProductStateTransaction.begin(
        targets: [credentialURL, url],
        root: url.deletingLastPathComponent()
      )
      do {
        try fileCredentials.put(keyPair.rawRepresentation, handle: handle)
        try writeDocument(authority)
        try transaction.commit()
        return try resolve(authority: authority, pin: pin)
      } catch {
        try? transaction.rollback()
        throw error
      }
    } else {
      let handle = try credentialStore.put(keyPair.rawRepresentation)
      do {
        let authority = try TreasuryAuthorityDocument(
          publicKey: keyPair.publicKey.rawRepresentation,
          privateCredentialHandle: handle,
          createdAt: dateProvider()
        )
        try persist(authority)
        return try resolve(authority: authority, pin: pin)
      } catch {
        try? credentialStore.remove(handle: handle)
        throw error
      }
    }
  }

  private func persist(_ authority: TreasuryAuthorityDocument) throws {
    let transaction = try ProductStateTransaction.begin(
      targets: [url],
      root: url.deletingLastPathComponent()
    )
    do {
      try writeDocument(authority)
      try transaction.commit()
    } catch {
      try? transaction.rollback()
      throw error
    }
  }

  private func writeDocument(_ authority: TreasuryAuthorityDocument) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(authority)
    guard data.count <= maximumBytes else {
      throw MikroKhorosError.runtime(
        "treasury.document_too_large",
        "the treasury authority document exceeds the configured byte limit",
        details: ["limit": String(maximumBytes)]
      )
    }
    try AtomicFileStore.write(data, to: url, lockURL: url.appendingPathExtension("lock"))
  }

  private func resolve(
    authority: TreasuryAuthorityDocument,
    pin: TreasuryAuthorityPin? = nil
  ) throws -> TreasuryAuthorityState {
    if let pin, !pin.matches(authority) {
      return TreasuryAuthorityState(authority: authority, signer: nil, pinMatches: false)
    }
    guard let keyData = try? credentialStore.read(handle: authority.privateCredentialHandle) else {
      return TreasuryAuthorityState(authority: authority, signer: nil, pinMatches: true)
    }
    do {
      let signer = try CreditRecordSigner(authority: authority, privateKeyData: keyData)
      return TreasuryAuthorityState(authority: authority, signer: signer, pinMatches: true)
    } catch {
      return TreasuryAuthorityState(authority: authority, signer: nil, pinMatches: true)
    }
  }

  private static func loadDocument(from url: URL, maximumBytes: Int) throws
    -> TreasuryAuthorityDocument
  {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw MikroKhorosError.runtime(
        "treasury.authority_not_found",
        "the treasury authority document is not available"
      )
    }
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      if let size = values.fileSize, size > maximumBytes {
        throw MikroKhorosError.persistence(
          "the treasury authority exceeds the configured byte limit")
      }
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(TreasuryAuthorityDocument.self, from: data)
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.persistence("the treasury authority JSON is invalid")
    }
  }
}
