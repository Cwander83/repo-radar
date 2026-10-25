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
    let state = WidgetState.current(
      readResult: .corrupt(detail: "Bad JSON syntax"), watchedRepos: ["owner/repo"])
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
    let resetDate = Date(timeIntervalSince1970: 1_792_900_000)
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
    #expect(
      state == .rateLimited(snapshot: snapshot, resetAt: resetDate, detail: "Rate limit exceeded"))
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

  @Test("relativeTimeString formats relative differences accurately")
  func testRelativeTimeString() {
    let now = Date()
    #expect(
      WidgetSnapshot.relativeTimeString(from: now.addingTimeInterval(-20), relativeTo: now)
        == "just now")
    #expect(
      WidgetSnapshot.relativeTimeString(from: now.addingTimeInterval(-300), relativeTo: now)
        == "5m ago")
    #expect(
      WidgetSnapshot.relativeTimeString(from: now.addingTimeInterval(-7200), relativeTo: now)
        == "2h ago")
    #expect(
      WidgetSnapshot.relativeTimeString(from: now.addingTimeInterval(-86400 * 4), relativeTo: now)
        == "4d ago")
    #expect(
      WidgetSnapshot.relativeTimeString(from: now.addingTimeInterval(50), relativeTo: now)
        == "just now")
  }

  @Test("prioritizedWidgetItems orders items: failing CI, running CI, PRs (reviews first), stale")
  func testPrioritizedWidgetItems() {
    let now = Date()
    let snapshot = WidgetSnapshot(
      updatedAt: now,
      status: .ok,
      failingCI: [
        FailingCIItem(
          repo: "Cwander83/repo-radar",
          ref: "main",
          kind: .mainBranch,
          check: "Build",
          conclusion: "FAILURE",
          url: URL(string: "https://github.com/Cwander83/repo-radar/actions/runs/1"),
          completedAt: now.addingTimeInterval(-120)
        )
      ],
      runningCI: [
        RunningCIItem(
          repo: "Cwander83/gravity-bar",
          ref: "develop",
          kind: .defaultBranch,
          check: "Test",
          status: "IN_PROGRESS",
          url: URL(string: "https://github.com/Cwander83/gravity-bar/actions/runs/2"),
          startedAt: now.addingTimeInterval(-60)
        )
      ],
      pullRequests: [
        ClassifiedPullRequest(
          repo: "Cwander83/repo-radar",
          number: 10,
          title: "My Feature",
          url: URL(string: "https://github.com/Cwander83/repo-radar/pull/10")!,
          headRefName: "my-feat",
          reason: .mine,
          authorLogin: "Cwander83",
          updatedAt: now.addingTimeInterval(-3600)
        ),
        ClassifiedPullRequest(
          repo: "Cwander83/gravity-bar",
          number: 22,
          title: "Review This Fix",
          url: URL(string: "https://github.com/Cwander83/gravity-bar/pull/22")!,
          headRefName: "fix-bug",
          reason: .reviewRequested,
          authorLogin: "alice",
          updatedAt: now.addingTimeInterval(-1800)
        ),
      ],
      staleBranches: [
        StaleBranchItem(
          repo: "Cwander83/repo-radar",
          branch: "old-experiment",
          ageDays: 45,
          lastCommitDate: now.addingTimeInterval(-86400 * 45),
          lastCommitOid: "1234567"
        )
      ]
    )

    let items = snapshot.prioritizedWidgetItems(now: now)
    #expect(items.count == 5)

    // 1. Failing CI first
    #expect(items[0].kind == .failingCI)
    #expect(items[0].iconName == "xmark.circle.fill")
    #expect(items[0].title == "Cwander83/repo-radar · main")
    #expect(items[0].subtitle == "Build · 2m ago")

    // 2. Running CI second
    #expect(items[1].kind == .runningCI)
    #expect(items[1].iconName == "circle.dashed")
    #expect(items[1].title == "Cwander83/gravity-bar · develop")
    #expect(items[1].subtitle == "Test · running")

    // 3. Review requested PR third
    #expect(items[2].kind == .pullRequest(isReviewRequested: true))
    #expect(items[2].iconName == "eye")
    #expect(items[2].title == "Review This Fix")
    #expect(items[2].subtitle.contains("review requested"))

    // 4. Authored PR fourth
    #expect(items[3].kind == .pullRequest(isReviewRequested: false))
    #expect(items[3].iconName == "arrow.triangle.pull")
    #expect(items[3].title == "My Feature")
    #expect(!items[3].subtitle.contains("review requested"))

    // 5. Stale branch fifth
    #expect(items[4].kind == .staleBranch)
    #expect(items[4].iconName == "arrow.triangle.branch")
    #expect(items[4].title == "old-experiment")
    #expect(items[4].subtitle == "Cwander83/repo-radar · 45d")
  }

  @Test("WidgetSnapshot filtering by section isolates specific categories")
  func testSnapshotFilteringBySection() {
    let now = Date()
    let snapshot = WidgetSnapshot(
      updatedAt: now,
      status: .ok,
      failingCI: [
        FailingCIItem(
          repo: "Cwander83/repo-radar",
          ref: "main",
          kind: .mainBranch,
          check: "CI",
          conclusion: "FAILURE"
        )
      ],
      runningCI: [
        RunningCIItem(
          repo: "Cwander83/repo-radar",
          ref: "dev",
          kind: .defaultBranch,
          check: "Tests",
          status: "IN_PROGRESS"
        )
      ],
      pullRequests: [
        ClassifiedPullRequest(
          repo: "Cwander83/repo-radar",
          number: 1,
          title: "PR",
          url: URL(string: "https://github.com/Cwander83/repo-radar/pull/1")!,
          headRefName: "pr",
          reason: .mine,
          updatedAt: now
        )
      ],
      staleBranches: [
        StaleBranchItem(
          repo: "Cwander83/repo-radar",
          branch: "stale",
          ageDays: 40,
          lastCommitDate: now,
          lastCommitOid: "123"
        )
      ]
    )

    // Filter to failingCI: keeps failing and running, clears PRs and stale
    let ciOnly = snapshot.filtered(section: .failingCI)
    #expect(ciOnly.failingCI.count == 1)
    #expect(ciOnly.runningCI.count == 1)
    #expect(ciOnly.pullRequests.isEmpty)
    #expect(ciOnly.staleBranches.isEmpty)

    // Filter to pullRequests: keeps PRs, clears others
    let prOnly = snapshot.filtered(section: .pullRequests)
    #expect(prOnly.failingCI.isEmpty)
    #expect(prOnly.runningCI.isEmpty)
    #expect(prOnly.pullRequests.count == 1)
    #expect(prOnly.staleBranches.isEmpty)

    // Filter to staleBranches: keeps stale, clears others
    let staleOnly = snapshot.filtered(section: .staleBranches)
    #expect(staleOnly.failingCI.isEmpty)
    #expect(staleOnly.runningCI.isEmpty)
    #expect(staleOnly.pullRequests.isEmpty)
    #expect(staleOnly.staleBranches.count == 1)
  }

  @Test("WidgetSnapshot filtering by repository isolates specific repository")
  func testSnapshotFilteringByRepository() {
    let now = Date()
    let snapshot = WidgetSnapshot(
      updatedAt: now,
      status: .ok,
      failingCI: [
        FailingCIItem(
          repo: "Cwander83/repo-radar",
          ref: "main",
          kind: .mainBranch,
          check: "CI",
          conclusion: "FAILURE"
        ),
        FailingCIItem(
          repo: "Cwander83/gravity-bar",
          ref: "main",
          kind: .mainBranch,
          check: "CI",
          conclusion: "FAILURE"
        )
      ],
      pullRequests: [
        ClassifiedPullRequest(
          repo: "Cwander83/repo-radar",
          number: 1,
          title: "PR 1",
          url: URL(string: "https://github.com/Cwander83/repo-radar/pull/1")!,
          headRefName: "pr1",
          reason: .mine,
          updatedAt: now
        ),
        ClassifiedPullRequest(
          repo: "Cwander83/gravity-bar",
          number: 2,
          title: "PR 2",
          url: URL(string: "https://github.com/Cwander83/gravity-bar/pull/2")!,
          headRefName: "pr2",
          reason: .mine,
          updatedAt: now
        )
      ],
      repositoryAccess: [
        RepositoryAccessItem(name: "Cwander83/repo-radar", defaultBranch: "main"),
        RepositoryAccessItem(name: "Cwander83/gravity-bar", defaultBranch: "main")
      ]
    )

    // Filter by specific repository
    let repoRadarOnly = snapshot.filtered(repository: "Cwander83/repo-radar")
    #expect(repoRadarOnly.failingCI.count == 1)
    #expect(repoRadarOnly.failingCI.first?.repo == "Cwander83/repo-radar")
    #expect(repoRadarOnly.pullRequests.count == 1)
    #expect(repoRadarOnly.pullRequests.first?.repo == "Cwander83/repo-radar")
    #expect(repoRadarOnly.repositoryAccess.count == 1)

    // "all" repository keyword keeps all repositories
    let allRepos = snapshot.filtered(repository: "all")
    #expect(allRepos.failingCI.count == 2)
    #expect(allRepos.pullRequests.count == 2)

    // Section + repository combined filter
    let combined = snapshot.filtered(section: .failingCI, repository: "Cwander83/gravity-bar")
    #expect(combined.failingCI.count == 1)
    #expect(combined.failingCI.first?.repo == "Cwander83/gravity-bar")
    #expect(combined.pullRequests.isEmpty)
  }

  @Test("WidgetTimelineLoader loadEntry applies section and repository filters")
  func testLoaderFilters() throws {
    let tempDir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let snapshotFile = tempDir.appendingPathComponent("snapshot.json")
    let suiteName = "test-widget-filters-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let snapshotStore = SnapshotStore(fileURL: snapshotFile)
    let configStore = ConfigStore(userDefaults: defaults)

    let now = Date()
    let snapshot = WidgetSnapshot(
      updatedAt: now,
      status: .ok,
      failingCI: [
        FailingCIItem(
          repo: "Cwander83/repo-radar",
          ref: "main",
          kind: .mainBranch,
          check: "CI",
          conclusion: "FAILURE"
        )
      ],
      pullRequests: [
        ClassifiedPullRequest(
          repo: "Cwander83/gravity-bar",
          number: 14,
          title: "PR",
          url: URL(string: "https://github.com/Cwander83/gravity-bar/pull/14")!,
          headRefName: "pr",
          reason: .mine,
          updatedAt: now
        )
      ]
    )
    try snapshotStore.write(snapshot)

    let loader = WidgetTimelineLoader(snapshotStore: snapshotStore, configStore: configStore)

    // 1. Load with section: .pullRequests
    let prEntry = loader.loadEntry(section: .pullRequests)
    #expect(prEntry.section == WidgetSectionChoice.pullRequests)
    #expect(prEntry.snapshot?.failingCI.isEmpty == true)
    #expect(prEntry.snapshot?.pullRequests.count == 1)

    // 2. Load with repository: "Cwander83/repo-radar"
    let repoEntry = loader.loadEntry(repository: "Cwander83/repo-radar")
    #expect(repoEntry.repositoryFilter == "Cwander83/repo-radar")
    #expect(repoEntry.snapshot?.failingCI.count == 1)
    #expect(repoEntry.snapshot?.pullRequests.isEmpty == true)
  }
}
