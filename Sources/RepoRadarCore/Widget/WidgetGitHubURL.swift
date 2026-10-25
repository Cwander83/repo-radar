import Foundation

/// Resolves target GitHub URLs for widget items and layouts.
public enum WidgetGitHubURL {
  /// Base GitHub URL string.
  public static let baseGitHubURL = "https://github.com"

  /// Returns the target GitHub URL for a failing CI item, falling back to repository actions page if check run URL is missing.
  public static func url(for item: FailingCIItem) -> URL {
    if let url = item.url {
      return url
    }
    return URL(string: "\(baseGitHubURL)/\(item.repo)/actions")
      ?? URL(string: baseGitHubURL)!
  }

  /// Returns the target GitHub URL for a running CI item, falling back to repository actions page if check run URL is missing.
  public static func url(for item: RunningCIItem) -> URL {
    if let url = item.url {
      return url
    }
    return URL(string: "\(baseGitHubURL)/\(item.repo)/actions")
      ?? URL(string: baseGitHubURL)!
  }

  /// Returns the target GitHub URL for a pull request.
  public static func url(for pr: ClassifiedPullRequest) -> URL {
    pr.url
  }

  /// Returns the target GitHub URL for a stale branch, encoding branch name if necessary.
  public static func url(for branch: StaleBranchItem) -> URL {
    let encodedBranch =
      branch.branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch.branch
    return URL(string: "\(baseGitHubURL)/\(branch.repo)/tree/\(encodedBranch)")
      ?? URL(string: "\(baseGitHubURL)/\(branch.repo)")
      ?? URL(string: baseGitHubURL)!
  }

  /// Returns the target GitHub URL for a display item.
  public static func url(for item: WidgetDisplayItem) -> URL? {
    item.url
  }

  /// Returns the target GitHub URL for a small widget based on the active snapshot and configuration.
  public static func smallWidgetURL(
    snapshot: WidgetSnapshot?,
    section: WidgetSectionChoice = .all,
    repositoryFilter: String? = nil
  ) -> URL? {
    // 1. If active prioritized items exist, link to the top item's page
    if let topItem = snapshot?.prioritizedWidgetItems().first, let url = topItem.url {
      return url
    }

    // 2. If filtered to a specific repository
    if let repo = repositoryFilter, !repo.isEmpty, repo.lowercased() != "all" {
      switch section {
      case .all:
        return URL(string: "\(baseGitHubURL)/\(repo)")
      case .failingCI:
        return URL(string: "\(baseGitHubURL)/\(repo)/actions")
      case .pullRequests:
        return URL(string: "\(baseGitHubURL)/\(repo)/pulls")
      case .staleBranches:
        return URL(string: "\(baseGitHubURL)/\(repo)/branches")
      }
    }

    // 3. Section without a repository filter
    switch section {
    case .all:
      return URL(string: baseGitHubURL)
    case .failingCI:
      return URL(string: "\(baseGitHubURL)/notifications")
    case .pullRequests:
      return URL(string: "\(baseGitHubURL)/pulls")
    case .staleBranches:
      return URL(string: baseGitHubURL)
    }
  }
}
