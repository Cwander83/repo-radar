import Foundation
import Security

/// Errors occurring during Keychain operations.
public enum KeychainError: Error, Sendable, Equatable, LocalizedError {
  case emptyToken
  case itemNotFound
  case invalidData
  case osStatus(status: OSStatus, message: String)

  public var errorDescription: String? {
    switch self {
    case .emptyToken:
      return "Personal access token cannot be empty."
    case .itemNotFound:
      return "Personal access token not found in Keychain."
    case .invalidData:
      return "Keychain item contained invalid data."
    case .osStatus(let status, let message):
      return "Keychain error (\(status)): \(message)"
    }
  }

  public static func from(status: OSStatus) -> KeychainError {
    let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
    return .osStatus(status: status, message: message)
  }
}

/// Abstract protocol for reading, saving, and deleting personal access tokens.
public protocol TokenStore: Sendable {
  /// Reads the current token from storage, returning nil if not set.
  func read() throws -> String?

  /// Saves or updates the token in storage.
  func save(token: String) throws

  /// Deletes the token from storage. Idempotent.
  func delete() throws

  /// Returns true if a token is present in storage.
  func hasToken() -> Bool
}

extension TokenStore {
  public func hasToken() -> Bool {
    (try? read()) != nil
  }
}

/// Secure storage of the GitHub Personal Access Token in the macOS Keychain.
public struct KeychainTokenStore: TokenStore {
  /// Default Keychain service name for RepoRadar.
  public static let defaultService = "com.chriswander.reporadar"

  /// Default Keychain account identifier for the GitHub token.
  public static let defaultAccount = "github-token"

  /// The service name used for the generic password Keychain item.
  public let service: String

  /// The account name used for the generic password Keychain item.
  public let account: String

  /// Optional Keychain access group (used for sandboxed App Groups if configured).
  public let accessGroup: String?

  public init(
    service: String = defaultService,
    account: String = defaultAccount,
    accessGroup: String? = nil
  ) {
    self.service = service
    self.account = account
    self.accessGroup = accessGroup
  }

  /// Reads the token from the Keychain.
  public func read() throws -> String? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    switch status {
    case errSecSuccess:
      guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
        throw KeychainError.invalidData
      }
      return token
    case errSecItemNotFound:
      return nil
    default:
      throw KeychainError.from(status: status)
    }
  }

  /// Saves or updates the token in the Keychain.
  public func save(token: String) throws {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw KeychainError.emptyToken
    }

    let tokenData = Data(trimmed.utf8)

    var addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: tokenData,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    if let accessGroup {
      addQuery[kSecAttrAccessGroup as String] = accessGroup
    }

    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

    if addStatus == errSecDuplicateItem {
      var searchQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
      ]
      if let accessGroup {
        searchQuery[kSecAttrAccessGroup as String] = accessGroup
      }

      let updateAttributes: [String: Any] = [
        kSecValueData as String: tokenData,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
      ]

      let updateStatus = SecItemUpdate(
        searchQuery as CFDictionary, updateAttributes as CFDictionary)
      guard updateStatus == errSecSuccess else {
        throw KeychainError.from(status: updateStatus)
      }
    } else if addStatus != errSecSuccess {
      throw KeychainError.from(status: addStatus)
    }
  }

  /// Deletes the token from the Keychain.
  public func delete() throws {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }

    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.from(status: status)
    }
  }
}

/// In-memory token store for testing and preview environments.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
  private let lock = NSLock()
  private var token: String?

  public init(initialToken: String? = nil) {
    self.token = initialToken
  }

  public func read() throws -> String? {
    lock.lock()
    defer { lock.unlock() }
    return token
  }

  public func save(token: String) throws {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw KeychainError.emptyToken
    }
    lock.lock()
    defer { lock.unlock() }
    self.token = trimmed
  }

  public func delete() throws {
    lock.lock()
    defer { lock.unlock() }
    self.token = nil
  }
}
