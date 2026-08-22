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

import XCTest

@testable import MikroKhoros

final class CreditServiceTests: XCTestCase {
  private func service(worldID: String = "world-credit-service") throws -> CreditService {
    try CreditService(worldID: worldID, authorityState: testTreasuryAuthorityState)
  }

  private func registerTwoWallets(_ service: CreditService) throws {
    _ = try service.register(
      walletID: "wallet-a",
      agentID: "agent-a",
      backpackID: "backpack-a",
      locationCommitment: "location-a",
      operationID: "register-a"
    )
    _ = try service.register(
      walletID: "wallet-b",
      agentID: "agent-b",
      backpackID: "backpack-b",
      locationCommitment: "location-b",
      operationID: "register-b"
    )
  }

  func testDepositDeductionDebtRepaymentAndTreasuryInvariant() throws {
    let service = try service()
    try registerTwoWallets(service)

    XCTAssertEqual(
      try service.deposit(
        walletID: "wallet-a",
        amount: CreditAmount(minorUnits: 100),
        operationID: "deposit-a"
      ).minorUnits,
      100
    )
    let commitment = try XCTUnwrap(service.custodyCommitment(for: "wallet-a"))
    XCTAssertEqual(
      try service.deduct(
        walletID: "wallet-a",
        amount: CreditAmount(minorUnits: 150),
        actor: .human,
        operationID: "deduct-a",
        sourceOwner: "agent-a",
        sourceCustodyCommitment: commitment
      ).minorUnits,
      -50
    )
    XCTAssertEqual(service.treasuryBalanceValue().minorUnits, 50)

    XCTAssertEqual(
      try service.deposit(
        walletID: "wallet-a",
        amount: CreditAmount(minorUnits: 75),
        operationID: "repay-a"
      ).minorUnits,
      25
    )
    XCTAssertEqual(service.treasuryBalanceValue().minorUnits, -25)
    XCTAssertNoThrow(try service.verify())
  }

  func testFiniteUnlimitedPurchaseAndTransferRules() throws {
    let service = try service(worldID: "world-modes")
    try registerTwoWallets(service)
    _ = try service.deposit(
      walletID: "wallet-a",
      amount: CreditAmount(minorUnits: 100),
      operationID: "fund-a"
    )
    let commitment = try XCTUnwrap(service.custodyCommitment(for: "wallet-a"))

    XCTAssertThrowsError(
      try service.deduct(
        walletID: "wallet-a",
        amount: CreditAmount(minorUnits: 101),
        actor: .agent,
        operationID: "finite-overdraft",
        sourceOwner: "agent-a",
        sourceCustodyCommitment: commitment,
        kind: .purchase
      ))

    try service.setMode(
      walletID: "wallet-a",
      mode: .unlimited,
      actor: .human,
      operationID: "unlimited-a"
    )
    XCTAssertEqual(
      try service.deduct(
        walletID: "wallet-a",
        amount: CreditAmount(minorUnits: 10_000),
        actor: .agent,
        operationID: "unlimited-purchase",
        sourceOwner: "agent-a",
        sourceCustodyCommitment: commitment,
        kind: .purchase
      ).minorUnits,
      100
    )
    XCTAssertEqual(service.treasuryBalanceValue().minorUnits, -100)

    let transfer = try service.transfer(
      from: "wallet-a",
      to: "wallet-b",
      amount: CreditAmount(minorUnits: 80),
      operationID: "transfer-shadow",
      sourceOwner: "agent-a",
      sourceCustodyCommitment: commitment
    )
    XCTAssertEqual(transfer.source.minorUnits, 20)
    XCTAssertEqual(transfer.destination.minorUnits, 80)
    XCTAssertThrowsError(
      try service.transfer(
        from: "wallet-a",
        to: "wallet-b",
        amount: CreditAmount(minorUnits: 21),
        operationID: "transfer-overdraft",
        sourceOwner: "agent-a",
        sourceCustodyCommitment: commitment
      ))

    try service.setMode(
      walletID: "wallet-a",
      mode: .finite,
      actor: .human,
      operationID: "finite-a"
    )
    XCTAssertEqual(try service.balance(for: "wallet-a").minorUnits, 20)
  }

  func testReplayRejectsUnlimitedTransferThatOverdrawsFiniteShadowBalance() throws {
    let service = try service(worldID: "world-unlimited-transfer-replay")
    try registerTwoWallets(service)
    _ = try service.deposit(
      walletID: "wallet-a",
      amount: CreditAmount(minorUnits: 1),
      operationID: "fund-a"
    )
    try service.setMode(
      walletID: "wallet-a",
      mode: .unlimited,
      actor: .human,
      operationID: "unlimited-a"
    )

    let priorHash = try XCTUnwrap(service.chain.last).recordHash()
    let sourceCommitment = try XCTUnwrap(service.custodyCommitment(for: "wallet-a"))
    let invalid = try UnsignedCreditRecord(
      kind: .transfer,
      worldID: service.worldID,
      keyID: service.authority.keyID,
      priorRecordHash: priorHash,
      operationID: "invalid-unlimited-transfer",
      actionIndex: 0,
      transactionID: "invalid-unlimited-transfer",
      accounts: ["wallet-a", "wallet-b"],
      amounts: [
        CreditBalance(minorUnits: -2),
        CreditBalance(minorUnits: 2),
      ],
      postBalances: [
        CreditBalance(minorUnits: -1),
        CreditBalance(minorUnits: 2),
      ],
      treasuryDelta: .zero,
      treasuryBalance: service.treasuryBalanceValue(),
      sourceWalletID: "wallet-a",
      sourceWalletOwner: "agent-a",
      sourceWalletCustodyCommitment: sourceCommitment,
      mode: .unlimited,
      actor: CreditActor.agent.rawValue,
      owner: "agent-a"
    )
    let signed = try XCTUnwrap(testTreasuryAuthorityState.signer).sign(invalid)

    XCTAssertThrowsError(try service.apply(signed))
    XCTAssertEqual(try service.balance(for: "wallet-a").minorUnits, 1)
    XCTAssertEqual(try service.balance(for: "wallet-b").minorUnits, 0)
  }

  func testBearerCustodyChangesDebitAuthorityWithoutChangingIssuance() throws {
    let service = try service(worldID: "world-custody")
    try registerTwoWallets(service)
    _ = try service.deposit(
      walletID: "wallet-a",
      amount: CreditAmount(minorUnits: 100),
      operationID: "fund-custody"
    )
    let oldCommitment = try XCTUnwrap(service.custodyCommitment(for: "wallet-a"))
    try service.updateCustody(
      walletID: "wallet-a",
      oldOwner: "agent-a",
      newOwner: "agent-b",
      oldLocationCommitment: "location-a",
      newLocationCommitment: "location-b-held",
      operationID: "handoff-a-b"
    )
    let newCommitment = try XCTUnwrap(service.custodyCommitment(for: "wallet-a"))
    XCTAssertNotEqual(oldCommitment, newCommitment)
    XCTAssertEqual(service.custodyOwner(for: "wallet-a"), "agent-b")
    XCTAssertEqual(service.registration(for: "wallet-a")?.agentID, "agent-a")

    XCTAssertThrowsError(
      try service.transfer(
        from: "wallet-a",
        to: "wallet-b",
        amount: CreditAmount(minorUnits: 1),
        operationID: "stale-bearer",
        sourceOwner: "agent-a",
        sourceCustodyCommitment: oldCommitment
      ))
    XCTAssertNoThrow(
      try service.transfer(
        from: "wallet-a",
        to: "wallet-b",
        amount: CreditAmount(minorUnits: 1),
        operationID: "new-bearer",
        sourceOwner: "agent-b",
        sourceCustodyCommitment: newCommitment
      ))
  }

  func testOperationRetryIsExactAndVerifyOnlyFailsClosedForNewMutation() throws {
    let service = try service(worldID: "world-idempotency")
    _ = try service.register(
      walletID: "wallet-a",
      agentID: "agent-a",
      backpackID: "backpack-a",
      locationCommitment: "location-a",
      operationID: "register-a"
    )
    let amount = try CreditAmount(minorUnits: 100)
    let first = try service.deposit(
      walletID: "wallet-a",
      amount: amount,
      operationID: "stable-deposit",
      note: "work accepted"
    )
    let chainCount = service.chain.count
    let retried = try service.deposit(
      walletID: "wallet-a",
      amount: amount,
      operationID: "stable-deposit",
      note: "work accepted"
    )
    XCTAssertEqual(first, retried)
    XCTAssertEqual(service.chain.count, chainCount)
    XCTAssertThrowsError(
      try service.deposit(
        walletID: "wallet-a",
        amount: CreditAmount(minorUnits: 101),
        operationID: "stable-deposit",
        note: "work accepted"
      ))
    XCTAssertEqual(service.chain.count, chainCount)

    let verifyOnly = try CreditService(verifyOnly: service.snapshot())
    XCTAssertEqual(
      try verifyOnly.deposit(
        walletID: "wallet-a",
        amount: amount,
        operationID: "stable-deposit",
        note: "work accepted"
      ),
      first
    )
    XCTAssertThrowsError(
      try verifyOnly.deposit(
        walletID: "wallet-a",
        amount: CreditAmount(minorUnits: 1),
        operationID: "new-deposit"
      ))
  }

  func testExposureCapRejectsOffsettingNextUnitAtomically() throws {
    let service = try service(worldID: "world-exposure-cap")
    try registerTwoWallets(service)
    _ = try service.register(
      walletID: "wallet-c",
      agentID: "agent-c",
      backpackID: "backpack-c",
      locationCommitment: "location-c",
      operationID: "register-c"
    )

    let maximum = try CreditAmount(minorUnits: Int64.max)
    _ = try service.deduct(
      walletID: "wallet-a",
      amount: maximum,
      actor: .human,
      operationID: "maximum-debt",
      sourceOwner: "agent-a",
      sourceCustodyCommitment: try XCTUnwrap(
        service.custodyCommitment(for: "wallet-a")
      )
    )
    _ = try service.deposit(
      walletID: "wallet-b",
      amount: maximum,
      operationID: "maximum-positive"
    )
    XCTAssertEqual(try service.balance(for: "wallet-a").minorUnits, -Int64.max)
    XCTAssertEqual(try service.balance(for: "wallet-b").minorUnits, Int64.max)
    XCTAssertEqual(service.treasuryBalanceValue(), .zero)

    let before = service.snapshot()
    XCTAssertThrowsError(
      try service.deposit(
        walletID: "wallet-c",
        amount: CreditAmount(minorUnits: 1),
        operationID: "one-unit-over-exposure"
      )
    )
    XCTAssertEqual(service.snapshot(), before)
    XCTAssertEqual(try service.balance(for: "wallet-c"), .zero)
  }
}
