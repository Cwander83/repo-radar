import Foundation
import Testing

@testable import RepoRadarCore

@Suite(.serialized)
struct GitHubGraphQLClientTests {
  private func makeClient() -> (GitHubGraphQLClient, URL) {
    let endpoint = URL(string: "https://api.github.com/graphql")!
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    let client = GitHubGraphQLClient(session: session, endpoint: endpoint)
    return (client, endpoint)
  }

  private func loadRecordedPublicFixture() throws -> Data {
    try TestFixtures.loadData(named: "recorded-public")
  }

  @Test("Successful fetch verifies request headers, body and decodes response")
  func testSuccessfulFetch() async throws {
    let (client, endpoint) = makeClient()
    let fixtureData = try loadRecordedPublicFixture()

    var capturedRequest: URLRequest?
    MockURLProtocol.requestHandler = { request in
      capturedRequest = request
      let response = HTTPURLResponse(
        url: endpoint,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }

    let response = try await client.fetch(
      repos: ["Cwander83/repo-radar", "Cwander83/gravity-bar"],
      token: "test-token-value"
    )

    // Verify request
    let req = try #require(capturedRequest)
    #expect(req.httpMethod == "POST")
    #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-value")
    #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(req.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    #expect(req.value(forHTTPHeaderField: "User-Agent") == "RepoRadar")

    // Verify body
    let bodyData = try #require(req.bodyData)
    let body = try JSONDecoder().decode(RepoRadarQuery.RequestBody.self, from: bodyData)
    #expect(body.variables["search"] == "repo:Cwander83/repo-radar repo:Cwander83/gravity-bar")
    #expect(body.query.contains("query RepoRadar"))

    // Verify response
    let data = try #require(response.data)
    #expect(data.viewer.login == "Cwander83")
    #expect(data.search.nodes.count == 6)
  }

  @Test("Missing or empty token throws tokenMissing immediately")
  func testTokenMissing() async {
    let (client, _) = makeClient()
    MockURLProtocol.requestHandler = { _ in
      Issue.record("Network request should not be made when token is missing")
      throw URLError(.badURL)
    }

    await #expect(throws: RepoRadarError.tokenMissing) {
      _ = try await client.fetch(repos: ["owner/repo"], token: "")
    }

    await #expect(throws: RepoRadarError.tokenMissing) {
      _ = try await client.fetch(repos: ["owner/repo"], token: "   \n\t ")
    }
  }

  @Test("HTTP 401 maps to tokenUnauthorized")
  func testTokenUnauthorized401() async {
    let (client, endpoint) = makeClient()
    MockURLProtocol.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: endpoint,
        statusCode: 401,
        httpVersion: nil,
        headerFields: nil
      )!
      let data = "{\"message\": \"Bad credentials\"}".data(using: .utf8)!
      return (response, data)
    }

    do {
      _ = try await client.fetch(repos: ["owner/repo"], token: "invalid-token")
      Issue.record("Expected tokenUnauthorized error")
    } catch let error as RepoRadarError {
      #expect(error == .tokenUnauthorized(detail: "Bad credentials"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("HTTP 403 without rate limit maps to tokenUnauthorized")
  func testTokenUnauthorized403() async {
    let (client, endpoint) = makeClient()
    MockURLProtocol.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: endpoint,
        statusCode: 403,
        httpVersion: nil,
        headerFields: nil
      )!
      let data =
        "{\"message\": \"Resource not accessible by personal access token\"}".data(
          using: .utf8
        )!
      return (response, data)
    }

    do {
      _ = try await client.fetch(repos: ["owner/repo"], token: "insufficient-token")
      Issue.record("Expected tokenUnauthorized error")
    } catch let error as RepoRadarError {
      #expect(
        error == .tokenUnauthorized(detail: "Resource not accessible by personal access token"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("HTTP 403 with rate limit headers maps to rateLimited with resetAt")
  func testRateLimited403WithHeader() async {
    let (client, endpoint) = makeClient()
    let resetEpoch: TimeInterval = 1_700_000_000
    MockURLProtocol.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: endpoint,
        statusCode: 403,
        httpVersion: nil,
        headerFields: [
          "x-ratelimit-remaining": "0",
          "x-ratelimit-reset": "\(Int(resetEpoch))",
        ]
      )!
      let data = "{\"message\": \"API rate limit exceeded\"}".data(using: .utf8)!
      return (response, data)
    }

    do {
      _ = try await client.fetch(repos: ["owner/repo"], token: "token")
      Issue.record("Expected rateLimited error")
    } catch let error as RepoRadarError {
      let expectedDate = Date(timeIntervalSince1970: resetEpoch)
      #expect(error == .rateLimited(resetAt: expectedDate))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("HTTP 429 maps to rateLimited")
  func testRateLimited429() async {
    let (client, endpoint) = makeClient()
    let resetEpoch: TimeInterval = 1_700_000_000
    MockURLProtocol.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: endpoint,
        statusCode: 429,
        httpVersion: nil,
        headerFields: [
          "x-ratelimit-reset": "\(Int(resetEpoch))"
        ]
      )!
      let data = "{\"message\": \"Too many requests\"}".data(using: .utf8)!
      return (response, data)
    }

    do {
      _ = try await client.fetch(repos: ["owner/repo"], token: "token")
      Issue.record("Expected rateLimited error")
    } catch let error as RepoRadarError {
      let expectedDate = Date(timeIntervalSince1970: resetEpoch)
      #expect(error == .rateLimited(resetAt: expectedDate))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("GraphQL RATE_LIMITED error with null data maps to rateLimited with header resetAt")
  func testGraphQLRateLimitedError() async {
    let (client, endpoint) = makeClient()
    let json = """
      {
        "data": null,
        "errors": [
          { "type": "RATE_LIMITED", "message": "API rate limit already exceeded for user ID 1." }
        ]
      }
      """.data(using: .utf8)!

    MockURLProtocol.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: endpoint,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1792874712"]
      )!
      return (response, json)
    }

    do {
      _ = try await client.fetch(repos: ["owner/repo"], token: "token")
      Issue.record("Expected rateLimited error")
    } catch let error as RepoRadarError {
      #expect(error == .rateLimited(resetAt: Date(timeIntervalSince1970: 1_792_874_712)))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("Cancelled request throws CancellationError, not offline")
  func testCancelledRequest() async {
    let (client, _) = makeClient()
    MockURLProtocol.requestHandler = { _ in
      throw URLError(.cancelled)
    }

    await #expect(throws: CancellationError.self) {
      _ = try await client.fetch(repos: ["owner/repo"], token: "token")
    }
  }

  @Test("Successful response with 0 rateLimit remaining still returns data")
  func testZeroRemainingReturnsData() async throws {
    let (client, endpoint) = makeClient()
    let resetString = "2026-10-24T18:00:00Z"
    let json = """
      {
        "data": {
          "viewer": { "login": "test" },
          "rateLimit": {
            "cost": 1,
            "limit": 5000,
            "remaining": 0,
            "resetAt": "\(resetString)"
          },
          "search": { "repositoryCount": 0, "nodes": [] }
        }
      }
      """.data(using: .utf8)!

    MockURLProtocol.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: endpoint,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, json)
    }

    let response = try await client.fetch(repos: ["owner/repo"], token: "token")
    let rateLimit = try #require(response.data?.rateLimit)
    #expect(rateLimit.remaining == 0)
    #expect(rateLimit.resetAt == (try Date(resetString, strategy: .iso8601)))
  }

  @Test("Offline URLError maps to offline")
  func testOfflineURLError() async {
    let (client, _) = makeClient()
    MockURLProtocol.requestHandler = { _ in
      throw URLError(.notConnectedToInternet)
    }

    do {
      _ = try await client.fetch(repos: ["owner/repo"], token: "token")
      Issue.record("Expected offline error")
    } catch let error as RepoRadarError {
      if case .offline(let detail) = error {
        #expect(!detail.isEmpty)
      } else {
        Issue.record("Expected .offline case, got \(error)")
      }
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("HTTP 500 server error maps to serverError")
  func testServerError500() async {
    let (client, endpoint) = makeClient()
    MockURLProtocol.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: endpoint,
        statusCode: 500,
        httpVersion: nil,
        headerFields: nil
      )!
      let data = "{\"message\": \"Internal Server Error\"}".data(using: .utf8)!
      return (response, data)
    }

    do {
      _ = try await client.fetch(repos: ["owner/repo"], token: "token")
      Issue.record("Expected serverError")
    } catch let error as RepoRadarError {
      #expect(error == .serverError(statusCode: 500, detail: "Internal Server Error"))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("GraphQL query errors with null data map to graphQL or unauthorized")
  func testGraphQLErrors() async {
    let (client, endpoint) = makeClient()
    let errorJSON = """
      {
        "data": null,
        "errors": [
          { "message": "Syntax error in GraphQL query" }
        ]
      }
      """.data(using: .utf8)!

    MockURLProtocol.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: endpoint,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, errorJSON)
    }

    do {
      _ = try await client.fetch(repos: ["owner/repo"], token: "token")
      Issue.record("Expected graphQL error")
    } catch let error as RepoRadarError {
      if case .graphQL(let errors) = error {
        #expect(errors.count == 1)
        #expect(errors[0].message == "Syntax error in GraphQL query")
      } else {
        Issue.record("Expected .graphQL case, got \(error)")
      }
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("Decoding error maps to decodingError")
  func testDecodingError() async {
    let (client, endpoint) = makeClient()
    MockURLProtocol.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: endpoint,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, "invalid json bytes".data(using: .utf8)!)
    }

    do {
      _ = try await client.fetch(repos: ["owner/repo"], token: "token")
      Issue.record("Expected decodingError")
    } catch let error as RepoRadarError {
      if case .decodingError(let detail) = error {
        #expect(!detail.isEmpty)
      } else {
        Issue.record("Expected .decodingError case, got \(error)")
      }
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("validateToken returns viewer login and rateLimit")
  func testValidateToken() async throws {
    let (client, endpoint) = makeClient()
    let json = """
      {
        "data": {
          "viewer": { "login": "octocat" },
          "rateLimit": {
            "cost": 1,
            "limit": 5000,
            "remaining": 4980,
            "resetAt": "2026-10-24T18:00:00Z"
          },
          "search": { "repositoryCount": 0, "nodes": [] }
        }
      }
      """.data(using: .utf8)!

    MockURLProtocol.requestHandler = { _ in
      let response = HTTPURLResponse(
        url: endpoint,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, json)
    }

    let (viewer, rateLimit) = try await client.validateToken(token: "valid-token")
    #expect(viewer == "octocat")
    let rl = try #require(rateLimit)
    #expect(rl.remaining == 4980)
    #expect(rl.limit == 5000)
    #expect(rl.cost == 1)
  }

  @Test("Search string builder formats repo list correctly")
  func testSearchStringBuilder() {
    let formatted = RepoRadarQuery.searchString(for: [
      "Cwander83/repo-radar",
      "repo:Cwander83/gravity-bar",
      "  Cwander83/workout-tracker  ",
      "",
    ])
    #expect(
      formatted
        == "repo:Cwander83/repo-radar repo:Cwander83/gravity-bar repo:Cwander83/workout-tracker"
    )
  }
}
