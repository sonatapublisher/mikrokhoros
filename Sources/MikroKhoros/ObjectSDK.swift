import Foundation

public enum ObjectCapability: String, Codable, CaseIterable, Sendable {
  case privateChildren = "private-children"
  case broadcast
  case worldRead = "world-read"
  case worldWrite = "world-write"
  case worldSystem = "world-system"
  case network
  case userMachine = "user-machine"
}

public enum ObjectPackageRuntime: String, Codable, Sendable {
  case declarative
  case nativeSwift = "native-swift"
  case javascript
}

public struct ObjectPackageManifest: Codable, Equatable, Sendable {
  public let id: String
  public let displayName: String
  public let objectType: String
  public let runtime: ObjectPackageRuntime
  public let entryPoint: String?
  public let requestedCapabilities: Set<ObjectCapability>

  public init(
    id: String,
    displayName: String,
    objectType: String,
    runtime: ObjectPackageRuntime,
    entryPoint: String? = nil,
    requestedCapabilities: Set<ObjectCapability> = []
  ) throws {
    guard !id.isEmpty, id.count <= 128,
      id.allSatisfy({ $0.isLetter || $0.isNumber || "-._".contains($0) })
    else {
      throw MikroKhorosError.bundle(
        "object package id must use letters, numbers, dash, dot, or underscore"
      )
    }
    guard !displayName.isEmpty, displayName.count <= 128,
      !displayName.contains(where: { $0.isNewline })
    else {
      throw MikroKhorosError.bundle("object package name must be one line")
    }
    guard objectType.hasSuffix(".object"), objectType.count <= 128,
      !objectType.contains(where: { $0.isWhitespace })
    else {
      throw MikroKhorosError.bundle("object type must be one token ending in .object")
    }
    if runtime == .declarative, entryPoint != nil {
      throw MikroKhorosError.bundle("declarative packages do not have an executable entry point")
    }
    if runtime != .declarative {
      guard let entryPoint, !entryPoint.isEmpty, entryPoint.count <= 512,
        !entryPoint.hasPrefix("/"), !entryPoint.contains("..")
      else {
        throw MikroKhorosError.bundle(
          "executable object packages require a bounded relative entry point"
        )
      }
    }
    self.id = id
    self.displayName = displayName
    self.objectType = objectType
    self.runtime = runtime
    self.entryPoint = entryPoint
    self.requestedCapabilities = requestedCapabilities
  }
}

public struct ObjectInstallation: Codable, Equatable, Sendable {
  public let id: String
  public let package: ObjectPackageManifest
  public let worldID: String
  public private(set) var grantedCapabilities: Set<ObjectCapability>

  public init(
    id: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
    package: ObjectPackageManifest,
    worldID: String,
    grantedCapabilities: Set<ObjectCapability> = []
  ) throws {
    guard grantedCapabilities.isSubset(of: package.requestedCapabilities) else {
      throw MikroKhorosError.bundle(
        "an installation cannot grant capabilities the package did not request"
      )
    }
    self.id = id
    self.package = package
    self.worldID = worldID
    self.grantedCapabilities = grantedCapabilities
  }

  mutating func replaceGrants(_ grants: Set<ObjectCapability>) throws {
    guard grants.isSubset(of: package.requestedCapabilities) else {
      throw MikroKhorosError.bundle(
        "an installation cannot grant capabilities the package did not request"
      )
    }
    grantedCapabilities = grants
  }
}

public final class ObjectInstallationRegistry {
  private var installations: [String: ObjectInstallation] = [:]

  public init() {}

  public var all: [ObjectInstallation] {
    installations.values.sorted { $0.id < $1.id }
  }

  @discardableResult
  public func install(
    _ package: ObjectPackageManifest,
    intoWorld worldID: String,
    grants: Set<ObjectCapability> = []
  ) throws -> ObjectInstallation {
    let installation = try ObjectInstallation(
      package: package,
      worldID: worldID,
      grantedCapabilities: grants
    )
    installations[installation.id] = installation
    return installation
  }

  public func approve(
    _ capabilities: Set<ObjectCapability>,
    for installationID: String
  ) throws {
    guard var installation = installations[installationID] else {
      throw MikroKhorosError.bundle("object installation was not found")
    }
    try installation.replaceGrants(installation.grantedCapabilities.union(capabilities))
    installations[installationID] = installation
  }

  public func revoke(
    _ capabilities: Set<ObjectCapability>,
    for installationID: String
  ) throws {
    guard var installation = installations[installationID] else {
      throw MikroKhorosError.bundle("object installation was not found")
    }
    try installation.replaceGrants(installation.grantedCapabilities.subtracting(capabilities))
    installations[installationID] = installation
  }

  public func require(
    _ capability: ObjectCapability,
    installationID: String
  ) throws {
    guard let installation = installations[installationID],
      installation.grantedCapabilities.contains(capability)
    else {
      throw MikroKhorosError.runtime(
        "object.capability_denied",
        "the object installation does not have the required capability"
      )
    }
  }
}

public struct ObjectInvocationIdentity: Equatable, Sendable {
  public let invocationID: String
  public let objectID: String
  public let installationID: String?
  public let agentID: String
  public let worldID: String

  public init(
    invocationID: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
    objectID: String,
    installationID: String?,
    agentID: String,
    worldID: String
  ) {
    self.invocationID = invocationID
    self.objectID = objectID
    self.installationID = installationID
    self.agentID = agentID
    self.worldID = worldID
  }
}
