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

/// A crash-recoverable transaction around the product documents changed by one
/// template operation. Callers must hold ``ProductStateLock`` for the complete
/// lifetime of the transaction.
public final class ProductStateTransaction: @unchecked Sendable {
  private static let schemaVersion = 1
  private static let directoryName = "transactions"
  private static let manifestName = "manifest.json"
  private static let maximumManifestBytes = 1_048_576

  private enum State: String, Codable {
    case prepared
    case committed
  }

  private struct Entry: Codable {
    let targetPath: String
    let existed: Bool
    let backupName: String?
    let priorHash: String?
    var stagedHash: String?
  }

  private struct Manifest: Codable {
    let schema: Int
    let id: String
    var state: State
    let createdAt: Date
    /// Exact runtime identities for world documents affected by this transaction.
    /// Nil keeps recovery compatible with manifests created before world catalogs.
    let affectedWorldIDs: [String]?
    var entries: [Entry]
  }

  private let directory: URL
  private var manifest: Manifest
  private var finished = false

  private init(directory: URL, manifest: Manifest) {
    self.directory = directory
    self.manifest = manifest
  }

  public static func begin(
    targets: [URL],
    affectedWorldIDs: Set<String> = [],
    root: URL = MikroKhorosPaths.root
  ) throws -> ProductStateTransaction {
    let normalized = targets.map(\.standardizedFileURL)
    guard !normalized.isEmpty,
      Set(normalized.map(\.path)).count == normalized.count
    else {
      throw recoveryFailure("the product transaction has invalid targets")
    }
    guard affectedWorldIDs.allSatisfy(InventoryIdentity.isValid) else {
      throw recoveryFailure("the product transaction has an invalid world identity")
    }

    let manager = FileManager.default
    let transactions = root.appendingPathComponent(directoryName, isDirectory: true)
    let id = InventoryIdentity.make()
    let directory = transactions.appendingPathComponent(id, isDirectory: true)
    do {
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
      #if !os(Windows)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      #endif
      var entries: [Entry] = []
      for (index, target) in normalized.enumerated() {
        let exists = manager.fileExists(atPath: target.path)
        if exists {
          let backupName = "prior-\(index).bin"
          let backup = directory.appendingPathComponent(backupName, isDirectory: false)
          let data = try Data(contentsOf: target, options: [.mappedIfSafe])
          try AtomicFileStore.write(
            data,
            to: backup,
            lockURL: backup.appendingPathExtension("lock")
          )
          entries.append(
            Entry(
              targetPath: target.path,
              existed: true,
              backupName: backupName,
              priorHash: SHA256Digest.hex(data),
              stagedHash: nil
            )
          )
        } else {
          entries.append(
            Entry(
              targetPath: target.path,
              existed: false,
              backupName: nil,
              priorHash: nil,
              stagedHash: nil
            )
          )
        }
      }
      let manifest = Manifest(
        schema: schemaVersion,
        id: id,
        state: .prepared,
        createdAt: Date(),
        affectedWorldIDs: affectedWorldIDs.isEmpty ? nil : affectedWorldIDs.sorted(),
        entries: entries
      )
      try writeManifest(manifest, in: directory)
      return ProductStateTransaction(directory: directory, manifest: manifest)
    } catch let error as MikroKhorosError {
      try? manager.removeItem(at: directory)
      throw error
    } catch {
      try? manager.removeItem(at: directory)
      throw recoveryFailure("could not prepare the product transaction")
    }
  }

  public func commit() throws {
    guard !finished else { return }
    do {
      manifest.entries = try manifest.entries.map { entry in
        var updated = entry
        let target = URL(fileURLWithPath: entry.targetPath, isDirectory: false)
        updated.stagedHash =
          FileManager.default.fileExists(atPath: target.path)
          ? SHA256Digest.hex(try Data(contentsOf: target, options: [.mappedIfSafe]))
          : nil
        return updated
      }
      manifest.state = .committed
      try Self.writeManifest(manifest, in: directory)
      try FileManager.default.removeItem(at: directory)
      finished = true
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw Self.recoveryFailure("could not commit the product transaction")
    }
  }

  public func rollback() throws {
    guard !finished else { return }
    try Self.restore(manifest, from: directory)
    try FileManager.default.removeItem(at: directory)
    finished = true
  }

  /// Completes or rolls back any transaction left by an interrupted process.
  /// This must run while the caller holds ``ProductStateLock`` and before any
  /// persistent product document is loaded.
  public static func recoverPending(root: URL = MikroKhorosPaths.root) throws {
    let manager = FileManager.default
    let transactions = root.appendingPathComponent(directoryName, isDirectory: true)
    guard manager.fileExists(atPath: transactions.path) else { return }
    do {
      let directories = try manager.contentsOfDirectory(
        at: transactions,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      ).sorted { $0.lastPathComponent < $1.lastPathComponent }
      for directory in directories {
        guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
          try manager.removeItem(at: directory)
          continue
        }
        let manifestURL = directory.appendingPathComponent(manifestName, isDirectory: false)
        guard manager.fileExists(atPath: manifestURL.path) else {
          // begin() exposes no product mutation until this manifest exists.
          try manager.removeItem(at: directory)
          continue
        }
        let manifest = try readManifest(from: manifestURL, directory: directory)
        switch manifest.state {
        case .prepared:
          try restore(manifest, from: directory)
        case .committed:
          try validateCommitted(manifest)
        }
        try manager.removeItem(at: directory)
      }
      if (try? manager.contentsOfDirectory(atPath: transactions.path).isEmpty) == true {
        try? manager.removeItem(at: transactions)
      }
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw recoveryFailure("could not recover an interrupted product transaction")
    }
  }

  private static func readManifest(from url: URL, directory: URL) throws -> Manifest {
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    guard let size = values.fileSize, size > 0, size <= maximumManifestBytes else {
      throw recoveryFailure("the product transaction manifest has an invalid size")
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let manifest = try decoder.decode(Manifest.self, from: Data(contentsOf: url))
    let worldIDsAreValid =
      manifest.affectedWorldIDs.map { ids in
        Set(ids).count == ids.count && ids.allSatisfy(InventoryIdentity.isValid)
      } ?? true
    guard manifest.schema == schemaVersion,
      InventoryIdentity.isValid(manifest.id),
      manifest.id == directory.lastPathComponent,
      !manifest.entries.isEmpty,
      Set(manifest.entries.map(\.targetPath)).count == manifest.entries.count,
      worldIDsAreValid,
      manifest.entries.allSatisfy(validEntry)
    else {
      throw recoveryFailure("the product transaction manifest is invalid")
    }
    return manifest
  }

  private static func validEntry(_ entry: Entry) -> Bool {
    let target = URL(fileURLWithPath: entry.targetPath, isDirectory: false)
    guard target.path == target.standardizedFileURL.path else {
      return false
    }
    #if os(Windows)
      let portablePath = entry.targetPath.replacingOccurrences(of: "\\", with: "/")
      guard
        portablePath.range(
          of: #"^/?[A-Za-z]:/"#,
          options: .regularExpression
        ) != nil || portablePath.hasPrefix("//")
      else { return false }
    #else
      guard target.path.hasPrefix("/") else { return false }
    #endif
    if entry.existed {
      return entry.backupName?.range(of: #"^prior-[0-9]+\.bin$"#, options: .regularExpression)
        != nil && entry.priorHash?.count == 64
    }
    return entry.backupName == nil && entry.priorHash == nil
  }

  private static func restore(_ manifest: Manifest, from directory: URL) throws {
    let manager = FileManager.default
    do {
      for entry in manifest.entries {
        let target = URL(fileURLWithPath: entry.targetPath, isDirectory: false)
        if entry.existed {
          guard let backupName = entry.backupName else {
            throw recoveryFailure("a product transaction backup is missing")
          }
          let backup = directory.appendingPathComponent(backupName, isDirectory: false)
          let data = try Data(contentsOf: backup, options: [.mappedIfSafe])
          guard SHA256Digest.hex(data) == entry.priorHash else {
            throw recoveryFailure("a product transaction backup failed integrity validation")
          }
          try AtomicFileStore.write(
            data,
            to: target,
            lockURL: target.appendingPathExtension("lock")
          )
        } else if manager.fileExists(atPath: target.path) {
          try manager.removeItem(at: target)
        }
      }
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw recoveryFailure("could not restore an interrupted product transaction")
    }
  }

  private static func validateCommitted(_ manifest: Manifest) throws {
    for entry in manifest.entries {
      let target = URL(fileURLWithPath: entry.targetPath, isDirectory: false)
      let exists = FileManager.default.fileExists(atPath: target.path)
      guard exists == (entry.stagedHash != nil) else {
        throw recoveryFailure("a committed product transaction is incomplete")
      }
      if let stagedHash = entry.stagedHash {
        let data = try Data(contentsOf: target, options: [.mappedIfSafe])
        guard SHA256Digest.hex(data) == stagedHash else {
          throw recoveryFailure("a committed product transaction failed integrity validation")
        }
      }
    }
  }

  private static func writeManifest(_ manifest: Manifest, in directory: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(manifest)
    guard data.count <= maximumManifestBytes else {
      throw recoveryFailure("the product transaction manifest is too large")
    }
    let url = directory.appendingPathComponent(manifestName, isDirectory: false)
    try AtomicFileStore.write(data, to: url, lockURL: url.appendingPathExtension("lock"))
  }

  private static func recoveryFailure(_ message: String) -> MikroKhorosError {
    MikroKhorosError.runtime(
      "world_template.transaction_recovery_failed",
      message,
      suggestions: ["run `khoros doctor` after restoring access to the affected paths"]
    )
  }
}
