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

private struct CreditSnapshotCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

/// The actor used by the credit service when authorizing a ledger operation.
/// Model and object text never becomes an actor; callers must provide one of
/// these runtime-owned values.
public enum CreditActor: String, Codable, Sendable {
  case human
  case system
  case agent
}

public struct WalletRegistration: Codable, Equatable, Sendable {
  public let walletID: String
  public let agentID: String
  public let worldID: String
  public let issuerID: String
  public let backpackID: String
  public let coordinate: Coordinate
  public private(set) var mode: WalletMode

  public init(
    walletID: String,
    agentID: String,
    worldID: String,
    issuerID: String,
    backpackID: String,
    coordinate: Coordinate = Coordinate(x: 4, y: 0),
    mode: WalletMode = .finite
  ) throws {
    guard !walletID.isEmpty, !agentID.isEmpty, !worldID.isEmpty, !issuerID.isEmpty,
      !backpackID.isEmpty
    else {
      throw MikroKhorosError.persistence("wallet registration contains an empty identity")
    }
    guard coordinate == Coordinate(x: 4, y: 0) else {
      throw MikroKhorosError.persistence(
        "a registered wallet must be bound to backpack coordinate (4,0)"
      )
    }
    self.walletID = walletID
    self.agentID = agentID
    self.worldID = worldID
    self.issuerID = issuerID
    self.backpackID = backpackID
    self.coordinate = coordinate
    self.mode = mode
  }

  mutating func setMode(_ value: WalletMode) { mode = value }
}

/// A proposed bearer transition for one registered wallet. Transitions are
/// collected and emitted as one canonical zero-delta custody record so a
/// container move cannot publish only part of its wallet subtree.
public struct WalletCustodyTransition: Equatable, Sendable {
  public let walletID: String
  public let oldOwner: String?
  public let newOwner: String?
  public let oldLocationCommitment: String
  public let newLocationCommitment: String
  public let oldCustodyCommitment: String?

  public init(
    walletID: String,
    oldOwner: String?,
    newOwner: String?,
    oldLocationCommitment: String,
    newLocationCommitment: String,
    oldCustodyCommitment: String? = nil
  ) {
    self.walletID = walletID
    self.oldOwner = oldOwner
    self.newOwner = newOwner
    self.oldLocationCommitment = oldLocationCommitment
    self.newLocationCommitment = newLocationCommitment
    self.oldCustodyCommitment = oldCustodyCommitment
  }
}

/// Persisted credit metadata. Balances and modes are deliberately absent from
/// this value: they are derived by replaying the signed chain. Registrations
/// are encoded without their convenience `mode` field for the same reason.
public struct CreditServiceSnapshot: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let worldID: String
  public let authority: TreasuryAuthorityDocument
  public let chain: [SignedCreditRecord]

  public init(
    schemaVersion: Int = Self.currentSchemaVersion,
    worldID: String,
    authority: TreasuryAuthorityDocument,
    chain: [SignedCreditRecord] = []
  ) {
    self.schemaVersion = schemaVersion
    self.worldID = worldID
    self.authority = authority
    self.chain = chain
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion
    case worldID
    case authority
    case chain
    case registrations
    case idempotencyKeys
    case balances
  }

  public init(from decoder: Decoder) throws {
    let raw = try decoder.container(keyedBy: CreditSnapshotCodingKey.self)
    let allowed = Set(["schemaVersion", "worldID", "authority", "chain"])
    if let unknown = raw.allKeys.first(where: { !allowed.contains($0.stringValue) }) {
      if ["balances", "registrations", "idempotencyKeys"].contains(unknown.stringValue) {
        throw MikroKhorosError.persistence(
          "credit snapshot contains forbidden independently writable derived state"
        )
      }
      throw MikroKhorosError.persistence("credit snapshot contains an unknown field")
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let known: Set<CodingKeys> = [.schemaVersion, .worldID, .authority, .chain]
    if let unknown = Set(container.allKeys).subtracting(known).first {
      if unknown == .balances || unknown == .registrations || unknown == .idempotencyKeys {
        throw MikroKhorosError.persistence(
          "credit snapshot contains forbidden independently writable derived state"
        )
      }
      throw MikroKhorosError.persistence("credit snapshot contains an unknown field")
    }
    let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    guard schemaVersion == Self.currentSchemaVersion else {
      throw MikroKhorosError.persistence(
        "unsupported credit snapshot schema version found \(schemaVersion); required \(Self.currentSchemaVersion)"
      )
    }
    self.schemaVersion = schemaVersion
    self.worldID = try container.decode(String.self, forKey: .worldID)
    self.authority = try container.decode(TreasuryAuthorityDocument.self, forKey: .authority)
    self.chain = try container.decodeIfPresent([SignedCreditRecord].self, forKey: .chain) ?? []
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(worldID, forKey: .worldID)
    try container.encode(authority, forKey: .authority)
    try container.encode(chain, forKey: .chain)
  }

  /// A checkpoint that carries only the pinned authority. Registrations,
  /// balances, modes, custody, and idempotency are all replay-derived.
  func withoutDerivedState() -> CreditServiceSnapshot {
    CreditServiceSnapshot(
      schemaVersion: schemaVersion,
      worldID: worldID,
      authority: authority,
      chain: []
    )
  }
}

/// A deterministic world-local accounting service. It owns all mutable wallet
/// state; WalletObject is only the native surface that delegates to this
/// service. Every mutation is represented by a signed record and applied only
/// after the record has been signed and verified.
public final class CreditService: @unchecked Sendable {
  public let worldID: String
  public let authority: TreasuryAuthorityDocument
  public let issuerID: String

  private var signer: CreditRecordSigner?
  private var registrationsByWallet: [String: WalletRegistration]
  private var balancesByWallet: [String: CreditBalance]
  private var chainRecords: [SignedCreditRecord]
  private var idempotency: Set<String>
  /// Hash of the latest signed registration/custody record for each wallet.
  private var custodyCommitments: [String: String]
  /// Physical location commitment carried by the latest signed registration
  /// or owner-changing custody record. Same-owner moves are intentionally not
  /// signed, so the live graph—not this historical projection—is authoritative
  /// for the Wallet's present location.
  private var locationCommitments: [String: String]
  private var custodyOwners: [String: String?]
  private var issuanceCommitments: [String: String]
  private var treasuryBalance: CreditBalance

  public init(
    worldID: String,
    privateCredentialHandle: String = "product-root-treasury",
    privateKeyData: Data? = nil,
    snapshot: CreditServiceSnapshot? = nil,
    authority pinnedAuthority: TreasuryAuthorityDocument? = nil,
    authorityState: TreasuryAuthorityState? = nil
  ) throws {
    guard !worldID.isEmpty else {
      throw MikroKhorosError.persistence("credit service requires a world identity")
    }

    let resolvedAuthority: TreasuryAuthorityDocument
    if let snapshot {
      guard snapshot.schemaVersion == CreditServiceSnapshot.currentSchemaVersion,
        snapshot.worldID == worldID
      else {
        throw MikroKhorosError.persistence("credit snapshot world or schema does not match")
      }
      resolvedAuthority = snapshot.authority
      if let pinnedAuthority, pinnedAuthority != resolvedAuthority {
        throw MikroKhorosError.persistence("credit authority pin does not match the world snapshot")
      }
      if let authorityState, authorityState.authority != resolvedAuthority {
        throw MikroKhorosError.persistence(
          "treasury authority state does not match the world snapshot")
      }
    } else if let pinnedAuthority {
      resolvedAuthority = pinnedAuthority
    } else if let authorityState {
      resolvedAuthority = authorityState.authority
    } else {
      throw MikroKhorosError.runtime(
        "wallet.authority_unavailable",
        "the treasury authority is not configured; the world is verify-only"
      )
    }

    self.worldID = worldID
    self.authority = resolvedAuthority
    // `issuerID` on a registration is genesis provenance, not the treasury
    // signing key. The latter remains available as `authority.keyID`.
    self.issuerID = resolvedAuthority.keyID
    if let authorityState, authorityState.authority == resolvedAuthority {
      self.signer = authorityState.signer
    } else if let privateKeyData {
      self.signer = try CreditRecordSigner(
        authority: resolvedAuthority,
        privateKeyData: privateKeyData
      )
    } else {
      self.signer = nil
    }
    self.registrationsByWallet = [:]
    self.balancesByWallet = [:]
    self.chainRecords = []
    self.idempotency = []
    self.custodyCommitments = [:]
    self.locationCommitments = [:]
    self.custodyOwners = [:]
    self.issuanceCommitments = [:]
    self.treasuryBalance = .zero

    if let snapshot {
      try applyRecords(snapshot.chain)
    }
    try validateChain()
    try validateExposureInvariant()
  }

  /// Verify-only construction is useful while loading a world when its private
  /// credential is intentionally unavailable. Mutations then fail closed, but
  /// signed records remain inspectable.
  public convenience init(verifyOnly snapshot: CreditServiceSnapshot) throws {
    try self.init(
      worldID: snapshot.worldID,
      privateCredentialHandle: snapshot.authority.privateCredentialHandle,
      privateKeyData: nil,
      snapshot: snapshot,
      authority: snapshot.authority
    )
    signer = nil
  }

  public var registrations: [WalletRegistration] {
    registrationsByWallet.values.sorted { $0.walletID < $1.walletID }
  }

  public var chain: [SignedCreditRecord] { chainRecords }

  var canSignMutations: Bool { signer != nil }

  /// Derived balances are intentionally read-only and never part of a snapshot.
  public var balances: [String: CreditBalance] { balancesByWallet }

  public func registration(for walletID: String) -> WalletRegistration? {
    registrationsByWallet[walletID]
  }

  public func balance(for walletID: String) throws -> CreditBalance {
    guard registrationsByWallet[walletID] != nil else { throw unknownWallet() }
    return try balancesByWallet[walletID] ?? CreditBalance(minorUnits: 0)
  }

  public func mode(for walletID: String) throws -> WalletMode {
    guard let registration = registrationsByWallet[walletID] else { throw unknownWallet() }
    return registration.mode
  }

  public func treasuryBalanceValue() -> CreditBalance { treasuryBalance }

  @discardableResult
  public func register(
    walletID: String,
    agentID: String,
    backpackID: String,
    issuerID: String? = nil,
    initialBalance: CreditBalance = .zero,
    mode: WalletMode = .finite,
    locationCommitment: String? = nil,
    operationID: String = CreditService.makeID(),
    actionIndex: UInt64 = 0,
    actor: CreditActor = .system
  ) throws -> WalletRegistration {
    if let record = existingRecord(operationID: operationID, actionIndex: actionIndex) {
      guard record.unsigned.kind == .registration,
        record.unsigned.accounts == [walletID],
        record.unsigned.issuanceAgentID == agentID,
        record.unsigned.issuanceBackpackID == backpackID,
        record.unsigned.issuanceCoordinate == Coordinate(x: 4, y: 0),
        record.unsigned.issuanceLocationCommitment == (locationCommitment ?? "\(backpackID)@(4,0)"),
        record.unsigned.actor == actor.rawValue,
        record.unsigned.owner == agentID
      else { throw operationConflict() }
      return try requireRegistered(walletID)
    }
    if let existing = registrationsByWallet[walletID] {
      throw MikroKhorosError.persistence(
        "wallet \(existing.walletID) is already registered by another operation"
      )
    }
    guard initialBalance == .zero else {
      throw MikroKhorosError.runtime(
        "wallet.initial_balance_denied",
        "new wallets always begin at a zero balance"
      )
    }
    guard signer != nil else { throw missingSigner() }
    guard issuerID == nil || issuerID == agentID else {
      throw MikroKhorosError.persistence(
        "wallet issuance provenance must name the issuing genesis agent"
      )
    }
    guard mode == .finite else {
      throw MikroKhorosError.runtime(
        "wallet.registration_mode_invalid",
        "new wallets register in finite mode; mode changes are separate signed operations"
      )
    }
    _ = try WalletRegistration(
      walletID: walletID,
      agentID: agentID,
      worldID: worldID,
      issuerID: issuerID ?? agentID,
      backpackID: backpackID,
      mode: .finite
    )
    let commitment = locationCommitment ?? "\(backpackID)@(4,0)"
    try appendRecord(
      kind: .registration,
      operationID: operationID,
      actionIndex: actionIndex,
      transactionID: transactionID(operationID: operationID, actionIndex: actionIndex),
      accounts: [walletID],
      amounts: [.zero],
      postBalances: [.zero],
      treasuryDelta: .zero,
      treasuryBalance: treasuryBalance,
      issuanceAgentID: agentID,
      issuanceBackpackID: backpackID,
      issuanceCoordinate: Coordinate(x: 4, y: 0),
      issuanceLocationCommitment: commitment,
      mode: .finite,
      actor: actor.rawValue,
      owner: agentID,
      note: "wallet registration"
    )
    return try requireRegistered(walletID)
  }

  public func setMode(
    walletID: String,
    mode: WalletMode,
    actor: CreditActor,
    operationID: String = CreditService.makeID(),
    actionIndex: UInt64 = 0,
    causalObjectIDs: [String] = [],
    causalFunctionIDs: [String] = [],
    note: String = ""
  ) throws {
    guard actor == .human || actor == .system else {
      throw MikroKhorosError.runtime(
        "wallet.mode_denied", "only the human or system may change wallet mode")
    }
    _ = try requireRegistered(walletID)
    if let record = existingRecord(operationID: operationID, actionIndex: actionIndex) {
      guard record.unsigned.kind == .modeChange,
        record.unsigned.accounts == [walletID],
        record.unsigned.mode == mode,
        record.unsigned.actor == actor.rawValue,
        record.unsigned.causalObjectIDs == causalObjectIDs.sorted(),
        record.unsigned.causalFunctionIDs == causalFunctionIDs.sorted(),
        record.unsigned.note == note
      else { throw operationConflict() }
      return
    }
    guard signer != nil else { throw missingSigner() }
    let current = try balance(for: walletID)
    try appendRecord(
      kind: .modeChange,
      operationID: operationID,
      actionIndex: actionIndex,
      transactionID: transactionID(operationID: operationID, actionIndex: actionIndex),
      accounts: [walletID],
      amounts: [.zero],
      postBalances: [current],
      treasuryDelta: .zero,
      treasuryBalance: treasuryBalance,
      mode: mode,
      actor: actor.rawValue,
      owner: custodyOwner(for: walletID),
      causalObjectIDs: causalObjectIDs.sorted(),
      causalFunctionIDs: causalFunctionIDs.sorted(),
      note: note
    )
  }

  @discardableResult
  public func deposit(
    walletID: String,
    amount: CreditAmount,
    actor: CreditActor = .human,
    operationID: String = CreditService.makeID(),
    actionIndex: UInt64 = 0,
    causalObjectIDs: [String] = [],
    causalFunctionIDs: [String] = [],
    note: String = ""
  ) throws -> CreditBalance {
    guard actor == .human || actor == .system else {
      throw MikroKhorosError.runtime("wallet.deposit_denied", "agents cannot deposit directly")
    }
    let registration = try requireRegistered(walletID)
    if let record = existingRecord(operationID: operationID, actionIndex: actionIndex) {
      guard record.unsigned.kind == .deposit,
        record.unsigned.accounts == [walletID],
        record.unsigned.amounts == [try CreditBalance(minorUnits: amount.minorUnits)],
        record.unsigned.actor == actor.rawValue,
        record.unsigned.causalObjectIDs == causalObjectIDs.sorted(),
        record.unsigned.causalFunctionIDs == causalFunctionIDs.sorted(),
        record.unsigned.note == note
      else { throw operationConflict() }
      return record.unsigned.postBalances[0]
    }
    guard signer != nil else { throw missingSigner() }
    let current = try balance(for: walletID)
    let result = try CreditBalance(
      minorUnits: try checkedAdd(current.minorUnits, amount.minorUnits))
    let nextTreasury = try CreditBalance(
      minorUnits: try checkedSubtract(treasuryBalance.minorUnits, amount.minorUnits)
    )
    try appendRecord(
      kind: .deposit,
      operationID: operationID,
      actionIndex: actionIndex,
      transactionID: transactionID(operationID: operationID, actionIndex: actionIndex),
      accounts: [walletID],
      amounts: [try CreditBalance(minorUnits: amount.minorUnits)],
      postBalances: [result],
      treasuryDelta: try CreditBalance(minorUnits: -amount.minorUnits),
      treasuryBalance: nextTreasury,
      mode: registration.mode,
      actor: actor.rawValue,
      owner: custodyOwner(for: walletID),
      causalObjectIDs: causalObjectIDs.sorted(),
      causalFunctionIDs: causalFunctionIDs.sorted(),
      note: note
    )
    return result
  }

  @discardableResult
  public func deduct(
    walletID: String,
    amount: CreditAmount,
    actor: CreditActor,
    operationID: String = CreditService.makeID(),
    actionIndex: UInt64 = 0,
    allowExposure: Bool = false,
    sourceOwner: String? = nil,
    sourceCustodyCommitment: String? = nil,
    kind: CreditRecordKind = .deduction,
    nominalPurchaseAmount: CreditBalance? = nil,
    appliedPurchaseAmount: CreditBalance? = nil,
    causalObjectIDs: [String] = [],
    causalFunctionIDs: [String] = [],
    causalMerchantIDs: [String] = [],
    causalItemIDs: [String] = [],
    note: String = ""
  ) throws -> CreditBalance {
    guard kind == .deduction || kind == .purchase else {
      throw MikroKhorosError.runtime("wallet.deduct_denied", "the wallet debit kind is invalid")
    }
    if kind == .deduction, actor != .human {
      throw MikroKhorosError.runtime(
        "wallet.deduct_denied", "only the human may perform a direct deduction")
    }
    if kind == .purchase, actor != .agent, actor != .system {
      throw MikroKhorosError.runtime("wallet.deduct_denied", "the purchase actor is invalid")
    }
    if kind == .purchase, sourceOwner == nil {
      throw MikroKhorosError.runtime(
        "wallet.owner_mismatch", "an ownerless wallet cannot make a purchase"
      )
    }
    let registration = try requireRegistered(walletID)
    if let record = existingRecord(operationID: operationID, actionIndex: actionIndex) {
      let expectedApplied =
        kind == .purchase && record.unsigned.mode == .unlimited
        ? Int64(0) : amount.minorUnits
      let expectedNominal: CreditBalance?
      let expectedAppliedAmount: CreditBalance?
      if kind == .purchase {
        if let nominalPurchaseAmount {
          expectedNominal = nominalPurchaseAmount
        } else {
          expectedNominal = try CreditBalance(minorUnits: amount.minorUnits)
        }
        if let appliedPurchaseAmount {
          expectedAppliedAmount = appliedPurchaseAmount
        } else {
          expectedAppliedAmount = try CreditBalance(minorUnits: expectedApplied)
        }
      } else {
        expectedNominal = nominalPurchaseAmount
        expectedAppliedAmount = appliedPurchaseAmount
      }
      guard record.unsigned.kind == kind,
        record.unsigned.accounts == [walletID],
        record.unsigned.amounts == [try CreditBalance(minorUnits: -expectedApplied)],
        record.unsigned.nominalPurchaseAmount == expectedNominal,
        record.unsigned.appliedPurchaseAmount == expectedAppliedAmount,
        record.unsigned.sourceWalletID == walletID,
        record.unsigned.sourceWalletOwner == sourceOwner,
        record.unsigned.sourceWalletCustodyCommitment == sourceCustodyCommitment,
        record.unsigned.actor == actor.rawValue,
        record.unsigned.causalObjectIDs == causalObjectIDs.sorted(),
        record.unsigned.causalFunctionIDs == causalFunctionIDs.sorted(),
        record.unsigned.causalMerchantIDs == causalMerchantIDs.sorted(),
        record.unsigned.causalItemIDs == causalItemIDs.sorted(),
        record.unsigned.note == note
      else { throw operationConflict() }
      return record.unsigned.postBalances[0]
    }
    guard signer != nil else { throw missingSigner() }
    try validateSourceContext(
      registration: registration,
      sourceOwner: sourceOwner,
      sourceCustodyCommitment: sourceCustodyCommitment
    )
    let current = try balance(for: walletID)
    let unlimitedPurchase = kind == .purchase && registration.mode == .unlimited
    let appliedUnits = unlimitedPurchase ? Int64(0) : amount.minorUnits
    let nextUnits = try checkedSubtract(current.minorUnits, appliedUnits)
    if kind == .purchase, registration.mode == .finite, nextUnits < 0 {
      throw MikroKhorosError.runtime(
        "wallet.insufficient_funds",
        "the wallet does not have sufficient funds",
        details: ["wallet": walletID]
      )
    }
    _ = allowExposure
    let result = try CreditBalance(minorUnits: nextUnits)
    let nextTreasury = try CreditBalance(
      minorUnits: try checkedAdd(treasuryBalance.minorUnits, appliedUnits)
    )
    let delta = try CreditBalance(minorUnits: -appliedUnits)
    try appendRecord(
      kind: kind,
      operationID: operationID,
      actionIndex: actionIndex,
      transactionID: transactionID(operationID: operationID, actionIndex: actionIndex),
      accounts: [walletID],
      amounts: [delta],
      postBalances: [result],
      treasuryDelta: try CreditBalance(minorUnits: appliedUnits),
      treasuryBalance: nextTreasury,
      nominalPurchaseAmount: kind == .purchase
        ? (nominalPurchaseAmount ?? (try CreditBalance(minorUnits: amount.minorUnits)))
        : nominalPurchaseAmount,
      appliedPurchaseAmount: kind == .purchase
        ? (appliedPurchaseAmount ?? (try CreditBalance(minorUnits: appliedUnits)))
        : appliedPurchaseAmount,
      sourceWalletID: walletID,
      // Registration provenance is immutable and is not the current bearer.
      // A human administrator may leave the owner nil while presenting the
      // current custody commitment; agent/system debits carry the signed
      // current owner explicitly.
      sourceWalletOwner: sourceOwner,
      sourceWalletCustodyCommitment: sourceCustodyCommitment,
      mode: registration.mode,
      actor: actor.rawValue,
      owner: custodyOwners[walletID] ?? nil,
      causalObjectIDs: causalObjectIDs.sorted(),
      causalFunctionIDs: causalFunctionIDs.sorted(),
      causalMerchantIDs: causalMerchantIDs.sorted(),
      causalItemIDs: causalItemIDs.sorted(),
      note: note
    )
    return result
  }

  @discardableResult
  public func transfer(
    from sourceWalletID: String,
    to destinationWalletID: String,
    amount: CreditAmount,
    actor: CreditActor = .agent,
    operationID: String = CreditService.makeID(),
    actionIndex: UInt64 = 0,
    sourceOwner: String? = nil,
    sourceCustodyCommitment: String? = nil,
    causalObjectIDs: [String] = [],
    causalFunctionIDs: [String] = [],
    note: String = ""
  ) throws -> (source: CreditBalance, destination: CreditBalance) {
    guard actor == .agent || actor == .system else {
      throw MikroKhorosError.runtime("wallet.transfer_denied", "the transfer actor is invalid")
    }
    guard sourceOwner != nil else {
      throw MikroKhorosError.runtime(
        "wallet.owner_mismatch", "an ownerless wallet cannot send a transfer"
      )
    }
    guard sourceWalletID != destinationWalletID else {
      throw MikroKhorosError.runtime(
        "wallet.transfer_same", "source and destination wallets must differ")
    }
    let source = try requireRegistered(sourceWalletID)
    _ = try requireRegistered(destinationWalletID)
    if let record = existingRecord(operationID: operationID, actionIndex: actionIndex) {
      guard record.unsigned.kind == .transfer,
        record.unsigned.sourceWalletID == sourceWalletID,
        record.unsigned.sourceWalletOwner == sourceOwner,
        record.unsigned.sourceWalletCustodyCommitment == sourceCustodyCommitment,
        record.unsigned.actor == actor.rawValue,
        record.unsigned.causalObjectIDs == causalObjectIDs.sorted(),
        record.unsigned.causalFunctionIDs == causalFunctionIDs.sorted(),
        record.unsigned.note == note,
        let sourceIndex = record.unsigned.accounts.firstIndex(of: sourceWalletID),
        let destinationIndex = record.unsigned.accounts.firstIndex(of: destinationWalletID),
        record.unsigned.amounts[sourceIndex].minorUnits == -amount.minorUnits,
        record.unsigned.amounts[destinationIndex].minorUnits == amount.minorUnits
      else { throw operationConflict() }
      return (
        record.unsigned.postBalances[sourceIndex],
        record.unsigned.postBalances[destinationIndex]
      )
    }
    guard signer != nil else { throw missingSigner() }
    try validateSourceContext(
      registration: source,
      sourceOwner: sourceOwner,
      sourceCustodyCommitment: sourceCustodyCommitment
    )
    let sourceBalance = try balance(for: sourceWalletID)
    let destinationBalance = try balance(for: destinationWalletID)
    let sourceNext = try checkedSubtract(sourceBalance.minorUnits, amount.minorUnits)
    // Unlimited wallets bypass purchases, not transfers. A transfer always
    // spends the finite shadow balance.
    guard sourceNext >= 0 else {
      throw MikroKhorosError.runtime(
        "wallet.insufficient_funds", "the source wallet has insufficient funds")
    }
    let destinationNext = try checkedAdd(destinationBalance.minorUnits, amount.minorUnits)
    let nextSource = try CreditBalance(minorUnits: sourceNext)
    let nextDestination = try CreditBalance(minorUnits: destinationNext)
    let entries: [(String, CreditBalance, CreditBalance)] = [
      (sourceWalletID, try CreditBalance(minorUnits: -amount.minorUnits), nextSource),
      (destinationWalletID, try CreditBalance(minorUnits: amount.minorUnits), nextDestination),
    ].sorted { $0.0 < $1.0 }
    try appendRecord(
      kind: .transfer,
      operationID: operationID,
      actionIndex: actionIndex,
      transactionID: transactionID(operationID: operationID, actionIndex: actionIndex),
      accounts: entries.map { $0.0 },
      amounts: entries.map { $0.1 },
      postBalances: entries.map { $0.2 },
      treasuryDelta: .zero,
      treasuryBalance: treasuryBalance,
      sourceWalletID: sourceWalletID,
      sourceWalletOwner: sourceOwner,
      sourceWalletCustodyCommitment: sourceCustodyCommitment,
      mode: source.mode,
      actor: actor.rawValue,
      owner: custodyOwners[sourceWalletID] ?? nil,
      causalObjectIDs: causalObjectIDs.sorted(),
      causalFunctionIDs: causalFunctionIDs.sorted(),
      note: note
    )
    return (nextSource, nextDestination)
  }

  public func sufficientFunds(
    walletID: String,
    amount: CreditAmount,
    forPurchase: Bool = true
  ) throws -> Bool {
    let registration = try requireRegistered(walletID)
    let current = try balance(for: walletID)
    return (forPurchase && registration.mode == .unlimited)
      || current.minorUnits >= amount.minorUnits
  }

  /// Record a custody transition. This is intentionally a zero-delta signed
  /// record. Callers must provide the commitment they observed immediately
  /// before the move; stale or verify-only transitions fail closed.
  public func updateCustody(
    walletID: String,
    oldOwner: String?,
    newOwner: String?,
    oldLocationCommitment: String,
    newLocationCommitment: String,
    operationID: String = CreditService.makeID(),
    actionIndex: UInt64 = 0,
    actor: CreditActor = .system
  ) throws {
    try updateCustodies(
      [
        WalletCustodyTransition(
          walletID: walletID,
          oldOwner: oldOwner,
          newOwner: newOwner,
          oldLocationCommitment: oldLocationCommitment,
          newLocationCommitment: newLocationCommitment,
          oldCustodyCommitment: custodyCommitment(for: walletID)
        )
      ],
      operationID: operationID,
      actionIndex: actionIndex,
      actor: actor
    )
  }

  /// Atomically authenticates all registered wallets whose derived bearer
  /// changed in one object/holding operation. Same-owner transitions are
  /// intentionally omitted: no signature is needed for them.
  public func updateCustodies(
    _ transitions: [WalletCustodyTransition],
    operationID: String = CreditService.makeID(),
    actionIndex: UInt64 = 0,
    actor: CreditActor = .system
  ) throws {
    guard !transitions.isEmpty else { return }
    let changed = transitions.filter { $0.oldOwner != $0.newOwner }
    guard !changed.isEmpty else { return }
    let sorted = changed.sorted { $0.walletID < $1.walletID }
    if let record = existingRecord(operationID: operationID, actionIndex: actionIndex) {
      guard record.unsigned.kind == .custodyChange,
        record.unsigned.actor == actor.rawValue,
        record.unsigned.custody.count == sorted.count,
        zip(record.unsigned.custody, sorted).allSatisfy({ persisted, requested in
          persisted.wallet == requested.walletID
            && persisted.oldOwner == requested.oldOwner
            && persisted.newOwner == requested.newOwner
            && persisted.oldLocationCommitment == requested.oldLocationCommitment
            && persisted.newLocationCommitment == requested.newLocationCommitment
            && (requested.oldCustodyCommitment == nil
              || persisted.previousCustodyCommitment == requested.oldCustodyCommitment)
        })
      else { throw operationConflict() }
      return
    }
    guard signer != nil else { throw missingSigner() }
    var entries: [CreditCustodyEntry] = []
    for transition in sorted {
      _ = try requireRegistered(transition.walletID)
      guard let priorCustody = custodyCommitments[transition.walletID],
        transition.oldCustodyCommitment == nil
          || transition.oldCustodyCommitment == priorCustody
      else {
        throw MikroKhorosError.runtime("wallet.custody_stale", "wallet custody is not current")
      }
      if custodyOwners.keys.contains(transition.walletID) {
        guard custodyOwners[transition.walletID] == transition.oldOwner else {
          throw MikroKhorosError.runtime("wallet.owner_mismatch", "the wallet owner is not current")
        }
      } else {
        guard transition.oldOwner == nil else {
          throw MikroKhorosError.runtime("wallet.owner_mismatch", "the wallet owner is not current")
        }
      }
      entries.append(
        try CreditCustodyEntry(
          wallet: transition.walletID,
          oldOwner: transition.oldOwner,
          newOwner: transition.newOwner,
          oldLocationCommitment: transition.oldLocationCommitment,
          newLocationCommitment: transition.newLocationCommitment,
          previousCustodyCommitment: priorCustody
        ))
    }
    let accounts = sorted.map(\.walletID)
    let currentBalances = try accounts.map { try balance(for: $0) }
    try appendRecord(
      kind: .custodyChange,
      operationID: operationID,
      actionIndex: actionIndex,
      transactionID: transactionID(operationID: operationID, actionIndex: actionIndex),
      accounts: accounts,
      amounts: Array(repeating: .zero, count: accounts.count),
      postBalances: currentBalances,
      treasuryDelta: .zero,
      treasuryBalance: treasuryBalance,
      mode: .finite,
      actor: actor.rawValue,
      owner: nil,
      custody: entries,
      note: "wallet custody changed"
    )
  }

  public func custodyCommitment(for walletID: String) -> String? {
    custodyCommitments[walletID]
  }

  public func custodyLocationCommitment(for walletID: String) -> String? {
    locationCommitments[walletID]
  }

  public func custodyOwner(for walletID: String) -> String? {
    custodyOwners[walletID] ?? nil
  }

  /// Re-runs signed-chain, custody, and exposure validation without changing
  /// any derived state. Human management uses this as its verify action.
  public func verify() throws {
    try validateChain()
    try validateExposureInvariant()
  }

  public func snapshot() -> CreditServiceSnapshot {
    CreditServiceSnapshot(
      worldID: worldID,
      authority: authority,
      chain: chainRecords
    )
  }

  public func restore(_ snapshot: CreditServiceSnapshot) throws {
    guard snapshot.worldID == worldID,
      snapshot.schemaVersion == CreditServiceSnapshot.currentSchemaVersion,
      snapshot.authority == authority
    else {
      throw MikroKhorosError.persistence(
        "credit snapshot does not belong to this world or authority")
    }
    let priorRegistrations = registrationsByWallet
    let priorBalances = balancesByWallet
    let priorChain = chainRecords
    let priorIDs = idempotency
    let priorCustody = custodyCommitments
    let priorLocations = locationCommitments
    let priorOwners = custodyOwners
    let priorIssuance = issuanceCommitments
    let priorTreasury = treasuryBalance
    do {
      registrationsByWallet = [:]
      balancesByWallet = [:]
      chainRecords = []
      idempotency = []
      custodyCommitments = [:]
      locationCommitments = [:]
      custodyOwners = [:]
      issuanceCommitments = [:]
      treasuryBalance = .zero
      try applyRecords(snapshot.chain)
      try validateExposureInvariant()
    } catch {
      registrationsByWallet = priorRegistrations
      balancesByWallet = priorBalances
      chainRecords = priorChain
      idempotency = priorIDs
      custodyCommitments = priorCustody
      locationCommitments = priorLocations
      custodyOwners = priorOwners
      issuanceCommitments = priorIssuance
      treasuryBalance = priorTreasury
      throw error
    }
  }

  /// Apply one signed record after verifying its authority, chain position, and
  /// account deltas. Duplicate record IDs are idempotent only when the payload
  /// hash is identical.
  public func apply(_ record: SignedCreditRecord) throws {
    try applyRecords([record])
  }

  public func apply(_ records: [SignedCreditRecord]) throws {
    try applyRecords(records)
  }

  private func applyRecords(_ records: [SignedCreditRecord]) throws {
    if records.isEmpty { return }
    let oldRegistrations = registrationsByWallet
    let oldBalances = balancesByWallet
    let oldChain = chainRecords
    let oldIDs = idempotency
    let oldCustody = custodyCommitments
    let oldLocations = locationCommitments
    let oldOwners = custodyOwners
    let oldIssuance = issuanceCommitments
    let oldTreasury = treasuryBalance
    do {
      for record in records { try applyOne(record) }
    } catch {
      registrationsByWallet = oldRegistrations
      balancesByWallet = oldBalances
      chainRecords = oldChain
      idempotency = oldIDs
      custodyCommitments = oldCustody
      locationCommitments = oldLocations
      custodyOwners = oldOwners
      issuanceCommitments = oldIssuance
      treasuryBalance = oldTreasury
      throw error
    }
  }

  private func applyOne(_ record: SignedCreditRecord) throws {
    let verifier = CreditRecordVerifier(authority: authority, expectedWorld: worldID)
    try verifier.verify(record)
    if idempotency.contains(record.recordID) {
      guard let existing = chainRecords.first(where: { $0.recordID == record.recordID }),
        try existing.recordHash() == record.recordHash()
      else { throw MikroKhorosError.persistence("credit record idempotency payload conflict") }
      return
    }
    let expectedPrior =
      chainRecords.last.flatMap { try? $0.recordHash() }
      ?? UnsignedCreditRecord.genesisPriorRecordHash
    guard record.unsigned.priorRecordHash == expectedPrior else {
      throw MikroKhorosError.persistence("credit record chain order is invalid")
    }
    guard record.unsigned.accounts.count == record.unsigned.amounts.count,
      record.unsigned.accounts.count == record.unsigned.postBalances.count
    else { throw MikroKhorosError.persistence("credit record account shape is invalid") }
    guard
      !chainRecords.contains(where: {
        $0.unsigned.transactionID == record.unsigned.transactionID
      })
    else {
      throw MikroKhorosError.persistence("credit transaction identity is duplicated")
    }
    guard
      record.unsigned.transactionID
        == transactionID(
          operationID: record.unsigned.operationID,
          actionIndex: record.unsigned.actionIndex
        )
    else {
      throw MikroKhorosError.persistence(
        "credit transaction identity does not match its operation action"
      )
    }

    try validateRecordActor(record.unsigned)
    let recordHash = try record.recordHash()
    var registrationWalletID: String?
    if record.unsigned.kind == .registration {
      let walletID = record.unsigned.accounts[0]
      guard registrationsByWallet[walletID] == nil,
        let issuingAgentID = record.unsigned.issuanceAgentID,
        let backpackID = record.unsigned.issuanceBackpackID,
        let coordinate = record.unsigned.issuanceCoordinate,
        let issuanceLocationCommitment = record.unsigned.issuanceLocationCommitment,
        record.unsigned.owner == issuingAgentID,
        record.unsigned.mode == .finite
      else {
        throw MikroKhorosError.persistence("registration record has invalid issuance provenance")
      }
      registrationsByWallet[walletID] = try WalletRegistration(
        walletID: walletID,
        agentID: issuingAgentID,
        worldID: worldID,
        issuerID: issuingAgentID,
        backpackID: backpackID,
        coordinate: coordinate,
        mode: .finite
      )
      balancesByWallet[walletID] = .zero
      issuanceCommitments[walletID] = issuanceLocationCommitment
      registrationWalletID = walletID
    } else {
      for walletID in record.unsigned.accounts {
        guard registrationsByWallet[walletID] != nil else { throw unknownWallet() }
      }
    }

    switch record.unsigned.kind {
    case .registration:
      break
    case .deposit, .deduction, .modeChange:
      let walletID = record.unsigned.accounts[0]
      guard let registration = registrationsByWallet[walletID],
        record.unsigned.kind == .modeChange || record.unsigned.mode == registration.mode,
        record.unsigned.owner == (custodyOwners[walletID] ?? nil)
      else {
        throw MikroKhorosError.persistence(
          "credit record mode or bearer projection is stale"
        )
      }
    case .transfer, .purchase:
      guard let sourceWalletID = record.unsigned.sourceWalletID,
        let registration = registrationsByWallet[sourceWalletID],
        record.unsigned.mode == registration.mode,
        record.unsigned.owner == (custodyOwners[sourceWalletID] ?? nil),
        record.unsigned.sourceWalletOwner != nil
      else {
        throw MikroKhorosError.persistence(
          "credit debit mode or bearer projection is stale"
        )
      }
    case .custodyChange:
      guard record.unsigned.owner == nil else {
        throw MikroKhorosError.persistence("custody records cannot name one aggregate owner")
      }
    }
    if record.unsigned.kind == .deduction || record.unsigned.kind == .transfer
      || record.unsigned.kind == .purchase
    {
      guard let sourceWalletID = record.unsigned.sourceWalletID,
        let sourceCommitment = record.unsigned.sourceWalletCustodyCommitment,
        record.unsigned.accounts.contains(sourceWalletID),
        custodyCommitments[sourceWalletID] == sourceCommitment
      else {
        throw MikroKhorosError.persistence("credit debit source custody is stale")
      }
      let currentOwner = custodyOwners[sourceWalletID] ?? nil
      guard record.unsigned.sourceWalletOwner == currentOwner else {
        throw MikroKhorosError.persistence("credit debit source owner is stale")
      }
    }

    for custody in record.unsigned.custody {
      guard registrationsByWallet[custody.wallet] != nil,
        custody.oldOwner != custody.newOwner,
        custodyCommitments[custody.wallet] == custody.previousCustodyCommitment,
        (custodyOwners[custody.wallet] ?? nil) == custody.oldOwner
      else {
        throw MikroKhorosError.persistence("credit custody transition is stale or malformed")
      }
    }

    for index in record.unsigned.accounts.indices {
      let walletID = record.unsigned.accounts[index]
      guard registrationsByWallet[walletID] != nil else { throw unknownWallet() }
      let current = balancesByWallet[walletID] ?? .zero
      let delta = record.unsigned.amounts[index].minorUnits
      let (expected, overflow) = current.minorUnits.addingReportingOverflow(delta)
      guard !overflow, expected == record.unsigned.postBalances[index].minorUnits else {
        throw MikroKhorosError.persistence("credit record balance transition is invalid")
      }
    }
    if let sourceWalletID = record.unsigned.sourceWalletID,
      let sourceIndex = record.unsigned.accounts.firstIndex(of: sourceWalletID)
    {
      let sourceWouldBeNegative = record.unsigned.postBalances[sourceIndex].minorUnits < 0
      if record.unsigned.kind == .transfer && sourceWouldBeNegative {
        throw MikroKhorosError.persistence(
          "transfers cannot overdraw a wallet's finite shadow balance"
        )
      }
      if record.unsigned.kind == .purchase, record.unsigned.mode == .finite,
        sourceWouldBeNegative
      {
        throw MikroKhorosError.persistence("finite purchases cannot overdraw a wallet")
      }
    }
    let (treasuryExpected, treasuryOverflow) = treasuryBalance.minorUnits.addingReportingOverflow(
      record.unsigned.treasuryDelta.minorUnits
    )
    guard !treasuryOverflow, treasuryExpected == record.unsigned.treasuryBalance.minorUnits else {
      throw MikroKhorosError.persistence("credit record treasury transition is invalid")
    }
    for index in record.unsigned.accounts.indices {
      balancesByWallet[record.unsigned.accounts[index]] = record.unsigned.postBalances[index]
    }
    if record.unsigned.kind == .registration || record.unsigned.kind == .modeChange {
      for walletID in record.unsigned.accounts {
        guard var registration = registrationsByWallet[walletID] else { throw unknownWallet() }
        registration.setMode(record.unsigned.mode)
        registrationsByWallet[walletID] = registration
      }
    }
    for custody in record.unsigned.custody {
      locationCommitments[custody.wallet] = custody.newLocationCommitment
      custodyOwners[custody.wallet] = custody.newOwner
    }
    treasuryBalance = record.unsigned.treasuryBalance
    try validateExposureInvariant()
    chainRecords.append(record)
    idempotency.insert(record.recordID)
    if let walletID = registrationWalletID,
      let issuanceLocationCommitment = record.unsigned.issuanceLocationCommitment,
      let issuingAgentID = record.unsigned.issuanceAgentID
    {
      locationCommitments[walletID] = issuanceLocationCommitment
      custodyOwners[walletID] = issuingAgentID
      custodyCommitments[walletID] = recordHash
    }
    for custody in record.unsigned.custody {
      custodyCommitments[custody.wallet] = recordHash
    }
  }

  private func appendRecord(
    kind: CreditRecordKind,
    operationID: String,
    actionIndex: UInt64,
    transactionID: String,
    accounts: [String],
    amounts: [CreditBalance],
    postBalances: [CreditBalance],
    treasuryDelta: CreditBalance,
    treasuryBalance: CreditBalance,
    nominalPurchaseAmount: CreditBalance? = nil,
    appliedPurchaseAmount: CreditBalance? = nil,
    sourceWalletID: String? = nil,
    sourceWalletOwner: String? = nil,
    sourceWalletCustodyCommitment: String? = nil,
    issuanceAgentID: String? = nil,
    issuanceBackpackID: String? = nil,
    issuanceCoordinate: Coordinate? = nil,
    issuanceLocationCommitment: String? = nil,
    mode: WalletMode,
    actor: String,
    owner: String?,
    custody: [CreditCustodyEntry] = [],
    causalObjectIDs: [String] = [],
    causalFunctionIDs: [String] = [],
    causalMerchantIDs: [String] = [],
    causalItemIDs: [String] = [],
    note: String
  ) throws {
    guard let signer else { throw missingSigner() }
    guard existingRecord(operationID: operationID, actionIndex: actionIndex) == nil else {
      throw operationConflict()
    }
    let unsigned = try UnsignedCreditRecord(
      kind: kind,
      worldID: worldID,
      keyID: authority.keyID,
      priorRecordHash: chainRecords.last.flatMap { try? $0.recordHash() }
        ?? UnsignedCreditRecord.genesisPriorRecordHash,
      operationID: operationID,
      actionIndex: actionIndex,
      transactionID: transactionID,
      accounts: accounts,
      amounts: amounts,
      postBalances: postBalances,
      treasuryDelta: treasuryDelta,
      treasuryBalance: treasuryBalance,
      nominalPurchaseAmount: nominalPurchaseAmount,
      appliedPurchaseAmount: appliedPurchaseAmount,
      sourceWalletID: sourceWalletID,
      sourceWalletOwner: sourceWalletOwner,
      sourceWalletCustodyCommitment: sourceWalletCustodyCommitment,
      issuanceAgentID: issuanceAgentID,
      issuanceBackpackID: issuanceBackpackID,
      issuanceCoordinate: issuanceCoordinate,
      issuanceLocationCommitment: issuanceLocationCommitment,
      mode: mode,
      actor: actor,
      owner: owner,
      custody: custody,
      causalObjectIDs: causalObjectIDs,
      causalFunctionIDs: causalFunctionIDs,
      causalMerchantIDs: causalMerchantIDs,
      causalItemIDs: causalItemIDs,
      note: note
    )
    try preflightAccounting(unsigned)
    let signed = try signer.sign(unsigned)
    try applyRecords([signed])
  }

  /// Validate the exact affected contribution replacement and treasury result
  /// before producing an authority signature. This uses the same unsigned,
  /// order-independent exposure accumulator as replay, so an overflow or cap
  /// failure cannot leave even an unattached valid signed record behind.
  private func preflightAccounting(_ record: UnsignedCreditRecord) throws {
    var proposedBalances = balancesByWallet
    for index in record.accounts.indices {
      let walletID = record.accounts[index]
      let current = proposedBalances[walletID] ?? .zero
      let (next, overflow) = current.minorUnits.addingReportingOverflow(
        record.amounts[index].minorUnits
      )
      guard !overflow, next != Int64.min,
        next == record.postBalances[index].minorUnits
      else {
        throw MikroKhorosError.runtime(
          "wallet.overflow",
          "the wallet accounting transition is not representable"
        )
      }
      proposedBalances[walletID] = record.postBalances[index]
    }
    let (nextTreasury, treasuryOverflow) = treasuryBalance.minorUnits
      .addingReportingOverflow(record.treasuryDelta.minorUnits)
    guard !treasuryOverflow, nextTreasury != Int64.min,
      nextTreasury == record.treasuryBalance.minorUnits
    else {
      throw MikroKhorosError.runtime(
        "wallet.overflow",
        "the treasury accounting transition is not representable"
      )
    }
    let ledger = try CreditLedger(
      contributions: Dictionary(
        uniqueKeysWithValues: proposedBalances.map { ($0.key, $0.value.minorUnits) }
      )
    )
    guard ledger.expectedTreasurySignedDifference == nextTreasury else {
      throw MikroKhorosError.persistence(
        "credit exposure and treasury balance are inconsistent"
      )
    }
  }

  private func validateSourceContext(
    registration: WalletRegistration,
    sourceOwner: String?,
    sourceCustodyCommitment: String?
  ) throws {
    guard sourceOwner == (custodyOwners[registration.walletID] ?? nil) else {
      throw MikroKhorosError.runtime("wallet.owner_mismatch", "the wallet owner is not current")
    }
    guard let sourceCustodyCommitment,
      sourceCustodyCommitment == custodyCommitment(for: registration.walletID)
    else {
      throw MikroKhorosError.runtime("wallet.custody_stale", "the wallet custody is not current")
    }
  }

  private func validateRecordActor(_ record: UnsignedCreditRecord) throws {
    let actor = CreditActor(rawValue: record.actor)
    switch record.kind {
    case .registration:
      guard actor == .system else {
        throw MikroKhorosError.persistence("wallet registration actor is invalid")
      }
    case .deposit, .modeChange:
      guard actor == .human || actor == .system else {
        throw MikroKhorosError.persistence("wallet administrative actor is invalid")
      }
    case .deduction:
      guard actor == .human else {
        throw MikroKhorosError.persistence("only a human deduction may create wallet debt")
      }
    case .transfer:
      guard actor == .agent || actor == .system else {
        throw MikroKhorosError.persistence("wallet transfer actor is invalid")
      }
    case .purchase:
      guard actor == .agent || actor == .system else {
        throw MikroKhorosError.persistence("wallet purchase actor is invalid")
      }
    case .custodyChange:
      guard actor == .human || actor == .system || actor == .agent else {
        throw MikroKhorosError.persistence("wallet custody actor is invalid")
      }
    }
  }

  private func validateChain() throws {
    var chain = CreditRecordChain(authority: authority, expectedWorld: worldID)
    for record in chainRecords { try chain.append(record) }
  }

  private func validateExposureInvariant() throws {
    let ledger = try CreditLedger(
      contributions: Dictionary(
        uniqueKeysWithValues: balancesByWallet.map { ($0.key, $0.value.minorUnits) })
    )
    guard ledger.expectedTreasurySignedDifference == treasuryBalance.minorUnits else {
      throw MikroKhorosError.persistence("credit exposure and treasury balance are inconsistent")
    }
  }

  private func requireRegistered(_ walletID: String) throws -> WalletRegistration {
    guard let registration = registrationsByWallet[walletID] else { throw unknownWallet() }
    return registration
  }

  private func unknownWallet() -> MikroKhorosError {
    .runtime("wallet.unknown", "the wallet is not registered in this world")
  }

  private func missingSigner() -> MikroKhorosError {
    .runtime(
      "wallet.credential_unavailable",
      "the treasury credential is unavailable; verify-only mode cannot mutate credit"
    )
  }

  private func existingRecord(
    operationID: String,
    actionIndex: UInt64
  ) -> SignedCreditRecord? {
    let recordID = "\(operationID)#\(actionIndex)"
    return chainRecords.first(where: { $0.recordID == recordID })
  }

  private func transactionID(operationID: String, actionIndex: UInt64) -> String {
    actionIndex == 0 ? operationID : "\(operationID):\(actionIndex)"
  }

  private func operationConflict() -> MikroKhorosError {
    .runtime(
      "wallet.operation_conflict",
      "the operation identity was already used with a different payload"
    )
  }

  private func checkedAdd(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
    let (value, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow else {
      throw MikroKhorosError.runtime("wallet.overflow", "wallet balance overflow")
    }
    return value
  }

  private func checkedSubtract(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
    let (value, overflow) = lhs.subtractingReportingOverflow(rhs)
    guard !overflow else {
      throw MikroKhorosError.runtime("wallet.overflow", "wallet balance overflow")
    }
    return value
  }

  public static func makeID() -> String {
    UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
  }
}
