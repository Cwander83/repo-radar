import Foundation

/// Decoder and encoder configured for GitHub GraphQL responses and ISO8601 timestamps.
public enum RepoRadarDecoder {
  /// Creates a `JSONDecoder` configured to parse ISO8601 timestamps with or without fractional seconds.
  public static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)
      if let date = try? Date(string, strategy: .iso8601) {
        return date
      }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid ISO8601 date: \(string)"
      )
    }
    return decoder
  }

  /// Decodes a `GraphQLQueryResponse` from raw JSON data.
  public static func decode(from data: Data) throws -> GraphQLQueryResponse {
    try makeDecoder().decode(GraphQLQueryResponse.self, from: data)
  }
}

/// Helper encoder configured for standard ISO8601 formatting.
public enum RepoRadarEncoder {
  /// Creates a `JSONEncoder` using standard ISO8601 dates.
  public static func makeEncoder(prettyPrinted: Bool = false) -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if prettyPrinted {
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    return encoder
  }

  /// Encodes a value to JSON data.
  public static func encode<T: Encodable>(_ value: T, prettyPrinted: Bool = false) throws -> Data {
    try makeEncoder(prettyPrinted: prettyPrinted).encode(value)
  }
}

extension GraphQLQueryResponse {
  /// Convenience method to decode a query response from JSON data.
  public static func decode(from data: Data) throws -> GraphQLQueryResponse {
    try RepoRadarDecoder.decode(from: data)
  }
}
