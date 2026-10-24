import Foundation
import Testing

@testable import RepoRadarCore

struct SnapshotStoreTests {
  private func makeSampleSnapshot(
    status: SnapshotStatus = .ok,
    schemaVersion: Int = WidgetSnapshot.currentSchemaVersion
  ) -> WidgetSnapshot {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let failing = FailingCIItem(
      repo: "Cwander83/repo-radar",
      ref: "main",
      kind: .mainBranch,
      check: "Build",
      conclusion: "FAILURE",
      url: URL(string: "https://github.com/Cwander83/repo-radar/actions/runs/1"),
      startedAt: now.addingTimeInterval(-600),
      completedAt: now.addingTimeInterval(-300)
    )
    let running = RunningCIItem(
      repo: "Cwander83/repo-radar",
      ref: "develop",
      kind: .defaultBranch,
      check: "Test",
      status: "IN_PROGRESS",
      url: URL(string: "https://github.com/Cwander83/repo-radar/actions/runs/2"),
      startedAt: now.addingTimeInterval(-120)
    )
    let pr = ClassifiedPullRequest(
      repo: "Cwander83/repo-radar",
      number: 42,
      title: "Add widget snapshot store",
      url: URL(string: "https://github.com/Cwander83/repo-radar/pull/42")!,
      headRefName: "feature/snapshot",
      reason: .mine,
      authorLogin: "Cwander83",
      updatedAt: now.addingTimeInterval(-1800)
    )
    let stale = StaleBranchItem(
      repo: "Cwander83/repo-radar",
      branch: "old-experiment",
      ageDays: 45,
      lastCommitDate: now.addingTimeInterval(-45 * 86400),
      lastCommitOid: "abc1234def"
    )
    let rateLimit = SnapshotRateLimit(
      remaining: 4950,
      limit: 5000,
      resetAt: now.addingTimeInterval(3600),
      cost: 1
    )

    return WidgetSnapshot(
      schemaVersion: schemaVersion,
      updatedAt: now,
      status: status,
      failingCI: [failing],
      runningCI: [running],
      pullRequests: [pr],
      staleBranches: [stale],
      rateLimit: rateLimit
    )
  }

  @Test("Round-trip encoding and decoding preserves all snapshot data")
  func roundTripEncodingPreservesData() throws {
    let original = makeSampleSnapshot(status: .ok)
    let data = try RepoRadarEncoder.encode(original, prettyPrinted: true)
    let decoded = try RepoRadarDecoder.makeDecoder().decode(WidgetSnapshot.self, from: data)

    #expect(decoded.schemaVersion == original.schemaVersion)
    #expect(decoded.status == original.status)
    #expect(decoded.failingCI == original.failingCI)
    #expect(decoded.runningCI == original.runningCI)
    #expect(decoded.pullRequests == original.pullRequests)
    #expect(decoded.staleBranches == original.staleBranches)
    #expect(decoded.rateLimit == original.rateLimit)
    #expect(decoded.report.failingCI == original.failingCI)
  }

  @Test("Snapshot never serializes authentication tokens or secrets")
  func snapshotNeverContainsSecrets() throws {
    let snapshot = makeSampleSnapshot(status: .tokenError(detail: "Token expired"))
    let data = try RepoRadarEncoder.encode(snapshot, prettyPrinted: true)
    let jsonString = String(decoding: data, as: UTF8.self).lowercased()

    #expect(!jsonString.contains("token_value"))
    #expect(!jsonString.contains("bearer"))
    #expect(!jsonString.contains("authorization"))
    #expect(!jsonString.contains("password"))
  }

  @Test("SnapshotStatus Codable round-trips all status variants")
  func snapshotStatusRoundTrips() throws {
    let resetDate = Date(timeIntervalSince1970: 1_700_000_000)
    let cases: [SnapshotStatus] = [
      .ok,
      .offline(detail: "No internet connection"),
      .rateLimited(resetAt: resetDate, detail: "Primary rate limit hit"),
      .tokenError(detail: "PAT missing"),
      .serverError(detail: "502 Bad Gateway"),
      .missing,
      .corrupt(detail: "JSON parse error"),
      .unsupportedVersion(version: 2),
    ]

    let encoder = RepoRadarEncoder.makeEncoder()
    let decoder = RepoRadarDecoder.makeDecoder()

    for item in cases {
      let data = try encoder.encode(item)
      let decoded = try decoder.decode(SnapshotStatus.self, from: data)
      #expect(decoded == item)
    }
  }

  @Test("SnapshotStatus maps accurately from RepoRadarError")
  func snapshotStatusMapsFromRepoRadarError() {
    let reset = Date(timeIntervalSince1970: 1_700_000_000)

    #expect(
      SnapshotStatus(error: .tokenMissing)
        == .tokenError(detail: "GitHub personal access token missing"))
    #expect(
      SnapshotStatus(error: .tokenUnauthorized(detail: "Bad credentials"))
        == .tokenError(detail: "Bad credentials"))
    #expect(
      SnapshotStatus(error: .rateLimited(resetAt: reset))
        == .rateLimited(resetAt: reset, detail: "GitHub rate limit exceeded"))
    #expect(SnapshotStatus(error: .offline(detail: "Timeout")) == .offline(detail: "Timeout"))
    #expect(
      SnapshotStatus(error: .serverError(statusCode: 500, detail: "Internal error"))
        == .serverError(detail: "Internal error"))
    #expect(
      SnapshotStatus(error: .decodingError(detail: "keyNotFound"))
        == .corrupt(detail: "Failed to decode response: keyNotFound"))
  }

  @Test("Atomic write writes file and creates missing parent directory")
  func atomicWriteCreatesDirectoryAndFile() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("RepoRadarTest-\(UUID().uuidString)")
      .appendingPathComponent("nested-dir")
    defer {
      try? FileManager.default.removeItem(at: tempDir.deletingLastPathComponent())
    }

    let fileURL = tempDir.appendingPathComponent("snapshot.json")
    let store = SnapshotStore(fileURL: fileURL)
    let snapshot = makeSampleSnapshot(status: .ok)

    try store.write(snapshot)

    #expect(FileManager.default.fileExists(atPath: fileURL.path))
    let readSnapshot = try store.read()
    #expect(readSnapshot.schemaVersion == snapshot.schemaVersion)
    #expect(readSnapshot.status == .ok)
    #expect(readSnapshot.failingCI.count == 1)
  }

  @Test("Missing file maps to missing widget state without throwing on load()")
  func missingFileMapsToMissingWidgetState() {
    let missingURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("NonExistent-\(UUID().uuidString).json")
    let store = SnapshotStore(fileURL: missingURL)

    #expect(store.readResult() == .missing)

    let loaded = store.load()
    #expect(loaded.status == .missing)
    #expect(loaded.failingCI.isEmpty)
    #expect(loaded.pullRequests.isEmpty)
    #expect(loaded.staleBranches.isEmpty)

    #expect(throws: SnapshotStoreError.self) {
      try store.read()
    }
  }

  @Test("Corrupted JSON maps to corrupt widget state without throwing on load()")
  func corruptedFileMapsToCorruptWidgetState() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("RepoRadarTest-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let fileURL = tempDir.appendingPathComponent("corrupted.json")
    try "not-json-content{[[".write(to: fileURL, atomically: true, encoding: .utf8)

    let store = SnapshotStore(fileURL: fileURL)

    if case .corrupt = store.readResult() {
      // Expected
    } else {
      Issue.record("Expected .corrupt from readResult()")
    }

    let loaded = store.load()
    if case .corrupt(let detail) = loaded.status {
      #expect(!detail.isEmpty)
    } else {
      Issue.record("Expected .corrupt status in loaded snapshot")
    }

    #expect(throws: SnapshotStoreError.self) {
      try store.read()
    }
  }

  @Test("Empty (0 bytes) file maps to corrupt widget state")
  func emptyFileMapsToCorruptWidgetState() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("RepoRadarTest-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let fileURL = tempDir.appendingPathComponent("empty.json")
    try Data().write(to: fileURL)

    let store = SnapshotStore(fileURL: fileURL)

    #expect(store.readResult() == .corrupt(detail: "Snapshot file is empty (0 bytes)"))
    let loaded = store.load()
    #expect(loaded.status == .corrupt(detail: "Snapshot file is empty (0 bytes)"))
  }

  @Test("Future unknown schema version maps to unsupportedVersion widget state")
  func futureSchemaVersionMapsToUnsupportedVersion() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("RepoRadarTest-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let fileURL = tempDir.appendingPathComponent("future.json")

    // Write valid JSON with schemaVersion = 99
    let jsonFuture = """
      {
        "schemaVersion": 99,
        "updatedAt": "2026-10-24T12:00:00Z",
        "status": { "type": "ok" },
        "failingCI": [],
        "runningCI": [],
        "pullRequests": [],
        "staleBranches": []
      }
      """
    try jsonFuture.write(to: fileURL, atomically: true, encoding: .utf8)

    let store = SnapshotStore(fileURL: fileURL)

    #expect(store.readResult() == .unsupportedVersion(version: 99))

    let loaded = store.load()
    #expect(loaded.status == .unsupportedVersion(version: 99))

    #expect(throws: SnapshotStoreError.unsupportedSchemaVersion(99)) {
      try store.read()
    }
  }

  @Test("App Group container error when group identifier is unavailable")
  func appGroupContainerUnavailableThrowsError() {
    let invalidGroupID = ""
    #expect(SnapshotStore(appGroupIdentifier: invalidGroupID) == nil)

    #expect(throws: SnapshotStoreError.appGroupContainerNotFound(invalidGroupID)) {
      try SnapshotStore.appGroup(identifier: invalidGroupID)
    }
  }
}
