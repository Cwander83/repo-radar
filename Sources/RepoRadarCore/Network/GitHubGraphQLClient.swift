import Foundation

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

  /// Validates a GitHub token and retrieves viewer login and current API budget.
  public func validateToken(
    token: String
  ) async throws -> (viewer: String, rateLimit: RateLimit?) {
    let response = try await fetch(search: "", token: token)
    guard let data = response.data else {
      throw RepoRadarError.decodingError(detail: "Missing viewer in GraphQL response.")
    }
    return (data.viewer.login, data.rateLimit)
  }

  /// Executes the RepoRadar query with a custom search string.
  public func fetch(
    search: String,
    token: String
  ) async throws -> GraphQLQueryResponse {
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

    let body = RepoRadarQuery.RequestBody(search: search)
    do {
      request.httpBody = try JSONEncoder().encode(body)
    } catch {
      throw RepoRadarError.decodingError(detail: "Failed to encode request body: \(error)")
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
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
      let queryResponse: GraphQLQueryResponse
      do {
        queryResponse = try RepoRadarDecoder.decode(from: data)
      } catch {
        throw RepoRadarError.decodingError(detail: error.localizedDescription)
      }

      // If data is null, inspect errors
      if queryResponse.data == nil {
        if let errors = queryResponse.errors, !errors.isEmpty {
          for error in errors {
            let msg = error.message.lowercased()
            if msg.contains("bad credentials") || msg.contains("resource not accessible")
              || msg.contains("requires authentication")
            {
              throw RepoRadarError.tokenUnauthorized(detail: error.message)
            }
            if msg.contains("rate limit") {
              throw RepoRadarError.rateLimited(resetAt: nil)
            }
          }
          throw RepoRadarError.graphQL(errors: errors)
        } else {
          throw RepoRadarError.decodingError(detail: "Empty GraphQL response data.")
        }
      }

      // Check if GraphQL rateLimit shows 0 remaining
      if queryResponse.data?.rateLimit?.remaining == 0 {
        throw RepoRadarError.rateLimited(resetAt: queryResponse.data?.rateLimit?.resetAt)
      }

      return queryResponse

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
}
