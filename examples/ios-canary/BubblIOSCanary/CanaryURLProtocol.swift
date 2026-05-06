import Foundation

struct CanaryRequestRecord: Equatable {
    let method: String
    let host: String
    let path: String
    let headers: [String: String]
    let body: Data?
}

final class CanaryURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var records: [CanaryRequestRecord] = []
    private static var runtimeAvailable = true
    private static var ingestStatusCode = 200

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else {
            return false
        }

        return host == "canary-runtime.bubbl.local" || host == "canary-ingest.bubbl.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let host = url.host else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let body = bodyData(from: request)
        Self.record(request: request, body: body)

        if host == "canary-runtime.bubbl.local" {
            handleRuntimeRequest(url)
            return
        }

        handleIngestRequest(url)
    }

    override func stopLoading() {}

    static func reset() {
        withLock {
            records = []
            runtimeAvailable = true
            ingestStatusCode = 200
        }
    }

    static func setRuntimeAvailable(_ available: Bool) {
        withLock {
            runtimeAvailable = available
        }
    }

    static func setIngestStatusCode(_ statusCode: Int) {
        withLock {
            ingestStatusCode = statusCode
        }
    }

    static func requestRecords() -> [CanaryRequestRecord] {
        withLock {
            records
        }
    }

    private func handleRuntimeRequest(_ url: URL) {
        guard Self.currentRuntimeAvailable() else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }

        if url.path == "/api/check-geofence" {
            respond(url: url, statusCode: 200, body: geofenceResponseBody)
            return
        }

        let responseBody = Data(
            """
            {
              "configuration": {
                "notificationsCount": 2,
                "daysCount": 7,
                "batteryCount": 1,
                "privacyText": "Canary privacy text"
              }
            }
            """.utf8
        )
        respond(url: url, statusCode: 200, body: responseBody)
    }

    private var geofenceResponseBody: Data {
        Data(
            """
            {
              "geoCampaign": [
                {
                  "campaignId": 123,
                  "campaignName": "Canary geofence",
                  "type": "GEO",
                  "active": true,
                  "locationsArray": {
                    "locationId": 10,
                    "geofence": [
                      { "position": 1, "latitude": "51.501476", "longitude": "-0.140112" },
                      { "position": 2, "latitude": "51.501800", "longitude": "-0.141000" },
                      { "position": 3, "latitude": "51.501476", "longitude": "-0.142000" }
                    ]
                  },
                  "notificationsArray": [
                    {
                      "curatedNotificationId": 456,
                      "headline": "Welcome",
                      "body": "Thanks for visiting",
                      "type": "notification",
                      "activation": "ON_ENTER",
                      "published": true
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {
                "notificationsCount": 2,
                "daysCount": 7,
                "batteryCount": 1,
                "privacyText": "Canary privacy text"
              }
            }
            """.utf8
        )
    }

    private func handleIngestRequest(_ url: URL) {
        let statusCode = Self.currentIngestStatusCode()
        let responseBody = Data(#"{"success":true,"queued":true}"#.utf8)
        respond(url: url, statusCode: statusCode, body: responseBody)
    }

    private func respond(url: URL, statusCode: Int, body: Data) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func record(request: URLRequest, body: Data?) {
        let url = request.url
        let record = CanaryRequestRecord(
            method: request.httpMethod ?? "GET",
            host: url?.host ?? "",
            path: url?.path ?? "",
            headers: request.allHTTPHeaderFields ?? [:],
            body: body
        )

        withLock {
            records.append(record)
        }
    }

    private static func currentRuntimeAvailable() -> Bool {
        withLock {
            runtimeAvailable
        }
    }

    private static func currentIngestStatusCode() -> Int {
        withLock {
            ingestStatusCode
        }
    }

    private static func withLock<T>(_ work: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return work()
    }

    private func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)

        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }

        return data
    }
}
