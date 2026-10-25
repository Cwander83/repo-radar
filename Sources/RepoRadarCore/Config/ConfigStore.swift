import Foundation

/// Persistence store for RepoRadar user configuration in App Group UserDefaults.
public struct ConfigStore: @unchecked Sendable {
  /// Default App Group suite identifier.
  public static let defaultSuiteName = "7P5RMM8JP7.com.chriswander.reporadar"

  /// Storage keys used in UserDefaults.
  public enum Keys {
    public static let watchedRepos = "reporadar.watchedRepos"
    public static let pollIntervalMinutes = "reporadar.pollIntervalMinutes"
    public static let staleDays = "reporadar.staleDays"
    public static let refreshOnWake = "reporadar.refreshOnWake"
    public static let launchAtLogin = "reporadar.launchAtLogin"
    public static let showMenuBarCount = "reporadar.showMenuBarCount"
    public static let ciNotifications = "reporadar.ciNotifications"
  }

  /// Underlying UserDefaults instance.
  public let userDefaults: UserDefaults

  /// Creates a ConfigStore with a specific UserDefaults instance.
  public init(userDefaults: UserDefaults) {
    self.userDefaults = userDefaults
  }

  /// Creates a ConfigStore with an App Group suite name, or nil if the suite is unavailable.
  public init?(suiteName: String = defaultSuiteName) {
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return nil
    }
    self.userDefaults = defaults
  }

  /// Loads configuration from UserDefaults, falling back to defaults for missing keys.
  public func load() -> RepoRadarConfig {
    let watchedRepos =
      userDefaults.stringArray(forKey: Keys.watchedRepos) ?? RepoRadarConfig.default.watchedRepos

    let pollInterval: PollInterval
    if userDefaults.object(forKey: Keys.pollIntervalMinutes) != nil {
      let minutes = userDefaults.integer(forKey: Keys.pollIntervalMinutes)
      pollInterval = PollInterval(minutes: minutes)
    } else {
      pollInterval = RepoRadarConfig.default.pollInterval
    }

    let staleDays: Int
    if userDefaults.object(forKey: Keys.staleDays) != nil {
      staleDays = max(1, userDefaults.integer(forKey: Keys.staleDays))
    } else {
      staleDays = RepoRadarConfig.default.staleDays
    }

    let refreshOnWake: Bool
    if userDefaults.object(forKey: Keys.refreshOnWake) != nil {
      refreshOnWake = userDefaults.bool(forKey: Keys.refreshOnWake)
    } else {
      refreshOnWake = RepoRadarConfig.default.refreshOnWake
    }

    let launchAtLogin: Bool
    if userDefaults.object(forKey: Keys.launchAtLogin) != nil {
      launchAtLogin = userDefaults.bool(forKey: Keys.launchAtLogin)
    } else {
      launchAtLogin = RepoRadarConfig.default.launchAtLogin
    }

    let showMenuBarCount: Bool
    if userDefaults.object(forKey: Keys.showMenuBarCount) != nil {
      showMenuBarCount = userDefaults.bool(forKey: Keys.showMenuBarCount)
    } else {
      showMenuBarCount = RepoRadarConfig.default.showMenuBarCount
    }

    let ciNotifications: Bool
    if userDefaults.object(forKey: Keys.ciNotifications) != nil {
      ciNotifications = userDefaults.bool(forKey: Keys.ciNotifications)
    } else {
      ciNotifications = RepoRadarConfig.default.ciNotifications
    }

    return RepoRadarConfig(
      watchedRepos: watchedRepos,
      pollInterval: pollInterval,
      staleDays: staleDays,
      refreshOnWake: refreshOnWake,
      launchAtLogin: launchAtLogin,
      showMenuBarCount: showMenuBarCount,
      ciNotifications: ciNotifications
    )
  }

  /// Saves the configuration after validating it, throwing if validation fails.
  public func save(_ config: RepoRadarConfig) throws {
    try config.validate()
    persist(config)
  }

  /// Sanitizes and saves the configuration without throwing.
  public func save(sanitizing config: RepoRadarConfig) {
    persist(config.sanitized())
  }

  /// Clears all RepoRadar configuration keys from storage.
  public func resetToDefaults() {
    userDefaults.removeObject(forKey: Keys.watchedRepos)
    userDefaults.removeObject(forKey: Keys.pollIntervalMinutes)
    userDefaults.removeObject(forKey: Keys.staleDays)
    userDefaults.removeObject(forKey: Keys.refreshOnWake)
    userDefaults.removeObject(forKey: Keys.launchAtLogin)
    userDefaults.removeObject(forKey: Keys.showMenuBarCount)
    userDefaults.removeObject(forKey: Keys.ciNotifications)
  }

  /// Adds a repository to watched repos, throwing if invalid or already present.
  public func addWatchedRepo(_ repo: String) throws {
    let clean = try RepoRadarConfig.validate(repo: repo)
    var config = load()
    let canonical = clean.lowercased()
    if config.watchedRepos.contains(where: { $0.lowercased() == canonical }) {
      throw RepoValidationError.duplicate(clean)
    }
    config.watchedRepos.append(clean)
    try save(config)
  }

  /// Removes a repository from watched repos.
  public func removeWatchedRepo(_ repo: String) {
    let canonical = repo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    var config = load()
    config.watchedRepos.removeAll(where: { $0.lowercased() == canonical })
    persist(config)
  }

  private func persist(_ config: RepoRadarConfig) {
    userDefaults.set(config.watchedRepos, forKey: Keys.watchedRepos)
    userDefaults.set(config.pollInterval.minutes, forKey: Keys.pollIntervalMinutes)
    userDefaults.set(config.staleDays, forKey: Keys.staleDays)
    userDefaults.set(config.refreshOnWake, forKey: Keys.refreshOnWake)
    userDefaults.set(config.launchAtLogin, forKey: Keys.launchAtLogin)
    userDefaults.set(config.showMenuBarCount, forKey: Keys.showMenuBarCount)
    userDefaults.set(config.ciNotifications, forKey: Keys.ciNotifications)
  }
}
