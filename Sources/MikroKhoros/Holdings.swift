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

public enum HoldingNumber: Int, Hashable, Codable, Comparable, CaseIterable, Sendable {
  case one = 1
  case two = 2
  case three = 3
  case four = 4

  public static let first = HoldingNumber.one
  public static let second = HoldingNumber.two
  public static let third = HoldingNumber.three
  public static let fourth = HoldingNumber.four

  public init(_ value: Int) throws {
    guard let number = HoldingNumber(rawValue: value) else {
      throw HoldingNumberError.invalidRange(value)
    }
    self = number
  }

  public static func < (lhs: HoldingNumber, rhs: HoldingNumber) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public enum HoldingNumberError: Error, Equatable, Sendable {
  case invalidRange(Int)
}

public enum AgentHoldingsError: Error, Equatable, Sendable {
  case duplicateHolding(String)
  case occupied(HoldingNumber, String)
}

public struct AgentHoldings {
  private var roots: [MikroObject?] = Array(repeating: nil, count: 4)

  public private(set) var primaryHoldingNumber: HoldingNumber

  public init(
    slot1: MikroObject? = nil,
    slot2: MikroObject? = nil,
    slot3: MikroObject? = nil,
    slot4: MikroObject? = nil,
    primaryHoldingNumber: HoldingNumber = .one
  ) throws {
    self.primaryHoldingNumber = primaryHoldingNumber
    try assign(slot1, to: .one)
    try assign(slot2, to: .two)
    try assign(slot3, to: .three)
    try assign(slot4, to: .four)
  }

  public init(
    eye: EyeObject?,
    primaryHoldingNumber: HoldingNumber = .one
  ) throws {
    try self.init(slot1: eye, primaryHoldingNumber: primaryHoldingNumber)
  }

  public var primaryHeldObject: MikroObject? {
    self[primaryHoldingNumber]
  }

  public var occupiedRoots: [MikroObject] {
    roots.compactMap { $0 }
  }

  public mutating func select(_ holdingNumber: HoldingNumber) {
    primaryHoldingNumber = holdingNumber
  }

  @discardableResult
  public mutating func putPrimary(_ object: MikroObject) throws -> MikroObject? {
    let index = Int(primaryHoldingNumber.rawValue) - 1
    if let existing = roots[index] {
      throw AgentHoldingsError.occupied(primaryHoldingNumber, existing.hash)
    }
    if roots.contains(where: { $0?.hash == object.hash }) {
      throw AgentHoldingsError.duplicateHolding(object.hash)
    }
    let previous = roots[index]
    roots[index] = object
    return previous
  }

  @discardableResult
  public mutating func removePrimary() -> MikroObject? {
    let index = Int(primaryHoldingNumber.rawValue) - 1
    let removed = roots[index]
    roots[index] = nil
    return removed
  }

  public internal(set) subscript(_ holdingNumber: HoldingNumber) -> MikroObject? {
    get {
      roots[Int(holdingNumber.rawValue) - 1]
    }
    set {
      roots[Int(holdingNumber.rawValue) - 1] = newValue
    }
  }

  private mutating func assign(_ object: MikroObject?, to holdingNumber: HoldingNumber) throws {
    if let object {
      let current = roots[Int(holdingNumber.rawValue) - 1]
      if let current, current.hash == object.hash { return }
      guard !roots.compactMap({ $0 }).contains(where: { $0.hash == object.hash }) else {
        throw AgentHoldingsError.duplicateHolding(object.hash)
      }
    }
    roots[Int(holdingNumber.rawValue) - 1] = object
  }
}
