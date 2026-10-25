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
  public let snapshot: WidgetSnapshot?
  public var onConfigChange: ((RepoRadarConfig) -> Void)?
  public var onRefreshRequest: (() -> Void)?

  public init(
    configStore: ConfigStore,
    snapshot: WidgetSnapshot? = nil,
    initialTab: SettingsTab = .general,
    onConfigChange: ((RepoRadarConfig) -> Void)? = nil,
    onRefreshRequest: (() -> Void)? = nil
  ) {
    self.configStore = configStore
    self.snapshot = snapshot
    self._selectedTab = State(initialValue: initialTab)
    self.onConfigChange = onConfigChange
    self.onRefreshRequest = onRefreshRequest
  }

  public var body: some View {
    TabView(selection: $selectedTab) {
      GeneralSettingsView(configStore: configStore, onConfigChange: onConfigChange)
        .tabItem {
          Label(SettingsTab.general.title, systemImage: SettingsTab.general.systemImage)
        }
        .tag(SettingsTab.general)

      RepositoriesSettingsView(
        configStore: configStore,
        snapshot: snapshot,
        onConfigChange: onConfigChange,
        onRefreshRequest: onRefreshRequest
      )
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

/// Repositories settings tab displaying watched repositories, reachability, access statuses, and stale threshold.
public struct RepositoriesSettingsView: View {
  @StateObject private var viewModel: RepositoriesSettingsViewModel

  public init(viewModel: RepositoriesSettingsViewModel) {
    self._viewModel = StateObject(wrappedValue: viewModel)
  }

  public init(
    configStore: ConfigStore,
    snapshot: WidgetSnapshot? = nil,
    onConfigChange: ((RepoRadarConfig) -> Void)? = nil,
    onRefreshRequest: (() -> Void)? = nil
  ) {
    self._viewModel = StateObject(
      wrappedValue: RepositoriesSettingsViewModel(
        configStore: configStore,
        snapshot: snapshot,
        onConfigChange: onConfigChange,
        onRefreshRequest: onRefreshRequest
      )
    )
  }

  public var body: some View {
    Form {
      Section {
        if viewModel.watchedRepos.isEmpty {
          Text("No repositories configured yet.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
        } else {
          ForEach(viewModel.watchedRepos, id: \.self) { repo in
            repositoryRow(repo)
          }
        }

        addRepositoryRow
      } header: {
        HStack {
          Text("WATCHED REPOSITORIES")
          Spacer()
          Text("\(viewModel.reachableCount) of \(viewModel.totalCount) reachable")
            .font(.system(size: 11, weight: .regular))
        }
      } footer: {
        Text("Your token must include each repository. “No access” means the token can’t read it.")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }

      Section {
        HStack {
          Text("Mark branches stale after")
            .font(.system(size: 13))
          Spacer()
          Stepper(
            "\(viewModel.staleDays) days",
            value: $viewModel.staleDays,
            in: 1...365
          )
          .font(.system(size: 13))
        }
      } footer: {
        Text("Skips the default branch, main, develop, protected branches, and branches with an open PR.")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 480)
    .padding(.bottom, 8)
  }

  private func repositoryRow(_ repo: String) -> some View {
    HStack(spacing: 8) {
      repoNameView(repo)

      Spacer()

      if let branch = viewModel.defaultBranch(for: repo) {
        Text(branch)
          .font(.system(size: 11))
          .padding(.horizontal, 6)
          .padding(.vertical, 1)
          .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 4) {
        Circle()
          .fill(viewModel.hasAccess(for: repo) ? Color.green : Color.red)
          .frame(width: 6, height: 6)

        Text(viewModel.statusText(for: repo))
          .font(.system(size: 11))
          .foregroundStyle(viewModel.hasAccess(for: repo) ? Color.secondary : Color.red)
      }
      .frame(width: 80, alignment: .leading)

      Button {
        viewModel.removeRepository(repo)
      } label: {
        Image(systemName: "minus.circle")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Remove \(repo)")
    }
    .padding(.vertical, 2)
  }

  private func repoNameView(_ repo: String) -> some View {
    let parts = repo.split(separator: "/", maxSplits: 1)
    return HStack(spacing: 0) {
      if parts.count == 2 {
        Text("\(parts[0])/")
          .foregroundStyle(.secondary)
        Text(parts[1])
          .foregroundStyle(.primary)
      } else {
        Text(repo)
          .foregroundStyle(.primary)
      }
    }
    .font(.system(size: 13))
    .lineLimit(1)
    .truncationMode(.tail)
  }

  private var addRepositoryRow: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        TextField("owner/repo", text: $viewModel.newRepoInput)
          .textFieldStyle(.roundedBorder)
          .font(.system(size: 13))
          .onSubmit {
            viewModel.addRepository()
          }

        Button("Add") {
          viewModel.addRepository()
        }
        .disabled(viewModel.newRepoInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }

      if let error = viewModel.errorMessage {
        Text(error)
          .font(.system(size: 11))
          .foregroundStyle(.red)
      }
    }
    .padding(.vertical, 2)
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
  let suite = "reporadar.preview.settings"
  let defaults = UserDefaults(suiteName: suite) ?? .standard
  let store = ConfigStore(userDefaults: defaults)
  if store.load().watchedRepos.isEmpty {
    store.save(
      sanitizing: RepoRadarConfig(
        watchedRepos: [
          "Cwander83/repo-radar",
          "Cwander83/gravity-bar",
          "Cwander83/ollama-bar",
          "Cwander83/workout-tracker",
          "Cwander83/vite-portfolio"
        ],
        staleDays: 30
      )
    )
  }
  return store
}

private func makePreviewSnapshot() -> WidgetSnapshot {
  WidgetSnapshot(
    status: .ok,
    repositoryAccess: [
      RepositoryAccessItem(name: "Cwander83/repo-radar", defaultBranch: "develop", hasAccess: true),
      RepositoryAccessItem(name: "Cwander83/gravity-bar", defaultBranch: "main", hasAccess: true),
      RepositoryAccessItem(name: "Cwander83/ollama-bar", defaultBranch: "main", hasAccess: true),
      RepositoryAccessItem(name: "Cwander83/workout-tracker", defaultBranch: "main", hasAccess: true),
      RepositoryAccessItem(name: "Cwander83/vite-portfolio", defaultBranch: nil, hasAccess: false)
    ]
  )
}

#Preview("General Settings - Light") {
  GeneralSettingsView(configStore: makePreviewStore())
    .preferredColorScheme(.light)
}

#Preview("General Settings - Dark") {
  GeneralSettingsView(configStore: makePreviewStore())
    .preferredColorScheme(.dark)
}

#Preview("Repositories Settings - Light") {
  RepositoriesSettingsView(
    configStore: makePreviewStore(),
    snapshot: makePreviewSnapshot()
  )
  .preferredColorScheme(.light)
}

#Preview("Repositories Settings - Dark") {
  RepositoriesSettingsView(
    configStore: makePreviewStore(),
    snapshot: makePreviewSnapshot()
  )
  .preferredColorScheme(.dark)
}

#Preview("Settings Window - Repositories - Light") {
  SettingsView(
    configStore: makePreviewStore(),
    snapshot: makePreviewSnapshot(),
    initialTab: .repositories
  )
  .preferredColorScheme(.light)
}

#Preview("Settings Window - Repositories - Dark") {
  SettingsView(
    configStore: makePreviewStore(),
    snapshot: makePreviewSnapshot(),
    initialTab: .repositories
  )
  .preferredColorScheme(.dark)
}
