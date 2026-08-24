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

/// ObjectLocationIndex walks a graph depth derived from the runtime action
/// depth.  Keep the multiplication checked: persisted configuration is
/// untrusted input and `Int.max * 64` must fail closed instead of trapping
/// before the world can report a persistence error.
private func worldLocationIndexDepth(_ maximumObjectInvocationDepth: Int) throws -> Int {
  let (depth, overflow) = maximumObjectInvocationDepth.multipliedReportingOverflow(by: 64)
  guard !overflow, depth > 0 else {
    throw MikroKhorosError.persistence(
      "maximum object invocation depth cannot produce a valid location-index depth"
    )
  }
  return depth
}

private struct WorldPersistenceCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil

  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

private func rejectUnknownWorldFields(
  _ decoder: Decoder,
  allowed: Set<String>,
  context: String
) throws {
  let container = try decoder.container(keyedBy: WorldPersistenceCodingKey.self)
  guard container.allKeys.first(where: { !allowed.contains($0.stringValue) }) == nil else {
    throw MikroKhorosError.persistence("\(context) contains an unknown field")
  }
}

private func validateWorldEnvelopeText(
  _ value: String,
  label: String,
  maximumCharacters: Int = 256,
  allowEmpty: Bool = false
) throws {
  guard allowEmpty || !value.isEmpty, value.count <= maximumCharacters,
    !value.contains(where: { $0.isNewline })
  else {
    throw MikroKhorosError.persistence("operation envelope \(label) is invalid")
  }
}

public struct WorldAgentRecord: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let maximumActionsPerResponse: Int
  public let genesis: AgentGenesisIDs
  public let initialProfile: AIProfile?

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, name, maximumActionsPerResponse, genesis, initialProfile
  }

  public init(
    id: String,
    name: String,
    maximumActionsPerResponse: Int,
    genesis: AgentGenesisIDs,
    initialProfile: AIProfile? = nil
  ) {
    self.id = id
    self.name = name
    self.maximumActionsPerResponse = maximumActionsPerResponse
    self.genesis = genesis
    self.initialProfile = initialProfile
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownWorldFields(
      decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "world agent record"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.name = try container.decode(String.self, forKey: .name)
    self.maximumActionsPerResponse = try container.decode(
      Int.self,
      forKey: .maximumActionsPerResponse
    )
    let genesisDecoder = try container.superDecoder(forKey: .genesis)
    try rejectUnknownWorldFields(
      genesisDecoder,
      allowed: ["backpack", "wallet", "eye", "scratchpad", "messenger", "calculator"],
      context: "agent genesis record"
    )
    self.genesis = try AgentGenesisIDs(from: genesisDecoder)
    self.initialProfile = try container.decodeIfPresent(AIProfile.self, forKey: .initialProfile)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(maximumActionsPerResponse, forKey: .maximumActionsPerResponse)
    try container.encode(genesis, forKey: .genesis)
    try container.encodeIfPresent(initialProfile, forKey: .initialProfile)
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

public struct WorldObjectMutation: Codable, Equatable, Sendable {
  public let objectID: String
  public let operation: String
  public let priorRevision: Int?
  public let nextRevision: Int?

  public init(
    objectID: String,
    operation: String,
    priorRevision: Int? = nil,
    nextRevision: Int? = nil
  ) {
    self.objectID = objectID
    self.operation = operation
    self.priorRevision = priorRevision
    self.nextRevision = nextRevision
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case objectID, operation, priorRevision, nextRevision
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownWorldFields(
      decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "world object mutation"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.objectID = try container.decode(String.self, forKey: .objectID)
    self.operation = try container.decode(String.self, forKey: .operation)
    self.priorRevision = try container.decodeIfPresent(Int.self, forKey: .priorRevision)
    self.nextRevision = try container.decodeIfPresent(Int.self, forKey: .nextRevision)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(objectID, forKey: .objectID)
    try container.encode(operation, forKey: .operation)
    try container.encodeIfPresent(priorRevision, forKey: .priorRevision)
    try container.encodeIfPresent(nextRevision, forKey: .nextRevision)
  }
}

public struct WorldOperationReceipt: Codable, Equatable, Sendable {
  public let id: String
  public let kind: String
  public let value: String

  public init(id: String, kind: String, value: String = "") {
    self.id = id
    self.kind = kind
    self.value = value
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, kind, value
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownWorldFields(
      decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "world operation receipt"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.kind = try container.decode(String.self, forKey: .kind)
    self.value = try container.decode(String.self, forKey: .value)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(kind, forKey: .kind)
    try container.encode(value, forKey: .value)
  }
}

public struct WorldUnreadRecord: Codable, Equatable, Sendable {
  public let eventID: String
  /// Informational bearer at the time the event was signed. The Wallet is the
  /// durable source queue; this value is never used as its authority and is
  /// nil for an ownerless wallet.
  public let agentID: String?
  public let sourceID: String
  public let sourceType: String
  public let timestamp: Date
  public let priority: String?
  public let title: String
  public let body: String

  public init(
    eventID: String,
    agentID: String? = nil,
    sourceID: String,
    sourceType: String = "wallet.object",
    timestamp: Date = Date(timeIntervalSince1970: 0),
    priority: String? = nil,
    title: String = "Wallet update",
    body: String = ""
  ) {
    self.eventID = eventID
    self.agentID = agentID
    self.sourceID = sourceID
    self.sourceType = sourceType
    self.timestamp = timestamp
    self.priority = priority
    self.title = title
    self.body = body
  }

  public init(agentID: String? = nil, event: AgentBroadcastEvent) {
    self.init(
      eventID: event.id,
      agentID: agentID,
      sourceID: event.sourceID,
      sourceType: event.sourceType,
      timestamp: event.timestamp,
      priority: event.priority,
      title: event.title,
      body: event.body
    )
  }

  public var event: AgentBroadcastEvent {
    AgentBroadcastEvent(
      id: eventID,
      timestamp: timestamp,
      sourceID: sourceID,
      sourceType: sourceType,
      priority: priority,
      title: title,
      body: body
    )
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case eventID, agentID, sourceID, sourceType, timestamp, priority, title, body
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownWorldFields(
      decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "world unread record"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.eventID = try container.decode(String.self, forKey: .eventID)
    self.agentID = try container.decodeIfPresent(String.self, forKey: .agentID)
    self.sourceID = try container.decode(String.self, forKey: .sourceID)
    self.sourceType = try container.decode(String.self, forKey: .sourceType)
    self.timestamp = try container.decode(Date.self, forKey: .timestamp)
    self.priority = try container.decodeIfPresent(String.self, forKey: .priority)
    self.title = try container.decode(String.self, forKey: .title)
    self.body = try container.decode(String.self, forKey: .body)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(eventID, forKey: .eventID)
    try container.encodeIfPresent(agentID, forKey: .agentID)
    try container.encode(sourceID, forKey: .sourceID)
    try container.encode(sourceType, forKey: .sourceType)
    try container.encode(timestamp, forKey: .timestamp)
    try container.encodeIfPresent(priority, forKey: .priority)
    try container.encode(title, forKey: .title)
    try container.encode(body, forKey: .body)
  }
}

public struct WorldUnreadAcknowledgement: Codable, Equatable, Sendable {
  public let agentID: String
  public let sourceID: String
  public let eventID: String

  public init(agentID: String, eventID: String, sourceID: String) {
    self.agentID = agentID
    self.sourceID = sourceID
    self.eventID = eventID
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case agentID, sourceID, eventID
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownWorldFields(
      decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "world unread acknowledgement"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.agentID = try container.decode(String.self, forKey: .agentID)
    self.sourceID = try container.decode(String.self, forKey: .sourceID)
    self.eventID = try container.decode(String.self, forKey: .eventID)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(agentID, forKey: .agentID)
    try container.encode(sourceID, forKey: .sourceID)
    try container.encode(eventID, forKey: .eventID)
  }
}

/// Sanitized activity is an administrative audit signal, not a model transcript.
/// It intentionally has no arguments, raw output, prompt, or reasoning fields.
public struct ActivityRecord: Codable, Equatable, Sendable {
  public let id: String
  public let timestamp: Date
  public let agentID: String?
  public let operation: String
  public let success: Bool
  public let code: String?

  public init(
    id: String,
    timestamp: Date,
    agentID: String? = nil,
    operation: String,
    success: Bool,
    code: String? = nil
  ) {
    self.id = id
    self.timestamp = timestamp
    self.agentID = agentID
    self.operation = operation
    self.success = success
    self.code = code
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case id, timestamp, agentID, operation, success, code
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownWorldFields(
      decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "world activity"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.timestamp = try container.decode(Date.self, forKey: .timestamp)
    self.agentID = try container.decodeIfPresent(String.self, forKey: .agentID)
    self.operation = try container.decode(String.self, forKey: .operation)
    self.success = try container.decode(Bool.self, forKey: .success)
    self.code = try container.decodeIfPresent(String.self, forKey: .code)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(timestamp, forKey: .timestamp)
    try container.encodeIfPresent(agentID, forKey: .agentID)
    try container.encode(operation, forKey: .operation)
    try container.encode(success, forKey: .success)
    try container.encodeIfPresent(code, forKey: .code)
  }
}

public struct WorldPurchaseRestockMutation: Codable, Equatable, Sendable {
  public let objectID: String
  public let restockRuleID: String
  public let inventoryObjectID: String
  public let inventoryRevision: Int
  public let deploymentID: String
  public let coordinate: Coordinate
  public let price: CreditBalance

  public init(
    objectID: String,
    restockRuleID: String,
    inventoryObjectID: String,
    inventoryRevision: Int,
    deploymentID: String,
    coordinate: Coordinate,
    price: CreditBalance
  ) {
    self.objectID = objectID
    self.restockRuleID = restockRuleID
    self.inventoryObjectID = inventoryObjectID
    self.inventoryRevision = inventoryRevision
    self.deploymentID = deploymentID
    self.coordinate = coordinate
    self.price = price
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case objectID, restockRuleID, inventoryObjectID, inventoryRevision, deploymentID
    case coordinate, price
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownWorldFields(
      decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "world purchase restock mutation"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    objectID = try container.decode(String.self, forKey: .objectID)
    restockRuleID = try container.decode(String.self, forKey: .restockRuleID)
    inventoryObjectID = try container.decode(String.self, forKey: .inventoryObjectID)
    inventoryRevision = try container.decode(Int.self, forKey: .inventoryRevision)
    deploymentID = try container.decode(String.self, forKey: .deploymentID)
    coordinate = try container.decode(Coordinate.self, forKey: .coordinate)
    price = try container.decode(CreditBalance.self, forKey: .price)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(objectID, forKey: .objectID)
    try container.encode(restockRuleID, forKey: .restockRuleID)
    try container.encode(inventoryObjectID, forKey: .inventoryObjectID)
    try container.encode(inventoryRevision, forKey: .inventoryRevision)
    try container.encode(deploymentID, forKey: .deploymentID)
    try container.encode(coordinate, forKey: .coordinate)
    try container.encode(price, forKey: .price)
  }

  var signedCausalFunctionID: String {
    let components = [
      objectID,
      restockRuleID,
      inventoryObjectID,
      String(inventoryRevision),
      deploymentID,
      String(coordinate.x),
      String(coordinate.y),
      price.decimalText,
    ]
    let digest = SHA256Digest.hex(Data(components.joined(separator: "\u{0}").utf8))
    return "merchant.buy.restock.\(String(digest.prefix(48)))"
  }
}

public struct WorldPurchaseMutation: Codable, Equatable, Sendable {
  public let recordID: String
  public let payerWalletID: String
  public let buyerAgentID: String
  public let merchantID: String
  public let itemID: String
  public let nominalAmount: CreditBalance
  public let appliedAmount: CreditBalance
  public let replacement: WorldPurchaseRestockMutation?
  public let receiptID: String
  public let unreadEventID: String

  public init(
    recordID: String,
    payerWalletID: String,
    buyerAgentID: String,
    merchantID: String,
    itemID: String,
    nominalAmount: CreditBalance,
    appliedAmount: CreditBalance,
    replacement: WorldPurchaseRestockMutation? = nil,
    receiptID: String,
    unreadEventID: String
  ) {
    self.recordID = recordID
    self.payerWalletID = payerWalletID
    self.buyerAgentID = buyerAgentID
    self.merchantID = merchantID
    self.itemID = itemID
    self.nominalAmount = nominalAmount
    self.appliedAmount = appliedAmount
    self.replacement = replacement
    self.receiptID = receiptID
    self.unreadEventID = unreadEventID
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case recordID, payerWalletID, buyerAgentID, merchantID, itemID
    case nominalAmount, appliedAmount, replacement, receiptID, unreadEventID
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownWorldFields(
      decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "world purchase mutation"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    recordID = try container.decode(String.self, forKey: .recordID)
    payerWalletID = try container.decode(String.self, forKey: .payerWalletID)
    buyerAgentID = try container.decode(String.self, forKey: .buyerAgentID)
    merchantID = try container.decode(String.self, forKey: .merchantID)
    itemID = try container.decode(String.self, forKey: .itemID)
    nominalAmount = try container.decode(CreditBalance.self, forKey: .nominalAmount)
    appliedAmount = try container.decode(CreditBalance.self, forKey: .appliedAmount)
    replacement = try container.decodeIfPresent(
      WorldPurchaseRestockMutation.self,
      forKey: .replacement
    )
    receiptID = try container.decode(String.self, forKey: .receiptID)
    unreadEventID = try container.decode(String.self, forKey: .unreadEventID)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(recordID, forKey: .recordID)
    try container.encode(payerWalletID, forKey: .payerWalletID)
    try container.encode(buyerAgentID, forKey: .buyerAgentID)
    try container.encode(merchantID, forKey: .merchantID)
    try container.encode(itemID, forKey: .itemID)
    try container.encode(nominalAmount, forKey: .nominalAmount)
    try container.encode(appliedAmount, forKey: .appliedAmount)
    try container.encodeIfPresent(replacement, forKey: .replacement)
    try container.encode(receiptID, forKey: .receiptID)
    try container.encode(unreadEventID, forKey: .unreadEventID)
  }
}

public struct WorldOperationEnvelope: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let operationID: String
  public let worldID: String
  public let actor: String
  public let timestamp: Date
  public let actionIndex: UInt64
  public let signedCreditRecords: [SignedCreditRecord]
  public let purchases: [WorldPurchaseMutation]
  public let objectMutations: [WorldObjectMutation]
  public let receipts: [WorldOperationReceipt]
  public let unread: [WorldUnreadRecord]
  public let acknowledgements: [WorldUnreadAcknowledgement]
  public let activity: [ActivityRecord]
  public let idempotencyKey: String?

  public init(
    schemaVersion: Int = Self.currentSchemaVersion,
    operationID: String,
    worldID: String,
    actor: String,
    timestamp: Date,
    actionIndex: UInt64 = 0,
    signedCreditRecords: [SignedCreditRecord] = [],
    purchases: [WorldPurchaseMutation] = [],
    objectMutations: [WorldObjectMutation] = [],
    receipts: [WorldOperationReceipt] = [],
    unread: [WorldUnreadRecord] = [],
    acknowledgements: [WorldUnreadAcknowledgement] = [],
    activity: [ActivityRecord] = [],
    idempotencyKey: String? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.operationID = operationID
    self.worldID = worldID
    self.actor = actor
    self.timestamp = timestamp
    self.actionIndex = actionIndex
    self.signedCreditRecords = signedCreditRecords
    self.purchases = purchases
    self.objectMutations = objectMutations
    self.receipts = receipts
    self.unread = unread
    self.acknowledgements = acknowledgements
    self.activity = activity
    self.idempotencyKey = idempotencyKey
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion
    case operationID
    case worldID
    case actor
    case timestamp
    case actionIndex
    case signedCreditRecords
    case purchases
    case objectMutations
    case receipts
    case unread
    case acknowledgements
    case activity
    case idempotencyKey
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownWorldFields(
      decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "world operation envelope"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    guard schemaVersion == Self.currentSchemaVersion else {
      throw MikroKhorosError.persistence(
        "unsupported world operation envelope schema version found \(schemaVersion); required \(Self.currentSchemaVersion)"
      )
    }
    let operationID = try container.decode(String.self, forKey: .operationID)
    let worldID = try container.decode(String.self, forKey: .worldID)
    let actor = try container.decode(String.self, forKey: .actor)
    let timestamp = try container.decode(Date.self, forKey: .timestamp)
    let actionIndex = try container.decode(UInt64.self, forKey: .actionIndex)
    let signedCreditRecords = try container.decode(
      [SignedCreditRecord].self,
      forKey: .signedCreditRecords
    )
    let purchases = try container.decode([WorldPurchaseMutation].self, forKey: .purchases)
    let objectMutations = try container.decode(
      [WorldObjectMutation].self,
      forKey: .objectMutations
    )
    let receipts = try container.decode([WorldOperationReceipt].self, forKey: .receipts)
    let unread = try container.decode([WorldUnreadRecord].self, forKey: .unread)
    let acknowledgements = try container.decode(
      [WorldUnreadAcknowledgement].self,
      forKey: .acknowledgements
    )
    let activity = try container.decode([ActivityRecord].self, forKey: .activity)
    let idempotencyKey = try container.decodeIfPresent(String.self, forKey: .idempotencyKey)

    try Self.validate(
      operationID: operationID,
      worldID: worldID,
      actor: actor,
      timestamp: timestamp,
      actionIndex: actionIndex,
      signedCreditRecords: signedCreditRecords,
      purchases: purchases,
      objectMutations: objectMutations,
      receipts: receipts,
      unread: unread,
      acknowledgements: acknowledgements,
      activity: activity,
      idempotencyKey: idempotencyKey
    )

    self.schemaVersion = schemaVersion
    self.operationID = operationID
    self.worldID = worldID
    self.actor = actor
    self.timestamp = timestamp
    self.actionIndex = actionIndex
    self.signedCreditRecords = signedCreditRecords
    self.purchases = purchases
    self.objectMutations = objectMutations
    self.receipts = receipts
    self.unread = unread
    self.acknowledgements = acknowledgements
    self.activity = activity
    self.idempotencyKey = idempotencyKey
  }

  public func encode(to encoder: Encoder) throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw MikroKhorosError.persistence(
        "unsupported world operation envelope schema version found \(schemaVersion); required \(Self.currentSchemaVersion)"
      )
    }
    try Self.validate(
      operationID: operationID,
      worldID: worldID,
      actor: actor,
      timestamp: timestamp,
      actionIndex: actionIndex,
      signedCreditRecords: signedCreditRecords,
      purchases: purchases,
      objectMutations: objectMutations,
      receipts: receipts,
      unread: unread,
      acknowledgements: acknowledgements,
      activity: activity,
      idempotencyKey: idempotencyKey
    )
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(operationID, forKey: .operationID)
    try container.encode(worldID, forKey: .worldID)
    try container.encode(actor, forKey: .actor)
    try container.encode(timestamp, forKey: .timestamp)
    try container.encode(actionIndex, forKey: .actionIndex)
    try container.encode(signedCreditRecords, forKey: .signedCreditRecords)
    try container.encode(purchases, forKey: .purchases)
    try container.encode(objectMutations, forKey: .objectMutations)
    try container.encode(receipts, forKey: .receipts)
    try container.encode(unread, forKey: .unread)
    try container.encode(acknowledgements, forKey: .acknowledgements)
    try container.encode(activity, forKey: .activity)
    try container.encodeIfPresent(idempotencyKey, forKey: .idempotencyKey)
  }

  fileprivate func validateForPersistence() throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw MikroKhorosError.persistence(
        "unsupported world operation envelope schema version found \(schemaVersion); required \(Self.currentSchemaVersion)"
      )
    }
    try Self.validate(
      operationID: operationID,
      worldID: worldID,
      actor: actor,
      timestamp: timestamp,
      actionIndex: actionIndex,
      signedCreditRecords: signedCreditRecords,
      purchases: purchases,
      objectMutations: objectMutations,
      receipts: receipts,
      unread: unread,
      acknowledgements: acknowledgements,
      activity: activity,
      idempotencyKey: idempotencyKey
    )
  }

  fileprivate static func validate(
    operationID: String,
    worldID: String,
    actor: String,
    timestamp: Date,
    actionIndex: UInt64,
    signedCreditRecords: [SignedCreditRecord],
    purchases: [WorldPurchaseMutation],
    objectMutations: [WorldObjectMutation],
    receipts: [WorldOperationReceipt],
    unread: [WorldUnreadRecord],
    acknowledgements: [WorldUnreadAcknowledgement],
    activity: [ActivityRecord],
    idempotencyKey: String?
  ) throws {
    try validateWorldEnvelopeText(operationID, label: "operation identity")
    try validateWorldEnvelopeText(worldID, label: "world identity")
    try validateWorldEnvelopeText(actor, label: "actor", maximumCharacters: 128)
    guard CreditActor(rawValue: actor) != nil else {
      throw MikroKhorosError.persistence("operation envelope actor is invalid")
    }
    guard timestamp.timeIntervalSince1970.isFinite else {
      throw MikroKhorosError.persistence("operation envelope timestamp is invalid")
    }
    if let idempotencyKey {
      try validateWorldEnvelopeText(idempotencyKey, label: "idempotency key")
    }
    guard signedCreditRecords.count <= 10_000,
      purchases.count <= 10_000,
      objectMutations.count <= 10_000,
      receipts.count <= 10_000,
      unread.count <= 10_000,
      acknowledgements.count <= 10_000,
      activity.count <= 10_000
    else {
      throw MikroKhorosError.persistence("operation envelope exceeds its record limit")
    }
    let recordIDs = signedCreditRecords.map(\.recordID)
    guard Set(recordIDs).count == recordIDs.count else {
      throw MikroKhorosError.persistence("operation envelope contains duplicate credit records")
    }
    var previousRecordHash: String?
    for record in signedCreditRecords {
      guard record.unsigned.worldID == worldID,
        record.unsigned.operationID == operationID,
        record.unsigned.actionIndex == actionIndex,
        record.unsigned.actor == actor,
        record.unsigned.time == timestamp
      else {
        throw MikroKhorosError.persistence(
          "operation envelope credit record identity does not match its envelope"
        )
      }
      if let previousRecordHash {
        guard record.unsigned.priorRecordHash == previousRecordHash else {
          throw MikroKhorosError.persistence(
            "operation envelope credit records are not in canonical chain order"
          )
        }
      }
      previousRecordHash = try record.recordHash()
    }
    let purchaseRecordIDs =
      signedCreditRecords
      .filter { $0.unsigned.kind == .purchase }
      .map(\.recordID)
    let purchaseMutationRecordIDs = purchases.map(\.recordID)
    guard Set(purchaseMutationRecordIDs).count == purchaseMutationRecordIDs.count,
      Set(purchaseMutationRecordIDs) == Set(purchaseRecordIDs)
    else {
      throw MikroKhorosError.persistence(
        "operation envelope purchase records and mutations do not match"
      )
    }
    for purchase in purchases {
      try validateWorldEnvelopeText(purchase.recordID, label: "purchase record identity")
      try validateWorldEnvelopeText(purchase.payerWalletID, label: "purchase payer wallet")
      try validateWorldEnvelopeText(purchase.buyerAgentID, label: "purchase buyer")
      try validateWorldEnvelopeText(purchase.merchantID, label: "purchase merchant")
      try validateWorldEnvelopeText(purchase.itemID, label: "purchase item")
      try validateWorldEnvelopeText(purchase.receiptID, label: "purchase receipt")
      try validateWorldEnvelopeText(purchase.unreadEventID, label: "purchase unread event")
      guard purchase.nominalAmount.minorUnits > 0,
        purchase.appliedAmount.minorUnits >= 0,
        let record = signedCreditRecords.first(where: { $0.recordID == purchase.recordID }),
        record.unsigned.sourceWalletID == purchase.payerWalletID,
        record.unsigned.sourceWalletOwner == purchase.buyerAgentID,
        record.unsigned.causalFunctionIDs
          == (["merchant.buy"]
          + (purchase.replacement.map { [$0.signedCausalFunctionID] } ?? [])).sorted(),
        record.unsigned.causalMerchantIDs == [purchase.merchantID],
        record.unsigned.causalItemIDs == [purchase.itemID],
        record.unsigned.nominalPurchaseAmount == purchase.nominalAmount,
        record.unsigned.appliedPurchaseAmount == purchase.appliedAmount,
        purchase.appliedAmount.minorUnits
          == (record.unsigned.mode == .unlimited ? 0 : purchase.nominalAmount.minorUnits),
        record.unsigned.accounts == [purchase.payerWalletID],
        record.unsigned.amounts
          == [try CreditBalance(minorUnits: -purchase.appliedAmount.minorUnits)]
      else {
        throw MikroKhorosError.persistence(
          "operation envelope purchase mutation conflicts with its signed record"
        )
      }
      let expectedCausalObjects =
        [purchase.payerWalletID, purchase.itemID]
        + (purchase.replacement.map { [$0.objectID] } ?? [])
      guard record.unsigned.causalObjectIDs == expectedCausalObjects.sorted() else {
        throw MikroKhorosError.persistence(
          "operation envelope purchase replacement is not signed by its credit record"
        )
      }
      if let replacement = purchase.replacement {
        try validateWorldEnvelopeText(
          replacement.objectID,
          label: "purchase replacement object"
        )
        try validateWorldEnvelopeText(
          replacement.restockRuleID,
          label: "purchase restock rule"
        )
        try validateWorldEnvelopeText(
          replacement.inventoryObjectID,
          label: "purchase Inventory object"
        )
        try validateWorldEnvelopeText(
          replacement.deploymentID,
          label: "purchase deployment"
        )
        guard replacement.inventoryRevision > 0, replacement.price.minorUnits > 0 else {
          throw MikroKhorosError.persistence(
            "operation envelope purchase replacement is invalid"
          )
        }
      }
      guard purchase.receiptID == purchaseReceiptID(for: purchase.recordID),
        receipts.contains(where: {
          $0.id == purchase.receiptID
            && $0.kind == "merchant_purchase"
            && $0.value == purchase.recordID
        }),
        unread.contains(where: {
          $0.eventID == purchase.unreadEventID
            && $0.sourceID == purchase.payerWalletID
            && $0.timestamp == record.unsigned.time
        })
      else {
        throw MikroKhorosError.persistence(
          "operation envelope purchase receipt or unread record is missing"
        )
      }
    }
    guard receipts.filter({ $0.kind == "merchant_purchase" }).count == purchases.count else {
      throw MikroKhorosError.persistence(
        "operation envelope contains an unbound purchase receipt"
      )
    }
    for mutation in objectMutations {
      try validateWorldEnvelopeText(mutation.objectID, label: "object identity")
      try validateWorldEnvelopeText(
        mutation.operation,
        label: "object mutation",
        maximumCharacters: 128
      )
      if let priorRevision = mutation.priorRevision {
        guard priorRevision >= 0 else {
          throw MikroKhorosError.persistence("operation envelope object revision is invalid")
        }
      }
      if let nextRevision = mutation.nextRevision {
        guard nextRevision >= 0 else {
          throw MikroKhorosError.persistence("operation envelope object revision is invalid")
        }
      }
    }
    for receipt in receipts {
      try validateWorldEnvelopeText(receipt.id, label: "receipt identity")
      try validateWorldEnvelopeText(receipt.kind, label: "receipt kind", maximumCharacters: 128)
      try validateWorldEnvelopeText(
        receipt.value,
        label: "receipt value",
        maximumCharacters: 512,
        allowEmpty: true
      )
    }
    for unread in unread {
      try validateWorldEnvelopeText(unread.eventID, label: "unread event identity")
      if let agentID = unread.agentID {
        try validateWorldEnvelopeText(agentID, label: "unread agent identity")
      }
      try validateWorldEnvelopeText(unread.sourceID, label: "unread source identity")
      try validateWorldEnvelopeText(unread.sourceType, label: "unread source type")
      guard unread.sourceType == "wallet.object" else {
        throw MikroKhorosError.persistence(
          "operation envelope unread records may target only native wallets"
        )
      }
      guard unread.timestamp.timeIntervalSince1970.isFinite else {
        throw MikroKhorosError.persistence("operation envelope unread timestamp is invalid")
      }
      try validateWorldEnvelopeText(
        unread.title,
        label: "unread title",
        maximumCharacters: 255,
        allowEmpty: true
      )
      try validateWorldEnvelopeText(
        unread.body,
        label: "unread body",
        maximumCharacters: AgentBroadcastEvent.maximumBodyCharacters,
        allowEmpty: true
      )
      guard [nil, "!", "!!", "!!!"].contains(unread.priority) else {
        throw MikroKhorosError.persistence("operation envelope unread priority is invalid")
      }
      do {
        try PromptSafety.validateBroadcastEvent(unread.event)
      } catch {
        throw MikroKhorosError.persistence("operation envelope unread event is invalid")
      }
    }
    for acknowledgement in acknowledgements {
      try validateWorldEnvelopeText(
        acknowledgement.agentID,
        label: "acknowledgement agent identity"
      )
      try validateWorldEnvelopeText(
        acknowledgement.sourceID,
        label: "acknowledgement source identity"
      )
      try validateWorldEnvelopeText(
        acknowledgement.eventID,
        label: "acknowledgement event identity"
      )
    }
    let unreadIDs = unread.map { "\($0.sourceID)#\($0.eventID)" }
    guard Set(unreadIDs).count == unreadIDs.count else {
      throw MikroKhorosError.persistence("operation envelope contains duplicate unread events")
    }
    let acknowledgementIDs = acknowledgements.map { "\($0.sourceID)#\($0.eventID)#\($0.agentID)" }
    guard Set(acknowledgementIDs).count == acknowledgementIDs.count else {
      throw MikroKhorosError.persistence(
        "operation envelope contains duplicate unread acknowledgements"
      )
    }
    for record in activity {
      try validateWorldEnvelopeText(record.id, label: "activity identity")
      try validateWorldEnvelopeText(
        record.operation,
        label: "activity operation",
        maximumCharacters: 128
      )
      if let agentID = record.agentID {
        try validateWorldEnvelopeText(agentID, label: "activity agent identity")
      }
      if let code = record.code {
        try validateWorldEnvelopeText(code, label: "activity code", maximumCharacters: 128)
      }
      guard record.timestamp.timeIntervalSince1970.isFinite else {
        throw MikroKhorosError.persistence("operation envelope activity timestamp is invalid")
      }
    }
  }

  fileprivate static func purchaseReceiptID(for recordID: String) -> String {
    let digest = SHA256Digest.hex(Data(recordID.utf8))
    return "purchase-\(String(digest.prefix(48)))"
  }
}

/// Trusted host-facing management contract for exact native runtime objects.
/// Implementations must select by concrete instance conformance, never by a
/// package id or mutable type-name string supplied by an object package.
public protocol NativeObjectManagementProvider: AnyObject {
  func managementInterface(for object: MikroObject) throws -> ObjectManagementInterface
  func runManagementAction(
    _ actionID: String,
    inputs: [String],
    on object: MikroObject
  ) throws -> JSONValue
  func renderManagementView(_ viewID: String, on object: MikroObject) throws -> JSONValue
}

public typealias TrustedNativeObjectManagementProvider = NativeObjectManagementProvider

public enum WorldEvent: Codable, Equatable, Sendable {
  case addAgent(agentID: String, coordinate: Coordinate, autoAdapt: Bool)
  case removeAgent(agentID: String)
  case configureAgent(agentID: String, maximumActionsPerResponse: Int)
  case attachProfile(agentID: String, profile: AIProfile)
  case detachProfile(agentID: String)
  case actions(
    operationID: String,
    agentID: String,
    commands: [String],
    actionIndexes: [UInt64],
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
  case messengerAcknowledged(messengerID: String, messageID: String)
  case humanInboxAcknowledged(agentID: String, messageID: String)
  case humanMessage(
    agentID: String,
    id: String,
    body: String,
    sender: String,
    senderAgentID: String?,
    threadID: String,
    priority: BroadcastPriority?,
    timestamp: Date
  )
  case objectivePostedAt(
    boardID: String,
    id: String,
    title: String,
    body: String,
    createdAt: Date,
    coordinate: Coordinate
  )
  case objectiveAcknowledged(boardID: String, objectiveID: String, eventID: String)
  case libraryDocumentAddedTo(
    libraryID: String,
    id: String,
    title: String,
    sourceURL: String,
    content: String,
    fetchedAt: Date,
    coordinate: Coordinate
  )
  case athenaNoticeFrom(athenaID: String, deliveries: [AthenaNoticeDelivery])
  case worldTemplateApplied(record: WorldTemplateApplicationRecord)
  case worldTemplateComponentsRepaired(record: WorldTemplateRepairRecord)
  case objectDeployed(record: ObjectDeploymentRecord)
  case objectStateChanged(
    objectID: String,
    adapterID: String,
    adapterVersion: String,
    state: [String: JSONValue],
    instanceRevision: Int,
    durability: Int?
  )
  case objectMoved(
    objectID: String,
    destinationObjectID: String,
    coordinate: Coordinate,
    instanceRevision: Int
  )
  case externalEffectReceipt(
    id: String,
    objectID: String,
    operation: String,
    result: String,
    timestamp: Date
  )
  case nestedInvocationReceipt(
    rootInvocationID: String,
    currentInvocationID: String,
    callingObjectID: String,
    targetObjectID: String,
    originalAgentID: String,
    function: String,
    result: String,
    depth: Int
  )
  case objectsDeleted(objectIDs: [String])
  case listenerChanged(objectID: String, enabled: Bool)
  case objectReportDelivered(report: ObjectReport)
  case restockRuleCreated(rule: RestockRule)
  case restockRuleUpdated(rule: RestockRule)
  case restockRuleDeleted(ruleID: String)
  case operationEnvelope(WorldOperationEnvelope)
}

private final class WorldEntropy {
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

public struct WorldDocument: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 7

  public var schemaVersion: Int
  public var worldID: String
  public var worldName: String
  public var templateApplications: [WorldTemplateApplicationRecord]
  public var agents: [WorldAgentRecord]
  public var events: [WorldEvent]
  public var histories: [String: [AIConversationMessage]]
  public var credit: CreditServiceSnapshot?
  public var operations: [WorldOperationEnvelope]

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion, worldID, worldName, templateApplications
    case agents, events, histories, credit, operations
  }

  public init(
    schemaVersion: Int = WorldDocument.currentSchemaVersion,
    worldID: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
    worldName: String = "world",
    templateApplications: [WorldTemplateApplicationRecord] = [],
    agents: [WorldAgentRecord] = [],
    events: [WorldEvent] = [],
    histories: [String: [AIConversationMessage]] = [:],
    credit: CreditServiceSnapshot? = nil,
    operations: [WorldOperationEnvelope] = []
  ) {
    self.schemaVersion = schemaVersion
    self.worldID = worldID
    self.worldName = worldName
    self.templateApplications = templateApplications
    self.agents = agents
    self.events = events
    self.histories = histories
    self.credit = credit
    self.operations = operations
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownWorldFields(
      decoder,
      allowed: Set(CodingKeys.allCases.map(\.rawValue)),
      context: "world document"
    )
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let storedVersion = try container.decode(Int.self, forKey: .schemaVersion)
    guard storedVersion == Self.currentSchemaVersion else {
      throw MikroKhorosError.persistence(
        "unsupported world schema version found \(storedVersion); required \(Self.currentSchemaVersion)"
      )
    }
    let requiredKeys: [CodingKeys] = [
      .worldID, .worldName, .templateApplications, .agents, .events, .histories, .operations,
    ]
    guard requiredKeys.allSatisfy(container.contains) else {
      throw MikroKhorosError.persistence(
        "world document is missing a required schema-7 field"
      )
    }
    let worldID = try container.decode(String.self, forKey: .worldID)
    schemaVersion = Self.currentSchemaVersion
    self.worldID = worldID
    worldName = try container.decode(String.self, forKey: .worldName)
    templateApplications = try container.decode(
      [WorldTemplateApplicationRecord].self,
      forKey: .templateApplications
    )
    agents = try container.decode([WorldAgentRecord].self, forKey: .agents)
    events = try container.decode([WorldEvent].self, forKey: .events)
    histories = try container.decode(
      [String: [AIConversationMessage]].self,
      forKey: .histories
    )
    credit = try container.decodeIfPresent(CreditServiceSnapshot.self, forKey: .credit)
    operations = try container.decode([WorldOperationEnvelope].self, forKey: .operations)
  }

  public func encode(to encoder: Encoder) throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw MikroKhorosError.persistence(
        "unsupported world schema version found \(schemaVersion); required \(Self.currentSchemaVersion)"
      )
    }
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(worldID, forKey: .worldID)
    try container.encode(worldName, forKey: .worldName)
    try container.encode(templateApplications, forKey: .templateApplications)
    try container.encode(agents, forKey: .agents)
    try container.encode(events, forKey: .events)
    try container.encode(histories, forKey: .histories)
    try container.encodeIfPresent(credit, forKey: .credit)
    try container.encode(operations, forKey: .operations)
  }
}

/// A persistent, event-sourced world. Custom hosts may use the lower-level
/// library directly and provide their own object snapshot storage.
private struct WorldOperationIdentity: Hashable {
  let operationID: String
  let actionIndex: UInt64
}

/// Returns the two exact arguments of the persisted buy action. Agent action
/// syntax deliberately keeps the merchant as the invocation target rather
/// than serializing it in the command, so the signed purchase record remains
/// the authority for that target.
private func persistedPurchaseActionArguments(
  _ command: String
) -> (itemSelector: String, walletID: String)? {
  let pattern = #"(?i)^\s*object\s*\(\s*buy\s*\(\s*([^\s()]+)\s*\)\s*\(\s*([^\s()]+)\s*\)\s*\)\s*$"#
  guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
  let range = NSRange(command.startIndex..<command.endIndex, in: command)
  guard let match = expression.firstMatch(in: command, range: range),
    let itemRange = Range(match.range(at: 1), in: command),
    let walletRange = Range(match.range(at: 2), in: command)
  else {
    return nil
  }
  return (
    itemSelector: String(command[itemRange]),
    walletID: String(command[walletRange])
  )
}

private struct ReplayWalletLocation: Equatable {
  let ownerID: String?
  let locationCommitment: String
}

private struct ReplayCustodyTransition: Equatable {
  let walletID: String
  let oldOwner: String?
  let newOwner: String?
  let oldLocationCommitment: String
  let newLocationCommitment: String
  /// Model actions carry an explicit composite operation identity. Non-action
  /// graph events leave this nil and are matched against the next system
  /// custody envelope in journal order.
  let operation: WorldOperationIdentity?
}

private struct ObjectiveAcknowledgementKey: Hashable {
  let boardID: String
  let objectiveID: String
  let eventID: String

  var receiptValue: String { "\(boardID)#\(objectiveID)#\(eventID)" }
}

public final class WorldRuntime {
  public private(set) var document: WorldDocument
  public let configuration: RuntimeConfiguration
  public let harness: Harness
  public private(set) var creditService: CreditService
  public let inventory: InventoryStore?
  public private(set) var listeners: Set<String> = []
  public private(set) var reports: [ObjectReport] = []
  public private(set) var restockRules: [String: RestockRule] = [:]
  public private(set) var activity: [ActivityRecord] = []
  private var sessions: [String: AgentSession] = [:]
  private let entropy: WorldEntropy
  private let inventoryReferenceOwner: String
  /// Operation envelopes are persisted in both the ordered event journal and
  /// the compact operation index. This set is replay-local state; it is never
  /// serialized and therefore cannot become a second source of truth.
  private var replayedOperationEnvelopes: [WorldOperationIdentity: WorldOperationEnvelope] = [:]
  /// During action replay, a financial record must be applied before its
  /// command (so the command observes the same idempotent ledger result),
  /// while a custody record must be applied after the command (so its signed
  /// old/new location boundary is measured against the command's graph
  /// transition).  The envelope event itself still performs the durable
  /// unread/activity/object side effects in journal order.
  private var preappliedReplayOperationEnvelopes: Set<WorldOperationIdentity> = []
  private var pendingReplayCustodyTransitions: [ReplayCustodyTransition] = []
  private var replayedObjectiveAcknowledgements: Set<String> = []
  private var replayedMessengerAcknowledgements: Set<String> = []

  public init(
    document: WorldDocument = WorldDocument(),
    configuration: RuntimeConfiguration = .defaults,
    inventory: InventoryStore? = nil,
    treasuryAuthority: TreasuryAuthorityState? = nil
  ) throws {
    try configuration.validate()
    guard document.schemaVersion == WorldDocument.currentSchemaVersion else {
      throw MikroKhorosError.persistence(
        "unsupported world schema version found \(document.schemaVersion); required \(WorldDocument.currentSchemaVersion)"
      )
    }
    guard !document.worldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      document.worldName.count <= 128,
      !document.worldName.contains(where: \.isNewline)
    else {
      throw MikroKhorosError.runtime(
        "world.name_invalid",
        "world names must be a non-empty single line of at most 128 characters"
      )
    }
    guard document.agents.count <= 10_000, document.events.count <= 1_000_000 else {
      throw MikroKhorosError.persistence("world exceeds the supported record limits")
    }
    let agentIDs = document.agents.map(\.id)
    guard Set(agentIDs).count == agentIDs.count else {
      throw MikroKhorosError.persistence("world contains duplicate agent identities")
    }
    guard document.histories.count <= document.agents.count,
      document.histories.keys.allSatisfy({ agentIDs.contains($0) })
    else {
      throw MikroKhorosError.persistence("world contains history for an unknown agent")
    }
    do {
      let persistenceLimits = RuntimeLimits.persistenceValidation(
        maximumCharacters: configuration.runtime.maximumWorldBytes
      )
      for history in document.histories.values {
        try PromptSafety.validateModelHistory(history, limits: persistenceLimits)
      }
    } catch {
      throw MikroKhorosError.persistence("world contains invalid model history")
    }

    let persistedCredit = document.credit
    let entropy = WorldEntropy()
    self.entropy = entropy
    self.inventoryReferenceOwner = InventoryIdentity.make()
    self.document = document
    self.configuration = configuration
    self.inventory = inventory
    let world = try createWorld(name: document.worldName, hash: document.worldID)
    self.harness = try Harness(
      world: world,
      limits: configuration.runtime,
      runtimeIdentityProvider: { entropy.nextID() },
      runtimeDateProvider: { entropy.nextDate() }
    )
    let creditSnapshotForRuntime: CreditServiceSnapshot?
    if let persistedCredit {
      // The compact snapshot is the final signed chain, not a registration
      // cache. Start replay from an empty derived service and apply that chain
      // as one verified checkpoint below; registration records may be
      // interleaved with later financial operations.
      creditSnapshotForRuntime = CreditServiceSnapshot(
        schemaVersion: persistedCredit.schemaVersion,
        worldID: persistedCredit.worldID,
        authority: persistedCredit.authority,
        chain: []
      )
    } else {
      creditSnapshotForRuntime = nil
    }
    if let treasuryAuthority {
      let authorityState: TreasuryAuthorityState
      if let persistedCredit {
        // JSON date encoding may normalize sub-second creation precision. The
        // cryptographic pin is the authority identity; use the persisted
        // document for verification while retaining the explicitly supplied
        // signer for live mutations.
        let pin = TreasuryAuthorityPin(
          keyID: persistedCredit.authority.keyID,
          publicKey: persistedCredit.authority.publicKey
        )
        guard pin.matches(treasuryAuthority.authority), treasuryAuthority.pinMatches else {
          throw MikroKhorosError.persistence(
            "treasury authority pin does not match the world snapshot")
        }
        authorityState = TreasuryAuthorityState(
          authority: persistedCredit.authority,
          signer: treasuryAuthority.signer,
          pinMatches: true
        )
      } else {
        authorityState = treasuryAuthority
      }
      self.creditService = try CreditService(
        worldID: world.hash,
        snapshot: creditSnapshotForRuntime,
        authority: authorityState.authority,
        authorityState: authorityState
      )
    } else if let snapshot = document.credit {
      // A persisted authority pin is sufficient for deterministic verification;
      // without its matching credential this runtime is deliberately read-only.
      self.creditService = try CreditService(
        worldID: world.hash,
        snapshot: creditSnapshotForRuntime ?? snapshot,
        authority: snapshot.authority
      )
    } else {
      throw MikroKhorosError.runtime(
        "wallet.authority_unavailable",
        "the world has no pinned treasury authority; load or bootstrap one before creating agents"
      )
    }
    // Build the concrete graph before attaching credit. Harness registration
    // uses a canonical location commitment supplied below; attaching the
    // service first would sign registrations with an unverified placeholder
    // and make the persisted graph and ledger disagree.
    try harness.setCreditService(nil)
    for record in document.agents {
      let backpack = try createBackpack(ids: record.genesis)
      let agent = try harness.createAgent(
        name: record.name,
        maximumActionsPerResponse: record.maximumActionsPerResponse,
        hash: record.id,
        backpack: backpack
      )
      if let profile = record.initialProfile {
        try harness.attachProfile(profile, to: agent)
      }
      sessions[agent.hash] = AgentSession(
        harness: harness,
        agent: agent,
        history: document.histories[agent.hash] ?? []
      )
    }
    let locationIndex = try ObjectLocationIndex(
      world: harness.world,
      registeredObjects: harness.objects,
      agents: harness.agents,
      maxDepth: try worldLocationIndexDepth(
        configuration.runtime.maximumObjectInvocationDepth
      )
    )
    var bootstrapCreditRecords: [SignedCreditRecord] = []
    if persistedCredit == nil {
      for agent in harness.agents {
        let before = creditService.chain
        _ = try creditService.register(
          walletID: agent.wallet.hash,
          agentID: agent.hash,
          backpackID: agent.backpack.hash,
          locationCommitment: try locationIndex.locationCommitment(for: agent.wallet.hash),
          actor: .system
        )
        bootstrapCreditRecords.append(
          contentsOf: try creditRecords(after: creditService.chain, comparedTo: before)
        )
      }
    }
    try harness.setCreditService(creditService, registerMissingWallets: false)
    if persistedCredit == nil {
      self.document.credit = creditService.snapshot()
    }
    if persistedCredit == nil {
      for record in bootstrapCreditRecords {
        try appendCreditOperation(
          records: [record],
          actor: CreditActor.system.rawValue
        )
      }
    }
    harness.setWorldReplayMode(true)
    try validatePersistedAgentActionBindings()
    for (index, event) in document.events.enumerated() {
      do { try replay(event) } catch {
        throw MikroKhorosError.persistence(
          "world event \(index + 1) could not be replayed: \(safeReason(error))"
        )
      }
    }
    harness.setWorldReplayMode(false)
    try validatePersistedOperationJournal(expectedCredit: persistedCredit)
    try validateLoadedWorldState()
    harness.setHumanReportHandler { [weak self] object, draft in
      try self?.deliverReport(from: object, draft: draft)
    }
    harness.setObjectStateChangeHandler { [weak self] object in
      guard let self, let stateful = object as? RuntimeAdapterObject else { return }
      self.document.events.append(
        .objectStateChanged(
          objectID: object.hash,
          adapterID: stateful.runtimeAdapterID,
          adapterVersion: stateful.runtimeAdapterVersion,
          state: stateful.runtimeAdapterState,
          instanceRevision: object.instanceRevision,
          durability: object.durability
        )
      )
    }
    harness.setExternalEffectHandler { [weak self] id, object, operation, result, timestamp in
      self?.document.events.append(
        .externalEffectReceipt(
          id: id,
          objectID: object.hash,
          operation: operation,
          result: result,
          timestamp: timestamp
        )
      )
    }
    harness.setHumanMessageHandler { [weak self] agent, message in
      guard let self, !self.harness.isAgentActionOperationActive else { return }
      self.document.events.append(
        .humanMessage(
          agentID: agent.hash,
          id: message.id,
          body: message.body,
          sender: message.sender,
          senderAgentID: message.senderAgentID,
          threadID: message.threadID,
          priority: message.priority,
          timestamp: message.timestamp
        )
      )
    }
    harness.setNestedInvocationHandler {
      [weak self] identity, source, target, function, result in
      self?.document.events.append(
        .nestedInvocationReceipt(
          rootInvocationID: identity.rootInvocationID,
          currentInvocationID: identity.currentInvocationID,
          callingObjectID: source.hash,
          targetObjectID: target.hash,
          originalAgentID: identity.originalAgentID,
          function: function,
          result: result,
          depth: identity.callDepth
        )
      )
    }
    harness.setInventoryRestockHandler { [weak self] item, merchant in
      try self?.prepareAutomaticRestock(for: item, merchant: merchant)
    }
    retainActiveInventoryReferences()
  }

  @discardableResult
  public func createAgent(
    name: String,
    maximumActionsPerResponse: Int? = nil
  ) throws -> Agent {
    let resolvedMaximum =
      maximumActionsPerResponse ?? configuration.agents.maximumActionsPerResponse
    let genesis = AgentGenesisIDs()
    let backpack = try createBackpack(ids: genesis)
    let previousChain = creditService.chain
    try harness.setCreditService(nil)
    let agent: Agent
    do {
      agent = try harness.createAgent(
        name: name,
        maximumActionsPerResponse: resolvedMaximum,
        backpack: backpack
      )
      try registerNewAgentWallet(agent)
      try harness.setCreditService(creditService)
    } catch {
      try? harness.setCreditService(creditService)
      throw error
    }
    document.agents.append(
      WorldAgentRecord(
        id: agent.hash,
        name: name,
        maximumActionsPerResponse: resolvedMaximum,
        genesis: genesis
      )
    )
    sessions[agent.hash] = AgentSession(harness: harness, agent: agent)
    document.credit = creditService.snapshot()
    try appendCreditOperation(
      records: creditRecords(after: creditService.chain, comparedTo: previousChain),
      actor: "system"
    )
    return agent
  }

  /// Registers a user-owned agent identity with this world before placement.
  public func registerAgent(_ source: UserAgentRecord) throws -> Agent {
    if let existing = harness.findAgent(source.id) {
      guard let snapshot = document.agents.first(where: { $0.id == source.id }),
        snapshot.name == source.name, snapshot.genesis == source.genesis
      else {
        throw MikroKhorosError.persistence(
          "the world agent snapshot conflicts with the user agent catalog"
        )
      }
      return existing
    }
    let backpack = try createBackpack(ids: source.genesis)
    let previousChain = creditService.chain
    try harness.setCreditService(nil)
    let agent: Agent
    do {
      agent = try harness.createAgent(
        name: source.name,
        maximumActionsPerResponse: source.maximumActionsPerResponse,
        hash: source.id,
        backpack: backpack
      )
      try registerNewAgentWallet(agent)
      try harness.setCreditService(creditService)
    } catch {
      try? harness.setCreditService(creditService)
      throw error
    }
    if let profile = source.profile {
      try harness.attachProfile(profile, to: agent)
    }
    document.agents.append(
      WorldAgentRecord(
        id: source.id,
        name: source.name,
        maximumActionsPerResponse: source.maximumActionsPerResponse,
        genesis: source.genesis,
        initialProfile: source.profile
      )
    )
    sessions[agent.hash] = AgentSession(harness: harness, agent: agent)
    document.credit = creditService.snapshot()
    try appendCreditOperation(
      records: creditRecords(after: creditService.chain, comparedTo: previousChain),
      actor: "system"
    )
    return agent
  }

  /// Applies current user-level settings after the world journal has replayed.
  public func synchronizeAgent(_ source: UserAgentRecord) throws {
    guard let agent = harness.findAgent(source.id),
      let snapshot = document.agents.first(where: { $0.id == source.id }),
      snapshot.name == source.name, snapshot.genesis == source.genesis
    else {
      throw MikroKhorosError.persistence(
        "the world agent snapshot conflicts with the user agent catalog"
      )
    }
    try harness.setMaximumActionsPerResponse(source.maximumActionsPerResponse, for: agent)
    if let profile = source.profile {
      try harness.attachProfile(profile, to: agent)
    } else {
      harness.detachProfile(from: agent)
    }
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
    let previousChain = creditService.chain
    entropy.beginRecording()
    let operationID = harness.nextRuntimeIdentity()
    let turn = session.run(response, operationID: operationID)
    let generated = entropy.finishRecording()
    let activities = actionActivity(
      operationID: operationID,
      agentID: agent.hash,
      turn: turn
    )
    let actionPairs = turn.results.compactMap { result -> (index: UInt64, command: String)? in
      guard let command = result.command, result.index > 0 else { return nil }
      return (index: UInt64(result.index - 1), command: command)
    }
    let commands = actionPairs.map(\.command)
    let actionIndexes = actionPairs.map(\.index)
    let drained = turn.events.contains { if case .broadcast = $0 { true } else { false } }
    if !commands.isEmpty || drained {
      document.events.append(
        .actions(
          operationID: operationID,
          agentID: agent.hash,
          commands: commands,
          actionIndexes: actionIndexes,
          drainedBroadcasts: drained,
          generatedIDs: generated.ids,
          generatedDates: generated.dates
        )
      )
    }
    document.credit = creditService.snapshot()
    try appendCreditOperation(
      records: creditRecords(after: creditService.chain, comparedTo: previousChain),
      actor: CreditActor.agent.rawValue,
      operationID: operationID,
      activity: activities
    )
    appendActivity(activities)
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

  public func deposit(_ amount: CreditAmount, to wallet: WalletObject) throws {
    // Human administration addresses the exact registered Wallet instance,
    // not its original bearer.  Issuance provenance remains part of the
    // native-identity check, while current custody may be another agent or
    // ownerless after a bearer handoff.
    guard case .wallet = nativeManagedObject(for: wallet) else {
      throw MikroKhorosError.runtime(
        "wallet.management_identity_invalid",
        "the selected wallet is not the exact registered world wallet"
      )
    }
    let previousChain = creditService.chain
    let operationID = CreditService.makeID()
    _ = try creditService.deposit(
      walletID: wallet.hash,
      amount: amount,
      actor: .human,
      operationID: operationID
    )
    document.credit = creditService.snapshot()
    try appendCreditOperation(
      records: creditRecords(after: creditService.chain, comparedTo: previousChain),
      actor: CreditActor.human.rawValue
    )
  }

  public func defaultKhorosFacility(
    _ component: DefaultKhorosComponent
  ) throws -> MikroObject {
    if let facility = optionalDefaultKhorosFacility(component) { return facility }
    throw MikroKhorosError.runtime(
      "world.facility_unavailable",
      "the selected world does not contain the required Default Khoros facility",
      details: ["component": component.rawValue, "world": harness.world.hash],
      suggestions: [
        "run `khoros --world \(harness.world.hash) world template apply default-khoros`"
      ]
    )
  }

  public func optionalDefaultKhorosFacility(
    _ component: DefaultKhorosComponent
  ) -> MikroObject? {
    let applications = document.templateApplications.filter {
      $0.templateID == "default-khoros"
    }
    if applications.count == 1, let application = applications.first {
      let matches =
        harness.world.container?.items.compactMap { item -> MikroObject? in
          guard let template = item.object.lineage?.worldTemplate,
            template.templateID == application.templateID,
            template.templateVersion == application.templateVersion,
            template.applicationID == application.id,
            template.componentKey == component.rawValue
          else { return nil }
          return item.object
        } ?? []
      if matches.count == 1 { return matches[0] }
      return nil
    }
    return nil
  }

  public var objectives: [ObjectiveObject] {
    guard let board = optionalDefaultKhorosFacility(.objectiveBoard) else { return [] }
    return board.container?.items.compactMap { $0.object as? ObjectiveObject } ?? []
  }

  public var libraryDocuments: [LibraryDocumentObject] {
    guard let library = optionalDefaultKhorosFacility(.library) else { return [] }
    return library.container?.items.compactMap { $0.object as? LibraryDocumentObject } ?? []
  }

  public func administrativeWorldSnapshot() -> JSONValue {
    var value = harness.administrativeWorldSnapshot().objectValue ?? [:]
    value["world_name"] = .string(document.worldName)
    value["templates"] = .array(
      document.templateApplications.map { application in
        let active = application.components.filter {
          harness.findObject($0.rootObjectID) != nil
        }.count
        return .object([
          "id": .string(application.templateID),
          "version": .string(application.templateVersion),
          "application_id": .string(application.id),
          "active_components": .number(Double(active)),
          "expected_components": .number(Double(application.components.count)),
          "status": .string(
            active == application.components.count ? "healthy" : "degraded"
          ),
        ])
      }
    )
    return .object(value)
  }

  @discardableResult
  public func postObjective(
    title: String,
    body: String,
    createdAt: Date = Date()
  ) throws -> ObjectiveObject {
    try validateWorldText(title, label: "objective title", allowNewlines: false, name: true)
    try validateWorldText(body, label: "objective body", allowNewlines: true)
    let board = try defaultKhorosFacility(.objectiveBoard)
    guard let space = board.container else {
      throw MikroKhorosError.persistence("the Objective Board has no container capability")
    }
    let objective = try ObjectiveObject(
      title: title,
      body: body,
      createdAt: createdAt,
      origin: board.origin == .package ? .package : .native,
      lineage: board.lineage,
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
      .objectivePostedAt(
        boardID: board.hash,
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

  private func appendReceiptOperation(
    operationID: String,
    kind: String,
    value: String
  ) throws {
    let envelope = WorldOperationEnvelope(
      operationID: operationID,
      worldID: harness.world.hash,
      actor: CreditActor.human.rawValue,
      timestamp: harness.runtimeDate(),
      receipts: [
        WorldOperationReceipt(
          id: "\(operationID)-receipt",
          kind: kind,
          value: value
        )
      ]
    )
    try envelope.validateForPersistence()
    guard
      !document.operations.contains(where: {
        $0.operationID == envelope.operationID && $0.actionIndex == envelope.actionIndex
      })
    else {
      throw MikroKhorosError.persistence("receipt operation identity is already persisted")
    }
    document.operations.append(envelope)
    document.events.append(.operationEnvelope(envelope))
  }

  /// Persist a human acknowledgement of one exact Objective Board event.
  /// This is a receipt only: it never changes objective participation,
  /// scoring, approval, payment, or submission state.
  private func acknowledgeObjectiveEvent(
    board: ObjectiveBoardObject,
    eventID: String
  ) throws -> Bool {
    guard
      let objective = board.container?.items.compactMap({ $0.object as? ObjectiveObject })
        .first(where: { objective in
          objective.hash == eventID
            || objective.objectiveRecords.contains(where: { $0.id == eventID })
        })
    else {
      throw nativeManagementInputError("ack requires an exact objective or submission event id")
    }
    let key = ObjectiveAcknowledgementKey(
      boardID: board.hash,
      objectiveID: objective.hash,
      eventID: eventID
    )
    guard
      !document.events.contains(where: { event in
        if case .objectiveAcknowledged(let boardID, let objectiveID, let acknowledgedID) = event {
          return ObjectiveAcknowledgementKey(
            boardID: boardID,
            objectiveID: objectiveID,
            eventID: acknowledgedID
          ) == key
        }
        return false
      })
    else {
      return false
    }
    document.events.append(
      .objectiveAcknowledged(
        boardID: board.hash,
        objectiveID: objective.hash,
        eventID: eventID
      )
    )
    try appendReceiptOperation(
      operationID: CreditService.makeID(),
      kind: "objective_acknowledgement",
      value: key.receiptValue
    )
    return true
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
    let library = try defaultKhorosFacility(.library)
    guard let space = library.container else {
      throw MikroKhorosError.persistence("the Library has no container capability")
    }
    let documentObject = try LibraryDocumentObject(
      title: title,
      sourceURL: sourceURL,
      content: content,
      fetchedAt: fetchedAt,
      origin: library.origin == .package ? .package : .native,
      lineage: library.lineage,
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
      .libraryDocumentAddedTo(
        libraryID: library.hash,
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

  @discardableResult
  public func deployInventoryObject(
    _ inventoryID: String,
    to destinationQuery: String = "world",
    at requestedCoordinate: Coordinate = .origin,
    autoAdapt: Bool = false,
    restockRuleID: String? = nil,
    pickupLock: ObjectLock? = nil
  ) throws -> ObjectDeploymentRecord {
    let prepared = try prepareDeployment(
      inventoryID,
      destinationQuery: destinationQuery,
      requestedCoordinate: requestedCoordinate,
      autoAdapt: autoAdapt,
      restockRuleID: restockRuleID,
      pickupLock: pickupLock
    )
    try harness.place(
      prepared.object,
      at: prepared.record.actualCoordinate,
      in: prepared.space
    )
    let record = prepared.record
    document.events.append(.objectDeployed(record: record))
    retainActiveInventoryReferences()
    return record
  }

  @discardableResult
  public func applyWorldTemplate(
    _ plan: WorldTemplatePlan
  ) throws -> WorldTemplateRuntimeApplyResult {
    guard plan.worldID == harness.world.hash else {
      throw MikroKhorosError.runtime(
        "world_template.plan_stale",
        "the world-template plan targets a different world"
      )
    }
    guard plan.collisions.isEmpty else {
      throw MikroKhorosError.runtime(
        "world_template.placement_conflict",
        "one or more template coordinates contain unrelated world content",
        details: [
          "positions": plan.collisions.map { $0.definition.coordinate.description }
            .joined(separator: ",")
        ],
        suggestions: ["move the occupants or apply again with `--auto-adapt`"]
      )
    }
    let existingApplication = document.templateApplications.first {
      $0.id == plan.applicationID
    }
    if let existingApplication {
      guard existingApplication.templateID == plan.definition.id,
        existingApplication.templateVersion == plan.definition.version,
        existingApplication.templateContentHash == plan.definition.contentHash
      else {
        throw MikroKhorosError.runtime(
          "world_template.application_corrupt",
          "the stored template application does not match the registered template"
        )
      }
    }

    var prepared: [(record: ObjectDeploymentRecord, object: MikroObject, space: Space)] = []
    var reserved = Set<Coordinate>()
    for component in plan.components where component.requiresDeployment {
      guard let inventoryObjectID = component.inventoryObjectID else {
        throw MikroKhorosError.runtime(
          "world_template.source_missing",
          "a template component has no canonical Inventory source",
          details: ["component": component.definition.key]
        )
      }
      let lineage = WorldTemplateComponentLineage(
        templateID: plan.definition.id,
        templateVersion: plan.definition.version,
        applicationID: plan.applicationID,
        componentKey: component.definition.key
      )
      let deployment = try prepareDeployment(
        inventoryObjectID,
        destinationQuery: "world",
        requestedCoordinate: component.definition.coordinate,
        autoAdapt: component.actualCoordinate != component.definition.coordinate,
        restockRuleID: nil,
        pickupLock: nil,
        worldTemplate: lineage,
        templatePickupLockReason: component.definition.pickupLockReason,
        reservedCoordinates: reserved
      )
      guard deployment.record.actualCoordinate == component.actualCoordinate else {
        throw MikroKhorosError.runtime(
          "world_template.plan_stale",
          "world occupancy changed after the template plan was prepared",
          suggestions: ["run the command again to compute a current plan"]
        )
      }
      prepared.append(deployment)
      reserved.insert(deployment.record.actualCoordinate)
    }

    if prepared.isEmpty, let existingApplication {
      return WorldTemplateRuntimeApplyResult(
        application: existingApplication,
        deployedObjectIDs: [],
        repaired: false
      )
    }

    var placed: [MikroObject] = []
    do {
      for deployment in prepared {
        try harness.place(
          deployment.object,
          at: deployment.record.actualCoordinate,
          in: deployment.space
        )
        placed.append(deployment.object)
      }
    } catch {
      for object in placed.reversed() { try? harness.removeObject(object) }
      throw error
    }

    let newDeployments = prepared.map(\.record)
    let application: WorldTemplateApplicationRecord
    let repaired = existingApplication != nil
    if let existingApplication {
      let repair = WorldTemplateRepairRecord(
        applicationID: existingApplication.id,
        deployments: newDeployments,
        repairedAt: harness.runtimeDate()
      )
      document.events.append(.worldTemplateComponentsRepaired(record: repair))
      application = WorldTemplateApplicationRecord(
        id: existingApplication.id,
        templateID: existingApplication.templateID,
        templateVersion: existingApplication.templateVersion,
        templateContentHash: existingApplication.templateContentHash,
        appliedAt: existingApplication.appliedAt,
        deployments: existingApplication.deployments + newDeployments,
        inactiveRootObjectIDs: existingApplication.inactiveRootObjectIDs
      )
      if let index = document.templateApplications.firstIndex(where: {
        $0.id == existingApplication.id
      }) {
        document.templateApplications[index] = application
      }
    } else {
      application = WorldTemplateApplicationRecord(
        id: plan.applicationID,
        definition: plan.definition,
        deployments: newDeployments,
        appliedAt: harness.runtimeDate()
      )
      document.templateApplications.append(application)
      document.events.append(.worldTemplateApplied(record: application))
    }
    retainActiveInventoryReferences()
    if !newDeployments.isEmpty, !harness.activeAgents.isEmpty {
      try announceThroughAthena(
        repaired
          ? "The default-khoros facilities were repaired."
          : "The default-khoros facilities are now available."
      )
    }
    return WorldTemplateRuntimeApplyResult(
      application: application,
      deployedObjectIDs: newDeployments.map(\.snapshot.objectID),
      repaired: repaired
    )
  }

  public var activeInventoryArtifactReferences: WorldArtifactReferences {
    let objects = harness.objects.filter { $0.lineage != nil }
    return WorldArtifactReferences(
      credentialHandles: Set(objects.flatMap { $0.deploymentCredentialHandles.values }),
      packageHashes: Set(objects.compactMap { $0.lineage?.packageHash })
    )
  }

  public func validateInventoryArtifacts() throws {
    let packagedObjects = harness.objects.filter { $0.lineage != nil }
    guard packagedObjects.isEmpty || inventory != nil else {
      throw MikroKhorosError.persistence("world package artifacts require an Inventory store")
    }
    if let inventory {
      for object in packagedObjects {
        guard let lineage = object.lineage else { continue }
        let package = try inventory.package(contentHash: lineage.packageHash)
        guard package.manifest.id == lineage.packageID,
          package.manifest.version == lineage.packageVersion,
          object.deploymentCredentialHandles.values.allSatisfy(
            inventory.credentialStore.contains(handle:)
          )
        else {
          throw MikroKhorosError.persistence(
            "a deployed object has unavailable package or credential artifacts"
          )
        }
      }
      for rule in restockRules.values {
        _ = try inventory.resolve(rule.inventoryObjectID)
        guard (try? MerchantObject.creditAmount(for: rule.price)) != nil,
          harness.findObject(rule.merchantID) is MerchantObject,
          rule.createdObjects.allSatisfy({
            InventoryIdentity.isValid($0.objectID)
              && (try? MerchantObject.creditAmount(for: $0.price)) != nil
          })
        else {
          throw MikroKhorosError.persistence("world contains an invalid restock rule")
        }
      }
    }
  }

  /// Validates trusted template metadata, replay ordering, concrete lineage, and
  /// canonical Inventory provenance. Missing deleted components or sources are
  /// returned as repairable diagnostics; contradictory identities are rejected.
  public func validateWorldTemplates(
    catalog: WorldTemplateCatalog = .installedCLI()
  ) throws -> [String] {
    guard
      Set(document.templateApplications.map(\.id)).count
        == document.templateApplications.count,
      Set(document.templateApplications.map(\.templateID)).count
        == document.templateApplications.count
    else {
      throw MikroKhorosError.runtime(
        "world_template.application_corrupt",
        "the world contains duplicate world-template applications"
      )
    }

    var warnings: [String] = []
    var deploymentIDs = Set<String>()
    var concreteIDs = Set<String>()
    var applicationsSeen = Set<String>()
    var objectiveBoardsSeen = Set<String>()
    var librariesSeen = Set<String>()
    var athenasSeen = Set<String>()
    let storedApplications = Dictionary(
      uniqueKeysWithValues: document.templateApplications.map { ($0.id, $0) }
    )

    func validateDeployments(
      _ deployments: [ObjectDeploymentRecord],
      applicationID: String,
      definition: WorldTemplateDefinition
    ) throws {
      for deployment in deployments {
        guard deployment.destinationObjectID == harness.world.hash,
          deployment.adapted
            == (deployment.requestedCoordinate != deployment.actualCoordinate),
          deploymentIDs.insert(deployment.snapshot.lineage.deploymentID).inserted,
          concreteIDs.insert(deployment.snapshot.objectID).inserted,
          deployment.snapshot.ownedObjects.allSatisfy({
            concreteIDs.insert($0.objectID).inserted
          }),
          let template = deployment.snapshot.lineage.worldTemplate,
          template.templateID == definition.id,
          template.templateVersion == definition.version,
          template.applicationID == applicationID,
          let component = definition.components.first(where: {
            $0.key == template.componentKey
          }),
          component.packageID == deployment.snapshot.lineage.packageID,
          component.packageVersion == deployment.snapshot.lineage.packageVersion,
          component.ownedObjectKeys == deployment.snapshot.ownedObjects.map(\.localID),
          deployment.snapshot.pickupLock?.reason == component.pickupLockReason
        else {
          throw MikroKhorosError.runtime(
            "world_template.component_invalid",
            "a stored world-template deployment is invalid"
          )
        }
        switch template.componentKey {
        case DefaultKhorosComponent.athena.rawValue:
          athenasSeen.insert(deployment.snapshot.objectID)
        case DefaultKhorosComponent.objectiveBoard.rawValue:
          objectiveBoardsSeen.insert(deployment.snapshot.objectID)
        case DefaultKhorosComponent.library.rawValue:
          librariesSeen.insert(deployment.snapshot.objectID)
        default:
          break
        }
      }
    }

    for event in document.events {
      switch event {
      case .worldTemplateApplied(let record):
        guard let stored = storedApplications[record.id],
          applicationsSeen.insert(record.id).inserted,
          stored.templateID == record.templateID,
          stored.templateVersion == record.templateVersion,
          stored.templateContentHash == record.templateContentHash,
          stored.appliedAt == record.appliedAt,
          stored.deployments.starts(with: record.deployments)
        else {
          throw MikroKhorosError.runtime(
            "world_template.application_corrupt",
            "a world-template application event is inconsistent"
          )
        }
        let definition = try catalog.resolve(record.templateID)
        guard definition.version == record.templateVersion,
          definition.contentHash == record.templateContentHash
        else {
          throw MikroKhorosError.runtime(
            "world_template.application_corrupt",
            "an applied world template does not match the trusted catalog"
          )
        }
        try validateDeployments(
          record.deployments,
          applicationID: record.id,
          definition: definition
        )
      case .worldTemplateComponentsRepaired(let record):
        guard applicationsSeen.contains(record.applicationID),
          let stored = storedApplications[record.applicationID]
        else {
          throw MikroKhorosError.runtime(
            "world_template.application_corrupt",
            "a world-template repair precedes its application"
          )
        }
        let definition = try catalog.resolve(stored.templateID)
        try validateDeployments(
          record.deployments,
          applicationID: record.applicationID,
          definition: definition
        )
      case .objectivePostedAt(let boardID, _, _, _, _, _):
        guard objectiveBoardsSeen.contains(boardID) else {
          throw MikroKhorosError.runtime(
            "world_template.application_corrupt",
            "an objective event references an unavailable Objective Board"
          )
        }
      case .libraryDocumentAddedTo(let libraryID, _, _, _, _, _, _):
        guard librariesSeen.contains(libraryID) else {
          throw MikroKhorosError.runtime(
            "world_template.application_corrupt",
            "a Library event references an unavailable Library"
          )
        }
      case .athenaNoticeFrom(let athenaID, _):
        guard athenasSeen.contains(athenaID) else {
          throw MikroKhorosError.runtime(
            "world_template.application_corrupt",
            "an Athena notice references an unavailable Athena component"
          )
        }
      default:
        break
      }
    }
    guard applicationsSeen == Set(storedApplications.keys) else {
      throw MikroKhorosError.runtime(
        "world_template.application_corrupt",
        "a stored world-template application has no application event"
      )
    }

    for application in document.templateApplications {
      let definition = try catalog.resolve(application.templateID)
      let knownRoots = Set(application.deployments.map(\.snapshot.objectID))
      guard application.templateVersion == definition.version,
        application.templateContentHash == definition.contentHash,
        (application.inactiveRootObjectIDs ?? []).isSubset(of: knownRoots),
        (application.inactiveRootObjectIDs ?? []).allSatisfy({
          harness.findObject($0) == nil
        }),
        Set(application.components.map(\.componentKey))
          == Set(definition.components.map(\.key))
      else {
        throw MikroKhorosError.runtime(
          "world_template.application_corrupt",
          "a world-template application is incomplete or has unknown metadata"
        )
      }
      for component in application.components {
        guard
          let componentDefinition = definition.components.first(where: {
            $0.key == component.componentKey
          }),
          let deployment = application.deployments.last(where: {
            $0.snapshot.objectID == component.rootObjectID
          })
        else {
          throw MikroKhorosError.runtime(
            "world_template.component_invalid",
            "a world-template component has no deployment snapshot"
          )
        }
        if let inventory {
          guard
            let source = inventory.allInventoryObjects(includeDeleted: true).first(where: {
              $0.id == component.inventoryObjectID
            }),
            source.templateSource?.templateID == definition.id,
            source.templateSource?.templateVersion == definition.version,
            source.templateSource?.componentKey == component.componentKey
          else {
            throw MikroKhorosError.runtime(
              "world_template.source_missing",
              "a world-template component has no retained canonical source",
              details: ["component": component.componentKey]
            )
          }
          if source.deleted {
            warnings.append(
              "canonical source for \(component.componentKey) is deleted and can be recreated"
            )
          }
        }
        guard component.active,
          let object = harness.findObject(component.rootObjectID)
        else {
          warnings.append(
            "component \(component.componentKey) is absent and requires template repair"
          )
          continue
        }
        guard object.parentSpace === harness.world.container,
          object.lineage == deployment.snapshot.lineage,
          object.lineage?.packageID == componentDefinition.packageID,
          object.lockInfo?.reason == componentDefinition.pickupLockReason,
          component.ownedObjectIDs.allSatisfy({ childID in
            guard let child = harness.findObject(childID) else { return false }
            return child.parentSpace === object.container
              && child.lineage == object.lineage
              && child.lockInfo != nil
          })
        else {
          throw MikroKhorosError.runtime(
            "world_template.component_invalid",
            "a live world-template component does not match its deployment snapshot",
            details: ["component": component.componentKey]
          )
        }
      }
    }
    return warnings.sorted()
  }

  /// Shared human-management description consumed by the CLI and future UI.
  public func managementInterface(for inventoryQuery: String) throws -> JSONValue {
    guard let inventory else {
      throw MikroKhorosError.runtime(
        "inventory.store_unavailable",
        "this world runtime has no Inventory store"
      )
    }
    let object = try inventory.resolve(inventoryQuery)
    let package = try inventory.package(contentHash: object.packageHash)
    let readiness = try inventory.readiness(of: object)
    let copies = copies(inventoryID: object.id)
    let rules = restockRules.values.filter { $0.inventoryObjectID == object.id }
      .sorted { $0.id < $1.id }
    let listened = copies.filter { listeners.contains($0.hash) }
    let recentReports = reports.filter { $0.inventoryObjectID == object.id }.suffix(20)
    let encoded = try JSONEncoder().encode(package.manifest.management)
    let objectInterface = try JSONDecoder().decode(JSONValue.self, from: encoded)
    let fork: JSONValue =
      object.forkProvenance.map { provenance in
        .object([
          "parent_inventory_object_id": .string(provenance.parentInventoryObjectID),
          "parent_revision": .number(Double(provenance.parentRevision)),
          "forked_at": .string(ISO8601DateFormatter().string(from: provenance.forkedAt)),
        ])
      } ?? .null
    let identity: JSONValue = .object([
      "inventory_object_id": .string(object.id),
      "name": .string(object.name),
      "revision": .number(Double(object.revision)),
      "deleted": .bool(object.deleted),
      "folder_id": .string(object.folderID),
      "folder_path": .string(inventory.folderPath(for: object.folderID)),
      "world_binding": object.worldBinding.map { .string($0.worldID) } ?? .null,
      "fork": fork,
    ])
    let packageIdentity: JSONValue = .object([
      "id": .string(package.manifest.id),
      "version": .string(package.manifest.version),
      "content_hash": .string(package.contentHash),
      "runtime": .string(package.manifest.runtime.rawValue),
    ])
    let readinessValue: JSONValue = .object([
      "ready": .bool(readiness.ready),
      "missing_configuration": .array(readiness.missingConfiguration.map(JSONValue.string)),
      "missing_credentials": .array(readiness.missingCredentials.map(JSONValue.string)),
      "missing_capabilities": .array(
        readiness.missingCapabilities.map(\.rawValue).map(JSONValue.string)
      ),
    ])
    let recentReportValues: [JSONValue] = recentReports.map { report in
      .object([
        "id": .string(report.id),
        "object_id": .string(report.objectID),
        "type": .string(report.type),
        "title": .string(report.title),
        "timestamp": .string(ISO8601DateFormatter().string(from: report.timestamp)),
      ])
    }
    let selectedWorld: JSONValue = .object([
      "deployments": .array(
        Set(copies.compactMap { $0.lineage?.deploymentID }).sorted().map(JSONValue.string)
      ),
      "world_objects": .array(copies.map { .string($0.hash) }),
      "restock_rules": .array(rules.map { .string($0.id) }),
      "listeners": .array(listened.map { .string($0.hash) }),
      "recent_reports": .array(recentReportValues),
    ])
    let controls: JSONValue = .array([
      .object(["id": .string("configure"), "mutating": .bool(true)]),
      .object(["id": .string("deploy"), "mutating": .bool(true)]),
      .object(["id": .string("inspect"), "mutating": .bool(false)]),
      .object(["id": .string("delete"), "mutating": .bool(true)]),
    ])
    let base: JSONValue = .object([
      "identity": identity,
      "package": packageIdentity,
      "readiness": readinessValue,
      "selected_world": selectedWorld,
      "controls": controls,
    ])
    return .object(["base": base, "object": objectInterface])
  }

  public func concreteObjects(
    containerID: String? = nil,
    type: String? = nil,
    packageID: String? = nil,
    inventoryID: String? = nil,
    deploymentID: String? = nil
  ) -> [MikroObject] {
    harness.objects.filter { object in
      object !== harness.world
        && (containerID == nil || object.parentSpace?.owner.hash == containerID)
        && (type == nil || object.typeName == type)
        && (packageID == nil || object.lineage?.packageID == packageID)
        && (inventoryID == nil || object.lineage?.inventoryObjectID == inventoryID)
        && (deploymentID == nil || object.lineage?.deploymentID == deploymentID)
    }
  }

  public func exactWorldObject(_ query: String) throws -> MikroObject {
    let object = try HumanSelectorResolver.resolve(
      query,
      among: harness.objects.filter { $0 !== harness.world },
      id: \.hash,
      name: { $0.name },
      kind: "world object",
      listCommand: "khoros world object list"
    ).value
    try (object as? LiveWorldObject)?.prepareForInteraction(harness: harness)
    return object
  }

  public func resolveDeploymentID(_ query: String, inventoryID: String? = nil) throws -> String {
    let identities = Array(
      Set(
        harness.objects.compactMap { object -> String? in
          guard let lineage = object.lineage,
            inventoryID == nil || lineage.inventoryObjectID == inventoryID
          else { return nil }
          return lineage.deploymentID
        })
    ).sorted()
    return try HumanSelectorResolver.resolve(
      query,
      among: identities,
      id: { $0 },
      kind: "deployment",
      listCommand: inventoryID == nil
        ? "khoros world object list" : "khoros inventory copies list \(inventoryID!)"
    ).value
  }

  public func worldManagementInterface(for objectID: String) throws -> JSONValue {
    let object = try exactWorldObject(objectID)
    if let native = try nativeManagementInterface(for: object) {
      let encoded = try JSONEncoder().encode(native)
      let contract = try JSONDecoder().decode(JSONValue.self, from: encoded)
      return .object(["base": worldObjectBaseInterface(object), "object": contract])
    }
    guard let lineage = object.lineage, let inventory else {
      return .object([
        "base": worldObjectBaseInterface(object),
        "object": .object(["actions": .array([]), "views": .array([])]),
      ])
    }
    let package = try inventory.package(contentHash: lineage.packageHash)
    let encoded = try JSONEncoder().encode(package.manifest.management)
    let contract = try JSONDecoder().decode(JSONValue.self, from: encoded)
    return .object(["base": worldObjectBaseInterface(object), "object": contract])
  }

  @discardableResult
  public func runWorldManagementAction(
    objectID: String,
    actionID: String,
    inputs: [String]
  ) throws -> JSONValue {
    let object = try exactWorldObject(objectID)
    if let result = try runNativeManagementAction(actionID, inputs: inputs, on: object) {
      return result
    }
    guard let lineage = object.lineage, let inventory else {
      throw MikroKhorosError.runtime(
        "object.management_unavailable",
        "the selected object has no package-defined management interface"
      )
    }
    let package = try inventory.package(contentHash: lineage.packageHash)
    guard let action = package.manifest.management.actions.first(where: { $0.id == actionID })
    else {
      throw MikroKhorosError.runtime(
        "object.management_action_unknown",
        "the package does not declare this world-object action"
      )
    }
    guard action.scope.acceptsWorld else {
      throw MikroKhorosError.runtime(
        "object.management_scope_denied",
        "this management action is available only on its Inventory source"
      )
    }
    guard inputs.count == action.parameters.count else {
      throw MikroKhorosError.runtime(
        "object.management_input_invalid", "the world-object action received the wrong inputs")
    }
    for (index, parameter) in action.parameters.enumerated() {
      try validateWorldManagementInput(
        inputs[index],
        type: action.inputTypes[parameter] ?? .text,
        choices: action.inputChoices[parameter] ?? [],
        maximumCharacters: configuration.runtime.maximumModelFieldCharacters,
        parameter: parameter
      )
    }
    let broker = ObjectCapabilityBroker(granted: object.capturedCapabilities)
    for capability in action.requiredCapabilities { try broker.require(capability) }
    guard package.manifest.runtime == .nativeSwift else {
      throw MikroKhorosError.runtime(
        "object.management_runtime_unavailable",
        "this runtime does not provide concrete-instance management actions"
      )
    }
    let startingRevision = object.instanceRevision
    let managementContext = try WorldObjectManagementContext(object: object, harness: harness)
    let output = try inventory.runtimeRegistry.adapter(for: package.manifest).runWorldAction(
      action,
      inputs: inputs,
      context: managementContext,
      limits: configuration.runtime
    )
    if action.mutating, object.instanceRevision == startingRevision {
      object.advanceInstanceRevision()
      try harness.notifyObjectStateChanged(object)
    }
    return output
  }

  public func renderWorldManagementView(objectID: String, viewID: String) throws -> JSONValue {
    let object = try exactWorldObject(objectID)
    if let result = try renderNativeManagementView(viewID, on: object) {
      return result
    }
    guard let lineage = object.lineage, let inventory else {
      throw MikroKhorosError.runtime(
        "object.management_unavailable", "the selected object has no package-defined views")
    }
    let package = try inventory.package(contentHash: lineage.packageHash)
    guard let view = package.manifest.management.views.first(where: { $0.id == viewID }) else {
      throw MikroKhorosError.runtime(
        "object.management_view_unknown", "the package does not declare this world-object view")
    }
    guard view.scope.acceptsWorld else {
      throw MikroKhorosError.runtime(
        "object.management_scope_denied", "this view is available only on its Inventory source")
    }
    guard package.manifest.runtime == .nativeSwift else {
      throw MikroKhorosError.runtime(
        "object.management_runtime_unavailable",
        "this runtime does not provide concrete-instance management views"
      )
    }
    let managementContext = try WorldObjectManagementContext(object: object, harness: harness)
    return try inventory.runtimeRegistry.adapter(for: package.manifest).renderWorldView(
      view, context: managementContext, limits: configuration.runtime)
  }

  @discardableResult
  public func moveWorldObject(
    objectID: String,
    to destinationQuery: String,
    at requestedCoordinate: Coordinate = .origin,
    autoAdapt: Bool = false
  ) throws -> Coordinate {
    let object = try exactWorldObject(objectID)
    guard !(object is AnchoredWorldObject) else {
      throw MikroKhorosError.runtime(
        "object.anchored",
        "the projected filesystem object is anchored to its user-workspace projection"
      )
    }
    let destination = try resolveDeploymentDestination(destinationQuery)
    guard let space = destination.container else {
      throw MikroKhorosError.runtime(
        "object.destination_not_container", "the selected destination is not a container")
    }
    let actual: Coordinate
    if deploymentCoordinateIsAvailable(requestedCoordinate, in: space, reserved: []) {
      actual = requestedCoordinate
    } else if autoAdapt {
      actual = nearestDeploymentCoordinate(in: space, around: requestedCoordinate, reserved: [])
    } else {
      throw MikroKhorosError.runtime(
        "placement.occupied", "the requested destination coordinate is occupied",
        suggestions: ["choose another coordinate or enable auto-adapt placement"])
    }
    let previousChain = creditService.chain
    try harness.moveObject(object, to: actual, in: space)
    let revision = object.advanceInstanceRevision()
    document.events.append(
      .objectMoved(
        objectID: object.hash,
        destinationObjectID: destination.hash,
        coordinate: actual,
        instanceRevision: revision
      )
    )
    document.credit = creditService.snapshot()
    try appendCreditOperation(
      records: creditRecords(after: creditService.chain, comparedTo: previousChain),
      actor: CreditActor.system.rawValue
    )
    return actual
  }

  public func copies(
    inventoryID: String,
    deploymentID: String? = nil,
    listenedOnly: Bool = false
  ) -> [MikroObject] {
    harness.objects.filter { object in
      guard let lineage = object.lineage,
        lineage.inventoryObjectID == inventoryID,
        deploymentID == nil || lineage.deploymentID == deploymentID
      else { return false }
      return !listenedOnly || listeners.contains(object.hash)
    }.sorted { $0.hash < $1.hash }
  }

  public func previewCopyDeletion(
    inventoryID: String,
    scope: WorldCopyDeleteScope,
    recursive: Bool = false
  ) throws -> WorldCopyDeletionPreview {
    let descendants = copies(inventoryID: inventoryID)
    let selected: [MikroObject]
    switch scope {
    case .all:
      selected = descendants
    case .deployments(let deploymentIDs):
      guard !deploymentIDs.isEmpty else {
        throw MikroKhorosError.command("at least one deployment id is required")
      }
      selected = descendants.filter {
        $0.lineage.map { deploymentIDs.contains($0.deploymentID) } == true
      }
    case .objects(let objectIDs):
      guard !objectIDs.isEmpty else {
        throw MikroKhorosError.command("at least one concrete object id is required")
      }
      selected = try objectIDs.map { query in
        let object = try harness.resolveObject(query)
        guard object.lineage?.inventoryObjectID == inventoryID else {
          throw MikroKhorosError.runtime(
            "inventory.copy_scope_mismatch",
            "the selected world object does not descend from this Inventory object",
            details: ["object": object.hash]
          )
        }
        return object
      }
    }
    guard !selected.isEmpty else {
      throw MikroKhorosError.runtime(
        "inventory.copy_not_found",
        "the delete scope resolves to no concrete world objects"
      )
    }
    let selectedIDs = Set(selected.map(\.hash))
    let roots = selected.filter { object in
      var parent = object.parentSpace?.owner
      while let value = parent {
        if selectedIDs.contains(value.hash) { return false }
        parent = value.parentSpace?.owner
      }
      return true
    }
    for object in roots where !recursive && !(object.container?.items.isEmpty ?? true) {
      throw MikroKhorosError.runtime(
        "inventory.copy_container_not_empty",
        "a selected container is not empty",
        details: ["object": object.hash],
        suggestions: ["preview the deletion again with recursive deletion enabled"]
      )
    }
    let affected =
      recursive
      ? roots.flatMap { [$0] + $0.walkContents() }
      : roots
    return WorldCopyDeletionPreview(
      rootObjectIDs: roots.map(\.hash),
      affectedObjectIDs: Array(Set(affected.map(\.hash)))
    )
  }

  /// Validate the complete deletion set before the first mutation.  Harness
  /// `removeObject` has the same lifecycle guards, but checking only the root
  /// lets an earlier root be deleted before a later root's nested Wallet is
  /// rejected.  Treat this as the transaction's prepare phase: all concrete
  /// identities, registrations, and active-agent boundaries are checked for
  /// every root/subtree before prices, listeners, template flags, events, or
  /// the object registry are changed.
  private func preflightCopyDeletion(
    inventoryID: String,
    preview: WorldCopyDeletionPreview,
    recursive: Bool
  ) throws -> [MikroObject] {
    var roots: [MikroObject] = []
    var visited = Set<String>()
    let expectedAffected = Set(preview.affectedObjectIDs)

    for rootID in preview.rootObjectIDs {
      guard let root = harness.findObject(rootID),
        root.lineage?.inventoryObjectID == inventoryID
      else {
        throw MikroKhorosError.runtime(
          "inventory.copy_changed",
          "the resolved deletion targets changed before commit",
          suggestions: ["run the deletion preview again"]
        )
      }

      let members = recursive ? [root] + root.walkContents() : [root]
      for member in members {
        guard visited.insert(member.hash).inserted,
          harness.findObject(member.hash) === member
        else {
          throw MikroKhorosError.runtime(
            "inventory.copy_changed",
            "the resolved deletion targets changed before commit",
            suggestions: ["run the deletion preview again"]
          )
        }

        // A genesis Wallet is a live lifecycle attachment and a registered
        // Wallet remains protected even after its bearer has handed it off or
        // left it ownerless.  Check exact object identity, never a type/name
        // proxy, so a same-shaped unregistered object is still deletable.
        if creditService.registration(for: member.hash) != nil {
          guard member is WalletObject else {
            throw MikroKhorosError.runtime(
              "inventory.copy_changed",
              "a registered wallet identity was replaced in the deletion target",
              details: ["object": member.hash]
            )
          }
          throw MikroKhorosError.runtime(
            "inventory.copy_in_use",
            "a selected object contains a registered Wallet",
            details: ["object": root.hash]
          )
        }
        if let wallet = member as? WalletObject,
          harness.agents.contains(where: { $0.wallet === wallet })
        {
          throw MikroKhorosError.runtime(
            "inventory.copy_in_use",
            "a selected object contains an active Wallet attachment",
            details: ["object": root.hash]
          )
        }

        guard !harness.agents.contains(where: { $0.backpack === member }) else {
          throw MikroKhorosError.runtime(
            "inventory.copy_in_use",
            "a selected object is an agent lifecycle attachment",
            details: ["object": root.hash]
          )
        }
      }

      if root.container != nil,
        harness.activeAgents.contains(where: { $0.space.isInside(root) })
      {
        throw MikroKhorosError.runtime(
          "inventory.copy_in_use",
          "a selected container contains an active agent",
          details: ["object": root.hash]
        )
      }
      roots.append(root)
    }

    guard visited == expectedAffected else {
      throw MikroKhorosError.runtime(
        "inventory.copy_changed",
        "the resolved deletion targets changed before commit",
        suggestions: ["run the deletion preview again"]
      )
    }
    return roots
  }

  @discardableResult
  public func deleteCopies(
    inventoryID: String,
    scope: WorldCopyDeleteScope,
    recursive: Bool = false
  ) throws -> WorldCopyDeletionPreview {
    let preview = try previewCopyDeletion(
      inventoryID: inventoryID,
      scope: scope,
      recursive: recursive
    )
    let roots = try preflightCopyDeletion(
      inventoryID: inventoryID,
      preview: preview,
      recursive: recursive
    )

    // Commit only after every root has passed the complete preflight above.
    // `Harness.removeObject` repeats these guards; with the world isolated to
    // this synchronous mutation, no fallible work remains between roots and
    // therefore a later protected subtree cannot leave an earlier root
    // partially deleted.
    removeMerchantPrices(for: Set(preview.affectedObjectIDs))
    for object in roots { try harness.removeObject(object) }
    listeners.subtract(preview.affectedObjectIDs)
    let deletedRootIDs = Set(preview.rootObjectIDs)
    for index in document.templateApplications.indices {
      document.templateApplications[index].markInactive(rootObjectIDs: deletedRootIDs)
    }
    document.events.append(.objectsDeleted(objectIDs: preview.rootObjectIDs))
    retainActiveInventoryReferences()
    return preview
  }

  public func setListener(_ enabled: Bool, objectQuery: String) throws {
    let object = try harness.resolveObject(objectQuery)
    guard object.lineage != nil else {
      throw MikroKhorosError.runtime(
        "inventory.listener_requires_copy",
        "listeners can be enabled only for Inventory-backed world objects"
      )
    }
    if enabled { listeners.insert(object.hash) } else { listeners.remove(object.hash) }
    document.events.append(.listenerChanged(objectID: object.hash, enabled: enabled))
  }

  public func resolveReport(_ query: String) throws -> ObjectReport {
    try HumanSelectorResolver.resolve(
      query,
      among: reports,
      id: \.id,
      kind: "object report",
      listCommand: "khoros inventory reports list"
    ).value
  }

  @discardableResult
  public func createRestockRule(
    inventoryID: String,
    merchantQuery: String,
    price: Decimal,
    at coordinate: Coordinate = .origin,
    autoAdapt: Bool = true
  ) throws -> RestockRule {
    try validateRestockPrice(price)
    guard let merchant = try harness.resolveObject(merchantQuery) as? MerchantObject else {
      throw MikroKhorosError.runtime(
        "inventory.restock_merchant_invalid",
        "the selected object is not a merchant"
      )
    }
    let shop = try harness.object(byHash: merchant.shopHash)
    guard shop.container != nil else {
      throw MikroKhorosError.persistence("the merchant shop has no container capability")
    }
    var rule = RestockRule(
      inventoryObjectID: try inventory?.resolve(inventoryID).id ?? inventoryID,
      merchantID: merchant.hash,
      price: price,
      requestedCoordinate: coordinate,
      autoAdapt: autoAdapt
    )
    let stock = try deployInventoryObject(
      rule.inventoryObjectID,
      to: shop.hash,
      at: coordinate,
      autoAdapt: autoAdapt,
      restockRuleID: rule.id,
      pickupLock: ObjectLock(
        authority: .system,
        owner: merchant.hash,
        reason: "shop_inventory"
      )
    )
    try merchant.addPrice(price, for: stock.snapshot.objectID)
    rule.createdObjects.append(
      RestockStockRecord(objectID: stock.snapshot.objectID, price: price)
    )
    restockRules[rule.id] = rule
    document.events.append(.restockRuleCreated(rule: rule))
    return rule
  }

  public func resolveRestockRule(_ query: String) throws -> RestockRule {
    try HumanSelectorResolver.resolve(
      query,
      among: Array(restockRules.values),
      id: \.id,
      kind: "restock rule",
      listCommand: "khoros inventory restock list"
    ).value
  }

  @discardableResult
  public func runRestockRule(_ query: String, count: Int = 1) throws -> RestockRule {
    guard count > 0 else {
      throw MikroKhorosError.runtime(
        "inventory.restock_count_invalid",
        "restock count must be a positive integer"
      )
    }
    var rule = try resolveRestockRule(query)
    guard rule.enabled else {
      throw MikroKhorosError.runtime(
        "inventory.restock_rule_disabled",
        "the restock rule is disabled"
      )
    }
    guard let merchant = harness.findObject(rule.merchantID) as? MerchantObject else {
      throw MikroKhorosError.runtime(
        "inventory.restock_merchant_missing",
        "the restock rule's merchant is unavailable"
      )
    }
    let shop = try harness.object(byHash: merchant.shopHash)
    guard let space = shop.container else {
      throw MikroKhorosError.persistence("the merchant shop has no container capability")
    }
    var reserved: Set<Coordinate> = []
    var prepared: [(record: ObjectDeploymentRecord, object: MikroObject, space: Space)] = []
    for _ in 0..<count {
      let stock = try prepareDeployment(
        rule.inventoryObjectID,
        destinationQuery: shop.hash,
        requestedCoordinate: rule.requestedCoordinate,
        autoAdapt: rule.autoAdapt,
        restockRuleID: rule.id,
        pickupLock: ObjectLock(
          authority: .system,
          owner: merchant.hash,
          reason: "shop_inventory"
        ),
        reservedCoordinates: reserved
      )
      reserved.insert(stock.record.actualCoordinate)
      prepared.append(stock)
    }
    let startingEventCount = document.events.count
    var placed: [MikroObject] = []
    do {
      for stock in prepared {
        try harness.place(stock.object, at: stock.record.actualCoordinate, in: space)
        placed.append(stock.object)
        try merchant.addPrice(rule.price, for: stock.record.snapshot.objectID)
        document.events.append(.objectDeployed(record: stock.record))
        rule.createdObjects.append(
          RestockStockRecord(objectID: stock.record.snapshot.objectID, price: rule.price)
        )
      }
    } catch {
      for object in placed.reversed() {
        merchant.removePrice(for: object.hash)
        try? harness.removeObject(object)
      }
      document.events.removeLast(document.events.count - startingEventCount)
      throw error
    }
    restockRules[rule.id] = rule
    document.events.append(.restockRuleUpdated(rule: rule))
    retainActiveInventoryReferences()
    return rule
  }

  @discardableResult
  public func updateRestockRule(
    _ query: String,
    price: Decimal? = nil,
    enabled: Bool? = nil
  ) throws -> RestockRule {
    var rule = try resolveRestockRule(query)
    if let price {
      try validateRestockPrice(price)
      rule.price = price
    }
    if let enabled { rule.enabled = enabled }
    restockRules[rule.id] = rule
    document.events.append(.restockRuleUpdated(rule: rule))
    return rule
  }

  public func deleteRestockRule(_ query: String) throws {
    let rule = try resolveRestockRule(query)
    restockRules.removeValue(forKey: rule.id)
    document.events.append(.restockRuleDeleted(ruleID: rule.id))
  }

  private func validateRestockPrice(_ price: Decimal) throws {
    do {
      _ = try MerchantObject.creditAmount(for: price)
    } catch {
      throw MikroKhorosError.runtime(
        "inventory.restock_price_invalid",
        "price must be a positive credit value with at most two decimal places"
      )
    }
  }

  public func handlePendingRequest(
    for agent: Agent,
    using client: (any AICompleting)? = nil
  ) async throws -> AgentTurn? {
    let session = try session(for: agent)
    let resolvedClient: any AICompleting =
      client ?? AICompletionClient(limits: configuration.runtime)
    let previousChain = creditService.chain
    // Capture the exact source events presented to this request. The session
    // removes a source event only after accepted model output; this snapshot
    // lets the world journal persist those acknowledgements after the history
    // checkpoint below, without coupling persistence to a bearer-specific
    // pending queue.
    let broadcastsBefore = agent.pendingBroadcasts.compactMap { event -> AgentBroadcastEvent? in
      guard let source = harness.findObject(event.sourceID) as? BroadcastSource,
        source.unreadEvent(eventID: event.id) == event
      else { return nil }
      return event
    }
    entropy.beginRecording()
    let operationID = harness.nextRuntimeIdentity()
    let turn: AgentTurn?
    do {
      turn = try await session.handlePendingRequest(
        using: resolvedClient,
        operationID: operationID
      )
    } catch {
      _ = entropy.finishRecording()
      throw error
    }
    let generated = entropy.finishRecording()
    guard let turn else { return nil }
    let activities = actionActivity(
      operationID: operationID,
      agentID: agent.hash,
      turn: turn
    )
    // Persist the model-history checkpoint before recording the action that
    // drained broadcasts. A replay must never acknowledge a broadcast whose
    // corresponding history has not been durably captured.
    document.histories[agent.hash] = session.history
    let actionPairs = turn.results.compactMap { result -> (index: UInt64, command: String)? in
      guard let command = result.command, result.index > 0 else { return nil }
      return (index: UInt64(result.index - 1), command: command)
    }
    let commands = actionPairs.map(\.command)
    let actionIndexes = actionPairs.map(\.index)
    let accepted =
      !turn.results.isEmpty
      && turn.results.allSatisfy {
        $0.status == .success
      }
    let acknowledgements: [WorldUnreadAcknowledgement] =
      accepted
      ? broadcastsBefore.compactMap { event in
        guard let source = harness.findObject(event.sourceID) as? BroadcastSource,
          source.unreadEvent(eventID: event.id) == nil
        else { return nil }
        return WorldUnreadAcknowledgement(
          agentID: agent.hash,
          eventID: event.id,
          sourceID: event.sourceID
        )
      }
      : []
    if !commands.isEmpty || accepted {
      document.events.append(
        .actions(
          operationID: operationID,
          agentID: agent.hash,
          commands: commands,
          actionIndexes: actionIndexes,
          drainedBroadcasts: accepted,
          generatedIDs: generated.ids,
          generatedDates: generated.dates
        )
      )
    }
    document.credit = creditService.snapshot()
    try appendCreditOperation(
      records: creditRecords(after: creditService.chain, comparedTo: previousChain),
      actor: CreditActor.agent.rawValue,
      operationID: operationID,
      acknowledgements: acknowledgements,
      activity: activities
    )
    appendActivity(activities)
    return turn
  }

  public func session(for agent: Agent) throws -> AgentSession {
    guard harness.findAgent(agent.hash) === agent, let session = sessions[agent.hash] else {
      throw MikroKhorosError.command("agent does not belong to this world")
    }
    return session
  }

  private func record(for agent: Agent) throws -> WorldAgentRecord {
    guard let record = document.agents.first(where: { $0.id == agent.hash }) else {
      throw MikroKhorosError.command("agent does not belong to this world")
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

  private func worldObjectBaseInterface(_ object: MikroObject) -> JSONValue {
    let source: JSONValue =
      object.lineage.flatMap { lineage in
        inventory?.allInventoryObjects(includeDeleted: true).first {
          $0.id == lineage.inventoryObjectID
        }
      }.map { record in
        inventorySourceSnapshot(record)
      } ?? .null
    return .object([
      "identity": .object([
        "object_id": .string(object.hash),
        "type": .string(object.typeName),
        "name": .string(object.name),
        "instance_revision": .number(Double(object.instanceRevision)),
      ]),
      "location": .object([
        "container_id": object.parentSpace.map { .string($0.owner.hash) } ?? .null,
        "coordinate": object.coordinate.map { .string($0.description) } ?? .null,
        "anchored": .bool(object is AnchoredWorldObject),
      ]),
      "lineage": object.lineage.map { lineage in
        .object([
          "package_id": .string(lineage.packageID),
          "package_version": .string(lineage.packageVersion),
          "inventory_object_id": .string(lineage.inventoryObjectID),
          "inventory_revision": .number(Double(lineage.inventoryRevision)),
          "deployment_id": .string(lineage.deploymentID),
        ])
      } ?? .null,
      "inventory_source": source,
      "capabilities": .array(
        object.capturedCapabilities.sorted { $0.rawValue < $1.rawValue }
          .map { .string($0.rawValue) }
      ),
      "functions": .array(
        object.inspect().functions.map { function in
          .object([
            "name": .string(function.name),
            "audience": .string(function.audience.rawValue),
          ])
        }
      ),
    ])
  }

  private func inventorySourceSnapshot(_ object: InventoryObjectRecord) -> JSONValue {
    .object([
      "id": .string(object.id),
      "folder_id": .string(object.folderID),
      "folder_path": inventory.map { .string($0.folderPath(for: object.folderID)) } ?? .null,
      "world_binding": object.worldBinding.map { .string($0.worldID) } ?? .null,
      "fork": object.forkProvenance.map { provenance in
        .object([
          "parent_inventory_object_id": .string(provenance.parentInventoryObjectID),
          "parent_revision": .number(Double(provenance.parentRevision)),
          "forked_at": .string(ISO8601DateFormatter().string(from: provenance.forkedAt)),
        ])
      } ?? .null,
    ])
  }

  private func validateWorldManagementInput(
    _ raw: String,
    type: ManagementFieldKind,
    choices: [String],
    maximumCharacters: Int,
    parameter: String
  ) throws {
    guard raw.count <= maximumCharacters else {
      throw MikroKhorosError.runtime(
        "object.management_input_invalid",
        "the world-object action input exceeds the configured field limit",
        details: ["input": parameter, "limit": String(maximumCharacters)]
      )
    }
    let valid: Bool
    switch type {
    case .text: valid = true
    case .url:
      valid =
        URL(string: raw).flatMap(\.scheme).map {
          ["http", "https"].contains($0.lowercased())
        } == true
    case .path: valid = !raw.isEmpty && !raw.contains("\0")
    case .choice: valid = choices.contains(raw)
    case .secret: valid = false
    case .integer: valid = Int(raw) != nil
    case .decimal: valid = Double(raw).map(\.isFinite) == true
    case .boolean: valid = ["true", "false", "1", "0", "yes", "no"].contains(raw.lowercased())
    }
    guard valid else {
      throw MikroKhorosError.runtime(
        "object.management_input_invalid",
        "the management input does not match its declared type",
        details: ["input": parameter, "type": type.rawValue]
      )
    }
  }

  private func announceThroughAthena(_ body: String) throws {
    guard let athena = optionalDefaultKhorosFacility(.athena) else { return }
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
    if !deliveries.isEmpty {
      document.events.append(.athenaNoticeFrom(athenaID: athena.hash, deliveries: deliveries))
    }
  }

  private func resolveDeploymentDestination(_ query: String) throws -> MikroObject {
    if query == "world" || query == harness.world.hash { return harness.world }
    if let agent = try? harness.resolveAgent(query) { return agent.backpack }
    return try harness.resolveObject(query)
  }

  private func prepareDeployment(
    _ inventoryID: String,
    destinationQuery: String,
    requestedCoordinate: Coordinate,
    autoAdapt: Bool,
    restockRuleID: String?,
    pickupLock: ObjectLock?,
    worldTemplate: WorldTemplateComponentLineage? = nil,
    templatePickupLockReason: String? = nil,
    reservedCoordinates: Set<Coordinate> = []
  ) throws -> (record: ObjectDeploymentRecord, object: MikroObject, space: Space) {
    guard let inventory else {
      throw MikroKhorosError.runtime(
        "inventory.store_unavailable",
        "this world runtime has no Inventory store"
      )
    }
    let source = try inventory.resolve(inventoryID)
    if let binding = source.worldBinding, binding.worldID != harness.world.hash {
      throw MikroKhorosError.runtime(
        "inventory.world_binding_mismatch",
        "this Inventory source is bound to a different world",
        details: [
          "bound_world": binding.worldID,
          "active_world": harness.world.hash,
        ],
        suggestions: ["select the bound world or fork a source for this world"]
      )
    }
    try inventory.requireReady(source)
    let package = try inventory.package(contentHash: source.packageHash)
    let destination = try resolveDeploymentDestination(destinationQuery)
    guard let space = destination.container else {
      throw MikroKhorosError.runtime(
        "inventory.destination_not_container",
        "the deployment destination has no container capability",
        details: ["destination": destination.hash]
      )
    }
    let actual: Coordinate
    if deploymentCoordinateIsAvailable(
      requestedCoordinate,
      in: space,
      reserved: reservedCoordinates
    ) {
      actual = requestedCoordinate
    } else if autoAdapt {
      actual = nearestDeploymentCoordinate(
        in: space,
        around: requestedCoordinate,
        reserved: reservedCoordinates
      )
    } else {
      throw MikroKhorosError.runtime(
        "placement.occupied",
        "cannot place the object at an occupied coordinate",
        details: ["position": requestedCoordinate.description],
        suggestions: ["choose another coordinate or enable auto-adapt placement"]
      )
    }
    let lineage = ObjectLineage(
      packageID: source.packageID,
      packageVersion: source.packageVersion,
      packageHash: source.packageHash,
      inventoryObjectID: source.id,
      inventoryRevision: source.revision,
      deploymentID: InventoryIdentity.make(),
      restockRuleID: restockRuleID,
      worldTemplate: worldTemplate
    )
    let adapterIdentity = try inventory.runtimeRegistry.adapterIdentity(for: package.manifest)
    let deploymentState: [String: JSONValue]
    if package.manifest.runtime == .nativeSwift {
      deploymentState = try inventory.runtimeRegistry.adapter(for: package.manifest)
        .captureDeploymentState(record: source, limits: configuration.runtime)
    } else {
      deploymentState = source.managementState
    }
    let deployableFields = Set(
      package.manifest.management.fields.filter { $0.deployable }.map(\.id)
    )
    let rootObjectID = InventoryIdentity.make()
    let concreteIDs = Dictionary(
      uniqueKeysWithValues: package.manifest.ownedObjects.map {
        ($0.id, InventoryIdentity.make())
      }
    )
    let ownedSnapshots = package.manifest.ownedObjects.map { owned in
      let objectID = concreteIDs[owned.id]!
      let fixedFacilityPackages = Set([
        FirstPartyPackageID.objectiveBoard,
        FirstPartyPackageID.library,
        FirstPartyPackageID.warehouse,
        FirstPartyPackageID.marketplace,
      ])
      let childLockReason =
        fixedFacilityPackages.contains(package.manifest.id)
        ? (owned.id == "merchant" ? "merchant_anchor" : "template_child") : nil
      return OwnedObjectDeploymentSnapshot(
        localID: owned.id,
        objectID: objectID,
        parentObjectID: owned.parent == "root" ? rootObjectID : concreteIDs[owned.parent]!,
        coordinate: owned.coordinate,
        definition: owned.object,
        privateState: owned.object.state,
        currentDurability: owned.object.durability,
        pickupLock: childLockReason.map { reason in
          ObjectLock(
            authority: .system,
            owner: objectID,
            reason: reason
          )
        }
      )
    }
    let snapshot = ObjectDeploymentSnapshot(
      manifest: package.manifest,
      runtimeAdapterID: adapterIdentity.0,
      runtimeAdapterVersion: adapterIdentity.1,
      objectID: rootObjectID,
      name: source.name,
      configuration: source.configuration.filter { deployableFields.contains($0.key) },
      credentialHandles: source.credentialHandles.filter {
        deployableFields.contains($0.key)
      },
      privateState: deploymentState,
      currentDurability: package.manifest.object.durability,
      pickupLock: pickupLock
        ?? templatePickupLockReason.map {
          ObjectLock(authority: .system, owner: rootObjectID, reason: $0)
        },
      capturedCapabilities: source.grantedCapabilities,
      lineage: lineage,
      ownedObjects: ownedSnapshots
    )
    let record = ObjectDeploymentRecord(
      snapshot: snapshot,
      destinationObjectID: destination.hash,
      requestedCoordinate: requestedCoordinate,
      actualCoordinate: actual,
      adapted: actual != requestedCoordinate
    )
    return (record, try instantiate(snapshot), space)
  }

  private func deploymentCoordinateIsAvailable(
    _ coordinate: Coordinate,
    in space: Space,
    reserved: Set<Coordinate>
  ) -> Bool {
    // Agents and their nonmaterial holding roots never occupy material
    // coordinates. Only a concrete object in the target space can block a
    // deployment.
    !reserved.contains(coordinate) && space.object(at: coordinate) == nil
  }

  private func nearestDeploymentCoordinate(
    in space: Space,
    around origin: Coordinate,
    reserved: Set<Coordinate>
  ) -> Coordinate {
    if deploymentCoordinateIsAvailable(origin, in: space, reserved: reserved) { return origin }
    var distance = 1
    while true {
      for offset in deploymentDiamondOffsets(distance: distance) {
        let candidate = origin + offset
        if deploymentCoordinateIsAvailable(candidate, in: space, reserved: reserved) {
          return candidate
        }
      }
      distance += 1
    }
  }

  private func deploymentDiamondOffsets(distance: Int) -> [Coordinate] {
    guard distance > 0 else { return [.origin] }
    var result: [Coordinate] = []
    for index in 0..<distance {
      result.append(Coordinate(x: index, y: -distance + index))
    }
    for index in 0..<distance {
      result.append(Coordinate(x: distance - index, y: index))
    }
    for index in 0..<distance {
      result.append(Coordinate(x: -index, y: distance - index))
    }
    for index in 0..<distance {
      result.append(Coordinate(x: -distance + index, y: -index))
    }
    return result
  }

  private func prepareAutomaticRestock(
    for item: MikroObject,
    merchant: MerchantObject
  ) throws -> InventoryRestockPlan? {
    guard let ruleID = item.lineage?.restockRuleID,
      var rule = restockRules[ruleID],
      rule.enabled
    else { return nil }
    guard rule.merchantID == merchant.hash else {
      throw MikroKhorosError.persistence("restock lineage does not match its merchant")
    }
    let shop = try harness.object(byHash: merchant.shopHash)
    let prepared = try prepareDeployment(
      rule.inventoryObjectID,
      destinationQuery: shop.hash,
      requestedCoordinate: rule.requestedCoordinate,
      autoAdapt: rule.autoAdapt,
      restockRuleID: rule.id,
      pickupLock: ObjectLock(
        authority: .system,
        owner: merchant.hash,
        reason: "shop_inventory"
      )
    )
    return InventoryRestockPlan(
      object: prepared.object,
      coordinate: prepared.record.actualCoordinate,
      price: rule.price
    ) { [weak self] in
      guard let self else { return }
      self.document.events.append(.objectDeployed(record: prepared.record))
      rule.createdObjects.append(
        RestockStockRecord(objectID: prepared.record.snapshot.objectID, price: rule.price)
      )
      self.restockRules[rule.id] = rule
      self.document.events.append(.restockRuleUpdated(rule: rule))
    }
  }

  private func instantiate(_ snapshot: ObjectDeploymentSnapshot) throws -> MikroObject {
    guard snapshot.lineage.packageID == snapshot.manifest.id,
      snapshot.lineage.packageVersion == snapshot.manifest.version,
      snapshot.objectID.count <= 128,
      snapshot.currentDurability == nil
        || snapshot.manifest.object.durability.map({ snapshot.currentDurability! <= $0 }) == true,
      snapshot.capturedCapabilities.isSubset(of: snapshot.manifest.requestedCapabilities)
    else {
      throw MikroKhorosError.persistence("deployment snapshot contains invalid lineage or state")
    }
    let object: MikroObject
    if snapshot.manifest.runtime == .declarative {
      guard snapshot.runtimeAdapterID == ObjectRuntimeRegistry.declarativeAdapterID,
        snapshot.runtimeAdapterVersion == ObjectRuntimeRegistry.declarativeAdapterVersion
      else { throw MikroKhorosError.persistence("declarative runtime adapter identity is invalid") }
      object = try DeclarativeObject(
        manifest: snapshot.manifest,
        name: snapshot.name,
        configuration: snapshot.configuration,
        credentialHandles: snapshot.credentialHandles,
        privateState: snapshot.privateState,
        currentDurability: snapshot.currentDurability,
        capturedCapabilities: snapshot.capturedCapabilities,
        lineage: snapshot.lineage,
        hash: snapshot.objectID
      )
    } else {
      guard let inventory else {
        throw MikroKhorosError.persistence("native object runtime requires an Inventory store")
      }
      let adapter = try inventory.runtimeRegistry.adapter(for: snapshot.manifest)
      guard adapter.id == snapshot.runtimeAdapterID,
        adapter.version == snapshot.runtimeAdapterVersion
      else { throw MikroKhorosError.persistence("runtime adapter identity or version changed") }
      object = try adapter.instantiate(
        snapshot: snapshot,
        limits: configuration.runtime,
        replaying: harness.isReplayingWorldEvents
      )
    }
    object.setInstanceRevision(snapshot.instanceRevision)
    object.restoreLock(snapshot.pickupLock)
    if let declarative = object as? DeclarativeObject {
      try instantiateOwnedObjects(snapshot.ownedObjects, root: declarative, snapshot: snapshot)
    }
    return object
  }

  private func retainActiveInventoryReferences() {
    guard let inventory else { return }
    let references = activeInventoryArtifactReferences
    inventory.setRuntimeReferences(
      owner: inventoryReferenceOwner,
      credentialHandles: references.credentialHandles,
      packageHashes: references.packageHashes
    )
  }

  private func instantiateOwnedObjects(
    _ ownedSnapshots: [OwnedObjectDeploymentSnapshot],
    root: DeclarativeObject,
    snapshot: ObjectDeploymentSnapshot
  ) throws {
    let definitions = Dictionary(
      uniqueKeysWithValues: snapshot.manifest.ownedObjects.map { ($0.id, $0) }
    )
    let grouped = Dictionary(grouping: ownedSnapshots, by: \.localID)
    guard grouped.count == definitions.count,
      grouped.values.allSatisfy({ $0.count == 1 }),
      Set(grouped.keys) == Set(definitions.keys)
    else {
      throw MikroKhorosError.persistence("deployment snapshot has an invalid owned-object graph")
    }
    var objects: [String: DeclarativeObject] = [snapshot.objectID: root]
    var pending = ownedSnapshots
    while !pending.isEmpty {
      var progressed = false
      for index in pending.indices.reversed() {
        let stored = pending[index]
        guard let parent = objects[stored.parentObjectID] else { continue }
        guard let declared = definitions[stored.localID],
          stored.definition == declared.object,
          stored.parentObjectID
            == (declared.parent == "root"
              ? snapshot.objectID
              : grouped[declared.parent]!.first!.objectID),
          InventoryIdentity.isValid(stored.objectID),
          objects[stored.objectID] == nil,
          stored.currentDurability == nil
            || stored.definition.durability.map({ stored.currentDurability! <= $0 }) == true,
          let space = parent.container,
          space.object(at: stored.coordinate) == nil
        else {
          throw MikroKhorosError.persistence("deployment snapshot has invalid owned-object state")
        }
        let object = try DeclarativeObject(
          manifest: snapshot.manifest,
          definition: stored.definition,
          configuration: snapshot.configuration,
          credentialHandles: snapshot.credentialHandles,
          privateState: stored.privateState,
          currentDurability: stored.currentDurability,
          capturedCapabilities: snapshot.capturedCapabilities,
          lineage: snapshot.lineage,
          hash: stored.objectID
        )
        object.restoreLock(stored.pickupLock)
        try space.place(object, at: stored.coordinate)
        objects[stored.objectID] = object
        pending.remove(at: index)
        progressed = true
      }
      guard progressed else {
        throw MikroKhorosError.persistence("deployment snapshot owned-object graph is disconnected")
      }
    }
  }

  private func deliverReport(from object: MikroObject, draft: HumanObjectReportDraft) throws {
    guard listeners.contains(object.hash) else { return }
    guard let lineage = object.lineage else {
      throw MikroKhorosError.runtime(
        "object.report_lineage_missing",
        "the concrete object has no Inventory lineage"
      )
    }
    guard let inventory else {
      throw MikroKhorosError.runtime(
        "object.report_package_unavailable",
        "the concrete object's retained package is unavailable"
      )
    }
    let package = try inventory.package(contentHash: lineage.packageHash)
    guard package.manifest.id == lineage.packageID,
      package.manifest.version == lineage.packageVersion,
      let definition = package.manifest.management.reports.first(where: {
        $0.type == draft.type
      })
    else {
      throw MikroKhorosError.runtime(
        "object.report_type_unknown",
        "the package does not declare this report type",
        details: ["report_type": draft.type]
      )
    }
    guard draft.title.count <= definition.maximumTitleCharacters,
      draft.body.count <= definition.maximumBodyCharacters
    else {
      throw MikroKhorosError.runtime(
        "object.report_contract_invalid",
        "the report title or body exceeds its declared contract"
      )
    }
    try validateReportPayload(draft.payload, definition: definition)
    let payloadBytes = try JSONEncoder().encode(draft.payload).count
    if let packageLimit = definition.maximumPayloadBytes, payloadBytes > packageLimit {
      throw MikroKhorosError.runtime(
        "object.report_too_large",
        "the report payload exceeds its package-declared byte limit",
        details: ["limit": String(packageLimit)]
      )
    }
    let report = ObjectReport(
      id: harness.nextRuntimeIdentity(),
      timestamp: harness.runtimeDate(),
      worldID: harness.world.hash,
      objectID: object.hash,
      lineage: lineage,
      type: draft.type,
      title: draft.title,
      body: draft.body,
      payload: draft.payload
    )
    let encoder = JSONEncoder()
    guard try encoder.encode(report).count <= configuration.runtime.maximumReportBytes else {
      throw MikroKhorosError.runtime(
        "object.report_too_large",
        "the report exceeds the configured byte limit",
        details: ["limit": String(configuration.runtime.maximumReportBytes)]
      )
    }
    reports.append(report)
    if reports.count > configuration.runtime.maximumRetainedReports {
      reports.removeFirst(reports.count - configuration.runtime.maximumRetainedReports)
    }
    document.events.append(.objectReportDelivered(report: report))
    let retainedIDs = Set(reports.map(\.id))
    document.events.removeAll { event in
      guard case .objectReportDelivered(let stored) = event else { return false }
      return !retainedIDs.contains(stored.id)
    }
  }

  private func replayObjective(
    boardID: String,
    id: String,
    title: String,
    body: String,
    createdAt: Date,
    coordinate: Coordinate
  ) throws {
    let board = try harness.object(byHash: boardID)
    guard let space = board.container else {
      throw MikroKhorosError.persistence("the Objective Board has no container capability")
    }
    let objective = try ObjectiveObject(
      title: title,
      body: body,
      createdAt: createdAt,
      origin: board.origin == .package ? .package : .native,
      lineage: board.lineage,
      hash: id
    )
    try objective.lock(
      authority: .system,
      owner: board.hash,
      reason: "objective_board_entry"
    )
    try harness.place(objective, at: coordinate, in: space)
  }

  private func replayObjectiveAcknowledgement(
    boardID: String,
    objectiveID: String,
    eventID: String
  ) throws {
    let key = ObjectiveAcknowledgementKey(
      boardID: boardID,
      objectiveID: objectiveID,
      eventID: eventID
    ).receiptValue
    guard replayedObjectiveAcknowledgements.insert(key).inserted else { return }
    let board = try harness.object(byHash: boardID)
    guard board is ObjectiveBoardObject,
      let objective = board.container?.items.compactMap({ $0.object as? ObjectiveObject })
        .first(where: { $0.hash == objectiveID }),
      eventID == objective.hash
        || objective.objectiveRecords.contains(where: { $0.id == eventID })
    else {
      throw MikroKhorosError.persistence(
        "objective acknowledgement references an unknown exact event"
      )
    }
  }

  private func replayLibraryDocument(
    libraryID: String,
    id: String,
    title: String,
    sourceURL: String,
    content: String,
    fetchedAt: Date,
    coordinate: Coordinate
  ) throws {
    let library = try harness.object(byHash: libraryID)
    guard let space = library.container else {
      throw MikroKhorosError.persistence("the Library has no container capability")
    }
    let documentObject = try LibraryDocumentObject(
      title: title,
      sourceURL: sourceURL,
      content: content,
      fetchedAt: fetchedAt,
      origin: library.origin == .package ? .package : .native,
      lineage: library.lineage,
      hash: id
    )
    try documentObject.lock(
      authority: .system,
      owner: library.hash,
      reason: "library_document"
    )
    try harness.place(documentObject, at: coordinate, in: space)
  }

  private func replayAthenaNotice(_ deliveries: [AthenaNoticeDelivery]) throws {
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

  private func replayTemplateDeployments(_ deployments: [ObjectDeploymentRecord]) throws {
    guard let worldSpace = harness.world.container else {
      throw MikroKhorosError.persistence("the root world has no container capability")
    }
    for record in deployments {
      guard record.destinationObjectID == harness.world.hash,
        record.snapshot.lineage.worldTemplate != nil,
        record.adapted == (record.requestedCoordinate != record.actualCoordinate)
      else {
        throw MikroKhorosError.persistence("world-template deployment record is invalid")
      }
      try harness.place(
        instantiate(record.snapshot),
        at: record.actualCoordinate,
        in: worldSpace
      )
    }
  }

  private func replay(_ event: WorldEvent) throws {
    if case .operationEnvelope(let envelope) = event {
      try envelope.validateForPersistence()
      guard envelope.worldID == harness.world.hash else {
        throw MikroKhorosError.persistence("operation envelope is invalid for this world")
      }
      try validateReplayCustodyBoundary(envelope)
      try replayEvent(event)
      return
    }
    // A batch is an ordered sequence of independent actions.  Taking one
    // custody snapshot around the entire batch loses transitions that return
    // to the original bearer (for example `drop` followed by `pickup`).
    // Replay each command at its persisted action index instead.
    if case .actions = event {
      try replayActionsEvent(event)
      return
    }
    let before = try replayWalletLocations()
    try replayEvent(event)
    let after = try replayWalletLocations()
    recordReplayCustodyTransitions(before: before, after: after)
  }

  private func replayActionsEvent(_ event: WorldEvent) throws {
    guard
      case .actions(
        let operationID, let id, let commands, let actionIndexes, let drainedBroadcasts,
        let generatedIDs, let generatedDates
      ) = event
    else {
      throw MikroKhorosError.persistence("internal action replay event mismatch")
    }
    let agent = try harness.resolveAgent(id)
    entropy.beginReplay(ids: generatedIDs, dates: generatedDates)
    guard harness.nextRuntimeIdentity() == operationID else {
      throw MikroKhorosError.persistence(
        "action operation identity does not match its entropy tape")
    }
    let relatedEnvelopes = document.operations.filter { $0.operationID == operationID }
    if !commands.isEmpty || drainedBroadcasts {
      guard !relatedEnvelopes.isEmpty else {
        throw MikroKhorosError.persistence(
          "an action event has no matching operation envelope"
        )
      }
    }
    guard relatedEnvelopes.allSatisfy({ $0.actor == CreditActor.agent.rawValue }) else {
      throw MikroKhorosError.persistence(
        "an action event has a non-agent operation envelope"
      )
    }
    guard actionIndexes.count == commands.count,
      zip(actionIndexes, actionIndexes.dropFirst()).allSatisfy({ $0 < $1 })
    else {
      throw MikroKhorosError.persistence(
        "an action event has missing, duplicate, or reordered action indexes"
      )
    }
    for (command, actionIndex) in zip(commands, actionIndexes) {
      // Ensure every earlier indexed credit checkpoint is available before
      // this command.  This matters when action 0 changes custody and action
      // 1 performs a debit whose signed prior hash includes that custody
      // record.
      try preapplyReplayEnvelopes(
        operationID: operationID,
        through: actionIndex == 0 ? nil : actionIndex - 1
      )
      if let envelope = try replayEnvelope(
        operationID: operationID,
        actionIndex: actionIndex
      ), !envelope.signedCreditRecords.isEmpty,
        envelope.signedCreditRecords.allSatisfy({ $0.unsigned.kind != .custodyChange })
      {
        // Financial records are idempotent checkpoints for the action and
        // must be visible before the command executes.
        try preapplyReplayEnvelope(envelope)
      }
      let before = try replayWalletLocations()
      try replayPersistedAction(
        command,
        for: agent,
        operationID: operationID,
        actionIndex: actionIndex
      )
      let after = try replayWalletLocations()
      recordReplayCustodyTransitions(
        before: before,
        after: after,
        operation: WorldOperationIdentity(
          operationID: operationID,
          actionIndex: actionIndex
        )
      )
      // Financial records are pre-applied before their action.  Custody-only
      // records are applied now, after the graph transition they authenticate.
      if let envelope = try replayEnvelope(operationID: operationID, actionIndex: actionIndex),
        !envelope.signedCreditRecords.isEmpty,
        envelope.signedCreditRecords.allSatisfy({ $0.unsigned.kind == .custodyChange })
      {
        try preapplyReplayEnvelope(envelope)
      }
    }
    if commands.isEmpty, drainedBroadcasts {
      _ = harness.drainBroadcasts(for: agent)
    }
    try entropy.finishReplay()
  }

  private func replayEnvelope(
    operationID: String,
    actionIndex: UInt64
  ) throws -> WorldOperationEnvelope? {
    let matches = document.operations.filter {
      $0.operationID == operationID && $0.actionIndex == actionIndex
    }
    guard let first = matches.first else { return nil }
    guard matches.allSatisfy({ $0 == first }) else {
      throw MikroKhorosError.persistence(
        "the world contains conflicting envelopes for one action identity"
      )
    }
    return first
  }

  private func preapplyReplayEnvelopes(
    operationID: String,
    through actionIndex: UInt64?
  ) throws {
    guard let actionIndex else { return }
    let envelopes = document.operations
      .filter {
        $0.operationID == operationID && $0.actionIndex <= actionIndex
      }
      .sorted(by: { $0.actionIndex < $1.actionIndex })
    var seenActionIndexes: [UInt64: WorldOperationEnvelope] = [:]
    for envelope in envelopes {
      if let existing = seenActionIndexes[envelope.actionIndex] {
        guard existing == envelope else {
          throw MikroKhorosError.persistence(
            "the world contains conflicting envelopes for one action identity"
          )
        }
        continue
      }
      seenActionIndexes[envelope.actionIndex] = envelope
      try preapplyReplayEnvelope(envelope)
    }
  }

  private func preapplyReplayEnvelope(_ envelope: WorldOperationEnvelope) throws {
    let identity = WorldOperationIdentity(
      operationID: envelope.operationID,
      actionIndex: envelope.actionIndex
    )
    guard !replayedOperationEnvelopes.keys.contains(identity),
      !preappliedReplayOperationEnvelopes.contains(identity)
    else { return }
    try envelope.validateForPersistence()
    guard envelope.worldID == harness.world.hash else {
      throw MikroKhorosError.persistence("operation envelope is invalid for this world")
    }
    guard envelope.actor == CreditActor.agent.rawValue else {
      throw MikroKhorosError.persistence(
        "an agent action envelope has a non-agent actor"
      )
    }
    // A mixed custody/financial envelope cannot be safely split around a graph
    // command. Live persistence emits one signed action record per operation;
    // reject a malformed mixed envelope rather than reordering its chain.
    let hasCustody = envelope.signedCreditRecords.contains {
      $0.unsigned.kind == .custodyChange
    }
    let hasFinancial = envelope.signedCreditRecords.contains {
      $0.unsigned.kind != .custodyChange
    }
    guard !(hasCustody && hasFinancial) else {
      throw MikroKhorosError.persistence(
        "an action envelope mixes custody and financial records"
      )
    }
    for record in envelope.signedCreditRecords {
      try creditService.apply(record)
    }
    guard try unreadRecords(for: envelope.signedCreditRecords) == envelope.unread else {
      throw MikroKhorosError.persistence(
        "operation envelope unread records conflict with their signed credit records"
      )
    }
    for purchase in envelope.purchases {
      try replayPurchaseMutation(purchase)
    }
    if !envelope.signedCreditRecords.isEmpty {
      preappliedReplayOperationEnvelopes.insert(identity)
      document.credit = creditService.snapshot()
    }
  }

  private func replayPersistedAction(
    _ command: String,
    for agent: Agent,
    operationID: String,
    actionIndex: UInt64
  ) throws {
    let interpreter = ActionInterpreter(harness: harness)
    let queued = harness.performQueuedAction { () -> Result<String, RuntimeIssue> in
      let apply = { () -> Result<String, RuntimeIssue> in
        do {
          return .success(try interpreter.applyPersisted(command, for: agent))
        } catch let error as MikroKhorosError {
          return .failure(error.issue)
        } catch {
          return .failure(
            RuntimeIssue(code: "action.failed", message: "action failed")
          )
        }
      }
      return harness.withCreditOperation(
        operationID: operationID,
        actionIndex: actionIndex,
        apply
      )
    }
    guard case .success = queued.1 else {
      throw MikroKhorosError.persistence("persisted action no longer replays successfully")
    }
    _ = harness.drainBroadcasts(for: agent)
  }

  private func replayEvent(_ event: WorldEvent) throws {
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
      let operationID, let id, let commands, let actionIndexes, let drainedBroadcasts,
      let generatedIDs, let generatedDates
    ):
      let agent = try harness.resolveAgent(id)
      entropy.beginReplay(ids: generatedIDs, dates: generatedDates)
      guard harness.nextRuntimeIdentity() == operationID else {
        throw MikroKhorosError.persistence(
          "action operation identity does not match its entropy tape")
      }
      if !commands.isEmpty {
        guard actionIndexes.count == commands.count,
          zip(actionIndexes, actionIndexes.dropFirst()).allSatisfy({ $0 < $1 })
        else {
          throw MikroKhorosError.persistence(
            "an action event has missing, duplicate, or reordered action indexes"
          )
        }
        for (command, actionIndex) in zip(commands, actionIndexes) {
          try replayPersistedAction(
            command,
            for: agent,
            operationID: operationID,
            actionIndex: actionIndex
          )
        }
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
      if let existing = messenger.messages.first(where: { $0.id == id }) {
        guard
          existing
            == MessengerMessage(
              id: id,
              threadID: threadID,
              sender: sender,
              senderAgentID: senderAgentID,
              body: body,
              priority: priority,
              timestamp: timestamp,
              isRead: false
            )
            || existing
              == MessengerMessage(
                id: id,
                threadID: threadID,
                sender: sender,
                senderAgentID: senderAgentID,
                body: body,
                priority: priority,
                timestamp: timestamp,
                isRead: true
              )
        else {
          throw MikroKhorosError.persistence("message event identity has conflicting content")
        }
        return
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
    case .messengerAcknowledged(let messengerID, let messageID):
      let acknowledgementKey = "messenger#\(messengerID)#\(messageID)"
      if replayedMessengerAcknowledgements.contains(acknowledgementKey) { return }
      guard let messenger = try harness.object(byHash: messengerID) as? MessengerObject,
        let message = messenger.messages.first(where: { $0.id == messageID })
      else {
        throw MikroKhorosError.persistence("message acknowledgement target is invalid")
      }
      if !message.isRead {
        guard messenger.acknowledge(eventID: messageID) else {
          throw MikroKhorosError.persistence("message acknowledgement could not be applied")
        }
      }
      replayedMessengerAcknowledgements.insert(acknowledgementKey)
    case .humanInboxAcknowledged(let agentID, let messageID):
      let acknowledgementKey = "human#\(agentID)#\(messageID)"
      if replayedMessengerAcknowledgements.contains(acknowledgementKey) { return }
      let agent = try harness.resolveAgent(agentID)
      guard let message = try harness.humanInbox(for: agent).first(where: { $0.id == messageID })
      else {
        throw MikroKhorosError.persistence(
          "human inbox acknowledgement references an unknown message"
        )
      }
      if !message.isRead {
        guard try harness.acknowledgeHumanInbox(for: agent, messageID: messageID) else {
          throw MikroKhorosError.persistence(
            "human inbox acknowledgement could not be applied"
          )
        }
      }
      replayedMessengerAcknowledgements.insert(acknowledgementKey)
    case .humanMessage(
      let agentID, let id, let body, let sender, let senderAgentID,
      let threadID, let priority, let timestamp
    ):
      let agent = try harness.resolveAgent(agentID)
      // A human-directed send has two durable projections: the source
      // Messenger transcript (already read by its sender) and the separate
      // human inbox copy (unread until the human acknowledges it).  The
      // WorldEvent historically replayed only the latter, which made a
      // restored agent transcript diverge from the live world.  Reconstruct
      // both projections idempotently before considering the event applied.
      guard sender == agent.name, senderAgentID == agent.hash else {
        throw MikroKhorosError.persistence(
          "human message event sender does not match its issuing agent"
        )
      }
      let messenger = try harness.messenger(for: agent)
      let threadTitle =
        messenger.threads.first(where: { $0.id == threadID })?.title
        ?? (threadID == "#1" ? "Messages" : "Human funding requests")
      _ = try messenger.ensureThread(id: threadID, title: threadTitle)
      let expectedSent = MessengerMessage(
        id: id,
        threadID: threadID,
        sender: agent.name,
        senderAgentID: agent.hash,
        body: body,
        priority: priority,
        timestamp: timestamp,
        isRead: true
      )
      if let existingSent = messenger.messages.first(where: { $0.id == id }) {
        guard existingSent == expectedSent else {
          throw MikroKhorosError.persistence(
            "human message source transcript has conflicting content"
          )
        }
      } else {
        _ = try messenger.recordSent(
          threadID: threadID,
          body: body,
          priority: priority,
          agent: agent,
          id: id,
          timestamp: timestamp
        )
      }
      let expectedInbox = MessengerMessage(
        id: id,
        threadID: threadID,
        sender: sender,
        senderAgentID: senderAgentID,
        body: body,
        priority: priority,
        timestamp: timestamp,
        isRead: false
      )
      if let existing = try harness.humanInbox(for: agent).first(where: { $0.id == id }) {
        guard existing == expectedInbox else {
          throw MikroKhorosError.persistence(
            "human message event identity has conflicting content"
          )
        }
        return
      }
      try harness.replayHumanMessage(from: agent, message: expectedInbox)
    case .operationEnvelope(let envelope):
      try replayOperationEnvelope(envelope)
    case .objectivePostedAt(
      let boardID, let id, let title, let body, let createdAt, let coordinate
    ):
      try replayObjective(
        boardID: boardID,
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        coordinate: coordinate
      )
    case .objectiveAcknowledged(let boardID, let objectiveID, let eventID):
      try replayObjectiveAcknowledgement(
        boardID: boardID,
        objectiveID: objectiveID,
        eventID: eventID
      )
    case .libraryDocumentAddedTo(
      let libraryID, let id, let title, let sourceURL, let content, let fetchedAt,
      let coordinate
    ):
      try replayLibraryDocument(
        libraryID: libraryID,
        id: id,
        title: title,
        sourceURL: sourceURL,
        content: content,
        fetchedAt: fetchedAt,
        coordinate: coordinate
      )
    case .athenaNoticeFrom(let athenaID, let deliveries):
      guard harness.findObject(athenaID) is AthenaObject else {
        throw MikroKhorosError.persistence("Athena notice source is not Athena")
      }
      try replayAthenaNotice(deliveries)
    case .worldTemplateApplied(let record):
      try replayTemplateDeployments(record.deployments)
      if let stored = document.templateApplications.first(where: { $0.id == record.id }) {
        guard stored.templateID == record.templateID,
          stored.templateVersion == record.templateVersion,
          stored.templateContentHash == record.templateContentHash
        else {
          throw MikroKhorosError.persistence(
            "world-template application metadata is inconsistent"
          )
        }
      } else {
        document.templateApplications.append(record)
      }
    case .worldTemplateComponentsRepaired(let record):
      guard
        document.templateApplications.contains(where: {
          $0.id == record.applicationID
        })
      else {
        throw MikroKhorosError.persistence("template repair references an unknown application")
      }
      try replayTemplateDeployments(record.deployments)
    case .objectDeployed(let record):
      let destination = try harness.object(byHash: record.destinationObjectID)
      guard let space = destination.container else {
        throw MikroKhorosError.persistence("deployment destination is not a container")
      }
      guard record.adapted == (record.requestedCoordinate != record.actualCoordinate) else {
        throw MikroKhorosError.persistence("deployment adaptation record is inconsistent")
      }
      try harness.place(
        instantiate(record.snapshot),
        at: record.actualCoordinate,
        in: space
      )
    case .objectStateChanged(
      let objectID, let adapterID, let adapterVersion, let state, let revision, let durability
    ):
      guard let object = harness.findObject(objectID) as? (MikroObject & RuntimeAdapterObject),
        object.runtimeAdapterID == adapterID,
        object.runtimeAdapterVersion == adapterVersion
      else {
        throw MikroKhorosError.persistence("object state event has no matching runtime adapter")
      }
      try object.restoreRuntimeAdapterState(state, revision: revision)
      object.restoreDurability(durability)
      if let workspace = object as? UserWorkspaceObject {
        try workspace.restoreProjectedTopology(harness: harness)
      }
    case .objectMoved(let objectID, let destinationID, let coordinate, let revision):
      guard let object = harness.findObject(objectID),
        let destination = harness.findObject(destinationID),
        let space = destination.container,
        revision > object.instanceRevision
      else { throw MikroKhorosError.persistence("object movement event is invalid") }
      try harness.moveObject(object, to: coordinate, in: space)
      object.setInstanceRevision(revision)
    case .externalEffectReceipt(let id, let objectID, let operation, let result, _):
      guard InventoryIdentity.isValid(id), harness.findObject(objectID) != nil,
        !operation.isEmpty, operation.count <= 128, result.count <= 512
      else { throw MikroKhorosError.persistence("external-effect receipt is invalid") }
    case .nestedInvocationReceipt(
      let rootID, let currentID, let sourceID, let targetID, let agentID,
      let function, let result, let depth
    ):
      guard InventoryIdentity.isValid(rootID), InventoryIdentity.isValid(currentID),
        rootID != currentID,
        harness.findObject(sourceID) != nil,
        harness.findObject(targetID) != nil,
        harness.findAgent(agentID) != nil,
        !function.isEmpty, function.count <= 128,
        result.count <= configuration.runtime.maximumActionCharacters,
        depth > 0, depth <= configuration.runtime.maximumObjectInvocationDepth
      else { throw MikroKhorosError.persistence("nested-invocation receipt is invalid") }
    case .objectsDeleted(let objectIDs):
      let deletedRootIDs = Set(objectIDs)
      for index in document.templateApplications.indices {
        document.templateApplications[index].markInactive(rootObjectIDs: deletedRootIDs)
      }
      for id in objectIDs {
        if let object = harness.findObject(id) {
          let affected = Set(([object] + object.walkContents()).map(\.hash))
          removeMerchantPrices(for: affected)
          listeners.subtract(affected)
          try harness.removeObject(object)
        }
      }
    case .listenerChanged(let objectID, let enabled):
      guard harness.findObject(objectID)?.lineage != nil else {
        throw MikroKhorosError.persistence("listener target is not an Inventory-backed object")
      }
      if enabled { listeners.insert(objectID) } else { listeners.remove(objectID) }
    case .objectReportDelivered(let report):
      guard report.worldID == harness.world.hash,
        listeners.contains(report.objectID),
        let object = harness.findObject(report.objectID) as? DeclarativeObject,
        object.lineage?.inventoryObjectID == report.inventoryObjectID,
        object.lineage?.inventoryRevision == report.inventoryRevision,
        object.lineage?.packageID == report.packageID,
        object.lineage?.packageVersion == report.packageVersion,
        let definition = object.packageManifest.management.reports.first(where: {
          $0.type == report.type
        }),
        report.title.count <= definition.maximumTitleCharacters,
        report.body.count <= definition.maximumBodyCharacters,
        try JSONEncoder().encode(report).count <= configuration.runtime.maximumReportBytes
      else { throw MikroKhorosError.persistence("object report failed lineage validation") }
      try validateReportPayload(report.payload, definition: definition)
      if let packageLimit = definition.maximumPayloadBytes {
        guard try JSONEncoder().encode(report.payload).count <= packageLimit else {
          throw MikroKhorosError.persistence("object report exceeds its package payload limit")
        }
      }
      reports.append(report)
      if reports.count > configuration.runtime.maximumRetainedReports {
        reports.removeFirst(reports.count - configuration.runtime.maximumRetainedReports)
      }
    case .restockRuleCreated(let rule):
      guard restockRules[rule.id] == nil else {
        throw MikroKhorosError.persistence("duplicate restock rule identity")
      }
      try validatePersistedRestockRule(rule)
      restockRules[rule.id] = rule
      try restoreMerchantCatalog(for: rule)
    case .restockRuleUpdated(let rule):
      guard restockRules[rule.id] != nil else {
        throw MikroKhorosError.persistence("restock update references an unknown rule")
      }
      try validatePersistedRestockRule(rule)
      restockRules[rule.id] = rule
      try restoreMerchantCatalog(for: rule)
    case .restockRuleDeleted(let ruleID):
      guard restockRules.removeValue(forKey: ruleID) != nil else {
        throw MikroKhorosError.persistence("restock deletion references an unknown rule")
      }
    }
  }

  private func replayWalletLocations() throws -> [String: ReplayWalletLocation] {
    let index = try ObjectLocationIndex(
      world: harness.world,
      registeredObjects: harness.objects,
      agents: harness.agents,
      maxDepth: try worldLocationIndexDepth(
        configuration.runtime.maximumObjectInvocationDepth
      )
    )
    var result: [String: ReplayWalletLocation] = [:]
    for registration in creditService.registrations {
      guard let location = index.location(for: registration.walletID) else {
        throw MikroKhorosError.persistence("a registered wallet has no replay location")
      }
      result[registration.walletID] = ReplayWalletLocation(
        ownerID: location.owner?.agentID,
        locationCommitment: try index.locationCommitment(for: registration.walletID)
      )
    }
    return result
  }

  private func recordReplayCustodyTransitions(
    before: [String: ReplayWalletLocation],
    after: [String: ReplayWalletLocation],
    operation: WorldOperationIdentity? = nil
  ) {
    for walletID in before.keys.sorted() {
      guard let old = before[walletID], let new = after[walletID], old.ownerID != new.ownerID else {
        continue
      }
      pendingReplayCustodyTransitions.append(
        ReplayCustodyTransition(
          walletID: walletID,
          oldOwner: old.ownerID,
          newOwner: new.ownerID,
          oldLocationCommitment: old.locationCommitment,
          newLocationCommitment: new.locationCommitment,
          operation: operation
        )
      )
    }
  }

  private func validateReplayCustodyBoundary(_ envelope: WorldOperationEnvelope) throws {
    let identity = WorldOperationIdentity(
      operationID: envelope.operationID,
      actionIndex: envelope.actionIndex
    )
    if let existing = replayedOperationEnvelopes[identity] {
      guard existing == envelope else {
        throw MikroKhorosError.persistence(
          "operation envelope identity has conflicting content"
        )
      }
      return
    }
    var signedTransitions: [ReplayCustodyTransition] = []
    for record in envelope.signedCreditRecords where record.unsigned.kind == .custodyChange {
      for custody in record.unsigned.custody {
        signedTransitions.append(
          ReplayCustodyTransition(
            walletID: custody.wallet,
            oldOwner: custody.oldOwner,
            newOwner: custody.newOwner,
            oldLocationCommitment: custody.oldLocationCommitment,
            newLocationCommitment: custody.newLocationCommitment,
            operation: envelope.actor == CreditActor.agent.rawValue ? identity : nil
          )
        )
      }
    }
    // A single `.actions` event may contain several indexed commands while
    // its envelopes follow as separate events. Consume only the custody
    // transitions carried by this envelope; later envelopes consume the
    // remaining transitions, and the final-load check rejects any orphan.
    for transition in signedTransitions {
      guard let pending = pendingReplayCustodyTransitions.first,
        pending == transition
      else {
        throw MikroKhorosError.persistence(
          "operation envelope custody commitments do not match the replayed graph boundary"
        )
      }
      pendingReplayCustodyTransitions.removeFirst()
    }
  }

  private func replayOperationEnvelope(_ envelope: WorldOperationEnvelope) throws {
    try envelope.validateForPersistence()
    guard envelope.worldID == harness.world.hash else {
      throw MikroKhorosError.persistence("operation envelope is invalid for this world")
    }
    let operation = WorldOperationIdentity(
      operationID: envelope.operationID,
      actionIndex: envelope.actionIndex
    )
    if let existing = replayedOperationEnvelopes[operation] {
      guard existing == envelope else {
        throw MikroKhorosError.persistence(
          "operation envelope identity has conflicting content"
        )
      }
      return
    }
    guard
      envelope.signedCreditRecords.allSatisfy({
        $0.unsigned.operationID == envelope.operationID
          && $0.unsigned.worldID == envelope.worldID
      })
    else {
      throw MikroKhorosError.persistence(
        "operation envelope credit records have a conflicting operation identity"
      )
    }
    for record in envelope.signedCreditRecords {
      try creditService.apply(record)
    }
    guard try unreadRecords(for: envelope.signedCreditRecords) == envelope.unread else {
      throw MikroKhorosError.persistence(
        "operation envelope unread records conflict with their signed credit records"
      )
    }
    for purchase in envelope.purchases {
      try replayPurchaseMutation(purchase)
    }
    for receipt in envelope.receipts where receipt.kind == "objective_acknowledgement" {
      guard replayedObjectiveAcknowledgements.contains(receipt.value) else {
        throw MikroKhorosError.persistence(
          "objective acknowledgement receipt is not bound to its durable event"
        )
      }
    }
    for receipt in envelope.receipts where receipt.kind == "messenger_acknowledgement" {
      guard replayedMessengerAcknowledgements.contains(receipt.value) else {
        throw MikroKhorosError.persistence(
          "messenger acknowledgement receipt is not bound to its durable event"
        )
      }
    }
    for receipt in envelope.receipts where receipt.kind == "human_inbox_acknowledgement" {
      guard replayedMessengerAcknowledgements.contains(receipt.value) else {
        throw MikroKhorosError.persistence(
          "human inbox acknowledgement receipt is not bound to its durable event"
        )
      }
    }
    preappliedReplayOperationEnvelopes.remove(operation)
    reconcileWalletBroadcastQueues(for: envelope.signedCreditRecords)
    for mutation in envelope.objectMutations {
      guard let object = harness.findObject(mutation.objectID) else {
        throw MikroKhorosError.persistence("operation envelope references an unknown object")
      }
      if let priorRevision = mutation.priorRevision {
        guard object.instanceRevision == priorRevision else {
          throw MikroKhorosError.persistence(
            "operation envelope object revision does not match the graph"
          )
        }
      }
      if let revision = mutation.nextRevision {
        guard revision >= object.instanceRevision else {
          throw MikroKhorosError.persistence("operation envelope object revision regressed")
        }
        object.setInstanceRevision(revision)
      }
    }
    for unread in envelope.unread {
      guard let wallet = harness.findObject(unread.sourceID) as? WalletObject,
        harness.findObject(wallet.hash) === wallet,
        creditService.registration(for: wallet.hash) != nil,
        unread.event.sourceID == wallet.hash,
        unread.event.sourceType == "wallet.object"
      else {
        throw MikroKhorosError.persistence("operation envelope unread record is invalid")
      }
      if let existing = wallet.unreadEvent(eventID: unread.eventID) {
        guard existing == unread.event else {
          throw MikroKhorosError.persistence(
            "operation envelope unread identity has conflicting content"
          )
        }
      } else {
        guard wallet.recordBroadcast(unread.event) else {
          throw MikroKhorosError.persistence("operation envelope unread event could not be applied")
        }
      }
      // The wallet queue is authoritative. A bearer-specific pending queue is
      // only a delivery cache; ownerless wallets intentionally remain queued
      // on the Wallet until a future bearer carries it.
      if let ownerID = creditService.custodyOwner(for: wallet.hash),
        let owner = harness.findAgent(ownerID), owner.aiProfile != nil,
        harness.isCarried(wallet, by: owner),
        !owner.pendingBroadcasts.contains(where: {
          $0.sourceID == unread.event.sourceID && $0.id == unread.event.id
        })
      {
        owner.pendingBroadcasts.append(unread.event)
      }
    }
    for acknowledgement in envelope.acknowledgements {
      guard let sourceObject = harness.findObject(acknowledgement.sourceID),
        let source = sourceObject as? BroadcastSource,
        let agent = harness.findAgent(acknowledgement.agentID),
        harness.isCarried(sourceObject, by: agent),
        let event = source.unreadEvent(eventID: acknowledgement.eventID)
      else {
        throw MikroKhorosError.persistence(
          "operation envelope acknowledgement target is invalid"
        )
      }
      if let wallet = sourceObject as? WalletObject {
        guard creditService.registration(for: wallet.hash) != nil,
          creditService.custodyOwner(for: wallet.hash) == agent.hash
        else {
          throw MikroKhorosError.persistence(
            "operation envelope wallet acknowledgement bearer is invalid"
          )
        }
      }
      _ = source.acknowledge(eventID: event.id)
      for queuedAgent in harness.agents {
        queuedAgent.pendingBroadcasts.removeAll {
          $0.sourceID == acknowledgement.sourceID && $0.id == acknowledgement.eventID
        }
      }
    }
    appendActivity(envelope.activity)
    replayedOperationEnvelopes[operation] = envelope
    document.credit = creditService.snapshot()
  }

  private func replayPurchaseMutation(_ purchase: WorldPurchaseMutation) throws {
    guard let record = creditService.chain.first(where: { $0.recordID == purchase.recordID }) else {
      throw MikroKhorosError.persistence(
        "operation envelope purchase record is unavailable"
      )
    }
    let buyer = try validatePurchasePayer(
      record: record,
      walletID: purchase.payerWalletID,
      buyerAgentID: purchase.buyerAgentID
    )
    guard let merchant = harness.findObject(purchase.merchantID) as? MerchantObject,
      let item = harness.findObject(purchase.itemID),
      item.parentSpace?.owner.hash == merchant.shopHash,
      let price = merchant.prices[purchase.itemID],
      try MerchantObject.creditAmount(for: price).minorUnits
        == purchase.nominalAmount.minorUnits
    else {
      throw MikroKhorosError.persistence(
        "operation envelope purchase graph conflicts with its signed identities"
      )
    }
    let claim = ObjectLock(
      mode: .allowOnly,
      authority: .system,
      owner: merchant.hash,
      reason: "purchased_claim",
      allowedAgentIDs: [buyer.hash],
      clearsOnPickup: true
    )
    if item.lockInfo != claim {
      guard
        item.lockInfo
          == ObjectLock(
            authority: .system,
            owner: merchant.hash,
            reason: "shop_inventory"
          )
      else {
        throw MikroKhorosError.persistence(
          "operation envelope purchase claim conflicts with the item lock"
        )
      }
      try item.claimPickup(
        for: buyer.hash,
        authority: .system,
        owner: merchant.hash,
        reason: "purchased_claim",
        clearsOnPickup: true
      )
    }
    guard let replacement = purchase.replacement else { return }
    guard let object = harness.findObject(replacement.objectID),
      let lineage = object.lineage,
      lineage.restockRuleID == replacement.restockRuleID,
      lineage.inventoryObjectID == replacement.inventoryObjectID,
      lineage.inventoryRevision == replacement.inventoryRevision,
      lineage.deploymentID == replacement.deploymentID,
      object.coordinate == replacement.coordinate,
      object.parentSpace?.owner.hash == merchant.shopHash,
      object.lockInfo
        == ObjectLock(
          authority: .system,
          owner: merchant.hash,
          reason: "shop_inventory"
        ),
      let replacementPrice = merchant.prices[replacement.objectID],
      try MerchantObject.creditAmount(for: replacementPrice).minorUnits
        == replacement.price.minorUnits,
      let rule = restockRules[replacement.restockRuleID],
      rule.merchantID == merchant.hash,
      rule.inventoryObjectID == replacement.inventoryObjectID,
      let stock = rule.createdObjects.first(where: { $0.objectID == replacement.objectID }),
      rule.createdObjects.filter({ $0.objectID == replacement.objectID }).count == 1,
      try MerchantObject.creditAmount(for: stock.price).minorUnits
        == replacement.price.minorUnits,
      document.events.contains(where: { event in
        guard case .objectDeployed(let deployment) = event else { return false }
        return deployment.snapshot.objectID == replacement.objectID
          && deployment.snapshot.lineage == lineage
          && deployment.destinationObjectID == merchant.shopHash
          && deployment.actualCoordinate == replacement.coordinate
      })
    else {
      throw MikroKhorosError.persistence(
        "operation envelope purchase replacement conflicts with its durable restock transaction"
      )
    }
  }

  private func validatePurchasePayer(
    record: SignedCreditRecord,
    walletID: String,
    buyerAgentID: String
  ) throws -> Agent {
    let index = try ObjectLocationIndex(
      world: harness.world,
      registeredObjects: harness.objects,
      agents: harness.agents,
      maxDepth: try worldLocationIndexDepth(
        configuration.runtime.maximumObjectInvocationDepth
      )
    )
    guard let buyer = harness.findAgent(buyerAgentID),
      let registration = creditService.registration(for: walletID),
      registration.walletID == walletID,
      registration.worldID == harness.world.hash,
      let wallet = harness.findObject(walletID) as? WalletObject,
      harness.findObject(wallet.hash) === wallet,
      index.location(for: walletID) != nil,
      index.currentOwner(of: walletID)?.agentID == buyerAgentID,
      creditService.custodyOwner(for: walletID) == buyerAgentID,
      let latestCustodyCommitment = creditService.custodyCommitment(for: walletID),
      !latestCustodyCommitment.isEmpty,
      record.unsigned.sourceWalletID == walletID,
      record.unsigned.sourceWalletOwner == buyerAgentID,
      record.unsigned.sourceWalletCustodyCommitment == latestCustodyCommitment
    else {
      throw MikroKhorosError.persistence(
        "operation envelope purchase payer conflicts with current Wallet custody"
      )
    }
    return buyer
  }

  private func restoreMerchantCatalog(for rule: RestockRule) throws {
    guard let merchant = harness.findObject(rule.merchantID) as? MerchantObject else {
      throw MikroKhorosError.persistence("restock rule merchant is unavailable")
    }
    for stock in rule.createdObjects where harness.findObject(stock.objectID) != nil {
      try merchant.addPrice(stock.price, for: stock.objectID)
    }
  }

  private func validatePersistedRestockRule(_ rule: RestockRule) throws {
    guard InventoryIdentity.isValid(rule.id),
      InventoryIdentity.isValid(rule.inventoryObjectID),
      InventoryIdentity.isValid(rule.merchantID),
      (try? MerchantObject.creditAmount(for: rule.price)) != nil,
      rule.createdObjects.allSatisfy({
        InventoryIdentity.isValid($0.objectID)
          && (try? MerchantObject.creditAmount(for: $0.price)) != nil
      })
    else {
      throw MikroKhorosError.persistence("world contains an invalid restock rule")
    }
  }

  private func removeMerchantPrices(for objectIDs: Set<String>) {
    for merchant in harness.objects.compactMap({ $0 as? MerchantObject }) {
      for id in objectIDs { merchant.removePrice(for: id) }
    }
  }

  private func validateReportPayload(
    _ payload: JSONValue,
    definition: ObjectReportDefinition
  ) throws {
    guard !definition.payload.isEmpty else { return }
    guard case .object(let values) = payload,
      Set(values.keys) == Set(definition.payload.keys)
    else {
      throw MikroKhorosError.runtime(
        "object.report_contract_invalid",
        "the report payload does not match its declared fields"
      )
    }
    for (key, type) in definition.payload {
      let value = values[key]!
      let valid: Bool
      switch (type, value) {
      case (.text, .string), (.choice, .string), (.url, .string), (.path, .string):
        valid = true
      case (.integer, .number(let number)):
        valid = number.isFinite && number.rounded() == number
      case (.decimal, .number(let number)):
        valid = number.isFinite
      case (.boolean, .bool):
        valid = true
      case (.secret, _):
        valid = false
      default:
        valid = false
      }
      guard valid else {
        throw MikroKhorosError.runtime(
          "object.report_contract_invalid",
          "a report payload field does not match its declared type",
          details: ["field": key, "type": type.rawValue]
        )
      }
    }
  }

  private func registerNewAgentWallet(_ agent: Agent) throws {
    guard creditService.registration(for: agent.wallet.hash) == nil else {
      throw MikroKhorosError.persistence(
        "a newly registered agent already has a wallet registration"
      )
    }
    let index = try ObjectLocationIndex(
      world: harness.world,
      registeredObjects: harness.objects,
      agents: harness.agents,
      maxDepth: try worldLocationIndexDepth(
        configuration.runtime.maximumObjectInvocationDepth
      )
    )
    _ = try creditService.register(
      walletID: agent.wallet.hash,
      agentID: agent.hash,
      backpackID: agent.backpack.hash,
      locationCommitment: try index.locationCommitment(for: agent.wallet.hash),
      actor: .system
    )
  }

  private func creditRecords(
    after chain: [SignedCreditRecord],
    comparedTo previous: [SignedCreditRecord]
  ) throws -> [SignedCreditRecord] {
    guard chain.count >= previous.count,
      Array(chain.prefix(previous.count)) == previous
    else {
      throw MikroKhorosError.persistence("credit chain changed outside the current operation")
    }
    return Array(chain.dropFirst(previous.count))
  }

  /// Build the bounded model-facing projection for signed financial records.
  /// The signed record remains the accounting authority; this allowlisted
  /// event is only a durable notification carried by the exact native Wallet.
  private func walletModesByRecordID() throws -> [String: [String: WalletMode]] {
    var current: [String: WalletMode] = [:]
    var result: [String: [String: WalletMode]] = [:]
    for record in creditService.chain {
      var modes: [String: WalletMode] = [:]
      for walletID in record.unsigned.accounts {
        switch record.unsigned.kind {
        case .registration:
          guard current[walletID] == nil else {
            throw MikroKhorosError.persistence("wallet mode history repeats a registration")
          }
          current[walletID] = record.unsigned.mode
        case .modeChange:
          guard current[walletID] != nil else {
            throw MikroKhorosError.persistence("wallet mode history has an unknown wallet")
          }
          current[walletID] = record.unsigned.mode
        default:
          guard current[walletID] != nil else {
            throw MikroKhorosError.persistence("wallet mode history has an unknown wallet")
          }
        }
        modes[walletID] = current[walletID]
      }
      result[record.recordID] = modes
    }
    return result
  }

  private func purchaseEnvelopeComponents(
    for records: [SignedCreditRecord],
    unread: [WorldUnreadRecord]
  ) throws -> (mutations: [WorldPurchaseMutation], receipts: [WorldOperationReceipt]) {
    var mutations: [WorldPurchaseMutation] = []
    var receipts: [WorldOperationReceipt] = []
    for record in records where record.unsigned.kind == .purchase {
      guard let payerWalletID = record.unsigned.sourceWalletID,
        let buyerAgentID = record.unsigned.sourceWalletOwner
      else {
        throw MikroKhorosError.persistence(
          "committed purchase has no signed payer custody"
        )
      }
      _ = try validatePurchasePayer(
        record: record,
        walletID: payerWalletID,
        buyerAgentID: buyerAgentID
      )
      guard
        record.unsigned.causalMerchantIDs.count == 1,
        let merchantID = record.unsigned.causalMerchantIDs.first,
        let merchant = harness.findObject(merchantID) as? MerchantObject,
        record.unsigned.causalItemIDs.count == 1,
        let itemID = record.unsigned.causalItemIDs.first,
        let item = harness.findObject(itemID),
        let nominalAmount = record.unsigned.nominalPurchaseAmount,
        let appliedAmount = record.unsigned.appliedPurchaseAmount,
        let itemPrice = merchant.prices[itemID],
        try MerchantObject.creditAmount(for: itemPrice).minorUnits == nominalAmount.minorUnits,
        item.parentSpace?.owner.hash == merchant.shopHash,
        item.lockInfo
          == ObjectLock(
            mode: .allowOnly,
            authority: .system,
            owner: merchantID,
            reason: "purchased_claim",
            allowedAgentIDs: [buyerAgentID],
            clearsOnPickup: true
          )
      else {
        throw MikroKhorosError.persistence(
          "committed purchase state conflicts with its signed credit record"
        )
      }
      let replacementIDs = record.unsigned.causalObjectIDs.filter {
        $0 != payerWalletID && $0 != itemID
      }
      guard replacementIDs.count <= 1 else {
        throw MikroKhorosError.persistence(
          "committed purchase has more than one signed replacement"
        )
      }
      var replacementMutation: WorldPurchaseRestockMutation?
      if let replacementID = replacementIDs.first {
        guard let replacement = harness.findObject(replacementID),
          let lineage = replacement.lineage,
          let restockRuleID = lineage.restockRuleID,
          let coordinate = replacement.coordinate,
          replacement.parentSpace?.owner.hash == merchant.shopHash,
          replacement.lockInfo
            == ObjectLock(
              authority: .system,
              owner: merchantID,
              reason: "shop_inventory"
            ),
          let rule = restockRules[restockRuleID],
          rule.merchantID == merchantID,
          rule.inventoryObjectID == lineage.inventoryObjectID,
          let stock = rule.createdObjects.first(where: { $0.objectID == replacementID }),
          rule.createdObjects.filter({ $0.objectID == replacementID }).count == 1,
          merchant.prices[replacementID] == stock.price,
          let deployment = document.events.compactMap({ event -> ObjectDeploymentRecord? in
            guard case .objectDeployed(let deployment) = event,
              deployment.snapshot.objectID == replacementID
            else { return nil }
            return deployment
          }).last,
          deployment.destinationObjectID == merchant.shopHash,
          deployment.actualCoordinate == coordinate,
          deployment.snapshot.lineage == lineage
        else {
          throw MikroKhorosError.persistence(
            "committed purchase replacement conflicts with its Inventory transaction"
          )
        }
        let replacementAmount = try MerchantObject.creditAmount(for: stock.price)
        replacementMutation = WorldPurchaseRestockMutation(
          objectID: replacementID,
          restockRuleID: restockRuleID,
          inventoryObjectID: lineage.inventoryObjectID,
          inventoryRevision: lineage.inventoryRevision,
          deploymentID: lineage.deploymentID,
          coordinate: coordinate,
          price: try CreditBalance(minorUnits: replacementAmount.minorUnits)
        )
      }
      guard
        let unreadRecord = unread.first(where: {
          $0.sourceID == payerWalletID && $0.timestamp == record.unsigned.time
        }),
        unread.filter({
          $0.sourceID == payerWalletID && $0.timestamp == record.unsigned.time
        }).count == 1
      else {
        throw MikroKhorosError.persistence(
          "committed purchase has no unique payer notification"
        )
      }
      let receiptID = WorldOperationEnvelope.purchaseReceiptID(for: record.recordID)
      mutations.append(
        WorldPurchaseMutation(
          recordID: record.recordID,
          payerWalletID: payerWalletID,
          buyerAgentID: buyerAgentID,
          merchantID: merchantID,
          itemID: itemID,
          nominalAmount: nominalAmount,
          appliedAmount: appliedAmount,
          replacement: replacementMutation,
          receiptID: receiptID,
          unreadEventID: unreadRecord.eventID
        )
      )
      receipts.append(
        WorldOperationReceipt(
          id: receiptID,
          kind: "merchant_purchase",
          value: record.recordID
        )
      )
    }
    return (mutations, receipts)
  }

  private func unreadRecords(
    for records: [SignedCreditRecord]
  ) throws -> [WorldUnreadRecord] {
    let modesByRecordID = try walletModesByRecordID()
    var result: [WorldUnreadRecord] = []
    for record in records {
      switch record.unsigned.kind {
      case .deposit, .deduction, .transfer, .purchase, .modeChange:
        break
      case .registration, .custodyChange:
        continue
      }
      for (index, walletID) in record.unsigned.accounts.enumerated() {
        guard let wallet = harness.findObject(walletID) as? WalletObject,
          harness.findObject(walletID) === wallet,
          creditService.registration(for: walletID) != nil
        else {
          throw MikroKhorosError.persistence(
            "a signed financial record targets a non-native registered wallet"
          )
        }
        let transactionID = PromptSafety.yamlScalar(
          record.unsigned.transactionID,
          limit: 256
        )
        let kind = PromptSafety.yamlScalar(record.unsigned.kind.rawValue, limit: 32)
        let timestamp = PromptSafety.yamlScalar(
          ISO8601DateFormatter().string(from: record.unsigned.time),
          limit: 64
        )
        let finiteShadowBalance = PromptSafety.yamlScalar(
          record.unsigned.postBalances[index].decimalText,
          limit: 64
        )
        guard let walletMode = modesByRecordID[record.recordID]?[walletID] else {
          throw MikroKhorosError.persistence("wallet notification mode history is unavailable")
        }
        let mode = PromptSafety.yamlScalar(walletMode.rawValue, limit: 32)
        let signedDelta = PromptSafety.yamlScalar(
          record.unsigned.amounts[index].decimalText,
          limit: 64
        )
        var fields = [
          "wallet_id: \(PromptSafety.yamlScalar(walletID, limit: 128))",
          "transaction_id: \(transactionID)",
          "kind: \(kind)",
          "timestamp: \(timestamp)",
          "resulting_shadow_balance: \(finiteShadowBalance)",
          "mode: \(mode)",
          "signed_delta: \(signedDelta)",
        ]
        if let nominal = record.unsigned.nominalPurchaseAmount {
          fields.append(
            "nominal_amount: \(PromptSafety.yamlScalar(nominal.decimalText, limit: 64))"
          )
        }
        if let applied = record.unsigned.appliedPurchaseAmount {
          fields.append(
            "applied_amount: \(PromptSafety.yamlScalar(applied.decimalText, limit: 64))"
          )
        }
        // `note` is optional in the model allowlist. A valid signed note may
        // be 256 characters and YAML escaping can expand it further, so omit
        // only that optional field when the bounded event would overflow.
        // Mandatory accounting fields remain deterministic and are always
        // present; notification projection can never reject an already-signed
        // credit record after the ledger has committed it.
        // WalletObject's durable native queue uses the shared broadcast bound.
        // Keep the required signed projection labels while avoiding optional
        // presentation whitespace that would push a purchase over that cap.
        let baseBody = fields.joined(separator: ";")
        var body = baseBody
        if !record.unsigned.note.isEmpty {
          let note = PromptSafety.yamlScalar(
            record.unsigned.note,
            limit: UnsignedCreditRecord.maxNoteLength
          )
          let withNote = baseBody + "; note: \(note)"
          if withNote.count <= AgentBroadcastEvent.maximumBodyCharacters {
            body = withNote
          }
        }
        guard body.count <= AgentBroadcastEvent.maximumBodyCharacters else {
          throw MikroKhorosError.persistence(
            "wallet notification mandatory fields exceed the model event limit"
          )
        }
        // Keep the event identity opaque and bounded even when a valid caller
        // supplies a long transaction identifier. The digest is derived only
        // from the stable transaction/action/account coordinates; it is not a
        // ledger record hash and is never surfaced in the event body.
        let eventSeed =
          "\(record.unsigned.transactionID)\u{0}\(record.unsigned.actionIndex)\u{0}\(walletID)\u{0}\(index)"
        let eventID = "credit-\(String(SHA256Digest.hex(Data(eventSeed.utf8)).prefix(48)))"
        let event = AgentBroadcastEvent(
          id: eventID,
          timestamp: record.unsigned.time,
          sourceID: walletID,
          sourceType: "wallet.object",
          title: "Wallet credit update",
          body: body
        )
        result.append(
          WorldUnreadRecord(
            agentID: creditService.custodyOwner(for: walletID),
            event: event
          )
        )
      }
    }
    return result
  }

  private func actionActivity(
    operationID: String,
    agentID: String,
    turn: AgentTurn
  ) -> [ActivityRecord] {
    turn.results.map { result in
      let operation: String
      if let command = result.command,
        let head = command.split(whereSeparator: { $0.isWhitespace }).first,
        AgentActionKind(rawValue: head.lowercased()) != nil
      {
        operation = head.lowercased()
      } else {
        operation = "action"
      }
      let suffix = result.index > 0 ? "-\(result.index)" : ""
      return ActivityRecord(
        id: "\(operationID)-activity\(suffix)",
        timestamp: harness.runtimeDate(),
        agentID: agentID,
        operation: operation,
        success: result.status == .success,
        code: result.error?.code
      )
    }
  }

  private func activityActionIndex(
    _ record: ActivityRecord,
    operationID: String
  ) -> UInt64? {
    let prefix = "\(operationID)-activity"
    guard record.id == prefix || record.id.hasPrefix(prefix + "-") else { return nil }
    guard record.id != prefix else { return 0 }
    let suffix = String(record.id.dropFirst(prefix.count + 1))
    guard let resultIndex = UInt64(suffix), resultIndex > 0 else { return nil }
    // AgentActionResult.index is one-based, while credit envelopes are
    // explicitly zero-based.
    return resultIndex - 1
  }

  private func appendActivity(_ records: [ActivityRecord]) {
    guard !records.isEmpty else { return }
    activity.append(contentsOf: records)
    if activity.count > 10_000 {
      activity.removeFirst(activity.count - 10_000)
    }
  }

  private func appendCreditOperation(
    records: [SignedCreditRecord],
    actor: String,
    operationID: String? = nil,
    actionIndex: UInt64 = 0,
    acknowledgements: [WorldUnreadAcknowledgement] = [],
    activity: [ActivityRecord] = []
  ) throws {
    guard !records.isEmpty || !acknowledgements.isEmpty || !activity.isEmpty else { return }

    // A single agent turn may perform more than one purchase. CreditService
    // gives each financial mutation its own operation identity, so preserve
    // the signed-chain order while emitting one envelope per contiguous
    // operation. Interleaving records from one identity would make replay
    // ambiguous and is rejected instead of silently reordering the chain.
    var groups: [[SignedCreditRecord]] = []
    var currentOperation: WorldOperationIdentity?
    var closedOperations = Set<WorldOperationIdentity>()
    for record in records {
      guard record.unsigned.worldID == harness.world.hash else {
        throw MikroKhorosError.persistence(
          "credit record belongs to a different world"
        )
      }
      let operationID = record.unsigned.operationID
      let operation = WorldOperationIdentity(
        operationID: operationID,
        actionIndex: record.unsigned.actionIndex
      )
      if operation != currentOperation {
        if let currentOperation { closedOperations.insert(currentOperation) }
        guard !closedOperations.contains(operation) else {
          throw MikroKhorosError.persistence(
            "credit records for one operation are not contiguous in the signed chain"
          )
        }
        groups.append([])
        currentOperation = operation
      }
      groups[groups.count - 1].append(record)
    }

    var envelopes: [WorldOperationEnvelope] = []
    var assignedActivity = Set<Int>()
    for (offset, group) in groups.enumerated() {
      let groupOperation = WorldOperationIdentity(
        operationID: group[0].unsigned.operationID,
        actionIndex: group[0].unsigned.actionIndex
      )
      var groupActivity: [ActivityRecord] = []
      for (activityOffset, record) in activity.enumerated() {
        guard
          let activityIndex = activityActionIndex(
            record,
            operationID: groupOperation.operationID
          )
        else {
          // Preserve an activity record with an unrecognised generated id in
          // the first envelope rather than silently discarding audit data.
          if offset == 0, assignedActivity.insert(activityOffset).inserted {
            groupActivity.append(record)
          }
          continue
        }
        if activityIndex == groupOperation.actionIndex,
          assignedActivity.insert(activityOffset).inserted
        {
          groupActivity.append(record)
        }
      }
      let groupUnread = try unreadRecords(for: group)
      let purchaseComponents = try purchaseEnvelopeComponents(
        for: group,
        unread: groupUnread
      )
      envelopes.append(
        WorldOperationEnvelope(
          operationID: group[0].unsigned.operationID,
          worldID: harness.world.hash,
          actor: actor,
          timestamp: group[0].unsigned.time,
          actionIndex: group[0].unsigned.actionIndex,
          signedCreditRecords: group,
          purchases: purchaseComponents.mutations,
          receipts: purchaseComponents.receipts,
          unread: groupUnread,
          acknowledgements: offset == 0 ? acknowledgements : [],
          activity: groupActivity
        )
      )
    }
    let fallbackActivityOperationID = operationID ?? groups.first?.first?.unsigned.operationID
    if !activity.isEmpty, let fallbackActivityOperationID {
      var orphanActivity: [UInt64: [ActivityRecord]] = [:]
      for (offset, record) in activity.enumerated() where !assignedActivity.contains(offset) {
        let index =
          activityActionIndex(
            record,
            operationID: fallbackActivityOperationID
          ) ?? actionIndex
        orphanActivity[index, default: []].append(record)
      }
      for index in orphanActivity.keys.sorted() {
        guard let recordsForIndex = orphanActivity[index], !recordsForIndex.isEmpty else {
          continue
        }
        envelopes.append(
          WorldOperationEnvelope(
            operationID: fallbackActivityOperationID,
            worldID: harness.world.hash,
            actor: actor,
            timestamp: recordsForIndex[0].timestamp,
            actionIndex: index,
            activity: recordsForIndex
          )
        )
      }
    }
    if records.isEmpty {
      guard let operationID else {
        throw MikroKhorosError.persistence(
          "an acknowledgement envelope requires an operation identity"
        )
      }
      if envelopes.isEmpty {
        envelopes = [
          WorldOperationEnvelope(
            operationID: operationID,
            worldID: harness.world.hash,
            actor: actor,
            timestamp: activity.first?.timestamp ?? harness.runtimeDate(),
            actionIndex: actionIndex,
            acknowledgements: acknowledgements,
            activity: activity
          )
        ]
      } else {
        envelopes[0] = WorldOperationEnvelope(
          operationID: envelopes[0].operationID,
          worldID: envelopes[0].worldID,
          actor: envelopes[0].actor,
          timestamp: envelopes[0].timestamp,
          actionIndex: envelopes[0].actionIndex,
          signedCreditRecords: envelopes[0].signedCreditRecords,
          purchases: envelopes[0].purchases,
          objectMutations: envelopes[0].objectMutations,
          receipts: envelopes[0].receipts,
          unread: envelopes[0].unread,
          acknowledgements: acknowledgements,
          activity: envelopes[0].activity,
          idempotencyKey: envelopes[0].idempotencyKey
        )
      }
    }
    for envelope in envelopes { try envelope.validateForPersistence() }
    for envelope in envelopes {
      for unread in envelope.unread {
        guard let wallet = harness.findObject(unread.sourceID) as? WalletObject,
          harness.findObject(wallet.hash) === wallet
        else {
          throw MikroKhorosError.persistence(
            "operation envelope unread record targets a non-native wallet"
          )
        }
        if let existing = wallet.unreadEvent(eventID: unread.eventID) {
          guard existing == unread.event else {
            throw MikroKhorosError.persistence(
              "wallet notification identity has conflicting content"
            )
          }
        }
      }
    }
    for envelope in envelopes {
      if let existing = document.operations.first(where: {
        $0.operationID == envelope.operationID && $0.actionIndex == envelope.actionIndex
      }) {
        guard existing == envelope else {
          throw MikroKhorosError.persistence(
            "credit operation identity has a conflicting envelope"
          )
        }
      }
    }
    // All identity/content checks complete before changing any Wallet queue.
    // This keeps a conflicting operation from publishing a partial native
    // notification when document mutation is rejected.
    reconcileWalletBroadcastQueues(
      for: envelopes.flatMap { $0.signedCreditRecords }
    )
    for envelope in envelopes {
      for unread in envelope.unread {
        guard let wallet = harness.findObject(unread.sourceID) as? WalletObject,
          wallet.unreadEvent(eventID: unread.eventID) != nil
            || wallet.recordBroadcast(unread.event)
        else {
          throw MikroKhorosError.persistence("wallet notification could not be recorded")
        }
        if let ownerID = creditService.custodyOwner(for: wallet.hash),
          let owner = harness.findAgent(ownerID), owner.aiProfile != nil,
          harness.isCarried(wallet, by: owner),
          !owner.pendingBroadcasts.contains(where: {
            $0.sourceID == unread.sourceID && $0.id == unread.eventID
          })
        {
          owner.pendingBroadcasts.append(unread.event)
        }
      }
    }
    for envelope in envelopes
    where !document.operations.contains(where: {
      $0.operationID == envelope.operationID && $0.actionIndex == envelope.actionIndex
    }) {
      document.operations.append(envelope)
      document.events.append(.operationEnvelope(envelope))
    }
  }

  /// A pending agent queue is only a delivery cache.  A signed custody change
  /// can invalidate the old bearer's cache while the Wallet's own unread queue
  /// remains authoritative, so drop stale copies before re-queuing for the new
  /// bearer below (or leaving the event ownerless on the Wallet).
  private func reconcileWalletBroadcastQueues(
    for records: [SignedCreditRecord]
  ) {
    let walletIDs = Set(
      records
        .filter { $0.unsigned.kind == .custodyChange }
        .flatMap { $0.unsigned.custody.map(\.wallet) }
    )
    guard !walletIDs.isEmpty else { return }
    for agent in harness.agents {
      agent.pendingBroadcasts.removeAll { walletIDs.contains($0.sourceID) }
    }
  }

  /// Every agent financial envelope is an effect checkpoint for one exact
  /// command in the unsigned action journal. The signed envelope remains the
  /// accounting authority, but a persisted world must not be able to remove,
  /// shrink, or reorder the command journal and still replay the debit.
  private func validatePersistedAgentActionBindings() throws {
    var actionEvents:
      [String: (
        eventIndex: Int,
        agentID: String,
        commands: [String],
        actionIndexes: [UInt64]
      )] = [:]
    var envelopeEventIndexes: [WorldOperationIdentity: [Int]] = [:]
    var seenEventIdentities = Set<WorldOperationIdentity>()
    var seenOperationIdentities = Set<WorldOperationIdentity>()

    for (index, event) in document.events.enumerated() {
      switch event {
      case .actions(
        let operationID, let agentID, let commands, let actionIndexes, _, _, _
      ):
        guard actionEvents[operationID] == nil else {
          throw MikroKhorosError.persistence(
            "the world contains duplicate action journals for one operation"
          )
        }
        guard actionIndexes.count == commands.count,
          zip(actionIndexes, actionIndexes.dropFirst()).allSatisfy({ $0 < $1 })
        else {
          throw MikroKhorosError.persistence(
            "an action event has missing, duplicate, or reordered action indexes"
          )
        }
        actionEvents[operationID] = (
          eventIndex: index,
          agentID: agentID,
          commands: commands,
          actionIndexes: actionIndexes
        )
      case .operationEnvelope(let envelope):
        let identity = WorldOperationIdentity(
          operationID: envelope.operationID,
          actionIndex: envelope.actionIndex
        )
        guard seenEventIdentities.insert(identity).inserted else {
          throw MikroKhorosError.persistence(
            "the world contains duplicate operation envelopes"
          )
        }
        envelopeEventIndexes[identity, default: []].append(index)
      default:
        continue
      }
    }

    var operationEntries: [String: [(actionIndex: UInt64, eventIndex: Int)]] = [:]
    for envelope in document.operations {
      let identity = WorldOperationIdentity(
        operationID: envelope.operationID,
        actionIndex: envelope.actionIndex
      )
      guard seenOperationIdentities.insert(identity).inserted else {
        throw MikroKhorosError.persistence(
          "the world contains duplicate operation envelopes"
        )
      }
      guard let eventIndexes = envelopeEventIndexes[identity], eventIndexes.count == 1 else {
        throw MikroKhorosError.persistence(
          "the operation index is missing its unique ordered envelope event"
        )
      }
      let isAgentFinancialEnvelope =
        envelope.actor == CreditActor.agent.rawValue
        && (!envelope.signedCreditRecords.isEmpty || !envelope.purchases.isEmpty)
      guard isAgentFinancialEnvelope else { continue }
      guard let action = actionEvents[envelope.operationID] else {
        throw MikroKhorosError.persistence(
          "an agent financial envelope has no corresponding action journal"
        )
      }
      guard action.eventIndex < eventIndexes[0],
        action.actionIndexes.contains(envelope.actionIndex)
      else {
        throw MikroKhorosError.persistence(
          "an agent financial envelope is not bound to one persisted command"
        )
      }
      if !envelope.purchases.isEmpty {
        guard envelope.purchases.count == 1,
          let purchase = envelope.purchases.first,
          action.agentID == purchase.buyerAgentID,
          let commandOffset = action.actionIndexes.firstIndex(of: envelope.actionIndex),
          commandOffset < action.commands.count
        else {
          throw MikroKhorosError.persistence(
            "a purchase envelope is not bound to its canonical buy command"
          )
        }
        let command = action.commands[commandOffset]
        guard let purchaseArguments = persistedPurchaseActionArguments(command),
          purchaseArguments.walletID == purchase.payerWalletID,
          !purchaseArguments.itemSelector.isEmpty,
          purchase.itemID == purchaseArguments.itemSelector
            || purchase.itemID.hasPrefix(purchaseArguments.itemSelector)
        else {
          throw MikroKhorosError.persistence(
            "a purchase envelope is not bound to its canonical buy command"
          )
        }
      }
      operationEntries[envelope.operationID, default: []].append(
        (actionIndex: envelope.actionIndex, eventIndex: eventIndexes[0])
      )
    }

    for entries in operationEntries.values {
      let ordered = entries.sorted { $0.actionIndex < $1.actionIndex }
      guard zip(ordered, ordered.dropFirst()).allSatisfy({ $0.eventIndex < $1.eventIndex }) else {
        throw MikroKhorosError.persistence(
          "operation envelope events are reordered relative to their action indexes"
        )
      }
    }
  }

  private func validatePersistedOperationJournal(
    expectedCredit: CreditServiceSnapshot? = nil
  ) throws {
    let eventEnvelopes = document.events.compactMap { event -> WorldOperationEnvelope? in
      guard case .operationEnvelope(let envelope) = event else { return nil }
      return envelope
    }
    guard eventEnvelopes == document.operations else {
      throw MikroKhorosError.persistence(
        "the world operation index does not match its ordered event journal"
      )
    }
    try validatePersistedAgentActionBindings()
    var seenOperations: [WorldOperationIdentity: WorldOperationEnvelope] = [:]
    var flattened: [SignedCreditRecord] = []
    var seenRecords = Set<String>()
    var seenUnread = Set<String>()
    var seenAcknowledgements = Set<String>()
    var seenReceipts = Set<String>()
    var seenActivity = Set<String>()
    for envelope in eventEnvelopes {
      try envelope.validateForPersistence()
      guard envelope.worldID == harness.world.hash else {
        throw MikroKhorosError.persistence("the world contains an invalid operation envelope")
      }
      let operation = WorldOperationIdentity(
        operationID: envelope.operationID,
        actionIndex: envelope.actionIndex
      )
      if let existing = seenOperations[operation] {
        throw MikroKhorosError.persistence(
          existing == envelope
            ? "the world contains duplicate operation envelopes"
            : "the world contains conflicting operation envelopes"
        )
      }
      seenOperations[operation] = envelope
      guard
        envelope.signedCreditRecords.allSatisfy({
          $0.unsigned.operationID == envelope.operationID
            && $0.unsigned.worldID == envelope.worldID
        })
      else {
        throw MikroKhorosError.persistence(
          "an operation envelope contains a credit record for another operation"
        )
      }
      for record in envelope.signedCreditRecords {
        guard seenRecords.insert(record.recordID).inserted else {
          throw MikroKhorosError.persistence(
            "the world operation journal repeats a credit record"
          )
        }
        flattened.append(record)
      }
      for unread in envelope.unread {
        let identity = "\(unread.sourceID)#\(unread.eventID)"
        guard seenUnread.insert(identity).inserted else {
          throw MikroKhorosError.persistence(
            "the world operation journal repeats a wallet notification"
          )
        }
      }
      for acknowledgement in envelope.acknowledgements {
        let identity =
          "\(acknowledgement.sourceID)#\(acknowledgement.eventID)#\(acknowledgement.agentID)"
        guard seenAcknowledgements.insert(identity).inserted else {
          throw MikroKhorosError.persistence(
            "the world operation journal repeats a notification acknowledgement"
          )
        }
      }
      for receipt in envelope.receipts {
        guard seenReceipts.insert(receipt.id).inserted else {
          throw MikroKhorosError.persistence(
            "the world operation journal repeats an operation receipt"
          )
        }
      }
      for activityRecord in envelope.activity {
        guard seenActivity.insert(activityRecord.id).inserted else {
          throw MikroKhorosError.persistence(
            "the world operation journal repeats an activity record"
          )
        }
      }
    }

    let expectedChain = expectedCredit?.chain ?? creditService.chain
    guard flattened == expectedChain else {
      throw MikroKhorosError.persistence(
        "the persisted signed credit chain does not match its operation envelopes"
      )
    }
    guard creditService.chain == expectedChain else {
      throw MikroKhorosError.persistence(
        "replaying the world changed the persisted signed credit chain"
      )
    }
  }

  private func validateLoadedWorldState() throws {
    guard pendingReplayCustodyTransitions.isEmpty else {
      throw MikroKhorosError.persistence(
        "the replayed graph contains an owner change without a custody envelope"
      )
    }
    let index = try ObjectLocationIndex(
      world: harness.world,
      registeredObjects: harness.objects,
      agents: harness.agents,
      maxDepth: try worldLocationIndexDepth(
        configuration.runtime.maximumObjectInvocationDepth
      )
    )
    let worldAgents = Dictionary(uniqueKeysWithValues: document.agents.map { ($0.id, $0) })
    let registeredWallets = creditService.registrations
    guard registeredWallets.count == worldAgents.count else {
      throw MikroKhorosError.persistence(
        "the world wallet registrations do not match its agent graph"
      )
    }
    for record in document.agents {
      guard let agent = harness.findAgent(record.id),
        agent.name == record.name,
        agent.backpack.hash == record.genesis.backpack,
        agent.wallet.hash == record.genesis.wallet,
        let registration = creditService.registration(for: agent.wallet.hash),
        registration.walletID == agent.wallet.hash,
        registration.agentID == agent.hash,
        registration.issuerID == agent.hash,
        registration.worldID == harness.world.hash,
        registration.backpackID == agent.backpack.hash,
        registration.coordinate == Coordinate(x: 4, y: 0),
        harness.findObject(agent.wallet.hash) === agent.wallet,
        agent.wallet.origin == .genesis,
        index.location(for: agent.wallet.hash) != nil,
        let issuance = creditService.chain.first(where: {
          $0.unsigned.kind == .registration
            && $0.unsigned.accounts == [agent.wallet.hash]
        }),
        issuance.unsigned.issuanceAgentID == agent.hash,
        issuance.unsigned.issuanceBackpackID == agent.backpack.hash,
        issuance.unsigned.issuanceCoordinate == Coordinate(x: 4, y: 0),
        issuance.unsigned.issuanceLocationCommitment?.isEmpty == false,
        issuance.unsigned.owner == agent.hash,
        creditService.custodyCommitment(for: agent.wallet.hash)?.isEmpty == false,
        creditService.custodyLocationCommitment(for: agent.wallet.hash)?.isEmpty == false
      else {
        throw MikroKhorosError.persistence(
          "the world wallet registration does not match its exact genesis provenance"
        )
      }

      // Issuance provenance is immutable, but custody is not. A wallet may
      // later be held by another agent or placed in world space without a
      // signed record for every same-owner move. Compare only the current
      // bearer projection here; owner-changing location commitments are
      // checked at their operation-envelope boundary during replay.
      let indexedOwner = index.currentOwner(of: agent.wallet)?.agentID
      guard indexedOwner == creditService.custodyOwner(for: agent.wallet.hash) else {
        throw MikroKhorosError.persistence(
          "the registered wallet current owner conflicts with its credit projection"
        )
      }
    }
    for registration in registeredWallets {
      guard
        worldAgents.values.contains(where: {
          $0.id == registration.agentID && $0.genesis.wallet == registration.walletID
        })
      else {
        throw MikroKhorosError.persistence(
          "the credit chain contains a wallet for an unknown agent"
        )
      }
    }
  }

  private func safeReason(_ error: Error) -> String {
    if let error = error as? MikroKhorosError { return error.description }
    return "invalid persisted state"
  }
}

extension WorldRuntime: NativeObjectManagementProvider {
  public func managementInterface(for object: MikroObject) throws -> ObjectManagementInterface {
    try requireRegisteredNativeObject(object)
    switch object {
    case is WalletObject:
      return try Self.walletManagementInterface()
    case is MessengerObject:
      return try Self.messengerManagementInterface()
    case is ObjectiveBoardObject:
      return try Self.objectiveBoardManagementInterface()
    default:
      throw MikroKhorosError.runtime(
        "object.management_unavailable",
        "the selected object has no trusted native management provider"
      )
    }
  }

  @discardableResult
  public func runManagementAction(
    _ actionID: String,
    inputs: [String],
    on object: MikroObject
  ) throws -> JSONValue {
    try requireRegisteredNativeObject(object)
    switch object {
    case let wallet as WalletObject:
      return try runWalletManagementAction(
        actionID,
        inputs: inputs,
        wallet: wallet,
        operationID: CreditService.makeID()
      )
    case let messenger as MessengerObject:
      return try runMessengerManagementAction(actionID, inputs: inputs, messenger: messenger)
    case let board as ObjectiveBoardObject:
      return try runObjectiveBoardManagementAction(actionID, inputs: inputs, board: board)
    default:
      throw MikroKhorosError.runtime(
        "object.management_unavailable",
        "the selected object has no trusted native management provider"
      )
    }
  }

  private func nativeMessengerAgent(_ messenger: MessengerObject) throws -> Agent {
    guard
      let record = document.agents.first(where: {
        $0.genesis.messenger == messenger.hash
      }), let agent = harness.findAgent(record.id),
      (try? harness.messenger(for: agent)) === messenger
    else {
      throw MikroKhorosError.runtime(
        "messenger.management_identity_invalid",
        "the selected messenger is not bound to its exact world agent"
      )
    }
    return agent
  }

  private func mergedNativeMessengerMessages(
    _ messenger: MessengerObject
  ) throws -> [MessengerMessage] {
    let agent = try nativeMessengerAgent(messenger)
    var merged = messenger.messages
    let humanMessages = try harness.humanInbox(for: agent)
    for humanMessage in humanMessages {
      if let index = merged.firstIndex(where: { $0.id == humanMessage.id }) {
        // The durable human inbox is authoritative for its own messages,
        // especially read state; the source sent copy is only a transcript.
        merged[index] = humanMessage
      } else {
        merged.append(humanMessage)
      }
    }
    return merged
  }

  public func renderManagementView(_ viewID: String, on object: MikroObject) throws -> JSONValue {
    try requireRegisteredNativeObject(object)
    switch object {
    case let wallet as WalletObject:
      let creditService = self.creditService
      switch viewID {
      case "balance":
        let balance = try creditService.balance(for: wallet.hash)
        let mode = try creditService.mode(for: wallet.hash)
        return .object([
          "wallet_id": .string(wallet.hash),
          "balance": .string(balance.decimalText),
          "mode": .string(mode.rawValue),
        ])
      case "statement":
        let modesByRecordID = try walletModesByRecordID()
        let records = creditService.chain
          .filter { $0.unsigned.accounts.contains(wallet.hash) }
          .suffix(128)
          .reversed()
        return .array(
          records.map { record in
            let index = record.unsigned.accounts.firstIndex(of: wallet.hash)!
            return .object([
              "event_id": .string(record.recordID),
              "transaction_id": .string(record.unsigned.transactionID),
              "kind": .string(record.unsigned.kind.rawValue),
              "delta": .string(record.unsigned.amounts[index].decimalText),
              "resulting_balance": .string(record.unsigned.postBalances[index].decimalText),
              "mode": .string(
                modesByRecordID[record.recordID]?[wallet.hash]?.rawValue
                  ?? record.unsigned.mode.rawValue
              ),
              "timestamp": .string(ISO8601DateFormatter().string(from: record.unsigned.time)),
              "note": .string(record.unsigned.note),
            ])
          })
      case "verify":
        try creditService.verify()
        return .object(["verified": .bool(true), "wallet_id": .string(wallet.hash)])
      default:
        throw MikroKhorosError.runtime("object.management_view_unknown", "unknown wallet view")
      }
    case let messenger as MessengerObject:
      let mergedMessages = try mergedNativeMessengerMessages(messenger)
      switch viewID {
      case "threads":
        return .array(
          messenger.threads.map { thread in
            .object([
              "id": .string(thread.id),
              "title": .string(thread.title),
              "unread": .number(
                Double(
                  mergedMessages.filter {
                    $0.threadID == thread.id && !$0.isRead
                  }.count)),
            ])
          })
      case "inbox", "unread":
        let messages = mergedMessages.filter { viewID == "inbox" || !$0.isRead }.suffix(128)
        return .array(messages.map(Self.messageJSON))
      default:
        throw MikroKhorosError.runtime("object.management_view_unknown", "unknown messenger view")
      }
    case let board as ObjectiveBoardObject:
      let objectives = board.container?.items.compactMap { $0.object as? ObjectiveObject } ?? []
      switch viewID {
      case "objectives":
        return .array(objectives.sorted { $0.hash < $1.hash }.map(Self.objectiveJSON))
      case "attention":
        let acknowledged = Set(
          document.events.compactMap { event -> ObjectiveAcknowledgementKey? in
            guard
              case .objectiveAcknowledged(let boardID, let objectiveID, let eventID) = event,
              boardID == board.hash
            else { return nil }
            return ObjectiveAcknowledgementKey(
              boardID: boardID,
              objectiveID: objectiveID,
              eventID: eventID
            )
          }
        )
        // Attention is the unseen projection over exact objective/submission
        // identities. Acknowledgements remain append-only receipts and never
        // remove the underlying objective or its activity history. The bound
        // is applied after filtering so acknowledged entries do not hide later
        // unseen work.
        let events: [JSONValue] = objectives.sorted { $0.hash < $1.hash }.flatMap {
          objective -> [JSONValue] in
          if objective.objectiveRecords.isEmpty {
            let key = ObjectiveAcknowledgementKey(
              boardID: board.hash,
              objectiveID: objective.hash,
              eventID: objective.hash
            )
            guard !acknowledged.contains(key) else { return [] }
            return [
              .object([
                "objective_id": .string(objective.hash),
                "event_id": .string(objective.hash),
                "kind": .string("objective"),
                "title": .string(objective.title),
                "body": .string(objective.body),
                "timestamp": .string(ISO8601DateFormatter().string(from: objective.createdAt)),
              ])
            ]
          }
          return objective.objectiveRecords.compactMap { record in
            let key = ObjectiveAcknowledgementKey(
              boardID: board.hash,
              objectiveID: objective.hash,
              eventID: record.id
            )
            guard !acknowledged.contains(key) else { return nil }
            return .object([
              "objective_id": .string(objective.hash),
              "event_id": .string(record.id),
              "kind": .string(record.kind.rawValue),
              "agent_id": .string(record.agentID),
              "body": .string(record.body),
              "timestamp": .string(ISO8601DateFormatter().string(from: record.timestamp)),
            ])
          }
        }
        return .array(Array(events.prefix(128)))
      case "activity":
        return .array(activity.map { Self.activityJSON($0) })
      default:
        throw MikroKhorosError.runtime(
          "object.management_view_unknown", "unknown Objective Board view")
      }
    default:
      throw MikroKhorosError.runtime(
        "object.management_unavailable",
        "the selected object has no trusted native management provider"
      )
    }
  }

  private func requireRegisteredNativeObject(_ object: MikroObject) throws {
    guard nativeManagedObject(for: object) != nil else {
      throw MikroKhorosError.runtime(
        "object.management_identity_invalid",
        "the selected object is not the exact trusted native world instance"
      )
    }
  }

  private func walletServiceUnavailable() -> MikroKhorosError {
    .runtime("wallet.unavailable", "the wallet service is unavailable")
  }

  private func runWalletManagementAction(
    _ actionID: String,
    inputs: [String],
    wallet: WalletObject,
    operationID: String
  ) throws -> JSONValue {
    let creditService = self.creditService
    guard creditService.registration(for: wallet.hash) != nil else {
      throw MikroKhorosError.runtime(
        "wallet.unknown", "the wallet is not registered in this world")
    }
    switch actionID {
    case "deposit":
      guard inputs.count == 1 || inputs.count == 2 else {
        throw nativeManagementInputError("deposit requires amount and an optional note")
      }
      let amount = try CreditAmount.parse(inputs[0])
      let note = try nativeManagementNote(inputs, index: 1)
      let previousChain = creditService.chain
      let balance = try creditService.deposit(
        walletID: wallet.hash,
        amount: amount,
        actor: .human,
        operationID: operationID,
        note: note
      )
      document.credit = creditService.snapshot()
      try appendCreditOperation(
        records: creditRecords(after: creditService.chain, comparedTo: previousChain),
        actor: CreditActor.human.rawValue
      )
      return .object(["wallet_id": .string(wallet.hash), "balance": .string(balance.decimalText)])
    case "deduct":
      guard inputs.count == 1 || inputs.count == 2 else {
        throw nativeManagementInputError("deduct requires amount and an optional note")
      }
      let amount = try CreditAmount.parse(inputs[0])
      let note = try nativeManagementNote(inputs, index: 1)
      let previousChain = creditService.chain
      let balance = try creditService.deduct(
        walletID: wallet.hash,
        amount: amount,
        actor: .human,
        operationID: operationID,
        allowExposure: true,
        sourceOwner: creditService.custodyOwner(for: wallet.hash),
        sourceCustodyCommitment: creditService.custodyCommitment(for: wallet.hash),
        note: note
      )
      document.credit = creditService.snapshot()
      try appendCreditOperation(
        records: creditRecords(after: creditService.chain, comparedTo: previousChain),
        actor: CreditActor.human.rawValue
      )
      return .object(["wallet_id": .string(wallet.hash), "balance": .string(balance.decimalText)])
    case "setMode", "set-mode":
      guard inputs.count == 1 || inputs.count == 2,
        let mode = WalletMode(rawValue: inputs[0])
      else {
        throw nativeManagementInputError(
          "setMode requires finite or unlimited and an optional note")
      }
      let note = try nativeManagementNote(inputs, index: 1)
      let previousChain = creditService.chain
      try creditService.setMode(
        walletID: wallet.hash,
        mode: mode,
        actor: .human,
        operationID: operationID,
        note: note
      )
      document.credit = creditService.snapshot()
      try appendCreditOperation(
        records: creditRecords(after: creditService.chain, comparedTo: previousChain),
        actor: CreditActor.human.rawValue
      )
      return .object(["wallet_id": .string(wallet.hash), "mode": .string(mode.rawValue)])
    default:
      throw MikroKhorosError.runtime("object.management_action_unknown", "unknown wallet action")
    }
  }

  private func runMessengerManagementAction(
    _ actionID: String,
    inputs: [String],
    messenger: MessengerObject
  ) throws -> JSONValue {
    switch actionID {
    case "send":
      guard inputs.count == 3 || inputs.count == 4 else {
        throw nativeManagementInputError(
          "send requires recipient, thread, body, and optional priority")
      }
      let recipient = try harness.resolveAgent(inputs[0])
      let destination = try harness.messenger(for: recipient)
      let priority = inputs.count == 4 ? try BroadcastPriority.parse(inputs[3]) : nil
      let threadID = inputs[1]
      _ = try destination.ensureThread(
        id: threadID, title: threadID == "#1" ? "Messages" : threadID)
      let message = try harness.deliverMessage(
        to: destination,
        body: inputs[2],
        id: harness.nextRuntimeIdentity(),
        sender: "human",
        threadID: threadID,
        priority: priority,
        timestamp: harness.runtimeDate()
      )
      document.events.append(
        .message(
          messengerID: destination.hash,
          id: message.id,
          body: message.body,
          sender: message.sender,
          senderAgentID: message.senderAgentID,
          threadID: message.threadID,
          priority: message.priority,
          timestamp: message.timestamp
        )
      )
      return .object(["message_id": .string(message.id), "recipient": .string(recipient.hash)])
    case "read", "ack", "acknowledge":
      guard inputs.count == 1 else { throw nativeManagementInputError("ack requires event_id") }
      let owner = try nativeMessengerAgent(messenger)
      if let humanMessage = try harness.humanInbox(for: owner).first(where: {
        $0.id == inputs[0]
      }) {
        let changed = try harness.acknowledgeHumanInbox(for: owner, messageID: humanMessage.id)
        if changed {
          document.events.append(
            .humanInboxAcknowledged(agentID: owner.hash, messageID: humanMessage.id)
          )
          try appendReceiptOperation(
            operationID: CreditService.makeID(),
            kind: "human_inbox_acknowledgement",
            value: "human#\(owner.hash)#\(humanMessage.id)"
          )
        }
        return .object(["acknowledged": .bool(changed)])
      }
      let changed = messenger.acknowledge(eventID: inputs[0])
      if changed {
        document.events.append(
          .messengerAcknowledged(messengerID: messenger.hash, messageID: inputs[0])
        )
        try appendReceiptOperation(
          operationID: CreditService.makeID(),
          kind: "messenger_acknowledgement",
          value: "messenger#\(messenger.hash)#\(inputs[0])"
        )
      }
      return .object(["acknowledged": .bool(changed)])
    default:
      throw MikroKhorosError.runtime("object.management_action_unknown", "unknown messenger action")
    }
  }

  private func runObjectiveBoardManagementAction(
    _ actionID: String,
    inputs: [String],
    board: ObjectiveBoardObject
  ) throws -> JSONValue {
    switch actionID {
    case "post":
      guard inputs.count == 2 else {
        throw nativeManagementInputError("post requires title and body")
      }
      let objective = try postObjective(title: inputs[0], body: inputs[1])
      return .object(["objective_id": .string(objective.hash)])
    case "ack", "acknowledge":
      guard inputs.count == 1 else {
        throw nativeManagementInputError("ack requires an exact event_id")
      }
      let acknowledged = try acknowledgeObjectiveEvent(board: board, eventID: inputs[0])
      return .object(["acknowledged": .bool(acknowledged), "event_id": .string(inputs[0])])
    default:
      throw MikroKhorosError.runtime(
        "object.management_action_unknown", "unknown Objective Board action")
    }
  }

  private func nativeManagementInputError(_ message: String) -> MikroKhorosError {
    .runtime("object.management_input_invalid", message)
  }

  private func nativeManagementNote(_ inputs: [String], index: Int) throws -> String {
    guard inputs.count > index else { return "" }
    let note = inputs[index]
    guard note.count <= 256, !note.contains(where: { $0.isNewline }) else {
      throw nativeManagementInputError(
        "the optional note must be at most 256 characters on one line")
    }
    return note
  }

  private func parseNativeBool(_ value: String) throws -> Bool {
    switch value.lowercased() {
    case "true", "1", "yes": return true
    case "false", "0", "no": return false
    default: throw nativeManagementInputError("boolean input must be true or false")
    }
  }

  private static func walletManagementInterface() throws -> ObjectManagementInterface {
    return try ObjectManagementInterface(
      actions: [
        try ManagementAction(
          id: "deposit", summary: "Deposit credit as the human administrator.",
          parameters: ["amount", "note"],
          inputTypes: ["amount": .decimal, "note": .text],
          inputDefaults: ["note": .string("")],
          mutating: true, scope: .world, action: try DeclarativeAction(kind: .return)
        ),
        try ManagementAction(
          id: "deduct", summary: "Deduct credit as the human administrator.",
          parameters: ["amount", "note"],
          inputTypes: ["amount": .decimal, "note": .text],
          inputDefaults: ["note": .string("")],
          mutating: true, scope: .world,
          action: try DeclarativeAction(kind: .return)
        ),
        try ManagementAction(
          id: "setMode", summary: "Set finite or unlimited purchase mode.",
          parameters: ["mode", "note"],
          inputTypes: ["mode": .choice, "note": .text],
          inputDefaults: ["note": .string("")],
          inputChoices: ["mode": WalletMode.allCases.map(\.rawValue)],
          mutating: true, scope: .world,
          action: try DeclarativeAction(kind: .return)
        ),
      ],
      views: [
        try ManagementView(id: "balance", source: "state", scope: .world),
        try ManagementView(id: "statement", source: "state", scope: .world),
        try ManagementView(id: "verify", source: "state", scope: .world),
      ]
    )
  }

  private static func messengerManagementInterface() throws -> ObjectManagementInterface {
    try ObjectManagementInterface(
      actions: [
        try ManagementAction(
          id: "send", summary: "Send a human-mediated message to one agent.",
          parameters: ["recipient", "thread", "body", "priority_optional"],
          mutating: true, scope: .world, action: try DeclarativeAction(kind: .return)
        ),
        try ManagementAction(
          id: "read", summary: "Mark one exact message as read.",
          parameters: ["event_id"],
          mutating: true, scope: .world, action: try DeclarativeAction(kind: .return)
        ),
        try ManagementAction(
          id: "ack", summary: "Acknowledge one exact unread message.", parameters: ["event_id"],
          mutating: true, scope: .world, action: try DeclarativeAction(kind: .return)
        ),
      ],
      views: [
        try ManagementView(id: "threads", source: "state", scope: .world),
        try ManagementView(id: "inbox", source: "state", scope: .world),
        try ManagementView(id: "unread", source: "state", scope: .world),
      ]
    )
  }

  private static func objectiveBoardManagementInterface() throws -> ObjectManagementInterface {
    try ObjectManagementInterface(
      actions: [
        try ManagementAction(
          id: "post", summary: "Post an objective without a review or payment gate.",
          parameters: ["title", "body"], mutating: true, scope: .world,
          action: try DeclarativeAction(kind: .return)
        ),
        try ManagementAction(
          id: "ack",
          summary: "Acknowledge one exact objective or submission event.",
          parameters: ["event_id"],
          mutating: true,
          scope: .world,
          action: try DeclarativeAction(kind: .return)
        ),
      ],
      views: [
        try ManagementView(id: "objectives", source: "state", scope: .world),
        try ManagementView(id: "attention", source: "state", scope: .world),
        try ManagementView(id: "activity", source: "state", scope: .world),
      ]
    )
  }

  private static func messageJSON(_ message: MessengerMessage) -> JSONValue {
    .object([
      "id": .string(message.id),
      "thread": .string(message.threadID),
      "sender": .string(message.sender),
      "body": .string(message.body),
      "read": .bool(message.isRead),
      "timestamp": .string(ISO8601DateFormatter().string(from: message.timestamp)),
    ])
  }

  private static func objectiveJSON(_ objective: ObjectiveObject) -> JSONValue {
    let status = objective.participantAgentIDs.isEmpty ? "open" : "in_progress"
    return .object([
      "id": .string(objective.hash),
      "title": .string(objective.title),
      "body": .string(objective.body),
      "status": .string(status),
    ])
  }

  private static func activityJSON(_ record: ActivityRecord) -> JSONValue {
    .object([
      "id": .string(record.id),
      "operation": .string(record.operation),
      "success": .bool(record.success),
      "code": record.code.map(JSONValue.string) ?? .null,
      "timestamp": .string(ISO8601DateFormatter().string(from: record.timestamp)),
    ])
  }
}

public enum WorldStore {
  public static var directoryURL: URL {
    MikroKhorosPaths.root.appendingPathComponent("worlds", isDirectory: true)
  }

  public static func url(for worldID: String) throws -> URL {
    guard InventoryIdentity.isValid(worldID) else {
      throw MikroKhorosError.runtime(
        "world.identity_invalid",
        "the world id must be a complete runtime-issued identity"
      )
    }
    return directoryURL.appendingPathComponent("\(worldID).json", isDirectory: false)
  }

  public static func load(
    from url: URL,
    maximumBytes: Int = RuntimeLimits.defaults.maximumWorldBytes
  ) throws -> WorldDocument {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw MikroKhorosError.runtime(
        "world.not_found",
        "the selected world document is unavailable"
      )
    }
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      if let size = values.fileSize, size > maximumBytes {
        throw MikroKhorosError.persistence("world exceeds the configured byte limit")
      }
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(WorldDocument.self, from: data)
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.persistence("could not read the world JSON")
    }
  }

  public static func save(
    _ document: WorldDocument,
    to url: URL,
    maximumBytes: Int = RuntimeLimits.defaults.maximumWorldBytes
  ) throws {
    guard document.schemaVersion == WorldDocument.currentSchemaVersion else {
      throw MikroKhorosError.persistence(
        "unsupported world schema version found \(document.schemaVersion); required \(WorldDocument.currentSchemaVersion)"
      )
    }
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
        throw MikroKhorosError.persistence("world exceeds the configured byte limit")
      }
      try AtomicFileStore.write(data, to: url, lockURL: url.appendingPathExtension("lock"))
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.persistence("could not write the world JSON")
    }
  }
}
