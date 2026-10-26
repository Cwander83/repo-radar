import Foundation
import RepoRadarCore

/// Test double recording posted CI failure notifications and authorization requests.
public final class MockCINotificationManager: CINotificationManaging, @unchecked Sendable {
  private let lock = NSLock()
  private var _postedItems: [FailingCIItem] = []
  private var _authorizationRequestsCount: Int = 0
  public var authorizationResult: Bool

  public init(authorizationResult: Bool = true) {
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

  @discardableResult
  public func requestAuthorization() async -> Bool {
    withLock {
      _authorizationRequestsCount += 1
      return authorizationResult
    }
  }

  public func postNotification(for item: FailingCIItem) async throws {
    withLock {
      _postedItems.append(item)
    }
  }

  public func reset() {
    withLock {
      _postedItems.removeAll()
      _authorizationRequestsCount = 0
    }
  }
}
