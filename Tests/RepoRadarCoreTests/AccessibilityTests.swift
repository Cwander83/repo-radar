import Foundation
import Testing

@testable import RepoRadarCore

@Suite("Accessibility & Contrast Tests")
struct AccessibilityTests {

  // MARK: - CHR-73 / CHR-92 Contrast Verification (>= 4.5:1)

  @Test("All colored text tokens meet WCAG AA 4.5:1 contrast in Light mode")
  func lightModeTextContrastMeetsWCAGAA() {
    let tokens: [(name: String, text: RepoRadarColors.RGB, tint: RepoRadarColors.RGB)] = [
      ("statusFailText", RepoRadarColors.statusFailTextLight, RepoRadarColors.statusFailIconLight),
      ("statusStaleText", RepoRadarColors.statusStaleTextLight, RepoRadarColors.statusStaleIconLight),
      ("statusPassText", RepoRadarColors.statusPassTextLight, RepoRadarColors.statusPassIconLight),
      ("statusReviewText", RepoRadarColors.statusReviewTextLight, RepoRadarColors.statusReviewIconLight),
      ("statusIndigoText", RepoRadarColors.statusIndigoTextLight, RepoRadarColors.statusIndigoIconLight),
    ]

    for token in tokens {
      let windowRatio = token.text.contrastRatio(against: RepoRadarColors.lightWindowBackground)
      #expect(
        windowRatio >= 4.5,
        "\(token.name) on light window background was \(windowRatio), expected >= 4.5"
      )

      let popoverRatio = token.text.contrastRatio(against: RepoRadarColors.lightPopoverBackground)
      #expect(
        popoverRatio >= 4.5,
        "\(token.name) on light popover background was \(popoverRatio), expected >= 4.5"
      )

      // Tinted chip / banner background (up to 16% alpha over light surfaces)
      let chipOnWindow = token.tint.composited(alpha: 0.16, over: RepoRadarColors.lightWindowBackground)
      let chipWindowRatio = token.text.contrastRatio(against: chipOnWindow)
      #expect(
        chipWindowRatio >= 4.5,
        "\(token.name) on 16% tinted light window surface was \(chipWindowRatio), expected >= 4.5"
      )

      let chipOnPopover = token.tint.composited(alpha: 0.16, over: RepoRadarColors.lightPopoverBackground)
      let chipPopoverRatio = token.text.contrastRatio(against: chipOnPopover)
      #expect(
        chipPopoverRatio >= 4.5,
        "\(token.name) on 16% tinted light popover surface was \(chipPopoverRatio), expected >= 4.5"
      )
    }
  }

  @Test("All colored text tokens meet WCAG AA 4.5:1 contrast in Dark mode")
  func darkModeTextContrastMeetsWCAGAA() {
    let tokens: [(name: String, text: RepoRadarColors.RGB, tint: RepoRadarColors.RGB)] = [
      ("statusFailText", RepoRadarColors.statusFailTextDark, RepoRadarColors.statusFailIconDark),
      ("statusStaleText", RepoRadarColors.statusStaleTextDark, RepoRadarColors.statusStaleIconDark),
      ("statusPassText", RepoRadarColors.statusPassTextDark, RepoRadarColors.statusPassIconDark),
      ("statusReviewText", RepoRadarColors.statusReviewTextDark, RepoRadarColors.statusReviewIconDark),
      ("statusIndigoText", RepoRadarColors.statusIndigoTextDark, RepoRadarColors.statusIndigoIconDark),
    ]

    for token in tokens {
      let windowRatio = token.text.contrastRatio(against: RepoRadarColors.darkWindowBackground)
      #expect(
        windowRatio >= 4.5,
        "\(token.name) on dark window background was \(windowRatio), expected >= 4.5"
      )

      let popoverRatio = token.text.contrastRatio(against: RepoRadarColors.darkPopoverBackground)
      #expect(
        popoverRatio >= 4.5,
        "\(token.name) on dark popover background was \(popoverRatio), expected >= 4.5"
      )

      // Tinted chip / banner background (up to 16% alpha over dark surfaces)
      let chipOnWindow = token.tint.composited(alpha: 0.16, over: RepoRadarColors.darkWindowBackground)
      let chipWindowRatio = token.text.contrastRatio(against: chipOnWindow)
      #expect(
        chipWindowRatio >= 4.5,
        "\(token.name) on 16% tinted dark window surface was \(chipWindowRatio), expected >= 4.5"
      )

      let chipOnPopover = token.tint.composited(alpha: 0.16, over: RepoRadarColors.darkPopoverBackground)
      let chipPopoverRatio = token.text.contrastRatio(against: chipOnPopover)
      #expect(
        chipPopoverRatio >= 4.5,
        "\(token.name) on 16% tinted dark popover surface was \(chipPopoverRatio), expected >= 4.5"
      )
    }
  }

  // MARK: - VoiceOver Labels

  @Test("FailingCIItem VoiceOver label matches CHR-92 specification")
  func failingCIAccessibilityLabel() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let item = FailingCIItem(
      repo: "Cwander83/gravity-bar",
      ref: "main",
      kind: .defaultBranch,
      check: "Build & Test",
      conclusion: "FAILURE",
      url: URL(string: "https://github.com/Cwander83/gravity-bar/actions/runs/1"),
      completedAt: now.addingTimeInterval(-12 * 60)
    )

    #expect(
      item.accessibilityLabel(now: now)
        == "Failing CI, gravity-bar main, Build and Test, 12 minutes ago"
    )
  }

  @Test("RunningCIItem VoiceOver label reads duration sensibly")
  func runningCIAccessibilityLabel() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let item = RunningCIItem(
      repo: "Cwander83/repo-radar",
      ref: "develop",
      kind: .defaultBranch,
      check: "CI & Lint",
      status: "IN_PROGRESS",
      url: nil,
      startedAt: now.addingTimeInterval(-45)
    )

    #expect(
      item.accessibilityLabel(now: now)
        == "Running CI, repo-radar develop, CI and Lint, running 45 seconds"
    )
  }

  @Test("ClassifiedPullRequest VoiceOver label distinguishes review requested and authored PRs")
  func pullRequestAccessibilityLabel() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let reviewPR = ClassifiedPullRequest(
      repo: "Cwander83/gravity-bar",
      number: 42,
      title: "Add menubar animation",
      url: URL(string: "https://github.com/Cwander83/gravity-bar/pull/42")!,
      headRefName: "feat/menubar-animation",
      reason: .reviewRequested,
      authorLogin: "octocat",
      updatedAt: now.addingTimeInterval(-3 * 3600)
    )
    let myPR = ClassifiedPullRequest(
      repo: "Cwander83/repo-radar",
      number: 18,
      title: "Fix snapshot decoding",
      url: URL(string: "https://github.com/Cwander83/repo-radar/pull/18")!,
      headRefName: "fix/snapshot-decoding",
      reason: .mine,
      authorLogin: "Cwander83",
      updatedAt: now.addingTimeInterval(-2 * 86400)
    )

    #expect(
      reviewPR.accessibilityLabel(now: now)
        == "Review requested pull request, Add menubar animation, gravity-bar #42, 3 hours ago"
    )
    #expect(
      myPR.accessibilityLabel(now: now)
        == "Pull request, Fix snapshot decoding, repo-radar #18, 2 days ago"
    )
  }

  @Test("StaleBranchItem VoiceOver label reads branch, repo, and age in days")
  func staleBranchAccessibilityLabel() {
    let item = StaleBranchItem(
      repo: "Cwander83/repo-radar",
      branch: "feat/old-experiment",
      ageDays: 21,
      lastCommitDate: Date(timeIntervalSince1970: 1_698_000_000),
      lastCommitOid: "abc1234"
    )

    #expect(
      item.accessibilityLabel == "Stale branch, feat/old-experiment, repo-radar, 21 days old"
    )
  }

  @Test("WidgetSnapshot prioritizedWidgetItems populates spoken accessibilityLabel on every row")
  func widgetDisplayItemAccessibilityLabels() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let snapshot = WidgetSnapshot(
      updatedAt: now,
      status: .ok,
      failingCI: [
        FailingCIItem(
          repo: "Cwander83/gravity-bar",
          ref: "main",
          kind: .defaultBranch,
          check: "Build & Test",
          conclusion: "FAILURE",
          url: URL(string: "https://github.com/Cwander83/gravity-bar/actions/runs/1"),
          completedAt: now.addingTimeInterval(-12 * 60)
        )
      ],
      runningCI: [],
      pullRequests: [
        ClassifiedPullRequest(
          repo: "Cwander83/gravity-bar",
          number: 7,
          title: "Improve contrast",
          url: URL(string: "https://github.com/Cwander83/gravity-bar/pull/7")!,
          headRefName: "feat/contrast",
          reason: .reviewRequested,
          authorLogin: "octocat",
          updatedAt: now.addingTimeInterval(-60)
        )
      ],
      staleBranches: [
        StaleBranchItem(
          repo: "Cwander83/gravity-bar",
          branch: "spike/old",
          ageDays: 19,
          lastCommitDate: now.addingTimeInterval(-19 * 86400),
          lastCommitOid: "def5678"
        )
      ],
      repositoryAccess: [
        RepositoryAccessItem(name: "Cwander83/gravity-bar", defaultBranch: "main")
      ]
    )

    let items = snapshot.prioritizedWidgetItems(now: now)
    #expect(items.count == 3)
    #expect(
      items[0].accessibilityLabel
        == "Failing CI, gravity-bar main, Build and Test, 12 minutes ago"
    )
    #expect(
      items[1].accessibilityLabel
        == "Review requested pull request, Improve contrast, gravity-bar #7, 1 minute ago"
    )
    #expect(
      items[2].accessibilityLabel
        == "Stale branch, spike/old, gravity-bar, 19 days old"
    )
  }
}
