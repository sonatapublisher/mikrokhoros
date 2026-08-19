import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public let maximumBundleBytes = 1_000_000

private struct BundleFunctionDefinition {
  let summary: String
  let parameters: [String]
  let durabilityCost: Int
  let action: BundleAction
}

private struct BundleAction {
  let kind: String
  let key: String?
  let argument: Int?
  let amount: Double?
  let value: JSONValue?
}

private struct BundleDefinition {
  let typeName: String
  let name: String?
  let summary: String
  let publicData: [String: JSONValue]
  let state: [String: JSONValue]
  let durability: Int?
  let hasContainer: Bool
  let functions: [String: BundleFunctionDefinition]
}

public final class BundleRegistry {
  private var definitions: [String: BundleDefinition] = [:]

  public init() {}

  public var types: [String] { definitions.keys.sorted() }

  @discardableResult
  public func install(data: Data) throws -> String {
    guard data.count <= maximumBundleBytes else {
      throw MikroKhorosError.bundle("bundle exceeds the 1 MB limit")
    }
    let root: JSONValue
    do {
      root = try JSONDecoder().decode(JSONValue.self, from: data)
    } catch {
      throw MikroKhorosError.bundle(
        "bundle must be valid UTF-8 JSON: \(error.localizedDescription)"
      )
    }
    let definition = try Self.validate(root)
    guard definitions[definition.typeName] == nil else {
      throw MikroKhorosError.bundle(
        "bundle '\(definition.typeName)' is already installed; remove it "
          + "before installing another definition"
      )
    }
    definitions[definition.typeName] = definition
    return definition.typeName
  }

  @discardableResult
  public func install(from url: URL) throws -> String {
    let scheme = url.scheme?.lowercased()
    guard scheme == nil || scheme == "file" || scheme == "http" || scheme == "https" else {
      throw MikroKhorosError.bundle(
        "bundle source must be a local file or HTTP(S) URL"
      )
    }
    do {
      let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
      if let size = resourceValues?.fileSize, size > maximumBundleBytes {
        throw MikroKhorosError.bundle("bundle exceeds the 1 MB limit")
      }
      let data = try Data(contentsOf: url)
      return try install(data: data)
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.bundle(
        "could not load bundle: \(error.localizedDescription)"
      )
    }
  }

  @discardableResult
  public func install(fromRemoteURL url: URL) async throws -> String {
    let scheme = url.scheme?.lowercased()
    guard scheme == "http" || scheme == "https" else {
      throw MikroKhorosError.bundle(
        "remote bundle source must be an HTTP(S) URL"
      )
    }
    do {
      let (data, response) = try await URLSession.shared.data(from: url)
      if let response = response as? HTTPURLResponse,
        !(200..<300).contains(response.statusCode)
      {
        throw MikroKhorosError.bundle(
          "bundle server returned HTTP \(response.statusCode)"
        )
      }
      let finalScheme = response.url?.scheme?.lowercased()
      guard finalScheme == "http" || finalScheme == "https" else {
        throw MikroKhorosError.bundle("bundle redirect left HTTP(S)")
      }
      return try install(data: data)
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.bundle(
        "could not download bundle: \(error.localizedDescription)"
      )
    }
  }

  @discardableResult
  public func install(path: String) throws -> String {
    try install(from: URL(fileURLWithPath: path))
  }

  public func remove(_ typeName: String) throws {
    guard definitions.removeValue(forKey: typeName) != nil else {
      throw MikroKhorosError.bundle(
        "bundle '\(typeName)' is not installed"
      )
    }
  }

  public func create(_ typeName: String, name: String? = nil) throws -> DeclarativeObject {
    guard let definition = definitions[typeName] else {
      throw MikroKhorosError.bundle(
        "bundle '\(typeName)' is not installed"
      )
    }
    return try DeclarativeObject(definition: definition, name: name)
  }

  private static func validate(_ root: JSONValue) throws -> BundleDefinition {
    guard let manifest = root.objectValue else {
      throw MikroKhorosError.bundle("bundle root must be a JSON object")
    }
    guard manifest["version"] == nil else {
      throw MikroKhorosError.bundle("bundle versioning is not supported")
    }
    let allowedTop: Set<String> = [
      "type", "name", "description", "public", "state", "durability",
      "container", "functions",
    ]
    try rejectUnknown(Set(manifest.keys), allowed: allowedTop, context: "bundle")

    guard let typeName = manifest["type"]?.stringValue,
      typeName.hasSuffix(".object"), !typeName.contains(where: { $0.isWhitespace })
    else {
      throw MikroKhorosError.bundle(
        "bundle type must be a whitespace-free string ending in '.object'"
      )
    }
    let name = try optionalString(manifest["name"], field: "name")
    let summary = try optionalString(manifest["description"], field: "description") ?? ""
    let publicData = try optionalObject(manifest["public"], field: "public") ?? [:]
    let state = try optionalObject(manifest["state"], field: "state") ?? [:]
    let durability = try optionalNonnegativeInt(
      manifest["durability"],
      field: "durability"
    )

    let hasContainer = try validateContainer(manifest["container"])
    let functionValues =
      try optionalObject(
        manifest["functions"],
        field: "functions"
      ) ?? [:]
    var functions: [String: BundleFunctionDefinition] = [:]
    for (functionName, value) in functionValues {
      let function = try validateFunction(functionName, value: value)
      if function.durabilityCost > 0, durability == nil {
        throw MikroKhorosError.bundle(
          "function '\(functionName)' consumes durability but the bundle "
            + "has no durability"
        )
      }
      functions[functionName] = function
    }
    return BundleDefinition(
      typeName: typeName,
      name: name,
      summary: summary,
      publicData: publicData,
      state: state,
      durability: durability,
      hasContainer: hasContainer,
      functions: functions
    )
  }

  private static func validateContainer(
    _ value: JSONValue?
  ) throws -> Bool {
    guard let value else { return false }
    guard let enabled = value.boolValue else {
      throw MikroKhorosError.bundle(
        "bundle container must be true or false; all container spaces are infinite"
      )
    }
    return enabled
  }

  private static func validateFunction(
    _ name: String,
    value: JSONValue
  ) throws -> BundleFunctionDefinition {
    guard !name.isEmpty, !name.contains(where: { $0.isWhitespace }) else {
      throw MikroKhorosError.bundle(
        "function names must be non-empty single tokens"
      )
    }
    guard let definition = value.objectValue else {
      throw MikroKhorosError.bundle("function '\(name)' must be an object")
    }
    try rejectUnknown(
      Set(definition.keys),
      allowed: ["description", "parameters", "durability_cost", "action"],
      context: "function '\(name)'"
    )
    let summary =
      try optionalString(
        definition["description"],
        field: "function '\(name)' description"
      ) ?? ""
    let parameters: [String]
    if let value = definition["parameters"] {
      guard let array = value.arrayValue,
        array.allSatisfy({ $0.stringValue != nil })
      else {
        throw MikroKhorosError.bundle(
          "function '\(name)' parameters must be a list of strings"
        )
      }
      parameters = array.map { $0.stringValue! }
    } else {
      parameters = []
    }
    let cost =
      try optionalNonnegativeInt(
        definition["durability_cost"],
        field: "function '\(name)' durability_cost"
      ) ?? 0
    guard let actionValue = definition["action"],
      let actionObject = actionValue.objectValue,
      let kind = actionObject["kind"]?.stringValue
    else {
      throw MikroKhorosError.bundle(
        "function '\(name)' requires an action object with a kind"
      )
    }
    let allowedKinds: Set<String> = ["return", "get", "set", "append", "increment", "toggle"]
    guard allowedKinds.contains(kind) else {
      throw MikroKhorosError.bundle(
        "function '\(name)' uses unsupported action '\(kind)'"
      )
    }
    let actionFields: [String: Set<String>] = [
      "return": ["kind", "value"],
      "get": ["kind", "key"],
      "set": ["kind", "key", "argument"],
      "append": ["kind", "key", "argument"],
      "increment": ["kind", "key", "argument", "amount"],
      "toggle": ["kind", "key"],
    ]
    try rejectUnknown(
      Set(actionObject.keys),
      allowed: actionFields[kind]!,
      context: "function '\(name)' action"
    )
    let key = try optionalString(
      actionObject["key"],
      field: "function '\(name)' action key"
    )
    if kind != "return", key == nil {
      throw MikroKhorosError.bundle(
        "function '\(name)' action requires a string key"
      )
    }
    let argument = try optionalNonnegativeInt(
      actionObject["argument"],
      field: "function '\(name)' action argument"
    )
    if let argument, argument >= parameters.count {
      throw MikroKhorosError.bundle(
        "function '\(name)' action argument index is out of range"
      )
    }
    if kind == "set" || kind == "append", parameters.isEmpty {
      throw MikroKhorosError.bundle(
        "function '\(name)' needs a parameter for its \(kind) action"
      )
    }
    if kind == "increment", argument != nil, actionObject["amount"] != nil {
      throw MikroKhorosError.bundle(
        "function '\(name)' increment action cannot use both argument and amount"
      )
    }
    let amount: Double?
    if let amountValue = actionObject["amount"] {
      guard let number = amountValue.numberValue else {
        throw MikroKhorosError.bundle(
          "function '\(name)' increment amount must be a number"
        )
      }
      amount = number
    } else {
      amount = nil
    }
    return BundleFunctionDefinition(
      summary: summary,
      parameters: parameters,
      durabilityCost: cost,
      action: BundleAction(
        kind: kind,
        key: key,
        argument: argument,
        amount: amount,
        value: actionObject["value"]
      )
    )
  }

  private static func rejectUnknown(
    _ fields: Set<String>,
    allowed: Set<String>,
    context: String
  ) throws {
    let unknown = fields.subtracting(allowed).sorted()
    guard unknown.isEmpty else {
      throw MikroKhorosError.bundle(
        "\(context) has unknown field(s): \(unknown.joined(separator: ", "))"
      )
    }
  }

  private static func optionalString(
    _ value: JSONValue?,
    field: String
  ) throws -> String? {
    guard let value else { return nil }
    guard let text = value.stringValue else {
      throw MikroKhorosError.bundle("\(field) must be a string")
    }
    return text
  }

  private static func optionalObject(
    _ value: JSONValue?,
    field: String
  ) throws -> [String: JSONValue]? {
    guard let value else { return nil }
    guard let object = value.objectValue else {
      throw MikroKhorosError.bundle("bundle \(field) must be an object")
    }
    return object
  }

  private static func optionalNonnegativeInt(
    _ value: JSONValue?,
    field: String
  ) throws -> Int? {
    guard let value else { return nil }
    guard let integer = value.intValue, integer >= 0 else {
      throw MikroKhorosError.bundle(
        "\(field) must be a non-negative integer"
      )
    }
    return integer
  }
}

public final class DeclarativeObject: MikroObject {
  public private(set) var privateState: [String: JSONValue]
  private let definition: BundleDefinition

  fileprivate init(definition: BundleDefinition, name: String?, hash: String? = nil) throws {
    self.definition = definition
    self.privateState = definition.state
    try super.init(
      typeName: definition.typeName,
      name: name ?? definition.name,
      summary: definition.summary,
      publicData: definition.publicData,
      durability: definition.durability,
      origin: .package,
      hash: hash
    )
    if definition.hasContainer {
      try addContainerCapability()
    }
    for (functionName, function) in definition.functions {
      try registerFunction(
        name: functionName,
        summary: function.summary,
        parameters: function.parameters,
        durabilityCost: function.durabilityCost
      ) { context, arguments in
        let object = context.object as! DeclarativeObject
        guard arguments.count == function.parameters.count else {
          throw MikroKhorosError.function(
            "expected exactly \(function.parameters.count) argument(s), "
              + "received \(arguments.count)"
          )
        }
        return try object.apply(function.action, arguments: arguments)
      }
    }
  }

  private func apply(_ action: BundleAction, arguments: [String]) throws -> String {
    switch action.kind {
    case "return":
      return action.value?.description ?? ""
    case "get":
      return privateState[action.key!]?.description ?? "null"
    case "set":
      let index = action.argument ?? 0
      privateState[action.key!] = Self.coerce(arguments[index])
      return privateState[action.key!]!.description
    case "append":
      let index = action.argument ?? 0
      let value = Self.coerce(arguments[index])
      var array: [JSONValue]
      if let existing = privateState[action.key!] {
        guard let existingArray = existing.arrayValue else {
          throw MikroKhorosError.function(
            "private state value is not a list"
          )
        }
        array = existingArray
      } else {
        array = []
      }
      array.append(value)
      privateState[action.key!] = .array(array)
      return String(array.count)
    case "increment":
      let current: Double
      if let existing = privateState[action.key!] {
        guard let number = existing.numberValue else {
          throw MikroKhorosError.function(
            "increment requires numeric state and amount"
          )
        }
        current = number
      } else {
        current = 0
      }
      let amount: Double
      if let index = action.argument {
        guard let value = Double(arguments[index]), value.isFinite else {
          throw MikroKhorosError.function(
            "increment requires numeric state and amount"
          )
        }
        amount = value
      } else {
        amount = action.amount ?? 1
      }
      let result = current + amount
      guard result.isFinite else {
        throw MikroKhorosError.function("increment values must be finite")
      }
      privateState[action.key!] = .number(result)
      return JSONValue.number(result).description
    case "toggle":
      let current: Bool
      if let existing = privateState[action.key!] {
        guard let value = existing.boolValue else {
          throw MikroKhorosError.function(
            "private state value is not boolean"
          )
        }
        current = value
      } else {
        current = false
      }
      privateState[action.key!] = .bool(!current)
      return JSONValue.bool(!current).description
    default:
      throw MikroKhorosError.function("unsupported declarative action")
    }
  }

  private static func coerce(_ value: String) -> JSONValue {
    guard let data = value.data(using: .utf8),
      let decoded = try? JSONDecoder().decode(JSONValue.self, from: data)
    else {
      return .string(value)
    }
    return decoded
  }

  public override func freshCopy(hash: String? = nil) throws -> MikroObject {
    try DeclarativeObject(definition: definition, name: name, hash: hash)
  }
}
