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

#if os(Windows)
  import WinSDK
#elseif canImport(Darwin)
  import Darwin
#else
  import Glibc
#endif

public struct TerminalDimensions: Equatable, Sendable {
  public let columns: Int
  public let rows: Int

  public init(columns: Int, rows: Int) {
    self.columns = max(1, columns)
    self.rows = max(1, rows)
  }
}

public struct TerminalCapabilities: Equatable, Sendable {
  public let interactiveInput: Bool
  public let interactiveOutput: Bool
  public let dimensions: TerminalDimensions?
  public let supportsCursorAddressing: Bool
  public let supportsColor: Bool
  public let supportsUnicode: Bool

  public init(
    interactiveInput: Bool,
    interactiveOutput: Bool,
    dimensions: TerminalDimensions? = nil,
    supportsCursorAddressing: Bool = true,
    supportsColor: Bool = true,
    supportsUnicode: Bool = true
  ) {
    self.interactiveInput = interactiveInput
    self.interactiveOutput = interactiveOutput
    self.dimensions = dimensions
    self.supportsCursorAddressing = supportsCursorAddressing
    self.supportsColor = supportsColor
    self.supportsUnicode = supportsUnicode
  }

  public var isInteractive: Bool { interactiveInput && interactiveOutput }
}

public struct TerminalFrame: Equatable, Sendable {
  public let rows: [String]
  public let cursorRow: Int
  public let cursorColumn: Int
  public let clearRows: Int

  public init(rows: [String], cursorRow: Int, cursorColumn: Int, clearRows: Int? = nil) {
    self.rows = rows.isEmpty ? [""] : rows
    self.cursorRow = max(0, min(cursorRow, self.rows.count - 1))
    self.cursorColumn = max(0, cursorColumn)
    self.clearRows = max(self.rows.count, clearRows ?? self.rows.count)
  }
}

public enum TerminalEvent: Equatable, Sendable {
  case character(Character)
  case paste(String)
  case left
  case right
  case up
  case down
  case home
  case end
  case backspace
  case delete
  case tab
  case enter
  case escape
  case interrupt
  case endOfInput
  case resize
}

public protocol TerminalBackend: AnyObject, Sendable {
  var isInteractive: Bool { get }
  var capabilities: TerminalCapabilities { get }
  func begin() throws
  func end()
  func readEvent(timeoutMilliseconds: Int) throws -> TerminalEvent?
  func write(_ text: String)
  func writeFrame(_ frame: TerminalFrame)
  func writeScrollback(_ text: String)
}

extension TerminalBackend {
  public var capabilities: TerminalCapabilities {
    TerminalCapabilities(
      interactiveInput: isInteractive,
      interactiveOutput: isInteractive,
      dimensions: nil,
      supportsCursorAddressing: isInteractive,
      supportsColor: isInteractive,
      supportsUnicode: true
    )
  }

  public func writeFrame(_ frame: TerminalFrame) {
    write(frame.rows.joined(separator: "\r\n"))
  }

  public func writeScrollback(_ text: String) { write(text) }
}

public final class SystemTerminalBackend: TerminalBackend, @unchecked Sendable {
  private let output = FileHandle.standardOutput
  private let lock = NSLock()
  private var active = false
  private var lastDimensions: TerminalDimensions?
  private var pendingBytes: [UInt8] = []
  private var escapeDeadlineMilliseconds = 30

  #if os(Windows)
    private let inputHandle = GetStdHandle(STD_INPUT_HANDLE)
    private let outputHandle = GetStdHandle(STD_OUTPUT_HANDLE)
    private var originalInputMode: DWORD = 0
    private var originalOutputMode: DWORD = 0
  #else
    private var originalMode: termios?
    private var terminationSources: [DispatchSourceSignal] = []
  #endif

  public init() {}

  deinit { end() }

  public var isInteractive: Bool { capabilities.isInteractive }

  public var capabilities: TerminalCapabilities {
    let environment = ProcessInfo.processInfo.environment
    let dumb = environment["TERM"] == "dumb"
    #if os(Windows)
      let inputInteractive = inputHandle != INVALID_HANDLE_VALUE
      let outputInteractive = outputHandle != INVALID_HANDLE_VALUE
    #else
      let inputInteractive = isatty(STDIN_FILENO) != 0
      let outputInteractive = isatty(STDOUT_FILENO) != 0
    #endif
    return TerminalCapabilities(
      interactiveInput: inputInteractive,
      interactiveOutput: outputInteractive,
      dimensions: dimensions(),
      supportsCursorAddressing: inputInteractive && outputInteractive && !dumb,
      supportsColor: inputInteractive && outputInteractive && !dumb,
      supportsUnicode: environment["LC_ALL"] != "C" && environment["LANG"] != "C"
    )
  }

  public func setEscapeTimeout(milliseconds: Int) {
    escapeDeadlineMilliseconds = max(1, milliseconds)
  }

  public func begin() throws {
    guard !active else { return }
    guard capabilities.isInteractive else { throw TerminalError.terminalRequired }
    #if os(Windows)
      guard inputHandle != INVALID_HANDLE_VALUE,
        outputHandle != INVALID_HANDLE_VALUE,
        GetConsoleMode(inputHandle, &originalInputMode),
        GetConsoleMode(outputHandle, &originalOutputMode)
      else {
        throw TerminalError.modeUnavailable
      }
      let inputMode =
        originalInputMode
        & ~DWORD(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT)
        | DWORD(ENABLE_WINDOW_INPUT)
      let outputMode = originalOutputMode | DWORD(ENABLE_VIRTUAL_TERMINAL_PROCESSING)
      guard SetConsoleMode(inputHandle, inputMode), SetConsoleMode(outputHandle, outputMode) else {
        throw TerminalError.modeUnavailable
      }
    #else
      var mode = termios()
      guard tcgetattr(STDIN_FILENO, &mode) == 0 else { throw TerminalError.modeUnavailable }
      originalMode = mode
      mode.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
      mode.c_iflag &= ~tcflag_t(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
      // Own output translation while raw mode is active. Every terminal write
      // below uses explicit CRLF, so cursor motion does not depend on the
      // caller's OPOST/ONLCR settings.
      mode.c_oflag &= ~tcflag_t(OPOST)
      mode.c_cflag |= tcflag_t(CS8)
      withUnsafeMutablePointer(to: &mode.c_cc) { pointer in
        pointer.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { controls in
          controls[Int(VMIN)] = 0
          controls[Int(VTIME)] = 0
        }
      }
      guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &mode) == 0 else {
        originalMode = nil
        throw TerminalError.modeUnavailable
      }
    #endif
    active = true
    lastDimensions = dimensions()
    #if !os(Windows)
      installTerminationHandlers()
    #endif
    if capabilities.supportsCursorAddressing { writeRaw("\u{1B}[?2004h") }
  }

  public func end() {
    lock.lock()
    defer { lock.unlock() }
    guard active else { return }
    if capabilities.supportsCursorAddressing {
      writeRaw("\u{1B}[?2004l\u{1B}[?25h\u{1B}[0m")
    }
    #if os(Windows)
      _ = SetConsoleMode(inputHandle, originalInputMode)
      _ = SetConsoleMode(outputHandle, originalOutputMode)
    #else
      // Restore immediately. TCSAFLUSH can block while a pseudoterminal still
      // has unread input, which leaves an otherwise closed console process
      // alive after Ctrl-C. The editor has already consumed its input and owns
      // no buffered canonical line at this boundary.
      if var originalMode {
        _ = tcflush(STDIN_FILENO, TCIFLUSH)
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &originalMode)
        _ = tcflush(STDIN_FILENO, TCIFLUSH)
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &originalMode)
      }
      originalMode = nil
      for source in terminationSources { source.cancel() }
      terminationSources.removeAll()
    #endif
    active = false
  }

  public func readEvent(timeoutMilliseconds: Int) throws -> TerminalEvent? {
    if let changed = resizeEvent() { return changed }
    #if os(Windows)
      let wait = WaitForSingleObject(inputHandle, DWORD(max(0, timeoutMilliseconds)))
      guard wait == WAIT_OBJECT_0 else { return resizeEvent() }
      var record = INPUT_RECORD()
      var count: DWORD = 0
      guard ReadConsoleInputW(inputHandle, &record, 1, &count), count == 1 else {
        throw TerminalError.readFailed
      }
      if record.EventType == WORD(WINDOW_BUFFER_SIZE_EVENT) {
        lastDimensions = dimensions()
        return .resize
      }
      guard record.EventType == WORD(KEY_EVENT) else { return nil }
      let key = record.Event.KeyEvent
      guard key.bKeyDown.boolValue else { return nil }
      switch Int32(key.wVirtualKeyCode) {
      case VK_LEFT: return .left
      case VK_RIGHT: return .right
      case VK_UP: return .up
      case VK_DOWN: return .down
      case VK_HOME: return .home
      case VK_END: return .end
      case VK_DELETE: return .delete
      case VK_BACK: return .backspace
      case VK_TAB: return .tab
      case VK_RETURN: return .enter
      case VK_ESCAPE: return .escape
      default: break
      }
      let scalar = UInt32(key.uChar.UnicodeChar)
      if scalar == 3 { return .interrupt }
      if scalar == 4 { return .endOfInput }
      guard scalar > 0, let value = UnicodeScalar(scalar) else { return nil }
      return .character(Character(String(value)))
    #else
      guard let first = try readByte(timeoutMilliseconds: timeoutMilliseconds) else {
        return resizeEvent()
      }
      switch first {
      case 3: return .interrupt
      case 4: return .endOfInput
      case 9: return .tab
      case 10, 13: return .enter
      case 8, 127: return .backspace
      case 27: return try escapeEvent()
      default:
        guard first >= 32 else { return nil }
        return try characterEvent(firstByte: first)
      }
    #endif
  }

  public func write(_ text: String) { writeScrollback(text) }

  public func writeFrame(_ frame: TerminalFrame) {
    if !capabilities.supportsCursorAddressing {
      writeScrollback((frame.rows.first ?? "") + "\n")
      return
    }
    writeRaw(Self.encodedFrame(frame))
  }

  static func encodedFrame(_ frame: TerminalFrame) -> String {
    // Erasing a terminal line does not move the cursor. Every frame must first
    // establish column zero or the first row inherits the input cursor's offset.
    var buffer = "\u{1B}[?25l\r"
    for index in 0..<frame.clearRows {
      if index > 0 { buffer += "\r\n" }
      buffer += "\u{1B}[2K" + (index < frame.rows.count ? frame.rows[index] : "")
    }
    if frame.clearRows > 1 { buffer += "\u{1B}[\(frame.clearRows - 1)A" }
    buffer += "\r"
    if frame.cursorColumn > 0 { buffer += "\u{1B}[\(frame.cursorColumn)C" }
    if frame.cursorRow > 0 { buffer += "\u{1B}[\(frame.cursorRow)B" }
    buffer += "\u{1B}[?25h"
    return buffer
  }

  public func writeScrollback(_ text: String) {
    writeRaw(Self.normalizedTerminalText(text))
  }

  public static func normalizedTerminalText(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.utf8.count + 8)
    var previousWasCarriageReturn = false
    for character in text {
      if character == "\n" {
        if !previousWasCarriageReturn { result.append("\r") }
        result.append("\n")
        previousWasCarriageReturn = false
      } else {
        result.append(character)
        previousWasCarriageReturn = character == "\r"
      }
    }
    return result
  }

  private func writeRaw(_ text: String) { output.write(Data(text.utf8)) }

  private func resizeEvent() -> TerminalEvent? {
    let current = dimensions()
    guard current != lastDimensions else { return nil }
    lastDimensions = current
    return .resize
  }

  private func dimensions() -> TerminalDimensions? {
    #if os(Windows)
      var info = CONSOLE_SCREEN_BUFFER_INFO()
      guard outputHandle != INVALID_HANDLE_VALUE, GetConsoleScreenBufferInfo(outputHandle, &info)
      else { return nil }
      return TerminalDimensions(
        columns: Int(info.srWindow.Right - info.srWindow.Left + 1),
        rows: Int(info.srWindow.Bottom - info.srWindow.Top + 1)
      )
    #else
      var size = winsize()
      guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0,
        size.ws_col > 0, size.ws_row > 0
      else { return nil }
      return TerminalDimensions(columns: Int(size.ws_col), rows: Int(size.ws_row))
    #endif
  }

  #if !os(Windows)
    private func installTerminationHandlers() {
      for signalNumber in [SIGHUP, SIGQUIT, SIGTERM] {
        _ = signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(
          signal: signalNumber,
          queue: DispatchQueue.global(qos: .userInitiated)
        )
        source.setEventHandler { [weak self] in
          self?.end()
          _ = signal(signalNumber, SIG_DFL)
          _ = raise(signalNumber)
        }
        source.resume()
        terminationSources.append(source)
      }
    }

    private func readByte(timeoutMilliseconds: Int) throws -> UInt8? {
      if !pendingBytes.isEmpty { return pendingBytes.removeFirst() }
      var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
      let result = poll(&descriptor, 1, Int32(max(0, timeoutMilliseconds)))
      guard result >= 0 else { throw TerminalError.readFailed }
      guard result > 0, descriptor.revents & Int16(POLLIN) != 0 else { return nil }
      var byte: UInt8 = 0
      let count = read(STDIN_FILENO, &byte, 1)
      guard count >= 0 else { throw TerminalError.readFailed }
      return count == 1 ? byte : nil
    }

    private func characterEvent(firstByte: UInt8) throws -> TerminalEvent {
      let width: Int
      switch firstByte {
      case 0..<0x80: width = 1
      case 0xC0..<0xE0: width = 2
      case 0xE0..<0xF0: width = 3
      default: width = 4
      }
      var bytes = [firstByte]
      while bytes.count < width {
        guard let next = try readByte(timeoutMilliseconds: escapeDeadlineMilliseconds) else {
          throw TerminalError.invalidEncoding
        }
        bytes.append(next)
      }
      guard let text = String(bytes: bytes, encoding: .utf8), let character = text.first else {
        throw TerminalError.invalidEncoding
      }
      return .character(character)
    }

    private func escapeEvent() throws -> TerminalEvent {
      guard let second = try readByte(timeoutMilliseconds: escapeDeadlineMilliseconds) else {
        return .escape
      }
      guard second == 91 || second == 79 else {
        pendingBytes.insert(second, at: 0)
        return .escape
      }
      guard let third = try readByte(timeoutMilliseconds: escapeDeadlineMilliseconds) else {
        return .escape
      }
      switch third {
      case 65: return .up
      case 66: return .down
      case 67: return .right
      case 68: return .left
      case 70: return .end
      case 72: return .home
      case 49, 55:
        _ = try consumeCSIEnd()
        return .home
      case 52, 56:
        _ = try consumeCSIEnd()
        return .end
      case 51:
        _ = try consumeCSIEnd()
        return .delete
      case 50:
        let suffix = try consumeCSIEnd()
        if suffix == "00" { return .paste(try readBracketedPaste()) }
        return .escape
      default: return .escape
      }
    }

    private func consumeCSIEnd() throws -> String {
      var bytes: [UInt8] = []
      while let byte = try readByte(timeoutMilliseconds: escapeDeadlineMilliseconds) {
        if byte == 126 { break }
        guard bytes.count < 8 else { break }
        bytes.append(byte)
      }
      return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    private func readBracketedPaste() throws -> String {
      let terminator: [UInt8] = [27, 91, 50, 48, 49, 126]
      var bytes: [UInt8] = []
      while bytes.count < 1_048_576 {
        guard let byte = try readByte(timeoutMilliseconds: 1_000) else { break }
        bytes.append(byte)
        if bytes.count >= terminator.count,
          Array(bytes.suffix(terminator.count)) == terminator
        {
          bytes.removeLast(terminator.count)
          break
        }
      }
      return String(decoding: bytes, as: UTF8.self)
    }
  #endif
}

public enum TerminalError: Error {
  case terminalRequired
  case modeUnavailable
  case readFailed
  case invalidEncoding
}

public final class FakeTerminalBackend: TerminalBackend, @unchecked Sendable {
  public var isInteractive = true
  public var dimensions = TerminalDimensions(columns: 80, rows: 24)
  public var supportsCursorAddressing = true
  public var supportsColor = true
  private let lock = NSLock()
  private var events: [TerminalEvent]
  public private(set) var output = ""
  public private(set) var frames: [TerminalFrame] = []
  public private(set) var beginCount = 0
  public private(set) var endCount = 0

  public init(events: [TerminalEvent] = []) { self.events = events }

  public var capabilities: TerminalCapabilities {
    TerminalCapabilities(
      interactiveInput: isInteractive,
      interactiveOutput: isInteractive,
      dimensions: dimensions,
      supportsCursorAddressing: supportsCursorAddressing,
      supportsColor: supportsColor,
      supportsUnicode: true
    )
  }

  public func begin() { lock.withTerminalLock { beginCount += 1 } }
  public func end() { lock.withTerminalLock { endCount += 1 } }

  public func readEvent(timeoutMilliseconds _: Int) -> TerminalEvent? {
    lock.withTerminalLock { events.isEmpty ? nil : events.removeFirst() }
  }

  public func write(_ text: String) { lock.withTerminalLock { output += text } }
  public func writeScrollback(_ text: String) { write(text) }
  public func writeFrame(_ frame: TerminalFrame) {
    lock.withTerminalLock {
      frames.append(frame)
      output += frame.rows.joined(separator: "\n")
    }
  }

  public func append(_ newEvents: [TerminalEvent]) {
    lock.withTerminalLock { events.append(contentsOf: newEvents) }
  }
}

extension NSLock {
  fileprivate func withTerminalLock<Result>(_ body: () -> Result) -> Result {
    lock()
    defer { unlock() }
    return body()
  }
}
