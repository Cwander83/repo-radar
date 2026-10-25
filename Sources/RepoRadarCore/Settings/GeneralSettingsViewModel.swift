import Foundation
import Combine

/// View model driving the General tab in Settings.
/// Reads and writes user configuration via ConfigStore.
@MainActor
public final class GeneralSettingsViewModel: ObservableObject {
  public let configStore: ConfigStore
  public var onConfigChange: ((RepoRadarConfig) -> Void)?

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
      save()
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
      save()
    }
  }

  public init(
    configStore: ConfigStore,
    onConfigChange: ((RepoRadarConfig) -> Void)? = nil
  ) {
    self.configStore = configStore
    self.onConfigChange = onConfigChange

    let config = configStore.load()
    self.pollInterval = config.pollInterval
    self.refreshOnWake = config.refreshOnWake
    self.launchAtLogin = config.launchAtLogin
    self.showMenuBarCount = config.showMenuBarCount
    self.ciNotifications = config.ciNotifications
  }

  /// Reloads all values from the configuration store.
  public func reload() {
    let config = configStore.load()
    self.pollInterval = config.pollInterval
    self.refreshOnWake = config.refreshOnWake
    self.launchAtLogin = config.launchAtLogin
    self.showMenuBarCount = config.showMenuBarCount
    self.ciNotifications = config.ciNotifications
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
