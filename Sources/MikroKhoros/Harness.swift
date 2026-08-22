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

public enum Directions {
  public static let values: [String: Coordinate] = [
    "north": Coordinate(x: 0, y: -1), "n": Coordinate(x: 0, y: -1),
    "up": Coordinate(x: 0, y: -1),
    "northeast": Coordinate(x: 1, y: -1), "ne": Coordinate(x: 1, y: -1),
    "east": Coordinate(x: 1, y: 0), "e": Coordinate(x: 1, y: 0),
    "right": Coordinate(x: 1, y: 0),
    "southeast": Coordinate(x: 1, y: 1), "se": Coordinate(x: 1, y: 1),
    "south": Coordinate(x: 0, y: 1), "s": Coordinate(x: 0, y: 1),
    "down": Coordinate(x: 0, y: 1),
    "southwest": Coordinate(x: -1, y: 1), "sw": Coordinate(x: -1, y: 1),
    "west": Coordinate(x: -1, y: 0), "w": Coordinate(x: -1, y: 0),
    "left": Coordinate(x: -1, y: 0),
    "northwest": Coordinate(x: -1, y: -1), "nw": Coordinate(x: -1, y: -1),
  ]
}

public struct AgentPlacement: Equatable, Sendable {
  public let requested: Coordinate
  public let actual: Coordinate
  public let adapted: Bool
}

public struct PurchaseResult {
  public let item: MikroObject
  public let price: Decimal
  public let restocked: MikroObject?
  public let creditRecord: SignedCreditRecord
}

private struct WalletCustodyState {
  let walletID: String
  let ownerID: String?
  let locationCommitment: String
  let custodyCommitment: String
}

struct CreditOperationIdentity: Equatable, Sendable {
  let operationID: String
  let actionIndex: UInt64
  let actor: CreditActor
}

public final class Harness {
  public let world: MikroObject
  public let limits: RuntimeLimits
  public private(set) var creditService: CreditService?
  private var objectRegistry: [String: MikroObject] = [:]
  private var agentRegistry: [String: Agent] = [:]
  private var agentMessengerRegistry: [String: MessengerObject] = [:]
  private var humanInboxRegistry: [String: [MessengerMessage]] = [:]
  private let actionCondition = NSCondition()
  private var actionSequence: UInt64 = 0
  private var nextActionTicket: UInt64 = 0
  private var servingActionTicket: UInt64 = 0
  private let runtimeIdentityProvider: () -> String
  private let runtimeDateProvider: () -> Date
  private var humanReportHandler: ((MikroObject, HumanObjectReportDraft) throws -> Void)?
  private var objectStateChangeHandler: ((MikroObject) throws -> Void)?
  private var externalEffectHandler: ((String, MikroObject, String, String, Date) throws -> Void)?
  private var nestedInvocationHandler:
    ((ObjectInvocationIdentity, MikroObject, MikroObject, String, String) throws -> Void)?
  private var inventoryRestockHandler:
    ((MikroObject, MerchantObject) throws -> InventoryRestockPlan?)?
  private var humanMessageHandler: ((Agent, MessengerMessage) throws -> Void)?
  private(set) var isReplayingWorldEvents = false
  private var activeCreditOperation: CreditOperationIdentity?

  public init(
    world: MikroObject? = nil,
    limits: RuntimeLimits = .defaults,
    runtimeIdentityProvider: @escaping () -> String = {
      UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    },
    runtimeDateProvider: @escaping () -> Date = Date.init
  ) throws {
    try limits.validate()
    self.limits = limits
    self.runtimeIdentityProvider = runtimeIdentityProvider
    self.runtimeDateProvider = runtimeDateProvider
    self.world = try world ?? createWorld()
    guard self.world.container != nil else {
      throw MikroKhorosError.placement("the world must have container capability")
    }
    guard self.world.parentSpace == nil else {
      throw MikroKhorosError.placement("the root world cannot be placed inside another object")
    }
    registerTree(self.world)
    // Credit authority is product-root state owned by the world runtime. A
    // standalone harness starts without an accounting service; callers inject
    // a pinned service through `setCreditService`.
    self.creditService = nil
  }

  public var agents: [Agent] { agentRegistry.values.sorted { $0.hash < $1.hash } }
  public var activeAgents: [Agent] { agents.filter(\.isInWorld) }
  public var objects: [MikroObject] { objectRegistry.values.sorted { $0.hash < $1.hash } }

  public func findAgent(_ hash: String) -> Agent? { agentRegistry[hash] }

  public func resolveAgent(_ query: String) throws -> Agent {
    try HumanSelectorResolver.resolve(
      query,
      among: agents,
      id: \.hash,
      name: { $0.name },
      kind: "agent in the selected world",
      listCommand: "khoros agent list"
    ).value
  }

  @discardableResult
  public func createAgent(
    name: String = "agent",
    maximumActionsPerResponse: Int = 8,
    hash: String? = nil,
    backpack: MikroObject? = nil,
    wallet: WalletObject? = nil,
    holdings: AgentHoldings? = nil
  ) throws -> Agent {
    guard !name.isEmpty, name.count <= 128, !name.contains(where: { $0.isNewline }) else {
      throw MikroKhorosError.command("agent name must be one line of at most 128 characters")
    }
    let resolvedBackpack = try backpack ?? createBackpack()
    let resolvedWallet: WalletObject
    if let wallet {
      resolvedWallet = wallet
      guard wallet.parentSpace == nil || wallet.parentSpace?.owner === resolvedBackpack else {
        throw MikroKhorosError.placement("the wallet must be unplaced or inside the agent backpack")
      }
      if wallet.parentSpace == nil {
        guard resolvedBackpack.container?.object(at: Coordinate(x: 4, y: 0)) == nil else {
          throw MikroKhorosError.placement("the backpack wallet coordinate is occupied")
        }
        try resolvedBackpack.container!.place(wallet, at: Coordinate(x: 4, y: 0))
      } else if wallet.coordinate != Coordinate(x: 4, y: 0) {
        throw MikroKhorosError.placement(
          "the genesis wallet must begin at backpack coordinate (4,0)")
      }
    } else if let existing = resolvedBackpack.container?.object(at: Coordinate(x: 4, y: 0))
      as? WalletObject
    {
      resolvedWallet = existing
    } else {
      resolvedWallet = try WalletObject()
      guard resolvedBackpack.container?.object(at: Coordinate(x: 4, y: 0)) == nil else {
        throw MikroKhorosError.placement("the backpack wallet coordinate is occupied")
      }
      try resolvedBackpack.container!.place(resolvedWallet, at: Coordinate(x: 4, y: 0))
    }
    let holdingRoots = holdings?.occupiedRoots ?? []
    let equipmentRoots = [resolvedBackpack] + holdingRoots
    var equipmentIDs: Set<String> = []
    for root in holdingRoots {
      guard root.parentSpace == nil else {
        throw MikroKhorosError.placement(
          "an initial holding object cannot also be placed in a space"
        )
      }
    }
    for root in equipmentRoots {
      try ensureTreeAvailable(root)
      for member in [root] + root.walkContents() {
        guard equipmentIDs.insert(member.hash).inserted,
          objectRegistry[member.hash] == nil
        else {
          throw MikroKhorosError.placement(
            "agent equipment contains an already registered or duplicate object"
          )
        }
      }
    }
    let agent = try Agent(
      name: name,
      worldSpace: world.container!,
      backpack: resolvedBackpack,
      wallet: resolvedWallet,
      holdings: holdings,
      maximumActionsPerResponse: maximumActionsPerResponse,
      hash: hash
    )
    guard agentRegistry[agent.hash] == nil else {
      throw MikroKhorosError.placement("agent identity is already registered")
    }
    agentRegistry[agent.hash] = agent
    for root in equipmentRoots { registerTree(root) }
    do {
      if let creditService {
        let commitment = try locationIndex().locationCommitment(for: resolvedWallet.hash)
        _ = try creditService.register(
          walletID: resolvedWallet.hash,
          agentID: agent.hash,
          backpackID: resolvedBackpack.hash,
          locationCommitment: commitment,
          actor: .system
        )
      }
    } catch {
      agentRegistry.removeValue(forKey: agent.hash)
      for root in equipmentRoots {
        for member in [root] + root.walkContents() {
          objectRegistry.removeValue(forKey: member.hash)
        }
      }
      throw error
    }
    if let messenger = resolvedBackpack.walkContents()
      .compactMap({ $0 as? MessengerObject })
      .filter({ $0.origin == .genesis })
      .sorted(by: { $0.hash < $1.hash })
      .first
    {
      agentMessengerRegistry[agent.hash] = messenger
    }
    return agent
  }

  public func setCreditService(
    _ service: CreditService?,
    registerMissingWallets: Bool = true
  ) throws {
    if let service, service.worldID != world.hash {
      throw MikroKhorosError.persistence("credit service belongs to a different world")
    }
    creditService = service
    guard let service, registerMissingWallets else { return }
    for agent in agents {
      if service.registration(for: agent.wallet.hash) == nil {
        let commitment = try locationIndex().locationCommitment(for: agent.wallet.hash)
        _ = try service.register(
          walletID: agent.wallet.hash,
          agentID: agent.hash,
          backpackID: agent.backpack.hash,
          locationCommitment: commitment,
          actor: .system
        )
      }
    }
  }

  /// Installs the world journal hook for dedicated human-recipient messages.
  /// Agents can write this inbox but never enumerate it through an object
  /// function; only the host-side management surface can read it.
  public func setHumanMessageHandler(
    _ handler: ((Agent, MessengerMessage) throws -> Void)?
  ) {
    humanMessageHandler = handler
  }

  public func humanInbox(for agent: Agent) throws -> [MessengerMessage] {
    guard agentRegistry[agent.hash] === agent else {
      throw MikroKhorosError.function("agent is not registered with this world")
    }
    return humanInboxRegistry[agent.hash] ?? []
  }

  @discardableResult
  public func acknowledgeHumanInbox(
    for agent: Agent,
    messageID: String
  ) throws -> Bool {
    guard agentRegistry[agent.hash] === agent else {
      throw MikroKhorosError.function("agent is not registered with this world")
    }
    guard var messages = humanInboxRegistry[agent.hash],
      let index = messages.firstIndex(where: { $0.id == messageID && !$0.isRead })
    else { return false }
    messages[index].isRead = true
    humanInboxRegistry[agent.hash] = messages
    return true
  }

  func replayHumanMessage(
    from agent: Agent,
    message: MessengerMessage
  ) throws {
    guard agentRegistry[agent.hash] === agent else {
      throw MikroKhorosError.persistence("human inbox event references an unknown agent")
    }
    var messages = humanInboxRegistry[agent.hash] ?? []
    if let existing = messages.first(where: { $0.id == message.id }) {
      guard existing == message else {
        throw MikroKhorosError.persistence(
          "human inbox message identity has conflicting replay payloads"
        )
      }
      return
    }
    guard messages.count < Self.maximumHumanInboxMessages else {
      throw MikroKhorosError.persistence("human inbox exceeds its bounded message limit")
    }
    messages.append(message)
    humanInboxRegistry[agent.hash] = messages
  }

  public func selectHolding(_ number: HoldingNumber, for agent: Agent) throws {
    try requireActive(agent)
    agent.holdings.select(number)
  }

  public func holdings(for agent: Agent) throws -> [MikroObject?] {
    guard agentRegistry[agent.hash] === agent else {
      throw MikroKhorosError.function("agent is not registered with this world")
    }
    return [.one, .two, .three, .four].map { agent.holdings[$0] }
  }

  public func currentOwner(of object: MikroObject) throws -> ObjectOwner? {
    try locationIndex().currentOwner(of: object)
  }

  public func requireWalletOwner(_ agent: Agent, _ wallet: WalletObject) throws {
    try requireWalletOwner(agent, walletID: wallet.hash)
  }

  public func requireWalletOwner(_ agent: Agent, walletID: String) throws {
    guard agentRegistry[agent.hash] === agent else {
      throw MikroKhorosError.runtime("wallet.owner_denied", "wallet access is not authorized")
    }
    guard let service = creditService,
      let registration = service.registration(for: walletID),
      registration.worldID == world.hash,
      let wallet = findObject(walletID) as? WalletObject,
      let owner = try? currentOwner(of: wallet),
      owner.agentID == agent.hash,
      service.custodyOwner(for: walletID) == agent.hash
    else {
      throw MikroKhorosError.runtime("wallet.owner_denied", "wallet access is not authorized")
    }
  }

  private func locationIndex() throws -> ObjectLocationIndex {
    let (maximumDepth, overflow) = limits.maximumObjectInvocationDepth
      .multipliedReportingOverflow(by: 64)
    guard !overflow else {
      throw MikroKhorosError.configuration(
        "the object invocation depth is too large for bounded ownership traversal"
      )
    }
    return try ObjectLocationIndex(
      world: world,
      registeredObjects: objects,
      agents: agents,
      holdingRoots: { agent in
        [.one, .two, .three, .four].map { agent.holdings[$0] }
      },
      attachmentRoots: { agent in
        [AttachmentRoot(kind: "backpack", object: agent.backpack)]
      },
      maxDepth: maximumDepth
    )
  }

  private func walletCustodySnapshot(for root: MikroObject) throws -> [WalletCustodyState] {
    guard let creditService else { return [] }
    let index = try locationIndex()
    let candidates = ([root] + root.walkContents()).compactMap { object -> WalletObject? in
      guard let wallet = object as? WalletObject,
        creditService.registration(for: wallet.hash) != nil
      else { return nil }
      return wallet
    }
    return try candidates.sorted { $0.hash < $1.hash }.map { wallet in
      guard let custodyCommitment = creditService.custodyCommitment(for: wallet.hash) else {
        throw MikroKhorosError.persistence("registered wallet has no custody commitment")
      }
      return WalletCustodyState(
        walletID: wallet.hash,
        ownerID: index.currentOwner(of: wallet)?.agentID,
        locationCommitment: try index.locationCommitment(for: wallet.hash),
        custodyCommitment: custodyCommitment
      )
    }
  }

  private func commitWalletCustody(_ before: [WalletCustodyState]) throws {
    guard !isReplayingWorldEvents, let creditService, !before.isEmpty else { return }
    let after = try locationIndex()
    let transitions = try before.compactMap { state -> WalletCustodyTransition? in
      guard let wallet = findObject(state.walletID) else {
        throw MikroKhorosError.persistence("registered wallet disappeared during custody move")
      }
      let newOwner = after.currentOwner(of: wallet)?.agentID
      guard newOwner != state.ownerID else { return nil }
      let newCommitment = try after.locationCommitment(for: state.walletID)
      return WalletCustodyTransition(
        walletID: state.walletID,
        oldOwner: state.ownerID,
        newOwner: newOwner,
        oldLocationCommitment: state.locationCommitment,
        newLocationCommitment: newCommitment,
        oldCustodyCommitment: state.custodyCommitment
      )
    }
    let operation = creditOperationIdentity()
    try creditService.updateCustodies(
      transitions,
      operationID: operation.operationID,
      actionIndex: operation.actionIndex,
      actor: operation.actor
    )
  }

  func requireAgentObjectAccess(_ object: MikroObject, for agent: Agent) throws {
    guard let owner = try currentOwner(of: object) else { return }
    guard owner.agentID == agent.hash else {
      // Deliberately do not disclose the owner's identity or whether the object
      // is held directly or nested in another private container.
      throw MikroKhorosError.runtime(
        "object.unavailable",
        "the requested object is unavailable"
      )
    }
  }

  func validateDirectInvocation(of object: MikroObject, for agent: Agent) throws {
    try requireActive(agent)
    guard objectRegistry[object.hash] === object else {
      throw MikroKhorosError.runtime("object.unavailable", "the requested object is unavailable")
    }
    try requireAgentObjectAccess(object, for: agent)
  }

  public func messenger(for agent: Agent) throws -> MessengerObject {
    guard agentRegistry[agent.hash] === agent else {
      throw MikroKhorosError.function("agent is not registered with this world")
    }
    guard let messenger = agentMessengerRegistry[agent.hash],
      findObject(messenger.hash) === messenger
    else {
      throw MikroKhorosError.function("agent has no registered genesis messager.object")
    }
    return messenger
  }

  public func setMaximumActionsPerResponse(_ value: Int, for agent: Agent) throws {
    guard agentRegistry[agent.hash] === agent else {
      throw MikroKhorosError.command("agent is not registered with this world")
    }
    try agent.setMaximumActionsPerResponse(value)
  }

  @discardableResult
  public func addAgent(
    _ agent: Agent,
    at requested: Coordinate = .origin,
    autoAdapt: Bool = false,
    eye: EyeObject? = nil
  ) throws -> AgentPlacement {
    guard agentRegistry[agent.hash] === agent else {
      throw MikroKhorosError.placement("agent is not registered with this world")
    }
    guard !agent.isInWorld else {
      throw MikroKhorosError.runtime(
        "agent.add.already_present",
        "agent is already present in this world"
      )
    }
    let resolvedEye: EyeObject?
    if agent.hasEnteredWorld {
      guard eye == nil else {
        throw MikroKhorosError.placement("a returning agent does not receive another eye")
      }
      resolvedEye = nil
    } else {
      resolvedEye = try eye ?? EyeObject()
      try ensureTreeAvailable(resolvedEye!)
    }
    // Agents are occupants, not material objects. They may enter, stand on,
    // and leave a coordinate containing a placed object; `autoAdapt` remains
    // in the journal for deterministic replay but no longer changes the
    // requested coordinate.
    let actual = requested
    agent.space = world.container!
    agent.coordinate = actual
    if let resolvedEye { try agent.holdings.putPrimary(resolvedEye) }
    agent.isInWorld = true
    agent.hasEnteredWorld = true
    if let resolvedEye { registerTree(resolvedEye) }
    if agent.aiProfile != nil { enqueueLatestUnreadFromCarriedSources(for: agent) }
    return AgentPlacement(requested: requested, actual: actual, adapted: requested != actual)
  }

  public func removeAgentFromWorld(_ agent: Agent) throws {
    try requireActive(agent)
    agent.isInWorld = false
    agent.backpackReturn = nil
  }

  public func attachProfile(_ profile: AIProfile, to agent: Agent) throws {
    guard agentRegistry[agent.hash] === agent else {
      throw MikroKhorosError.profile("agent is not registered with this world")
    }
    guard let definition = AIAdapterCatalog.definition(id: profile.adapterID) else {
      throw MikroKhorosError.profile("AI profile references an unknown adapter")
    }
    guard definition.transport == profile.transport else {
      throw MikroKhorosError.profile("AI profile transport does not match its adapter")
    }
    if definition.requiresRoleSeparatedBridge {
      guard profile.endpoint != nil, profile.transport == .roleSeparatedBridge else {
        throw MikroKhorosError.profile(
          "this coding-agent adapter requires a role-separated HTTP bridge endpoint"
        )
      }
    }
    agent.aiProfile = profile
    enqueueLatestUnreadFromCarriedSources(for: agent)
  }

  public func detachProfile(from agent: Agent) {
    agent.aiProfile = nil
  }

  public func performQueuedAction<T>(_ body: () throws -> T) rethrows -> (UInt64, T) {
    actionCondition.lock()
    let ticket = nextActionTicket
    nextActionTicket += 1
    while ticket != servingActionTicket { actionCondition.wait() }
    actionSequence += 1
    let sequence = actionSequence
    actionCondition.unlock()
    defer {
      actionCondition.lock()
      servingActionTicket += 1
      actionCondition.broadcast()
      actionCondition.unlock()
    }
    return (sequence, try body())
  }

  func withCreditOperation<T>(
    operationID: String,
    actionIndex: UInt64,
    actor: CreditActor = .agent,
    _ body: () throws -> T
  ) rethrows -> T {
    precondition(activeCreditOperation == nil, "credit operation contexts may not be nested")
    activeCreditOperation = CreditOperationIdentity(
      operationID: operationID,
      actionIndex: actionIndex,
      actor: actor
    )
    defer { activeCreditOperation = nil }
    return try body()
  }

  func creditOperationIdentity() -> CreditOperationIdentity {
    activeCreditOperation
      ?? CreditOperationIdentity(
        operationID: nextRuntimeIdentity(),
        actionIndex: 0,
        actor: .system
      )
  }

  var isAgentActionOperationActive: Bool {
    activeCreditOperation?.actor == .agent
  }

  func nextRuntimeIdentity() -> String { runtimeIdentityProvider() }

  func runtimeDate() -> Date { runtimeDateProvider() }

  public func setHumanReportHandler(
    _ handler: ((MikroObject, HumanObjectReportDraft) throws -> Void)?
  ) {
    humanReportHandler = handler
  }

  public func setObjectStateChangeHandler(
    _ handler: @escaping (MikroObject) throws -> Void
  ) {
    objectStateChangeHandler = handler
  }

  public func notifyObjectStateChanged(_ object: MikroObject) throws {
    guard objectRegistry[object.hash] === object else {
      throw MikroKhorosError.runtime(
        "object.identity_unavailable",
        "the changed object is not registered in this world"
      )
    }
    try objectStateChangeHandler?(object)
  }

  public func setExternalEffectHandler(
    _ handler: @escaping (String, MikroObject, String, String, Date) throws -> Void
  ) {
    externalEffectHandler = handler
  }

  func setNestedInvocationHandler(
    _ handler:
      @escaping (
        ObjectInvocationIdentity, MikroObject, MikroObject, String, String
      ) throws -> Void
  ) {
    nestedInvocationHandler = handler
  }

  func recordNestedInvocation(
    identity: ObjectInvocationIdentity,
    source: MikroObject,
    target: MikroObject,
    function: String,
    result: String
  ) throws {
    guard objectRegistry[source.hash] === source, objectRegistry[target.hash] === target else {
      throw MikroKhorosError.runtime(
        "object.identity_unavailable", "a nested invocation object is not registered")
    }
    try nestedInvocationHandler?(
      identity,
      source,
      target,
      function,
      String(result.prefix(limits.maximumActionCharacters))
    )
  }

  public func recordExternalEffect(
    from object: MikroObject,
    operation: String,
    result: String
  ) throws {
    guard objectRegistry[object.hash] === object else {
      throw MikroKhorosError.runtime(
        "object.identity_unavailable", "the external-effect object is not registered")
    }
    let id = nextRuntimeIdentity()
    let timestamp = runtimeDate()
    try externalEffectHandler?(id, object, operation, result, timestamp)
  }

  func setWorldReplayMode(_ enabled: Bool) {
    isReplayingWorldEvents = enabled
  }

  public func setInventoryRestockHandler(
    _ handler: ((MikroObject, MerchantObject) throws -> InventoryRestockPlan?)?
  ) {
    inventoryRestockHandler = handler
  }

  public func emitHumanReport(
    from object: MikroObject,
    type: String,
    title: String,
    body: String,
    payload: JSONValue = .null
  ) throws {
    guard objectRegistry[object.hash] === object else {
      throw MikroKhorosError.runtime(
        "object.report_identity_invalid",
        "only a registered concrete world object may emit a report"
      )
    }
    try humanReportHandler?(
      object,
      HumanObjectReportDraft(type: type, title: title, body: body, payload: payload)
    )
  }

  public func place(
    _ object: MikroObject,
    at coordinate: Coordinate = .origin,
    in space: Space? = nil
  ) throws {
    let destination = space ?? world.container!
    try requireRegisteredSpace(destination)
    try ensureTreeAvailable(object)
    if let blocker = materialBlocker(in: destination, at: coordinate, excluding: nil) {
      throw MikroKhorosError.runtime(
        "placement.occupied",
        "cannot place the object at an occupied coordinate",
        details: ["position": coordinate.description, "blocker": blocker],
        suggestions: ["choose another coordinate"]
      )
    }
    try destination.place(object, at: coordinate)
    registerTree(object)
    // A newly placed object has no prior custody state. Registered wallets,
    // however, can be temporarily unplaced during a host transfer; authenticate
    // that transition once the graph has a concrete location again.
    if let carrier = carrier(of: object), carrier.aiProfile != nil {
      enqueueLatestUnread(from: object, for: carrier)
    }
  }

  public func moveObject(
    _ object: MikroObject,
    to destination: Coordinate,
    in targetSpace: Space? = nil
  ) throws {
    try requireNoActiveAgentInside(object)
    let custodyBefore = try walletCustodySnapshot(for: object)
    let holdingCarrier = agents.first {
      $0.holdings.occupiedRoots.contains(where: { $0 === object })
    }
    let holdingSlot = holdingCarrier.flatMap { carrier in
      Self.holdingNumbers.first(where: { carrier.holdings[$0] === object })
    }
    guard holdingCarrier != nil || (object.parentSpace != nil && object.coordinate != nil) else {
      throw MikroKhorosError.placement("object is not placed in a space")
    }
    let sourceSpace = object.parentSpace
    let source = object.coordinate
    let previousCarrier = holdingCarrier ?? carrier(of: object)
    guard let target = targetSpace ?? sourceSpace else {
      throw MikroKhorosError.placement("a held object requires an explicit destination space")
    }
    try requireRegisteredSpace(target)
    if let blocker = materialBlocker(in: target, at: destination, excluding: holdingCarrier),
      !(target === sourceSpace && destination == source)
    {
      throw MikroKhorosError.runtime(
        "placement.occupied",
        "cannot move the object to an occupied coordinate",
        details: ["position": destination.description, "blocker": blocker],
        suggestions: ["choose another coordinate"]
      )
    }
    if let sourceSpace, let source, target === sourceSpace {
      try sourceSpace.move(from: source, to: destination)
    } else if let sourceSpace, let source {
      _ = try sourceSpace.remove(at: source)
      do { try target.place(object, at: destination) } catch {
        try? sourceSpace.place(object, at: source)
        throw error
      }
    } else {
      if let holdingCarrier, let holdingSlot { holdingCarrier.holdings[holdingSlot] = nil }
      do { try target.place(object, at: destination) } catch {
        if let holdingCarrier, let holdingSlot { holdingCarrier.holdings[holdingSlot] = object }
        throw error
      }
    }
    do {
      try commitWalletCustody(custodyBefore)
    } catch {
      // Do not leave a physical move published when its signed custody
      // transition cannot be authenticated (including verify-only worlds).
      if let sourceSpace, let source, target === sourceSpace {
        if destination != source { try? sourceSpace.move(from: destination, to: source) }
      } else if let sourceSpace, let source {
        _ = try? target.remove(at: destination)
        try? sourceSpace.place(object, at: source)
      } else {
        _ = try? target.remove(at: destination)
        if let holdingCarrier, let holdingSlot { holdingCarrier.holdings[holdingSlot] = object }
      }
      throw error
    }
    let newCarrier = carrier(of: object)
    if let newCarrier, previousCarrier !== newCarrier, newCarrier.aiProfile != nil {
      enqueueLatestUnread(from: object, for: newCarrier)
    }
  }

  public func removeObject(_ object: MikroObject) throws {
    guard object !== world else {
      throw MikroKhorosError.placement("the root world cannot be removed")
    }
    guard !agents.contains(where: { object === $0.backpack }) else {
      throw MikroKhorosError.placement("agent-attached objects cannot be removed")
    }
    guard
      !([object] + object.walkContents()).contains(where: { member in
        guard member is WalletObject else { return false }
        return agents.contains(where: { $0.wallet === member })
          || creditService?.registration(for: member.hash) != nil
      })
    else {
      throw MikroKhorosError.placement("wallet or a wallet-containing subtree cannot be removed")
    }
    for agent in activeAgents where object.container != nil && agent.space.isInside(object) {
      throw MikroKhorosError.placement("cannot remove a container while an agent is inside it")
    }
    for agent in agents {
      for slot in Self.holdingNumbers where agent.holdings[slot] === object {
        agent.holdings[slot] = nil
      }
    }
    if let parent = object.parentSpace, let coordinate = object.coordinate {
      _ = try parent.remove(at: coordinate)
    }
    for member in [object] + object.walkContents() {
      objectRegistry.removeValue(forKey: member.hash)
    }
  }

  public func findObject(_ hash: String) -> MikroObject? { objectRegistry[hash] }

  public func object(byHash hash: String) throws -> MikroObject {
    guard let object = objectRegistry[hash] else {
      throw MikroKhorosError.function("object hash does not exist in this world")
    }
    return object
  }

  public func resolveObject(_ query: String) throws -> MikroObject {
    try HumanSelectorResolver.resolve(
      query,
      among: objects,
      id: \.hash,
      name: { $0.name },
      kind: "object in the selected world",
      listCommand: "khoros world object list"
    ).value
  }

  public func isCarried(_ object: MikroObject, by agent: Agent) -> Bool {
    carrier(of: object) === agent
  }

  public func carrier(of object: MikroObject) -> Agent? {
    guard let index = try? locationIndex(),
      let owner = index.currentOwner(of: object)
    else { return nil }
    return agentRegistry[owner.agentID]
  }

  @discardableResult
  public func move(_ agent: Agent, direction: String, steps: Int = 1) throws -> Coordinate {
    try requireActive(agent)
    guard let delta = Directions.values[direction.lowercased()] else {
      throw MikroKhorosError.runtime(
        "move.direction_unknown",
        "unknown movement direction",
        suggestions: ["use north, northeast, east, southeast, south, southwest, west, or northwest"]
      )
    }
    guard steps > 0 else {
      throw MikroKhorosError.runtime(
        "move.step_invalid",
        "step count must be a positive integer",
        suggestions: ["use a positive step count"]
      )
    }
    let scaledDelta = try delta.scaledExactly(by: steps)
    agent.coordinate = try agent.coordinate.addingExactly(scaledDelta)
    return agent.coordinate
  }

  @discardableResult
  public func pickup(for agent: Agent) throws -> MikroObject {
    try requireActive(agent)
    guard agent.holdings[agent.primaryHoldingNumber] == nil else {
      throw MikroKhorosError.runtime(
        "pickup.holding_occupied",
        "cannot pick up; the primary holding already contains an object",
        details: ["held": agent.holdings[agent.primaryHoldingNumber]!.hash],
        suggestions: ["select an empty holding or drop the primary object"]
      )
    }
    guard let object = agent.space.object(at: agent.coordinate) else {
      throw MikroKhorosError.runtime(
        "pickup.empty",
        "there is no object at the current coordinate",
        suggestions: ["move onto an object before running `pickup`"]
      )
    }
    try requireAgentObjectAccess(object, for: agent)
    if let lock = object.lockInfo, !lock.permits(agentID: agent.hash) {
      var details = ["object": object.hash, "authority": lock.authority.description]
      if !lock.reason.isEmpty { details["reason"] = lock.reason }
      throw MikroKhorosError.runtime(
        "pickup.locked",
        "cannot pick up the object; its pickup lock does not permit this agent",
        details: details,
        suggestions: ["remove or satisfy the pickup lock, then run `pickup` again"]
      )
    }
    try requireNoActiveAgentInside(object)
    let custodyBefore = try walletCustodySnapshot(for: object)
    _ = try agent.space.remove(at: agent.coordinate)
    try agent.holdings.putPrimary(object)
    object.clearPickupClaimAfterSuccess(for: agent.hash)
    do {
      try commitWalletCustody(custodyBefore)
    } catch {
      _ = agent.holdings.removePrimary()
      try? agent.space.place(object, at: agent.coordinate)
      throw error
    }
    enqueueLatestUnread(from: object, for: agent)
    return object
  }

  @discardableResult
  public func drop(for agent: Agent, delta: Coordinate = .origin) throws -> MikroObject {
    try requireActive(agent)
    guard let object = agent.primaryHeldObject else {
      throw MikroKhorosError.runtime(
        "drop.primary_empty",
        "cannot drop; the primary holding is empty",
        suggestions: ["select a holding with an object before running `drop`"]
      )
    }
    guard (-1...1).contains(delta.x), (-1...1).contains(delta.y) else {
      throw MikroKhorosError.runtime(
        "drop.delta_invalid",
        "drop target must be the current cell or one of its eight neighbors",
        suggestions: ["use a direction or a delta between -1 and 1"]
      )
    }
    let destination = try agent.coordinate.addingExactly(delta)
    if let blocker = materialBlocker(in: agent.space, at: destination, excluding: agent) {
      throw MikroKhorosError.runtime(
        "drop.occupied",
        "cannot drop into material occupancy",
        details: ["position": destination.description, "blocker": blocker],
        suggestions: ["choose another drop direction"]
      )
    }
    let custodyBefore = try walletCustodySnapshot(for: object)
    _ = agent.holdings.removePrimary()
    do { try agent.space.place(object, at: destination) } catch {
      _ = try? agent.holdings.putPrimary(object)
      throw error
    }
    do {
      try commitWalletCustody(custodyBefore)
    } catch {
      _ = try? agent.space.remove(at: destination)
      _ = try? agent.holdings.putPrimary(object)
      throw error
    }
    return object
  }

  public func stowHeldObject(for agent: Agent) throws {
    guard let object = agent.primaryHeldObject else {
      throw MikroKhorosError.runtime("backpack.store.primary_empty", "the primary holding is empty")
    }
    let coordinate = nearestAvailableCoordinate(in: agent.backpack.container!, around: .origin)
    _ = agent.holdings.removePrimary()
    do { try agent.backpack.container!.place(object, at: coordinate) } catch {
      _ = try? agent.holdings.putPrimary(object)
      throw error
    }
  }

  @discardableResult
  public func enterContainer(for agent: Agent) throws -> MikroObject {
    try requireActive(agent)
    guard let object = agent.space.object(at: agent.coordinate) else {
      throw MikroKhorosError.runtime(
        "container.enter.missing",
        "there is no container at the current coordinate",
        suggestions: ["move onto a container before running `container in`"]
      )
    }
    try (object as? LiveWorldObject)?.prepareForInteraction(harness: self)
    try requireAgentObjectAccess(object, for: agent)
    guard let container = object.container else {
      throw MikroKhorosError.runtime(
        "container.enter.missing",
        "there is no container at the current coordinate",
        suggestions: ["move onto a container before running `container in`"]
      )
    }
    agent.space = container
    agent.coordinate = .origin
    return object
  }

  @discardableResult
  public func exitContainer(for agent: Agent) throws -> MikroObject {
    try requireActive(agent)
    let owner = agent.space.owner
    guard owner !== world else {
      throw MikroKhorosError.runtime("container.exit.root", "agent is already in the root world")
    }
    guard owner !== agent.backpack else {
      throw MikroKhorosError.runtime(
        "container.exit.backpack",
        "use `backpack close` to leave the backpack"
      )
    }
    guard let parent = owner.parentSpace, let coordinate = owner.coordinate else {
      throw MikroKhorosError.runtime(
        "container.exit.unplaced",
        "this container is no longer placed anywhere"
      )
    }
    agent.space = parent
    agent.coordinate = coordinate
    return owner
  }

  public func openBackpack(for agent: Agent) throws {
    try requireActive(agent)
    guard agent.backpackReturn == nil else {
      throw MikroKhorosError.runtime("backpack.already_open", "backpack is already open")
    }
    agent.backpackReturn = NavigationFrame(space: agent.space, coordinate: agent.coordinate)
    agent.space = agent.backpack.container!
    agent.coordinate = .origin
  }

  public func closeBackpack(for agent: Agent) throws {
    guard let returnPoint = agent.backpackReturn else {
      throw MikroKhorosError.runtime("backpack.not_open", "backpack is not open")
    }
    guard agent.space === agent.backpack.container else {
      throw MikroKhorosError.runtime(
        "backpack.nested_container",
        "exit the nested container before closing the backpack"
      )
    }
    agent.space = returnPoint.space
    agent.coordinate = returnPoint.coordinate
    agent.backpackReturn = nil
  }

  @discardableResult
  public func inspect(for agent: Agent, target: String = "here") throws -> MikroObject {
    try requireActive(agent)
    let object: MikroObject
    switch target {
    case "held":
      guard let held = agent.primaryHeldObject else {
        throw MikroKhorosError.runtime(
          "inspect.hand_empty",
          "there is no held object to inspect",
          suggestions: ["pick up an object before running `inspect held`"]
        )
      }
      object = held
    case "here":
      guard let current = agent.space.object(at: agent.coordinate) else {
        throw MikroKhorosError.runtime(
          "inspect.empty",
          "there is no object at the current coordinate",
          suggestions: ["move onto an object before running `inspect here`"]
        )
      }
      object = current
    default:
      throw MikroKhorosError.command("inspect accepts only 'here' or 'held'")
    }
    try (object as? LiveWorldObject)?.prepareForInteraction(harness: self)
    try requireAgentObjectAccess(object, for: agent)
    agent.knownHashes.insert(object.hash)
    return object
  }

  public func invokeAccessible(
    for agent: Agent,
    function: String,
    arguments: [String]
  ) throws -> String {
    try requireActive(agent)
    let object: MikroObject
    if let held = agent.primaryHeldObject {
      object = held
    } else if let surface = agent.space.object(at: agent.coordinate),
      surface.invocationAccess == .surface
    {
      object = surface
    } else {
      throw MikroKhorosError.runtime(
        "object.unavailable",
        "no callable object is held or available on the current surface",
        suggestions: ["pick up an object, or stand on an object with surface invocation"]
      )
    }
    try requireAgentObjectAccess(object, for: agent)
    return try object.invoke(function, arguments: arguments, harness: self, agent: agent)
  }

  public func invokeHeld(
    for agent: Agent,
    function: String,
    arguments: [String]
  ) throws -> String {
    guard let object = agent.primaryHeldObject else {
      throw MikroKhorosError.runtime("object.primary_empty", "the primary holding is empty")
    }
    try requireAgentObjectAccess(object, for: agent)
    return try object.invoke(function, arguments: arguments, harness: self, agent: agent)
  }

  public func teleport(_ agent: Agent, to portal: PortalObject) throws {
    try validateTeleportDestination(portal, for: agent)
    let parent = portal.parentSpace!
    let coordinate = portal.coordinate!
    agent.space = parent
    agent.coordinate = coordinate
    agent.backpackReturn = nil
  }

  func validateTeleportDestination(_ portal: PortalObject, for agent: Agent) throws {
    try requireActive(agent)
    guard findObject(portal.hash) === portal else {
      throw MikroKhorosError.runtime("object.unavailable", "the requested object is unavailable")
    }
    try requireAgentObjectAccess(portal, for: agent)
    guard portal.parentSpace != nil, portal.coordinate != nil else {
      throw MikroKhorosError.function("the paired portal is not placed in a space")
    }
    guard try currentOwner(of: portal) == nil else {
      throw MikroKhorosError.runtime(
        "teleport.destination_carried",
        "the paired portal must be rooted in the ownerless world graph"
      )
    }
  }

  @discardableResult
  public func validateSummon(_ hash: String, for agent: Agent) throws -> MikroObject {
    try requireActive(agent)
    guard !hash.isEmpty, let object = findObject(hash), agent.knownHashes.contains(hash)
    else {
      throw MikroKhorosError.runtime("object.unavailable", "the requested object is unavailable")
    }
    try requireAgentObjectAccess(object, for: agent)
    guard object !== world,
      !agents.contains(where: { object === $0.backpack || object === $0.wallet }),
      !agents.contains(where: { $0.holdings.occupiedRoots.contains(where: { $0 === object }) })
    else {
      throw MikroKhorosError.function("this object cannot be summoned")
    }
    try requireNoActiveAgentInside(object)
    guard object.lockInfo == nil else {
      throw MikroKhorosError.runtime(
        "summon.locked",
        "the target object has a pickup lock",
        suggestions: ["remove or satisfy the target's pickup lock before summoning"]
      )
    }
    guard object.parentSpace != nil else {
      throw MikroKhorosError.function("object is not placed in a space")
    }
    if let blocker = materialBlocker(in: agent.space, at: agent.coordinate, excluding: agent),
      agent.space.object(at: agent.coordinate) !== object
    {
      throw MikroKhorosError.runtime(
        "summon.destination_occupied",
        "the current coordinate is occupied",
        details: ["blocker": blocker],
        suggestions: ["move to an empty coordinate and try again"]
      )
    }
    try requireSummonCustodySigningIfNeeded(object, destination: agent.space)
    return object
  }

  @discardableResult
  public func summon(_ hash: String, for agent: Agent) throws -> MikroObject {
    let object = try validateSummon(hash, for: agent)
    try moveObject(object, to: agent.coordinate, in: agent.space)
    return object
  }

  @discardableResult
  public func stowPrimaryAndSummon(_ hash: String, for agent: Agent) throws -> MikroObject {
    let target = try validateSummon(hash, for: agent)
    guard let tool = agent.primaryHeldObject else {
      throw MikroKhorosError.runtime("backpack.store.primary_empty", "the primary holding is empty")
    }
    let slot = agent.primaryHoldingNumber
    let coordinate = nearestAvailableCoordinate(in: agent.backpack.container!, around: .origin)
    _ = agent.holdings.removePrimary()
    do {
      try agent.backpack.container!.place(tool, at: coordinate)
    } catch {
      agent.holdings[slot] = tool
      throw error
    }
    do {
      try moveObject(target, to: agent.coordinate, in: agent.space)
      return target
    } catch {
      let originalError = error
      do {
        let restored = try agent.backpack.container!.remove(at: coordinate)
        guard restored === tool, agent.holdings[slot] == nil else {
          throw MikroKhorosError.persistence("summoner rollback identity mismatch")
        }
        agent.holdings[slot] = tool
      } catch {
        throw MikroKhorosError.persistence("summoner rollback failed")
      }
      throw originalError
    }
  }

  public func purchase(
    itemSelector: String,
    walletID: String,
    from merchant: MerchantObject,
    for agent: Agent
  ) throws -> PurchaseResult {
    try requireActive(agent)
    try requireWalletOwner(agent, walletID: walletID)
    guard let creditService else {
      throw MikroKhorosError.runtime("wallet.unavailable", "the wallet service is unavailable")
    }
    let operation = creditOperationIdentity()
    let replayRecord = creditService.chain.last(where: {
      $0.unsigned.operationID == operation.operationID
        && $0.unsigned.actionIndex == operation.actionIndex
    })
    if let replayRecord, replayRecord.unsigned.kind != .purchase {
      throw MikroKhorosError.persistence(
        "purchase operation identity conflicts with a non-purchase credit record"
      )
    }
    let candidates: [String]
    if let replayRecord {
      guard replayRecord.unsigned.causalItemIDs.count == 1,
        let replayItemID = replayRecord.unsigned.causalItemIDs.first,
        replayItemID == itemSelector || replayItemID.hasPrefix(itemSelector)
      else {
        throw MikroKhorosError.persistence(
          "purchase replay selector conflicts with its signed item identity"
        )
      }
      candidates = [replayItemID]
    } else {
      candidates = merchant.prices.keys.filter {
        $0 == itemSelector || $0.hasPrefix(itemSelector)
      }
    }
    guard !candidates.isEmpty else {
      throw MikroKhorosError.runtime(
        "purchase.item_unknown",
        "item hash is not sold by this merchant",
        suggestions: ["run the merchant's `catalog` function and use an available exact id"]
      )
    }
    guard candidates.count == 1, let itemHash = candidates.first else {
      throw MikroKhorosError.runtime(
        "purchase.item_ambiguous",
        "catalog hash prefix is ambiguous",
        suggestions: ["use the complete item id from the catalog"]
      )
    }
    let item = try object(byHash: itemHash)
    let shop = try object(byHash: merchant.shopHash)
    guard item.parentSpace?.owner === shop else {
      throw MikroKhorosError.runtime(
        "purchase.item_moved", "the item is no longer inside this shop")
    }
    let purchaseClaim = ObjectLock(
      mode: .allowOnly,
      authority: .system,
      owner: merchant.hash,
      reason: "purchased_claim",
      allowedAgentIDs: [agent.hash],
      clearsOnPickup: true
    )
    let inventoryAvailable =
      item.lockInfo
      == ObjectLock(
        authority: .system,
        owner: merchant.hash,
        reason: "shop_inventory"
      )
    guard inventoryAvailable || (replayRecord != nil && item.lockInfo == purchaseClaim) else {
      throw MikroKhorosError.runtime(
        "purchase.item_unavailable",
        "the item is already sold, reserved, or unavailable"
      )
    }
    let price = merchant.prices[itemHash]!
    let amount = try MerchantObject.creditAmount(for: price)
    if replayRecord == nil,
      !(try creditService.sufficientFunds(walletID: walletID, amount: amount))
    {
      throw MikroKhorosError.runtime(
        "purchase.insufficient_funds",
        "the wallet does not have enough credit",
        details: ["price": amount.decimalText],
        suggestions: ["choose another item or fund the wallet through human management"]
      )
    }

    let walletMode = try creditService.mode(for: walletID)
    var replacement: MikroObject?
    var replacementCoordinate: Coordinate?
    var replacementPrice = price
    var restockPlan: InventoryRestockPlan?
    if let replayRecord {
      guard replayRecord.unsigned.sourceWalletID == walletID,
        replayRecord.unsigned.sourceWalletOwner == agent.hash,
        replayRecord.unsigned.causalMerchantIDs == [merchant.hash],
        replayRecord.unsigned.causalFunctionIDs.contains("merchant.buy"),
        replayRecord.unsigned.causalFunctionIDs.count <= 2,
        replayRecord.unsigned.nominalPurchaseAmount?.minorUnits == amount.minorUnits,
        replayRecord.unsigned.appliedPurchaseAmount?.minorUnits
          == (walletMode == .unlimited ? 0 : amount.minorUnits)
      else {
        throw MikroKhorosError.persistence(
          "purchase replay conflicts with its signed payer, merchant, or amount"
        )
      }
      let replacementIDs = replayRecord.unsigned.causalObjectIDs.filter {
        $0 != item.hash && $0 != walletID
      }
      guard replacementIDs.count <= 1,
        Set(replayRecord.unsigned.causalObjectIDs)
          == Set([item.hash, walletID] + replacementIDs)
      else {
        throw MikroKhorosError.persistence(
          "purchase replay contains an invalid signed replacement identity"
        )
      }
      replacement = replacementIDs.first.flatMap { findObject($0) }
      if replacementIDs.first != nil, replacement == nil {
        throw MikroKhorosError.persistence(
          "purchase replay replacement is missing from the world graph"
        )
      }
    } else if item.lineage?.restockRuleID != nil {
      restockPlan = try inventoryRestockHandler?(item, merchant)
      replacement = restockPlan?.object
      replacementCoordinate = restockPlan?.coordinate
      replacementPrice = restockPlan?.price ?? price
    } else if merchant.autoRestock {
      guard inventoryRestockHandler == nil || activeCreditOperation?.actor != .agent else {
        throw MikroKhorosError.runtime(
          "purchase.restock_not_durable",
          "automatic restock requires an Inventory-backed restock rule in a persistent world",
          suggestions: ["configure an Inventory restock rule for this merchant"]
        )
      }
      let fresh = try item.freshCopy(hash: nextRuntimeIdentity())
      try fresh.lock(authority: .system, owner: merchant.hash, reason: "shop_inventory")
      replacement = fresh
      replacementCoordinate = nearestAvailableCoordinate(
        in: shop.container!, around: .origin, excluding: nil
      )
    }

    var causalFunctionIDs = ["merchant.buy"]
    if let replacement, let lineage = replacement.lineage,
      let restockRuleID = lineage.restockRuleID,
      let coordinate = replacementCoordinate ?? replacement.coordinate,
      let resolvedPrice = replayRecord == nil
        ? Optional(replacementPrice) : merchant.prices[replacement.hash]
    {
      let replacementAmount = try MerchantObject.creditAmount(for: resolvedPrice)
      let mutation = WorldPurchaseRestockMutation(
        objectID: replacement.hash,
        restockRuleID: restockRuleID,
        inventoryObjectID: lineage.inventoryObjectID,
        inventoryRevision: lineage.inventoryRevision,
        deploymentID: lineage.deploymentID,
        coordinate: coordinate,
        price: try CreditBalance(minorUnits: replacementAmount.minorUnits)
      )
      causalFunctionIDs.append(mutation.signedCausalFunctionID)
    }

    let previousLock = item.lockInfo
    let creditCheckpoint = creditService.snapshot()
    do {
      if item.lockInfo != purchaseClaim {
        try item.claimPickup(
          for: agent.hash,
          authority: .system,
          owner: merchant.hash,
          reason: "purchased_claim",
          clearsOnPickup: true
        )
      }
      let causalObjectIDs =
        replayRecord?.unsigned.causalObjectIDs
        ?? [item.hash, walletID] + (replacement.map { [$0.hash] } ?? [])
      _ = try creditService.deduct(
        walletID: walletID,
        amount: amount,
        actor: .agent,
        operationID: operation.operationID,
        actionIndex: operation.actionIndex,
        sourceOwner: agent.hash,
        sourceCustodyCommitment: creditService.custodyCommitment(for: walletID),
        kind: .purchase,
        nominalPurchaseAmount: try CreditBalance(minorUnits: amount.minorUnits),
        appliedPurchaseAmount: try CreditBalance(
          minorUnits: walletMode == .unlimited ? 0 : amount.minorUnits),
        causalObjectIDs: causalObjectIDs,
        causalFunctionIDs: causalFunctionIDs,
        causalMerchantIDs: [merchant.hash],
        causalItemIDs: [item.hash]
      )
      if let replacement, let replacementCoordinate {
        try place(replacement, at: replacementCoordinate, in: shop.container!)
        try merchant.addPrice(replacementPrice, for: replacement.hash)
      }
      restockPlan?.commit()
    } catch {
      let operationError = error
      item.restoreLock(previousLock)
      if let replacement {
        merchant.removePrice(for: replacement.hash)
        if replacement.parentSpace != nil {
          try? removeObject(replacement)
        }
      }
      do {
        try creditService.restore(creditCheckpoint)
      } catch {
        throw MikroKhorosError.persistence(
          "purchase rollback could not restore the signed credit checkpoint"
        )
      }
      throw operationError
    }
    guard
      let creditRecord = creditService.chain.last(where: {
        $0.unsigned.operationID == operation.operationID
          && $0.unsigned.actionIndex == operation.actionIndex
          && $0.unsigned.kind == .purchase
      })
    else {
      throw MikroKhorosError.persistence(
        "the committed purchase has no signed credit record"
      )
    }
    return PurchaseResult(
      item: item,
      price: price,
      restocked: replacement,
      creditRecord: creditRecord
    )
  }

  @discardableResult
  public func deliverMessage(
    to messenger: MessengerObject,
    body: String,
    id: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
    sender: String = "user",
    senderAgentID: String? = nil,
    threadID: String = "#1",
    priority: BroadcastPriority? = nil,
    timestamp: Date = Date()
  ) throws -> MessengerMessage {
    guard findObject(messenger.hash) === messenger else {
      throw MikroKhorosError.function("messenger is not registered in this world")
    }
    let message = try messenger.receive(
      body,
      id: id,
      sender: sender,
      senderAgentID: senderAgentID,
      threadID: threadID,
      priority: priority,
      timestamp: timestamp
    )
    if let carrier = carrier(of: messenger), carrier.aiProfile != nil {
      enqueueLatestUnread(from: messenger, for: carrier)
    }
    return message
  }

  @discardableResult
  public func deliverMessage(
    to agent: Agent,
    body: String,
    id: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
    sender: String = "user",
    threadID: String = "#1",
    priority: BroadcastPriority? = nil,
    timestamp: Date = Date()
  ) throws -> MessengerMessage {
    let messenger = try messenger(for: agent)
    return try deliverMessage(
      to: messenger,
      body: body,
      id: id,
      sender: sender,
      threadID: threadID,
      priority: priority,
      timestamp: timestamp
    )
  }

  @discardableResult
  public func sendMessage(
    from sender: Agent,
    using source: MessengerObject,
    to recipientQuery: String,
    threadID: String,
    body: String,
    priority: BroadcastPriority? = nil
  ) throws -> MessengerMessage {
    guard agentRegistry[sender.hash] === sender,
      findObject(source.hash) === source,
      (try? currentOwner(of: source))?.agentID == sender.hash
    else {
      throw MikroKhorosError.runtime(
        "object.unavailable", "the requested object is unavailable"
      )
    }
    let normalizedRecipient = recipientQuery.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if normalizedRecipient == "human" || normalizedRecipient == "@human" {
      try MessengerObject.validateEnvelope(body: body, sender: sender.name)
      let sourceTitle =
        source.threads.first(where: { $0.id == threadID })?.title
        ?? "Human funding requests"
      _ = try source.ensureThread(id: threadID, title: sourceTitle)
      let id = nextRuntimeIdentity()
      let timestamp = runtimeDate()
      let message = MessengerMessage(
        id: id,
        threadID: threadID,
        sender: sender.name,
        senderAgentID: sender.hash,
        body: body,
        priority: priority,
        timestamp: timestamp,
        isRead: false
      )
      var inbox = humanInboxRegistry[sender.hash] ?? []
      guard !inbox.contains(where: { $0.id == id }) else {
        throw MikroKhorosError.runtime("messenger.duplicate", "message identity already exists")
      }
      guard inbox.count < Self.maximumHumanInboxMessages else {
        throw MikroKhorosError.runtime(
          "messenger.inbox_full", "the human inbox cannot accept more messages"
        )
      }
      inbox.append(message)
      humanInboxRegistry[sender.hash] = inbox
      _ = try source.recordSent(
        threadID: threadID,
        body: body,
        priority: priority,
        agent: sender,
        id: id,
        timestamp: timestamp
      )
      try humanMessageHandler?(sender, message)
      return message
    }

    let recipient = try resolveAgent(recipientQuery)
    let destination = try messenger(for: recipient)
    try MessengerObject.validateEnvelope(body: body, sender: sender.name)

    let sourceTitle =
      source.threads.first(where: { $0.id == threadID })?.title
      ?? "Conversation with \(recipient.name)"
    let destinationTitle =
      destination.threads.first(where: { $0.id == threadID })?.title
      ?? "Conversation with \(sender.name)"
    _ = try source.ensureThread(id: threadID, title: sourceTitle)
    if destination !== source {
      _ = try destination.ensureThread(id: threadID, title: destinationTitle)
    }

    let id = nextRuntimeIdentity()
    let timestamp = runtimeDate()
    if destination === source {
      return try source.recordSent(
        threadID: threadID,
        body: body,
        priority: priority,
        agent: sender,
        id: id,
        timestamp: timestamp
      )
    }
    let received = try deliverMessage(
      to: destination,
      body: body,
      id: id,
      sender: sender.name,
      senderAgentID: sender.hash,
      threadID: threadID,
      priority: priority,
      timestamp: timestamp
    )
    _ = try source.recordSent(
      threadID: threadID,
      body: body,
      priority: priority,
      agent: sender,
      id: id,
      timestamp: timestamp
    )
    return received
  }

  public func drainBroadcasts(for agent: Agent) -> [AgentBroadcastEvent] {
    let events = agent.pendingBroadcasts
    agent.pendingBroadcasts.removeAll()
    return events
  }

  /// Acknowledges only the exact source events that were successfully handed
  /// to the model. Failed validation or transport leaves the agent queue
  /// untouched, so a later request can retry without losing notifications.
  public func acknowledgeBroadcasts(_ events: [AgentBroadcastEvent], for agent: Agent) {
    for event in events {
      guard let sourceObject = findObject(event.sourceID),
        let source = sourceObject as? BroadcastSource,
        source.unreadEvents(limit: Self.maximumBroadcastEnumeration).contains(where: {
          $0.id == event.id && $0.sourceType == event.sourceType
        }),
        isCarried(sourceObject, by: agent)
      else { continue }
      _ = source.acknowledge(eventID: event.id)
    }
  }

  public func selfState(_ agent: Agent) throws -> String {
    try requireActive(agent)
    try (agent.space.owner as? LiveWorldObject)?.prepareForInteraction(harness: self)
    var lines = [
      "agent:",
      "  id: \(yamlScalar(agent.hash, limit: 128))",
      "  name: \(yamlScalar(agent.name, limit: 128))",
      "  active: \(agent.isInWorld ? "true" : "false")",
      "position: \(yamlScalar(agentPath(agent), limit: 2_048))",
    ]
    lines.append("holdings:")
    for number in Self.holdingNumbers {
      lines.append("  - slot: \(number.rawValue)")
      lines.append("    primary: \(agent.primaryHoldingNumber == number ? "true" : "false")")
      if let held = agent.holdings[number] {
        lines.append(contentsOf: surfaceLines(held, indentation: "    "))
      } else {
        lines.append("    object: none")
      }
    }
    if let current = agent.space.object(at: agent.coordinate) {
      lines.append("standing_on:")
      lines.append(contentsOf: surfaceLines(current, indentation: "  "))
    } else {
      lines.append("standing_on: none")
    }
    if let creditService { try creditService.verify() }
    let ownedWallets: [WalletObject] =
      creditService?.registrations.compactMap {
        guard let wallet = findObject($0.walletID) as? WalletObject,
          (try? currentOwner(of: wallet))?.agentID == agent.hash,
          creditService?.custodyOwner(for: wallet.hash) == agent.hash
        else { return nil }
        return wallet
      } ?? []
    if let creditService, !ownedWallets.isEmpty {
      lines.append("wallets:")
      for wallet in ownedWallets.sorted(by: { $0.hash < $1.hash }) {
        lines.append("  - id: \(yamlScalar(wallet.hash, limit: 128))")
        if let balance = try? creditService.balance(for: wallet.hash) {
          lines.append("    finite_shadow_balance: \(yamlScalar(balance.decimalText))")
          lines.append("    debt: \(yamlScalar(AgentWalletProjection.debtText(for: balance)))")
        }
        if let mode = try? creditService.mode(for: wallet.hash) {
          lines.append("    mode: \(mode.rawValue)")
        }
      }
    } else {
      lines.append("wallets: []")
    }
    return lines.joined(separator: "\n")
  }

  public func renderEyeView(for agent: Agent) throws -> String {
    try (agent.space.owner as? LiveWorldObject)?.prepareForInteraction(harness: self)
    let minimum = agent.coordinate.offset(x: -EyeObject.radius, y: -EyeObject.radius)
    let maximum = agent.coordinate.offset(x: EyeObject.radius, y: EyeObject.radius)
    var lines = [
      "view:",
      "  center: \(yamlScalar(agent.coordinate.description))",
      "  size: \"5x5\"",
      "  x: \"\(minimum.x)..\(maximum.x)\"",
      "  y: \"\(minimum.y)..\(maximum.y)\"",
      "  cells:",
    ]
    var found = false
    for y in minimum.y...maximum.y {
      for x in minimum.x...maximum.x {
        let coordinate = Coordinate(x: x, y: y)
        let object = agent.space.object(at: coordinate)
        let visibleAgents = activeAgents.filter {
          $0 !== agent && $0.space === agent.space && $0.coordinate == coordinate
        }
        guard object != nil || !visibleAgents.isEmpty else { continue }
        found = true
        lines.append("    - at: \(yamlScalar(coordinate.description))")
        if let object {
          lines.append("      object:")
          lines.append(contentsOf: surfaceLines(object, indentation: "        "))
        } else {
          lines.append("      object: none")
        }
        if visibleAgents.isEmpty {
          lines.append("      agents: []")
        } else {
          lines.append("      agents:")
          for visible in visibleAgents.sorted(by: { $0.hash < $1.hash }) {
            lines.append("        - id: \(yamlScalar(visible.hash, limit: 128))")
            lines.append("          name: \(yamlScalar(visible.name, limit: 128))")
          }
        }
      }
    }
    if !found {
      lines.removeLast()
      lines.append("  cells: []")
    }
    return lines.joined(separator: "\n")
  }

  public func renderInspection(_ object: MikroObject) -> String {
    if object is WalletObject, (try? currentOwner(of: object)) == nil {
      return [
        "object:",
        "  id: \(yamlScalar(object.hash, limit: 128))",
        "  type: \(yamlScalar(object.typeName, limit: 128))",
        "  name: \(yamlScalar(object.name, limit: 128))",
      ].joined(separator: "\n")
    }
    let inspection = object.inspect()
    var lines = [
      "object:",
      "  id: \(yamlScalar(inspection.hash, limit: 128))",
      "  type: \(yamlScalar(inspection.typeName, limit: 128))",
      "  name: \(yamlScalar(inspection.name, limit: 128))",
      "  summary: \(yamlScalar(inspection.summary, limit: 512))",
      "  durability: \(durabilityDescription(inspection.durability, inspection.maximumDurability))",
      "  container: \(inspection.hasContainerCapability ? "true" : "false")",
      "  origin: \(inspection.origin.rawValue)",
      "  invocation: \(inspection.invocationAccess.rawValue)",
    ]
    if !inspection.publicData.isEmpty {
      lines.append("  public:")
      for key in inspection.publicData.keys.sorted() {
        lines.append(
          "    \(safeYAMLKey(key)): \(yamlScalar(inspection.publicData[key]!.description))"
        )
      }
    } else {
      lines.append("  public: {}")
    }
    if let lock = inspection.lock {
      lines.append("  pickup_lock:")
      lines.append("    mode: \(lock.mode.rawValue)")
      lines.append("    authority: \(lock.authority)")
      lines.append("    reason: \(yamlScalar(lock.reason, limit: 128))")
    } else {
      lines.append("  pickup_lock: none")
    }
    if inspection.functions.isEmpty {
      lines.append("  functions: []")
    } else {
      lines.append("  functions:")
      for function in inspection.functions {
        lines.append("    - signature: \(yamlScalar(function.signature, limit: 512))")
        lines.append("      summary: \(yamlScalar(function.summary, limit: 512))")
      }
    }
    return lines.joined(separator: "\n")
  }

  public func agentPath(_ agent: Agent) -> String {
    "\(agent.coordinate)@\(spacePath(agent.space))"
  }

  public func spacePath(_ space: Space) -> String {
    guard space.owner !== world else { return "world" }
    var segments: [(coordinate: Coordinate, object: MikroObject)] = []
    var current: Space? = space
    while let value = current, let coordinate = value.owner.coordinate,
      let parent = value.owner.parentSpace
    {
      segments.append((coordinate, value.owner))
      current = parent
    }
    let root = current?.owner ?? space.owner
    let base: String
    if root === world {
      base = "world"
    } else if agents.contains(where: { $0.backpack === root }) {
      base = "backpack[\(quotedPathName(root.name))#\(root.hash)]"
    } else {
      base = "detached[\(quotedPathName(root.name))#\(root.hash)]"
    }
    let suffix = segments.reversed().map {
      "\($0.coordinate)[\(quotedPathName($0.object.name))#\($0.object.hash)]"
    }.joined(separator: "/")
    return suffix.isEmpty ? base : "\(base)/\(suffix)"
  }

  public func basicLine(_ object: MikroObject) -> String {
    "\(object.name) [\(object.typeName)] #\(object.hash)"
  }

  public func nearestAvailableCoordinate(
    in space: Space,
    around origin: Coordinate,
    excluding agent: Agent? = nil
  ) -> Coordinate {
    if materialBlocker(in: space, at: origin, excluding: agent) == nil { return origin }
    var distance = 1
    while true {
      for offset in diamondOffsets(distance: distance) {
        let candidate = origin + offset
        if materialBlocker(in: space, at: candidate, excluding: agent) == nil {
          return candidate
        }
      }
      distance += 1
    }
  }

  private func requireActive(_ agent: Agent) throws {
    guard agentRegistry[agent.hash] === agent, agent.isInWorld else {
      throw MikroKhorosError.runtime("agent.not_in_world", "agent is not present in this world")
    }
  }

  private static let holdingNumbers: [HoldingNumber] = [.one, .two, .three, .four]
  private static let maximumBroadcastEnumeration = 64
  private static let maximumBroadcastEncodedBytes = 65_536
  private static let maximumHumanInboxMessages = 1_024

  private func materialBlocker(
    in space: Space,
    at coordinate: Coordinate,
    excluding excludedAgent: Agent?
  ) -> String? {
    if let object = space.object(at: coordinate) {
      return "object #\(object.hash)"
    }
    return nil
  }

  private func requireNoActiveAgentInside(_ object: MikroObject) throws {
    guard
      object.container == nil
        || !activeAgents.contains(where: { $0.space.isInside(object) })
    else {
      throw MikroKhorosError.runtime(
        "container.occupied_by_agent",
        "cannot relocate a container while an agent is inside it"
      )
    }
  }

  private func requireSummonCustodySigningIfNeeded(
    _ object: MikroObject,
    destination: Space
  ) throws {
    guard let creditService else { return }
    let index = try locationIndex()
    let destinationOwner = index.currentOwner(of: destination.owner)?.agentID
    let ownerChanges = ([object] + object.walkContents()).contains { member in
      member is WalletObject
        && creditService.registration(for: member.hash) != nil
        && index.currentOwner(of: member)?.agentID != destinationOwner
    }
    guard !ownerChanges || creditService.canSignMutations else {
      throw MikroKhorosError.runtime(
        "wallet.credential_unavailable",
        "the treasury credential is unavailable; verify-only mode cannot change wallet custody"
      )
    }
  }

  private func requireRegisteredSpace(_ space: Space) throws {
    guard objectRegistry[space.owner.hash] === space.owner,
      space.owner.container === space
    else {
      throw MikroKhorosError.placement(
        "the destination space is not registered in this world"
      )
    }
  }

  private func diamondOffsets(distance: Int) -> [Coordinate] {
    guard distance > 0 else { return [.origin] }
    var result: [Coordinate] = []
    for index in 0..<distance { result.append(Coordinate(x: index, y: -distance + index)) }
    for index in 0..<distance { result.append(Coordinate(x: distance - index, y: index)) }
    for index in 0..<distance { result.append(Coordinate(x: -index, y: distance - index)) }
    for index in 0..<distance { result.append(Coordinate(x: -distance + index, y: -index)) }
    return result
  }

  private func carriedObjects(for agent: Agent) -> [MikroObject] {
    var result: [MikroObject] = []
    var seen: Set<String> = []
    for root in agent.holdings.occupiedRoots + [agent.backpack] {
      for object in [root] + root.walkContents() where seen.insert(object.hash).inserted {
        result.append(object)
      }
    }
    return result
  }

  private func enqueueLatestUnreadFromCarriedSources(for agent: Agent) {
    guard agent.isInWorld, agent.aiProfile != nil else { return }
    var proposed = agent.pendingBroadcasts
    for object in carriedObjects(for: agent).sorted(by: { $0.hash < $1.hash }) {
      guard let source = object as? BroadcastSource else { continue }
      let events = source.unreadEvents(limit: Self.maximumBroadcastEnumeration + 1)
      guard events.count <= Self.maximumBroadcastEnumeration else { return }
      for event in events
      where !proposed.contains(where: {
        $0.sourceID == event.sourceID && $0.id == event.id
      }) {
        proposed.append(event)
      }
      guard broadcastQueueFits(proposed) else { return }
    }
    agent.pendingBroadcasts = proposed
  }

  private func enqueueLatestUnread(from object: MikroObject, for agent: Agent) {
    guard agent.isInWorld, agent.aiProfile != nil,
      isCarried(object, by: agent),
      let source = object as? BroadcastSource
    else { return }
    let events = source.unreadEvents(limit: Self.maximumBroadcastEnumeration + 1)
    guard events.count <= Self.maximumBroadcastEnumeration else { return }
    var proposed = agent.pendingBroadcasts
    for event in events
    where !proposed.contains(where: {
      $0.sourceID == event.sourceID && $0.id == event.id
    }) {
      proposed.append(event)
    }
    guard broadcastQueueFits(proposed) else { return }
    agent.pendingBroadcasts = proposed
  }

  private func broadcastQueueFits(_ events: [AgentBroadcastEvent]) -> Bool {
    guard events.count <= Self.maximumBroadcastEnumeration else { return false }
    var bytes = 0
    for event in events {
      let eventBytes =
        event.id.utf8.count + event.sourceID.utf8.count
        + event.sourceType.utf8.count + event.title.utf8.count + event.body.utf8.count
        + (event.priority?.utf8.count ?? 0) + 64
      let (next, overflow) = bytes.addingReportingOverflow(eventBytes)
      guard !overflow, next <= Self.maximumBroadcastEncodedBytes else { return false }
      bytes = next
    }
    return true
  }

  private func surfaceLines(_ object: MikroObject, indentation: String) -> [String] {
    let condition: String
    if let durability = object.durability {
      condition = durability == 0 ? "spent" : "usable"
    } else {
      condition = "usable"
    }
    return [
      "\(indentation)id: \(yamlScalar(object.hash, limit: 128))",
      "\(indentation)type: \(yamlScalar(object.typeName, limit: 128))",
      "\(indentation)name: \(yamlScalar(object.name, limit: 128))",
      "\(indentation)summary: \(yamlScalar(object.summary, limit: 512))",
      "\(indentation)condition: \(condition)",
      "\(indentation)durability: \(durabilityDescription(object.durability, object.maximumDurability))",
      "\(indentation)container: \(object.container == nil ? "false" : "true")",
      "\(indentation)origin: \(object.origin.rawValue)",
    ]
  }

  private func durabilityDescription(_ current: Int?, _ maximum: Int?) -> String {
    guard let current, let maximum else { return "unlimited" }
    return "\(current)/\(maximum)"
  }

  private func quotedPathName(_ name: String) -> String {
    yamlScalar(name, limit: 128)
  }

  private func safeYAMLKey(_ value: String) -> String {
    yamlScalar(value, limit: 128)
  }

  private func yamlScalar(_ value: String, limit: Int? = nil) -> String {
    PromptSafety.yamlScalar(
      value,
      limit: min(limit ?? limits.maximumModelFieldCharacters, limits.maximumModelFieldCharacters)
    )
  }

  private func ensureTreeAvailable(_ object: MikroObject) throws {
    var seen: Set<String> = []
    for member in [object] + object.walkContents() {
      guard !seen.contains(member.hash) else {
        throw MikroKhorosError.placement("duplicate object identity inside object tree")
      }
      seen.insert(member.hash)
      guard objectRegistry[member.hash] == nil else {
        throw MikroKhorosError.placement("object identity is already registered")
      }
    }
  }

  private func registerTree(_ object: MikroObject) {
    for member in [object] + object.walkContents() { objectRegistry[member.hash] = member }
  }
}
