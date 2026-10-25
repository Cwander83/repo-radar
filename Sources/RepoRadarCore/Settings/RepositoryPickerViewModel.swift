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
    selectedRepos.count
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

  /// Checks whether a repository is currently selected.
  public func isSelected(_ repo: String) -> Bool {
    selectedRepos.contains(repo)
  }

  /// Whether a repository checkbox can be clicked (true if already selected or below cap).
  public func canToggle(_ repo: String) -> Bool {
    isSelected(repo) || canSelectMore
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

  /// Toggles selection of a repository, enforcing the 25-repo cap.
  public func toggleSelection(_ repo: String) {
    if selectedRepos.contains(repo) {
      selectedRepos.remove(repo)
    } else if canSelectMore {
      selectedRepos.insert(repo)
    }
  }

  /// Selects the 25 most recently pushed repositories from the visible list.
  public func selectAll() {
    let candidates = visibleRepositories
    let top25 = candidates.prefix(maxSelection)
    self.selectedRepos = Set(top25.map(\.nameWithOwner))
  }

  /// Deselects all repositories.
  public func selectNone() {
    selectedRepos.removeAll()
  }

  /// Saves the selection, preserving existing order for previously watched repos and appending new selections.
  public func save() {
    var ordered: [String] = []

    // 1. Existing watched repos that remain selected
    for repo in initialWatchedRepos where selectedRepos.contains(repo) {
      ordered.append(repo)
    }

    // 2. Newly selected repos in order of recent pushes (from allRepositories)
    for repo in allRepositories where selectedRepos.contains(repo.nameWithOwner) && !ordered.contains(repo.nameWithOwner) {
      ordered.append(repo.nameWithOwner)
    }

    // 3. Fallback for any selected repo not in allRepositories (e.g. manually typed)
    for repo in selectedRepos where !ordered.contains(repo) {
      ordered.append(repo)
    }

    let finalSelection = Array(ordered.prefix(maxSelection))
    onSave?(finalSelection)
  }

  private func mapRepoRadarError(_ error: RepoRadarError) {
    switch error {
    case .tokenUnauthorized(let detail):
      let lower = detail.lowercased()
      if lower.contains("expired") {
        errorMessage = "Token expired on GitHub. Please update your token in Settings → GitHub."
      } else {
        errorMessage = "GitHub authentication failed: \(detail)"
      }
    case .rateLimited(let resetAt):
      if let resetAt {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        errorMessage = "GitHub API rate limit exceeded. Resets at \(formatter.string(from: resetAt))."
      } else {
        errorMessage = "GitHub API rate limit exceeded. Please try again later."
      }
    case .offline(let detail):
      errorMessage = "Network offline: \(detail)"
    case .serverError(let code, let detail):
      errorMessage = "GitHub server error (\(code)): \(detail)"
    default:
      errorMessage = error.localizedDescription
    }
  }
}
