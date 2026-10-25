import SwiftUI
import Combine
import RepoRadarCore

@MainActor
final class AppModel: ObservableObject {
  let scheduler: RefreshScheduler?
  private var cancellable: AnyCancellable?

  init(scheduler: RefreshScheduler? = RefreshScheduler()) {
    self.scheduler = scheduler
    if let scheduler {
      cancellable = scheduler.objectWillChange
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
          self?.objectWillChange.send()
        }
    }
    scheduler?.start()
  }

  var menuBarState: MenuBarState {
    scheduler?.menuBarState ?? .error
  }
}

@main
struct RepoRadarApp: App {
  @StateObject private var model = AppModel()

  init() {
    NSApplication.shared.setActivationPolicy(.accessory)
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
