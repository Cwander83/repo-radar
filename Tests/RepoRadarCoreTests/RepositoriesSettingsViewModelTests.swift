import Foundation
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
        watchedRepos: ["Cwander83/repo-radar", "Cwander83/private-no-access"]
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

    #expect(vm.totalCount == 2)
    #expect(vm.reachableCount == 1)

    #expect(vm.hasAccess(for: "Cwander83/repo-radar") == true)
    #expect(vm.statusText(for: "Cwander83/repo-radar") == "OK")
    #expect(vm.defaultBranch(for: "Cwander83/repo-radar") == "develop")

    #expect(vm.hasAccess(for: "Cwander83/private-no-access") == false)
    #expect(vm.statusText(for: "Cwander83/private-no-access") == "No access")
    #expect(vm.defaultBranch(for: "Cwander83/private-no-access") == nil)

    // Unlisted repo defaults to No access
    #expect(vm.hasAccess(for: "unknown/repo") == false)
    #expect(vm.statusText(for: "unknown/repo") == "No access")
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

  @Test("Modifying stale days threshold persists to config store")
  @MainActor
  func modifyingStaleDays() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    var refreshCount = 0
    let vm = RepositoriesSettingsViewModel(
      configStore: store,
      onRefreshRequest: { refreshCount += 1 }
    )

    vm.staleDays = 60
    #expect(store.load().staleDays == 60)
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
