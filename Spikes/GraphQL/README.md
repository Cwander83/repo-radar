# Spike: GitHub GraphQL query (CHR-65)

One GraphQL request per refresh returns everything Repo Radar shows: open PRs and review requests, CI status on default branches and PR heads, and branches with their last commit date.

## Files

| File | Purpose |
| :-- | :-- |
| `RepoRadar.graphql` | The query. `$search` is a list of `repo:owner/name` qualifiers. |
| `run.sh` | Runs the query with the `gh` CLI token: `Spikes/GraphQL/run.sh Cwander83/repo-radar Cwander83/gravity-bar` |
| `check-token.sh` | Runs the query with a token you paste (hidden) and summarizes what it can see. Use it to test a fine-grained PAT. |
| `fixtures/recorded-public.json` | Real response for six **public** repos (2026-10-24). No tokens; all data is already public. |
| `fixtures/synthetic-edge-cases.json` | Hand-written response covering PRs and CI/stale edge cases the public repos don't have. |
| `fixtures/expected-synthetic-edge-cases.json` | Expected classification for the synthetic fixture, for CHR-75 tests. |

## Results

- **Works with one request.** `search(type: REPOSITORY)` with `repo:` qualifiers takes a static query and a variable repo list. No per-repo aliases or query building needed.
- **Cost: 49 points per run** (reported by `rateLimit.cost`). GitHub computes cost from the `first:` limits, not from how much data comes back, so it stays about the same for 1–25 repos.
  - Every 5 min (12 runs/hour) → about **588 of 5,000 points/hour (~12%)**.
  - `refs(first: 100)` is the biggest driver (it was 36 points at `first: 50`). Lower it if the budget gets tight.
- **Limits per request:** 25 repos (`search first: 25`), 30 open PRs, 100 branches, and 25 checks per commit.
  - The Repositories settings tab must cap the watched list at 25, or the client must split the list into several requests. Past 25, `search.repositoryCount` exceeds the number of nodes returned and repos are silently dropped.
  - `refs.pageInfo.hasNextPage` tells the client a repo has more than 100 branches. Fetch the next page with `endCursor`, or flag the stale list as incomplete.
- **Empty repos** (`seo_reader`): `defaultBranchRef` is `null`. Decoding must treat it as optional.
- **No CI** (`workout-tracker`): `statusCheckRollup` is `null`. Show as "no checks", not as passing.
- **Third-party statuses arrive as `StatusContext`** (Vercel on two repos). GitHub Actions jobs arrive as `CheckRun`. Both need handling.
- **Duplicate check runs:** the same job appears twice when a commit ran for both `push` and `pull_request` (gravity-bar). De-duplicate by workflow name (or none) + check name and keep the latest `startedAt`.
- **Dependabot** adds a `.github/dependabot.yml` check run with `checkSuite.workflowRun: null` (recorded in repo-radar, and added to the synthetic fixture). `workflowRun` must decode as optional. It reports through the same rollup; treat it like any other check.
- **Branch protection:** `branchProtectionRule` is set for `main` here. It only reflects classic protection rules, not repository rulesets. Fine for now, since `main`/`develop`/default are always excluded by name.
- **Stale branches are real:** `workout-tracker/frontend-001` (2021) and `cursor/site-nav-history-session-4cb2` (62 days).
- **Branches can't be sorted by date in the query.** `TAG_COMMIT_DATE` only orders tags; on branches it returned 2026, 2021, 2026 for workout-tracker. The query now orders `ALPHABETICAL`, and the client sorts by `target.committedDate`.

## Classification rules (confirmed for CHR-75)

- **Failing:** check run conclusion `FAILURE`, `TIMED_OUT`, `STARTUP_FAILURE`; commit status `FAILURE` or `ERROR`. `CANCELLED` is ignored even when GitHub's rollup `state` says `FAILURE` (see `octo-user/beta`), so decide per context and never from `statusCheckRollup.state` alone.
- **Running:** check run status `QUEUED`, `IN_PROGRESS`, `WAITING`, `PENDING`, `REQUESTED`; commit status `PENDING`/`EXPECTED`.
- **Not decided yet:** `ACTION_REQUIRED`, `NEUTRAL`, `SKIPPED`, `STALE`. Proposal: `ACTION_REQUIRED` counts as failing; the others are ignored.
- **CI scope:** default branch, plus `main` when it differs from the default (here: `repo-radar` default is `develop`), plus the head commit of each of **my own** open, non-draft PRs. PRs where my review is requested are listed, but their CI isn't shown.
- **PRs:** authored by `viewer.login`, or with a `User` review request for `viewer.login`. Team requests don't count. Drafts hidden. Review requests first, then by `updatedAt`.
- **Stale:** age ≥ `staleDays` (30). Excludes the default branch, `main`, `develop`, protected branches, and branches with an open PR.

## ⚠️ Open risk: fine-grained PATs and check runs

GitHub lists calling the Checks API as a known gap for fine-grained personal access tokens ([Managing your personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)), and a community thread reports the Checks permission can't be assigned to them ([community discussion](https://github.com/orgs/community/discussions/129512)). The official permission list has no "Checks" entry ([permissions for fine-grained PATs](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens)). Commit statuses, pull requests, and branches are covered (`Commit statuses`, `Pull requests`, `Contents`: read).

This spike ran with the `gh` OAuth token, which can see check runs. The 2026-10-24 code review (Linear CHR-65) reports that a fine-grained PAT gets `Resource not accessible by personal access token` on `statusCheckRollup` / `CheckRun`. That run isn't recorded here; `check-token.sh` below reproduces it. If it holds, GitHub Actions results are invisible to Repo Radar with a fine-grained PAT, and ADR-001's token choice has to change.

**To test** (you create the token; nothing is stored):

1. GitHub → Settings → Developer settings → Fine-grained tokens → Generate. Repository access: `repo-radar` and `gravity-bar`. Permissions, all **read-only**: Metadata, Contents, Pull requests, Commit statuses, Actions.
2. Run `Spikes/GraphQL/check-token.sh Cwander83/repo-radar Cwander83/gravity-bar` and paste the token when asked.
3. Compare `checkRuns` with the `gh` token result: repo-radar 3, gravity-bar 4. Equal means fine-grained PATs work. `0` means they don't.

**If they don't work**, the options to decide in ADR-001:

- A classic PAT with the `repo` scope (broad: read and write to all repos).
- Keep the fine-grained PAT and read Actions results via the REST `actions/runs` endpoints (needs `Actions: read`), with extra requests per repo.
- Reuse the `gh` OAuth token for the prototype only.
