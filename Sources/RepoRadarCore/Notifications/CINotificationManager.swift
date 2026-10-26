import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Notification authorization states.
public enum CINotificationAuthorizationStatus: String, Sendable, Equatable {
  case notDetermined
  case authorized
  case denied
}

/// Protocol abstracting local notification management for CI failures.
public protocol CINotificationManaging: Sendable {
  /// Returns the current notification authorization status.
  func authorizationStatus() async -> CINotificationAuthorizationStatus

  /// Requests user authorization to display local notifications.
  @discardableResult
  func requestAuthorization() async -> Bool

  /// Posts a local notification for a newly failing CI check.
  func postNotification(for item: FailingCIItem) async throws

  /// Opens macOS System Settings -> Notifications.
  func openSystemSettingsNotifications()
}

/// Production implementation of `CINotificationManaging` backed by Apple's `UserNotifications` framework.
public final class SystemCINotificationManager: NSObject, CINotificationManaging, @unchecked Sendable {
  private let centerProvider: @Sendable () -> UNUserNotificationCenter?

  public init(
    centerProvider: @escaping @Sendable () -> UNUserNotificationCenter? = {
      // Avoid calling UNUserNotificationCenter.current() in CLI test environments where bundle proxy is missing.
      guard Bundle.main.bundleIdentifier != nil else { return nil }
      return UNUserNotificationCenter.current()
    }
  ) {
    self.centerProvider = centerProvider
    super.init()
  }

  public func authorizationStatus() async -> CINotificationAuthorizationStatus {
    guard let center = centerProvider() else { return .notDetermined }
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .notDetermined:
      return .notDetermined
    case .denied:
      return .denied
    case .authorized, .provisional, .ephemeral:
      return .authorized
    @unknown default:
      return .notDetermined
    }
  }

  @discardableResult
  public func requestAuthorization() async -> Bool {
    guard let center = centerProvider() else { return false }
    do {
      return try await center.requestAuthorization(options: [.alert, .sound])
    } catch {
      return false
    }
  }

  public func postNotification(for item: FailingCIItem) async throws {
    guard let center = centerProvider() else { return }

    let content = UNMutableNotificationContent()
    content.title = item.repo
    content.subtitle = item.ref
    content.body = "\(item.check) failed"
    content.sound = .default

    let targetURL = WidgetGitHubURL.url(for: item)
    content.userInfo = [
      "targetURL": targetURL.absoluteString
    ]

    let request = UNNotificationRequest(
      identifier: "ci-failure-\(item.id)",
      content: content,
      trigger: nil
    )
    try await center.add(request)
  }

  public func openSystemSettingsNotifications() {
    #if canImport(AppKit)
    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"),
       NSWorkspace.shared.open(url) {
      return
    }
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
      NSWorkspace.shared.open(url)
    }
    #endif
  }
}

/// UserNotificationCenter delegate handling notification actions and banner presentation.
public final class CINotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  public let openURL: @Sendable (URL) -> Void

  public init(
    openURL: @escaping @Sendable (URL) -> Void = { url in
      #if canImport(AppKit)
      NSWorkspace.shared.open(url)
      #endif
    }
  ) {
    self.openURL = openURL
    super.init()
  }

  /// Processes notification response userInfo and opens the GitHub run URL.
  @discardableResult
  public func handleNotificationResponse(userInfo: [AnyHashable: Any]) -> Bool {
    guard
      let urlString = userInfo["targetURL"] as? String,
      let url = URL(string: urlString)
    else {
      return false
    }
    openURL(url)
    return true
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    handleNotificationResponse(userInfo: response.notification.request.content.userInfo)
    completionHandler()
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
}
