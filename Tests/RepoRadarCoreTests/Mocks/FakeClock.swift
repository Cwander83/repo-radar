import Foundation
import RepoRadarCore

public final class FakeClock: ClockProtocol, @unchecked Sendable {
  private let lock = NSLock()
  private var _now: Date
  private var scheduled: [(deadline: Date, continuation: CheckedContinuation<Void, Error>)] = []
  private var _sleepCallCount: Int = 0
  private var _lastSleepRequestedDuration: TimeInterval?

  public struct TimeoutError: Error, LocalizedError {
    public var errorDescription: String? { "Timed out waiting for FakeClock sleep registration." }
  }

  public init(now: Date = Date(timeIntervalSince1970: 1700000000)) {
    self._now = now
  }

  public var now: Date {
    lock.lock()
    defer { lock.unlock() }
    return _now
  }

  public var sleepCallCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return _sleepCallCount
  }

  public var lastSleepRequestedDuration: TimeInterval? {
    lock.lock()
    defer { lock.unlock() }
    return _lastSleepRequestedDuration
  }

  public func sleep(seconds: TimeInterval) async throws {
    try await withCheckedThrowingContinuation { continuation in
      lock.lock()
      _sleepCallCount += 1
      _lastSleepRequestedDuration = seconds
      let deadline = _now.addingTimeInterval(seconds)
      scheduled.append((deadline: deadline, continuation: continuation))
      scheduled.sort { $0.deadline < $1.deadline }
      lock.unlock()
    }
  }

  public func advance(by seconds: TimeInterval) {
    lock.lock()
    _now = _now.addingTimeInterval(seconds)
    var toResume: [CheckedContinuation<Void, Error>] = []
    while let first = scheduled.first, first.deadline <= _now {
      toResume.append(first.continuation)
      scheduled.removeFirst()
    }
    lock.unlock()

    for cont in toResume {
      cont.resume()
    }
  }

  public func pendingSleepCount() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return scheduled.count
  }

  public func waitForSleepCalls(count: Int, timeoutSeconds: TimeInterval = 2.0) async throws {
    let start = Date()
    while Date().timeIntervalSince(start) < timeoutSeconds {
      if sleepCallCount >= count {
        return
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw TimeoutError()
  }

  public func cancelAll() {
    lock.lock()
    let toCancel = scheduled
    scheduled.removeAll()
    lock.unlock()
    for item in toCancel {
      item.continuation.resume(throwing: CancellationError())
    }
  }
}
