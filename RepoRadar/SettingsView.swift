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
  public let launchAtLoginManager: any LaunchAtLoginManaging
  public let snapshot: WidgetSnapshot?
  public let snapshotPublisher: AnyPublisher<WidgetSnapshot?, Never>?
  public var onConfigChange: ((RepoRadarConfig) -> Void)?
  public var onRefreshRequest: (() -> Void)?

  public init(
    configStore: ConfigStore,
    tokenStore: any TokenStore,
    launchAtLoginManager: any LaunchAtLoginManaging = AppServiceLaunchAtLoginManager(),
    snapshot: WidgetSnapshot? = nil,
    snapshotPublisher: AnyPublisher<WidgetSnapshot?, Never>? = nil,
    initialTab: SettingsTab = .general,
    onConfigChange: ((RepoRadarConfig) -> Void)? = nil,
    onRefreshRequest: (() -> Void)? = nil
  ) {
    self.configStore = configStore
    self.tokenStore = tokenStore
    self.launchAtLoginManager = launchAtLoginManager
    self.snapshot = snapshot
    self.snapshotPublisher = snapshotPublisher
    self._selectedTab = State(initialValue: initialTab)
    self.onConfigChange = onConfigChange
    self.onRefreshRequest = onRefreshRequest
  }

  public init(
    configStore: ConfigStore,
    scheduler: RefreshScheduler,
    launchAtLoginManager: any LaunchAtLoginManaging = AppServiceLaunchAtLoginManager(),
    initialTab: SettingsTab = .general,
    onConfigChange: ((RepoRadarConfig) -> Void)? = nil,
    onRefreshRequest: (() -> Void)? = nil
  ) {
    self.init(
      configStore: configStore,
      tokenStore: scheduler.service.tokenStore,
      launchAtLoginManager: launchAtLoginManager,
      snapshot: scheduler.latestSnapshot,
      snapshotPublisher: scheduler.$latestSnapshot.eraseToAnyPublisher(),
      initialTab: initialTab,
      onConfigChange: onConfigChange,
      onRefreshRequest: onRefreshRequest
    )
  }

  public var body: some View {
    TabView(selection: $selectedTab) {
      GeneralSettingsView(
        configStore: configStore,
        launchAtLoginManager: launchAtLoginManager,
        onConfigChange: onConfigChange
      )
        .tabItem {
          Label(SettingsTab.general.title, systemImage: SettingsTab.general.systemImage)
        }
        .tag(SettingsTab.general)

      RepositoriesSettingsView(
        configStore: configStore,
        tokenStore: tokenStore,
        snapshot: snapshot,
        snapshotPublisher: snapshotPublisher,
        onNavigateToGitHub: { selectedTab = .github },
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
    launchAtLoginManager: any LaunchAtLoginManaging = AppServiceLaunchAtLoginManager(),
    onConfigChange: ((RepoRadarConfig) -> Void)? = nil
  ) {
    self._viewModel = StateObject(
      wrappedValue: GeneralSettingsViewModel(
        configStore: configStore,
        launchAtLoginManager: launchAtLoginManager,
        onConfigChange: onConfigChange
      )
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

        if viewModel.launchAtLoginStatus == .requiresApproval {
          HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
            Text("Requires approval in System Settings")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button("Open Settings") {
              viewModel.openSystemSettingsLoginItems()
            }
            .buttonStyle(.link)
            .font(.caption)
          }
        }

        if let error = viewModel.launchAtLoginError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }

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
    .onAppear {
      viewModel.refreshLaunchAtLoginStatus()
    }
  }
}

/// Repositories settings tab displaying watched repositories, reachability, access statuses, and stale threshold.
public struct RepositoriesSettingsView: View {
  @StateObject private var viewModel: RepositoriesSettingsViewModel
  private let snapshot: WidgetSnapshot?
  public var onNavigateToGitHub: (() -> Void)?
  @State private var isPickerPresented: Bool = false

  public init(
    viewModel: RepositoriesSettingsViewModel,
    snapshot: WidgetSnapshot? = nil,
    onNavigateToGitHub: (() -> Void)? = nil
  ) {
    self._viewModel = StateObject(wrappedValue: viewModel)
    self.snapshot = snapshot
    self.onNavigateToGitHub = onNavigateToGitHub
  }

  public init(
    configStore: ConfigStore,
    tokenStore: (any TokenStore)? = nil,
    snapshot: WidgetSnapshot? = nil,
    snapshotPublisher: AnyPublisher<WidgetSnapshot?, Never>? = nil,
    onNavigateToGitHub: (() -> Void)? = nil,
    onConfigChange: ((RepoRadarConfig) -> Void)? = nil,
    onRefreshRequest: (() -> Void)? = nil
  ) {
    self.snapshot = snapshot
    self.onNavigateToGitHub = onNavigateToGitHub
    self._viewModel = StateObject(
      wrappedValue: RepositoriesSettingsViewModel(
        configStore: configStore,
        tokenStore: tokenStore,
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
        HStack(spacing: 8) {
          Button("Choose repositories…") {
            isPickerPresented = true
          }
          .disabled(!viewModel.hasToken)

          if !viewModel.hasToken {
            Text("Add a GitHub token first")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)

            Button("GitHub tab") {
              onNavigateToGitHub?()
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
          }
        }
        .padding(.vertical, 2)

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
    .sheet(isPresented: $isPickerPresented) {
      RepositoryPickerSheet(viewModel: viewModel.makePickerViewModel())
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
    configStore: ConfigStore,
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

/// Sheet modal for picking repositories to watch from GitHub token permissions.
public struct RepositoryPickerSheet: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject public var viewModel: RepositoryPickerViewModel

  public init(viewModel: RepositoryPickerViewModel) {
    self._viewModel = StateObject(wrappedValue: viewModel)
  }

  public var body: some View {
    VStack(spacing: 0) {
      headerSection
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)

      Divider()

      controlsBar
        .padding(.horizontal, 20)
        .padding(.vertical, 10)

      if viewModel.isAtCap {
        capBanner
          .padding(.horizontal, 20)
          .padding(.bottom, 8)
      }

      Divider()

      contentArea
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      Divider()

      footerBar
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    .frame(width: 520, height: 480)
    .task {
      await viewModel.loadRepositories()
    }
  }

  private var headerSection: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("Choose Repositories")
          .font(.headline)
        Text("Select repositories to monitor on your desktop widget.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text(viewModel.selectionCounterText)
        .font(.system(size: 12, weight: viewModel.isAtCap ? .semibold : .regular))
        .foregroundStyle(viewModel.isAtCap ? .orange : .secondary)
    }
  }

  private var controlsBar: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField("Filter repositories…", text: $viewModel.searchQuery)
          .textFieldStyle(.plain)
          .font(.system(size: 13))
        if !viewModel.searchQuery.isEmpty {
          Button {
            viewModel.searchQuery = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(6)
      .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))

      HStack {
        Button("Select all") {
          viewModel.selectAll()
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(Color.accentColor)
        .disabled(viewModel.isLoading || viewModel.allRepositories.isEmpty)

        Text("•")
          .font(.system(size: 10))
          .foregroundStyle(.secondary)

        Button("Select none") {
          viewModel.selectNone()
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .disabled(viewModel.isLoading || viewModel.selectedRepos.isEmpty)

        Spacer()

        Toggle("Show archived", isOn: $viewModel.showArchived)
          .toggleStyle(.checkbox)
          .font(.system(size: 11))
      }
    }
  }

  private var capBanner: some View {
    HStack(spacing: 6) {
      Image(systemName: "info.circle.fill")
        .foregroundStyle(.orange)
      Text(viewModel.capExplanation)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(8)
    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
  }

  private var contentArea: some View {
    Group {
      if viewModel.isLoading {
        VStack(spacing: 12) {
          ProgressView()
          Text("Loading repositories from GitHub…")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let error = viewModel.errorMessage {
        VStack(spacing: 12) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.title2)
            .foregroundStyle(.red)
          Text(error)
            .font(.system(size: 12))
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)
            .padding(.horizontal, 32)
          Button("Try Again") {
            Task {
              await viewModel.loadRepositories()
            }
          }
          .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if viewModel.isZeroRepos {
        VStack(spacing: 10) {
          Image(systemName: "lock.shield")
            .font(.system(size: 28))
            .foregroundStyle(.secondary)
          Text("This token can't read any repositories")
            .font(.system(size: 13, weight: .medium))
          Text("Make sure your fine-grained token has repository access permissions.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
          Link("Edit token on GitHub ↗", destination: URL(string: "https://github.com/settings/tokens")!)
            .font(.system(size: 12))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if viewModel.visibleRepositories.isEmpty {
        VStack(spacing: 8) {
          Text("No matching repositories")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
          if !viewModel.searchQuery.isEmpty {
            Text("No repositories match “\(viewModel.searchQuery)”")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(viewModel.visibleRepositories) { repo in
              repositoryPickerRow(repo)
              Divider()
                .padding(.leading, 36)
            }
          }
        }
      }
    }
  }

  private func repositoryPickerRow(_ repo: ViewerRepositoryNode) -> some View {
    let isSelected = viewModel.isSelected(repo.nameWithOwner)
    let canToggle = viewModel.canToggle(repo.nameWithOwner)

    return Button {
      viewModel.toggleSelection(repo.nameWithOwner)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
          .font(.system(size: 14))
          .foregroundStyle(isSelected ? Color.accentColor : (canToggle ? Color.secondary : Color.secondary.opacity(0.4)))

        repoNameFormatted(repo.nameWithOwner)

        if repo.isPrivate {
          Image(systemName: "lock.fill")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .help("Private repository")
        }

        if repo.isArchived {
          Text("Archived")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
        }

        Spacer()

        if let pushed = repo.pushedAt {
          Text("pushed \(WidgetSnapshot.relativeTimeString(from: pushed))")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 7)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!canToggle)
    .opacity(canToggle ? 1.0 : 0.6)
  }

  private func repoNameFormatted(_ name: String) -> some View {
    let parts = name.split(separator: "/", maxSplits: 1)
    return HStack(spacing: 0) {
      if parts.count == 2 {
        Text("\(parts[0])/")
          .foregroundStyle(.secondary)
        Text(parts[1])
          .fontWeight(.bold)
          .foregroundStyle(.primary)
      } else {
        Text(name)
          .fontWeight(.bold)
          .foregroundStyle(.primary)
      }
    }
    .font(.system(size: 12))
    .lineLimit(1)
    .truncationMode(.tail)
  }

  private var footerBar: some View {
    HStack {
      Button("Cancel") {
        dismiss()
      }
      .keyboardShortcut(.cancelAction)

      Spacer()

      Button("Save") {
        viewModel.save()
        dismiss()
      }
      .buttonStyle(.borderedProminent)
      .disabled(viewModel.isLoading)
      .keyboardShortcut(.defaultAction)
    }
  }
}

// MARK: - Previews

private func makePreviewStore() -> ConfigStore {
  let suite = "reporadar.preview.settings"
  let defaults = UserDefaults(suiteName: suite)!
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
  GeneralSettingsView(
    configStore: makePreviewStore(),
    launchAtLoginManager: InMemoryLaunchAtLoginManager(status: .enabled)
  )
  .preferredColorScheme(.light)
}

#Preview("General Settings - Dark") {
  GeneralSettingsView(
    configStore: makePreviewStore(),
    launchAtLoginManager: InMemoryLaunchAtLoginManager(status: .enabled)
  )
  .preferredColorScheme(.dark)
}

#Preview("General Settings - Requires Approval") {
  GeneralSettingsView(
    configStore: makePreviewStore(),
    launchAtLoginManager: InMemoryLaunchAtLoginManager(status: .requiresApproval)
  )
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
    tokenStore: makePreviewValidTokenStore(),
    launchAtLoginManager: InMemoryLaunchAtLoginManager(status: .enabled),
    snapshot: makePreviewSnapshot(),
    initialTab: .repositories
  )
  .preferredColorScheme(.light)
}

#Preview("Settings Window - Repositories - Dark") {
  SettingsView(
    configStore: makePreviewStore(),
    tokenStore: makePreviewValidTokenStore(),
    launchAtLoginManager: InMemoryLaunchAtLoginManager(status: .enabled),
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

@MainActor
private func makePreviewPickerVM(
  repos: [ViewerRepositoryNode] = [
    ViewerRepositoryNode(
      nameWithOwner: "Cwander83/repo-radar",
      isPrivate: false,
      isArchived: false,
      pushedAt: Date().addingTimeInterval(-3600),
      defaultBranchRef: RefBranch(name: "develop")
    ),
    ViewerRepositoryNode(
      nameWithOwner: "Cwander83/gravity-bar",
      isPrivate: false,
      isArchived: false,
      pushedAt: Date().addingTimeInterval(-86400 * 3),
      defaultBranchRef: RefBranch(name: "main")
    ),
    ViewerRepositoryNode(
      nameWithOwner: "Cwander83/secret-project",
      isPrivate: true,
      isArchived: false,
      pushedAt: Date().addingTimeInterval(-86400 * 7),
      defaultBranchRef: RefBranch(name: "main")
    ),
    ViewerRepositoryNode(
      nameWithOwner: "Cwander83/old-experiment",
      isPrivate: false,
      isArchived: true,
      pushedAt: Date().addingTimeInterval(-86400 * 90),
      defaultBranchRef: RefBranch(name: "master")
    )
  ],
  isLoading: Bool = false,
  errorMessage: String? = nil,
  isZeroRepos: Bool = false
) -> RepositoryPickerViewModel {
  let store = makePreviewStore()
  let vm = RepositoryPickerViewModel(
    configStore: store,
    tokenStore: makePreviewValidTokenStore(),
    fetcher: { repos }
  )
  vm.allRepositories = repos
  vm.isLoading = isLoading
  vm.errorMessage = errorMessage
  vm.isZeroRepos = isZeroRepos
  return vm
}

#Preview("Repository Picker - Loaded - Light") {
  RepositoryPickerSheet(viewModel: makePreviewPickerVM())
    .preferredColorScheme(.light)
}

#Preview("Repository Picker - Loaded - Dark") {
  RepositoryPickerSheet(viewModel: makePreviewPickerVM())
    .preferredColorScheme(.dark)
}

#Preview("Repository Picker - Zero Repos") {
  RepositoryPickerSheet(viewModel: makePreviewPickerVM(repos: [], isZeroRepos: true))
    .preferredColorScheme(.dark)
}

#Preview("Repository Picker - Error") {
  RepositoryPickerSheet(viewModel: makePreviewPickerVM(repos: [], errorMessage: "GitHub authentication failed: Bad credentials"))
    .preferredColorScheme(.dark)
}

