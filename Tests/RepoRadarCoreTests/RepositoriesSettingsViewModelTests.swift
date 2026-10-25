import Foundation
import Combine
import Testing

@testable import RepoRadarCore

@Suite("RepositoriesSettingsViewModelTests")
struct RepositoriesSettingsViewModelTests {
  private func makeTestDefaults() -> (UserDefaults, String) {
    let suiteName = "test-reporadar-repos-settings-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (defaults, suiteName)
  }

  @Test("Initializes with watched repos and stale days from store")
  @MainActor
  func initializesFromStore() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    store.save(
      sanitizing: RepoRadarConfig(
        watchedRepos: ["Cwander83/repo-radar", "Cwander83/gravity-bar"],
        staleDays: 45
      )
    )

    let vm = RepositoriesSettingsViewModel(configStore: store)

    #expect(vm.watchedRepos == ["Cwander83/repo-radar", "Cwander83/gravity-bar"])
    #expect(vm.staleDays == 45)
    #expect(vm.totalCount == 2)
  }

  @Test("Access mapping computes reachable count, status text, and default branch")
  @MainActor
  func accessMappingFromSnapshot() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    store.save(
      sanitizing: RepoRadarConfig(
        watchedRepos: ["Cwander83/repo-radar", "Cwander83/private-no-access", "Cwander83/pending-repo"]
      )
    )

    let snapshot = WidgetSnapshot(
      status: .ok,
      repositoryAccess: [
        RepositoryAccessItem(name: "Cwander83/repo-radar", defaultBranch: "develop", hasAccess: true),
        RepositoryAccessItem(name: "Cwander83/private-no-access", defaultBranch: nil, hasAccess: false)
      ]
    )

    let vm = RepositoriesSettingsViewModel(configStore: store, snapshot: snapshot)

    #expect(vm.totalCount == 3)
    #expect(vm.reachableCount == 1) // only confirmed-OK repos count

    #expect(vm.hasAccess(for: "Cwander83/repo-radar") == true)
    #expect(vm.accessStatus(for: "Cwander83/repo-radar") == .ok)
    #expect(vm.statusText(for: "Cwander83/repo-radar") == "OK")
    #expect(vm.defaultBranch(for: "Cwander83/repo-radar") == "develop")

    #expect(vm.hasAccess(for: "Cwander83/private-no-access") == false)
    #expect(vm.accessStatus(for: "Cwander83/private-no-access") == .noAccess)
    #expect(vm.statusText(for: "Cwander83/private-no-access") == "No access")
    #expect(vm.defaultBranch(for: "Cwander83/private-no-access") == nil)

    // Unlisted/pending repo displays Checking… and hasAccess is nil
    #expect(vm.hasAccess(for: "Cwander83/pending-repo") == nil)
    #expect(vm.accessStatus(for: "Cwander83/pending-repo") == .checking)
    #expect(vm.statusText(for: "Cwander83/pending-repo") == "Checking…")
    #expect(vm.defaultBranch(for: "Cwander83/pending-repo") == nil)
  }

  @Test("Unverified repos display Checking… state without counting as reachable")
  @MainActor
  func unverifiedRepositoriesShowCheckingState() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    store.save(
      sanitizing: RepoRadarConfig(
        watchedRepos: ["owner/unverified-1", "owner/unverified-2"]
      )
    )

    // Nil snapshot or snapshot with empty repositoryAccess
    let vm = RepositoriesSettingsViewModel(configStore: store, snapshot: nil)

    #expect(vm.totalCount == 2)
    #expect(vm.reachableCount == 0)

    #expect(vm.accessStatus(for: "owner/unverified-1") == .checking)
    #expect(vm.statusText(for: "owner/unverified-1") == "Checking…")
    #expect(vm.hasAccess(for: "owner/unverified-1") == nil)

    #expect(vm.accessStatus(for: "owner/unverified-2") == .checking)
    #expect(vm.statusText(for: "owner/unverified-2") == "Checking…")
    #expect(vm.hasAccess(for: "owner/unverified-2") == nil)
  }

  @Test("Adding a repo and delivering new snapshot updates access status and reachable count")
  @MainActor
  func liveSnapshotUpdatesAccessAfterAdd() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let snapshotSubject = PassthroughSubject<WidgetSnapshot?, Never>()

    let vm = RepositoriesSettingsViewModel(
      configStore: store,
      snapshotPublisher: snapshotSubject.eraseToAnyPublisher()
    )

    vm.newRepoInput = "Cwander83/new-repo"
    vm.addRepository()

    #expect(vm.watchedRepos == ["Cwander83/new-repo"])
    #expect(vm.accessStatus(for: "Cwander83/new-repo") == .checking)
    #expect(vm.statusText(for: "Cwander83/new-repo") == "Checking…")
    #expect(vm.hasAccess(for: "Cwander83/new-repo") == nil)
    #expect(vm.reachableCount == 0)

    // Deliver updated snapshot
    let updatedSnapshot = WidgetSnapshot(
      status: .ok,
      repositoryAccess: [
        RepositoryAccessItem(name: "Cwander83/new-repo", defaultBranch: "main", hasAccess: true)
      ]
    )
    snapshotSubject.send(updatedSnapshot)

    #expect(vm.accessStatus(for: "Cwander83/new-repo") == .ok)
    #expect(vm.statusText(for: "Cwander83/new-repo") == "OK")
    #expect(vm.hasAccess(for: "Cwander83/new-repo") == true)
    #expect(vm.defaultBranch(for: "Cwander83/new-repo") == "main")
    #expect(vm.reachableCount == 1)
  }

  @Test("Adding valid repository persists and triggers refresh")
  @MainActor
  func addingValidRepository() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    var changeCount = 0
    var refreshCount = 0

    let vm = RepositoriesSettingsViewModel(
      configStore: store,
      onConfigChange: { _ in changeCount += 1 },
      onRefreshRequest: { refreshCount += 1 }
    )

    vm.newRepoInput = "Cwander83/repo-radar"
    vm.addRepository()

    #expect(vm.errorMessage == nil)
    #expect(vm.newRepoInput == "")
    #expect(vm.watchedRepos == ["Cwander83/repo-radar"])
    #expect(store.load().watchedRepos == ["Cwander83/repo-radar"])
    #expect(changeCount == 1)
    #expect(refreshCount == 1)
  }

  @Test("Adding duplicate or invalid repository sets errorMessage without changing store")
  @MainActor
  func addingInvalidRepository() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    try? store.addWatchedRepo("Cwander83/repo-radar")

    let vm = RepositoriesSettingsViewModel(configStore: store)

    // 1. Missing slash
    vm.newRepoInput = "just-a-name"
    vm.addRepository()
    #expect(vm.errorMessage != nil)
    #expect(vm.watchedRepos.count == 1)

    // 2. Duplicate repo
    vm.newRepoInput = "Cwander83/repo-radar"
    vm.addRepository()
    #expect(vm.errorMessage?.contains("Duplicate") == true)
    #expect(vm.watchedRepos.count == 1)
  }

  @Test("Removing repository persists and triggers refresh")
  @MainActor
  func removingRepository() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    try? store.addWatchedRepo("Cwander83/repo-radar")
    try? store.addWatchedRepo("Cwander83/gravity-bar")

    var refreshCount = 0
    let vm = RepositoriesSettingsViewModel(
      configStore: store,
      onRefreshRequest: { refreshCount += 1 }
    )

    #expect(vm.watchedRepos.count == 2)
    vm.removeRepository("Cwander83/repo-radar")

    #expect(vm.watchedRepos == ["Cwander83/gravity-bar"])
    #expect(store.load().watchedRepos == ["Cwander83/gravity-bar"])
    #expect(refreshCount == 1)
  }

  @Test("Modifying stale days threshold persists to config store and debounces refresh (CHR-101)")
  @MainActor
  func modifyingStaleDays() async throws {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let fakeClock = FakeClock()
    var refreshCount = 0
    let vm = RepositoriesSettingsViewModel(
      configStore: store,
      clock: fakeClock,
      onRefreshRequest: { refreshCount += 1 }
    )

    // Rapidly change staleDays multiple times (simulating holding or repeatedly clicking stepper)
    vm.staleDays = 31
    vm.staleDays = 32
    vm.staleDays = 60

    #expect(store.load().staleDays == 60)
    #expect(refreshCount == 0)

    try await fakeClock.waitForPendingSleepCount(1)
    fakeClock.advance(by: 1.0)

    for _ in 0..<50 {
      if refreshCount == 1 { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(refreshCount == 1)
  }

  @Test("Debounced stale days refresh still fires after the view model is released (CHR-101)")
  @MainActor
  func debouncedRefreshSurvivesRelease() async throws {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let fakeClock = FakeClock()
    var refreshCount = 0
    var vm: RepositoriesSettingsViewModel? = RepositoriesSettingsViewModel(
      configStore: store,
      clock: fakeClock,
      onRefreshRequest: { refreshCount += 1 }
    )
    weak var weakVM = vm

    vm?.staleDays = 45
    try await fakeClock.waitForPendingSleepCount(1)

    // Settings window closes before the debounce ends.
    vm = nil
    #expect(weakVM == nil)

    fakeClock.advance(by: 1.0)

    for _ in 0..<50 {
      if refreshCount == 1 { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(store.load().staleDays == 45)
    #expect(refreshCount == 1)
  }

  @Test("Classifier correctly identifies inaccessible repos when missing from GraphQL nodes")
  func classifierFlagsMissingReposAsNoAccess() {
    let repoNode = RepositoryNode(
      nameWithOwner: "Cwander83/repo-radar",
      url: URL(string: "https://github.com/Cwander83/repo-radar")!,
      isPrivate: false,
      isArchived: false,
      defaultBranchRef: RefBranch(name: "develop"),
      pullRequests: PullRequestConnection(totalCount: 0, nodes: []),
      refs: RefConnection(totalCount: 0, pageInfo: nil, nodes: [])
    )

    let report = Classifier.classify(
      repos: [repoNode],
      watchedRepos: ["Cwander83/repo-radar", "Cwander83/forbidden-repo"],
      viewerLogin: "Cwander83"
    )

    #expect(report.repositoryAccess.count == 2)

    let accessible = report.repositoryAccess.first { $0.name == "Cwander83/repo-radar" }
    #expect(accessible?.hasAccess == true)
    #expect(accessible?.defaultBranch == "develop")

    let inaccessible = report.repositoryAccess.first { $0.name == "Cwander83/forbidden-repo" }
    #expect(inaccessible?.hasAccess == false)
    #expect(inaccessible?.defaultBranch == nil)
  }
}
