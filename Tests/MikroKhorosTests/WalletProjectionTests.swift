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
import XCTest

@testable import MikroKhoros

final class WalletProjectionTests: XCTestCase {
  func testWalletBroadcastsAreDeduplicatedBoundedAndOldestFirst() throws {
    let wallet = try WalletObject(hash: "wallet-broadcast")
    let events = (0..<(WalletObject.maximumBroadcastEvents + 3)).map { index in
      AgentBroadcastEvent(
        id: "event-\(index)",
        timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
        sourceID: wallet.hash,
        sourceType: wallet.typeName,
        title: "credit",
        body: "entry \(index)"
      )
    }

    for event in events {
      XCTAssertTrue(wallet.recordBroadcast(event))
    }
    XCTAssertFalse(wallet.recordBroadcast(events.last!))
    XCTAssertEqual(wallet.unreadEvents(limit: 3).map(\.id), ["event-3", "event-4", "event-5"])
    XCTAssertEqual(wallet.latestUnreadEvent()?.id, "event-258")
    XCTAssertTrue(wallet.acknowledge(eventID: "event-4"))
    XCTAssertNil(wallet.unreadEvent(eventID: "event-4"))
    XCTAssertFalse(wallet.acknowledge(eventID: "event-4"))
    XCTAssertEqual(wallet.unreadEvents(limit: 2).map(\.id), ["event-3", "event-5"])
  }

  func testWalletProjectionUsesNewestFirstOpaqueExactWalletCursor() throws {
    let runtime = try testWorldRuntime()
    let first = try runtime.createAgent(name: "first")
    let second = try runtime.createAgent(name: "second")
    _ = try runtime.addAgent(first)
    _ = try runtime.addAgent(second)
    let service = try XCTUnwrap(runtime.harness.creditService)

    _ = try service.deposit(
      walletID: first.wallet.hash,
      amount: CreditAmount.parse("1.00"),
      actor: .human
    )
    let firstPage = try AgentWalletProjection.statement(
      service: service,
      walletID: first.wallet.hash,
      count: 1
    )
    XCTAssertEqual(firstPage.entries.count, 1)
    XCTAssertEqual(firstPage.entries.first?.kind, CreditRecordKind.deposit.rawValue)
    let cursor = try XCTUnwrap(firstPage.nextCursor)

    let secondPage = try AgentWalletProjection.statement(
      service: service,
      walletID: first.wallet.hash,
      cursor: cursor,
      count: 1
    )
    XCTAssertEqual(secondPage.entries.first?.kind, CreditRecordKind.registration.rawValue)
    XCTAssertNil(secondPage.nextCursor)
    XCTAssertTrue(cursor.hasPrefix("mk-wallet-cursor-v1."))

    XCTAssertThrowsError(
      try AgentWalletProjection.statement(
        service: service,
        walletID: second.wallet.hash,
        cursor: cursor,
        count: 1
      )
    ) { error in
      guard case MikroKhorosError.runtime(let issue) = error else {
        return XCTFail("expected a bounded runtime cursor error, got \(error)")
      }
      XCTAssertEqual(issue.code, "wallet.statement_cursor_invalid")
    }
  }

  func testWalletProjectionRejectsCountAndByteExpansionAndRendersMinimumDebtSafely() throws {
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "bounded")
    _ = try runtime.addAgent(agent)
    let service = try XCTUnwrap(runtime.harness.creditService)

    XCTAssertThrowsError(
      try AgentWalletProjection.statement(
        service: service,
        walletID: agent.wallet.hash,
        count: AgentWalletProjection.maximumStatementCount + 1
      )
    )
    XCTAssertThrowsError(
      try AgentWalletProjection.statement(
        service: service,
        walletID: agent.wallet.hash,
        maximumBytes: 1
      )
    )
    XCTAssertEqual(
      AgentWalletProjection.debtText(for: Int64.min),
      "92233720368547758.08"
    )
    XCTAssertEqual(
      AgentWalletProjection.debtText(for: try CreditBalance(minorUnits: -1)),
      "0.01"
    )
  }

  func testWriteOnlyDestinationCannotBeProbedWithInvalidSourceRequests() throws {
    let runtime = try testWorldRuntime()
    let source = try runtime.createAgent(name: "source")
    let destination = try runtime.createAgent(name: "destination")
    _ = try runtime.addAgent(source)
    _ = try runtime.addAgent(destination)

    func failure(_ destinationID: String, amount: String, note: String? = nil) -> String {
      var arguments = [destinationID, amount]
      if let note { arguments.append(note) }
      do {
        _ = try source.wallet.invoke(
          "transfer",
          arguments: arguments,
          harness: runtime.harness,
          agent: source
        )
        XCTFail("expected transfer to fail")
        return "unexpected-success"
      } catch let error as MikroKhorosError {
        return error.issue.code
      } catch {
        return String(describing: error)
      }
    }

    let invalidDestination = "unregistered-exact-wallet-id"
    XCTAssertEqual(
      failure(destination.wallet.hash, amount: "1.00"),
      failure(invalidDestination, amount: "1.00")
    )
    XCTAssertEqual(
      failure(destination.wallet.hash, amount: "not-an-amount"),
      failure(invalidDestination, amount: "not-an-amount")
    )
    let oversizedNote = String(repeating: "n", count: UnsignedCreditRecord.maxNoteLength + 1)
    XCTAssertEqual(
      failure(destination.wallet.hash, amount: "1.00", note: oversizedNote),
      failure(invalidDestination, amount: "1.00", note: oversizedNote)
    )
  }
}
