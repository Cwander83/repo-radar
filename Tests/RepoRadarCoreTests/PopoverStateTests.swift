import Foundation
import Testing
@testable import RepoRadarCore

@Suite("PopoverStateTests")
struct PopoverStateTests {

  @Test("PopoverState maps correctly across all conditions and error statuses")
  func testPopoverStateMapping() {
    // Missing token -> setup
    #expect(
      PopoverState.current(
        hasToken: false,
        watchedRepos: ["owner/repo"],
        snapshot: nil
      ) == .setup
    )

    // Empty watched repos -> setup
    #expect(
      PopoverState.current(
        hasToken: true,
        watchedRepos: [],
        snapshot: nil
      ) == .setup
    )

    // First run with token & repos, no snapshot -> clear
    #expect(
      PopoverState.current(
        hasToken: true,
        watchedRepos: ["owner/repo"],
        snapshot: nil
      ) == .clear
    )

    // Missing status -> clear
    let missingSnapshot = WidgetSnapshot(
      updatedAt: Date(),
      status: .missing,
      failingCI: []
    )
    #expect(
      PopoverState.current(
        hasToken: true,
        watchedRepos: ["owner/repo"],
        snapshot: missingSnapshot
      ) == .clear
    )

    // Token error status -> token
    let tokenSnapshot = WidgetSnapshot(
      updatedAt: Date(),
      status: .tokenError(detail: "Bad credentials"),
      failingCI: []
    )
    #expect(
      PopoverState.current(
        hasToken: true,
        watchedRepos: ["owner/repo"],
        snapshot: tokenSnapshot
      ) == .token
    )

    // Offline status -> offline
    let offlineSnapshot = WidgetSnapshot(
      updatedAt: Date(),
      status: .offline(detail: "The Internet connection appears to be offline."),
      failingCI: []
    )
    #expect(
      PopoverState.current(
        hasToken: true,
        watchedRepos: ["owner/repo"],
        snapshot: offlineSnapshot
      ) == .offline
    )

    // Server error status -> error (neutral error banner)
    let serverErrorSnapshot = WidgetSnapshot(
      updatedAt: Date(),
      status: .serverError(detail: "HTTP 502 Bad Gateway"),
      failingCI: []
    )
    #expect(
      PopoverState.current(
        hasToken: true,
        watchedRepos: ["owner/repo"],
        snapshot: serverErrorSnapshot
      ) == .error
    )

    // Corrupt snapshot status -> error
    let corruptSnapshot = WidgetSnapshot(
      updatedAt: Date(),
      status: .corrupt(detail: "Invalid JSON format"),
      failingCI: []
    )
    #expect(
      PopoverState.current(
        hasToken: true,
        watchedRepos: ["owner/repo"],
        snapshot: corruptSnapshot
      ) == .error
    )

    // Unsupported version status -> error
    let unsupportedSnapshot = WidgetSnapshot(
      updatedAt: Date(),
      status: .unsupportedVersion(version: 99),
      failingCI: []
    )
    #expect(
      PopoverState.current(
        hasToken: true,
        watchedRepos: ["owner/repo"],
        snapshot: unsupportedSnapshot
      ) == .error
    )

    // OK status with 0 failures and 0 running -> clear
    let clearSnapshot = WidgetSnapshot(
      updatedAt: Date(),
      status: .ok,
      failingCI: [],
      runningCI: []
    )
    #expect(
      PopoverState.current(
        hasToken: true,
        watchedRepos: ["owner/repo"],
        snapshot: clearSnapshot
      ) == .clear
    )

    // OK status with running checks only (no failing CI) -> clear
    let runningOnlySnapshot = WidgetSnapshot(
      updatedAt: Date(),
      status: .ok,
      failingCI: [],
      runningCI: [
        RunningCIItem(
          repo: "owner/repo",
          ref: "main",
          kind: .defaultBranch,
          check: "Build",
          status: "IN_PROGRESS"
        )
      ]
    )
    #expect(
      PopoverState.current(
        hasToken: true,
        watchedRepos: ["owner/repo"],
        snapshot: runningOnlySnapshot
      ) == .clear
    )

    // OK status with failing CI -> issues
    let failingSnapshot = WidgetSnapshot(
      updatedAt: Date(),
      status: .ok,
      failingCI: [
        FailingCIItem(
          repo: "owner/repo",
          ref: "main",
          kind: .defaultBranch,
          check: "Build",
          conclusion: "FAILURE"
        )
      ]
    )
    #expect(
      PopoverState.current(
        hasToken: true,
        watchedRepos: ["owner/repo"],
        snapshot: failingSnapshot
      ) == .issues
    )

    // Rate limited status with failing CI -> issues
    let rateLimitedFailingSnapshot = WidgetSnapshot(
      updatedAt: Date(),
      status: .rateLimited(),
      failingCI: [
        FailingCIItem(
          repo: "owner/repo",
          ref: "main",
          kind: .defaultBranch,
          check: "Build",
          conclusion: "FAILURE"
        )
      ]
    )
    #expect(
      PopoverState.current(
        hasToken: true,
        watchedRepos: ["owner/repo"],
        snapshot: rateLimitedFailingSnapshot
      ) == .issues
    )

    // Rate limited status with 0 failures -> clear
    let rateLimitedClearSnapshot = WidgetSnapshot(
      updatedAt: Date(),
      status: .rateLimited(),
      failingCI: []
    )
    #expect(
      PopoverState.current(
        hasToken: true,
        watchedRepos: ["owner/repo"],
        snapshot: rateLimitedClearSnapshot
      ) == .clear
    )
  }
}
