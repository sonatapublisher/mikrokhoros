import Foundation

/// Human-administration views of the authoritative runtime state. These snapshots
/// are never included in an agent model request.
extension Harness {
  public func administrativeWorldSnapshot() -> JSONValue {
    .object([
      "schema_version": .number(1),
      "world_id": .string(world.hash),
      "agents": .array(agents.map(administrativeAgentSnapshot)),
      "objects": .array(objects.map(administrativeObjectSnapshot)),
    ])
  }

  public func administrativeSnapshot(for query: String) throws -> JSONValue {
    let exactAgents = agents.filter { $0.hash == query }
    let exactObjects = objects.filter { $0.hash == query }
    if let agent = exactAgents.first { return administrativeAgentSnapshot(agent) }
    if let object = exactObjects.first { return administrativeObjectSnapshot(object) }

    let matchingAgents = agents.filter { $0.hash.hasPrefix(query) }
    let matchingObjects = objects.filter { $0.hash.hasPrefix(query) }
    let count = matchingAgents.count + matchingObjects.count
    guard count > 0 else {
      throw MikroKhorosError.command("no agent or object matches this id")
    }
    guard count == 1 else {
      throw MikroKhorosError.command("agent or object id prefix is ambiguous")
    }
    if let agent = matchingAgents.first { return administrativeAgentSnapshot(agent) }
    return administrativeObjectSnapshot(matchingObjects[0])
  }

  private func administrativeAgentSnapshot(_ agent: Agent) -> JSONValue {
    let profile: JSONValue
    if let value = agent.aiProfile {
      profile = .object([
        "id": .string(value.id),
        "name": .string(value.name),
        "adapter_id": .string(value.adapterID),
        "transport": .string(value.transport.rawValue),
        "model": .string(value.model),
        "endpoint": value.endpoint.map(JSONValue.string) ?? .null,
        "credential_environment_variable":
          value.credentialEnvironmentVariable.map(JSONValue.string) ?? .null,
        "temperature": value.temperature.map(JSONValue.number) ?? .null,
        "maximum_output_tokens": value.maximumOutputTokens.map {
          .number(Double($0))
        } ?? .null,
        "reasoning_effort": value.reasoningEffort.map(JSONValue.string) ?? .null,
      ])
    } else {
      profile = .null
    }

    let returnFrame: JSONValue
    if let frame = agent.backpackReturn {
      returnFrame = .object([
        "space_owner_id": .string(frame.space.owner.hash),
        "coordinate": coordinateValue(frame.coordinate),
        "path": .string("\(frame.coordinate)@\(spacePath(frame.space))"),
      ])
    } else {
      returnFrame = .null
    }

    return .object([
      "kind": .string("agent"),
      "id": .string(agent.hash),
      "name": .string(agent.name),
      "in_world": .bool(agent.isInWorld),
      "has_entered_world": .bool(agent.hasEnteredWorld),
      "space_owner_id": .string(agent.space.owner.hash),
      "coordinate": coordinateValue(agent.coordinate),
      "path": agent.isInWorld ? .string(agentPath(agent)) : .null,
      "hand_object_id": agent.hand.map { .string($0.hash) } ?? .null,
      "backpack_object_id": .string(agent.backpack.hash),
      "coin_object_id": .string(agent.coin.hash),
      "backpack_return": returnFrame,
      "ai_profile": profile,
      "maximum_actions_per_response": .number(Double(agent.maximumActionsPerResponse)),
      "effective_maximum_actions_per_response": .number(
        Double(min(agent.maximumActionsPerResponse, limits.maximumActionsPerResponse))
      ),
      "known_object_ids": .array(agent.knownHashes.sorted().map(JSONValue.string)),
      "pending_notifications": .array(
        agent.pendingBroadcasts.map(administrativeBroadcastSnapshot)
      ),
    ])
  }

  private func administrativeObjectSnapshot(_ object: MikroObject) -> JSONValue {
    let inspection = object.inspect()
    let lock: JSONValue
    if let value = inspection.lock {
      lock = .object([
        "mode": .string(value.mode.rawValue),
        "authority": .string(value.authority.description),
        "owner": .string(value.owner),
        "reason": .string(value.reason),
        "allowed_agent_ids": .array(value.allowedAgentIDs.sorted().map(JSONValue.string)),
        "clears_on_pickup": .bool(value.clearsOnPickup),
      ])
    } else {
      lock = .null
    }

    let contents =
      object.container?.items.map {
        JSONValue.object([
          "coordinate": coordinateValue($0.coordinate),
          "object_id": .string($0.object.hash),
        ])
      } ?? []

    return .object([
      "kind": .string("object"),
      "id": .string(inspection.hash),
      "type": .string(inspection.typeName),
      "name": .string(inspection.name),
      "summary": .string(inspection.summary),
      "origin": .string(inspection.origin.rawValue),
      "invocation_access": .string(inspection.invocationAccess.rawValue),
      "installation_id": inspection.installationID.map(JSONValue.string) ?? .null,
      "durability": inspection.durability.map { .number(Double($0)) } ?? .null,
      "maximum_durability": inspection.maximumDurability.map {
        .number(Double($0))
      } ?? .null,
      "public_data": .object(inspection.publicData),
      "pickup_lock": lock,
      "location": administrativeLocation(of: object),
      "container_contents": .array(contents),
      "functions": .array(
        inspection.functions.map {
          .object([
            "name": .string($0.name),
            "signature": .string($0.signature),
            "summary": .string($0.summary),
            "parameters": .array($0.parameters.map(JSONValue.string)),
            "durability_cost": .number(Double($0.durabilityCost)),
          ])
        }
      ),
      "state": administrativeState(of: object),
    ])
  }

  private func administrativeLocation(of object: MikroObject) -> JSONValue {
    if object === world {
      return .object(["kind": .string("root")])
    }
    if let agent = agents.first(where: { $0.hand === object }) {
      return .object([
        "kind": .string("held"),
        "agent_id": .string(agent.hash),
      ])
    }
    if let agent = agents.first(where: { $0.backpack === object }) {
      return .object([
        "kind": .string("owned"),
        "agent_id": .string(agent.hash),
        "slot": .string("backpack"),
      ])
    }
    if let agent = agents.first(where: { $0.coin === object }) {
      return .object([
        "kind": .string("owned"),
        "agent_id": .string(agent.hash),
        "slot": .string("coin"),
      ])
    }
    if let space = object.parentSpace, let coordinate = object.coordinate {
      var location: [String: JSONValue] = [
        "kind": .string("placed"),
        "parent_object_id": .string(space.owner.hash),
        "coordinate": coordinateValue(coordinate),
        "path": .string("\(coordinate)@\(spacePath(space))"),
      ]
      if let agent = carrier(of: object) {
        location["carrier_agent_id"] = .string(agent.hash)
      }
      return .object(location)
    }
    return .object(["kind": .string("detached")])
  }

  private func administrativeState(of object: MikroObject) -> JSONValue {
    switch object {
    case let value as ScratchpadObject:
      return .object(["text": .string(value.text)])
    case let value as MessengerObject:
      return .object([
        "threads": .array(
          value.threads.map {
            .object(["id": .string($0.id), "title": .string($0.title)])
          }
        ),
        "messages": .array(
          value.messages.map {
            .object([
              "id": .string($0.id),
              "thread_id": .string($0.threadID),
              "sender": .string($0.sender),
              "sender_agent_id": $0.senderAgentID.map(JSONValue.string) ?? .null,
              "body": .string($0.body),
              "priority": $0.priority.map { .string($0.rawValue) } ?? .null,
              "timestamp": .string(Self.administrativeDate($0.timestamp)),
              "is_read": .bool($0.isRead),
            ])
          }
        ),
        "read_receipts": .array(
          value.readReceipts.map {
            .object([
              "message_id": .string($0.messageID),
              "reader_agent_id": .string($0.readerAgentID),
              "timestamp": .string(Self.administrativeDate($0.timestamp)),
            ])
          }
        ),
      ])
    case let value as CoinObject:
      return .object([
        "balance": value.balance.map { .string(formatAmount($0)) } ?? .string("infinite")
      ])
    case let value as PortalObject:
      return .object(["key_hash": value.keyHash.map(JSONValue.string) ?? .null])
    case let value as KeyObject:
      return .object(["portal_hash": .string(value.portalHash)])
    case let value as MerchantObject:
      return .object([
        "shop_hash": .string(value.shopHash),
        "prices": .object(value.prices.mapValues { .string(formatAmount($0)) }),
        "auto_restock": .bool(value.autoRestock),
      ])
    case let value as ObjectiveObject:
      return .object([
        "title": .string(value.title),
        "body": .string(value.body),
        "created_at": .string(Self.administrativeDate(value.createdAt)),
        "state": .string(value.state.rawValue),
        "participant_agent_ids": .array(
          value.participantAgentIDs.sorted().map(JSONValue.string)
        ),
        "completed_by_agent_id": value.completedByAgentID.map(JSONValue.string) ?? .null,
      ])
    case let value as ObjectiveIndexObject:
      return .object(["board_id": .string(value.boardID)])
    case let value as WarehouseDirectoryObject:
      return .object(["warehouse_id": .string(value.warehouseID)])
    case let value as LibraryDocumentObject:
      return .object([
        "title": .string(value.title),
        "source_url": .string(value.sourceURL),
        "content": .string(value.content),
        "fetched_at": .string(Self.administrativeDate(value.fetchedAt)),
      ])
    case let value as LibraryCatalogObject:
      return .object(["library_id": .string(value.libraryID)])
    case let value as DeclarativeObject:
      return .object(["private_state": .object(value.privateState)])
    default:
      return .object([:])
    }
  }

  private func administrativeBroadcastSnapshot(_ event: AgentBroadcastEvent) -> JSONValue {
    .object([
      "id": .string(event.id),
      "timestamp": .string(Self.administrativeDate(event.timestamp)),
      "source_id": .string(event.sourceID),
      "source_type": .string(event.sourceType),
      "priority": event.priority.map(JSONValue.string) ?? .null,
      "title": .string(event.title),
      "body": .string(event.body),
    ])
  }

  private func coordinateValue(_ coordinate: Coordinate) -> JSONValue {
    .object([
      "x": .number(Double(coordinate.x)),
      "y": .number(Double(coordinate.y)),
    ])
  }

  private static func administrativeDate(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }
}
