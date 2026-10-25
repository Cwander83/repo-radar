import SwiftUI
import RepoRadarCore

/// Supported tabs in the RepoRadar Settings window.
public enum SettingsTab: String, CaseIterable, Identifiable {
  case general
  case repositories
  case github

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .general:
      return "General"
    case .repositories:
      return "Repositories"
    case .github:
      return "GitHub"
    }
  }

  public var systemImage: String {
    switch self {
    case .general:
      return "slider.horizontal.3"
    case .repositories:
      return "book.closed"
    case .github:
      return "key"
    }
  }
}

/// Root settings window view presenting tab navigation across General, Repositories, and GitHub tabs.
public struct SettingsView: View {
  @State private var selectedTab: SettingsTab
  public let configStore: ConfigStore
  public var onConfigChange: ((RepoRadarConfig) -> Void)?

  public init(
    configStore: ConfigStore,
    initialTab: SettingsTab = .general,
    onConfigChange: ((RepoRadarConfig) -> Void)? = nil
  ) {
    self.configStore = configStore
    self._selectedTab = State(initialValue: initialTab)
    self.onConfigChange = onConfigChange
  }

  public var body: some View {
    TabView(selection: $selectedTab) {
      GeneralSettingsView(configStore: configStore, onConfigChange: onConfigChange)
        .tabItem {
          Label(SettingsTab.general.title, systemImage: SettingsTab.general.systemImage)
        }
        .tag(SettingsTab.general)

      RepositoriesSettingsPlaceholderView()
        .tabItem {
          Label(SettingsTab.repositories.title, systemImage: SettingsTab.repositories.systemImage)
        }
        .tag(SettingsTab.repositories)

      GitHubSettingsPlaceholderView()
        .tabItem {
          Label(SettingsTab.github.title, systemImage: SettingsTab.github.systemImage)
        }
        .tag(SettingsTab.github)
    }
    .frame(width: 480)
  }
}

/// General settings tab displaying polling intervals, wake refresh, login item, menu bar badge, and CI notifications.
public struct GeneralSettingsView: View {
  @StateObject private var viewModel: GeneralSettingsViewModel

  public init(viewModel: GeneralSettingsViewModel) {
    self._viewModel = StateObject(wrappedValue: viewModel)
  }

  public init(
    configStore: ConfigStore,
    onConfigChange: ((RepoRadarConfig) -> Void)? = nil
  ) {
    self._viewModel = StateObject(
      wrappedValue: GeneralSettingsViewModel(configStore: configStore, onConfigChange: onConfigChange)
    )
  }

  public var body: some View {
    Form {
      Section {
        Picker("Check GitHub every", selection: $viewModel.pollInterval) {
          ForEach(PollInterval.allCases, id: \.self) { interval in
            Text(interval.displayName).tag(interval)
          }
        }

        Toggle("Refresh when your Mac wakes", isOn: $viewModel.refreshOnWake)
      } footer: {
        Text("The widget redraws about every 15 minutes. macOS decides the exact timing.")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }

      Section {
        Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
        Toggle("Show failing-CI count in the menu bar", isOn: $viewModel.showMenuBarCount)
      }

      Section {
        Toggle("Notify me when CI turns red", isOn: $viewModel.ciNotifications)
      } footer: {
        Text("Only when a check goes from passing to failing. Off by default.")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .toggleStyle(.switch)
    .frame(width: 480)
    .padding(.bottom, 8)
  }
}

/// Placeholder view for Repositories tab (to be implemented in CHR-84).
public struct RepositoriesSettingsPlaceholderView: View {
  public init() {}

  public var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "book.closed")
        .font(.system(size: 32))
        .foregroundStyle(.secondary)
      Text("Repositories")
        .font(.headline)
      Text("Watched repository management will be configured here.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(width: 480, height: 260)
  }
}

/// Placeholder view for GitHub tab (to be implemented in CHR-85).
public struct GitHubSettingsPlaceholderView: View {
  public init() {}

  public var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "key")
        .font(.system(size: 32))
        .foregroundStyle(.secondary)
      Text("GitHub Token")
        .font(.headline)
      Text("Personal access token and credentials will be configured here.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(width: 480, height: 260)
  }
}

// MARK: - Previews

private func makePreviewStore() -> ConfigStore {
  let defaults = UserDefaults(suiteName: "reporadar.preview.settings") ?? .standard
  return ConfigStore(userDefaults: defaults)
}

#Preview("General Settings - Light") {
  GeneralSettingsView(configStore: makePreviewStore())
    .preferredColorScheme(.light)
}

#Preview("General Settings - Dark") {
  GeneralSettingsView(configStore: makePreviewStore())
    .preferredColorScheme(.dark)
}

#Preview("Settings Window - Light") {
  SettingsView(configStore: makePreviewStore())
    .preferredColorScheme(.light)
}

#Preview("Settings Window - Dark") {
  SettingsView(configStore: makePreviewStore())
    .preferredColorScheme(.dark)
}
