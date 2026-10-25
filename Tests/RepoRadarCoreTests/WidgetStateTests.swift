import Foundation
import Testing

@testable import RepoRadarCore

@Suite("WidgetStateTests")
struct WidgetStateTests {
  private func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("reporadar-widget-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test("Missing snapshot maps to firstRun")
  func missingSnapshotMapsToFirstRun() {
    let state = WidgetState.current(readResult: .missing, watchedRepos: [])
    #expect(state == .firstRun)
    #expect(state.statusTitle == "Welcome to Repo Radar")
    #expect(state.isDimmed == false)
    #expect(state.snapshot == nil)
  }

  @Test("Corrupt snapshot maps to error")
  func corruptSnapshotMapsToError() {
    let state = WidgetState.current(readResult: .corrupt(detail: "Bad JSON syntax"), watchedRepos: ["owner/repo"])
    #expect(state == .error(detail: "Bad JSON syntax"))
    #expect(state.statusTitle == "Error")
    #expect(state.statusSubtitle == "Bad JSON syntax")
    #expect(state.isDimmed == false)
  }

  @Test("Unsupported version maps to error with update notice")
  func unsupportedVersionMapsToError() {
    let state = WidgetState.current(readResult: .unsupportedVersion(version: 99), watchedRepos: [])
    if case .error(let detail) = state {
      #expect(detail.contains("version 99"))
    } else {
      Issue.record("Expected .error state")
    }
  }

  @Test("Token error maps to tokenError state")
  func tokenErrorMapsCorrectly() {
    let snapshot = WidgetSnapshot(
      status: .tokenError(detail: "Token expired on Oct 24"),
      report: ClassifiedReport()
    )
    let state = WidgetState.current(snapshot: snapshot, watchedRepos: ["Cwander83/repo-radar"])
    #expect(state == .tokenError(detail: "Token expired on Oct 24"))
    #expect(state.statusTitle == "Authentication Error")
    #expect(state.statusSubtitle == "Token expired on Oct 24")
  }

  @Test("No repositories configured maps to noRepos state")
  func noReposMapsCorrectly() {
    let emptySnapshot = WidgetSnapshot(
      status: .ok,
      report: ClassifiedReport(),
      rateLimit: nil
    )
    let state = WidgetState.current(snapshot: emptySnapshot, watchedRepos: [])
    #expect(state == .noRepos)
    #expect(state.statusTitle == "No Repositories")
  }

  @Test("All clear state when watched repos have no issues")
  func allClearState() {
    let snapshot = WidgetSnapshot(
      status: .ok,
      failingCI: [],
      runningCI: [],
      pullRequests: [],
      staleBranches: [],
      repositoryAccess: [
        RepositoryAccessItem(name: "Cwander83/repo-radar", defaultBranch: "main", hasAccess: true)
      ]
    )
    let state = WidgetState.current(snapshot: snapshot, watchedRepos: ["Cwander83/repo-radar"])
    #expect(state == .allClear(snapshot))
    #expect(state.statusTitle == "All Clear")
    #expect(state.hasActionableItems == false)
    #expect(state.failingCount == 0)
    #expect(state.prCount == 0)
    #expect(state.staleCount == 0)
  }

  @Test("Data state when active items exist")
  func dataStateWithItems() {
    let failing = FailingCIItem(
      repo: "Cwander83/repo-radar",
      ref: "main",
      kind: .mainBranch,
      check: "CI",
      conclusion: "FAILURE",
      url: URL(string: "https://github.com/Cwander83/repo-radar")!
    )
    let pr = ClassifiedPullRequest(
      repo: "Cwander83/repo-radar",
      number: 1,
      title: "Test PR",
      url: URL(string: "https://github.com/Cwander83/repo-radar/pull/1")!,
      headRefName: "test-pr",
      reason: .reviewRequested,
      authorLogin: "Cwander83",
      updatedAt: Date()
    )
    let snapshot = WidgetSnapshot(
      status: .ok,
      failingCI: [failing],
      pullRequests: [pr]
    )

    let state = WidgetState.current(snapshot: snapshot, watchedRepos: ["Cwander83/repo-radar"])
    #expect(state == .data(snapshot))
    #expect(state.failingCount == 1)
    #expect(state.prCount == 1)
    #expect(state.reviewRequestCount == 1)
    #expect(state.hasActionableItems == true)
    #expect(state.isDimmed == false)
  }

  @Test("Offline state preserves cached snapshot and dims content")
  func offlineStateDimsContent() {
    let snapshot = WidgetSnapshot(
      status: .offline(detail: "DNS resolution failed"),
      failingCI: [
        FailingCIItem(
          repo: "Cwander83/gravity-bar",
          ref: "main",
          kind: .mainBranch,
          check: "CI",
          conclusion: "FAILURE",
          url: URL(string: "https://github.com/Cwander83/gravity-bar")!
        )
      ]
    )

    let state = WidgetState.current(snapshot: snapshot, watchedRepos: ["Cwander83/gravity-bar"])
    #expect(state == .offline(snapshot: snapshot, detail: "DNS resolution failed"))
    #expect(state.isDimmed == true)
    #expect(state.statusTitle == "Offline")
    #expect(state.statusSubtitle == "DNS resolution failed")
    #expect(state.failingCount == 1)
    #expect(state.snapshot == snapshot)
  }

  @Test("Rate limited state preserves cached snapshot and shows reset time")
  func rateLimitedStateShowsResetTime() {
    let resetDate = Date(timeIntervalSince1970: 1792900000)
    let snapshot = WidgetSnapshot(
      status: .rateLimited(resetAt: resetDate, detail: "Rate limit exceeded"),
      staleBranches: [
        StaleBranchItem(
          repo: "Cwander83/repo-radar",
          branch: "old-branch",
          ageDays: 45,
          lastCommitDate: Date().addingTimeInterval(-86400 * 45),
          lastCommitOid: "abc"
        )
      ]
    )

    let state = WidgetState.current(snapshot: snapshot, watchedRepos: ["Cwander83/repo-radar"])
    #expect(state == .rateLimited(snapshot: snapshot, resetAt: resetDate, detail: "Rate limit exceeded"))
    #expect(state.isDimmed == true)
    #expect(state.statusTitle == "Rate Limited")
    #expect(state.statusSubtitle?.contains("Resets at") == true)
    #expect(state.staleCount == 1)
  }

  @Test("WidgetTimelineLoader loads entry from disk snapshot and config store")
  func widgetTimelineLoaderReadsDisk() throws {
    let tempDir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileURL = tempDir.appendingPathComponent("snapshot.json")
    let snapshotStore = SnapshotStore(fileURL: fileURL)

    let suiteName = "test-widget-config-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let configStore = ConfigStore(userDefaults: defaults)
    configStore.save(sanitizing: RepoRadarConfig(watchedRepos: ["Cwander83/repo-radar"]))

    let loader = WidgetTimelineLoader(snapshotStore: snapshotStore, configStore: configStore)

    // 1. Missing snapshot initially
    let initialEntry = loader.loadEntry()
    #expect(initialEntry.state == .firstRun)
    #expect(initialEntry.watchedRepos == ["Cwander83/repo-radar"])

    // 2. Write snapshot to disk
    let snapshot = WidgetSnapshot(
      status: .ok,
      failingCI: [
        FailingCIItem(
          repo: "Cwander83/repo-radar",
          ref: "main",
          kind: .mainBranch,
          check: "CI",
          conclusion: "FAILURE",
          url: URL(string: "https://github.com/Cwander83/repo-radar")!
        )
      ]
    )
    try snapshotStore.write(snapshot)

    // 3. Re-read entry reflects new snapshot
    let updatedEntry = loader.loadEntry()
    if case .data(let loaded) = updatedEntry.state {
      #expect(loaded.failingCI == snapshot.failingCI)
      #expect(loaded.status == snapshot.status)
    } else {
      Issue.record("Expected .data state, got \(updatedEntry.state)")
    }
    #expect(updatedEntry.snapshot?.failingCI.count == 1)
  }

  @Test("WidgetTimelineLoader handles unavailable snapshot store")
  func loaderHandlesNilSnapshotStore() {
    let loader = WidgetTimelineLoader(snapshotStore: nil, configStore: nil)
    let entry = loader.loadEntry()
    #expect(entry.state == .error(detail: "App Group container unavailable"))
  }
}
