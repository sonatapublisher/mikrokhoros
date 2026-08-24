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

public struct LineEditorSuggestion: Equatable, Sendable {
  public let value: String
  public let summary: String?

  public init(value: String, summary: String? = nil) {
    self.value = value
    self.summary = summary
  }
}

public struct LineEditorState: Equatable, Sendable {
  public private(set) var characters: [Character]
  public private(set) var cursor: Int
  public private(set) var selectedSuggestion: Int
  public private(set) var selectedHistory: Int?
  public private(set) var historyDraft: String?
  public private(set) var paletteRequested: Bool
  private var historyPaletteRequested: Bool?

  public init(text: String = "", cursor: Int? = nil) {
    characters = Array(text)
    self.cursor = min(max(0, cursor ?? characters.count), characters.count)
    selectedSuggestion = 0
    selectedHistory = nil
    historyDraft = nil
    paletteRequested = false
    historyPaletteRequested = nil
  }

  public var text: String { String(characters) }

  public mutating func apply(
    _ event: TerminalEvent,
    suggestions: [LineEditorSuggestion],
    suggestionsVisible: Bool = false,
    history: [String],
    maximumCharacters: Int
  ) -> LineEditorAction {
    switch event {
    case .character(let value):
      guard characters.count < maximumCharacters else { return .none }
      characters.insert(value, at: cursor)
      cursor += 1
      paletteRequested = true
      resetNavigation()
    case .paste(let value):
      let accepted = Array(value).prefix(max(0, maximumCharacters - characters.count))
      characters.insert(contentsOf: accepted, at: cursor)
      cursor += accepted.count
      paletteRequested = true
      resetNavigation()
    case .left:
      cursor = max(0, cursor - 1)
    case .right:
      cursor = min(characters.count, cursor + 1)
    case .home:
      cursor = 0
    case .end:
      cursor = characters.count
    case .backspace:
      if cursor > 0 {
        characters.remove(at: cursor - 1)
        cursor -= 1
        resetNavigation()
      }
    case .delete:
      if cursor < characters.count {
        characters.remove(at: cursor)
        resetNavigation()
      }
    case .tab:
      if suggestionsVisible, let suggestion = suggestions[safe: selectedSuggestion] {
        replace(with: suggestion.value)
      } else if !suggestionsVisible {
        paletteRequested = true
      }
    case .up:
      if selectedHistory != nil || !suggestionsVisible {
        guard !history.isEmpty else { return .none }
        if selectedHistory == nil {
          historyDraft = text
          historyPaletteRequested = paletteRequested
        }
        let next = min((selectedHistory ?? -1) + 1, history.count - 1)
        selectedHistory = next
        replace(with: history[next], resetHistory: false)
      } else if suggestions.count > 1 {
        selectedSuggestion = (selectedSuggestion - 1 + suggestions.count) % suggestions.count
      }
    case .down:
      if let selectedHistory {
        let next = selectedHistory - 1
        if next >= 0 {
          self.selectedHistory = next
          replace(with: history[next], resetHistory: false)
        } else {
          let draft = historyDraft ?? ""
          let restorePalette = historyPaletteRequested ?? paletteRequested
          self.selectedHistory = nil
          historyDraft = nil
          historyPaletteRequested = nil
          replace(with: draft, resetHistory: false)
          paletteRequested = restorePalette
        }
      } else if suggestionsVisible, suggestions.count > 1 {
        selectedSuggestion = (selectedSuggestion + 1) % suggestions.count
      }
    case .enter:
      return .submit
    case .escape:
      return .cancel
    case .interrupt:
      return .interrupt
    case .endOfInput:
      return .endOfInput
    case .resize:
      break
    }
    return .none
  }

  private mutating func replace(with value: String, resetHistory: Bool = true) {
    characters = Array(value)
    cursor = characters.count
    selectedSuggestion = 0
    paletteRequested = true
    if resetHistory { selectedHistory = nil }
  }

  private mutating func resetNavigation() {
    selectedSuggestion = 0
    selectedHistory = nil
    historyDraft = nil
    historyPaletteRequested = nil
  }
}

public enum LineEditorAction: Equatable, Sendable {
  case none
  case submit
  case cancel
  case interrupt
  case endOfInput
}

public enum LineEditorResult: Equatable, Sendable {
  case submitted(String)
  case cancelled(String)
  case interrupted(String)
  case endOfInput
  case suspended(LineEditorState)
}

public enum TerminalCellWidth {
  public static func measure(_ text: String) -> Int {
    text.reduce(0) { $0 + measure($1) }
  }

  public static func measure(_ character: Character) -> Int {
    let scalars = character.unicodeScalars
    guard let first = scalars.first else { return 0 }
    if scalars.allSatisfy({ isZeroWidth($0.value) }) { return 0 }
    if scalars.contains(where: { isWide($0.value) || isEmoji($0.value) }) { return 2 }
    return isZeroWidth(first.value) ? 0 : 1
  }

  public static func prefix(_ text: String, fitting maximumCells: Int) -> String {
    guard maximumCells > 0 else { return "" }
    var result = ""
    var cells = 0
    for character in text {
      let width = measure(character)
      guard cells + width <= maximumCells else { break }
      result.append(character)
      cells += width
    }
    return result
  }

  public static func suffix(_ text: String, fitting maximumCells: Int) -> String {
    guard maximumCells > 0 else { return "" }
    var result: [Character] = []
    var cells = 0
    for character in text.reversed() {
      let width = measure(character)
      guard cells + width <= maximumCells else { break }
      result.append(character)
      cells += width
    }
    return String(result.reversed())
  }

  public static func ellipsized(
    _ text: String,
    fitting maximumCells: Int,
    marker: String = "…"
  ) -> String {
    guard measure(text) > maximumCells else { return text }
    let markerWidth = measure(marker)
    guard maximumCells >= markerWidth else { return prefix(marker, fitting: maximumCells) }
    return prefix(text, fitting: maximumCells - markerWidth) + marker
  }

  private static func isZeroWidth(_ value: UInt32) -> Bool {
    switch value {
    case 0x0300...0x036F, 0x0483...0x0489, 0x0591...0x05BD, 0x05BF,
      0x05C1...0x05C2, 0x05C4...0x05C5, 0x0610...0x061A, 0x064B...0x065F,
      0x0670, 0x06D6...0x06ED, 0x0711, 0x0730...0x074A, 0x07A6...0x07B0,
      0x07EB...0x07F3, 0x0816...0x082D, 0x0859...0x085B, 0x08D3...0x0902,
      0x093A, 0x093C, 0x0941...0x0948, 0x094D, 0x0951...0x0957,
      0x0962...0x0963, 0x1AB0...0x1AFF, 0x1DC0...0x1DFF, 0x200B...0x200F,
      0x202A...0x202E, 0x2060...0x2064, 0x2066...0x206F, 0x20D0...0x20FF,
      0xFE00...0xFE0F, 0xFE20...0xFE2F, 0xE0100...0xE01EF:
      return true
    default:
      return value == 0x200D
    }
  }

  private static func isWide(_ value: UInt32) -> Bool {
    switch value {
    case 0x1100...0x115F, 0x2329...0x232A, 0x2E80...0x303E, 0x3040...0xA4CF,
      0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE10...0xFE19, 0xFE30...0xFE6F,
      0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x1B000...0x1B2FF, 0x20000...0x3FFFD:
      return true
    default:
      return false
    }
  }

  private static func isEmoji(_ value: UInt32) -> Bool {
    switch value {
    case 0x1F000...0x1FAFF, 0x2600...0x26FF, 0x2700...0x27BF:
      return true
    default:
      return false
    }
  }
}

public enum TerminalText {
  public static func escapedUntrusted(_ text: String) -> String {
    var result = ""
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 0x09:
        result.append(" ")
      case 0x20...0x7E, 0xA0...0x10FFFF:
        result.unicodeScalars.append(scalar)
      default:
        continue
      }
    }
    return result
  }
}

public final class LineEditor {
  private let terminal: any TerminalBackend
  private let unicodeEnabled: Bool
  private var renderedRows = 0
  private var plainRenderedCells = 0

  public init(terminal: any TerminalBackend, unicodeEnabled: Bool? = nil) {
    self.terminal = terminal
    self.unicodeEnabled = unicodeEnabled ?? terminal.capabilities.supportsUnicode
  }

  public func prompt(_ label: String) -> String {
    "\(label) \(unicodeEnabled ? "›" : ">") "
  }

  public func readLine(
    prompt: String,
    initialState: LineEditorState = LineEditorState(),
    hidden: Bool = false,
    help: String? = nil,
    maximumCharacters: Int,
    history: [String] = [],
    suggestions: (String) -> [LineEditorSuggestion] = { _ in [] },
    showSuggestionsWhenEmpty: Bool = true,
    onTick: () -> Bool = { false }
  ) throws -> LineEditorResult {
    var state = initialState
    render(
      prompt: prompt,
      state: state,
      hidden: hidden,
      help: help,
      suggestions: suggestions(state.text),
      showSuggestionsWhenEmpty: showSuggestionsWhenEmpty
    )
    while true {
      if onTick() {
        clear()
        return .suspended(state)
      }
      guard let event = try terminal.readEvent(timeoutMilliseconds: 40) else { continue }
      let currentSuggestions = suggestions(state.text)
      let suggestionsVisible =
        showSuggestionsWhenEmpty || !state.text.isEmpty || state.paletteRequested
      let action = state.apply(
        event,
        suggestions: currentSuggestions,
        suggestionsVisible: suggestionsVisible,
        history: history,
        maximumCharacters: maximumCharacters
      )
      switch action {
      case .none:
        render(
          prompt: prompt,
          state: state,
          hidden: hidden,
          help: help,
          suggestions: suggestions(state.text),
          showSuggestionsWhenEmpty: showSuggestionsWhenEmpty
        )
      case .submit:
        clear()
        terminal.writeScrollback(
          "\r\(prompt)\(hidden ? String(repeating: unicodeEnabled ? "•" : "*", count: state.characters.count) : state.text)\n"
        )
        return .submitted(state.text)
      case .cancel:
        clear()
        return .cancelled(state.text)
      case .interrupt:
        clear()
        terminal.writeScrollback("^C\n")
        return .interrupted(state.text)
      case .endOfInput:
        clear()
        return .endOfInput
      }
    }
  }

  public func clear() {
    guard renderedRows > 0 || plainRenderedCells > 0 else { return }
    if terminal.capabilities.supportsCursorAddressing {
      terminal.writeFrame(
        TerminalFrame(rows: [""], cursorRow: 0, cursorColumn: 0, clearRows: renderedRows)
      )
    } else {
      terminal.write("\r" + String(repeating: " ", count: plainRenderedCells) + "\r")
    }
    renderedRows = 0
    plainRenderedCells = 0
  }

  private func render(
    prompt: String,
    state: LineEditorState,
    hidden: Bool,
    help: String?,
    suggestions: [LineEditorSuggestion],
    showSuggestionsWhenEmpty: Bool
  ) {
    let capabilities = terminal.capabilities
    let columns = max(8, capabilities.dimensions?.columns ?? 80)
    let hiddenCharacter = unicodeEnabled ? "•" : "*"
    let visible =
      hidden ? String(repeating: hiddenCharacter, count: state.characters.count) : state.text
    let cursorText =
      hidden
      ? String(repeating: hiddenCharacter, count: state.cursor)
      : String(state.characters.prefix(state.cursor))
    let promptCells = TerminalCellWidth.measure(prompt)
    let availableInputCells = max(1, columns - promptCells)
    let cursorCells = TerminalCellWidth.measure(cursorText)
    let viewport: String
    let viewportCursor: Int
    if cursorCells <= availableInputCells {
      viewport = TerminalCellWidth.prefix(visible, fitting: availableInputCells)
      viewportCursor = cursorCells
    } else {
      let before = TerminalCellWidth.suffix(cursorText, fitting: max(1, availableInputCells - 1))
      let remaining = max(0, availableInputCells - 1 - TerminalCellWidth.measure(before))
      let after = String(state.characters.dropFirst(state.cursor))
      viewport =
        (unicodeEnabled ? "‹" : "<") + before
        + TerminalCellWidth.prefix(after, fitting: remaining)
      viewportCursor = 1 + TerminalCellWidth.measure(before)
    }

    let paletteVisible = showSuggestionsWhenEmpty || !state.text.isEmpty || state.paletteRequested
    let selected = paletteVisible ? suggestions[safe: state.selectedSuggestion] : nil
    var ghost = ""
    if !hidden, let selected, selected.value.hasPrefix(state.text) {
      let suffix = String(selected.value.dropFirst(state.text.count))
      let remaining = max(0, availableInputCells - TerminalCellWidth.measure(viewport))
      ghost = TerminalCellWidth.prefix(suffix, fitting: remaining)
    }

    if !capabilities.supportsCursorAddressing {
      clear()
      let row = TerminalCellWidth.ellipsized(
        prompt + viewport,
        fitting: columns,
        marker: unicodeEnabled ? "…" : "..."
      )
      terminal.write("\r" + row)
      plainRenderedCells = TerminalCellWidth.measure(row)
      renderedRows = 1
      return
    }

    let styledGhost = ghost.isEmpty ? "" : "\u{1B}[2m\(ghost)\u{1B}[0m"
    let ellipsis = unicodeEnabled ? "…" : "..."
    var rows = [
      TerminalCellWidth.ellipsized(prompt + viewport, fitting: columns, marker: ellipsis)
        + styledGhost
    ]
    if let help, !help.isEmpty {
      let escaped = TerminalText.escapedUntrusted(help)
      let fitted = TerminalCellWidth.ellipsized(
        "  \(escaped)", fitting: columns, marker: ellipsis)
      rows.append("\u{1B}[2m\(fitted)\u{1B}[0m")
    }
    let maximumRows = max(0, (capabilities.dimensions?.rows ?? 24) - rows.count - 1)
    let visibleSuggestions = paletteVisible ? suggestions : []
    for (index, suggestion) in visibleSuggestions.prefix(maximumRows).enumerated() {
      let marker = index == state.selectedSuggestion ? (unicodeEnabled ? "›" : ">") : " "
      let value = TerminalText.escapedUntrusted(suggestion.value)
      let summary = suggestion.summary.map(TerminalText.escapedUntrusted)
      let separator = unicodeEnabled ? " — " : " - "
      let plain = "  \(marker) \(value)" + (summary.map { separator + $0 } ?? "")
      let fitted = TerminalCellWidth.ellipsized(plain, fitting: columns, marker: ellipsis)
      if index == state.selectedSuggestion {
        rows.append("\u{1B}[7m\(fitted)\u{1B}[0m")
      } else if summary != nil {
        let valuePart = TerminalCellWidth.ellipsized(
          "  \(marker) \(value)", fitting: columns, marker: ellipsis)
        let remaining = max(0, columns - TerminalCellWidth.measure(valuePart))
        let summaryPart = TerminalCellWidth.ellipsized(
          separator + summary!, fitting: remaining, marker: ellipsis)
        rows.append(valuePart + "\u{1B}[2m\(summaryPart)\u{1B}[0m")
      } else {
        rows.append(fitted)
      }
    }
    terminal.writeFrame(
      TerminalFrame(
        rows: rows,
        cursorRow: 0,
        cursorColumn: min(columns - 1, promptCells + viewportCursor),
        clearRows: max(renderedRows, rows.count)
      )
    )
    renderedRows = rows.count
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
