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
import MikroKhorosServices
import MikroKhorosWeb
import XCTest

@testable import MikroKhoros
@testable import MikroKhorosCLIKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class WebCapabilityGatewayTests: XCTestCase {
  func testRegistryExactlyCoversTheLiveCatalogAcrossTheFiveWebViews() throws {
    let descriptors = CLIWebCapabilityRegistry.descriptors()

    XCTAssertEqual(CommandKind.allCases.count, 89)
    XCTAssertEqual(descriptors.count, CommandKind.allCases.count)
    XCTAssertEqual(Set(descriptors.map(\.id)), Set(CommandKind.allCases.map(\.rawValue)))
    XCTAssertEqual(Set(descriptors.map(\.commandKind)), Set(CommandKind.allCases.map(\.rawValue)))
    XCTAssertEqual(descriptors.map(\.id).count, Set(descriptors.map(\.id)).count)
    let unavailableInBrowser: Set<String> = [
      CommandKind.inventoryShow.rawValue,
      CommandKind.inventoryCopiesShow.rawValue,
      CommandKind.worldObjectShow.rawValue,
    ]
    XCTAssertEqual(
      Set(descriptors.filter { !$0.enabled }.map(\.id)),
      unavailableInBrowser
    )
    XCTAssertTrue(
      descriptors
        .filter { !unavailableInBrowser.contains($0.id) }
        .allSatisfy(\.enabled)
    )
    for view in WebView.primary {
      XCTAssertTrue(descriptors.contains(where: { $0.placement == view }), view.rawValue)
    }
    XCTAssertEqual(
      descriptors.first(where: { $0.commandKind == CommandKind.web.rawValue })?.interaction,
      .hostStatus
    )
    XCTAssertTrue(
      descriptors.first(where: { $0.commandKind == CommandKind.web.rawValue })?.fields.isEmpty
        == true
    )
    XCTAssertEqual(
      descriptors.first(where: { $0.commandKind == CommandKind.inventorySecretSet.rawValue })?
        .interaction,
      .secret
    )
    let secretFields =
      descriptors.first(where: {
        $0.commandKind == CommandKind.inventorySecretSet.rawValue
      })?.fields ?? []
    XCTAssertEqual(secretFields.last?.id, "credential-value")
    XCTAssertTrue(secretFields.last?.isPrivate == true)
    XCTAssertFalse(secretFields.contains(where: { ["stdin", "from-env"].contains($0.id) }))
    XCTAssertFalse(
      descriptors
        .filter { $0.interaction == .confirmation }
        .flatMap(\.fields)
        .contains(where: { $0.id == "yes" })
    )
    XCTAssertEqual(
      descriptors.first(where: { $0.commandKind == CommandKind.agentShell.rawValue })?.interaction,
      .agentController
    )
    XCTAssertEqual(
      descriptors.first(where: { $0.commandKind == CommandKind.agentShell.rawValue })?
        .fields.first(where: { $0.id == "action" })?.cardinality,
      .requiredRepeated
    )
    XCTAssertEqual(
      descriptors.first(where: { $0.commandKind == CommandKind.inventoryReportsFollow.rawValue })?
        .interaction,
      .reportStream
    )
    XCTAssertEqual(
      descriptors.first(where: { $0.commandKind == CommandKind.worldShow.rawValue })?
        .fields.first(where: { $0.id == "world" })?.cardinality,
      .required
    )
    XCTAssertEqual(
      descriptors.first(where: { $0.commandKind == CommandKind.inventoryViewShow.rawValue })?
        .scope,
      .explicitWorld
    )
    XCTAssertEqual(
      descriptors.first(where: { $0.commandKind == CommandKind.web.rawValue })?.summary,
      "Show the running MikroKhoros Web host."
    )
    let installSource =
      descriptors
      .first(where: { $0.commandKind == CommandKind.inventoryInstall.rawValue })?
      .fields.first(where: { $0.id == "path-or-url" })
    XCTAssertEqual(installSource?.label, "Trusted package source")
    XCTAssertEqual(
      installSource?.help,
      "Use an available built-in package such as builtin:paper, or an HTTPS URL."
    )
    for id in [
      CommandKind.inventoryCopiesShow.rawValue,
      CommandKind.worldObjectShow.rawValue,
    ] {
      let descriptor = try XCTUnwrap(descriptors.first(where: { $0.id == id }))
      XCTAssertTrue(descriptor.summary.contains("raw administrative object snapshot"))
      XCTAssertTrue(descriptor.help.contains("Use the local CLI"))
    }
    let inventoryShow = try XCTUnwrap(
      descriptors.first(where: { $0.id == CommandKind.inventoryShow.rawValue })
    )
    XCTAssertFalse(inventoryShow.enabled)
    XCTAssertEqual(inventoryShow.canonicalPath, ["inventory", "show"])
    XCTAssertTrue(inventoryShow.summary.contains("administrative source snapshot"))
    XCTAssertTrue(inventoryShow.help.contains("Use the local CLI"))
  }

  func testBrowserOutputUsesOneAggregateUTF8Budget() {
    let maximum = CLIWebCapabilityGateway.maximumOutputBytes
    let bounded = CLIWebCapabilityGateway.boundedBrowserOutput(
      stdout: String(repeating: "é", count: maximum),
      stderr: String(repeating: "ø", count: maximum),
      maximumBytes: maximum
    )

    XCTAssertTrue(bounded.truncated)
    XCTAssertLessThanOrEqual(
      Data(bounded.stdout.utf8).count + Data(bounded.stderr.utf8).count,
      maximum
    )
    XCTAssertNotNil(bounded.stdout.data(using: .utf8))
    XCTAssertNotNil(bounded.stderr.data(using: .utf8))
    XCTAssertFalse(bounded.stdout.isEmpty)
    XCTAssertFalse(bounded.stderr.isEmpty)
  }

  func testHostStatusIsFiniteAndDoesNotReenterTheWebHost() async throws {
    let root = temporaryRoot("host-status")
    let gateway = CLIWebCapabilityGateway()
    let context = capabilityContext(root: root, session: String(repeating: "a", count: 64))

    let result = try await gateway.execute(
      WebCapabilityRequest(
        capabilityID: CommandKind.web.rawValue,
        sessionID: context.sessionID,
        interaction: .hostStatus
      ),
      in: context
    )

    XCTAssertTrue(result.accepted)
    XCTAssertEqual(result.exitStatus, 0)
    XCTAssertEqual(result.displayCommand, "khoros web")
    XCTAssertTrue(result.standardOutput.contains("lifecycle: running"))
    XCTAssertTrue(result.standardOutput.contains("port: 43127"))
    XCTAssertFalse(result.standardOutput.contains(context.sessionID))
    XCTAssertFalse(result.standardOutput.contains(root.path))

    await assertThrowsErrorAsync(
      try await gateway.execute(
        WebCapabilityRequest(
          capabilityID: CommandKind.web.rawValue,
          fields: ["port": ["47568"]],
          sessionID: context.sessionID,
          interaction: .hostStatus
        ),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .invalidField("unknown"))
    }
  }

  func testExecutionRedactsCanonicalProductAndConfigurationPaths() async throws {
    let root = temporaryRoot("path-redaction")
    let outsideConfiguration = temporaryRoot("outside-configuration")
      .appendingPathComponent("selected.json", isDirectory: false)
    try FileManager.default.createDirectory(
      at: outsideConfiguration.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try ConfigurationStore.save(RuntimeConfiguration.defaults, to: outsideConfiguration)
    let layout = ProductLayout(canonicalRoot: root, configurationURL: outsideConfiguration)
    let gateway = CLIWebCapabilityGateway()
    let session = String(repeating: "9", count: 64)
    let context = WebCapabilityContext(
      layout: layout,
      sessionID: session,
      hostState: WebHostState(lifecycle: .running, address: "127.0.0.1", port: 43127)
    )

    let status = try await gateway.execute(
      WebCapabilityRequest(
        capabilityID: CommandKind.status.rawValue,
        sessionID: session,
        interaction: .projection
      ),
      in: context
    )
    let configurationPath = try await gateway.execute(
      WebCapabilityRequest(
        capabilityID: CommandKind.configPath.rawValue,
        sessionID: session,
        interaction: .projection
      ),
      in: context
    )

    for result in [status, configurationPath] {
      XCTAssertFalse(result.standardOutput.contains(root.path))
      XCTAssertFalse(result.standardError.contains(root.path))
      XCTAssertFalse(result.standardOutput.contains(outsideConfiguration.path))
      XCTAssertFalse(result.standardError.contains(outsideConfiguration.path))
    }
    XCTAssertTrue(configurationPath.standardOutput.contains("[configuration file]"))
  }

  func testCompletionsUseTheExactProductLayoutAndExcludeFilesystemValues() async throws {
    let root = temporaryRoot("completions")
    let layout = ProductLayout(canonicalRoot: root)
    let world = try WorldCreationService(layout: layout).createBareWorld(name: "Completion World")
    let gateway = CLIWebCapabilityGateway()
    let context = capabilityContext(root: root, session: String(repeating: "b", count: 64))

    let worlds = try await gateway.completions(
      for: WebCapabilityCompletionRequest(
        capabilityID: CommandKind.worldDelete.rawValue,
        fieldID: "world",
        source: "Completion"
      ),
      in: context
    )
    XCTAssertEqual(
      worlds, [WebCapabilityCompletionValue(value: world.id, label: world.name)])

    let files = try await gateway.completions(
      for: WebCapabilityCompletionRequest(
        capabilityID: CommandKind.inventoryInstall.rawValue,
        fieldID: "path-or-url",
        source: "/"
      ),
      in: context
    )
    XCTAssertTrue(files.isEmpty)
  }

  func testPreparedMutationIsSessionBoundSingleUseAndActuallyCommits() async throws {
    let root = temporaryRoot("confirmation")
    let layout = ProductLayout(canonicalRoot: root)
    let world = try WorldCreationService(layout: layout).createBareWorld(name: "Disposable")
    let gateway = CLIWebCapabilityGateway()
    let sessionA = String(repeating: "c", count: 64)
    let sessionB = String(repeating: "d", count: 64)
    let contextA = capabilityContext(root: root, session: sessionA)
    let contextB = capabilityContext(root: root, session: sessionB)
    let request = WebCapabilityRequest(
      capabilityID: CommandKind.worldDelete.rawValue,
      fields: ["world": [world.id]],
      sessionID: sessionA,
      interaction: .confirmation
    )

    let plan = try await gateway.prepare(request, in: contextA)
    await assertThrowsErrorAsync(
      try await gateway.commit(
        WebCapabilityCommitRequest(planID: plan.planID, sessionID: sessionB),
        in: contextB
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .invalidSession)
    }

    let result = try await gateway.commit(
      WebCapabilityCommitRequest(planID: plan.planID, sessionID: sessionA),
      in: contextA
    )
    XCTAssertTrue(result.accepted, result.standardError)
    XCTAssertFalse(
      try WorldCatalogStore(
        url: layout.catalogURL,
        maximumBytes: RuntimeConfiguration.defaults.runtime.maximumWorldBytes
      ).document.worlds.contains(where: { $0.id == world.id })
    )

    await assertThrowsErrorAsync(
      try await gateway.commit(
        WebCapabilityCommitRequest(planID: plan.planID, sessionID: sessionA),
        in: contextA
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .replayedPlan)
    }
  }

  func testPreparedMutationRejectsChangedPersistentProductState() async throws {
    let root = temporaryRoot("confirmation-state-binding")
    let layout = ProductLayout(canonicalRoot: root)
    let target = try WorldCreationService(layout: layout).createBareWorld(name: "Target")
    let gateway = CLIWebCapabilityGateway()
    let session = String(repeating: "6", count: 64)
    let context = capabilityContext(root: root, session: session)
    let plan = try await gateway.prepare(
      WebCapabilityRequest(
        capabilityID: CommandKind.worldDelete.rawValue,
        fields: ["world": [target.id]],
        sessionID: session,
        interaction: .confirmation
      ),
      in: context
    )

    _ = try WorldCreationService(layout: layout).createBareWorld(name: "Concurrent change")

    await assertThrowsErrorAsync(
      try await gateway.commit(
        WebCapabilityCommitRequest(planID: plan.planID, sessionID: session),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .tamperedPlan)
    }
    XCTAssertTrue(
      try WorldCatalogStore(
        url: layout.catalogURL,
        maximumBytes: RuntimeConfiguration.defaults.runtime.maximumWorldBytes
      ).document.worlds.contains(where: { $0.id == target.id })
    )
  }

  func testBusyCommitLeavesPreparedPlanRetryable() async throws {
    let root = temporaryRoot("confirmation-busy-retry")
    let layout = ProductLayout(canonicalRoot: root)
    let world = try WorldCreationService(layout: layout).createBareWorld(name: "Retryable")
    let session = String(repeating: "1", count: 64)
    let context = capabilityContext(root: root, session: session)
    let gate = FirstExecutionGate()
    let gateway = CLIWebCapabilityGateway(testBeforeExecution: {
      await gate.holdFirstExecution()
    })
    let plan = try await gateway.prepare(
      WebCapabilityRequest(
        capabilityID: CommandKind.worldDelete.rawValue,
        fields: ["world": [world.id]],
        sessionID: session,
        interaction: .confirmation
      ),
      in: context
    )

    let inFlight = Task {
      try await gateway.execute(
        WebCapabilityRequest(
          capabilityID: CommandKind.web.rawValue,
          sessionID: session,
          interaction: .hostStatus
        ),
        in: context
      )
    }
    await gate.waitUntilFirstExecutionEnters()

    await assertThrowsErrorAsync(
      try await gateway.commit(
        WebCapabilityCommitRequest(planID: plan.planID, sessionID: session),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .busy)
    }

    await gate.releaseFirstExecution()
    let inFlightResult = try await inFlight.value
    XCTAssertTrue(inFlightResult.accepted)

    let committed = try await gateway.commit(
      WebCapabilityCommitRequest(planID: plan.planID, sessionID: session),
      in: context
    )
    XCTAssertTrue(committed.accepted, committed.standardError)
    XCTAssertFalse(
      try WorldCatalogStore(
        url: layout.catalogURL,
        maximumBytes: RuntimeConfiguration.defaults.runtime.maximumWorldBytes
      ).document.worlds.contains(where: { $0.id == world.id })
    )

    await assertThrowsErrorAsync(
      try await gateway.commit(
        WebCapabilityCommitRequest(planID: plan.planID, sessionID: session),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .replayedPlan)
    }
  }

  func testPreparedPlanStorageIsCountBounded() async throws {
    let root = temporaryRoot("confirmation-cap")
    let layout = ProductLayout(canonicalRoot: root)
    let world = try WorldCreationService(layout: layout).createBareWorld(name: "Retained")
    let gateway = CLIWebCapabilityGateway()
    let session = String(repeating: "5", count: 64)
    let context = capabilityContext(root: root, session: session)
    let request = WebCapabilityRequest(
      capabilityID: CommandKind.worldDelete.rawValue,
      fields: ["world": [world.id]],
      sessionID: session,
      interaction: .confirmation
    )
    for _ in 0..<CLIWebCapabilityGateway.maximumPendingPlans {
      _ = try await gateway.prepare(request, in: context)
    }
    await assertThrowsErrorAsync(try await gateway.prepare(request, in: context)) { error in
      XCTAssertEqual(error as? WebCapabilityError, .busy)
    }
  }

  func testGatewayRejectsRawAdministrativeObjectSnapshotCapabilities() async {
    let root = temporaryRoot("raw-administrative-snapshots")
    let gateway = CLIWebCapabilityGateway()
    let session = String(repeating: "2", count: 64)
    let context = capabilityContext(root: root, session: session)

    for capabilityID in [
      CommandKind.inventoryShow.rawValue,
      CommandKind.inventoryCopiesShow.rawValue,
      CommandKind.worldObjectShow.rawValue,
    ] {
      await assertThrowsErrorAsync(
        try await gateway.execute(
          WebCapabilityRequest(
            capabilityID: capabilityID,
            sessionID: session,
            interaction: .projection
          ),
          in: context
        )
      ) { error in
        XCTAssertEqual(error as? WebCapabilityError, .unavailable)
      }
    }
  }

  func testGatewayRejectsBrowserSuppliedManagementPaths() async throws {
    let root = temporaryRoot("management-paths")
    let layout = ProductLayout(canonicalRoot: root)
    let world = try WorldCreationService(layout: layout).createBareWorld(name: "Paths")
    let inventory = try InventoryStore(
      url: layout.inventoryURL,
      packageDirectory: layout.packagesDirectoryURL,
      credentialStore: FileCredentialStore(directory: layout.credentialsDirectoryURL),
      runtimeRegistry: .installedCLI()
    )
    let manifestData = try JSONEncoder().encode(pathManagementTestManifest())
    let source = try XCTUnwrap(inventory.install(data: manifestData).inventoryObject)
    let gateway = CLIWebCapabilityGateway()
    let session = String(repeating: "0", count: 64)
    let context = capabilityContext(root: root, session: session)

    await assertThrowsErrorAsync(
      try await gateway.execute(
        WebCapabilityRequest(
          capabilityID: CommandKind.inventoryConfigure.rawValue,
          fields: ["inventory-id": [source.id], "set": ["workspace=/private/host-path"]],
          sessionID: session,
          interaction: .form
        ),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .invalidValue("set"))
    }

    await assertThrowsErrorAsync(
      try await gateway.execute(
        WebCapabilityRequest(
          capabilityID: CommandKind.inventoryConfigure.rawValue,
          fields: ["inventory-id": [source.id], "unset": ["workspace"]],
          sessionID: session,
          interaction: .form
        ),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .invalidValue("unset"))
    }

    await assertThrowsErrorAsync(
      try await gateway.execute(
        WebCapabilityRequest(
          capabilityID: CommandKind.inventoryActionRun.rawValue,
          fields: [
            "inventory-id": [source.id],
            "action": ["relocate"],
            "input": ["destination=/private/host-path"],
          ],
          sessionID: session,
          interaction: .form
        ),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .invalidValue("action"))
    }

    await assertThrowsErrorAsync(
      try await gateway.execute(
        WebCapabilityRequest(
          capabilityID: CommandKind.inventoryActionRun.rawValue,
          fields: ["inventory-id": [source.id], "action": ["relocate"]],
          sessionID: session,
          interaction: .form
        ),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .invalidValue("action"))
    }

    await assertThrowsErrorAsync(
      try await gateway.execute(
        WebCapabilityRequest(
          capabilityID: CommandKind.inventoryViewShow.rawValue,
          fields: ["inventory-id": [source.id], "view": ["configuration"]],
          exactWorldID: world.id,
          sessionID: session,
          interaction: .projection
        ),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .invalidValue("view"))
    }

    let deployment = try await gateway.execute(
      WebCapabilityRequest(
        capabilityID: CommandKind.inventoryDeploy.rawValue,
        fields: ["inventory-id": [source.id]],
        exactWorldID: world.id,
        sessionID: session,
        interaction: .form
      ),
      in: context
    )
    XCTAssertTrue(deployment.accepted, deployment.standardError)
    let worldSnapshot = try WorldProjectionService(layout: layout).snapshotExact(world: world.id)
    let objectID = try XCTUnwrap(
      worldSnapshot.objects.first(where: { $0.type == "path-fixture.object" })?.id
    )

    await assertThrowsErrorAsync(
      try await gateway.execute(
        WebCapabilityRequest(
          capabilityID: CommandKind.worldObjectActionRun.rawValue,
          fields: [
            "world-object-id": [objectID],
            "action": ["relocate"],
            "input": ["destination=/private/host-path"],
          ],
          exactWorldID: world.id,
          sessionID: session,
          interaction: .form
        ),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .invalidValue("action"))
    }

    await assertThrowsErrorAsync(
      try await gateway.execute(
        WebCapabilityRequest(
          capabilityID: CommandKind.worldObjectViewShow.rawValue,
          fields: ["world-object-id": [objectID], "view": ["configuration"]],
          exactWorldID: world.id,
          sessionID: session,
          interaction: .projection
        ),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .invalidValue("view"))
    }
  }

  func testBrowserMutationOutputPresentsConfigurationPresenceOnly() async throws {
    let root = temporaryRoot("browser-configuration-presentation")
    let layout = ProductLayout(canonicalRoot: root)
    _ = try WorldCreationService(layout: layout).createBareWorld(name: "Presentation")
    let inventory = try InventoryStore(
      url: layout.inventoryURL,
      packageDirectory: layout.packagesDirectoryURL,
      credentialStore: FileCredentialStore(directory: layout.credentialsDirectoryURL),
      runtimeRegistry: .installedCLI()
    )
    let source = try XCTUnwrap(
      inventory.install(data: JSONEncoder().encode(pathManagementTestManifest())).inventoryObject
    )
    let gateway = CLIWebCapabilityGateway()
    let session = String(repeating: "b", count: 64)
    let context = capabilityContext(root: root, session: session)
    let configuredValue = "browser-visible-value-must-not-leak"
    let defaultPath = "/private/default-workspace-must-not-leak"

    let result = try await gateway.execute(
      WebCapabilityRequest(
        capabilityID: CommandKind.inventoryConfigure.rawValue,
        fields: ["inventory-id": [source.id], "set": ["mode=\(configuredValue)"]],
        sessionID: session,
        interaction: .form
      ),
      in: context
    )

    XCTAssertTrue(result.accepted, result.standardError)
    XCTAssertTrue(result.standardOutput.contains("configuration"), result.standardOutput)
    XCTAssertTrue(result.standardOutput.contains("present  yes"), result.standardOutput)
    for privateValue in [configuredValue, defaultPath] {
      XCTAssertFalse(result.standardOutput.contains(privateValue), result.standardOutput)
      XCTAssertFalse(result.standardError.contains(privateValue), result.standardError)
    }
  }

  func testBrowserKeepsPathFreeTypedActionsAndViewsOperational() async throws {
    let root = temporaryRoot("path-free-management")
    let layout = ProductLayout(canonicalRoot: root)
    let world = try WorldCreationService(layout: layout).createBareWorld(name: "Path Free")
    let inventory = try InventoryStore(
      url: layout.inventoryURL,
      packageDirectory: layout.packagesDirectoryURL,
      credentialStore: FileCredentialStore(directory: layout.credentialsDirectoryURL),
      runtimeRegistry: .installedCLI()
    )
    let source = try XCTUnwrap(
      inventory.install(
        data: JSONEncoder().encode(pathFreeManagementTestManifest())
      ).inventoryObject
    )
    let paper = try XCTUnwrap(
      inventory.install(data: FirstPartyPackageCatalog.data(named: "paper")).inventoryObject
    )
    let gateway = CLIWebCapabilityGateway()
    let session = String(repeating: "c", count: 64)
    let context = capabilityContext(root: root, session: session)

    let inventoryAction = try await gateway.execute(
      WebCapabilityRequest(
        capabilityID: CommandKind.inventoryActionRun.rawValue,
        fields: [
          "inventory-id": [source.id],
          "action": ["set-mode"],
          "input": ["mode=active"],
        ],
        sessionID: session,
        interaction: .form
      ),
      in: context
    )
    XCTAssertTrue(inventoryAction.accepted, inventoryAction.standardError)

    let inventoryView = try await gateway.execute(
      WebCapabilityRequest(
        capabilityID: CommandKind.inventoryViewShow.rawValue,
        fields: ["inventory-id": [source.id], "view": ["summary"]],
        exactWorldID: world.id,
        sessionID: session,
        interaction: .projection
      ),
      in: context
    )
    XCTAssertTrue(inventoryView.accepted, inventoryView.standardError)

    await assertThrowsErrorAsync(
      try await gateway.execute(
        WebCapabilityRequest(
          capabilityID: CommandKind.inventoryViewShow.rawValue,
          fields: ["inventory-id": [source.id], "view": ["configuration"]],
          exactWorldID: world.id,
          sessionID: session,
          interaction: .projection
        ),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .invalidValue("view"))
    }

    let deployed = try await gateway.execute(
      WebCapabilityRequest(
        capabilityID: CommandKind.inventoryDeploy.rawValue,
        fields: ["inventory-id": [paper.id]],
        exactWorldID: world.id,
        sessionID: session,
        interaction: .form
      ),
      in: context
    )
    XCTAssertTrue(deployed.accepted, deployed.standardError)
    let snapshot = try WorldProjectionService(layout: layout).snapshotExact(world: world.id)
    let paperObjectID = try XCTUnwrap(
      snapshot.objects.first(where: { $0.type == "paper.object" })?.id
    )

    let worldAction = try await gateway.execute(
      WebCapabilityRequest(
        capabilityID: CommandKind.worldObjectActionRun.rawValue,
        fields: [
          "world-object-id": [paperObjectID],
          "action": ["replace"],
          "input": ["text=browser-safe"],
        ],
        exactWorldID: world.id,
        sessionID: session,
        interaction: .form
      ),
      in: context
    )
    XCTAssertTrue(worldAction.accepted, worldAction.standardError)

    let worldView = try await gateway.execute(
      WebCapabilityRequest(
        capabilityID: CommandKind.worldObjectViewShow.rawValue,
        fields: ["world-object-id": [paperObjectID], "view": ["contents"]],
        exactWorldID: world.id,
        sessionID: session,
        interaction: .projection
      ),
      in: context
    )
    XCTAssertTrue(worldView.accepted, worldView.standardError)
  }

  func testReportStreamConcurrencyIsBounded() async throws {
    let root = temporaryRoot("report-stream-cap")
    let layout = ProductLayout(canonicalRoot: root)
    let world = try WorldCreationService(layout: layout).createBareWorld(name: "Reports")
    let gateway = CLIWebCapabilityGateway()
    let session = String(repeating: "4", count: 64)
    let context = capabilityContext(root: root, session: session)
    let request = WebCapabilityRequest(
      capabilityID: CommandKind.inventoryReportsFollow.rawValue,
      exactWorldID: world.id,
      sessionID: session,
      interaction: .reportStream
    )
    var streams: [AsyncThrowingStream<String, Error>] = []
    for _ in 0..<CLIWebCapabilityGateway.maximumConcurrentReportStreams {
      streams.append(try await gateway.reportStream(request, in: context))
    }
    await assertThrowsErrorAsync(try await gateway.reportStream(request, in: context)) { error in
      XCTAssertEqual(error as? WebCapabilityError, .busy)
    }
    streams.removeAll()
    try await Task.sleep(for: .milliseconds(50))
  }

  func testGatewayRejectsUnknownFieldsAndUntrustedGlobalWorldContext() async throws {
    let root = temporaryRoot("validation")
    let gateway = CLIWebCapabilityGateway()
    let session = String(repeating: "e", count: 64)
    let context = capabilityContext(root: root, session: session)

    await assertThrowsErrorAsync(
      try await gateway.execute(
        WebCapabilityRequest(
          capabilityID: CommandKind.status.rawValue,
          fields: ["--config": ["/tmp/private"]],
          sessionID: session,
          interaction: .projection
        ),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .invalidField("unknown"))
    }

    await assertThrowsErrorAsync(
      try await gateway.execute(
        WebCapabilityRequest(
          capabilityID: CommandKind.status.rawValue,
          exactWorldID: String(repeating: "f", count: 32),
          sessionID: session,
          interaction: .projection
        ),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .invalidWorldContext)
    }
  }

  func testGatewayRejectsGlobalOptionInjectionInsideFieldValues() async throws {
    let root = temporaryRoot("global-value-injection")
    let layout = ProductLayout(canonicalRoot: root)
    let selected = try WorldCreationService(layout: layout).createBareWorld(name: "Selected")
    let other = try WorldCreationService(layout: layout).createBareWorld(name: "Other")
    let gateway = CLIWebCapabilityGateway()
    let session = String(repeating: "8", count: 64)
    let context = capabilityContext(root: root, session: session)

    await assertThrowsErrorAsync(
      try await gateway.execute(
        WebCapabilityRequest(
          capabilityID: CommandKind.worldShow.rawValue,
          fields: ["world": ["--world=\(other.id)"]],
          exactWorldID: selected.id,
          sessionID: session,
          interaction: .projection
        ),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .invalidValue("world"))
    }

    await assertThrowsErrorAsync(
      try await gateway.execute(
        WebCapabilityRequest(
          capabilityID: CommandKind.worldShow.rawValue,
          fields: ["world": [other.id]],
          exactWorldID: selected.id,
          sessionID: session,
          interaction: .projection
        ),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .invalidWorldContext)
    }

    await assertThrowsErrorAsync(
      try await gateway.execute(
        WebCapabilityRequest(
          capabilityID: CommandKind.configSet.rawValue,
          fields: ["key": ["console.unicode"], "value": ["--config=/tmp/private.json"]],
          sessionID: session,
          interaction: .form
        ),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .invalidValue("value"))
    }
  }

  func testGatewayInstallsAnExactBuiltInBrowserPackageSource() async throws {
    let root = temporaryRoot("package-built-in-source")
    let layout = ProductLayout(canonicalRoot: root)
    let gateway = CLIWebCapabilityGateway()
    let session = String(repeating: "7", count: 64)
    let context = capabilityContext(root: root, session: session)

    let result = try await gateway.execute(
      WebCapabilityRequest(
        capabilityID: CommandKind.inventoryInstall.rawValue,
        fields: ["path-or-url": ["builtin:paper"]],
        sessionID: session,
        interaction: .form
      ),
      in: context
    )

    XCTAssertTrue(result.accepted, result.standardError)
    let inventory = try InventoryStore(
      url: layout.inventoryURL,
      packageDirectory: layout.packagesDirectoryURL,
      credentialStore: FileCredentialStore(directory: layout.credentialsDirectoryURL),
      runtimeRegistry: .installedCLI()
    )
    XCTAssertTrue(
      inventory.document.packages.contains(where: {
        $0.manifest.id == FirstPartyPackageID.paper && $0.visible
      })
    )
  }

  func testBrowserPackageSourceClassificationAcceptsHTTPSAndExactBuiltIns() {
    XCTAssertTrue(
      CLIWebCapabilityGateway.isBrowserSafePackageInstallSource("builtin:paper")
    )
    XCTAssertTrue(
      CLIWebCapabilityGateway.isBrowserSafePackageInstallSource(
        "builtin:org.mikrokhoros.paper"
      )
    )
    XCTAssertTrue(
      CLIWebCapabilityGateway.isBrowserSafePackageInstallSource(
        "https://packages.example/object.json"
      )
    )
  }

  func testBrowserPackageDownloadRejectsPlaintextLoopbackRedirectBeforeRequest() async throws {
    let source = try XCTUnwrap(URL(string: "https://packages.example.invalid/object.json"))
    let redirect = try XCTUnwrap(URL(string: "http://127.0.0.1:8181/object.json"))
    ControlledPackageRedirectURLProtocol.recorder.configure(
      source: source,
      redirect: redirect,
      body: Data("package".utf8)
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ControlledPackageRedirectURLProtocol.self]

    await assertThrowsErrorAsync(
      try await ObjectPackageDownloader.download(
        source,
        maximumBytes: 1_024,
        acquisitionPolicy: .browser,
        sessionConfiguration: configuration
      )
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "object_package.url_rejected")
    }

    XCTAssertEqual(ControlledPackageRedirectURLProtocol.recorder.requestedURLs(), [source])
  }

  func testBrowserPackageDownloadAcceptsHTTPSRedirectChain() async throws {
    let source = try XCTUnwrap(URL(string: "https://packages.example.invalid/object.json"))
    let redirect = try XCTUnwrap(URL(string: "https://cdn.example.invalid/object.json"))
    let body = Data("package".utf8)
    ControlledPackageRedirectURLProtocol.recorder.configure(
      source: source,
      redirect: redirect,
      body: body
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ControlledPackageRedirectURLProtocol.self]

    let downloaded = try await ObjectPackageDownloader.download(
      source,
      maximumBytes: 1_024,
      acquisitionPolicy: .browser,
      sessionConfiguration: configuration
    )

    XCTAssertEqual(downloaded, body)
    XCTAssertEqual(
      ControlledPackageRedirectURLProtocol.recorder.requestedURLs(), [source, redirect])
  }

  func testCommandLinePackagePolicyRetainsLoopbackHTTPDevelopmentSupport() throws {
    let loopback = try XCTUnwrap(URL(string: "http://127.0.0.1:8181/object.json"))
    XCTAssertNoThrow(try ObjectPackageAcquisitionPolicy.commandLine.validate(loopback))
  }

  func testBrowserAcquisitionContextRejectsLoopbackBeforeInventoryAccess() async throws {
    let root = temporaryRoot("browser-package-acquisition-context")
    let layout = ProductLayout(canonicalRoot: root)
    let inventory = try InventoryStore(
      url: layout.inventoryURL,
      packageDirectory: layout.packagesDirectoryURL,
      credentialStore: FileCredentialStore(directory: layout.credentialsDirectoryURL),
      runtimeRegistry: .installedCLI()
    )

    await assertThrowsErrorAsync(
      try await ObjectPackageAcquisitionContext.$policy.withValue(.browser) {
        try await inventory.install(from: "http://127.0.0.1:8181/object.json")
      }
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "object_package.url_rejected")
    }
  }

  func testGatewayRejectsUntrustedBrowserPackageSources() async throws {
    let root = temporaryRoot("package-source-boundary")
    let gateway = CLIWebCapabilityGateway()
    let session = String(repeating: "7", count: 64)
    let context = capabilityContext(root: root, session: session)
    for source in [
      root.appendingPathComponent("private.json").path,
      "file:///private.json",
      "http://example.com/object.json",
      "https://package-user:password@example.com/object.json",
      "builtin:does-not-exist",
      "builtin:../paper",
      "builtin:paper/..",
      "--config=/tmp/private.json",
    ] {
      XCTAssertFalse(CLIWebCapabilityGateway.isBrowserSafePackageInstallSource(source))
      await assertThrowsErrorAsync(
        try await gateway.execute(
          WebCapabilityRequest(
            capabilityID: CommandKind.inventoryInstall.rawValue,
            fields: ["path-or-url": [source]],
            sessionID: session,
            interaction: .form
          ),
          in: context
        )
      ) { error in
        XCTAssertEqual(error as? WebCapabilityError, .invalidValue("path-or-url"))
      }
    }
  }

  func testSecretSubmissionIsBoundedStdinOnlyAndNeverEchoed() async throws {
    let root = temporaryRoot("secret")
    let layout = ProductLayout(canonicalRoot: root)
    _ = try WorldCreationService(layout: layout).createBareWorld(name: "Secrets")
    let inventory = try InventoryStore(
      url: layout.inventoryURL,
      packageDirectory: layout.packagesDirectoryURL,
      credentialStore: FileCredentialStore(directory: layout.credentialsDirectoryURL),
      runtimeRegistry: .installedCLI()
    )
    let manifest = try secretTestManifest()
    let installed = try XCTUnwrap(
      inventory.install(data: JSONEncoder().encode(manifest)).inventoryObject
    )
    let gateway = CLIWebCapabilityGateway()
    let session = String(repeating: "3", count: 64)
    let context = capabilityContext(root: root, session: session)
    let privateValue = "gateway-secret-value"
    let request = WebCapabilityRequest(
      capabilityID: CommandKind.inventorySecretSet.rawValue,
      fields: ["inventory-id": [installed.id], "field": ["api_key"]],
      sessionID: session,
      secret: Data(privateValue.utf8),
      interaction: .secret
    )

    let result = try await gateway.execute(request, in: context)

    XCTAssertTrue(result.accepted, result.standardError)
    XCTAssertTrue(result.standardOutput.contains("present"), result.standardOutput)
    for presented in [result.displayCommand, result.standardOutput, result.standardError] {
      XCTAssertFalse(presented.contains(privateValue))
    }
    let persisted = try InventoryStore(
      url: layout.inventoryURL,
      packageDirectory: layout.packagesDirectoryURL,
      credentialStore: FileCredentialStore(directory: layout.credentialsDirectoryURL),
      runtimeRegistry: .installedCLI()
    )
    let updated = try persisted.resolve(installed.id)
    let handle = try XCTUnwrap(updated.credentialHandles["api_key"])
    XCTAssertEqual(
      try FileCredentialStore(directory: layout.credentialsDirectoryURL).read(handle: handle),
      Data(privateValue.utf8)
    )
    XCTAssertFalse(
      String(decoding: try JSONEncoder().encode(persisted.document), as: UTF8.self).contains(
        privateValue))

    await assertThrowsErrorAsync(
      try await gateway.execute(
        WebCapabilityRequest(
          capabilityID: CommandKind.inventorySecretSet.rawValue,
          fields: ["inventory-id": [installed.id], "field": ["api_key"]],
          sessionID: session,
          secret: Data(
            repeating: 0x61, count: CLIWebCapabilityGateway.maximumSecretBytes + 1),
          interaction: .secret
        ),
        in: context
      )
    ) { error in
      XCTAssertEqual(error as? WebCapabilityError, .invalidValue("credential-value"))
    }
  }

  func testDisplayCommandOmitsShellActiveUntrustedValues() async throws {
    let root = temporaryRoot("inert-command-display")
    let layout = ProductLayout(canonicalRoot: root)
    let world = try WorldCreationService(layout: layout).createBareWorld(name: "Rename")
    let gateway = CLIWebCapabilityGateway()
    let session = String(repeating: "2", count: 64)
    let context = capabilityContext(root: root, session: session)
    let hostile = "name;$(touch should-not-run)|`command`"

    let result = try await gateway.execute(
      WebCapabilityRequest(
        capabilityID: CommandKind.worldRename.rawValue,
        fields: ["world": [world.id], "name": [hostile]],
        sessionID: session,
        interaction: .form
      ),
      in: context
    )

    XCTAssertTrue(result.accepted, result.standardError)
    XCTAssertFalse(result.displayCommand.contains(hostile))
    XCTAssertFalse(result.displayCommand.contains("$"))
    XCTAssertFalse(result.displayCommand.contains(";"))
    XCTAssertTrue(result.displayCommand.contains("value_omitted"))
  }

  func testPrivateRevealAndAcceptedAndFailedDownloadUseDistinctTransports() async throws {
    let root = temporaryRoot("private-transports")
    let layout = ProductLayout(canonicalRoot: root)
    let available = try WorldCreationService(layout: layout).createBareWorld(name: "Private")
    let oversized = try WorldCreationService(layout: layout).createBareWorld(name: "Oversized")
    let corrupted = try WorldCreationService(layout: layout).createBareWorld(name: "Corrupted")
    var oversizedDocument = try WorldStore.load(from: layout.worldURL(for: oversized.id))
    oversizedDocument.events = Array(
      repeating: .objectsDeleted(objectIDs: []),
      count: 40_000
    )
    XCTAssertGreaterThan(
      try JSONEncoder().encode(oversizedDocument).count,
      CLIWebCapabilityGateway.maximumOutputBytes
    )
    try WorldStore.save(oversizedDocument, to: layout.worldURL(for: oversized.id))
    let directOversized = try await CLIWebCapabilityGateway().execute(
      WebCapabilityRequest(
        capabilityID: CommandKind.worldExport.rawValue,
        fields: [:],
        exactWorldID: oversized.id,
        sessionID: String(repeating: "e", count: 64),
        interaction: .download
      ),
      in: capabilityContext(root: root, session: String(repeating: "e", count: 64))
    )
    XCTAssertTrue(directOversized.accepted, directOversized.standardError)
    XCTAssertTrue(directOversized.outputTruncated)
    let transport = try authenticatedTransport(root: root, port: 43131)

    let inspect = await transport.router.routeAsync(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/web/execute",
        headers: transport.headers,
        body: try JSONSerialization.data(withJSONObject: [
          "operationID": CommandKind.worldInspect.rawValue,
          "worldID": available.id,
          "fields": [:],
        ])
      )
    )
    XCTAssertEqual(inspect.statusCode, 200)
    XCTAssertEqual(inspect.headers["content-type"], "application/json")
    let inspectJSON = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: inspect.body) as? [String: Any]
    )
    XCTAssertEqual(inspectJSON["accepted"] as? Bool, true)
    XCTAssertNil(inspect.body.range(of: Data(root.path.utf8)))

    let accepted = await transport.router.routeAsync(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/web/execute",
        headers: transport.headers,
        body: try JSONSerialization.data(withJSONObject: [
          "operationID": CommandKind.worldExport.rawValue,
          "worldID": available.id,
          "fields": [:],
        ])
      )
    )
    XCTAssertEqual(accepted.statusCode, 200)
    XCTAssertEqual(accepted.headers["content-type"], "application/octet-stream")
    XCTAssertNotNil(accepted.headers["content-disposition"])
    XCTAssertFalse(accepted.body.isEmpty)

    let truncated = await transport.router.routeAsync(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/web/execute",
        headers: transport.headers,
        body: try JSONSerialization.data(withJSONObject: [
          "operationID": CommandKind.worldExport.rawValue,
          "worldID": oversized.id,
          "fields": [:],
        ])
      )
    )
    XCTAssertEqual(truncated.statusCode, 200)
    XCTAssertEqual(truncated.headers["content-type"], "application/json")
    XCTAssertNil(truncated.headers["content-disposition"])
    let truncatedJSON = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: truncated.body) as? [String: Any]
    )
    XCTAssertEqual(truncatedJSON["accepted"] as? Bool, false)
    XCTAssertEqual(truncatedJSON["outputTruncated"] as? Bool, true)
    XCTAssertEqual(truncatedJSON["standardOutput"] as? String, "")
    XCTAssertTrue(
      (truncatedJSON["standardError"] as? String ?? "").contains("browser transfer limit")
    )

    try Data("not a world document".utf8).write(to: layout.worldURL(for: corrupted.id))
    let failed = await transport.router.routeAsync(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/web/execute",
        headers: transport.headers,
        body: try JSONSerialization.data(withJSONObject: [
          "operationID": CommandKind.worldExport.rawValue,
          "worldID": corrupted.id,
          "fields": [:],
        ])
      )
    )
    XCTAssertEqual(failed.statusCode, 200)
    XCTAssertEqual(failed.headers["content-type"], "application/json")
    XCTAssertNil(failed.headers["content-disposition"])
    let failedJSON = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: failed.body) as? [String: Any]
    )
    XCTAssertEqual(failedJSON["accepted"] as? Bool, false)
    XCTAssertFalse((failedJSON["standardError"] as? String ?? "").isEmpty)
  }

  func testWebTransportHonorsCapabilityAndSecretBodyLimits() async throws {
    let root = temporaryRoot("web-capability-body-limits")
    let layout = ProductLayout(canonicalRoot: root)
    _ = try WorldCreationService(layout: layout).createBareWorld(name: "Body limits")
    let inventory = try InventoryStore(
      url: layout.inventoryURL,
      packageDirectory: layout.packagesDirectoryURL,
      credentialStore: FileCredentialStore(directory: layout.credentialsDirectoryURL),
      runtimeRegistry: .installedCLI()
    )
    let installed = try XCTUnwrap(
      inventory.install(data: JSONEncoder().encode(try secretTestManifest())).inventoryObject
    )
    let transport = try authenticatedTransport(root: root, port: 43132)
    let privateValue = String(repeating: "s", count: 12 * 1_024)
    let body = try JSONSerialization.data(withJSONObject: [
      "operationID": CommandKind.inventorySecretSet.rawValue,
      "fields": ["inventory-id": [installed.id], "field": ["api_key"]],
      "secret": privateValue,
    ])
    XCTAssertGreaterThan(body.count, 8_192)
    XCTAssertLessThanOrEqual(body.count, 65_536)

    let accepted = await transport.router.routeAsync(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/web/secret",
        headers: transport.headers,
        body: body
      )
    )
    XCTAssertEqual(accepted.statusCode, 200)
    let acceptedJSON = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: accepted.body) as? [String: Any]
    )
    XCTAssertEqual(acceptedJSON["accepted"] as? Bool, true)
    XCTAssertNil(accepted.body.range(of: Data(privateValue.utf8)))
    let updated = try InventoryStore(
      url: layout.inventoryURL,
      packageDirectory: layout.packagesDirectoryURL,
      credentialStore: FileCredentialStore(directory: layout.credentialsDirectoryURL),
      runtimeRegistry: .installedCLI()
    ).resolve(installed.id)
    let handle = try XCTUnwrap(updated.credentialHandles["api_key"])
    XCTAssertEqual(
      try FileCredentialStore(directory: layout.credentialsDirectoryURL).read(handle: handle),
      Data(privateValue.utf8)
    )

    let rejected = await transport.router.routeAsync(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/web/execute",
        headers: transport.headers,
        body: Data(repeating: 0x61, count: 65_537)
      )
    )
    XCTAssertEqual(rejected.statusCode, 413)
  }

  func testAuthenticatedWebTransportCoversCatalogCompletionExecutionAndCommit()
    async throws
  {
    let root = temporaryRoot("transport")
    let layout = ProductLayout(canonicalRoot: root)
    let world = try WorldCreationService(layout: layout).createBareWorld(name: "Transport World")
    let sessions = WebSessionStore()
    let router = KhorosWebRouter(
      projection: WorldProjectionService(layout: layout),
      webCapabilities: CLIWebCapabilityGateway(),
      sessions: sessions
    )
    let port = 43129
    router.setEndpoint(port: port)
    let token = router.installBootstrapToken()
    let sessionResponse = router.route(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/session",
        headers: [
          "host": ["127.0.0.1:\(port)"],
          "origin": ["http://127.0.0.1:\(port)"],
          "content-type": ["application/json"],
        ],
        body: Data(#"{"token":"\#(token)"}"#.utf8)
      )
    )
    XCTAssertEqual(sessionResponse.statusCode, 200)
    let cookie = try XCTUnwrap(
      sessionResponse.headers["set-cookie"]?.split(separator: ";", maxSplits: 1).first
    )
    let headers = [
      "host": ["127.0.0.1:\(port)"],
      "cookie": [String(cookie)],
    ]

    let catalog = router.route(
      KhorosWebRequest(
        method: "GET",
        uri: "/api/v1/web/capabilities",
        headers: headers
      )
    )
    XCTAssertEqual(catalog.statusCode, 200)
    let catalogJSON = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: catalog.body) as? [String: Any]
    )
    let capabilities = try XCTUnwrap(catalogJSON["capabilities"] as? [[String: Any]])
    XCTAssertEqual(capabilities.count, 89)
    XCTAssertEqual(
      capabilities.first {
        $0["id"] as? String == CommandKind.worldObjectShow.rawValue
      }?["enabled"] as? Bool,
      false
    )
    XCTAssertEqual(
      capabilities.first(where: { $0["id"] as? String == CommandKind.web.rawValue })?["mode"]
        as? String,
      WebCapabilityInteractionMode.hostStatus.rawValue
    )
    XCTAssertNil(catalog.body.range(of: Data(token.utf8)))
    XCTAssertNil(catalog.body.range(of: Data(root.path.utf8)))

    let postHeaders = headers.merging([
      "origin": ["http://127.0.0.1:\(port)"],
      "content-type": ["application/json"],
    ]) { _, new in new }
    let hostStatus = await router.routeAsync(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/web/execute",
        headers: postHeaders,
        body: Data(#"{"operationID":"web","fields":{}}"#.utf8)
      )
    )
    XCTAssertEqual(hostStatus.statusCode, 200)
    let hostJSON = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: hostStatus.body) as? [String: Any]
    )
    XCTAssertEqual(hostJSON["accepted"] as? Bool, true)
    XCTAssertEqual(hostJSON["displayCommand"] as? String, "khoros web")

    let completions = await router.routeAsync(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/web/completions",
        headers: postHeaders,
        body: try JSONSerialization.data(withJSONObject: [
          "operationID": CommandKind.worldDelete.rawValue,
          "fieldID": "world",
          "source": "Transport",
          "fields": [:],
        ])
      )
    )
    XCTAssertEqual(completions.statusCode, 200)
    let completionJSON = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: completions.body) as? [String: Any]
    )
    XCTAssertEqual(
      (completionJSON["values"] as? [[String: Any]])?.first?["value"] as? String,
      world.id
    )

    let prepared = await router.routeAsync(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/web/prepare",
        headers: postHeaders,
        body: try JSONSerialization.data(withJSONObject: [
          "operationID": CommandKind.worldDelete.rawValue,
          "fields": ["world": [world.id]],
        ])
      )
    )
    XCTAssertEqual(prepared.statusCode, 200)
    let preparedJSON = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: prepared.body) as? [String: Any]
    )
    let planID = try XCTUnwrap(preparedJSON["planID"] as? String)
    XCTAssertEqual(preparedJSON["operationID"] as? String, CommandKind.worldDelete.rawValue)
    XCTAssertEqual(preparedJSON["command"] as? String, "khoros world delete \(world.id)")

    let committed = await router.routeAsync(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/web/commit",
        headers: postHeaders,
        body: try JSONSerialization.data(withJSONObject: [
          "planID": planID,
          "confirmed": true,
        ])
      )
    )
    XCTAssertEqual(committed.statusCode, 200)
    let replayed = await router.routeAsync(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/web/commit",
        headers: postHeaders,
        body: try JSONSerialization.data(withJSONObject: [
          "planID": planID,
          "confirmed": true,
        ])
      )
    )
    XCTAssertEqual(replayed.statusCode, 410)

    let privateValue = "do-not-echo-this-value"
    let duplicateNested = await router.routeAsync(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/web/secret",
        headers: postHeaders,
        body: Data(
          "{\"operationID\":\"web\",\"fields\":{\"value\":[\"\(privateValue)\"],\"val\\u0075e\":[\"second\"]},\"secret\":\"\(privateValue)\"}"
            .utf8
        )
      )
    )
    XCTAssertEqual(duplicateNested.statusCode, 400)
    XCTAssertEqual(duplicateNested.body, Data(#"{"error":"request_rejected"}"#.utf8))
    XCTAssertNil(duplicateNested.body.range(of: Data(privateValue.utf8)))

    let nested = String(repeating: "[", count: 70) + "0" + String(repeating: "]", count: 70)
    let overDeep = await router.routeAsync(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/web/execute",
        headers: postHeaders,
        body: Data("{\"operationID\":\"web\",\"fields\":{\"value\":\(nested)}}".utf8)
      )
    )
    XCTAssertEqual(overDeep.statusCode, 400)
    XCTAssertEqual(overDeep.body, Data(#"{"error":"request_rejected"}"#.utf8))
  }

  private func temporaryRoot(_ label: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-web-capability-\(label)-\(UUID().uuidString)",
      isDirectory: true
    )
  }

  private func capabilityContext(root: URL, session: String) -> WebCapabilityContext {
    WebCapabilityContext(
      layout: ProductLayout(canonicalRoot: root),
      sessionID: session,
      hostState: WebHostState(
        lifecycle: .running,
        address: "127.0.0.1",
        port: 43127
      )
    )
  }

  private func authenticatedTransport(
    root: URL,
    port: Int
  ) throws -> (router: KhorosWebRouter, headers: [String: [String]]) {
    let layout = ProductLayout(canonicalRoot: root)
    let sessions = WebSessionStore()
    let router = KhorosWebRouter(
      projection: WorldProjectionService(layout: layout),
      webCapabilities: CLIWebCapabilityGateway(),
      sessions: sessions
    )
    router.setEndpoint(port: port)
    let token = router.installBootstrapToken()
    let response = router.route(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/session",
        headers: [
          "host": ["127.0.0.1:\(port)"],
          "origin": ["http://127.0.0.1:\(port)"],
          "content-type": ["application/json"],
        ],
        body: Data(#"{"token":"\#(token)"}"#.utf8)
      )
    )
    XCTAssertEqual(response.statusCode, 200)
    let cookie = try XCTUnwrap(
      response.headers["set-cookie"]?.split(separator: ";", maxSplits: 1).first
    )
    return (
      router,
      [
        "host": ["127.0.0.1:\(port)"],
        "origin": ["http://127.0.0.1:\(port)"],
        "content-type": ["application/json"],
        "cookie": [String(cookie)],
      ]
    )
  }

  private func secretTestManifest() throws -> ObjectPackageManifest {
    try ObjectPackageManifest(
      id: "example.web-secret",
      version: "1.0.0",
      displayName: "Web Secret Fixture",
      installation: PackageInstallationPolicy(onInstall: .createInventoryObject),
      object: DeclarativeObjectDefinition(type: "secret-fixture.object", name: "Secret fixture"),
      management: ObjectManagementInterface(
        fields: [
          try ManagementField(
            id: "api_key",
            label: "API key",
            kind: .secret,
            required: true
          )
        ]
      )
    )
  }

  private func pathManagementTestManifest() throws -> ObjectPackageManifest {
    try ObjectPackageManifest(
      id: "example.web-path",
      version: "1.0.0",
      displayName: "Web Path Fixture",
      installation: PackageInstallationPolicy(onInstall: .createInventoryObject),
      object: DeclarativeObjectDefinition(type: "path-fixture.object", name: "Path fixture"),
      management: ObjectManagementInterface(
        fields: [
          try ManagementField(
            id: "workspace",
            label: "Workspace",
            kind: .path,
            defaultValue: .string("/private/default-workspace-must-not-leak")
          ),
          try ManagementField(id: "mode", label: "Mode", kind: .text),
        ],
        actions: [
          try ManagementAction(
            id: "relocate",
            parameters: ["destination"],
            inputTypes: ["destination": .path],
            scope: .both,
            action: DeclarativeAction(kind: .return)
          )
        ],
        views: [
          try ManagementView(id: "configuration", source: "configuration", scope: .both)
        ]
      )
    )
  }

  private func pathFreeManagementTestManifest() throws -> ObjectPackageManifest {
    try ObjectPackageManifest(
      id: "example.web-path-free",
      version: "1.0.0",
      displayName: "Web Path-Free Fixture",
      installation: PackageInstallationPolicy(onInstall: .createInventoryObject),
      object: DeclarativeObjectDefinition(
        type: "path-free-fixture.object",
        name: "Path-free fixture"
      ),
      management: ObjectManagementInterface(
        fields: [try ManagementField(id: "mode", label: "Mode", kind: .text)],
        actions: [
          try ManagementAction(
            id: "set-mode",
            parameters: ["mode"],
            inputTypes: ["mode": .text],
            mutating: true,
            scope: .inventory,
            action: DeclarativeAction(kind: .set, key: "mode", argument: 0)
          )
        ],
        views: [
          try ManagementView(id: "summary", source: "summary", scope: .inventory),
          try ManagementView(id: "configuration", source: "configuration", scope: .inventory),
        ]
      )
    )
  }
}

private func assertThrowsErrorAsync<T>(
  _ expression: @autoclosure () async throws -> T,
  _ errorHandler: (Error) -> Void = { _ in },
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("Expected an error", file: file, line: line)
  } catch {
    errorHandler(error)
  }
}

private actor FirstExecutionGate {
  private var hasHeldFirstExecution = false
  private var firstExecutionEntered: CheckedContinuation<Void, Never>?
  private var firstExecutionRelease: CheckedContinuation<Void, Never>?

  func holdFirstExecution() async {
    guard !hasHeldFirstExecution else { return }
    hasHeldFirstExecution = true
    firstExecutionEntered?.resume()
    firstExecutionEntered = nil
    await withCheckedContinuation { continuation in
      firstExecutionRelease = continuation
    }
  }

  func waitUntilFirstExecutionEnters() async {
    guard !hasHeldFirstExecution else { return }
    await withCheckedContinuation { continuation in
      firstExecutionEntered = continuation
    }
  }

  func releaseFirstExecution() {
    firstExecutionRelease?.resume()
    firstExecutionRelease = nil
  }
}

private final class ControlledPackageRedirectRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var source: URL?
  private var redirect: URL?
  private var body = Data()
  private var requests = [URL]()

  func configure(source: URL, redirect: URL, body: Data) {
    lock.lock()
    self.source = source
    self.redirect = redirect
    self.body = body
    requests = []
    lock.unlock()
  }

  func shouldHandle(_ url: URL) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return url == source || url == redirect
  }

  func record(_ url: URL) -> (redirect: URL?, body: Data) {
    lock.lock()
    defer { lock.unlock() }
    requests.append(url)
    return (url == source ? redirect : nil, body)
  }

  func requestedURLs() -> [URL] {
    lock.lock()
    defer { lock.unlock() }
    return requests
  }
}

private final class ControlledPackageRedirectURLProtocol: URLProtocol, @unchecked Sendable {
  static let recorder = ControlledPackageRedirectRecorder()

  override class func canInit(with request: URLRequest) -> Bool {
    guard let url = request.url else { return false }
    return recorder.shouldHandle(url)
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    let event = Self.recorder.record(url)
    if let redirect = event.redirect {
      guard
        let response = HTTPURLResponse(
          url: url,
          statusCode: 302,
          httpVersion: "HTTP/1.1",
          headerFields: ["Location": redirect.absoluteString]
        )
      else {
        client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
        return
      }
      client?.urlProtocol(
        self,
        wasRedirectedTo: URLRequest(url: redirect),
        redirectResponse: response
      )
      return
    }
    guard
      let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Length": String(event.body.count)]
      )
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: event.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
