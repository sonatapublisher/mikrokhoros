import Foundation

public struct WorkspaceAgentRecord: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let initialCoinBalance: Decimal?
  public let maximumActionsPerResponse: Int
  public let genesis: AgentGenesisIDs

  public init(
    id: String,
    name: String,
    initialCoinBalance: Decimal?,
    maximumActionsPerResponse: Int,
    genesis: AgentGenesisIDs
  ) {
    self.id = id
    self.name = name
    self.initialCoinBalance = initialCoinBalance
    self.maximumActionsPerResponse = maximumActionsPerResponse
    self.genesis = genesis
  }
}

public struct AthenaNoticeDelivery: Codable, Equatable, Sendable {
  public let messengerID: String
  public let messageID: String
  public let body: String
  public let timestamp: Date

  public init(
    messengerID: String,
    messageID: String,
    body: String,
    timestamp: Date
  ) {
    self.messengerID = messengerID
    self.messageID = messageID
    self.body = body
    self.timestamp = timestamp
  }
}

public enum WorkspaceEvent: Codable, Equatable, Sendable {
  case addAgent(agentID: String, coordinate: Coordinate, autoAdapt: Bool)
  case removeAgent(agentID: String)
  case configureAgent(agentID: String, maximumActionsPerResponse: Int)
  case attachProfile(agentID: String, profile: AIProfile)
  case detachProfile(agentID: String)
  case actions(
    agentID: String,
    commands: [String],
    drainedBroadcasts: Bool,
    generatedIDs: [String],
    generatedDates: [Date]
  )
  case message(
    messengerID: String,
    id: String,
    body: String,
    sender: String,
    senderAgentID: String?,
    threadID: String,
    priority: BroadcastPriority?,
    timestamp: Date
  )
  case grantCoin(agentID: String, amount: Decimal?)
  case objectivePosted(
    id: String,
    title: String,
    body: String,
    createdAt: Date,
    coordinate: Coordinate
  )
  case libraryDocumentAdded(
    id: String,
    title: String,
    sourceURL: String,
    content: String,
    fetchedAt: Date,
    coordinate: Coordinate
  )
  case athenaNotice(deliveries: [AthenaNoticeDelivery])
}

private final class WorkspaceEntropy {
  private enum Mode {
    case idle
    case recording(ids: [String], dates: [Date])
    case replaying(ids: [String], dates: [Date], idIndex: Int, dateIndex: Int, mismatch: Bool)
  }

  private var mode: Mode = .idle

  func beginRecording() { mode = .recording(ids: [], dates: []) }

  func finishRecording() -> (ids: [String], dates: [Date]) {
    guard case .recording(let ids, let dates) = mode else { return ([], []) }
    mode = .idle
    return (ids, dates)
  }

  func beginReplay(ids: [String], dates: [Date]) {
    mode = .replaying(
      ids: ids, dates: dates, idIndex: 0, dateIndex: 0, mismatch: false
    )
  }

  func finishReplay() throws {
    guard case .replaying(_, _, _, _, let mismatch) = mode else { return }
    mode = .idle
    if mismatch {
      throw MikroKhorosError.persistence("action entropy tape is incomplete")
    }
  }

  func nextID() -> String {
    switch mode {
    case .idle:
      return Self.makeID()
    case .recording(var ids, let dates):
      let value = Self.makeID()
      ids.append(value)
      mode = .recording(ids: ids, dates: dates)
      return value
    case .replaying(let ids, let dates, let index, let dateIndex, let mismatch):
      guard index < ids.count else {
        mode = .replaying(
          ids: ids, dates: dates, idIndex: index, dateIndex: dateIndex, mismatch: true
        )
        return Self.makeID()
      }
      mode = .replaying(
        ids: ids,
        dates: dates,
        idIndex: index + 1,
        dateIndex: dateIndex,
        mismatch: mismatch
      )
      return ids[index]
    }
  }

  func nextDate() -> Date {
    switch mode {
    case .idle:
      return Date()
    case .recording(let ids, var dates):
      let value = Date()
      dates.append(value)
      mode = .recording(ids: ids, dates: dates)
      return value
    case .replaying(let ids, let dates, let idIndex, let index, let mismatch):
      guard index < dates.count else {
        mode = .replaying(
          ids: ids, dates: dates, idIndex: idIndex, dateIndex: index, mismatch: true
        )
        return Date()
      }
      mode = .replaying(
        ids: ids,
        dates: dates,
        idIndex: idIndex,
        dateIndex: index + 1,
        mismatch: mismatch
      )
      return dates[index]
    }
  }

  private static func makeID() -> String {
    UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
  }
}

public struct WorkspaceDocument: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 2

  public var schemaVersion: Int
  public var worldID: String
  public var worldGenesis: WorldGenesisIDs
  public var agents: [WorkspaceAgentRecord]
  public var events: [WorkspaceEvent]
  public var histories: [String: [AIConversationMessage]]

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, worldID, worldGenesis, agents, events, histories
  }

  public init(
    schemaVersion: Int = WorkspaceDocument.currentSchemaVersion,
    worldID: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
    worldGenesis: WorldGenesisIDs? = nil,
    agents: [WorkspaceAgentRecord] = [],
    events: [WorkspaceEvent] = [],
    histories: [String: [AIConversationMessage]] = [:]
  ) {
    self.schemaVersion = schemaVersion
    self.worldID = worldID
    self.worldGenesis = worldGenesis ?? WorldGenesisIDs()
    self.agents = agents
    self.events = events
    self.histories = histories
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let storedVersion = try container.decode(Int.self, forKey: .schemaVersion)
    let worldID = try container.decode(String.self, forKey: .worldID)
    schemaVersion = storedVersion == 1 ? Self.currentSchemaVersion : storedVersion
    self.worldID = worldID
    worldGenesis =
      try container.decodeIfPresent(WorldGenesisIDs.self, forKey: .worldGenesis)
      ?? WorldGenesisIDs.derived(from: worldID)
    agents = try container.decode([WorkspaceAgentRecord].self, forKey: .agents)
    events = try container.decode([WorkspaceEvent].self, forKey: .events)
    histories = try container.decode(
      [String: [AIConversationMessage]].self,
      forKey: .histories
    )
  }
}

/// A persistent, event-sourced CLI workspace. Custom hosts may use the lower-level
/// library directly and provide their own object snapshot storage.
public final class WorkspaceRuntime {
  public private(set) var document: WorkspaceDocument
  public let configuration: RuntimeConfiguration
  public let harness: Harness
  private var sessions: [String: AgentSession] = [:]
  private let entropy: WorkspaceEntropy

  public init(
    document: WorkspaceDocument = WorkspaceDocument(),
    configuration: RuntimeConfiguration = .defaults
  ) throws {
    try configuration.validate()
    guard document.schemaVersion == WorkspaceDocument.currentSchemaVersion else {
      throw MikroKhorosError.persistence(
        "unsupported workspace schema version \(document.schemaVersion)"
      )
    }
    guard document.agents.count <= 10_000, document.events.count <= 1_000_000 else {
      throw MikroKhorosError.persistence("workspace exceeds the supported record limits")
    }
    let agentIDs = document.agents.map(\.id)
    guard Set(agentIDs).count == agentIDs.count else {
      throw MikroKhorosError.persistence("workspace contains duplicate agent identities")
    }
    guard document.histories.count <= document.agents.count,
      document.histories.keys.allSatisfy({ agentIDs.contains($0) })
    else {
      throw MikroKhorosError.persistence("workspace contains history for an unknown agent")
    }
    do {
      let persistenceLimits = RuntimeLimits.persistenceValidation(
        maximumCharacters: WorkspaceStore.maximumBytes
      )
      for history in document.histories.values {
        try PromptSafety.validateModelHistory(history, limits: persistenceLimits)
      }
    } catch {
      throw MikroKhorosError.persistence("workspace contains invalid model history")
    }

    let entropy = WorkspaceEntropy()
    self.entropy = entropy
    self.document = document
    self.configuration = configuration
    self.harness = try Harness(
      world: createWorld(hash: document.worldID, genesisIDs: document.worldGenesis),
      limits: configuration.runtime,
      runtimeIdentityProvider: { entropy.nextID() },
      runtimeDateProvider: { entropy.nextDate() }
    )
    for record in document.agents {
      let backpack = try createBackpack(ids: record.genesis)
      let coin = try CoinObject(balance: record.initialCoinBalance, hash: record.genesis.coin)
      let agent = try harness.createAgent(
        name: record.name,
        coinBalance: record.initialCoinBalance,
        maximumActionsPerResponse: record.maximumActionsPerResponse,
        hash: record.id,
        backpack: backpack,
        coin: coin
      )
      sessions[agent.hash] = AgentSession(
        harness: harness,
        agent: agent,
        history: document.histories[agent.hash] ?? []
      )
    }
    for (index, event) in document.events.enumerated() {
      do { try replay(event) } catch {
        throw MikroKhorosError.persistence(
          "workspace event \(index + 1) could not be replayed: \(safeReason(error))"
        )
      }
    }
  }

  @discardableResult
  public func createAgent(
    name: String,
    coinBalance: Decimal? = 0,
    maximumActionsPerResponse: Int? = nil
  ) throws -> Agent {
    let resolvedMaximum =
      maximumActionsPerResponse ?? configuration.agents.maximumActionsPerResponse
    let genesis = AgentGenesisIDs()
    let backpack = try createBackpack(ids: genesis)
    let coin = try CoinObject(balance: coinBalance, hash: genesis.coin)
    let agent = try harness.createAgent(
      name: name,
      coinBalance: coinBalance,
      maximumActionsPerResponse: resolvedMaximum,
      backpack: backpack,
      coin: coin
    )
    document.agents.append(
      WorkspaceAgentRecord(
        id: agent.hash,
        name: name,
        initialCoinBalance: coinBalance,
        maximumActionsPerResponse: resolvedMaximum,
        genesis: genesis
      )
    )
    sessions[agent.hash] = AgentSession(harness: harness, agent: agent)
    return agent
  }

  public func setMaximumActionsPerResponse(_ value: Int, for agent: Agent) throws {
    _ = try record(for: agent)
    try harness.setMaximumActionsPerResponse(value, for: agent)
    document.events.append(
      .configureAgent(
        agentID: agent.hash,
        maximumActionsPerResponse: value
      )
    )
  }

  @discardableResult
  public func addAgent(
    _ agent: Agent,
    at coordinate: Coordinate = .origin,
    autoAdapt: Bool = false
  ) throws -> AgentPlacement {
    let record = try record(for: agent)
    let eye = agent.hasEnteredWorld ? nil : try EyeObject(hash: record.genesis.eye)
    let placement = try harness.addAgent(agent, at: coordinate, autoAdapt: autoAdapt, eye: eye)
    document.events.append(
      .addAgent(agentID: agent.hash, coordinate: coordinate, autoAdapt: autoAdapt)
    )
    try announceThroughAthena(
      "\(agent.name) entered the world at \(harness.agentPath(agent))."
    )
    return placement
  }

  public func removeAgent(_ agent: Agent) throws {
    let name = agent.name
    try harness.removeAgentFromWorld(agent)
    document.events.append(.removeAgent(agentID: agent.hash))
    try announceThroughAthena("\(name) left the world.")
  }

  public func attachProfile(_ profile: AIProfile, to agent: Agent) throws {
    try harness.attachProfile(profile, to: agent)
    document.events.append(.attachProfile(agentID: agent.hash, profile: profile))
  }

  public func detachProfile(from agent: Agent) throws {
    _ = try record(for: agent)
    harness.detachProfile(from: agent)
    document.events.append(.detachProfile(agentID: agent.hash))
  }

  @discardableResult
  public func run(_ response: String, for agent: Agent) throws -> AgentTurn {
    let session = try session(for: agent)
    entropy.beginRecording()
    let turn = session.run(response)
    let generated = entropy.finishRecording()
    let commands = turn.results.compactMap(\.command)
    let drained = turn.events.contains { if case .broadcast = $0 { true } else { false } }
    if !commands.isEmpty || drained {
      document.events.append(
        .actions(
          agentID: agent.hash,
          commands: commands,
          drainedBroadcasts: drained,
          generatedIDs: generated.ids,
          generatedDates: generated.dates
        )
      )
    }
    return turn
  }

  @discardableResult
  public func sendMessage(
    to agent: Agent,
    body: String,
    sender: String = "user",
    senderAgentID: String? = nil,
    threadID: String = "#1",
    priority: BroadcastPriority? = nil,
    timestamp: Date = Date()
  ) throws -> MessengerMessage {
    let messenger = try harness.messenger(for: agent)
    _ = try messenger.ensureThread(id: threadID, title: threadID == "#1" ? "Messages" : threadID)
    let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let message = try harness.deliverMessage(
      to: messenger,
      body: body,
      id: id,
      sender: sender,
      senderAgentID: senderAgentID,
      threadID: threadID,
      priority: priority,
      timestamp: timestamp
    )
    document.events.append(
      .message(
        messengerID: messenger.hash,
        id: id,
        body: body,
        sender: sender,
        senderAgentID: senderAgentID,
        threadID: threadID,
        priority: priority,
        timestamp: timestamp
      )
    )
    return message
  }

  public func grantCoin(_ amount: Decimal?, to agent: Agent) throws {
    try agent.coin.grant(amount)
    document.events.append(.grantCoin(agentID: agent.hash, amount: amount))
  }

  public var objectives: [ObjectiveObject] {
    guard let board = harness.findObject(document.worldGenesis.objectiveBoard) else { return [] }
    return board.container?.items.compactMap { $0.object as? ObjectiveObject } ?? []
  }

  public var libraryDocuments: [LibraryDocumentObject] {
    guard let library = harness.findObject(document.worldGenesis.library) else { return [] }
    return library.container?.items.compactMap { $0.object as? LibraryDocumentObject } ?? []
  }

  @discardableResult
  public func postObjective(
    title: String,
    body: String,
    createdAt: Date = Date()
  ) throws -> ObjectiveObject {
    try validateWorldText(title, label: "objective title", allowNewlines: false, name: true)
    try validateWorldText(body, label: "objective body", allowNewlines: true)
    let board = try harness.object(byHash: document.worldGenesis.objectiveBoard)
    guard let space = board.container else {
      throw MikroKhorosError.persistence("the Objective Board has no container capability")
    }
    let objective = try ObjectiveObject(
      title: title,
      body: body,
      createdAt: createdAt,
      hash: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    )
    try objective.lock(
      authority: .system,
      owner: board.hash,
      reason: "objective_board_entry"
    )
    let coordinate = harness.nearestAvailableCoordinate(in: space, around: .origin)
    try harness.place(objective, at: coordinate, in: space)
    document.events.append(
      .objectivePosted(
        id: objective.hash,
        title: title,
        body: body,
        createdAt: createdAt,
        coordinate: coordinate
      )
    )
    try announceThroughAthena("A new objective was posted: \(title).")
    return objective
  }

  @discardableResult
  public func addLibraryDocument(
    title: String,
    sourceURL: String,
    content: String,
    fetchedAt: Date = Date()
  ) throws -> LibraryDocumentObject {
    try validateWorldText(title, label: "document title", allowNewlines: false, name: true)
    try validateWorldText(sourceURL, label: "document source", allowNewlines: false)
    guard content.utf8.count <= configuration.runtime.maximumProviderResponseBytes else {
      throw MikroKhorosError.runtime(
        "library.document_too_large",
        "the document exceeds the configured external response byte limit",
        details: ["limit": String(configuration.runtime.maximumProviderResponseBytes)],
        suggestions: ["raise the configured byte limit or use a smaller source"]
      )
    }
    guard !content.isEmpty else {
      throw MikroKhorosError.function("document content cannot be empty")
    }
    let library = try harness.object(byHash: document.worldGenesis.library)
    guard let space = library.container else {
      throw MikroKhorosError.persistence("the Library has no container capability")
    }
    let documentObject = try LibraryDocumentObject(
      title: title,
      sourceURL: sourceURL,
      content: content,
      fetchedAt: fetchedAt,
      hash: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    )
    try documentObject.lock(
      authority: .system,
      owner: library.hash,
      reason: "library_document"
    )
    let coordinate = harness.nearestAvailableCoordinate(in: space, around: .origin)
    try harness.place(documentObject, at: coordinate, in: space)
    document.events.append(
      .libraryDocumentAdded(
        id: documentObject.hash,
        title: title,
        sourceURL: sourceURL,
        content: content,
        fetchedAt: fetchedAt,
        coordinate: coordinate
      )
    )
    try announceThroughAthena("A document was added to the Library: \(title).")
    return documentObject
  }

  public func handlePendingRequest(
    for agent: Agent,
    using client: (any AICompleting)? = nil
  ) async throws -> AgentTurn? {
    let session = try session(for: agent)
    let resolvedClient: any AICompleting =
      client ?? AICompletionClient(limits: configuration.runtime)
    entropy.beginRecording()
    let turn: AgentTurn?
    do {
      turn = try await session.handlePendingRequest(using: resolvedClient)
    } catch {
      _ = entropy.finishRecording()
      throw error
    }
    let generated = entropy.finishRecording()
    guard let turn else { return nil }
    let commands = turn.results.compactMap(\.command)
    document.events.append(
      .actions(
        agentID: agent.hash,
        commands: commands,
        drainedBroadcasts: true,
        generatedIDs: generated.ids,
        generatedDates: generated.dates
      )
    )
    document.histories[agent.hash] = session.history
    return turn
  }

  public func session(for agent: Agent) throws -> AgentSession {
    guard harness.findAgent(agent.hash) === agent, let session = sessions[agent.hash] else {
      throw MikroKhorosError.command("agent does not belong to this workspace")
    }
    return session
  }

  private func record(for agent: Agent) throws -> WorkspaceAgentRecord {
    guard let record = document.agents.first(where: { $0.id == agent.hash }) else {
      throw MikroKhorosError.command("agent does not belong to this workspace")
    }
    return record
  }

  private func validateWorldText(
    _ value: String,
    label: String,
    allowNewlines: Bool,
    name: Bool = false
  ) throws {
    let maximum =
      name
      ? min(128, configuration.runtime.maximumModelFieldCharacters)
      : configuration.runtime.maximumModelFieldCharacters
    guard !value.isEmpty, value.count <= maximum,
      allowNewlines || !value.contains(where: { $0.isNewline })
    else {
      throw MikroKhorosError.function(
        "\(label) must be non-empty and fit the configured field limit"
      )
    }
  }

  private func announceThroughAthena(_ body: String) throws {
    let timestamp = Date()
    var deliveries: [AthenaNoticeDelivery] = []
    for agent in harness.activeAgents {
      guard let record = document.agents.first(where: { $0.id == agent.hash }),
        let messenger = harness.findObject(record.genesis.messenger) as? MessengerObject
      else { continue }
      _ = try messenger.ensureThread(id: "#athena", title: "Athena")
      let messageID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
      _ = try harness.deliverMessage(
        to: messenger,
        body: body,
        id: messageID,
        sender: "Athena",
        threadID: "#athena",
        timestamp: timestamp
      )
      deliveries.append(
        AthenaNoticeDelivery(
          messengerID: messenger.hash,
          messageID: messageID,
          body: body,
          timestamp: timestamp
        )
      )
    }
    if !deliveries.isEmpty { document.events.append(.athenaNotice(deliveries: deliveries)) }
  }

  private func replay(_ event: WorkspaceEvent) throws {
    switch event {
    case .addAgent(let id, let coordinate, let autoAdapt):
      let agent = try harness.resolveAgent(id)
      let ids = try record(for: agent).genesis
      let eye = agent.hasEnteredWorld ? nil : try EyeObject(hash: ids.eye)
      _ = try harness.addAgent(agent, at: coordinate, autoAdapt: autoAdapt, eye: eye)
    case .removeAgent(let id):
      try harness.removeAgentFromWorld(try harness.resolveAgent(id))
    case .configureAgent(let id, let maximumActionsPerResponse):
      try harness.setMaximumActionsPerResponse(
        maximumActionsPerResponse,
        for: harness.resolveAgent(id)
      )
    case .attachProfile(let id, let profile):
      try harness.attachProfile(profile, to: harness.resolveAgent(id))
    case .detachProfile(let id):
      harness.detachProfile(from: try harness.resolveAgent(id))
    case .actions(
      let id, let commands, let drainedBroadcasts, let generatedIDs, let generatedDates
    ):
      let agent = try harness.resolveAgent(id)
      entropy.beginReplay(ids: generatedIDs, dates: generatedDates)
      if !commands.isEmpty {
        try session(for: agent).replayPersisted(commands)
      } else if drainedBroadcasts {
        _ = harness.drainBroadcasts(for: agent)
      }
      try entropy.finishReplay()
    case .message(
      let messengerID, let id, let body, let sender, let senderAgentID,
      let threadID, let priority, let timestamp
    ):
      guard let messenger = try harness.object(byHash: messengerID) as? MessengerObject else {
        throw MikroKhorosError.persistence("message target is not a messenger")
      }
      _ = try messenger.ensureThread(
        id: threadID,
        title: threadID == "#1" ? "Messages" : threadID
      )
      _ = try harness.deliverMessage(
        to: messenger,
        body: body,
        id: id,
        sender: sender,
        senderAgentID: senderAgentID,
        threadID: threadID,
        priority: priority,
        timestamp: timestamp
      )
    case .grantCoin(let id, let amount):
      try harness.resolveAgent(id).coin.grant(amount)
    case .objectivePosted(let id, let title, let body, let createdAt, let coordinate):
      let board = try harness.object(byHash: document.worldGenesis.objectiveBoard)
      guard let space = board.container else {
        throw MikroKhorosError.persistence("the Objective Board has no container capability")
      }
      let objective = try ObjectiveObject(
        title: title,
        body: body,
        createdAt: createdAt,
        hash: id
      )
      try objective.lock(
        authority: .system,
        owner: board.hash,
        reason: "objective_board_entry"
      )
      try harness.place(objective, at: coordinate, in: space)
    case .libraryDocumentAdded(
      let id, let title, let sourceURL, let content, let fetchedAt, let coordinate
    ):
      let library = try harness.object(byHash: document.worldGenesis.library)
      guard let space = library.container else {
        throw MikroKhorosError.persistence("the Library has no container capability")
      }
      let documentObject = try LibraryDocumentObject(
        title: title,
        sourceURL: sourceURL,
        content: content,
        fetchedAt: fetchedAt,
        hash: id
      )
      try documentObject.lock(
        authority: .system,
        owner: library.hash,
        reason: "library_document"
      )
      try harness.place(documentObject, at: coordinate, in: space)
    case .athenaNotice(let deliveries):
      for delivery in deliveries {
        guard let messenger = try harness.object(byHash: delivery.messengerID) as? MessengerObject
        else {
          throw MikroKhorosError.persistence("Athena notice target is not a messenger")
        }
        _ = try messenger.ensureThread(id: "#athena", title: "Athena")
        _ = try harness.deliverMessage(
          to: messenger,
          body: delivery.body,
          id: delivery.messageID,
          sender: "Athena",
          threadID: "#athena",
          timestamp: delivery.timestamp
        )
      }
    }
  }

  private func safeReason(_ error: Error) -> String {
    if let error = error as? MikroKhorosError { return error.description }
    return "invalid persisted state"
  }
}

public enum WorkspaceStore {
  public static let maximumBytes = 64 * 1_024 * 1_024

  public static var defaultURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".mikrokhoros", isDirectory: true)
      .appendingPathComponent("workspace.json", isDirectory: false)
  }

  public static func load(from url: URL = defaultURL) throws -> WorkspaceDocument {
    guard FileManager.default.fileExists(atPath: url.path) else { return WorkspaceDocument() }
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      if let size = values.fileSize, size > maximumBytes {
        throw MikroKhorosError.persistence("workspace exceeds the 64 MB limit")
      }
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(WorkspaceDocument.self, from: data)
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.persistence("could not read the workspace JSON")
    }
  }

  public static func save(
    _ document: WorkspaceDocument,
    to url: URL = defaultURL
  ) throws {
    do {
      let directory = url.deletingLastPathComponent()
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(document)
      guard data.count <= maximumBytes else {
        throw MikroKhorosError.persistence("workspace exceeds the 64 MB limit")
      }
      try data.write(to: url, options: [.atomic])
      #if !os(Windows)
        try? FileManager.default.setAttributes(
          [.posixPermissions: 0o600],
          ofItemAtPath: url.path
        )
      #endif
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.persistence("could not write the workspace JSON")
    }
  }
}
