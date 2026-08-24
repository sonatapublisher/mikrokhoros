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
import MikroKhoros

/// How the loopback web host chooses its listening port.
public enum WebPortSelection: Equatable, Sendable {
  /// The stable product default used by an ordinary `khoros web` launch.
  case stable
  /// One exact human-selected port.
  case explicit(Int)
  /// An available port selected atomically by the operating system.
  case available

  public static let stablePort = 47_567

  public var requestedPort: Int {
    switch self {
    case .stable:
      Self.stablePort
    case .explicit(let port):
      port
    case .available:
      0
    }
  }
}

/// Best-effort diagnostic classification for a listener that prevented a bind.
/// A public HTTP marker is useful guidance, not an authorization or identity
/// boundary: another local process can imitate it.
public enum WebPortListenerHint: String, Equatable, Sendable {
  case mikroKhoros = "mikrokhoros"
  case other = "other_local_service"
}

/// Typed failures shared by the transport implementation and human CLI.
public enum WebServingError: Error, Equatable, Sendable {
  case alreadyRunning
  case invalidPort
  case portUnavailable(port: Int, listener: WebPortListenerHint)
  case bindFailed
}

/// Inputs for the foreground local World host.
public struct WebLaunchRequest: Equatable, Sendable {
  public let canonicalRoot: URL
  public let configurationURL: URL?
  public let worldSelector: String?
  public let portSelection: WebPortSelection

  public init(
    canonicalRoot: URL = MikroKhorosPaths.root,
    configurationURL: URL? = nil,
    worldSelector: String? = nil,
    portSelection: WebPortSelection = .stable
  ) {
    self.canonicalRoot = canonicalRoot.standardizedFileURL
    self.configurationURL = configurationURL?.standardizedFileURL
    self.worldSelector = worldSelector
    self.portSelection = portSelection
  }

  public init(
    layout: ProductLayout,
    worldSelector: String? = nil,
    portSelection: WebPortSelection = .stable
  ) {
    canonicalRoot = layout.canonicalRoot
    configurationURL = layout.configurationURL
    self.worldSelector = worldSelector
    self.portSelection = portSelection
  }

}

/// A transport-neutral lifecycle boundary for the native web host.
public protocol KhorosWebServing: Sendable {
  func serve(
    _ request: WebLaunchRequest,
    onLaunch: @escaping @Sendable (URL) -> Void
  ) async throws

  func stop() async
}

extension KhorosWebServing {
  public func start(
    _ request: WebLaunchRequest,
    onLaunch: @escaping @Sendable (URL) -> Void
  ) async throws {
    try await serve(request, onLaunch: onLaunch)
  }
}
