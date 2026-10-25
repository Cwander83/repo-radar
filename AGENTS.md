# AGENTS.md

## Project

repo-radar: a macOS desktop widget showing open PRs, failing CI, and stale branches across my GitHub repos. Native Swift, free to run, GitHub only. Sibling of GravityBar (`~/Codebases/gravity-bar`); match its feel and conventions where sensible.

- Scope, risks, phases, open decisions: `docs/HANDOFF.md` (source of truth)
- Architecture spec: `docs/PROJECT_PLAN.md`
- `docs/templates/` holds generic planning templates. They are not specs for this project; ignore them unless asked.

## Architecture

- **Host app** (menu-bar-only, no Dock icon): fetches GitHub data on a timer, writes a JSON snapshot to the App Group container, calls `WidgetCenter.shared.reloadAllTimelines()`.
- **WidgetKit extension** (SwiftUI): reads the snapshot and renders it. No network or background work in the widget.
- **Data**: one GitHub GraphQL query for all configured repos.
- **Auth**: read-only fine-grained PAT in the macOS Keychain. `gh auth token` acceptable for prototyping.

## Critical rules

- Keep responses concise unless asked otherwise.
- Planning: ask clarifying questions. Never assume design, tech stack, or features beyond `docs/HANDOFF.md`.
- Work phase by phase. Do Phase 0 (GraphQL spike + App Group signing spike) and report results before writing UI code.
- Swift only. Prefer Foundation / URLSession / SwiftUI. Do not add third-party packages without asking.
- Never write tokens to the repo, config files, logs, fixtures, or the snapshot. Scrub fixtures of anything secret before committing.
- Keep the codebase small. Optimize for low token use: no speculative abstractions.
- No silent fallbacks in production code. If the App Group, Keychain or another required resource is unavailable, surface an error state; never fall back to `UserDefaults.standard`, in-memory stores or temp paths (those are for tests only).

## Environment

- Dev machine: macOS 26, Swift 6.x.
- Full Xcode is required for the widget extension (`xcode-select -p` must point into `Xcode.app`, not CommandLineTools).
- Signing: free personal team. No paid Apple Developer Program.
- `gh` CLI is authenticated; use it for Phase 0 queries and GitHub operations.

## Testing

- Never assume changes work. Build and run tests after every change.
- Unit-test decoding and classification (failing / stale / review-requested) against recorded fixtures.
- If no test tooling exists yet for a change, ask whether to skip testing.

## Git workflow

- `develop` is the working branch. Every change: branch off `develop`, PR back into `develop`.
- Never commit to, merge into, push to, or open PRs against `main` unless the user explicitly says so. The user promotes `develop` to `main` themselves.
- Linear issue branches use the `chriswandermail/chr-NN-short-name` format.
- Conventional Commits (`feat:`, `fix:`, `docs:`, `build:`, `ci:`, `test:`).
- CI must pass (Gitleaks secret scan, plus build/test once sources exist).
