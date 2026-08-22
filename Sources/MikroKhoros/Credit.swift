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

private struct CreditDynamicCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init?(stringValue: String) {
    self.stringValue = stringValue
    self.intValue = nil
  }

  init?(intValue: Int) {
    self.stringValue = String(intValue)
    self.intValue = intValue
  }
}

private func rejectUnknownKeys(
  _ decoder: Decoder,
  allowed: Set<String>,
  context: String
) throws {
  let container = try decoder.container(keyedBy: CreditDynamicCodingKey.self)
  if let unknown = container.allKeys.map(\.stringValue).first(where: { !allowed.contains($0) }) {
    throw CreditError.malformedRecord("unknown \(context) field: \(unknown)")
  }
}

public enum CreditError: Error, Equatable, CustomStringConvertible {
  case malformedDecimal(String)
  case amountOutOfRange(String)
  case balanceOutOfRange(String)
  case contributionOutOfRange(String)
  case accountingTotalsOverflow
  case duplicateWalletContribution(String)
  case duplicateIdentifier(String)
  case malformedRecord(String)
  case malformedTime
  case keyMismatch
  case keyIDMismatch
  case wrongWorld
  case signatureInvalid
  case chainOrderMismatch(expected: String, found: String)
  case duplicateRecordID(String)
  case invalidAuthority(String)

  public var description: String {
    switch self {
    case .malformedDecimal(let value):
      "credit decimal text is malformed: \(value)"
    case .amountOutOfRange(let value):
      "credit amount is out of range: \(value)"
    case .balanceOutOfRange(let value):
      "credit balance is out of range: \(value)"
    case .contributionOutOfRange(let value):
      "ledger contribution is out of range: \(value)"
    case .accountingTotalsOverflow:
      "ledger accounting totals exceed Int64.max"
    case .duplicateWalletContribution(let wallet):
      "wallet contribution is duplicated: \(wallet)"
    case .duplicateIdentifier(let identifier):
      "identifier is duplicated: \(identifier)"
    case .malformedRecord(let value):
      "record is malformed: \(value)"
    case .malformedTime:
      "record time must be finite integral seconds"
    case .keyMismatch:
      "record signing key does not match expected authority key"
    case .keyIDMismatch:
      "record key identifier does not match authority key identifier"
    case .wrongWorld:
      "record world does not match verifier world"
    case .signatureInvalid:
      "record signature is invalid"
    case .chainOrderMismatch(let expected, let found):
      "record chain order mismatch, expected prior hash \(expected), found \(found)"
    case .duplicateRecordID(let id):
      "record identifier is already present in chain: \(id)"
    case .invalidAuthority(let reason):
      "treasury authority is invalid: \(reason)"
    }
  }
}

public enum WalletMode: String, Codable, CaseIterable, Sendable {
  case finite
  case unlimited
}

public struct CreditAmount: Equatable, Codable, Hashable, Sendable {
  public static let maxDecimalPlaces = 2
  public let minorUnits: Int64

  public init(minorUnits: Int64) throws {
    guard minorUnits > 0 else {
      throw CreditError.amountOutOfRange("minorUnits must be in 1...Int64.max")
    }
    self.minorUnits = minorUnits
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let units = try container.decode(Int64.self)
    try self.init(minorUnits: units)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(minorUnits)
  }

  public static func parse(_ text: String) throws -> CreditAmount {
    let minorUnits = try parseDecimalToMinorUnits(text, allowNegative: false, allowZero: false)
    return try CreditAmount(minorUnits: minorUnits)
  }

  public var decimalText: String {
    Self.formatDecimal(minorUnits)
  }

  fileprivate static func parseDecimalToMinorUnits(
    _ text: String,
    allowNegative: Bool,
    allowZero: Bool
  ) throws -> Int64 {
    guard text == text.trimmingCharacters(in: .whitespacesAndNewlines),
      !text.isEmpty
    else {
      throw CreditError.malformedDecimal(text)
    }
    let lowered = text.lowercased()
    guard !lowered.contains("nan"), !lowered.contains("inf") else {
      throw CreditError.malformedDecimal(text)
    }
    guard !text.contains("e"), !text.contains("E"), !text.contains("+") else {
      throw CreditError.malformedDecimal(text)
    }

    var normalized = text
    let isNegative: Bool
    if normalized.hasPrefix("-") {
      guard allowNegative else {
        throw CreditError.malformedDecimal("negative values are not allowed: \(text)")
      }
      isNegative = true
      normalized.removeFirst()
    } else {
      isNegative = false
    }

    guard !normalized.isEmpty,
      !normalized.hasPrefix("."),
      !normalized.hasSuffix(".")
    else {
      throw CreditError.malformedDecimal(text)
    }

    let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2 else {
      throw CreditError.malformedDecimal(text)
    }

    let integerPart = String(parts[0])
    let fractionalPart = parts.count == 2 ? String(parts[1]) : ""
    guard !integerPart.isEmpty,
      integerPart.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }),
      fractionalPart.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }),
      fractionalPart.count <= maxDecimalPlaces
    else {
      throw CreditError.malformedDecimal(text)
    }
    guard integerPart == "0" || !integerPart.hasPrefix("0") else {
      throw CreditError.malformedDecimal("leading zeroes are not canonical: \(text)")
    }

    let integerValue = try parseUnsignedDecimalDigits(integerPart, context: "integer part")
    let paddedFractional = fractionalPart.padding(
      toLength: maxDecimalPlaces, withPad: "0", startingAt: 0)
    let fractionalValue = try parseUnsignedDecimalDigits(
      paddedFractional, context: "fractional part")

    let (scaledInteger, integerOverflow) = integerValue.multipliedReportingOverflow(by: 100)
    guard !integerOverflow else {
      throw CreditError.malformedDecimal(text)
    }
    let (minorUnits, fractionalOverflow) = scaledInteger.addingReportingOverflow(fractionalValue)
    guard !fractionalOverflow else {
      throw CreditError.malformedDecimal(text)
    }

    if !allowZero && minorUnits == 0 {
      throw CreditError.amountOutOfRange("0 is invalid")
    }
    if isNegative && minorUnits == 0 {
      throw CreditError.malformedDecimal("negative zero is not canonical: \(text)")
    }
    guard allowNegative || !isNegative else {
      throw CreditError.malformedDecimal("negative amount is not allowed: \(text)")
    }
    return isNegative ? -minorUnits : minorUnits
  }

  fileprivate static func parseUnsignedDecimalDigits(_ text: String, context: String) throws
    -> Int64
  {
    var value: Int64 = 0
    for scalar in text.unicodeScalars {
      guard scalar.value >= 48, scalar.value <= 57 else {
        throw CreditError.malformedDecimal(context)
      }
      let digit = scalar.value - 48
      let (times10, overflowMul) = value.multipliedReportingOverflow(by: 10)
      guard !overflowMul else {
        throw CreditError.amountOutOfRange(context)
      }
      let (next, overflowAdd) = times10.addingReportingOverflow(Int64(digit))
      guard !overflowAdd else {
        throw CreditError.amountOutOfRange(context)
      }
      value = next
    }
    return value
  }

  fileprivate static func formatDecimal(_ value: Int64) -> String {
    let absoluteMagnitude: UInt64
    if value >= 0 {
      absoluteMagnitude = UInt64(value)
    } else {
      absoluteMagnitude = UInt64(truncatingIfNeeded: -value)
    }
    let integerValue = absoluteMagnitude / 100
    let fractionalValue = Int(absoluteMagnitude % 100)
    let sign = value < 0 ? "-" : ""
    return "\(sign)\(integerValue).\(String(format: "%02d", fractionalValue))"
  }
}

public struct CreditBalance: Equatable, Codable, Hashable, Sendable {
  public let minorUnits: Int64
  public static let zero = try! CreditBalance(minorUnits: 0)

  public init(minorUnits: Int64) throws {
    guard minorUnits != Int64.min else {
      throw CreditError.balanceOutOfRange("Int64.min is rejected")
    }
    self.minorUnits = minorUnits
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let units = try container.decode(Int64.self)
    try self.init(minorUnits: units)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(minorUnits)
  }

  public static func parse(_ text: String) throws -> CreditBalance {
    let minorUnits = try CreditAmount.parseDecimalToMinorUnits(
      text,
      allowNegative: true,
      allowZero: true
    )
    return try CreditBalance(minorUnits: minorUnits)
  }

  public var decimalText: String {
    CreditAmount.formatDecimal(minorUnits)
  }
}

public struct CreditLedger: Equatable, Sendable {
  public private(set) var contributions: [String: Int64]
  public private(set) var totalPositive: UInt64
  public private(set) var totalDebt: UInt64

  public static let maxWalletIDLength = 256

  public init(contributions: [String: Int64] = [:]) throws {
    try Self.validateContributionIdentifiers(contributions.keys)
    self.contributions = contributions
    (self.totalPositive, self.totalDebt) = try Self.calculateTotals(contributions: contributions)
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownKeys(
      decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "credit ledger"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if container.contains(.totalPositive) || container.contains(.totalDebt) {
      throw CreditError.malformedRecord("derived totals are not accepted")
    }

    let contributions = try container.decode([String: Int64].self, forKey: .contributions)
    try Self.validateContributionIdentifiers(contributions.keys)
    self.contributions = contributions
    (self.totalPositive, self.totalDebt) = try Self.calculateTotals(contributions: contributions)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(contributions, forKey: .contributions)
  }

  public var debtMagnitude: UInt64 { totalDebt }

  public var netIssued: Int64 {
    Int64(totalPositive) - Int64(totalDebt)
  }

  public var expectedTreasurySignedDifference: Int64 {
    Int64(totalDebt) - Int64(totalPositive)
  }

  public var orderedContributions: [WalletContribution] {
    contributions
      .map { WalletContribution(wallet: $0.key, value: $0.value) }
      .sorted { $0.wallet < $1.wallet }
  }

  public mutating func replaceContribution(wallet: String, value: Int64) throws {
    guard !wallet.isEmpty, wallet.count <= Self.maxWalletIDLength else {
      throw CreditError.contributionOutOfRange("wallet identifier is invalid")
    }
    guard value != Int64.min else {
      throw CreditError.contributionOutOfRange("Int64.min is rejected")
    }

    var nextContributions = contributions
    if value == 0 {
      nextContributions.removeValue(forKey: wallet)
    } else {
      nextContributions[wallet] = value
    }
    let nextTotals = try Self.calculateTotals(contributions: nextContributions)
    contributions = nextContributions
    (totalPositive, totalDebt) = nextTotals
  }

  private static func validateContributionIdentifiers(_ identifiers: Dictionary<String, Int64>.Keys)
    throws
  {
    for identifier in identifiers {
      if identifier.isEmpty || identifier.count > maxWalletIDLength {
        throw CreditError.contributionOutOfRange("wallet identifier invalid: \(identifier)")
      }
    }
  }

  private static func calculateTotals(contributions: [String: Int64]) throws -> (UInt64, UInt64) {
    var positive: UInt64 = 0
    var debt: UInt64 = 0

    for value in contributions.values {
      if value > 0 {
        let (newPositive, overflowed) = positive.addingReportingOverflow(UInt64(value))
        guard !overflowed else {
          throw CreditError.accountingTotalsOverflow
        }
        positive = newPositive
      } else if value < 0 {
        guard value != Int64.min else {
          throw CreditError.contributionOutOfRange("Int64.min is rejected")
        }
        let magnitude = UInt64(truncatingIfNeeded: -value)
        let (newDebt, overflowed) = debt.addingReportingOverflow(magnitude)
        guard !overflowed else {
          throw CreditError.accountingTotalsOverflow
        }
        debt = newDebt
      }
      if positive > UInt64(Int64.max) || debt > UInt64(Int64.max) {
        throw CreditError.accountingTotalsOverflow
      }
    }
    return (positive, debt)
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case contributions
    case totalPositive
    case totalDebt
  }
}

public struct WalletContribution: Equatable, Codable, Sendable {
  public let wallet: String
  public let value: Int64
}

public enum CreditRecordKind: String, Codable, Sendable {
  case registration
  case deposit
  case deduction
  case transfer
  case purchase
  case modeChange
  case custodyChange
}

public struct TreasuryAuthorityDocument: Equatable, Codable, Sendable {
  public static let currentSchema = "1"
  public static let algorithm = "ed25519"
  public static let keyDomainSeparator = "com.mikrokhoros.economy.credit.treasury-key"
  public static let maxPrivateCredentialHandleLength = 256

  public let schema: String
  public let algorithm: String
  public let publicKey: Data
  public let keyID: String
  public let privateCredentialHandle: String
  public let createdAt: Date

  public init(
    publicKey: Data,
    privateCredentialHandle: String,
    createdAt: Date = Date()
  ) throws {
    guard !privateCredentialHandle.isEmpty,
      privateCredentialHandle.count <= Self.maxPrivateCredentialHandleLength
    else {
      throw CreditError.invalidAuthority("privateCredentialHandle is invalid")
    }
    guard !privateCredentialHandle.contains(where: { $0.isWhitespace || $0.isNewline }) else {
      throw CreditError.invalidAuthority("privateCredentialHandle must be one token")
    }
    guard createdAt.timeIntervalSince1970.isFinite else {
      throw CreditError.invalidAuthority("creation timestamp is invalid")
    }
    let resolvedPublicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    guard resolvedPublicKey.rawRepresentation.count == publicKey.count else {
      throw CreditError.invalidAuthority("public key encoding length is invalid")
    }

    self.schema = Self.currentSchema
    self.algorithm = Self.algorithm
    self.publicKey = publicKey
    self.privateCredentialHandle = privateCredentialHandle
    self.createdAt = createdAt
    self.keyID = Self.deriveKeyID(from: publicKey)
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownKeys(
      decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "treasury authority"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)

    let schema = try container.decode(String.self, forKey: .schema)
    let algorithm = try container.decode(String.self, forKey: .algorithm)
    let publicKey = try container.decode(Data.self, forKey: .publicKey)
    let keyID = try container.decode(String.self, forKey: .keyID)
    let privateCredentialHandle = try container.decode(
      String.self, forKey: .privateCredentialHandle)
    let createdAt = try container.decode(Date.self, forKey: .createdAt)

    guard schema == Self.currentSchema else {
      throw CreditError.invalidAuthority("unsupported schema: \(schema)")
    }
    guard algorithm == Self.algorithm else {
      throw CreditError.invalidAuthority("unsupported algorithm: \(algorithm)")
    }
    let derived = Self.deriveKeyID(from: publicKey)
    guard keyID == derived else {
      throw CreditError.keyIDMismatch
    }

    try self.init(
      publicKey: publicKey,
      privateCredentialHandle: privateCredentialHandle,
      createdAt: createdAt
    )
    guard self.keyID == keyID else {
      throw CreditError.keyIDMismatch
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schema, forKey: .schema)
    try container.encode(algorithm, forKey: .algorithm)
    try container.encode(publicKey, forKey: .publicKey)
    try container.encode(keyID, forKey: .keyID)
    try container.encode(privateCredentialHandle, forKey: .privateCredentialHandle)
    try container.encode(createdAt, forKey: .createdAt)
  }

  public static func deriveKeyID(from publicKey: Data) -> String {
    let separator = keyDomainSeparator.data(using: .utf8) ?? Data()
    let digest = SHA256.hash(data: separator + publicKey)
    return digest.hexString
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schema
    case algorithm
    case publicKey
    case keyID
    case privateCredentialHandle
    case createdAt
  }
}

public struct CreditCustodyEntry: Equatable, Codable, Sendable {
  public static let maxIdentifierLength = 256
  public let wallet: String
  public let oldOwner: String?
  public let newOwner: String?
  public let oldLocationCommitment: String
  public let newLocationCommitment: String
  public let previousCustodyCommitment: String

  public init(
    wallet: String,
    oldOwner: String?,
    newOwner: String?,
    oldLocationCommitment: String,
    newLocationCommitment: String,
    previousCustodyCommitment: String
  ) throws {
    guard !wallet.isEmpty, wallet.count <= Self.maxIdentifierLength else {
      throw CreditError.malformedRecord("custody wallet is invalid")
    }
    if let oldOwner {
      guard !oldOwner.isEmpty, oldOwner.count <= Self.maxIdentifierLength else {
        throw CreditError.malformedRecord("custody oldOwner is invalid")
      }
    }
    if let newOwner {
      guard !newOwner.isEmpty, newOwner.count <= Self.maxIdentifierLength else {
        throw CreditError.malformedRecord("custody newOwner is invalid")
      }
    }
    guard !oldLocationCommitment.isEmpty,
      oldLocationCommitment.count <= Self.maxIdentifierLength,
      !newLocationCommitment.isEmpty,
      newLocationCommitment.count <= Self.maxIdentifierLength,
      !previousCustodyCommitment.isEmpty,
      previousCustodyCommitment.count <= Self.maxIdentifierLength
    else {
      throw CreditError.malformedRecord("custody commitments are invalid")
    }

    self.wallet = wallet
    self.oldOwner = oldOwner
    self.newOwner = newOwner
    self.oldLocationCommitment = oldLocationCommitment
    self.newLocationCommitment = newLocationCommitment
    self.previousCustodyCommitment = previousCustodyCommitment
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownKeys(
      decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "custody entry"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let wallet = try container.decode(String.self, forKey: .wallet)
    let oldOwner = try container.decodeIfPresent(String.self, forKey: .oldOwner)
    let newOwner = try container.decodeIfPresent(String.self, forKey: .newOwner)
    let oldLocationCommitment = try container.decode(String.self, forKey: .oldLocationCommitment)
    let newLocationCommitment = try container.decode(String.self, forKey: .newLocationCommitment)
    let previousCustodyCommitment = try container.decode(
      String.self, forKey: .previousCustodyCommitment)

    try self.init(
      wallet: wallet,
      oldOwner: oldOwner,
      newOwner: newOwner,
      oldLocationCommitment: oldLocationCommitment,
      newLocationCommitment: newLocationCommitment,
      previousCustodyCommitment: previousCustodyCommitment
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(wallet, forKey: .wallet)
    try container.encode(oldOwner, forKey: .oldOwner)
    try container.encode(newOwner, forKey: .newOwner)
    try container.encode(oldLocationCommitment, forKey: .oldLocationCommitment)
    try container.encode(newLocationCommitment, forKey: .newLocationCommitment)
    try container.encode(previousCustodyCommitment, forKey: .previousCustodyCommitment)
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case wallet
    case oldOwner
    case newOwner
    case oldLocationCommitment
    case newLocationCommitment
    case previousCustodyCommitment
  }
}

public struct UnsignedCreditRecord: Equatable, Codable, Sendable {
  public static let currentVersion: UInt8 = 1
  public static let domainSeparator = "com.mikrokhoros.economy.credit.record.v1"
  public static let maxNoteLength = 256
  public static let maxIdentifierLength = 256
  public static let maxCausals = 512
  public static let maxAccounts = 10_000
  public static let genesisPriorRecordHash = String(repeating: "0", count: 64)

  public let version: UInt8
  public let kind: CreditRecordKind
  public let worldID: String
  public let keyID: String
  public let priorRecordHash: String
  public let operationID: String
  public let actionIndex: UInt64
  public let transactionID: String
  public let accounts: [String]
  public let amounts: [CreditBalance]
  public let postBalances: [CreditBalance]
  public let treasuryDelta: CreditBalance
  public let treasuryBalance: CreditBalance
  public let nominalPurchaseAmount: CreditBalance?
  public let appliedPurchaseAmount: CreditBalance?
  public let sourceWalletID: String?
  public let sourceWalletOwner: String?
  public let sourceWalletCustodyCommitment: String?
  public let issuanceAgentID: String?
  public let issuanceBackpackID: String?
  public let issuanceCoordinate: Coordinate?
  public let issuanceLocationCommitment: String?
  public let mode: WalletMode
  public let actor: String
  public let owner: String?
  public let custody: [CreditCustodyEntry]
  public let causalRecordIDs: [String]
  public let causalObjectIDs: [String]
  public let causalFunctionIDs: [String]
  public let causalMerchantIDs: [String]
  public let causalItemIDs: [String]
  public let time: Date
  public let note: String

  public init(
    version: UInt8 = Self.currentVersion,
    kind: CreditRecordKind,
    worldID: String,
    keyID: String,
    priorRecordHash: String,
    operationID: String,
    actionIndex: UInt64,
    transactionID: String,
    accounts: [String],
    amounts: [CreditBalance],
    postBalances: [CreditBalance],
    treasuryDelta: CreditBalance = .zero,
    treasuryBalance: CreditBalance = .zero,
    nominalPurchaseAmount: CreditBalance? = nil,
    appliedPurchaseAmount: CreditBalance? = nil,
    sourceWalletID: String? = nil,
    sourceWalletOwner: String? = nil,
    sourceWalletCustodyCommitment: String? = nil,
    issuanceAgentID: String? = nil,
    issuanceBackpackID: String? = nil,
    issuanceCoordinate: Coordinate? = nil,
    issuanceLocationCommitment: String? = nil,
    mode: WalletMode = .finite,
    actor: String,
    owner: String? = nil,
    custody: [CreditCustodyEntry] = [],
    causalRecordIDs: [String] = [],
    causalObjectIDs: [String] = [],
    causalFunctionIDs: [String] = [],
    causalMerchantIDs: [String] = [],
    causalItemIDs: [String] = [],
    time: Date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970)),
    note: String = ""
  ) throws {
    guard version == Self.currentVersion else {
      throw CreditError.malformedRecord("unsupported record version")
    }
    try Self.validateIdentifier(worldID, name: "worldID")
    try Self.validateIdentifier(keyID, name: "keyID")
    try Self.validateIdentifier(operationID, name: "operationID")
    try Self.validateIdentifier(transactionID, name: "transactionID")
    try Self.validateIdentifier(priorRecordHash, name: "priorRecordHash")
    try Self.validateIdentifier(actor, name: "actor")
    if let owner {
      try Self.validateIdentifier(owner, name: "owner")
    }

    guard !accounts.isEmpty,
      accounts.count <= Self.maxAccounts,
      !amounts.isEmpty,
      accounts.count == amounts.count,
      postBalances.count == accounts.count
    else {
      throw CreditError.malformedRecord("accounts, deltas, and post-balances are malformed")
    }
    guard note.count <= Self.maxNoteLength else {
      throw CreditError.malformedRecord("note exceeds max length")
    }

    guard priorRecordHash.count == 64,
      priorRecordHash.unicodeScalars.allSatisfy({
        ($0.value >= 48 && $0.value <= 57) || ($0.value >= 97 && $0.value <= 102)
      })
    else {
      throw CreditError.malformedRecord("priorRecordHash must be a lowercase SHA-256 digest")
    }

    for account in accounts {
      try Self.validateIdentifier(account, name: "account")
    }
    let uniqueAccounts = Set(accounts)
    guard uniqueAccounts.count == accounts.count else {
      throw CreditError.duplicateWalletContribution("accounts")
    }
    guard accounts == accounts.sorted() else {
      throw CreditError.malformedRecord("accounts are not in canonical wallet-id order")
    }

    let uniqueCausals = Set(causalRecordIDs)
    guard uniqueCausals.count == causalRecordIDs.count else {
      throw CreditError.duplicateIdentifier("causalRecordIDs")
    }
    try Self.validateCausalIdentifiers(causalRecordIDs, name: "causalRecordID")
    try Self.validateCausalIdentifiers(causalObjectIDs, name: "causalObjectID")
    try Self.validateCausalIdentifiers(causalFunctionIDs, name: "causalFunctionID")
    try Self.validateCausalIdentifiers(causalMerchantIDs, name: "causalMerchantID")
    try Self.validateCausalIdentifiers(causalItemIDs, name: "causalItemID")
    try Self.validateZeroDeltaKinds(kind: kind, amounts: amounts)
    try Self.validateCustodyEntries(custody)
    try Self.validateSourceContext(
      kind: kind,
      sourceWalletID: sourceWalletID,
      sourceWalletOwner: sourceWalletOwner,
      sourceWalletCustodyCommitment: sourceWalletCustodyCommitment
    )
    try Self.validateIssuanceContext(
      kind: kind,
      issuanceAgentID: issuanceAgentID,
      issuanceBackpackID: issuanceBackpackID,
      issuanceCoordinate: issuanceCoordinate,
      issuanceLocationCommitment: issuanceLocationCommitment
    )
    try Self.validatePurchaseAmounts(
      kind: kind, nominalPurchaseAmount: nominalPurchaseAmount,
      appliedPurchaseAmount: appliedPurchaseAmount)
    try Self.validateAccountingShape(
      kind: kind,
      accounts: accounts,
      amounts: amounts,
      postBalances: postBalances,
      treasuryDelta: treasuryDelta,
      nominalPurchaseAmount: nominalPurchaseAmount,
      appliedPurchaseAmount: appliedPurchaseAmount,
      sourceWalletID: sourceWalletID,
      mode: mode,
      custody: custody
    )
    try Self.validateIntegralTime(time)
    try Self.validateRecordKind(kind)

    self.version = version
    self.kind = kind
    self.worldID = worldID
    self.keyID = keyID
    self.priorRecordHash = priorRecordHash
    self.operationID = operationID
    self.actionIndex = actionIndex
    self.transactionID = transactionID
    self.accounts = accounts
    self.amounts = amounts
    self.postBalances = postBalances
    self.treasuryDelta = treasuryDelta
    self.treasuryBalance = treasuryBalance
    self.nominalPurchaseAmount = nominalPurchaseAmount
    self.appliedPurchaseAmount = appliedPurchaseAmount
    self.sourceWalletID = sourceWalletID
    self.sourceWalletOwner = sourceWalletOwner
    self.sourceWalletCustodyCommitment = sourceWalletCustodyCommitment
    self.issuanceAgentID = issuanceAgentID
    self.issuanceBackpackID = issuanceBackpackID
    self.issuanceCoordinate = issuanceCoordinate
    self.issuanceLocationCommitment = issuanceLocationCommitment
    self.mode = mode
    self.actor = actor
    self.owner = owner
    self.custody = custody
    self.causalRecordIDs = causalRecordIDs
    self.causalObjectIDs = causalObjectIDs
    self.causalFunctionIDs = causalFunctionIDs
    self.causalMerchantIDs = causalMerchantIDs
    self.causalItemIDs = causalItemIDs
    self.time = time
    self.note = note
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownKeys(
      decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)), context: "credit record")
    let container = try decoder.container(keyedBy: CodingKeys.self)

    let version = try container.decode(UInt8.self, forKey: .version)
    let kind = try container.decode(CreditRecordKind.self, forKey: .kind)
    let worldID = try container.decode(String.self, forKey: .worldID)
    let keyID = try container.decode(String.self, forKey: .keyID)
    let priorRecordHash = try container.decode(String.self, forKey: .priorRecordHash)
    let operationID = try container.decode(String.self, forKey: .operationID)
    let actionIndex = try container.decode(UInt64.self, forKey: .actionIndex)
    let transactionID = try container.decode(String.self, forKey: .transactionID)
    let accounts = try container.decode([String].self, forKey: .accounts)
    let amounts = try container.decode([CreditBalance].self, forKey: .amounts)
    let postBalances = try container.decode([CreditBalance].self, forKey: .postBalances)
    let treasuryDelta =
      try container.decodeIfPresent(CreditBalance.self, forKey: .treasuryDelta) ?? .zero
    let treasuryBalance =
      try container.decodeIfPresent(CreditBalance.self, forKey: .treasuryBalance) ?? .zero
    let nominalPurchaseAmount = try container.decodeIfPresent(
      CreditBalance.self, forKey: .nominalPurchaseAmount)
    let appliedPurchaseAmount = try container.decodeIfPresent(
      CreditBalance.self, forKey: .appliedPurchaseAmount)
    let sourceWalletID = try container.decodeIfPresent(String.self, forKey: .sourceWalletID)
    let sourceWalletOwner = try container.decodeIfPresent(String.self, forKey: .sourceWalletOwner)
    let sourceWalletCustodyCommitment = try container.decodeIfPresent(
      String.self,
      forKey: .sourceWalletCustodyCommitment
    )
    let issuanceAgentID = try container.decodeIfPresent(String.self, forKey: .issuanceAgentID)
    let issuanceBackpackID = try container.decodeIfPresent(String.self, forKey: .issuanceBackpackID)
    let issuanceCoordinate = try container.decodeIfPresent(
      Coordinate.self, forKey: .issuanceCoordinate)
    let issuanceLocationCommitment = try container.decodeIfPresent(
      String.self,
      forKey: .issuanceLocationCommitment
    )
    let mode = try container.decode(WalletMode.self, forKey: .mode)
    let actor = try container.decode(String.self, forKey: .actor)
    let owner = try container.decodeIfPresent(String.self, forKey: .owner)
    let custody = try container.decodeIfPresent([CreditCustodyEntry].self, forKey: .custody) ?? []
    let causalRecordIDs =
      try container.decodeIfPresent([String].self, forKey: .causalRecordIDs) ?? []
    let causalObjectIDs =
      try container.decodeIfPresent([String].self, forKey: .causalObjectIDs) ?? []
    let causalFunctionIDs =
      try container.decodeIfPresent([String].self, forKey: .causalFunctionIDs) ?? []
    let causalMerchantIDs =
      try container.decodeIfPresent([String].self, forKey: .causalMerchantIDs) ?? []
    let causalItemIDs = try container.decodeIfPresent([String].self, forKey: .causalItemIDs) ?? []
    let time = try container.decode(Int64.self, forKey: .time)
    let interval = TimeInterval(time)
    guard Int64(exactly: interval) == time else {
      throw CreditError.malformedTime
    }
    let note = try container.decode(String.self, forKey: .note)

    try self.init(
      version: version,
      kind: kind,
      worldID: worldID,
      keyID: keyID,
      priorRecordHash: priorRecordHash,
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
      causalRecordIDs: causalRecordIDs,
      causalObjectIDs: causalObjectIDs,
      causalFunctionIDs: causalFunctionIDs,
      causalMerchantIDs: causalMerchantIDs,
      causalItemIDs: causalItemIDs,
      time: Date(timeIntervalSince1970: interval),
      note: note
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(version, forKey: .version)
    try container.encode(kind, forKey: .kind)
    try container.encode(worldID, forKey: .worldID)
    try container.encode(keyID, forKey: .keyID)
    try container.encode(priorRecordHash, forKey: .priorRecordHash)
    try container.encode(operationID, forKey: .operationID)
    try container.encode(actionIndex, forKey: .actionIndex)
    try container.encode(transactionID, forKey: .transactionID)
    try container.encode(accounts, forKey: .accounts)
    try container.encode(amounts, forKey: .amounts)
    try container.encode(postBalances, forKey: .postBalances)
    try container.encode(treasuryDelta, forKey: .treasuryDelta)
    try container.encode(treasuryBalance, forKey: .treasuryBalance)
    try container.encode(nominalPurchaseAmount, forKey: .nominalPurchaseAmount)
    try container.encode(appliedPurchaseAmount, forKey: .appliedPurchaseAmount)
    try container.encode(sourceWalletID, forKey: .sourceWalletID)
    try container.encode(sourceWalletOwner, forKey: .sourceWalletOwner)
    try container.encode(sourceWalletCustodyCommitment, forKey: .sourceWalletCustodyCommitment)
    try container.encode(issuanceAgentID, forKey: .issuanceAgentID)
    try container.encode(issuanceBackpackID, forKey: .issuanceBackpackID)
    try container.encode(issuanceCoordinate, forKey: .issuanceCoordinate)
    try container.encode(issuanceLocationCommitment, forKey: .issuanceLocationCommitment)
    try container.encode(mode, forKey: .mode)
    try container.encode(actor, forKey: .actor)
    try container.encode(owner, forKey: .owner)
    try container.encode(custody, forKey: .custody)
    try container.encode(causalRecordIDs, forKey: .causalRecordIDs)
    try container.encode(causalObjectIDs, forKey: .causalObjectIDs)
    try container.encode(causalFunctionIDs, forKey: .causalFunctionIDs)
    try container.encode(causalMerchantIDs, forKey: .causalMerchantIDs)
    try container.encode(causalItemIDs, forKey: .causalItemIDs)
    try container.encode(Int64(time.timeIntervalSince1970), forKey: .time)
    try container.encode(note, forKey: .note)
  }

  public var recordID: String { "\(operationID)#\(actionIndex)" }

  public func canonicalBytes() throws -> Data {
    let sortedTriples = canonicalWalletTriples()
    let sortedCustody = custody.map {
      CanonicalCustodyEntry(
        wallet: $0.wallet,
        oldOwner: $0.oldOwner,
        newOwner: $0.newOwner,
        oldLocationCommitment: $0.oldLocationCommitment,
        newLocationCommitment: $0.newLocationCommitment,
        previousCustodyCommitment: $0.previousCustodyCommitment
      )
    }

    let payload = CanonicalUnsignedCreditRecord(
      domain: Self.domainSeparator,
      version: version,
      kind: kind.rawValue,
      worldID: worldID,
      keyID: keyID,
      priorRecordHash: priorRecordHash,
      operationID: operationID,
      actionIndex: actionIndex,
      transactionID: transactionID,
      accounts: sortedTriples.map(\.account),
      amounts: sortedTriples.map(\.amount),
      postBalances: sortedTriples.map(\.postBalance),
      treasuryDelta: treasuryDelta.decimalText,
      treasuryBalance: treasuryBalance.decimalText,
      nominalPurchaseAmount: nominalPurchaseAmount?.decimalText,
      appliedPurchaseAmount: appliedPurchaseAmount?.decimalText,
      sourceWalletID: sourceWalletID,
      sourceWalletOwner: sourceWalletOwner,
      sourceWalletCustodyCommitment: sourceWalletCustodyCommitment,
      issuanceAgentID: issuanceAgentID,
      issuanceBackpackID: issuanceBackpackID,
      issuanceCoordinate: issuanceCoordinate?.description,
      issuanceLocationCommitment: issuanceLocationCommitment,
      mode: mode.rawValue,
      actor: actor,
      owner: owner,
      custody: sortedCustody,
      causalRecordIDs: causalRecordIDs,
      causalObjectIDs: causalObjectIDs,
      causalFunctionIDs: causalFunctionIDs,
      causalMerchantIDs: causalMerchantIDs,
      causalItemIDs: causalItemIDs,
      time: Int64(time.timeIntervalSince1970),
      note: note
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(payload)
  }

  public func canonicalHash() throws -> String {
    let digest = SHA256.hash(data: try canonicalBytes())
    return digest.hexString
  }

  private func canonicalWalletTriples() -> [CanonicalWalletTriple] {
    var triples: [CanonicalWalletTriple] = []
    for index in accounts.indices {
      triples.append(
        CanonicalWalletTriple(
          account: accounts[index],
          amount: amounts[index].decimalText,
          postBalance: postBalances[index].decimalText
        )
      )
    }
    return triples.sorted()
  }

  private static func validateRecordKind(_ kind: CreditRecordKind) throws {
    switch kind {
    case .registration, .deposit, .deduction, .transfer, .purchase, .modeChange, .custodyChange:
      return
    }
  }

  private static func validateIdentifier(_ value: String, name: String) throws {
    guard !value.isEmpty else {
      throw CreditError.malformedRecord("\(name) is missing")
    }
    guard value.count <= maxIdentifierLength else {
      throw CreditError.malformedRecord("\(name) exceeds maximum length")
    }
    guard
      !value.contains(where: {
        $0.isWhitespace || $0.isNewline
          || $0.isASCII && $0.asciiValue.map({ $0 < 0x20 || $0 == 0x7f }) == true
      })
    else {
      throw CreditError.malformedRecord("\(name) must be one printable token")
    }
  }

  private static func validateZeroDeltaKinds(kind: CreditRecordKind, amounts: [CreditBalance])
    throws
  {
    switch kind {
    case .registration, .modeChange, .custodyChange:
      guard amounts.allSatisfy({ $0.minorUnits == 0 }) else {
        throw CreditError.malformedRecord("non-zero amounts for zero-delta record kind")
      }
    default:
      return
    }
  }

  private static func validateCausalIdentifiers(_ identifiers: [String], name: String) throws {
    for identifier in identifiers {
      try validateIdentifier(identifier, name: name)
    }
    guard identifiers.count <= maxCausals else {
      throw CreditError.malformedRecord("\(name) exceeds maximum size")
    }
    let unique = Set(identifiers)
    guard unique.count == identifiers.count else {
      throw CreditError.duplicateIdentifier(name)
    }
    guard identifiers == identifiers.sorted() else {
      throw CreditError.malformedRecord("\(name) values are not in canonical order")
    }
  }

  private static func validateCustodyEntries(_ custody: [CreditCustodyEntry]) throws {
    if custody.isEmpty { return }
    guard custody.count <= maxAccounts else {
      throw CreditError.malformedRecord("too many custody entries")
    }
    let wallets = custody.map(\.wallet)
    let uniqueWallets = Set(wallets)
    guard uniqueWallets.count == wallets.count else {
      throw CreditError.duplicateWalletContribution("custody.wallet")
    }
    guard wallets == wallets.sorted() else {
      throw CreditError.malformedRecord("custody entries are not in canonical wallet-id order")
    }
  }

  private static func validateSourceContext(
    kind: CreditRecordKind,
    sourceWalletID: String?,
    sourceWalletOwner: String?,
    sourceWalletCustodyCommitment: String?
  ) throws {
    let hasSource =
      sourceWalletID != nil || sourceWalletOwner != nil || sourceWalletCustodyCommitment != nil
    if !hasSource {
      switch kind {
      case .deduction, .transfer, .purchase:
        throw CreditError.malformedRecord("debit record is missing source wallet context")
      default:
        return
      }
    }
    guard let sourceWalletID, let sourceWalletCustodyCommitment else {
      throw CreditError.malformedRecord("source wallet context is incomplete")
    }
    try validateIdentifier(sourceWalletID, name: "sourceWalletID")
    if let sourceWalletOwner {
      try validateIdentifier(sourceWalletOwner, name: "sourceWalletOwner")
    }
    try validateIdentifier(sourceWalletCustodyCommitment, name: "sourceWalletCustodyCommitment")
    if kind == .registration {
      throw CreditError.malformedRecord("registration cannot bind source wallet context")
    }
  }

  private static func validateIssuanceContext(
    kind: CreditRecordKind,
    issuanceAgentID: String?,
    issuanceBackpackID: String?,
    issuanceCoordinate: Coordinate?,
    issuanceLocationCommitment: String?
  ) throws {
    if kind == .registration {
      guard let issuanceAgentID, let issuanceBackpackID, let issuanceCoordinate,
        let issuanceLocationCommitment
      else {
        throw CreditError.malformedRecord("registration is missing issuance provenance")
      }
      try validateIdentifier(issuanceAgentID, name: "issuanceAgentID")
      try validateIdentifier(issuanceBackpackID, name: "issuanceBackpackID")
      try validateIdentifier(issuanceLocationCommitment, name: "issuanceLocationCommitment")
      guard issuanceCoordinate == Coordinate(x: 4, y: 0) else {
        throw CreditError.malformedRecord("registration issuance coordinate must be (4,0)")
      }
      return
    }
    guard issuanceAgentID == nil, issuanceBackpackID == nil,
      issuanceCoordinate == nil, issuanceLocationCommitment == nil
    else {
      throw CreditError.malformedRecord("issuance provenance is only valid for registration")
    }
  }

  private static func validatePurchaseAmounts(
    kind: CreditRecordKind,
    nominalPurchaseAmount: CreditBalance?,
    appliedPurchaseAmount: CreditBalance?
  ) throws {
    if kind == .purchase {
      guard let nominalPurchaseAmount, let appliedPurchaseAmount else {
        throw CreditError.malformedRecord("purchase requires both nominal and applied amounts")
      }
      guard nominalPurchaseAmount.minorUnits > 0,
        appliedPurchaseAmount.minorUnits >= 0,
        appliedPurchaseAmount.minorUnits <= nominalPurchaseAmount.minorUnits
      else {
        throw CreditError.malformedRecord("purchase nominal/applied amounts are invalid")
      }
      return
    }
    guard nominalPurchaseAmount == nil && appliedPurchaseAmount == nil else {
      throw CreditError.malformedRecord("purchase fields are only valid for purchase records")
    }
  }

  private static func validateAccountingShape(
    kind: CreditRecordKind,
    accounts: [String],
    amounts: [CreditBalance],
    postBalances: [CreditBalance],
    treasuryDelta: CreditBalance,
    nominalPurchaseAmount: CreditBalance?,
    appliedPurchaseAmount: CreditBalance?,
    sourceWalletID: String?,
    mode: WalletMode,
    custody: [CreditCustodyEntry]
  ) throws {
    guard accounts.count == amounts.count, accounts.count == postBalances.count else {
      throw CreditError.malformedRecord("accounting vectors have different lengths")
    }
    switch kind {
    case .registration:
      guard accounts.count == 1, amounts[0].minorUnits == 0,
        postBalances[0].minorUnits == 0, treasuryDelta.minorUnits == 0,
        custody.isEmpty
      else {
        throw CreditError.malformedRecord("registration accounting shape is invalid")
      }
    case .deposit:
      guard accounts.count == 1, amounts[0].minorUnits > 0,
        treasuryDelta.minorUnits == -amounts[0].minorUnits,
        custody.isEmpty
      else {
        throw CreditError.malformedRecord("deposit accounting shape is invalid")
      }
    case .deduction:
      guard accounts.count == 1, amounts[0].minorUnits < 0,
        amounts[0].minorUnits != Int64.min,
        treasuryDelta.minorUnits == -amounts[0].minorUnits,
        sourceWalletID == accounts[0], custody.isEmpty
      else {
        throw CreditError.malformedRecord("deduction accounting shape is invalid")
      }
    case .transfer:
      guard accounts.count == 2,
        let sourceWalletID,
        let sourceIndex = accounts.firstIndex(of: sourceWalletID),
        amounts[sourceIndex].minorUnits < 0,
        amounts[sourceIndex].minorUnits != Int64.min
      else {
        throw CreditError.malformedRecord("transfer source accounting shape is invalid")
      }
      let destinationIndex = sourceIndex == 0 ? 1 : 0
      guard amounts[destinationIndex].minorUnits > 0,
        amounts[destinationIndex].minorUnits == -amounts[sourceIndex].minorUnits,
        treasuryDelta.minorUnits == 0, custody.isEmpty
      else {
        throw CreditError.malformedRecord("transfer accounting shape is invalid")
      }
    case .purchase:
      guard accounts.count == 1, sourceWalletID == accounts[0],
        let nominalPurchaseAmount, let appliedPurchaseAmount,
        amounts[0].minorUnits == -appliedPurchaseAmount.minorUnits,
        treasuryDelta.minorUnits == appliedPurchaseAmount.minorUnits,
        custody.isEmpty
      else {
        throw CreditError.malformedRecord("purchase accounting shape is invalid")
      }
      switch mode {
      case .finite:
        guard appliedPurchaseAmount == nominalPurchaseAmount else {
          throw CreditError.malformedRecord("finite purchase must apply the nominal amount")
        }
      case .unlimited:
        guard appliedPurchaseAmount.minorUnits == 0 else {
          throw CreditError.malformedRecord("unlimited purchase must apply zero")
        }
      }
    case .modeChange:
      guard accounts.count == 1, amounts[0].minorUnits == 0,
        treasuryDelta.minorUnits == 0, custody.isEmpty
      else {
        throw CreditError.malformedRecord("mode-change accounting shape is invalid")
      }
    case .custodyChange:
      guard !custody.isEmpty, custody.map(\.wallet) == accounts,
        amounts.allSatisfy({ $0.minorUnits == 0 }),
        treasuryDelta.minorUnits == 0
      else {
        throw CreditError.malformedRecord("custody-change accounting shape is invalid")
      }
    }
  }

  private static func validateIntegralTime(_ time: Date) throws {
    let interval = time.timeIntervalSince1970
    guard interval.isFinite, interval == floor(interval) else {
      throw CreditError.malformedTime
    }
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case version
    case kind
    case worldID
    case keyID
    case priorRecordHash
    case operationID
    case actionIndex
    case transactionID
    case accounts
    case amounts
    case postBalances
    case treasuryDelta
    case treasuryBalance
    case nominalPurchaseAmount
    case appliedPurchaseAmount
    case sourceWalletID
    case sourceWalletOwner
    case sourceWalletCustodyCommitment
    case issuanceAgentID
    case issuanceBackpackID
    case issuanceCoordinate
    case issuanceLocationCommitment
    case mode
    case actor
    case owner
    case custody
    case causalRecordIDs
    case causalObjectIDs
    case causalFunctionIDs
    case causalMerchantIDs
    case causalItemIDs
    case time
    case note
  }
}

public struct SignedCreditRecord: Equatable, Codable, Sendable {
  public static let signedDomainSeparator = "com.mikrokhoros.economy.credit.record.signed.v1"
  public static let expectedSignatureLength = 64
  public static let expectedPublicKeyLength = 32

  public let unsigned: UnsignedCreditRecord
  public let signature: Data
  public let signerPublicKey: Data

  public init(unsigned: UnsignedCreditRecord, signature: Data, signerPublicKey: Data) throws {
    guard signature.count == Self.expectedSignatureLength else {
      throw CreditError.malformedRecord("signature length is invalid")
    }
    guard signerPublicKey.count == Self.expectedPublicKeyLength else {
      throw CreditError.malformedRecord("signer public key length is invalid")
    }

    self.unsigned = unsigned
    self.signature = signature
    self.signerPublicKey = signerPublicKey
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownKeys(
      decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)), context: "signed credit record")
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let unsigned = try container.decode(UnsignedCreditRecord.self, forKey: .unsigned)
    let signature = try container.decode(Data.self, forKey: .signature)
    let signerPublicKey = try container.decode(Data.self, forKey: .signerPublicKey)

    try self.init(
      unsigned: unsigned,
      signature: signature,
      signerPublicKey: signerPublicKey
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(unsigned, forKey: .unsigned)
    try container.encode(signature, forKey: .signature)
    try container.encode(signerPublicKey, forKey: .signerPublicKey)
  }

  public func canonicalBytes() throws -> Data {
    var bytes = Data(SignedCreditRecord.signedDomainSeparator.utf8)
    let unsignedBytes = try unsigned.canonicalBytes()
    appendLengthPrefixed(&bytes, unsignedBytes)
    appendLengthPrefixed(&bytes, signature)
    appendLengthPrefixed(&bytes, signerPublicKey)
    return bytes
  }

  public func recordHash() throws -> String {
    let digest = SHA256.hash(data: try canonicalBytes())
    return digest.hexString
  }

  public var recordID: String { unsigned.recordID }

  private func appendLengthPrefixed(_ output: inout Data, _ value: Data) {
    var length = UInt64(value.count).bigEndian
    withUnsafeBytes(of: &length) { bytes in
      output.append(contentsOf: bytes)
    }
    output.append(value)
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case unsigned
    case signature
    case signerPublicKey
  }
}

public struct CreditRecordSigner {
  public let authority: TreasuryAuthorityDocument
  private let privateKey: Curve25519.Signing.PrivateKey

  public init(privateCredentialHandle: String, privateKeyData: Data? = nil) throws {
    if let privateKeyData {
      privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
    } else {
      privateKey = Curve25519.Signing.PrivateKey()
    }

    authority = try TreasuryAuthorityDocument(
      publicKey: privateKey.publicKey.rawRepresentation,
      privateCredentialHandle: privateCredentialHandle
    )
  }

  public init(authority: TreasuryAuthorityDocument, privateKeyData: Data) throws {
    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
    guard privateKey.publicKey.rawRepresentation == authority.publicKey else {
      throw CreditError.keyMismatch
    }
    let derivedKeyID = TreasuryAuthorityDocument.deriveKeyID(
      from: privateKey.publicKey.rawRepresentation)
    guard derivedKeyID == authority.keyID else {
      throw CreditError.keyIDMismatch
    }
    self.authority = authority
    self.privateKey = privateKey
  }

  public func sign(_ record: UnsignedCreditRecord) throws -> SignedCreditRecord {
    guard record.keyID == authority.keyID else {
      throw CreditError.keyIDMismatch
    }
    let signature = try privateKey.signature(for: record.canonicalBytes())
    let signatureBytes = Data(signature)
    return try SignedCreditRecord(
      unsigned: record,
      signature: signatureBytes,
      signerPublicKey: privateKey.publicKey.rawRepresentation
    )
  }
}

public struct CreditRecordVerifier {
  public let authority: TreasuryAuthorityDocument
  public let expectedWorld: String?

  public init(authority: TreasuryAuthorityDocument, expectedWorld: String? = nil) {
    self.authority = authority
    self.expectedWorld = expectedWorld
  }

  public func verify(_ signed: SignedCreditRecord) throws {
    if let expectedWorld, expectedWorld != signed.unsigned.worldID {
      throw CreditError.wrongWorld
    }
    if signed.unsigned.keyID != authority.keyID {
      throw CreditError.keyIDMismatch
    }
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: authority.publicKey)
    if publicKey.rawRepresentation != signed.signerPublicKey {
      throw CreditError.keyMismatch
    }

    let canonicalBytes = try signed.unsigned.canonicalBytes()
    guard publicKey.isValidSignature(signed.signature, for: canonicalBytes) else {
      throw CreditError.signatureInvalid
    }
  }
}

public struct CreditRecordChain {
  public let expectedWorld: String?
  public let verifier: CreditRecordVerifier
  public private(set) var lastRecordHash: String?
  private var recordIDs: Set<String>
  private var transactionIDs: Set<String>
  private var registeredWalletIDs: Set<String>

  public init(authority: TreasuryAuthorityDocument, expectedWorld: String? = nil) {
    verifier = CreditRecordVerifier(authority: authority, expectedWorld: expectedWorld)
    self.expectedWorld = expectedWorld
    lastRecordHash = nil
    recordIDs = []
    transactionIDs = []
    registeredWalletIDs = []
  }

  public mutating func append(_ record: SignedCreditRecord) throws {
    try verifier.verify(record)

    let expectedPrior = lastRecordHash ?? UnsignedCreditRecord.genesisPriorRecordHash
    if record.unsigned.priorRecordHash != expectedPrior {
      throw CreditError.chainOrderMismatch(
        expected: expectedPrior, found: record.unsigned.priorRecordHash)
    }
    if recordIDs.contains(record.recordID) {
      throw CreditError.duplicateRecordID(record.recordID)
    }
    if transactionIDs.contains(record.unsigned.transactionID) {
      throw CreditError.duplicateIdentifier("transactionID")
    }
    if record.unsigned.kind == .registration {
      guard let walletID = record.unsigned.accounts.first,
        !registeredWalletIDs.contains(walletID)
      else {
        throw CreditError.duplicateIdentifier("wallet registration")
      }
      registeredWalletIDs.insert(walletID)
    }

    lastRecordHash = try record.recordHash()
    recordIDs.insert(record.recordID)
    transactionIDs.insert(record.unsigned.transactionID)
  }
}

extension Digest {
  fileprivate var hexString: String {
    reduce(into: "") { result, byte in
      result.append(String(format: "%02x", byte))
    }
  }
}

private struct CanonicalUnsignedCreditRecord: Codable {
  let domain: String
  let version: UInt8
  let kind: String
  let worldID: String
  let keyID: String
  let priorRecordHash: String
  let operationID: String
  let actionIndex: UInt64
  let transactionID: String
  let accounts: [String]
  let amounts: [String]
  let postBalances: [String]
  let treasuryDelta: String
  let treasuryBalance: String
  let nominalPurchaseAmount: String?
  let appliedPurchaseAmount: String?
  let sourceWalletID: String?
  let sourceWalletOwner: String?
  let sourceWalletCustodyCommitment: String?
  let issuanceAgentID: String?
  let issuanceBackpackID: String?
  let issuanceCoordinate: String?
  let issuanceLocationCommitment: String?
  let mode: String
  let actor: String
  let owner: String?
  let custody: [CanonicalCustodyEntry]
  let causalRecordIDs: [String]
  let causalObjectIDs: [String]
  let causalFunctionIDs: [String]
  let causalMerchantIDs: [String]
  let causalItemIDs: [String]
  let time: Int64
  let note: String
}

private struct CanonicalCustodyEntry: Codable {
  let wallet: String
  let oldOwner: String?
  let newOwner: String?
  let oldLocationCommitment: String
  let newLocationCommitment: String
  let previousCustodyCommitment: String
}

private struct CanonicalWalletTriple: Comparable {
  let account: String
  let amount: String
  let postBalance: String

  static func < (lhs: CanonicalWalletTriple, rhs: CanonicalWalletTriple) -> Bool {
    lhs.account < rhs.account
  }
}
