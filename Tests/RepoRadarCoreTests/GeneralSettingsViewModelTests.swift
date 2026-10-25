import Foundation
import Testing

@testable import RepoRadarCore

@Suite("GeneralSettingsViewModelTests")
struct GeneralSettingsViewModelTests {
  private func makeTestDefaults() -> (UserDefaults, String) {
    let suiteName = "test-reporadar-settings-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (defaults, suiteName)
  }

  @Test("PollInterval displayName matches mockup format")
  func pollIntervalDisplayName() {
    #expect(PollInterval.fiveMinutes.displayName == "5 minutes")
    #expect(PollInterval.tenMinutes.displayName == "10 minutes")
    #expect(PollInterval.fifteenMinutes.displayName == "15 minutes")
  }

  @Test("Initializes with values from config store")
  @MainActor
  func initializesWithDefaults() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let vm = GeneralSettingsViewModel(configStore: store)

    #expect(vm.pollInterval == .fiveMinutes)
    #expect(vm.refreshOnWake == true)
    #expect(vm.launchAtLogin == false)
    #expect(vm.showMenuBarCount == true)
    #expect(vm.ciNotifications == false)
  }

  @Test("Modifying each control persists to config store and triggers callback")
  @MainActor
  func modifyingControlsPersists() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    var changeCount = 0
    var latestConfig: RepoRadarConfig?

    let vm = GeneralSettingsViewModel(configStore: store) { config in
      changeCount += 1
      latestConfig = config
    }

    // 1. Poll interval
    vm.pollInterval = .tenMinutes
    #expect(store.load().pollInterval == .tenMinutes)
    #expect(latestConfig?.pollInterval == .tenMinutes)
    #expect(changeCount == 1)

    // 2. Refresh on wake
    vm.refreshOnWake = false
    #expect(store.load().refreshOnWake == false)
    #expect(latestConfig?.refreshOnWake == false)
    #expect(changeCount == 2)

    // 3. Launch at login
    vm.launchAtLogin = true
    #expect(store.load().launchAtLogin == true)
    #expect(latestConfig?.launchAtLogin == true)
    #expect(changeCount == 3)

    // 4. Show failing-CI count in menu bar
    vm.showMenuBarCount = false
    #expect(store.load().showMenuBarCount == false)
    #expect(latestConfig?.showMenuBarCount == false)
    #expect(changeCount == 4)

    // 5. Notify when CI turns red
    vm.ciNotifications = true
    #expect(store.load().ciNotifications == true)
    #expect(latestConfig?.ciNotifications == true)
    #expect(changeCount == 5)

    // Unchanged value does not trigger additional save/callback
    vm.ciNotifications = true
    #expect(changeCount == 5)
  }

  @Test("Reload updates properties from store")
  @MainActor
  func reloadPicksUpExternalChanges() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let vm = GeneralSettingsViewModel(configStore: store)

    var updated = store.load()
    updated.pollInterval = .fifteenMinutes
    updated.refreshOnWake = false
    updated.launchAtLogin = true
    updated.showMenuBarCount = false
    updated.ciNotifications = true
    store.save(sanitizing: updated)

    vm.reload()

    #expect(vm.pollInterval == .fifteenMinutes)
    #expect(vm.refreshOnWake == false)
    #expect(vm.launchAtLogin == true)
    #expect(vm.showMenuBarCount == false)
    #expect(vm.ciNotifications == true)
  }
}
