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
import NIOCore
import NIOHTTP1
import NIOPosix

// This guard runs before the route is classified.  It must retain the
// web capability gateway's documented 64 KiB budget; the World command route
// applies its stricter 8 KiB limit only after classification in `asyncRoute`.
private let webMaximumRequestBytes = 64 * 1_024
private let webMaximumRequestLineCharacters = 8_192
private let webMaximumHeaderBytes = 16_384
private let webMaximumWorldCreationBytes = 512
private let webMaximumAgentAdditionBytes = 1_024
private let webMaximumCommandRequestBytes = 8_192
private let webMaximumCommandSourceCharacters = 4_096
private let webMaximumCapabilityRequestBytes = 64 * 1_024
private let webMaximumCapabilityStreamChunkBytes = 256 * 1_024 + 128
private let webTokenLifetime: TimeInterval = 90
private let webRouteKeys: Set<String> = [
  "view", "world", "container", "focus", "agent", "source", "folder", "package", "version",
  "template", "setting",
]
private let webViews: Set<String> = [
  "world", "agentManager", "inventory", "packages", "templates", "settings",
]
private let webRouteIdentityKeys: Set<String> = ["world", "container", "focus"]
private let webMaximumRouteValueCharacters = 256
private let webListenerMarkerHeader = "x-mikrokhoros-listener"
private let webListenerMarkerValue = "khoros-web/1"

public struct KhorosWebRequest: Sendable {
  public let method: String
  public let uri: String
  public let headers: [String: [String]]
  public let body: Data

  public init(
    method: String,
    uri: String,
    headers: [String: [String]] = [:],
    body: Data = Data()
  ) {
    self.method = method
    self.uri = uri
    self.headers = headers.reduce(into: [:]) { result, item in
      result[item.key.lowercased(), default: []].append(contentsOf: item.value)
    }
    self.body = body
  }
}

public struct KhorosWebResponse: Sendable, Equatable {
  public let statusCode: Int
  public let headers: [String: String]
  public let body: Data

  public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
    self.statusCode = statusCode
    self.headers = headers
    self.body = body
  }
}

private enum KhorosWebStreamRoute: Sendable {
  case response(KhorosWebResponse)
  case stream(headers: [String: String], body: AsyncThrowingStream<String, Error>)
}

/// The bounded HTTP router is intentionally transport-neutral so request
/// security rules can be tested without opening a socket.
public final class KhorosWebRouter: @unchecked Sendable {
  private let projection: WorldProjectionService
  private let worldCreation: WorldCreationService
  private let agentPresence: WorldAgentPresenceService
  private let webProjections: WebProjectionService
  private let commandConsole: (any WorldCommandConsoleServing)?
  private let webCapabilities: (any WebCapabilityServing)?
  private let sessions: WebSessionStore
  private let assets: WebAssetStore
  private let stateLock = NSLock()
  private var expectedHost = "127.0.0.1:0"
  private var expectedOrigin = "http://127.0.0.1:0"
  private var expectedSessionCookieName = "khoros_session_0"

  public init(
    projection: WorldProjectionService,
    commandConsole: (any WorldCommandConsoleServing)? = nil,
    webCapabilities: (any WebCapabilityServing)? = nil,
    assets: WebAssetStore = WebAssetStore(),
    sessions: WebSessionStore = WebSessionStore()
  ) {
    self.projection = projection
    worldCreation = WorldCreationService(layout: projection.layout)
    agentPresence = WorldAgentPresenceService(layout: projection.layout)
    webProjections = WebProjectionService(layout: projection.layout)
    self.commandConsole = commandConsole
    self.webCapabilities = webCapabilities
    self.assets = assets
    self.sessions = sessions
  }

  public func setEndpoint(port: Int) {
    stateLock.lock()
    expectedHost = "127.0.0.1:\(port)"
    expectedOrigin = "http://127.0.0.1:\(port)"
    expectedSessionCookieName = "khoros_session_\(port)"
    stateLock.unlock()
  }

  public func installBootstrapToken() -> String {
    sessions.installBootstrapToken()
  }

  public func route(_ request: KhorosWebRequest) -> KhorosWebResponse {
    let response = routeInternal(request)
    guard request.method.uppercased() == "HEAD" else { return response }
    return KhorosWebResponse(statusCode: response.statusCode, headers: response.headers)
  }

  /// Routes finite command-console and web capability POSTs without turning the
  /// ordinary static/projection router into an asynchronous API.
  public func routeAsync(_ request: KhorosWebRequest) async -> KhorosWebResponse {
    guard requiresAsyncRoute(request) else { return route(request) }
    let response = await asyncRoute(request)
    guard request.method.uppercased() == "HEAD" else { return response }
    return KhorosWebResponse(statusCode: response.statusCode, headers: response.headers)
  }

  fileprivate func requiresAsyncRoute(_ request: KhorosWebRequest) -> Bool {
    guard let target = parseTarget(request.uri) else { return false }
    return target.path == "/api/v1/world-command/completions"
      || target.path == "/api/v1/world-command/execute"
      || target.path == "/api/v1/web/completions"
      || target.path == "/api/v1/web/execute"
      || target.path == "/api/v1/web/prepare"
      || target.path == "/api/v1/web/commit"
      || target.path == "/api/v1/web/secret"
      || target.path == "/api/v1/web/agent-controller"
  }

  fileprivate func requiresStreamingRoute(_ request: KhorosWebRequest) -> Bool {
    guard let target = parseTarget(request.uri) else { return false }
    return target.path == "/api/v1/web/report-follow"
  }

  fileprivate func routeStream(_ request: KhorosWebRequest) async -> KhorosWebStreamRoute {
    guard request.uri.utf8.count <= webMaximumRequestLineCharacters,
      request.body.count <= webMaximumCapabilityRequestBytes
    else { return .response(failure(413)) }
    guard headerBytes(request.headers) <= webMaximumHeaderBytes else {
      return .response(failure(431))
    }
    guard validHost(request.headers), validOrigin(request.headers, method: request.method) else {
      return .response(failure(400))
    }
    guard !request.headers.keys.contains("transfer-encoding"),
      !request.headers.keys.contains("content-transfer-encoding")
    else { return .response(failure(400)) }
    if let lengths = request.headers["content-length"] {
      guard lengths.count == 1, let declared = Int(lengths[0]), declared == request.body.count
      else { return .response(failure(400)) }
    }
    guard let target = parseTarget(request.uri), target.query.isEmpty,
      target.path == "/api/v1/web/report-follow"
    else { return .response(failure(400)) }
    guard request.method.uppercased() == "POST" else { return .response(failure(405)) }
    guard let sessionID = authenticatedSession(request.headers) else {
      return .response(failure(401))
    }
    guard request.headers["content-type"]?.count == 1,
      request.headers["content-type"]?.first == "application/json"
    else { return .response(failure(415)) }
    guard let body = StrictWebRequestBody.decode(request.body, allowsSecret: false) else {
      return .response(failure(400))
    }
    guard let webCapabilities else { return .response(failure(503)) }
    let context = webCapabilityContext(sessionID: sessionID)
    do {
      guard
        try webCapabilities.descriptors(in: context)
          .first(where: { $0.id == body.operationID })?.interaction == .reportStream
      else { return .response(failure(400)) }
      let stream = try await webCapabilities.reportStream(
        WebCapabilityRequest(
          capabilityID: body.operationID,
          fields: body.fields,
          exactWorldID: body.worldID,
          sessionID: sessionID,
          interaction: .reportStream
        ),
        in: context
      )
      guard let sessionExpiry = sessions.expiration(for: sessionID) else {
        return .response(failure(401))
      }
      var headers = securityHeaders
      headers["content-type"] = "text/plain; charset=utf-8"
      headers["transfer-encoding"] = "chunked"
      return .stream(
        headers: headers,
        body: sessionBoundStream(stream, sessionID: sessionID, expiresAt: sessionExpiry)
      )
    } catch {
      return .response(webCapabilityFailure(error))
    }
  }

  private func routeInternal(_ request: KhorosWebRequest) -> KhorosWebResponse {
    guard request.uri.utf8.count <= webMaximumRequestLineCharacters,
      request.body.count <= webMaximumRequestBytes
    else { return failure(413) }
    guard headerBytes(request.headers) <= webMaximumHeaderBytes else { return failure(431) }
    guard validHost(request.headers), validOrigin(request.headers, method: request.method) else {
      return failure(400)
    }
    guard !request.headers.keys.contains(where: { $0 == "transfer-encoding" }),
      !request.headers.keys.contains(where: { $0 == "content-transfer-encoding" })
    else { return failure(400) }
    if let lengths = request.headers["content-length"] {
      guard lengths.count == 1, let declared = Int(lengths[0]), declared >= 0,
        declared == request.body.count
      else { return failure(400) }
    }

    guard let target = parseTarget(request.uri) else { return failure(400) }
    let method = request.method.uppercased()
    if method == "POST" && target.path == "/api/v1/session" {
      return session(request: request, target: target)
    }
    if method == "POST" {
      guard authenticatedSession(request.headers) != nil else { return failure(401) }
      switch target.path {
      case "/api/v1/worlds":
        return createWorld(request: request, target: target)
      case "/api/v1/world-agents":
        return addWorldAgent(request: request, target: target)
      case "/api/v1/world-command/completions", "/api/v1/world-command/execute":
        return failure(503)
      case "/api/v1/web/completions", "/api/v1/web/execute",
        "/api/v1/web/prepare", "/api/v1/web/commit",
        "/api/v1/web/secret", "/api/v1/web/agent-controller",
        "/api/v1/web/report-follow":
        return failure(503)
      default:
        return failure(405)
      }
    }
    guard method == "GET" || method == "HEAD" else { return failure(405) }
    guard request.body.isEmpty else { return failure(400) }
    if let lengths = request.headers["content-length"], lengths[0] != "0" {
      return failure(400)
    }
    let headOnly = method == "HEAD"

    if let asset = assets.asset(for: target.path) {
      guard target.query.isEmpty || validWebDeepLink(target) else { return failure(400) }
      return response(
        statusCode: 200,
        contentType: asset.contentType,
        body: asset.data,
        headOnly: headOnly,
        extraHeaders: target.path == "/"
          ? [webListenerMarkerHeader: webListenerMarkerValue]
          : [:]
      )
    }
    guard target.path.hasPrefix("/api/v1/") else { return failure(404) }
    guard let sessionID = authenticatedSession(request.headers) else { return failure(401) }
    guard
      target.query.isEmpty || target.path == "/api/v1/world"
        || target.path == "/api/v1/object" || target.path == "/api/v1/world-agents"
    else { return failure(400) }
    switch target.path {
    case "/api/v1/web/capabilities":
      return webCapabilityCatalog(sessionID: sessionID, headOnly: headOnly)
    case "/api/v1/agents", "/api/v1/inventory",
      "/api/v1/packages", "/api/v1/templates",
      "/api/v1/settings":
      guard target.query.isEmpty else { return failure(400) }
      return webProjection(target.path, headOnly: headOnly)
    case "/api/v1/world":
      return world(target: target, headOnly: headOnly)
    case "/api/v1/object":
      return object(target: target, headOnly: headOnly)
    case "/api/v1/world-agents":
      return worldAgentOptions(target: target, headOnly: headOnly)
    case "/api/v1/worlds":
      return failure(405)
    case "/api/v1/world-command/completions", "/api/v1/world-command/execute":
      return failure(405)
    case "/api/v1/web/completions", "/api/v1/web/execute",
      "/api/v1/web/prepare", "/api/v1/web/commit",
      "/api/v1/web/secret", "/api/v1/web/agent-controller",
      "/api/v1/web/report-follow":
      return failure(405)
    default:
      return failure(404)
    }
  }

  private func asyncRoute(_ request: KhorosWebRequest) async -> KhorosWebResponse {
    guard request.uri.utf8.count <= webMaximumRequestLineCharacters,
      request.body.count <= webMaximumRequestBytes
    else { return failure(413) }
    guard headerBytes(request.headers) <= webMaximumHeaderBytes else { return failure(431) }
    guard validHost(request.headers), validOrigin(request.headers, method: request.method) else {
      return failure(400)
    }
    guard !request.headers.keys.contains(where: { $0 == "transfer-encoding" }),
      !request.headers.keys.contains(where: { $0 == "content-transfer-encoding" })
    else { return failure(400) }
    if let lengths = request.headers["content-length"] {
      guard lengths.count == 1, let declared = Int(lengths[0]), declared >= 0,
        declared == request.body.count
      else { return failure(400) }
    }
    guard let target = parseTarget(request.uri), target.query.isEmpty else {
      return failure(400)
    }
    guard request.method.uppercased() == "POST" else { return failure(405) }
    guard let sessionID = authenticatedSession(request.headers) else { return failure(401) }
    guard request.headers["content-type"]?.count == 1,
      request.headers["content-type"]?.first == "application/json"
    else { return failure(415) }
    if target.path.hasPrefix("/api/v1/web/") {
      return await webCapabilityRoute(
        request,
        target: target,
        sessionID: sessionID
      )
    }
    guard request.body.count <= webMaximumCommandRequestBytes else { return failure(413) }
    guard let body = StrictWorldCommandBody.decode(request.body),
      InventoryIdentity.isValid(body.worldID),
      body.worldID == body.worldID.lowercased(),
      body.source.count <= webMaximumCommandSourceCharacters,
      !body.source.contains(where: { $0.isNewline || $0 == "\0" })
    else { return failure(400) }
    guard let commandConsole else { return failure(503) }

    let commandRequest = WorldCommandConsoleRequest(
      layout: projection.layout,
      worldID: body.worldID,
      source: body.source
    )
    do {
      switch target.path {
      case "/api/v1/world-command/completions":
        return try json(await commandConsole.completions(for: commandRequest))
      case "/api/v1/world-command/execute":
        guard !body.source.trimmingCharacters(in: .whitespaces).isEmpty else {
          return failure(400)
        }
        return try json(await commandConsole.execute(commandRequest))
      default:
        return failure(404)
      }
    } catch WorldCommandConsoleServiceError.busy {
      return failure(409)
    } catch WorldCommandConsoleServiceError.invalidContext {
      return failure(400)
    } catch {
      return failure(503)
    }
  }

  private func webCapabilityCatalog(
    sessionID: String,
    headOnly: Bool
  ) -> KhorosWebResponse {
    guard let webCapabilities else { return failure(503) }
    do {
      let descriptors = try webCapabilities.descriptors(
        in: webCapabilityContext(sessionID: sessionID)
      )
      guard descriptors.map(\.id).count == Set(descriptors.map(\.id)).count else {
        return failure(503)
      }
      let catalog = WebCapabilityCatalogResponse(
        capabilities: descriptors.map(WebCapabilityDescriptorResponse.init)
      )
      return try json(catalog, headOnly: headOnly)
    } catch {
      return failure(503)
    }
  }

  private func webProjection(
    _ path: String,
    headOnly: Bool
  ) -> KhorosWebResponse {
    do {
      switch path {
      case "/api/v1/agents":
        return try json(webProjections.agents(), headOnly: headOnly)
      case "/api/v1/inventory":
        return try json(webProjections.inventory(), headOnly: headOnly)
      case "/api/v1/packages":
        return try json(webProjections.packages(), headOnly: headOnly)
      case "/api/v1/templates":
        return try json(webProjections.templates(), headOnly: headOnly)
      case "/api/v1/settings":
        return try json(webProjections.settings(), headOnly: headOnly)
      default:
        return failure(404)
      }
    } catch {
      return failure(503)
    }
  }

  private func webCapabilityRoute(
    _ request: KhorosWebRequest,
    target: ParsedTarget,
    sessionID: String
  ) async -> KhorosWebResponse {
    guard request.body.count <= webMaximumCapabilityRequestBytes else {
      return failure(413)
    }
    guard request.headers["content-type"]?.count == 1,
      request.headers["content-type"]?.first == "application/json"
    else { return failure(415) }
    guard let webCapabilities else { return failure(503) }
    let context = webCapabilityContext(sessionID: sessionID)
    do {
      switch target.path {
      case "/api/v1/web/completions":
        guard let body = StrictWebCompletionBody.decode(request.body) else {
          return failure(400)
        }
        let values = try await webCapabilities.completions(
          for: WebCapabilityCompletionRequest(
            capabilityID: body.operationID,
            fieldID: body.fieldID,
            source: body.source,
            fields: body.fields,
            exactWorldID: body.worldID
          ),
          in: context
        )
        return try json(WebCompletionResponse(values: values))
      case "/api/v1/web/commit":
        guard let body = StrictWebCommitBody.decode(request.body), body.confirmed else {
          return failure(400)
        }
        let result = try await webCapabilities.commit(
          WebCapabilityCommitRequest(planID: body.planID, sessionID: sessionID),
          in: context
        )
        return try json(result)
      case "/api/v1/web/execute", "/api/v1/web/prepare",
        "/api/v1/web/secret", "/api/v1/web/agent-controller":
        guard
          let body = StrictWebRequestBody.decode(
            request.body,
            allowsSecret: target.path == "/api/v1/web/secret"
          )
        else { return failure(400) }
        guard
          let mode = try webCapabilities.descriptors(in: context)
            .first(where: { $0.id == body.operationID })?.interaction
        else { return failure(400) }
        switch target.path {
        case "/api/v1/web/prepare":
          guard mode == .confirmation else { return failure(400) }
        case "/api/v1/web/secret":
          guard mode == .secret else { return failure(400) }
        case "/api/v1/web/agent-controller":
          guard mode == .agentController else { return failure(400) }
        default:
          guard ![.confirmation, .secret, .agentController, .reportStream].contains(mode)
          else { return failure(400) }
        }
        let capabilityRequest = WebCapabilityRequest(
          capabilityID: body.operationID,
          fields: body.fields,
          exactWorldID: body.worldID,
          sessionID: sessionID,
          secret: body.secret.map { Data($0.utf8) },
          interaction: mode
        )
        if mode == .confirmation {
          let plan = try await webCapabilities.prepare(capabilityRequest, in: context)
          return try json(WebCapabilityPlanResponse(plan))
        }
        let result = try await webCapabilities.execute(capabilityRequest, in: context)
        if try isDownloadCapability(body.operationID, context: context) {
          guard result.accepted else { return try json(result) }
          guard !result.outputTruncated else {
            return try json(truncatedDownloadFailure(result))
          }
          let filename = "mikrokhoros-world-export.txt"
          return response(
            statusCode: 200,
            contentType: "application/octet-stream",
            body: Data(result.standardOutput.utf8),
            extraHeaders: ["content-disposition": "attachment; filename=\"\(filename)\""]
          )
        }
        return try json(result)
      default:
        return failure(404)
      }
    } catch {
      return webCapabilityFailure(error)
    }
  }

  private func isDownloadCapability(
    _ id: String,
    context: WebCapabilityContext
  ) throws -> Bool {
    guard let webCapabilities else { return false }
    return try webCapabilities.descriptors(in: context).first(where: { $0.id == id })?
      .interaction == .download
  }

  private func truncatedDownloadFailure(
    _ result: WebCapabilityExecutionResult
  ) -> WebCapabilityExecutionResult {
    WebCapabilityExecutionResult(
      accepted: false,
      displayCommand: result.displayCommand,
      standardError:
        "The private export exceeds the browser transfer limit. "
        + "Run the displayed command in the local CLI to write the complete export.",
      exitStatus: 1,
      outputTruncated: true,
      category: .failure
    )
  }

  private func sessionBoundStream(
    _ source: AsyncThrowingStream<String, Error>,
    sessionID: String,
    expiresAt: Date
  ) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let relay = Task { [sessions] in
        await withTaskGroup(of: Void.self) { group in
          group.addTask {
            do {
              for try await chunk in source {
                guard !Task.isCancelled, sessions.contains(sessionID) else { break }
                continuation.yield(chunk)
              }
            } catch {
              continuation.finish(throwing: error)
            }
          }
          group.addTask {
            let interval = max(0, expiresAt.timeIntervalSinceNow)
            do { try await Task.sleep(for: .seconds(interval)) } catch { return }
          }
          _ = await group.next()
          group.cancelAll()
        }
        continuation.finish()
      }
      continuation.onTermination = { @Sendable _ in relay.cancel() }
    }
  }

  private func webCapabilityContext(sessionID: String) -> WebCapabilityContext {
    stateLock.withLock {
      WebCapabilityContext(
        layout: projection.layout,
        sessionID: sessionID,
        hostState: WebHostState(
          lifecycle: .running,
          address: "127.0.0.1",
          port: Int(expectedHost.split(separator: ":").last ?? "")
        )
      )
    }
  }

  private func webCapabilityFailure(_ error: Error) -> KhorosWebResponse {
    guard let error = error as? WebCapabilityError else { return failure(503) }
    switch error {
    case .invalidSession:
      return failure(401)
    case .busy:
      return failure(409)
    case .expiredPlan, .replayedPlan, .tamperedPlan, .invalidPlan:
      return failure(410)
    case .unavailable:
      return failure(503)
    case .unknownCapability, .invalidField, .missingField, .duplicateField, .invalidValue,
      .invalidWorldContext, .globalOptionsRejected, .wrongInteraction, .secretRequired,
      .secretNotAllowed:
      return failure(400)
    }
  }

  private func session(request: KhorosWebRequest, target: ParsedTarget) -> KhorosWebResponse {
    guard target.query.isEmpty,
      request.headers["content-type"]?.count == 1,
      request.headers["content-type"]?.first == "application/json",
      request.body.count <= 512,
      let token = StrictSessionBody.decode(request.body),
      token.count == 64,
      token.allSatisfy(\.isHexDigit),
      let cookie = sessions.consumeBootstrapToken(token)
    else { return failure(401) }
    let body = Data(#"{"ok":true}"#.utf8)
    let cookieName = stateLock.withLock { expectedSessionCookieName }
    return response(
      statusCode: 200,
      contentType: "application/json",
      body: body,
      extraHeaders: [
        "set-cookie": "\(cookieName)=\(cookie); Path=/; HttpOnly; SameSite=Strict"
      ]
    )
  }

  private func createWorld(
    request: KhorosWebRequest,
    target: ParsedTarget
  ) -> KhorosWebResponse {
    guard target.query.isEmpty else { return failure(400) }
    guard request.body.count <= webMaximumWorldCreationBytes else { return failure(413) }
    guard request.headers["content-type"]?.count == 1,
      request.headers["content-type"]?.first == "application/json"
    else { return failure(415) }
    guard let name = StrictWorldCreationBody.decode(request.body) else { return failure(400) }
    do {
      let result = try worldCreation.createBareWorld(name: name)
      return try json(result, statusCode: 201)
    } catch WorldCreationError.invalidName {
      return failure(400)
    } catch {
      return failure(503)
    }
  }

  private func addWorldAgent(
    request: KhorosWebRequest,
    target: ParsedTarget
  ) -> KhorosWebResponse {
    guard target.query.isEmpty else { return failure(400) }
    guard request.body.count <= webMaximumAgentAdditionBytes else { return failure(413) }
    guard request.headers["content-type"]?.count == 1,
      request.headers["content-type"]?.first == "application/json"
    else { return failure(415) }
    guard let body = StrictWorldAgentAdditionBody.decode(request.body) else {
      return failure(400)
    }
    do {
      let result = try agentPresence.addAgent(
        worldID: body.worldID,
        agentID: body.agentID,
        coordinate: Coordinate(x: body.x, y: body.y),
        autoAdapt: body.autoAdapt
      )
      return try json(result, statusCode: 201)
    } catch WorldAgentPresenceError.invalidSelector {
      return failure(400)
    } catch WorldAgentPresenceError.alreadyPresent,
      WorldAgentPresenceError.assignedElsewhere
    {
      return failure(409)
    } catch {
      return failure(503)
    }
  }

  private func world(target: ParsedTarget, headOnly: Bool) -> KhorosWebResponse {
    guard Set(target.allowedQueryKeys).isSubset(of: ["container", "focus", "world"]),
      target.queryValues.allSatisfy({ $0.value.count == 1 })
    else { return failure(400) }
    let world = target.queryValues["world"]?.first
    let container = target.queryValues["container"]?.first
    let focus = target.queryValues["focus"]?.first
    guard [world, container, focus].compactMap({ $0 }).allSatisfy(InventoryIdentity.isValid) else {
      return failure(400)
    }
    do {
      let snapshot = try projection.snapshotExact(world: world, container: container, focus: focus)
      return try json(snapshot, headOnly: headOnly)
    } catch WorldProjectionError.invalidSelector {
      return failure(400)
    } catch {
      return failure(503)
    }
  }

  private func object(target: ParsedTarget, headOnly: Bool) -> KhorosWebResponse {
    guard target.allowedQueryKeys == ["object", "world"],
      target.queryValues.allSatisfy({ $0.value.count == 1 }),
      let world = target.queryValues["world"]?.first,
      let object = target.queryValues["object"]?.first,
      InventoryIdentity.isValid(world), InventoryIdentity.isValid(object)
    else { return failure(400) }
    do {
      let snapshot = try projection.objectSnapshot(world: world, object: object)
      return try json(snapshot, headOnly: headOnly)
    } catch WorldProjectionError.invalidSelector {
      return failure(404)
    } catch {
      return failure(503)
    }
  }

  private func worldAgentOptions(
    target: ParsedTarget,
    headOnly: Bool
  ) -> KhorosWebResponse {
    guard target.allowedQueryKeys == ["world"],
      target.queryValues["world"]?.count == 1,
      let worldID = target.queryValues["world"]?.first,
      InventoryIdentity.isValid(worldID)
    else { return failure(400) }
    do {
      return try json(agentPresence.options(worldID: worldID), headOnly: headOnly)
    } catch WorldAgentPresenceError.invalidSelector {
      return failure(400)
    } catch {
      return failure(503)
    }
  }

  private func json<Value: Encodable>(
    _ value: Value,
    statusCode: Int = 200,
    headOnly: Bool = false
  ) throws -> KhorosWebResponse {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let body = try encoder.encode(value)
    return response(
      statusCode: statusCode,
      contentType: "application/json",
      body: body,
      headOnly: headOnly
    )
  }

  private func response(
    statusCode: Int,
    contentType: String,
    body: Data,
    headOnly: Bool = false,
    extraHeaders: [String: String] = [:]
  ) -> KhorosWebResponse {
    var headers = securityHeaders
    headers["content-type"] = contentType
    headers["content-length"] = String(body.count)
    headers.merge(extraHeaders) { _, new in new }
    return KhorosWebResponse(
      statusCode: statusCode,
      headers: headers,
      body: headOnly ? Data() : body
    )
  }

  private func failure(_ statusCode: Int) -> KhorosWebResponse {
    let body = Data(#"{"error":"request_rejected"}"#.utf8)
    return response(
      statusCode: statusCode,
      contentType: "application/json",
      body: body
    )
  }

  fileprivate func internalFailure() -> KhorosWebResponse {
    failure(503)
  }

  private var securityHeaders: [String: String] {
    [
      "cache-control": "no-store",
      "content-security-policy":
        "default-src 'none'; script-src 'self'; style-src 'self'; font-src 'self'; "
        + "img-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; "
        + "form-action 'none'; object-src 'none'",
      "cross-origin-opener-policy": "same-origin",
      "cross-origin-resource-policy": "same-origin",
      "permissions-policy": "camera=(), microphone=(), geolocation=(), payment=()",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
    ]
  }

  private func validHost(_ headers: [String: [String]]) -> Bool {
    stateLock.lock()
    let expected = expectedHost
    stateLock.unlock()
    return headers["host"]?.count == 1 && headers["host"]?.first == expected
  }

  private func validOrigin(_ headers: [String: [String]], method: String) -> Bool {
    guard let values = headers["origin"] else { return method.uppercased() != "POST" }
    guard values.count == 1 else { return false }
    stateLock.lock()
    let expected = expectedOrigin
    stateLock.unlock()
    return values[0] == expected
  }

  private func authenticatedSession(_ headers: [String: [String]]) -> String? {
    guard let values = headers["cookie"], values.count == 1 else { return nil }
    let cookieName = stateLock.withLock { expectedSessionCookieName }
    var sessionValue: String?
    for piece in values[0].split(separator: ";", omittingEmptySubsequences: true) {
      let pair = piece.trimmingCharacters(in: .whitespaces)
        .split(separator: "=", maxSplits: 1)
      guard pair.count == 2 else { continue }
      guard pair[0] == cookieName else { continue }
      guard sessionValue == nil else { return nil }
      sessionValue = String(pair[1])
    }
    guard let value = sessionValue,
      value.count == 64,
      value.allSatisfy(\.isHexDigit),
      sessions.contains(value)
    else { return nil }
    return value
  }

  private func parseTarget(_ uri: String) -> ParsedTarget? {
    guard !uri.isEmpty, !uri.contains("#"), uri.first == "/" else { return nil }
    let parts = uri.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
    let rawPath = String(parts[0])
    guard !rawPath.isEmpty, !rawPath.contains("\\"),
      !rawPath.lowercased().contains("%2f"),
      !rawPath.lowercased().contains("%5c"),
      !rawPath.lowercased().contains("%00"),
      let path = rawPath.removingPercentEncoding,
      path.unicodeScalars.allSatisfy({ $0.value >= 0x20 }),
      !path.contains("//"),
      !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    else { return nil }
    let rawQuery = parts.count == 2 ? String(parts[1]) : ""
    var queryValues: [String: [String]] = [:]
    if !rawQuery.isEmpty {
      for component in rawQuery.split(separator: "&", omittingEmptySubsequences: false) {
        let pair = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard pair.count == 2, let key = String(pair[0]).removingPercentEncoding,
          let value = String(pair[1]).removingPercentEncoding,
          !key.isEmpty, !key.contains("."), !value.contains(where: \.isNewline)
        else { return nil }
        queryValues[key, default: []].append(value)
      }
    }
    return ParsedTarget(path: path, queryValues: queryValues)
  }

  /// Client routes are allowed only on the root document. Static assets retain
  /// their query-free contract so route parameters cannot broaden asset serving.
  private func validWebDeepLink(_ target: ParsedTarget) -> Bool {
    guard target.path == "/", !target.queryValues.isEmpty else { return false }
    for (key, values) in target.queryValues {
      guard webRouteKeys.contains(key), values.count == 1,
        let value = values.first,
        !value.isEmpty,
        value.count <= webMaximumRouteValueCharacters,
        !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
      else { return false }
      if key == "view" && !webViews.contains(value) { return false }
      if webRouteIdentityKeys.contains(key), !InventoryIdentity.isValid(value) {
        return false
      }
    }
    return true
  }

  private func headerBytes(_ headers: [String: [String]]) -> Int {
    headers.reduce(0) { total, pair in
      total + pair.key.utf8.count + pair.value.reduce(0) { $0 + $1.utf8.count }
    }
  }
}

public typealias WebRouter = KhorosWebRouter
public typealias WebRequest = KhorosWebRequest
public typealias WebResponse = KhorosWebResponse

public final class WebAssetStore: @unchecked Sendable {
  public struct Asset: Sendable {
    public let data: Data
    public let contentType: String

    public init(data: Data, contentType: String) {
      self.data = data
      self.contentType = contentType
    }
  }

  private let bundle: Bundle
  private let phosphorIcons: [String: String] = [
    "archive": "ph-archive",
    "arrow-elbow-down-left": "ph-arrow-elbow-down-left",
    "arrow-left": "ph-arrow-left",
    "arrow-square-out": "ph-arrow-square-out",
    "bell": "ph-bell",
    "caret-down": "ph-caret-down",
    "check": "ph-check",
    "circle-notch": "ph-circle-notch",
    "crosshair": "ph-crosshair",
    "cube": "ph-cube",
    "dots-three": "ph-dots-three",
    "eye": "ph-eye",
    "file-text": "ph-file-text",
    "gear-six": "ph-gear-six",
    "globe": "ph-globe",
    "info": "ph-info",
    "magnifying-glass": "ph-magnifying-glass",
    "magnifying-glass-minus": "ph-magnifying-glass-minus",
    "magnifying-glass-plus": "ph-magnifying-glass-plus",
    "package": "ph-package",
    "plus": "ph-plus",
    "push-pin": "ph-push-pin",
    "shield": "ph-shield",
    "sidebar-simple": "ph-sidebar-simple",
    "user-plus": "ph-user-plus",
    "x": "ph-x",
  ]
  private let identityShapes: [String: String] = [
    "heart": "identity-heart-fill",
    "hexagon": "identity-hexagon-fill",
    "pentagon": "identity-pentagon-fill",
    "seal": "identity-seal-fill",
    "shield": "identity-shield-fill",
    "square": "identity-square-fill",
    "star": "identity-star-fill",
    "triangle": "identity-triangle-fill",
  ]

  public init() {
    bundle = .module
  }

  public init(bundle: Bundle) {
    self.bundle = bundle
  }

  public func asset(for path: String) -> Asset? {
    let resource: (name: String, extension: String, subdirectory: String?, type: String)?
    switch path {
    case "/": resource = ("index", "html", nil, "text/html; charset=utf-8")
    case "/styles.css": resource = ("styles", "css", nil, "text/css; charset=utf-8")
    case "/app.js": resource = ("app", "js", nil, "text/javascript; charset=utf-8")
    case "/fonts/google-sans-flex.woff2":
      resource = ("google-sans-flex-latin", "woff2", "fonts", "font/woff2")
    case "/fonts/google-sans-flex-latin.woff2":
      resource = ("google-sans-flex-latin", "woff2", "fonts", "font/woff2")
    case "/fonts/google-sans-flex-latin-ext.woff2":
      resource = ("google-sans-flex-latin-ext", "woff2", "fonts", "font/woff2")
    case "/fonts/google-sans-flex-vietnamese.woff2":
      resource = ("google-sans-flex-vietnamese", "woff2", "fonts", "font/woff2")
    default:
      let phosphorPrefix = "/icons/phosphor/"
      let identityPrefix = "/identity-shapes/"
      if path.hasPrefix(phosphorPrefix), path.hasSuffix(".svg") {
        let name = String(path.dropFirst(phosphorPrefix.count).dropLast(4))
        guard let resourceName = phosphorIcons[name] else { return nil }
        resource = (resourceName, "svg", "icons/phosphor", "image/svg+xml")
      } else if path.hasPrefix(identityPrefix), path.hasSuffix(".svg") {
        let name = String(path.dropFirst(identityPrefix.count).dropLast(4))
        guard let resourceName = identityShapes[name] else { return nil }
        resource = (resourceName, "svg", "identity-shapes", "image/svg+xml")
      } else {
        return nil
      }
    }
    guard let resource, let url = resourceURL(resource), let data = try? Data(contentsOf: url)
    else { return nil }
    return Asset(data: data, contentType: resource.type)
  }

  private func resourceURL(
    _ resource: (name: String, extension: String, subdirectory: String?, type: String)
  ) -> URL? {
    // SwiftPM may flatten processed resources into the bundle root. Keep the
    // subdirectory lookup as a fallback for manually assembled bundles and
    // older SwiftPM layouts, while resolving the packaged product reliably.
    bundle.url(
      forResource: resource.name,
      withExtension: resource.extension,
      subdirectory: nil
    )
      ?? resource.subdirectory.flatMap {
        bundle.url(
          forResource: resource.name,
          withExtension: resource.extension,
          subdirectory: $0
        )
      }
  }
}

public final class WebSessionStore: @unchecked Sendable {
  private let lock = NSLock()
  private var bootstrapToken: (value: String, expiresAt: Date)?
  private var sessionTokens: [String: Date] = [:]

  public init() {}

  public func installBootstrapToken(now: Date = Date()) -> String {
    let token = WebRandomToken.make()
    lock.lock()
    bootstrapToken = (token, now.addingTimeInterval(webTokenLifetime))
    lock.unlock()
    return token
  }

  public func consumeBootstrapToken(_ value: String, now: Date = Date()) -> String? {
    lock.lock()
    defer { lock.unlock() }
    guard let bootstrapToken, bootstrapToken.value == value, bootstrapToken.expiresAt >= now else {
      return nil
    }
    self.bootstrapToken = nil
    let session = WebRandomToken.make()
    sessionTokens[session] = now.addingTimeInterval(8 * 60 * 60)
    return session
  }

  public func contains(_ value: String, now: Date = Date()) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard let expiresAt = sessionTokens[value], expiresAt >= now else {
      sessionTokens.removeValue(forKey: value)
      return false
    }
    return true
  }

  public func expiration(for value: String, now: Date = Date()) -> Date? {
    lock.lock()
    defer { lock.unlock() }
    guard let expiresAt = sessionTokens[value], expiresAt >= now else {
      sessionTokens.removeValue(forKey: value)
      return nil
    }
    return expiresAt
  }

  public func invalidateAll() {
    lock.lock()
    bootstrapToken = nil
    sessionTokens.removeAll()
    lock.unlock()
  }
}

private enum WebRandomToken {
  static func make() -> String {
    var generator = SystemRandomNumberGenerator()
    var bytes = [UInt8](repeating: 0, count: 32)
    for index in bytes.indices { bytes[index] = generator.next() }
    return bytes.map { String(format: "%02x", $0) }.joined()
  }
}

private struct WebCapabilityCatalogResponse: Encodable {
  let capabilities: [WebCapabilityDescriptorResponse]
}

private struct WebCapabilityDescriptorResponse: Encodable {
  let id: String
  let command: String
  let summary: String
  let view: String
  let section: String
  let scope: String
  let mode: String
  let enabled: Bool
  let fields: [WebCapabilityFieldResponse]
  let refreshTargets: [String]
  let successTestID: String
  let failureTestID: String

  init(_ descriptor: WebCapabilityDescriptor) {
    id = descriptor.id
    command = descriptor.syntax
    summary = descriptor.summary
    view = descriptor.placement.rawValue
    section = descriptor.section
    scope = descriptor.scope.rawValue
    mode = descriptor.interaction.rawValue
    enabled = descriptor.enabled
    fields = descriptor.fields.map(WebCapabilityFieldResponse.init)
    refreshTargets = descriptor.refreshTargets.map(\.rawValue)
    successTestID = descriptor.successTestID
    failureTestID = descriptor.failureTestID
  }
}

private struct WebCapabilityFieldResponse: Encodable {
  let id: String
  let label: String
  let help: String
  let syntax: String
  let cardinality: String
  let completion: String
  let historyPolicy: String
  let defaultValue: String?
  let choices: [String]

  init(_ field: WebCapabilityField) {
    id = field.id
    label = field.label
    help = field.help
    switch field.syntax {
    case .positional:
      syntax = "positional"
    case .option(let spelling):
      syntax = "option \(spelling)"
    case .flag(let spelling):
      syntax = "flag \(spelling)"
    }
    cardinality = field.cardinality.rawValue
    completion = field.completion.canonicalKind
    historyPolicy = field.historyPolicy.rawValue
    defaultValue = field.safeDefault
    if case .choices(let values) = field.completion { choices = values } else { choices = [] }
  }
}

private struct WebCapabilityPlanResponse: Encodable {
  let planID: String
  let operationID: String
  let expiresAt: Date
  let command: String
  let summary: String

  init(_ plan: WebCapabilityPlan) {
    planID = plan.planID
    operationID = plan.capabilityID
    expiresAt = plan.expiresAt
    command = plan.commandSummary
    summary = plan.consequenceSummary
  }
}

private struct WebCompletionResponse: Encodable {
  let values: [WebCapabilityCompletionValue]
}

private struct StrictWebRequestBody {
  let operationID: String
  let worldID: String?
  let fields: [String: [String]]
  let secret: String?

  static func decode(_ data: Data, allowsSecret: Bool) -> StrictWebRequestBody? {
    guard let object = StrictJSONDocument.object(data) else { return nil }
    var allowed = Set(["fields", "operationID", "worldID"])
    if allowsSecret { allowed.insert("secret") }
    guard Set(object.keys).isSubset(of: allowed),
      let operationID = boundedString(object["operationID"], maximum: 256),
      let fields = fields(object["fields"])
    else { return nil }
    let worldID: String?
    if let value = object["worldID"] {
      guard let decoded = boundedString(value, maximum: 64) else { return nil }
      worldID = decoded
    } else {
      worldID = nil
    }
    let secret: String?
    if let value = object["secret"] {
      guard allowsSecret, let decoded = boundedString(value, maximum: 16_384) else { return nil }
      secret = decoded
    } else {
      secret = nil
    }
    return StrictWebRequestBody(
      operationID: operationID,
      worldID: worldID,
      fields: fields,
      secret: secret
    )
  }

  fileprivate static func boundedString(_ value: Any?, maximum: Int) -> String? {
    guard let value = value as? String,
      !value.isEmpty,
      value.count <= maximum,
      !value.contains("\0")
    else { return nil }
    return value
  }

  fileprivate static func fields(_ value: Any?) -> [String: [String]]? {
    guard let value else { return [:] }
    guard let object = value as? [String: Any], object.count <= 128 else { return nil }
    var result: [String: [String]] = [:]
    for (key, raw) in object {
      guard !key.isEmpty, key.count <= 128,
        let values = raw as? [Any], values.count <= 64
      else { return nil }
      var decoded: [String] = []
      for item in values {
        guard let string = item as? String,
          string.count <= 16_384,
          !string.contains("\0")
        else { return nil }
        decoded.append(string)
      }
      result[key] = decoded
    }
    return result
  }
}

private struct StrictWebCompletionBody {
  let operationID: String
  let fieldID: String
  let source: String
  let worldID: String?
  let fields: [String: [String]]

  static func decode(_ data: Data) -> StrictWebCompletionBody? {
    guard let object = StrictJSONDocument.object(data),
      Set(object.keys).isSubset(of: ["fieldID", "fields", "operationID", "source", "worldID"]),
      let operationID = StrictWebRequestBody.boundedString(
        object["operationID"], maximum: 256
      ),
      let fieldID = StrictWebRequestBody.boundedString(object["fieldID"], maximum: 128),
      let fields = StrictWebRequestBody.fields(object["fields"])
    else { return nil }
    let source: String
    if let raw = object["source"] {
      guard let decoded = raw as? String, decoded.count <= 1_024, !decoded.contains("\0") else {
        return nil
      }
      source = decoded
    } else {
      source = ""
    }
    let worldID: String?
    if let raw = object["worldID"] {
      guard let decoded = StrictWebRequestBody.boundedString(raw, maximum: 64) else {
        return nil
      }
      worldID = decoded
    } else {
      worldID = nil
    }
    return StrictWebCompletionBody(
      operationID: operationID,
      fieldID: fieldID,
      source: source,
      worldID: worldID,
      fields: fields
    )
  }
}

private struct StrictWebCommitBody {
  let planID: String
  let confirmed: Bool

  static func decode(_ data: Data) -> StrictWebCommitBody? {
    guard let object = StrictJSONDocument.object(data),
      Set(object.keys) == ["confirmed", "planID"],
      let planID = StrictWebRequestBody.boundedString(object["planID"], maximum: 64),
      let confirmed = object["confirmed"] as? Bool
    else { return nil }
    return StrictWebCommitBody(planID: planID, confirmed: confirmed)
  }
}

/// Validates every JSON object before Foundation materializes it so literal or
/// escaped duplicate members are rejected at every nesting depth.
private struct StrictJSONDocument {
  private static let maximumDepth = 64
  private static let maximumNodes = 4_096

  private let bytes: [UInt8]
  private var index = 0
  private var remainingNodes = Self.maximumNodes

  private init(_ data: Data) { bytes = Array(data) }

  static func object(_ data: Data) -> [String: Any]? {
    var parser = StrictJSONDocument(data)
    parser.skipWhitespace()
    guard parser.value(depth: 0), parser.finished else { return nil }
    guard let value = try? JSONSerialization.jsonObject(with: data),
      let object = value as? [String: Any]
    else { return nil }
    return object
  }

  private var finished: Bool {
    var copy = self
    copy.skipWhitespace()
    return copy.index == copy.bytes.count
  }

  private mutating func value(depth: Int) -> Bool {
    skipWhitespace()
    guard depth <= Self.maximumDepth, index < bytes.count, remainingNodes > 0 else {
      return false
    }
    remainingNodes -= 1
    switch bytes[index] {
    case 0x7B: return object(depth: depth)
    case 0x5B: return array(depth: depth)
    case 0x22: return jsonString() != nil
    case 0x74: return consumeSequence([0x74, 0x72, 0x75, 0x65])
    case 0x66: return consumeSequence([0x66, 0x61, 0x6C, 0x73, 0x65])
    case 0x6E: return consumeSequence([0x6E, 0x75, 0x6C, 0x6C])
    default: return number()
    }
  }

  private mutating func object(depth: Int) -> Bool {
    guard consume(0x7B) else { return false }
    skipWhitespace()
    var keys: Set<String> = []
    if consume(0x7D) { return true }
    while true {
      guard let key = jsonString(), keys.insert(key).inserted else { return false }
      skipWhitespace()
      guard consume(0x3A), value(depth: depth + 1) else { return false }
      skipWhitespace()
      if consume(0x7D) { return true }
      guard consume(0x2C) else { return false }
      skipWhitespace()
    }
  }

  private mutating func array(depth: Int) -> Bool {
    guard consume(0x5B) else { return false }
    skipWhitespace()
    if consume(0x5D) { return true }
    while true {
      guard value(depth: depth + 1) else { return false }
      skipWhitespace()
      if consume(0x5D) { return true }
      guard consume(0x2C) else { return false }
      skipWhitespace()
    }
  }

  private mutating func number() -> Bool {
    let start = index
    _ = consume(0x2D)
    guard index < bytes.count else {
      index = start
      return false
    }
    if consume(0x30) {
      if index < bytes.count, (0x30...0x39).contains(bytes[index]) {
        index = start
        return false
      }
    } else {
      guard index < bytes.count, (0x31...0x39).contains(bytes[index]) else {
        index = start
        return false
      }
      index += 1
      while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
    }
    if consume(0x2E) {
      guard index < bytes.count, (0x30...0x39).contains(bytes[index]) else {
        index = start
        return false
      }
      while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
    }
    if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 {
      index += 1
      if index < bytes.count, bytes[index] == 0x2B || bytes[index] == 0x2D { index += 1 }
      guard index < bytes.count, (0x30...0x39).contains(bytes[index]) else {
        index = start
        return false
      }
      while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
    }
    return index > start
  }

  private mutating func jsonString() -> String? {
    guard index < bytes.count, bytes[index] == 0x22 else { return nil }
    let start = index
    index += 1
    while index < bytes.count {
      let byte = bytes[index]
      if byte == 0x22 {
        index += 1
        return try? JSONDecoder().decode(
          String.self,
          from: Data(bytes[start..<index])
        )
      }
      if byte < 0x20 { return nil }
      if byte == 0x5C {
        index += 1
        guard index < bytes.count else { return nil }
        if bytes[index] == 0x75 {
          guard index + 4 < bytes.count,
            bytes[(index + 1)...(index + 4)].allSatisfy(Self.isHexDigit)
          else { return nil }
          index += 5
          continue
        }
        guard
          [0x22, 0x2F, 0x5C, 0x62, 0x66, 0x6E, 0x72, 0x74]
            .contains(bytes[index])
        else { return nil }
      }
      index += 1
    }
    return nil
  }

  private mutating func skipWhitespace() {
    while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
      index += 1
    }
  }

  private mutating func consume(_ byte: UInt8) -> Bool {
    guard index < bytes.count, bytes[index] == byte else { return false }
    index += 1
    return true
  }

  private mutating func consumeSequence(_ sequence: [UInt8]) -> Bool {
    guard index + sequence.count <= bytes.count,
      Array(bytes[index..<(index + sequence.count)]) == sequence
    else { return false }
    index += sequence.count
    return true
  }

  private static func isHexDigit(_ byte: UInt8) -> Bool {
    (0x30...0x39).contains(byte)
      || (0x41...0x46).contains(byte)
      || (0x61...0x66).contains(byte)
  }
}

private struct StrictSessionBody {
  static func decode(_ data: Data) -> String? {
    guard let object = StrictJSONPrimitiveObject.decode(data), object.count == 1,
      let value = object["token"], case .string(let token) = value
    else { return nil }
    return token
  }
}

private struct StrictWorldCreationBody {
  static func decode(_ data: Data) -> String? {
    guard let object = StrictJSONPrimitiveObject.decode(data), object.count == 1,
      let value = object["name"], case .string(let name) = value
    else { return nil }
    return name
  }
}

private struct StrictWorldAgentAdditionBody {
  let worldID: String
  let agentID: String
  let x: Int
  let y: Int
  let autoAdapt: Bool

  static func decode(_ data: Data) -> StrictWorldAgentAdditionBody? {
    guard let object = StrictJSONPrimitiveObject.decode(data),
      Set(object.keys) == ["agentID", "autoAdapt", "worldID", "x", "y"],
      let worldValue = object["worldID"], case .string(let worldID) = worldValue,
      let agentValue = object["agentID"], case .string(let agentID) = agentValue,
      let xValue = object["x"], case .integer(let x) = xValue,
      let yValue = object["y"], case .integer(let y) = yValue,
      let adaptValue = object["autoAdapt"], case .boolean(let autoAdapt) = adaptValue
    else { return nil }
    return StrictWorldAgentAdditionBody(
      worldID: worldID,
      agentID: agentID,
      x: x,
      y: y,
      autoAdapt: autoAdapt
    )
  }
}

private struct StrictWorldCommandBody {
  let worldID: String
  let source: String

  static func decode(_ data: Data) -> StrictWorldCommandBody? {
    guard let object = StrictJSONPrimitiveObject.decode(data),
      Set(object.keys) == ["source", "worldID"],
      let worldValue = object["worldID"], case .string(let worldID) = worldValue,
      let sourceValue = object["source"], case .string(let source) = sourceValue
    else { return nil }
    return StrictWorldCommandBody(worldID: worldID, source: source)
  }
}

/// A bounded primitive-only JSON object reader. Foundation's general JSON object
/// representation folds duplicate members, so state-bearing browser requests use
/// this small parser to reject literal and escaped duplicates before decoding.
private enum StrictJSONPrimitive {
  case string(String)
  case integer(Int)
  case boolean(Bool)
}

private struct StrictJSONPrimitiveObject {
  private let bytes: [UInt8]
  private var index = 0

  private init(_ data: Data) {
    bytes = Array(data)
  }

  static func decode(_ data: Data) -> [String: StrictJSONPrimitive]? {
    var parser = StrictJSONPrimitiveObject(data)
    return parser.decode()
  }

  private mutating func decode() -> [String: StrictJSONPrimitive]? {
    skipWhitespace()
    guard consume(0x7B) else { return nil }  // {
    skipWhitespace()
    var object: [String: StrictJSONPrimitive] = [:]
    if consume(0x7D) {  // }
      skipWhitespace()
      return index == bytes.count ? object : nil
    }
    while true {
      guard let key = jsonString(), object[key] == nil else { return nil }
      skipWhitespace()
      guard consume(0x3A) else { return nil }  // :
      skipWhitespace()
      guard let value = primitive() else { return nil }
      object[key] = value
      skipWhitespace()
      if consume(0x7D) { break }  // }
      guard consume(0x2C) else { return nil }  // ,
      skipWhitespace()
    }
    skipWhitespace()
    guard index == bytes.count else { return nil }
    return object
  }

  private mutating func primitive() -> StrictJSONPrimitive? {
    guard index < bytes.count else { return nil }
    if bytes[index] == 0x22 {
      return jsonString().map(StrictJSONPrimitive.string)
    }
    if consumeSequence([0x74, 0x72, 0x75, 0x65]) {  // true
      return .boolean(true)
    }
    if consumeSequence([0x66, 0x61, 0x6C, 0x73, 0x65]) {  // false
      return .boolean(false)
    }
    return jsonInteger().map(StrictJSONPrimitive.integer)
  }

  private mutating func jsonInteger() -> Int? {
    let start = index
    _ = consume(0x2D)  // -
    guard index < bytes.count else {
      index = start
      return nil
    }
    if bytes[index] == 0x30 {
      index += 1
      if index < bytes.count, (0x30...0x39).contains(bytes[index]) {
        index = start
        return nil
      }
    } else {
      guard (0x31...0x39).contains(bytes[index]) else {
        index = start
        return nil
      }
      index += 1
      while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
    }
    guard let value = Int(String(decoding: bytes[start..<index], as: UTF8.self)) else {
      index = start
      return nil
    }
    return value
  }

  private mutating func jsonString() -> String? {
    guard index < bytes.count, bytes[index] == 0x22 else { return nil }
    let start = index
    index += 1
    while index < bytes.count {
      let byte = bytes[index]
      if byte == 0x22 {
        index += 1
        let data = Data(bytes[start..<index])
        return try? JSONDecoder().decode(String.self, from: data)
      }
      if byte < 0x20 { return nil }
      if byte == 0x5C {
        index += 1
        guard index < bytes.count else { return nil }
        let escape = bytes[index]
        if escape == 0x75 {
          guard index + 4 < bytes.count,
            bytes[(index + 1)...(index + 4)].allSatisfy(Self.isHexDigit)
          else { return nil }
          index += 5
          continue
        }
        guard [0x22, 0x2F, 0x5C, 0x62, 0x66, 0x6E, 0x72, 0x74].contains(escape)
        else { return nil }
      }
      index += 1
    }
    return nil
  }

  private mutating func skipWhitespace() {
    while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
      index += 1
    }
  }

  private mutating func consume(_ byte: UInt8) -> Bool {
    guard index < bytes.count, bytes[index] == byte else { return false }
    index += 1
    return true
  }

  private mutating func consumeSequence(_ sequence: [UInt8]) -> Bool {
    guard index + sequence.count <= bytes.count,
      Array(bytes[index..<(index + sequence.count)]) == sequence
    else { return false }
    index += sequence.count
    return true
  }

  private static func isHexDigit(_ byte: UInt8) -> Bool {
    (0x30...0x39).contains(byte)
      || (0x41...0x46).contains(byte)
      || (0x61...0x66).contains(byte)
  }
}

private struct ParsedTarget {
  let path: String
  let queryValues: [String: [String]]

  var query: String { queryValues.isEmpty ? "" : "present" }
  var allowedQueryKeys: [String] { queryValues.keys.sorted() }
}

private final class KhorosHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
  typealias InboundIn = HTTPServerRequestPart
  typealias OutboundOut = HTTPServerResponsePart

  private let router: KhorosWebRouter
  private let threadPool: NIOThreadPool
  private var requestHead: HTTPRequestHead?
  private var body = Data()
  private var responseInFlight = false
  private var streamTask: Task<Void, Never>?

  init(router: KhorosWebRouter, threadPool: NIOThreadPool) {
    self.router = router
    self.threadPool = threadPool
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    switch Self.unwrapInboundIn(data) {
    case .head(let head):
      guard requestHead == nil, !responseInFlight else {
        context.close(promise: nil)
        return
      }
      requestHead = head
      body.removeAll(keepingCapacity: true)
    case .body(var buffer):
      guard requestHead != nil else {
        context.close(promise: nil)
        return
      }
      let count = buffer.readableBytes
      guard body.count + count <= webMaximumRequestBytes,
        let bytes = buffer.readBytes(length: count)
      else {
        context.close(promise: nil)
        return
      }
      body.append(contentsOf: bytes)
    case .end:
      guard let head = requestHead else {
        context.close(promise: nil)
        return
      }
      requestHead = nil
      responseInFlight = true
      var requestHeaders: [String: [String]] = [:]
      for header in head.headers {
        requestHeaders[header.name.lowercased(), default: []].append(header.value)
      }
      let request = KhorosWebRequest(
        method: head.method.rawValue,
        uri: head.uri,
        headers: requestHeaders,
        body: body
      )
      let eventLoop = context.eventLoop
      let contextBox = HandlerContextBox(context)
      if router.requiresStreamingRoute(request) {
        let task = Task { [router, request] in
          let routed = await router.routeStream(request)
          switch routed {
          case .response(let response):
            eventLoop.execute {
              self.write(response, for: head, context: contextBox.value)
              self.streamTask = nil
            }
          case .stream(let headers, let stream):
            eventLoop.execute {
              self.writeStreamHead(headers: headers, for: head, context: contextBox.value)
            }
            do {
              for try await chunk in stream {
                guard !Task.isCancelled else { break }
                let data = Data(chunk.utf8)
                guard !data.isEmpty else { continue }
                guard
                  await self.writeStreamChunk(
                    data,
                    eventLoop: eventLoop,
                    context: contextBox
                  )
                else { break }
              }
            } catch {
              // A stream cannot change status after its response head. Ending it
              // preserves the bounded, inert transport contract.
            }
            eventLoop.execute {
              self.finishStream(for: head, context: contextBox.value)
              self.streamTask = nil
            }
          }
        }
        streamTask = task
      } else if router.requiresAsyncRoute(request) {
        Task { [router, request] in
          let response = await router.routeAsync(request)
          eventLoop.execute {
            self.write(response, for: head, context: contextBox.value)
          }
        }
      } else {
        let future = threadPool.runIfActive(eventLoop: eventLoop) { [router, request] in
          router.route(request)
        }
        future.whenComplete { result in
          eventLoop.execute {
            switch result {
            case .success(let response):
              self.write(response, for: head, context: contextBox.value)
            case .failure:
              self.write(self.errorResponse(), for: head, context: contextBox.value)
            }
          }
        }
      }
    }
  }

  func channelReadComplete(context: ChannelHandlerContext) { context.flush() }

  func channelInactive(context: ChannelHandlerContext) {
    streamTask?.cancel()
    streamTask = nil
    context.fireChannelInactive()
  }

  private func write(
    _ response: KhorosWebResponse,
    for request: HTTPRequestHead,
    context: ChannelHandlerContext
  ) {
    var headers = HTTPHeaders()
    for (name, value) in response.headers { headers.add(name: name, value: value) }
    let head = HTTPResponseHead(
      version: request.version,
      status: HTTPResponseStatus(statusCode: response.statusCode),
      headers: headers
    )
    context.write(Self.wrapOutboundOut(.head(head)), promise: nil)
    if request.method != .HEAD, !response.body.isEmpty {
      var buffer = context.channel.allocator.buffer(capacity: response.body.count)
      buffer.writeBytes(response.body)
      context.write(Self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
    }
    context.writeAndFlush(Self.wrapOutboundOut(.end(nil)), promise: nil)
    responseInFlight = false
    if !request.isKeepAlive { context.close(promise: nil) }
  }

  private func writeStreamHead(
    headers responseHeaders: [String: String],
    for request: HTTPRequestHead,
    context: ChannelHandlerContext
  ) {
    var headers = HTTPHeaders()
    for (name, value) in responseHeaders { headers.add(name: name, value: value) }
    let head = HTTPResponseHead(version: request.version, status: .ok, headers: headers)
    context.writeAndFlush(Self.wrapOutboundOut(.head(head)), promise: nil)
  }

  private func writeStreamChunk(
    _ data: Data,
    eventLoop: any EventLoop,
    context: HandlerContextBox
  ) async -> Bool {
    guard data.count <= webMaximumCapabilityStreamChunkBytes else { return false }
    return await withCheckedContinuation { continuation in
      eventLoop.execute {
        let channelContext = context.value
        guard channelContext.channel.isActive, channelContext.channel.isWritable else {
          continuation.resume(returning: false)
          return
        }
        var buffer = channelContext.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        channelContext.writeAndFlush(
          Self.wrapOutboundOut(.body(.byteBuffer(buffer)))
        ).whenComplete { result in
          switch result {
          case .success:
            continuation.resume(returning: true)
          case .failure:
            continuation.resume(returning: false)
          }
        }
      }
    }
  }

  private func finishStream(for request: HTTPRequestHead, context: ChannelHandlerContext) {
    guard context.channel.isActive else { return }
    context.writeAndFlush(Self.wrapOutboundOut(.end(nil)), promise: nil)
    responseInFlight = false
    if !request.isKeepAlive { context.close(promise: nil) }
  }

  private func errorResponse() -> KhorosWebResponse {
    router.internalFailure()
  }
}

private final class HandlerContextBox: @unchecked Sendable {
  let value: ChannelHandlerContext

  init(_ value: ChannelHandlerContext) {
    self.value = value
  }
}

/// Internal synchronization points used to make host-lifecycle regressions
/// deterministic. Product callers cannot construct a host with this observer.
enum KhorosWebServerLifecycleTestEvent: Sendable {
  case beforeLaunchCallback
  case waitingForShutdown
  case beforeShutdownCompletion
}

enum WebListenerProbe {
  enum Result: Equatable, Sendable {
    case mikroKhoros
    case other
    case unreachable
  }

  static func classify(port: Int, group: EventLoopGroup) async -> Result {
    guard (1...65_535).contains(port) else { return .unreachable }

    let completion = WebListenerProbeCompletion()
    let probeChannel: Channel
    do {
      probeChannel = try await ClientBootstrap(group: group)
        .channelInitializer { channel in
          channel.pipeline.addHTTPClientHandlers().flatMap {
            channel.pipeline.addHandler(
              WebListenerProbeResponseHandler(port: port, completion: completion)
            )
          }
        }
        .connect(host: "127.0.0.1", port: port)
        .get()
    } catch {
      return .unreachable
    }
    defer { probeChannel.close(promise: nil) }
    let timeout = probeChannel.eventLoop.scheduleTask(in: .milliseconds(750)) {
      completion.finish(.other)
    }
    defer { timeout.cancel() }
    return await completion.wait()
  }

  static func servingError(for port: Int, result: Result) -> WebServingError {
    switch result {
    case .mikroKhoros:
      .portUnavailable(port: port, listener: .mikroKhoros)
    case .other:
      .portUnavailable(port: port, listener: .other)
    case .unreachable:
      .bindFailed
    }
  }
}

/// Finishes the listener probe exactly once. The channel callback and its
/// deadline can run on different event loops, so this narrow synchronization
/// point keeps the externally observable classification deterministic.
private final class WebListenerProbeCompletion: @unchecked Sendable {
  private let lock = NSLock()
  private var result: WebListenerProbe.Result?
  private var waiter: CheckedContinuation<WebListenerProbe.Result, Never>?

  func wait() async -> WebListenerProbe.Result {
    await withCheckedContinuation { continuation in
      lock.lock()
      if let result {
        lock.unlock()
        continuation.resume(returning: result)
      } else {
        waiter = continuation
        lock.unlock()
      }
    }
  }

  func finish(_ result: WebListenerProbe.Result) {
    lock.lock()
    guard self.result == nil else {
      lock.unlock()
      return
    }
    self.result = result
    let continuation = waiter
    waiter = nil
    lock.unlock()
    continuation?.resume(returning: result)
  }
}

/// Performs a single unredirected HTTP request after TCP connect. This uses the
/// same HTTP parser and loopback behavior as the server rather than relying on
/// platform URL loading behavior during a bind-collision diagnostic.
private final class WebListenerProbeResponseHandler: ChannelInboundHandler, @unchecked Sendable {
  typealias InboundIn = HTTPClientResponsePart
  typealias OutboundOut = HTTPClientRequestPart

  private let port: Int
  private let completion: WebListenerProbeCompletion

  init(port: Int, completion: WebListenerProbeCompletion) {
    self.port = port
    self.completion = completion
  }

  func channelActive(context: ChannelHandlerContext) {
    let headers = HTTPHeaders([
      ("host", "127.0.0.1:\(port)"),
      ("cache-control", "no-store"),
    ])
    let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: "/", headers: headers)
    context.write(Self.wrapOutboundOut(.head(head)), promise: nil)
    context.writeAndFlush(Self.wrapOutboundOut(.end(nil)), promise: nil)
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    guard case .head(let head) = Self.unwrapInboundIn(data) else { return }
    let result: WebListenerProbe.Result =
      head.headers.first(name: webListenerMarkerHeader) == webListenerMarkerValue
      ? .mikroKhoros
      : .other
    completion.finish(result)
    context.close(promise: nil)
  }

  func errorCaught(context: ChannelHandlerContext, error: Error) {
    completion.finish(.other)
    context.close(promise: nil)
  }

  func channelInactive(context: ChannelHandlerContext) {
    completion.finish(.other)
    context.fireChannelInactive()
  }
}

public final class KhorosWebServer: KhorosWebServing, @unchecked Sendable {
  private enum Lifecycle {
    case idle
    case starting(UUID)
    case running(UUID)
    case stopping(UUID)
  }

  private struct ShutdownResources {
    let token: UUID
    let channel: Channel?
    let group: MultiThreadedEventLoopGroup?
    let threadPool: NIOThreadPool?
    let completion: ShutdownSignal
  }

  private enum StopAction {
    case none
    case wait(ShutdownSignal)
    case shutDown(ShutdownResources)
  }

  /// A stop owner finishes this signal only after the lifecycle has reached
  /// `.idle`. All overlapping stop callers join it instead of returning while
  /// resources or state are still being torn down.
  private final class ShutdownSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let resumeImmediately = lock.withLock {
          guard !finished else { return true }
          waiters.append(continuation)
          return false
        }
        if resumeImmediately { continuation.resume() }
      }
    }

    func finish() {
      let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
        guard !finished else { return [] }
        finished = true
        let pending = waiters
        waiters.removeAll()
        return pending
      }
      for continuation in pending { continuation.resume() }
    }
  }

  private let commandConsole: (any WorldCommandConsoleServing)?
  private let webCapabilities: (any WebCapabilityServing)?
  private let testLifecycleEvent: (@Sendable (KhorosWebServerLifecycleTestEvent) async -> Void)?
  private let lock = NSLock()
  private var lifecycle = Lifecycle.idle
  private var channel: Channel?
  private var group: MultiThreadedEventLoopGroup?
  private var threadPool: NIOThreadPool?
  private var shutdownSignal: ShutdownSignal?

  public init(
    commandConsole: (any WorldCommandConsoleServing)? = nil,
    webCapabilities: (any WebCapabilityServing)? = nil
  ) {
    self.commandConsole = commandConsole
    self.webCapabilities = webCapabilities
    testLifecycleEvent = nil
  }

  init(
    testLifecycleEvent: @escaping @Sendable (KhorosWebServerLifecycleTestEvent) async -> Void
  ) {
    commandConsole = nil
    webCapabilities = nil
    self.testLifecycleEvent = testLifecycleEvent
  }

  public func serve(
    _ request: WebLaunchRequest,
    onLaunch: @escaping @Sendable (URL) -> Void
  ) async throws {
    try Task.checkCancellation()
    let startToken = try reserveStart()

    let layout = ProductLayout(
      canonicalRoot: request.canonicalRoot,
      configurationURL: request.configurationURL
    )
    let projection = WorldProjectionService(
      layout: layout,
      defaultWorldSelector: request.worldSelector
    )
    let router = KhorosWebRouter(
      projection: projection,
      commandConsole: commandConsole,
      webCapabilities: webCapabilities
    )
    let eventGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let workPool = NIOThreadPool(numberOfThreads: 2)
    workPool.start()
    guard installResources(group: eventGroup, threadPool: workPool, for: startToken) else {
      try? await workPool.shutdownGracefully()
      try? await eventGroup.shutdownGracefully()
      await stop(startToken)
      throw CancellationError()
    }
    do {
      let desiredPort: Int
      switch request.portSelection {
      case .stable:
        desiredPort = WebPortSelection.stablePort
      case .explicit(let port):
        guard (1...65_535).contains(port) else { throw WebServerError.invalidPort }
        desiredPort = port
      case .available:
        desiredPort = 0
      }
      let bootstrap = ServerBootstrap(group: eventGroup)
        .serverChannelOption(.backlog, value: 128)
        .childChannelInitializer { channel in
          channel.pipeline.configureHTTPServerPipeline(
            withPipeliningAssistance: false,
            withErrorHandling: true
          ).flatMap {
            channel.pipeline.addHandler(KhorosHTTPHandler(router: router, threadPool: workPool))
          }
        }
      let serverChannel: Channel
      do {
        serverChannel =
          try await bootstrap
          .bind(host: "127.0.0.1", port: desiredPort)
          .get()
      } catch {
        guard desiredPort != 0 else { throw WebServerError.bindFailed }
        let probe = await WebListenerProbe.classify(port: desiredPort, group: eventGroup)
        throw WebListenerProbe.servingError(for: desiredPort, result: probe)
      }
      guard let port = serverChannel.localAddress?.port else {
        try? await serverChannel.close()
        throw WebServerError.bindFailed
      }
      router.setEndpoint(port: port)
      let token = router.installBootstrapToken()
      guard installChannel(serverChannel, for: startToken) else {
        try? await serverChannel.close()
        throw CancellationError()
      }
      guard let launchURL = URL(string: "http://127.0.0.1:\(port)/#token=\(token)") else {
        await stop(startToken)
        throw WebServerError.bindFailed
      }
      await testLifecycleEvent?(.beforeLaunchCallback)
      guard isRunning(startToken) else {
        await stop(startToken)
        return
      }
      try Task.checkCancellation()
      onLaunch(launchURL)
      try await withTaskCancellationHandler {
        try await serverChannel.closeFuture.get()
      } onCancel: {
        serverChannel.close(promise: nil)
      }
      await stop(startToken)
    } catch {
      await stop(startToken)
      throw error
    }
  }

  public func stop() async {
    await stop(expectedToken: nil)
  }

  private func stop(_ token: UUID) async {
    await stop(expectedToken: token)
  }

  private func stop(expectedToken: UUID?) async {
    switch beginStop(expectedToken: expectedToken) {
    case .none:
      return
    case .wait(let completion):
      await testLifecycleEvent?(.waitingForShutdown)
      await completion.wait()
    case .shutDown(let resources):
      await shutDown(resources)
      await testLifecycleEvent?(.beforeShutdownCompletion)
      completeStop(resources)
    }
  }

  private func reserveStart() throws -> UUID {
    lock.lock()
    defer { lock.unlock() }
    guard case .idle = lifecycle else {
      throw WebServerError.alreadyRunning
    }
    let token = UUID()
    lifecycle = .starting(token)
    return token
  }

  private func installResources(
    group: MultiThreadedEventLoopGroup,
    threadPool: NIOThreadPool,
    for token: UUID
  ) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard case .starting(let currentToken) = lifecycle, currentToken == token else {
      return false
    }
    self.group = group
    self.threadPool = threadPool
    return true
  }

  private func installChannel(_ channel: Channel, for token: UUID) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard case .starting(let currentToken) = lifecycle, currentToken == token else {
      return false
    }
    self.channel = channel
    lifecycle = .running(token)
    return true
  }

  private func isRunning(_ token: UUID) -> Bool {
    lock.withLock {
      guard case .running(let currentToken) = lifecycle else { return false }
      return currentToken == token
    }
  }

  private func beginStop(expectedToken: UUID?) -> StopAction {
    lock.lock()
    defer { lock.unlock() }
    switch lifecycle {
    case .starting(let currentToken), .running(let currentToken):
      guard expectedToken == nil || expectedToken == currentToken else { return .none }
      let completion = ShutdownSignal()
      lifecycle = .stopping(currentToken)
      shutdownSignal = completion
      let resources = ShutdownResources(
        token: currentToken,
        channel: channel,
        group: group,
        threadPool: threadPool,
        completion: completion
      )
      channel = nil
      group = nil
      threadPool = nil
      return .shutDown(resources)
    case .stopping(let currentToken):
      guard expectedToken == nil || expectedToken == currentToken else { return .none }
      guard let shutdownSignal else {
        preconditionFailure("stopping lifecycle is missing its shutdown signal")
      }
      return .wait(shutdownSignal)
    case .idle:
      return .none
    }
  }

  private func shutDown(_ resources: ShutdownResources) async {
    try? await resources.channel?.close()
    try? await resources.threadPool?.shutdownGracefully()
    try? await resources.group?.shutdownGracefully()
  }

  private func completeStop(_ resources: ShutdownResources) {
    let completion = lock.withLock { () -> ShutdownSignal in
      guard case .stopping(let currentToken) = lifecycle, currentToken == resources.token else {
        preconditionFailure("shutdown completion did not own the active lifecycle")
      }
      guard shutdownSignal === resources.completion else {
        preconditionFailure("shutdown completion did not own the active signal")
      }
      lifecycle = .idle
      shutdownSignal = nil
      return resources.completion
    }
    completion.finish()
  }
}

public typealias MikroKhorosWebHost = KhorosWebServer
public typealias WebServerError = WebServingError
