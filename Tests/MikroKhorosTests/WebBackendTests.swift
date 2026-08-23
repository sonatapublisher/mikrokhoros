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

import Crypto
import Foundation
import MikroKhoros
import MikroKhorosCLIKit
import NIOCore
import NIOPosix
import XCTest

@testable import MikroKhorosServices
@testable import MikroKhorosWeb

final class WebBackendTests: XCTestCase {
  func testProductLayoutUsesExplicitRootAndKeepsConfigSeparate() throws {
    let root = URL(fileURLWithPath: "/tmp/mikrokhoros-web-layout", isDirectory: true)
    let layout = ProductLayout(canonicalRoot: root)
    XCTAssertEqual(layout.canonicalRoot.path, root.standardizedFileURL.path)
    XCTAssertEqual(layout.configurationURL.path, root.appendingPathComponent("config.json").path)
    XCTAssertEqual(layout.catalogURL.path, root.appendingPathComponent("worlds/index.json").path)
    XCTAssertEqual(layout.agentURL.path, root.appendingPathComponent("agents.json").path)
    XCTAssertEqual(layout.inventoryURL.path, root.appendingPathComponent("inventory.json").path)
    XCTAssertEqual(layout.packagesDirectoryURL.path, root.appendingPathComponent("packages").path)
    XCTAssertEqual(
      layout.credentialsDirectoryURL.path,
      root.appendingPathComponent("credentials").path
    )
    XCTAssertEqual(
      layout.treasuryURL.path,
      root.appendingPathComponent("treasury-authority.json").path
    )
    XCTAssertThrowsError(try layout.worldURL(for: "not-an-id"))
  }

  func testWebCommandCatalogsStableCustomAndAvailablePortModes() throws {
    let parsed = try CommandParser.parse(["web"])
    XCTAssertEqual(parsed.kind, .web)
    XCTAssertEqual(parsed.definition.path, ["web"])
    XCTAssertEqual(parsed.definition.fields.map(\.id), ["port", "available-port"])
    XCTAssertEqual(
      try CommandParser.parse(["web", "--port", "47568"]).fieldValues["port"],
      ["47568"]
    )
    XCTAssertEqual(
      try CommandParser.parse(["web", "--available-port"]).fieldValues["available-port"],
      ["true"]
    )
    XCTAssertEqual(CommandExecutor.route(for: .web), .web)
    let help = CommandCatalog.renderHelp()
    XCTAssertTrue(help.contains("web"))
    let webHelp = CommandCatalog.renderHelp(path: ["web"])
    XCTAssertTrue(webHelp.contains("stable loopback port 47567"))
    XCTAssertTrue(webHelp.contains("--port <port>"))
    XCTAssertTrue(webHelp.contains("--available-port"))
  }

  func testWebCommandForwardsPortSelectionAndRejectsInvalidCombinations() async throws {
    let host = RecordingWebHost()
    let io = WebCommandIO()
    let configuration = FileManager.default.temporaryDirectory
      .appendingPathComponent("mikrokhoros-web-command-\(UUID().uuidString).json")

    let stableStatus = await KhorosCommandRunner.execute(
      arguments: ["web"],
      io: io,
      webHost: host
    )
    XCTAssertEqual(stableStatus, 0)
    let explicitStatus = await KhorosCommandRunner.execute(
      arguments: [
        "--config", configuration.path, "--world", "selected-world", "web", "--port",
        "47568",
      ],
      io: io,
      webHost: host
    )
    XCTAssertEqual(explicitStatus, 0)
    let availableStatus = await KhorosCommandRunner.execute(
      arguments: ["web", "--available-port"],
      io: io,
      webHost: host
    )
    XCTAssertEqual(availableStatus, 0)

    let requests = host.recordedRequests()
    XCTAssertEqual(requests.map(\.portSelection), [.stable, .explicit(47_568), .available])
    XCTAssertEqual(requests[1].configurationURL, configuration.standardizedFileURL)
    XCTAssertEqual(requests[1].worldSelector, "selected-world")

    for arguments in [
      ["web", "--port", "0"],
      ["web", "--port", "65536"],
      ["web", "--port", "not-a-port"],
      ["web", "--port", "47568", "--available-port"],
    ] {
      let status = await KhorosCommandRunner.execute(arguments: arguments, io: io, webHost: host)
      XCTAssertEqual(status, 1)
    }
    XCTAssertEqual(host.recordedRequests().count, 3)
    XCTAssertTrue(io.standardError.contains("--port"))
  }

  func testWebCommandPresentsBoundedPortCollisionGuidance() async {
    for (listener, expectedText) in [
      (WebPortListenerHint.mikroKhoros, "identifies as MikroKhoros Web"),
      (.other, "another local service"),
    ] {
      let io = WebCommandIO()
      let host = FailingWebHost(
        error: WebServingError.portUnavailable(port: 47_568, listener: listener)
      )
      let status = await KhorosCommandRunner.execute(
        arguments: ["web", "--port", "47568"],
        io: io,
        webHost: host
      )
      XCTAssertEqual(status, 1)
      XCTAssertTrue(io.standardError.contains("web.port_unavailable"))
      XCTAssertTrue(io.standardError.contains("47568"))
      XCTAssertTrue(io.standardError.contains(expectedText))
      XCTAssertTrue(io.standardError.contains("khoros web --available-port"))
      XCTAssertFalse(io.standardError.lowercased().contains("errno"))
    }
  }

  func testRouterRequiresExactHostOriginAndSingleUseSession() throws {
    let root = URL(fileURLWithPath: "/tmp/mikrokhoros-web-router", isDirectory: true)
    let sessions = WebSessionStore()
    let router = KhorosWebRouter(
      projection: WorldProjectionService(layout: ProductLayout(canonicalRoot: root)),
      sessions: sessions
    )
    router.setEndpoint(port: 43127)

    let acceptedDocument = router.route(
      KhorosWebRequest(
        method: "GET",
        uri: "/",
        headers: ["host": ["127.0.0.1:43127"]]
      )
    )
    XCTAssertEqual(acceptedDocument.statusCode, 200)
    XCTAssertEqual(
      acceptedDocument.headers["x-mikrokhoros-listener"],
      "khoros-web/1"
    )

    let rejectedHosts: [(String, [String: [String]])] = [
      ("missing", [:]),
      ("localhost", ["host": ["localhost:43127"]]),
      ("wrong port", ["host": ["127.0.0.1:43128"]]),
      ("duplicate", ["host": ["127.0.0.1:43127", "127.0.0.1:43127"]]),
      ("comma joined", ["host": ["127.0.0.1:43127, localhost:43127"]]),
      (
        "forwarded alias",
        [
          "host": ["localhost:43127"],
          "x-forwarded-host": ["127.0.0.1:43127"],
          "forwarded": ["host=127.0.0.1:43127"],
        ]
      ),
    ]
    for (label, headers) in rejectedHosts {
      let response = router.route(
        KhorosWebRequest(method: "GET", uri: "/", headers: headers)
      )
      XCTAssertEqual(response.statusCode, 400, label)
      XCTAssertEqual(response.body, Data(#"{"error":"request_rejected"}"#.utf8), label)
    }

    let token = sessions.installBootstrapToken()
    let body = try JSONSerialization.data(withJSONObject: ["token": token])

    let duplicateTokenBodies = [
      Data("{\"token\":\"\(token)\",\"token\":\"\(token)\"}".utf8),
      Data("{\"token\":\"\(token)\",\"to\\u006ben\":\"\(token)\"}".utf8),
    ]
    for duplicateBody in duplicateTokenBodies {
      let rejected = router.route(
        KhorosWebRequest(
          method: "POST",
          uri: "/api/v1/session",
          headers: [
            "host": ["127.0.0.1:43127"],
            "origin": ["http://127.0.0.1:43127"],
            "content-type": ["application/json"],
          ],
          body: duplicateBody
        )
      )
      XCTAssertEqual(rejected.statusCode, 401)
      XCTAssertEqual(rejected.body, Data(#"{"error":"request_rejected"}"#.utf8))
      XCTAssertNil(rejected.body.range(of: Data(token.utf8)))
    }

    let session = router.route(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/session",
        headers: [
          "host": ["127.0.0.1:43127"],
          "origin": ["http://127.0.0.1:43127"],
          "content-type": ["application/json"],
        ],
        body: body
      )
    )
    XCTAssertEqual(session.statusCode, 200)
    let cookie = try XCTUnwrap(session.headers["set-cookie"])
    XCTAssertTrue(cookie.hasPrefix("khoros_session_43127="))
    let cookieValue = try XCTUnwrap(
      cookie.split(separator: ";", maxSplits: 1).first?
        .split(separator: "=", maxSplits: 1).last
    )
    XCTAssertEqual(cookieValue.count, 64)

    let reused = router.route(
      KhorosWebRequest(
        method: "POST",
        uri: "/api/v1/session",
        headers: [
          "host": ["127.0.0.1:43127"],
          "origin": ["http://127.0.0.1:43127"],
          "content-type": ["application/json"],
        ],
        body: body
      )
    )
    XCTAssertEqual(reused.statusCode, 401)

    let unauthenticated = router.route(
      KhorosWebRequest(
        method: "GET",
        uri: "/api/v1/world",
        headers: ["host": ["127.0.0.1:43127"]]
      )
    )
    XCTAssertEqual(unauthenticated.statusCode, 401)

    let withUnrelatedCookies = router.route(
      KhorosWebRequest(
        method: "GET",
        uri: "/api/v1/world",
        headers: [
          "host": ["127.0.0.1:43127"],
          "cookie": [
            "before=one; \(sessionCookieHeader(port: 43127, value: String(cookieValue))); after=two"
          ],
        ]
      )
    )
    XCTAssertNotEqual(withUnrelatedCookies.statusCode, 401)

    let duplicateSessionCookie = router.route(
      KhorosWebRequest(
        method: "GET",
        uri: "/api/v1/world",
        headers: [
          "host": ["127.0.0.1:43127"],
          "cookie": [
            "\(sessionCookieHeader(port: 43127, value: String(cookieValue))); "
              + sessionCookieHeader(port: 43127, value: String(cookieValue))
          ],
        ]
      )
    )
    XCTAssertEqual(duplicateSessionCookie.statusCode, 401)

    let wrongOrigin = router.route(
      KhorosWebRequest(
        method: "GET",
        uri: "/api/v1/world",
        headers: [
          "host": ["127.0.0.1:43127"],
          "origin": ["http://127.0.0.1:43128"],
          "cookie": [sessionCookieHeader(port: 43127, value: String(cookieValue))],
        ]
      )
    )
    XCTAssertEqual(wrongOrigin.statusCode, 400)
  }

  func testSessionCookiesAreIsolatedAcrossConcurrentLoopbackPorts() throws {
    let firstRoot = temporaryProductRoot("cookie-port-first")
    let secondRoot = temporaryProductRoot("cookie-port-second")
    defer {
      try? FileManager.default.removeItem(at: firstRoot)
      try? FileManager.default.removeItem(at: secondRoot)
    }
    let firstPort = 43141
    let secondPort = 43142
    let first = try authenticatedFixture(root: firstRoot, port: firstPort)
    let second = try authenticatedFixture(root: secondRoot, port: secondPort)
    let combined = [
      sessionCookieHeader(port: firstPort, value: first.cookie),
      sessionCookieHeader(port: secondPort, value: second.cookie),
    ].joined(separator: "; ")

    let firstResponse = first.router.route(
      KhorosWebRequest(
        method: "GET",
        uri: "/api/v1/world",
        headers: ["host": ["127.0.0.1:\(firstPort)"], "cookie": [combined]]
      )
    )
    XCTAssertEqual(firstResponse.statusCode, 200)

    let secondResponse = second.router.route(
      KhorosWebRequest(
        method: "GET",
        uri: "/api/v1/world",
        headers: ["host": ["127.0.0.1:\(secondPort)"], "cookie": [combined]]
      )
    )
    XCTAssertEqual(secondResponse.statusCode, 200)

    let wrongPortOnly = first.router.route(
      KhorosWebRequest(
        method: "GET",
        uri: "/api/v1/world",
        headers: [
          "host": ["127.0.0.1:\(firstPort)"],
          "cookie": [sessionCookieHeader(port: secondPort, value: second.cookie)],
        ]
      )
    )
    XCTAssertEqual(wrongPortOnly.statusCode, 401)

    let legacyFixedName = first.router.route(
      KhorosWebRequest(
        method: "GET",
        uri: "/api/v1/world",
        headers: [
          "host": ["127.0.0.1:\(firstPort)"],
          "cookie": ["khoros_session=\(first.cookie)"],
        ]
      )
    )
    XCTAssertEqual(legacyFixedName.statusCode, 401)

    let duplicateExpected = first.router.route(
      KhorosWebRequest(
        method: "GET",
        uri: "/api/v1/world",
        headers: [
          "host": ["127.0.0.1:\(firstPort)"],
          "cookie": [
            "\(sessionCookieHeader(port: firstPort, value: first.cookie)); "
              + sessionCookieHeader(port: firstPort, value: first.cookie)
          ],
        ]
      )
    )
    XCTAssertEqual(duplicateExpected.statusCode, 401)
  }

  func testAuthenticatedWorldCreationReturnsExactIdentityAndLoadsProjection() throws {
    let root = temporaryProductRoot("world-create")
    defer { try? FileManager.default.removeItem(at: root) }
    let port = 43131
    let fixture = try authenticatedFixture(root: root, port: port)
    let name = "Browser-created world"
    let response = fixture.router.route(
      worldCreationRequest(
        port: port,
        cookie: fixture.cookie,
        body: Data(#"{"name":"Browser-created world"}"#.utf8)
      )
    )

    XCTAssertEqual(response.statusCode, 201)
    XCTAssertEqual(response.headers["cache-control"], "no-store")
    for header in [
      "content-security-policy",
      "cross-origin-opener-policy",
      "cross-origin-resource-policy",
      "permissions-policy",
      "referrer-policy",
      "x-content-type-options",
    ] {
      XCTAssertNotNil(response.headers[header], header)
    }

    let object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
      "world creation response must be a JSON object"
    )
    XCTAssertEqual(Set(object.keys), ["id", "name"])
    let id = try XCTUnwrap(object["id"] as? String)
    XCTAssertEqual(id.count, 32)
    XCTAssertEqual(id, id.lowercased())
    XCTAssertTrue(id.allSatisfy(\.isHexDigit))
    XCTAssertEqual(object["name"] as? String, name)

    let catalog = try WorldCatalogStore(url: fixture.layout.catalogURL)
    XCTAssertEqual(catalog.document.currentWorldID, id)
    XCTAssertEqual(catalog.currentWorld?.id, id)
    XCTAssertEqual(catalog.currentWorld?.name, name)

    let projectionResponse = fixture.router.route(
      KhorosWebRequest(
        method: "GET",
        uri: "/api/v1/world?world=\(id)",
        headers: [
          "host": ["127.0.0.1:\(port)"],
          "cookie": [sessionCookieHeader(port: port, value: fixture.cookie)],
        ]
      )
    )
    XCTAssertEqual(projectionResponse.statusCode, 200)
    let snapshot = try JSONDecoder().decode(WorldPageSnapshot.self, from: projectionResponse.body)
    XCTAssertEqual(snapshot.state, .available)
    XCTAssertEqual(snapshot.selectedWorldID, id)
    XCTAssertEqual(snapshot.worldName, name)
  }

  func testWorldCreationRejectionMatrixIsGenericAndDoesNotMutateProductState() throws {
    let root = temporaryProductRoot("world-create-rejections")
    defer { try? FileManager.default.removeItem(at: root) }
    let port = 43132
    let fixture = try authenticatedFixture(root: root, port: port)
    let validBody = Data(#"{"name":"Baseline world"}"#.utf8)
    let baseline = fixture.router.route(
      worldCreationRequest(port: port, cookie: fixture.cookie, body: validBody)
    )
    XCTAssertEqual(baseline.statusCode, 201)
    let before = try fileSnapshot(at: root)

    let baseHeaders = [
      "host": ["127.0.0.1:\(port)"],
      "origin": ["http://127.0.0.1:\(port)"],
      "cookie": [sessionCookieHeader(port: port, value: fixture.cookie)],
      "content-type": ["application/json"],
    ]
    func validRequest(
      uri: String = "/api/v1/worlds",
      headers: [String: [String]] = baseHeaders,
      body: Data = validBody
    ) -> KhorosWebRequest {
      KhorosWebRequest(method: "POST", uri: uri, headers: headers, body: body)
    }
    var cases: [(String, KhorosWebRequest, Int)] = []

    var headers = baseHeaders
    headers.removeValue(forKey: "origin")
    cases.append(("missing origin", validRequest(headers: headers), 400))
    headers = baseHeaders
    headers["origin"] = ["http://127.0.0.1:\(port + 1)"]
    cases.append(("wrong origin", validRequest(headers: headers), 400))
    headers = baseHeaders
    headers["origin"] = ["http://127.0.0.1:\(port)", "http://127.0.0.1:\(port)"]
    cases.append(("duplicate origin", validRequest(headers: headers), 400))

    headers = baseHeaders
    headers.removeValue(forKey: "cookie")
    cases.append(("missing session", validRequest(headers: headers), 401))
    headers = baseHeaders
    headers["cookie"] = [
      "\(sessionCookieHeader(port: port, value: fixture.cookie)); "
        + sessionCookieHeader(port: port, value: fixture.cookie)
    ]
    cases.append(("duplicate session", validRequest(headers: headers), 401))
    headers = baseHeaders
    headers["cookie"] = [
      sessionCookieHeader(port: port, value: fixture.cookie),
      sessionCookieHeader(port: port, value: fixture.cookie),
    ]
    cases.append(("duplicate session header", validRequest(headers: headers), 401))
    headers = baseHeaders
    headers["cookie"] = [
      sessionCookieHeader(port: port, value: String(repeating: "0", count: 64))
    ]
    cases.append(("wrong session", validRequest(headers: headers), 401))

    cases.append(("query", validRequest(uri: "/api/v1/worlds?unexpected=1"), 400))

    headers = baseHeaders
    headers.removeValue(forKey: "content-type")
    cases.append(("missing content type", validRequest(headers: headers), 415))
    headers = baseHeaders
    headers["content-type"] = ["application/json", "application/json"]
    cases.append(("duplicate content type", validRequest(headers: headers), 415))
    headers = baseHeaders
    headers["content-type"] = ["text/plain"]
    cases.append(("wrong content type", validRequest(headers: headers), 415))
    headers = baseHeaders
    headers["content-type"] = ["application/json; charset=utf-8"]
    cases.append(("parameterized content type", validRequest(headers: headers), 415))

    cases.append(
      (
        "body over named limit",
        validRequest(body: Data(repeating: 0x61, count: 513)),
        413
      ))
    headers = baseHeaders
    headers["transfer-encoding"] = ["chunked"]
    cases.append(("transfer encoding", validRequest(headers: headers), 400))
    headers = baseHeaders
    headers["content-length"] = ["1"]
    cases.append(("bad content length", validRequest(headers: headers), 400))

    let malformedBodies: [(String, Data)] = [
      ("malformed JSON", Data(#"{"name":"unterminated""#.utf8)),
      ("scalar JSON", Data("1".utf8)),
      ("array JSON", Data("[\"world\"]".utf8)),
      ("missing name", Data("{}".utf8)),
      ("extra JSON key", Data(#"{"name":"world","extra":true}"#.utf8)),
      ("non-string name", Data(#"{"name":123}"#.utf8)),
      ("literal duplicate name", Data(#"{"name":"one","name":"two"}"#.utf8)),
      ("escaped duplicate name", Data(#"{"name":"one","\u006eame":"two"}"#.utf8)),
      ("whitespace name", Data(#"{"name":"   "}"#.utf8)),
      ("newline name", Data(#"{"name":"line\nname"}"#.utf8)),
      (
        "129-character name",
        try JSONSerialization.data(withJSONObject: [
          "name": String(repeating: "a", count: 129)
        ])
      ),
    ]
    for (label, body) in malformedBodies {
      cases.append((label, validRequest(body: body), 400))
    }

    cases.append(
      (
        "authenticated GET",
        KhorosWebRequest(method: "GET", uri: "/api/v1/worlds", headers: baseHeaders),
        405
      ))
    cases.append(
      (
        "authenticated HEAD",
        KhorosWebRequest(method: "HEAD", uri: "/api/v1/worlds", headers: baseHeaders),
        405
      ))
    cases.append(
      (
        "authenticated other method",
        KhorosWebRequest(method: "PUT", uri: "/api/v1/worlds", headers: baseHeaders),
        405
      ))

    for (label, request, status) in cases {
      let response = fixture.router.route(request)
      XCTAssertEqual(response.statusCode, status, label)
      XCTAssertEqual(response.headers["content-type"], "application/json", label)
      XCTAssertEqual(response.headers["cache-control"], "no-store", label)
      if request.method.uppercased() == "HEAD" {
        XCTAssertTrue(response.body.isEmpty, label)
      } else {
        XCTAssertEqual(response.body, Data(#"{"error":"request_rejected"}"#.utf8), label)
      }
      XCTAssertEqual(try fileSnapshot(at: root), before, label)
    }
  }

  func testWorldAgentPresenceOptionsAndAdditionEndpointsReturnBoundedResponses() throws {
    let root = temporaryProductRoot("world-agent-presence")
    defer { try? FileManager.default.removeItem(at: root) }
    let port = 43134
    let fixture = try authenticatedFixture(root: root, port: port)
    let worldResponse = fixture.router.route(
      worldCreationRequest(
        port: port,
        cookie: fixture.cookie,
        body: Data(#"{"name":"Agent world"}"#.utf8)
      )
    )
    XCTAssertEqual(worldResponse.statusCode, 201)
    let worldObject = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: worldResponse.body) as? [String: Any]
    )
    let worldID = try XCTUnwrap(worldObject["id"] as? String)

    let configuration = try ConfigurationStore.load(from: fixture.layout.configurationURL)
    let agents = try AgentStore(
      url: fixture.layout.agentURL,
      maximumBytes: configuration.runtime.maximumAgentStoreBytes
    )
    let candidate = try agents.create(name: "Adder", maximumActionsPerResponse: 8)
    let paddedCandidate = try agents.create(name: "Padded", maximumActionsPerResponse: 8)
    try agents.save()

    let options = fixture.router.route(
      worldAgentOptionsRequest(port: port, cookie: fixture.cookie, worldID: worldID)
    )
    XCTAssertEqual(options.statusCode, 200)
    XCTAssertEqual(options.headers["content-type"], "application/json")
    let optionsObject = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: options.body) as? [String: Any]
    )
    XCTAssertEqual(optionsObject["worldID"] as? String, worldID)
    XCTAssertEqual(Set(optionsObject.keys), ["agents", "worldID"])
    let agentList = try XCTUnwrap(optionsObject["agents"] as? [[String: Any]])
    XCTAssertEqual(agentList.count, 2)
    for entry in agentList {
      XCTAssertEqual(Set(entry.keys), ["id", "name", "state", "visual"])
    }

    let addResponse = fixture.router.route(
      worldAgentAdditionRequest(
        port: port,
        cookie: fixture.cookie,
        worldID: worldID,
        agentID: candidate.id,
        x: 4,
        y: -2,
        autoAdapt: false
      )
    )
    XCTAssertEqual(addResponse.statusCode, 201)
    XCTAssertEqual(addResponse.headers["content-type"], "application/json")
    let addObject = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: addResponse.body) as? [String: Any])
    XCTAssertEqual(
      Set(addObject.keys), ["actual", "adapted", "agentID", "name", "requested", "worldID"])
    XCTAssertEqual(addObject["worldID"] as? String, worldID)
    XCTAssertEqual(addObject["agentID"] as? String, candidate.id)
    let requested = try XCTUnwrap(addObject["requested"] as? [String: Any])
    XCTAssertEqual(try XCTUnwrap(requested["x"] as? NSNumber).intValue, 4)
    XCTAssertEqual(try XCTUnwrap(requested["y"] as? NSNumber).intValue, -2)
    let actual = try XCTUnwrap(addObject["actual"] as? [String: Any])
    XCTAssertEqual(try XCTUnwrap(actual["x"] as? NSNumber).intValue, 4)
    XCTAssertEqual(try XCTUnwrap(actual["y"] as? NSNumber).intValue, -2)
    XCTAssertEqual(addObject["adapted"] as? Bool, false)

    let postBody = worldAgentAdditionBody(
      worldID: worldID, agentID: paddedCandidate.id, x: 0, y: 0, autoAdapt: false)
    var padded = postBody
    if padded.count < 1_024 {
      padded.append(contentsOf: Array(repeating: 0x20, count: 1_024 - padded.count))
    }
    let oneKiBResponse = fixture.router.route(
      worldAgentAdditionRequest(
        port: port,
        cookie: fixture.cookie,
        worldID: worldID,
        agentID: paddedCandidate.id,
        body: padded
      )
    )
    XCTAssertEqual(oneKiBResponse.statusCode, 201)

    let projection = try WorldProjectionService(layout: fixture.layout).snapshotExact(
      world: worldID)
    let projected = (projection.primaryAgents + projection.otherAgents).first(where: {
      $0.id == candidate.id
    })
    XCTAssertNotNil(projected)
  }

  func testWebProjectionRoutesExposeBoundedDomainReadModels() throws {
    let root = temporaryProductRoot("web-projections")
    defer { try? FileManager.default.removeItem(at: root) }
    let port = 43172
    let fixture = try authenticatedFixture(root: root, port: port)
    let createdResponse = fixture.router.route(
      worldCreationRequest(
        port: port,
        cookie: fixture.cookie,
        body: Data(#"{"name":"Projection world"}"#.utf8)
      )
    )
    XCTAssertEqual(createdResponse.statusCode, 201)
    let created = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: createdResponse.body) as? [String: Any]
    )
    let worldID = try XCTUnwrap(created["id"] as? String)

    let configuration = try ConfigurationStore.load(from: fixture.layout.configurationURL)
    let agents = try AgentStore(
      url: fixture.layout.agentURL,
      maximumBytes: configuration.runtime.maximumAgentStoreBytes
    )
    let source = try agents.create(name: "Projection Agent", maximumActionsPerResponse: 8)
    let profile = try AIProfile(
      name: "Private profile",
      adapterID: "openai-compatible",
      transport: .openAICompatible,
      model: "private-projection-model",
      endpoint: "https://profiles.example.invalid/v1",
      credentialEnvironmentVariable: "PROJECTION_PRIVATE_CREDENTIAL"
    )
    _ = try agents.setProfile(profile, for: source.id)
    let inactive = try agents.create(
      name: "Inactive Projection Agent",
      maximumActionsPerResponse: 8
    )
    try agents.save()

    let addedResponse = fixture.router.route(
      worldAgentAdditionRequest(
        port: port,
        cookie: fixture.cookie,
        worldID: worldID,
        agentID: source.id,
        x: 2,
        y: -1
      )
    )
    XCTAssertEqual(addedResponse.statusCode, 201)

    let inventory = try InventoryStore(
      url: fixture.layout.inventoryURL,
      packageDirectory: fixture.layout.packagesDirectoryURL,
      limits: configuration.runtime,
      runtimeRegistry: .installedCLI()
    )
    _ = try inventory.install(data: FirstPartyPackageCatalog.data(named: "printer"))
    let customInstall = try inventory.install(
      data: JSONEncoder().encode(try nativeManagementProjectionFixtureManifest())
    )
    let customSource = try XCTUnwrap(customInstall.inventoryObject)
    let configuredSource = try inventory.configure(
      id: customSource.id,
      setting: ["endpoint": .string("https://PROJECTION_CONFIGURED_VALUE.invalid")]
    )
    let forkedSource = try inventory.fork(
      id: configuredSource.id,
      worldID: worldID,
      name: "Projection fork"
    )
    _ = try inventory.grant(id: configuredSource.id, capabilities: [.network])

    let messageRuntime = try WorldRuntime(
      document: try WorldStore.load(
        from: fixture.layout.worldURL(for: worldID),
        maximumBytes: configuration.runtime.maximumWorldBytes
      ),
      configuration: configuration,
      inventory: inventory,
      treasuryAuthority: nil
    )
    let activeAgent = try XCTUnwrap(messageRuntime.harness.findAgent(source.id))
    _ = try messageRuntime.sendMessage(
      to: activeAgent,
      body: "PROJECTION_PRIVATE_NOTIFICATION_BODY",
      sender: "PROJECTION_PRIVATE_NOTIFICATION_SENDER",
      priority: .three
    )
    let deployedManagementObjectID = try messageRuntime.deployInventoryObject(
      configuredSource.id,
      at: Coordinate(x: 8, y: -3)
    ).snapshot.objectID
    try WorldStore.save(
      messageRuntime.document,
      to: fixture.layout.worldURL(for: worldID),
      maximumBytes: configuration.runtime.maximumWorldBytes
    )

    let endpoint = { (path: String) in
      fixture.router.route(
        KhorosWebRequest(
          method: "GET",
          uri: path,
          headers: [
            "host": ["127.0.0.1:\(port)"],
            "origin": ["http://127.0.0.1:\(port)"],
            "cookie": [self.sessionCookieHeader(port: port, value: fixture.cookie)],
          ]
        )
      )
    }
    let routed = { (method: String, uri: String) in
      fixture.router.route(
        KhorosWebRequest(
          method: method,
          uri: uri,
          headers: [
            "host": ["127.0.0.1:\(port)"],
            "origin": ["http://127.0.0.1:\(port)"],
            "cookie": [self.sessionCookieHeader(port: port, value: fixture.cookie)],
          ]
        )
      )
    }
    let projectionDecoder = JSONDecoder()
    projectionDecoder.dateDecodingStrategy = .iso8601

    let agentResponse = endpoint("/api/v1/agents")
    XCTAssertEqual(agentResponse.statusCode, 200)
    let agentSnapshot = try projectionDecoder.decode(
      NativeAgentManagerSnapshot.self,
      from: agentResponse.body
    )
    XCTAssertEqual(agentSnapshot.count, 2)
    let agent = try XCTUnwrap(agentSnapshot.agents.first(where: { $0.id == source.id }))
    XCTAssertEqual(agent.worldAssignment?.worldID, worldID)
    XCTAssertTrue(agent.hasProfile)
    XCTAssertEqual(agent.notifications.unreadCount, 1)
    XCTAssertTrue(agent.notifications.canRetry)
    let presence = try XCTUnwrap(agent.activePresence)
    XCTAssertTrue(presence.isActive)
    XCTAssertEqual(presence.coordinate, WorldCoordinateSnapshot(x: 2, y: -1))
    XCTAssertEqual(presence.holdings.map(\.slot), [1, 2, 3, 4])
    XCTAssertEqual(
      Set(presence.lifecycle.map(\.role)),
      ["backpack", "wallet", "eye", "scratchpad", "messenger", "calculator"]
    )
    XCTAssertFalse(
      String(decoding: agentResponse.body, as: UTF8.self).contains("private-projection-model"))
    XCTAssertFalse(
      String(decoding: agentResponse.body, as: UTF8.self).contains("profiles.example.invalid"))
    XCTAssertFalse(
      String(decoding: agentResponse.body, as: UTF8.self).contains("PROJECTION_PRIVATE_CREDENTIAL")
    )
    XCTAssertFalse(
      String(decoding: agentResponse.body, as: UTF8.self).contains(
        "PROJECTION_PRIVATE_NOTIFICATION_BODY"
      )
    )
    XCTAssertFalse(
      String(decoding: agentResponse.body, as: UTF8.self).contains(
        "PROJECTION_PRIVATE_NOTIFICATION_SENDER"
      )
    )

    // Both a directly held root and an agent-attached lifecycle root resolve
    // through the exact world object endpoint. They carry structural paths and
    // no invented coordinate.
    let heldID = try XCTUnwrap(presence.holdings.first(where: { $0.objectID != nil })?.objectID)
    let heldResponse = endpoint("/api/v1/object?world=\(worldID)&object=\(heldID)")
    XCTAssertEqual(heldResponse.statusCode, 200)
    let heldPage = try projectionDecoder.decode(
      WorldObjectPageSnapshot.self, from: heldResponse.body)
    XCTAssertEqual(heldPage.state, .available)
    XCTAssertEqual(heldPage.worldID, worldID)
    XCTAssertEqual(heldPage.object?.id, heldID)
    XCTAssertNil(heldPage.object?.coordinate)
    XCTAssertEqual(heldPage.object?.canMove, true)
    XCTAssertEqual(heldPage.object?.path, "agent:\(source.id):holding:1")
    XCTAssertNotNil(heldPage.interface)

    let backpackID = try XCTUnwrap(
      presence.lifecycle.first(where: { $0.role == "backpack" })?.id
    )
    let backpackResponse = endpoint("/api/v1/object?world=\(worldID)&object=\(backpackID)")
    XCTAssertEqual(backpackResponse.statusCode, 200)
    let backpackPage = try projectionDecoder.decode(
      WorldObjectPageSnapshot.self,
      from: backpackResponse.body
    )
    XCTAssertEqual(backpackPage.state, .available)
    XCTAssertEqual(backpackPage.object?.id, backpackID)
    XCTAssertNil(backpackPage.object?.coordinate)
    XCTAssertEqual(backpackPage.object?.canMove, false)
    XCTAssertEqual(backpackPage.object?.path, "agent:\(source.id):attachment:backpack")
    XCTAssertNotNil(backpackPage.interface)

    // Lifecycle children preserve their local coordinate while the path keeps
    // the agent attachment root and exact parent-object identity. The web
    // projection must not substitute a generic Harness path here.
    let walletID = try XCTUnwrap(
      presence.lifecycle.first(where: { $0.role == "wallet" })?.id
    )
    let walletResponse = endpoint("/api/v1/object?world=\(worldID)&object=\(walletID)")
    XCTAssertEqual(walletResponse.statusCode, 200)
    let walletPage = try projectionDecoder.decode(
      WorldObjectPageSnapshot.self,
      from: walletResponse.body
    )
    XCTAssertEqual(walletPage.state, .available)
    XCTAssertEqual(walletPage.object?.id, walletID)
    XCTAssertEqual(walletPage.object?.coordinate, WorldCoordinateSnapshot(x: 4, y: 0))
    let walletPath = try XCTUnwrap(walletPage.object?.path)
    XCTAssertEqual(
      walletPath,
      "agent:\(source.id):attachment:backpack/4,0#\(backpackID)"
    )
    XCTAssertNotNil(walletPage.interface)

    let heldJSON = String(decoding: heldResponse.body, as: UTF8.self)
    let backpackJSON = String(decoding: backpackResponse.body, as: UTF8.self)
    let walletJSON = String(decoding: walletResponse.body, as: UTF8.self)
    for privateValue in [
      "private-projection-model",
      "profiles.example.invalid",
      "PROJECTION_PRIVATE_CREDENTIAL",
      "PROJECTION_PRIVATE_NOTIFICATION_BODY",
      "PROJECTION_PRIVATE_NOTIFICATION_SENDER",
    ] {
      XCTAssertFalse(heldJSON.contains(privateValue))
      XCTAssertFalse(backpackJSON.contains(privateValue))
      XCTAssertFalse(walletJSON.contains(privateValue))
    }

    // A world copy with a deliberately rich declared interface is projected
    // through the bounded management contract, never as a raw package model.
    let managedObjectResponse = endpoint(
      "/api/v1/object?world=\(worldID)&object=\(deployedManagementObjectID)"
    )
    XCTAssertEqual(managedObjectResponse.statusCode, 200)
    let managedObjectPage = try projectionDecoder.decode(
      WorldObjectPageSnapshot.self,
      from: managedObjectResponse.body
    )
    XCTAssertEqual(managedObjectPage.state, .available)
    XCTAssertEqual(managedObjectPage.object?.id, deployedManagementObjectID)
    XCTAssertEqual(managedObjectPage.object?.coordinate, WorldCoordinateSnapshot(x: 8, y: -3))
    let managedObjectJSON = String(decoding: managedObjectResponse.body, as: UTF8.self)
    XCTAssertFalse(managedObjectJSON.contains("/private/management-workspace"))
    XCTAssertFalse(managedObjectJSON.contains("PROJECTION_CONFIGURED_VALUE"))
    XCTAssertFalse(managedObjectJSON.contains("\"action\":"))
    XCTAssertFalse(managedObjectJSON.contains("\"output_x\":0"))
    XCTAssertFalse(managedObjectJSON.contains("\"output_y\":-1"))
    let managedTop = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: managedObjectResponse.body) as? [String: Any]
    )
    let managedInterface = try XCTUnwrap(managedTop["interface"] as? [String: Any])
    let management = try XCTUnwrap(managedInterface["object"] as? [String: Any])
    let managedFields = try XCTUnwrap(management["fields"] as? [[String: Any]])
    let workspace = try XCTUnwrap(
      managedFields.first(where: { $0["id"] as? String == "workspace" }))
    XCTAssertNil(workspace["defaultValue"])
    let managedAction = try XCTUnwrap(
      (management["actions"] as? [[String: Any]])?.first
    )
    XCTAssertNil(managedAction["action"])
    XCTAssertEqual((managedAction["inputChoices"] as? [String: [String]])?["mode"]?.count, 64)
    XCTAssertEqual((workspace["choices"] as? [String])?.count, 0)
    let mode = try XCTUnwrap(managedFields.first(where: { $0["id"] as? String == "mode" }))
    XCTAssertEqual((mode["choices"] as? [String])?.count, 64)
    let managedReports = try XCTUnwrap(management["reports"] as? [[String: Any]])
    let managedReport = try XCTUnwrap(managedReports.first)
    XCTAssertEqual((managedReport["maximumTitleCharacters"] as? NSNumber)?.intValue, 8_192)
    XCTAssertEqual((managedReport["maximumBodyCharacters"] as? NSNumber)?.intValue, 1_048_576)
    XCTAssertEqual((managedReport["maximumPayloadBytes"] as? NSNumber)?.intValue, 1_048_576)
    let inactiveAgent = try XCTUnwrap(agentSnapshot.agents.first(where: { $0.id == inactive.id }))
    XCTAssertNil(inactiveAgent.activePresence)
    XCTAssertEqual(inactiveAgent.notifications, .none)

    let inventoryResponse = endpoint("/api/v1/inventory")
    XCTAssertEqual(inventoryResponse.statusCode, 200)
    let inventorySnapshot = try projectionDecoder.decode(
      NativeInventorySnapshot.self,
      from: inventoryResponse.body
    )
    XCTAssertEqual(inventorySnapshot.counts.sources, 3)
    let inventorySource = try XCTUnwrap(
      inventorySnapshot.sources.first(where: { $0.packageID == FirstPartyPackageID.printer })
    )
    XCTAssertEqual(inventorySource.packageID, FirstPartyPackageID.printer)
    let typedSource = try XCTUnwrap(
      inventorySnapshot.sources.first(where: { $0.id == configuredSource.id })
    )
    XCTAssertNil(typedSource.forkProvenance)
    let forkedProjection = try XCTUnwrap(
      inventorySnapshot.sources.first(where: { $0.id == forkedSource.id })
    )
    let forkProvenance = try XCTUnwrap(forkedProjection.forkProvenance)
    XCTAssertEqual(forkProvenance.parentSourceID, configuredSource.id)
    XCTAssertEqual(forkProvenance.parentRevision, configuredSource.revision)
    XCTAssertLessThanOrEqual(
      abs(
        forkProvenance.forkedAt.timeIntervalSince1970
          - (forkedSource.forkProvenance?.forkedAt.timeIntervalSince1970 ?? 0)
      ),
      1
    )
    XCTAssertEqual(forkedProjection.worldBindingID, worldID)
    let typedField = try XCTUnwrap(typedSource.management.fields.first(where: { $0.id == "mode" }))
    XCTAssertEqual(typedField.label, "Mode")
    XCTAssertEqual(typedField.summary, "How this source is refreshed.")
    XCTAssertEqual(typedField.kind, "choice")
    XCTAssertTrue(typedField.required)
    XCTAssertTrue(typedField.deployable)
    XCTAssertEqual(typedField.defaultValue, .string("quiet"))
    XCTAssertEqual(typedField.choices.count, 64)
    XCTAssertEqual(typedField.minimumCharacters, 2)
    XCTAssertEqual(typedField.maximumCharacters, 16)
    let privatePathField = try XCTUnwrap(
      typedSource.management.fields.first(where: { $0.id == "workspace" })
    )
    XCTAssertNil(privatePathField.defaultValue)
    let action = try XCTUnwrap(typedSource.management.actions.first)
    XCTAssertEqual(action.id, "refresh")
    XCTAssertEqual(action.parameters, ["endpoint", "mode", "enabled", "workspace"])
    XCTAssertEqual(
      action.inputTypes,
      [
        "endpoint": "url",
        "mode": "choice",
        "enabled": "boolean",
        "workspace": "path",
      ])
    XCTAssertEqual(action.inputDefaults["endpoint"], .string("https://example.invalid/run"))
    XCTAssertEqual(action.inputDefaults["enabled"], .bool(true))
    XCTAssertNil(action.inputDefaults["workspace"])
    XCTAssertEqual(action.inputChoices["mode"]?.count, 64)
    XCTAssertTrue(action.mutating)
    XCTAssertEqual(action.requiredCapabilityIDs, [ObjectCapability.network.rawValue])
    XCTAssertEqual(action.scope, "both")
    XCTAssertEqual(action.result, ["accepted": "boolean", "message": "text"])
    let view = try XCTUnwrap(typedSource.management.views.first)
    XCTAssertEqual(view.id, "status")
    XCTAssertEqual(view.source, "state")
    XCTAssertEqual(view.scope, "both")
    XCTAssertEqual(view.result, ["ready": "boolean"])
    let report = try XCTUnwrap(typedSource.management.reports.first)
    XCTAssertEqual(report.type, "run-status")
    XCTAssertEqual(report.summary, "A bounded refresh report.")
    XCTAssertEqual(report.maximumTitleCharacters, 8_192)
    XCTAssertEqual(report.maximumBodyCharacters, 1_048_576)
    XCTAssertEqual(report.maximumPayloadBytes, 1_048_576)
    XCTAssertEqual(report.payload, ["ready": "boolean"])
    let inventoryJSON = String(decoding: inventoryResponse.body, as: UTF8.self)
    XCTAssertFalse(inventoryJSON.contains("output_x\":0"))
    XCTAssertFalse(inventoryJSON.contains("output_y\":-1"))
    XCTAssertFalse(inventoryJSON.contains("/private/management-workspace"))
    XCTAssertFalse(inventoryJSON.contains("PROJECTION_CONFIGURED_VALUE"))

    let packageResponse = endpoint("/api/v1/packages")
    XCTAssertEqual(packageResponse.statusCode, 200)
    let packageSnapshot = try projectionDecoder.decode(
      NativePackagesSnapshot.self,
      from: packageResponse.body
    )
    XCTAssertTrue(
      packageSnapshot.packages.contains(where: { $0.id == FirstPartyPackageID.printer }))
    XCTAssertEqual(packageSnapshot.retainedPackages.count, 2)
    let retainedPrinter = try XCTUnwrap(
      packageSnapshot.retainedPackages.first(where: { $0.id == FirstPartyPackageID.printer })
    )
    XCTAssertEqual(retainedPrinter.sourceCount, 1)
    XCTAssertEqual(retainedPrinter.retainedSourceCount, 1)
    let retainedManaged = try XCTUnwrap(
      packageSnapshot.retainedPackages.first(where: { $0.id == "example.web-management" })
    )
    XCTAssertEqual(retainedManaged.sourceCount, 2)
    XCTAssertEqual(retainedManaged.retainedSourceCount, 2)
    XCTAssertEqual(retainedManaged.management.fieldCount, 4)
    XCTAssertEqual(retainedManaged.management.actionCount, 1)
    XCTAssertEqual(retainedManaged.management.viewCount, 1)

    let templateResponse = endpoint("/api/v1/templates")
    XCTAssertEqual(templateResponse.statusCode, 200)
    let templateSnapshot = try projectionDecoder.decode(
      NativeTemplatesSnapshot.self,
      from: templateResponse.body
    )
    let defaultTemplate = try XCTUnwrap(
      templateSnapshot.templates.first(where: { $0.id == "default-khoros" }))
    XCTAssertTrue(defaultTemplate.trusted)
    XCTAssertEqual(defaultTemplate.components.count, 5)
    XCTAssertEqual(defaultTemplate.placements.count, 9)
    XCTAssertTrue(defaultTemplate.placements.contains(where: { $0.kind == "root" }))
    XCTAssertTrue(defaultTemplate.placements.contains(where: { $0.kind == "owned" }))

    let settingsResponse = endpoint("/api/v1/settings")
    XCTAssertEqual(settingsResponse.statusCode, 200)
    let settingsSnapshot = try projectionDecoder.decode(
      NativeSettingsSnapshot.self,
      from: settingsResponse.body
    )
    XCTAssertEqual(settingsSnapshot.currentWorld?.id, worldID)
    XCTAssertEqual(settingsSnapshot.counts.agents, 2)
    XCTAssertTrue(settingsSnapshot.groups.contains(where: { $0.id == "runtime" }))
    XCTAssertTrue(settingsSnapshot.adapters.allSatisfy { $0.declared })
    XCTAssertFalse(String(decoding: settingsResponse.body, as: UTF8.self).contains("/usr/"))

    let headResponse = routed("HEAD", "/api/v1/templates")
    XCTAssertEqual(headResponse.statusCode, 200)
    XCTAssertTrue(headResponse.body.isEmpty)
    XCTAssertNotNil(headResponse.headers["content-length"])

    XCTAssertEqual(routed("GET", "/api/v1/agents?unexpected=value").statusCode, 400)
    XCTAssertEqual(routed("POST", "/api/v1/inventory").statusCode, 405)
    let unauthenticated = fixture.router.route(
      KhorosWebRequest(
        method: "GET",
        uri: "/api/v1/settings",
        headers: ["host": ["127.0.0.1:\(port)"]]
      )
    )
    XCTAssertEqual(unauthenticated.statusCode, 401)
  }

  func testWorldAgentPresenceRoutesRejectStrictlyForInvalidInputAndAuth() throws {
    let root = temporaryProductRoot("world-agent-presence-rejections")
    defer { try? FileManager.default.removeItem(at: root) }
    let port = 43135
    let fixture = try authenticatedFixture(root: root, port: port)
    let worldResponse = fixture.router.route(
      worldCreationRequest(
        port: port,
        cookie: fixture.cookie,
        body: Data(#"{"name":"Reject world"}"#.utf8)
      )
    )
    XCTAssertEqual(worldResponse.statusCode, 201)
    let world = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: worldResponse.body) as? [String: Any])
    let worldID = try XCTUnwrap(world["id"] as? String)

    let configuration = try ConfigurationStore.load(from: fixture.layout.configurationURL)
    let agents = try AgentStore(
      url: fixture.layout.agentURL,
      maximumBytes: configuration.runtime.maximumAgentStoreBytes
    )
    let candidate = try agents.create(name: "Rejector", maximumActionsPerResponse: 8)
    try agents.save()

    func candidateHeaders(_ configure: (inout [String: [String]]) -> Void) -> [String: [String]] {
      var headers = [
        "host": ["127.0.0.1:\(port)"],
        "origin": ["http://127.0.0.1:\(port)"],
        "cookie": [sessionCookieHeader(port: port, value: fixture.cookie)],
        "content-type": ["application/json"],
      ]
      configure(&headers)
      return headers
    }

    let baseRequest = { (uri: String, headers: [String: [String]]) -> KhorosWebRequest in
      KhorosWebRequest(method: "POST", uri: uri, headers: headers)
    }

    let duplicateKeyBody = Data(
      #"{"worldID":"\#(worldID)","agentID":"\#(candidate.id)","x":0,"y":0,"autoAdapt":false,"worldID":"\#(worldID)"}"#
        .utf8
    )
    let escapedDuplicateKeyBody = Data(
      #"{"worldID":"\#(worldID)","agentID":"\#(candidate.id)","x":0,"y":0,"autoAdapt":false,"\\u0077orldID":"\#(worldID)"}"#
        .utf8
    )
    let invalidWorldIDBody = worldAgentAdditionBody(
      worldID: "\(String(repeating: "a", count: 31))", agentID: candidate.id)
    let invalidAgentIDBody = worldAgentAdditionBody(
      worldID: worldID, agentID: "\(String(repeating: "g", count: 31))")

    let cases: [(String, KhorosWebRequest, Int)] = [
      (
        "GET missing world",
        KhorosWebRequest(
          method: "GET", uri: "/api/v1/world-agents",
          headers: [
            "host": ["127.0.0.1:\(port)"],
            "cookie": [sessionCookieHeader(port: port, value: fixture.cookie)],
          ]),
        400
      ),
      (
        "GET extra query",
        KhorosWebRequest(
          method: "GET", uri: "/api/v1/world-agents?unexpected=1",
          headers: [
            "host": ["127.0.0.1:\(port)"],
            "cookie": [sessionCookieHeader(port: port, value: fixture.cookie)],
          ]),
        400
      ),
      (
        "GET invalid world ID",
        worldAgentOptionsRequest(port: port, cookie: fixture.cookie, worldID: "invalid"),
        400
      ),
      (
        "POST wrong path",
        baseRequest(
          "/api/v1/world-agents?world=\(worldID)",
          candidateHeaders { $0["content-type"] = ["application/json"] }
        ),
        400
      ),
      (
        "POST duplicate content type",
        worldAgentAdditionRequest(
          port: port,
          cookie: fixture.cookie,
          worldID: worldID,
          agentID: candidate.id,
          headers: candidateHeaders {
            $0["content-type"] = ["application/json", "application/json"]
          }
        ),
        415
      ),
      (
        "POST missing content type",
        worldAgentAdditionRequest(
          port: port,
          cookie: fixture.cookie,
          worldID: worldID,
          agentID: candidate.id,
          headers: candidateHeaders { $0["content-type"] = [] }
        ),
        415
      ),
      (
        "POST duplicate agent key",
        worldAgentAdditionRequest(
          port: port,
          cookie: fixture.cookie,
          worldID: worldID,
          agentID: candidate.id,
          body: duplicateKeyBody
        ),
        400
      ),
      (
        "POST escaped duplicate key",
        worldAgentAdditionRequest(
          port: port,
          cookie: fixture.cookie,
          worldID: worldID,
          agentID: candidate.id,
          body: escapedDuplicateKeyBody
        ),
        400
      ),
      (
        "POST invalid world selector",
        worldAgentAdditionRequest(
          port: port,
          cookie: fixture.cookie,
          worldID: worldID,
          agentID: "\(String(repeating: "a", count: 31))"
        ),
        400
      ),
      (
        "POST invalid world selector in body",
        worldAgentAdditionRequest(
          port: port,
          cookie: fixture.cookie,
          body: invalidWorldIDBody
        ),
        400
      ),
      (
        "POST invalid agent selector in body",
        worldAgentAdditionRequest(
          port: port,
          cookie: fixture.cookie,
          body: invalidAgentIDBody
        ),
        400
      ),
      (
        "POST missing auth",
        worldAgentAdditionRequest(
          port: port,
          cookie: fixture.cookie,
          worldID: worldID,
          agentID: candidate.id,
          headers: candidateHeaders { $0["cookie"] = [] }
        ),
        401
      ),
      (
        "POST duplicate session",
        worldAgentAdditionRequest(
          port: port,
          cookie: fixture.cookie,
          worldID: worldID,
          agentID: candidate.id,
          headers: candidateHeaders {
            $0["cookie"] = [
              sessionCookieHeader(port: port, value: fixture.cookie),
              sessionCookieHeader(port: port, value: fixture.cookie),
            ]
          }
        ),
        401
      ),
      (
        "POST request too large",
        worldAgentAdditionRequest(
          port: port,
          cookie: fixture.cookie,
          body: Data(repeating: 0x61, count: 1_025)
        ),
        413
      ),
    ]

    for (label, request, status) in cases {
      let response = fixture.router.route(request)
      XCTAssertEqual(response.statusCode, status, label)
      XCTAssertEqual(response.body, Data(#"{"error":"request_rejected"}"#.utf8), label)
    }

    let assignment = try agents.resolve(candidate.id)
    XCTAssertNil(assignment.worldAssignment)
  }

  func testWorldCommandPolicyExhaustiveAllowAndRefreshMatrix() {
    let allowed: Set<CommandKind> = [
      .help,
      .worldTemplateStatus,
      .worldShow,
      .worldObjectList,
      .worldObjectViewList,
      .worldObjectMove,
    ]
    let refreshes: Set<CommandKind> = [.worldObjectMove]
    for kind in CommandKind.allCases {
      XCTAssertEqual(
        WorldCommandConsolePolicy.allows(kind),
        allowed.contains(kind),
        "allows \(kind.rawValue)"
      )
      XCTAssertEqual(
        WorldCommandConsolePolicy.refreshesWorld(kind),
        refreshes.contains(kind),
        "refreshes \(kind.rawValue)"
      )
    }
  }

  func testWorldCommandExecuteUsesExplicitLayoutUnderAmbientRootOverride() async throws {
    let validRoot = temporaryProductRoot("world-command-layout-valid")
    let ambientRoot = temporaryProductRoot("world-command-layout-ambient")
    defer {
      try? FileManager.default.removeItem(at: validRoot)
      try? FileManager.default.removeItem(at: ambientRoot)
    }
    let validLayout = ProductLayout(canonicalRoot: validRoot)
    let created = try WorldCreationService(layout: validLayout).createBareWorld(name: "Bound world")
    let request = WorldCommandConsoleRequest(
      layout: validLayout,
      worldID: created.id,
      source: "world show"
    )
    let service = CLIWorldCommandConsoleService()
    let result = try await MikroKhorosPathContext.$canonicalRootOverride.withValue(
      ambientRoot
    ) {
      try await service.execute(request)
    }
    XCTAssertTrue(result.accepted)
    XCTAssertEqual(result.exitStatus, 0)
  }

  func testWorldCommandRoutesRejectMalformedPayloadsWithoutInvokingService() async throws {
    let root = temporaryProductRoot("world-command-rejections")
    defer { try? FileManager.default.removeItem(at: root) }
    let port = 43136
    let stub = StubWorldCommandConsoleService()
    let fixture = try authenticatedFixture(root: root, port: port, commandConsole: stub)
    let createResponse = fixture.router.route(
      worldCreationRequest(
        port: port,
        cookie: fixture.cookie,
        body: Data(#"{"name":"Command world"}"#.utf8)
      )
    )
    XCTAssertEqual(createResponse.statusCode, 201)
    let created = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: createResponse.body) as? [String: Any])
    let worldID = try XCTUnwrap(created["id"] as? String)
    stub.setCompletionResult(.success(WorldCommandCompletionResult(suggestions: [])))
    stub.setExecuteResult(
      .success(
        WorldCommandExecutionResult(
          accepted: true,
          displayCommand: "help",
          standardOutput: "ok\n",
          standardError: "",
          exitStatus: 0,
          outputTruncated: false,
          refreshWorld: false
        )
      )
    )

    let malformed: [(String, Data)] = [
      ("not JSON", Data("[]".utf8)),
      (
        "bad world selector",
        try worldCommandBody(worldID: String(repeating: "g", count: 31), source: "help")
      ),
      ("extra field", Data(#"{"worldID":"\#(worldID)","source":"help","extra":true}"#.utf8)),
      ("missing field", Data(#"{"worldID":"\#(worldID)}"#.utf8)),
      (
        "duplicate key",
        Data(#"{"worldID":"\#(worldID)","source":"help","worldID":"\#(worldID)"}"#.utf8)
      ),
      (
        "escaped duplicate",
        Data(
          #"{"worldID":"\#(worldID)","\\u0077orldID":"\#(worldID)","source":"help"}"#
            .utf8)
      ),
      ("newline source", try worldCommandBody(worldID: worldID, source: "line\nbreak")),
      ("non-string source", Data(#"{"worldID":"\#(worldID)","source":true}"#.utf8)),
    ]
    for (label, body) in malformed {
      let completionBefore = stub.completionRequestCount
      let executeBefore = stub.executeRequestCount
      let completionResponse = await fixture.router.routeAsync(
        worldCommandRequest(
          port: port,
          cookie: fixture.cookie,
          body: body,
          endpoint: "completions"
        )
      )
      XCTAssertEqual(completionResponse.statusCode, 400, label)
      XCTAssertEqual(stub.completionRequestCount, completionBefore, label)

      let executeResponse = await fixture.router.routeAsync(
        worldCommandRequest(port: port, cookie: fixture.cookie, body: body, endpoint: "execute")
      )
      XCTAssertEqual(executeResponse.statusCode, 400, label)
      XCTAssertEqual(stub.executeRequestCount, executeBefore, label)
    }

    let oversizedBody = Data(repeating: 0x61, count: 8_193)
    let oversizedResponse = await fixture.router.routeAsync(
      worldCommandRequest(
        port: port,
        cookie: fixture.cookie,
        body: oversizedBody,
        endpoint: "execute"
      )
    )
    XCTAssertEqual(oversizedResponse.statusCode, 413)

    let missingOrigin = await fixture.router.routeAsync(
      worldCommandRequest(
        port: port,
        cookie: fixture.cookie,
        body: try worldCommandBody(worldID: worldID, source: "help"),
        endpoint: "completions",
        headers: ["origin": []]
      )
    )
    XCTAssertEqual(missingOrigin.statusCode, 400)

    let badContentType = await fixture.router.routeAsync(
      worldCommandRequest(
        port: port,
        cookie: fixture.cookie,
        body: try worldCommandBody(worldID: worldID, source: "help"),
        endpoint: "completions",
        headers: ["content-type": ["text/plain"]]
      )
    )
    XCTAssertEqual(badContentType.statusCode, 415)

    let getNotAllowed = await fixture.router.routeAsync(
      worldCommandRequest(
        port: port,
        cookie: fixture.cookie,
        body: try worldCommandBody(worldID: worldID, source: "help"),
        endpoint: "completions",
        method: "GET"
      )
    )
    XCTAssertEqual(getNotAllowed.statusCode, 405)

    let authBefore = stub.completionRequestCount
    let missingAuth = await fixture.router.routeAsync(
      worldCommandRequest(
        port: port,
        cookie: fixture.cookie,
        body: try worldCommandBody(worldID: worldID, source: "help"),
        endpoint: "completions",
        headers: ["cookie": []]
      )
    )
    XCTAssertEqual(missingAuth.statusCode, 401)
    XCTAssertEqual(stub.completionRequestCount, authBefore)

    let whitespaceExecute = await fixture.router.routeAsync(
      worldCommandRequest(
        port: port,
        cookie: fixture.cookie,
        body: try worldCommandBody(worldID: worldID, source: "   "),
        endpoint: "execute"
      )
    )
    XCTAssertEqual(whitespaceExecute.statusCode, 400)

    let completionResponse = await fixture.router.routeAsync(
      worldCommandRequest(
        port: port,
        cookie: fixture.cookie,
        body: try worldCommandBody(worldID: worldID, source: ""),
        endpoint: "completions"
      )
    )
    XCTAssertEqual(completionResponse.statusCode, 200)
    XCTAssertEqual(stub.completionRequestCount, 1)
    let executeResponse = await fixture.router.routeAsync(
      worldCommandRequest(
        port: port,
        cookie: fixture.cookie,
        body: try worldCommandBody(worldID: worldID, source: "help"),
        endpoint: "execute"
      )
    )
    XCTAssertEqual(executeResponse.statusCode, 200)
    XCTAssertEqual(stub.executeRequestCount, 1)
    let executeDecoded = try JSONDecoder().decode(
      WorldCommandExecutionResult.self,
      from: executeResponse.body
    )
    XCTAssertEqual(executeDecoded.accepted, true)
  }

  func testWorldCommandRoutesMapServiceErrorsToHTTPStatus() async throws {
    let root = temporaryProductRoot("world-command-errors")
    defer { try? FileManager.default.removeItem(at: root) }
    let port = 43137
    let stub = StubWorldCommandConsoleService()
    let fixture = try authenticatedFixture(root: root, port: port, commandConsole: stub)
    let create = fixture.router.route(
      worldCreationRequest(
        port: port,
        cookie: fixture.cookie,
        body: Data(#"{"name":"Error world"}"#.utf8)
      )
    )
    XCTAssertEqual(create.statusCode, 201)
    let created = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: create.body) as? [String: Any])
    let worldID = try XCTUnwrap(created["id"] as? String)
    let body = try worldCommandBody(worldID: worldID, source: "help")

    stub.setCompletionResult(.failure(WorldCommandConsoleServiceError.busy))
    stub.setExecuteResult(.failure(WorldCommandConsoleServiceError.busy))
    let busyCompletion = await fixture.router.routeAsync(
      worldCommandRequest(port: port, cookie: fixture.cookie, body: body, endpoint: "completions")
    )
    let busyExecute = await fixture.router.routeAsync(
      worldCommandRequest(port: port, cookie: fixture.cookie, body: body, endpoint: "execute")
    )
    XCTAssertEqual(busyCompletion.statusCode, 409)
    XCTAssertEqual(busyExecute.statusCode, 409)

    stub.setCompletionResult(.failure(WorldCommandConsoleServiceError.invalidContext))
    stub.setExecuteResult(.failure(WorldCommandConsoleServiceError.invalidContext))
    let invalidCompletion = await fixture.router.routeAsync(
      worldCommandRequest(port: port, cookie: fixture.cookie, body: body, endpoint: "completions")
    )
    let invalidExecute = await fixture.router.routeAsync(
      worldCommandRequest(port: port, cookie: fixture.cookie, body: body, endpoint: "execute")
    )
    XCTAssertEqual(invalidCompletion.statusCode, 400)
    XCTAssertEqual(invalidExecute.statusCode, 400)

    struct MappingError: Error {}
    stub.setCompletionResult(.failure(MappingError()))
    stub.setExecuteResult(.failure(MappingError()))
    let unknownCompletion = await fixture.router.routeAsync(
      worldCommandRequest(port: port, cookie: fixture.cookie, body: body, endpoint: "completions")
    )
    let unknownExecute = await fixture.router.routeAsync(
      worldCommandRequest(port: port, cookie: fixture.cookie, body: body, endpoint: "execute")
    )
    XCTAssertEqual(unknownCompletion.statusCode, 503)
    XCTAssertEqual(unknownExecute.statusCode, 503)

    let absentService = try authenticatedFixture(
      root: root,
      port: port + 1
    )
    let absentCompletion = await absentService.router.routeAsync(
      worldCommandRequest(
        port: port + 1, cookie: absentService.cookie, body: body, endpoint: "completions")
    )
    XCTAssertEqual(absentCompletion.statusCode, 503)
    let absent = await absentService.router.routeAsync(
      worldCommandRequest(
        port: port + 1, cookie: absentService.cookie, body: body, endpoint: "execute")
    )
    XCTAssertEqual(absent.statusCode, 503)
  }

  func testApplicationRequestsKeepTheir64KiBBudgetWhileWorldCommandsStayAt8KiB() async throws {
    let root = temporaryProductRoot("web-capability-request-budgets")
    defer { try? FileManager.default.removeItem(at: root) }
    let port = 43173
    let capabilityService = StubWebCapabilityService(
      descriptors: [webDescriptor(id: "large-form", interaction: .form)],
      executeResult: webExecutionResult()
    )
    let fixture = try authenticatedFixture(
      root: root,
      port: port,
      webCapabilities: capabilityService
    )

    let exactWebBudget = try webRequestBodyAt64KiB(operationID: "large-form")
    XCTAssertEqual(exactWebBudget.count, 64 * 1_024)
    let accepted = await fixture.router.routeAsync(
      webRequest(
        port: port,
        cookie: fixture.cookie,
        body: exactWebBudget,
        endpoint: "execute"
      )
    )
    XCTAssertEqual(accepted.statusCode, 200)
    XCTAssertEqual(accepted.headers["content-type"], "application/json")
    XCTAssertEqual(capabilityService.executeRequestCount, 1)

    let overWebBudget = await fixture.router.routeAsync(
      webRequest(
        port: port,
        cookie: fixture.cookie,
        body: Data(repeating: 0x78, count: 64 * 1_024 + 1),
        endpoint: "execute"
      )
    )
    XCTAssertEqual(overWebBudget.statusCode, 413)
    XCTAssertEqual(overWebBudget.body, Data(#"{"error":"request_rejected"}"#.utf8))
    XCTAssertEqual(capabilityService.executeRequestCount, 1)

    let overWorldCommandBudget = await fixture.router.routeAsync(
      worldCommandRequest(
        port: port,
        cookie: fixture.cookie,
        body: Data(repeating: 0x78, count: 8 * 1_024 + 1),
        endpoint: "execute"
      )
    )
    XCTAssertEqual(overWorldCommandBudget.statusCode, 413)
    XCTAssertEqual(overWorldCommandBudget.body, Data(#"{"error":"request_rejected"}"#.utf8))
  }

  func testDownloadCapabilityNeverAttachesTruncatedOutputAndKeepsSafeJSONFailures() async throws {
    let root = temporaryProductRoot("web-download-bounds")
    defer { try? FileManager.default.removeItem(at: root) }
    let port = 43174
    let descriptor = webDescriptor(id: "world-export", interaction: .download)
    let capabilityService = StubWebCapabilityService(
      descriptors: [descriptor],
      executeResult: webExecutionResult(
        standardOutput: "{\"world\":\"small\"}\n"
      )
    )
    let fixture = try authenticatedFixture(
      root: root,
      port: port,
      webCapabilities: capabilityService
    )
    let request = webRequest(
      port: port,
      cookie: fixture.cookie,
      body: try webRequestBody(operationID: "world-export"),
      endpoint: "execute"
    )

    let attachment = await fixture.router.routeAsync(request)
    XCTAssertEqual(attachment.statusCode, 200)
    XCTAssertEqual(attachment.headers["content-type"], "application/octet-stream")
    XCTAssertEqual(
      attachment.headers["content-disposition"],
      "attachment; filename=\"mikrokhoros-world-export.txt\""
    )
    XCTAssertEqual(attachment.body, Data("{\"world\":\"small\"}\n".utf8))

    let rejected = webExecutionResult(
      accepted: false,
      standardError: "The export is not available for this World.",
      exitStatus: 1,
      category: .rejected
    )
    capabilityService.setExecuteResult(rejected)
    let rejectedResponse = await fixture.router.routeAsync(request)
    XCTAssertEqual(rejectedResponse.statusCode, 200)
    XCTAssertEqual(rejectedResponse.headers["content-type"], "application/json")
    XCTAssertNil(rejectedResponse.headers["content-disposition"])
    let decodedRejected = try JSONDecoder().decode(
      WebCapabilityExecutionResult.self,
      from: rejectedResponse.body
    )
    XCTAssertEqual(decodedRejected, rejected)

    let oversizedOutput = String(repeating: "w", count: 256 * 1_024 + 1)
    capabilityService.setExecuteResult(
      webExecutionResult(
        standardOutput: oversizedOutput,
        outputTruncated: true
      )
    )
    let truncatedResponse = await fixture.router.routeAsync(request)
    XCTAssertEqual(truncatedResponse.statusCode, 200)
    XCTAssertEqual(truncatedResponse.headers["content-type"], "application/json")
    XCTAssertNil(truncatedResponse.headers["content-disposition"])
    XCTAssertLessThan(truncatedResponse.body.count, 2_048)
    let truncated = try JSONDecoder().decode(
      WebCapabilityExecutionResult.self,
      from: truncatedResponse.body
    )
    XCTAssertFalse(truncated.accepted)
    XCTAssertTrue(truncated.outputTruncated)
    XCTAssertEqual(truncated.category, .failure)
    XCTAssertTrue(truncated.standardOutput.isEmpty)
    XCTAssertFalse(truncated.standardError.contains(oversizedOutput))
  }

  func testWorldCommandStaticConsoleAssetsExposeAccessibilityHooks() throws {
    let root = URL(fileURLWithPath: "/tmp/mikrokhoros-web-command-console", isDirectory: true)
    let router = KhorosWebRouter(
      projection: WorldProjectionService(layout: ProductLayout(canonicalRoot: root))
    )
    router.setEndpoint(port: 43138)
    let headers = ["host": ["127.0.0.1:43138"]]
    let index = router.route(
      KhorosWebRequest(method: "GET", uri: "/", headers: headers)
    )
    XCTAssertEqual(index.statusCode, 200)
    let markup = String(decoding: index.body, as: UTF8.self)
    XCTAssertTrue(markup.contains("id=\"worldCommandForm\""))
    XCTAssertTrue(markup.contains("id=\"worldCommandInput\""))
    XCTAssertTrue(markup.contains("id=\"worldCommandSubmit\""))
    XCTAssertTrue(markup.contains("id=\"commandSuggestions\""))
    XCTAssertTrue(markup.contains("role=\"combobox\""))
    XCTAssertTrue(markup.contains("aria-controls=\"commandSuggestions\""))
    XCTAssertTrue(markup.contains("id=\"worldConsoleDock\""))
    XCTAssertTrue(markup.contains("id=\"consoleOutputLog\""))
    XCTAssertTrue(markup.contains("role=\"log\""))
    XCTAssertTrue(markup.contains("id=\"consoleAgentContextMode\""))
    XCTAssertTrue(markup.contains("id=\"consoleObjectContextMode\""))
    XCTAssertTrue(markup.contains("aria-keyshortcuts=\"1\""))
    XCTAssertTrue(markup.contains("aria-keyshortcuts=\"2\""))
    XCTAssertTrue(markup.contains("aria-keyshortcuts=\"3\""))
    XCTAssertTrue(markup.contains("aria-keyshortcuts=\"C\""))
    XCTAssertTrue(markup.contains("to keep detail"))

    let script = router.route(
      KhorosWebRequest(method: "GET", uri: "/app.js", headers: headers)
    )
    XCTAssertEqual(script.statusCode, 200)
    let code = String(decoding: script.body, as: UTF8.self)
    XCTAssertTrue(code.contains("requestWorldCommand(\"completions\", source)"))
    XCTAssertTrue(code.contains("requestWorldCommand(\"execute\", source)"))
    XCTAssertTrue(code.contains("elements.worldCommandForm"))
    XCTAssertTrue(code.contains("elements.worldCommandInput"))
    XCTAssertTrue(code.contains("elements.worldCommandSubmit"))
    XCTAssertTrue(code.contains("submitWorldCommand"))
    XCTAssertTrue(code.contains("function selectConsoleTab"))
    XCTAssertTrue(code.contains("function toggleConsoleContextFreeze"))
    XCTAssertTrue(code.contains("consoleContextFrozen"))
    XCTAssertTrue(
      code.contains(
        "const shortcutTabs = { \"1\": \"output\", \"2\": \"agent\", "
          + "\"3\": \"object\" }"
      )
    )
    XCTAssertTrue(code.contains("shortcutTarget.matches(\"input, textarea, select\")"))
    XCTAssertTrue(code.contains("state.consoleHover = state.consoleLiveCoordinate"))
    XCTAssertTrue(code.contains("state.consoleHover?.coordinate || state.consoleLastCoordinate"))

    let styleResponse = router.route(
      KhorosWebRequest(method: "GET", uri: "/styles.css", headers: headers)
    )
    XCTAssertEqual(styleResponse.statusCode, 200)
    let styles = String(decoding: styleResponse.body, as: UTF8.self)
    XCTAssertTrue(styles.contains(".console-tab-shortcut"))
    XCTAssertTrue(styles.contains(".console-context-mode.is-kept"))
  }

  func testCommandExecutionTruncatesTranscriptForSmallOutputLimit() async throws {
    let root = temporaryProductRoot("world-command-transcript")
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try WorldCreationService(layout: ProductLayout(canonicalRoot: root)).createBareWorld(
      name: "Transcript")
    let transcript = await CommandExecutor.executeTranscript(
      arguments: ["help"],
      layout: ProductLayout(canonicalRoot: root),
      maximumOutputBytes: 1
    )
    XCTAssertTrue(transcript.outputTruncated)
    XCTAssertLessThanOrEqual(transcript.standardOutput.count + transcript.standardError.count, 2)
  }

  func testWorldCommandExecuteRejectsDisallowedAndGlobalOptionInputWithoutEcho() async throws {
    let root = temporaryProductRoot("world-command-echo")
    defer { try? FileManager.default.removeItem(at: root) }
    let layout = ProductLayout(canonicalRoot: root)
    let created = try WorldCreationService(layout: layout).createBareWorld(name: "Display")
    let service = CLIWorldCommandConsoleService()
    let denied = try await service.execute(
      WorldCommandConsoleRequest(layout: layout, worldID: created.id, source: "status --json")
    )
    let deniedEchoCandidate = "status --json"
    XCTAssertFalse(denied.accepted)
    XCTAssertNotEqual(denied.displayCommand, deniedEchoCandidate)
    XCTAssertFalse(denied.standardError.contains(deniedEchoCandidate))

    let globalCommand = "--world \(created.id) help"
    let withGlobal = try await service.execute(
      WorldCommandConsoleRequest(layout: layout, worldID: created.id, source: globalCommand)
    )
    let globalEchoCandidate = "help --world \(created.id)"
    XCTAssertFalse(withGlobal.accepted)
    XCTAssertNotEqual(withGlobal.displayCommand, globalCommand)
    XCTAssertNotEqual(withGlobal.displayCommand, globalEchoCandidate)
    XCTAssertFalse(withGlobal.standardError.contains("--world"))

    for (source, command) in [
      ("world object interface " + String(repeating: "a", count: 32), "world object interface"),
      ("world object action list " + String(repeating: "a", count: 32), "world object action list"),
    ] {
      let protectedManagement = try await service.execute(
        WorldCommandConsoleRequest(layout: layout, worldID: created.id, source: source)
      )
      XCTAssertFalse(protectedManagement.accepted, source)
      XCTAssertEqual(protectedManagement.displayCommand, command, source)
      XCTAssertTrue(
        protectedManagement.standardError.contains("terminal CLI or its dedicated app view"),
        source
      )
      XCTAssertFalse(
        protectedManagement.standardOutput.contains("/private/management-workspace"), source)
      XCTAssertFalse(
        protectedManagement.standardError.contains("/private/management-workspace"), source)
    }
  }

  func testWorldReportProjectionEnforcesFiniteAggregateByteBudget() throws {
    let lineage = ObjectLineage(
      packageID: "org.mikrokhoros.audit",
      packageVersion: "1.0.0",
      packageHash: String(repeating: "a", count: 64),
      inventoryObjectID: String(repeating: "b", count: 32),
      inventoryRevision: 1,
      deploymentID: String(repeating: "c", count: 32)
    )
    let newest = ObjectReport(
      id: String(repeating: "d", count: 32),
      timestamp: Date(timeIntervalSince1970: 2),
      worldID: String(repeating: "e", count: 32),
      objectID: String(repeating: "f", count: 32),
      lineage: lineage,
      type: "status",
      title: "Newest",
      body: String(repeating: "n", count: 2_048),
      payload: .null
    )
    let older = ObjectReport(
      id: String(repeating: "1", count: 32),
      timestamp: Date(timeIntervalSince1970: 1),
      worldID: newest.worldID,
      objectID: newest.objectID,
      lineage: lineage,
      type: "status",
      title: "Older",
      body: String(repeating: "o", count: 2_048),
      payload: .null
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let newestByteCount = try encoder.encode(WorldReportSnapshot(newest)).count
    let budget = newestByteCount + 2

    let projected = try WorldProjectionService.boundedReports(
      [older, newest],
      limit: 32,
      maximumBytes: budget
    )
    XCTAssertEqual(projected.map(\.id), [newest.id])
    XCTAssertLessThanOrEqual(try encoder.encode(projected).count, budget)

    let rejectedOversized = try WorldProjectionService.boundedReports(
      [newest],
      limit: 32,
      maximumBytes: newestByteCount + 1
    )
    XCTAssertTrue(rejectedOversized.isEmpty)
  }

  func testWorldProjectionCollectionPrefixesAreFiniteAndDeterministic() {
    let visual = WorldVisualIdentitySnapshot(shapeIndex: 0, colorIndex: 0)
    let worldEntries = (0...WorldProjectionService.maximumWorldPickerEntries).map { index in
      WorldPickerEntry(id: "world-\(index)", name: "World \(index)", isCurrent: index == 0)
    }
    let projectedWorlds = WorldProjectionService.boundedWorldPickerEntries(worldEntries)
    XCTAssertEqual(
      projectedWorlds,
      Array(worldEntries.prefix(WorldProjectionService.maximumWorldPickerEntries))
    )

    let otherAgents = (0...WorldProjectionService.maximumOtherAgentEntries).map { index in
      WorldAgentSnapshot(
        id: "agent-\(index)",
        name: "Agent \(index)",
        containerID: "container",
        coordinate: .init(x: index, y: 0),
        path: "/world",
        visual: visual,
        isFocused: false
      )
    }
    let projectedOtherAgents = WorldProjectionService.boundedOtherAgentEntries(otherAgents)
    XCTAssertEqual(
      projectedOtherAgents,
      Array(otherAgents.prefix(WorldProjectionService.maximumOtherAgentEntries))
    )

    let objects = (0...WorldProjectionService.maximumObjectEntries).map { index in
      WorldObjectSnapshot(
        id: "object-\(index)",
        name: "Object \(index)",
        type: "fixture",
        summary: "fixture",
        coordinate: .init(x: index, y: 0),
        hasContainer: false,
        canMove: true,
        path: "/world",
        visual: visual
      )
    }
    let projectedObjects = WorldProjectionService.boundedObjectEntries(objects)
    XCTAssertEqual(
      projectedObjects,
      Array(objects.prefix(WorldProjectionService.maximumObjectEntries))
    )
  }

  func testStaticResourcesAreUnauthenticatedAndPathQueriesAreRejected() {
    let root = URL(fileURLWithPath: "/tmp/mikrokhoros-web-static", isDirectory: true)
    let router = KhorosWebRouter(
      projection: WorldProjectionService(layout: ProductLayout(canonicalRoot: root))
    )
    router.setEndpoint(port: 43129)
    let commonHeaders = ["host": ["127.0.0.1:43129"]]
    let assertStaticAsset: (String, String) -> Void = { path, mimeType in
      let response = router.route(
        KhorosWebRequest(
          method: "GET",
          uri: path,
          headers: commonHeaders
        )
      )
      XCTAssertEqual(response.statusCode, 200, path)
      XCTAssertEqual(response.headers["content-type"], mimeType, path)
      XCTAssertFalse(response.body.isEmpty, path)
      let head = router.route(
        KhorosWebRequest(
          method: "HEAD",
          uri: path,
          headers: commonHeaders
        )
      )
      XCTAssertEqual(head.statusCode, 200, path)
      XCTAssertTrue(head.body.isEmpty, path)
      XCTAssertEqual(head.headers["content-length"], response.headers["content-length"], path)
      XCTAssertEqual(head.headers["content-type"], mimeType, path)
      if path != "/" {
        XCTAssertEqual(
          router.route(
            KhorosWebRequest(
              method: "GET",
              uri: "\(path)?v=1",
              headers: commonHeaders
            )
          ).statusCode,
          400,
          path
        )
      }
    }
    [
      ("/", "text/html; charset=utf-8"),
      ("/styles.css", "text/css; charset=utf-8"),
      ("/app.js", "text/javascript; charset=utf-8"),
      ("/fonts/google-sans-flex.woff2", "font/woff2"),
      ("/fonts/google-sans-flex-latin.woff2", "font/woff2"),
      ("/fonts/google-sans-flex-latin-ext.woff2", "font/woff2"),
      ("/fonts/google-sans-flex-vietnamese.woff2", "font/woff2"),
    ].forEach(assertStaticAsset)

    let document = router.route(
      KhorosWebRequest(method: "GET", uri: "/", headers: commonHeaders)
    )
    let routeIdentity = String(repeating: "a", count: 32)
    let validDocumentRoutes = [
      "/?view=agentManager",
      "/?view=inventory&source=inventory-source",
      "/?view=packages&package=org.mikrokhoros.paper&version=1.0.0",
      "/?view=templates&template=default-khoros%401.0.0",
      "/?view=settings&setting=appearance",
      "/?world=\(routeIdentity)&container=\(routeIdentity)&focus=\(routeIdentity)",
    ]
    for uri in validDocumentRoutes {
      let response = router.route(
        KhorosWebRequest(method: "GET", uri: uri, headers: commonHeaders)
      )
      XCTAssertEqual(response.statusCode, 200, uri)
      XCTAssertEqual(response.headers["content-type"], "text/html; charset=utf-8", uri)
      XCTAssertEqual(response.headers["cache-control"], "no-store", uri)
      XCTAssertNil(response.headers["set-cookie"], uri)
      XCTAssertEqual(response.body, document.body, uri)

      let head = router.route(
        KhorosWebRequest(method: "HEAD", uri: uri, headers: commonHeaders)
      )
      XCTAssertEqual(head.statusCode, 200, uri)
      XCTAssertTrue(head.body.isEmpty, uri)
      XCTAssertEqual(head.headers["content-length"], response.headers["content-length"], uri)
    }

    let invalidDocumentRoutes = [
      "/?v=1",
      "/?view=unknown",
      "/?view=inventory&view=packages",
      "/?view=",
      "/?world=not-an-exact-id",
      "/?container=\(routeIdentity)&container=\(routeIdentity)",
      "/?source=\(String(repeating: "s", count: 257))",
      "/?source=%0A",
    ]
    for uri in invalidDocumentRoutes {
      let response = router.route(
        KhorosWebRequest(method: "GET", uri: uri, headers: commonHeaders)
      )
      XCTAssertEqual(response.statusCode, 400, uri)
      XCTAssertEqual(response.body, Data(#"{"error":"request_rejected"}"#.utf8), uri)
    }

    let phosphor = [
      "archive",
      "arrow-elbow-down-left",
      "arrow-left",
      "arrow-square-out",
      "bell",
      "caret-down",
      "check",
      "circle-notch",
      "crosshair",
      "cube",
      "dots-three",
      "eye",
      "file-text",
      "gear-six",
      "globe",
      "info",
      "magnifying-glass",
      "magnifying-glass-minus",
      "magnifying-glass-plus",
      "package",
      "plus",
      "push-pin",
      "shield",
      "sidebar-simple",
      "user-plus",
      "x",
    ]
    var phosphorPayloads = Set<Data>()
    for name in phosphor {
      assertStaticAsset("/icons/phosphor/\(name).svg", "image/svg+xml")
      let response = router.route(
        KhorosWebRequest(
          method: "GET",
          uri: "/icons/phosphor/\(name).svg",
          headers: commonHeaders
        )
      )
      phosphorPayloads.insert(response.body)
    }

    let identity = [
      "heart",
      "hexagon",
      "pentagon",
      "seal",
      "shield",
      "square",
      "star",
      "triangle",
    ]
    var identityPayloads = Set<Data>()
    for name in identity {
      assertStaticAsset("/identity-shapes/\(name).svg", "image/svg+xml")
      let response = router.route(
        KhorosWebRequest(
          method: "GET",
          uri: "/identity-shapes/\(name).svg",
          headers: commonHeaders
        )
      )
      let markup = String(decoding: response.body, as: UTF8.self)
      XCTAssertTrue(markup.contains("viewBox=\"0 0 256 256\""), name)
      XCTAssertTrue(markup.contains("aria-hidden=\"true\""), name)
      XCTAssertTrue(markup.contains("focusable=\"false\""), name)
      XCTAssertTrue(markup.contains("<path fill=\"currentColor\""), name)
      XCTAssertEqual(markup.components(separatedBy: "<path").count - 1, 1, name)
      XCTAssertFalse(markup.contains("stroke="), name)
      XCTAssertFalse(markup.contains("<g"), name)
      XCTAssertFalse(markup.contains("<circle"), name)
      XCTAssertFalse(markup.contains("<rect"), name)
      XCTAssertFalse(phosphorPayloads.contains(response.body), name)
      if name == "shield" {
        let digest = SHA256.hash(data: response.body)
          .map { String(format: "%02x", $0) }
          .joined()
        XCTAssertEqual(
          digest,
          "435db35a8dd31a78156c7094391e1f65cbba048fa368129063b085dac947401d"
        )
      }
      identityPayloads.insert(response.body)
    }
    XCTAssertEqual(identityPayloads.count, identity.count)
    XCTAssertEqual(
      router.route(
        KhorosWebRequest(
          method: "GET",
          uri: "/identity-shapes/circle.svg",
          headers: commonHeaders
        )
      ).statusCode,
      404
    )
    XCTAssertEqual(
      router.route(
        KhorosWebRequest(
          method: "GET",
          uri: "/icons/phosphor/does-not-exist.svg",
          headers: commonHeaders
        )
      ).statusCode,
      404
    )
    XCTAssertEqual(
      router.route(
        KhorosWebRequest(
          method: "GET",
          uri: "/icons/phosphor",
          headers: commonHeaders
        )
      ).statusCode,
      404
    )
    XCTAssertEqual(
      router.route(
        KhorosWebRequest(
          method: "GET",
          uri: "/api/v2/world",
          headers: commonHeaders
        )
      ).statusCode,
      404
    )
    XCTAssertEqual(
      router.route(
        KhorosWebRequest(
          method: "GET",
          uri: "/icons/%2e%2e%2fstyles.css",
          headers: commonHeaders
        )
      ).statusCode,
      400
    )
    XCTAssertEqual(
      router.route(
        KhorosWebRequest(
          method: "GET",
          uri: "/styles.css?namespace.value=1",
          headers: commonHeaders
        )
      ).statusCode,
      400
    )
    XCTAssertEqual(
      router.route(
        KhorosWebRequest(
          method: "PUT",
          uri: "/styles.css",
          headers: commonHeaders
        )
      ).statusCode,
      405
    )
  }

  func testWorldStaticResourcesKeepCellAndControlInteractionContracts() throws {
    let root = URL(fileURLWithPath: "/tmp/mikrokhoros-web-contract", isDirectory: true)
    let router = KhorosWebRouter(
      projection: WorldProjectionService(layout: ProductLayout(canonicalRoot: root))
    )
    router.setEndpoint(port: 43130)
    let headers = ["host": ["127.0.0.1:43130"]]
    let resource: (String) throws -> String = { path in
      let response = router.route(
        KhorosWebRequest(method: "GET", uri: path, headers: headers)
      )
      XCTAssertEqual(response.statusCode, 200, path)
      return String(decoding: response.body, as: UTF8.self)
    }

    let markup = try resource("/")
    for line in markup.split(separator: "\n") where line.contains("<img") {
      XCTAssertTrue(line.contains("src=\"/icons/phosphor/"), String(line))
    }
    XCTAssertFalse(markup.contains("<svg"))
    XCTAssertEqual(
      markup.components(separatedBy: "/icons/phosphor/magnifying-glass.svg").count - 1,
      2
    )
    XCTAssertEqual(
      markup.components(separatedBy: "/icons/phosphor/magnifying-glass-plus.svg").count - 1,
      1
    )
    XCTAssertTrue(markup.contains("/icons/phosphor/arrow-elbow-down-left.svg"))
    XCTAssertFalse(markup.contains(">↵<"))
    XCTAssertTrue(markup.contains("id=\"cellQuickMenu\""))
    XCTAssertFalse(markup.contains("cellTooltip"))
    XCTAssertFalse(markup.contains("humanViewSummary"))
    XCTAssertFalse(markup.contains("/icons/phosphor/eye.svg"))
    let helpLine = try XCTUnwrap(
      markup.split(separator: "\n").first(where: { $0.contains("id=\"helpButton\"") })
    )
    XCTAssertFalse(helpLine.contains("settings-control"))
    XCTAssertFalse(markup.contains("id=\"operationSearch\""))
    XCTAssertFalse(markup.contains("id=\"operationCatalog\""))
    XCTAssertFalse(markup.contains("id=\"operationCatalogEmpty\""))
    XCTAssertTrue(markup.contains("id=\"sidebarResizeHandle\""))
    XCTAssertTrue(markup.contains("role=\"separator\""))
    XCTAssertTrue(markup.contains("aria-orientation=\"vertical\""))
    XCTAssertTrue(markup.contains("aria-valuemin=\"208\""))
    XCTAssertTrue(markup.contains("aria-valuemax=\"352\""))
    XCTAssertTrue(markup.contains("aria-valuenow=\"240\""))
    XCTAssertTrue(markup.contains("id=\"workspaceRefresh\""))
    XCTAssertTrue(markup.contains("aria-label=\"Refresh\""))
    XCTAssertEqual(markup.components(separatedBy: "Create new world").count - 1, 1)
    XCTAssertTrue(
      markup.contains(
        "<section class=\"compact-dialog\" id=\"worldCreateDialog\" role=\"dialog\" "
          + "aria-modal=\"true\""
      )
    )
    XCTAssertTrue(markup.contains("aria-labelledby=\"worldCreateTitle\""))
    XCTAssertTrue(markup.contains("aria-describedby=\"worldCreateDescription\""))
    XCTAssertTrue(markup.contains("<label class=\"field-label\" for=\"worldNameInput\">"))
    XCTAssertTrue(markup.contains("id=\"worldNameInput\""))
    XCTAssertTrue(markup.contains("maxlength=\"128\""))
    XCTAssertTrue(markup.contains("required"))
    XCTAssertFalse(markup.contains("floating-menu all-agents-menu"))
    XCTAssertFalse(markup.contains("id=\"allAgentsMenu\""))
    XCTAssertTrue(markup.contains("id=\"allAgentsLabel\">All 3 agents</span>"))
    XCTAssertFalse(markup.contains("id=\"allAgentsCount\""))
    XCTAssertFalse(markup.contains("World unavailable"))
    XCTAssertFalse(markup.contains("khoros world create"))
    XCTAssertFalse(markup.contains("khoros init"))
    let submitLine = try XCTUnwrap(
      markup.split(separator: "\n").first(where: { $0.contains("id=\"worldCreateSubmit\"") })
    )
    XCTAssertFalse(submitLine.contains("glass-control"))

    let script = try resource("/app.js")
    XCTAssertFalse(script.contains("createElement(\"svg\")"))
    XCTAssertFalse(script.contains("data:image"))
    XCTAssertTrue(
      script.contains(
        "[\"Read setting\", \"magnifying-glass\", NATIVE_ACTION_CANDIDATES.readSetting]"
      )
    )
    XCTAssertFalse(script.contains("[\"Read setting\", \"magnifying-glass-plus\""))
    XCTAssertTrue(script.contains("agentOrderByWorld: new Map()"))
    XCTAssertTrue(script.contains("function openCellQuickMenu"))
    XCTAssertTrue(script.contains("\"Empty position\""))
    XCTAssertTrue(script.contains("event.key === \"Enter\" || event.key === \" \""))
    XCTAssertTrue(script.contains("function structuralPathForSnapshot"))
    XCTAssertTrue(script.contains("snapshot?.focusedAgentID !== state.followedAgentID"))
    XCTAssertTrue(script.contains("updateStructuralPath();"))
    XCTAssertFalse(script.contains("if (state.following) recenterOnFollow();"))
    XCTAssertTrue(
      script.contains(
        "const availableHeight = Math.max(0, rect.height - consoleOcclusionHeight());"
      )
    )
    XCTAssertTrue(
      script.contains("const startY = Math.ceil(state.cameraY - halfUsableRows + 0.5);")
    )
    XCTAssertTrue(
      script.contains("const endY = Math.floor(state.cameraY + halfUsableRows - 0.5);")
    )
    XCTAssertTrue(script.contains("consumeNextEmptyCellActivation: false"))
    XCTAssertTrue(script.contains("function shouldConsumeEmptyCellDismissal"))
    XCTAssertTrue(script.contains("activeSurface?.panel === elements.cellQuickMenu"))
    XCTAssertTrue(script.contains("activeSurface.trigger.classList.contains(\"is-occupied\")"))
    XCTAssertTrue(script.contains("target.closest(\".world-cell.is-empty\")"))
    XCTAssertTrue(script.contains("state.consumeNextEmptyCellActivation = true;"))
    XCTAssertFalse(script.contains("showCellTooltip"))
    XCTAssertTrue(
      script.contains("elements.primaryAgents.replaceChildren(...visible.map(agentRow));"))
    XCTAssertFalse(script.contains("promoteAgentOrder"))
    XCTAssertTrue(script.contains("ordered.slice(0, 3)"))
    XCTAssertTrue(script.contains("`All ${all.length} agents`"))
    XCTAssertTrue(script.contains("all.length >= 3"))
    XCTAssertTrue(script.contains("expandedAgentWorlds: new Set()"))
    XCTAssertFalse(script.contains("allAgentsMenu"))
    XCTAssertFalse(script.contains("allAgentsCount"))
    XCTAssertFalse(script.contains("Choose from all"))
    XCTAssertTrue(script.contains("Create new world"))
    XCTAssertTrue(script.contains("renderWorldPicker(null);"))
    XCTAssertTrue(script.contains("elements.worldTrigger.disabled = false;"))
    XCTAssertFalse(script.contains("elements.worldTrigger.disabled = true;"))
    XCTAssertTrue(
      script.contains("const createRow = node(\"button\", \"menu-row create-world-row\")"))
    XCTAssertTrue(script.contains("createRow.addEventListener(\"click\", openWorldCreateDialog)"))
    XCTAssertTrue(script.contains("window.fetch(\"/api/v1/worlds\""))
    XCTAssertTrue(script.contains("if (state.worldCreateInFlight) return;"))
    XCTAssertTrue(script.contains("setWorldCreateBusy(true);"))
    XCTAssertTrue(script.contains("if (response.status !== 201)"))
    XCTAssertTrue(script.contains("!isExactID(result.id)"))
    XCTAssertTrue(script.contains("restoreHumanViewForWorld(created.id"))
    XCTAssertFalse(script.contains("prompt("))
    XCTAssertFalse(script.contains("innerHTML"))
    XCTAssertTrue(script.contains("agentRetry"))
    XCTAssertTrue(script.contains("function managementInputSchema"))
    XCTAssertTrue(script.contains("Required capabilities"))
    XCTAssertTrue(script.contains("\"None required\""))
    XCTAssertTrue(script.contains("Payload schema"))
    XCTAssertTrue(script.contains("sourceForkProvenance"))
    XCTAssertTrue(
      script.contains(
        "if (fork && (fork.parentSourceID || fork.parentRevision !== null || fork.forkedAt))"
      )
    )
    XCTAssertFalse(script.contains("if (fork?.parentSourceID || fork?.parentRevision !== null"))
    XCTAssertTrue(script.contains("actionWorldLock"))
    XCTAssertTrue(script.contains("function openReportDetail"))
    XCTAssertTrue(script.contains("function compactOverflowControl"))
    XCTAssertTrue(
      script.contains(
        "section.id === \"details\" && isExactID(exactObject?.id) && exactObject.canMove === true"
      )
    )
    XCTAssertTrue(script.contains("const placementByLocalID = new Map"))
    XCTAssertTrue(script.contains("if (placement.kind === \"owned\")"))
    XCTAssertTrue(
      script.contains("component?.inventoryName || placement.componentKey")
    )
    XCTAssertTrue(script.contains("contentSection(\"Objects\", table)"))
    XCTAssertTrue(script.contains("`${objectCount} object${objectCount === 1 ? \"\" : \"s\"}`"))
    XCTAssertTrue(script.contains("label: \"Template help\""))
    XCTAssertTrue(script.contains("return \"world template\";"))
    XCTAssertTrue(script.contains("label: \"Assignment\""))
    XCTAssertTrue(script.contains("label: \"State\""))
    XCTAssertTrue(script.contains("label: \"All states\""))
    XCTAssertTrue(script.contains("const anchor = node(\"div\", \"agent-filter-anchor\")"))
    XCTAssertTrue(
      script.contains("const menu = node(\"div\", \"floating-menu agent-filter-menu\")")
    )
    XCTAssertTrue(script.contains("node(\"button\", \"menu-row menu-row-text-only\")"))
    XCTAssertTrue(
      script.contains(
        "node(\"button\", \"menu-row menu-row-text-only web-autocomplete-option\")"
      )
    )
    XCTAssertTrue(
      script.contains(
        "node(\"button\", \"menu-row menu-row-text-only web-combobox-option\")"
      )
    )
    let filterControl = try XCTUnwrap(
      script.components(separatedBy: "function compactProjectionFilterControl").dropFirst().first?
        .components(separatedBy: "function settingsSections").first
    )
    XCTAssertFalse(filterControl.contains("template-overflow"))
    XCTAssertFalse(script.contains("World unavailable"))
    XCTAssertFalse(script.contains("khoros world create"))
    XCTAssertFalse(script.contains("khoros init"))
    XCTAssertTrue(script.contains("enabled: raw.enabled !== false"))
    XCTAssertTrue(script.contains("capability.id === id && capability.enabled"))
    XCTAssertTrue(script.contains("Host filesystem paths are available only in the local CLI."))
    XCTAssertTrue(script.contains("function managementContractUsesHostPaths"))
    XCTAssertTrue(script.contains("function managementViewIsCLIOnly"))
    XCTAssertTrue(
      script.contains("String(view?.source || \"\").toLocaleLowerCase() === \"configuration\"")
    )
    XCTAssertTrue(script.contains("icon(\"cube\", \"template-object-icon\")"))
    XCTAssertFalse(script.contains("templateDefinitionVisual"))
    XCTAssertFalse(script.contains("template-object-symbol"))
    XCTAssertTrue(script.contains("SIDEBAR_MIN_WIDTH = 208"))
    XCTAssertTrue(script.contains("SIDEBAR_DEFAULT_WIDTH = 240"))
    XCTAssertTrue(script.contains("SIDEBAR_MAX_WIDTH = 352"))
    XCTAssertTrue(script.contains("SIDEBAR_MIN_MAIN_WIDTH = 480"))
    XCTAssertTrue(script.contains("sidebarResizeGesture: null"))
    XCTAssertTrue(script.contains("function updateSidebarResizeHandle"))
    XCTAssertTrue(script.contains("function finishSidebarResize"))
    XCTAssertTrue(
      script.contains("elements.sidebarResizeHandle.setPointerCapture(event.pointerId)")
    )
    XCTAssertTrue(
      script.contains("elements.sidebarResizeHandle.addEventListener(\"pointercancel\"")
    )
    XCTAssertTrue(
      script.contains("elements.sidebarResizeHandle.addEventListener(\"lostpointercapture\"")
    )
    XCTAssertTrue(script.contains("if (event.key === \"ArrowLeft\")"))
    XCTAssertTrue(script.contains("if (event.key === \"ArrowRight\")"))
    XCTAssertTrue(script.contains("if (event.key === \"Home\")"))
    XCTAssertTrue(script.contains("if (event.key === \"End\")"))
    XCTAssertTrue(script.contains("if (event.key === \"0\")"))
    XCTAssertTrue(script.contains("event.key !== \"Escape\" || !state.sidebarResizeGesture"))
    XCTAssertTrue(script.contains("const rawSidebar = parsed && typeof parsed.sidebar"))
    XCTAssertTrue(script.contains("next.sidebar = { width: state.sidebarPreferredWidth }"))
    XCTAssertTrue(script.contains("workspaceScrollPositions: new Map()"))
    XCTAssertTrue(script.contains("domainSidebarScrollPositions: new Map()"))
    XCTAssertTrue(script.contains("function workspaceDetailScrollKey"))
    XCTAssertTrue(script.contains("function rememberWorkspaceScroll"))
    XCTAssertTrue(script.contains("function restoreWorkspaceScroll"))
    XCTAssertTrue(script.contains("state.workspaceScrollPositions.set("))
    XCTAssertTrue(script.contains("state.domainSidebarScrollPositions.set("))
    XCTAssertTrue(script.contains("window.requestAnimationFrame(() =>"))
    XCTAssertTrue(script.contains("updateRoute(initial, \"replace\")"))
    XCTAssertTrue(script.contains("switchWebView(initial.view, { historyMode: null })"))
    XCTAssertTrue(script.contains("if (isCompactSidebarViewport()) setSidebarCollapsed(true)"))

    let styles = try resource("/styles.css")
    XCTAssertTrue(styles.contains("--cell-size: 48px"))
    XCTAssertTrue(styles.contains("--workspace-column-max: 1080px"))
    XCTAssertTrue(styles.contains("--workspace-inline-gutter: clamp(18px, 2.4vw, 36px)"))
    XCTAssertTrue(styles.contains("--smooth-corner: superellipse(1.78)"))
    let workspaceHeaderStyles = try XCTUnwrap(
      cssBlocks(named: ".workspace-header", in: styles).first(where: {
        $0.contains("var(--workspace-column-max)")
      })
    )
    XCTAssertTrue(workspaceHeaderStyles.contains("var(--workspace-column-max)"))
    XCTAssertTrue(workspaceHeaderStyles.contains("var(--workspace-inline-gutter)"))
    XCTAssertTrue(workspaceHeaderStyles.contains("margin-inline: auto"))
    XCTAssertTrue(workspaceHeaderStyles.contains("padding: 10px 0 8px"))
    let workspaceScrollRegionStyles = try XCTUnwrap(
      cssBlocks(named: ".workspace-scroll-region", in: styles).first(where: {
        $0.contains("overflow-y: auto")
      })
    )
    XCTAssertTrue(
      workspaceScrollRegionStyles.contains(
        "padding: 0 var(--workspace-inline-gutter) 32px"
      )
    )
    let workspaceContentStyles = try XCTUnwrap(
      cssBlocks(named: ".workspace-content", in: styles).first
    )
    XCTAssertTrue(workspaceContentStyles.contains("gap: 16px"))
    XCTAssertTrue(workspaceContentStyles.contains("width: 100%"))
    XCTAssertTrue(workspaceContentStyles.contains("max-width: var(--workspace-column-max)"))
    XCTAssertTrue(workspaceContentStyles.contains("margin-inline: auto"))
    let workspaceStateStyles = try XCTUnwrap(cssBlock(named: ".workspace-state", in: styles))
    XCTAssertTrue(workspaceStateStyles.contains("width: 100%"))
    XCTAssertTrue(workspaceStateStyles.contains("max-width: var(--workspace-column-max)"))
    let nativeDetailSectionStyles = try XCTUnwrap(
      cssBlock(named: ".native-detail-section", in: styles)
    )
    XCTAssertTrue(nativeDetailSectionStyles.contains("gap: 8px"))
    XCTAssertTrue(nativeDetailSectionStyles.contains("padding: 0"))
    let nativeSectionTitleStyles = try XCTUnwrap(
      cssBlock(named: ".native-section-title", in: styles)
    )
    XCTAssertTrue(nativeSectionTitleStyles.contains("margin: 0"))
    let nativeDetailCopyStyles = try XCTUnwrap(
      cssBlock(named: ".native-detail-copy", in: styles)
    )
    XCTAssertTrue(nativeDetailCopyStyles.contains("margin: 0"))
    XCTAssertTrue(styles.contains("@container web-workspace (max-width: 820px)"))
    XCTAssertTrue(styles.contains(".app-shell[data-sidebar=\"expanded\"] .domain-sidebar"))
    XCTAssertTrue(
      cssBlocks(named: ".domain-sidebar", in: styles).contains(where: {
        $0.contains("display: none")
      })
    )
    XCTAssertEqual(styles.components(separatedBy: "corner-shape: round").count - 1, 3)
    for roundedBlock in styles.components(separatedBy: "}")
    where roundedBlock.contains("border-radius:") && !roundedBlock.contains("border-radius: 0") {
      XCTAssertTrue(
        roundedBlock.contains("corner-shape: var(--smooth-corner)")
          || roundedBlock.contains("corner-shape: inherit")
          || (roundedBlock.contains("border-radius: 50%")
            && roundedBlock.contains("corner-shape: round")),
        roundedBlock
      )
    }
    let glassControlStyles = try XCTUnwrap(
      styles.components(separatedBy: ".glass-control {").dropFirst().first?
        .components(separatedBy: "}").first
    )
    XCTAssertTrue(glassControlStyles.contains("height: var(--control-height)"))
    XCTAssertTrue(glassControlStyles.contains("min-height: var(--control-height)"))
    XCTAssertTrue(glassControlStyles.contains("line-height: 20px"))
    XCTAssertFalse(glassControlStyles.contains("line-height: 1;"))
    let controlLabelStyles = try XCTUnwrap(
      styles.components(separatedBy: ".control-label {").dropFirst().first?
        .components(separatedBy: "}").first
    )
    XCTAssertTrue(controlLabelStyles.contains("overflow: hidden"))
    XCTAssertTrue(controlLabelStyles.contains("text-overflow: ellipsis"))
    let domainSearchStyles = try XCTUnwrap(cssBlock(named: ".domain-search-wrap", in: styles))
    XCTAssertTrue(domainSearchStyles.contains("height: var(--control-height)"))
    XCTAssertTrue(domainSearchStyles.contains("border-radius: var(--pill-radius)"))
    XCTAssertTrue(domainSearchStyles.contains("corner-shape: var(--smooth-corner)"))
    let domainEntityStyles = try XCTUnwrap(cssBlock(named: ".domain-entity-row", in: styles))
    XCTAssertTrue(domainEntityStyles.contains("border-radius: 12px"))
    XCTAssertFalse(domainEntityStyles.contains("var(--pill-radius)"))
    let nativeButtonStyles = try XCTUnwrap(cssBlock(named: ".native-button", in: styles))
    XCTAssertTrue(nativeButtonStyles.contains("height: var(--control-height)"))
    XCTAssertTrue(nativeButtonStyles.contains("min-height: var(--control-height)"))
    XCTAssertTrue(nativeButtonStyles.contains("border-radius: var(--pill-radius)"))
    XCTAssertTrue(nativeButtonStyles.contains("corner-shape: var(--smooth-corner)"))
    let comboboxTriggerStyles = try XCTUnwrap(
      cssBlock(named: ".web-combobox-trigger", in: styles)
    )
    XCTAssertTrue(comboboxTriggerStyles.contains("height: var(--control-height)"))
    XCTAssertTrue(comboboxTriggerStyles.contains("min-height: var(--control-height)"))
    XCTAssertTrue(comboboxTriggerStyles.contains("border-radius: var(--pill-radius)"))
    XCTAssertTrue(comboboxTriggerStyles.contains("corner-shape: var(--smooth-corner)"))
    let modalControlStyles = try XCTUnwrap(cssBlock(named: ".modal-control", in: styles))
    XCTAssertTrue(modalControlStyles.contains("height: var(--control-height)"))
    XCTAssertTrue(modalControlStyles.contains("border-radius: var(--pill-radius)"))
    XCTAssertTrue(modalControlStyles.contains("corner-shape: var(--smooth-corner)"))
    let dialogButtonStyles = try XCTUnwrap(cssBlock(named: ".dialog-button", in: styles))
    XCTAssertTrue(dialogButtonStyles.contains("height: var(--control-height)"))
    XCTAssertTrue(dialogButtonStyles.contains("border-radius: var(--pill-radius)"))
    XCTAssertTrue(dialogButtonStyles.contains("corner-shape: var(--smooth-corner)"))
    let actionButtonBlock = styles.components(
      separatedBy: ".action-button,\n.secondary-button,\n.copy-button {"
    )
    .dropFirst()
    .first?
    .components(separatedBy: "}")
    .first
    let actionButtonStyles = try XCTUnwrap(actionButtonBlock)
    XCTAssertTrue(actionButtonStyles.contains("height: var(--control-height)"))
    XCTAssertTrue(actionButtonStyles.contains("min-height: var(--control-height)"))
    XCTAssertTrue(actionButtonStyles.contains("border-radius: var(--pill-radius)"))
    XCTAssertTrue(actionButtonStyles.contains("corner-shape: var(--smooth-corner)"))
    let closeButtonStyles = try XCTUnwrap(
      cssBlock(named: ".native-action-dialog .dialog-close", in: styles)
    )
    XCTAssertTrue(closeButtonStyles.contains("width: 32px"))
    XCTAssertTrue(closeButtonStyles.contains("height: 32px"))
    XCTAssertTrue(closeButtonStyles.contains("border-radius: var(--pill-radius)"))
    XCTAssertTrue(closeButtonStyles.contains("corner-shape: var(--smooth-corner)"))
    let worldDetailActionStyles = try XCTUnwrap(cssBlock(named: ".world-detail-action", in: styles))
    XCTAssertTrue(worldDetailActionStyles.contains("height: var(--control-height)"))
    XCTAssertTrue(worldDetailActionStyles.contains("min-height: var(--control-height)"))
    XCTAssertTrue(worldDetailActionStyles.contains("border-radius: var(--pill-radius)"))
    XCTAssertTrue(worldDetailActionStyles.contains("corner-shape: var(--smooth-corner)"))
    let selectorTriggerStyles = try XCTUnwrap(
      cssBlock(named: ".text-field.select-field", in: styles)
    )
    XCTAssertTrue(selectorTriggerStyles.contains("border-radius: var(--pill-radius)"))
    XCTAssertTrue(selectorTriggerStyles.contains("corner-shape: var(--smooth-corner)"))
    let agentFilterAnchorStyles = try XCTUnwrap(cssBlock(named: ".agent-filter-anchor", in: styles))
    XCTAssertTrue(agentFilterAnchorStyles.contains("width: fit-content"))
    let agentFilterMenuStyles = try XCTUnwrap(cssBlock(named: ".agent-filter-menu", in: styles))
    XCTAssertTrue(agentFilterMenuStyles.contains("left: 0"))
    XCTAssertTrue(agentFilterMenuStyles.contains("right: auto"))
    XCTAssertTrue(agentFilterMenuStyles.contains("width: fit-content"))
    XCTAssertTrue(agentFilterMenuStyles.contains("min-width: 100%"))
    XCTAssertTrue(agentFilterMenuStyles.contains("background: rgba(255, 255, 255, 0.96)"))
    let textOnlyMenuRowStyles = try XCTUnwrap(cssBlock(named: ".menu-row-text-only", in: styles))
    XCTAssertTrue(textOnlyMenuRowStyles.contains("grid-template-columns: minmax(0, 1fr) auto"))
    let menuRowStyles = try XCTUnwrap(cssBlock(named: ".menu-row", in: styles))
    XCTAssertTrue(menuRowStyles.contains("grid-template-columns: 16px minmax(0, 1fr) auto"))
    XCTAssertTrue(menuRowStyles.contains("border-radius: var(--row-radius)"))
    XCTAssertFalse(menuRowStyles.contains("var(--pill-radius)"))
    let worldCellStyles = try XCTUnwrap(cssBlock(named: ".world-cell", in: styles))
    XCTAssertTrue(worldCellStyles.contains("border-radius: 15px"))
    XCTAssertTrue(worldCellStyles.contains("corner-shape: var(--smooth-corner)"))
    XCTAssertFalse(worldCellStyles.contains("var(--pill-radius)"))
    let formOptionStyles = try XCTUnwrap(cssBlock(named: ".form-option", in: styles))
    XCTAssertTrue(formOptionStyles.contains("height: var(--control-height)"))
    XCTAssertTrue(formOptionStyles.contains("min-height: var(--control-height)"))
    XCTAssertTrue(formOptionStyles.contains("border-radius: var(--pill-radius)"))
    XCTAssertTrue(formOptionStyles.contains("corner-shape: var(--smooth-corner)"))
    XCTAssertTrue(styles.contains("scale(var(--world-zoom, 1))"))
    XCTAssertTrue(styles.contains(".genie-glass-wrapper.is-top-left"))
    XCTAssertTrue(styles.contains("right: -12px"))
    XCTAssertFalse(styles.contains("right: -36px"))
    XCTAssertFalse(styles.contains("right: -18px"))
    XCTAssertFalse(styles.contains("rgba(37, 34, 31, 0.2)"))
    XCTAssertFalse(styles.contains("rgba(37, 34, 31, 0.16)"))
    XCTAssertTrue(styles.contains("background: rgba(43, 38, 34, 0.08);"))
    XCTAssertFalse(styles.contains(".sidebar-row::after"))
    XCTAssertFalse(styles.contains(".inspector-nav-button::after"))
    XCTAssertTrue(styles.contains("--control-height: 32px"))
    XCTAssertTrue(styles.contains("height: var(--control-height);"))
    XCTAssertTrue(styles.contains("--sidebar-min-width: 208px"))
    XCTAssertTrue(styles.contains("--sidebar-default-width: 240px"))
    XCTAssertTrue(styles.contains("--sidebar-max-width: 352px"))
    XCTAssertTrue(styles.contains("--sidebar-min-main-width: 480px"))
    XCTAssertTrue(styles.contains("grid-template-columns: var(--sidebar-rendered-width)"))
    let appShellStyles = try XCTUnwrap(cssBlock(named: ".app-shell", in: styles))
    XCTAssertTrue(appShellStyles.contains("--sidebar-rendered-width: clamp("))
    XCTAssertTrue(appShellStyles.contains("var(--sidebar-preferred-width)"))
    let workspaceMainStyles = try XCTUnwrap(cssBlock(named: ".workspace-main", in: styles))
    XCTAssertTrue(workspaceMainStyles.contains("min-height: 0"))
    XCTAssertTrue(workspaceMainStyles.contains("height: 100%"))
    XCTAssertTrue(workspaceMainStyles.contains("overflow: hidden"))
    let sidebarResizeStyles = try XCTUnwrap(
      cssBlock(named: ".sidebar-resize-handle", in: styles)
    )
    XCTAssertTrue(sidebarResizeStyles.contains("position: absolute"))
    XCTAssertTrue(sidebarResizeStyles.contains("width: 16px"))
    XCTAssertTrue(sidebarResizeStyles.contains("touch-action: none"))
    XCTAssertTrue(sidebarResizeStyles.contains("background: transparent"))
    XCTAssertTrue(sidebarResizeStyles.contains("border: 0"))
    XCTAssertFalse(sidebarResizeStyles.contains("border-left"))
    let sidebarResizeIndicatorStyles = try XCTUnwrap(
      cssBlock(named: ".sidebar-resize-handle > span", in: styles)
    )
    XCTAssertTrue(sidebarResizeIndicatorStyles.contains("width: 2px"))
    XCTAssertTrue(sidebarResizeIndicatorStyles.contains("height: 34px"))
    XCTAssertTrue(sidebarResizeIndicatorStyles.contains("opacity: 0"))
    let sidebarScrollStyles = try XCTUnwrap(cssBlock(named: ".sidebar-scroll", in: styles))
    XCTAssertTrue(sidebarScrollStyles.contains("overflow-y: auto"))
    XCTAssertTrue(sidebarScrollStyles.contains("overscroll-behavior: contain"))
    XCTAssertTrue(sidebarScrollStyles.contains("scrollbar-gutter: stable"))
    let domainSidebarStyles = try XCTUnwrap(cssBlock(named: ".domain-sidebar", in: styles))
    XCTAssertTrue(domainSidebarStyles.contains("overflow: hidden"))
    XCTAssertFalse(domainSidebarStyles.contains("overflow: hidden auto"))
    let domainSidebarContentStyles = try XCTUnwrap(
      cssBlock(named: ".domain-sidebar-content", in: styles)
    )
    XCTAssertTrue(domainSidebarContentStyles.contains("overflow-y: auto"))
    XCTAssertTrue(domainSidebarContentStyles.contains("overscroll-behavior: contain"))
    XCTAssertTrue(domainSidebarContentStyles.contains("scrollbar-gutter: stable"))
    XCTAssertTrue(workspaceScrollRegionStyles.contains("min-height: 0"))
    XCTAssertTrue(workspaceScrollRegionStyles.contains("overflow-x: hidden"))
    XCTAssertTrue(workspaceScrollRegionStyles.contains("overflow-y: auto"))
    XCTAssertTrue(workspaceScrollRegionStyles.contains("overscroll-behavior: contain"))
    XCTAssertTrue(workspaceScrollRegionStyles.contains("scrollbar-gutter: stable"))
    let dialogBlock = try XCTUnwrap(cssBlock(named: ".compact-dialog", in: styles))
    XCTAssertTrue(dialogBlock.contains("border: 0;"))
    XCTAssertFalse(dialogBlock.contains("border: 1px"))
    XCTAssertFalse(dialogBlock.contains("var(--border"))
  }

  func testStableVisualIdentityProducesDeterministicShapeBucketsAndColorCycles() throws {
    let makeExactID = { (firstByte: Int, secondByte: Int) -> String in
      String(format: "%02x%02x", firstByte, secondByte) + String(repeating: "00", count: 14)
    }

    let shapeCases: [(Int, Int)] = [
      (0, 0),
      (31, 1),
      (32, 2),
      (63, 3),
      (64, 4),
      (95, 5),
      (96, 6),
      (127, 7),
      (128, 8),
      (159, 9),
      (160, 10),
      (191, 11),
      (192, 12),
      (223, 13),
      (224, 14),
      (255, 15),
    ]
    for (firstByte, secondByte) in shapeCases {
      let snapshot = try StableVisualIdentity.snapshot(for: makeExactID(firstByte, secondByte))
      XCTAssertEqual(snapshot.shapeIndex, firstByte / 32, "first byte \(firstByte)")
      XCTAssertEqual(snapshot.colorIndex, secondByte % 12, "second byte \(secondByte)")
    }

    for colorIndex in 0..<12 {
      let snapshot = try StableVisualIdentity.snapshot(for: makeExactID(1, colorIndex))
      XCTAssertEqual(snapshot.shapeIndex, 0)
      XCTAssertEqual(snapshot.colorIndex, colorIndex)
    }
  }

  func testStableVisualIdentityRejectsInvalidExactSelectors() {
    for invalid in [
      "",
      String(repeating: "0", count: 31),
      String(repeating: "0", count: 33),
      String(repeating: "g", count: 32),
    ] {
      XCTAssertThrowsError(try StableVisualIdentity.snapshot(for: invalid)) { error in
        XCTAssertEqual(error as? WorldProjectionError, .invalidVisualIdentity)
      }
    }
  }

  func testWorldHeldObjectSnapshotJSONSerializesOnlyVisualIdentity() throws {
    let snapshot = WorldHeldObjectSnapshot(visual: .init(shapeIndex: 3, colorIndex: 7))
    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))
    let top = try XCTUnwrap(encoded as? [String: Any], "snapshot must be a JSON object")
    XCTAssertEqual(Set(top.keys), ["visual"])
    let visual = try XCTUnwrap(top["visual"] as? [String: Any], "visual must be object")
    XCTAssertEqual(Set(visual.keys), ["colorIndex", "shapeIndex"])
    XCTAssertEqual(try XCTUnwrap(visual["shapeIndex"] as? NSNumber).intValue, 3)
    XCTAssertEqual(try XCTUnwrap(visual["colorIndex"] as? NSNumber).intValue, 7)
  }

  func testWorldSnapshotDoesNotApplyImplicitFocusForContainerSelection() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "mikrokhoros-no-implicit-focus-\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: root) }
    let layout = ProductLayout(canonicalRoot: root)
    let runtime = try testWorldRuntime()
    let agent = try runtime.createAgent(name: "Focusless")
    _ = try runtime.addAgent(agent)
    let worldID = runtime.document.worldID
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let catalog = WorldCatalogDocument(
      currentWorldID: worldID,
      worlds: [try WorldCatalogRecord(id: worldID, name: runtime.document.worldName)]
    )
    try FileManager.default.createDirectory(
      at: layout.worldsDirectoryURL, withIntermediateDirectories: true)
    try WorldStore.save(runtime.document, to: layout.worldURL(for: worldID))
    try encoder.encode(catalog).write(to: layout.catalogURL)
    let snapshot = try WorldProjectionService(layout: layout).snapshotExact(
      world: worldID,
      container: agent.backpack.hash
    )
    XCTAssertEqual(snapshot.state, .available)
    XCTAssertNil(snapshot.focusedAgentID)
    XCTAssertFalse(snapshot.primaryAgents.contains(where: \.isFocused))
    XCTAssertFalse(snapshot.otherAgents.contains(where: \.isFocused))
  }

  func testProjectionReportsTypedUnavailableStateWithoutProductDetails() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("mikrokhoros-web-unavailable-\(UUID().uuidString)", isDirectory: true)
    let worldsDirectory = root.appendingPathComponent("worlds", isDirectory: true)
    try FileManager.default.createDirectory(at: worldsDirectory, withIntermediateDirectories: true)
    let configuration = RuntimeConfiguration.defaults
    let configurationData = try JSONEncoder().encode(configuration)
    try configurationData.write(to: root.appendingPathComponent("config.json"))
    let worldID = String(repeating: "a", count: 32)
    let record = try WorldCatalogRecord(id: worldID, name: "Missing world")
    let catalog = WorldCatalogDocument(currentWorldID: worldID, worlds: [record])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(catalog).write(to: worldsDirectory.appendingPathComponent("index.json"))
    let service = WorldProjectionService(
      layout: ProductLayout(canonicalRoot: root)
    )
    let catalogURL = worldsDirectory.appendingPathComponent("index.json")
    let beforeConfiguration = try Data(contentsOf: root.appendingPathComponent("config.json"))
    let beforeCatalog = try Data(contentsOf: catalogURL)
    let snapshot = try service.snapshotExact()
    XCTAssertEqual(snapshot.state, .unavailable)
    XCTAssertEqual(snapshot.message, WorldPageSnapshot.unavailableMessage)
    XCTAssertEqual(snapshot.worlds.count, 1)
    XCTAssertTrue(snapshot.primaryAgents.isEmpty)
    XCTAssertTrue(snapshot.otherAgents.isEmpty)
    XCTAssertTrue(snapshot.objects.isEmpty)
    XCTAssertTrue(snapshot.reports.isEmpty)
    XCTAssertEqual(
      try Data(contentsOf: root.appendingPathComponent("config.json")),
      beforeConfiguration
    )
    XCTAssertEqual(try Data(contentsOf: catalogURL), beforeCatalog)
  }

  func testLoopbackServerStartsAndStops() async throws {
    let server = KhorosWebServer()
    let request = WebLaunchRequest(
      canonicalRoot: URL(fileURLWithPath: "/tmp/mikrokhoros-web-loopback", isDirectory: true),
      portSelection: .available
    )
    let serving = Task {
      try await server.serve(request) { launchURL in
        XCTAssertEqual(launchURL.host, "127.0.0.1")
        XCTAssertTrue(launchURL.fragment?.hasPrefix("token=") == true)
        Task { await server.stop() }
      }
    }
    try await serving.value
  }

  func testLoopbackServerAllowsPortZeroOnlyForAvailableSelection() async throws {
    for invalidSelection in [WebPortSelection.explicit(0), .explicit(65_536)] {
      let server = KhorosWebServer()
      let request = WebLaunchRequest(
        canonicalRoot: URL(
          fileURLWithPath: "/tmp/mikrokhoros-web-invalid-port-\(UUID().uuidString)",
          isDirectory: true
        ),
        portSelection: invalidSelection
      )
      do {
        try await server.serve(request) { _ in
          XCTFail("an invalid exact port unexpectedly launched")
        }
        XCTFail("an invalid exact port unexpectedly succeeded")
      } catch let error as WebServingError {
        XCTAssertEqual(error, .invalidPort)
      }
    }
  }

  func testLoopbackServerClassifiesMikroKhorosPortCollisionAndReusesReleasedPort()
    async throws
  {
    let first = KhorosWebServer()
    let firstRequest = WebLaunchRequest(
      canonicalRoot: URL(
        fileURLWithPath: "/tmp/mikrokhoros-web-first-\(UUID().uuidString)",
        isDirectory: true
      ),
      portSelection: .available
    )
    let (launches, continuation) = AsyncStream<URL>.makeStream()
    let servingFirst = Task {
      try await first.serve(firstRequest) { continuation.yield($0) }
    }
    var iterator = launches.makeAsyncIterator()
    let nextLaunch = await iterator.next()
    let firstURL = try XCTUnwrap(nextLaunch)
    let port = try XCTUnwrap(firstURL.port)

    let second = KhorosWebServer()
    let secondRequest = WebLaunchRequest(
      canonicalRoot: URL(
        fileURLWithPath: "/tmp/mikrokhoros-web-second-\(UUID().uuidString)",
        isDirectory: true
      ),
      portSelection: .explicit(port)
    )
    do {
      try await second.serve(secondRequest) { _ in
        XCTFail("a colliding listener unexpectedly launched")
      }
      XCTFail("a colliding listener unexpectedly succeeded")
    } catch let error as WebServingError {
      XCTAssertEqual(
        error,
        .portUnavailable(port: port, listener: .mikroKhoros)
      )
    }

    await first.stop()
    try await servingFirst.value
    continuation.finish()

    let relaunched = Task {
      try await second.serve(secondRequest) { launchURL in
        XCTAssertEqual(launchURL.port, port)
        Task { await second.stop() }
      }
    }
    try await relaunched.value
  }

  func testLoopbackServerClassifiesAnotherListeningServiceAsPortUnavailable() async throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let listener = try await ServerBootstrap(group: group)
      .serverChannelOption(.backlog, value: 8)
      .childChannelInitializer { channel in
        channel.pipeline.addHandler(PlainHTTPPortListener())
      }
      .bind(host: "127.0.0.1", port: 0)
      .get()
    let port = try XCTUnwrap(listener.localAddress?.port)

    let server = KhorosWebServer()
    let request = WebLaunchRequest(
      canonicalRoot: URL(
        fileURLWithPath: "/tmp/mikrokhoros-web-other-listener-\(UUID().uuidString)",
        isDirectory: true
      ),
      portSelection: .explicit(port)
    )

    let servingError: Error?
    do {
      try await server.serve(request) { _ in
        XCTFail("a listener collision unexpectedly launched")
      }
      XCTFail("a listener collision unexpectedly succeeded")
      servingError = nil
    } catch {
      servingError = error
    }
    XCTAssertEqual(
      servingError as? WebServingError,
      .portUnavailable(port: port, listener: .other)
    )
    try? await listener.close()
    try? await group.shutdownGracefully()
  }

  func testUnreachableBindProbeMapsToGenericBindFailure() {
    XCTAssertEqual(
      WebListenerProbe.servingError(for: 47_568, result: .unreachable),
      .bindFailed
    )
  }

  func testLoopbackServerRejectsASecondStartWithoutReplacingTheActiveListener() async throws {
    let server = KhorosWebServer()
    let request = WebLaunchRequest(
      canonicalRoot: URL(fileURLWithPath: "/tmp/mikrokhoros-web-loopback", isDirectory: true),
      portSelection: .available
    )
    let (launches, launchContinuation) = AsyncStream<URL>.makeStream()
    let serving = Task {
      try await server.serve(request) { launchURL in
        launchContinuation.yield(launchURL)
      }
    }
    var iterator = launches.makeAsyncIterator()
    let nextLaunch = await iterator.next()
    let launchURL = try XCTUnwrap(nextLaunch)
    XCTAssertEqual(launchURL.host, "127.0.0.1")

    do {
      try await server.serve(request) { _ in
        XCTFail("a second listener unexpectedly launched")
      }
      XCTFail("a second serve call unexpectedly succeeded")
    } catch let error as WebServerError {
      XCTAssertEqual(error, .alreadyRunning)
    }

    await server.stop()
    try await serving.value
    launchContinuation.finish()
  }

  func testLoopbackServerJoinsOverlappingStopsBeforeReturningAndCanRestart() async throws {
    let gate = LoopbackShutdownGate()
    let server = KhorosWebServer(testLifecycleEvent: { event in
      await gate.observe(event)
    })
    let request = WebLaunchRequest(
      canonicalRoot: URL(
        fileURLWithPath: "/tmp/mikrokhoros-web-joined-stop-\(UUID().uuidString)",
        isDirectory: true
      ),
      portSelection: .available
    )
    let (launches, launchContinuation) = AsyncStream<URL>.makeStream()
    let serving = Task {
      try await server.serve(request) { launchURL in
        launchContinuation.yield(launchURL)
      }
    }
    var iterator = launches.makeAsyncIterator()
    let firstLaunch = await iterator.next()
    _ = try XCTUnwrap(firstLaunch)

    let owningStop = Task { await server.stop() }
    await gate.waitUntilShutdownCompletionIsHeld()
    let joiningStop = Task { await server.stop() }
    await gate.waitUntilTwoCallersAreWaitingForShutdown()

    await gate.releaseShutdownCompletion()
    await owningStop.value
    await joiningStop.value
    try await serving.value

    let restartLaunches = LockedLaunchCounter()
    let restarted = Task {
      try await server.serve(request) { _ in
        restartLaunches.record()
        Task { await server.stop() }
      }
    }
    try await restarted.value
    XCTAssertEqual(restartLaunches.value, 1)
    launchContinuation.finish()
  }

  func testLoopbackServerDoesNotLaunchAfterStopWinsBeforeCallback() async throws {
    let gate = LoopbackLaunchGate()
    let launches = LockedLaunchCounter()
    let server = KhorosWebServer(testLifecycleEvent: { event in
      await gate.observe(event)
    })
    let request = WebLaunchRequest(
      canonicalRoot: URL(
        fileURLWithPath: "/tmp/mikrokhoros-web-suppressed-launch-\(UUID().uuidString)",
        isDirectory: true
      ),
      portSelection: .available
    )
    let serving = Task {
      try await server.serve(request) { _ in
        launches.record()
      }
    }

    await gate.waitUntilLaunchCallbackIsHeld()
    let stopping = Task { await server.stop() }
    await gate.waitUntilShutdownCompletionIsObserved()
    await stopping.value
    await gate.releaseLaunchCallback()
    try await serving.value

    XCTAssertEqual(launches.value, 0)
  }

  private func nativeManagementProjectionFixtureManifest() throws -> ObjectPackageManifest {
    let choices = (0..<80).map { "mode-\($0)" }
    return try ObjectPackageManifest(
      id: "example.web-management",
      version: "1.0.0",
      displayName: "Web Management Fixture",
      requestedCapabilities: [.network],
      installation: PackageInstallationPolicy(onInstall: .createInventoryObject),
      object: DeclarativeObjectDefinition(
        type: "web-management.object",
        name: "Web management fixture",
        summary: "Only typed declaration metadata is public to the host."
      ),
      management: ObjectManagementInterface(
        fields: [
          try ManagementField(
            id: "endpoint",
            label: "Endpoint",
            summary: "The service endpoint.",
            kind: .url,
            required: true,
            defaultValue: .string("https://example.invalid/default")
          ),
          try ManagementField(
            id: "mode",
            label: "Mode",
            summary: "How this source is refreshed.",
            kind: .choice,
            required: true,
            defaultValue: .string("quiet"),
            choices: ["quiet"] + choices,
            minimumCharacters: 2,
            maximumCharacters: 16
          ),
          try ManagementField(
            id: "workspace",
            label: "Workspace",
            summary: "A local workspace path.",
            kind: .path,
            defaultValue: .string("/private/management-workspace")
          ),
          try ManagementField(
            id: "api-token",
            label: "API token",
            summary: "Credential kept in the source credential store.",
            kind: .secret
          ),
        ],
        actions: [
          try ManagementAction(
            id: "refresh",
            summary: "Refresh the declared endpoint.",
            parameters: ["endpoint", "mode", "enabled", "workspace"],
            inputTypes: [
              "endpoint": .url,
              "mode": .choice,
              "enabled": .boolean,
              "workspace": .path,
            ],
            inputDefaults: [
              "endpoint": .string("https://example.invalid/run"),
              "mode": .string("quiet"),
              "enabled": .bool(true),
              "workspace": .string("/private/management-workspace"),
            ],
            inputChoices: ["mode": ["quiet"] + choices],
            mutating: true,
            requiredCapabilities: [.network],
            scope: .both,
            action: DeclarativeAction(kind: .return),
            result: ["accepted": .boolean, "message": .text]
          )
        ],
        views: [
          try ManagementView(
            id: "status",
            summary: "Show the declared status.",
            source: "state",
            scope: .both,
            result: ["ready": .boolean]
          )
        ],
        reports: [
          try ObjectReportDefinition(
            type: "run-status",
            summary: "A bounded refresh report.",
            maximumTitleCharacters: 100_000,
            maximumBodyCharacters: 2_000_000,
            maximumPayloadBytes: 3_000_000,
            payload: ["ready": .boolean]
          )
        ]
      )
    )
  }

  private struct AuthenticatedFixture {
    let router: KhorosWebRouter
    let layout: ProductLayout
    let cookie: String
  }

  private func sessionCookieHeader(port: Int, value: String) -> String {
    "khoros_session_\(port)=\(value)"
  }

  private func temporaryProductRoot(_ label: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "mikrokhoros-web-\(label)-\(UUID().uuidString)",
      isDirectory: true
    )
  }

  private func authenticatedFixture(
    root: URL,
    port: Int,
    commandConsole: (any WorldCommandConsoleServing)? = nil,
    webCapabilities: (any WebCapabilityServing)? = nil
  ) throws -> AuthenticatedFixture {
    let layout = ProductLayout(canonicalRoot: root)
    let sessions = WebSessionStore()
    let router = KhorosWebRouter(
      projection: WorldProjectionService(layout: layout),
      commandConsole: commandConsole,
      webCapabilities: webCapabilities,
      sessions: sessions
    )
    router.setEndpoint(port: port)
    let token = router.installBootstrapToken()
    let session = router.route(
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
    XCTAssertEqual(session.statusCode, 200)
    let setCookie = try XCTUnwrap(session.headers["set-cookie"])
    XCTAssertTrue(setCookie.hasPrefix("khoros_session_\(port)="))
    let cookie = try XCTUnwrap(
      setCookie.split(separator: ";", maxSplits: 1).first?
        .split(separator: "=", maxSplits: 1).last
    )
    XCTAssertEqual(cookie.count, 64)
    XCTAssertTrue(cookie.allSatisfy(\.isHexDigit))
    return AuthenticatedFixture(router: router, layout: layout, cookie: String(cookie))
  }

  private func worldCreationRequest(
    port: Int,
    cookie: String,
    body: Data,
    uri: String = "/api/v1/worlds",
    headers extraHeaders: [String: [String]] = [:]
  ) -> KhorosWebRequest {
    var headers = [
      "host": ["127.0.0.1:\(port)"],
      "origin": ["http://127.0.0.1:\(port)"],
      "cookie": [sessionCookieHeader(port: port, value: cookie)],
      "content-type": ["application/json"],
    ]
    for (key, values) in extraHeaders {
      headers[key] = values
    }
    return KhorosWebRequest(method: "POST", uri: uri, headers: headers, body: body)
  }

  private func worldAgentOptionsRequest(
    port: Int,
    cookie: String,
    worldID: String,
    headers extraHeaders: [String: [String]] = [:]
  ) -> KhorosWebRequest {
    var headers = [
      "host": ["127.0.0.1:\(port)"],
      "cookie": [sessionCookieHeader(port: port, value: cookie)],
    ]
    for (key, values) in extraHeaders {
      headers[key] = values
    }
    return KhorosWebRequest(
      method: "GET", uri: "/api/v1/world-agents?world=\(worldID)", headers: headers)
  }

  private func worldAgentAdditionBody(
    worldID: String = String(repeating: "0", count: 32),
    agentID: String = String(repeating: "f", count: 32),
    x: Int = 0,
    y: Int = 0,
    autoAdapt: Bool = false
  ) -> Data {
    Data(
      #"{"worldID":"\#(worldID)","agentID":"\#(agentID)","x":\#(x),"y":\#(y),"autoAdapt":\#(autoAdapt)}"#
        .utf8)
  }

  private func worldAgentAdditionRequest(
    port: Int,
    cookie: String,
    worldID: String? = nil,
    agentID: String? = nil,
    x: Int = 0,
    y: Int = 0,
    autoAdapt: Bool = false,
    body: Data? = nil,
    headers extraHeaders: [String: [String]] = [:]
  ) -> KhorosWebRequest {
    let payload = worldAgentAdditionBody(
      worldID: worldID ?? String(repeating: "0", count: 32),
      agentID: agentID ?? String(repeating: "f", count: 32),
      x: x,
      y: y,
      autoAdapt: autoAdapt
    )
    var headers = [
      "host": ["127.0.0.1:\(port)"],
      "origin": ["http://127.0.0.1:\(port)"],
      "cookie": [sessionCookieHeader(port: port, value: cookie)],
      "content-type": ["application/json"],
    ]
    for (key, values) in extraHeaders {
      if values.isEmpty {
        headers.removeValue(forKey: key)
      } else {
        headers[key] = values
      }
    }
    return KhorosWebRequest(
      method: "POST",
      uri: "/api/v1/world-agents",
      headers: headers,
      body: body ?? payload
    )
  }

  private func worldCommandBody(worldID: String, source: String) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: ["worldID": worldID, "source": source],
      options: []
    )
  }

  private func worldCommandRequest(
    port: Int,
    cookie: String,
    body: Data,
    endpoint: String,
    method: String = "POST",
    headers extraHeaders: [String: [String]] = [:]
  ) -> KhorosWebRequest {
    var headers = [
      "host": ["127.0.0.1:\(port)"],
      "origin": ["http://127.0.0.1:\(port)"],
      "cookie": [sessionCookieHeader(port: port, value: cookie)],
      "content-type": ["application/json"],
    ]
    for (key, values) in extraHeaders {
      if values.isEmpty {
        headers.removeValue(forKey: key)
      } else {
        headers[key] = values
      }
    }
    return KhorosWebRequest(
      method: method,
      uri: "/api/v1/world-command/\(endpoint)",
      headers: headers,
      body: body
    )
  }

  private func webRequest(
    port: Int,
    cookie: String,
    body: Data,
    endpoint: String,
    method: String = "POST",
    headers extraHeaders: [String: [String]] = [:]
  ) -> KhorosWebRequest {
    var headers = [
      "host": ["127.0.0.1:\(port)"],
      "origin": ["http://127.0.0.1:\(port)"],
      "cookie": [sessionCookieHeader(port: port, value: cookie)],
      "content-type": ["application/json"],
    ]
    for (key, values) in extraHeaders {
      if values.isEmpty {
        headers.removeValue(forKey: key)
      } else {
        headers[key] = values
      }
    }
    return KhorosWebRequest(
      method: method,
      uri: "/api/v1/web/\(endpoint)",
      headers: headers,
      body: body
    )
  }

  private func webRequestBody(
    operationID: String,
    fields: [String: [String]] = [:]
  ) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: ["operationID": operationID, "fields": fields],
      options: [.sortedKeys]
    )
  }

  private func webRequestBodyAt64KiB(operationID: String) throws -> Data {
    let maximumBytes = 64 * 1_024
    var values = Array(repeating: "", count: 4)
    let emptyBody = try webRequestBody(
      operationID: operationID,
      fields: ["padding": values]
    )
    var remaining = maximumBytes - emptyBody.count
    for index in values.indices {
      let count = min(16_384, remaining)
      values[index] = String(repeating: "x", count: count)
      remaining -= count
    }
    guard remaining == 0 else { throw WebFixtureError.budgetConstructionFailed }
    let body = try webRequestBody(operationID: operationID, fields: ["padding": values])
    guard body.count == maximumBytes else { throw WebFixtureError.budgetConstructionFailed }
    return body
  }

  private func webDescriptor(
    id: String,
    interaction: WebCapabilityInteractionMode
  ) -> WebCapabilityDescriptor {
    WebCapabilityDescriptor(
      id: id,
      commandKind: "test.fixture",
      canonicalPath: ["test", "fixture"],
      label: "Test fixture",
      summary: "A bounded web transport fixture.",
      help: "",
      fields: [],
      placement: .world,
      section: "Test",
      scope: .selectedWorld,
      interaction: interaction
    )
  }

  private func webExecutionResult(
    accepted: Bool = true,
    standardOutput: String = "",
    standardError: String = "",
    exitStatus: Int = 0,
    outputTruncated: Bool = false,
    category: WebCapabilityResultCategory = .success
  ) -> WebCapabilityExecutionResult {
    WebCapabilityExecutionResult(
      accepted: accepted,
      displayCommand: "test fixture",
      standardOutput: standardOutput,
      standardError: standardError,
      exitStatus: exitStatus,
      outputTruncated: outputTruncated,
      category: category
    )
  }

  private func fileSnapshot(at root: URL) throws -> [String: Data] {
    guard FileManager.default.fileExists(atPath: root.path) else { return [:] }
    let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    )
    var snapshot: [String: Data] = [:]
    while let url = enumerator?.nextObject() as? URL {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey])
      guard values.isRegularFile == true else { continue }
      let relativePath = String(url.path.dropFirst(root.path.count))
      snapshot[relativePath] = try Data(contentsOf: url)
    }
    return snapshot
  }

  private func cssBlock(named selector: String, in styles: String) -> String? {
    guard let start = styles.range(of: "\(selector) {") else { return nil }
    let contentStart = start.upperBound
    guard let end = styles[contentStart...].firstIndex(of: "}") else { return nil }
    return String(styles[start.lowerBound...end])
  }

  private func cssBlocks(named selector: String, in styles: String) -> [String] {
    var blocks: [String] = []
    var searchStart = styles.startIndex
    let opening = "\(selector) {"
    while let start = styles.range(of: opening, range: searchStart..<styles.endIndex) {
      guard let end = styles[start.upperBound...].firstIndex(of: "}") else { break }
      blocks.append(String(styles[start.lowerBound...end]))
      searchStart = styles.index(after: end)
    }
    return blocks
  }

  private enum WebFixtureError: Error {
    case budgetConstructionFailed
  }

  private actor LoopbackShutdownGate {
    private var shutdownCompletionHeld = false
    private var shutdownCompletionReleased = false
    private var waitingForShutdownCount = 0
    private var shutdownCompletionWaiter: CheckedContinuation<Void, Never>?
    private var shutdownReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var twoWaitingCallersWaiter: CheckedContinuation<Void, Never>?

    func observe(_ event: KhorosWebServerLifecycleTestEvent) async {
      switch event {
      case .beforeShutdownCompletion:
        shutdownCompletionHeld = true
        shutdownCompletionWaiter?.resume()
        shutdownCompletionWaiter = nil
        guard !shutdownCompletionReleased else { return }
        await withCheckedContinuation { continuation in
          shutdownReleaseWaiters.append(continuation)
        }
      case .waitingForShutdown:
        waitingForShutdownCount += 1
        if waitingForShutdownCount >= 2 {
          twoWaitingCallersWaiter?.resume()
          twoWaitingCallersWaiter = nil
        }
      case .beforeLaunchCallback:
        return
      }
    }

    func waitUntilShutdownCompletionIsHeld() async {
      guard !shutdownCompletionHeld else { return }
      await withCheckedContinuation { continuation in
        shutdownCompletionWaiter = continuation
      }
    }

    func waitUntilTwoCallersAreWaitingForShutdown() async {
      guard waitingForShutdownCount < 2 else { return }
      await withCheckedContinuation { continuation in
        twoWaitingCallersWaiter = continuation
      }
    }

    func releaseShutdownCompletion() {
      shutdownCompletionReleased = true
      let waiters = shutdownReleaseWaiters
      shutdownReleaseWaiters.removeAll()
      for waiter in waiters { waiter.resume() }
    }
  }

  private actor LoopbackLaunchGate {
    private var launchCallbackHeld = false
    private var launchCallbackReleased = false
    private var shutdownCompletionObserved = false
    private var launchCallbackWaiter: CheckedContinuation<Void, Never>?
    private var launchReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var shutdownCompletionWaiter: CheckedContinuation<Void, Never>?

    func observe(_ event: KhorosWebServerLifecycleTestEvent) async {
      switch event {
      case .beforeLaunchCallback:
        launchCallbackHeld = true
        launchCallbackWaiter?.resume()
        launchCallbackWaiter = nil
        guard !launchCallbackReleased else { return }
        await withCheckedContinuation { continuation in
          launchReleaseWaiters.append(continuation)
        }
      case .beforeShutdownCompletion:
        shutdownCompletionObserved = true
        shutdownCompletionWaiter?.resume()
        shutdownCompletionWaiter = nil
      case .waitingForShutdown:
        return
      }
    }

    func waitUntilLaunchCallbackIsHeld() async {
      guard !launchCallbackHeld else { return }
      await withCheckedContinuation { continuation in
        launchCallbackWaiter = continuation
      }
    }

    func waitUntilShutdownCompletionIsObserved() async {
      guard !shutdownCompletionObserved else { return }
      await withCheckedContinuation { continuation in
        shutdownCompletionWaiter = continuation
      }
    }

    func releaseLaunchCallback() {
      launchCallbackReleased = true
      let waiters = launchReleaseWaiters
      launchReleaseWaiters.removeAll()
      for waiter in waiters { waiter.resume() }
    }
  }

  private final class LockedLaunchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func record() {
      lock.withLock { count += 1 }
    }

    var value: Int {
      lock.withLock { count }
    }
  }

  private final class StubWorldCommandConsoleService: WorldCommandConsoleServing,
    @unchecked Sendable
  {
    private(set) var completionRequestCount = 0
    private(set) var executeRequestCount = 0
    private var completionResult: Result<WorldCommandCompletionResult, any Error>
    private var executeResult: Result<WorldCommandExecutionResult, any Error>

    init(
      completionResult: Result<WorldCommandCompletionResult, any Error> = .success(
        WorldCommandCompletionResult(suggestions: [])
      ),
      executeResult: Result<WorldCommandExecutionResult, any Error> = .failure(
        WorldCommandConsoleServiceError.invalidContext
      )
    ) {
      self.completionResult = completionResult
      self.executeResult = executeResult
    }

    func resetCounts() {
      completionRequestCount = 0
      executeRequestCount = 0
    }

    func setCompletionResult(_ result: Result<WorldCommandCompletionResult, any Error>) {
      completionResult = result
    }

    func setExecuteResult(_ result: Result<WorldCommandExecutionResult, any Error>) {
      executeResult = result
    }

    func completions(for request: WorldCommandConsoleRequest) async throws
      -> WorldCommandCompletionResult
    {
      completionRequestCount += 1
      return try completionResult.get()
    }

    func execute(_ request: WorldCommandConsoleRequest) async throws -> WorldCommandExecutionResult
    {
      executeRequestCount += 1
      return try executeResult.get()
    }
  }

  private final class PlainHTTPPortListener: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
      var response = context.channel.allocator.buffer(capacity: 64)
      response.writeString("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
      context.writeAndFlush(wrapOutboundOut(response), promise: nil)
    }
  }

  private final class RecordingWebHost: KhorosWebServing, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [WebLaunchRequest] = []

    func serve(
      _ request: WebLaunchRequest,
      onLaunch: @escaping @Sendable (URL) -> Void
    ) async throws {
      lock.withLock { requests.append(request) }
      let port =
        request.portSelection.requestedPort == 0
        ? 49_123
        : request.portSelection.requestedPort
      onLaunch(
        URL(string: "http://127.0.0.1:\(port)/#token=\(String(repeating: "a", count: 64))")!
      )
    }

    func stop() async {}

    func recordedRequests() -> [WebLaunchRequest] {
      lock.withLock { requests }
    }
  }

  private final class FailingWebHost: KhorosWebServing, @unchecked Sendable {
    private let error: WebServingError

    init(error: WebServingError) {
      self.error = error
    }

    func serve(
      _ request: WebLaunchRequest,
      onLaunch: @escaping @Sendable (URL) -> Void
    ) async throws {
      throw error
    }

    func stop() async {}
  }

  private final class WebCommandIO: CommandIO, @unchecked Sendable {
    private let lock = NSLock()
    private var output = ""
    private var error = ""

    var isInteractive: Bool { false }

    var standardOutput: String { lock.withLock { output } }
    var standardError: String { lock.withLock { error } }

    func writeStandardOutput(_ text: String) {
      lock.withLock { output += text }
    }

    func writeStandardError(_ text: String) {
      lock.withLock { error += text }
    }

    func readLine(prompt: String, hidden: Bool) throws -> String? { nil }
    func readStandardInputToEnd() throws -> Data { Data() }
  }

  private final class StubWebCapabilityService: WebCapabilityServing,
    @unchecked Sendable
  {
    private let descriptorValues: [WebCapabilityDescriptor]
    private var executionResult: WebCapabilityExecutionResult
    private(set) var executeRequestCount = 0

    init(
      descriptors: [WebCapabilityDescriptor],
      executeResult: WebCapabilityExecutionResult
    ) {
      descriptorValues = descriptors
      executionResult = executeResult
    }

    func setExecuteResult(_ result: WebCapabilityExecutionResult) {
      executionResult = result
    }

    func descriptors(
      in context: WebCapabilityContext
    ) throws -> [WebCapabilityDescriptor] {
      descriptorValues
    }

    func completions(
      for request: WebCapabilityCompletionRequest,
      in context: WebCapabilityContext
    ) async throws -> [WebCapabilityCompletionValue] {
      []
    }

    func execute(
      _ request: WebCapabilityRequest,
      in context: WebCapabilityContext
    ) async throws -> WebCapabilityExecutionResult {
      executeRequestCount += 1
      return executionResult
    }

    func prepare(
      _ request: WebCapabilityRequest,
      in context: WebCapabilityContext
    ) async throws -> WebCapabilityPlan {
      WebCapabilityPlan(
        planID: "test-plan",
        capabilityID: request.capabilityID,
        expiresAt: Date(timeIntervalSince1970: 0),
        commandSummary: "test fixture",
        consequenceSummary: "test fixture"
      )
    }

    func commit(
      _ request: WebCapabilityCommitRequest,
      in context: WebCapabilityContext
    ) async throws -> WebCapabilityExecutionResult {
      executionResult
    }

    func reportStream(
      _ request: WebCapabilityRequest,
      in context: WebCapabilityContext
    ) async throws -> AsyncThrowingStream<String, Error> {
      AsyncThrowingStream { continuation in
        continuation.finish()
      }
    }
  }
}
