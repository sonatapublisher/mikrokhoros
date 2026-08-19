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
      guard context.agent.hand === context.object else {
        throw MikroKhorosError.runtime(
          "eye.not_held",
          "the eye must be held to look through it",
          suggestions: ["pick up the eye, then run `object (look)`"]
        )
      }
      return context.harness.renderEyeView(for: context.agent)
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
}

public final class MessengerObject: MikroObject, BroadcastSource {
  public static let maximumMessageCharacters = 65_536
  public static let maximumSenderCharacters = 128
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
      summary: "Send to an agent ID and thread; optional priority is !, !!, or !!!.",
      parameters: ["agent_id", "thread", "body", "priority_optional"]
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
      return "sent message #\(message.id) to agent #\(arguments[0]) in thread \(arguments[1])"
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

public final class CoinObject: MikroObject {
  public private(set) var balance: Decimal?

  public init(
    balance: Decimal? = 0,
    name: String = "coin",
    hash: String? = nil
  ) throws {
    if let balance, balance < 0 {
      throw MikroKhorosError.function("coin balance must be non-negative, or nil for infinite")
    }
    self.balance = balance
    try super.init(
      typeName: "coin.object",
      name: name,
      summary: "The agent's user-granted purchasing allowance.",
      origin: .genesis,
      hash: hash
    )
    try registerFunction(name: "balance", summary: "Show the remaining allowance.") {
      context, arguments in
      try expect(arguments, minimum: 0)
      return formatAmount((context.object as! CoinObject).balance)
    }
  }

  public func canPay(_ amount: Decimal) -> Bool {
    amount >= 0 && (balance == nil || balance! >= amount)
  }

  public func pay(_ amount: Decimal) throws {
    guard canPay(amount) else {
      throw MikroKhorosError.runtime(
        "purchase.insufficient_coin",
        "the agent does not have enough coin",
        details: ["price": formatAmount(amount), "balance": formatAmount(balance)],
        suggestions: ["choose a less expensive item or ask the human user to grant more coin"]
      )
    }
    if let balance { self.balance = balance - amount }
  }

  func refund(_ amount: Decimal) {
    if let balance { self.balance = balance + amount }
  }

  public func grant(_ amount: Decimal?) throws {
    guard let amount else {
      balance = nil
      return
    }
    guard amount >= 0 else {
      throw MikroKhorosError.function("grant must be non-negative, or nil for infinite")
    }
    if let balance { self.balance = balance + amount }
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
      guard let portal = try context.harness.object(byHash: key.portalHash) as? PortalObject else {
        throw MikroKhorosError.function("the paired portal no longer exists")
      }
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
      try context.harness.stowHeldObject(for: context.agent)
      let object = try context.harness.summon(arguments[0], for: context.agent)
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
    hash: String? = nil
  ) throws {
    guard prices.values.allSatisfy({ $0 >= 0 }) else {
      throw MikroKhorosError.function("shop prices must be non-negative")
    }
    self.shopHash = shopHash
    self.prices = prices
    self.autoRestock = autoRestock
    try super.init(
      typeName: "merchant.object",
      name: name,
      summary: "Accepts coin and reserves one concrete shop item for its buyer.",
      invocationAccess: .surface,
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
      summary: "Pay for and reserve one concrete item by hash.",
      parameters: ["object_hash"]
    ) { context, arguments in
      try expect(arguments, minimum: 1)
      let merchant = context.object as! MerchantObject
      let purchase = try context.harness.purchase(arguments[0], from: merchant, for: context.agent)
      var result =
        "paid \(formatAmount(purchase.price)) coin; reserved "
        + "\(purchase.item.name) #\(purchase.item.hash) for this agent"
      if let restocked = purchase.restocked {
        result += "; restocked #\(restocked.hash) at \(restocked.coordinate!)"
      }
      result += "; balance \(formatAmount(context.agent.coin.balance))"
      return result
    }
  }

  func addPrice(_ price: Decimal, for objectID: String) {
    prices[objectID] = price
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
  hash: String? = nil,
  genesisIDs: WorldGenesisIDs = WorldGenesisIDs()
) throws -> MikroObject {
  let world = try MikroObject(
    typeName: "world.object",
    name: name,
    summary: "The root infinite sparse matrix.",
    origin: .genesis,
    hash: hash
  )
  try world.addContainerCapability()
  try installWorldGenesis(in: world, ids: genesisIDs)
  return world
}

public struct AgentGenesisIDs: Codable, Equatable, Sendable {
  public let backpack: String
  public let coin: String
  public let eye: String
  public let scratchpad: String
  public let messenger: String
  public let calculator: String

  public init(
    backpack: String = AgentGenesisIDs.makeID(),
    coin: String = AgentGenesisIDs.makeID(),
    eye: String = AgentGenesisIDs.makeID(),
    scratchpad: String = AgentGenesisIDs.makeID(),
    messenger: String = AgentGenesisIDs.makeID(),
    calculator: String = AgentGenesisIDs.makeID()
  ) {
    self.backpack = backpack
    self.coin = coin
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
  calculatorHash: String? = nil
) throws -> MikroObject {
  let backpack = try MikroObject(
    typeName: "backpack.object",
    name: "backpack",
    summary: "An attached infinite container carried by one agent.",
    origin: .genesis,
    hash: hash
  )
  try backpack.addContainerCapability()
  // Origin stays empty so a loaded agent can enter and store its held object.
  try backpack.container!.place(
    try ScratchpadObject(hash: scratchpadHash), at: Coordinate(x: 1, y: 0)
  )
  try backpack.container!.place(
    try MessengerObject(hash: messengerHash), at: Coordinate(x: 2, y: 0)
  )
  try backpack.container!.place(
    try CalculatorObject(hash: calculatorHash), at: Coordinate(x: 3, y: 0)
  )
  return backpack
}

public func createBackpack(ids: AgentGenesisIDs) throws -> MikroObject {
  try createBackpack(
    hash: ids.backpack,
    scratchpadHash: ids.scratchpad,
    messengerHash: ids.messenger,
    calculatorHash: ids.calculator
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
