import Foundation

/// Represents the visual states of the RepoRadar menu bar item.
public enum MenuBarState: Equatable, Sendable {
  /// All checks passing, normal template icon.
  case clear

  /// Failing CI check runs detected; displays the red count badge if enabled.
  case failing(count: Int)

  /// Warning icon indicating an authentication, system, or configuration error.
  case error

  /// Dimmed template icon indicating offline status.
  case offline

  /// Name of the SF Symbol representing this state.
  public var systemImageName: String {
    switch self {
    case .clear, .failing, .offline:
      return "radar"
    case .error:
      return "exclamationmark.triangle"
    }
  }

  /// Whether the menu bar icon should be dimmed.
  public var isDimmed: Bool {
    switch self {
    case .offline:
      return true
    case .clear, .failing, .error:
      return false
    }
  }

  /// Failing CI count for the badge, or nil if no badge should be shown.
  public var badgeCount: Int? {
    switch self {
    case .failing(let count):
      return count > 0 ? count : nil
    case .clear, .offline, .error:
      return nil
    }
  }

  /// Human-readable VoiceOver accessibility label.
  public var accessibilityLabel: String {
    switch self {
    case .clear:
      return "Repo Radar: All checks passing"
    case .failing(let count):
      return "Repo Radar: \(count) failing check\(count == 1 ? "" : "s")"
    case .offline:
      return "Repo Radar: Offline"
    case .error:
      return "Repo Radar: Attention required"
    }
  }

  /// Computes the current menu bar state from snapshot status, failing CI count, and config preferences.
  public static func current(
    status: SnapshotStatus?,
    failingCICount: Int,
    showMenuBarCount: Bool = true,
    hasToken: Bool = true,
    hasWatchedRepos: Bool = true
  ) -> MenuBarState {
    guard let status else {
      // Scheduler or snapshot store unavailable (e.g. App Group missing)
      return .error
    }

    if !hasToken || !hasWatchedRepos {
      return .error
    }

    switch status {
    case .tokenError, .corrupt, .unsupportedVersion, .serverError:
      return .error

    case .offline:
      return .offline

    case .missing:
      return .clear

    case .ok, .rateLimited:
      if failingCICount > 0 && showMenuBarCount {
        return .failing(count: failingCICount)
      } else {
        return .clear
      }
    }
  }
}
