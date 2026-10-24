# Spike: App Group + WidgetKit with Free Personal Team (CHR-64)

This spike validates whether a sandboxed macOS host app and its WidgetKit extension can share data via an App Group container when signed with a free personal Apple ID.

## Project Structure

- `AppGroupWidgetSpike.xcodeproj`: Xcode project containing two targets:
  - `HostApp`: macOS SwiftUI application that writes a timestamped JSON payload to the App Group container and reloads widget timelines.
  - `SpikeWidgetExtension`: WidgetKit extension (small & medium) that reads and displays the payload from the container, with a link out to GitHub.
- `HostApp/`: Host app source and entitlements.
- `WidgetExtension/`: Widget extension source and entitlements.

## Verification Steps in Xcode

1. In Xcode, select target **HostApp** → **Signing & Capabilities**:
   - Check **Automatically manage signing**.
   - Under **Team**, select your **Personal Team** (`7P5RMM8JP7`).
   - Under **App Groups**, select `7P5RMM8JP7.com.chriswander.reporadar`.
2. Select target **SpikeWidgetExtension** → **Signing & Capabilities**:
   - Check **Automatically manage signing**.
   - Select the same **Personal Team**.
   - Under **App Groups**, select the same group ID.
3. Set scheme to **HostApp** and build/run (⌘R).
4. In HostApp, click **Write to App Group Container**.
5. Add **Spike Widget** to macOS desktop.
   - Confirm widget displays payload written by host app.
   - Click **Open GitHub ↗** to confirm browser opens.

## Results

1. **App Group Identifier on Free Personal Team:**
   - **Must use `<TEAMID>.com.chriswander.reporadar` on macOS.**
   - Unprefixed `group.com.chriswander.reporadar` was rejected by macOS `containermanagerd`:
     ```
     containermanagerd: [com.chriswander.reporadar.HostApp.SpikeWidgetExtension] requesting [group.com.chriswander.reporadar]: REJECTED. Requestor's signature does not allow it to access a TCC-protected group container. Group containers identifiers should be prefixed by requestor's team ID to allow access on this platform.
     kernel: (Sandbox) System Policy: SpikeWidgetExtension deny(1) file-read-data .../spike-payload.json
     ```
   - With `7P5RMM8JP7.com.chriswander.reporadar`:
     ```
     containermanagerd: [com.chriswander.reporadar.HostApp] requesting [7P5RMM8JP7.com.chriswander.reporadar]: APPROVED. Requestor's signature allows it to access a TCC-protected group container
     containermanagerd: [com.chriswander.reporadar.HostApp.SpikeWidgetExtension] requesting [7P5RMM8JP7.com.chriswander.reporadar]: APPROVED. Requestor's signature allows it to access a TCC-protected group container
     ```
   - Core constants `SnapshotStore.defaultAppGroupIdentifier` and `ConfigStore.defaultSuiteName` updated to `7P5RMM8JP7.com.chriswander.reporadar`.
2. **WidgetKit Extension Recognition & Read:**
   - Plugin point `com.apple.widgetkit-extension` verified via `pluginkit`.
   - Widget displays `Hello from Host App!` and host timestamp directly on macOS desktop.
   - Calling `WidgetCenter.shared.reloadAllTimelines()` from host app immediately refreshes widget UI.
3. **Link to HTTPS:**
   - Widget `Link(destination: URL(string: "https://github.com/Cwander83/repo-radar")!)` opens default web browser on macOS.
4. **Free Signing Lifetime:**
   - Provisioning profile (`embedded.provisionprofile`) has an expiration date of **7 days** from creation (`ExpirationDate: 2026-10-31T22:29:48Z`), standard for Apple free personal team accounts.
