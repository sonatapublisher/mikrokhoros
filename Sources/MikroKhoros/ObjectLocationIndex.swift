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

public struct CanonicalLocationPath: Hashable, Comparable, Sendable {
  public let components: [String]

  public init(components: [String]) {
    self.components = components
  }

  public init(world: String) {
    self.components = ["world:\(world)"]
  }

  public init(agentHolding: String, slot: HoldingNumber) {
    self.components = ["agent:\(agentHolding):holding:\(slot.rawValue)"]
  }

  public init(agentAttachment: String, kind: String) {
    self.components = ["agent:\(agentAttachment):attachment:\(kind)"]
  }

  public func appendingCoordinate(_ coordinate: Coordinate, in ownerHash: String)
    -> CanonicalLocationPath
  {
    CanonicalLocationPath(components: components + ["\(coordinate.x),\(coordinate.y)#\(ownerHash)"])
  }

  public func droppingLast() -> CanonicalLocationPath {
    CanonicalLocationPath(components: Array(components.dropLast()))
  }

  public var description: String {
    components.joined(separator: "/")
  }

  public static func < (lhs: CanonicalLocationPath, rhs: CanonicalLocationPath) -> Bool {
    lhs.description < rhs.description
  }
}

public enum ObjectOwner: Hashable, Sendable {
  case agent(id: String, holding: HoldingNumber?)

  public var agentID: String {
    switch self {
    case .agent(let id, _):
      return id
    }
  }

  public var holding: HoldingNumber? {
    switch self {
    case .agent(_, let holding):
      return holding
    }
  }

  public var commitmentTag: String {
    switch self {
    case .agent(let id, let holding):
      if let holding {
        return "agent\(id)#\(holding.rawValue)"
      }
      return "agent\(id)#attachment"
    }
  }
}

public struct AttachmentRoot {
  public let kind: String
  public let object: MikroObject

  public init(kind: String, object: MikroObject) {
    self.kind = kind
    self.object = object
  }
}

public typealias HoldingRootsProvider = (Agent) -> [MikroObject?]
public typealias AttachmentRootsProvider = (Agent) -> [AttachmentRoot]

func defaultHoldingRoots(_ agent: Agent) -> [MikroObject?] {
  HoldingNumber.allCases.map { agent.holdings[$0] }
}

func defaultAttachmentRoots(_ agent: Agent) -> [AttachmentRoot] {
  [AttachmentRoot(kind: "backpack", object: agent.backpack)]
}

public enum ObjectLocationIndexError: Error, Equatable, Sendable {
  case duplicateObject(String)
  case duplicateObjectPlacement(
    objectHash: String,
    existingOwner: ObjectOwner?,
    incomingOwner: ObjectOwner?,
    existingPath: CanonicalLocationPath,
    incomingPath: CanonicalLocationPath
  )
  case ambiguousOwner(
    objectHash: String,
    ownerA: ObjectOwner?,
    ownerB: ObjectOwner?,
    existingPath: CanonicalLocationPath,
    incomingPath: CanonicalLocationPath
  )
  case invalidRoot(
    objectHash: String,
    reason: String
  )
  case cycleDetected(objectHash: String, path: CanonicalLocationPath)
  case depthExceeded(objectHash: String, limit: Int)
  case invalidHoldingRootsCount(agentID: String, expected: Int, actual: Int)
  case unregisteredObjectInTraversal(String)
  case orphanedObjects([String])
}

public struct AgentLocationRecord: Hashable, Sendable {
  public let objectHash: String
  public let locationPath: CanonicalLocationPath
  public let owner: ObjectOwner?

  public var parentPath: CanonicalLocationPath {
    locationPath.droppingLast()
  }
}

public struct ObjectLocationIndex {
  private let world: MikroObject
  private let registeredObjectsByHash: [String: MikroObject]
  private let locations: [String: AgentLocationRecord]
  private let maxDepth: Int

  public let worldHash: String
  public let maxTraversalDepth: Int

  public init(
    world: MikroObject,
    registeredObjects: [MikroObject],
    agents: [Agent],
    holdingRoots: HoldingRootsProvider? = nil,
    attachmentRoots: AttachmentRootsProvider? = nil,
    maxDepth: Int = 10_000
  ) throws {
    guard world.container != nil else {
      throw ObjectLocationIndexError.invalidRoot(
        objectHash: world.hash,
        reason: "world object must expose a container"
      )
    }

    worldHash = world.hash
    self.world = world
    self.maxDepth = max(4, maxDepth)
    self.maxTraversalDepth = self.maxDepth
    let holdingRoots = holdingRoots ?? defaultHoldingRoots
    let attachmentRoots = attachmentRoots ?? defaultAttachmentRoots

    var byHash: [String: MikroObject] = [:]
    for object in registeredObjects {
      if byHash[object.hash] != nil { throw ObjectLocationIndexError.duplicateObject(object.hash) }
      byHash[object.hash] = object
    }
    guard byHash[world.hash] === world else {
      throw ObjectLocationIndexError.unregisteredObjectInTraversal(world.hash)
    }
    registeredObjectsByHash = byHash

    var discovered: [String: AgentLocationRecord] = [:]
    var stack: Set<String> = []

    func assignSubtree(
      _ object: MikroObject,
      owner: ObjectOwner?,
      path: CanonicalLocationPath,
      depth: Int
    ) throws {
      guard byHash[object.hash] === object else {
        throw ObjectLocationIndexError.unregisteredObjectInTraversal(object.hash)
      }
      guard object !== world else {
        throw ObjectLocationIndexError.invalidRoot(
          objectHash: object.hash,
          reason: "world may not appear in object container traversals"
        )
      }
      guard depth <= maxDepth else {
        throw ObjectLocationIndexError.depthExceeded(objectHash: object.hash, limit: maxDepth)
      }
      guard !stack.contains(object.hash) else {
        throw ObjectLocationIndexError.cycleDetected(objectHash: object.hash, path: path)
      }

      if let existing = discovered[object.hash] {
        if existing.owner != owner {
          throw ObjectLocationIndexError.ambiguousOwner(
            objectHash: object.hash,
            ownerA: existing.owner,
            ownerB: owner,
            existingPath: existing.locationPath,
            incomingPath: path
          )
        }
        throw ObjectLocationIndexError.duplicateObjectPlacement(
          objectHash: object.hash,
          existingOwner: existing.owner,
          incomingOwner: owner,
          existingPath: existing.locationPath,
          incomingPath: path
        )
      }
      discovered[object.hash] = AgentLocationRecord(
        objectHash: object.hash,
        locationPath: path,
        owner: owner
      )

      if let container = object.container {
        stack.insert(object.hash)
        for item in container.items {
          if depth + 1 > maxDepth {
            throw ObjectLocationIndexError.depthExceeded(objectHash: object.hash, limit: maxDepth)
          }
          let nextPath = path.appendingCoordinate(item.coordinate, in: object.hash)
          try assignSubtree(item.object, owner: owner, path: nextPath, depth: depth + 1)
        }
        _ = stack.remove(object.hash)
      }
    }

    // 1) World-space roots (including nested children).
    let worldPath = CanonicalLocationPath(world: world.hash)
    for item in world.container!.items {
      let itemPath = worldPath.appendingCoordinate(item.coordinate, in: world.hash)
      try assignSubtree(item.object, owner: nil, path: itemPath, depth: 1)
    }

    // 2) Agent holdings + agent-attached roots. Includes inactive agents.
    let deterministicAgents = agents.sorted(by: { $0.hash < $1.hash })
    for agent in deterministicAgents {
      let handRoots = holdingRoots(agent)
      if handRoots.count != 4 {
        throw ObjectLocationIndexError.invalidHoldingRootsCount(
          agentID: agent.hash,
          expected: 4,
          actual: handRoots.count
        )
      }
      for (index, maybeRoot) in handRoots.enumerated() {
        let slot = HoldingNumber(rawValue: index + 1)!
        if let root = maybeRoot {
          let slotPath = CanonicalLocationPath(agentHolding: agent.hash, slot: slot)
          try assignSubtree(
            root,
            owner: .agent(id: agent.hash, holding: slot),
            path: slotPath,
            depth: 1
          )
        }
      }

      for attachment in attachmentRoots(agent) {
        let attachmentPath = CanonicalLocationPath(
          agentAttachment: agent.hash, kind: attachment.kind)
        try assignSubtree(
          attachment.object,
          owner: .agent(id: agent.hash, holding: nil),
          path: attachmentPath,
          depth: 1
        )
      }
    }

    let expected = Set(byHash.keys).subtracting([world.hash])
    let present = Set(discovered.keys)
    guard expected == present else {
      let missing = expected.subtracting(present).sorted()
      throw ObjectLocationIndexError.orphanedObjects(Array(missing))
    }

    locations = discovered
  }

  public var objectHashes: [String] {
    locations.keys.sorted()
  }

  public var records: [AgentLocationRecord] {
    objectHashes.compactMap { locations[$0] }
  }

  public func location(for objectHash: String) -> AgentLocationRecord? {
    locations[objectHash]
  }

  public func location(for object: MikroObject) -> AgentLocationRecord? {
    guard registeredObjectsByHash[object.hash] === object else { return nil }
    return locations[object.hash]
  }

  public func currentOwner(of objectHash: String) -> ObjectOwner? {
    locations[objectHash]?.owner
  }

  public func currentOwner(of object: MikroObject) -> ObjectOwner? {
    guard registeredObjectsByHash[object.hash] === object else { return nil }
    return locations[object.hash]?.owner
  }

  public func parentPath(for objectHash: String) -> CanonicalLocationPath? {
    locations[objectHash]?.parentPath
  }

  public func commitmentMaterial(domain: String) -> Data {
    var rows: [String] = ["domain=\(domain)", "world=\(worldHash)"]
    for record in records {
      let ownerValue = record.owner?.commitmentTag ?? "world"
      rows.append("\(record.objectHash)|\(ownerValue)|\(record.locationPath.description)")
    }
    return Data(rows.joined(separator: "\n").utf8)
  }

  /// Returns the canonical, domain-separated commitment for one concrete
  /// object location. The commitment binds the world, exact object identity,
  /// complete parent/edge path, root kind/root identity, and derived bearer.
  public func locationCommitment(
    for objectHash: String,
    domain: String = "com.mikrokhoros.wallet.custody.location.v1"
  ) throws -> String {
    guard let record = locations[objectHash] else {
      throw ObjectLocationIndexError.orphanedObjects([objectHash])
    }
    var material = Data()
    for field in [
      domain,
      worldHash,
      objectHash,
      record.locationPath.description,
      record.locationPath.components.first ?? "invalid-root",
      record.owner?.agentID ?? "ownerless",
    ] {
      let bytes = Data(field.utf8)
      var count = UInt64(bytes.count).bigEndian
      withUnsafeBytes(of: &count) { material.append(contentsOf: $0) }
      material.append(bytes)
    }
    return SHA256Digest.hex(material)
  }
}
