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

private func expect(_ arguments: [String], minimum: Int, maximum: Int? = nil) throws {
  let upper = maximum ?? minimum
  guard arguments.count >= minimum, arguments.count <= upper else {
    let expected = minimum == upper ? "exactly \(minimum)" : "between \(minimum) and \(upper)"
    throw MikroKhorosError.function(
      "expected \(expected) argument(s), received \(arguments.count)"
    )
  }
}

func parseDecimal(_ text: String, label: String = "value") throws -> Decimal {
  guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
    throw MikroKhorosError.function("\(label) must be a number")
  }
  return value
}

public func formatAmount(_ value: Decimal?) -> String {
  guard let value else { return "infinite" }
  return NSDecimalNumber(decimal: value).stringValue
}

public final class ScratchpadObject: MikroObject {
  public static let maximumCharacters = 65_536
  public private(set) var text: String

  public init(
    name: String = "scratchpad",
    text: String = "",
    origin: ObjectOrigin = .genesis,
    hash: String? = nil
  ) throws {
    guard text.count <= Self.maximumCharacters else {
      throw MikroKhorosError.function("scratchpad exceeds its storage limit")
    }
    self.text = text
    try super.init(
      typeName: "scratchpad.object",
      name: name,
      summary: "Private persistent text for the carrying agent.",
      origin: origin,
      hash: hash
    )
    try registerFunction(name: "read", summary: "Read the complete note.") {
      context, arguments in
      try expect(arguments, minimum: 0)
      let object = context.object as! ScratchpadObject
      return object.text.isEmpty ? "(scratchpad is empty)" : object.text
    }
    try registerFunction(name: "write", summary: "Replace the note.", parameters: ["text"]) {
      context, arguments in
      try expect(arguments, minimum: 1)
      guard arguments[0].count <= Self.maximumCharacters else {
        throw MikroKhorosError.function("scratchpad exceeds its storage limit")
      }
      let object = context.object as! ScratchpadObject
      object.text = arguments[0]
      return "wrote \(object.text.count) character(s)"
    }
    try registerFunction(name: "append", summary: "Append text.", parameters: ["text"]) {
      context, arguments in
      try expect(arguments, minimum: 1)
      let object = context.object as! ScratchpadObject
      guard object.text.count + arguments[0].count <= Self.maximumCharacters else {
        throw MikroKhorosError.function("scratchpad exceeds its storage limit")
      }
      object.text += arguments[0]
      return "scratchpad now contains \(object.text.count) character(s)"
    }
    try registerFunction(name: "clear", summary: "Delete the note.") {
      context, arguments in
      try expect(arguments, minimum: 0)
      (context.object as! ScratchpadObject).text = ""
      return "scratchpad cleared"
    }
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try ScratchpadObject(name: name, origin: origin, hash: hash)
  }
}

private enum ArithmeticToken: Equatable {
  case number(Double)
  case plus, minus, multiply, divide, floorDivide, modulo, power
  case leftParenthesis, rightParenthesis, end
}

private struct ArithmeticParser {
  private let tokens: [ArithmeticToken]
  private var index = 0

  init(_ expression: String) throws {
    guard expression.count <= 512 else {
      throw MikroKhorosError.function("expression is too long")
    }
    self.tokens = try Self.tokenize(expression) + [.end]
  }

  mutating func evaluate() throws -> Double {
    let result = try expression()
    guard current == .end else {
      throw MikroKhorosError.function("unexpected input in calculation")
    }
    guard result.isFinite, abs(result) <= 1e100 else {
      throw MikroKhorosError.function("result is too large")
    }
    return result
  }

  private var current: ArithmeticToken { tokens[index] }
  private mutating func advance() { index += 1 }

  private mutating func expression() throws -> Double {
    var value = try term()
    while true {
      switch current {
      case .plus:
        advance()
        value += try term()
      case .minus:
        advance()
        value -= try term()
      default: return value
      }
    }
  }

  private mutating func term() throws -> Double {
    var value = try power()
    while true {
      switch current {
      case .multiply:
        advance()
        value *= try power()
      case .divide:
        advance()
        let divisor = try power()
        guard divisor != 0 else { throw MikroKhorosError.function("division by zero") }
        value /= divisor
      case .floorDivide:
        advance()
        let divisor = try power()
        guard divisor != 0 else { throw MikroKhorosError.function("division by zero") }
        value = floor(value / divisor)
      case .modulo:
        advance()
        let divisor = try power()
        guard divisor != 0 else { throw MikroKhorosError.function("division by zero") }
        value.formTruncatingRemainder(dividingBy: divisor)
      default: return value
      }
    }
  }

  private mutating func power() throws -> Double {
    let base = try unary()
    guard current == .power else { return base }
    advance()
    let exponent = try power()
    guard abs(exponent) <= 100 else {
      throw MikroKhorosError.function("exponent magnitude cannot exceed 100")
    }
    return Foundation.pow(base, exponent)
  }

  private mutating func unary() throws -> Double {
    switch current {
    case .plus:
      advance()
      return try unary()
    case .minus:
      advance()
      return -(try unary())
    default: return try primary()
    }
  }

  private mutating func primary() throws -> Double {
    switch current {
    case .number(let value):
      advance()
      return value
    case .leftParenthesis:
      advance()
      let value = try expression()
      guard current == .rightParenthesis else {
        throw MikroKhorosError.function("missing ')' in calculation")
      }
      advance()
      return value
    default:
      throw MikroKhorosError.function("expected a number or '('")
    }
  }

  private static func tokenize(_ expression: String) throws -> [ArithmeticToken] {
    let characters = Array(expression)
    var result: [ArithmeticToken] = []
    var index = 0
    while index < characters.count {
      let character = characters[index]
      if character.isWhitespace {
        index += 1
        continue
      }
      if character.isNumber || character == "." {
        let start = index
        var sawDot = character == "."
        index += 1
        while index < characters.count {
          let next = characters[index]
          if next.isNumber {
            index += 1
          } else if next == ".", !sawDot {
            sawDot = true
            index += 1
          } else {
            break
          }
        }
        let text = String(characters[start..<index])
        guard let value = Double(text), value.isFinite else {
          throw MikroKhorosError.function("calculation contains an invalid number")
        }
        result.append(.number(value))
        continue
      }
      switch character {
      case "+": result.append(.plus)
      case "-": result.append(.minus)
      case "*":
        if index + 1 < characters.count, characters[index + 1] == "*" {
          result.append(.power)
          index += 1
        } else {
          result.append(.multiply)
        }
      case "/":
        if index + 1 < characters.count, characters[index + 1] == "/" {
          result.append(.floorDivide)
          index += 1
        } else {
          result.append(.divide)
        }
      case "%": result.append(.modulo)
      case "(": result.append(.leftParenthesis)
      case ")": result.append(.rightParenthesis)
      default:
        throw MikroKhorosError.function("calculation contains an unsupported character")
      }
      index += 1
    }
    return result
  }
}

public final class CalculatorObject: MikroObject {
  public init(
    name: String = "calculator",
    origin: ObjectOrigin = .genesis,
    hash: String? = nil
  ) throws {
    try super.init(
      typeName: "calculator.object",
      name: name,
      summary: "A small arithmetic calculator with no code execution.",
      origin: origin,
      hash: hash
    )
    try registerFunction(
      name: "calculate",
      summary: "Evaluate arithmetic using +, -, *, /, //, %, and **.",
      parameters: ["expression"]
    ) { _, arguments in
      try expect(arguments, minimum: 1)
      var parser = try ArithmeticParser(arguments[0])
      let result = try parser.evaluate()
      if result.rounded() == result, result >= Double(Int.min), result <= Double(Int.max) {
        return String(Int(result))
      }
      return String(result)
    }
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try CalculatorObject(name: name, origin: origin, hash: hash)
  }
}

public final class EyeObject: MikroObject {
  public static let radius = 2

  public init(
    name: String = "Eye",
    durability: Int? = nil,
    hash: String? = nil
  ) throws {
    try super.init(
      typeName: "eye.object",
      name: name,
      summary: "A handheld object for seeing the nearby 5-by-5 world.",
      publicData: ["view_width": .number(5), "view_height": .number(5)],
      durability: durability,
      origin: .genesis,
      hash: hash
    )
    try registerFunction(
      name: "look",
      summary: "Observe the fixed 5-by-5 area centered on the carrier.",
      durabilityCost: durability == nil ? 0 : 1
    ) { context, arguments in
      try expect(arguments, minimum: 0)
      guard context.agent.primaryHeldObject === context.object else {
        throw MikroKhorosError.runtime(
          "eye.not_held",
          "the eye must be held to look through it",
          suggestions: ["pick up the eye, then run `object (look)`"]
        )
      }
      return try context.harness.renderEyeView(for: context.agent)
    }
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try EyeObject(name: name, durability: maximumDurability, hash: hash)
  }
}

public enum BroadcastPriority: String, Codable, CaseIterable, Comparable, Sendable {
  case one = "!"
  case two = "!!"
  case three = "!!!"

  public static func < (lhs: BroadcastPriority, rhs: BroadcastPriority) -> Bool {
    lhs.rawValue.count < rhs.rawValue.count
  }

  public static func parse(_ value: String) throws -> BroadcastPriority {
    guard let priority = BroadcastPriority(rawValue: value) else {
      throw MikroKhorosError.function("priority must be !, !!, or !!!")
    }
    return priority
  }
}

public struct MessengerMessage: Codable, Equatable, Sendable {
  public let id: String
  public let threadID: String
  public let sender: String
  public let senderAgentID: String?
  public let body: String
  public let priority: BroadcastPriority?
  public let timestamp: Date
  public var isRead: Bool

  public init(
    id: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
    threadID: String = "#1",
    sender: String,
    senderAgentID: String? = nil,
    body: String,
    priority: BroadcastPriority? = nil,
    timestamp: Date = Date(),
    isRead: Bool = false
  ) {
    self.id = id
    self.threadID = threadID
    self.sender = sender
    self.senderAgentID = senderAgentID
    self.body = body
    self.priority = priority
    self.timestamp = timestamp
    self.isRead = isRead
  }

  public var preview: String { String(body.prefix(255)) }
}

public struct MessengerThread: Codable, Equatable, Sendable {
  public let id: String
  public var title: String

  public init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}

public struct MessengerReadReceipt: Codable, Equatable, Sendable {
  public let messageID: String
  public let readerAgentID: String
  public let timestamp: Date
}

public protocol BroadcastSource: AnyObject {
  func latestUnreadEvent() -> AgentBroadcastEvent?
  /// Returns at most `limit` unread events in deterministic source order. A
  /// source must never use this method to expose another owner's state.
  func unreadEvents(limit: Int) -> [AgentBroadcastEvent]
  /// Acknowledges exactly one event after the host has successfully delivered
  /// it to the model. Unknown ids are a safe no-op.
  @discardableResult
  func acknowledge(eventID: String) -> Bool
}

extension BroadcastSource {
  public func unreadEvents(limit: Int) -> [AgentBroadcastEvent] {
    guard limit > 0 else { return [] }
    return Array((latestUnreadEvent().map { [$0] } ?? []).prefix(limit))
  }

  /// Look up one exact unread event without exposing a source-specific state
  /// representation.  Concrete sources override this with a direct lookup;
  /// the bounded default keeps third-party sources source-compatible.
  public func unreadEvent(eventID: String) -> AgentBroadcastEvent? {
    guard !eventID.isEmpty else { return nil }
    return unreadEvents(limit: 256).first(where: { $0.id == eventID })
  }

  @discardableResult
  public func acknowledge(eventID: String) -> Bool { false }
}

public final class MessengerObject: MikroObject, BroadcastSource {
  public static let maximumMessageCharacters = 65_536
  public static let maximumSenderCharacters = 128
  public static let maximumBroadcastEvents = 256
  public private(set) var threads: [MessengerThread]
  public private(set) var messages: [MessengerMessage]
  public private(set) var readReceipts: [MessengerReadReceipt]

  public init(
    name: String = "messager",
    threads: [MessengerThread] = [MessengerThread(id: "#1", title: "Messages")],
    messages: [MessengerMessage] = [],
    readReceipts: [MessengerReadReceipt] = [],
    origin: ObjectOrigin = .genesis,
    hash: String? = nil
  ) throws {
    self.threads = threads.isEmpty ? [MessengerThread(id: "#1", title: "Messages")] : threads
    self.messages = messages
    self.readReceipts = readReceipts
    try super.init(
      typeName: "messager.object",
      name: name,
      summary: "A persistent messenger application with threads and read receipts.",
      publicData: ["broadcastable": .bool(true), "preview_limit": .number(255)],
      origin: origin,
      hash: hash
    )
    try registerFunction(name: "threads", summary: "List persistent chat threads.") {
      context, arguments in
      try expect(arguments, minimum: 0)
      let object = context.object as! MessengerObject
      var lines = ["threads:"]
      for thread in object.threads {
        let unread = object.messages.filter { $0.threadID == thread.id && !$0.isRead }.count
        lines.append("  - id: \(PromptSafety.yamlScalar(thread.id, limit: 64))")
        lines.append("    title: \(PromptSafety.yamlScalar(thread.title, limit: 255))")
        lines.append("    unread: \(unread)")
      }
      return lines.joined(separator: "\n")
    }
    try registerFunction(
      name: "thread_create",
      summary: "Create a persistent thread.",
      parameters: ["title"]
    ) { context, arguments in
      try expect(arguments, minimum: 1)
      let object = context.object as! MessengerObject
      let thread = try object.createThread(title: arguments[0])
      return "created thread \(thread.id)"
    }
    try registerFunction(
      name: "read",
      summary: "Read messages using a Python index or slice such as -1 or -10:.",
      parameters: ["thread", "index_or_slice"]
    ) { context, arguments in
      try expect(arguments, minimum: 2)
      return try (context.object as! MessengerObject).read(
        threadID: arguments[0],
        selection: arguments[1],
        readerAgentID: context.agent.hash
      )
    }
    try registerFunction(
      name: "send",
      summary:
        "Send to an agent ID or the dedicated human inbox; optional priority is !, !!, or !!!.",
      parameters: ["recipient", "thread", "body", "priority_optional"]
    ) { context, arguments in
      try expect(arguments, minimum: 3, maximum: 4)
      let priority = arguments.count == 4 ? try BroadcastPriority.parse(arguments[3]) : nil
      let message = try context.harness.sendMessage(
        from: context.agent,
        using: context.object as! MessengerObject,
        to: arguments[0],
        threadID: arguments[1],
        body: arguments[2],
        priority: priority
      )
      return
        "sent message #\(message.id) to \(PromptSafety.yamlScalar(arguments[0], limit: 128)) in thread \(arguments[1])"
    }
    try registerFunction(name: "unread", summary: "Count unread messages, optionally by thread.") {
      context, arguments in
      try expect(arguments, minimum: 0, maximum: 1)
      let object = context.object as! MessengerObject
      return String(
        object.messages.filter {
          !$0.isRead && (arguments.isEmpty || $0.threadID == arguments[0])
        }.count)
    }
  }

  @discardableResult
  public func createThread(title: String) throws -> MessengerThread {
    guard !title.isEmpty, title.count <= 255, !title.contains(where: { $0.isNewline }) else {
      throw MikroKhorosError.function("thread title must be one line of at most 255 characters")
    }
    let next = (threads.compactMap { Int($0.id.dropFirst()) }.max() ?? 0) + 1
    let thread = MessengerThread(id: "#\(next)", title: title)
    threads.append(thread)
    return thread
  }

  @discardableResult
  func ensureThread(id: String, title: String) throws -> MessengerThread {
    if let existing = threads.first(where: { $0.id == id }) { return existing }
    guard !id.isEmpty, id.count <= 64, !id.contains(where: { $0.isNewline }),
      !title.isEmpty, title.count <= 255, !title.contains(where: { $0.isNewline })
    else {
      throw MikroKhorosError.function(
        "thread identity and title must be bounded single-line values")
    }
    let thread = MessengerThread(id: id, title: title)
    threads.append(thread)
    return thread
  }

  @discardableResult
  public func receive(
    _ body: String,
    id: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
    sender: String,
    senderAgentID: String? = nil,
    threadID: String = "#1",
    priority: BroadcastPriority? = nil,
    timestamp: Date = Date()
  ) throws -> MessengerMessage {
    try validateMessage(body: body, sender: sender, threadID: threadID)
    let message = MessengerMessage(
      id: id,
      threadID: threadID,
      sender: sender,
      senderAgentID: senderAgentID,
      body: body,
      priority: priority,
      timestamp: timestamp,
      isRead: false
    )
    if let existing = messages.first(where: { $0.id == id }) {
      guard existing == message else {
        throw MikroKhorosError.persistence("message identity has conflicting replay content")
      }
      return existing
    }
    messages.append(message)
    return message
  }

  public func latestUnreadEvent() -> AgentBroadcastEvent? {
    guard let message = messages.last(where: { !$0.isRead }) else { return nil }
    let title = threads.first(where: { $0.id == message.threadID })?.title ?? message.sender
    return AgentBroadcastEvent(
      id: message.id,
      timestamp: message.timestamp,
      sourceID: hash,
      sourceType: typeName,
      priority: message.priority?.rawValue,
      title: title,
      body: message.preview
    )
  }

  public func unreadEvents(limit: Int) -> [AgentBroadcastEvent] {
    guard limit > 0 else { return [] }
    // The source order is message insertion order.  Enumerate the oldest
    // unread prefix so a bounded read never skips an earlier notification.
    return messages.filter { !$0.isRead }
      .prefix(min(limit, Self.maximumBroadcastEvents)).map { message in
        let title = threads.first(where: { $0.id == message.threadID })?.title ?? message.sender
        return AgentBroadcastEvent(
          id: message.id,
          timestamp: message.timestamp,
          sourceID: hash,
          sourceType: typeName,
          priority: message.priority?.rawValue,
          title: title,
          body: message.preview
        )
      }
  }

  public func unreadEvent(eventID: String) -> AgentBroadcastEvent? {
    guard let message = messages.first(where: { $0.id == eventID && !$0.isRead }) else {
      return nil
    }
    let title = threads.first(where: { $0.id == message.threadID })?.title ?? message.sender
    return AgentBroadcastEvent(
      id: message.id,
      timestamp: message.timestamp,
      sourceID: hash,
      sourceType: typeName,
      priority: message.priority?.rawValue,
      title: title,
      body: message.preview
    )
  }

  @discardableResult
  public func acknowledge(eventID: String) -> Bool {
    guard let index = messages.firstIndex(where: { $0.id == eventID && !$0.isRead }) else {
      return false
    }
    messages[index].isRead = true
    return true
  }

  public func drainReadReceipts() -> [MessengerReadReceipt] {
    let result = readReceipts
    readReceipts.removeAll()
    return result
  }

  func recordSent(
    threadID: String,
    body: String,
    priority: BroadcastPriority?,
    agent: Agent,
    id: String,
    timestamp: Date
  ) throws -> MessengerMessage {
    try validateMessage(body: body, sender: agent.name, threadID: threadID)
    let message = MessengerMessage(
      id: id,
      threadID: threadID,
      sender: agent.name,
      senderAgentID: agent.hash,
      body: body,
      priority: priority,
      timestamp: timestamp,
      isRead: true
    )
    messages.append(message)
    return message
  }

  private func validateMessage(body: String, sender: String, threadID: String) throws {
    try Self.validateEnvelope(body: body, sender: sender)
    guard threads.contains(where: { $0.id == threadID }) else {
      throw MikroKhorosError.function("thread was not found")
    }
  }

  static func validateEnvelope(body: String, sender: String) throws {
    guard body.count <= maximumMessageCharacters else {
      throw MikroKhorosError.function("message exceeds the storage limit")
    }
    guard !sender.isEmpty, sender.count <= maximumSenderCharacters,
      !sender.contains(where: { $0.isNewline })
    else {
      throw MikroKhorosError.function("message sender must be one line of at most 128 characters")
    }
  }

  private func read(
    threadID: String,
    selection: String,
    readerAgentID: String
  ) throws -> String {
    guard threads.contains(where: { $0.id == threadID }) else {
      throw MikroKhorosError.function("thread was not found")
    }
    let indices = messages.indices.filter { messages[$0].threadID == threadID }
    let selected = try selectedOffsets(selection, count: indices.count).map { indices[$0] }
    let now = Date()
    for index in selected where !messages[index].isRead {
      messages[index].isRead = true
      readReceipts.append(
        MessengerReadReceipt(
          messageID: messages[index].id,
          readerAgentID: readerAgentID,
          timestamp: now
        )
      )
    }
    guard !selected.isEmpty else { return "messages: []" }
    var lines = ["messages:"]
    let formatter = ISO8601DateFormatter()
    for index in selected {
      let message = messages[index]
      lines.append("  - id: \(PromptSafety.yamlScalar(message.id, limit: 128))")
      lines.append("    thread: \(PromptSafety.yamlScalar(message.threadID, limit: 64))")
      lines.append("    sender: \(PromptSafety.yamlScalar(message.sender, limit: 128))")
      lines.append(
        "    timestamp: \(PromptSafety.yamlScalar(formatter.string(from: message.timestamp)))")
      lines.append(
        "    body: \(PromptSafety.yamlScalar(message.body, limit: Self.maximumMessageCharacters))")
      if let priority = message.priority {
        lines.append("    priority: \(PromptSafety.yamlScalar(priority.rawValue, limit: 3))")
      } else {
        lines.append("    priority: null")
      }
      lines.append("    seen: true")
    }
    return lines.joined(separator: "\n")
  }

  private func selectedOffsets(_ source: String, count: Int) throws -> [Int] {
    if source.contains(":") {
      let parts = source.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else { throw MikroKhorosError.function("invalid Python slice") }
      let rawStart = parts[0].isEmpty ? nil : Int(parts[0])
      let rawEnd = parts[1].isEmpty ? nil : Int(parts[1])
      if (!parts[0].isEmpty && rawStart == nil) || (!parts[1].isEmpty && rawEnd == nil) {
        throw MikroKhorosError.function("invalid Python slice")
      }
      let start = min(max(normalize(rawStart ?? 0, count: count, endpoint: true), 0), count)
      let end = min(max(normalize(rawEnd ?? count, count: count, endpoint: true), 0), count)
      return start < end ? Array(start..<end) : []
    }
    guard let raw = Int(source) else {
      throw MikroKhorosError.function("message selection must be a Python index or slice")
    }
    let index = normalize(raw, count: count, endpoint: false)
    guard indicesContain(index, count: count) else {
      throw MikroKhorosError.function("message index is out of range")
    }
    return [index]
  }

  private func normalize(_ value: Int, count: Int, endpoint: Bool) -> Int {
    value < 0 ? count + value : value
  }

  private func indicesContain(_ index: Int, count: Int) -> Bool {
    index >= 0 && index < count
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try MessengerObject(name: name, origin: origin, hash: hash)
  }
}

/// Native world wallet. A wallet is a concrete object in the agent backpack at
/// (4,0); the ledger and its signatures live in ``CreditService``. The object
/// deliberately stores no balance or mode. A fabricated/copy object with the
/// same type name therefore cannot create a spendable account.
public final class WalletObject: MikroObject, BroadcastSource {
  public static let maximumBroadcastEvents = 256
  private var broadcastEvents: [AgentBroadcastEvent] = []

  public init(
    name: String = "wallet",
    hash: String? = nil
  ) throws {
    try super.init(
      typeName: "wallet.object",
      name: name,
      summary: "A native signed credit account bound to one agent backpack.",
      publicData: ["currency": .string("credit")],
      origin: .genesis,
      hash: hash,
      allowReservedNativeType: true
    )
    try registerFunction(name: "balance", summary: "Show the current credit balance.") {
      context, arguments in
      try expect(arguments, minimum: 0)
      let wallet = context.object as! WalletObject
      try wallet.requireExactAgentWallet(context: context)
      try context.harness.requireWalletOwner(context.agent, wallet)
      guard let service = context.harness.creditService else {
        throw MikroKhorosError.runtime("wallet.unavailable", "the wallet service is unavailable")
      }
      return try AgentWalletProjection.renderBalance(service: service, walletID: wallet.hash)
    }
    try registerFunction(
      name: "statement",
      summary: "Show a bounded newest-first statement for this wallet.",
      parameters: ["cursor_optional", "count_optional"]
    ) { context, arguments in
      try expect(arguments, minimum: 0, maximum: 2)
      let wallet = context.object as! WalletObject
      try wallet.requireExactAgentWallet(context: context)
      try context.harness.requireWalletOwner(context.agent, wallet)
      guard let service = context.harness.creditService else {
        throw MikroKhorosError.runtime("wallet.unavailable", "the wallet service is unavailable")
      }
      let parsed = try Self.parseStatementArguments(arguments)
      return try AgentWalletProjection.renderStatement(
        service: service,
        walletID: wallet.hash,
        cursor: parsed.cursor,
        count: parsed.count
      )
    }
    try registerFunction(name: "verify", summary: "Verify the local signed credit chain.") {
      context, arguments in
      try expect(arguments, minimum: 0)
      let wallet = context.object as! WalletObject
      try wallet.requireExactAgentWallet(context: context)
      try context.harness.requireWalletOwner(context.agent, wallet)
      guard let service = context.harness.creditService else {
        throw MikroKhorosError.runtime("wallet.unavailable", "the wallet service is unavailable")
      }
      return try AgentWalletProjection.renderVerify(service: service, walletID: wallet.hash)
    }
    try registerFunction(
      name: "transfer",
      summary: "Transfer credit to one exact destination wallet id.",
      parameters: ["destination_wallet_id", "amount", "note_optional"]
    ) { context, arguments in
      try expect(arguments, minimum: 2, maximum: 3)
      let wallet = context.object as! WalletObject
      try wallet.requireExactAgentWallet(context: context)
      try context.harness.requireWalletOwner(context.agent, wallet)
      guard let service = context.harness.creditService else {
        throw MikroKhorosError.runtime("wallet.unavailable", "the wallet service is unavailable")
      }
      let amount = try CreditAmount.parse(arguments[1])
      let note = arguments.count == 3 ? arguments[2] : ""
      guard note.count <= UnsignedCreditRecord.maxNoteLength else {
        throw MikroKhorosError.runtime(
          "wallet.note_too_long",
          "the wallet note exceeds the allowed length"
        )
      }
      guard Self.isExactWalletID(arguments[0]) else { throw Self.destinationUnavailable() }
      guard arguments[0] != wallet.hash else {
        throw MikroKhorosError.runtime(
          "wallet.transfer_same",
          "source and destination wallets must differ"
        )
      }
      guard let currentOwner = service.custodyOwner(for: wallet.hash),
        currentOwner == context.agent.hash,
        let custodyCommitment = service.custodyCommitment(for: wallet.hash),
        !custodyCommitment.isEmpty
      else {
        throw MikroKhorosError.runtime(
          "wallet.custody_stale",
          "the wallet custody is not current"
        )
      }
      guard service.canSignMutations else {
        throw MikroKhorosError.runtime(
          "wallet.credential_unavailable",
          "the treasury credential is unavailable; verify-only mode cannot mutate credit"
        )
      }
      // Resolve all source-side authorization and funds failures before
      // touching the write-only recipient capability. Otherwise a sender
      // could probe destination existence using an intentionally empty Wallet.
      guard try service.balance(for: wallet.hash).minorUnits >= amount.minorUnits else {
        throw MikroKhorosError.runtime(
          "wallet.insufficient_funds",
          "the source wallet has insufficient funds"
        )
      }
      guard let destination = context.harness.findObject(arguments[0]) as? WalletObject,
        context.harness.findObject(destination.hash) === destination,
        service.registration(for: destination.hash) != nil
      else { throw Self.destinationUnavailable() }
      do {
        let operation = context.harness.creditOperationIdentity()
        let result = try service.transfer(
          from: wallet.hash,
          to: arguments[0],
          amount: amount,
          actor: .agent,
          operationID: operation.operationID,
          actionIndex: operation.actionIndex,
          sourceOwner: currentOwner,
          sourceCustodyCommitment: custodyCommitment,
          causalObjectIDs: [wallet.hash],
          causalFunctionIDs: ["wallet.transfer"],
          note: note
        )
        guard
          let record = service.chain.last(where: {
            $0.unsigned.operationID == operation.operationID
              && $0.unsigned.actionIndex == operation.actionIndex
          })
        else {
          throw MikroKhorosError.runtime(
            "wallet.transfer_failed",
            "the transfer result is unavailable"
          )
        }
        return try AgentWalletProjection.renderTransfer(
          record: record,
          sourceWalletID: wallet.hash,
          fallbackSourceBalance: result.source
        )
      } catch let error as MikroKhorosError {
        // Preserve only failures attributable to the invoking source Wallet.
        // Every destination-side or registry failure shares one response so
        // the write-only destination ID cannot become a balance/location oracle.
        if [
          "wallet.insufficient_funds",
          "wallet.owner_mismatch",
          "wallet.custody_stale",
          "wallet.operation_conflict",
          "wallet.credential_unavailable",
        ].contains(error.issue.code) {
          throw error
        }
        throw Self.destinationUnavailable()
      } catch {
        throw MikroKhorosError.runtime(
          "wallet.transfer_failed", "the transfer could not be completed")
      }
    }
  }

  private func requireExactAgentWallet(context: TrustedInvocationContext) throws {
    guard context.harness.findObject(hash) === self,
      context.object === self
    else {
      throw MikroKhorosError.runtime(
        "wallet.owner_denied",
        "wallet access is not authorized"
      )
    }
  }

  private static func isExactWalletID(_ value: String) -> Bool {
    // Do not resolve prefixes here: doing so would create an enumeration and
    // ambiguity oracle for a transfer destination.  The exact registration
    // lookup in CreditService remains the authority for the accepted ID; this
    // shape check only rejects whitespace and control data.  Case is part of
    // the exact identifier and must not be normalized here.
    !value.isEmpty && value.count <= UnsignedCreditRecord.maxIdentifierLength
      && !value.unicodeScalars.contains(where: {
        CharacterSet.whitespacesAndNewlines.contains($0)
          || CharacterSet.controlCharacters.contains($0)
      })
  }

  private static func destinationUnavailable() -> MikroKhorosError {
    .runtime(
      "wallet.destination_unavailable",
      "the destination wallet is unavailable"
    )
  }

  private static func parseStatementArguments(
    _ arguments: [String]
  ) throws -> (cursor: String?, count: Int) {
    guard !arguments.isEmpty else {
      return (nil, AgentWalletProjection.maximumStatementCount)
    }
    if arguments.count == 1, let count = Int(arguments[0]) {
      guard count > 0 else {
        throw MikroKhorosError.runtime(
          "wallet.statement_limit",
          "wallet statement count must be positive"
        )
      }
      return (nil, count)
    }
    let count: Int
    if arguments.count == 2 {
      guard let parsed = Int(arguments[1]), parsed > 0 else {
        throw MikroKhorosError.runtime(
          "wallet.statement_limit",
          "wallet statement count must be positive"
        )
      }
      count = parsed
    } else {
      count = AgentWalletProjection.maximumStatementCount
    }
    guard !arguments[0].isEmpty else {
      throw MikroKhorosError.runtime(
        "wallet.statement_cursor_invalid",
        "wallet statement cursor is invalid"
      )
    }
    return (arguments[0], count)
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    throw MikroKhorosError.objectPackage("wallet.object is native and cannot be copied")
  }

  /// The runtime records wallet activity as a bounded source event. The event
  /// is intentionally separate from the ledger: the signed ledger remains the
  /// source of truth and this queue only carries a model-facing notification.
  @discardableResult
  public func recordBroadcast(_ event: AgentBroadcastEvent) -> Bool {
    guard (try? PromptSafety.validateBroadcastEvent(event)) != nil else { return false }
    guard event.sourceID == hash, event.sourceType == typeName,
      event.timestamp.timeIntervalSince1970.isFinite,
      !event.id.isEmpty, event.id.count <= 256,
      !event.sourceID.isEmpty, event.sourceID.count <= 128,
      !event.sourceType.isEmpty, event.sourceType.count <= 128,
      event.title.count <= 255,
      event.body.count <= AgentBroadcastEvent.maximumBodyCharacters,
      [nil, "!", "!!", "!!!"].contains(event.priority),
      !event.id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
      !event.sourceID.unicodeScalars.contains(where: {
        CharacterSet.controlCharacters.contains($0)
      }),
      !event.title.unicodeScalars.contains(where: {
        CharacterSet.controlCharacters.subtracting(.newlines).contains($0)
      }),
      !event.body.unicodeScalars.contains(where: {
        CharacterSet.controlCharacters.subtracting(.newlines).contains($0)
      })
    else { return false }
    // Event identity is immutable.  Replays of the same operation are a
    // no-op, preserving source order instead of moving a duplicate to the
    // newest position.
    guard !broadcastEvents.contains(where: { $0.id == event.id }) else { return false }
    broadcastEvents.append(event)
    if broadcastEvents.count > Self.maximumBroadcastEvents {
      broadcastEvents.removeFirst(broadcastEvents.count - Self.maximumBroadcastEvents)
    }
    return true
  }

  public func latestUnreadEvent() -> AgentBroadcastEvent? {
    broadcastEvents.last
  }

  public func unreadEvents(limit: Int) -> [AgentBroadcastEvent] {
    guard limit > 0 else { return [] }
    return Array(broadcastEvents.prefix(min(limit, Self.maximumBroadcastEvents)))
  }

  public func unreadEvent(eventID: String) -> AgentBroadcastEvent? {
    broadcastEvents.first(where: { $0.id == eventID })
  }

  @discardableResult
  public func acknowledge(eventID: String) -> Bool {
    guard let index = broadcastEvents.firstIndex(where: { $0.id == eventID }) else {
      return false
    }
    broadcastEvents.remove(at: index)
    return true
  }
}

public final class PortalObject: MikroObject {
  public private(set) var keyHash: String?

  public init(name: String = "portal", keyHash: String? = nil, hash: String? = nil) throws {
    self.keyHash = keyHash
    try super.init(
      typeName: "portal.object",
      name: name,
      summary: "A fixed teleport destination paired with a key.",
      hash: hash
    )
    if let keyHash { setPublicData(.string(keyHash), forKey: "key_hash") }
  }

  public func pair(with keyHash: String) throws {
    if let current = self.keyHash, current != keyHash {
      throw MikroKhorosError.function("portal is already paired with another key")
    }
    self.keyHash = keyHash
    setPublicData(.string(keyHash), forKey: "key_hash")
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try PortalObject(name: name, hash: hash)
  }
}

public final class KeyObject: MikroObject {
  public let portalHash: String

  public init(
    portalHash: String,
    name: String = "portal key",
    durability: Int? = nil,
    hash: String? = nil
  ) throws {
    self.portalHash = portalHash
    try super.init(
      typeName: "key.object",
      name: name,
      summary: "Teleports its carrier to one paired portal instance.",
      publicData: ["portal_hash": .string(portalHash)],
      durability: durability,
      hash: hash
    )
    try registerFunction(
      name: "use",
      summary: "Store this key and teleport to the paired portal.",
      durabilityCost: durability == nil ? 0 : 1
    ) { context, arguments in
      try expect(arguments, minimum: 0)
      let key = context.object as! KeyObject
      guard let portal = context.harness.findObject(key.portalHash) as? PortalObject else {
        throw MikroKhorosError.runtime("object.unavailable", "the requested object is unavailable")
      }
      try context.harness.validateTeleportDestination(portal, for: context.agent)
      try context.harness.stowHeldObject(for: context.agent)
      try context.harness.teleport(context.agent, to: portal)
      return "teleported to \(context.harness.agentPath(context.agent))"
    }
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try KeyObject(
      portalHash: portalHash,
      name: name,
      durability: maximumDurability,
      hash: hash
    )
  }
}

public struct PortalPair {
  public let portal: PortalObject
  public let key: KeyObject
}

public func createPortalPair(
  portalName: String = "portal",
  keyName: String = "portal key",
  keyDurability: Int? = nil
) throws -> PortalPair {
  let portal = try PortalObject(name: portalName)
  let key = try KeyObject(portalHash: portal.hash, name: keyName, durability: keyDurability)
  try portal.pair(with: key.hash)
  return PortalPair(portal: portal, key: key)
}

public final class SummonerObject: MikroObject {
  public init(name: String = "summoner", durability: Int? = nil, hash: String? = nil) throws {
    try super.init(
      typeName: "summoner.object",
      name: name,
      summary: "Moves one previously inspected object instance to the agent.",
      durability: durability,
      hash: hash
    )
    try registerFunction(
      name: "summon",
      summary: "Store this summoner and move a known object to the current coordinate.",
      parameters: ["object_hash"],
      durabilityCost: durability == nil ? 0 : 1
    ) { context, arguments in
      try expect(arguments, minimum: 1)
      guard context.agent.primaryHeldObject === context.object else {
        throw MikroKhorosError.runtime(
          "object.unavailable",
          "the requested object is unavailable"
        )
      }
      let object = try context.harness.stowPrimaryAndSummon(arguments[0], for: context.agent)
      return "summoned \(object.name) #\(object.hash) to \(context.agent.coordinate)"
    }
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try SummonerObject(name: name, durability: maximumDurability, hash: hash)
  }
}

public final class AppleObject: MikroObject {
  public init(name: String = "apple", durability: Int = 1, hash: String? = nil) throws {
    try super.init(
      typeName: "apple.object",
      name: name,
      summary: "An edible example object.",
      durability: durability,
      hash: hash
    )
    try registerFunction(
      name: "eat",
      summary: "Eat a fraction greater than 0 and at most 1.",
      parameters: ["amount"],
      durabilityCost: 1
    ) { context, arguments in
      try expect(arguments, minimum: 1)
      let amount = try parseDecimal(arguments[0], label: "amount")
      guard amount > 0, amount <= 1 else {
        throw MikroKhorosError.function("amount must be greater than 0 and at most 1")
      }
      return "ate \(formatAmount(amount)) of \(context.object.name)"
    }
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try AppleObject(name: name, durability: maximumDurability ?? 1, hash: hash)
  }
}

public final class MerchantObject: MikroObject {
  public let shopHash: String
  public private(set) var prices: [String: Decimal]
  public let autoRestock: Bool

  public init(
    shopHash: String,
    prices: [String: Decimal],
    autoRestock: Bool,
    name: String = "merchant",
    origin: ObjectOrigin = .native,
    lineage: ObjectLineage? = nil,
    hash: String? = nil
  ) throws {
    do {
      for price in prices.values { _ = try Self.creditAmount(for: price) }
    } catch {
      throw MikroKhorosError.function(
        "shop prices must be positive credit values with at most two decimal places"
      )
    }
    self.shopHash = shopHash
    self.prices = prices
    self.autoRestock = autoRestock
    try super.init(
      typeName: "merchant.object",
      name: name,
      summary: "Accepts credit and reserves one concrete shop item for its buyer.",
      origin: origin,
      invocationAccess: .surface,
      lineage: lineage,
      hash: hash
    )
    try registerFunction(name: "catalog", summary: "List concrete item hashes and prices.") {
      context, arguments in
      try expect(arguments, minimum: 0)
      let merchant = context.object as! MerchantObject
      guard !merchant.prices.isEmpty else { return "catalog: []" }
      var lines = ["catalog:"]
      for hash in merchant.prices.keys.sorted() {
        guard let item = context.harness.findObject(hash) else { continue }
        let state: String
        if item.lockInfo?.mode == .denyAll, item.lockInfo?.owner == merchant.hash {
          state = "available"
        } else if item.lockInfo?.mode == .allowOnly {
          state = "reserved"
        } else {
          state = "sold"
        }
        lines.append("  - id: \(PromptSafety.yamlScalar(hash, limit: 128))")
        lines.append("    name: \(PromptSafety.yamlScalar(item.name, limit: 128))")
        lines.append("    price: \(PromptSafety.yamlScalar(formatAmount(merchant.prices[hash])))")
        lines.append("    state: \(state)")
      }
      return lines.joined(separator: "\n")
    }
    try registerFunction(
      name: "buy",
      summary: "Pay for and reserve one concrete item using an exact wallet id.",
      parameters: ["item_selector", "payer_wallet_id"]
    ) { context, arguments in
      try expect(arguments, minimum: 2, maximum: 2)
      let merchant = context.object as! MerchantObject
      let purchase = try context.harness.purchase(
        itemSelector: arguments[0], walletID: arguments[1], from: merchant, for: context.agent)
      return try AgentWalletProjection.renderPurchase(
        record: purchase.creditRecord,
        itemID: purchase.item.hash,
        payerWalletID: arguments[1]
      )
    }
  }

  static func creditAmount(for price: Decimal) throws -> CreditAmount {
    try CreditAmount.parse(NSDecimalNumber(decimal: price).stringValue)
  }

  func addPrice(_ price: Decimal, for objectID: String) throws {
    _ = try Self.creditAmount(for: price)
    prices[objectID] = price
  }

  func removePrice(for objectID: String) {
    prices.removeValue(forKey: objectID)
  }
}

public struct PricedObject {
  public let object: MikroObject
  public let price: Decimal

  public init(_ object: MikroObject, price: Decimal) {
    self.object = object
    self.price = price
  }
}

public func createContainer(
  name: String,
  typeName: String = "container.object",
  summary: String = ""
) throws -> MikroObject {
  let object = try MikroObject(typeName: typeName, name: name, summary: summary)
  try object.addContainerCapability()
  return object
}

public func createWorld(
  name: String = "world",
  hash: String? = nil
) throws -> MikroObject {
  let world = try MikroObject(
    typeName: "world.object",
    name: name,
    summary: "The root infinite sparse matrix.",
    origin: .genesis,
    hash: hash
  )
  try world.addContainerCapability()
  return world
}

public struct AgentGenesisIDs: Codable, Equatable, Sendable {
  public let backpack: String
  public let wallet: String
  public let eye: String
  public let scratchpad: String
  public let messenger: String
  public let calculator: String

  public init(
    backpack: String = AgentGenesisIDs.makeID(),
    wallet: String = AgentGenesisIDs.makeID(),
    eye: String = AgentGenesisIDs.makeID(),
    scratchpad: String = AgentGenesisIDs.makeID(),
    messenger: String = AgentGenesisIDs.makeID(),
    calculator: String = AgentGenesisIDs.makeID()
  ) {
    self.backpack = backpack
    self.wallet = wallet
    self.eye = eye
    self.scratchpad = scratchpad
    self.messenger = messenger
    self.calculator = calculator
  }

  public static func makeID() -> String {
    UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
  }
}

public func createBackpack(
  hash: String? = nil,
  scratchpadHash: String? = nil,
  messengerHash: String? = nil,
  calculatorHash: String? = nil,
  walletHash: String? = nil
) throws -> MikroObject {
  let backpack = try MikroObject(
    typeName: "backpack.object",
    name: "backpack",
    summary: "An attached infinite container carried by one agent.",
    origin: .genesis,
    hash: hash
  )
  try backpack.addContainerCapability()
  // Origin stays empty so an agent can enter and store its selected held object.
  try backpack.container!.place(
    try ScratchpadObject(hash: scratchpadHash), at: Coordinate(x: 1, y: 0)
  )
  try backpack.container!.place(
    try MessengerObject(hash: messengerHash), at: Coordinate(x: 2, y: 0)
  )
  try backpack.container!.place(
    try CalculatorObject(hash: calculatorHash), at: Coordinate(x: 3, y: 0)
  )
  try backpack.container!.place(
    try WalletObject(hash: walletHash), at: Coordinate(x: 4, y: 0)
  )
  return backpack
}

public func createBackpack(ids: AgentGenesisIDs) throws -> MikroObject {
  try createBackpack(
    hash: ids.backpack,
    scratchpadHash: ids.scratchpad,
    messengerHash: ids.messenger,
    calculatorHash: ids.calculator,
    walletHash: ids.wallet
  )
}

public func createShop(
  name: String,
  inventory: [PricedObject],
  autoRestock: Bool = false
) throws -> (shop: MikroObject, merchant: MerchantObject) {
  let shop = try createContainer(
    name: name,
    typeName: "shop.object",
    summary: "An infinite shop container anchored by a merchant at local origin."
  )
  try shop.lock(authority: .system, owner: "shop-system", reason: "shop_container")
  let merchant = try MerchantObject(
    shopHash: shop.hash,
    prices: Dictionary(uniqueKeysWithValues: inventory.map { ($0.object.hash, $0.price) }),
    autoRestock: autoRestock
  )
  try merchant.lock(authority: .system, owner: merchant.hash, reason: "merchant_anchor")
  try shop.container!.place(merchant, at: .origin)
  for (index, entry) in inventory.enumerated() {
    try entry.object.lock(authority: .system, owner: merchant.hash, reason: "shop_inventory")
    try shop.container!.place(entry.object, at: Coordinate(x: index + 1, y: 0))
  }
  return (shop, merchant)
}
