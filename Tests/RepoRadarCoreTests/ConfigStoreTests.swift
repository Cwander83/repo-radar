import Foundation
import Testing

@testable import RepoRadarCore

struct ConfigStoreTests {
  private func makeTestDefaults() -> (UserDefaults, String) {
    let suiteName = "test-reporadar-config-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (defaults, suiteName)
  }

  @Test("Default configuration values match spec")
  func defaultConfigValuesMatchSpec() {
    let config = RepoRadarConfig.default

    #expect(config.watchedRepos == [])
    #expect(config.pollInterval == .fiveMinutes)
    #expect(config.pollInterval.minutes == 5)
    #expect(config.pollInterval.timeInterval == 300)
    #expect(config.staleDays == 30)
    #expect(config.refreshOnWake == true)
    #expect(config.launchAtLogin == false)
    #expect(config.showMenuBarCount == true)
    #expect(config.ciNotifications == false)
  }

  @Test("Empty UserDefaults loads default configuration")
  func emptyUserDefaultsLoadsDefaults() {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let loaded = store.load()

    #expect(loaded == RepoRadarConfig.default)
  }

  @Test("Persistence round-trip preserves all configuration values")
  func persistenceRoundTrip() throws {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)

    let custom = RepoRadarConfig(
      watchedRepos: ["Cwander83/repo-radar", "Cwander83/gravity-bar"],
      pollInterval: .tenMinutes,
      staleDays: 14,
      refreshOnWake: false,
      launchAtLogin: true,
      showMenuBarCount: false,
      ciNotifications: true
    )

    try store.save(custom)

    // Verify raw user defaults keys
    #expect(
      defaults.stringArray(forKey: ConfigStore.Keys.watchedRepos) == [
        "Cwander83/repo-radar", "Cwander83/gravity-bar",
      ])
    #expect(defaults.integer(forKey: ConfigStore.Keys.pollIntervalMinutes) == 10)
    #expect(defaults.integer(forKey: ConfigStore.Keys.staleDays) == 14)
    #expect(defaults.bool(forKey: ConfigStore.Keys.refreshOnWake) == false)
    #expect(defaults.bool(forKey: ConfigStore.Keys.launchAtLogin) == true)
    #expect(defaults.bool(forKey: ConfigStore.Keys.showMenuBarCount) == false)
    #expect(defaults.bool(forKey: ConfigStore.Keys.ciNotifications) == true)

    // Reload from a separate store instance pointing to same defaults
    let store2 = ConfigStore(userDefaults: defaults)
    let reloaded = store2.load()

    #expect(reloaded == custom)
  }

  @Test("Reset to defaults removes keys from UserDefaults")
  func resetToDefaultsClearsKeys() throws {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)
    let custom = RepoRadarConfig(
      watchedRepos: ["Cwander83/repo-radar"],
      pollInterval: .fifteenMinutes,
      staleDays: 45
    )
    try store.save(custom)

    store.resetToDefaults()

    let resetLoaded = store.load()
    #expect(resetLoaded == RepoRadarConfig.default)
    #expect(defaults.object(forKey: ConfigStore.Keys.watchedRepos) == nil)
    #expect(defaults.object(forKey: ConfigStore.Keys.pollIntervalMinutes) == nil)
  }

  @Test("addWatchedRepo and removeWatchedRepo update configuration")
  func addAndRemoveWatchedRepo() throws {
    let (defaults, suite) = makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ConfigStore(userDefaults: defaults)

    try store.addWatchedRepo("Cwander83/repo-radar")
    #expect(store.load().watchedRepos == ["Cwander83/repo-radar"])

    try store.addWatchedRepo("Cwander83/gravity-bar")
    #expect(store.load().watchedRepos == ["Cwander83/repo-radar", "Cwander83/gravity-bar"])

    // Duplicate throws
    #expect(throws: RepoValidationError.duplicate("cwander83/repo-radar")) {
      try store.addWatchedRepo("cwander83/repo-radar")
    }

    // Invalid format throws
    #expect(throws: RepoValidationError.missingSlash("invalidrepo")) {
      try store.addWatchedRepo("invalidrepo")
    }

    // Remove
    store.removeWatchedRepo("Cwander83/repo-radar")
    #expect(store.load().watchedRepos == ["Cwander83/gravity-bar"])
  }

  @Test("Valid repo names pass validation")
  func validRepoNamesPass() throws {
    let valid = [
      "owner/repo",
      "Cwander83/repo-radar",
      "apple/swift-package-manager",
      "user_name/my.cool_repo-123",
    ]

    for item in valid {
      let result = try RepoRadarConfig.validate(repo: item)
      #expect(result == item)
    }

    let listResult = try RepoRadarConfig.validate(repos: valid)
    #expect(listResult == valid)
  }

  @Test("Bad owner/repo formats fail validation with specific errors")
  func badRepoFormatsFailValidation() {
    // Empty
    #expect(throws: RepoValidationError.empty) {
      try RepoRadarConfig.validate(repo: "   ")
    }

    // Missing slash
    #expect(throws: RepoValidationError.missingSlash("just-a-repo")) {
      try RepoRadarConfig.validate(repo: "just-a-repo")
    }

    // Multiple slashes
    #expect(throws: RepoValidationError.multipleSlashes("owner/repo/extra")) {
      try RepoRadarConfig.validate(repo: "owner/repo/extra")
    }

    // Empty owner
    #expect(throws: RepoValidationError.emptyOwner("/repo")) {
      try RepoRadarConfig.validate(repo: "/repo")
    }

    // Empty repo name
    #expect(throws: RepoValidationError.emptyRepo("owner/")) {
      try RepoRadarConfig.validate(repo: "owner/")
    }

    // Invalid characters (spaces, special symbols)
    #expect(throws: RepoValidationError.invalidCharacters("owner/repo with space")) {
      try RepoRadarConfig.validate(repo: "owner/repo with space")
    }

    #expect(throws: RepoValidationError.invalidCharacters("owner@name/repo")) {
      try RepoRadarConfig.validate(repo: "owner@name/repo")
    }
  }

  @Test("Duplicate repositories are detected and rejected")
  func duplicateRepositoriesDetected() {
    let duplicates = [
      "Cwander83/repo-radar",
      "other/repo",
      "cwander83/repo-radar",  // duplicate with different casing
    ]

    #expect(throws: RepoValidationError.duplicate("cwander83/repo-radar")) {
      try RepoRadarConfig.validate(repos: duplicates)
    }

    var config = RepoRadarConfig.default
    config.watchedRepos = duplicates
    #expect(throws: ConfigValidationError.self) {
      try config.validate()
    }
  }

  @Test("Stale days validation rejects values less than 1")
  func staleDaysValidation() {
    var config = RepoRadarConfig.default
    config.staleDays = 0
    #expect(throws: ConfigValidationError.invalidStaleDays(0)) {
      try config.validate()
    }

    config.staleDays = -5
    #expect(throws: ConfigValidationError.invalidStaleDays(-5)) {
      try config.validate()
    }

    config.staleDays = 1
    #expect(throws: Never.self) {
      try config.validate()
    }
  }

  @Test("Sanitized config cleans whitespace, deduplicates repos, and clamps staleDays")
  func sanitizedConfig() {
    let dirty = RepoRadarConfig(
      watchedRepos: [
        "  Cwander83/repo-radar  ",
        "cwander83/repo-radar",  // duplicate
        "Cwander83/gravity-bar",
        "invalid repo with space",  // invalid, will be omitted
      ],
      pollInterval: .tenMinutes,
      staleDays: -10
    )

    let clean = dirty.sanitized()
    #expect(clean.watchedRepos == ["Cwander83/repo-radar", "Cwander83/gravity-bar"])
    #expect(clean.staleDays == 1)
    #expect(clean.pollInterval == .tenMinutes)
  }

  @Test("PollInterval mapping and fallback behavior")
  func pollIntervalMapping() {
    #expect(PollInterval(minutes: 5) == .fiveMinutes)
    #expect(PollInterval(minutes: 10) == .tenMinutes)
    #expect(PollInterval(minutes: 15) == .fifteenMinutes)
    #expect(PollInterval(minutes: 999) == .fiveMinutes)
    #expect(PollInterval(minutes: 0) == .fiveMinutes)

    #expect(PollInterval.fiveMinutes < PollInterval.tenMinutes)
    #expect(PollInterval.tenMinutes < PollInterval.fifteenMinutes)
  }
}
