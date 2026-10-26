import Foundation
import Combine
#if os(macOS)
import AppKit
#endif

/// View model driving the General tab in Settings.
/// Reads and writes user configuration via ConfigStore and manages login item state via LaunchAtLoginManaging.
@MainActor
public final class GeneralSettingsViewModel: ObservableObject {
  public let configStore: ConfigStore
  public let launchAtLoginManager: any LaunchAtLoginManaging
  public let notificationManager: any CINotificationManaging
  public var onConfigChange: ((RepoRadarConfig) -> Void)?

  private var cancellables = Set<AnyCancellable>()
  private var isSyncingLaunchAtLogin = false

  @Published public var pollInterval: PollInterval {
    didSet {
      guard pollInterval != oldValue else { return }
      save()
    }
  }

  @Published public var refreshOnWake: Bool {
    didSet {
      guard refreshOnWake != oldValue else { return }
      save()
    }
  }

  @Published public var launchAtLogin: Bool {
    didSet {
      guard launchAtLogin != oldValue else { return }
      if isSyncingLaunchAtLogin { return }
      handleLaunchAtLoginChange(to: launchAtLogin)
    }
  }

  @Published public var showMenuBarCount: Bool {
    didSet {
      guard showMenuBarCount != oldValue else { return }
      save()
    }
  }

  @Published public var ciNotifications: Bool {
    didSet {
      guard ciNotifications != oldValue else { return }
      if ciNotifications {
        Task { [notificationManager] in
          await notificationManager.requestAuthorization()
        }
      }
      save()
    }
  }

  @Published public var launchAtLoginStatus: LaunchAtLoginStatus
  @Published public var launchAtLoginError: String?

  public init(
    configStore: ConfigStore,
    launchAtLoginManager: any LaunchAtLoginManaging = AppServiceLaunchAtLoginManager(),
    notificationManager: any CINotificationManaging = SystemCINotificationManager(),
    onConfigChange: ((RepoRadarConfig) -> Void)? = nil
  ) {
    self.configStore = configStore
    self.launchAtLoginManager = launchAtLoginManager
    self.notificationManager = notificationManager
    self.onConfigChange = onConfigChange

    let config = configStore.load()
    self.pollInterval = config.pollInterval
    self.refreshOnWake = config.refreshOnWake
    self.showMenuBarCount = config.showMenuBarCount
    self.ciNotifications = config.ciNotifications

    let systemStatus = launchAtLoginManager.status
    self.launchAtLoginStatus = systemStatus

    let initialLaunchAtLogin: Bool
    switch systemStatus {
    case .notFound:
      initialLaunchAtLogin = config.launchAtLogin
    case .enabled, .requiresApproval, .notRegistered:
      initialLaunchAtLogin = systemStatus.isOn
    }
    self.launchAtLogin = initialLaunchAtLogin

    if initialLaunchAtLogin != config.launchAtLogin && systemStatus != .notFound {
      var updated = config
      updated.launchAtLogin = initialLaunchAtLogin
      configStore.save(sanitizing: updated)
      onConfigChange?(updated)
    }

    #if os(macOS)
    NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.refreshLaunchAtLoginStatus()
      }
      .store(in: &cancellables)
    #endif
  }

  /// Re-checks system login item status and updates view model and config store if changed.
  public func refreshLaunchAtLoginStatus() {
    let systemStatus = launchAtLoginManager.status
    launchAtLoginStatus = systemStatus
    guard systemStatus != .notFound else { return }

    let systemEnabled = systemStatus.isOn
    if launchAtLogin != systemEnabled {
      isSyncingLaunchAtLogin = true
      launchAtLogin = systemEnabled
      isSyncingLaunchAtLogin = false
      save()
    }
  }

  /// Opens macOS System Settings -> General -> Login Items.
  public func openSystemSettingsLoginItems() {
    launchAtLoginManager.openSystemSettingsLoginItems()
  }

  /// Reloads all values from the configuration store and checks system login item status.
  public func reload() {
    let config = configStore.load()
    self.pollInterval = config.pollInterval
    self.refreshOnWake = config.refreshOnWake
    self.showMenuBarCount = config.showMenuBarCount
    self.ciNotifications = config.ciNotifications
    refreshLaunchAtLoginStatus()
  }

  private func handleLaunchAtLoginChange(to enabled: Bool) {
    launchAtLoginError = nil
    do {
      try launchAtLoginManager.setEnabled(enabled)
      launchAtLoginStatus = launchAtLoginManager.status
      save()
    } catch {
      isSyncingLaunchAtLogin = true
      launchAtLogin = launchAtLoginManager.status.isOn
      launchAtLoginStatus = launchAtLoginManager.status
      isSyncingLaunchAtLogin = false
      launchAtLoginError = "Failed to update launch at login: \(error.localizedDescription)"
    }
  }

  private func save() {
    var config = configStore.load()
    config.pollInterval = pollInterval
    config.refreshOnWake = refreshOnWake
    config.launchAtLogin = launchAtLogin
    config.showMenuBarCount = showMenuBarCount
    config.ciNotifications = ciNotifications
    configStore.save(sanitizing: config)
    onConfigChange?(config)
  }
}
