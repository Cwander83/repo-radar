import Foundation
import Combine

/// View model driving the repository picker sheet in Settings -> Repositories.
/// Fetches every repository the token can read, manages multi-selection with a 25-repo cap,
/// filtering/search, archived visibility, and saving through ConfigStore.
@MainActor
public final class RepositoryPickerViewModel: ObservableObject {
  public typealias RepositoriesFetcher = @Sendable () async throws -> [ViewerRepositoryNode]

  public let configStore: ConfigStore
  public let tokenStore: any TokenStore
  public let client: GitHubGraphQLClient
  public var fetcher: RepositoriesFetcher?
  public var onSave: (([String]) -> Void)?

  public let initialWatchedRepos: [String]
  public let maxSelection: Int = RepoRadarConfig.maxWatchedRepos

  @Published public var allRepositories: [ViewerRepositoryNode] = []
  @Published public var selectedRepos: Set<String> = []
  @Published public var searchQuery: String = ""
  @Published public var showArchived: Bool = false
  @Published public var isLoading: Bool = false
  @Published public var errorMessage: String? = nil
  @Published public var isZeroRepos: Bool = false

  public init(
    configStore: ConfigStore,
    tokenStore: any TokenStore,
    client: GitHubGraphQLClient = GitHubGraphQLClient(),
    fetcher: RepositoriesFetcher? = nil,
    onSave: (([String]) -> Void)? = nil
  ) {
    self.configStore = configStore
    self.tokenStore = tokenStore
    self.client = client
    self.fetcher = fetcher
    self.onSave = onSave

    let watched = configStore.load().watchedRepos
    self.initialWatchedRepos = watched
    self.selectedRepos = Set(watched)
  }

  /// Number of currently selected repositories.
  public var selectedCount: Int {
    Set(selectedRepos.map { $0.lowercased() }).count
  }

  /// Whether the selection has reached the 25-repository cap.
  public var isAtCap: Bool {
    selectedCount >= maxSelection
  }

  /// Whether more repositories can be selected.
  public var canSelectMore: Bool {
    selectedCount < maxSelection
  }

  /// Explanation displayed when the 25 cap is reached.
  public var capExplanation: String {
    "Maximum \(maxSelection) repositories selected (GitHub API search limit). Uncheck a repository to select another."
  }

  /// Display string for selection counter (e.g. "3 of 25 selected").
  public var selectionCounterText: String {
    "\(selectedCount) of \(maxSelection) selected"
  }

  /// Checks whether a repository is currently selected, case-insensitively.
  public func isSelected(_ repo: String) -> Bool {
    let lower = repo.lowercased()
    return selectedRepos.contains(where: { $0.lowercased() == lower })
  }

  /// Whether a repository checkbox can be clicked (true if already selected or below cap).
  public func canToggle(_ repo: String) -> Bool {
    isSelected(repo) || canSelectMore
  }

  /// Watched repositories not returned by the token listing (e.g. public repos added manually).
  public var manualRepositories: [String] {
    let fetchedKeys = Set(allRepositories.map { $0.nameWithOwner.lowercased() })
    var manual: [String] = []
    for repo in initialWatchedRepos where !fetchedKeys.contains(repo.lowercased()) {
      if !manual.contains(where: { $0.lowercased() == repo.lowercased() }) {
        manual.append(repo)
      }
    }
    for repo in selectedRepos where !fetchedKeys.contains(repo.lowercased()) {
      if !manual.contains(where: { $0.lowercased() == repo.lowercased() }) {
        manual.append(repo)
      }
    }
    return manual
  }

  /// Visible manual repositories matching search query.
  public var visibleManualRepositories: [String] {
    let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    return manualRepositories.filter { repo in
      if !trimmedQuery.isEmpty {
        return repo.localizedCaseInsensitiveContains(trimmedQuery)
      }
      return true
    }
  }

  /// Filtered repositories matching search query and archived toggle.
  public var visibleRepositories: [ViewerRepositoryNode] {
    let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    return allRepositories.filter { repo in
      if !showArchived && repo.isArchived {
        return false
      }
      if !trimmedQuery.isEmpty {
        return repo.nameWithOwner.localizedCaseInsensitiveContains(trimmedQuery)
      }
      return true
    }
  }

  /// Fetches viewer repositories from GitHub using the stored token or custom fetcher.
  public func loadRepositories() async {
    let token: String?
    do {
      token = try tokenStore.read()
    } catch {
      self.errorMessage = "Failed to read GitHub token: \(error.localizedDescription)"
      return
    }

    guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      self.errorMessage = "Add a GitHub token first."
      return
    }

    isLoading = true
    errorMessage = nil
    isZeroRepos = false

    do {
      let repos: [ViewerRepositoryNode]
      if let fetcher {
        repos = try await fetcher()
      } else {
        repos = try await client.fetchViewerRepositories(token: token)
      }

      self.allRepositories = repos
      self.isZeroRepos = repos.isEmpty
    } catch let error as RepoRadarError {
      mapRepoRadarError(error)
    } catch {
      self.errorMessage = error.localizedDescription
    }

    isLoading = false
  }

  /// Toggles selection of a repository, enforcing the 25-repo cap case-insensitively.
  public func toggleSelection(_ repo: String) {
    let canonical = repo.lowercased()
    if let existing = selectedRepos.first(where: { $0.lowercased() == canonical }) {
      selectedRepos.remove(existing)
    } else if canSelectMore {
      selectedRepos.insert(repo)
    }
  }

  /// Selects repositories up to the 25 cap, keeping visible manual repos and filling remaining slots with recently pushed repos.
  public func selectAll() {
    var newSelected: [String] = []

    // 1. Keep visible manual repositories first
    for repo in visibleManualRepositories {
      if newSelected.count == maxSelection { break }
      newSelected.append(repo)
    }

    // 2. Fill remaining slots with visible repositories in order of recent pushes
    for repo in visibleRepositories {
      if newSelected.count == maxSelection { break }
      let canonical = repo.nameWithOwner.lowercased()
      if !newSelected.contains(where: { $0.lowercased() == canonical }) {
        newSelected.append(repo.nameWithOwner)
      }
    }

    self.selectedRepos = Set(newSelected)
  }

  /// Deselects all repositories.
  public func selectNone() {
    selectedRepos.removeAll()
  }

  /// Saves the selection, preserving existing order for previously watched repos and appending new selections.
  public func save() {
    var ordered: [String] = []

    // 1. Existing watched repos that remain selected
    for repo in initialWatchedRepos where isSelected(repo) {
      if let official = allRepositories.first(where: { $0.nameWithOwner.lowercased() == repo.lowercased() })?.nameWithOwner {
        ordered.append(official)
      } else {
        ordered.append(repo)
      }
    }

    // 2. Newly selected repos in order of recent pushes (from allRepositories)
    for repo in allRepositories where isSelected(repo.nameWithOwner) && !ordered.contains(where: { $0.lowercased() == repo.nameWithOwner.lowercased() }) {
      ordered.append(repo.nameWithOwner)
    }

    // 3. Fallback for any selected repo not in allRepositories (e.g. manually typed)
    for repo in selectedRepos where !ordered.contains(where: { $0.lowercased() == repo.lowercased() }) {
      ordered.append(repo)
    }

    let finalSelection = Array(ordered.prefix(maxSelection))
    onSave?(finalSelection)
  }

  private func mapRepoRadarError(_ error: RepoRadarError) {
    switch error {
    case .tokenUnauthorized(let detail) where detail.lowercased().contains("expired"):
      errorMessage = "Token expired on GitHub. Please update your token in Settings → GitHub."
    case .rateLimited(let resetAt) where resetAt != nil:
      let formatter = DateFormatter()
      formatter.timeStyle = .short
      errorMessage = "GitHub API rate limit exceeded. Resets at \(formatter.string(from: resetAt!))."
    default:
      errorMessage = error.localizedDescription
    }
  }
}
