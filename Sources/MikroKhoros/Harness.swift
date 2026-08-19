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
}

public final class Harness {
  public let world: MikroObject
  public let limits: RuntimeLimits
  private var objectRegistry: [String: MikroObject] = [:]
  private var agentRegistry: [String: Agent] = [:]
  private var agentMessengerRegistry: [String: MessengerObject] = [:]
  private let actionCondition = NSCondition()
  private var actionSequence: UInt64 = 0
  private var nextActionTicket: UInt64 = 0
  private var servingActionTicket: UInt64 = 0
  private let runtimeIdentityProvider: () -> String
  private let runtimeDateProvider: () -> Date

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
  }

  public var agents: [Agent] { agentRegistry.values.sorted { $0.hash < $1.hash } }
  public var activeAgents: [Agent] { agents.filter(\.isInWorld) }
  public var objects: [MikroObject] { objectRegistry.values.sorted { $0.hash < $1.hash } }

  public func findAgent(_ hash: String) -> Agent? { agentRegistry[hash] }

  public func resolveAgent(_ query: String) throws -> Agent {
    if let exact = agentRegistry[query] { return exact }
    let matches = agentRegistry.filter { $0.key.hasPrefix(query) }.map(\.value)
    guard !matches.isEmpty else {
      throw MikroKhorosError.command("agent id does not exist in this world")
    }
    guard matches.count == 1, let match = matches.first else {
      throw MikroKhorosError.command("agent id prefix is ambiguous")
    }
    return match
  }

  @discardableResult
  public func createAgent(
    name: String = "agent",
    coinBalance: Decimal? = 0,
    maximumActionsPerResponse: Int = 8,
    hash: String? = nil,
    backpack: MikroObject? = nil,
    coin: CoinObject? = nil
  ) throws -> Agent {
    guard !name.isEmpty, name.count <= 128, !name.contains(where: { $0.isNewline }) else {
      throw MikroKhorosError.command("agent name must be one line of at most 128 characters")
    }
    let resolvedBackpack = try backpack ?? createBackpack()
    let resolvedCoin = try coin ?? CoinObject(balance: coinBalance)
    try ensureTreeAvailable(resolvedBackpack)
    try ensureTreeAvailable(resolvedCoin)
    let agent = try Agent(
      name: name,
      worldSpace: world.container!,
      backpack: resolvedBackpack,
      coin: resolvedCoin,
      maximumActionsPerResponse: maximumActionsPerResponse,
      hash: hash
    )
    guard agentRegistry[agent.hash] == nil else {
      throw MikroKhorosError.placement("agent identity is already registered")
    }
    registerTree(resolvedBackpack)
    registerTree(resolvedCoin)
    agentRegistry[agent.hash] = agent
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
      guard agent.hand == nil else {
        throw MikroKhorosError.placement("a new agent must have an empty hand before placement")
      }
      resolvedEye = try eye ?? EyeObject()
      try ensureTreeAvailable(resolvedEye!)
    }
    let willBeLoaded = resolvedEye != nil || agent.hand != nil
    let actual: Coordinate
    if !willBeLoaded
      || materialBlocker(in: world.container!, at: requested, excluding: agent) == nil
    {
      actual = requested
    } else if autoAdapt {
      actual = nearestAvailableCoordinate(
        in: world.container!, around: requested, excluding: agent
      )
    } else {
      throw MikroKhorosError.runtime(
        "agent.add.position_occupied",
        "cannot add the loaded agent at the requested coordinate",
        details: ["position": "\(requested)@world"],
        suggestions: ["choose another coordinate or enable auto-adapt placement"]
      )
    }
    agent.space = world.container!
    agent.coordinate = actual
    if let resolvedEye { agent.hand = resolvedEye }
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

  func nextRuntimeIdentity() -> String { runtimeIdentityProvider() }

  func runtimeDate() -> Date { runtimeDateProvider() }

  public func place(
    _ object: MikroObject,
    at coordinate: Coordinate = .origin,
    in space: Space? = nil
  ) throws {
    let destination = space ?? world.container!
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
    if let carrier = carrier(of: object), carrier.aiProfile != nil {
      enqueueLatestUnread(from: object, for: carrier)
    }
  }

  public func moveObject(
    _ object: MikroObject,
    to destination: Coordinate,
    in targetSpace: Space? = nil
  ) throws {
    guard let sourceSpace = object.parentSpace, let source = object.coordinate else {
      throw MikroKhorosError.placement("object is not placed in a space")
    }
    let previousCarrier = carrier(of: object)
    let target = targetSpace ?? sourceSpace
    if let blocker = materialBlocker(in: target, at: destination, excluding: nil),
      !(target === sourceSpace && destination == source)
    {
      throw MikroKhorosError.runtime(
        "placement.occupied",
        "cannot move the object to an occupied coordinate",
        details: ["position": destination.description, "blocker": blocker],
        suggestions: ["choose another coordinate"]
      )
    }
    if target === sourceSpace {
      try sourceSpace.move(from: source, to: destination)
    } else {
      _ = try sourceSpace.remove(at: source)
      do { try target.place(object, at: destination) } catch {
        try? sourceSpace.place(object, at: source)
        throw error
      }
    }
    let newCarrier = carrier(of: object)
    if previousCarrier == nil, let newCarrier, newCarrier.aiProfile != nil {
      enqueueLatestUnread(from: object, for: newCarrier)
    }
  }

  public func removeObject(_ object: MikroObject) throws {
    guard object !== world else {
      throw MikroKhorosError.placement("the root world cannot be removed")
    }
    guard !agents.contains(where: { object === $0.backpack || object === $0.coin }) else {
      throw MikroKhorosError.placement("agent-attached objects cannot be removed")
    }
    for agent in activeAgents where object.container != nil && agent.space.isInside(object) {
      throw MikroKhorosError.placement("cannot remove a container while an agent is inside it")
    }
    for agent in agents where agent.hand === object { agent.hand = nil }
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
    if let exact = objectRegistry[query] { return exact }
    let matches = objectRegistry.filter { $0.key.hasPrefix(query) }.map(\.value)
    guard !matches.isEmpty else {
      throw MikroKhorosError.function("object hash does not exist in this world")
    }
    guard matches.count == 1, let match = matches.first else {
      throw MikroKhorosError.function("object hash prefix is ambiguous")
    }
    return match
  }

  public func isCarried(_ object: MikroObject, by agent: Agent) -> Bool {
    carrier(of: object) === agent
  }

  public func carrier(of object: MikroObject) -> Agent? {
    if let holder = agents.first(where: { $0.hand === object }) { return holder }
    var current = object.parentSpace
    while let space = current {
      if let owner = agents.first(where: { $0.backpack === space.owner }) { return owner }
      current = space.owner.parentSpace
    }
    return nil
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
    if agent.hand != nil {
      for step in 1...steps {
        let candidate = agent.coordinate + delta.scaled(by: step)
        if let blocker = materialBlocker(in: agent.space, at: candidate, excluding: agent) {
          throw MikroKhorosError.runtime(
            "move.blocked",
            "a held object cannot move through material occupancy",
            details: ["position": candidate.description, "blocker": blocker],
            suggestions: [
              "try another direction, a shorter step count, or store/drop the held object"
            ]
          )
        }
      }
    }
    agent.coordinate = agent.coordinate + delta.scaled(by: steps)
    return agent.coordinate
  }

  @discardableResult
  public func pickup(for agent: Agent) throws -> MikroObject {
    try requireActive(agent)
    guard agent.hand == nil else {
      throw MikroKhorosError.runtime(
        "pickup.hand_occupied",
        "cannot pick up; the hand already holds an object",
        details: ["held": agent.hand!.hash],
        suggestions: ["run `drop`, then run `pickup`"]
      )
    }
    guard let object = agent.space.object(at: agent.coordinate) else {
      throw MikroKhorosError.runtime(
        "pickup.empty",
        "there is no object at the current coordinate",
        suggestions: ["move onto an object before running `pickup`"]
      )
    }
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
    _ = try agent.space.remove(at: agent.coordinate)
    agent.hand = object
    object.clearPickupClaimAfterSuccess(for: agent.hash)
    enqueueLatestUnread(from: object, for: agent)
    return object
  }

  @discardableResult
  public func drop(for agent: Agent, delta: Coordinate = .origin) throws -> MikroObject {
    try requireActive(agent)
    guard let object = agent.hand else {
      throw MikroKhorosError.runtime(
        "drop.hand_empty",
        "cannot drop; the hand is empty",
        suggestions: ["pick up an object before running `drop`"]
      )
    }
    guard abs(delta.x) <= 1, abs(delta.y) <= 1 else {
      throw MikroKhorosError.runtime(
        "drop.delta_invalid",
        "drop target must be the current cell or one of its eight neighbors",
        suggestions: ["use a direction or a delta between -1 and 1"]
      )
    }
    let destination = agent.coordinate + delta
    if let blocker = materialBlocker(in: agent.space, at: destination, excluding: agent) {
      throw MikroKhorosError.runtime(
        "drop.occupied",
        "cannot drop into material occupancy",
        details: ["position": destination.description, "blocker": blocker],
        suggestions: ["choose another drop direction"]
      )
    }
    agent.hand = nil
    do { try agent.space.place(object, at: destination) } catch {
      agent.hand = object
      throw error
    }
    return object
  }

  public func stowHeldObject(for agent: Agent) throws {
    guard let object = agent.hand else {
      throw MikroKhorosError.runtime("backpack.store.hand_empty", "the hand is empty")
    }
    let coordinate = nearestAvailableCoordinate(in: agent.backpack.container!, around: .origin)
    agent.hand = nil
    do { try agent.backpack.container!.place(object, at: coordinate) } catch {
      agent.hand = object
      throw error
    }
  }

  @discardableResult
  public func enterContainer(for agent: Agent) throws -> MikroObject {
    try requireActive(agent)
    guard agent.hand == nil else {
      throw MikroKhorosError.runtime(
        "container.enter.hand_occupied",
        "a loaded agent cannot stand on and enter a container",
        suggestions: ["store or drop the held object, then run `container in`"]
      )
    }
    guard let object = agent.space.object(at: agent.coordinate), let container = object.container
    else {
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
    guard agent.hand == nil else {
      throw MikroKhorosError.runtime(
        "container.exit.hand_occupied",
        "a loaded agent cannot overlap the container object in its parent space",
        suggestions: ["store or drop the held object, then run `container out`"]
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
    if agent.hand != nil,
      let blocker = materialBlocker(in: agent.backpack.container!, at: .origin, excluding: agent)
    {
      throw MikroKhorosError.runtime(
        "backpack.entry_blocked",
        "the backpack origin is occupied for a loaded entry",
        details: ["blocker": blocker],
        suggestions: ["free the backpack origin or drop the held object before opening"]
      )
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
    if agent.hand != nil,
      let blocker = materialBlocker(
        in: returnPoint.space, at: returnPoint.coordinate, excluding: agent
      )
    {
      throw MikroKhorosError.runtime(
        "backpack.return_blocked",
        "cannot return a loaded agent to material occupancy",
        details: ["blocker": blocker],
        suggestions: ["store or drop the held object inside the backpack, then close it"]
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
      guard let held = agent.hand else {
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
    if let held = agent.hand {
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
    return try object.invoke(function, arguments: arguments, harness: self, agent: agent)
  }

  public func invokeHeld(
    for agent: Agent,
    function: String,
    arguments: [String]
  ) throws -> String {
    guard let object = agent.hand else {
      throw MikroKhorosError.runtime("object.hand_empty", "the hand is empty")
    }
    return try object.invoke(function, arguments: arguments, harness: self, agent: agent)
  }

  public func teleport(_ agent: Agent, to portal: PortalObject) throws {
    guard agent.hand == nil else {
      throw MikroKhorosError.function("teleport arrival requires the hand to be empty")
    }
    guard let parent = portal.parentSpace, let coordinate = portal.coordinate else {
      throw MikroKhorosError.function("the paired portal is not placed in a space")
    }
    agent.space = parent
    agent.coordinate = coordinate
    agent.backpackReturn = nil
  }

  @discardableResult
  public func summon(_ hash: String, for agent: Agent) throws -> MikroObject {
    guard agent.hand == nil else {
      throw MikroKhorosError.function("summoning to the current coordinate requires an empty hand")
    }
    let object = try resolveObject(hash)
    guard agent.knownHashes.contains(object.hash) else {
      throw MikroKhorosError.function(
        "summon requires a previously inspected exact object instance")
    }
    guard object !== world,
      !agents.contains(where: { object === $0.backpack || object === $0.coin }),
      !agents.contains(where: { $0.hand === object })
    else {
      throw MikroKhorosError.function("this object cannot be summoned")
    }
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
    try moveObject(object, to: agent.coordinate, in: agent.space)
    return object
  }

  public func purchase(
    _ hash: String,
    from merchant: MerchantObject,
    for agent: Agent
  ) throws -> PurchaseResult {
    let candidates = merchant.prices.keys.filter { $0 == hash || $0.hasPrefix(hash) }
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
    guard let inventoryLock = item.lockInfo,
      inventoryLock.mode == .denyAll,
      inventoryLock.owner == merchant.hash
    else {
      throw MikroKhorosError.runtime(
        "purchase.item_unavailable",
        "the item is already sold, reserved, or unavailable"
      )
    }
    let price = merchant.prices[itemHash]!
    guard agent.coin.canPay(price) else {
      throw MikroKhorosError.runtime(
        "purchase.insufficient_coin",
        "the agent does not have enough coin",
        details: ["price": formatAmount(price), "balance": formatAmount(agent.coin.balance)],
        suggestions: ["choose another item or ask the human user to grant more coin"]
      )
    }

    var replacement: MikroObject?
    var replacementCoordinate: Coordinate?
    if merchant.autoRestock {
      let fresh = try item.freshCopy(hash: nextRuntimeIdentity())
      try fresh.lock(authority: .system, owner: merchant.hash, reason: "shop_inventory")
      replacement = fresh
      replacementCoordinate = nearestAvailableCoordinate(
        in: shop.container!, around: .origin, excluding: nil
      )
    }

    let previousLock = item.lockInfo
    var didPay = false
    do {
      try item.claimPickup(
        for: agent.hash,
        authority: .system,
        owner: merchant.hash,
        reason: "purchased_claim",
        clearsOnPickup: true
      )
      try agent.coin.pay(price)
      didPay = true
      if let replacement, let replacementCoordinate {
        try place(replacement, at: replacementCoordinate, in: shop.container!)
        merchant.addPrice(price, for: replacement.hash)
      }
    } catch {
      item.restoreLock(previousLock)
      if didPay { agent.coin.refund(price) }
      if let replacement, replacement.parentSpace != nil { try? removeObject(replacement) }
      throw error
    }
    return PurchaseResult(item: item, price: price, restocked: replacement)
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
    guard agentRegistry[sender.hash] === sender, findObject(source.hash) === source else {
      throw MikroKhorosError.function("messenger sender identity is invalid")
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

  public func selfState(_ agent: Agent) throws -> String {
    try requireActive(agent)
    var lines = [
      "agent:",
      "  id: \(yamlScalar(agent.hash, limit: 128))",
      "  name: \(yamlScalar(agent.name, limit: 128))",
      "position: \(yamlScalar(agentPath(agent), limit: 2_048))",
    ]
    if let hand = agent.hand {
      lines.append("held:")
      lines.append(contentsOf: surfaceLines(hand, indentation: "  "))
      lines.append("standing_on: none")
    } else {
      lines.append("held: none")
      if let current = agent.space.object(at: agent.coordinate) {
        lines.append("standing_on:")
        lines.append(contentsOf: surfaceLines(current, indentation: "  "))
      } else {
        lines.append("standing_on: none")
      }
    }
    lines.append("coin: \(yamlScalar(formatAmount(agent.coin.balance)))")
    return lines.joined(separator: "\n")
  }

  public func observe(_ agent: Agent) throws -> String { try selfState(agent) }

  public func renderEyeView(for agent: Agent) -> String {
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
            lines.append("          loaded: \(visible.hand == nil ? "false" : "true")")
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

  private func materialBlocker(
    in space: Space,
    at coordinate: Coordinate,
    excluding excludedAgent: Agent?
  ) -> String? {
    if let object = space.object(at: coordinate) {
      return "object #\(object.hash)"
    }
    if let loaded = activeAgents.first(where: {
      $0 !== excludedAgent && $0.space === space && $0.coordinate == coordinate && $0.hand != nil
    }) {
      return "loaded agent #\(loaded.hash)"
    }
    return nil
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
    let held = agent.hand.map { [$0] } ?? []
    return held + agent.backpack.walkContents()
  }

  private func enqueueLatestUnreadFromCarriedSources(for agent: Agent) {
    for object in carriedObjects(for: agent).sorted(by: { $0.hash < $1.hash }) {
      enqueueLatestUnread(from: object, for: agent)
    }
  }

  private func enqueueLatestUnread(from object: MikroObject, for agent: Agent) {
    guard agent.isInWorld, agent.aiProfile != nil,
      isCarried(object, by: agent),
      let source = object as? BroadcastSource,
      let event = source.latestUnreadEvent()
    else { return }
    if !agent.pendingBroadcasts.contains(where: { $0.id == event.id }) {
      agent.pendingBroadcasts.append(event)
    }
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
      if let registered = objectRegistry[member.hash], registered !== member {
        throw MikroKhorosError.placement("object identity is already registered")
      }
    }
  }

  private func registerTree(_ object: MikroObject) {
    for member in [object] + object.walkContents() { objectRegistry[member.hash] = member }
  }
}
