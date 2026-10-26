import SwiftUI
import Combine
import UserNotifications
import RepoRadarCore

@MainActor
final class AppModel: ObservableObject {
  let scheduler: RefreshScheduler?
  let notificationDelegate: CINotificationDelegate
  private var cancellable: AnyCancellable?
  private var wakeCancellable: AnyCancellable?

  init(
    scheduler: RefreshScheduler? = RefreshScheduler(),
    notificationDelegate: CINotificationDelegate = CINotificationDelegate()
  ) {
    self.notificationDelegate = notificationDelegate
    if Bundle.main.bundleIdentifier != nil {
      UNUserNotificationCenter.current().delegate = notificationDelegate
    }
    self.scheduler = scheduler

    if let scheduler {
      cancellable = scheduler.objectWillChange
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
          self?.objectWillChange.send()
        }

      // Refresh after sleep once the network is back (CHR-91).
      wakeCancellable = NSWorkspace.shared.notificationCenter
        .publisher(for: NSWorkspace.didWakeNotification)
        .receive(on: DispatchQueue.main)
        .sink { _ in
          scheduler.handleWake()
        }
    }
    scheduler?.start()
  }

  var configStore: ConfigStore? {
    scheduler?.service.configStore
  }

  var menuBarState: MenuBarState {
    scheduler?.menuBarState ?? .error
  }

  func handleConfigChanged(_ config: RepoRadarConfig) {
    scheduler?.configurationDidChange()
    objectWillChange.send()
  }
}

@main
struct RepoRadarApp: App {
  @StateObject private var model = AppModel()

  init() {
    #if DEBUG
    if CommandLine.arguments.contains("--verify-keychain") {
      runKeychainVerification()
    }
    #endif
    // No Dock icon: Info.plist sets LSUIElement, so no activation policy call is needed.
  }

  var body: some Scene {
    MenuBarExtra {
      if let scheduler = model.scheduler {
        PopoverView(scheduler: scheduler)
      } else {
        AppGroupUnavailableView()
      }
    } label: {
      MenuBarItemView(state: model.menuBarState)
    }
    .menuBarExtraStyle(.window)

    Settings {
      if let configStore = model.configStore, let scheduler = model.scheduler {
        SettingsView(
          configStore: configStore,
          scheduler: scheduler,
          onConfigChange: { config in
            model.handleConfigChanged(config)
          },
          onRefreshRequest: {
            model.scheduler?.refreshCachedState()
            Task {
              try? await model.scheduler?.refreshNow()
            }
          }
        )
      } else {
        AppGroupUnavailableView()
          .frame(width: 480, height: 200)
      }
    }
  }
}

struct MenuBarItemView: View {
  let state: MenuBarState

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: state.systemImageName)
        .opacity(state.isDimmed ? 0.45 : 1.0)

      if let count = state.badgeCount {
        #if canImport(AppKit)
        Image(nsImage: MenuBarBadgeImage.render(count: count))
        #else
        Text("\(count)")
          .font(.system(size: 9.5, weight: .bold))
          .foregroundStyle(.white)
          .padding(.horizontal, 4)
          .padding(.vertical, 1)
          .background(Color.red, in: Capsule())
        #endif
      }
    }
    .accessibilityLabel(state.accessibilityLabel)
  }
}

private struct AppGroupUnavailableView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("App Group unavailable — reinstall/re-sign")
        .foregroundStyle(.red)
        .font(.callout)
      Divider()
      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
      .keyboardShortcut("q")
    }
    .padding(12)
  }
}

#Preview("Clear - Light") {
  MenuBarItemView(state: .clear)
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Clear - Dark") {
  MenuBarItemView(state: .clear)
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Failing - Light") {
  MenuBarItemView(state: .failing(count: 2))
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Failing - Dark") {
  MenuBarItemView(state: .failing(count: 2))
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Error - Light") {
  MenuBarItemView(state: .error)
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Error - Dark") {
  MenuBarItemView(state: .error)
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Offline - Light") {
  MenuBarItemView(state: .offline)
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Offline - Dark") {
  MenuBarItemView(state: .offline)
    .padding()
    .preferredColorScheme(.dark)
}

#if DEBUG
private func runKeychainVerification() {
  let testAccount = "verify-sandbox-\(UUID().uuidString)"
  let testStore = KeychainTokenStore(account: testAccount)
  defer { try? testStore.delete() }
  do {
    let testToken = "test-token-\(UUID().uuidString)"
    try testStore.save(token: testToken)
    guard try testStore.read() == testToken else {
      fputs("KEYCHAIN VERIFICATION FAILED: read mismatch\n", stderr)
      exit(1)
    }
    try testStore.delete()
    guard try testStore.read() == nil else {
      fputs("KEYCHAIN VERIFICATION FAILED: token still present after delete\n", stderr)
      exit(1)
    }
    fputs("KEYCHAIN VERIFICATION SUCCESS\n", stdout)
    exit(0)
  } catch {
    fputs("KEYCHAIN VERIFICATION FAILED: \(error)\n", stderr)
    exit(1)
  }
}
#endif
