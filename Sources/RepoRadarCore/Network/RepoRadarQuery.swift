import Foundation

/// GraphQL query constants and request payloads for Repo Radar.
public enum RepoRadarQuery {
  /// Builds the search query string from a list of repository identifiers (e.g. `["owner/repo"]`).
  public static func searchString(for repos: [String]) -> String {
    repos
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .map { repo -> String in
        if repo.lowercased().hasPrefix("repo:") {
          return repo
        }
        return "repo:\(repo)"
      }
      .joined(separator: " ")
  }

  /// Request body payload sent to the GitHub GraphQL endpoint.
  public struct RequestBody: Codable, Sendable {
    public let query: String
    public let variables: [String: String]

    public init(query: String = RepoRadarQuery.query, search: String) {
      self.query = query
      self.variables = ["search": search]
    }
  }

  /// The static GraphQL query covering repos, PRs, review requests, CI checks, and branches.
  public static let query = """
    query RepoRadar($search: String!) {
      viewer {
        login
      }
      rateLimit {
        cost
        limit
        remaining
        resetAt
      }
      search(query: $search, type: REPOSITORY, first: 25) {
        repositoryCount
        nodes {
          ... on Repository {
            nameWithOwner
            url
            isPrivate
            isArchived
            defaultBranchRef {
              name
              target {
                ...CommitStatus
              }
            }
            mainRef: ref(qualifiedName: "refs/heads/main") {
              name
              target {
                ...CommitStatus
              }
            }
            pullRequests(states: OPEN, first: 30, orderBy: { field: UPDATED_AT, direction: DESC }) {
              totalCount
              nodes {
                number
                title
                url
                isDraft
                createdAt
                updatedAt
                headRefName
                reviewDecision
                author {
                  login
                }
                reviewRequests(first: 10) {
                  nodes {
                    requestedReviewer {
                      __typename
                      ... on User {
                        login
                      }
                      ... on Team {
                        slug
                      }
                    }
                  }
                }
                commits(last: 1) {
                  nodes {
                    commit {
                      ...CommitStatus
                    }
                  }
                }
              }
            }
            refs(refPrefix: "refs/heads/", first: 100, orderBy: { field: ALPHABETICAL, direction: ASC }) {
              totalCount
              pageInfo {
                hasNextPage
                endCursor
              }
              nodes {
                name
                branchProtectionRule {
                  id
                }
                associatedPullRequests(states: OPEN, first: 1) {
                  totalCount
                }
                target {
                  ... on Commit {
                    oid
                    committedDate
                  }
                }
              }
            }
          }
        }
      }
    }

    fragment CommitStatus on GitObject {
      ... on Commit {
        oid
        committedDate
        url
        statusCheckRollup {
          state
          contexts(first: 25) {
            totalCount
            nodes {
              __typename
              ... on CheckRun {
                name
                status
                conclusion
                detailsUrl
                startedAt
                completedAt
                checkSuite {
                  workflowRun {
                    workflow {
                      name
                    }
                  }
                }
              }
              ... on StatusContext {
                context
                state
                targetUrl
                createdAt
              }
            }
          }
        }
      }
    }
    """
}
