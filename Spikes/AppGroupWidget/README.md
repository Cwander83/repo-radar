# Spike: App Group + WidgetKit with Free Personal Team (CHR-64)

This spike validates whether a sandboxed macOS host app and its WidgetKit extension can share data via an App Group container when signed with a free personal Apple ID.

## Project Structure

- `AppGroupWidgetSpike.xcodeproj`: Xcode project containing two targets:
  - `HostApp`: macOS SwiftUI application that writes a timestamped JSON payload to the App Group container.
  - `SpikeWidgetExtension`: WidgetKit extension (small & medium) that reads and displays the payload from the container, with a link out to GitHub.
- `HostApp/`: Host app source and entitlements.
- `WidgetExtension/`: Widget extension source and entitlements.

## Verification Steps in Xcode

1. In Xcode (which is now open), click on the top-level **AppGroupWidgetSpike** project in the navigator.
2. Select target **HostApp** → **Signing & Capabilities**:
   - Check **Automatically manage signing**.
   - Under **Team**, select your **Personal Team** (your Apple ID).
   - Under **App Groups**, observe the status of `group.com.chriswander.reporadar`:
     - If it shows an error (e.g. requiring a paid developer account or `<TEAMID>.` prefix), record the exact message.
3. Select target **SpikeWidgetExtension** → **Signing & Capabilities**:
   - Check **Automatically manage signing**.
   - Select the same **Personal Team**.
   - Under **App Groups**, select the same group ID.
4. Set the active scheme to **HostApp** (destination: **My Mac**).
5. Build and run (⌘R).
6. In the running HostApp window, click **Write to App Group Container**.
   - Observe if the write succeeds and note the container path.
7. Open macOS Notification Center / Desktop Widgets:
   - Click **Edit Widgets...**
   - Look for **Spike Widget** in the gallery.
   - Add the widget to your desktop.
   - Observe if the widget displays the message and timestamp written by the host app.
   - Click the **Open GitHub ↗** link on the widget to test if it opens the browser.
