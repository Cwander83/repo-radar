import Foundation

/// Abstracts time and sleeping for testable schedulers.
public protocol ClockProtocol: Sendable {
  /// Current date and time.
  var now: Date { get }

  /// Suspends the current task for the specified duration in seconds.
  func sleep(seconds: TimeInterval) async throws
}

/// Standard system clock using `Date()` and `Task.sleep`.
public struct SystemClock: ClockProtocol {
  public init() {}

  public var now: Date { Date() }

  public func sleep(seconds: TimeInterval) async throws {
    guard seconds > 0 else { return }
    let nanos = UInt64(seconds * 1_000_000_000)
    try await Task.sleep(nanoseconds: nanos)
  }
}
