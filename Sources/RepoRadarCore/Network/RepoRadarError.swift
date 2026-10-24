import Foundation

/// Errors surfaced by the GitHub GraphQL client and refresh pipeline.
public enum RepoRadarError: Error, Codable, Sendable, Equatable, LocalizedError {
  case tokenMissing
  case tokenUnauthorized(detail: String)
  case rateLimited(resetAt: Date?)
  case offline(detail: String)
  case serverError(statusCode: Int, detail: String)
  case graphQL(errors: [GraphQLError])
  case decodingError(detail: String)

  public var errorDescription: String? {
    switch self {
    case .tokenMissing:
      return "GitHub personal access token is missing."
    case .tokenUnauthorized(let detail):
      return "GitHub authentication failed: \(detail)"
    case .rateLimited(let resetAt):
      if let resetAt {
        let formatter = ISO8601DateFormatter()
        return "GitHub rate limit exceeded. Resets at \(formatter.string(from: resetAt))."
      }
      return "GitHub rate limit exceeded."
    case .offline(let detail):
      return "Network offline: \(detail)"
    case .serverError(let statusCode, let detail):
      return "GitHub server error (\(statusCode)): \(detail)"
    case .graphQL(let errors):
      let messages = errors.map(\.message).joined(separator: "; ")
      return "GitHub GraphQL error: \(messages)"
    case .decodingError(let detail):
      return "Failed to decode GitHub response: \(detail)"
    }
  }
}
