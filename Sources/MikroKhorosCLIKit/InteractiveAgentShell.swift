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

enum InteractiveAgentShell {
  static func run(
    agent: Agent,
    runtime: WorldRuntime,
    worldURL: URL,
    color: Bool
  ) throws {
    let terminal = SystemTerminalBackend()
    terminal.setEscapeTimeout(milliseconds: runtime.configuration.console.escapeTimeoutMilliseconds)
    try terminal.begin()
    defer { terminal.end() }
    let unicode: Bool
    switch runtime.configuration.presentation.unicode {
    case .always: unicode = true
    case .never: unicode = false
    case .auto: unicode = terminal.capabilities.supportsUnicode
    }
    let editor = LineEditor(terminal: terminal, unicodeEnabled: unicode)
    var history: [String] = []
    terminal.writeScrollback(
      header(agent: agent, runtime: runtime, color: color, unicode: unicode))

    while true {
      let result = try editor.readLine(
        prompt: editor.prompt(agent.name),
        maximumCharacters: runtime.configuration.runtime.maximumActionCharacters,
        history: history.reversed(),
        suggestions: { source in completions(source: source, agent: agent) },
        showSuggestionsWhenEmpty: false
      )
      switch result {
      case .endOfInput:
        return
      case .cancelled:
        continue
      case .interrupted(let draft):
        if draft.isEmpty { return }
      case .suspended:
        preconditionFailure("the agent shell has no asynchronous renderer")
      case .submitted(let raw):
        let action = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !action.isEmpty else { continue }
        if action == ":quit" || action == ":exit" { return }
        if action == ":help" {
          terminal.writeScrollback(help(color: color))
          continue
        }
        history.removeAll(where: { $0 == action })
        history.insert(action, at: 0)
        let turn = try runtime.run(action, for: agent)
        try WorldStore.save(
          runtime.document,
          to: worldURL,
          maximumBytes: runtime.configuration.runtime.maximumWorldBytes
        )
        terminal.writeScrollback(render(turn: turn, color: color))
        terminal.writeScrollback(
          stateHeader(agent: agent, runtime: runtime, color: color, unicode: unicode))
      }
    }
  }

  private static func header(
    agent: Agent,
    runtime: WorldRuntime,
    color: Bool,
    unicode: Bool
  ) -> String {
    let style = ShellStyle(color: color)
    let separator = unicode ? " · " : " - "
    return "\(style.heading("MikroKhoros agent shell"))  "
      + "\(style.dim(":help for actions\(separator)Ctrl-C to exit when empty"))\n"
      + stateHeader(agent: agent, runtime: runtime, color: color, unicode: unicode)
  }

  private static func stateHeader(
    agent: Agent,
    runtime: WorldRuntime,
    color: Bool,
    unicode _: Bool
  ) -> String {
    let style = ShellStyle(color: color)
    let standing = agent.space.object(at: agent.coordinate)
    let holding1 =
      agent.holdings[.one].map { "\($0.typeName)#\(String($0.hash.prefix(8)))" } ?? "empty"
    let holding2 =
      agent.holdings[.two].map { "\($0.typeName)#\(String($0.hash.prefix(8)))" } ?? "empty"
    let holding3 =
      agent.holdings[.three].map { "\($0.typeName)#\(String($0.hash.prefix(8)))" } ?? "empty"
    let holding4 =
      agent.holdings[.four].map { "\($0.typeName)#\(String($0.hash.prefix(8)))" } ?? "empty"
    let surface = standing.map { "\($0.name)#\(String($0.hash.prefix(8)))" } ?? "empty"
    return "\(style.dim("path")) \(runtime.harness.agentPath(agent))  "
      + "\(style.dim("holdings")) #1=\(holding1) #2=\(holding2) #3=\(holding3) #4=\(holding4)  "
      + "\(style.dim("primary")) \(agent.primaryHoldingNumber.rawValue)  "
      + "\(style.dim("standing")) \(surface)\n"
  }

  private static func help(color: Bool) -> String {
    let style = ShellStyle(color: color)
    let rows = AgentActionCatalog.all.map {
      "  \(style.accent($0.syntax))\n      \(style.dim($0.summary))"
    }.joined(separator: "\n")
    return "Actions:\n\(rows)\n  \(style.accent(":quit"))\n      close the human shell\n"
  }

  private static func completions(source: String, agent: Agent) -> [LineEditorSuggestion] {
    var suggestions = AgentActionCatalog.all.compactMap { definition -> LineEditorSuggestion? in
      let head = definition.kind.rawValue
      guard
        source.isEmpty || head.hasPrefix(source.lowercased())
          || definition.syntax.lowercased().hasPrefix(source.lowercased())
      else { return nil }
      return LineEditorSuggestion(value: head, summary: definition.summary)
    }
    let target = agent.primaryHeldObject ?? agent.space.object(at: agent.coordinate)
    if source.lowercased().hasPrefix("object") || source.isEmpty, let target {
      suggestions += target.inspect().functions.filter(\.audience.acceptsAgent).map {
        LineEditorSuggestion(
          value: "object (\($0.name))",
          summary: "\(target.name) · \($0.summary)"
        )
      }
    }
    suggestions.append(.init(value: ":help", summary: "show action syntax"))
    suggestions.append(.init(value: ":quit", summary: "close the shell"))
    if source.isEmpty || "holding".hasPrefix(source.lowercased())
      || "holding select".hasPrefix(source.lowercased())
    {
      suggestions.append(.init(value: "holding select", summary: "choose primary holding slot 1-4"))
    }
    for index in 1...4 {
      let value = "holding select \(index)"
      let summary =
        index == agent.primaryHoldingNumber.rawValue
        ? "already selected primary holding"
        : "set primary holding to \(index)"
      suggestions.append(.init(value: value, summary: summary))
    }
    return suggestions
  }

  private static func render(turn: AgentTurn, color: Bool) -> String {
    let style = ShellStyle(color: color)
    var lines: [String] = []
    for event in turn.events {
      switch event {
      case .result(let result):
        if result.status == .success {
          lines.append("\(style.success("success"))  \(result.command ?? "action")")
          if let output = result.output {
            lines += output.split(separator: "\n", omittingEmptySubsequences: false).map {
              "  \(TerminalText.escapedUntrusted(String($0)))"
            }
          }
        } else if let issue = result.error {
          lines.append("\(style.error("error"))  \(issue.code)  \(issue.message)")
          for suggestion in issue.suggestions {
            lines.append("  \(style.warning("try"))  \(TerminalText.escapedUntrusted(suggestion))")
          }
        }
      case .broadcast(let event):
        let priority = event.priority.map { " \($0)" } ?? ""
        lines.append(
          "\(style.message("message\(priority)"))  \(TerminalText.escapedUntrusted(event.title))")
        lines.append("  \(TerminalText.escapedUntrusted(event.body))")
      case .warning(let warning):
        lines.append("\(style.warning("warning"))  \(warning.code)  \(warning.message)")
      }
    }
    return lines.joined(separator: "\n") + "\n"
  }
}

private struct ShellStyle {
  let color: Bool

  func heading(_ value: String) -> String { wrap("1;36", value) }
  func accent(_ value: String) -> String { wrap("36", value) }
  func success(_ value: String) -> String { wrap("32", value) }
  func warning(_ value: String) -> String { wrap("33", value) }
  func error(_ value: String) -> String { wrap("31", value) }
  func message(_ value: String) -> String { wrap("35", value) }
  func dim(_ value: String) -> String { wrap("2", value) }

  private func wrap(_ code: String, _ value: String) -> String {
    color ? "\u{1B}[\(code)m\(value)\u{1B}[0m" : value
  }
}
