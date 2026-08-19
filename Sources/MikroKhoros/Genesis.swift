import Foundation

private func requireGenesisArguments(
  _ arguments: [String],
  minimum: Int,
  maximum: Int? = nil
) throws {
  let upper = maximum ?? minimum
  guard arguments.count >= minimum, arguments.count <= upper else {
    let expected = minimum == upper ? "exactly \(minimum)" : "between \(minimum) and \(upper)"
    throw MikroKhorosError.function(
      "expected \(expected) argument(s), received \(arguments.count)"
    )
  }
}

public struct WorldGenesisIDs: Codable, Equatable, Sendable {
  public let athena: String
  public let objectiveBoard: String
  public let objectiveIndex: String
  public let warehouse: String
  public let warehouseDirectory: String
  public let library: String
  public let libraryCatalog: String

  public init(
    athena: String = AgentGenesisIDs.makeID(),
    objectiveBoard: String = AgentGenesisIDs.makeID(),
    objectiveIndex: String = AgentGenesisIDs.makeID(),
    warehouse: String = AgentGenesisIDs.makeID(),
    warehouseDirectory: String = AgentGenesisIDs.makeID(),
    library: String = AgentGenesisIDs.makeID(),
    libraryCatalog: String = AgentGenesisIDs.makeID()
  ) {
    self.athena = athena
    self.objectiveBoard = objectiveBoard
    self.objectiveIndex = objectiveIndex
    self.warehouse = warehouse
    self.warehouseDirectory = warehouseDirectory
    self.library = library
    self.libraryCatalog = libraryCatalog
  }

  static func derived(from worldID: String) -> WorldGenesisIDs {
    WorldGenesisIDs(
      athena: "\(worldID).athena",
      objectiveBoard: "\(worldID).objective-board",
      objectiveIndex: "\(worldID).objective-index",
      warehouse: "\(worldID).warehouse",
      warehouseDirectory: "\(worldID).warehouse-directory",
      library: "\(worldID).library",
      libraryCatalog: "\(worldID).library-catalog"
    )
  }

  fileprivate var all: [String] {
    [
      athena,
      objectiveBoard,
      objectiveIndex,
      warehouse,
      warehouseDirectory,
      library,
      libraryCatalog,
    ]
  }
}

public enum WorldGenesisLayout {
  public static let athena = Coordinate(x: 0, y: -2)
  public static let objectiveBoard = Coordinate(x: 1, y: -2)
  public static let library = Coordinate(x: -2, y: 2)
  public static let warehouse = Coordinate(x: 2, y: 2)
  public static let warehouseDirectory = Coordinate(x: 1, y: 0)
}

public final class AthenaObject: MikroObject {
  public init(hash: String? = nil) throws {
    try super.init(
      typeName: "athena.object",
      name: "Athena",
      summary: "The deterministic steward of the genesis district.",
      publicData: [
        "behavior": .string("deterministic"),
        "role": .string("orientation and human-authored world-change notices"),
      ],
      origin: .genesis,
      invocationAccess: .surface,
      hash: hash
    )
    try registerFunction(name: "brief", summary: "Explain the nearby genesis facilities.") {
      _, arguments in
      try requireGenesisArguments(arguments, minimum: 0)
      return """
        guide:
          steward: "Athena"
          kind: "deterministic object"
          places:
            - name: "Objective Board"
              at: "\(WorldGenesisLayout.objectiveBoard)@world"
              purpose: "enter to discover, register, and complete objectives"
            - name: "Library"
              at: "\(WorldGenesisLayout.library)@world"
              purpose: "enter to find and read sourced documents"
            - name: "Warehouse"
              at: "\(WorldGenesisLayout.warehouse)@world"
              purpose: "enter to share concrete tools and resources"
        """
    }
    try lock(authority: .system, owner: self.hash, reason: "genesis_anchor")
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try AthenaObject(hash: hash)
  }
}

public enum ObjectiveState: String, Codable, Sendable {
  case open
  case inProgress = "in_progress"
  case completed
}

public final class ObjectiveObject: MikroObject {
  public let title: String
  public let body: String
  public let createdAt: Date
  public private(set) var participantAgentIDs: Set<String> = []
  public private(set) var completedByAgentID: String?

  public var state: ObjectiveState {
    if completedByAgentID != nil { return .completed }
    return participantAgentIDs.isEmpty ? .open : .inProgress
  }

  public init(
    title: String,
    body: String,
    createdAt: Date,
    hash: String? = nil
  ) throws {
    self.title = title
    self.body = body
    self.createdAt = createdAt
    try super.init(
      typeName: "objective.object",
      name: title,
      summary: "A concrete objective posted by the human user.",
      publicData: ["status": .string(ObjectiveState.open.rawValue)],
      invocationAccess: .surface,
      hash: hash
    )
    try registerFunction(name: "read", summary: "Read the objective and its current state.") {
      context, arguments in
      try requireGenesisArguments(arguments, minimum: 0)
      return (context.object as! ObjectiveObject).render(limits: context.harness.limits)
    }
    try registerFunction(
      name: "register",
      summary: "Join this objective as a collaborating agent."
    ) { context, arguments in
      try requireGenesisArguments(arguments, minimum: 0)
      let objective = context.object as! ObjectiveObject
      guard objective.state != .completed else {
        throw MikroKhorosError.runtime(
          "objective.completed",
          "this objective is already complete",
          suggestions: ["choose an open objective from the Objective Board"]
        )
      }
      let inserted = objective.participantAgentIDs.insert(context.agent.hash).inserted
      objective.refreshPublicState()
      return inserted ? "registered for objective #\(objective.hash)" : "already registered"
    }
    try registerFunction(
      name: "complete",
      summary: "Mark the objective complete after participating in it."
    ) { context, arguments in
      try requireGenesisArguments(arguments, minimum: 0)
      let objective = context.object as! ObjectiveObject
      guard objective.state != .completed else {
        throw MikroKhorosError.runtime(
          "objective.completed",
          "this objective is already complete",
          suggestions: ["choose an open objective from the Objective Board"]
        )
      }
      guard objective.participantAgentIDs.contains(context.agent.hash) else {
        throw MikroKhorosError.runtime(
          "objective.not_registered",
          "the agent is not registered for this objective",
          suggestions: ["run `object (register)` before completing the objective"]
        )
      }
      objective.completedByAgentID = context.agent.hash
      objective.refreshPublicState()
      return "completed objective #\(objective.hash)"
    }
  }

  private func refreshPublicState() {
    setPublicData(.string(state.rawValue), forKey: "status")
    setPublicData(
      .array(participantAgentIDs.sorted().map(JSONValue.string)),
      forKey: "participants"
    )
    if let completedByAgentID {
      setPublicData(.string(completedByAgentID), forKey: "completed_by")
    }
  }

  private func render(limits: RuntimeLimits) -> String {
    let formatter = ISO8601DateFormatter()
    var lines = [
      "objective:",
      "  id: \(PromptSafety.yamlScalar(hash, limit: 128))",
      "  title: \(PromptSafety.yamlScalar(title, limit: limits.maximumModelFieldCharacters))",
      "  status: \(state.rawValue)",
      "  created_at: \(PromptSafety.yamlScalar(formatter.string(from: createdAt)))",
      "  body: \(PromptSafety.yamlScalar(body, limit: limits.maximumModelFieldCharacters))",
    ]
    if participantAgentIDs.isEmpty {
      lines.append("  participants: []")
    } else {
      lines.append("  participants:")
      for participant in participantAgentIDs.sorted() {
        lines.append("    - \(PromptSafety.yamlScalar(participant, limit: 128))")
      }
    }
    if let completedByAgentID {
      lines.append(
        "  completed_by: \(PromptSafety.yamlScalar(completedByAgentID, limit: 128))"
      )
    } else {
      lines.append("  completed_by: null")
    }
    return lines.joined(separator: "\n")
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try ObjectiveObject(title: title, body: body, createdAt: createdAt, hash: hash)
  }
}

public final class ObjectiveIndexObject: MikroObject {
  public let boardID: String

  public init(boardID: String, hash: String? = nil) throws {
    self.boardID = boardID
    try super.init(
      typeName: "objective-index.object",
      name: "Objective Index",
      summary: "The directory inside the Objective Board.",
      origin: .genesis,
      invocationAccess: .surface,
      hash: hash
    )
    try registerFunction(name: "list", summary: "List objectives and their local positions.") {
      context, arguments in
      try requireGenesisArguments(arguments, minimum: 0)
      let index = context.object as! ObjectiveIndexObject
      let board = try context.harness.object(byHash: index.boardID)
      let objectives =
        board.container?.items.compactMap { item in
          (item.object as? ObjectiveObject).map { (item.coordinate, $0) }
        } ?? []
      guard !objectives.isEmpty else { return "objectives: []" }
      var lines = ["objectives:"]
      for (coordinate, objective) in objectives {
        lines.append("  - id: \(PromptSafety.yamlScalar(objective.hash, limit: 128))")
        lines.append(
          "    title: \(PromptSafety.yamlScalar(objective.title, limit: context.harness.limits.maximumModelFieldCharacters))"
        )
        lines.append("    status: \(objective.state.rawValue)")
        lines.append("    at: \(PromptSafety.yamlScalar(coordinate.description))")
        lines.append("    participants: \(objective.participantAgentIDs.count)")
      }
      return lines.joined(separator: "\n")
    }
    try lock(authority: .system, owner: self.hash, reason: "genesis_anchor")
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try ObjectiveIndexObject(boardID: boardID, hash: hash)
  }
}

public final class WarehouseDirectoryObject: MikroObject {
  public let warehouseID: String

  public init(warehouseID: String, hash: String? = nil) throws {
    self.warehouseID = warehouseID
    try super.init(
      typeName: "warehouse-directory.object",
      name: "Warehouse Directory",
      summary: "Lists the concrete objects currently stored in the shared warehouse.",
      origin: .genesis,
      invocationAccess: .surface,
      hash: hash
    )
    try registerFunction(name: "list", summary: "List stored objects and local positions.") {
      context, arguments in
      try requireGenesisArguments(arguments, minimum: 0)
      let directory = context.object as! WarehouseDirectoryObject
      let warehouse = try context.harness.object(byHash: directory.warehouseID)
      let items = warehouse.container?.items.filter { $0.object !== directory } ?? []
      guard !items.isEmpty else { return "inventory: []" }
      var lines = ["inventory:"]
      for item in items {
        lines.append("  - at: \(PromptSafety.yamlScalar(item.coordinate.description))")
        lines.append("    id: \(PromptSafety.yamlScalar(item.object.hash, limit: 128))")
        lines.append("    type: \(PromptSafety.yamlScalar(item.object.typeName, limit: 128))")
        lines.append("    name: \(PromptSafety.yamlScalar(item.object.name, limit: 128))")
      }
      return lines.joined(separator: "\n")
    }
    try lock(authority: .system, owner: self.hash, reason: "genesis_anchor")
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try WarehouseDirectoryObject(warehouseID: warehouseID, hash: hash)
  }
}

public final class LibraryDocumentObject: MikroObject {
  public let title: String
  public let sourceURL: String
  public let content: String
  public let fetchedAt: Date

  public init(
    title: String,
    sourceURL: String,
    content: String,
    fetchedAt: Date,
    hash: String? = nil
  ) throws {
    self.title = title
    self.sourceURL = sourceURL
    self.content = content
    self.fetchedAt = fetchedAt
    try super.init(
      typeName: "document.object",
      name: title,
      summary: "A sourced document stored in the world library.",
      publicData: [
        "characters": .number(Double(content.count)),
        "source": .string(sourceURL),
        "trust": .string("external_untrusted"),
      ],
      invocationAccess: .surface,
      hash: hash
    )
    try registerFunction(name: "read", summary: "Read the first bounded document page.") {
      context, arguments in
      try requireGenesisArguments(arguments, minimum: 0)
      return try (context.object as! LibraryDocumentObject).renderPage(
        start: 0,
        requestedCount: context.harness.limits.maximumModelFieldCharacters,
        limits: context.harness.limits
      )
    }
    try registerFunction(
      name: "read_range",
      summary: "Read a bounded character range.",
      parameters: ["start", "length"]
    ) { context, arguments in
      try requireGenesisArguments(arguments, minimum: 2)
      guard let start = Int(arguments[0]), start >= 0,
        let length = Int(arguments[1]), length > 0
      else {
        throw MikroKhorosError.function(
          "document range requires a non-negative start and positive length")
      }
      return try (context.object as! LibraryDocumentObject).renderPage(
        start: start,
        requestedCount: length,
        limits: context.harness.limits
      )
    }
  }

  private func renderPage(
    start: Int,
    requestedCount: Int,
    limits: RuntimeLimits
  ) throws -> String {
    guard start <= content.count else {
      throw MikroKhorosError.runtime(
        "document.range_out_of_bounds",
        "document range starts beyond the available content",
        suggestions: ["use a start between 0 and \(content.count)"]
      )
    }
    let pageLimit = limits.maximumModelFieldCharacters
    let count = min(requestedCount, pageLimit, content.count - start)
    let lower = content.index(content.startIndex, offsetBy: start)
    let upper = content.index(lower, offsetBy: count)
    let page = String(content[lower..<upper])
    let end = start + count
    let formatter = ISO8601DateFormatter()
    return """
      document:
        id: \(PromptSafety.yamlScalar(hash, limit: 128))
        title: \(PromptSafety.yamlScalar(title, limit: limits.maximumModelFieldCharacters))
        source: \(PromptSafety.yamlScalar(sourceURL, limit: limits.maximumModelFieldCharacters))
        fetched_at: \(PromptSafety.yamlScalar(formatter.string(from: fetchedAt)))
        trust: external_untrusted
        start: \(start)
        end: \(end)
        total: \(content.count)
        next_start: \(end < content.count ? String(end) : "null")
        body: \(PromptSafety.yamlScalar(page, limit: pageLimit))
      """
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try LibraryDocumentObject(
      title: title,
      sourceURL: sourceURL,
      content: content,
      fetchedAt: fetchedAt,
      hash: hash
    )
  }
}

public final class LibraryCatalogObject: MikroObject {
  public let libraryID: String

  public init(libraryID: String, hash: String? = nil) throws {
    self.libraryID = libraryID
    try super.init(
      typeName: "library-catalog.object",
      name: "Library Catalog",
      summary: "Lists sourced document objects stored in the library.",
      origin: .genesis,
      invocationAccess: .surface,
      hash: hash
    )
    try registerFunction(name: "list", summary: "List documents and their local positions.") {
      context, arguments in
      try requireGenesisArguments(arguments, minimum: 0)
      let catalog = context.object as! LibraryCatalogObject
      let library = try context.harness.object(byHash: catalog.libraryID)
      let documents =
        library.container?.items.compactMap { item in
          (item.object as? LibraryDocumentObject).map { (item.coordinate, $0) }
        } ?? []
      guard !documents.isEmpty else { return "documents: []" }
      var lines = ["documents:"]
      for (coordinate, document) in documents {
        lines.append("  - id: \(PromptSafety.yamlScalar(document.hash, limit: 128))")
        lines.append(
          "    title: \(PromptSafety.yamlScalar(document.title, limit: context.harness.limits.maximumModelFieldCharacters))"
        )
        lines.append("    at: \(PromptSafety.yamlScalar(coordinate.description))")
        lines.append("    characters: \(document.content.count)")
        lines.append(
          "    source: \(PromptSafety.yamlScalar(document.sourceURL, limit: context.harness.limits.maximumModelFieldCharacters))"
        )
      }
      return lines.joined(separator: "\n")
    }
    try lock(authority: .system, owner: self.hash, reason: "genesis_anchor")
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try LibraryCatalogObject(libraryID: libraryID, hash: hash)
  }
}

func installWorldGenesis(in world: MikroObject, ids: WorldGenesisIDs) throws {
  guard let space = world.container else {
    throw MikroKhorosError.placement("the world must have container capability")
  }
  guard
    ids.all.allSatisfy({ !$0.isEmpty && $0.count <= 128 && !$0.contains(where: { $0.isNewline }) }),
    Set(ids.all).count == ids.all.count,
    !ids.all.contains(world.hash)
  else {
    throw MikroKhorosError.placement(
      "world genesis identities must be unique bounded single-line values"
    )
  }

  let athena = try AthenaObject(hash: ids.athena)

  let objectiveBoard = try MikroObject(
    typeName: "objective-board.object",
    name: "Objective Board",
    summary: "A shared container where agents discover and pursue concrete objectives.",
    origin: .genesis,
    hash: ids.objectiveBoard
  )
  try objectiveBoard.addContainerCapability()
  try objectiveBoard.lock(
    authority: .system,
    owner: objectiveBoard.hash,
    reason: "genesis_anchor"
  )
  let objectiveIndex = try ObjectiveIndexObject(
    boardID: objectiveBoard.hash,
    hash: ids.objectiveIndex
  )
  try objectiveBoard.container!.place(objectiveIndex, at: .origin)

  let warehouse = try MikroObject(
    typeName: "warehouse.object",
    name: "Warehouse",
    summary: "A shared container for concrete tools and resources.",
    origin: .genesis,
    hash: ids.warehouse
  )
  try warehouse.addContainerCapability()
  try warehouse.lock(authority: .system, owner: warehouse.hash, reason: "genesis_anchor")
  let warehouseDirectory = try WarehouseDirectoryObject(
    warehouseID: warehouse.hash,
    hash: ids.warehouseDirectory
  )
  try warehouse.container!.place(
    warehouseDirectory,
    at: WorldGenesisLayout.warehouseDirectory
  )

  let library = try MikroObject(
    typeName: "library.object",
    name: "Library",
    summary: "A shared container of sourced document objects.",
    origin: .genesis,
    hash: ids.library
  )
  try library.addContainerCapability()
  try library.lock(authority: .system, owner: library.hash, reason: "genesis_anchor")
  let libraryCatalog = try LibraryCatalogObject(
    libraryID: library.hash,
    hash: ids.libraryCatalog
  )
  try library.container!.place(libraryCatalog, at: .origin)

  try space.place(athena, at: WorldGenesisLayout.athena)
  try space.place(objectiveBoard, at: WorldGenesisLayout.objectiveBoard)
  try space.place(library, at: WorldGenesisLayout.library)
  try space.place(warehouse, at: WorldGenesisLayout.warehouse)
}
