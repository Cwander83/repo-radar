# repo-radar

A macOS desktop widget and menu bar utility that gives a glance at your GitHub repos:

- Failing CI
- Open pull requests (authored + review requested)
- Stale branches

Native Swift (`RepoRadarCore` package + menu bar host app + WidgetKit extension), free to run, GitHub only.

## Requirements

- macOS 26+
- Full Xcode (not just Command Line Tools; `xcode-select -p` must point into `Xcode.app`)
- Apple ID signed in to Xcode (Settings → Accounts) for free personal-team signing
- GitHub fine-grained Personal Access Token (read-only: Contents, Pull requests, Checks, Commit statuses, Metadata)

## Build & Install

1. Configure your Apple Developer personal team ID (git-ignored):

   ```bash
   cp Configurations/Local.xcconfig.template Configurations/Local.xcconfig
   # Edit Configurations/Local.xcconfig if your DEVELOPMENT_TEAM differs
   ```

2. Build, sign, install to `/Applications/RepoRadar.app`, and launch:

   ```bash
   make install
   ```

   Other `make` targets:
   - `make test` — run `RepoRadarCore` unit tests (`swift test`)
   - `make build` — debug build of `RepoRadarCore` (`swift build`)
   - `make app` — build and sign `dist/RepoRadar.app` in Release without installing
   - `make clean` — remove `dist/` and `.build/`

### Weekly Re-signing (Free Personal Team)

Free Apple personal-team provisioning profiles expire after **7 days**. `make install` passes `-allowProvisioningUpdates` to `xcodebuild` to refresh and re-sign the app and widget extension. Re-run `make install` at least **once a week** so the app and desktop widget keep running.
