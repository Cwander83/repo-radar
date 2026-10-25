import Foundation
import Combine

/// Access status of a watched repository.
public enum RepoAccessStatus: String, Equatable, Sendable {
  case ok = "OK"
  case noAccess = "No access"
  case checking = "Checking…"

  public var displayText: String {
    rawValue
  }
}

/// View model driving the Repositories tab in Settings.
/// Manages watched repositories and stale days threshold in ConfigStore.
@MainActor
public final class RepositoriesSettingsViewModel: ObservableObject {
  public let configStore: ConfigStore
  public var onConfigChange: ((RepoRadarConfig) -> Void)?
  public var onRefreshRequest: (() -> Void)?

  private var cancellables = Set<AnyCancellable>()

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
    snapshotPublisher: AnyPublisher<WidgetSnapshot?, Never>? = nil,
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

    if let snapshotPublisher {
      snapshotPublisher
        .sink { [weak self] newSnapshot in
          if Thread.isMainThread {
            self?.updateAccess(from: newSnapshot)
          } else {
            Task { @MainActor [weak self] in
              self?.updateAccess(from: newSnapshot)
            }
          }
        }
        .store(in: &cancellables)
    }
  }

  public convenience init(
    configStore: ConfigStore,
    scheduler: RefreshScheduler?,
    onConfigChange: ((RepoRadarConfig) -> Void)? = nil,
    onRefreshRequest: (() -> Void)? = nil
  ) {
    self.init(
      configStore: configStore,
      snapshot: scheduler?.latestSnapshot,
      snapshotPublisher: scheduler?.$latestSnapshot.eraseToAnyPublisher(),
      onConfigChange: onConfigChange,
      onRefreshRequest: onRefreshRequest
    )
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

  /// Number of confirmed reachable watched repositories.
  public var reachableCount: Int {
    watchedRepos.filter { repo in
      repositoryAccess[repo.lowercased()]?.hasAccess == true
    }.count
  }

  /// Total number of watched repositories.
  public var totalCount: Int {
    watchedRepos.count
  }

  /// Access status for a repository: .ok (accessible), .noAccess (token cannot read), or .checking (unverified / unknown).
  public func accessStatus(for repo: String) -> RepoAccessStatus {
    guard let info = repositoryAccess[repo.lowercased()] else {
      return .checking
    }
    return info.hasAccess ? .ok : .noAccess
  }

  /// Human-readable access status ("OK", "No access", or "Checking…").
  public func statusText(for repo: String) -> String {
    accessStatus(for: repo).displayText
  }

  /// Default branch name for a repository if known.
  public func defaultBranch(for repo: String) -> String? {
    repositoryAccess[repo.lowercased()]?.defaultBranch
  }

  /// Whether the authenticated token has confirmed access to read the repository.
  /// Returns nil if access has not yet been verified.
  public func hasAccess(for repo: String) -> Bool? {
    repositoryAccess[repo.lowercased()]?.hasAccess
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
