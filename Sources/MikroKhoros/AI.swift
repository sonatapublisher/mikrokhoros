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

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public enum AITransportKind: String, Codable, CaseIterable, Sendable {
  case openAIResponses = "openai-responses"
  case openAICompatible = "openai-compatible"
  case azureOpenAI = "azure-openai"
  case anthropic
  case gemini
  case roleSeparatedBridge = "role-separated-bridge"
}

public struct AIProfile: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let adapterID: String
  public let transport: AITransportKind
  public let model: String
  public let endpoint: String?
  public let credentialEnvironmentVariable: String?
  public let temperature: Double?
  public let maximumOutputTokens: Int?
  public let reasoningEffort: String?

  private enum CodingKeys: String, CodingKey {
    case id, name, adapterID, transport, model, endpoint
    case credentialEnvironmentVariable, temperature, maximumOutputTokens, reasoningEffort
  }

  public init(
    id: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
    name: String,
    adapterID: String,
    transport: AITransportKind,
    model: String,
    endpoint: String? = nil,
    credentialEnvironmentVariable: String? = nil,
    temperature: Double? = nil,
    maximumOutputTokens: Int? = nil,
    reasoningEffort: String? = nil
  ) throws {
    guard !id.isEmpty, id.count <= 128, !id.contains(where: { $0.isWhitespace }) else {
      throw MikroKhorosError.profile("profile id must be one token of at most 128 characters")
    }
    guard !name.isEmpty, name.count <= 128, !name.contains(where: { $0.isNewline }) else {
      throw MikroKhorosError.profile("profile name must be one line of at most 128 characters")
    }
    guard !adapterID.isEmpty, adapterID.count <= 128,
      !adapterID.contains(where: { $0.isWhitespace })
    else {
      throw MikroKhorosError.profile("adapter id must be one token of at most 128 characters")
    }
    guard !model.isEmpty, model.count <= 256, !model.contains(where: { $0.isNewline }) else {
      throw MikroKhorosError.profile("model must be one line of at most 256 characters")
    }
    let resolvedEndpoint = endpoint ?? AIAdapterCatalog.definition(id: adapterID)?.defaultEndpoint
    if let resolvedEndpoint {
      _ = try Self.validatedEndpointURL(
        resolvedEndpoint,
        sendsCredential: credentialEnvironmentVariable != nil
      )
    }
    if let credentialEnvironmentVariable {
      guard !credentialEnvironmentVariable.isEmpty,
        credentialEnvironmentVariable.count <= 128,
        credentialEnvironmentVariable.first.map({ $0.isLetter || $0 == "_" }) == true,
        credentialEnvironmentVariable.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
      else {
        throw MikroKhorosError.profile(
          "credential environment variable must contain only letters, numbers, or underscore"
        )
      }
    }
    if let temperature, !(0...2).contains(temperature) {
      throw MikroKhorosError.profile("temperature must be between 0 and 2")
    }
    if let maximumOutputTokens, !(1...1_000_000).contains(maximumOutputTokens) {
      throw MikroKhorosError.profile("maximum output tokens must be between 1 and 1000000")
    }
    if let reasoningEffort,
      !["none", "low", "medium", "high", "xhigh", "max"].contains(reasoningEffort)
    {
      throw MikroKhorosError.profile(
        "reasoning effort must be none, low, medium, high, xhigh, or max"
      )
    }
    self.id = id
    self.name = name
    self.adapterID = adapterID
    self.transport = transport
    self.model = model
    self.endpoint = endpoint
    self.credentialEnvironmentVariable = credentialEnvironmentVariable
    self.temperature = temperature
    self.maximumOutputTokens = maximumOutputTokens
    self.reasoningEffort = reasoningEffort
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        id: container.decode(String.self, forKey: .id),
        name: container.decode(String.self, forKey: .name),
        adapterID: container.decode(String.self, forKey: .adapterID),
        transport: container.decode(AITransportKind.self, forKey: .transport),
        model: container.decode(String.self, forKey: .model),
        endpoint: container.decodeIfPresent(String.self, forKey: .endpoint),
        credentialEnvironmentVariable: container.decodeIfPresent(
          String.self, forKey: .credentialEnvironmentVariable
        ),
        temperature: container.decodeIfPresent(Double.self, forKey: .temperature),
        maximumOutputTokens: container.decodeIfPresent(Int.self, forKey: .maximumOutputTokens),
        reasoningEffort: container.decodeIfPresent(String.self, forKey: .reasoningEffort)
      )
    } catch {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "invalid AI profile")
      )
    }
  }

  fileprivate static func validatedEndpointURL(
    _ endpoint: String,
    sendsCredential: Bool
  ) throws -> URL {
    guard endpoint.count <= 2_048, let url = URL(string: endpoint),
      let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      let host = url.host, !host.isEmpty,
      url.user == nil, url.password == nil, url.fragment == nil
    else {
      throw MikroKhorosError.profile(
        "endpoint must be an HTTP(S) URL without user info or fragment")
    }
    if scheme == "http", !isLoopbackHost(host) {
      throw MikroKhorosError.profile("unencrypted provider endpoints are limited to loopback")
    }
    if scheme == "http", sendsCredential {
      throw MikroKhorosError.profile("credentials cannot be sent to an unencrypted endpoint")
    }
    return url
  }

  private static func isLoopbackHost(_ host: String) -> Bool {
    ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
  }
}

public enum AIAdapterCategory: String, Codable, Sendable {
  case provider
  case localServer = "local-server"
  case localCLI = "local-cli"
}

public struct AIAdapterDefinition: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let category: AIAdapterCategory
  public let transport: AITransportKind
  public let binaries: [String]
  public let defaultEndpoint: String?
  public let defaultCredentialEnvironmentVariable: String?
  public let requiresRoleSeparatedBridge: Bool

  public init(
    id: String,
    name: String,
    category: AIAdapterCategory,
    transport: AITransportKind,
    binaries: [String] = [],
    defaultEndpoint: String? = nil,
    defaultCredentialEnvironmentVariable: String? = nil,
    requiresRoleSeparatedBridge: Bool = false
  ) {
    self.id = id
    self.name = name
    self.category = category
    self.transport = transport
    self.binaries = binaries
    self.defaultEndpoint = defaultEndpoint
    self.defaultCredentialEnvironmentVariable = defaultCredentialEnvironmentVariable
    self.requiresRoleSeparatedBridge = requiresRoleSeparatedBridge
  }
}

public struct AIAdapterAvailability: Equatable, Sendable {
  public let definition: AIAdapterDefinition
  public let detectedExecutable: String?

  public var isDetected: Bool {
    definition.category != .localCLI || detectedExecutable != nil
  }
}

public enum AIAdapterCatalog {
  public static let definitions: [AIAdapterDefinition] = {
    let providers: [AIAdapterDefinition] = [
      .init(
        id: "openai", name: "OpenAI", category: .provider,
        transport: .openAIResponses,
        defaultEndpoint: "https://api.openai.com/v1/responses",
        defaultCredentialEnvironmentVariable: "OPENAI_API_KEY"
      ),
      .init(
        id: "anthropic", name: "Anthropic", category: .provider,
        transport: .anthropic,
        defaultEndpoint: "https://api.anthropic.com/v1/messages",
        defaultCredentialEnvironmentVariable: "ANTHROPIC_API_KEY"
      ),
      .init(
        id: "azure-openai", name: "Azure OpenAI", category: .provider,
        transport: .azureOpenAI,
        defaultCredentialEnvironmentVariable: "AZURE_OPENAI_API_KEY"
      ),
      .init(
        id: "google-gemini", name: "Google Gemini", category: .provider,
        transport: .gemini,
        defaultCredentialEnvironmentVariable: "GEMINI_API_KEY"
      ),
      .init(
        id: "openai-compatible", name: "OpenAI-compatible endpoint",
        category: .provider, transport: .openAICompatible
      ),
      .init(
        id: "ollama", name: "Ollama", category: .localServer,
        transport: .openAICompatible,
        defaultEndpoint: "http://127.0.0.1:11434/v1/chat/completions"
      ),
      .init(
        id: "lm-studio", name: "LM Studio", category: .localServer,
        transport: .openAICompatible,
        defaultEndpoint: "http://127.0.0.1:1234/v1/chat/completions"
      ),
      .init(id: "vllm", name: "vLLM", category: .localServer, transport: .openAICompatible),
      .init(
        id: "atlas-cloud", name: "Atlas Cloud", category: .provider,
        transport: .openAICompatible
      ),
    ]

    let local: [(String, String, [String])] = [
      ("amr", "Vela / AMR", ["amr"]),
      ("claude", "Claude Code", ["claude"]),
      ("codex", "Codex", ["codex"]),
      ("devin", "Devin", ["devin"]),
      ("opencode", "OpenCode", ["opencode"]),
      ("byok-opencode", "BYOK OpenCode", ["opencode"]),
      ("hermes", "Hermes", ["hermes"]),
      ("trae-cli", "Trae CLI", ["trae"]),
      ("grok-build", "Grok Build", ["grok"]),
      ("kimi", "Kimi", ["kimi"]),
      ("cursor-agent", "Cursor Agent", ["cursor-agent"]),
      ("qwen", "Qwen", ["qwen"]),
      ("qoder", "Qoder", ["qoder"]),
      ("copilot", "GitHub Copilot CLI", ["copilot", "github-copilot"]),
      ("amp", "Amp", ["amp"]),
      ("pi", "Pi Agent", ["pi"]),
      ("kiro", "Kiro", ["kiro-cli", "kiro"]),
      ("kilo", "Kilo", ["kilo"]),
      ("vibe", "Mistral Vibe", ["vibe"]),
      ("deepseek", "DeepSeek CLI", ["deepseek"]),
      ("deepseek-harness", "DeepSeek Harness", ["deepseek-harness"]),
      ("aider", "Aider", ["aider"]),
      ("antigravity", "Antigravity", ["antigravity"]),
      ("reasonix", "Reasonix", ["reasonix"]),
      ("codebuddy", "CodeBuddy", ["codebuddy"]),
      ("mimo", "Mimo", ["mimo"]),
      ("atomcode", "AtomCode", ["atomcode"]),
    ]
    let localDefinitions = local.map {
      AIAdapterDefinition(
        id: $0.0,
        name: $0.1,
        category: .localCLI,
        transport: .roleSeparatedBridge,
        binaries: $0.2,
        requiresRoleSeparatedBridge: true
      )
    }
    let result = providers + localDefinitions
    precondition(Set(result.map(\.id)).count == result.count, "duplicate AI adapter id")
    return result
  }()

  public static func definition(id: String) -> AIAdapterDefinition? {
    definitions.first { $0.id == id }
  }

  public static func detect(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> [AIAdapterAvailability] {
    definitions.map { definition in
      AIAdapterAvailability(
        definition: definition,
        detectedExecutable: firstExecutable(
          named: definition.binaries,
          path: environment["PATH"] ?? ""
        )
      )
    }
  }

  private static func firstExecutable(named names: [String], path: String) -> String? {
    guard !names.isEmpty else { return nil }
    #if os(Windows)
      let separator: Character = ";"
      let suffixes = ["", ".exe", ".cmd", ".bat"]
    #else
      let separator: Character = ":"
      let suffixes = [""]
    #endif
    for directory in path.split(separator: separator).map(String.init) where !directory.isEmpty {
      for name in names {
        for suffix in suffixes {
          let candidate = URL(fileURLWithPath: directory)
            .appendingPathComponent(name + suffix).path
          #if os(Windows)
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
          #else
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
          #endif
        }
      }
    }
    return nil
  }
}

public enum AIMessageRole: String, Codable, Sendable {
  case user
  case assistant
}

public struct AIConversationMessage: Codable, Equatable, Sendable {
  public let role: AIMessageRole
  public let content: String

  public init(role: AIMessageRole, content: String) {
    self.role = role
    self.content = content
  }
}

public protocol AICompleting: Sendable {
  func complete(
    profile: AIProfile,
    request: AgentModelRequest,
    history: [AIConversationMessage]
  ) async throws -> String
}

public struct AICompletionClient: AICompleting, Sendable {
  public let limits: RuntimeLimits

  public init(limits: RuntimeLimits = .defaults) {
    self.limits = limits
  }

  public func complete(
    profile: AIProfile,
    request: AgentModelRequest,
    history: [AIConversationMessage] = []
  ) async throws -> String {
    try PromptSafety.validateModelContext(request: request, history: history, limits: limits)
    switch profile.transport {
    case .openAIResponses:
      return try await completeOpenAIResponses(
        profile: profile, request: request, history: history
      )
    case .openAICompatible, .azureOpenAI:
      return try await completeOpenAI(profile: profile, request: request, history: history)
    case .anthropic:
      return try await completeAnthropic(profile: profile, request: request, history: history)
    case .gemini:
      return try await completeGemini(profile: profile, request: request, history: history)
    case .roleSeparatedBridge:
      return try await completeBridge(profile: profile, request: request, history: history)
    }
  }

  private func completeOpenAIResponses(
    profile: AIProfile,
    request: AgentModelRequest,
    history: [AIConversationMessage]
  ) async throws -> String {
    let input =
      history.map {
        ResponsesInputMessage(role: $0.role.rawValue, content: $0.content)
      } + [ResponsesInputMessage(role: "user", content: request.input)]
    let body = ResponsesRequest(
      model: profile.model,
      instructions: request.system,
      input: input,
      reasoning: profile.reasoningEffort.map(ResponsesReasoning.init(effort:)),
      temperature: profile.temperature,
      maxOutputTokens: profile.maximumOutputTokens
    )
    var headers: [String: String] = [:]
    if let key = try credential(for: profile) {
      headers["Authorization"] = "Bearer \(key)"
    }
    let response: ResponsesResponse = try await perform(
      url: endpoint(for: profile),
      headers: headers,
      body: body,
      response: ResponsesResponse.self
    )
    let output = response.output
      .flatMap { $0.content ?? [] }
      .filter { $0.type == "output_text" }
      .compactMap(\.text)
      .joined(separator: "\n")
    guard !output.isEmpty else {
      throw MikroKhorosError.profile("AI provider returned no action text")
    }
    return output
  }

  private func credential(for profile: AIProfile) throws -> String? {
    guard let variable = profile.credentialEnvironmentVariable else { return nil }
    guard let value = ProcessInfo.processInfo.environment[variable], !value.isEmpty else {
      throw MikroKhorosError.profile(
        "credential environment variable is not set for this profile"
      )
    }
    return value
  }

  private func endpoint(for profile: AIProfile) throws -> URL {
    let fallback = AIAdapterCatalog.definition(id: profile.adapterID)?.defaultEndpoint
    guard let raw = profile.endpoint ?? fallback else {
      throw MikroKhorosError.profile("this AI profile requires an endpoint")
    }
    return try AIProfile.validatedEndpointURL(
      raw,
      sendsCredential: profile.credentialEnvironmentVariable != nil
    )
  }

  private func perform<Response: Decodable>(
    url: URL,
    headers: [String: String],
    body: some Encodable,
    response: Response.Type
  ) async throws -> Response {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 120
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
    request.httpBody = try JSONEncoder().encode(body)
    let (data, rawResponse) = try await URLSession.shared.data(for: request)
    guard data.count <= limits.maximumProviderResponseBytes else {
      throw MikroKhorosError.profile("AI provider response exceeded the byte limit")
    }
    guard let http = rawResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      let status = (rawResponse as? HTTPURLResponse)?.statusCode ?? 0
      throw MikroKhorosError.profile("AI provider returned HTTP \(status)")
    }
    do {
      return try JSONDecoder().decode(Response.self, from: data)
    } catch {
      throw MikroKhorosError.profile("AI provider returned an invalid response")
    }
  }

  private func completeOpenAI(
    profile: AIProfile,
    request: AgentModelRequest,
    history: [AIConversationMessage]
  ) async throws -> String {
    let messages =
      [OpenAIMessage(role: "system", content: request.system)]
      + history.map { OpenAIMessage(role: $0.role.rawValue, content: $0.content) }
      + [OpenAIMessage(role: "user", content: request.input)]
    let body = OpenAIRequest(
      model: profile.model,
      messages: messages,
      temperature: profile.temperature,
      maxTokens: profile.maximumOutputTokens
    )
    var headers: [String: String] = [:]
    if let key = try credential(for: profile) {
      if profile.transport == .azureOpenAI {
        headers["api-key"] = key
      } else {
        headers["Authorization"] = "Bearer \(key)"
      }
    }
    let response: OpenAIResponse = try await perform(
      url: endpoint(for: profile), headers: headers, body: body, response: OpenAIResponse.self
    )
    guard let output = response.choices.first?.message.content, !output.isEmpty else {
      throw MikroKhorosError.profile("AI provider returned no action text")
    }
    return output
  }

  private func completeAnthropic(
    profile: AIProfile,
    request: AgentModelRequest,
    history: [AIConversationMessage]
  ) async throws -> String {
    let messages =
      history.map { AnthropicMessage(role: $0.role.rawValue, content: $0.content) }
      + [AnthropicMessage(role: "user", content: request.input)]
    let body = AnthropicRequest(
      model: profile.model,
      system: request.system,
      messages: messages,
      maxTokens: profile.maximumOutputTokens ?? 4_096,
      temperature: profile.temperature
    )
    let response: AnthropicResponse = try await perform(
      url: endpoint(for: profile),
      headers: [
        "x-api-key": try credential(for: profile) ?? "",
        "anthropic-version": "2023-06-01",
      ],
      body: body,
      response: AnthropicResponse.self
    )
    let output = response.content.filter { $0.type == "text" }.map(\.text)
      .joined(separator: "\n")
    guard !output.isEmpty else {
      throw MikroKhorosError.profile("AI provider returned no action text")
    }
    return output
  }

  private func completeGemini(
    profile: AIProfile,
    request: AgentModelRequest,
    history: [AIConversationMessage]
  ) async throws -> String {
    let base = profile.endpoint ?? "https://generativelanguage.googleapis.com/v1beta/models"
    let encodedModel =
      profile.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
      ?? profile.model
    guard let components = URLComponents(string: "\(base)/\(encodedModel):generateContent") else {
      throw MikroKhorosError.profile("Gemini endpoint is invalid")
    }
    guard let url = components.url else {
      throw MikroKhorosError.profile("Gemini endpoint is invalid")
    }
    let key = try credential(for: profile)
    _ = try AIProfile.validatedEndpointURL(
      url.absoluteString,
      sendsCredential: key != nil
    )
    let contents =
      history.map {
        GeminiContent(
          role: $0.role == .assistant ? "model" : "user",
          parts: [GeminiPart(text: $0.content)]
        )
      } + [GeminiContent(role: "user", parts: [GeminiPart(text: request.input)])]
    let body = GeminiRequest(
      systemInstruction: GeminiContent(role: nil, parts: [GeminiPart(text: request.system)]),
      contents: contents,
      generationConfig: GeminiGenerationConfig(
        temperature: profile.temperature,
        maxOutputTokens: profile.maximumOutputTokens
      )
    )
    let response: GeminiResponse = try await perform(
      url: url,
      headers: key.map { ["x-goog-api-key": $0] } ?? [:],
      body: body,
      response: GeminiResponse.self
    )
    let output =
      response.candidates.first?.content.parts.map(\.text)
      .joined(separator: "\n") ?? ""
    guard !output.isEmpty else {
      throw MikroKhorosError.profile("AI provider returned no action text")
    }
    return output
  }

  private func completeBridge(
    profile: AIProfile,
    request: AgentModelRequest,
    history: [AIConversationMessage]
  ) async throws -> String {
    let body = BridgeRequest(
      adapter: profile.adapterID,
      model: profile.model,
      system: request.system,
      input: request.input,
      history: history,
      reasoningEffort: profile.reasoningEffort
    )
    let response: BridgeResponse = try await perform(
      url: endpoint(for: profile), headers: [:], body: body, response: BridgeResponse.self
    )
    guard !response.output.isEmpty else {
      throw MikroKhorosError.profile("AI bridge returned no action text")
    }
    return response.output
  }
}

private struct ResponsesInputMessage: Encodable {
  let role: String
  let content: String
}
private struct ResponsesReasoning: Encodable { let effort: String }
private struct ResponsesRequest: Encodable {
  let model: String
  let instructions: String
  let input: [ResponsesInputMessage]
  let reasoning: ResponsesReasoning?
  let temperature: Double?
  let maxOutputTokens: Int?
  let store = false

  enum CodingKeys: String, CodingKey {
    case model, instructions, input, reasoning, temperature, store
    case maxOutputTokens = "max_output_tokens"
  }
}
private struct ResponsesResponse: Decodable {
  struct Output: Decodable {
    struct Content: Decodable {
      let type: String
      let text: String?
    }
    let content: [Content]?
  }
  let output: [Output]
}

private struct OpenAIMessage: Codable {
  let role: String
  let content: String
}
private struct OpenAIRequest: Encodable {
  let model: String
  let messages: [OpenAIMessage]
  let temperature: Double?
  let maxTokens: Int?

  enum CodingKeys: String, CodingKey {
    case model, messages, temperature
    case maxTokens = "max_tokens"
  }
}
private struct OpenAIResponse: Decodable {
  struct Choice: Decodable { let message: OpenAIMessage }
  let choices: [Choice]
}

private struct AnthropicMessage: Codable {
  let role: String
  let content: String
}
private struct AnthropicRequest: Encodable {
  let model: String
  let system: String
  let messages: [AnthropicMessage]
  let maxTokens: Int
  let temperature: Double?

  enum CodingKeys: String, CodingKey {
    case model, system, messages, temperature
    case maxTokens = "max_tokens"
  }
}
private struct AnthropicResponse: Decodable {
  struct Block: Decodable {
    let type: String
    let text: String
  }
  let content: [Block]
}

private struct GeminiPart: Codable { let text: String }
private struct GeminiContent: Codable {
  let role: String?
  let parts: [GeminiPart]
}
private struct GeminiGenerationConfig: Codable {
  let temperature: Double?
  let maxOutputTokens: Int?
}
private struct GeminiRequest: Encodable {
  let systemInstruction: GeminiContent
  let contents: [GeminiContent]
  let generationConfig: GeminiGenerationConfig
}
private struct GeminiResponse: Decodable {
  struct Candidate: Decodable { let content: GeminiContent }
  let candidates: [Candidate]
}

private struct BridgeRequest: Encodable {
  let adapter: String
  let model: String
  let system: String
  let input: String
  let history: [AIConversationMessage]
  let reasoningEffort: String?

  enum CodingKeys: String, CodingKey {
    case adapter, model, system, input, history
    case reasoningEffort = "reasoning_effort"
  }
}
private struct BridgeResponse: Decodable { let output: String }
