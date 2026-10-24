import Foundation
import Testing

@testable import RepoRadarCore

struct ClassificationTests {
  private func loadFixture(named name: String) throws -> Data {
    #if SWIFT_PACKAGE
      if let url = Bundle.module.url(
        forResource: name,
        withExtension: "json",
        subdirectory: "Fixtures"
      ) {
        return try Data(contentsOf: url)
      }
      if let url = Bundle.module.url(forResource: name, withExtension: "json") {
        return try Data(contentsOf: url)
      }
    #endif

    let thisFile = URL(fileURLWithPath: #filePath)
    let packageRoot =
      thisFile
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let fallback =
      packageRoot
      .appendingPathComponent("Spikes/GraphQL/fixtures/\(name).json")
    return try Data(contentsOf: fallback)
  }

  @Test("Classifies synthetic edge cases fixture matching expected-synthetic-edge-cases.json")
  func classifiesSyntheticEdgeCases() throws {
    let data = try loadFixture(named: "synthetic-edge-cases")
    let response = try RepoRadarDecoder.decode(from: data)

    let fixedNow = try Date("2026-10-24T12:00:00Z", strategy: .iso8601)
    let report = Classifier.classify(
      response: response,
      viewerLogin: "octo-user",
      staleDays: 30,
      now: fixedNow
    )

    // 1. Failing CI: exactly 4 items expected
    #expect(report.failingCI.count == 4)

    let alphaDevelop = try #require(
      report.failingCI.first {
        $0.repo == "octo-user/alpha" && $0.ref == "develop" && $0.check == "CI / Build & Test"
      }
    )
    #expect(alphaDevelop.kind == .defaultBranch)
    #expect(alphaDevelop.conclusion == "FAILURE")

    let alphaPR12 = try #require(
      report.failingCI.first {
        $0.repo == "octo-user/alpha" && $0.ref == "#12 feat/fetcher" && $0.check == "CI / Lint"
      }
    )
    #expect(alphaPR12.kind == .myPullRequest)
    #expect(alphaPR12.conclusion == "TIMED_OUT")

    let deltaBuild = try #require(
      report.failingCI.first {
        $0.repo == "octo-user/delta" && $0.ref == "main" && $0.check == "CI / Build"
      }
    )
    #expect(deltaBuild.kind == .defaultBranch)
    #expect(deltaBuild.conclusion == "STARTUP_FAILURE")

    let deltaLegacy = try #require(
      report.failingCI.first {
        $0.repo == "octo-user/delta" && $0.ref == "main" && $0.check == "ci/legacy"
      }
    )
    #expect(deltaLegacy.kind == .defaultBranch)
    #expect(deltaLegacy.conclusion == "ERROR")

    // 2. Running CI: exactly 1 item expected
    #expect(report.runningCI.count == 1)
    let running = report.runningCI[0]
    #expect(running.repo == "octo-user/alpha")
    #expect(running.ref == "#12 feat/fetcher")
    #expect(running.check == "CI / Unit tests")
    #expect(running.status == "IN_PROGRESS")
    #expect(running.kind == .myPullRequest)

    // Verify non-failing edge cases:
    // - octo-user/beta only check is CANCELLED -> not in failingCI
    #expect(report.failingCI.allSatisfy { $0.repo != "octo-user/beta" })
    // - octo-user/gamma is empty -> not in failingCI
    #expect(report.failingCI.allSatisfy { $0.repo != "octo-user/gamma" })
    // - octo-user/epsilon rollup is null -> not in failingCI
    #expect(report.failingCI.allSatisfy { $0.repo != "octo-user/epsilon" })
    // - PR #14 review requested from me, but CI scope is only my PRs -> not in CI
    #expect(report.failingCI.allSatisfy { !$0.ref.contains("#14") })
    #expect(report.runningCI.allSatisfy { !$0.ref.contains("#14") })
    // - PR #15 is draft -> not in CI
    #expect(report.failingCI.allSatisfy { !$0.ref.contains("#15") })
    // - PR #17 is dependabot -> not in CI
    #expect(report.failingCI.allSatisfy { !$0.ref.contains("#17") })

    // 3. Pull requests: exactly 2 items expected (#14 review requested first, then #12 mine)
    #expect(report.pullRequests.count == 2)
    #expect(report.pullRequests[0].number == 14)
    #expect(report.pullRequests[0].reason == .reviewRequested)
    #expect(report.pullRequests[1].number == 12)
    #expect(report.pullRequests[1].reason == .mine)

    // Excluded PRs:
    // - PR #15: draft
    // - PR #16: review requested from team 'core', not user
    // - PR #17: other author and no review requested
    let prNumbers = report.pullRequests.map(\.number)
    #expect(!prNumbers.contains(15))
    #expect(!prNumbers.contains(16))
    #expect(!prNumbers.contains(17))

    // 4. Stale branches: exactly 2 items expected
    #expect(report.staleBranches.count == 2)
    #expect(report.staleBranches[0].branch == "feat/old-experiment")
    #expect(report.staleBranches[0].ageDays == 84)
    #expect(report.staleBranches[1].branch == "feat/exactly-30-days")
    #expect(report.staleBranches[1].ageDays == 30)

    // Excluded branches:
    let branchNames = report.staleBranches.map(\.branch)
    #expect(!branchNames.contains("release/1.0"))  // protected
    #expect(!branchNames.contains("feat/has-open-pr"))  // has open PR
    #expect(!branchNames.contains("wip/29-days"))  // 29 < 30
    #expect(!branchNames.contains("main"))  // main excluded
    #expect(!branchNames.contains("develop"))  // develop/default excluded
    #expect(!branchNames.contains("feat/fetcher"))  // has open PR
  }

  @Test("Boundary: exactly 30 days is stale, 29 days is not")
  func staleDayBoundary() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let thirtyDaysAgo = now.addingTimeInterval(-30 * 86400)
    let twentyNineDaysAgo = now.addingTimeInterval(-29 * 86400)
    let thirtyOneDaysAgo = now.addingTimeInterval(-31 * 86400)

    let repo = RepositoryNode(
      nameWithOwner: "owner/repo",
      url: URL(string: "https://github.com/owner/repo")!,
      isPrivate: false,
      isArchived: false,
      defaultBranchRef: RefBranch(name: "main"),
      mainRef: nil,
      pullRequests: PullRequestConnection(totalCount: 0, nodes: []),
      refs: RefConnection(
        totalCount: 3,
        pageInfo: nil,
        nodes: [
          RefNode(
            name: "feat/30",
            target: CommitTarget(oid: "1", committedDate: thirtyDaysAgo)
          ),
          RefNode(
            name: "feat/29",
            target: CommitTarget(oid: "2", committedDate: twentyNineDaysAgo)
          ),
          RefNode(
            name: "feat/31",
            target: CommitTarget(oid: "3", committedDate: thirtyOneDaysAgo)
          ),
        ]
      )
    )

    let report = Classifier.classify(
      repos: [repo],
      viewerLogin: "owner",
      staleDays: 30,
      now: now
    )

    let staleNames = report.staleBranches.map(\.branch)
    #expect(staleNames.contains("feat/31"))
    #expect(staleNames.contains("feat/30"))
    #expect(!staleNames.contains("feat/29"))
  }

  @Test("Duplicate checks keep the latest run")
  func duplicateChecksLatestWins() {
    let t1 = Date(timeIntervalSince1970: 1_000)
    let t2 = Date(timeIntervalSince1970: 2_000)

    let commitWithFailureFirst = CommitTarget(
      oid: "c1",
      committedDate: t1,
      statusCheckRollup: StatusCheckRollup(
        state: "SUCCESS",
        contexts: StatusCheckRollupContextConnection(
          totalCount: 2,
          nodes: [
            .checkRun(
              CheckRun(
                name: "Test",
                status: "COMPLETED",
                conclusion: "FAILURE",
                startedAt: t1,
                checkSuite: CheckSuite(workflowRun: WorkflowRun(workflow: Workflow(name: "CI")))
              )
            ),
            .checkRun(
              CheckRun(
                name: "Test",
                status: "COMPLETED",
                conclusion: "SUCCESS",
                startedAt: t2,
                checkSuite: CheckSuite(workflowRun: WorkflowRun(workflow: Workflow(name: "CI")))
              )
            ),
          ]
        )
      )
    )

    let repo = RepositoryNode(
      nameWithOwner: "owner/repo",
      url: URL(string: "https://github.com/owner/repo")!,
      isPrivate: false,
      isArchived: false,
      defaultBranchRef: RefBranch(name: "main", target: commitWithFailureFirst),
      pullRequests: PullRequestConnection(totalCount: 0, nodes: []),
      refs: RefConnection(totalCount: 0, pageInfo: nil, nodes: [])
    )

    let report = Classifier.classify(repos: [repo], viewerLogin: "owner")
    // t2 (SUCCESS) beat t1 (FAILURE) -> not failing
    #expect(report.failingCI.isEmpty)
  }

  @Test("Cancelled-only rollup is ignored")
  func cancelledOnlyIgnored() {
    let commit = CommitTarget(
      oid: "c1",
      committedDate: Date(),
      statusCheckRollup: StatusCheckRollup(
        state: "FAILURE",
        contexts: StatusCheckRollupContextConnection(
          totalCount: 1,
          nodes: [
            .checkRun(
              CheckRun(
                name: "deploy",
                status: "COMPLETED",
                conclusion: "CANCELLED"
              )
            )
          ]
        )
      )
    )

    let repo = RepositoryNode(
      nameWithOwner: "owner/repo",
      url: URL(string: "https://github.com/owner/repo")!,
      isPrivate: false,
      isArchived: false,
      defaultBranchRef: RefBranch(name: "main", target: commit),
      pullRequests: PullRequestConnection(totalCount: 0, nodes: []),
      refs: RefConnection(totalCount: 0, pageInfo: nil, nodes: [])
    )

    let report = Classifier.classify(repos: [repo], viewerLogin: "owner")
    #expect(report.failingCI.isEmpty)
    #expect(report.runningCI.isEmpty)
  }

  @Test("Action required counts as failing, status context pending counts as running")
  func actionRequiredAndStatusContextPending() {
    let commit = CommitTarget(
      oid: "c1",
      committedDate: Date(),
      statusCheckRollup: StatusCheckRollup(
        state: "PENDING",
        contexts: StatusCheckRollupContextConnection(
          totalCount: 2,
          nodes: [
            .checkRun(
              CheckRun(
                name: "Approval",
                status: "COMPLETED",
                conclusion: "ACTION_REQUIRED"
              )
            ),
            .statusContext(
              StatusContext(
                context: "deployment/preview",
                state: "PENDING"
              )
            ),
          ]
        )
      )
    )

    let repo = RepositoryNode(
      nameWithOwner: "owner/repo",
      url: URL(string: "https://github.com/owner/repo")!,
      isPrivate: false,
      isArchived: false,
      defaultBranchRef: RefBranch(name: "main", target: commit),
      pullRequests: PullRequestConnection(totalCount: 0, nodes: []),
      refs: RefConnection(totalCount: 0, pageInfo: nil, nodes: [])
    )

    let report = Classifier.classify(repos: [repo], viewerLogin: "owner")
    #expect(report.failingCI.count == 1)
    #expect(report.failingCI[0].check == "Approval")
    #expect(report.failingCI[0].conclusion == "ACTION_REQUIRED")

    #expect(report.runningCI.count == 1)
    #expect(report.runningCI[0].check == "deployment/preview")
    #expect(report.runningCI[0].status == "PENDING")
  }

  @Test("Protected branches and branches with open PRs are excluded from stale list")
  func protectedAndOpenPRBranchesNotStale() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let sixtyDaysAgo = now.addingTimeInterval(-60 * 86400)

    let repo = RepositoryNode(
      nameWithOwner: "owner/repo",
      url: URL(string: "https://github.com/owner/repo")!,
      isPrivate: false,
      isArchived: false,
      defaultBranchRef: RefBranch(name: "main"),
      pullRequests: PullRequestConnection(totalCount: 0, nodes: []),
      refs: RefConnection(
        totalCount: 3,
        pageInfo: nil,
        nodes: [
          RefNode(
            name: "release/v1",
            branchProtectionRule: BranchProtectionRule(id: "rule1"),
            associatedPullRequests: AssociatedPullRequests(totalCount: 0),
            target: CommitTarget(oid: "1", committedDate: sixtyDaysAgo)
          ),
          RefNode(
            name: "feat/pr-open",
            branchProtectionRule: nil,
            associatedPullRequests: AssociatedPullRequests(totalCount: 1),
            target: CommitTarget(oid: "2", committedDate: sixtyDaysAgo)
          ),
          RefNode(
            name: "feat/unprotected-no-pr",
            branchProtectionRule: nil,
            associatedPullRequests: AssociatedPullRequests(totalCount: 0),
            target: CommitTarget(oid: "3", committedDate: sixtyDaysAgo)
          ),
        ]
      )
    )

    let report = Classifier.classify(
      repos: [repo],
      viewerLogin: "owner",
      staleDays: 30,
      now: now
    )

    let staleNames = report.staleBranches.map(\.branch)
    #expect(staleNames == ["feat/unprotected-no-pr"])
  }

  @Test("Draft PR failing check is excluded from CI scope")
  func draftPRChecksIgnored() {
    let failingCommit = CommitTarget(
      oid: "pr-head",
      committedDate: Date(),
      statusCheckRollup: StatusCheckRollup(
        state: "FAILURE",
        contexts: StatusCheckRollupContextConnection(
          totalCount: 1,
          nodes: [
            .checkRun(
              CheckRun(
                name: "CI",
                status: "COMPLETED",
                conclusion: "FAILURE"
              )
            )
          ]
        )
      )
    )

    let draftPR = PullRequestNode(
      number: 99,
      title: "Draft PR",
      url: URL(string: "https://github.com/owner/repo/pull/99")!,
      isDraft: true,
      createdAt: Date(),
      updatedAt: Date(),
      headRefName: "draft-branch",
      author: Actor(login: "owner"),
      reviewRequests: ReviewRequestConnection(nodes: []),
      commits: PullRequestCommitConnection(
        nodes: [PullRequestCommitNode(commit: failingCommit)]
      )
    )

    let repo = RepositoryNode(
      nameWithOwner: "owner/repo",
      url: URL(string: "https://github.com/owner/repo")!,
      isPrivate: false,
      isArchived: false,
      defaultBranchRef: RefBranch(name: "main"),
      pullRequests: PullRequestConnection(totalCount: 1, nodes: [draftPR]),
      refs: RefConnection(totalCount: 0, pageInfo: nil, nodes: [])
    )

    let report = Classifier.classify(repos: [repo], viewerLogin: "owner")
    #expect(report.failingCI.isEmpty)
    #expect(report.pullRequests.isEmpty)
  }

  @Test("Classifies recorded public repository fixture")
  func classifiesRecordedPublicFixture() throws {
    let data = try loadFixture(named: "recorded-public")
    let response = try RepoRadarDecoder.decode(from: data)

    let fixedNow = try Date("2026-10-24T12:00:00Z", strategy: .iso8601)
    let report = Classifier.classify(
      response: response,
      viewerLogin: "Cwander83",
      staleDays: 30,
      now: fixedNow
    )

    // workout-tracker has 2 stale branches: frontend-001 (2021) and cursor session (August 2026)
    let staleBranches = report.staleBranches.filter { $0.repo == "Cwander83/workout-tracker" }
    #expect(staleBranches.count == 2)
    let staleNames = staleBranches.map(\.branch)
    #expect(staleNames.contains("frontend-001"))
    #expect(staleNames.contains("cursor/site-nav-history-session-4cb2"))

    let frontend001 = try #require(staleBranches.first { $0.branch == "frontend-001" })
    #expect(frontend001.ageDays > 1000)

    // Empty repository produces 0 items
    #expect(!report.failingCI.contains { $0.repo == "Cwander83/seo_reader" })
    #expect(!report.pullRequests.contains { $0.repo == "Cwander83/seo_reader" })
    #expect(!report.staleBranches.contains { $0.repo == "Cwander83/seo_reader" })
  }
}
