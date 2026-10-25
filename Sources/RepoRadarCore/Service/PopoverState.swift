import Foundation

/// Represents the high-level presentation states of the RepoRadar popover.
public enum PopoverState: String, Codable, Sendable, Equatable, CaseIterable {
  /// Repositories have active CI failures.
  case issues

  /// All watched repositories have passing CI checks.
  case clear

  /// Authentication token was rejected by GitHub (expired, missing, or unauthorized).
  case token

  /// Network is unreachable or GitHub returned a server error; showing cached snapshot data if available.
  case offline

  /// Local snapshot problem (corrupted file, unsupported version).
  case error

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
    case .tokenError:
      return .token

    // A GitHub server error is transient, so it shows like Offline with the last data
    // kept (CHR-101). The banner reads the snapshot status to say which one happened.
    case .offline, .serverError:
      return .offline

    case .corrupt, .unsupportedVersion:
      return .error

    case .missing:
      return .clear

    case .ok, .rateLimited:
      return snapshot.failingCI.isEmpty ? .clear : .issues
    }
  }
}
