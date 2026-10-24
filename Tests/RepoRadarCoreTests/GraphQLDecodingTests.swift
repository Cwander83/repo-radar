import Foundation
import Testing

@testable import RepoRadarCore

struct GraphQLDecodingTests {
  private func loadFixture(named name: String) throws -> Data {
    #if SWIFT_PACKAGE
      if let url = Bundle.module.url(
        forResource: name, withExtension: "json", subdirectory: "Fixtures")
      {
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

  @Test("Decodes recorded public repository fixture")
  func decodesRecordedPublicFixture() throws {
    let data = try loadFixture(named: "recorded-public")
    let response = try RepoRadarDecoder.decode(from: data)

    let queryData = try #require(response.data)
    #expect(response.errors == nil)
    #expect(queryData.viewer.login == "Cwander83")

    let rateLimit = try #require(queryData.rateLimit)
    #expect(rateLimit.cost == 49)
    #expect(rateLimit.limit == 5000)
    #expect(rateLimit.remaining <= 5000)

    let repos = queryData.search.nodes
    #expect(repos.count == 6)
    #expect(queryData.search.repositoryCount == 6)

    let names = repos.map(\.nameWithOwner)
    #expect(names.contains("Cwander83/repo-radar"))
    #expect(names.contains("Cwander83/gravity-bar"))
    #expect(names.contains("Cwander83/seo_reader"))
    #expect(names.contains("Cwander83/workout-tracker"))

    // Edge case: empty repository with no default branch or main branch
    let emptyRepo = try #require(repos.first { $0.nameWithOwner == "Cwander83/seo_reader" })
    #expect(emptyRepo.defaultBranchRef == nil)
    #expect(emptyRepo.mainRef == nil)
    #expect(emptyRepo.pullRequests.nodes.isEmpty)
    #expect(emptyRepo.refs.nodes.isEmpty)

    // Edge case: repo without CI configured (statusCheckRollup is null)
    let noCIRepo = try #require(repos.first { $0.nameWithOwner == "Cwander83/workout-tracker" })
    let noCIDefaultRef = try #require(noCIRepo.defaultBranchRef)
    let noCITarget = try #require(noCIDefaultRef.target)
    #expect(noCITarget.statusCheckRollup == nil)

    // Edge case: third-party StatusContext (Vercel on ohiostatefootball)
    let osuRepo = try #require(repos.first { $0.nameWithOwner == "Cwander83/ohiostatefootball" })
    let osuTarget = try #require(osuRepo.defaultBranchRef?.target)
    let osuRollup = try #require(osuTarget.statusCheckRollup)
    let contexts = try #require(osuRollup.contexts?.nodes)
    let hasVercelContext = contexts.contains { context in
      if case .statusContext(let ctx) = context {
        return ctx.context == "Vercel"
      }
      return false
    }
    #expect(hasVercelContext)

    // Check GitHub Actions check run on repo-radar
    let repoRadar = try #require(repos.first { $0.nameWithOwner == "Cwander83/repo-radar" })
    let repoRadarTarget = try #require(repoRadar.defaultBranchRef?.target)
    let repoRadarRollup = try #require(repoRadarTarget.statusCheckRollup)
    let rrContexts = try #require(repoRadarRollup.contexts?.nodes)
    let hasBuildAndTest = rrContexts.contains { context in
      if case .checkRun(let run) = context {
        return run.name.contains("Build & Test")
      }
      return false
    }
    #expect(hasBuildAndTest)

    // Branch listing with commit target and committedDate
    let workoutBranches = noCIRepo.refs.nodes
    #expect(!workoutBranches.isEmpty)
    let frontendBranch = try #require(workoutBranches.first { $0.name == "frontend-001" })
    let frontendTarget = try #require(frontendBranch.target)
    #expect(!frontendTarget.oid.isEmpty)
    #expect(frontendTarget.committedDate < Date())
  }

  @Test("Decodes synthetic edge cases fixture")
  func decodesSyntheticEdgeCasesFixture() throws {
    let data = try loadFixture(named: "synthetic-edge-cases")
    let response = try RepoRadarDecoder.decode(from: data)

    let queryData = try #require(response.data)
    #expect(queryData.viewer.login == "octo-user")

    let repos = queryData.search.nodes
    #expect(repos.count == 5)

    // 1. Empty repository (gamma)
    let gamma = try #require(repos.first { $0.nameWithOwner == "octo-user/gamma" })
    #expect(gamma.defaultBranchRef == nil)
    #expect(gamma.mainRef == nil)

    // 2. Missing rollup (epsilon)
    let epsilon = try #require(repos.first { $0.nameWithOwner == "octo-user/epsilon" })
    #expect(epsilon.defaultBranchRef?.target?.statusCheckRollup == nil)
    #expect(epsilon.mainRef?.target?.statusCheckRollup == nil)

    // 3. STARTUP_FAILURE and commit status ERROR (delta)
    let delta = try #require(repos.first { $0.nameWithOwner == "octo-user/delta" })
    let deltaRollup = try #require(delta.defaultBranchRef?.target?.statusCheckRollup)
    #expect(deltaRollup.state == "ERROR")
    let deltaContexts = try #require(deltaRollup.contexts?.nodes)
    #expect(deltaContexts.count == 2)

    var foundStartupFailure = false
    var foundStatusError = false
    for ctx in deltaContexts {
      switch ctx {
      case .checkRun(let run):
        if run.name == "Build" && run.conclusion == "STARTUP_FAILURE" {
          foundStartupFailure = true
          #expect(run.workflowName == "CI")
        }
      case .statusContext(let status):
        if status.context == "ci/legacy" && status.state == "ERROR" {
          foundStatusError = true
        }
      }
    }
    #expect(foundStartupFailure)
    #expect(foundStatusError)

    // 4. Alpha repo: checks, PRs, review requests, branches
    let alpha = try #require(repos.first { $0.nameWithOwner == "octo-user/alpha" })

    // Dependabot check with checkSuite.workflowRun == nil
    let alphaDefaultRollup = try #require(alpha.defaultBranchRef?.target?.statusCheckRollup)
    let alphaDefaultContexts = try #require(alphaDefaultRollup.contexts?.nodes)
    let dependabotCheck = try #require(
      alphaDefaultContexts.compactMap { ctx -> CheckRun? in
        if case .checkRun(let run) = ctx, run.name == ".github/dependabot.yml" {
          return run
        }
        return nil
      }.first)
    #expect(dependabotCheck.status == "COMPLETED")
    #expect(dependabotCheck.conclusion == "SUCCESS")
    #expect(dependabotCheck.workflowName == nil)

    // PR #12: TIMED_OUT and IN_PROGRESS checks
    let pr12 = try #require(alpha.pullRequests.nodes.first { $0.number == 12 })
    #expect(pr12.isDraft == false)
    #expect(pr12.author?.login == "octo-user")
    let pr12HeadCommit = try #require(pr12.headCommit)
    let pr12Rollup = try #require(pr12HeadCommit.statusCheckRollup)
    let pr12Contexts = try #require(pr12Rollup.contexts?.nodes)

    let lintCheck = try #require(
      pr12Contexts.compactMap { ctx -> CheckRun? in
        if case .checkRun(let run) = ctx, run.name == "Lint" { return run }
        return nil
      }.first)
    #expect(lintCheck.conclusion == "TIMED_OUT")

    let unitCheck = try #require(
      pr12Contexts.compactMap { ctx -> CheckRun? in
        if case .checkRun(let run) = ctx, run.name == "Unit tests" { return run }
        return nil
      }.first)
    #expect(unitCheck.status == "IN_PROGRESS")
    #expect(unitCheck.conclusion == nil)

    // Review requests: User vs Team
    let pr14 = try #require(alpha.pullRequests.nodes.first { $0.number == 14 })
    let pr14Reviewer = try #require(pr14.reviewRequests.nodes.first?.requestedReviewer)
    #expect(pr14Reviewer == .user(login: "octo-user"))

    let pr16 = try #require(alpha.pullRequests.nodes.first { $0.number == 16 })
    let pr16Reviewer = try #require(pr16.reviewRequests.nodes.first?.requestedReviewer)
    #expect(pr16Reviewer == .team(slug: "core"))

    // Draft PR
    let pr15 = try #require(alpha.pullRequests.nodes.first { $0.number == 15 })
    #expect(pr15.isDraft == true)

    // Branches: protection rules and associated open PRs
    let alphaBranches = alpha.refs.nodes
    let protectedBranch = try #require(alphaBranches.first { $0.name == "release/1.0" })
    #expect(protectedBranch.branchProtectionRule != nil)

    let branchWithPR = try #require(alphaBranches.first { $0.name == "feat/has-open-pr" })
    #expect(branchWithPR.associatedPullRequests?.totalCount == 1)

    let oldExperiment = try #require(alphaBranches.first { $0.name == "feat/old-experiment" })
    #expect(oldExperiment.branchProtectionRule == nil)
    #expect(oldExperiment.target != nil)

    // Beta repo: CANCELLED check
    let beta = try #require(repos.first { $0.nameWithOwner == "octo-user/beta" })
    let betaRollup = try #require(beta.defaultBranchRef?.target?.statusCheckRollup)
    let betaContext = try #require(betaRollup.contexts?.nodes.first)
    if case .checkRun(let run) = betaContext {
      #expect(run.conclusion == "CANCELLED")
    } else {
      Issue.record("Expected CheckRun for beta")
    }
  }

  @Test("Round-trip encoding and re-decoding preserves synthetic fixture data")
  func roundtripSyntheticFixture() throws {
    let originalData = try loadFixture(named: "synthetic-edge-cases")
    let decoded = try RepoRadarDecoder.decode(from: originalData)

    let encoded = try RepoRadarEncoder.encode(decoded, prettyPrinted: true)
    let reDecoded = try RepoRadarDecoder.decode(from: encoded)

    #expect(decoded == reDecoded)
  }

  @Test("Round-trip encoding and re-decoding preserves recorded public fixture data")
  func roundtripRecordedPublicFixture() throws {
    let originalData = try loadFixture(named: "recorded-public")
    let decoded = try RepoRadarDecoder.decode(from: originalData)

    let encoded = try RepoRadarEncoder.encode(decoded, prettyPrinted: true)
    let reDecoded = try RepoRadarDecoder.decode(from: encoded)

    #expect(decoded == reDecoded)
  }

  @Test("Decodes pagination edges and empty collections")
  func decodesPaginationEdges() throws {
    let json = """
      {
          "data": {
              "viewer": { "login": "test-user" },
              "rateLimit": { "cost": 1, "limit": 5000, "remaining": 4999, "resetAt": "2026-10-24T12:00:00Z" },
              "search": {
                  "repositoryCount": 1,
                  "nodes": [
                      {
                          "nameWithOwner": "test-user/paginated-repo",
                          "url": "https://github.com/test-user/paginated-repo",
                          "isPrivate": false,
                          "isArchived": false,
                          "defaultBranchRef": null,
                          "mainRef": null,
                          "pullRequests": { "totalCount": 0, "nodes": [] },
                          "refs": {
                              "totalCount": 250,
                              "pageInfo": {
                                  "hasNextPage": true,
                                  "endCursor": "cursor-xyz-100"
                              },
                              "nodes": []
                          }
                      }
                  ]
              }
          }
      }
      """.data(using: .utf8)!

    let response = try GraphQLQueryResponse.decode(from: json)
    let repo = try #require(response.data?.search.nodes.first)
    #expect(repo.refs.totalCount == 250)
    let pageInfo = try #require(repo.refs.pageInfo)
    #expect(pageInfo.hasNextPage == true)
    #expect(pageInfo.endCursor == "cursor-xyz-100")
    #expect(repo.refs.nodes.isEmpty)
    #expect(repo.pullRequests.nodes.isEmpty)
  }

  @Test("Decodes GraphQL errors array when returned")
  func decodesGraphQLErrors() throws {
    let json = """
      {
          "errors": [
              {
                  "message": "Field 'badField' doesn't exist on type 'Repository'",
                  "type": "GRAPHQL_VALIDATION_FAILED",
                  "path": ["query", "search", "nodes", "badField"]
              }
          ],
          "data": null
      }
      """.data(using: .utf8)!

    let response = try GraphQLQueryResponse.decode(from: json)
    #expect(response.data == nil)
    let errors = try #require(response.errors)
    #expect(errors.count == 1)
    #expect(errors[0].message.contains("badField"))
    #expect(errors[0].type == "GRAPHQL_VALIDATION_FAILED")
    #expect(errors[0].path == ["query", "search", "nodes", "badField"])
  }

  @Test("Decodes GraphQL error paths containing list indexes alongside partial data")
  func decodesErrorPathWithIndexes() throws {
    let json = """
      {
          "errors": [
              {
                  "message": "Resource not accessible by integration",
                  "type": "FORBIDDEN",
                  "path": ["search", "nodes", 0, "refs"]
              }
          ],
          "data": {
              "viewer": { "login": "test" },
              "rateLimit": null,
              "search": { "repositoryCount": 0, "nodes": [] }
          }
      }
      """.data(using: .utf8)!

    let response = try GraphQLQueryResponse.decode(from: json)
    #expect(response.data != nil)
    let error = try #require(response.errors?.first)
    #expect(error.path == ["search", "nodes", "0", "refs"])
  }

  @Test("Throws DecodingError on invalid JSON or unknown context typename")
  func throwsOnInvalidData() {
    let invalidJSON = "not json".data(using: .utf8)!
    #expect(throws: DecodingError.self) {
      _ = try RepoRadarDecoder.decode(from: invalidJSON)
    }

    let unknownTypenameJSON = """
      {
          "data": {
              "viewer": { "login": "test" },
              "rateLimit": null,
              "search": {
                  "repositoryCount": 1,
                  "nodes": [
                      {
                          "nameWithOwner": "test/repo",
                          "url": "https://github.com/test/repo",
                          "isPrivate": false,
                          "isArchived": false,
                          "defaultBranchRef": {
                              "name": "main",
                              "target": {
                                  "oid": "123",
                                  "committedDate": "2026-10-24T12:00:00Z",
                                  "url": null,
                                  "statusCheckRollup": {
                                      "state": "SUCCESS",
                                      "contexts": {
                                          "totalCount": 1,
                                          "nodes": [
                                              { "__typename": "UnknownContextType" }
                                          ]
                                      }
                                  }
                              }
                          },
                          "mainRef": null,
                          "pullRequests": { "totalCount": 0, "nodes": [] },
                          "refs": { "totalCount": 0, "pageInfo": null, "nodes": [] }
                      }
                  ]
              }
          }
      }
      """.data(using: .utf8)!

    #expect(throws: DecodingError.self) {
      _ = try RepoRadarDecoder.decode(from: unknownTypenameJSON)
    }
  }
}
