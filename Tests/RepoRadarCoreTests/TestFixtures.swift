import Foundation

enum TestFixtures {
  /// Loads fixture data from the test bundle's `Fixtures/` directory.
  static func loadData(named name: String) throws -> Data {
    guard
      let url = Bundle.module.url(
        forResource: name,
        withExtension: "json",
        subdirectory: "Fixtures"
      ) ?? Bundle.module.url(forResource: name, withExtension: "json")
    else {
      throw CocoaError(.fileNoSuchFile)
    }
    return try Data(contentsOf: url)
  }
}
