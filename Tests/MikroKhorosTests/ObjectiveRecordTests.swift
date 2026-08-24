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
import XCTest

@testable import MikroKhoros

final class ObjectiveRecordTests: XCTestCase {
  func testObjectiveFunctionsAppendImmutableRecordsAndExposeNoCompleteAction() throws {
    let fixture = try makeFixture()
    let first = fixture.first
    let second = fixture.second
    let objective = fixture.objective
    let harness = fixture.harness

    XCTAssertEqual(objective.state, .open)
    XCTAssertTrue(objective.records.isEmpty)
    XCTAssertFalse(objective.inspect().functions.map(\.name).contains("complete"))
    XCTAssertEqual(
      try invoke(objective, harness: harness, agent: first, function: "register"),
      "registered for objective #objective"
    )
    XCTAssertEqual(objective.state, .inProgress)
    XCTAssertEqual(objective.participantAgentIDs, [first.hash])
    XCTAssertEqual(objective.records.map(\.kind), [.registration])
    XCTAssertEqual(objective.records[0].body, "")
    XCTAssertEqual(
      objective.records[0].timestamp.timeIntervalSince1970.rounded(),
      1_700_000_000
    )

    let registration = objective.records[0]
    XCTAssertEqual(
      try invoke(
        objective,
        harness: harness,
        agent: first,
        function: "progress",
        arguments: ["first progress"]
      ),
      "submitted progress for objective #objective"
    )
    XCTAssertEqual(
      try invoke(
        objective,
        harness: harness,
        agent: first,
        function: "final",
        arguments: ["first final"]
      ),
      "submitted final for objective #objective"
    )
    XCTAssertEqual(
      try invoke(
        objective,
        harness: harness,
        agent: first,
        function: "revision",
        arguments: ["corrected final"]
      ),
      "submitted revision for objective #objective"
    )

    XCTAssertEqual(
      objective.records.map(\.kind),
      [.registration, .progress, .final, .revision]
    )
    XCTAssertEqual(
      objective.records.map(\.body),
      ["", "first progress", "first final", "corrected final"]
    )
    XCTAssertEqual(objective.records[0], registration)
    XCTAssertEqual(objective.records(for: first.hash).count, 4)
    XCTAssertEqual(objective.state, .inProgress)

    XCTAssertThrowsError(
      try invoke(
        objective,
        harness: harness,
        agent: first,
        function: "final",
        arguments: ["second final"]
      )
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "objective.final_already_submitted")
    }
    XCTAssertEqual(objective.records.count, 4)

    XCTAssertThrowsError(
      try invoke(
        objective,
        harness: harness,
        agent: second,
        function: "revision",
        arguments: ["unregistered revision"]
      )
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "objective.not_registered")
    }
    XCTAssertEqual(objective.records.count, 4)

    _ = try invoke(objective, harness: harness, agent: second, function: "register")
    XCTAssertThrowsError(
      try invoke(
        objective,
        harness: harness,
        agent: second,
        function: "revision",
        arguments: ["no final yet"]
      )
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "objective.final_required")
    }
    XCTAssertEqual(objective.records.count, 5)
    XCTAssertEqual(objective.state, .inProgress)

    let rendered = try invoke(objective, harness: harness, agent: first, function: "read")
    XCTAssertTrue(rendered.contains("records:"))
    XCTAssertTrue(rendered.contains("first progress"))
    XCTAssertTrue(rendered.contains("corrected final"))
    XCTAssertTrue(rendered.contains(second.hash))
    XCTAssertFalse(rendered.contains("completed_by"))
  }

  func testObjectiveRecordBodiesUseActiveLimitAndRecordsRoundTrip() throws {
    let limits = try RuntimeLimits.defaults.setting(
      .maximumModelFieldCharacters,
      to: 8
    )
    let fixture = try makeFixture(limits: limits)
    let objective = fixture.objective
    let harness = fixture.harness
    let first = fixture.first

    _ = try invoke(objective, harness: harness, agent: first, function: "register")
    XCTAssertThrowsError(
      try invoke(
        objective,
        harness: harness,
        agent: first,
        function: "progress",
        arguments: ["123456789"]
      )
    ) { error in
      XCTAssertEqual((error as? MikroKhorosError)?.issue.code, "objective.body_too_large")
    }
    XCTAssertEqual(objective.records.count, 1)

    _ = try invoke(
      objective,
      harness: harness,
      agent: first,
      function: "progress",
      arguments: ["bounded"]
    )
    let record = try XCTUnwrap(objective.records.last)
    let data = try JSONEncoder().encode(record)
    XCTAssertEqual(try JSONDecoder().decode(ObjectiveRecord.self, from: data), record)
    XCTAssertEqual(record.recordID, record.eventID)
    XCTAssertEqual(record.text, record.body)
    XCTAssertEqual(
      record.timestamp.timeIntervalSince1970,
      floor(record.timestamp.timeIntervalSince1970)
    )
  }

  func testFreshCopyStartsWithOnlyImmutableObjectiveBody() throws {
    let fixture = try makeFixture()
    let copy = try XCTUnwrap(
      try fixture.objective.freshCopy(hash: "copy") as? ObjectiveObject
    )
    XCTAssertEqual(copy.hash, "copy")
    XCTAssertEqual(copy.title, fixture.objective.title)
    XCTAssertEqual(copy.body, fixture.objective.body)
    XCTAssertEqual(copy.state, .open)
    XCTAssertTrue(copy.records.isEmpty)
    XCTAssertTrue(copy.participantAgentIDs.isEmpty)
  }

  private func invoke(
    _ objective: ObjectiveObject,
    harness: Harness,
    agent: Agent,
    function: String,
    arguments: [String] = []
  ) throws -> String {
    XCTAssertTrue(harness.findObject(objective.hash) === objective)
    return try harness.invokeAccessible(for: agent, function: function, arguments: arguments)
  }

  private func makeFixture(
    limits: RuntimeLimits = .defaults
  ) throws -> (harness: Harness, objective: ObjectiveObject, first: Agent, second: Agent) {
    var nextIdentity = 0
    let harness = try Harness(
      limits: limits,
      runtimeIdentityProvider: {
        defer { nextIdentity += 1 }
        return "runtime-\(nextIdentity)"
      },
      runtimeDateProvider: { Date(timeIntervalSince1970: 1_700_000_000.75) }
    )
    let objective = try ObjectiveObject(
      title: "objective title",
      body: "objective body",
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      hash: "objective"
    )
    try harness.place(objective, at: Coordinate(x: 1, y: 0))
    let first = try harness.createAgent(name: "first", hash: "first-agent")
    let second = try harness.createAgent(name: "second", hash: "second-agent")
    _ = try harness.addAgent(first, at: Coordinate(x: 1, y: 0))
    _ = try harness.addAgent(second, at: Coordinate(x: 1, y: 0))
    try harness.stowHeldObject(for: first)
    try harness.stowHeldObject(for: second)
    return (harness, objective, first, second)
  }
}
