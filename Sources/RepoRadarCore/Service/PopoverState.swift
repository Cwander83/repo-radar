import Foundation

/// Represents the high-level presentation states of the RepoRadar popover.
public enum PopoverState: String, Codable, Sendable, Equatable, CaseIterable {
  /// Repositories have active CI failures or running checks.
  case issues

  /// All watched repositories have passing CI checks.
  case clear

  /// Authentication token is missing, expired, or invalid.
  case token

  /// Network is unreachable; showing cached snapshot data if available.
  case offline

  /// First run experience before a token or watched repositories are configured.
  case setup

  /// Computes the active popover state from token availability, watched repositories, and snapshot data.
  public static func current(
    hasToken: Bool,
    watchedRepos: [String],
    snapshot: WidgetSnapshot?
  ) -> PopoverState {
    guard hasToken && !watchedRepos.isEmpty else {
      return .setup
    }

    guard let snapshot else {
      return .clear
    }

    switch snapshot.status {
    case .tokenError, .corrupt, .unsupportedVersion, .serverError:
      return .token

    case .offline:
      return .offline

    case .missing:
      return .clear

    case .ok, .rateLimited:
      return snapshot.failingCI.isEmpty ? .clear : .issues
    }
  }
}
