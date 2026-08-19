import Foundation

public struct RuntimeIssue: Error, Equatable, Sendable {
  public let code: String
  public let message: String
  public let details: [String: String]
  public let suggestions: [String]

  public init(
    code: String,
    message: String,
    details: [String: String] = [:],
    suggestions: [String] = []
  ) {
    self.code = code
    self.message = message
    self.details = details
    self.suggestions = suggestions
  }
}

public enum MikroKhorosError: Error, Equatable, CustomStringConvertible {
  case command(String)
  case placement(String)
  case objectLocked(String)
  case function(String)
  case bundle(String)
  case profile(String)
  case configuration(String)
  case persistence(String)
  case runtime(RuntimeIssue)

  public var description: String {
    switch self {
    case .command(let message),
      .placement(let message),
      .objectLocked(let message),
      .function(let message),
      .bundle(let message),
      .profile(let message),
      .configuration(let message),
      .persistence(let message):
      return message
    case .runtime(let issue):
      return issue.message
    }
  }

  public var issue: RuntimeIssue {
    switch self {
    case .runtime(let issue):
      return issue
    case .command(let message):
      return RuntimeIssue(
        code: "command.invalid",
        message: message,
        suggestions: ["check the documented command syntax and try again"]
      )
    case .placement(let message):
      return RuntimeIssue(
        code: "placement.invalid",
        message: message,
        suggestions: ["choose another coordinate and try again"]
      )
    case .objectLocked(let message):
      return RuntimeIssue(
        code: "pickup.locked",
        message: message,
        suggestions: ["remove or satisfy the pickup lock, then run `pickup` again"]
      )
    case .function(let message):
      return RuntimeIssue(
        code: "object.function_failed",
        message: message,
        suggestions: ["run `inspect held` and retry with its documented function syntax"]
      )
    case .bundle(let message):
      return RuntimeIssue(code: "object_package.invalid", message: message)
    case .profile(let message):
      return RuntimeIssue(
        code: "ai.profile_invalid",
        message: message,
        suggestions: ["inspect the AI profile and its credential reference"]
      )
    case .configuration(let message):
      return RuntimeIssue(
        code: "config.invalid",
        message: message,
        suggestions: [
          "run `khoros config validate` after correcting the file",
          "run `khoros config reset` to restore every built-in default",
        ]
      )
    case .persistence(let message):
      return RuntimeIssue(code: "workspace.persistence_failed", message: message)
    }
  }

  public static func runtime(
    _ code: String,
    _ message: String,
    details: [String: String] = [:],
    suggestions: [String] = []
  ) -> MikroKhorosError {
    .runtime(
      RuntimeIssue(
        code: code,
        message: message,
        details: details,
        suggestions: suggestions
      )
    )
  }
}
