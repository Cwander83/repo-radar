import Foundation
import Combine

/// View model driving the Repositories tab in Settings.
/// Manages watched repositories and stale days threshold in ConfigStore.
@MainActor
public final class RepositoriesSettingsViewModel: ObservableObject {
  public let configStore: ConfigStore
  public var onConfigChange: ((RepoRadarConfig) -> Void)?
  public var onRefreshRequest: (() -> Void)?

  @Published public var watchedRepos: [String] = []
  @Published public var staleDays: Int = 30 {
    didSet {
      guard staleDays != oldValue else { return }
      saveStaleDays()
    }
  }

  @Published public var repositoryAccess: [String: RepositoryAccessItem] = [:]
  @Published public var newRepoInput: String = ""
  @Published public var errorMessage: String?

  public init(
    configStore: ConfigStore,
    snapshot: WidgetSnapshot? = nil,
    onConfigChange: ((RepoRadarConfig) -> Void)? = nil,
    onRefreshRequest: (() -> Void)? = nil
  ) {
    self.configStore = configStore
    self.onConfigChange = onConfigChange
    self.onRefreshRequest = onRefreshRequest

    let config = configStore.load()
    self.watchedRepos = config.watchedRepos
    self.staleDays = config.staleDays

    updateAccess(from: snapshot)
  }

  /// Updates cached repository access statuses from a snapshot.
  public func updateAccess(from snapshot: WidgetSnapshot?) {
    guard let snapshot else { return }
    var map: [String: RepositoryAccessItem] = [:]
    for item in snapshot.repositoryAccess {
      map[item.name.lowercased()] = item
    }
    self.repositoryAccess = map
  }

  /// Number of reachable watched repositories.
  public var reachableCount: Int {
    watchedRepos.filter { repo in
      repositoryAccess[repo.lowercased()]?.hasAccess ?? false
    }.count
  }

  /// Total number of watched repositories.
  public var totalCount: Int {
    watchedRepos.count
  }

  /// Human-readable access status ("OK" or "No access").
  public func statusText(for repo: String) -> String {
    guard let info = repositoryAccess[repo.lowercased()] else {
      return "No access"
    }
    return info.hasAccess ? "OK" : "No access"
  }

  /// Default branch name for a repository if known.
  public func defaultBranch(for repo: String) -> String? {
    repositoryAccess[repo.lowercased()]?.defaultBranch
  }

  /// Whether the authenticated token has access to read the repository.
  public func hasAccess(for repo: String) -> Bool {
    repositoryAccess[repo.lowercased()]?.hasAccess ?? false
  }

  /// Adds a new repository to the watched list.
  public func addRepository() {
    errorMessage = nil
    let trimmed = newRepoInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    do {
      try configStore.addWatchedRepo(trimmed)
      newRepoInput = ""
      reload()
      onConfigChange?(configStore.load())
      onRefreshRequest?()
    } catch let error as RepoValidationError {
      errorMessage = error.description
    } catch let error as ConfigValidationError {
      errorMessage = error.description
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Removes a repository from the watched list.
  public func removeRepository(_ repo: String) {
    errorMessage = nil
    configStore.removeWatchedRepo(repo)
    reload()
    onConfigChange?(configStore.load())
    onRefreshRequest?()
  }

  /// Reloads watched repos and stale threshold from config store.
  public func reload() {
    let config = configStore.load()
    self.watchedRepos = config.watchedRepos
    self.staleDays = config.staleDays
  }

  private func saveStaleDays() {
    var config = configStore.load()
    config.staleDays = max(1, staleDays)
    configStore.save(sanitizing: config)
    onConfigChange?(config)
    onRefreshRequest?()
  }
}
