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

public protocol CommandIO: AnyObject, Sendable {
  var isInteractive: Bool { get }
  func writeStandardOutput(_ text: String)
  func writeStandardError(_ text: String)
  func readLine(prompt: String, hidden: Bool) throws -> String?
  func readStandardInputToEnd() throws -> Data
}

public enum CommandRuntimeIO {
  @TaskLocal public static var current: (any CommandIO)?

  public static var active: any CommandIO { current ?? StandardCommandIO.shared }

  public static func readLine(prompt: String = "", hidden: Bool = false) throws -> String? {
    try active.readLine(prompt: prompt, hidden: hidden)
  }

  public static func writeError(_ text: String) {
    active.writeStandardError(text)
  }
}

public final class StandardCommandIO: CommandIO, @unchecked Sendable {
  public static let shared = StandardCommandIO()

  public var isInteractive: Bool {
    #if os(Windows)
      return _isatty(_fileno(stdin)) != 0 && _isatty(_fileno(stdout)) != 0
    #else
      return isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
    #endif
  }

  public func writeStandardOutput(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
  }

  public func writeStandardError(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
  }

  public func readLine(prompt: String, hidden: Bool) throws -> String? {
    if !prompt.isEmpty { writeStandardOutput(prompt) }
    guard hidden else { return Swift.readLine(strippingNewline: true) }
    guard isInteractive else { return Swift.readLine(strippingNewline: true) }
    #if os(Windows)
      let handle = GetStdHandle(STD_INPUT_HANDLE)
      var mode: DWORD = 0
      guard handle != INVALID_HANDLE_VALUE, GetConsoleMode(handle, &mode) else {
        throw CommandIOError.terminalMode
      }
      guard SetConsoleMode(handle, mode & ~DWORD(ENABLE_ECHO_INPUT)) else {
        throw CommandIOError.terminalMode
      }
      defer {
        _ = SetConsoleMode(handle, mode)
        writeStandardOutput("\n")
      }
      return Swift.readLine(strippingNewline: true)
    #else
      var current = termios()
      guard tcgetattr(STDIN_FILENO, &current) == 0 else {
        throw CommandIOError.terminalMode
      }
      let original = current
      current.c_lflag &= ~tcflag_t(ECHO)
      guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &current) == 0 else {
        throw CommandIOError.terminalMode
      }
      defer {
        var restored = original
        _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &restored)
        writeStandardOutput("\n")
      }
      return Swift.readLine(strippingNewline: true)
    #endif
  }

  public func readStandardInputToEnd() throws -> Data {
    FileHandle.standardInput.readDataToEndOfFile()
  }
}

public enum CommandIOError: Error {
  case terminalMode
}

func print(_ value: String, terminator: String = "\n") {
  CommandRuntimeIO.active.writeStandardOutput(value + terminator)
}
