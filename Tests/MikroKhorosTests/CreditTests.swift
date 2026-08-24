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

import Crypto
import Foundation
import XCTest

@testable import MikroKhoros

final class CreditTests: XCTestCase {
  private func data(hex: String) throws -> Data {
    guard hex.count.isMultiple(of: 2) else {
      throw MikroKhorosError.persistence("test vector has odd-length hex")
    }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else {
        throw MikroKhorosError.persistence("test vector has invalid hex")
      }
      bytes.append(byte)
      index = next
    }
    return Data(bytes)
  }

  func testSHA256AndEd25519KnownVectors() throws {
    XCTAssertEqual(
      SHA256Digest.hex(Data("abc".utf8)),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )

    // RFC 8032, Ed25519 test vector 1 (empty message).
    let seed = try data(
      hex: "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
    )
    let expectedPublicKey = try data(
      hex: "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
    )
    let expectedSignature = try data(
      hex: "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155"
        + "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
    )
    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    XCTAssertEqual(privateKey.publicKey.rawRepresentation, expectedPublicKey)
    XCTAssertTrue(privateKey.publicKey.isValidSignature(expectedSignature, for: Data()))
    // swift-crypto uses hedged Ed25519 signing, so a newly generated signature
    // is intentionally not byte-identical to the deterministic RFC vector.
    let signature = try privateKey.signature(for: Data())
    XCTAssertTrue(privateKey.publicKey.isValidSignature(signature, for: Data()))
  }

  func testCreditAmountRejectsInvalidCanonicalSyntaxAndNumericExtremes() throws {
    XCTAssertEqual(try CreditAmount.parse("1").minorUnits, 100)
    XCTAssertEqual(try CreditAmount.parse("12.30").minorUnits, 1230)
    XCTAssertEqual(try CreditAmount.parse("12.3").decimalText, "12.30")

    XCTAssertThrowsError(try CreditAmount.parse("0"))
    XCTAssertThrowsError(try CreditAmount.parse("01.00"))
    XCTAssertThrowsError(try CreditAmount.parse("-0.00"))
    XCTAssertThrowsError(try CreditAmount.parse("nan"))
    XCTAssertThrowsError(try CreditAmount.parse("+1.00"))
    XCTAssertThrowsError(try CreditAmount.parse("1e3"))
    XCTAssertThrowsError(try CreditAmount.parse("1.234"))
    XCTAssertThrowsError(try CreditAmount.parse("１２.34"))  // non-ASCII digit
    XCTAssertThrowsError(try CreditAmount.parse("92233720368547758.08"))  // Int64 overflow
  }

  func testCreditBalanceRejectsNegativeZeroAndKeepsInt64MinBounds() {
    XCTAssertThrowsError(try CreditBalance(minorUnits: Int64.min))
    XCTAssertNoThrow(try CreditBalance(minorUnits: 0))
    XCTAssertNoThrow(try CreditBalance.parse("0"))

    XCTAssertThrowsError(try CreditBalance.parse("-0"))
    XCTAssertThrowsError(try CreditBalance.parse("00.10"))
    XCTAssertThrowsError(try CreditBalance.parse("NaN"))
    XCTAssertThrowsError(try CreditBalance.parse("∞"))

    let positive = try! CreditBalance.parse("10.00")
    XCTAssertEqual(positive.minorUnits, 1000)
    let negative = try! CreditBalance.parse("-1.01")
    XCTAssertEqual(negative.minorUnits, -101)
  }

  func testExposureTotalsAreOrderIndependentAndCappedIndependently() throws {
    let entries: [(String, Int64)] = [
      ("positive", Int64.max),
      ("debt", -Int64.max),
      ("zero", 0),
    ]
    for ordering in [entries, Array(entries.reversed()), [entries[1], entries[2], entries[0]]] {
      let ledger = try CreditLedger(contributions: Dictionary(uniqueKeysWithValues: ordering))
      XCTAssertEqual(ledger.totalPositive, UInt64(Int64.max))
      XCTAssertEqual(ledger.totalDebt, UInt64(Int64.max))
      XCTAssertEqual(ledger.expectedTreasurySignedDifference, 0)
      XCTAssertEqual(ledger.netIssued, 0)
    }

    XCTAssertThrowsError(
      try CreditLedger(contributions: ["a": Int64.max, "b": 1])
    )
    XCTAssertThrowsError(
      try CreditLedger(contributions: ["a": -Int64.max, "b": -1])
    )
  }

  func testTreasuryAuthorityDocumentRejectsInvalidSchemaAndHandle() throws {
    let signer = try CreditRecordSigner(privateCredentialHandle: "authority")
    let encoded = try JSONEncoder().encode(signer.authority)
    let decoded = try JSONDecoder().decode(TreasuryAuthorityDocument.self, from: encoded)
    XCTAssertEqual(decoded.keyID, signer.authority.keyID)
    XCTAssertEqual(decoded.privateCredentialHandle, signer.authority.privateCredentialHandle)
    XCTAssertEqual(decoded.publicKey, signer.authority.publicKey)
    XCTAssertEqual(decoded.schema, TreasuryAuthorityDocument.currentSchema)

    var object =
      try JSONSerialization.jsonObject(with: encoded, options: []) as? [String: Any] ?? [:]
    object["schema"] = "2"
    XCTAssertThrowsError(
      try JSONDecoder().decode(
        TreasuryAuthorityDocument.self, from: try JSONSerialization.data(withJSONObject: object)))
    object["schema"] = TreasuryAuthorityDocument.currentSchema
    object["keyID"] = "bad-key-id"
    XCTAssertThrowsError(
      try JSONDecoder().decode(
        TreasuryAuthorityDocument.self, from: try JSONSerialization.data(withJSONObject: object)))
    object["keyID"] = signer.authority.keyID
    object["privateCredentialHandle"] = ""
    XCTAssertThrowsError(
      try JSONDecoder().decode(
        TreasuryAuthorityDocument.self, from: try JSONSerialization.data(withJSONObject: object)))
  }

  func testUnsignedRecordRejectsNonCanonicalOrderingForCanonicalInputs() throws {
    let signer = try CreditRecordSigner(privateCredentialHandle: "canonical-order")

    XCTAssertThrowsError(
      try UnsignedCreditRecord(
        kind: .transfer,
        worldID: "world-order",
        keyID: signer.authority.keyID,
        priorRecordHash: UnsignedCreditRecord.genesisPriorRecordHash,
        operationID: "transfer-order",
        actionIndex: 1,
        transactionID: "transfer-order-tx",
        accounts: ["wallet-b", "wallet-a"],
        amounts: [try CreditBalance(minorUnits: -5), try CreditBalance(minorUnits: 5)],
        postBalances: [try CreditBalance(minorUnits: 0), try CreditBalance(minorUnits: 10)],
        sourceWalletID: "wallet-a",
        sourceWalletCustodyCommitment: "custody-order",
        actor: "agent-alpha",
        time: Date(timeIntervalSince1970: 1)
      )
    )

    XCTAssertThrowsError(
      try UnsignedCreditRecord(
        kind: .transfer,
        worldID: "world-order",
        keyID: signer.authority.keyID,
        priorRecordHash: UnsignedCreditRecord.genesisPriorRecordHash,
        operationID: "transfer-causal",
        actionIndex: 2,
        transactionID: "transfer-causal-tx",
        accounts: ["wallet-a", "wallet-b"],
        amounts: [try CreditBalance(minorUnits: -5), try CreditBalance(minorUnits: 5)],
        postBalances: [try CreditBalance(minorUnits: 0), try CreditBalance(minorUnits: 10)],
        sourceWalletID: "wallet-a",
        sourceWalletCustodyCommitment: "custody-order",
        actor: "agent-alpha",
        causalRecordIDs: ["b-record", "a-record"],
        time: Date(timeIntervalSince1970: 2)
      )
    )

    let accepted = try UnsignedCreditRecord(
      kind: .transfer,
      worldID: "world-order",
      keyID: signer.authority.keyID,
      priorRecordHash: UnsignedCreditRecord.genesisPriorRecordHash,
      operationID: "transfer-canonical",
      actionIndex: 3,
      transactionID: "transfer-canonical-tx",
      accounts: ["wallet-a", "wallet-b"],
      amounts: [try CreditBalance(minorUnits: -5), try CreditBalance(minorUnits: 5)],
      postBalances: [try CreditBalance(minorUnits: 0), try CreditBalance(minorUnits: 10)],
      sourceWalletID: "wallet-a",
      sourceWalletCustodyCommitment: "custody-order",
      actor: "agent-alpha",
      causalRecordIDs: ["a-record", "b-record"],
      time: Date(timeIntervalSince1970: 3)
    )
    XCTAssertEqual(accepted.accounts, ["wallet-a", "wallet-b"])
  }

  func testDebitRecordsRequireSourceWalletIDAndCustodyCommitment() throws {
    let signer = try CreditRecordSigner(privateCredentialHandle: "debit-source")

    XCTAssertThrowsError(
      try UnsignedCreditRecord(
        kind: .deduction,
        worldID: "world-source",
        keyID: signer.authority.keyID,
        priorRecordHash: UnsignedCreditRecord.genesisPriorRecordHash,
        operationID: "deduction-no-source",
        actionIndex: 1,
        transactionID: "deduction-no-source-tx",
        accounts: ["wallet-a"],
        amounts: [try CreditBalance(minorUnits: -50)],
        postBalances: [try CreditBalance(minorUnits: 50)],
        actor: "agent-alpha",
        time: Date(timeIntervalSince1970: 4)
      )
    )

    XCTAssertThrowsError(
      try UnsignedCreditRecord(
        kind: .deduction,
        worldID: "world-source",
        keyID: signer.authority.keyID,
        priorRecordHash: UnsignedCreditRecord.genesisPriorRecordHash,
        operationID: "deduction-incomplete-source",
        actionIndex: 2,
        transactionID: "deduction-incomplete-source-tx",
        accounts: ["wallet-a"],
        amounts: [try CreditBalance(minorUnits: -50)],
        postBalances: [try CreditBalance(minorUnits: 50)],
        sourceWalletID: "wallet-a",
        actor: "agent-alpha",
        time: Date(timeIntervalSince1970: 5)
      )
    )

    let deduction = try UnsignedCreditRecord(
      kind: .deduction,
      worldID: "world-source",
      keyID: signer.authority.keyID,
      priorRecordHash: UnsignedCreditRecord.genesisPriorRecordHash,
      operationID: "deduction-complete-source",
      actionIndex: 3,
      transactionID: "deduction-complete-source-tx",
      accounts: ["wallet-a"],
      amounts: [try CreditBalance(minorUnits: -50)],
      postBalances: [try CreditBalance(minorUnits: 50)],
      treasuryDelta: try CreditBalance(minorUnits: 50),
      sourceWalletID: "wallet-a",
      sourceWalletCustodyCommitment: "custody-complete-source",
      actor: "agent-alpha",
      time: Date(timeIntervalSince1970: 6)
    )
    XCTAssertNil(deduction.sourceWalletOwner)
    XCTAssertEqual(deduction.sourceWalletID, "wallet-a")
  }

  func testRegistrationRequiresIssuanceProvenanceAndCoordinate() throws {
    let signer = try CreditRecordSigner(privateCredentialHandle: "registration-provenance")

    XCTAssertThrowsError(
      try UnsignedCreditRecord(
        kind: .registration,
        worldID: "world-reg",
        keyID: signer.authority.keyID,
        priorRecordHash: UnsignedCreditRecord.genesisPriorRecordHash,
        operationID: "registration-missing",
        actionIndex: 1,
        transactionID: "registration-missing-tx",
        accounts: ["wallet-a"],
        amounts: [CreditBalance.zero],
        postBalances: [CreditBalance.zero],
        actor: "agent-alpha",
        time: Date(timeIntervalSince1970: 7)
      )
    )

    XCTAssertThrowsError(
      try UnsignedCreditRecord(
        kind: .registration,
        worldID: "world-reg",
        keyID: signer.authority.keyID,
        priorRecordHash: UnsignedCreditRecord.genesisPriorRecordHash,
        operationID: "registration-coordinate",
        actionIndex: 2,
        transactionID: "registration-coordinate-tx",
        accounts: ["wallet-a"],
        amounts: [CreditBalance.zero],
        postBalances: [CreditBalance.zero],
        issuanceAgentID: "agent-x",
        issuanceBackpackID: "backpack-x",
        issuanceCoordinate: Coordinate(x: 0, y: 0),
        issuanceLocationCommitment: "loc-x",
        actor: "agent-alpha",
        time: Date(timeIntervalSince1970: 8)
      )
    )

    let withProvenance = try UnsignedCreditRecord(
      kind: .registration,
      worldID: "world-reg",
      keyID: signer.authority.keyID,
      priorRecordHash: UnsignedCreditRecord.genesisPriorRecordHash,
      operationID: "registration-ok",
      actionIndex: 3,
      transactionID: "registration-ok-tx",
      accounts: ["wallet-a"],
      amounts: [CreditBalance.zero],
      postBalances: [CreditBalance.zero],
      issuanceAgentID: "agent-x",
      issuanceBackpackID: "backpack-x",
      issuanceCoordinate: Coordinate(x: 4, y: 0),
      issuanceLocationCommitment: "loc-x",
      actor: "agent-alpha",
      time: Date(timeIntervalSince1970: 9)
    )
    XCTAssertEqual(withProvenance.issuanceCoordinate, .some(Coordinate(x: 4, y: 0)))

    XCTAssertThrowsError(
      try UnsignedCreditRecord(
        kind: .deposit,
        worldID: "world-reg",
        keyID: signer.authority.keyID,
        priorRecordHash: UnsignedCreditRecord.genesisPriorRecordHash,
        operationID: "deposit-no-provenance",
        actionIndex: 4,
        transactionID: "deposit-no-provenance-tx",
        accounts: ["wallet-a"],
        amounts: [try CreditBalance(minorUnits: 10)],
        postBalances: [try CreditBalance(minorUnits: 10)],
        issuanceAgentID: "agent-x",
        issuanceBackpackID: "backpack-x",
        issuanceCoordinate: Coordinate(x: 4, y: 0),
        issuanceLocationCommitment: "loc-x",
        actor: "agent-alpha",
        time: Date(timeIntervalSince1970: 10)
      )
    )
  }

  func testPurchaseRecordsEnforceFiniteVsUnlimitedAppliedAmounts() throws {
    let signer = try CreditRecordSigner(privateCredentialHandle: "purchase-modes")

    let finite = try UnsignedCreditRecord(
      kind: .purchase,
      worldID: "world-purchase",
      keyID: signer.authority.keyID,
      priorRecordHash: UnsignedCreditRecord.genesisPriorRecordHash,
      operationID: "purchase-finite",
      actionIndex: 1,
      transactionID: "purchase-finite-tx",
      accounts: ["wallet-a"],
      amounts: [try CreditBalance(minorUnits: -250)],
      postBalances: [try CreditBalance(minorUnits: 75)],
      treasuryDelta: try CreditBalance(minorUnits: 250),
      nominalPurchaseAmount: try CreditBalance(minorUnits: 250),
      appliedPurchaseAmount: try CreditBalance(minorUnits: 250),
      sourceWalletID: "wallet-a",
      sourceWalletCustodyCommitment: "purchase-wallet-a-cust",
      mode: .finite,
      actor: "agent-alpha",
      time: Date(timeIntervalSince1970: 11)
    )
    XCTAssertEqual(
      finite.nominalPurchaseAmount?.minorUnits, finite.appliedPurchaseAmount?.minorUnits)

    XCTAssertThrowsError(
      try UnsignedCreditRecord(
        kind: .purchase,
        worldID: "world-purchase",
        keyID: signer.authority.keyID,
        priorRecordHash: UnsignedCreditRecord.genesisPriorRecordHash,
        operationID: "purchase-finite-under",
        actionIndex: 2,
        transactionID: "purchase-finite-under-tx",
        accounts: ["wallet-a"],
        amounts: [try CreditBalance(minorUnits: -25)],
        postBalances: [try CreditBalance(minorUnits: 70)],
        treasuryDelta: try CreditBalance(minorUnits: 25),
        nominalPurchaseAmount: try CreditBalance(minorUnits: 100),
        appliedPurchaseAmount: try CreditBalance(minorUnits: 25),
        sourceWalletID: "wallet-a",
        sourceWalletCustodyCommitment: "purchase-wallet-a-cust",
        mode: .finite,
        actor: "agent-alpha",
        time: Date(timeIntervalSince1970: 12)
      )
    )

    let unlimited = try UnsignedCreditRecord(
      kind: .purchase,
      worldID: "world-purchase",
      keyID: signer.authority.keyID,
      priorRecordHash: UnsignedCreditRecord.genesisPriorRecordHash,
      operationID: "purchase-unlimited",
      actionIndex: 3,
      transactionID: "purchase-unlimited-tx",
      accounts: ["wallet-a"],
      amounts: [try CreditBalance(minorUnits: 0)],
      postBalances: [try CreditBalance(minorUnits: 75)],
      treasuryDelta: CreditBalance.zero,
      nominalPurchaseAmount: try CreditBalance(minorUnits: 1000),
      appliedPurchaseAmount: CreditBalance.zero,
      sourceWalletID: "wallet-a",
      sourceWalletCustodyCommitment: "purchase-wallet-a-cust",
      mode: .unlimited,
      actor: "agent-alpha",
      time: Date(timeIntervalSince1970: 13)
    )
    XCTAssertEqual(unlimited.appliedPurchaseAmount, CreditBalance.zero)

    XCTAssertThrowsError(
      try UnsignedCreditRecord(
        kind: .purchase,
        worldID: "world-purchase",
        keyID: signer.authority.keyID,
        priorRecordHash: UnsignedCreditRecord.genesisPriorRecordHash,
        operationID: "purchase-unlimited-bad",
        actionIndex: 4,
        transactionID: "purchase-unlimited-bad-tx",
        accounts: ["wallet-a"],
        amounts: [try CreditBalance(minorUnits: -10)],
        postBalances: [try CreditBalance(minorUnits: 65)],
        treasuryDelta: try CreditBalance(minorUnits: 10),
        nominalPurchaseAmount: try CreditBalance(minorUnits: 1000),
        appliedPurchaseAmount: try CreditBalance(minorUnits: 10),
        sourceWalletID: "wallet-a",
        sourceWalletCustodyCommitment: "purchase-wallet-a-cust",
        mode: .unlimited,
        actor: "agent-alpha",
        time: Date(timeIntervalSince1970: 14)
      )
    )
  }

  func testSignedRecordChainRejectsTamperingAndOutOfOrderRecords() throws {
    let signer = try CreditRecordSigner(privateCredentialHandle: "chain-tamper")
    let world = "world-chain"

    let firstUnsigned = try UnsignedCreditRecord(
      kind: .deposit,
      worldID: world,
      keyID: signer.authority.keyID,
      priorRecordHash: UnsignedCreditRecord.genesisPriorRecordHash,
      operationID: "chain-deposit",
      actionIndex: 1,
      transactionID: "chain-deposit-tx",
      accounts: ["wallet-a"],
      amounts: [try CreditBalance(minorUnits: 100)],
      postBalances: [try CreditBalance(minorUnits: 100)],
      treasuryDelta: try CreditBalance(minorUnits: -100),
      actor: "agent-alpha",
      time: Date(timeIntervalSince1970: 15)
    )
    let firstSigned = try signer.sign(firstUnsigned)

    let secondUnsigned = try UnsignedCreditRecord(
      kind: .deduction,
      worldID: world,
      keyID: signer.authority.keyID,
      priorRecordHash: try firstSigned.recordHash(),
      operationID: "chain-deduction",
      actionIndex: 2,
      transactionID: "chain-deduction-tx",
      accounts: ["wallet-a"],
      amounts: [try CreditBalance(minorUnits: -25)],
      postBalances: [try CreditBalance(minorUnits: 75)],
      treasuryDelta: try CreditBalance(minorUnits: 25),
      sourceWalletID: "wallet-a",
      sourceWalletCustodyCommitment: "chain-custody",
      actor: "agent-alpha",
      time: Date(timeIntervalSince1970: 16)
    )
    let secondSigned = try signer.sign(secondUnsigned)

    var chain = CreditRecordChain(authority: signer.authority, expectedWorld: world)
    XCTAssertNoThrow(try chain.append(firstSigned))
    XCTAssertNoThrow(try chain.append(secondSigned))
    XCTAssertThrowsError(try chain.append(secondSigned))

    var badSignature = firstSigned.signature
    badSignature[0] ^= 0x01
    let tamperedSigned = try SignedCreditRecord(
      unsigned: firstUnsigned,
      signature: badSignature,
      signerPublicKey: firstSigned.signerPublicKey
    )
    let verifier = CreditRecordVerifier(authority: signer.authority, expectedWorld: world)
    XCTAssertThrowsError(try verifier.verify(tamperedSigned))

    let wrongPrior = try UnsignedCreditRecord(
      kind: .deposit,
      worldID: world,
      keyID: signer.authority.keyID,
      priorRecordHash: String(repeating: "a", count: 64),
      operationID: "chain-wrong-prior",
      actionIndex: 3,
      transactionID: "chain-wrong-prior-tx",
      accounts: ["wallet-b"],
      amounts: [try CreditBalance(minorUnits: 33)],
      postBalances: [try CreditBalance(minorUnits: 33)],
      treasuryDelta: try CreditBalance(minorUnits: -33),
      actor: "agent-alpha",
      time: Date(timeIntervalSince1970: 17)
    )
    let wrongPriorSigned = try signer.sign(wrongPrior)
    XCTAssertThrowsError(try chain.append(wrongPriorSigned))
  }
}
