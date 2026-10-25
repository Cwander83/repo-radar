import Foundation
#if canImport(ServiceManagement)
import ServiceManagement
#endif

/// Represents the registration state of the application as a login item.
public enum LaunchAtLoginStatus: String, Sendable, Equatable, CaseIterable {
  case enabled
  case notRegistered
  case requiresApproval
  case notFound

  public var displayName: String {
    switch self {
    case .enabled:
      return "Enabled"
    case .notRegistered:
      return "Not Registered"
    case .requiresApproval:
      return "Requires Approval"
    case .notFound:
      return "Not Found"
    }
  }

  /// Whether the General tab shows the toggle as on. `.requiresApproval` counts as on:
  /// the app is registered and only waiting for the user to approve it in System Settings.
  public var isOn: Bool {
    self == .enabled || self == .requiresApproval
  }
}

/// Protocol abstracting login item management for the host app.
public protocol LaunchAtLoginManaging: Sendable {
  /// The current login item status.
  var status: LaunchAtLoginStatus { get }

  /// Registers or unregisters the app as a login item.
  func setEnabled(_ enabled: Bool) throws

  /// Opens the macOS Login Items system settings pane.
  func openSystemSettingsLoginItems()
}

/// Production implementation of LaunchAtLoginManaging backed by SMAppService.mainApp.
public final class AppServiceLaunchAtLoginManager: LaunchAtLoginManaging, Sendable {
  public init() {}

  public var status: LaunchAtLoginStatus {
    #if os(macOS)
    let serviceStatus = SMAppService.mainApp.status
    switch serviceStatus {
    case .enabled:
      return .enabled
    case .notRegistered:
      return .notRegistered
    case .requiresApproval:
      return .requiresApproval
    case .notFound:
      return .notFound
    @unknown default:
      return .notRegistered
    }
    #else
    return .notRegistered
    #endif
  }

  public func setEnabled(_ enabled: Bool) throws {
    #if os(macOS)
    let service = SMAppService.mainApp
    if enabled {
      if service.status != .enabled {
        try service.register()
      }
    } else {
      if service.status == .enabled || service.status == .requiresApproval {
        try service.unregister()
      }
    }
    #endif
  }

  public func openSystemSettingsLoginItems() {
    #if os(macOS)
    SMAppService.openSystemSettingsLoginItems()
    #endif
  }
}

/// In-memory implementation of LaunchAtLoginManaging for unit testing and SwiftUI previews.
public final class InMemoryLaunchAtLoginManager: LaunchAtLoginManaging, @unchecked Sendable {
  public var status: LaunchAtLoginStatus
  public var setEnabledError: (any Error)?
  public private(set) var openSettingsCallCount = 0
  public private(set) var setEnabledCallCount = 0

  public init(status: LaunchAtLoginStatus = .notRegistered) {
    self.status = status
  }

  public func setEnabled(_ enabled: Bool) throws {
    setEnabledCallCount += 1
    if let error = setEnabledError {
      throw error
    }
    status = enabled ? .enabled : .notRegistered
  }

  public func openSystemSettingsLoginItems() {
    openSettingsCallCount += 1
  }
}
