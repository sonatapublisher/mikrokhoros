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

/// The deliberately small, read-only surface of a wallet that may cross into
/// an agent request.  CreditService remains the source of truth; this type
/// only selects records belonging to one exact registered wallet and renders
/// the allowlisted fields needed by the agent.
///
/// In particular, this projection must not be replaced with a projection of
/// `CreditService.chain` as a whole.  A credit record can contain other wallet
/// accounts, custody commitments, actor data, causal identifiers, and notes
/// that are useful to the trusted runtime but are not agent-facing data.
public struct AgentWalletProjection: Sendable {
  public static let cursorVersion = 1

  /// A statement page is intentionally bounded independently from the global
  /// world and model limits.  Wallet records are durable and may grow for the
  /// lifetime of a world, so the agent surface must always be finite.
  public static let maximumStatementCount = 64
  public static let maximumStatementBytes = 16 * 1_024

  public struct StatementEntry: Codable, Equatable, Sendable {
    public let eventID: String
    public let transactionID: String
    public let kind: String
    public let timestamp: String
    public let signedDelta: String
    public let resultingShadowBalance: String
    public let mode: String
    public let nominalAmount: String?
    public let appliedAmount: String?
    public let note: String?

    public init(
      eventID: String,
      transactionID: String,
      kind: String,
      timestamp: String,
      signedDelta: String,
      resultingShadowBalance: String,
      mode: String,
      nominalAmount: String? = nil,
      appliedAmount: String? = nil,
      note: String? = nil
    ) {
      self.eventID = eventID
      self.transactionID = transactionID
      self.kind = kind
      self.timestamp = timestamp
      self.signedDelta = signedDelta
      self.resultingShadowBalance = resultingShadowBalance
      self.mode = mode
      self.nominalAmount = nominalAmount
      self.appliedAmount = appliedAmount
      self.note = note
    }

    private enum CodingKeys: String, CodingKey {
      case eventID = "event_id"
      case transactionID = "transaction_id"
      case kind
      case timestamp
      case signedDelta = "signed_delta"
      case resultingShadowBalance = "resulting_shadow_balance"
      case mode
      case nominalAmount = "nominal_amount"
      case appliedAmount = "applied_amount"
      case note
    }
  }

  public struct StatementPage: Codable, Equatable, Sendable {
    public let entries: [StatementEntry]
    public let nextCursor: String?

    public init(entries: [StatementEntry], nextCursor: String?) {
      self.entries = entries
      self.nextCursor = nextCursor
    }

    public var hasMore: Bool { nextCursor != nil }

    private enum CodingKeys: String, CodingKey {
      case entries
      case nextCursor = "next_cursor"
    }
  }

  private struct CursorPayload: Codable {
    let version: Int
    let wallet: String
    let anchor: String

    enum CodingKeys: String, CodingKey, CaseIterable {
      case version
      case wallet
      case anchor
    }
  }

  private let service: CreditService
  private let walletID: String
  private let cursor: String?
  private let count: Int
  private let maximumBytes: Int

  /// Create a projection for one exact registered wallet.  No prefix or
  /// display-name resolution occurs here.  The caller must perform the
  /// bearer/ownership check before constructing an agent projection.
  public init(
    service: CreditService,
    walletID: String,
    cursor: String? = nil,
    count: Int = Self.maximumStatementCount,
    maximumBytes: Int = Self.maximumStatementBytes
  ) throws {
    guard service.registration(for: walletID) != nil else {
      throw Self.invalidProjection()
    }
    guard !walletID.isEmpty, walletID.count <= UnsignedCreditRecord.maxIdentifierLength else {
      throw Self.invalidProjection()
    }
    guard count > 0, count <= Self.maximumStatementCount else {
      throw MikroKhorosError.runtime(
        "wallet.statement_limit",
        "wallet statement count exceeds the agent projection limit",
        details: ["limit": String(Self.maximumStatementCount)]
      )
    }
    guard maximumBytes > 0, maximumBytes <= Self.maximumStatementBytes else {
      throw MikroKhorosError.runtime(
        "wallet.statement_bytes",
        "wallet statement byte limit exceeds the agent projection limit",
        details: ["limit": String(Self.maximumStatementBytes)]
      )
    }
    self.service = service
    self.walletID = walletID
    self.cursor = cursor
    self.count = count
    self.maximumBytes = maximumBytes
  }

  /// Compatibility spelling for callers that name the dependency after its
  /// domain role rather than its concrete type.
  public init(
    creditService: CreditService,
    walletID: String,
    cursor: String? = nil,
    count: Int = Self.maximumStatementCount,
    maximumBytes: Int = Self.maximumStatementBytes
  ) throws {
    try self.init(
      service: creditService,
      walletID: walletID,
      cursor: cursor,
      count: count,
      maximumBytes: maximumBytes
    )
  }

  /// Return a newest-first page.  The page's cursor is anchored to the exact
  /// last record returned rather than to a caller-controlled integer offset;
  /// appending later records therefore does not duplicate or skip entries.
  public func statement() throws -> StatementPage {
    let rows = try matchingRecords()
    var selected = Array(rows.prefix(count))
    while true {
      let nextCursor: String?
      if rows.count > selected.count, let last = selected.last {
        nextCursor = try Self.makeCursor(walletID: walletID, anchor: last.recordID)
      } else {
        nextCursor = nil
      }
      let page = try makePage(records: selected, nextCursor: nextCursor)
      if try fits(page) { return page }

      guard selected.count > 1 else {
        throw MikroKhorosError.runtime(
          "wallet.statement_bytes",
          "wallet statement cannot fit within the agent projection limit",
          details: ["limit": String(maximumBytes)]
        )
      }
      selected.removeLast()
    }
  }

  /// Render the page as a bounded YAML-compatible text surface.  Every value
  /// is quoted through PromptSafety and only the allowlisted statement fields
  /// are included.  The encoded page cap is checked before this conversion;
  /// the final UTF-8 surface is checked as well because quoting can expand it.
  public func renderStatement() throws -> String {
    let page = try statement()
    if page.entries.isEmpty, page.nextCursor == nil {
      return "statement: []"
    }
    var lines = ["statement:"]
    for entry in page.entries {
      lines.append("  - event_id: \(PromptSafety.yamlScalar(entry.eventID, limit: 512))")
      lines.append(
        "    transaction_id: \(PromptSafety.yamlScalar(entry.transactionID, limit: 512))"
      )
      lines.append("    kind: \(PromptSafety.yamlScalar(entry.kind, limit: 64))")
      lines.append("    timestamp: \(PromptSafety.yamlScalar(entry.timestamp, limit: 64))")
      lines.append("    signed_delta: \(PromptSafety.yamlScalar(entry.signedDelta, limit: 64))")
      lines.append(
        "    resulting_shadow_balance: \(PromptSafety.yamlScalar(entry.resultingShadowBalance, limit: 64))"
      )
      lines.append("    mode: \(PromptSafety.yamlScalar(entry.mode, limit: 32))")
      if let nominalAmount = entry.nominalAmount {
        lines.append("    nominal_amount: \(PromptSafety.yamlScalar(nominalAmount, limit: 64))")
      }
      if let appliedAmount = entry.appliedAmount {
        lines.append("    applied_amount: \(PromptSafety.yamlScalar(appliedAmount, limit: 64))")
      }
      if let note = entry.note {
        lines.append(
          "    note: \(PromptSafety.yamlScalar(note, limit: UnsignedCreditRecord.maxNoteLength))")
      }
    }
    if let cursor = page.nextCursor {
      lines.append("next_cursor: \(PromptSafety.yamlScalar(cursor, limit: 512))")
    } else {
      lines.append("next_cursor: null")
    }
    let rendered = lines.joined(separator: "\n")
    guard rendered.utf8.count <= maximumBytes else {
      throw MikroKhorosError.runtime(
        "wallet.statement_bytes",
        "wallet statement cannot fit within the agent projection limit",
        details: ["limit": String(maximumBytes)]
      )
    }
    return rendered
  }

  /// The allowlisted balance response. It contains the exact invoked Wallet
  /// identity and its finite shadow balance, debt magnitude, and mode only.
  public static func renderBalance(
    service: CreditService,
    walletID: String
  ) throws -> String {
    guard service.registration(for: walletID) != nil else { throw invalidProjection() }
    let balance = try service.balance(for: walletID)
    let mode = try service.mode(for: walletID)
    return [
      "wallet_id: \(PromptSafety.yamlScalar(walletID, limit: 512))",
      "finite_shadow_balance: \(PromptSafety.yamlScalar(safeDecimal(balance.minorUnits), limit: 64))",
      "debt: \(PromptSafety.yamlScalar(debtText(for: balance), limit: 64))",
      "mode: \(PromptSafety.yamlScalar(mode.rawValue, limit: 32))",
    ].joined(separator: "\n")
  }

  /// Verify the complete signed local chain and return the small agent-safe
  /// result.  Verification never exposes the chain, authority, or credential.
  public static func renderVerify(
    service: CreditService,
    walletID: String
  ) throws -> String {
    guard service.registration(for: walletID) != nil else { throw invalidProjection() }
    let wallet = PromptSafety.yamlScalar(walletID, limit: 512)
    do {
      try service.verify()
      return "wallet_id: \(wallet)\nstatus: valid"
    } catch {
      // Verification failures are data, not an opportunity to expose chain,
      // authority, signature, or credential metadata to the agent.
      return [
        "wallet_id: \(wallet)",
        "status: invalid",
        "error_code: wallet.verification_failed",
      ].joined(separator: "\n")
    }
  }

  /// Render the exact allowlisted result of one source-side transfer. The
  /// destination account is deliberately not projected.
  public static func renderTransfer(
    record: SignedCreditRecord,
    sourceWalletID: String,
    fallbackSourceBalance: CreditBalance
  ) throws -> String {
    guard record.unsigned.kind == .transfer,
      record.unsigned.sourceWalletID == sourceWalletID,
      let index = record.unsigned.accounts.firstIndex(of: sourceWalletID),
      record.unsigned.amounts.indices.contains(index),
      record.unsigned.postBalances.indices.contains(index),
      record.unsigned.postBalances[index] == fallbackSourceBalance
    else { throw invalidProjection() }
    let delta = record.unsigned.amounts[index].minorUnits
    guard delta < 0 else { throw invalidProjection() }
    let formatter = ISO8601DateFormatter()
    var lines = [
      "transaction_id: \(PromptSafety.yamlScalar(record.unsigned.transactionID, limit: 512))",
      "kind: transfer",
      "applied_amount: \(PromptSafety.yamlScalar(safeDecimal(-delta), limit: 64))",
      "resulting_source_shadow_balance: \(PromptSafety.yamlScalar(safeDecimal(fallbackSourceBalance.minorUnits), limit: 64))",
      "source_mode: \(PromptSafety.yamlScalar(record.unsigned.mode.rawValue, limit: 32))",
      "timestamp: \(PromptSafety.yamlScalar(formatter.string(from: record.unsigned.time), limit: 64))",
    ]
    if !record.unsigned.note.isEmpty {
      lines.append(
        "note: \(PromptSafety.yamlScalar(record.unsigned.note, limit: UnsignedCreditRecord.maxNoteLength))"
      )
    }
    return lines.joined(separator: "\n")
  }

  /// Render the allowlisted buyer receipt. Shop inventory and replacement
  /// details stay on the human/admin side of the merchant transaction.
  public static func renderPurchase(
    record: SignedCreditRecord,
    itemID: String,
    payerWalletID: String
  ) throws -> String {
    guard record.unsigned.kind == .purchase,
      record.unsigned.sourceWalletID == payerWalletID,
      record.unsigned.causalItemIDs.contains(itemID),
      let index = record.unsigned.accounts.firstIndex(of: payerWalletID),
      record.unsigned.postBalances.indices.contains(index),
      let nominal = record.unsigned.nominalPurchaseAmount,
      let applied = record.unsigned.appliedPurchaseAmount
    else { throw invalidProjection() }
    let formatter = ISO8601DateFormatter()
    return [
      "transaction_id: \(PromptSafety.yamlScalar(record.unsigned.transactionID, limit: 512))",
      "item_id: \(PromptSafety.yamlScalar(itemID, limit: 512))",
      "pickup_claim_status: active",
      "nominal_amount: \(PromptSafety.yamlScalar(safeDecimal(nominal.minorUnits), limit: 64))",
      "applied_amount: \(PromptSafety.yamlScalar(safeDecimal(applied.minorUnits), limit: 64))",
      "resulting_source_shadow_balance: \(PromptSafety.yamlScalar(safeDecimal(record.unsigned.postBalances[index].minorUnits), limit: 64))",
      "source_mode: \(PromptSafety.yamlScalar(record.unsigned.mode.rawValue, limit: 32))",
      "timestamp: \(PromptSafety.yamlScalar(formatter.string(from: record.unsigned.time), limit: 64))",
    ].joined(separator: "\n")
  }

  public static func statement(
    service: CreditService,
    walletID: String,
    cursor: String? = nil,
    count: Int = Self.maximumStatementCount,
    maximumBytes: Int = Self.maximumStatementBytes
  ) throws -> StatementPage {
    try Self(
      service: service,
      walletID: walletID,
      cursor: cursor,
      count: count,
      maximumBytes: maximumBytes
    ).statement()
  }

  public static func renderStatement(
    service: CreditService,
    walletID: String,
    cursor: String? = nil,
    count: Int = Self.maximumStatementCount,
    maximumBytes: Int = Self.maximumStatementBytes
  ) throws -> String {
    try Self(
      service: service,
      walletID: walletID,
      cursor: cursor,
      count: count,
      maximumBytes: maximumBytes
    ).renderStatement()
  }

  /// A debt projection is deliberately positive and uses unsigned magnitude
  /// arithmetic.  In particular, this remains safe for the mathematical
  /// magnitude of Int64.min even though CreditBalance itself rejects that raw
  /// value at its trust boundary.
  public static func debtText(for minorUnits: Int64) -> String {
    guard minorUnits < 0 else { return "0.00" }
    let magnitude =
      minorUnits == Int64.min
      ? UInt64(Int64.max) + 1
      : UInt64(-minorUnits)
    return safeDecimal(magnitude: magnitude)
  }

  /// Render a balance's debt projection without performing a signed negation
  /// on a potentially minimum-width integer.  This overload keeps callers
  /// from reaching into the balance representation merely to render the
  /// agent-safe debt field.
  public static func debtText(for balance: CreditBalance) -> String {
    debtText(for: balance.minorUnits)
  }

  /// Public decimal rendering for integrations that need to compose a
  /// bounded response while retaining the same Int64-minimum safety rule used
  /// by the built-in balance and statement renderers.
  public static func decimalText(for minorUnits: Int64) -> String {
    safeDecimal(minorUnits)
  }

  private func matchingRecords() throws -> [SignedCreditRecord] {
    let anchor: String?
    if let cursor, !cursor.isEmpty {
      let payload = try Self.decodeCursor(cursor)
      guard payload.wallet == walletID else { throw Self.invalidCursor() }
      anchor = payload.anchor
    } else {
      anchor = nil
    }

    var result: [SignedCreditRecord] = []
    result.reserveCapacity(Self.maximumStatementCount + 1)
    var foundAnchor = anchor == nil
    for record in service.chain.reversed() {
      guard let index = record.unsigned.accounts.firstIndex(of: walletID) else { continue }
      if let anchor, !foundAnchor {
        if record.recordID == anchor { foundAnchor = true }
        continue
      }
      guard record.unsigned.amounts.indices.contains(index),
        record.unsigned.postBalances.indices.contains(index)
      else {
        throw Self.invalidProjection()
      }
      result.append(record)
      // One look-ahead row is enough to prove that the page has another row;
      // keeping the remainder of a long-lived chain would defeat the bounded
      // projection boundary.
      if result.count > count { break }
    }
    if !foundAnchor { throw Self.invalidCursor() }
    return result
  }

  private func makePage(
    records: [SignedCreditRecord],
    nextCursor: String?
  ) throws -> StatementPage {
    let formatter = ISO8601DateFormatter()
    let modes = try modesByRecordID()
    var entries: [StatementEntry] = []
    entries.reserveCapacity(records.count)
    for record in records {
      guard let index = record.unsigned.accounts.firstIndex(of: walletID),
        record.unsigned.amounts.indices.contains(index),
        record.unsigned.postBalances.indices.contains(index),
        let mode = modes[record.recordID]
      else { throw Self.invalidProjection() }
      entries.append(
        StatementEntry(
          eventID: record.recordID,
          transactionID: record.unsigned.transactionID,
          kind: record.unsigned.kind.rawValue,
          timestamp: formatter.string(from: record.unsigned.time),
          signedDelta: Self.safeDecimal(record.unsigned.amounts[index].minorUnits),
          resultingShadowBalance: Self.safeDecimal(record.unsigned.postBalances[index].minorUnits),
          mode: mode.rawValue,
          nominalAmount: record.unsigned.nominalPurchaseAmount.map {
            Self.safeDecimal($0.minorUnits)
          },
          appliedAmount: record.unsigned.appliedPurchaseAmount.map {
            Self.safeDecimal($0.minorUnits)
          },
          note: record.unsigned.note.isEmpty ? nil : record.unsigned.note
        )
      )
    }
    return StatementPage(entries: entries, nextCursor: nextCursor)
  }

  private func modesByRecordID() throws -> [String: WalletMode] {
    var current: WalletMode?
    var result: [String: WalletMode] = [:]
    for record in service.chain {
      guard record.unsigned.accounts.contains(walletID) else { continue }
      switch record.unsigned.kind {
      case .registration:
        guard current == nil else { throw Self.invalidProjection() }
        current = .finite
      case .modeChange:
        guard current != nil else { throw Self.invalidProjection() }
        current = record.unsigned.mode
      default:
        guard current != nil else { throw Self.invalidProjection() }
      }
      guard let current else { throw Self.invalidProjection() }
      result[record.recordID] = current
    }
    return result
  }

  private func fits(_ page: StatementPage) throws -> Bool {
    let data = try JSONEncoder().encode(page)
    guard data.count <= maximumBytes else { return false }
    let rendered = try render(page)
    return rendered.utf8.count <= maximumBytes
  }

  private func render(_ page: StatementPage) throws -> String {
    if page.entries.isEmpty, page.nextCursor == nil {
      return "statement: []"
    }
    var lines = ["statement:"]
    for entry in page.entries {
      lines.append("  - event_id: \(PromptSafety.yamlScalar(entry.eventID, limit: 512))")
      lines.append(
        "    transaction_id: \(PromptSafety.yamlScalar(entry.transactionID, limit: 512))"
      )
      lines.append("    kind: \(PromptSafety.yamlScalar(entry.kind, limit: 64))")
      lines.append("    timestamp: \(PromptSafety.yamlScalar(entry.timestamp, limit: 64))")
      lines.append("    signed_delta: \(PromptSafety.yamlScalar(entry.signedDelta, limit: 64))")
      lines.append(
        "    resulting_shadow_balance: \(PromptSafety.yamlScalar(entry.resultingShadowBalance, limit: 64))"
      )
      lines.append("    mode: \(PromptSafety.yamlScalar(entry.mode, limit: 32))")
      if let nominalAmount = entry.nominalAmount {
        lines.append("    nominal_amount: \(PromptSafety.yamlScalar(nominalAmount, limit: 64))")
      }
      if let appliedAmount = entry.appliedAmount {
        lines.append("    applied_amount: \(PromptSafety.yamlScalar(appliedAmount, limit: 64))")
      }
      if let note = entry.note {
        lines.append(
          "    note: \(PromptSafety.yamlScalar(note, limit: UnsignedCreditRecord.maxNoteLength))")
      }
    }
    lines.append(
      page.nextCursor.map { "next_cursor: \(PromptSafety.yamlScalar($0, limit: 512))" }
        ?? "next_cursor: null"
    )
    return lines.joined(separator: "\n")
  }

  private static func makeCursor(walletID: String, anchor: String) throws -> String {
    let payload = CursorPayload(version: Self.cursorVersion, wallet: walletID, anchor: anchor)
    let data = try JSONEncoder().encode(payload)
    let encoded = data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    return "mk-wallet-cursor-v\(Self.cursorVersion).\(encoded)"
  }

  private static func decodeCursor(_ value: String) throws -> CursorPayload {
    let prefix = "mk-wallet-cursor-v\(Self.cursorVersion)."
    guard value.count <= 1_024, value.hasPrefix(prefix) else { throw invalidCursor() }
    let encoded = String(value.dropFirst(prefix.count))
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let padding = (4 - encoded.count % 4) % 4
    guard let data = Data(base64Encoded: encoded + String(repeating: "=", count: padding)) else {
      throw invalidCursor()
    }
    guard
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(object.keys) == Set(CursorPayload.CodingKeys.allCases.map(\.rawValue)),
      let version = object[CursorPayload.CodingKeys.version.rawValue] as? Int,
      let wallet = object[CursorPayload.CodingKeys.wallet.rawValue] as? String,
      let anchor = object[CursorPayload.CodingKeys.anchor.rawValue] as? String,
      version == Self.cursorVersion,
      !wallet.isEmpty,
      !anchor.isEmpty
    else { throw invalidCursor() }
    return CursorPayload(version: version, wallet: wallet, anchor: anchor)
  }

  private static func invalidProjection() -> MikroKhorosError {
    .runtime(
      "wallet.projection_invalid",
      "wallet projection is unavailable"
    )
  }

  private static func invalidCursor() -> MikroKhorosError {
    .runtime(
      "wallet.statement_cursor_invalid",
      "wallet statement cursor is invalid"
    )
  }

  private static func safeDecimal(_ value: Int64) -> String {
    if value >= 0 { return safeDecimal(magnitude: UInt64(value)) }
    let magnitude = value == Int64.min ? UInt64(Int64.max) + 1 : UInt64(-value)
    return "-\(safeDecimal(magnitude: magnitude))"
  }

  private static func safeDecimal(magnitude: UInt64) -> String {
    let integer = magnitude / 100
    let fraction = String(magnitude % 100)
    return "\(integer).\(fraction.count == 1 ? "0" : "")\(fraction)"
  }
}
