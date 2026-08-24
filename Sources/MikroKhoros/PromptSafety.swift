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

/// Deterministic boundaries for text crossing between mikrokhoros and an LLM.
/// These checks reduce the impact of prompt injection, but they are not an
/// authorization system. World permissions remain enforced by the runtime.
public enum PromptSafety {
  public static let historyCheckpoint = """
    context_scope:
      state_source: "current_request"
    """

  /// Reject a model response that contains a long verbatim window copied from
  /// privileged instructions or provider-visible user context. This is a narrow
  /// output-screening layer: it prevents direct prompt/envelope replay through an
  /// otherwise valid object action, but deterministic runtime authorization remains
  /// the actual security boundary.
  public static func validateModelOutput(
    _ response: String,
    system: String,
    input: String,
    history: [AIConversationMessage] = [],
    limits: RuntimeLimits = .defaults
  ) throws {
    guard response.count <= limits.maximumResponseCharacters else {
      throw MikroKhorosError.runtime(
        "model.output_too_large",
        "model output exceeded the execution limit and was not executed",
        suggestions: ["return a shorter batch of mikrokhoros actions"]
      )
    }
    guard !response.unicodeScalars.contains(where: isInvisibleFormatScalar) else {
      throw MikroKhorosError.runtime(
        "model.output_invisible_character",
        "model output contained an invisible formatting character and was not executed",
        suggestions: ["return visible plain-text mikrokhoros action lines"]
      )
    }
    guard
      !response.unicodeScalars.contains(where: {
        CharacterSet.controlCharacters.subtracting(.newlines).contains($0)
      })
    else {
      throw MikroKhorosError.runtime(
        "model.output_control_character",
        "model output contained a control character and was not executed",
        suggestions: ["return plain-text mikrokhoros action lines"]
      )
    }
    if containsProtectedVerbatimWindow(
      response,
      from: system,
      minimumWords: limits.minimumProtectedVerbatimWords
    ) {
      throw MikroKhorosError.runtime(
        "model.output_instruction_leakage",
        "model output copied protected runtime instructions and was not executed",
        suggestions: ["return only the chosen mikrokhoros action without copying runtime text"]
      )
    }
    if containsProtectedVerbatimWindow(
      response,
      from: input,
      minimumWords: limits.minimumProtectedVerbatimWords
    ) {
      throw MikroKhorosError.runtime(
        "model.output_prompt_echo",
        "model output copied the current request envelope and was not executed",
        suggestions: ["return only the chosen mikrokhoros action without copying request data"]
      )
    }
    for message in history where isProtectedHistoricalContext(message) {
      if containsProtectedVerbatimWindow(
        response,
        from: message.content,
        minimumWords: limits.minimumProtectedVerbatimWords
      ) {
        throw MikroKhorosError.runtime(
          "model.output_history_echo",
          "model output copied earlier model-visible context and was not executed",
          suggestions: ["return only the chosen mikrokhoros action without copying prior context"]
        )
      }
    }
  }

  /// Validate all model-visible history before a provider receives it. Persisted
  /// model-visible contexts are untrusted until this boundary succeeds.
  public static func validateModelHistory(
    _ history: [AIConversationMessage],
    limits: RuntimeLimits = .defaults
  ) throws {
    guard history.count <= limits.maximumModelHistoryMessages else {
      throw invalidHistory()
    }
    guard
      history.reduce(0, { $0 + $1.content.count })
        <= limits.maximumModelHistoryCharacters
    else {
      throw invalidHistory()
    }
    for message in history {
      guard !message.content.isEmpty,
        message.content.count <= limits.maximumModelInputCharacters,
        !message.content.unicodeScalars.contains(where: {
          CharacterSet.controlCharacters.subtracting(.newlines).contains($0)
        }),
        !message.content.unicodeScalars.contains(where: isInvisibleFormatScalar)
      else {
        throw invalidHistory()
      }
      switch message.role {
      case .assistant:
        do {
          let parsed = try actionLines(
            from: message.content,
            maximumActions: limits.maximumActionsPerResponse,
            limits: limits
          )
          guard parsed.ignored == 0 else { throw invalidHistory() }
          for action in parsed.accepted {
            let validated = try validatedAction(action, limits: limits)
            guard hasAllowedActionHead(validated) else { throw invalidHistory() }
          }
        } catch {
          throw invalidHistory()
        }
      case .user:
        guard message.content == historyCheckpoint || isCanonicalEventEnvelope(message.content)
        else {
          throw invalidHistory()
        }
      }
    }
  }

  public static func validateModelContext(
    request: AgentModelRequest,
    history: [AIConversationMessage],
    limits: RuntimeLimits = .defaults
  ) throws {
    guard request.system.count <= limits.maximumModelInputCharacters,
      request.input.count <= limits.maximumModelInputCharacters,
      !request.system.unicodeScalars.contains(where: {
        CharacterSet.controlCharacters.subtracting(.newlines).contains($0)
      }),
      !request.system.unicodeScalars.contains(where: isInvisibleFormatScalar),
      !request.input.unicodeScalars.contains(where: {
        CharacterSet.controlCharacters.subtracting(.newlines).contains($0)
      }),
      !request.input.unicodeScalars.contains(where: isInvisibleFormatScalar)
    else {
      throw MikroKhorosError.runtime(
        "model.context_invalid",
        "model-visible context failed structural validation"
      )
    }
    try validateModelHistory(history, limits: limits)
    let total =
      request.system.count + request.input.count
      + history.reduce(0) { $0 + $1.content.count }
    guard total <= limits.maximumModelContextCharacters else {
      throw MikroKhorosError.runtime(
        "model.context_too_large",
        "model-visible context exceeds the provider boundary",
        suggestions: ["reduce retained history or carried public data"]
      )
    }
  }

  /// Validate the bounded public portion of one broadcast before it is put in
  /// a model request.  Source ownership and unread state are checked by the
  /// runtime; this helper only protects the projection's shape and resource
  /// boundary.
  public static func validateBroadcastEvent(
    _ event: AgentBroadcastEvent,
    limits: RuntimeLimits = .defaults
  ) throws {
    let fieldLimit = limits.maximumModelFieldCharacters
    guard event.timestamp.timeIntervalSince1970.isFinite,
      !event.id.isEmpty, event.id.count <= min(256, fieldLimit),
      !event.sourceID.isEmpty, event.sourceID.count <= min(128, fieldLimit),
      !event.sourceType.isEmpty, event.sourceType.count <= min(128, fieldLimit),
      event.title.count <= min(255, fieldLimit),
      event.body.count <= min(AgentBroadcastEvent.maximumBodyCharacters, fieldLimit),
      [nil, "!", "!!", "!!!"].contains(event.priority),
      !event.id.unicodeScalars.contains(where: {
        CharacterSet.controlCharacters.contains($0)
      }),
      !event.sourceID.unicodeScalars.contains(where: {
        CharacterSet.controlCharacters.contains($0)
      }),
      !event.sourceType.unicodeScalars.contains(where: {
        CharacterSet.controlCharacters.contains($0)
      }),
      !event.title.unicodeScalars.contains(where: {
        CharacterSet.controlCharacters.subtracting(.newlines).contains($0)
      }),
      !event.body.unicodeScalars.contains(where: {
        CharacterSet.controlCharacters.subtracting(.newlines).contains($0)
      })
    else {
      throw MikroKhorosError.runtime(
        "model.broadcast_invalid",
        "broadcast event failed structural validation"
      )
    }
  }

  /// Validate one action line after a multi-action response has been split and
  /// bounded. Batch support must not weaken this per-line validation.
  public static func validatedAction(
    _ source: String,
    limits: RuntimeLimits = .defaults
  ) throws -> String {
    guard source.count <= limits.maximumActionCharacters else {
      throw MikroKhorosError.command("action exceeds the model-output limit")
    }
    let action = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !action.isEmpty else {
      throw MikroKhorosError.command("action is empty")
    }
    guard !action.contains(where: { $0.isNewline }) else {
      throw MikroKhorosError.command(
        "current protocol accepts exactly one action line"
      )
    }
    guard
      !action.unicodeScalars.contains(where: {
        CharacterSet.controlCharacters.contains($0)
      })
    else {
      throw MikroKhorosError.command("action contains a control character")
    }
    return action
  }

  public static func actionLines(
    from response: String,
    maximumActions: Int,
    limits: RuntimeLimits = .defaults
  ) throws -> (accepted: [String], ignored: Int) {
    guard maximumActions > 0, maximumActions <= limits.maximumActionsPerResponse else {
      throw MikroKhorosError.command("maximum actions is outside the supported range")
    }
    guard response.count <= limits.maximumResponseCharacters else {
      throw MikroKhorosError.command("model response exceeds the output limit")
    }
    guard
      !response.unicodeScalars.contains(where: {
        CharacterSet.controlCharacters.subtracting(.newlines).contains($0)
      })
    else {
      throw MikroKhorosError.command("model response contains a control character")
    }
    let lines = response.split(
      omittingEmptySubsequences: false,
      whereSeparator: { $0.isNewline }
    ).map(String.init)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    guard !lines.isEmpty else {
      throw MikroKhorosError.command("model response contains no action")
    }
    let accepted = Array(lines.prefix(maximumActions))
    return (accepted, max(0, lines.count - accepted.count))
  }

  /// JSON string syntax is also a valid YAML 1.2 quoted scalar. Encoding every
  /// mutable field this way prevents newlines, colons, and document markers in
  /// object or message text from creating model-facing envelope fields.
  public static func yamlScalar(
    _ source: String,
    limit: Int = RuntimeLimits.defaults.maximumModelFieldCharacters
  ) -> String {
    let value = bounded(escapeInvisibleFormatCharacters(source), limit: limit)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    guard let data = try? encoder.encode(value),
      let encoded = String(data: data, encoding: .utf8)
    else {
      return "\"[unavailable]\""
    }
    return encoded
  }

  public static func bounded(_ source: String, limit: Int) -> String {
    precondition(limit > 0)
    guard source.count > limit else { return source }
    return String(source.prefix(limit)) + "…[truncated]"
  }

  private static func containsProtectedVerbatimWindow(
    _ candidate: String,
    from protectedSource: String,
    minimumWords: Int
  ) -> Bool {
    let candidateWords = comparisonWords(candidate)
    let protectedWords = comparisonWords(protectedSource)
    guard candidateWords.count >= minimumWords,
      protectedWords.count >= minimumWords
    else {
      return false
    }
    var candidateWindows: Set<String> = []
    candidateWindows.reserveCapacity(candidateWords.count - minimumWords + 1)
    for index in 0...(candidateWords.count - minimumWords) {
      let end = index + minimumWords
      candidateWindows.insert(candidateWords[index..<end].joined(separator: " "))
    }

    for index in 0...(protectedWords.count - minimumWords) {
      let end = index + minimumWords
      let window = protectedWords[index..<end].joined(separator: " ")
      if candidateWindows.contains(window) { return true }
    }
    return false
  }

  private static func comparisonWords(_ source: String) -> [Substring] {
    source.precomposedStringWithCompatibilityMapping.lowercased()
      .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
  }

  private static func isProtectedHistoricalContext(_ message: AIConversationMessage) -> Bool {
    message.role == .user && message.content != historyCheckpoint
  }

  private static func isCanonicalEventEnvelope(_ source: String) -> Bool {
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard let first = lines.first, ["events:", "events: []"].contains(first),
      source.contains("\nstate:\n  snapshot: ")
    else {
      return false
    }
    let rootLines = lines.filter { !$0.isEmpty && !($0.first?.isWhitespace ?? false) }
    return rootLines == [first, "state:"]
  }

  private static func hasAllowedActionHead(_ source: String) -> Bool {
    guard let head = source.split(whereSeparator: { $0.isWhitespace }).first else { return false }
    return [
      "move", "container", "pickup", "drop", "backpack", "holding", "object", "inspect",
    ]
    .contains(head.lowercased())
  }

  private static func invalidHistory() -> MikroKhorosError {
    .runtime(
      "model.history_invalid",
      "model-visible history failed structural validation"
    )
  }

  private static func escapeInvisibleFormatCharacters(_ source: String) -> String {
    var pieces: [String] = []
    pieces.reserveCapacity(source.unicodeScalars.count)
    for scalar in source.unicodeScalars {
      if isInvisibleFormatScalar(scalar) {
        let value = String(scalar.value, radix: 16, uppercase: true)
        pieces.append("[format U+\(value)]")
      } else {
        pieces.append(String(scalar))
      }
    }
    return pieces.joined()
  }

  private static func isInvisibleFormatScalar(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x00AD, 0x061C, 0x180E, 0x200B...0x200F, 0x202A...0x202E,
      0x2060...0x206F, 0xFEFF, 0xE0000...0xE007F:
      return true
    default:
      return false
    }
  }
}

/// The host must preserve these roles when calling a model provider. The system
/// text must never be concatenated with the mutable input string.
public struct AgentModelRequest: Equatable, Sendable {
  public let system: String
  public let input: String

  public init(system: String, input: String) {
    self.system = system
    self.input = input
  }
}

/// A possession-eligible notification rendered into the unified model input.
/// All fields are encoded as quoted YAML scalars by `AgentSession`.
public struct AgentBroadcastEvent: Codable, Equatable, Sendable {
  /// Broadcast bodies remain independently bounded even when the configured
  /// model-field ceiling is larger. Wallet projections need room for every
  /// mandatory field of a valid maximum-length signed record; optional notes
  /// use their own tighter preview bound.
  public static let maximumBodyCharacters = 4_096

  public let id: String
  public let timestamp: Date
  public let sourceID: String
  public let sourceType: String
  public let priority: String?
  public let title: String
  public let body: String

  public init(
    id: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
    timestamp: Date = Date(),
    sourceID: String,
    sourceType: String,
    priority: String? = nil,
    title: String,
    body: String
  ) {
    self.id = id
    self.timestamp = timestamp
    self.sourceID = sourceID
    self.sourceType = sourceType
    self.priority = priority
    self.title = title
    self.body = body
  }
}
