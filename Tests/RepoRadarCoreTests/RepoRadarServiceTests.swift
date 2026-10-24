import Foundation
import Testing

@testable import RepoRadarCore

private struct FailingTokenStore: TokenStore {
  let errorToThrow: any Error

  func read() throws -> String? {
    throw errorToThrow
  }

  func save(token: String) throws {}
  func delete() throws {}
}

@Suite(.serialized)
struct RepoRadarServiceTests {
  private func makeMockClient(id: String) -> GitHubGraphQLClient {
    let endpoint = URL(string: "https://api.github.com/graphql")!
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    config.httpAdditionalHeaders = ["X-Mock-Handler-ID": id]
    let session = URLSession(configuration: config)
    return GitHubGraphQLClient(session: session, endpoint: endpoint)
  }

  private func loadRecordedPublicFixture() throws -> Data {
    try TestFixtures.loadData(named: "recorded-public")
  }

  @Test("End-to-end refresh loads config, fetches fixture, classifies, and writes snapshot")
  func endToEndRefreshSuccessWithFixture() async throws {
    let suiteName = "test-reporadar-service-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let configStore = ConfigStore(userDefaults: defaults)
    try configStore.save(
      RepoRadarConfig(
        watchedRepos: ["Cwander83/repo-radar", "Cwander83/gravity-bar"],
        pollInterval: .fiveMinutes,
        staleDays: 30
      )
    )

    let tokenStore = InMemoryTokenStore(initialToken: "test-auth-pat")

    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("RepoRadarTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let snapshotFile = tempDir.appendingPathComponent("snapshot.json")
    let snapshotStore = SnapshotStore(fileURL: snapshotFile)

    let mockID = UUID().uuidString
    let client = makeMockClient(id: mockID)
    let fixtureData = try loadRecordedPublicFixture()

    MockURLProtocol.registerHandler(id: mockID) { request in
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }
    defer { MockURLProtocol.unregisterHandler(id: mockID) }

    let service = RepoRadarService(
      configStore: configStore,
      tokenStore: tokenStore,
      client: client,
      snapshotStore: snapshotStore
    )

    let fixedNow = try Date("2026-10-24T12:00:00Z", strategy: .iso8601)
    let snapshot = try await service.refresh(now: fixedNow)

    #expect(snapshot.status == .ok)
    #expect(snapshot.updatedAt == fixedNow)
    #expect(snapshot.rateLimit?.remaining == 4857)
    #expect(snapshot.rateLimit?.cost == 49)
    #expect(snapshot.staleBranches.count > 0)

    // Verify snapshot was written to disk and can be read back identically
    let diskSnapshot = try snapshotStore.read()
    #expect(diskSnapshot == snapshot)

    // Verify file on disk never contains token string
    let fileData = try Data(contentsOf: snapshotFile)
    let fileContent = String(decoding: fileData, as: UTF8.self).lowercased()
    #expect(!fileContent.contains("test-auth-pat"))
    #expect(!fileContent.contains("authorization"))
    #expect(!fileContent.contains("bearer"))
  }

  @Test("End-to-end refresh writes empty ok snapshot when no repos are watched")
  func endToEndRefreshEmptyRepos() async throws {
    let suiteName = "test-reporadar-service-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let configStore = ConfigStore(userDefaults: defaults)
    try configStore.save(RepoRadarConfig(watchedRepos: []))

    let tokenStore = InMemoryTokenStore(initialToken: "test-token")
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("RepoRadarTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let snapshotStore = SnapshotStore(fileURL: tempDir.appendingPathComponent("snapshot.json"))

    let mockID = UUID().uuidString
    var networkCalled = false
    MockURLProtocol.registerHandler(id: mockID) { _ in
      networkCalled = true
      throw URLError(.badServerResponse)
    }
    defer { MockURLProtocol.unregisterHandler(id: mockID) }

    let service = RepoRadarService(
      configStore: configStore,
      tokenStore: tokenStore,
      client: makeMockClient(id: mockID),
      snapshotStore: snapshotStore
    )

    let now = Date()
    let snapshot = try await service.refresh(now: now)

    #expect(!networkCalled)
    #expect(snapshot.status == .ok)
    #expect(snapshot.pullRequests.isEmpty)
    #expect(snapshot.failingCI.isEmpty)

    let diskSnapshot = try snapshotStore.read()
    #expect(diskSnapshot.status == .ok)
  }

  @Test("End-to-end refresh writes tokenError snapshot and throws when token is missing")
  func endToEndRefreshMissingToken() async throws {
    let suiteName = "test-reporadar-service-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let configStore = ConfigStore(userDefaults: defaults)
    try configStore.save(RepoRadarConfig(watchedRepos: ["Cwander83/repo-radar"]))

    let tokenStore = InMemoryTokenStore(initialToken: nil)
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("RepoRadarTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let snapshotStore = SnapshotStore(fileURL: tempDir.appendingPathComponent("snapshot.json"))

    let mockID = UUID().uuidString
    let service = RepoRadarService(
      configStore: configStore,
      tokenStore: tokenStore,
      client: makeMockClient(id: mockID),
      snapshotStore: snapshotStore
    )

    await #expect(throws: RepoRadarError.tokenMissing) {
      try await service.refresh()
    }

    let diskSnapshot = try snapshotStore.read()
    #expect(diskSnapshot.status == .tokenError(detail: "GitHub personal access token missing"))
  }

  @Test("Keychain read failure reports tokenError with detail, not tokenMissing")
  func endToEndRefreshKeychainReadFailure() async throws {
    let suiteName = "test-reporadar-service-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let configStore = ConfigStore(userDefaults: defaults)
    try configStore.save(RepoRadarConfig(watchedRepos: ["Cwander83/repo-radar"]))

    let tokenStore = FailingTokenStore(
      errorToThrow: KeychainError.osStatus(status: -25300, message: "Decryption failure")
    )
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("RepoRadarTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let snapshotStore = SnapshotStore(fileURL: tempDir.appendingPathComponent("snapshot.json"))

    let service = RepoRadarService(
      configStore: configStore,
      tokenStore: tokenStore,
      client: makeMockClient(id: UUID().uuidString),
      snapshotStore: snapshotStore
    )

    let expectedError = RepoRadarError.tokenUnauthorized(
      detail: "Keychain error (-25300): Decryption failure"
    )
    await #expect(throws: expectedError) {
      try await service.refresh()
    }

    let diskSnapshot = try snapshotStore.read()
    #expect(
      diskSnapshot.status == .tokenError(detail: "Keychain error (-25300): Decryption failure")
    )
  }

  @Test(
    "End-to-end refresh preserves cached data across consecutive offline runs (ok -> offline -> offline)"
  )
  func endToEndRefreshConsecutiveOfflinePreservesCache() async throws {
    let suiteName = "test-reporadar-service-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let configStore = ConfigStore(userDefaults: defaults)
    try configStore.save(RepoRadarConfig(watchedRepos: ["Cwander83/repo-radar"]))

    let tokenStore = InMemoryTokenStore(initialToken: "valid-token")
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("RepoRadarTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let snapshotStore = SnapshotStore(fileURL: tempDir.appendingPathComponent("snapshot.json"))

    let fixtureData = try loadRecordedPublicFixture()
    let mockID = UUID().uuidString
    let service = RepoRadarService(
      configStore: configStore,
      tokenStore: tokenStore,
      client: makeMockClient(id: mockID),
      snapshotStore: snapshotStore
    )

    // 1. Initial successful refresh
    MockURLProtocol.registerHandler(id: mockID) { request in
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }

    let initialTime = try Date("2026-10-24T12:00:00Z", strategy: .iso8601)
    let initial = try await service.refresh(now: initialTime)
    #expect(initial.status == .ok)
    #expect(!initial.staleBranches.isEmpty)

    // 2. First offline refresh
    MockURLProtocol.registerHandler(id: mockID) { _ in
      throw URLError(.notConnectedToInternet)
    }

    let offlineTime1 = initialTime.addingTimeInterval(300)
    await #expect(throws: RepoRadarError.self) {
      try await service.refresh(now: offlineTime1)
    }

    let diskSnapshot1 = try snapshotStore.read()
    if case .offline = diskSnapshot1.status {
      #expect(!diskSnapshot1.staleBranches.isEmpty)
      #expect(diskSnapshot1.updatedAt == initialTime)  // Preserved original update time
    } else {
      Issue.record("Expected .offline status with cached data on first failure")
    }

    // 3. Second consecutive offline refresh (must NOT wipe data)
    let offlineTime2 = offlineTime1.addingTimeInterval(300)
    await #expect(throws: RepoRadarError.self) {
      try await service.refresh(now: offlineTime2)
    }

    let diskSnapshot2 = try snapshotStore.read()
    if case .offline = diskSnapshot2.status {
      #expect(!diskSnapshot2.staleBranches.isEmpty)
      #expect(diskSnapshot2.staleBranches == initial.staleBranches)
      #expect(diskSnapshot2.updatedAt == initialTime)
    } else {
      Issue.record("Expected .offline status to keep cached data on second consecutive failure")
    }

    MockURLProtocol.unregisterHandler(id: mockID)
  }

  @Test("End-to-end refresh preserves cached data across consecutive rate limited runs")
  func endToEndRefreshPreservesCacheRateLimited() async throws {
    let suiteName = "test-reporadar-service-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let configStore = ConfigStore(userDefaults: defaults)
    try configStore.save(RepoRadarConfig(watchedRepos: ["Cwander83/repo-radar"]))

    let tokenStore = InMemoryTokenStore(initialToken: "valid-token")
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("RepoRadarTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let snapshotStore = SnapshotStore(fileURL: tempDir.appendingPathComponent("snapshot.json"))

    let fixtureData = try loadRecordedPublicFixture()
    let mockID = UUID().uuidString
    let service = RepoRadarService(
      configStore: configStore,
      tokenStore: tokenStore,
      client: makeMockClient(id: mockID),
      snapshotStore: snapshotStore
    )

    // 1. Initial success
    MockURLProtocol.registerHandler(id: mockID) { request in
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }
    _ = try await service.refresh()

    // 2. Rate limited 403 response
    let resetEpoch = Int(Date().timeIntervalSince1970) + 1800
    MockURLProtocol.registerHandler(id: mockID) { request in
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 403,
        httpVersion: nil,
        headerFields: [
          "x-ratelimit-remaining": "0",
          "x-ratelimit-reset": "\(resetEpoch)",
        ]
      )!
      return (response, Data("rate limit exceeded".utf8))
    }
    defer { MockURLProtocol.unregisterHandler(id: mockID) }

    await #expect(throws: RepoRadarError.self) {
      try await service.refresh()
    }

    let diskSnapshot1 = try snapshotStore.read()
    if case .rateLimited(let resetAt, _) = diskSnapshot1.status {
      #expect(resetAt != nil)
      #expect(!diskSnapshot1.staleBranches.isEmpty)
    } else {
      Issue.record("Expected .rateLimited status with preserved cache on run 1")
    }

    // 3. Second consecutive rate-limited run
    await #expect(throws: RepoRadarError.self) {
      try await service.refresh()
    }

    let diskSnapshot2 = try snapshotStore.read()
    if case .rateLimited(let resetAt, _) = diskSnapshot2.status {
      #expect(resetAt != nil)
      #expect(!diskSnapshot2.staleBranches.isEmpty)
    } else {
      Issue.record("Expected .rateLimited status with preserved cache on run 2")
    }
  }

  @Test("Convenience init returns nil when App Group is unavailable")
  func convenienceInitReturnsNilOnUnavailableAppGroup() {
    let service = RepoRadarService(appGroupIdentifier: "")
    #expect(service == nil)
  }

  @Test(
    "Live refresh against GitHub writes a valid snapshot",
    .enabled(if: ProcessInfo.processInfo.environment["REPORADAR_LIVE_TEST"] == "1")
  )
  func liveRefreshAgainstGitHub() async throws {
    guard let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty else {
      return
    }

    let suiteName = "test-live-refresh-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let configStore = ConfigStore(userDefaults: defaults)
    try configStore.save(
      RepoRadarConfig(
        watchedRepos: ["Cwander83/repo-radar"],
        pollInterval: .fiveMinutes,
        staleDays: 30
      )
    )

    let tokenStore = InMemoryTokenStore(initialToken: token)
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("RepoRadarLiveTest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let snapshotStore = SnapshotStore(fileURL: tempDir.appendingPathComponent("snapshot.json"))

    let liveClient = GitHubGraphQLClient(session: .shared)
    let service = RepoRadarService(
      configStore: configStore,
      tokenStore: tokenStore,
      client: liveClient,
      snapshotStore: snapshotStore
    )

    let snapshot = try await service.refresh()
    #expect(snapshot.status == .ok)
    #expect(snapshot.rateLimit != nil)

    let diskSnapshot = try snapshotStore.read()
    #expect(diskSnapshot.status == .ok)
  }
}
