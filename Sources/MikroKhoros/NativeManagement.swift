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

extension WorldRuntime {
  internal enum NativeManagedObject {
    case wallet(WalletObject)
    case messenger(MessengerObject)
    case objectiveBoard(ObjectiveBoardObject)
  }

  internal func nativeManagementInterface(for object: MikroObject) throws
    -> ObjectManagementInterface?
  {
    guard let managed = nativeManagedObject(for: object) else { return nil }
    switch managed {
    case .objectiveBoard(let board):
      // Objective Board is surfaced only when the selected object is the exact
      // default-khoros board and still has backing container persistence.
      guard board.container != nil else { return nil }
      return try managementInterface(for: board)
    case .wallet, .messenger:
      return try managementInterface(for: object)
    }
  }

  internal func runNativeManagementAction(
    _ actionID: String,
    inputs: [String],
    on object: MikroObject
  ) throws -> JSONValue? {
    guard nativeManagedObject(for: object) != nil else { return nil }
    return try runManagementAction(actionID, inputs: inputs, on: object)
  }

  internal func renderNativeManagementView(_ viewID: String, on object: MikroObject) throws
    -> JSONValue?
  {
    guard nativeManagedObject(for: object) != nil else { return nil }
    return try renderManagementView(viewID, on: object)
  }

  // Internal so WorldRuntime's public provider entry points enforce the same
  // exact native identity boundary as the host-facing convenience wrappers.
  internal func nativeManagedObject(for object: MikroObject) -> NativeManagedObject? {
    guard harness.findObject(object.hash) === object else { return nil }
    switch object {
    case let wallet as WalletObject:
      let issuers = document.agents.filter { $0.genesis.wallet == wallet.hash }
      guard issuers.count == 1, let issuer = issuers.first,
        let agent = harness.findAgent(issuer.id),
        agent.wallet === wallet,
        let registration = creditService.registration(for: wallet.hash),
        registration.walletID == wallet.hash,
        registration.worldID == document.worldID,
        registration.agentID == issuer.id,
        registration.issuerID == issuer.id,
        registration.backpackID == issuer.genesis.backpack,
        registration.coordinate == Coordinate(x: 4, y: 0)
      else { return nil }
      return .wallet(wallet)
    case let messenger as MessengerObject:
      guard messenger.origin == .genesis else { return nil }
      let issuers = document.agents.filter { $0.genesis.messenger == messenger.hash }
      guard issuers.count == 1, let issuer = issuers.first,
        let agent = harness.findAgent(issuer.id),
        (try? harness.messenger(for: agent)) === messenger
      else { return nil }
      return .messenger(messenger)
    case let board as ObjectiveBoardObject:
      // The trusted default board is a template-deployed native component,
      // so its origin may be package rather than genesis. Exact template
      // lineage and instance identity below are the authority.
      guard board === optionalDefaultKhorosFacility(.objectiveBoard) else { return nil }
      return .objectiveBoard(board)
    default:
      return nil
    }
  }
}
