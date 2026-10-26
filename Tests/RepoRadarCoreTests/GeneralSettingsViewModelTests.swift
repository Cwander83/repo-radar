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

  @Test("Initializes with values from config store and launchAtLoginManager")
  @MainActor
  func initializesWithDefaults() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let loginManager = InMemoryLaunchAtLoginManager(status: .notRegistered)
    let vm = GeneralSettingsViewModel(configStore: store, launchAtLoginManager: loginManager)

    #expect(vm.pollInterval == .fiveMinutes)
    #expect(vm.refreshOnWake == true)
    #expect(vm.launchAtLogin == false)
    #expect(vm.launchAtLoginStatus == .notRegistered)
    #expect(vm.showMenuBarCount == true)
    #expect(vm.ciNotifications == false)
  }

  @Test("Initializes reflecting real system login item status when enabled or requiresApproval")
  @MainActor
  func initializesReflectingSystemStatus() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)

    // When system is enabled:
    let enabledManager = InMemoryLaunchAtLoginManager(status: .enabled)
    let vmEnabled = GeneralSettingsViewModel(configStore: store, launchAtLoginManager: enabledManager)
    #expect(vmEnabled.launchAtLogin == true)
    #expect(vmEnabled.launchAtLoginStatus == .enabled)
    #expect(store.load().launchAtLogin == true)

    // When system requires approval:
    let approvalManager = InMemoryLaunchAtLoginManager(status: .requiresApproval)
    let vmApproval = GeneralSettingsViewModel(configStore: store, launchAtLoginManager: approvalManager)
    #expect(vmApproval.launchAtLogin == true)
    #expect(vmApproval.launchAtLoginStatus == .requiresApproval)
  }

  @Test("Modifying each control persists to config store and triggers callback")
  @MainActor
  func modifyingControlsPersists() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let loginManager = InMemoryLaunchAtLoginManager(status: .notRegistered)
    var changeCount = 0
    var latestConfig: RepoRadarConfig?

    let vm = GeneralSettingsViewModel(configStore: store, launchAtLoginManager: loginManager) { config in
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
    #expect(loginManager.status == .enabled)
    #expect(loginManager.setEnabledCallCount == 1)
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

  @Test("Toggling launch at login unregisters from loginManager and persists")
  @MainActor
  func togglingLaunchAtLoginOff() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let loginManager = InMemoryLaunchAtLoginManager(status: .enabled)
    let vm = GeneralSettingsViewModel(configStore: store, launchAtLoginManager: loginManager)

    #expect(vm.launchAtLogin == true)
    vm.launchAtLogin = false

    #expect(loginManager.status == .notRegistered)
    #expect(store.load().launchAtLogin == false)
    #expect(vm.launchAtLoginError == nil)
  }

  @Test("Failed setEnabled reverts toggle and sets error message without updating store")
  @MainActor
  func failedSetEnabledReverts() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let loginManager = InMemoryLaunchAtLoginManager(status: .notRegistered)
    struct MockError: LocalizedError {
      var errorDescription: String? { "Operation not permitted" }
    }
    loginManager.setEnabledError = MockError()

    let vm = GeneralSettingsViewModel(configStore: store, launchAtLoginManager: loginManager)
    #expect(vm.launchAtLogin == false)

    vm.launchAtLogin = true

    #expect(vm.launchAtLogin == false)
    #expect(vm.launchAtLoginError?.contains("Operation not permitted") == true)
    #expect(store.load().launchAtLogin == false)
  }

  @Test("Failed toggle while status is requiresApproval reverts to on, not off (CHR-101)")
  @MainActor
  func failedToggleWhileRequiresApprovalRevertsToOn() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let loginManager = InMemoryLaunchAtLoginManager(status: .requiresApproval)
    struct MockError: LocalizedError {
      var errorDescription: String? { "Operation not permitted" }
    }
    loginManager.setEnabledError = MockError()

    let vm = GeneralSettingsViewModel(configStore: store, launchAtLoginManager: loginManager)
    #expect(vm.launchAtLogin == true)

    // Turning it off fails; the status is still requiresApproval, which the init and
    // refresh paths treat as on, so the revert must land on on as well.
    vm.launchAtLogin = false

    #expect(vm.launchAtLogin == true)
    #expect(vm.launchAtLoginStatus == .requiresApproval)
    #expect(vm.launchAtLoginError?.contains("Operation not permitted") == true)
    #expect(store.load().launchAtLogin == true)

    // A later status refresh agrees and doesn't flip the toggle.
    vm.refreshLaunchAtLoginStatus()
    #expect(vm.launchAtLogin == true)
  }

  @Test("Reflects external status changes from System Settings")
  @MainActor
  func reflectsExternalStatusChanges() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let loginManager = InMemoryLaunchAtLoginManager(status: .notRegistered)
    var changeCount = 0

    let vm = GeneralSettingsViewModel(configStore: store, launchAtLoginManager: loginManager) { _ in
      changeCount += 1
    }

    #expect(vm.launchAtLogin == false)

    // User enables RepoRadar in System Settings -> Login Items:
    loginManager.status = .enabled
    vm.refreshLaunchAtLoginStatus()

    #expect(vm.launchAtLogin == true)
    #expect(vm.launchAtLoginStatus == .enabled)
    #expect(store.load().launchAtLogin == true)
    #expect(changeCount == 1)

    // User disables RepoRadar in System Settings -> Login Items:
    loginManager.status = .notRegistered
    vm.refreshLaunchAtLoginStatus()

    #expect(vm.launchAtLogin == false)
    #expect(vm.launchAtLoginStatus == .notRegistered)
    #expect(store.load().launchAtLogin == false)
    #expect(changeCount == 2)
  }

  @Test("openSystemSettingsLoginItems calls through to manager")
  @MainActor
  func openSettingsDelegation() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let loginManager = InMemoryLaunchAtLoginManager(status: .requiresApproval)
    let vm = GeneralSettingsViewModel(configStore: store, launchAtLoginManager: loginManager)

    vm.openSystemSettingsLoginItems()
    #expect(loginManager.openSettingsCallCount == 1)
  }

  @Test("Reload updates properties from store and refreshes login item status")
  @MainActor
  func reloadPicksUpExternalChanges() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let loginManager = InMemoryLaunchAtLoginManager(status: .notRegistered)
    let vm = GeneralSettingsViewModel(configStore: store, launchAtLoginManager: loginManager)

    var updated = store.load()
    updated.pollInterval = .fifteenMinutes
    updated.refreshOnWake = false
    updated.showMenuBarCount = false
    updated.ciNotifications = true
    store.save(sanitizing: updated)

    loginManager.status = .enabled
    vm.reload()

    #expect(vm.pollInterval == .fifteenMinutes)
    #expect(vm.refreshOnWake == false)
    #expect(vm.launchAtLogin == true)
    #expect(vm.showMenuBarCount == false)
    #expect(vm.ciNotifications == true)
  }

  @Test("Toggling ciNotifications requests authorization on notificationManager")
  @MainActor
  func togglingCINotificationsRequestsAuthorization() async throws {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let loginManager = InMemoryLaunchAtLoginManager(status: .notRegistered)
    let mockNotifications = MockCINotificationManager(authorizationResult: true)

    let vm = GeneralSettingsViewModel(
      configStore: store,
      launchAtLoginManager: loginManager,
      notificationManager: mockNotifications
    )

    #expect(mockNotifications.authorizationRequestsCount == 0)

    vm.ciNotifications = true

    for _ in 0..<20 {
      if mockNotifications.authorizationRequestsCount > 0 { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(mockNotifications.authorizationRequestsCount == 1)
    #expect(store.load().ciNotifications == true)

    vm.ciNotifications = false
    #expect(mockNotifications.authorizationRequestsCount == 1)
    #expect(store.load().ciNotifications == false)
    #expect(vm.isNotificationPermissionDenied == false)
  }

  @Test("When notification authorization is denied, toggling on publishes denied state and keeps toggle on")
  @MainActor
  func deniedNotificationAuthorizationPublishesDeniedState() async throws {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let loginManager = InMemoryLaunchAtLoginManager(status: .notRegistered)
    let mockNotifications = MockCINotificationManager(
      status: .denied,
      authorizationResult: false
    )

    let vm = GeneralSettingsViewModel(
      configStore: store,
      launchAtLoginManager: loginManager,
      notificationManager: mockNotifications
    )

    // Wait for initial checkNotificationAuthorization
    for _ in 0..<20 {
      if vm.isNotificationPermissionDenied { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(vm.isNotificationPermissionDenied == true)

    // Toggling on when denied requests authorization and remains denied, keeping toggle on
    vm.ciNotifications = true

    for _ in 0..<20 {
      if mockNotifications.authorizationRequestsCount > 0 { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(mockNotifications.authorizationRequestsCount == 1)
    #expect(vm.ciNotifications == true)
    #expect(vm.isNotificationPermissionDenied == true)
    #expect(store.load().ciNotifications == true)

    // openSystemSettingsNotifications opens system settings
    #expect(mockNotifications.openSettingsCount == 0)
    vm.openSystemSettingsNotifications()
    #expect(mockNotifications.openSettingsCount == 1)
  }

  @Test("When notification authorization is authorized, no denied state is published")
  @MainActor
  func authorizedNotificationPublishesNoDeniedState() async throws {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let loginManager = InMemoryLaunchAtLoginManager(status: .notRegistered)
    let mockNotifications = MockCINotificationManager(
      status: .authorized,
      authorizationResult: true
    )

    let vm = GeneralSettingsViewModel(
      configStore: store,
      launchAtLoginManager: loginManager,
      notificationManager: mockNotifications
    )

    for _ in 0..<10 {
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    #expect(vm.isNotificationPermissionDenied == false)

    vm.ciNotifications = true

    for _ in 0..<20 {
      if mockNotifications.authorizationRequestsCount > 0 { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(mockNotifications.authorizationRequestsCount == 1)
    #expect(vm.ciNotifications == true)
    #expect(vm.isNotificationPermissionDenied == false)
  }
}
