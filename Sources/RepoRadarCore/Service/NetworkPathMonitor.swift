import Foundation
import Network

/// Waits for a usable network path, so a refresh on wake doesn't fail while Wi-Fi reconnects.
public protocol NetworkPathMonitoring: Sendable {
  /// Returns once the network path is satisfied. Throws `CancellationError` if the task is
  /// cancelled first.
  func waitUntilSatisfied() async throws
}

/// `NWPathMonitor`-backed monitor. Each wait runs its own monitor and cancels it when done.
public struct SystemNetworkPathMonitor: NetworkPathMonitoring {
  public init() {}

  public func waitUntilSatisfied() async throws {
    let (statuses, continuation) = AsyncStream.makeStream(
      of: NWPath.Status.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { path in
      continuation.yield(path.status)
    }
    monitor.start(queue: DispatchQueue(label: "com.chriswander.reporadar.network-path"))
    defer {
      monitor.cancel()
      continuation.finish()
    }

    // The monitor reports the current path first, then every change.
    for await status in statuses where status == .satisfied {
      return
    }
    // The stream only ends without a satisfied path when the task is cancelled.
    throw CancellationError()
  }
}
