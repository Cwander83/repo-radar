import Foundation
import Testing

@testable import RepoRadarCore

struct KeychainTokenStoreTests {
  private func makeTestStore() -> KeychainTokenStore {
    let uniqueService = "com.chriswander.reporadar.test.\(UUID().uuidString)"
    return KeychainTokenStore(service: uniqueService, account: "test-token")
  }

  @Test("Reading non-existent token returns nil")
  func readEmptyReturnsNil() throws {
    let store = makeTestStore()
    defer { try? store.delete() }

    #expect(try store.read() == nil)
    #expect(!store.hasToken())
  }

  @Test("Save, read, update, and delete token round-trips successfully")
  func saveReadUpdateDeleteRoundTrip() throws {
    let store = makeTestStore()
    defer { try? store.delete() }

    let token1 = "test-token-value-alpha"
    try store.save(token: token1)

    #expect(try store.read() == token1)
    #expect(store.hasToken())

    // Update existing token (triggers SecItemUpdate)
    let token2 = "test-token-value-beta"
    try store.save(token: token2)

    #expect(try store.read() == token2)
    #expect(store.hasToken())

    // Delete token
    try store.delete()

    #expect(try store.read() == nil)
    #expect(!store.hasToken())

    // Idempotent delete (deleting non-existent does not throw)
    #expect(throws: Never.self) {
      try store.delete()
    }
  }

  @Test("Saving empty or whitespace token throws emptyToken error")
  func emptyTokenThrows() {
    let store = makeTestStore()
    defer { try? store.delete() }

    #expect(throws: KeychainError.emptyToken) {
      try store.save(token: "")
    }

    #expect(throws: KeychainError.emptyToken) {
      try store.save(token: "   \n\t  ")
    }
  }

  @Test("InMemoryTokenStore round-trips save, read, and delete")
  func inMemoryTokenStoreRoundTrip() throws {
    let store = InMemoryTokenStore()

    #expect(try store.read() == nil)
    #expect(!store.hasToken())

    try store.save(token: "in-memory-token-1")
    #expect(try store.read() == "in-memory-token-1")
    #expect(store.hasToken())

    try store.save(token: "in-memory-token-2")
    #expect(try store.read() == "in-memory-token-2")

    try store.delete()
    #expect(try store.read() == nil)
    #expect(!store.hasToken())

    #expect(throws: KeychainError.emptyToken) {
      try store.save(token: "")
    }
  }

  @Test("KeychainError descriptions are formatted properly")
  func keychainErrorDescriptions() {
    #expect(KeychainError.emptyToken.errorDescription == "Personal access token cannot be empty.")
    #expect(
      KeychainError.itemNotFound.errorDescription == "Personal access token not found in Keychain.")
    #expect(KeychainError.invalidData.errorDescription == "Keychain item contained invalid data.")
    #expect(
      KeychainError.osStatus(status: -25300, message: "Item not found").errorDescription
        == "Keychain error (-25300): Item not found")
  }
}
