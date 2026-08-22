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

#if os(Windows)
  import WinSDK
#endif

public enum FirstPartyPackageID {
  public static let userWorkspace = "org.mikrokhoros.user-workspace"
  public static let pencil = "org.mikrokhoros.pencil"
  public static let printer = "org.mikrokhoros.printer"
  public static let paper = "org.mikrokhoros.paper"
  public static let athena = "org.mikrokhoros.athena"
  public static let objectiveBoard = "org.mikrokhoros.objective-board"
  public static let library = "org.mikrokhoros.library"
  public static let warehouse = "org.mikrokhoros.warehouse"
  public static let marketplace = "org.mikrokhoros.marketplace"

  public static let all = [
    userWorkspace, pencil, printer, paper, athena, objectiveBoard, library, warehouse,
    marketplace,
  ]
}

public protocol AnchoredWorldObject: AnyObject {}

public enum FirstPartyPackageCatalog {
  public static var available: [ObjectPackageManifest] {
    FirstPartyPackageID.all.compactMap { try? manifest(named: $0) }
  }

  public static func manifest(named name: String) throws -> ObjectPackageManifest {
    let id: String
    switch name {
    case "user-workspace", FirstPartyPackageID.userWorkspace: id = FirstPartyPackageID.userWorkspace
    case "pencil", FirstPartyPackageID.pencil: id = FirstPartyPackageID.pencil
    case "printer", FirstPartyPackageID.printer: id = FirstPartyPackageID.printer
    case "paper", FirstPartyPackageID.paper: id = FirstPartyPackageID.paper
    case "athena", FirstPartyPackageID.athena: id = FirstPartyPackageID.athena
    case "objective-board", FirstPartyPackageID.objectiveBoard:
      id = FirstPartyPackageID.objectiveBoard
    case "library", FirstPartyPackageID.library: id = FirstPartyPackageID.library
    case "warehouse", FirstPartyPackageID.warehouse: id = FirstPartyPackageID.warehouse
    case "marketplace", FirstPartyPackageID.marketplace: id = FirstPartyPackageID.marketplace
    default:
      throw MikroKhorosError.runtime(
        "object_package.builtin_not_found",
        "the requested built-in object package does not exist",
        details: ["package": name]
      )
    }
    let installation = PackageInstallationPolicy(
      onInstall: .createInventoryObject,
      additionalInventoryObjects: .allow
    )
    let templateInstallation = PackageInstallationPolicy(
      onInstall: .registerOnly,
      additionalInventoryObjects: .allow
    )
    switch id {
    case FirstPartyPackageID.userWorkspace:
      let actions = [
        try ManagementAction(
          id: "mount-add",
          summary: "Attach a host folder to this user-workspace source.",
          parameters: ["name", "path", "x", "y", "access", "auto-adapt"],
          inputTypes: [
            "path": .path, "x": .integer, "y": .integer, "access": .choice,
            "auto-adapt": .boolean,
          ],
          inputDefaults: [
            "x": .number(0), "y": .number(0), "access": .string("read-only"),
            "auto-adapt": .bool(false),
          ],
          inputChoices: ["access": ["read-only", "read-write"]],
          mutating: true,
          scope: .both,
          action: try DeclarativeAction(kind: .return)
        ),
        try ManagementAction(
          id: "mount-update",
          summary: "Replace one named host-folder binding.",
          parameters: ["name", "path", "x", "y", "access", "auto-adapt"],
          inputTypes: [
            "path": .path, "x": .integer, "y": .integer, "access": .choice,
            "auto-adapt": .boolean,
          ],
          inputDefaults: [
            "x": .number(0), "y": .number(0), "access": .string("read-only"),
            "auto-adapt": .bool(false),
          ],
          inputChoices: ["access": ["read-only", "read-write"]],
          mutating: true,
          scope: .both,
          action: try DeclarativeAction(kind: .return)
        ),
        try ManagementAction(
          id: "mount-remove",
          summary: "Remove one named host-folder binding.",
          parameters: ["name"],
          mutating: true,
          scope: .both,
          action: try DeclarativeAction(kind: .return)
        ),
      ]
      return try ObjectPackageManifest(
        id: id,
        version: "1.0.0",
        displayName: "User Workspace",
        runtime: .nativeSwift,
        requestedCapabilities: [.userMachine],
        installation: installation,
        object: DeclarativeObjectDefinition(
          type: "user-workspace.object",
          name: "user-workspace",
          summary: "Live folders selected by the human user.",
          container: true,
          invocationAccess: .surface,
          functions: [
            "status": try DeclarativeFunctionDefinition(
              audience: .agent,
              action: try DeclarativeAction(kind: .return)
            )
          ]
        ),
        management: try ObjectManagementInterface(
          actions: actions,
          views: [
            try ManagementView(id: "mounts", source: "state", scope: .both),
            try ManagementView(id: "readiness", source: "state", scope: .both),
          ]
        )
      )
    case FirstPartyPackageID.pencil:
      return try ObjectPackageManifest(
        id: id,
        version: "1.0.0",
        displayName: "Pencil",
        runtime: .nativeSwift,
        requestedCapabilities: [.worldWrite],
        installation: installation,
        object: DeclarativeObjectDefinition(
          type: "pencil.object",
          name: "pencil",
          summary: "Writes to a compatible neighboring object.",
          durability: 100,
          functions: [
            "write": try nativeFunction(parameters: ["dx", "dy", "text"]),
            "append": try nativeFunction(parameters: ["dx", "dy", "text"]),
            "clear": try nativeFunction(parameters: ["dx", "dy"]),
          ]
        )
      )
    case FirstPartyPackageID.printer:
      return try ObjectPackageManifest(
        id: id,
        version: "1.0.0",
        displayName: "Printer",
        runtime: .nativeSwift,
        requestedCapabilities: [.worldWrite],
        installation: installation,
        object: DeclarativeObjectDefinition(
          type: "printer.object",
          name: "printer",
          summary: "Writes text to a compatible object at its output delta.",
          durability: 100,
          invocationAccess: .surface,
          functions: ["print": try nativeFunction(parameters: ["text"])]
        ),
        management: try ObjectManagementInterface(
          fields: [
            try ManagementField(
              id: "output_x", label: "Output X", kind: .integer,
              defaultValue: .number(0)),
            try ManagementField(
              id: "output_y", label: "Output Y", kind: .integer,
              defaultValue: .number(-1)),
          ],
          actions: [
            try ManagementAction(
              id: "set-output-delta",
              summary: "Set the output position for this concrete printer.",
              parameters: ["x", "y"],
              inputTypes: ["x": .integer, "y": .integer],
              mutating: true,
              scope: .world,
              action: try DeclarativeAction(kind: .return)
            )
          ],
          views: [try ManagementView(id: "status", source: "state", scope: .both)]
        )
      )
    case FirstPartyPackageID.paper:
      return try ObjectPackageManifest(
        id: id,
        version: "1.0.0",
        displayName: "Paper",
        runtime: .nativeSwift,
        installation: installation,
        object: DeclarativeObjectDefinition(
          type: "paper.object",
          name: "paper",
          summary: "A movable writable text surface.",
          invocationAccess: .surface,
          functions: [
            "read": try nativeFunction(audience: .agent),
            "write": try nativeFunction(parameters: ["text"], audience: .object),
            "append": try nativeFunction(parameters: ["text"], audience: .object),
            "clear": try nativeFunction(audience: .object),
          ]
        ),
        management: try ObjectManagementInterface(
          actions: [
            try ManagementAction(
              id: "read",
              summary: "Read this paper.",
              scope: .world,
              action: try DeclarativeAction(kind: .return)
            ),
            try ManagementAction(
              id: "replace",
              summary: "Replace this paper's text.",
              parameters: ["text"],
              mutating: true,
              scope: .world,
              action: try DeclarativeAction(kind: .return)
            ),
          ],
          views: [try ManagementView(id: "contents", source: "state", scope: .world)]
        )
      )
    case FirstPartyPackageID.athena:
      return try ObjectPackageManifest(
        id: id,
        version: "1.0.0",
        displayName: "Athena",
        runtime: .nativeSwift,
        installation: templateInstallation,
        object: DeclarativeObjectDefinition(
          type: "athena.object",
          name: "Athena",
          summary: "The deterministic steward of the Default Khoros facilities.",
          invocationAccess: .surface,
          functions: ["brief": try nativeFunction()]
        ),
        management: try ObjectManagementInterface(
          views: [try ManagementView(id: "facilities", source: "state", scope: .world)]
        )
      )
    case FirstPartyPackageID.objectiveBoard:
      return try ObjectPackageManifest(
        id: id,
        version: "1.0.0",
        displayName: "Objective Board",
        runtime: .nativeSwift,
        installation: templateInstallation,
        object: DeclarativeObjectDefinition(
          type: "objective-board.object",
          name: "Objective Board",
          summary: "A shared container for concrete collaborative objectives.",
          container: true,
          invocationAccess: .surface,
          functions: ["view": try nativeFunction()]
        ),
        ownedObjects: [
          try DeclarativeOwnedObjectDefinition(
            id: "index",
            coordinate: .origin,
            object: DeclarativeObjectDefinition(
              type: "objective-index.object",
              name: "Objective Index",
              summary: "Lists the objectives stored in the board.",
              invocationAccess: .surface,
              functions: ["list": try nativeFunction()]
            )
          )
        ],
        management: try ObjectManagementInterface(
          actions: [
            try ManagementAction(
              id: "post",
              summary: "Post a new objective to the shared board.",
              parameters: ["title", "body"],
              mutating: true,
              scope: .world,
              action: try DeclarativeAction(kind: .return)
            ),
            try ManagementAction(
              id: "ack",
              summary: "Acknowledge one objective or attention item.",
              parameters: ["objective_id"],
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
      )
    case FirstPartyPackageID.library:
      return try ObjectPackageManifest(
        id: id,
        version: "1.0.0",
        displayName: "Library",
        runtime: .nativeSwift,
        installation: templateInstallation,
        object: DeclarativeObjectDefinition(
          type: "library.object",
          name: "Library",
          summary: "A shared container of sourced document objects.",
          container: true,
          invocationAccess: .surface
        ),
        ownedObjects: [
          try DeclarativeOwnedObjectDefinition(
            id: "catalog",
            coordinate: .origin,
            object: DeclarativeObjectDefinition(
              type: "library-catalog.object",
              name: "Library Catalog",
              summary: "Lists the sourced documents stored in the Library.",
              invocationAccess: .surface,
              functions: ["list": try nativeFunction()]
            )
          )
        ],
        management: try ObjectManagementInterface(
          views: [try ManagementView(id: "documents", source: "state", scope: .world)]
        )
      )
    case FirstPartyPackageID.warehouse:
      return try ObjectPackageManifest(
        id: id,
        version: "1.0.0",
        displayName: "Warehouse",
        runtime: .nativeSwift,
        installation: templateInstallation,
        object: DeclarativeObjectDefinition(
          type: "warehouse.object",
          name: "Warehouse",
          summary: "A shared container for concrete tools and resources.",
          container: true,
          invocationAccess: .surface
        ),
        ownedObjects: [
          try DeclarativeOwnedObjectDefinition(
            id: "directory",
            coordinate: DefaultKhorosLayout.warehouseDirectory,
            object: DeclarativeObjectDefinition(
              type: "warehouse-directory.object",
              name: "Warehouse Directory",
              summary: "Lists concrete objects stored in the Warehouse.",
              invocationAccess: .surface,
              functions: ["list": try nativeFunction()]
            )
          )
        ],
        management: try ObjectManagementInterface(
          views: [try ManagementView(id: "contents", source: "state", scope: .world)]
        )
      )
    case FirstPartyPackageID.marketplace:
      return try ObjectPackageManifest(
        id: id,
        version: "1.0.0",
        displayName: "Marketplace",
        runtime: .nativeSwift,
        installation: templateInstallation,
        object: DeclarativeObjectDefinition(
          type: "shop.object",
          name: "Marketplace",
          summary: "An infinite shop container anchored by a Merchant.",
          container: true,
          invocationAccess: .surface
        ),
        ownedObjects: [
          try DeclarativeOwnedObjectDefinition(
            id: "merchant",
            coordinate: .origin,
            object: DeclarativeObjectDefinition(
              type: "merchant.object",
              name: "merchant",
              summary:
                "Accepts credit from an exact payer wallet and reserves concrete shop objects.",
              invocationAccess: .surface,
              functions: [
                "catalog": try nativeFunction(),
                "buy": try nativeFunction(parameters: ["item_selector", "payer_wallet_id"]),
              ]
            )
          )
        ],
        management: try ObjectManagementInterface(
          views: [try ManagementView(id: "stock", source: "state", scope: .world)]
        )
      )
    default:
      preconditionFailure("unhandled first-party package")
    }
  }

  public static func data(named name: String) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(manifest(named: name))
  }

  private static func nativeFunction(
    parameters: [String] = [],
    audience: ObjectFunctionAudience = .agent
  ) throws -> DeclarativeFunctionDefinition {
    try DeclarativeFunctionDefinition(
      parameters: parameters,
      audience: audience,
      action: DeclarativeAction(kind: .return)
    )
  }
}

struct UserFolderMount: Equatable, Sendable {
  enum Access: String, Sendable {
    case readOnly = "read-only"
    case readWrite = "read-write"
  }

  let bindingID: String
  var name: String
  var hostPath: String
  var coordinate: Coordinate
  var access: Access

  var json: JSONValue {
    .object([
      "binding_id": .string(bindingID),
      "name": .string(name),
      "host_path": .string(hostPath),
      "x": .number(Double(coordinate.x)),
      "y": .number(Double(coordinate.y)),
      "access": .string(access.rawValue),
    ])
  }

  init(json: JSONValue) throws {
    guard let value = json.objectValue,
      let bindingID = value["binding_id"]?.stringValue,
      let name = value["name"]?.stringValue,
      let hostPath = value["host_path"]?.stringValue,
      let x = value["x"]?.intValue,
      let y = value["y"]?.intValue,
      let accessText = value["access"]?.stringValue,
      let access = Access(rawValue: accessText),
      InventoryIdentity.isValid(bindingID), !name.isEmpty
    else { throw MikroKhorosError.persistence("user-workspace mount state is invalid") }
    self.bindingID = bindingID
    self.name = name
    self.hostPath = hostPath
    self.coordinate = Coordinate(x: x, y: y)
    self.access = access
  }

  init(bindingID: String, name: String, hostPath: String, coordinate: Coordinate, access: Access) {
    self.bindingID = bindingID
    self.name = name
    self.hostPath = hostPath
    self.coordinate = coordinate
    self.access = access
  }
}

struct ProjectedEntryRecord: Equatable, Sendable {
  enum Kind: String, Sendable { case folder, file, link }

  let bindingID: String
  let relativePath: String
  let parentRelativePath: String?
  let id: String
  let kind: Kind
  let coordinate: Coordinate

  var json: JSONValue {
    .object([
      "binding_id": .string(bindingID),
      "relative_path": .string(relativePath),
      "parent_relative_path": parentRelativePath.map(JSONValue.string) ?? .null,
      "id": .string(id),
      "kind": .string(kind.rawValue),
      "x": .number(Double(coordinate.x)),
      "y": .number(Double(coordinate.y)),
    ])
  }

  init(json: JSONValue) throws {
    guard let value = json.objectValue,
      let bindingID = value["binding_id"]?.stringValue,
      let relativePath = value["relative_path"]?.stringValue,
      let id = value["id"]?.stringValue,
      let kindText = value["kind"]?.stringValue,
      let kind = Kind(rawValue: kindText),
      let x = value["x"]?.intValue,
      let y = value["y"]?.intValue,
      InventoryIdentity.isValid(bindingID), InventoryIdentity.isValid(id)
    else { throw MikroKhorosError.persistence("projected object topology is invalid") }
    self.bindingID = bindingID
    self.relativePath = relativePath
    self.parentRelativePath = value["parent_relative_path"]?.stringValue
    self.id = id
    self.kind = kind
    self.coordinate = Coordinate(x: x, y: y)
  }

  init(
    bindingID: String,
    relativePath: String,
    parentRelativePath: String?,
    id: String,
    kind: Kind,
    coordinate: Coordinate
  ) {
    self.bindingID = bindingID
    self.relativePath = relativePath
    self.parentRelativePath = parentRelativePath
    self.id = id
    self.kind = kind
    self.coordinate = coordinate
  }
}

public struct FirstPartyObjectRuntimeAdapter: ObjectRuntimeAdapter {
  public let id = "org.mikrokhoros.runtime.first-party"
  public let version = "1"
  public let packageIDs = Set(FirstPartyPackageID.all)

  public init() {}

  public func validate(manifest: ObjectPackageManifest) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let canonical = try FirstPartyPackageCatalog.manifest(named: manifest.id)
    let received = try encoder.encode(manifest)
    let expected = try encoder.encode(canonical)
    guard packageIDs.contains(manifest.id), manifest.runtime == .nativeSwift,
      received == expected
    else {
      throw MikroKhorosError.runtime(
        "object_package.adapter_mismatch",
        "the built-in runtime adapter accepts only its exact signed-in package contract",
        details: [
          "received": SHA256Digest.hex(received),
          "expected": SHA256Digest.hex(expected),
        ]
      )
    }
  }

  public func externalEffects(
    for manifest: ObjectPackageManifest
  ) throws -> Set<ObjectExternalEffect> {
    try validate(manifest: manifest)
    return manifest.id == FirstPartyPackageID.userWorkspace ? [.userFolder] : []
  }

  public func makeDefaultManagementState(manifest: ObjectPackageManifest) throws
    -> [String: JSONValue]
  {
    switch manifest.id {
    case FirstPartyPackageID.userWorkspace:
      return ["mounts": .array([]), "topology": .array([])]
    case FirstPartyPackageID.printer:
      return ["output_x": .number(0), "output_y": .number(-1)]
    case FirstPartyPackageID.paper:
      return ["content": .string("")]
    case FirstPartyPackageID.pencil, FirstPartyPackageID.athena,
      FirstPartyPackageID.objectiveBoard, FirstPartyPackageID.library,
      FirstPartyPackageID.warehouse, FirstPartyPackageID.marketplace:
      return [:]
    default:
      throw MikroKhorosError.runtime("object_package.adapter_mismatch", "unsupported package")
    }
  }

  public func runInventoryAction(
    _ action: ManagementAction,
    inputs: [String],
    record: inout InventoryObjectRecord,
    limits: RuntimeLimits
  ) throws -> JSONValue {
    guard record.packageID == FirstPartyPackageID.userWorkspace else {
      throw MikroKhorosError.runtime(
        "inventory.action_scope_denied",
        "this first-party package has no Inventory-scoped action"
      )
    }
    guard record.worldBinding != nil else {
      throw MikroKhorosError.runtime(
        "user_workspace.world_binding_required",
        "host folders can be attached only to an Inventory source bound to one world",
        suggestions: ["fork the user-workspace template into the selected world first"]
      )
    }
    var mounts = try Self.mounts(from: record.managementState)
    switch action.id {
    case "mount-add", "mount-update":
      let replacement = try Self.mount(
        from: inputs, existing: mounts.first { $0.name == inputs[0] })
      if action.id == "mount-add", mounts.contains(where: { $0.name == replacement.name }) {
        throw MikroKhorosError.runtime(
          "user_workspace.mount_exists", "a mount with this name already exists")
      }
      if action.id == "mount-update" {
        guard let index = mounts.firstIndex(where: { $0.name == replacement.name }) else {
          throw MikroKhorosError.runtime(
            "user_workspace.mount_not_found", "the selected mount does not exist")
        }
        mounts[index] = replacement
      } else {
        guard mounts.count < limits.maximumMountsPerObject else {
          throw MikroKhorosError.runtime(
            "user_workspace.mount_limit",
            "the configured mount limit has been reached",
            details: ["limit": String(limits.maximumMountsPerObject)]
          )
        }
        mounts.append(replacement)
      }
    case "mount-remove":
      guard let name = inputs.first,
        let index = mounts.firstIndex(where: { $0.name == name })
      else {
        throw MikroKhorosError.runtime(
          "user_workspace.mount_not_found", "the selected mount does not exist")
      }
      mounts.remove(at: index)
    default:
      throw MikroKhorosError.runtime("inventory.action_unknown", "unknown management action")
    }
    try Self.validateMountCoordinates(&mounts, requestedName: inputs.first, autoAdapt: inputs.last)
    record.managementState["mounts"] = .array(mounts.map(\.json))
    record.managementState["topology"] = .array([])
    return .object(["mount_count": .number(Double(mounts.count))])
  }

  public func renderInventoryView(
    _ view: ManagementView,
    record: InventoryObjectRecord,
    limits: RuntimeLimits
  ) throws -> JSONValue {
    switch view.id {
    case "mounts": return record.managementState["mounts"] ?? .array([])
    case "readiness":
      let mounts = try Self.mounts(from: record.managementState)
      let projection = Self.humanProjectionStatus(mounts: mounts)
      return .object([
        "world_bound": .bool(record.worldBinding != nil),
        "mount_count": .number(Double(mounts.count)),
        "unsupported_entries": .array(projection.unsupported.map(JSONValue.string)),
        "diagnostics": .array(projection.diagnostics.map(JSONValue.string)),
      ])
    case "status": return .object(record.managementState)
    default: throw MikroKhorosError.runtime("inventory.view_unknown", "unknown management view")
    }
  }

  public func captureDeploymentState(
    record: InventoryObjectRecord,
    limits: RuntimeLimits
  ) throws -> [String: JSONValue] {
    guard record.packageID == FirstPartyPackageID.userWorkspace else {
      return record.managementState
    }
    let mounts = try Self.mounts(from: record.managementState)
    let seed = InventoryIdentity.make()
    let topology = try HostFolderProjection.capture(mounts: mounts, seed: seed, limits: limits)
    var state = record.managementState
    state["projection_seed"] = .string(seed)
    state["topology"] = .array(topology.map(\.json))
    return state
  }

  public func instantiate(
    snapshot: ObjectDeploymentSnapshot,
    limits: RuntimeLimits,
    replaying: Bool
  ) throws -> MikroObject {
    switch snapshot.manifest.id {
    case FirstPartyPackageID.userWorkspace:
      return try UserWorkspaceObject(snapshot: snapshot, limits: limits)
    case FirstPartyPackageID.pencil:
      return try PencilObject(snapshot: snapshot)
    case FirstPartyPackageID.printer:
      return try PrinterObject(snapshot: snapshot)
    case FirstPartyPackageID.paper:
      return try PaperObject(snapshot: snapshot, limits: limits)
    case FirstPartyPackageID.athena:
      return try AthenaObject(
        origin: .package,
        lineage: snapshot.lineage,
        hash: snapshot.objectID
      )
    case FirstPartyPackageID.objectiveBoard:
      let board = try Self.facilityContainer(snapshot: snapshot)
      let child = try Self.owned(snapshot, key: "index")
      let index = try ObjectiveIndexObject(
        boardID: board.hash,
        origin: .package,
        lineage: snapshot.lineage,
        hash: child.objectID
      )
      index.restoreLock(child.pickupLock)
      try board.container!.place(index, at: child.coordinate)
      return board
    case FirstPartyPackageID.library:
      let library = try Self.facilityContainer(snapshot: snapshot)
      let child = try Self.owned(snapshot, key: "catalog")
      let catalog = try LibraryCatalogObject(
        libraryID: library.hash,
        origin: .package,
        lineage: snapshot.lineage,
        hash: child.objectID
      )
      catalog.restoreLock(child.pickupLock)
      try library.container!.place(catalog, at: child.coordinate)
      return library
    case FirstPartyPackageID.warehouse:
      let warehouse = try Self.facilityContainer(snapshot: snapshot)
      let child = try Self.owned(snapshot, key: "directory")
      let directory = try WarehouseDirectoryObject(
        warehouseID: warehouse.hash,
        origin: .package,
        lineage: snapshot.lineage,
        hash: child.objectID
      )
      directory.restoreLock(child.pickupLock)
      try warehouse.container!.place(directory, at: child.coordinate)
      return warehouse
    case FirstPartyPackageID.marketplace:
      let marketplace = try Self.facilityContainer(snapshot: snapshot)
      let child = try Self.owned(snapshot, key: "merchant")
      let merchant = try MerchantObject(
        shopHash: marketplace.hash,
        prices: [:],
        autoRestock: false,
        name: "merchant",
        origin: .package,
        lineage: snapshot.lineage,
        hash: child.objectID
      )
      merchant.restoreLock(child.pickupLock)
      try marketplace.container!.place(merchant, at: child.coordinate)
      return marketplace
    default:
      throw MikroKhorosError.runtime("object_package.adapter_mismatch", "unsupported package")
    }
  }

  public func runWorldAction(
    _ action: ManagementAction,
    inputs: [String],
    context: WorldObjectManagementContext,
    limits: RuntimeLimits
  ) throws -> JSONValue {
    let object = context.object
    switch (object, action.id) {
    case (let workspace as UserWorkspaceObject, "mount-add"),
      (let workspace as UserWorkspaceObject, "mount-update"),
      (let workspace as UserWorkspaceObject, "mount-remove"):
      try workspace.runMountAction(
        action.id, inputs: inputs, limits: limits, harness: context.harness)
      return .object(["mount_count": .number(Double(workspace.mounts.count))])
    case (let printer as PrinterObject, "set-output-delta"):
      guard inputs.count == 2, let x = Int(inputs[0]), let y = Int(inputs[1]) else {
        throw MikroKhorosError.runtime(
          "object.management_input_invalid", "printer output coordinates must be integers")
      }
      printer.setOutputDelta(Coordinate(x: x, y: y))
      try context.recordMutation()
      return .object(["x": .number(Double(x)), "y": .number(Double(y))])
    case (let paper as PaperObject, "read"):
      return .object(["content": .string(paper.text)])
    case (let paper as PaperObject, "replace"):
      guard inputs.count == 1 else {
        throw MikroKhorosError.runtime("object.management_input_invalid", "paper requires text")
      }
      try paper.replace(inputs[0], harness: context.harness, notify: true)
      return .object(["characters": .number(Double(paper.text.count))])
    default:
      throw MikroKhorosError.runtime(
        "object.management_action_unknown", "the object does not support this management action")
    }
  }

  public func renderWorldView(
    _ view: ManagementView,
    context: WorldObjectManagementContext,
    limits: RuntimeLimits
  ) throws -> JSONValue {
    let object = context.object
    switch object {
    case let workspace as UserWorkspaceObject:
      if view.id == "mounts" { return .array(workspace.mounts.map(\.humanJSON)) }
      let projection = Self.humanProjectionStatus(mounts: workspace.mounts)
      let diagnostics = workspace.degradedDiagnostics + projection.diagnostics
      return .object([
        "status": .string(diagnostics.isEmpty ? "ready" : "degraded"),
        "diagnostics": .array(diagnostics.map(JSONValue.string)),
        "unsupported_entries": .array(projection.unsupported.map(JSONValue.string)),
      ])
    case let printer as PrinterObject:
      return printer.runtimeAdapterState["output"] ?? .null
    case let paper as PaperObject:
      return .object(["content": .string(paper.text)])
    case let athena as AthenaObject:
      let applicationID = athena.lineage?.worldTemplate?.applicationID
      let facilities =
        context.harness.world.container?.items.compactMap { item -> JSONValue? in
          guard let component = item.object.lineage?.worldTemplate,
            component.applicationID == applicationID
          else { return nil }
          return .object([
            "component": .string(component.componentKey),
            "object_id": .string(item.object.hash),
            "coordinate": .string(item.coordinate.description),
          ])
        } ?? []
      return .object(["facilities": .array(facilities)])
    case is ObjectiveIndexObject, is LibraryCatalogObject, is WarehouseDirectoryObject:
      return .object(["status": .string("ready")])
    case let merchant as MerchantObject:
      return .object([
        "items": .number(Double(merchant.prices.count)),
        "shop_id": .string(merchant.shopHash),
      ])
    case let container
    where [
      FirstPartyPackageID.objectiveBoard, FirstPartyPackageID.library,
      FirstPartyPackageID.warehouse, FirstPartyPackageID.marketplace,
    ].contains(container.lineage?.packageID ?? ""):
      return .object([
        "items": .number(Double(container.container?.items.count ?? 0)),
        "object_id": .string(container.hash),
      ])
    default:
      throw MikroKhorosError.runtime("object.management_view_unknown", "unknown object view")
    }
  }

  private static func facilityContainer(
    snapshot: ObjectDeploymentSnapshot
  ) throws -> MikroObject {
    if snapshot.manifest.id == FirstPartyPackageID.objectiveBoard {
      return try ObjectiveBoardObject(
        name: snapshot.name,
        summary: snapshot.manifest.object.summary,
        origin: .package,
        lineage: snapshot.lineage,
        hash: snapshot.objectID
      )
    }
    let object = try MikroObject(
      typeName: snapshot.manifest.object.type,
      name: snapshot.name,
      summary: snapshot.manifest.object.summary,
      publicData: snapshot.manifest.object.publicData,
      durability: snapshot.currentDurability,
      origin: .package,
      invocationAccess: snapshot.manifest.object.invocationAccess,
      capturedCapabilities: snapshot.capturedCapabilities,
      lineage: snapshot.lineage,
      credentialHandles: snapshot.credentialHandles,
      instanceRevision: snapshot.instanceRevision,
      hash: snapshot.objectID
    )
    try object.addContainerCapability()
    return object
  }

  private static func owned(
    _ snapshot: ObjectDeploymentSnapshot,
    key: String
  ) throws -> OwnedObjectDeploymentSnapshot {
    guard let child = snapshot.ownedObjects.first(where: { $0.localID == key }),
      child.parentObjectID == snapshot.objectID
    else {
      throw MikroKhorosError.persistence(
        "the first-party facility deployment is missing its owned object"
      )
    }
    return child
  }

  private static func mounts(from state: [String: JSONValue]) throws -> [UserFolderMount] {
    try (state["mounts"]?.arrayValue ?? []).map(UserFolderMount.init(json:))
  }

  private static func humanProjectionStatus(
    mounts: [UserFolderMount]
  ) -> (unsupported: [String], diagnostics: [String]) {
    var unsupported: [String] = []
    var diagnostics: [String] = []
    for mount in mounts {
      do {
        unsupported += try HostFolderProjection.unsupportedEntries(
          mount: mount,
          relativePath: ""
        ).map { "\(mount.name)/\($0)" }
      } catch let error as MikroKhorosError {
        diagnostics.append("\(mount.name):\(error.issue.code)")
      } catch {
        diagnostics.append("\(mount.name):filesystem.unavailable")
      }
    }
    return (unsupported.sorted(), diagnostics.sorted())
  }

  private static func mount(from inputs: [String], existing: UserFolderMount?) throws
    -> UserFolderMount
  {
    guard inputs.count == 6, !inputs[0].isEmpty, inputs[0].count <= 128,
      !inputs[0].contains(where: { $0.isNewline }),
      let x = Int(inputs[2]), let y = Int(inputs[3]),
      let access = UserFolderMount.Access(rawValue: inputs[4]),
      let autoAdapt = Self.boolean(inputs[5])
    else {
      throw MikroKhorosError.runtime(
        "user_workspace.mount_invalid",
        "mount inputs require a name, directory, integer coordinates, access mode, and Boolean auto-adapt"
      )
    }
    var isDirectory: ObjCBool = false
    let canonical = URL(fileURLWithPath: inputs[1]).resolvingSymlinksInPath().standardizedFileURL
    guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw MikroKhorosError.runtime(
        "user_workspace.mount_unavailable",
        "the selected host path is not an accessible directory"
      )
    }
    _ = autoAdapt
    return UserFolderMount(
      bindingID: existing?.bindingID ?? InventoryIdentity.make(),
      name: inputs[0],
      hostPath: canonical.path,
      coordinate: Coordinate(x: x, y: y),
      access: access
    )
  }

  private static func validateMountCoordinates(
    _ mounts: inout [UserFolderMount],
    requestedName: String?,
    autoAdapt rawAutoAdapt: String?
  ) throws {
    guard let requestedName,
      let index = mounts.firstIndex(where: { $0.name == requestedName })
    else { return }
    let conflicts = mounts.indices.filter {
      $0 != index && mounts[$0].coordinate == mounts[index].coordinate
    }
    guard !conflicts.isEmpty else { return }
    guard rawAutoAdapt.flatMap(boolean) == true else {
      throw MikroKhorosError.runtime(
        "placement.occupied",
        "another mount already occupies the requested user-workspace coordinate",
        suggestions: ["choose another coordinate or enable auto-adapt placement"]
      )
    }
    let occupied = Set(mounts.indices.filter { $0 != index }.map { mounts[$0].coordinate })
    mounts[index].coordinate = ProjectionCoordinates.nearestFree(
      around: mounts[index].coordinate,
      occupied: occupied
    )
  }

  private static func boolean(_ raw: String) -> Bool? {
    switch raw.lowercased() {
    case "true", "1", "yes": true
    case "false", "0", "no": false
    default: nil
    }
  }
}

extension UserFolderMount {
  fileprivate var humanJSON: JSONValue { json }
}

enum ProjectionCoordinates {
  static func nearestFree(around origin: Coordinate, occupied: Set<Coordinate>) -> Coordinate {
    guard occupied.contains(origin) else { return origin }
    var distance = 1
    while true {
      for offset in diamond(distance) {
        let candidate = origin + offset
        if !occupied.contains(candidate) { return candidate }
      }
      distance += 1
    }
  }

  static func diamond(_ distance: Int) -> [Coordinate] {
    guard distance > 0 else { return [.origin] }
    var result: [Coordinate] = []
    for index in 0..<distance { result.append(Coordinate(x: index, y: -distance + index)) }
    for index in 0..<distance { result.append(Coordinate(x: distance - index, y: index)) }
    for index in 0..<distance { result.append(Coordinate(x: -index, y: distance - index)) }
    for index in 0..<distance { result.append(Coordinate(x: -distance + index, y: -index)) }
    return result
  }
}

enum HostFolderProjection {
  static func capture(mounts: [UserFolderMount], seed: String, limits: RuntimeLimits) throws
    -> [ProjectedEntryRecord]
  {
    var records: [ProjectedEntryRecord] = []
    for mount in mounts {
      let rootID = stableID(seed: seed, bindingID: mount.bindingID, relativePath: "")
      records.append(
        ProjectedEntryRecord(
          bindingID: mount.bindingID,
          relativePath: "",
          parentRelativePath: nil,
          id: rootID,
          kind: .folder,
          coordinate: mount.coordinate
        )
      )
      try captureDirectory(
        mount: mount,
        relativePath: "",
        depth: 0,
        seed: seed,
        limits: limits,
        records: &records
      )
    }
    return records
  }

  static func listDirectory(mount: UserFolderMount, relativePath: String) throws
    -> [(String, ProjectedEntryRecord.Kind)]
  {
    try scanDirectory(mount: mount, relativePath: relativePath).entries
  }

  static func unsupportedEntries(mount: UserFolderMount, relativePath: String) throws
    -> [String]
  {
    try scanDirectory(mount: mount, relativePath: relativePath).unsupported
  }

  private static func scanDirectory(mount: UserFolderMount, relativePath: String) throws
    -> (entries: [(String, ProjectedEntryRecord.Kind)], unsupported: [String])
  {
    let directory = try safeURL(mount: mount, relativePath: relativePath, expectedDirectory: true)
    let urls = try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { !$0.hasPrefix(".") }
      .map { directory.appendingPathComponent($0, isDirectory: false) }
    var entries: [(String, ProjectedEntryRecord.Kind)] = []
    var unsupported: [String] = []
    for url in urls {
      if isSymbolicLink(url) {
        entries.append((url.lastPathComponent, .link))
        continue
      }
      let values: URLResourceValues
      do {
        values = try url.resourceValues(forKeys: [
          .isDirectoryKey, .isRegularFileKey,
        ])
      } catch {
        unsupported.append(url.lastPathComponent)
        continue
      }
      if values.isDirectory == true {
        entries.append((url.lastPathComponent, .folder))
      } else if values.isRegularFile == true {
        entries.append((url.lastPathComponent, .file))
      } else {
        unsupported.append(url.lastPathComponent)
      }
    }
    return (entries.sorted { $0.0 < $1.0 }, unsupported.sorted())
  }

  static func safeURL(
    mount: UserFolderMount,
    relativePath: String,
    expectedDirectory: Bool? = nil
  ) throws -> URL {
    let components = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(
      String.init)
    guard !components.contains(where: { $0 == "." || $0 == ".." || $0.contains("\\") }) else {
      throw MikroKhorosError.runtime("file.path_escape", "the projected path is invalid")
    }
    let root = URL(fileURLWithPath: mount.hostPath).standardizedFileURL
    var current = root
    for component in components {
      current.appendPathComponent(component, isDirectory: false)
      guard !isSymbolicLink(current) else {
        throw MikroKhorosError.runtime(
          "file.symlink_not_traversable", "symbolic links cannot be traversed")
      }
    }
    let standardized = current.standardizedFileURL
    let rootComponents = root.pathComponents
    guard standardized.pathComponents.starts(with: rootComponents) else {
      throw MikroKhorosError.runtime("file.path_escape", "the projected path escaped its mount")
    }
    if let expectedDirectory {
      let values = try standardized.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
      let matches = expectedDirectory ? values.isDirectory == true : values.isRegularFile == true
      guard matches else {
        throw MikroKhorosError.runtime(
          "file.type_changed", "the host entry type no longer matches the projected object")
      }
    }
    return standardized
  }

  private static func isSymbolicLink(_ url: URL) -> Bool {
    #if os(Windows)
      var nativePath = url.path.replacingOccurrences(of: "/", with: "\\")
      if nativePath.range(
        of: #"^\\[A-Za-z]:\\"#,
        options: .regularExpression
      ) != nil {
        nativePath.removeFirst()
      }
      return nativePath.withCString(encodedAs: UTF16.self) { path in
        let attributes = GetFileAttributesW(path)
        return attributes != INVALID_FILE_ATTRIBUTES
          && attributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) != 0
      }
    #else
      return (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    #endif
  }

  static func stableID(seed: String, bindingID: String, relativePath: String) -> String {
    String(SHA256Digest.hex(Data("\(seed)\u{0}\(bindingID)\u{0}\(relativePath)".utf8)).prefix(32))
  }

  private static func captureDirectory(
    mount: UserFolderMount,
    relativePath: String,
    depth: Int,
    seed: String,
    limits: RuntimeLimits,
    records: inout [ProjectedEntryRecord]
  ) throws {
    guard depth < limits.maximumProjectedTreeDepth else { return }
    let entries = try listDirectory(mount: mount, relativePath: relativePath)
    guard entries.count <= limits.maximumProjectedEntriesPerDirectory else {
      throw MikroKhorosError.runtime(
        "user_workspace.directory_limit",
        "a projected directory exceeds the configured entry limit",
        details: ["limit": String(limits.maximumProjectedEntriesPerDirectory)]
      )
    }
    var occupied: Set<Coordinate> = []
    for (name, kind) in entries {
      let coordinate = ProjectionCoordinates.nearestFree(around: .origin, occupied: occupied)
      occupied.insert(coordinate)
      let childPath = relativePath.isEmpty ? name : "\(relativePath)/\(name)"
      records.append(
        ProjectedEntryRecord(
          bindingID: mount.bindingID,
          relativePath: childPath,
          parentRelativePath: relativePath,
          id: stableID(seed: seed, bindingID: mount.bindingID, relativePath: childPath),
          kind: kind,
          coordinate: coordinate
        )
      )
      if kind == .folder {
        try captureDirectory(
          mount: mount,
          relativePath: childPath,
          depth: depth + 1,
          seed: seed,
          limits: limits,
          records: &records
        )
      }
    }
  }
}

final class PaperObject: MikroObject, RuntimeAdapterObject {
  let runtimeAdapterID = "org.mikrokhoros.runtime.first-party"
  let runtimeAdapterVersion = "1"
  private let maximumBytes: Int
  private(set) var text: String

  var runtimeAdapterState: [String: JSONValue] { ["content": .string(text)] }

  init(snapshot: ObjectDeploymentSnapshot, limits: RuntimeLimits) throws {
    maximumBytes = limits.maximumUserFileWriteBytes
    text = snapshot.privateState["content"]?.stringValue ?? ""
    try super.init(
      typeName: "paper.object",
      name: snapshot.name,
      summary: snapshot.manifest.object.summary,
      durability: snapshot.manifest.object.durability,
      origin: .package,
      invocationAccess: .surface,
      capturedCapabilities: snapshot.capturedCapabilities,
      lineage: snapshot.lineage,
      credentialHandles: snapshot.credentialHandles,
      hash: snapshot.objectID
    )
    if let durability = snapshot.currentDurability { restoreDurability(durability) }
    try registerFunction(name: "read", summary: "Read the paper.", audience: .agent) {
      context, arguments in
      try expectFirstParty(arguments, count: 0)
      return (context.object as! PaperObject).text
    }
    try registerFunction(
      name: "write", summary: "Replace text.", parameters: ["text"], audience: .object
    ) { context, arguments in
      try expectFirstParty(arguments, count: 1)
      let paper = context.object as! PaperObject
      try paper.replace(arguments[0], harness: context.harness)
      return "written"
    }
    try registerFunction(
      name: "append", summary: "Append text.", parameters: ["text"], audience: .object
    ) { context, arguments in
      try expectFirstParty(arguments, count: 1)
      let paper = context.object as! PaperObject
      try paper.replace(paper.text + arguments[0], harness: context.harness)
      return "appended"
    }
    try registerFunction(name: "clear", summary: "Clear text.", audience: .object) {
      context, arguments in
      try expectFirstParty(arguments, count: 0)
      try (context.object as! PaperObject).replace("", harness: context.harness)
      return "cleared"
    }
  }

  func replace(_ value: String, harness: Harness, notify: Bool = false) throws {
    guard value.utf8.count <= maximumBytes else {
      throw MikroKhorosError.runtime(
        "file.write_too_large", "the text exceeds the configured write limit",
        details: ["limit": String(maximumBytes)])
    }
    text = value
    advanceInstanceRevision()
    if notify { try harness.notifyObjectStateChanged(self) }
  }

  func restoreRuntimeAdapterState(_ state: [String: JSONValue], revision: Int) throws {
    guard let content = state["content"]?.stringValue, revision > 0 else {
      throw MikroKhorosError.persistence("paper adapter state is invalid")
    }
    text = content
    setInstanceRevision(revision)
  }
}

final class PrinterObject: MikroObject, RuntimeAdapterObject {
  let runtimeAdapterID = "org.mikrokhoros.runtime.first-party"
  let runtimeAdapterVersion = "1"
  private(set) var outputDelta: Coordinate

  var runtimeAdapterState: [String: JSONValue] {
    ["output": .object(["x": .number(Double(outputDelta.x)), "y": .number(Double(outputDelta.y))])]
  }

  init(snapshot: ObjectDeploymentSnapshot) throws {
    outputDelta = Coordinate(
      x: snapshot.privateState["output_x"]?.intValue
        ?? snapshot.configuration["output_x"]?.intValue ?? 0,
      y: snapshot.privateState["output_y"]?.intValue
        ?? snapshot.configuration["output_y"]?.intValue ?? -1
    )
    try super.init(
      typeName: "printer.object", name: snapshot.name,
      summary: snapshot.manifest.object.summary, durability: 100, origin: .package,
      invocationAccess: .surface, capturedCapabilities: snapshot.capturedCapabilities,
      lineage: snapshot.lineage, credentialHandles: snapshot.credentialHandles,
      hash: snapshot.objectID
    )
    if let durability = snapshot.currentDurability { restoreDurability(durability) }
    try registerAgentFunction(
      name: "print", summary: "Write text at the configured output delta.",
      parameters: ["text"], durabilityCost: 1
    ) { [weak self] context, arguments in
      try expectFirstParty(arguments, count: 1)
      guard let self else {
        throw MikroKhorosError.runtime("object.unavailable", "printer is unavailable")
      }
      return try requireWorldWrite(context).invoke(
        at: self.outputDelta, function: "write", arguments: [arguments[0]])
    }
  }

  func setOutputDelta(_ delta: Coordinate) {
    outputDelta = delta
    advanceInstanceRevision()
  }

  func restoreRuntimeAdapterState(_ state: [String: JSONValue], revision: Int) throws {
    guard let output = state["output"]?.objectValue,
      let x = output["x"]?.intValue, let y = output["y"]?.intValue, revision > 0
    else { throw MikroKhorosError.persistence("printer adapter state is invalid") }
    outputDelta = Coordinate(x: x, y: y)
    setInstanceRevision(revision)
  }
}

final class PencilObject: MikroObject, RuntimeAdapterObject {
  let runtimeAdapterID = "org.mikrokhoros.runtime.first-party"
  let runtimeAdapterVersion = "1"
  var runtimeAdapterState: [String: JSONValue] { [:] }

  init(snapshot: ObjectDeploymentSnapshot) throws {
    try super.init(
      typeName: "pencil.object", name: snapshot.name,
      summary: snapshot.manifest.object.summary, durability: 100, origin: .package,
      capturedCapabilities: snapshot.capturedCapabilities, lineage: snapshot.lineage,
      credentialHandles: snapshot.credentialHandles, hash: snapshot.objectID
    )
    if let durability = snapshot.currentDurability { restoreDurability(durability) }
    try registerAgentFunction(
      name: "write", summary: "Replace text on a neighboring object.",
      parameters: ["dx", "dy", "text"], durabilityCost: 1
    ) { context, arguments in
      let delta = try Self.delta(arguments, textArgument: true)
      return try requireWorldWrite(context).invoke(
        at: delta, function: "write", arguments: [arguments[2]])
    }
    try registerAgentFunction(
      name: "append", summary: "Append text on a neighboring object.",
      parameters: ["dx", "dy", "text"], durabilityCost: 1
    ) { context, arguments in
      let delta = try Self.delta(arguments, textArgument: true)
      return try requireWorldWrite(context).invoke(
        at: delta, function: "append", arguments: [arguments[2]])
    }
    try registerAgentFunction(
      name: "clear", summary: "Clear a neighboring object.",
      parameters: ["dx", "dy"], durabilityCost: 1
    ) { context, arguments in
      let delta = try Self.delta(arguments, textArgument: false)
      return try requireWorldWrite(context).invoke(at: delta, function: "clear", arguments: [])
    }
  }

  func restoreRuntimeAdapterState(_ state: [String: JSONValue], revision: Int) throws {
    guard state.isEmpty, revision > 0 else {
      throw MikroKhorosError.persistence("pencil adapter state is invalid")
    }
    setInstanceRevision(revision)
  }

  private static func delta(_ arguments: [String], textArgument: Bool) throws -> Coordinate {
    try expectFirstParty(arguments, count: textArgument ? 3 : 2)
    guard let x = Int(arguments[0]), let y = Int(arguments[1]),
      (-1...1).contains(x), (-1...1).contains(y), !(x == 0 && y == 0)
    else {
      throw MikroKhorosError.runtime(
        "pencil.delta_invalid",
        "a pencil can address only one of the eight neighboring cells",
        suggestions: ["use dx and dy values from -1 through 1, excluding 0,0"]
      )
    }
    return Coordinate(x: x, y: y)
  }
}

final class UserWorkspaceObject: MikroObject, RuntimeAdapterObject, LiveWorldObject,
  ObjectUserFolderServiceProviding
{
  let runtimeAdapterID = "org.mikrokhoros.runtime.first-party"
  let runtimeAdapterVersion = "1"
  fileprivate var mounts: [UserFolderMount]
  fileprivate var topology: [ProjectedEntryRecord]
  fileprivate let projectionSeed: String
  fileprivate let limits: RuntimeLimits
  fileprivate(set) var degradedDiagnostics: [String] = []

  var runtimeAdapterState: [String: JSONValue] {
    [
      "mounts": .array(mounts.map(\.json)),
      "projection_seed": .string(projectionSeed),
      "topology": .array(topology.map(\.json)),
    ]
  }

  init(snapshot: ObjectDeploymentSnapshot, limits: RuntimeLimits) throws {
    self.limits = limits
    mounts = try (snapshot.privateState["mounts"]?.arrayValue ?? []).map(
      UserFolderMount.init(json:))
    topology = try (snapshot.privateState["topology"]?.arrayValue ?? []).map(
      ProjectedEntryRecord.init(json:))
    projectionSeed =
      snapshot.privateState["projection_seed"]?.stringValue
      ?? snapshot.lineage.deploymentID
    try super.init(
      typeName: "user-workspace.object", name: snapshot.name,
      summary: snapshot.manifest.object.summary, origin: .package,
      invocationAccess: .surface, capturedCapabilities: snapshot.capturedCapabilities,
      lineage: snapshot.lineage, credentialHandles: snapshot.credentialHandles,
      hash: snapshot.objectID
    )
    let space = try addContainerCapability()
    try registerFunction(name: "status", summary: "Show projected mount status.") {
      context, arguments in
      try expectFirstParty(arguments, count: 0)
      let workspace = context.object as! UserWorkspaceObject
      return JSONValue.object([
        "mounts": .number(Double(workspace.mounts.count)),
        "status": .string(workspace.degradedDiagnostics.isEmpty ? "ready" : "degraded"),
      ]).description
    }
    try instantiateTopology(in: space, snapshot: snapshot)
  }

  func restoreRuntimeAdapterState(_ state: [String: JSONValue], revision: Int) throws {
    guard revision > 0 else {
      throw MikroKhorosError.persistence("user-workspace revision is invalid")
    }
    mounts = try (state["mounts"]?.arrayValue ?? []).map(UserFolderMount.init(json:))
    topology = try (state["topology"]?.arrayValue ?? []).map(ProjectedEntryRecord.init(json:))
    setInstanceRevision(revision)
  }

  func prepareForInteraction(harness: Harness) throws {
    guard !harness.isReplayingWorldEvents, let container else { return }
    let mountRoots = container.items.compactMap { $0.object as? UserFolderObject }.filter {
      $0.relativePath.isEmpty
    }
    for folder in mountRoots {
      do {
        try reconcile(folder, harness: harness)
      } catch {
        // The root remains inspectable and enterable while an individual mount is degraded.
      }
    }
  }

  fileprivate func runMountAction(
    _ actionID: String,
    inputs: [String],
    limits: RuntimeLimits,
    harness: Harness
  ) throws {
    var record = InventoryObjectRecord(
      name: name,
      packageID: FirstPartyPackageID.userWorkspace,
      packageVersion: lineage!.packageVersion,
      packageHash: lineage!.packageHash,
      managementState: runtimeAdapterState,
      worldBinding: InventoryWorldBinding(worldID: harness.world.hash)
    )
    let action = try firstPartyManagementAction(id: actionID)
    _ = try FirstPartyObjectRuntimeAdapter().runInventoryAction(
      action, inputs: inputs, record: &record, limits: limits)
    let nextMounts = try (record.managementState["mounts"]?.arrayValue ?? []).map(
      UserFolderMount.init(json:))
    let nextTopology = try HostFolderProjection.capture(
      mounts: nextMounts, seed: projectionSeed, limits: limits)
    let previousMounts = mounts
    let previousTopology = topology
    mounts = nextMounts
    topology = nextTopology
    do {
      try rebuildTopology(harness: harness)
    } catch {
      mounts = previousMounts
      topology = previousTopology
      try? rebuildTopology(harness: harness)
      throw error
    }
    advanceInstanceRevision()
    try harness.notifyObjectStateChanged(self)
  }

  fileprivate func reconcile(_ folder: UserFolderObject, harness: Harness) throws {
    if harness.isReplayingWorldEvents { return }
    guard let mount = mounts.first(where: { $0.bindingID == folder.bindingID }) else {
      throw MikroKhorosError.runtime(
        "user_workspace.mount_not_found", "the projected mount is no longer configured")
    }
    do {
      let entries = try HostFolderProjection.listDirectory(
        mount: mount, relativePath: folder.relativePath)
      guard entries.count <= limits.maximumProjectedEntriesPerDirectory else {
        throw MikroKhorosError.runtime(
          "user_workspace.directory_limit", "the projected directory exceeds its entry limit")
      }
      let existing = topology.filter {
        $0.bindingID == mount.bindingID && $0.parentRelativePath == folder.relativePath
      }
      let desiredKinds = Dictionary(uniqueKeysWithValues: entries)
      var changed = false
      for record in existing {
        let name = URL(fileURLWithPath: record.relativePath).lastPathComponent
        guard desiredKinds[name] != record.kind else { continue }
        if let object = harness.findObject(record.id) { try harness.removeObject(object) }
        topology.removeAll {
          $0.bindingID == record.bindingID
            && ($0.relativePath == record.relativePath
              || $0.relativePath.hasPrefix(record.relativePath + "/"))
        }
        changed = true
      }
      let existingPaths = Set(topology.map { "\($0.bindingID)\u{0}\($0.relativePath)" })
      var occupied = Set(folder.container!.items.map(\.coordinate))
      for (name, kind) in entries {
        let path = folder.relativePath.isEmpty ? name : "\(folder.relativePath)/\(name)"
        guard !existingPaths.contains("\(mount.bindingID)\u{0}\(path)") else { continue }
        let coordinate = ProjectionCoordinates.nearestFree(around: .origin, occupied: occupied)
        occupied.insert(coordinate)
        let record = ProjectedEntryRecord(
          bindingID: mount.bindingID, relativePath: path,
          parentRelativePath: folder.relativePath,
          id: HostFolderProjection.stableID(
            seed: projectionSeed, bindingID: mount.bindingID, relativePath: path),
          kind: kind, coordinate: coordinate
        )
        topology.append(record)
        try harness.place(try projectedObject(record), at: coordinate, in: folder.container)
        changed = true
      }
      degradedDiagnostics.removeAll { $0.hasPrefix(mount.name + ":") }
      if changed {
        advanceInstanceRevision()
        try harness.notifyObjectStateChanged(self)
      }
    } catch let error as MikroKhorosError {
      let diagnostic = "\(mount.name):\(error.issue.code)"
      if !degradedDiagnostics.contains(diagnostic) { degradedDiagnostics.append(diagnostic) }
      throw error
    } catch {
      let diagnostic = "\(mount.name):filesystem.unavailable"
      if !degradedDiagnostics.contains(diagnostic) { degradedDiagnostics.append(diagnostic) }
      throw MikroKhorosError.runtime(
        "user_workspace.mount_unavailable",
        "the mounted host directory is unavailable",
        details: ["mount": mount.name]
      )
    }
  }

  fileprivate func mount(_ id: String) throws -> UserFolderMount {
    guard let mount = mounts.first(where: { $0.bindingID == id }) else {
      throw MikroKhorosError.runtime("user_workspace.mount_not_found", "mount is unavailable")
    }
    return mount
  }

  func makeObjectUserFolderService() -> ObjectUserFolderService {
    let broker = ObjectCapabilityBroker(granted: capturedCapabilities)
    return ObjectUserFolderService(
      capabilities: broker,
      list: { [weak self] bindingID, relativePath in
        guard let self else { throw Self.unavailable() }
        try self.validateRelativePath(relativePath)
        let mount = try self.mount(bindingID)
        let entries = try HostFolderProjection.listDirectory(
          mount: mount, relativePath: relativePath
        )
        guard entries.count <= self.limits.maximumProjectedEntriesPerDirectory else {
          throw MikroKhorosError.runtime(
            "user_workspace.directory_limit",
            "the projected directory exceeds the configured entry limit",
            details: ["limit": String(self.limits.maximumProjectedEntriesPerDirectory)]
          )
        }
        return entries.map { name, kind in
          let exposedKind: ObjectUserFolderEntry.Kind
          switch kind {
          case .folder: exposedKind = .directory
          case .file: exposedKind = .file
          case .link: exposedKind = .symbolicLink
          }
          return ObjectUserFolderEntry(
            name: name,
            kind: exposedKind
          )
        }
      },
      read: { [weak self] bindingID, relativePath, range in
        guard let self else { throw Self.unavailable() }
        try self.validateRelativePath(relativePath)
        let target = try HostFolderProjection.safeURL(
          mount: self.mount(bindingID), relativePath: relativePath, expectedDirectory: false)
        let data = try Data(contentsOf: target, options: [.mappedIfSafe])
        guard data.count <= self.limits.maximumUserFileReadBytes else {
          throw MikroKhorosError.runtime(
            "file.read_too_large", "the file exceeds the configured read limit",
            details: ["limit": String(self.limits.maximumUserFileReadBytes)])
        }
        guard let range else { return data }
        guard range.lowerBound >= 0, range.upperBound <= data.count else {
          throw MikroKhorosError.runtime(
            "file.range_invalid", "the requested range exceeds the file")
        }
        return data.subdata(in: range)
      },
      write: { [weak self] bindingID, relativePath, data in
        guard let self else { throw Self.unavailable() }
        try self.validateRelativePath(relativePath)
        try self.persist(data, bindingID: bindingID, relativePath: relativePath, append: false)
      },
      append: { [weak self] bindingID, relativePath, data in
        guard let self else { throw Self.unavailable() }
        try self.validateRelativePath(relativePath)
        try self.persist(data, bindingID: bindingID, relativePath: relativePath, append: true)
      },
      clear: { [weak self] bindingID, relativePath in
        guard let self else { throw Self.unavailable() }
        try self.validateRelativePath(relativePath)
        try self.persist(Data(), bindingID: bindingID, relativePath: relativePath, append: false)
      }
    )
  }

  private func persist(
    _ newData: Data,
    bindingID: String,
    relativePath: String,
    append: Bool
  ) throws {
    let mount = try mount(bindingID)
    guard mount.access == .readWrite else {
      throw MikroKhorosError.runtime(
        "file.read_only", "the projected file belongs to a read-only mount",
        suggestions: ["change the mount to read-write through the human management interface"])
    }
    guard newData.count <= limits.maximumUserFileWriteBytes else {
      throw MikroKhorosError.runtime(
        "file.write_too_large", "the data exceeds the configured write limit",
        details: ["limit": String(limits.maximumUserFileWriteBytes)])
    }
    let target = try HostFolderProjection.safeURL(
      mount: mount, relativePath: relativePath, expectedDirectory: false)
    let current = append ? try Data(contentsOf: target) : Data()
    var output = current
    output.append(newData)
    guard output.count <= limits.maximumUserFileWriteBytes else {
      throw MikroKhorosError.runtime(
        "file.write_too_large", "the resulting file exceeds the configured write limit",
        details: ["limit": String(limits.maximumUserFileWriteBytes)])
    }
    let attributes = try? FileManager.default.attributesOfItem(atPath: target.path)
    try output.write(to: target, options: .atomic)
    #if !os(Windows)
      if let permissions = attributes?[.posixPermissions] {
        try? FileManager.default.setAttributes(
          [.posixPermissions: permissions], ofItemAtPath: target.path)
      }
    #endif
  }

  private static func unavailable() -> MikroKhorosError {
    MikroKhorosError.runtime("user_workspace.unavailable", "user-workspace root is unavailable")
  }

  private func validateRelativePath(_ relativePath: String) throws {
    let depth = relativePath.split(separator: "/", omittingEmptySubsequences: true).count
    guard depth <= limits.maximumProjectedTreeDepth else {
      throw MikroKhorosError.runtime(
        "user_workspace.depth_limit",
        "the projected path exceeds the configured tree depth",
        details: ["limit": String(limits.maximumProjectedTreeDepth)]
      )
    }
  }

  private func instantiateTopology(in space: Space, snapshot: ObjectDeploymentSnapshot) throws {
    var objects: [String: MikroObject] = [:]
    var pending = topology
    while !pending.isEmpty {
      var progressed = false
      for index in pending.indices.reversed() {
        let record = pending[index]
        let parentSpace: Space?
        if record.parentRelativePath == nil {
          parentSpace = space
        } else {
          parentSpace = topology.first(where: {
            $0.bindingID == record.bindingID && $0.relativePath == record.parentRelativePath
          }).flatMap { objects[$0.id]?.container }
        }
        guard let parentSpace else { continue }
        let object = try projectedObject(record)
        try parentSpace.place(object, at: record.coordinate)
        objects[record.id] = object
        pending.remove(at: index)
        progressed = true
      }
      guard progressed else {
        throw MikroKhorosError.persistence("projected user-workspace topology is disconnected")
      }
    }
  }

  private func rebuildTopology(harness: Harness) throws {
    guard let space = container else { return }
    for item in space.items { try harness.removeObject(item.object) }
    var objects: [String: MikroObject] = [:]
    var pending = topology
    while !pending.isEmpty {
      var progressed = false
      for index in pending.indices.reversed() {
        let record = pending[index]
        let parentSpace: Space?
        if record.parentRelativePath == nil {
          parentSpace = space
        } else {
          parentSpace = topology.first(where: {
            $0.bindingID == record.bindingID && $0.relativePath == record.parentRelativePath
          }).flatMap { objects[$0.id]?.container }
        }
        guard let parentSpace else { continue }
        let object = try projectedObject(record)
        try harness.place(object, at: record.coordinate, in: parentSpace)
        objects[record.id] = object
        pending.remove(at: index)
        progressed = true
      }
      guard progressed else {
        throw MikroKhorosError.runtime(
          "user_workspace.projection_invalid", "projected topology could not be rebuilt")
      }
    }
  }

  func restoreProjectedTopology(harness: Harness) throws {
    try rebuildTopology(harness: harness)
  }

  private func projectedObject(_ record: ProjectedEntryRecord) throws -> MikroObject {
    let mount = try mount(record.bindingID)
    switch record.kind {
    case .folder:
      return try UserFolderObject(root: self, mount: mount, record: record, lineage: lineage)
    case .file:
      return try UserFileObject(root: self, mount: mount, record: record, lineage: lineage)
    case .link:
      return try FilesystemLinkObject(mount: mount, record: record, lineage: lineage)
    }
  }
}

private final class UserFolderObject: MikroObject, AnchoredWorldObject, LiveWorldObject,
  ObjectUserFolderServiceProviding
{
  weak var root: UserWorkspaceObject?
  let bindingID: String
  let relativePath: String

  init(
    root: UserWorkspaceObject,
    mount: UserFolderMount,
    record: ProjectedEntryRecord,
    lineage: ObjectLineage?
  ) throws {
    self.root = root
    bindingID = mount.bindingID
    relativePath = record.relativePath
    try super.init(
      typeName: "user-folder.object",
      name: record.relativePath.isEmpty
        ? mount.name : URL(fileURLWithPath: record.relativePath).lastPathComponent,
      summary: "Projected host folder.",
      publicData: [
        "mount": .string(mount.name),
        "relative_path": .string(record.relativePath),
      ],
      origin: .package,
      invocationAccess: .surface,
      capturedCapabilities: [.userMachine],
      lineage: lineage,
      hash: record.id
    )
    try addContainerCapability()
    try registerFunction(name: "list", summary: "List projected entries.") {
      context, arguments in
      try expectFirstParty(arguments, count: 0)
      let folder = context.object as! UserFolderObject
      guard let root = folder.root else {
        throw MikroKhorosError.runtime(
          "user_workspace.unavailable", "user-workspace root is unavailable")
      }
      try root.reconcile(folder, harness: context.harness)
      return JSONValue.array(
        folder.container!.items.map { item in
          .object([
            "coordinate": .string(item.coordinate.description),
            "id": .string(item.object.hash),
            "name": .string(item.object.name),
            "type": .string(item.object.typeName),
          ])
        }
      ).description
    }
    try registerFunction(name: "status", summary: "Show projected folder status.") {
      context, arguments in
      try expectFirstParty(arguments, count: 0)
      let folder = context.object as! UserFolderObject
      return JSONValue.object([
        "mount": .string(mount.name), "relative_path": .string(folder.relativePath),
      ]).description
    }
  }

  func prepareForInteraction(harness: Harness) throws {
    guard let root else {
      throw MikroKhorosError.runtime(
        "user_workspace.unavailable", "user-workspace root is unavailable")
    }
    try root.reconcile(self, harness: harness)
  }

  func makeObjectUserFolderService() -> ObjectUserFolderService {
    guard let root else {
      return ObjectUserFolderService(
        capabilities: ObjectCapabilityBroker(granted: []),
        list: { _, _ in
          throw MikroKhorosError.runtime(
            "user_workspace.unavailable", "user-workspace root is unavailable")
        },
        read: { _, _, _ in
          throw MikroKhorosError.runtime(
            "user_workspace.unavailable", "user-workspace root is unavailable")
        },
        write: { _, _, _ in
          throw MikroKhorosError.runtime(
            "user_workspace.unavailable", "user-workspace root is unavailable")
        },
        append: { _, _, _ in
          throw MikroKhorosError.runtime(
            "user_workspace.unavailable", "user-workspace root is unavailable")
        },
        clear: { _, _ in
          throw MikroKhorosError.runtime(
            "user_workspace.unavailable", "user-workspace root is unavailable")
        }
      )
    }
    return root.makeObjectUserFolderService()
  }
}

private final class UserFileObject: MikroObject, AnchoredWorldObject,
  ObjectUserFolderServiceProviding
{
  weak var root: UserWorkspaceObject?
  let bindingID: String
  let relativePath: String

  init(
    root: UserWorkspaceObject,
    mount: UserFolderMount,
    record: ProjectedEntryRecord,
    lineage: ObjectLineage?
  ) throws {
    self.root = root
    bindingID = mount.bindingID
    relativePath = record.relativePath
    try super.init(
      typeName: "user-file.object",
      name: URL(fileURLWithPath: record.relativePath).lastPathComponent,
      summary: "Projected host file.",
      publicData: ["mount": .string(mount.name), "relative_path": .string(record.relativePath)],
      origin: .package,
      invocationAccess: .surface,
      capturedCapabilities: [.userMachine],
      lineage: lineage,
      hash: record.id
    )
    try registerFunction(name: "stat", summary: "Show bounded file metadata.") {
      context, arguments in
      try expectFirstParty(arguments, count: 0)
      let file = context.object as! UserFileObject
      if context.harness.isReplayingWorldEvents {
        try context.harness.recordExternalEffect(from: file, operation: "stat", result: "replayed")
        return "{\"replayed\":true}"
      }
      let url = try file.url()
      let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
      try context.harness.recordExternalEffect(from: file, operation: "stat", result: "read")
      return JSONValue.object([
        "bytes": .number(Double(values.fileSize ?? 0)),
        "relative_path": .string(file.relativePath),
      ]).description
    }
    try registerFunction(name: "read", summary: "Read bounded UTF-8 text.") {
      context, arguments in
      try expectFirstParty(arguments, count: 0)
      return try (context.object as! UserFileObject).read(
        range: nil, harness: context.harness, service: context.userFolders)
    }
    try registerFunction(
      name: "read_range", summary: "Read a bounded UTF-8 byte range.",
      parameters: ["start", "end"]
    ) { context, arguments in
      try expectFirstParty(arguments, count: 2)
      guard let start = Int(arguments[0]), let end = Int(arguments[1]), start >= 0, end >= start
      else {
        throw MikroKhorosError.runtime(
          "file.range_invalid", "file range must satisfy 0 <= start <= end")
      }
      return try (context.object as! UserFileObject).read(
        range: start..<end, harness: context.harness, service: context.userFolders)
    }
    for function in ["write", "append"] {
      try registerFunction(
        name: function, summary: "Modify projected UTF-8 text.", parameters: ["text"],
        audience: .object
      ) { context, arguments in
        try expectFirstParty(arguments, count: 1)
        return try (context.object as! UserFileObject).write(
          arguments[0], append: function == "append", harness: context.harness,
          service: context.userFolders)
      }
    }
    try registerFunction(name: "clear", summary: "Clear projected text.", audience: .object) {
      context, arguments in
      try expectFirstParty(arguments, count: 0)
      return try (context.object as! UserFileObject).write(
        "", append: false, harness: context.harness, service: context.userFolders)
    }
  }

  func makeObjectUserFolderService() -> ObjectUserFolderService {
    guard let root else {
      return ObjectUserFolderService(
        capabilities: ObjectCapabilityBroker(granted: []),
        list: { _, _ in
          throw MikroKhorosError.runtime(
            "user_workspace.unavailable", "user-workspace root is unavailable")
        },
        read: { _, _, _ in
          throw MikroKhorosError.runtime(
            "user_workspace.unavailable", "user-workspace root is unavailable")
        },
        write: { _, _, _ in
          throw MikroKhorosError.runtime(
            "user_workspace.unavailable", "user-workspace root is unavailable")
        },
        append: { _, _, _ in
          throw MikroKhorosError.runtime(
            "user_workspace.unavailable", "user-workspace root is unavailable")
        },
        clear: { _, _ in
          throw MikroKhorosError.runtime(
            "user_workspace.unavailable", "user-workspace root is unavailable")
        }
      )
    }
    return root.makeObjectUserFolderService()
  }

  private func url() throws -> URL {
    guard let root else {
      throw MikroKhorosError.runtime(
        "user_workspace.unavailable", "user-workspace root is unavailable")
    }
    return try HostFolderProjection.safeURL(
      mount: root.mount(bindingID), relativePath: relativePath, expectedDirectory: false)
  }

  private func read(
    range: Range<Int>?,
    harness: Harness,
    service: ObjectUserFolderService?
  ) throws -> String {
    if harness.isReplayingWorldEvents {
      try harness.recordExternalEffect(from: self, operation: "read", result: "replayed")
      return "{\"replayed\":true}"
    }
    guard let service else {
      throw MikroKhorosError.runtime(
        "object.user_folder_service_unavailable", "folder-bound access is unavailable")
    }
    let data = try service.read(bindingID: bindingID, relativePath: relativePath, range: range)
    guard let text = String(data: data, encoding: .utf8) else {
      throw MikroKhorosError.runtime(
        "file.encoding_unsupported", "the projected file is not valid UTF-8 text")
    }
    try harness.recordExternalEffect(from: self, operation: "read", result: "read")
    return JSONValue.object([
      "content": .string(text),
      "relative_path": .string(relativePath),
      "untrusted": .bool(true),
    ]).description
  }

  private func write(
    _ text: String,
    append: Bool,
    harness: Harness,
    service: ObjectUserFolderService?
  ) throws -> String {
    if harness.isReplayingWorldEvents {
      try harness.recordExternalEffect(
        from: self, operation: append ? "append" : "write", result: "replayed")
      return append ? "appended" : "written"
    }
    guard let service else {
      throw MikroKhorosError.runtime(
        "object.user_folder_service_unavailable", "folder-bound access is unavailable")
    }
    let current = try service.read(bindingID: bindingID, relativePath: relativePath)
    guard String(data: current, encoding: .utf8) != nil else {
      throw MikroKhorosError.runtime(
        "file.encoding_unsupported", "the projected file is not valid UTF-8 text")
    }
    let data = Data(text.utf8)
    if append {
      try service.append(bindingID: bindingID, relativePath: relativePath, data: data)
    } else if data.isEmpty {
      try service.clear(bindingID: bindingID, relativePath: relativePath)
    } else {
      try service.write(bindingID: bindingID, relativePath: relativePath, data: data)
    }
    try harness.recordExternalEffect(
      from: self, operation: append ? "append" : "write", result: "written")
    return append ? "appended" : "written"
  }
}

private final class FilesystemLinkObject: MikroObject, AnchoredWorldObject {
  init(mount: UserFolderMount, record: ProjectedEntryRecord, lineage: ObjectLineage?) throws {
    try super.init(
      typeName: "filesystem-link.object",
      name: URL(fileURLWithPath: record.relativePath).lastPathComponent,
      summary: "Visible symbolic link; traversal is disabled.",
      publicData: ["mount": .string(mount.name), "relative_path": .string(record.relativePath)],
      origin: .package,
      invocationAccess: .surface,
      lineage: lineage,
      hash: record.id
    )
  }
}

private func expectFirstParty(_ arguments: [String], count: Int) throws {
  guard arguments.count == count else {
    throw MikroKhorosError.function(
      "expected exactly \(count) argument(s), received \(arguments.count)")
  }
}

private func requireWorldWrite(_ context: AgentObjectContext) throws -> ObjectWorldWriteService {
  guard let service = context.worldWrite else {
    throw MikroKhorosError.runtime(
      "object.world_service_unavailable", "relative object invocation is unavailable")
  }
  return service
}

private func firstPartyManagementAction(id: String) throws -> ManagementAction {
  try ManagementAction(
    id: id,
    mutating: true,
    scope: .both,
    action: DeclarativeAction(kind: .return)
  )
}
