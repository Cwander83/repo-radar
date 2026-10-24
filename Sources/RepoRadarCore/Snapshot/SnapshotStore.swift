import Foundation

/// Errors that can occur during snapshot storage and retrieval.
public enum SnapshotStoreError: Error, Sendable, Equatable, CustomStringConvertible {
  case appGroupContainerNotFound(String)
  case fileNotFound(URL)
  case corrupted(String)
  case unsupportedSchemaVersion(Int)
  case writeFailed(String)

  public var description: String {
    switch self {
    case .appGroupContainerNotFound(let identifier):
      return "App Group container not found for identifier: \(identifier)"
    case .fileNotFound(let url):
      return "Snapshot file not found at: \(url.path)"
    case .corrupted(let detail):
      return "Snapshot corrupted: \(detail)"
    case .unsupportedSchemaVersion(let version):
      return
        "Unsupported snapshot schema version \(version) (expected \(WidgetSnapshot.currentSchemaVersion))"
    case .writeFailed(let detail):
      return "Failed to write snapshot: \(detail)"
    }
  }
}

/// Explicit result of reading a snapshot from storage.
public enum SnapshotReadResult: Sendable, Equatable {
  case success(WidgetSnapshot)
  case missing
  case corrupt(detail: String)
  case unsupportedVersion(version: Int)
}

/// Helper struct to inspect schema version before full decode.
private struct SnapshotVersionHeader: Decodable {
  let schemaVersion: Int
}

/// Manages reading and writing widget snapshots in the shared App Group container.
public struct SnapshotStore: Sendable {
  /// Default macOS App Group container identifier.
  public static let defaultAppGroupIdentifier = "7P5RMM8JP7.com.chriswander.reporadar"

  /// Default snapshot filename within the App Group container.
  public static let defaultFilename = "snapshot.json"

  /// Target file URL for the snapshot.
  public let fileURL: URL

  /// Resolves the URL for an App Group container.
  public static func appGroupContainerURL(
    identifier: String = defaultAppGroupIdentifier,
    fileManager: FileManager = .default
  ) -> URL? {
    guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
  }

  /// Resolves the full URL for the snapshot file inside an App Group container.
  public static func snapshotURL(
    appGroupIdentifier: String = defaultAppGroupIdentifier,
    filename: String = defaultFilename,
    fileManager: FileManager = .default
  ) -> URL? {
    guard
      let container = appGroupContainerURL(identifier: appGroupIdentifier, fileManager: fileManager)
    else {
      return nil
    }
    return container.appendingPathComponent(filename, isDirectory: false)
  }

  /// Creates a store with an explicit file URL.
  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  /// Creates a store targeting an App Group container, returning nil if container cannot be resolved.
  public init?(
    appGroupIdentifier: String = defaultAppGroupIdentifier,
    filename: String = defaultFilename,
    fileManager: FileManager = .default
  ) {
    guard
      let url = Self.snapshotURL(
        appGroupIdentifier: appGroupIdentifier,
        filename: filename,
        fileManager: fileManager
      )
    else {
      return nil
    }
    self.fileURL = url
  }

  /// Creates a store targeting an App Group container or throws if container is unavailable.
  public static func appGroup(
    identifier: String = defaultAppGroupIdentifier,
    filename: String = defaultFilename,
    fileManager: FileManager = .default
  ) throws -> SnapshotStore {
    guard
      let store = SnapshotStore(
        appGroupIdentifier: identifier,
        filename: filename,
        fileManager: fileManager
      )
    else {
      throw SnapshotStoreError.appGroupContainerNotFound(identifier)
    }
    return store
  }

  /// Atomically writes a snapshot to disk.
  public func write(_ snapshot: WidgetSnapshot) throws {
    let encoder = RepoRadarEncoder.makeEncoder(prettyPrinted: true)
    let data: Data
    do {
      data = try encoder.encode(snapshot)
    } catch {
      throw SnapshotStoreError.writeFailed(
        "Failed to encode snapshot: \(error.localizedDescription)")
    }

    let directory = fileURL.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(to: fileURL, options: [.atomic])
    } catch {
      throw SnapshotStoreError.writeFailed(
        "Failed to write data to \(fileURL.path): \(error.localizedDescription)")
    }
  }

  /// Reads and parses the snapshot, throwing typed errors if missing, corrupt, or unsupported.
  public func read() throws -> WidgetSnapshot {
    switch readResult() {
    case .success(let snapshot):
      return snapshot
    case .missing:
      throw SnapshotStoreError.fileNotFound(fileURL)
    case .corrupt(let detail):
      throw SnapshotStoreError.corrupted(detail)
    case .unsupportedVersion(let version):
      throw SnapshotStoreError.unsupportedSchemaVersion(version)
    }
  }

  /// Reads the snapshot with explicit outcome classification.
  public func readResult() -> SnapshotReadResult {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return .missing
    }

    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      return .corrupt(detail: "Unable to read file: \(error.localizedDescription)")
    }

    guard !data.isEmpty else {
      return .corrupt(detail: "Snapshot file is empty (0 bytes)")
    }

    let decoder = RepoRadarDecoder.makeDecoder()
    if let header = try? decoder.decode(SnapshotVersionHeader.self, from: data) {
      if header.schemaVersion > WidgetSnapshot.currentSchemaVersion {
        return .unsupportedVersion(version: header.schemaVersion)
      }
    }

    do {
      let snapshot = try decoder.decode(WidgetSnapshot.self, from: data)
      return .success(snapshot)
    } catch {
      return .corrupt(detail: error.localizedDescription)
    }
  }

  /// Loads the current snapshot for widget rendering, mapping missing or corrupted states to fallback snapshots.
  public func load() -> WidgetSnapshot {
    switch readResult() {
    case .success(let snapshot):
      return snapshot
    case .missing:
      return WidgetSnapshot.empty(status: .missing)
    case .corrupt(let detail):
      return WidgetSnapshot.empty(status: .corrupt(detail: detail))
    case .unsupportedVersion(let version):
      return WidgetSnapshot.empty(status: .unsupportedVersion(version: version))
    }
  }
}
