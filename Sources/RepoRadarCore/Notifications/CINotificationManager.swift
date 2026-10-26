import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Protocol abstracting local notification management for CI failures.
public protocol CINotificationManaging: Sendable {
  /// Requests user authorization to display local notifications.
  @discardableResult
  func requestAuthorization() async -> Bool

  /// Posts a local notification for a newly failing CI check.
  func postNotification(for item: FailingCIItem) async throws
}

extension CINotificationManaging {
  /// Convenience helper to post notifications for multiple newly failing CI checks.
  public func postNotifications(for items: [FailingCIItem]) async throws {
    for item in items {
      try await postNotification(for: item)
    }
  }
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

  @discardableResult
  public func requestAuthorization() async -> Bool {
    guard let center = centerProvider() else { return false }
    do {
      return try await center.requestAuthorization(options: [.alert, .sound, .badge])
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
      "targetURL": targetURL.absoluteString,
      "repo": item.repo,
      "ref": item.ref,
      "check": item.check
    ]

    let request = UNNotificationRequest(
      identifier: "ci-failure-\(item.id)",
      content: content,
      trigger: nil
    )
    try await center.add(request)
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
