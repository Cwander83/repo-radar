import Foundation
import RepoRadarCore

/// Test double for `NetworkPathMonitoring`. Waits return at once while the path is satisfied;
/// otherwise they suspend until `satisfy()` runs or their task is cancelled.
public final class FakeNetworkPathMonitor: NetworkPathMonitoring, @unchecked Sendable {
  private let lock = NSLock()
  private var isSatisfied: Bool
  private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

  public struct TimeoutError: Error, LocalizedError {
    public var errorDescription: String? { "Timed out waiting for FakeNetworkPathMonitor waits." }
  }

  public init(isSatisfied: Bool = true) {
    self.isSatisfied = isSatisfied
  }

  public var pendingWaitCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return waiters.count
  }

  public func waitUntilSatisfied() async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        lock.lock()
        if Task.isCancelled {
          lock.unlock()
          continuation.resume(throwing: CancellationError())
          return
        }
        if isSatisfied {
          lock.unlock()
          continuation.resume()
          return
        }
        waiters.append((id: id, continuation: continuation))
        lock.unlock()
      }
    } onCancel: {
      lock.lock()
      let index = waiters.firstIndex { $0.id == id }
      let entry = index.map { waiters.remove(at: $0) }
      lock.unlock()
      entry?.continuation.resume(throwing: CancellationError())
    }
  }

  /// Marks the path satisfied and resumes every pending wait.
  public func satisfy() {
    lock.lock()
    isSatisfied = true
    let toResume = waiters.map(\.continuation)
    waiters.removeAll()
    lock.unlock()
    for continuation in toResume {
      continuation.resume()
    }
  }

  public func waitForPendingWaitCount(_ count: Int, timeoutSeconds: TimeInterval = 2.0) async throws {
    let start = Date()
    while Date().timeIntervalSince(start) < timeoutSeconds {
      if pendingWaitCount == count {
        return
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw TimeoutError()
  }
}
