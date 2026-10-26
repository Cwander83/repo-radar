import AppIntents
import Foundation

/// Available sections for filtering the widget display.
public enum WidgetSectionChoice: String, AppEnum, Sendable, CaseIterable {
  case all
  case failingCI
  case pullRequests
  case staleBranches

  public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Section"

  public static let caseDisplayRepresentations: [WidgetSectionChoice: DisplayRepresentation] = [
    .all: "All",
    .failingCI: "Failing CI",
    .pullRequests: "Pull Requests",
    .staleBranches: "Stale Branches"
  ]

  public var displayName: String {
    switch self {
    case .all: return "All"
    case .failingCI: return "Failing CI"
    case .pullRequests: return "Pull Requests"
    case .staleBranches: return "Stale Branches"
    }
  }

  public var iconName: String {
    switch self {
    case .all: return AppSymbol.app
    case .failingCI: return "xmark.circle.fill"
    case .pullRequests: return "arrow.triangle.pull"
    case .staleBranches: return "arrow.triangle.branch"
    }
  }
}

extension WidgetSnapshot {
  /// Returns a copy of the snapshot filtered by the given section choice and optional repository.
  public func filtered(
    section: WidgetSectionChoice = .all,
    repository: String? = nil
  ) -> WidgetSnapshot {
    let targetRepo: String? = {
      guard let repository, !repository.isEmpty, repository.lowercased() != "all" else {
        return nil
      }
      return repository.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }()

    // Filter by repository first (case-insensitive)
    let repoFailing = targetRepo == nil ? failingCI : failingCI.filter {
      $0.repo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == targetRepo
    }
    let repoRunning = targetRepo == nil ? runningCI : runningCI.filter {
      $0.repo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == targetRepo
    }
    let repoPRs = targetRepo == nil ? pullRequests : pullRequests.filter {
      $0.repo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == targetRepo
    }
    let repoStale = targetRepo == nil ? staleBranches : staleBranches.filter {
      $0.repo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == targetRepo
    }
    let repoAccess = targetRepo == nil ? repositoryAccess : repositoryAccess.filter {
      $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == targetRepo
    }

    // Filter by section
    let finalFailing: [FailingCIItem]
    let finalRunning: [RunningCIItem]
    let finalPRs: [ClassifiedPullRequest]
    let finalStale: [StaleBranchItem]

    switch section {
    case .all:
      finalFailing = repoFailing
      finalRunning = repoRunning
      finalPRs = repoPRs
      finalStale = repoStale

    case .failingCI:
      finalFailing = repoFailing
      finalRunning = repoRunning
      finalPRs = []
      finalStale = []

    case .pullRequests:
      finalFailing = []
      finalRunning = []
      finalPRs = repoPRs
      finalStale = []

    case .staleBranches:
      finalFailing = []
      finalRunning = []
      finalPRs = []
      finalStale = repoStale
    }

    return WidgetSnapshot(
      schemaVersion: schemaVersion,
      updatedAt: updatedAt,
      status: status,
      failingCI: finalFailing,
      runningCI: finalRunning,
      pullRequests: finalPRs,
      staleBranches: finalStale,
      repositoryAccess: repoAccess,
      rateLimit: rateLimit
    )
  }
}
