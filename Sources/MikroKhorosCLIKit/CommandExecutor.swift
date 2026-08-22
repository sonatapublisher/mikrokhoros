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

public enum CommandExecutionRoute: Equatable, Sendable {
  case help
  case adapters
  case configuration
  case runtime
}

public enum CommandExecutor {
  public static func route(for kind: CommandKind) -> CommandExecutionRoute {
    switch kind {
    case .help: .help
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
    io: any CommandIO = StandardCommandIO.shared
  ) async -> Int {
    let globals = (try? CommandParser.splitGlobals(arguments).0) ?? .init()
    let remaining = (try? CommandParser.splitGlobals(arguments).1) ?? arguments
    if remaining == ["console"] || (arguments.isEmpty && io.isInteractive) {
      return await executeResolved(arguments: arguments, io: io)
    }
    if io === StandardCommandIO.shared,
      let parsed = try? CommandParser.parse(arguments),
      parsed.kind == .agentShell,
      parsed.fieldValues["action"] == nil
    {
      return await executeResolved(arguments: arguments, io: io)
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
      return await executeResolved(arguments: arguments, io: stream)
    }
    let capture = CapturingCommandIO(base: io)
    let status = await executeResolved(arguments: arguments, io: capture)
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
    return status
  }
}
