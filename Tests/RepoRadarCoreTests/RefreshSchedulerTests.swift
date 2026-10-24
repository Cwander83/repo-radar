import Foundation
import Testing

@testable import RepoRadarCore

@Suite(.serialized)
@MainActor
struct RefreshSchedulerTests {
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

  private struct TestContext {
    let suiteName: String
    let defaults: UserDefaults
    let configStore: ConfigStore
    let tokenStore: InMemoryTokenStore
    let tempDir: URL
    let snapshotStore: SnapshotStore
    let mockID: String
    let client: GitHubGraphQLClient
    let service: RepoRadarService

    init(repos: [String] = ["Cwander83/repo-radar"], pollInterval: PollInterval = .fiveMinutes)
      throws
    {
      self.suiteName = "test-scheduler-\(UUID().uuidString)"
      self.defaults = UserDefaults(suiteName: suiteName)!
      self.configStore = ConfigStore(userDefaults: defaults)
      try configStore.save(
        RepoRadarConfig(
          watchedRepos: repos,
          pollInterval: pollInterval,
          staleDays: 30
        )
      )

      self.tokenStore = InMemoryTokenStore(initialToken: "test-valid-pat")
      self.tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("SchedulerTest-\(UUID().uuidString)")
      let snapshotFile = tempDir.appendingPathComponent("snapshot.json")
      self.snapshotStore = SnapshotStore(fileURL: snapshotFile)

      self.mockID = UUID().uuidString
      let endpoint = URL(string: "https://api.github.com/graphql")!
      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [MockURLProtocol.self]
      config.httpAdditionalHeaders = ["X-Mock-Handler-ID": mockID]
      let session = URLSession(configuration: config)
      self.client = GitHubGraphQLClient(session: session, endpoint: endpoint)

      self.service = RepoRadarService(
        configStore: configStore,
        tokenStore: tokenStore,
        client: client,
        snapshotStore: snapshotStore
      )
    }

    func cleanup() {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: tempDir)
      MockURLProtocol.unregisterHandler(id: mockID)
    }
  }

  @Test("Observable state publishes values and counts on successful refresh")
  func testObservableStateUpdates() async throws {
    let ctx = try TestContext()
    defer { ctx.cleanup() }

    let fixtureData = try loadRecordedPublicFixture()
    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }

    let fakeClock = FakeClock()
    let scheduler = RefreshScheduler(service: ctx.service, clock: fakeClock)

    #expect(scheduler.isRefreshing == false)
    #expect(scheduler.status == .missing)
    #expect(scheduler.lastUpdated == nil)
    #expect(scheduler.failingCICount == 0)

    let snapshot = try await scheduler.performRefresh()

    #expect(scheduler.isRefreshing == false)
    #expect(scheduler.status == .ok)
    #expect(scheduler.lastUpdated == fakeClock.now)
    #expect(scheduler.failingCICount == snapshot.failingCI.count)
    #expect(scheduler.pullRequestCount == snapshot.pullRequests.count)
    #expect(scheduler.staleBranchCount == snapshot.staleBranches.count)
    #expect(scheduler.lastError == nil)
  }

  @Test("Widget reloads after successful refresh and on error")
  func testWidgetReloads() async throws {
    let ctx = try TestContext()
    defer { ctx.cleanup() }

    let fixtureData = try loadRecordedPublicFixture()
    var returnError = false

    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      if returnError {
        let response = HTTPURLResponse(
          url: URL(string: "https://api.github.com/graphql")!,
          statusCode: 500,
          httpVersion: nil,
          headerFields: nil
        )!
        return (response, Data())
      }
      let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }

    final class ReloadTracker: @unchecked Sendable {
      var count = 0
    }
    let tracker = ReloadTracker()
    let fakeClock = FakeClock()

    let scheduler = RefreshScheduler(
      service: ctx.service,
      clock: fakeClock,
      widgetReloader: { tracker.count += 1 }
    )

    // 1. Success triggers reload
    try await scheduler.performRefresh()
    #expect(tracker.count == 1)

    // 2. Error write triggers reload as well
    returnError = true
    do {
      try await scheduler.performRefresh()
      Issue.record("Expected server error")
    } catch {
      #expect(tracker.count == 2)
      #expect(scheduler.status != .ok)
    }
  }

  @Test("No overlapping runs when concurrent refreshes are triggered")
  func testNoOverlappingRuns() async throws {
    let ctx = try TestContext()
    defer { ctx.cleanup() }

    let fixtureData = try loadRecordedPublicFixture()
    final class CallCounter: @unchecked Sendable {
      var calls = 0
    }
    let counter = CallCounter()

    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      counter.calls += 1
      Thread.sleep(forTimeInterval: 0.05)
      let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }

    let fakeClock = FakeClock()
    let scheduler = RefreshScheduler(service: ctx.service, clock: fakeClock)

    async let first = scheduler.performRefresh()
    async let second = scheduler.performRefresh()

    let (snap1, snap2) = try await (first, second)
    #expect(snap1.updatedAt == snap2.updatedAt)
    #expect(counter.calls == 1)
  }

  @Test("Timer loop triggers periodic refresh at configured interval")
  func testPeriodicTimerRefresh() async throws {
    let ctx = try TestContext(pollInterval: .fiveMinutes)
    defer { ctx.cleanup() }

    let fixtureData = try loadRecordedPublicFixture()
    final class QueryCounter: @unchecked Sendable {
      var count = 0
    }
    let counter = QueryCounter()

    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      counter.count += 1
      let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }

    let fakeClock = FakeClock()
    let scheduler = RefreshScheduler(service: ctx.service, clock: fakeClock)

    scheduler.start()
    defer { scheduler.stop() }

    // Wait for initial refresh and subsequent sleep scheduling
    try await fakeClock.waitForSleepCalls(count: 1)
    #expect(counter.count == 1)
    #expect(fakeClock.lastSleepRequestedDuration == 300)

    // Advance clock by 300 seconds to trigger second refresh
    fakeClock.advance(by: 300)
    try await fakeClock.waitForSleepCalls(count: 2)
    #expect(counter.count == 2)
  }

  @Test("Manual refresh executes immediately and restarts timer interval")
  func testManualRefreshRestartsTimer() async throws {
    let ctx = try TestContext(pollInterval: .tenMinutes)
    defer { ctx.cleanup() }

    let fixtureData = try loadRecordedPublicFixture()
    final class QueryCounter: @unchecked Sendable {
      var count = 0
    }
    let counter = QueryCounter()

    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      counter.count += 1
      let response = HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, fixtureData)
    }

    let fakeClock = FakeClock()
    let scheduler = RefreshScheduler(service: ctx.service, clock: fakeClock)

    scheduler.start()
    defer { scheduler.stop() }

    try await fakeClock.waitForSleepCalls(count: 1)
    #expect(counter.count == 1)

    // Manual refresh now
    let snap = try await scheduler.refreshNow()
    #expect(snap.status == .ok)
    #expect(counter.count == 2)

    // Timer was rescheduled to sleep 600s
    try await fakeClock.waitForSleepCalls(count: 2)
    #expect(fakeClock.lastSleepRequestedDuration == 600)
  }

  @Test("Rate limit backoff calculates delay until resetAt")
  func testRateLimitBackoff() throws {
    let ctx = try TestContext(pollInterval: .fiveMinutes)
    defer { ctx.cleanup() }

    let fakeClock = FakeClock(now: Date(timeIntervalSince1970: 10000))
    let scheduler = RefreshScheduler(service: ctx.service, clock: fakeClock)

    // Normal interval when no error
    #expect(scheduler.computeDelay(after: nil) == 300)

    // Rate limited with future resetAt
    let resetAt = Date(timeIntervalSince1970: 10750)
    let rateLimitError = RepoRadarError.rateLimited(resetAt: resetAt)
    let delay = scheduler.computeDelay(after: rateLimitError)
    #expect(delay == 750)

    // Rate limited with past resetAt uses 60s floor
    let pastReset = Date(timeIntervalSince1970: 9000)
    let pastError = RepoRadarError.rateLimited(resetAt: pastReset)
    #expect(scheduler.computeDelay(after: pastError) == 60)
  }

  @Test("Offline backoff increases exponentially on consecutive failures")
  func testOfflineBackoff() async throws {
    let ctx = try TestContext(pollInterval: .fifteenMinutes) // 900s
    defer { ctx.cleanup() }

    MockURLProtocol.registerHandler(id: ctx.mockID) { _ in
      throw URLError(.notConnectedToInternet)
    }

    let fakeClock = FakeClock()
    let scheduler = RefreshScheduler(service: ctx.service, clock: fakeClock)

    // First offline failure: 60s
    do { _ = try await scheduler.performRefresh() } catch {}
    #expect(scheduler.consecutiveOfflineCount == 1)
    #expect(scheduler.computeDelay(after: scheduler.lastError) == 60)

    // Second consecutive offline failure: 120s
    do { _ = try await scheduler.performRefresh() } catch {}
    #expect(scheduler.consecutiveOfflineCount == 2)
    #expect(scheduler.computeDelay(after: scheduler.lastError) == 120)

    // Third consecutive offline failure: 240s
    do { _ = try await scheduler.performRefresh() } catch {}
    #expect(scheduler.consecutiveOfflineCount == 3)
    #expect(scheduler.computeDelay(after: scheduler.lastError) == 240)
  }
}
