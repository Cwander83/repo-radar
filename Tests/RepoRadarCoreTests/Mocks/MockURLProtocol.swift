import Foundation

/// Stubbed URLProtocol for zero-network testing with URLSession.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var handlers:
    [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]
  nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  static func registerHandler(
    id: String, handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
  ) {
    lock.lock()
    defer { lock.unlock() }
    handlers[id] = handler
  }

  static func unregisterHandler(id: String) {
    lock.lock()
    defer { lock.unlock() }
    handlers.removeValue(forKey: id)
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    if let mockID = request.value(forHTTPHeaderField: "X-Mock-Handler-ID") {
      MockURLProtocol.lock.lock()
      handler = MockURLProtocol.handlers[mockID]
      MockURLProtocol.lock.unlock()
    } else {
      handler = MockURLProtocol.requestHandler
    }

    guard let handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.unknown))
      return
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

extension URLRequest {
  /// Reads request body whether delivered as `httpBody` or `httpBodyStream`.
  var bodyData: Data? {
    if let httpBody {
      return httpBody
    }
    guard let stream = httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let read = stream.read(buffer, maxLength: bufferSize)
      if read <= 0 { break }
      data.append(buffer, count: read)
    }
    return data
  }
}
