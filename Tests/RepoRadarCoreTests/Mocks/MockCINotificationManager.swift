import Foundation
import RepoRadarCore

/// Test double recording posted CI failure notifications, authorization requests, and settings actions.
public final class MockCINotificationManager: CINotificationManaging, @unchecked Sendable {
  private let lock = NSLock()
  private var _postedItems: [FailingCIItem] = []
  private var _authorizationRequestsCount: Int = 0
  private var _openSettingsCount: Int = 0
  public var currentStatus: CINotificationAuthorizationStatus
  public var authorizationResult: Bool

  public init(
    status: CINotificationAuthorizationStatus = .notDetermined,
    authorizationResult: Bool = true
  ) {
    self.currentStatus = status
    self.authorizationResult = authorizationResult
  }

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  public var postedItems: [FailingCIItem] {
    withLock { _postedItems }
  }

  public var authorizationRequestsCount: Int {
    withLock { _authorizationRequestsCount }
  }

  public var openSettingsCount: Int {
    withLock { _openSettingsCount }
  }

  public func authorizationStatus() async -> CINotificationAuthorizationStatus {
    withLock { currentStatus }
  }

  @discardableResult
  public func requestAuthorization() async -> Bool {
    withLock {
      _authorizationRequestsCount += 1
      if !authorizationResult {
        currentStatus = .denied
      } else {
        currentStatus = .authorized
      }
      return authorizationResult
    }
  }

  public func postNotification(for item: FailingCIItem) async throws {
    withLock {
      _postedItems.append(item)
    }
  }

  public func openSystemSettingsNotifications() {
    withLock {
      _openSettingsCount += 1
    }
  }

  public func reset() {
    withLock {
      _postedItems.removeAll()
      _authorizationRequestsCount = 0
      _openSettingsCount = 0
    }
  }
}
