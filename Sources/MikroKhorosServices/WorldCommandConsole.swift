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

/// One bounded command-line request made from an exact World route.
public struct WorldCommandConsoleRequest: Equatable, Sendable {
  public let layout: ProductLayout
  public let worldID: String
  public let source: String

  public init(layout: ProductLayout, worldID: String, source: String) {
    self.layout = layout
    self.worldID = worldID
    self.source = source
  }
}

/// A complete replacement suggested by the canonical human-command catalog.
public struct WorldCommandSuggestion: Codable, Equatable, Sendable {
  public let value: String
  public let summary: String

  public init(value: String, summary: String) {
    self.value = value
    self.summary = summary
  }
}

public struct WorldCommandCompletionResult: Codable, Equatable, Sendable {
  public let suggestions: [WorldCommandSuggestion]

  public init(suggestions: [WorldCommandSuggestion]) {
    self.suggestions = suggestions
  }
}

/// A finite, inert transcript produced by one canonical command execution.
public struct WorldCommandExecutionResult: Codable, Equatable, Sendable {
  public let accepted: Bool
  public let displayCommand: String
  public let standardOutput: String
  public let standardError: String
  public let exitStatus: Int
  public let outputTruncated: Bool
  public let refreshWorld: Bool

  public init(
    accepted: Bool,
    displayCommand: String,
    standardOutput: String,
    standardError: String,
    exitStatus: Int,
    outputTruncated: Bool,
    refreshWorld: Bool
  ) {
    self.accepted = accepted
    self.displayCommand = displayCommand
    self.standardOutput = standardOutput
    self.standardError = standardError
    self.exitStatus = exitStatus
    self.outputTruncated = outputTruncated
    self.refreshWorld = refreshWorld
  }
}

public enum WorldCommandConsoleServiceError: Error, Equatable, Sendable {
  case busy
  case invalidContext
  case unavailable
}

/// Dependency-inversion boundary between the World host and the canonical
/// command implementation. The web target never imports or emulates CLI code.
public protocol WorldCommandConsoleServing: Sendable {
  func completions(
    for request: WorldCommandConsoleRequest
  ) async throws -> WorldCommandCompletionResult

  func execute(
    _ request: WorldCommandConsoleRequest
  ) async throws -> WorldCommandExecutionResult
}
