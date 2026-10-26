import Foundation
import Testing

@testable import RepoRadarCore

@Suite("CINotificationManagerTests")
struct CINotificationManagerTests {
  private final class URLRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _openedURL: URL?
    private var _openedCount: Int = 0

    var openedURL: URL? {
      lock.lock()
      defer { lock.unlock() }
      return _openedURL
    }

    var openedCount: Int {
      lock.lock()
      defer { lock.unlock() }
      return _openedCount
    }

    func record(_ url: URL) {
      lock.lock()
      defer { lock.unlock() }
      _openedURL = url
      _openedCount += 1
    }
  }

  @Test("CINotificationDelegate opens targetURL when notification is clicked")
  func notificationDelegateOpensTargetURL() {
    let recorder = URLRecorder()
    let delegate = CINotificationDelegate { url in
      recorder.record(url)
    }

    let target = URL(string: "https://github.com/Cwander83/repo-radar/actions/runs/123456")!
    let userInfo: [AnyHashable: Any] = [
      "targetURL": target.absoluteString,
      "repo": "Cwander83/repo-radar",
      "ref": "main",
      "check": "test"
    ]

    let handled = delegate.handleNotificationResponse(userInfo: userInfo)
    #expect(handled == true)
    #expect(recorder.openedURL == target)
    #expect(recorder.openedCount == 1)
  }

  @Test("CINotificationDelegate ignores responses missing valid targetURL")
  func notificationDelegateIgnoresInvalidUserInfo() {
    let recorder = URLRecorder()
    let delegate = CINotificationDelegate { url in
      recorder.record(url)
    }

    let handledMissing = delegate.handleNotificationResponse(userInfo: ["repo": "Cwander83/repo-radar"])
    #expect(handledMissing == false)
    #expect(recorder.openedCount == 0)

    let handledNonString = delegate.handleNotificationResponse(userInfo: ["targetURL": 12345])
    #expect(handledNonString == false)
    #expect(recorder.openedCount == 0)
  }

  @Test("MockCINotificationManager records items and authorization requests")
  func mockNotificationManagerRecordsCorrectly() async throws {
    let mock = MockCINotificationManager(authorizationResult: true)
    #expect(mock.authorizationRequestsCount == 0)
    #expect(mock.postedItems.isEmpty)

    let authorized = await mock.requestAuthorization()
    #expect(authorized == true)
    #expect(mock.authorizationRequestsCount == 1)

    let item1 = FailingCIItem(
      repo: "Cwander83/repo-radar",
      ref: "main",
      kind: .defaultBranch,
      check: "build",
      conclusion: "failure",
      url: URL(string: "https://github.com/Cwander83/repo-radar/actions/runs/1")
    )
    let item2 = FailingCIItem(
      repo: "Cwander83/repo-radar",
      ref: "#42 feat/cool",
      kind: .myPullRequest,
      check: "lint",
      conclusion: "failure",
      url: URL(string: "https://github.com/Cwander83/repo-radar/actions/runs/2")
    )

    try await mock.postNotification(for: item1)
    try await mock.postNotification(for: item2)

    #expect(mock.postedItems.count == 2)
    #expect(mock.postedItems[0].id == item1.id)
    #expect(mock.postedItems[1].id == item2.id)

    mock.openSystemSettingsNotifications()
    #expect(mock.openSettingsCount == 1)

    let status = await mock.authorizationStatus()
    #expect(status == .authorized)

    mock.reset()
    #expect(mock.postedItems.isEmpty)
    #expect(mock.authorizationRequestsCount == 0)
    #expect(mock.openSettingsCount == 0)
  }

  @Test("SystemCINotificationManager safely no-ops without bundle proxy in CLI")
  func systemCINotificationManagerCLIEnvironmentSafety() async throws {
    let manager = SystemCINotificationManager(centerProvider: { nil })
    let authorized = await manager.requestAuthorization()
    #expect(authorized == false)

    let item = FailingCIItem(
      repo: "Cwander83/repo-radar",
      ref: "main",
      kind: .defaultBranch,
      check: "test",
      conclusion: "failure"
    )
    // Should not throw or crash when center is nil
    try await manager.postNotification(for: item)
  }
}
