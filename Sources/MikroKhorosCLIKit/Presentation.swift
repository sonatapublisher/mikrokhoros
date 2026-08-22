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
import MikroKhoros

public struct CommandHint: Equatable, Sendable {
  public let command: String
  public let summary: String

  public init(command: String, summary: String) {
    self.command = command
    self.summary = summary
  }
}

public struct HumanPresentation: Equatable, Sendable {
  public let title: String
  public let payload: JSONValue?

  public init(title: String, payload: JSONValue?) {
    self.title = title
    self.payload = payload
  }
}

public struct CommandResult: Sendable {
  public let command: CommandKind
  public let payload: JSONValue?
  public let exitStatus: Int
  public let humanPresentation: HumanPresentation
  public let trustedHints: [CommandHint]

  public init(
    command: CommandKind,
    payload: JSONValue?,
    exitStatus: Int,
    humanPresentation: HumanPresentation,
    trustedHints: [CommandHint] = []
  ) {
    self.command = command
    self.payload = payload
    self.exitStatus = exitStatus
    self.humanPresentation = humanPresentation
    self.trustedHints = trustedHints
  }
}

public enum CommandResultStream: Sendable {
  case finite(CommandResult)
  case events(AsyncStream<CommandResult>)
}

final class CapturingCommandIO: CommandIO, @unchecked Sendable {
  private let base: any CommandIO
  private let lock = NSLock()
  private var standardOutput = ""
  private var standardError = ""

  init(base: any CommandIO) { self.base = base }

  var isInteractive: Bool { base.isInteractive }

  func writeStandardOutput(_ text: String) {
    lock.withPresentationLock { standardOutput += text }
  }

  func writeStandardError(_ text: String) {
    lock.withPresentationLock { standardError += text }
  }

  func readLine(prompt: String, hidden: Bool) throws -> String? {
    try base.readLine(prompt: prompt, hidden: hidden)
  }

  func readStandardInputToEnd() throws -> Data { try base.readStandardInputToEnd() }

  func captured() -> (output: String, error: String) {
    lock.withPresentationLock { (standardOutput, standardError) }
  }
}

/// Presents each complete event as it arrives instead of buffering an
/// indefinite command until cancellation.
final class StreamingPresentationCommandIO: CommandIO, @unchecked Sendable {
  private let base: any CommandIO
  private let environment: PresentationEnvironment
  private let command: CommandKind
  private let lock = NSLock()
  private var emittedEvent = false

  init(
    base: any CommandIO,
    environment: PresentationEnvironment,
    command: CommandKind
  ) {
    self.base = base
    self.environment = environment
    self.command = command
  }

  var isInteractive: Bool { base.isInteractive }

  func writeStandardOutput(_ text: String) {
    emit(text, status: 0, error: false)
  }

  func writeStandardError(_ text: String) {
    emit(text, status: 1, error: true)
  }

  func readLine(prompt: String, hidden: Bool) throws -> String? {
    try base.readLine(prompt: prompt, hidden: hidden)
  }

  func readStandardInputToEnd() throws -> Data { try base.readStandardInputToEnd() }

  private func emit(_ source: String, status: Int, error: Bool) {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let payload = StructuredTextParser.parse(trimmed) ?? .string(trimmed)
    let result = CommandResult(
      command: command,
      payload: payload,
      exitStatus: status,
      humanPresentation: HumanPresentation(
        title: CommandCatalog.definition(for: command).summary,
        payload: payload
      )
    )
    let rendered: String
    switch environment.outputMode {
    case .auto:
      preconditionFailure("auto output mode is resolved before streaming")
    case .human:
      rendered = HumanResultRenderer.render(
        result,
        color: environment.colorEnabled,
        unicode: environment.unicodeEnabled,
        fallback: source
      )
    case .yaml:
      rendered = YAMLValueRenderer.render(payload)
    case .json:
      rendered = JSONValueRenderer.renderCompact(payload)
    }
    lock.withPresentationLock {
      let separator = environment.outputMode == .yaml && emittedEvent ? "---\n" : ""
      let complete = separator + rendered + (rendered.hasSuffix("\n") ? "" : "\n")
      emittedEvent = true
      if error { base.writeStandardError(complete) } else { base.writeStandardOutput(complete) }
    }
  }
}

public struct PresentationEnvironment: Equatable, Sendable {
  public let outputMode: OutputMode
  public let colorMode: ColorMode
  public let colorEnabled: Bool
  public let unicodeEnabled: Bool

  public static func resolve(
    globals: CommandGlobalOptions,
    configuration: RuntimeConfiguration,
    isInteractive: Bool,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> PresentationEnvironment {
    let requestedOutput = globals.outputMode ?? configuration.presentation.output
    let outputMode: OutputMode =
      requestedOutput == .auto
      ? (isInteractive ? .human : .yaml) : requestedOutput
    let requestedColor = globals.colorMode ?? configuration.presentation.color
    let colorEnabled: Bool
    if outputMode != .human {
      colorEnabled = false
    } else if let explicit = globals.colorMode, explicit != .auto {
      colorEnabled = explicit == .always
    } else if configuration.presentation.color != .auto {
      colorEnabled = configuration.presentation.color == .always
    } else if environment["NO_COLOR"]?.isEmpty == false {
      colorEnabled = false
    } else if environment["FORCE_COLOR"]?.isEmpty == false {
      colorEnabled = true
    } else if environment["TERM"] == "dumb" {
      colorEnabled = false
    } else {
      colorEnabled = isInteractive
    }
    let unicodeEnabled: Bool
    switch configuration.presentation.unicode {
    case .always:
      unicodeEnabled = true
    case .never:
      unicodeEnabled = false
    case .auto:
      unicodeEnabled = environment["LC_ALL"] != "C" && environment["LANG"] != "C"
    }
    return PresentationEnvironment(
      outputMode: outputMode,
      colorMode: requestedColor,
      colorEnabled: colorEnabled,
      unicodeEnabled: unicodeEnabled
    )
  }
}

enum CommandPresentation {
  static func configuration(for globals: CommandGlobalOptions) -> RuntimeConfiguration {
    let url =
      globals.configurationPath.map(URL.init(fileURLWithPath:))
      ?? ConfigurationStore.defaultURL
    return (try? ConfigurationStore.load(from: url)) ?? .defaults
  }

  static func result(
    rawOutput: String,
    rawError: String,
    status: Int,
    kind: CommandKind?
  ) -> CommandResult {
    let source = rawError.isEmpty ? rawOutput : rawError
    let payload = StructuredTextParser.parse(source)
    let command = kind ?? .help
    return CommandResult(
      command: command,
      payload: payload,
      exitStatus: status,
      humanPresentation: HumanPresentation(
        title: CommandCatalog.definition(for: command).summary,
        payload: payload
      ),
      trustedHints: hints(for: command, status: status, payload: payload)
    )
  }

  static func emit(
    result: CommandResult,
    rawOutput: String,
    rawError: String,
    environment: PresentationEnvironment,
    to io: any CommandIO
  ) {
    let isError = !rawError.isEmpty || result.exitStatus != 0
    let rendered: String
    switch environment.outputMode {
    case .auto:
      preconditionFailure("auto output mode is resolved before rendering")
    case .human:
      rendered = HumanResultRenderer.render(
        result,
        color: environment.colorEnabled,
        unicode: environment.unicodeEnabled,
        fallback: isError ? rawError : rawOutput
      )
    case .yaml:
      rendered =
        result.payload.map(YAMLValueRenderer.render)
        ?? YAMLValueRenderer.render(.object(["output": .string(isError ? rawError : rawOutput)]))
    case .json:
      rendered = JSONValueRenderer.render(
        result.payload ?? .object(["output": .string(isError ? rawError : rawOutput)])
      )
    }
    let complete = rendered.hasSuffix("\n") ? rendered : rendered + "\n"
    if isError {
      io.writeStandardError(complete)
    } else {
      io.writeStandardOutput(complete)
    }
  }

  private static func hints(
    for kind: CommandKind,
    status: Int,
    payload _: JSONValue?
  ) -> [CommandHint] {
    guard status == 0 else { return [] }
    switch kind {
    case .initialize:
      return [
        CommandHint(command: "khoros world show", summary: "inspect the world"),
        CommandHint(command: "khoros shell agent", summary: "drive the default agent"),
        CommandHint(
          command: "khoros inventory package available", summary: "browse built-in objects"),
      ]
    case .inventoryInstall:
      return [
        CommandHint(command: "khoros inventory list", summary: "inspect created Inventory sources")
      ]
    case .inventoryDeploy:
      return [
        CommandHint(command: "khoros world object list", summary: "inspect the concrete copy")
      ]
    default:
      return []
    }
  }
}

enum JSONValueRenderer {
  static func render(_ value: JSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value) else { return "null" }
    return String(decoding: data, as: UTF8.self)
  }

  static func renderCompact(_ value: JSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value) else { return "null" }
    return String(decoding: data, as: UTF8.self)
  }
}

enum YAMLValueRenderer {
  static func render(_ value: JSONValue) -> String { render(value, indentation: 0) }

  private static func render(_ value: JSONValue, indentation: Int) -> String {
    let prefix = String(repeating: " ", count: indentation)
    switch value {
    case .string(let text) where text.contains("\n"):
      let body = text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { prefix + "  " + $0 }
        .joined(separator: "\n")
      return "\(prefix)|-\n\(body)"
    case .object(let object):
      if object.isEmpty { return "{}" }
      return object.keys.sorted().map { key in
        let child = object[key]!
        if isCollection(child) {
          return "\(prefix)\(scalar(key)):\n\(render(child, indentation: indentation + 2))"
        }
        if case .string(let text) = child, text.contains("\n") {
          let body = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String(repeating: " ", count: indentation + 2) + $0 }
            .joined(separator: "\n")
          return "\(prefix)\(scalar(key)): |-\n\(body)"
        }
        return "\(prefix)\(scalar(key)): \(renderScalar(child))"
      }.joined(separator: "\n")
    case .array(let array):
      if array.isEmpty { return "\(prefix)[]" }
      return array.map { child in
        if case .object(let object) = child, !object.isEmpty {
          let rendered = render(child, indentation: indentation + 2)
          let lines = rendered.split(separator: "\n", omittingEmptySubsequences: false)
          guard let first = lines.first else { return "\(prefix)- {}" }
          return "\(prefix)- \(first.dropFirst(indentation + 2))"
            + lines.dropFirst().map { "\n\($0)" }.joined()
        }
        if isCollection(child) {
          return "\(prefix)-\n\(render(child, indentation: indentation + 2))"
        }
        if case .string(let text) = child, text.contains("\n") {
          let body = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String(repeating: " ", count: indentation + 2) + $0 }
            .joined(separator: "\n")
          return "\(prefix)- |-\n\(body)"
        }
        return "\(prefix)- \(renderScalar(child))"
      }.joined(separator: "\n")
    default:
      return prefix + renderScalar(value)
    }
  }

  private static func isCollection(_ value: JSONValue) -> Bool {
    switch value {
    case .object(let value): !value.isEmpty
    case .array(let value): !value.isEmpty
    default: false
    }
  }

  private static func renderScalar(_ value: JSONValue) -> String {
    switch value {
    case .string(let value): scalar(value)
    case .number(let value): value.rounded() == value ? String(Int(value)) : String(value)
    case .bool(let value): value ? "true" : "false"
    case .null: "null"
    case .array(let value): value.isEmpty ? "[]" : JSONValueRenderer.render(.array(value))
    case .object(let value): value.isEmpty ? "{}" : JSONValueRenderer.render(.object(value))
    }
  }

  private static func scalar(_ value: String) -> String {
    guard !value.isEmpty else { return "\"\"" }
    let safe = value.unicodeScalars.allSatisfy {
      ($0.value >= 0x20 || $0.value == 0x09)
        && !":{}[],&*#?|-<>=!%@`\"'".unicodeScalars.contains($0)
    }
    let reserved = ["null", "true", "false", "yes", "no", "~"]
    if safe, !value.contains("\n"), !value.hasPrefix(" "), !value.hasSuffix(" "),
      !reserved.contains(value.lowercased()), Double(value) == nil
    {
      return value
    }
    let data = try? JSONEncoder().encode(value)
    return data.map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
  }
}

enum HumanResultRenderer {
  static func render(
    _ result: CommandResult,
    color: Bool,
    unicode: Bool = true,
    fallback: String
  ) -> String {
    guard let payload = result.payload else {
      return TerminalText.escapedUntrusted(fallback)
    }
    let style = HumanStyle(color: color)
    var lines = [
      result.exitStatus == 0
        ? style.heading(result.humanPresentation.title)
        : "\(style.error("error"))  \(style.dim(result.humanPresentation.title))"
    ]
    lines.append(contentsOf: render(payload, indentation: 0, style: style, unicode: unicode))
    if !result.trustedHints.isEmpty {
      lines.append("")
      lines.append(style.heading("Next"))
      for hint in result.trustedHints {
        lines.append("  \(style.command(hint.command))  \(style.dim(hint.summary))")
      }
    }
    return lines.joined(separator: "\n")
  }

  private static func render(
    _ value: JSONValue,
    indentation: Int,
    style: HumanStyle,
    unicode: Bool
  ) -> [String] {
    let prefix = String(repeating: " ", count: indentation)
    switch value {
    case .string(let text) where text.contains("\n"):
      return text.split(separator: "\n", omittingEmptySubsequences: false).map {
        prefix + TerminalText.escapedUntrusted(String($0))
      }
    case .object(let object):
      if object.isEmpty { return [prefix + "{}"] }
      var lines: [String] = []
      for key in object.keys.sorted() {
        let child = object[key]!
        let label = key.replacingOccurrences(of: "_", with: " ")
        switch child {
        case .object, .array:
          lines.append(prefix + style.label(label))
          lines.append(
            contentsOf: render(
              child, indentation: indentation + 2, style: style, unicode: unicode))
        case .string(let text) where text.contains("\n"):
          lines.append(prefix + style.label(label))
          lines += text.split(separator: "\n", omittingEmptySubsequences: false).map {
            String(repeating: " ", count: indentation + 2)
              + TerminalText.escapedUntrusted(String($0))
          }
        default:
          lines.append(
            prefix + style.label(label) + "  "
              + scalar(child, style: style, unicode: unicode))
        }
      }
      return lines
    case .array(let array):
      if array.isEmpty { return [prefix + "none"] }
      if array.allSatisfy(tableFriendly) {
        return renderTable(array, indentation: indentation, style: style, unicode: unicode)
      }
      return array.flatMap { child -> [String] in
        if case .object = child {
          return [prefix + (unicode ? "•" : "-")]
            + render(child, indentation: indentation + 2, style: style, unicode: unicode)
        }
        return [prefix + (unicode ? "• " : "- ") + scalar(child, style: style, unicode: unicode)]
      }
    default:
      return [prefix + scalar(value, style: style, unicode: unicode)]
    }
  }

  private static func renderTable(
    _ array: [JSONValue],
    indentation: Int,
    style: HumanStyle,
    unicode: Bool
  ) -> [String] {
    let objects = array.compactMap { value -> [String: JSONValue]? in
      if case .object(let object) = value { return object }
      return nil
    }
    let preferred = ["name", "id", "object_id", "type", "status", "state", "location"]
    var keys: [String] = []
    for key in preferred where objects.contains(where: { $0[key] != nil }) { keys.append(key) }
    for key in objects.flatMap({ $0.keys }).sorted() where !keys.contains(key) && keys.count < 5 {
      if objects.allSatisfy({ object in
        guard let value = object[key] else { return true }
        if case .array = value { return false }
        if case .object = value { return false }
        return true
      }) {
        keys.append(key)
      }
    }
    guard !keys.isEmpty else {
      return objects.enumerated().flatMap { index, object in
        [String(repeating: " ", count: indentation) + "#\(index + 1)"]
          + render(
            .object(object), indentation: indentation + 2, style: style, unicode: unicode)
      }
    }
    let rows = objects.map { object in
      keys.map { key in
        shortScalar(
          object[key] ?? .null,
          peers: objects.compactMap { peer in
            guard case .string(let value) = peer[key] else { return nil }
            return value
          },
          identityColumn: key == "id" || key.hasSuffix("_id"),
          unicode: unicode
        )
      }
    }
    let widths = keys.indices.map { index in
      min(32, max(keys[index].count, rows.map { TerminalCellWidth.measure($0[index]) }.max() ?? 0))
    }
    let prefix = String(repeating: " ", count: indentation)
    let header = zip(keys, widths).map {
      pad($0.0.replacingOccurrences(of: "_", with: " "), to: $0.1, unicode: unicode)
    }
    .joined(separator: "  ")
    var output = [prefix + style.label(header)]
    for row in rows {
      output.append(
        prefix
          + zip(row, widths).map { pad($0.0, to: $0.1, unicode: unicode) }
          .joined(separator: "  "))
    }
    return output
  }

  private static func pad(_ value: String, to width: Int, unicode: Bool) -> String {
    let fitted = TerminalCellWidth.ellipsized(
      value, fitting: width, marker: unicode ? "…" : "...")
    return fitted + String(repeating: " ", count: max(0, width - TerminalCellWidth.measure(fitted)))
  }

  private static func shortScalar(
    _ value: JSONValue,
    peers: [String] = [],
    identityColumn: Bool = false,
    unicode: Bool
  ) -> String {
    switch value {
    case .string(let value):
      let safe = TerminalText.escapedUntrusted(value)
      if identityColumn, InventoryIdentity.isValid(safe) {
        return HumanSelectorResolver.uniquePrefix(
          for: safe,
          among: peers,
          id: { $0 },
          minimumLength: 8
        )
      }
      return safe
    case .number(let value): return value.rounded() == value ? String(Int(value)) : String(value)
    case .bool(let value): return value ? "yes" : "no"
    case .null: return unicode ? "—" : "-"
    case .array(let value): return "\(value.count) items"
    case .object(let value): return "\(value.count) fields"
    }
  }

  private static func scalar(_ value: JSONValue, style: HumanStyle, unicode: Bool) -> String {
    let text = shortScalar(value, unicode: unicode)
    if case .bool(true) = value { return style.success(text) }
    return text
  }

  private static func tableFriendly(_ value: JSONValue) -> Bool {
    guard case .object(let object) = value else { return false }
    return object.values.allSatisfy { child in
      switch child {
      case .array, .object:
        return false
      case .string(let value):
        return !value.contains("\n") && TerminalCellWidth.measure(value) <= 80
      default:
        return true
      }
    }
  }
}

private struct HumanStyle {
  let color: Bool
  func heading(_ value: String) -> String { decorate(value, "1") }
  func label(_ value: String) -> String { decorate(value, "36") }
  func command(_ value: String) -> String { decorate(value, "36") }
  func success(_ value: String) -> String { decorate(value, "32") }
  func error(_ value: String) -> String { decorate(value, "31") }
  func dim(_ value: String) -> String { decorate(value, "2") }

  private func decorate(_ value: String, _ code: String) -> String {
    let safe = TerminalText.escapedUntrusted(value)
    return color ? "\u{1B}[\(code)m\(safe)\u{1B}[0m" : safe
  }
}

enum StructuredTextParser {
  static func parse(_ source: String) -> JSONValue? {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let data = trimmed.data(using: .utf8),
      let value = try? JSONDecoder().decode(JSONValue.self, from: data)
    {
      return value
    }
    return YAMLSubsetParser(source: trimmed).parse()
  }
}

private struct YAMLSubsetParser {
  private struct Line {
    let indentation: Int
    let text: String
  }

  private let lines: [Line]

  init(source: String) {
    lines = source.split(separator: "\n", omittingEmptySubsequences: false).compactMap { raw in
      let text = String(raw)
      guard !text.trimmingCharacters(in: .whitespaces).isEmpty, text != "---" else { return nil }
      let indentation = text.prefix(while: { $0 == " " }).count
      return Line(indentation: indentation, text: String(text.dropFirst(indentation)))
    }
  }

  func parse() -> JSONValue? {
    guard !lines.isEmpty else { return nil }
    var index = 0
    let value = parseNode(index: &index, indentation: lines[0].indentation)
    return index == lines.count ? value : .string(lines.map(\.text).joined(separator: "\n"))
  }

  private func parseNode(index: inout Int, indentation: Int) -> JSONValue {
    guard index < lines.count else { return .null }
    return lines[index].text.hasPrefix("- ") || lines[index].text == "-"
      ? parseArray(index: &index, indentation: indentation)
      : parseObject(index: &index, indentation: indentation)
  }

  private func parseObject(index: inout Int, indentation: Int) -> JSONValue {
    var object: [String: JSONValue] = [:]
    while index < lines.count, lines[index].indentation == indentation,
      !lines[index].text.hasPrefix("- ")
    {
      let line = lines[index].text
      guard let separator = mappingSeparator(in: line) else {
        index += 1
        return .string(line)
      }
      let key = parseKey(String(line[..<separator]))
      let remainder = String(line[line.index(after: separator)...])
        .trimmingCharacters(in: .whitespaces)
      index += 1
      if remainder == "|" || remainder == "|-" || remainder == ">" || remainder == ">-" {
        var body: [String] = []
        while index < lines.count, lines[index].indentation > indentation {
          body.append(lines[index].text)
          index += 1
        }
        object[key] = .string(body.joined(separator: "\n"))
      } else if !remainder.isEmpty {
        object[key] = scalar(remainder)
      } else if index < lines.count, lines[index].indentation > indentation {
        object[key] = parseNode(index: &index, indentation: lines[index].indentation)
      } else {
        object[key] = .null
      }
    }
    return .object(object)
  }

  private func parseArray(index: inout Int, indentation: Int) -> JSONValue {
    var array: [JSONValue] = []
    while index < lines.count, lines[index].indentation == indentation,
      lines[index].text.hasPrefix("-")
    {
      let remainder = String(lines[index].text.dropFirst())
        .trimmingCharacters(in: .whitespaces)
      index += 1
      if remainder.isEmpty {
        if index < lines.count, lines[index].indentation > indentation {
          array.append(parseNode(index: &index, indentation: lines[index].indentation))
        } else {
          array.append(.null)
        }
      } else if let separator = mappingSeparator(in: remainder) {
        let key = parseKey(String(remainder[..<separator]))
        let tail = String(remainder[remainder.index(after: separator)...])
          .trimmingCharacters(in: .whitespaces)
        var object: [String: JSONValue] = [key: tail.isEmpty ? .null : scalar(tail)]
        if index < lines.count, lines[index].indentation > indentation {
          let childIndent = lines[index].indentation
          if case .object(let more) = parseObject(index: &index, indentation: childIndent) {
            object.merge(more) { _, new in new }
          }
        }
        array.append(.object(object))
      } else {
        array.append(scalar(remainder))
      }
    }
    return .array(array)
  }

  private func mappingSeparator(in text: String) -> String.Index? {
    var quoted = false
    var escaped = false
    for index in text.indices {
      let character = text[index]
      if escaped {
        escaped = false
        continue
      }
      if character == "\\" {
        escaped = true
        continue
      }
      if character == "\"" {
        quoted.toggle()
        continue
      }
      if character == ":", !quoted { return index }
    }
    return nil
  }

  private func parseKey(_ source: String) -> String {
    let value = source.trimmingCharacters(in: .whitespaces)
    if let data = value.data(using: .utf8),
      let decoded = try? JSONDecoder().decode(String.self, from: data)
    {
      return decoded
    }
    return value
  }

  private func scalar(_ source: String) -> JSONValue {
    if source == "null" || source == "~" { return .null }
    if source == "true" { return .bool(true) }
    if source == "false" { return .bool(false) }
    if source == "[]" { return .array([]) }
    if source == "{}" { return .object([:]) }
    if let number = Double(source) { return .number(number) }
    if let data = source.data(using: .utf8),
      let decoded = try? JSONDecoder().decode(JSONValue.self, from: data)
    {
      return decoded
    }
    return .string(source)
  }
}

extension NSLock {
  fileprivate func withPresentationLock<Result>(_ body: () -> Result) -> Result {
    lock()
    defer { unlock() }
    return body()
  }
}
