import Foundation
import Testing
@testable import RepoRadarCore

@Suite("PopoverStateTests")
struct PopoverStateTests {

  @Test("PopoverState maps correctly across all conditions")
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

    // Token error status -> token
    let tokenSnapshot = WidgetSnapshot(
      updatedAt: Date(),
      status: .tokenError(detail: "expired"),
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
      status: .offline(),
      failingCI: []
    )
    #expect(
      PopoverState.current(
        hasToken: true,
        watchedRepos: ["owner/repo"],
        snapshot: offlineSnapshot
      ) == .offline
    )

    // OK status with 0 failures -> clear
    let clearSnapshot = WidgetSnapshot(
      updatedAt: Date(),
      status: .ok,
      failingCI: []
    )
    #expect(
      PopoverState.current(
        hasToken: true,
        watchedRepos: ["owner/repo"],
        snapshot: clearSnapshot
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
  }
}
