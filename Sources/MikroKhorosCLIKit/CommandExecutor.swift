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
import MikroKhoros
import MikroKhorosServices

public struct CommandExecutionTranscript: Equatable, Sendable {
  public let exitStatus: Int
  public let standardOutput: String
  public let standardError: String
  public let outputTruncated: Bool

  public init(
    exitStatus: Int,
    standardOutput: String,
    standardError: String,
    outputTruncated: Bool
  ) {
    self.exitStatus = exitStatus
    self.standardOutput = standardOutput
    self.standardError = standardError
    self.outputTruncated = outputTruncated
  }
}

public enum CommandExecutionRoute: Equatable, Sendable {
  case help
  case web
  case adapters
  case configuration
  case runtime
}

public enum CommandExecutor {
  public static func route(for kind: CommandKind) -> CommandExecutionRoute {
    switch kind {
    case .help: .help
    case .web: .web
    case .adapters: .adapters
    case .configShow, .configPath, .configKeys, .configGet, .configSet, .configReset,
      .configValidate:
      .configuration
    case .initialize, .status, .doctor, .agentCreate, .agentList, .agentShow,
      .agentConfigure, .agentAdd, .agentRemove, .agentProfileSet, .agentProfileClear,
      .agentRetry, .agentShell, .libraryFetch, .libraryList, .inventoryInstall,
      .inventoryPackageAvailable, .inventoryPackageList, .inventoryPackageShow,
      .inventoryPackageRemove, .inventoryCreate, .inventoryFolderCreate,
      .inventoryFolderList, .inventoryFolderShow, .inventoryFolderRename,
      .inventoryFolderMove, .inventoryFolderDelete, .inventoryMove, .inventoryFork,
      .inventoryList, .inventoryShow, .inventoryInterface,
      .inventoryConfigure, .inventoryDelete, .inventorySecretSet, .inventorySecretClear,
      .inventoryCapabilityList, .inventoryCapabilityGrant, .inventoryCapabilityRevoke,
      .inventoryActionList, .inventoryActionRun, .inventoryViewList, .inventoryViewShow,
      .inventoryDeploy, .inventoryCopiesList, .inventoryCopiesShow,
      .inventoryCopiesDelete, .inventoryListenEnable, .inventoryListenDisable,
      .inventoryListenList, .inventoryReportsList, .inventoryReportsShow,
      .inventoryReportsFollow, .inventoryRestockCreate, .inventoryRestockList,
      .inventoryRestockShow, .inventoryRestockSet, .inventoryRestockRun,
      .inventoryRestockDelete, .worldList, .worldUse, .worldCreate, .worldRename,
      .worldDelete, .worldTemplateList, .worldTemplateShow,
      .worldTemplateStatus, .worldTemplateApply, .worldShow, .worldInspect, .worldExport,
      .worldObjectList, .worldObjectShow, .worldObjectInterface,
      .worldObjectActionList, .worldObjectActionRun, .worldObjectViewList,
      .worldObjectViewShow, .worldObjectMove:
      .runtime
    }
  }

  @discardableResult
  public static func execute(
    arguments: [String],
    io: any CommandIO = StandardCommandIO.shared,
    webHost: (any KhorosWebServing)? = nil
  ) async -> Int {
    await execute(
      arguments: arguments,
      io: io,
      webHost: webHost,
      maximumCaptureBytes: nil
    ).status
  }

  /// Executes one finite command against an explicit embedded product layout
  /// and returns the same presentation that the ordinary CLI would emit.
  /// Both the inner handler capture and the returned channels are bounded.
  public static func executeTranscript(
    arguments: [String],
    layout: ProductLayout,
    maximumOutputBytes: Int,
    standardInput: Data = Data(),
    expectedProductStateFingerprint: String? = nil
  ) async -> CommandExecutionTranscript {
    guard maximumOutputBytes > 0 else {
      return CommandExecutionTranscript(
        exitStatus: 1,
        standardOutput: "",
        standardError: "command output limit is invalid\n",
        outputTruncated: false
      )
    }
    let transcript = TranscriptCommandIO(
      maximumBytes: maximumOutputBytes,
      standardInput: standardInput
    )
    let outcome = await WebProductStateContext.$expectedFingerprint.withValue(
      expectedProductStateFingerprint
    ) {
      await MikroKhorosPathContext.$canonicalRootOverride.withValue(
        layout.canonicalRoot
      ) {
        await execute(
          arguments: arguments,
          io: transcript,
          webHost: nil,
          maximumCaptureBytes: maximumOutputBytes
        )
      }
    }
    let captured = transcript.captured()
    return CommandExecutionTranscript(
      exitStatus: outcome.status,
      standardOutput: captured.output,
      standardError: captured.error,
      outputTruncated: outcome.outputTruncated || captured.outputTruncated
        || captured.errorTruncated
    )
  }

  private static func execute(
    arguments: [String],
    io: any CommandIO,
    webHost: (any KhorosWebServing)?,
    maximumCaptureBytes: Int?
  ) async -> CommandExecutionOutcome {
    let globals = (try? CommandParser.splitGlobals(arguments).0) ?? .init()
    let remaining = (try? CommandParser.splitGlobals(arguments).1) ?? arguments
    if remaining == ["console"] || (arguments.isEmpty && io.isInteractive) {
      return CommandExecutionOutcome(
        status: await executeResolved(arguments: arguments, io: io, webHost: webHost)
      )
    }
    if io === StandardCommandIO.shared,
      let parsed = try? CommandParser.parse(arguments),
      parsed.kind == .agentShell,
      parsed.fieldValues["action"] == nil
    {
      return CommandExecutionOutcome(
        status: await executeResolved(arguments: arguments, io: io, webHost: webHost)
      )
    }
    if (try? CommandParser.parse(arguments).kind) == .web {
      return CommandExecutionOutcome(
        status: await executeResolved(arguments: arguments, io: io, webHost: webHost)
      )
    }
    let configuration = CommandPresentation.configuration(for: globals)
    let presentation = PresentationEnvironment.resolve(
      globals: globals,
      configuration: configuration,
      isInteractive: io.isInteractive
    )
    if let parsed = try? CommandParser.parse(arguments), parsed.kind == .inventoryReportsFollow {
      let stream = StreamingPresentationCommandIO(
        base: io,
        environment: presentation,
        command: parsed.kind
      )
      return CommandExecutionOutcome(
        status: await executeResolved(arguments: arguments, io: stream, webHost: webHost)
      )
    }
    let capture = CapturingCommandIO(base: io, maximumBytes: maximumCaptureBytes)
    let status = await executeResolved(arguments: arguments, io: capture, webHost: webHost)
    let captured = capture.captured()
    let kind = try? CommandParser.parse(arguments).kind
    let result = CommandPresentation.result(
      rawOutput: captured.output,
      rawError: captured.error,
      status: status,
      kind: kind
    )
    CommandPresentation.emit(
      result: result,
      rawOutput: captured.output,
      rawError: captured.error,
      environment: presentation,
      to: io
    )
    return CommandExecutionOutcome(
      status: status,
      outputTruncated: captured.outputTruncated || captured.errorTruncated
    )
  }
}

private struct CommandExecutionOutcome: Sendable {
  let status: Int
  let outputTruncated: Bool

  init(status: Int, outputTruncated: Bool = false) {
    self.status = status
    self.outputTruncated = outputTruncated
  }
}

private final class TranscriptCommandIO: CommandIO, @unchecked Sendable {
  private let capture: CapturingCommandIO
  private let inputLock = NSLock()
  private var standardInput: Data?

  init(maximumBytes: Int, standardInput: Data) {
    capture = CapturingCommandIO(
      base: NoninteractiveCommandIO.shared,
      maximumBytes: maximumBytes
    )
    self.standardInput = standardInput
  }

  var isInteractive: Bool { false }

  func writeStandardOutput(_ text: String) { capture.writeStandardOutput(text) }
  func writeStandardError(_ text: String) { capture.writeStandardError(text) }
  func readLine(prompt _: String, hidden _: Bool) throws -> String? { nil }
  func readStandardInputToEnd() throws -> Data {
    inputLock.lock()
    defer { inputLock.unlock() }
    let result = standardInput ?? Data()
    standardInput = nil
    return result
  }

  func captured() -> (
    output: String,
    error: String,
    outputTruncated: Bool,
    errorTruncated: Bool
  ) {
    capture.captured()
  }
}

private final class NoninteractiveCommandIO: CommandIO, @unchecked Sendable {
  static let shared = NoninteractiveCommandIO()

  var isInteractive: Bool { false }
  func writeStandardOutput(_: String) {}
  func writeStandardError(_: String) {}
  func readLine(prompt _: String, hidden _: Bool) throws -> String? { nil }
  func readStandardInputToEnd() throws -> Data { Data() }
}
