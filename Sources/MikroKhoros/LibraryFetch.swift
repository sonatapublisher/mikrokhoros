import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct FetchedLibraryDocument: Sendable {
  public let title: String
  public let sourceURL: String
  public let content: String

  public init(title: String, sourceURL: String, content: String) {
    self.title = title
    self.sourceURL = sourceURL
    self.content = content
  }
}

public enum LibraryDocumentFetcher {
  public static func fetch(
    _ source: String,
    maximumBytes: Int
  ) async throws -> FetchedLibraryDocument {
    guard maximumBytes > 0 else {
      throw MikroKhorosError.configuration("external response byte limit must be positive")
    }
    let url = try validatedURL(source)
    do {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.httpShouldSetCookies = false
      configuration.urlCredentialStorage = nil
      configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
      let session = URLSession(configuration: configuration)
      defer { session.invalidateAndCancel() }
      let (data, rawResponse) = try await session.data(from: url)
      guard data.count <= maximumBytes else {
        throw MikroKhorosError.runtime(
          "library.response_too_large",
          "the document response exceeded the configured byte limit",
          details: ["limit": String(maximumBytes)],
          suggestions: ["raise the configured byte limit or choose a smaller source"]
        )
      }
      guard let response = rawResponse as? HTTPURLResponse,
        (200..<300).contains(response.statusCode)
      else {
        let status = (rawResponse as? HTTPURLResponse)?.statusCode ?? 0
        throw MikroKhorosError.runtime(
          "library.http_failed",
          "the document server returned HTTP \(status)"
        )
      }
      let finalURL = try validatedURL(response.url?.absoluteString ?? source)
      guard let content = String(data: data, encoding: .utf8), !content.isEmpty else {
        throw MikroKhorosError.runtime(
          "library.content_invalid",
          "the document response must be non-empty UTF-8 text"
        )
      }
      let suggested = response.suggestedFilename?.trimmingCharacters(in: .whitespacesAndNewlines)
      let fallback =
        finalURL.lastPathComponent.isEmpty
        ? finalURL.host ?? "Document" : finalURL.lastPathComponent
      let rawTitle = suggested?.isEmpty == false ? suggested! : fallback
      let title = String(rawTitle.prefix(128))
      return FetchedLibraryDocument(
        title: title.isEmpty ? "Document" : title,
        sourceURL: finalURL.absoluteString,
        content: content
      )
    } catch let error as MikroKhorosError {
      throw error
    } catch {
      throw MikroKhorosError.runtime(
        "library.fetch_failed",
        "the document could not be fetched"
      )
    }
  }

  private static func validatedURL(_ source: String) throws -> URL {
    guard source.count <= 2_048, let url = URL(string: source),
      let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      let host = url.host, !host.isEmpty,
      url.user == nil, url.password == nil, url.fragment == nil
    else {
      throw MikroKhorosError.function(
        "document source must be an HTTP(S) URL without user info or fragment"
      )
    }
    if scheme == "http", !["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased()) {
      throw MikroKhorosError.function(
        "unencrypted document sources are limited to loopback"
      )
    }
    return url
  }
}
