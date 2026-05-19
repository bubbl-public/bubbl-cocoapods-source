import Foundation

public struct BubblHTTPRequest: Sendable, Equatable {
    public let method: String
    public let url: URL
    public let headers: [String: String]
    public let body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct BubblHTTPResponse: Sendable, Equatable {
    public let statusCode: Int
    public let data: Data
    public let headers: [String: String]

    public init(statusCode: Int, data: Data = Data(), headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
    }
}

public protocol BubblHTTPTransport: Sendable {
    func send(_ request: BubblHTTPRequest) async throws -> BubblHTTPResponse
}

public struct URLSessionBubblHTTPTransport: BubblHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: BubblHTTPRequest) async throws -> BubblHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = 30

        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BubblError.invalidResponse("Response was not HTTP.")
        }

        let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, item in
            guard let name = item.key as? String else { return }
            result[name] = String(describing: item.value)
        }

        return BubblHTTPResponse(statusCode: httpResponse.statusCode, data: data, headers: headers)
    }
}

enum BubblTransportMap {
    static let sdkVersion = "3.0.0"
    static let platform = "ios"

    static let runtimeAuthHeader = "x-api-key"
    static let ingestAuthHeader = "ApiKey"
    static let dashboardAuthHeader = "ApiKey"

    static let refreshGeofencePath = "/api/check-geofence"
    static let refreshPushPath = "/api/check-push"
    static let getConfigurationPath = "/api/get-config"

    static let registerDevicePath = "/api/device-registerd/create"
    static let bootBatchPath = "/api/device-data"
    static let trackEventPath = "/api/activities"
    static let updateSegmentsPath = "/api/segments"
    static let submitSurveyResponsePath = "/api/survey-response"
    static let trackGeofenceBatchPath = "/api/geofence-data"

    static func transmissionBaseURL(_ config: BubblConfig) -> URL {
        if let url = config.transmissionBaseUrl ?? config.runtimeBaseUrl {
            return url
        }

        switch config.environment {
        case .development, .nightly:
            return URL(string: "https://nightly.transmission.bubbl.tech")!
        case .staging:
            return URL(string: "https://staging.transmission.bubbl.tech")!
        case .production:
            return URL(string: "https://transmission.bubbl.tech")!
        }
    }

    static func runtimeBaseURL(_ config: BubblConfig) -> URL {
        transmissionBaseURL(config)
    }

    static func ingestBaseURL(_ config: BubblConfig) -> URL {
        if let url = config.ingestBaseUrl {
            return url
        }

        switch config.environment {
        case .development, .nightly:
            return URL(string: "https://nightly.ingest.bubbl.tech")!
        case .staging:
            return URL(string: "https://staging.ingest.bubbl.tech")!
        case .production:
            return URL(string: "https://ingest.bubbl.tech")!
        }
    }

    static func transmissionDistanceMiles(publicDistanceMeters: Int) -> Double {
        Double(max(publicDistanceMeters, 1)) / 1_609.344
    }
}
