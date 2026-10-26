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
- GitHub fine-grained Personal Access Token (read-only: Metadata, Contents, Pull requests, Commit statuses, Actions)

## Build & Install

1. Configure your Apple Developer personal team ID (git-ignored):

   ```bash
   cp Configurations/Local.xcconfig.template Configurations/Local.xcconfig
   ```

   Find your Team ID in Xcode (Settings → Accounts → your Apple ID → Team ID) or via:

   ```bash
   security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject -nameopt multiline | grep organizationalUnitName
   ```

   If it differs from the default in the template, edit `Configurations/Local.xcconfig`.

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
