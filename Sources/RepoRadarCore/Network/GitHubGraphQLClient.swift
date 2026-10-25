import Foundation

/// Parsed token validation result containing viewer, budget, and optional expiration.
public struct TokenValidationResult: Equatable, Sendable {
  public let viewer: String
  public let rateLimit: RateLimit?
  public let expiresAt: Date?

  public init(viewer: String, rateLimit: RateLimit?, expiresAt: Date? = nil) {
    self.viewer = viewer
    self.rateLimit = rateLimit
    self.expiresAt = expiresAt
  }
}

/// Utility for parsing HTTP response headers returned by GitHub API.
public enum GitHubHeaderDateParser {
  public static func parseExpirationDate(_ string: String) -> Date? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let date = try? Date(trimmed, strategy: .iso8601) {
      return date
    }

    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone(secondsFromGMT: 0)
    if let date = df.date(from: trimmed) {
      return date
    }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return iso.date(from: trimmed)
  }
}

/// URLSession-based client for the GitHub GraphQL API (`https://api.github.com/graphql`).
public final class GitHubGraphQLClient: Sendable {
  public static let defaultEndpoint = URL(string: "https://api.github.com/graphql")!

  private let session: URLSession
  private let endpoint: URL

  public init(
    session: URLSession = .shared,
    endpoint: URL = GitHubGraphQLClient.defaultEndpoint
  ) {
    self.session = session
    self.endpoint = endpoint
  }

  /// Fetches repo, PR, CI and branch status for a list of watched repositories.
  public func fetch(
    repos: [String],
    token: String
  ) async throws -> GraphQLQueryResponse {
    let search = RepoRadarQuery.searchString(for: repos)
    return try await fetch(search: search, token: token)
  }

  /// Executes the RepoRadar query with a custom search string.
  public func fetch(
    search: String,
    token: String
  ) async throws -> GraphQLQueryResponse {
    let (response, _) = try await execute(search: search, token: token)
    return response
  }

  /// Validates a GitHub token and retrieves viewer login and current API budget.
  public func validateToken(
    token: String
  ) async throws -> (viewer: String, rateLimit: RateLimit?) {
    let result = try await validateTokenDetails(token: token)
    return (result.viewer, result.rateLimit)
  }

  /// Validates a GitHub token and retrieves viewer login, API budget, and expiration from response headers.
  public func validateTokenDetails(
    token: String
  ) async throws -> TokenValidationResult {
    let (response, httpResponse) = try await execute(search: "", token: token)
    guard let responseData = response.data else {
      throw RepoRadarError.decodingError(detail: "Missing viewer in GraphQL response.")
    }

    var expiresAt: Date?
    if let expHeader = httpResponse.value(forHTTPHeaderField: "github-authentication-token-expiration") {
      expiresAt = GitHubHeaderDateParser.parseExpirationDate(expHeader)
    }

    return TokenValidationResult(
      viewer: responseData.viewer.login,
      rateLimit: responseData.rateLimit,
      expiresAt: expiresAt
    )
  }

  /// Fetches every repository the token can read, paginating until all pages are retrieved.
  public func fetchViewerRepositories(
    token: String
  ) async throws -> [ViewerRepositoryNode] {
    var allRepos: [ViewerRepositoryNode] = []
    var cursor: String? = nil

    while true {
      let (pageData, _) = try await executeViewerRepositoriesPage(after: cursor, token: token)
      let connection = pageData.viewer.repositories
      allRepos.append(contentsOf: connection.nodes)
      guard connection.pageInfo.hasNextPage,
            let nextCursor = connection.pageInfo.endCursor,
            !nextCursor.isEmpty else {
        break
      }
      cursor = nextCursor
    }

    return allRepos
  }

  /// Executes a single page of the viewer repositories query.
  private func executeViewerRepositoriesPage(
    after: String?,
    token: String
  ) async throws -> (data: ViewerRepositoriesData, httpResponse: HTTPURLResponse) {
    let body = RepoRadarQuery.ViewerRepositoriesRequestBody(after: after)
    let (data, httpResponse) = try await sendGraphQLRequest(body: body, token: token)

    let pageResponse: ViewerRepositoriesResponse
    do {
      pageResponse = try RepoRadarDecoder.makeDecoder().decode(ViewerRepositoriesResponse.self, from: data)
    } catch {
      throw RepoRadarError.decodingError(detail: error.localizedDescription)
    }

    if pageResponse.data == nil {
      try handleGraphQLErrors(pageResponse.errors, httpResponse: httpResponse)
      throw RepoRadarError.decodingError(detail: "Empty GraphQL response data.")
    }

    guard let responseData = pageResponse.data else {
      throw RepoRadarError.decodingError(detail: "Empty GraphQL response data.")
    }

    return (responseData, httpResponse)
  }

  /// Internal request execution sharing error mapping across fetch and validation paths.
  private func execute(
    search: String,
    token: String
  ) async throws -> (response: GraphQLQueryResponse, httpResponse: HTTPURLResponse) {
    let body = RepoRadarQuery.RequestBody(search: search)
    let (data, httpResponse) = try await sendGraphQLRequest(body: body, token: token)

    let queryResponse: GraphQLQueryResponse
    do {
      queryResponse = try RepoRadarDecoder.decode(from: data)
    } catch {
      throw RepoRadarError.decodingError(detail: error.localizedDescription)
    }

    if queryResponse.data == nil {
      try handleGraphQLErrors(queryResponse.errors, httpResponse: httpResponse)
      throw RepoRadarError.decodingError(detail: "Empty GraphQL response data.")
    }

    return (queryResponse, httpResponse)
  }

  /// Sends an authenticated GraphQL POST request, handling HTTP status codes and error mapping.
  private func sendGraphQLRequest<RequestBody: Encodable>(
    body: RequestBody,
    token: String
  ) async throws -> (data: Data, httpResponse: HTTPURLResponse) {
    let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedToken.isEmpty else {
      throw RepoRadarError.tokenMissing
    }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("RepoRadar", forHTTPHeaderField: "User-Agent")

    do {
      request.httpBody = try JSONEncoder().encode(body)
    } catch {
      throw RepoRadarError.decodingError(detail: "Failed to encode request body: \(error)")
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let urlError as URLError where urlError.code == .cancelled {
      throw CancellationError()
    } catch is CancellationError {
      throw CancellationError()
    } catch let urlError as URLError {
      throw RepoRadarError.offline(detail: urlError.localizedDescription)
    } catch {
      throw RepoRadarError.offline(detail: error.localizedDescription)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw RepoRadarError.offline(detail: "Invalid response from server.")
    }

    // Extract rate limit reset timestamp if present in response headers
    var headerResetAt: Date?
    if let resetHeader = httpResponse.value(forHTTPHeaderField: "x-ratelimit-reset"),
      let epochSeconds = TimeInterval(resetHeader)
    {
      headerResetAt = Date(timeIntervalSince1970: epochSeconds)
    }
    let isRemainingZero = httpResponse.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0"

    // Parse optional JSON error message
    var bodyMessage: String?
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let msg = json["message"] as? String
    {
      bodyMessage = msg
    }

    switch httpResponse.statusCode {
    case 200:
      return (data, httpResponse)

    case 401:
      throw RepoRadarError.tokenUnauthorized(detail: bodyMessage ?? "Bad credentials")

    case 403:
      let isRateLimit =
        isRemainingZero || (bodyMessage?.lowercased().contains("rate limit") ?? false)
      if isRateLimit {
        throw RepoRadarError.rateLimited(resetAt: headerResetAt)
      } else {
        throw RepoRadarError.tokenUnauthorized(detail: bodyMessage ?? "Forbidden")
      }

    case 429:
      throw RepoRadarError.rateLimited(resetAt: headerResetAt)

    case 500...599:
      let detail =
        bodyMessage ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
      throw RepoRadarError.serverError(statusCode: httpResponse.statusCode, detail: detail)

    default:
      let detail =
        bodyMessage ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
      throw RepoRadarError.serverError(statusCode: httpResponse.statusCode, detail: detail)
    }
  }

  /// Inspects GraphQL error array and maps known error patterns to RepoRadarErrors.
  private func handleGraphQLErrors(
    _ errors: [GraphQLError]?,
    httpResponse: HTTPURLResponse
  ) throws {
    guard let errors, !errors.isEmpty else { return }

    var headerResetAt: Date?
    if let resetHeader = httpResponse.value(forHTTPHeaderField: "x-ratelimit-reset"),
      let epochSeconds = TimeInterval(resetHeader)
    {
      headerResetAt = Date(timeIntervalSince1970: epochSeconds)
    }

    for error in errors {
      let msg = error.message.lowercased()
      if msg.contains("bad credentials") || msg.contains("resource not accessible")
        || msg.contains("requires authentication")
      {
        throw RepoRadarError.tokenUnauthorized(detail: error.message)
      }
      if error.type == "RATE_LIMITED" || msg.contains("rate limit") {
        throw RepoRadarError.rateLimited(resetAt: headerResetAt)
      }
    }
    throw RepoRadarError.graphQL(errors: errors)
  }
}
