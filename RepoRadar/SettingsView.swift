import SwiftUI
import Combine
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
  public let tokenStore: any TokenStore
  public let snapshot: WidgetSnapshot?
  public let snapshotPublisher: AnyPublisher<WidgetSnapshot?, Never>?
  public var onConfigChange: ((RepoRadarConfig) -> Void)?
  public var onRefreshRequest: (() -> Void)?

  public init(
    configStore: ConfigStore,
    tokenStore: any TokenStore = KeychainTokenStore(),
    snapshot: WidgetSnapshot? = nil,
    snapshotPublisher: AnyPublisher<WidgetSnapshot?, Never>? = nil,
    initialTab: SettingsTab = .general,
    onConfigChange: ((RepoRadarConfig) -> Void)? = nil,
    onRefreshRequest: (() -> Void)? = nil
  ) {
    self.configStore = configStore
    self.tokenStore = tokenStore
    self.snapshot = snapshot
    self.snapshotPublisher = snapshotPublisher
    self._selectedTab = State(initialValue: initialTab)
    self.onConfigChange = onConfigChange
    self.onRefreshRequest = onRefreshRequest
  }

  public init(
    configStore: ConfigStore,
    tokenStore: (any TokenStore)? = nil,
    scheduler: RefreshScheduler?,
    initialTab: SettingsTab = .general,
    onConfigChange: ((RepoRadarConfig) -> Void)? = nil,
    onRefreshRequest: (() -> Void)? = nil
  ) {
    self.init(
      configStore: configStore,
      tokenStore: tokenStore ?? scheduler?.service.tokenStore ?? KeychainTokenStore(),
      snapshot: scheduler?.latestSnapshot,
      snapshotPublisher: scheduler?.$latestSnapshot.eraseToAnyPublisher(),
      initialTab: initialTab,
      onConfigChange: onConfigChange,
      onRefreshRequest: onRefreshRequest
    )
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
        snapshotPublisher: snapshotPublisher,
        onConfigChange: onConfigChange,
        onRefreshRequest: onRefreshRequest
      )
      .tabItem {
        Label(SettingsTab.repositories.title, systemImage: SettingsTab.repositories.systemImage)
      }
      .tag(SettingsTab.repositories)

      GitHubSettingsView(
        tokenStore: tokenStore,
        configStore: configStore,
        snapshot: snapshot,
        snapshotPublisher: snapshotPublisher,
        onRefreshRequest: onRefreshRequest
      )
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
  private let snapshot: WidgetSnapshot?

  public init(viewModel: RepositoriesSettingsViewModel, snapshot: WidgetSnapshot? = nil) {
    self._viewModel = StateObject(wrappedValue: viewModel)
    self.snapshot = snapshot
  }

  public init(
    configStore: ConfigStore,
    snapshot: WidgetSnapshot? = nil,
    snapshotPublisher: AnyPublisher<WidgetSnapshot?, Never>? = nil,
    onConfigChange: ((RepoRadarConfig) -> Void)? = nil,
    onRefreshRequest: (() -> Void)? = nil
  ) {
    self.snapshot = snapshot
    self._viewModel = StateObject(
      wrappedValue: RepositoriesSettingsViewModel(
        configStore: configStore,
        snapshot: snapshot,
        snapshotPublisher: snapshotPublisher,
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
    .onChange(of: snapshot) { _, newSnapshot in
      viewModel.updateAccess(from: newSnapshot)
    }
    .onAppear {
      viewModel.updateAccess(from: snapshot)
    }
  }

  private func repositoryRow(_ repo: String) -> some View {
    let status = viewModel.accessStatus(for: repo)

    return HStack(spacing: 8) {
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
          .fill(statusDotColor(for: status))
          .frame(width: 6, height: 6)

        Text(status.displayText)
          .font(.system(size: 11))
          .foregroundStyle(statusTextColor(for: status))
      }
      .frame(width: 84, alignment: .leading)

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

  private func statusDotColor(for status: RepoAccessStatus) -> Color {
    switch status {
    case .ok:
      return .green
    case .noAccess:
      return .red
    case .checking:
      return .gray
    }
  }

  private func statusTextColor(for status: RepoAccessStatus) -> Color {
    switch status {
    case .ok, .checking:
      return .secondary
    case .noAccess:
      return .red
    }
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

/// GitHub settings tab displaying token presence, status, expiry, budget, required permissions, and replacement flow.
public struct GitHubSettingsView: View {
  @StateObject private var viewModel: GitHubSettingsViewModel
  private let snapshot: WidgetSnapshot?

  public init(viewModel: GitHubSettingsViewModel, snapshot: WidgetSnapshot? = nil) {
    self._viewModel = StateObject(wrappedValue: viewModel)
    self.snapshot = snapshot
  }

  public init(
    tokenStore: any TokenStore,
    configStore: ConfigStore? = nil,
    snapshot: WidgetSnapshot? = nil,
    snapshotPublisher: AnyPublisher<WidgetSnapshot?, Never>? = nil,
    onRefreshRequest: (() -> Void)? = nil
  ) {
    self.snapshot = snapshot
    self._viewModel = StateObject(
      wrappedValue: GitHubSettingsViewModel(
        tokenStore: tokenStore,
        configStore: configStore,
        snapshot: snapshot,
        snapshotPublisher: snapshotPublisher,
        onRefreshRequest: onRefreshRequest
      )
    )
  }

  public var body: some View {
    Form {
      if viewModel.status.isExpired {
        expiredBannerSection
      }

      if !viewModel.hasToken || viewModel.isReplacingToken {
        tokenInputSection
      }

      if viewModel.hasToken {
        tokenDetailsSection
      }

      permissionsSection
    }
    .formStyle(.grouped)
    .frame(width: 480)
    .padding(.bottom, 8)
    .onChange(of: snapshot) { _, newSnapshot in
      viewModel.updateFromSnapshot(newSnapshot)
    }
  }

  private var expiredBannerSection: some View {
    Section {
      HStack(alignment: .center, spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 16))
          .foregroundStyle(Color.red)

        Text(viewModel.expiredBannerText)
          .font(.system(size: 12))
          .foregroundStyle(Color.red)
          .lineLimit(2)

        Spacer()

        Button("Replace Token…") {
          viewModel.beginReplacingToken()
        }
        .buttonStyle(.borderedProminent)
        .font(.system(size: 13, weight: .medium))
      }
      .padding(.vertical, 4)
    }
  }

  private var tokenInputSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          SecureField("github_pat_...", text: $viewModel.tokenInput)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13))
            .disabled(viewModel.isValidating)
            .onSubmit {
              Task {
                await viewModel.saveToken()
              }
            }

          if viewModel.isValidating {
            ProgressView()
              .controlSize(.small)
          }

          Button("Save") {
            Task {
              await viewModel.saveToken()
            }
          }
          .disabled(viewModel.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isValidating)

          if viewModel.hasToken {
            Button("Cancel") {
              viewModel.cancelReplacingToken()
            }
            .disabled(viewModel.isValidating)
          }
        }

        if let error = viewModel.validationError {
          Text(error)
            .font(.system(size: 11))
            .foregroundStyle(.red)
        }
      }
      .padding(.vertical, 2)
    } header: {
      Text(viewModel.hasToken ? "REPLACE TOKEN" : "PERSONAL ACCESS TOKEN")
    } footer: {
      if !viewModel.hasToken {
        Text("Paste a fine-grained personal access token with the required permissions below.")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
    }
  }

  private var tokenDetailsSection: some View {
    Section {
      // Header row
      HStack(spacing: 10) {
        Image(systemName: "key")
          .font(.system(size: 16))
          .foregroundStyle(.secondary)
          .frame(width: 20)

        VStack(alignment: .leading, spacing: 1) {
          Text("Fine-grained token")
            .font(.system(size: 13))
          Text("\(viewModel.maskedToken ?? "") · stored in Keychain")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }

        Spacer()

        statusPill
      }
      .padding(.vertical, 2)

      // Facts rows
      factRow(label: "Account", value: viewModel.account ?? "—", isRed: false)

      if viewModel.status.isExpired {
        factRow(label: "Expired", value: viewModel.expirationText, isRed: true)
        factRow(label: "Repository access", value: viewModel.repositoryAccessText, isRed: false)
        factRow(label: "Last successful refresh", value: viewModel.lastRefreshText, isRed: false)
      } else {
        factRow(label: "Expires", value: viewModel.expirationText, isRed: false)
        factRow(label: "Repository access", value: viewModel.repositoryAccessText, isRed: false)
        factRow(label: "API budget this hour", value: viewModel.apiBudgetText, isRed: false)
      }

      // Actions row
      HStack {
        Spacer()

        Button("Remove Token") {
          viewModel.removeToken()
        }
        .font(.system(size: 13))
        .foregroundStyle(.red)
        .buttonStyle(.plain)

        Button("Replace Token…") {
          viewModel.beginReplacingToken()
        }
        .font(.system(size: 13))
        .buttonStyle(.plain)
        .padding(.leading, 8)
      }
      .padding(.vertical, 4)
    } header: {
      if !viewModel.isReplacingToken {
        Text("PERSONAL ACCESS TOKEN")
      }
    }
  }

  private var statusPill: some View {
    Text(viewModel.status.label)
      .font(.system(size: 11, weight: .semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .background(statusPillBackground, in: Capsule())
      .foregroundStyle(statusPillForeground)
  }

  private var statusPillBackground: Color {
    switch viewModel.status {
    case .valid:
      return Color.green.opacity(0.14)
    case .expired, .invalid:
      return Color.red.opacity(0.16)
    case .missing:
      return Color.secondary.opacity(0.12)
    }
  }

  private var statusPillForeground: Color {
    switch viewModel.status {
    case .valid:
      return Color.green
    case .expired, .invalid:
      return Color.red
    case .missing:
      return Color.secondary
    }
  }

  private func factRow(label: String, value: String, isRed: Bool) -> some View {
    HStack {
      Text(label)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.system(size: 13))
        .foregroundStyle(isRed ? Color.red : Color.primary)
    }
    .padding(.vertical, 1)
  }

  private var permissionsSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 6) {
        Text("Required permissions · all read-only")
          .font(.system(size: 12, weight: .semibold))

        Text("Metadata · Contents · Pull requests · Commit statuses · Actions")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)

        Link("Create a token on GitHub ↗", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
          .font(.system(size: 12, weight: .medium))
      }
      .padding(.vertical, 4)
    } footer: {
      Text("The token stays in your login Keychain and is only sent to api.github.com.")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
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

private func makePreviewValidTokenStore() -> InMemoryTokenStore {
  InMemoryTokenStore(initialToken: "github_pat_11ABCDEFGHIJKLM3fK2")
}

@MainActor
private func makePreviewValidVM() -> GitHubSettingsViewModel {
  let store = makePreviewStore()
  store.userDefaults.set("Cwander83", forKey: GitHubSettingsViewModel.CacheKeys.cachedAccount)
  let future = Calendar.current.date(byAdding: .day, value: 90, to: Date())!
  store.userDefaults.set(future.timeIntervalSince1970, forKey: GitHubSettingsViewModel.CacheKeys.cachedExpiration)
  let vm = GitHubSettingsViewModel(
    tokenStore: makePreviewValidTokenStore(),
    configStore: store,
    snapshot: WidgetSnapshot(
      status: .ok,
      rateLimit: SnapshotRateLimit(remaining: 4912, limit: 5000, resetAt: Date(), cost: 1)
    )
  )
  return vm
}

@MainActor
private func makePreviewExpiredVM() -> GitHubSettingsViewModel {
  let store = makePreviewStore()
  store.userDefaults.set("Cwander83", forKey: GitHubSettingsViewModel.CacheKeys.cachedAccount)
  let past = Calendar.current.date(byAdding: .day, value: -4, to: Date())!
  store.userDefaults.set(past.timeIntervalSince1970, forKey: GitHubSettingsViewModel.CacheKeys.cachedExpiration)
  let vm = GitHubSettingsViewModel(
    tokenStore: makePreviewValidTokenStore(),
    configStore: store,
    snapshot: WidgetSnapshot(
      updatedAt: past,
      status: .tokenError(detail: "Token expired on GitHub")
    )
  )
  return vm
}

#Preview("GitHub Settings - Valid - Light") {
  GitHubSettingsView(viewModel: makePreviewValidVM())
    .preferredColorScheme(.light)
}

#Preview("GitHub Settings - Valid - Dark") {
  GitHubSettingsView(viewModel: makePreviewValidVM())
    .preferredColorScheme(.dark)
}

#Preview("GitHub Settings - Expired - Light") {
  GitHubSettingsView(viewModel: makePreviewExpiredVM())
    .preferredColorScheme(.light)
}

#Preview("GitHub Settings - Expired - Dark") {
  GitHubSettingsView(viewModel: makePreviewExpiredVM())
    .preferredColorScheme(.dark)
}

#Preview("Settings Window - GitHub - Light") {
  SettingsView(
    configStore: makePreviewStore(),
    tokenStore: makePreviewValidTokenStore(),
    snapshot: makePreviewSnapshot(),
    initialTab: .github
  )
  .preferredColorScheme(.light)
}

#Preview("Settings Window - GitHub - Dark") {
  SettingsView(
    configStore: makePreviewStore(),
    tokenStore: makePreviewValidTokenStore(),
    snapshot: makePreviewSnapshot(),
    initialTab: .github
  )
  .preferredColorScheme(.dark)
}
