# repo-radar

A macOS desktop widget and menu bar utility that gives a glance at your GitHub repos:

- Failing CI
- Open pull requests (authored + review requested)
- Stale branches

Native Swift (`RepoRadarCore` package + menu bar host app + WidgetKit extension), free to run, GitHub only.

The menu bar app fetches your repos on a timer with one GitHub GraphQL query and hands a snapshot to the widget. The widget comes in small, medium, and large sizes; the menu bar popover shows the same data in more detail.

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

## First Run

RepoRadar lives in the menu bar (no Dock icon). Click its icon and choose **Open Settings…**.

1. **Create a token.** On GitHub, create a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new). Under *Repository access*, select the repos you want to watch. Under *Repository permissions*, set these to **Read-only**:
   - Contents
   - Pull requests
   - Commit statuses
   - Actions

   Metadata (read-only) is added automatically.
2. **Save the token.** In Settings → **GitHub**, paste the token and click **Save**. RepoRadar checks it with one API call, then stores it in your login Keychain. It is only ever sent to `api.github.com`.
3. **Choose repos.** In Settings → **Repositories**, click **Choose repositories…** or type `owner/repo` and click **Add**. A repo marked “No access” is not covered by your token.
4. **Add the widget.** Right-click the desktop, choose **Edit Widgets…**, search for **Repo Radar**, and drag the small, medium, or large size onto the desktop. It fills in after the first refresh.

Optional settings:

- **General**: how often to check GitHub, refresh on wake, launch at login, a failing-CI count in the menu bar, and notifications when CI turns red.
- **Repositories**: how many days before a branch counts as stale.

### Weekly Re-signing (Free Personal Team)

Free Apple personal-team provisioning profiles expire after **7 days**. `make install` passes `-allowProvisioningUpdates` to `xcodebuild` to refresh and re-sign the app and widget extension. Re-run `make install` at least **once a week** so the app and desktop widget keep running.

## License

[MIT](LICENSE)
