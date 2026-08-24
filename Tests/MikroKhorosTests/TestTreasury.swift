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

@testable import MikroKhoros

/// Tests inject one process-local authority explicitly. Production code must
/// load the product-root authority and must never manufacture a signer while
/// opening a world.
let testTreasuryAuthorityState: TreasuryAuthorityState = {
  do {
    let signer = try CreditRecordSigner(privateCredentialHandle: "mikrokhoros-test-treasury")
    return TreasuryAuthorityState(
      authority: signer.authority,
      signer: signer,
      pinMatches: true
    )
  } catch {
    fatalError("could not create the test treasury authority: \(error)")
  }
}()

func testWorldRuntime(
  document: WorldDocument = WorldDocument(),
  configuration: RuntimeConfiguration = .defaults,
  inventory: InventoryStore? = nil
) throws -> WorldRuntime {
  try WorldRuntime(
    document: document,
    configuration: configuration,
    inventory: inventory,
    treasuryAuthority: testTreasuryAuthorityState
  )
}
