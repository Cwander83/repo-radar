import Foundation

/// Pure functions classifying GraphQL models into dashboard items.
public enum Classifier {
  /// Classifies a decoded `GraphQLQueryResponse`.
  public static func classify(
    response: GraphQLQueryResponse,
    watchedRepos: [String] = [],
    viewerLogin: String? = nil,
    staleDays: Int = 30,
    now: Date = Date()
  ) -> ClassifiedReport {
    guard let data = response.data else {
      return ClassifiedReport()
    }
    let viewer = viewerLogin ?? data.viewer.login
    return classify(
      repos: data.search.nodes,
      watchedRepos: watchedRepos,
      viewerLogin: viewer,
      staleDays: staleDays,
      now: now
    )
  }

  /// Classifies a list of repositories for a given viewer.
  public static func classify(
    repos: [RepositoryNode],
    watchedRepos: [String] = [],
    viewerLogin: String,
    staleDays: Int = 30,
    now: Date = Date()
  ) -> ClassifiedReport {
    var allFailingCI: [FailingCIItem] = []
    var allRunningCI: [RunningCIItem] = []
    var allPRs: [ClassifiedPullRequest] = []
    var allStaleBranches: [StaleBranchItem] = []

    for repo in repos {
      // 1. CI Scope
      let ciResults = classifyCI(repo: repo, viewerLogin: viewerLogin)
      allFailingCI.append(contentsOf: ciResults.failing)
      allRunningCI.append(contentsOf: ciResults.running)

      // 2. PRs Scope
      let prResults = classifyPullRequests(repo: repo, viewerLogin: viewerLogin)
      allPRs.append(contentsOf: prResults)

      // 3. Stale Branches Scope
      let staleResults = classifyStaleBranches(
        repo: repo,
        staleDays: staleDays,
        now: now
      )
      allStaleBranches.append(contentsOf: staleResults)
    }

    // Sort PRs: review requested first, then mine; newest updated first within group.
    allPRs.sort { pr1, pr2 in
      if pr1.reason != pr2.reason {
        return pr1.reason == .reviewRequested
      }
      return pr1.updatedAt > pr2.updatedAt
    }

    // Sort stale branches: oldest first (highest ageDays).
    allStaleBranches.sort { b1, b2 in
      if b1.ageDays != b2.ageDays {
        return b1.ageDays > b2.ageDays
      }
      return b1.branch < b2.branch
    }

    // Repository access reachability and default branch mapping
    var repoAccessItems: [RepositoryAccessItem] = []
    let nodesByLowercasedName = Dictionary(
      repos.map { ($0.nameWithOwner.lowercased(), $0) },
      uniquingKeysWith: { first, _ in first }
    )

    if !watchedRepos.isEmpty {
      for watched in watchedRepos {
        let key = watched.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let node = nodesByLowercasedName[key] {
          let branch = node.defaultBranchRef?.name ?? node.mainRef?.name
          repoAccessItems.append(
            RepositoryAccessItem(name: node.nameWithOwner, defaultBranch: branch, hasAccess: true))
        } else {
          repoAccessItems.append(
            RepositoryAccessItem(name: watched, defaultBranch: nil, hasAccess: false))
        }
      }
    } else {
      for repo in repos {
        let branch = repo.defaultBranchRef?.name ?? repo.mainRef?.name
        repoAccessItems.append(
          RepositoryAccessItem(name: repo.nameWithOwner, defaultBranch: branch, hasAccess: true))
      }
    }

    return ClassifiedReport(
      failingCI: allFailingCI,
      runningCI: allRunningCI,
      pullRequests: allPRs,
      staleBranches: allStaleBranches,
      repositoryAccess: repoAccessItems
    )
  }

  // MARK: - CI Evaluation

  private struct CIResult {
    let failing: [FailingCIItem]
    let running: [RunningCIItem]
  }

  private static func classifyCI(repo: RepositoryNode, viewerLogin: String) -> CIResult {
    var failing: [FailingCIItem] = []
    var running: [RunningCIItem] = []

    // A. Default branch
    if let defaultRef = repo.defaultBranchRef, let target = defaultRef.target {
      let evaluated = evaluateChecks(
        commit: target,
        repo: repo.nameWithOwner,
        refName: defaultRef.name,
        kind: .defaultBranch
      )
      failing.append(contentsOf: evaluated.failing)
      running.append(contentsOf: evaluated.running)
    }

    // B. Main branch if distinct from default branch
    let defaultBranchName = repo.defaultBranchRef?.name
    let isMainDefault = defaultBranchName == "main" || defaultBranchName == "refs/heads/main"
    if !isMainDefault, let mainRef = repo.mainRef, let target = mainRef.target {
      let evaluated = evaluateChecks(
        commit: target,
        repo: repo.nameWithOwner,
        refName: "main",
        kind: .mainBranch
      )
      failing.append(contentsOf: evaluated.failing)
      running.append(contentsOf: evaluated.running)
    }

    // C. Open, non-draft PRs authored by viewer
    for pr in repo.pullRequests.nodes {
      guard !pr.isDraft else { continue }
      guard pr.author?.login == viewerLogin else { continue }
      guard let headCommit = pr.headCommit else { continue }

      let refName = "#\(pr.number) \(pr.headRefName)"
      let evaluated = evaluateChecks(
        commit: headCommit,
        repo: repo.nameWithOwner,
        refName: refName,
        kind: .myPullRequest
      )
      failing.append(contentsOf: evaluated.failing)
      running.append(contentsOf: evaluated.running)
    }

    return CIResult(failing: failing, running: running)
  }

  private struct EvaluatedCheck {
    let key: String
    let checkName: String
    let timestamp: Date?
    let isFailing: Bool
    let isRunning: Bool
    let conclusion: String?
    let status: String?
    let url: URL?
    let startedAt: Date?
    let completedAt: Date?
  }

  private static func evaluateChecks(
    commit: CommitTarget,
    repo: String,
    refName: String,
    kind: CIRefKind
  ) -> CIResult {
    guard let rollup = commit.statusCheckRollup, let contexts = rollup.contexts else {
      return CIResult(failing: [], running: [])
    }

    var deduplicatedKeys: [String] = []
    var checksByKey: [String: EvaluatedCheck] = [:]

    for node in contexts.nodes {
      let eval: EvaluatedCheck
      switch node {
      case .checkRun(let run):
        let wfName = run.workflowName
        let checkName = (wfName != nil && !wfName!.isEmpty) ? "\(wfName!) / \(run.name)" : run.name
        let key = "checkrun:\(wfName ?? "")/\(run.name)"
        let conclusion = run.conclusion?.uppercased()

        let isFailing: Bool
        if let conc = conclusion {
          switch conc {
          case "FAILURE", "ERROR", "TIMED_OUT", "STARTUP_FAILURE":
            isFailing = true
          default:
            isFailing = false
          }
        } else {
          isFailing = false
        }

        let isRunning: Bool
        if !isFailing && (conclusion == nil || conclusion == "") {
          switch run.status.uppercased() {
          case "QUEUED", "IN_PROGRESS", "WAITING", "PENDING", "REQUESTED":
            isRunning = true
          default:
            isRunning = false
          }
        } else {
          isRunning = false
        }

        eval = EvaluatedCheck(
          key: key,
          checkName: checkName,
          timestamp: run.startedAt ?? run.completedAt,
          isFailing: isFailing,
          isRunning: isRunning,
          conclusion: run.conclusion,
          status: run.status,
          url: run.detailsUrl ?? commit.url,
          startedAt: run.startedAt,
          completedAt: run.completedAt
        )

      case .statusContext(let ctx):
        let key = "status:\(ctx.context)"
        let state = ctx.state.uppercased()

        let isFailing: Bool
        switch state {
        case "FAILURE", "ERROR":
          isFailing = true
        default:
          isFailing = false
        }

        let isRunning: Bool
        switch state {
        case "PENDING", "EXPECTED":
          isRunning = true
        default:
          isRunning = false
        }

        eval = EvaluatedCheck(
          key: key,
          checkName: ctx.context,
          timestamp: ctx.createdAt,
          isFailing: isFailing,
          isRunning: isRunning,
          conclusion: ctx.state,
          status: ctx.state,
          url: ctx.targetUrl ?? commit.url,
          startedAt: ctx.createdAt,
          completedAt: ctx.createdAt
        )
      }

      // Deduplicate: keep the check with the later timestamp.
      if let existing = checksByKey[eval.key] {
        let existingTime = existing.timestamp ?? Date.distantPast
        let newTime = eval.timestamp ?? Date.distantPast
        if newTime >= existingTime {
          checksByKey[eval.key] = eval
        }
      } else {
        deduplicatedKeys.append(eval.key)
        checksByKey[eval.key] = eval
      }
    }

    var failing: [FailingCIItem] = []
    var running: [RunningCIItem] = []

    for key in deduplicatedKeys {
      guard let check = checksByKey[key] else { continue }
      if check.isFailing, let conc = check.conclusion {
        failing.append(
          FailingCIItem(
            repo: repo,
            ref: refName,
            kind: kind,
            check: check.checkName,
            conclusion: conc,
            url: check.url,
            startedAt: check.startedAt,
            completedAt: check.completedAt
          )
        )
      } else if check.isRunning, let stat = check.status {
        running.append(
          RunningCIItem(
            repo: repo,
            ref: refName,
            kind: kind,
            check: check.checkName,
            status: stat,
            url: check.url,
            startedAt: check.startedAt
          )
        )
      }
    }

    return CIResult(failing: failing, running: running)
  }

  // MARK: - Pull Requests Evaluation

  private static func classifyPullRequests(
    repo: RepositoryNode,
    viewerLogin: String
  ) -> [ClassifiedPullRequest] {
    var prs: [ClassifiedPullRequest] = []

    for pr in repo.pullRequests.nodes {
      guard !pr.isDraft else { continue }

      let hasReviewRequest = pr.reviewRequests.nodes.contains { node in
        if case .user(let login) = node.requestedReviewer {
          return login == viewerLogin
        }
        return false
      }

      let reason: PullRequestReason?
      if hasReviewRequest {
        reason = .reviewRequested
      } else if pr.author?.login == viewerLogin {
        reason = .mine
      } else {
        reason = nil
      }

      guard let reason else { continue }

      prs.append(
        ClassifiedPullRequest(
          repo: repo.nameWithOwner,
          number: pr.number,
          title: pr.title,
          url: pr.url,
          headRefName: pr.headRefName,
          reason: reason,
          authorLogin: pr.author?.login,
          updatedAt: pr.updatedAt
        )
      )
    }

    return prs
  }

  // MARK: - Stale Branches Evaluation

  private static func classifyStaleBranches(
    repo: RepositoryNode,
    staleDays: Int,
    now: Date
  ) -> [StaleBranchItem] {
    var stale: [StaleBranchItem] = []
    let defaultBranch = repo.defaultBranchRef?.name

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

    for ref in repo.refs.nodes {
      // Exclude special branches
      guard ref.name != "main" else { continue }
      guard ref.name != "develop" else { continue }
      guard ref.name != defaultBranch else { continue }

      // Exclude protected branches
      guard ref.branchProtectionRule == nil else { continue }

      // Exclude branches with open PRs
      guard (ref.associatedPullRequests?.totalCount ?? 0) == 0 else { continue }

      // Require commit target
      guard let target = ref.target else { continue }

      let ageDays = calendar.dateComponents([.day], from: target.committedDate, to: now).day ?? 0
      guard ageDays >= staleDays else { continue }

      stale.append(
        StaleBranchItem(
          repo: repo.nameWithOwner,
          branch: ref.name,
          ageDays: ageDays,
          lastCommitDate: target.committedDate,
          lastCommitOid: target.oid
        )
      )
    }

    return stale
  }
}
