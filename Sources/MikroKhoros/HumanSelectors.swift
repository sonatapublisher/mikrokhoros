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

public enum HumanSelectorResolution<Value> {
  case exact(Value)
  case uniquePrefix(Value)
  case uniqueName(Value)

  public var value: Value {
    switch self {
    case .exact(let value), .uniquePrefix(let value), .uniqueName(let value): value
    }
  }
}

public enum HumanSelectorResolver {
  public static func resolve<Value>(
    _ query: String,
    among values: [Value],
    id: (Value) -> String,
    name: ((Value) -> String?)? = nil,
    kind: String,
    listCommand: String
  ) throws -> HumanSelectorResolution<Value> {
    if let exact = values.first(where: { id($0) == query }) { return .exact(exact) }

    if query.count >= 4 {
      let prefixMatches = values.filter { id($0).hasPrefix(query) }
      if prefixMatches.count == 1, let match = prefixMatches.first {
        return .uniquePrefix(match)
      }
      if prefixMatches.count > 1 {
        throw ambiguous(
          query: query,
          values: prefixMatches,
          allValues: values,
          id: id,
          name: name,
          kind: kind
        )
      }
    }

    if let name {
      let nameMatches = values.filter {
        name($0)?.caseInsensitiveCompare(query) == .orderedSame
      }
      if nameMatches.count == 1, let match = nameMatches.first {
        return .uniqueName(match)
      }
      if nameMatches.count > 1 {
        throw ambiguous(
          query: query,
          values: nameMatches,
          allValues: values,
          id: id,
          name: name,
          kind: kind
        )
      }
    }

    throw MikroKhorosError.runtime(
      "selector.not_found",
      "no \(kind) matches the selected name or identity",
      details: ["selector": String(query.prefix(256)), "entity": kind],
      suggestions: ["run `\(listCommand)` and choose a listed name or ID prefix"]
    )
  }

  public static func uniquePrefix<Value>(
    for value: Value,
    among values: [Value],
    id: (Value) -> String,
    minimumLength: Int = 8
  ) -> String {
    let identity = id(value)
    guard !identity.isEmpty else { return identity }
    for length in max(1, minimumLength)...identity.count {
      let prefix = String(identity.prefix(length))
      if values.filter({ id($0).hasPrefix(prefix) }).count == 1 { return prefix }
    }
    return identity
  }

  private static func ambiguous<Value>(
    query: String,
    values: [Value],
    allValues: [Value],
    id: (Value) -> String,
    name: ((Value) -> String?)?,
    kind: String
  ) -> MikroKhorosError {
    let candidates = values.prefix(16).map { value in
      let prefix = uniquePrefix(for: value, among: allValues, id: id)
      return [name?(value), prefix].compactMap { $0 }.joined(separator: " #")
    }.joined(separator: ", ")
    return MikroKhorosError.runtime(
      "selector.ambiguous",
      "the selected \(kind) name or identity is ambiguous",
      details: [
        "selector": String(query.prefix(256)),
        "entity": kind,
        "candidates": candidates,
      ],
      suggestions: ["retry with one displayed unique ID prefix"]
    )
  }
}
