import Foundation
import Testing
@testable import RepoRadarCore

#if canImport(AppKit)
import AppKit
#endif

@Suite("MenuBarItemModelTests")
struct MenuBarItemModelTests {

  @Test("MenuBarState maps correctly across all status and configuration conditions")
  func testMenuBarStateMapping() {
    // Missing status / App Group unavailable
    #expect(
      MenuBarState.current(status: nil, failingCICount: 0) == .error
    )

    // Token missing
    #expect(
      MenuBarState.current(status: .ok, failingCICount: 0, hasToken: false) == .error
    )

    // Watched repos missing
    #expect(
      MenuBarState.current(status: .ok, failingCICount: 0, hasWatchedRepos: false) == .error
    )

    // Error statuses
    #expect(
      MenuBarState.current(status: .tokenError(detail: "expired"), failingCICount: 0) == .error
    )
    #expect(
      MenuBarState.current(status: .corrupt(detail: "bad json"), failingCICount: 0) == .error
    )
    #expect(
      MenuBarState.current(status: .unsupportedVersion(version: 99), failingCICount: 0) == .error
    )

    // Server error status is transient like offline (CHR-101)
    #expect(
      MenuBarState.current(status: .serverError(detail: "500"), failingCICount: 0) == .offline
    )
    #expect(
      MenuBarState.current(status: .serverError(detail: "500"), failingCICount: 4) == .offline
    )

    // Offline status
    #expect(
      MenuBarState.current(status: .offline(detail: "No network"), failingCICount: 0) == .offline
    )
    #expect(
      MenuBarState.current(status: .offline(detail: "No network"), failingCICount: 4) == .offline
    )

    // Missing (first run with token & repos)
    #expect(
      MenuBarState.current(status: .missing, failingCICount: 0) == .clear
    )

    // OK status with zero failures
    #expect(
      MenuBarState.current(status: .ok, failingCICount: 0) == .clear
    )

    // OK status with failures and badge enabled
    #expect(
      MenuBarState.current(status: .ok, failingCICount: 2, showMenuBarCount: true)
        == .failing(count: 2)
    )

    // OK status with failures but badge turned off in settings
    #expect(
      MenuBarState.current(status: .ok, failingCICount: 2, showMenuBarCount: false) == .clear
    )

    // Rate limited status with failures and badge enabled
    #expect(
      MenuBarState.current(status: .rateLimited(), failingCICount: 3, showMenuBarCount: true)
        == .failing(count: 3)
    )

    // Rate limited status with failures but badge turned off
    #expect(
      MenuBarState.current(status: .rateLimited(), failingCICount: 3, showMenuBarCount: false)
        == .clear
    )
  }

  @Test("MenuBarState properties return expected symbols, dimming, badge, and labels")
  func testMenuBarStateProperties() {
    let clear = MenuBarState.clear
    #expect(clear.systemImageName == AppSymbol.app)
    #expect(clear.isDimmed == false)
    #expect(clear.badgeCount == nil)
    #expect(clear.accessibilityLabel == "Repo Radar: All checks passing")

    let failing = MenuBarState.failing(count: 5)
    #expect(failing.systemImageName == AppSymbol.app)
    #expect(failing.isDimmed == false)
    #expect(failing.badgeCount == 5)
    #expect(failing.accessibilityLabel == "Repo Radar: 5 failing checks")

    let failingOne = MenuBarState.failing(count: 1)
    #expect(failingOne.accessibilityLabel == "Repo Radar: 1 failing check")

    let failingZero = MenuBarState.failing(count: 0)
    #expect(failingZero.badgeCount == nil)

    let offline = MenuBarState.offline
    #expect(offline.systemImageName == AppSymbol.app)
    #expect(offline.isDimmed == true)
    #expect(offline.badgeCount == nil)
    #expect(offline.accessibilityLabel == "Repo Radar: Offline")

    let error = MenuBarState.error
    #expect(error.systemImageName == "exclamationmark.triangle")
    #expect(error.isDimmed == false)
    #expect(error.badgeCount == nil)
    #expect(error.accessibilityLabel == "Repo Radar: Attention required")
  }

  #if canImport(AppKit)
  @Test("Every menu bar and widget section symbol exists in SF Symbols (CHR-102)")
  func testSymbolNamesResolve() {
    let states: [MenuBarState] = [.clear, .failing(count: 2), .offline, .error]
    let names = states.map(\.systemImageName) + WidgetSectionChoice.allCases.map(\.iconName)
    for name in names {
      #expect(
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
        "Missing SF Symbol: \(name)"
      )
    }
  }

  @Test("MenuBarBadgeImage renders valid, non-template image with correct bounds")
  @MainActor
  func testBadgeImageRendering() {
    let imgSingle = MenuBarBadgeImage.render(count: 2)
    #expect(imgSingle.isTemplate == false)
    #expect(imgSingle.size.height == MenuBarBadgeImage.badgeHeight)
    #expect(imgSingle.size.width >= MenuBarBadgeImage.badgeMinWidth)

    let imgDouble = MenuBarBadgeImage.render(count: 42)
    #expect(imgDouble.isTemplate == false)
    #expect(imgDouble.size.height == MenuBarBadgeImage.badgeHeight)
    #expect(imgDouble.size.width >= imgSingle.size.width)

    let imgCapped = MenuBarBadgeImage.render(count: 150)
    #expect(imgCapped.isTemplate == false)
    #expect(imgCapped.size.height == MenuBarBadgeImage.badgeHeight)
  }
  #endif

  @Test("RefreshScheduler.menuBarState reflects service state")
  @MainActor
  func testRefreshSchedulerMenuBarState() throws {
    let defaults = UserDefaults(suiteName: "test.menubar.state.\(UUID().uuidString)")!
    let configStore = ConfigStore(userDefaults: defaults)
    try configStore.save(
      RepoRadarConfig(
        watchedRepos: ["owner/repo"],
        showMenuBarCount: true
      )
    )

    let tokenStore = InMemoryTokenStore(initialToken: "ghp_valid_test_token")

    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let snapshotFile = tempDir.appendingPathComponent("snapshot.json")
    let snapshotStore = SnapshotStore(fileURL: snapshotFile)

    let service = RepoRadarService(
      configStore: configStore,
      tokenStore: tokenStore,
      client: GitHubGraphQLClient(),
      snapshotStore: snapshotStore
    )

    let scheduler = RefreshScheduler(service: service)
    // Initially snapshot is missing, but token & watchedRepos exist -> clear
    #expect(scheduler.menuBarState == MenuBarState.clear)

    // When snapshot has failing CI
    let snapshot = WidgetSnapshot(
      updatedAt: Date(),
      status: .ok,
      failingCI: [
        FailingCIItem(
          repo: "owner/repo",
          ref: "main",
          kind: .defaultBranch,
          check: "Test",
          conclusion: "FAILURE"
        )
      ]
    )
    try snapshotStore.write(snapshot)

    let schedulerWithSnapshot = RefreshScheduler(service: service)
    #expect(schedulerWithSnapshot.failingCICount == 1)
    #expect(schedulerWithSnapshot.menuBarState == MenuBarState.failing(count: 1))

    // When showMenuBarCount is false
    var disabledConfig = configStore.load()
    disabledConfig.showMenuBarCount = false
    try configStore.save(disabledConfig)
    schedulerWithSnapshot.configurationDidChange()

    #expect(schedulerWithSnapshot.menuBarState == MenuBarState.clear)
  }
}
