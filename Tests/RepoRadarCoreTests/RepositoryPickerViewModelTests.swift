import Foundation
import Testing

@testable import RepoRadarCore

@Suite("RepositoryPickerViewModelTests")
struct RepositoryPickerViewModelTests {
  private func makeTestDefaults() -> (UserDefaults, String) {
    let suiteName = "test-reporadar-picker-vm-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (defaults, suiteName)
  }

  private func makeSampleRepos(count: Int) -> [ViewerRepositoryNode] {
    var repos: [ViewerRepositoryNode] = []
    repos.reserveCapacity(count)
    for i in 1...count {
      let isPrivate = (i % 2 == 0)
      let isArchived = (i % 5 == 0)
      let offset = TimeInterval(-i * 3600)
      let pushed = Date().addingTimeInterval(offset)
      let repo = ViewerRepositoryNode(
        nameWithOwner: "owner/repo-\(i)",
        isPrivate: isPrivate,
        isArchived: isArchived,
        pushedAt: pushed,
        defaultBranchRef: RefBranch(name: "main")
      )
      repos.append(repo)
    }
    return repos
  }

  @Test("Initializes with watched repos checked and matches selection state")
  @MainActor
  func testInitializesWithWatchedRepos() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let configStore = ConfigStore(userDefaults: defaults)
    configStore.save(
      sanitizing: RepoRadarConfig(
        watchedRepos: ["Cwander83/repo-radar", "Cwander83/gravity-bar"]
      )
    )
    let tokenStore = InMemoryTokenStore(initialToken: "test-token")

    let vm = RepositoryPickerViewModel(configStore: configStore, tokenStore: tokenStore)

    #expect(vm.selectedCount == 2)
    #expect(vm.isSelected("Cwander83/repo-radar") == true)
    #expect(vm.isSelected("Cwander83/gravity-bar") == true)
    #expect(vm.isSelected("Cwander83/other-repo") == false)
    #expect(vm.isAtCap == false)
    #expect(vm.canSelectMore == true)
    #expect(vm.selectionCounterText == "2 of 25 selected")
  }

  @Test("Selection cap enforced at 25 repositories")
  @MainActor
  func testSelectionCapEnforced() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let initial25 = (1...25).map { "owner/repo-\($0)" }
    let configStore = ConfigStore(userDefaults: defaults)
    configStore.save(sanitizing: RepoRadarConfig(watchedRepos: initial25))
    let tokenStore = InMemoryTokenStore(initialToken: "test-token")

    let vm = RepositoryPickerViewModel(configStore: configStore, tokenStore: tokenStore)

    #expect(vm.selectedCount == 25)
    #expect(vm.isAtCap == true)
    #expect(vm.canSelectMore == false)
    #expect(vm.canToggle("owner/repo-1") == true)
    #expect(vm.canToggle("owner/repo-26") == false)

    // Cannot add a 26th repo
    vm.toggleSelection("owner/repo-26")
    #expect(vm.selectedCount == 25)
    #expect(vm.isSelected("owner/repo-26") == false)

    // Unselecting one frees up a slot
    vm.toggleSelection("owner/repo-1")
    #expect(vm.selectedCount == 24)
    #expect(vm.isAtCap == false)
    #expect(vm.canSelectMore == true)
    #expect(vm.canToggle("owner/repo-26") == true)

    // Can now select the new repo
    vm.toggleSelection("owner/repo-26")
    #expect(vm.selectedCount == 25)
    #expect(vm.isSelected("owner/repo-26") == true)
    #expect(vm.isAtCap == true)
  }

  @Test("Select all checks the 25 most recently pushed repos")
  @MainActor
  func testSelectAllPicksTop25() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let configStore = ConfigStore(userDefaults: defaults)
    let tokenStore = InMemoryTokenStore(initialToken: "test-token")
    var repos: [ViewerRepositoryNode] = []
    repos.reserveCapacity(35)
    for i in 1...35 {
      let offset = TimeInterval(-i * 3600)
      let pushed = Date().addingTimeInterval(offset)
      repos.append(
        ViewerRepositoryNode(
          nameWithOwner: "owner/repo-\(i)",
          isPrivate: false,
          isArchived: false,
          pushedAt: pushed,
          defaultBranchRef: RefBranch(name: "main")
        )
      )
    }

    let vm = RepositoryPickerViewModel(configStore: configStore, tokenStore: tokenStore)
    vm.allRepositories = repos

    vm.selectAll()

    #expect(vm.selectedCount == 25)
    #expect(vm.isAtCap == true)
    for i in 1...25 {
      #expect(vm.isSelected("owner/repo-\(i)") == true)
    }
    #expect(vm.isSelected("owner/repo-26") == false)
  }

  @Test("Select none clears all selections")
  @MainActor
  func testSelectNone() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let configStore = ConfigStore(userDefaults: defaults)
    configStore.save(sanitizing: RepoRadarConfig(watchedRepos: ["owner/repo-1", "owner/repo-2"]))
    let tokenStore = InMemoryTokenStore(initialToken: "test-token")

    let vm = RepositoryPickerViewModel(configStore: configStore, tokenStore: tokenStore)
    #expect(vm.selectedCount == 2)

    vm.selectNone()
    #expect(vm.selectedCount == 0)
    #expect(vm.selectedRepos.isEmpty == true)
    #expect(vm.selectionCounterText == "0 of 25 selected")
  }

  @Test("Search query filters visible repositories case-insensitively")
  @MainActor
  func testSearchFiltersVisibleRepositories() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let configStore = ConfigStore(userDefaults: defaults)
    let tokenStore = InMemoryTokenStore(initialToken: "test-token")
    let vm = RepositoryPickerViewModel(configStore: configStore, tokenStore: tokenStore)
    vm.allRepositories = [
      ViewerRepositoryNode(nameWithOwner: "Cwander83/repo-radar", isPrivate: false, isArchived: false),
      ViewerRepositoryNode(nameWithOwner: "Cwander83/gravity-bar", isPrivate: false, isArchived: false),
      ViewerRepositoryNode(nameWithOwner: "apple/swift", isPrivate: false, isArchived: false)
    ]

    #expect(vm.visibleRepositories.count == 3)

    vm.searchQuery = "radar"
    #expect(vm.visibleRepositories.count == 1)
    #expect(vm.visibleRepositories.first?.nameWithOwner == "Cwander83/repo-radar")

    vm.searchQuery = "CWANDER83"
    #expect(vm.visibleRepositories.count == 2)

    vm.searchQuery = "nonexistent"
    #expect(vm.visibleRepositories.isEmpty == true)

    vm.searchQuery = ""
    #expect(vm.visibleRepositories.count == 3)
  }

  @Test("Archived repositories are hidden by default and shown with toggle")
  @MainActor
  func testArchivedRepositoriesVisibility() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let configStore = ConfigStore(userDefaults: defaults)
    let tokenStore = InMemoryTokenStore(initialToken: "test-token")
    let vm = RepositoryPickerViewModel(configStore: configStore, tokenStore: tokenStore)
    vm.allRepositories = [
      ViewerRepositoryNode(nameWithOwner: "owner/active", isPrivate: false, isArchived: false),
      ViewerRepositoryNode(nameWithOwner: "owner/archived", isPrivate: false, isArchived: true)
    ]

    #expect(vm.showArchived == false)
    #expect(vm.visibleRepositories.count == 1)
    #expect(vm.visibleRepositories.first?.nameWithOwner == "owner/active")

    vm.showArchived = true
    #expect(vm.visibleRepositories.count == 2)
  }

  @Test("loadRepositories handles successful fetch, zero repos, and missing token")
  @MainActor
  func testLoadRepositoriesStates() async {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let configStore = ConfigStore(userDefaults: defaults)

    // 1. Missing token
    let emptyTokenStore = InMemoryTokenStore()
    let vmNoToken = RepositoryPickerViewModel(configStore: configStore, tokenStore: emptyTokenStore)
    await vmNoToken.loadRepositories()
    #expect(vmNoToken.errorMessage == "Add a GitHub token first.")
    #expect(vmNoToken.isLoading == false)

    // 2. Successful fetch with repos
    let tokenStore = InMemoryTokenStore(initialToken: "valid-token")
    let sample = makeSampleRepos(count: 3)
    let vmSuccess = RepositoryPickerViewModel(
      configStore: configStore,
      tokenStore: tokenStore,
      fetcher: { sample }
    )
    await vmSuccess.loadRepositories()
    #expect(vmSuccess.allRepositories.count == 3)
    #expect(vmSuccess.isZeroRepos == false)
    #expect(vmSuccess.errorMessage == nil)

    // 3. Zero repos returned
    let vmZero = RepositoryPickerViewModel(
      configStore: configStore,
      tokenStore: tokenStore,
      fetcher: { [] }
    )
    await vmZero.loadRepositories()
    #expect(vmZero.allRepositories.isEmpty == true)
    #expect(vmZero.isZeroRepos == true)
    #expect(vmZero.errorMessage == nil)
  }

  @Test("loadRepositories maps RepoRadarErrors accurately")
  @MainActor
  func testLoadRepositoriesErrorMapping() async {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let configStore = ConfigStore(userDefaults: defaults)
    let tokenStore = InMemoryTokenStore(initialToken: "token")

    // Offline error
    let vmOffline = RepositoryPickerViewModel(
      configStore: configStore,
      tokenStore: tokenStore,
      fetcher: { throw RepoRadarError.offline(detail: "DNS failed") }
    )
    await vmOffline.loadRepositories()
    #expect(vmOffline.errorMessage?.contains("Network offline") == true)

    // 401 Unauthorized
    let vmAuth = RepositoryPickerViewModel(
      configStore: configStore,
      tokenStore: tokenStore,
      fetcher: { throw RepoRadarError.tokenUnauthorized(detail: "Bad credentials") }
    )
    await vmAuth.loadRepositories()
    #expect(vmAuth.errorMessage?.contains("GitHub authentication failed") == true)

    // Rate limited
    let reset = Date(timeIntervalSince1970: 1800000000)
    let vmRate = RepositoryPickerViewModel(
      configStore: configStore,
      tokenStore: tokenStore,
      fetcher: { throw RepoRadarError.rateLimited(resetAt: reset) }
    )
    await vmRate.loadRepositories()
    #expect(vmRate.errorMessage?.contains("rate limit exceeded") == true)
  }

  @Test("save preserves existing watched order, appends new, and triggers callback")
  @MainActor
  func testSavePreservesOrderAndTriggersCallback() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let configStore = ConfigStore(userDefaults: defaults)
    configStore.save(sanitizing: RepoRadarConfig(watchedRepos: ["owner/b", "owner/a"]))
    let tokenStore = InMemoryTokenStore(initialToken: "token")

    var savedRepos: [String]?
    let vm = RepositoryPickerViewModel(
      configStore: configStore,
      tokenStore: tokenStore,
      onSave: { saved in
        savedRepos = saved
      }
    )
    vm.allRepositories = [
      ViewerRepositoryNode(nameWithOwner: "owner/c", isPrivate: false, isArchived: false),
      ViewerRepositoryNode(nameWithOwner: "owner/b", isPrivate: false, isArchived: false),
      ViewerRepositoryNode(nameWithOwner: "owner/a", isPrivate: false, isArchived: false)
    ]

    // Select owner/c as well
    vm.toggleSelection("owner/c")

    vm.save()

    #expect(savedRepos == ["owner/b", "owner/a", "owner/c"])
  }

  @Test("Integration: makePickerViewModel in RepositoriesSettingsViewModel saves and triggers refresh")
  @MainActor
  func testIntegrationWithRepositoriesSettingsViewModel() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let configStore = ConfigStore(userDefaults: defaults)
    configStore.save(sanitizing: RepoRadarConfig(watchedRepos: ["owner/repo-1"]))
    let tokenStore = InMemoryTokenStore(initialToken: "token")

    var refreshCount = 0
    var configChangedCount = 0

    let parentVM = RepositoriesSettingsViewModel(
      configStore: configStore,
      tokenStore: tokenStore,
      onConfigChange: { _ in configChangedCount += 1 },
      onRefreshRequest: { refreshCount += 1 }
    )

    let pickerVM = parentVM.makePickerViewModel(fetcher: {
      [
        ViewerRepositoryNode(nameWithOwner: "owner/repo-1", isPrivate: false, isArchived: false),
        ViewerRepositoryNode(nameWithOwner: "owner/repo-2", isPrivate: false, isArchived: false)
      ]
    })

    #expect(pickerVM.isSelected("owner/repo-1") == true)
    #expect(pickerVM.isSelected("owner/repo-2") == false)

    pickerVM.allRepositories = [
      ViewerRepositoryNode(nameWithOwner: "owner/repo-1", isPrivate: false, isArchived: false),
      ViewerRepositoryNode(nameWithOwner: "owner/repo-2", isPrivate: false, isArchived: false)
    ]
    pickerVM.toggleSelection("owner/repo-2")
    pickerVM.save()

    #expect(parentVM.watchedRepos == ["owner/repo-1", "owner/repo-2"])
    #expect(configStore.load().watchedRepos == ["owner/repo-1", "owner/repo-2"])
    #expect(refreshCount == 1)
    #expect(configChangedCount == 1)
  }
}
