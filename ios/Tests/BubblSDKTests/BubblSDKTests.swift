import XCTest
@testable import BubblSDK

final class MockTransport: BubblHTTPTransport, @unchecked Sendable {
    var requests: [BubblHTTPRequest] = []
    var handler: (BubblHTTPRequest) throws -> BubblHTTPResponse

    init(handler: @escaping (BubblHTTPRequest) throws -> BubblHTTPResponse) {
        self.handler = handler
    }

    func send(_ request: BubblHTTPRequest) async throws -> BubblHTTPResponse {
        requests.append(request)
        return try handler(request)
    }
}

final class MockNotificationPresenter: BubblNotificationPresenting, @unchecked Sendable {
    var payloads: [BubblNotificationPayload] = []
    var result = BubblNotificationDisplayResult(displayed: true)

    func present(_ payload: BubblNotificationPayload) async throws -> BubblNotificationDisplayResult {
        payloads.append(payload)
        return result
    }
}

final class BubblSDKTests: XCTestCase {
    func testBootRequiresApiKey() async {
        do {
            _ = try await BubblClient(storageDirectory: temporaryDirectory()).boot(BubblConfig(apiKey: ""))
            XCTFail("Expected empty apiKey to throw")
        } catch BubblError.invalidConfig {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBootReturnsHeadlessPermissionRequirements() async throws {
        let result = try await BubblClient(storageDirectory: temporaryDirectory()).boot(
            BubblConfig(
                apiKey: "test-key",
                enablePushHandling: true,
                enableLocationTracking: true
            )
        )

        XCTAssertTrue(result.ready)
        XCTAssertEqual(result.requiresPermission, ["location", "push"])
    }

    func testBootQueuesLegacyMirroredDeviceDataAndFlushPostsIt() async throws {
        let transport = MockTransport { request in
            XCTAssertEqual(request.url.host, "ingest.test")
            XCTAssertEqual(request.url.path, "/api/device-data")
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(request.headers["ApiKey"], "sdk-key")
            XCTAssertEqual(request.headers["X-Bubbl-SDK-Version"], "4.0.4")
            XCTAssertEqual(request.headers["X-Bubbl-SDK-Platform"], "ios")
            XCTAssertNotNil(request.headers["Idempotency-Key"])
            XCTAssertNotNil(request.headers["X-Bubbl-Install-ID"])

            let body = try XCTUnwrap(request.body)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertNotNil(json?["device_registered"])
            XCTAssertNotNil(json?["plugin_activity"])
            XCTAssertNotNil(json?["raw_data"])

            return BubblHTTPResponse(statusCode: 200, data: #"{"success":true,"queued":true,"data":{"ingest_message_id":"1","status":"queued"}}"#.data(using: .utf8)!)
        }
        let sdk = BubblClient(storageDirectory: temporaryDirectory(), transport: transport)

        _ = try await sdk.boot(
            BubblConfig(
                apiKey: "sdk-key",
                runtimeBaseUrl: URL(string: "https://runtime.test")!,
                ingestBaseUrl: URL(string: "https://ingest.test")!,
                segments: ["vip"]
            )
        )

        var diagnostics = await sdk.diagnostics()
        XCTAssertEqual(diagnostics.pendingIngestCount, 1)

        let flush = await sdk.flush()
        XCTAssertEqual(flush.pendingCount, 0)

        diagnostics = await sdk.diagnostics()
        XCTAssertEqual(diagnostics.pendingIngestCount, 0)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testUpdateFCMTokenFlushesDeviceRegistrationImmediately() async throws {
        let transport = MockTransport { request in
            BubblHTTPResponse(statusCode: 200, data: #"{"success":true,"queued":true,"data":{"ingest_message_id":"1","status":"queued"}}"#.data(using: .utf8)!)
        }
        let sdk = BubblClient(storageDirectory: temporaryDirectory(), transport: transport)

        _ = try await sdk.boot(
            BubblConfig(
                apiKey: "sdk-key",
                runtimeBaseUrl: URL(string: "https://runtime.test")!,
                ingestBaseUrl: URL(string: "https://ingest.test")!,
                segments: ["vip"]
            )
        )

        try await sdk.updateFCMToken("real-fcm-token")

        let diagnostics = await sdk.diagnostics()
        XCTAssertEqual(diagnostics.pendingIngestCount, 0)
        XCTAssertEqual(transport.requests.map(\.url.path), ["/api/device-data", "/api/device-registerd/create"])

        let body = try XCTUnwrap(transport.requests.last?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["device_token"] as? String, "real-fcm-token")
    }

    func testRuntimeConfigurationFallsBackToCachedResponse() async throws {
        let configJSON = #"{"configuration":{"notificationsCount":3,"daysCount":2,"batteryCount":1,"privacyText":"Cached privacy"}}"#.data(using: .utf8)!
        let transport = MockTransport { _ in
            BubblHTTPResponse(statusCode: 200, data: configJSON)
        }
        let sdk = BubblClient(storageDirectory: temporaryDirectory(), transport: transport)

        _ = try await sdk.boot(
            BubblConfig(
                apiKey: "sdk-key",
                runtimeBaseUrl: URL(string: "https://runtime.test")!,
                ingestBaseUrl: URL(string: "https://ingest.test")!
            )
        )

        let online = await sdk.getConfiguration()
        XCTAssertEqual(online?.privacyText, "Cached privacy")

        transport.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let fallback = await sdk.getConfiguration()
        XCTAssertEqual(fallback?.privacyText, "Cached privacy")
    }

    func testDefaultEnvironmentEndpointsUseRenewedSplitHostsAndConvertPublicMetersForTransmission() async throws {
        let cases: [(BubblEnvironment, String, String)] = [
            (.development, "staging.transmission.bubbl.tech", "staging.ingest.bubbl.tech"),
            (.staging, "staging.transmission.bubbl.tech", "staging.ingest.bubbl.tech"),
            (.production, "transmission.bubbl.tech", "ingest.bubbl.tech"),
        ]

        for (environment, expectedRuntimeHost, expectedIngestHost) in cases {
            let transport = MockTransport { request in
                if request.url.path == "/api/check-geofence" {
                    return BubblHTTPResponse(
                        statusCode: 200,
                        data: #"{"geoCampaign":[],"pushCampaign":[],"configuration":{"notificationsCount":0,"daysCount":0,"batteryCount":0,"privacyText":""}}"#.data(using: .utf8)!
                    )
                }

                return BubblHTTPResponse(statusCode: 200, data: #"{"success":true}"#.data(using: .utf8)!)
            }
            let sdk = BubblClient(storageDirectory: temporaryDirectory(), transport: transport)

            _ = try await sdk.boot(
                BubblConfig(
                    apiKey: "sdk-key",
                    environment: environment,
                    defaultDistanceMeters: 1609
                )
            )
            try await sdk.refreshGeofence(BubblLocation(latitude: 51.5072, longitude: -0.1276))
            _ = await sdk.flush()

            let runtimeRequest = try XCTUnwrap(transport.requests.first { $0.url.path == "/api/check-geofence" })
            let ingestRequest = try XCTUnwrap(transport.requests.first { $0.url.path == "/api/device-data" })
            let body = try XCTUnwrap(runtimeRequest.body)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let distance = try XCTUnwrap(json?["distance"] as? Double)

            XCTAssertEqual(runtimeRequest.url.host, expectedRuntimeHost)
            XCTAssertEqual(ingestRequest.url.host, expectedIngestHost)
            XCTAssertEqual(distance, 1.0, accuracy: 0.001)
            XCTAssertEqual(BubblTransportMap.runtimeAuthHeader, "x-api-key")
            XCTAssertEqual(BubblTransportMap.ingestAuthHeader, "ApiKey")
        }
    }

    func testKeychainStatePersistsAcrossStoreInstances() throws {
        let directory = temporaryDirectory()
        let store = BubblPersistentStore(directory: directory)
        defer { try? store.deleteSecureStateForTests() }

        var state = try store.loadState()
        state.correlationId = "corr-ios"
        state.segments = ["vip", "metro"]
        state.pushToken = "push-token-ios"
        try store.saveState(state)

        let restored = try BubblPersistentStore(directory: directory).loadState()

        XCTAssertEqual(restored.installId, state.installId)
        XCTAssertEqual(restored.correlationId, "corr-ios")
        XCTAssertEqual(restored.segments, ["vip", "metro"])
        XCTAssertEqual(restored.pushToken, "push-token-ios")
    }

    func testSQLiteQueuePersistsAcrossStoreInstances() throws {
        let directory = temporaryDirectory()
        let store = BubblPersistentStore(directory: directory)
        defer { try? store.deleteSecureStateForTests() }

        let body = #"{"device_registered":{"device_id":"ios-device"}}"#.data(using: .utf8)!
        try store.append(
            BubblQueuedRequest(
                path: "/api/device-data",
                body: body,
                idempotencyKey: "ios-idempotency"
            )
        )

        let restoredStore = BubblPersistentStore(directory: directory)
        let queue = try restoredStore.loadQueue()

        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.single?.path, "/api/device-data")
        XCTAssertEqual(queue.single?.body, body)
        XCTAssertEqual(queue.single?.idempotencyKey, "ios-idempotency")

        try restoredStore.saveQueue([])
        XCTAssertEqual(try restoredStore.pendingCount(), 0)
    }

    func testFlushKeepsFailedIngestQueuedThenRetriesSuccessfully() async throws {
        var statusCode = 500
        let transport = MockTransport { request in
            XCTAssertEqual(request.url.path, "/api/device-data")
            return BubblHTTPResponse(statusCode: statusCode, data: Data())
        }
        let directory = temporaryDirectory()
        let store = BubblPersistentStore(directory: directory)
        defer { try? store.deleteSecureStateForTests() }
        let sdk = BubblClient(storageDirectory: directory, transport: transport)

        _ = try await sdk.boot(
            BubblConfig(
                apiKey: "sdk-key",
                runtimeBaseUrl: URL(string: "https://runtime.test")!,
                ingestBaseUrl: URL(string: "https://ingest.test")!
            )
        )

        let failedFlush = await sdk.flush()
        XCTAssertEqual(failedFlush.pendingCount, 1)
        XCTAssertEqual(try store.loadQueue().single?.attempts, 1)

        statusCode = 200

        let successfulRetry = await sdk.flush()
        XCTAssertEqual(successfulRetry.pendingCount, 0)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testParsesRemoteNotificationWithMediaCtaAndSurvey() throws {
        let payload = try XCTUnwrap(
            BubblNotificationPayloadParser.fromRemoteNotification([
                "notification_data": [
                    "headline": "Welcome back",
                    "message": "Tap for your offer",
                    "curated_notification_id": "42",
                    "location_id": "7",
                    "media_url": "https://cdn.test/offer.png",
                    "cta_label": "Open",
                    "cta_url": "https://bubbl.test/offers/42",
                    "questions": #"[{"id":"1","title":"How was it?","type":"single_choice","choices":[{"id":"5","label":"Great"}]}]"#
                ]
            ])
        )

        XCTAssertEqual(payload.title, "Welcome back")
        XCTAssertEqual(payload.body, "Tap for your offer")
        XCTAssertEqual(payload.curatedNotificationId, "42")
        XCTAssertEqual(payload.locationId, "7")
        XCTAssertEqual(payload.media?.url.absoluteString, "https://cdn.test/offer.png")
        XCTAssertEqual(payload.cta?.label, "Open")
        XCTAssertEqual(payload.survey?.questions.single?.id, "1")
        XCTAssertEqual(payload.survey?.questions.single?.choices.single?.id, "5")
        XCTAssertEqual(payload.survey?.questions.single?.choices.single?.label, "Great")
    }

    func testParsesRemoteSurveyOptionsAliasAsSelectableChoices() throws {
        let payload = try XCTUnwrap(
            BubblNotificationPayloadParser.fromRemoteNotification([
                "title": "Survey",
                "body": "Pick one",
                "questions": #"[{"id":"1","title":"How was it?","type":"single_choice","options":[{"id":"5","label":"Great"}]}]"#
            ])
        )

        let choice = try XCTUnwrap(payload.survey?.questions.single?.choices.single)
        XCTAssertEqual(choice.id, "5")
        XCTAssertEqual(choice.label, "Great")
    }

    func testParsesLegacyNotificationIdAliasAsCuratedNotificationId() throws {
        let payload = try XCTUnwrap(
            BubblNotificationPayloadParser.fromRemoteNotification([
                "aps": ["alert": ["title": "Legacy push", "body": "Uses n_id"]],
                "n_id": "42"
            ])
        )

        XCTAssertEqual(payload.curatedNotificationId, "42")
        XCTAssertEqual(payload.id, "42")
    }

    func testKeepsProviderNotificationIdOutOfCuratedNotificationId() throws {
        let payload = try XCTUnwrap(
            BubblNotificationPayloadParser.fromRemoteNotification([
                "aps": ["alert": ["title": "Provider push", "body": "Has a provider id"]],
                "notification_id": "provider-123"
            ])
        )

        XCTAssertEqual(payload.id, "provider-123")
        XCTAssertNil(payload.curatedNotificationId)
    }

    func testNotificationAttachmentPlannerAcceptsRemoteImageMedia() throws {
        let media = BubblNotificationMedia(
            url: try XCTUnwrap(URL(string: "https://cdn.test/offer")),
            type: "image/png",
            altText: "Offer"
        )

        XCTAssertTrue(BubblNotificationAttachmentPlanner.isEligible(media))
        XCTAssertEqual(BubblNotificationAttachmentPlanner.fileExtension(for: media), "png")
        XCTAssertEqual(
            BubblNotificationAttachmentPlanner.fileName(notificationId: "offer/42", fileExtension: "png"),
            "offer_42.png"
        )
    }

    func testNotificationAttachmentPlannerUsesYoutubeThumbnailForYoutubeMedia() throws {
        let media = BubblNotificationMedia(
            url: try XCTUnwrap(URL(string: "https://youtu.be/dQw4w9WgXcQ")),
            type: "youtube",
            altText: "Watch video"
        )

        XCTAssertTrue(BubblNotificationAttachmentPlanner.isEligible(media))
        XCTAssertEqual(BubblNotificationAttachmentPlanner.fileExtension(for: media), "jpg")
        XCTAssertEqual(
            BubblNotificationAttachmentPlanner.attachmentURL(for: media)?.absoluteString,
            "https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
        )
        XCTAssertEqual(
            BubblNotificationAttachmentPlanner.youtubeEmbedURL(for: media)?.absoluteString,
            "https://www.youtube.com/embed/dQw4w9WgXcQ?playsinline=1&rel=0&origin=https%3A%2F%2Fbubbl.tech"
        )
    }

    func testDefaultNotificationModalMediaHTMLRendersMediaInline() throws {
        let imageHTML = BubblNotificationAttachmentPlanner.inlineMediaHTML(
            for: BubblNotificationMedia(
                url: try XCTUnwrap(URL(string: "https://cdn.test/offer.png")),
                type: "image/png",
                altText: "Offer"
            )
        )
        let audioHTML = BubblNotificationAttachmentPlanner.inlineMediaHTML(
            for: BubblNotificationMedia(
                url: try XCTUnwrap(URL(string: "https://cdn.test/audio.mp3")),
                type: "audio/mpeg"
            )
        )
        let videoHTML = BubblNotificationAttachmentPlanner.inlineMediaHTML(
            for: BubblNotificationMedia(
                url: try XCTUnwrap(URL(string: "https://cdn.test/video.mp4")),
                type: "video/mp4"
            )
        )

        XCTAssertTrue(imageHTML.contains(#"<img src="https://cdn.test/offer.png""#))
        XCTAssertTrue(audioHTML.contains(#"<audio src="https://cdn.test/audio.mp3" controls"#))
        XCTAssertTrue(videoHTML.contains(#"<video src="https://cdn.test/video.mp4" controls"#))
        XCTAssertFalse(imageHTML.contains("UIApplication.shared.open"))
        XCTAssertFalse(audioHTML.contains("UIApplication.shared.open"))
        XCTAssertFalse(videoHTML.contains("UIApplication.shared.open"))
    }

    func testNotificationAttachmentPlannerRejectsUnsupportedOrLocalMedia() throws {
        let local = BubblNotificationMedia(
            url: try XCTUnwrap(URL(string: "file:///tmp/offer.png")),
            type: "image/png"
        )
        let unsupported = BubblNotificationMedia(
            url: try XCTUnwrap(URL(string: "https://cdn.test/document")),
            type: "application/pdf"
        )

        XCTAssertFalse(BubblNotificationAttachmentPlanner.isEligible(local))
        XCTAssertFalse(BubblNotificationAttachmentPlanner.isEligible(unsupported))
        XCTAssertNil(BubblNotificationAttachmentPlanner.fileExtension(for: unsupported))
    }

    func testRejectsEmptyRemoteNotificationPayload() {
        XCTAssertNil(BubblNotificationPayloadParser.fromRemoteNotification([:]))
    }

    func testExtractsGeofenceRuntimeCampaignNotifications() throws {
        let response = """
            {
              "geoCampaign": [
                {
                  "campaignId": 123,
                  "campaignName": "Spring offers",
                  "type": "GEO",
                  "active": "true",
                  "locationsArray": {"locationId": 10},
                  "notificationsArray": [
                    {
                      "curatedNotificationId": 456,
                      "headline": "Welcome",
                      "body": "Thanks for visiting",
                      "type": "notification",
                      "ctaLabel": "Open",
                      "ctaUrl": "https://bubbl.tech",
                      "published": true
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.data(using: .utf8)!

        let payload = try XCTUnwrap(BubblNotificationPayloadParser.fromRuntimeResponse(response).single)

        XCTAssertEqual(payload.source, .geofence)
        XCTAssertEqual(payload.title, "Welcome")
        XCTAssertEqual(payload.body, "Thanks for visiting")
        XCTAssertEqual(payload.curatedNotificationId, "456")
        XCTAssertEqual(payload.locationId, "10")
        XCTAssertEqual(payload.cta?.label, "Open")
    }

    func testIgnoresNullRuntimeSurveyCTAValues() throws {
        let response = """
            {
              "geoCampaign": [
                {
                  "campaignId": 123,
                  "campaignName": "Survey offers",
                  "type": "GEO",
                  "active": "true",
                  "locationsArray": {"locationId": 10},
                  "notificationsArray": [
                    {
                      "curatedNotificationId": 456,
                      "headline": "Welcome",
                      "body": "Thanks for visiting",
                      "type": "notification",
                      "cta": [
                        {
                          "label": null,
                          "url": null
                        }
                      ],
                      "questions": [
                        {
                          "id": 1,
                          "title": "How was it?",
                          "type": "single_choice",
                          "choices": [
                            {
                              "id": 5,
                              "label": "Great"
                            }
                          ]
                        }
                      ],
                      "published": true
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.data(using: .utf8)!

        let payload = try XCTUnwrap(BubblNotificationPayloadParser.fromRuntimeResponse(response).single)

        XCTAssertNil(payload.cta)
        XCTAssertEqual(payload.survey?.questions.single?.choices.single?.label, "Great")
    }

    func testIgnoresPausedRuntimeCampaignNotifications() {
        let response = """
            {
              "geoCampaign": [
                {
                  "campaignId": "paused",
                  "campaignName": "Paused offers",
                  "active": true,
                  "paused": true,
                  "locationsArray": {"locationId": 10},
                  "notificationsArray": [
                    {
                      "curatedNotificationId": "paused-notification",
                      "headline": "Do not send",
                      "body": "Paused campaign",
                      "published": true
                    }
                  ]
                },
                {
                  "campaignId": "status-paused",
                  "campaignName": "Status paused offers",
                  "active": true,
                  "status": "paused",
                  "locationsArray": {"locationId": 11},
                  "notificationsArray": [
                    {
                      "curatedNotificationId": "status-paused-notification",
                      "headline": "Do not send either",
                      "body": "Status paused campaign",
                      "published": true
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.data(using: .utf8)!

        XCTAssertEqual(BubblNotificationPayloadParser.fromRuntimeResponse(response), [])
    }

    func testRefreshPushDispatchesRuntimeCampaignNotifications() async throws {
        let presenter = MockNotificationPresenter()
        let transport = MockTransport { request in
            if request.url.path == "/api/check-push" {
                return BubblHTTPResponse(
                    statusCode: 200,
                    data: """
                        {
                          "pushCampaign": [
                            {
                              "campaignId": 321,
                              "campaignName": "Push offers",
                              "type": "PUSH",
                              "active": true,
                              "notificationsArray": [
                                {
                                  "curatedNotificationId": 654,
                                  "headline": "Push hello",
                                  "body": "Runtime push",
                                  "type": "notification",
                                  "published": true
                                }
                              ]
                            }
                          ],
                          "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
                        }
                    """.data(using: .utf8)!
                )
            }

            return BubblHTTPResponse(statusCode: 200, data: #"{"success":true}"#.data(using: .utf8)!)
        }
        let sdk = BubblClient(
            storageDirectory: temporaryDirectory(),
            transport: transport,
            notificationPresenter: presenter
        )

        _ = try await sdk.boot(
            BubblConfig(
                apiKey: "sdk-key",
                runtimeBaseUrl: URL(string: "https://runtime.test")!,
                ingestBaseUrl: URL(string: "https://ingest.test")!
            )
        )
        try await sdk.refreshPush()

        XCTAssertEqual(presenter.payloads.single?.source, .runtime)
        XCTAssertEqual(presenter.payloads.single?.title, "Push hello")
        let diagnostics = await sdk.diagnostics()
        XCTAssertEqual(diagnostics.pendingIngestCount, 0)

        let activities = try transport.requests
            .filter { $0.url.path == "/api/activities" }
            .map { request -> String in
                let body = try XCTUnwrap(request.body)
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                return try XCTUnwrap(json?["activity"] as? String)
            }
        XCTAssertTrue(activities.contains("notification_sent"))
        XCTAssertTrue(activities.contains("notification_delivered"))
    }

    func testGeofenceEngineFiresEnterExitNotificationsWithCooldownAndMaximumTriggers() throws {
        let response = geofenceRuntimeResponse()
        let inside = BubblLocation(latitude: 51.50158, longitude: -0.141)
        let outside = BubblLocation(latitude: 51.500, longitude: -0.141)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-05T10:00:00Z"))

        let entered = BubblGeofenceEngine.evaluate(
            runtimeResponse: response,
            location: inside,
            state: BubblGeofenceState(),
            now: now
        )
        let repeated = BubblGeofenceEngine.evaluate(
            runtimeResponse: response,
            location: inside,
            state: entered.nextState,
            now: now.addingTimeInterval(60)
        )
        let exited = BubblGeofenceEngine.evaluate(
            runtimeResponse: response,
            location: outside,
            state: repeated.nextState,
            now: now.addingTimeInterval(120)
        )
        let reenteredAfterCooldown = BubblGeofenceEngine.evaluate(
            runtimeResponse: response,
            location: inside,
            state: exited.nextState,
            now: now.addingTimeInterval(7200)
        )

        XCTAssertEqual(entered.transitions.single?.type, .enter)
        XCTAssertEqual(entered.notifications.single?.payload.title, "Welcome")
        XCTAssertTrue(repeated.transitions.isEmpty)
        XCTAssertEqual(exited.transitions.single?.type, .exit)
        XCTAssertEqual(exited.notifications.single?.payload.title, "Goodbye")
        XCTAssertEqual(reenteredAfterCooldown.transitions.single?.type, .enter)
        XCTAssertTrue(reenteredAfterCooldown.notifications.isEmpty)
    }

    func testGeofenceSnapshotIncludesActiveCampaignPolygons() {
        let snapshot = BubblGeofenceEngine.snapshot(runtimeResponse: geofenceRuntimeResponse())

        XCTAssertEqual(snapshot.stats.campaignsTotal, 1)
        XCTAssertEqual(snapshot.stats.polygonsTotal, 1)
        XCTAssertEqual(snapshot.polygons.single?.campaignId, "123")
        XCTAssertEqual(snapshot.polygons.single?.campaignName, "Spring offers")
        XCTAssertEqual(snapshot.polygons.single?.locationId, "10")
        XCTAssertEqual(snapshot.polygons.single?.vertices.count, 3)
        XCTAssertEqual(snapshot.circles.single?.campaignId, "123")
    }

    func testGeofenceSnapshotAcceptsImportedLocationAndNotificationAliases() {
        let response = """
            {
              "geoCampaign": [
                {
                  "id": "travel-demo",
                  "name": "Travel demo",
                  "active": true,
                  "locations": [
                    {
                      "id": "london",
                      "polygon": [
                        [-0.140112, 51.501476],
                        [-0.141000, 51.501800],
                        [-0.142000, 51.501476]
                      ]
                    }
                  ],
                  "notifications": [
                    {
                      "curatedNotificationId": 456,
                      "headline": "Travel welcome",
                      "body": "Thanks for visiting",
                      "published": true
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.data(using: .utf8)!

        let snapshot = BubblGeofenceEngine.snapshot(runtimeResponse: response)
        let evaluation = BubblGeofenceEngine.evaluate(
            runtimeResponse: response,
            location: BubblLocation(latitude: 51.50158, longitude: -0.141),
            state: BubblGeofenceState(),
            now: Date()
        )

        XCTAssertEqual(snapshot.stats.campaignsTotal, 1)
        XCTAssertEqual(snapshot.polygons.single?.campaignId, "travel-demo")
        XCTAssertEqual(snapshot.polygons.single?.campaignName, "Travel demo")
        XCTAssertEqual(snapshot.polygons.single?.locationId, "london")
        XCTAssertEqual(evaluation.notifications.single?.payload.title, "Travel welcome")
    }

    func testGeofenceEngineIgnoresPausedCampaigns() {
        let response = """
            {
              "geoCampaign": [
                {
                  "campaignId": "paused",
                  "campaignName": "Paused campaign",
                  "active": true,
                  "paused": true,
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
                      "headline": "Paused welcome",
                      "body": "Should not send",
                      "activation": "ON_ENTER",
                      "published": true
                    }
                  ]
                },
                {
                  "campaignId": "status-paused",
                  "campaignName": "Status paused campaign",
                  "active": true,
                  "status": "paused",
                  "locationsArray": {
                    "locationId": 11,
                    "geofence": [
                      { "position": 1, "latitude": "51.501476", "longitude": "-0.140112" },
                      { "position": 2, "latitude": "51.501800", "longitude": "-0.141000" },
                      { "position": 3, "latitude": "51.501476", "longitude": "-0.142000" }
                    ]
                  },
                  "notificationsArray": [
                    {
                      "curatedNotificationId": 457,
                      "headline": "Status paused welcome",
                      "body": "Should not send",
                      "activation": "ON_ENTER",
                      "published": true
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.data(using: .utf8)!

        let evaluation = BubblGeofenceEngine.evaluate(
            runtimeResponse: response,
            location: BubblLocation(latitude: 51.50158, longitude: -0.141),
            state: BubblGeofenceState(),
            now: Date()
        )

        XCTAssertTrue(evaluation.transitions.isEmpty)
        XCTAssertTrue(evaluation.notifications.isEmpty)
    }

    func testGeofenceEngineUsesNestedDeliveryPolicyAndCTASuspend() throws {
        let response = geofenceRuntimeResponseWithDeliveryPolicy(
            deliveryPolicy: """
                {
                  "activation": "ON_ENTER",
                  "coolingPeriodSeconds": 120,
                  "maximumTriggers": 2,
                  "ctaSuspend": true
                }
            """,
            configurationFrequencyDefaults: """
                {
                  "coolingPeriodSeconds": 600,
                  "maximumTriggers": 5,
                  "ctaSuspend": false
                }
            """
        )
        let inside = BubblLocation(latitude: 51.50158, longitude: -0.141)
        let outside = BubblLocation(latitude: 51.500, longitude: -0.141)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-05T10:00:00Z"))

        let entered = BubblGeofenceEngine.evaluate(
            runtimeResponse: response,
            location: inside,
            state: BubblGeofenceState(),
            now: now
        )
        let triggerKey = try XCTUnwrap(entered.notifications.single?.payload.raw[BubblGeofenceTriggerMetadata.triggerKey])
        let exited = BubblGeofenceEngine.evaluate(
            runtimeResponse: response,
            location: outside,
            state: entered.nextState,
            now: now.addingTimeInterval(10)
        )
        var suspendedState = exited.nextState
        suspendedState.ctaSuspensions.insert(triggerKey)
        let reenteredAfterCTA = BubblGeofenceEngine.evaluate(
            runtimeResponse: response,
            location: inside,
            state: suspendedState,
            now: now.addingTimeInterval(240)
        )

        XCTAssertEqual(entered.notifications.single?.payload.raw[BubblGeofenceTriggerMetadata.ctaSuspend], "true")
        XCTAssertEqual(reenteredAfterCTA.transitions.single?.type, .enter)
        XCTAssertTrue(reenteredAfterCTA.notifications.isEmpty)
    }

    func testGeofenceEngineUsesConfigurationFrequencyDefaultsWhenNotificationPolicyIsMissing() throws {
        let response = geofenceRuntimeResponseWithDeliveryPolicy(
            deliveryPolicy: nil,
            configurationFrequencyDefaults: """
                {
                  "coolingPeriodSeconds": 0,
                  "maximumTriggers": 1,
                  "ctaSuspend": false
                }
            """
        )
        let inside = BubblLocation(latitude: 51.50158, longitude: -0.141)
        let outside = BubblLocation(latitude: 51.500, longitude: -0.141)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-05T10:00:00Z"))

        let entered = BubblGeofenceEngine.evaluate(
            runtimeResponse: response,
            location: inside,
            state: BubblGeofenceState(),
            now: now
        )
        let exited = BubblGeofenceEngine.evaluate(
            runtimeResponse: response,
            location: outside,
            state: entered.nextState,
            now: now.addingTimeInterval(10)
        )
        let reentered = BubblGeofenceEngine.evaluate(
            runtimeResponse: response,
            location: inside,
            state: exited.nextState,
            now: now.addingTimeInterval(20)
        )

        XCTAssertEqual(entered.notifications.single?.payload.title, "Policy hello")
        XCTAssertEqual(reentered.transitions.single?.type, .enter)
        XCTAssertTrue(reentered.notifications.isEmpty)
    }

    func testGeofenceEngineGatesSameNotificationAcrossCampaignLocations() throws {
        let response = geofenceRuntimeResponseWithTwoLocationsSameNotification()
        let firstLocation = BubblLocation(latitude: 51.50158, longitude: -0.141)
        let secondLocation = BubblLocation(latitude: 51.50358, longitude: -0.141)
        let outside = BubblLocation(latitude: 51.500, longitude: -0.141)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-05T10:00:00Z"))

        let firstEntered = BubblGeofenceEngine.evaluate(
            runtimeResponse: response,
            location: firstLocation,
            state: BubblGeofenceState(),
            now: now
        )
        let exited = BubblGeofenceEngine.evaluate(
            runtimeResponse: response,
            location: outside,
            state: firstEntered.nextState,
            now: now.addingTimeInterval(30)
        )
        let secondEntered = BubblGeofenceEngine.evaluate(
            runtimeResponse: response,
            location: secondLocation,
            state: exited.nextState,
            now: now.addingTimeInterval(60)
        )

        XCTAssertEqual(firstEntered.notifications.single?.payload.title, "Welcome")
        XCTAssertEqual(secondEntered.transitions.single?.type, .enter)
        XCTAssertTrue(secondEntered.notifications.isEmpty)
    }

    func testGeofenceEngineAllowsDistinctNotificationsInSameCampaign() throws {
        let entered = BubblGeofenceEngine.evaluate(
            runtimeResponse: geofenceRuntimeResponseWithDistinctEnterNotifications(),
            location: BubblLocation(latitude: 51.50158, longitude: -0.141),
            state: BubblGeofenceState(),
            now: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-05T10:00:00Z"))
        )

        XCTAssertEqual(
            entered.notifications.map(\.payload.title),
            ["First welcome", "Second welcome"]
        )
    }

    func testRefreshGeofenceRoutesEnterTransitionThroughNotificationEngine() async throws {
        let presenter = MockNotificationPresenter()
        let transport = MockTransport { request in
            if request.url.path == "/api/check-geofence" {
                return BubblHTTPResponse(statusCode: 200, data: self.geofenceRuntimeResponse())
            }

            return BubblHTTPResponse(statusCode: 200, data: #"{"success":true}"#.data(using: .utf8)!)
        }
        let sdk = BubblClient(
            storageDirectory: temporaryDirectory(),
            transport: transport,
            notificationPresenter: presenter
        )

        _ = try await sdk.boot(
            BubblConfig(
                apiKey: "sdk-key",
                runtimeBaseUrl: URL(string: "https://runtime.test")!,
                ingestBaseUrl: URL(string: "https://ingest.test")!
            )
        )

        try await sdk.refreshGeofence(BubblLocation(latitude: 51.50158, longitude: -0.141))
        try await sdk.refreshGeofence(BubblLocation(latitude: 51.50158, longitude: -0.141))

        XCTAssertEqual(presenter.payloads.count, 1)
        XCTAssertEqual(presenter.payloads.single?.title, "Welcome")
        let diagnostics = await sdk.diagnostics()
        XCTAssertEqual(diagnostics.pendingIngestCount, 1)

        let activities = try transport.requests
            .filter { $0.url.path == "/api/activities" }
            .map { request -> String in
                let body = try XCTUnwrap(request.body)
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                return try XCTUnwrap(json?["activity"] as? String)
            }
        XCTAssertTrue(activities.contains("notification_sent"))
        XCTAssertTrue(activities.contains("notification_delivered"))
    }

    func testGeofenceRegionSelectionCapsToNearestTwenty() {
        let reference = BubblLocation(latitude: 51.5002, longitude: -0.1402)

        let selected = BubblGeofenceEngine.nearestRegionCandidates(
            runtimeResponse: manyGeofenceRuntimeResponse(count: 25),
            near: reference,
            limit: 25
        )

        XCTAssertEqual(selected.count, 20)
        XCTAssertEqual(selected.first?.locationId, "0")
        XCTAssertFalse(selected.contains { $0.locationId == "24" })

        let distances = selected.map { BubblGeofenceEngine.distanceMeters(from: reference, to: $0.center) }
        XCTAssertEqual(distances, distances.sorted())
    }

    func testDefaultNotificationPresentationQueuesDeliveredTelemetry() async throws {
        let presenter = MockNotificationPresenter()
        let transport = MockTransport { _ in
            BubblHTTPResponse(statusCode: 200, data: #"{"success":true}"#.data(using: .utf8)!)
        }
        let sdk = BubblClient(
            storageDirectory: temporaryDirectory(),
            transport: transport,
            notificationPresenter: presenter
        )

        _ = try await sdk.boot(
            BubblConfig(
                apiKey: "sdk-key",
                runtimeBaseUrl: URL(string: "https://runtime.test")!,
                ingestBaseUrl: URL(string: "https://ingest.test")!
            )
        )

        let payload = try await sdk.handleRemoteNotification([
            "aps": ["alert": ["title": "APNs title", "body": "APNs body"]],
            "curated_notification_id": "99",
            "location_id": "12"
        ])

        XCTAssertEqual(payload?.title, "APNs title")
        XCTAssertEqual(presenter.payloads.single?.id, payload?.id)
        let diagnostics = await sdk.diagnostics()
        XCTAssertEqual(diagnostics.pendingIngestCount, 0)

        let paths = transport.requests.map(\.url.path)
        XCTAssertTrue(paths.contains("/api/device-data"))
        XCTAssertTrue(paths.contains("/api/activities"))

        let activityRequests = transport.requests.filter { $0.url.path == "/api/activities" }
        let activities = try activityRequests.map { request -> String in
            let body = try XCTUnwrap(request.body)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(json?["curated_notification_id"] as? Int, 99)
            return try XCTUnwrap(json?["activity"] as? String)
        }
        XCTAssertTrue(activities.contains("notification_sent"))
        XCTAssertTrue(activities.contains("notification_delivered"))
    }

    func testRemoteNotificationRestoresPersistedConfigForBackgroundWake() async throws {
        let directory = temporaryDirectory()
        let presenter = MockNotificationPresenter()
        let transport = MockTransport { _ in
            BubblHTTPResponse(statusCode: 200, data: #"{"success":true}"#.data(using: .utf8)!)
        }
        let bootedSdk = BubblClient(storageDirectory: directory, transport: transport)

        _ = try await bootedSdk.boot(
            BubblConfig(
                apiKey: "sdk-key",
                runtimeBaseUrl: URL(string: "https://runtime.test")!,
                ingestBaseUrl: URL(string: "https://ingest.test")!,
                enableDefaultNotificationModal: false
            )
        )
        await bootedSdk.shutdown()

        let backgroundSdk = BubblClient(
            storageDirectory: directory,
            transport: transport,
            notificationPresenter: presenter
        )

        let payload = try await backgroundSdk.handleRemoteNotification([
            "aps": ["alert": ["title": "Background title", "body": "Background body"]],
            "curated_notification_id": "99",
            "location_id": "12"
        ])

        XCTAssertEqual(payload?.title, "Background title")
        XCTAssertEqual(presenter.payloads.single?.id, payload?.id)
        let restored = try await backgroundSdk.restoreForBackground()
        XCTAssertTrue(restored)

        let activities = try transport.requests
            .filter { $0.url.path == "/api/activities" }
            .map { request -> String in
                let body = try XCTUnwrap(request.body)
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                return try XCTUnwrap(json?["activity"] as? String)
            }
        XCTAssertTrue(activities.contains("notification_sent"))
        XCTAssertTrue(activities.contains("notification_delivered"))
    }

    func testHostRenderedNotificationWithoutCuratedIdDoesNotHitDashboardActivityLookup() async throws {
        let transport = MockTransport { _ in
            BubblHTTPResponse(statusCode: 200, data: #"{"success":true}"#.data(using: .utf8)!)
        }
        let sdk = BubblClient(storageDirectory: temporaryDirectory(), transport: transport)

        _ = try await sdk.boot(
            BubblConfig(
                apiKey: "sdk-key",
                runtimeBaseUrl: URL(string: "https://runtime.test")!,
                ingestBaseUrl: URL(string: "https://ingest.test")!,
                notificationRenderingMode: .hostRendered
            )
        )

        let payload = try await sdk.handleRemoteNotification([
            "aps": ["alert": ["title": "APNs title", "body": "APNs body"]],
            "notification_id": "provider-99"
        ])

        XCTAssertEqual(payload?.id, "provider-99")
        XCTAssertNil(payload?.curatedNotificationId)
        let diagnostics = await sdk.diagnostics()
        XCTAssertEqual(diagnostics.pendingIngestCount, 0)

        let notificationSent = transport.requests.contains { request in
            guard request.url.path == "/api/activities",
                  let body = request.body,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return false
            }
            return json["activity"] as? String == "notification_sent"
        }
        XCTAssertFalse(notificationSent)
    }

    func testNotificationResponseAndInteractionsQueueAnalyticsEvents() async throws {
        let transport = MockTransport { _ in
            BubblHTTPResponse(statusCode: 200, data: #"{"success":true}"#.data(using: .utf8)!)
        }
        let sdk = BubblClient(
            storageDirectory: temporaryDirectory(),
            transport: transport,
            notificationPresenter: MockNotificationPresenter()
        )

        _ = try await sdk.boot(
            BubblConfig(
                apiKey: "sdk-key",
                runtimeBaseUrl: URL(string: "https://runtime.test")!,
                ingestBaseUrl: URL(string: "https://ingest.test")!
            )
        )

        let responsePayload = try await sdk.handleNotificationResponse(
            userInfo: [
                "title": "Opened",
                "body": "Body",
                "curated_notification_id": "100",
                "location_id": "10",
                "cta_label": "Open",
                "cta_url": "https://bubbl.test"
            ],
            actionIdentifier: "open_cta"
        )
        let payload = try XCTUnwrap(responsePayload)
        try await sdk.handleNotificationMediaViewed(payload)
        try await sdk.handleNotificationSurveyRequested(payload)

        let diagnostics = await sdk.diagnostics()
        XCTAssertEqual(diagnostics.pendingIngestCount, 4)

        _ = await sdk.flush()

        let activities = try transport.requests
            .filter { $0.url.path == "/api/activities" }
            .map { request -> String in
                let body = try XCTUnwrap(request.body)
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                return try XCTUnwrap(json?["activity"] as? String)
            }

        XCTAssertTrue(activities.contains("notification_opened"))
        XCTAssertEqual(activities.filter { $0 == "cta_engagment" }.count, 1)
        XCTAssertTrue(activities.contains("media_viewed"))
    }

    func testNotificationOpenQueuesPendingTapUntilFlutterSubscriberDrains() async throws {
        let transport = MockTransport { _ in
            BubblHTTPResponse(statusCode: 200, data: #"{"success":true}"#.data(using: .utf8)!)
        }
        let sdk = BubblClient(storageDirectory: temporaryDirectory(), transport: transport)

        _ = try await sdk.boot(
            BubblConfig(
                apiKey: "sdk-key",
                runtimeBaseUrl: URL(string: "https://runtime.test")!,
                ingestBaseUrl: URL(string: "https://ingest.test")!
            )
        )

        let payload = BubblNotificationPayload(
            id: "tap-1",
            title: "Opened",
            body: "From tray",
            source: .apns,
            locationId: "7",
            curatedNotificationId: "42"
        )

        try await sdk.handleNotificationOpen(payload, action: "default")

        let pending = await sdk.drainPendingNotificationTaps()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.single?.payload.id, "tap-1")
        XCTAssertEqual(pending.single?.action, "default")
        let remaining = await sdk.drainPendingNotificationTaps()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testNotificationOpenDoesNotQueueWhenFlutterSubscriberIsAttached() async throws {
        let transport = MockTransport { _ in
            BubblHTTPResponse(statusCode: 200, data: #"{"success":true}"#.data(using: .utf8)!)
        }
        let sdk = BubblClient(storageDirectory: temporaryDirectory(), transport: transport)

        _ = try await sdk.boot(
            BubblConfig(
                apiKey: "sdk-key",
                runtimeBaseUrl: URL(string: "https://runtime.test")!,
                ingestBaseUrl: URL(string: "https://ingest.test")!
            )
        )

        let subscriberId = await sdk.registerEventSubscriber()

        try await sdk.handleNotificationOpen(
            BubblNotificationPayload(
                id: "tap-2",
                title: "Opened",
                body: "From tray",
                source: .apns
            ),
            action: "default"
        )

        let pending = await sdk.drainPendingNotificationTaps()
        XCTAssertTrue(pending.isEmpty)
        await sdk.unregisterEventSubscriber(subscriberId)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bubbl-sdk-tests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func geofenceRuntimeResponse() -> Data {
        """
            {
              "geoCampaign": [
                {
                  "campaignId": 123,
                  "campaignName": "Spring offers",
                  "type": "GEO",
                  "active": "true",
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
                      "published": true,
                      "coolingPeriodSeconds": 3600,
                      "maximumTriggers": 1
                    },
                    {
                      "curatedNotificationId": 457,
                      "headline": "Goodbye",
                      "body": "See you soon",
                      "type": "notification",
                      "activation": "ON_EXIT",
                      "published": true
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.data(using: .utf8)!
    }

    private func geofenceRuntimeResponseWithDeliveryPolicy(
        deliveryPolicy: String?,
        configurationFrequencyDefaults: String
    ) -> Data {
        let policyBlock = deliveryPolicy.map { #","deliveryPolicy": \#($0)"# } ?? ""

        return """
            {
              "geoCampaign": [
                {
                  "campaignId": 123,
                  "campaignName": "Policy campaign",
                  "type": "GEO",
                  "active": "true",
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
                      "curatedNotificationId": 789,
                      "headline": "Policy hello",
                      "body": "Policy body",
                      "type": "notification",
                      "activation": "ON_ENTER",
                      "published": true
                      \(policyBlock)
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {
                "notificationsCount":10,
                "daysCount":1,
                "batteryCount":10,
                "privacyText":"Privacy",
                "frequencyDefaults": \(configurationFrequencyDefaults)
              }
            }
        """.data(using: .utf8)!
    }

    private func geofenceRuntimeResponseWithTwoLocationsSameNotification() -> Data {
        """
            {
              "geoCampaign": [
                {
                  "campaignId": 123,
                  "campaignName": "Multi-location campaign",
                  "type": "GEO",
                  "active": "true",
                  "locationsArray": [
                    {
                      "locationId": 10,
                      "geofence": [
                        { "position": 1, "latitude": "51.501476", "longitude": "-0.140112" },
                        { "position": 2, "latitude": "51.501800", "longitude": "-0.141000" },
                        { "position": 3, "latitude": "51.501476", "longitude": "-0.142000" }
                      ]
                    },
                    {
                      "locationId": 11,
                      "geofence": [
                        { "position": 1, "latitude": "51.503476", "longitude": "-0.140112" },
                        { "position": 2, "latitude": "51.503800", "longitude": "-0.141000" },
                        { "position": 3, "latitude": "51.503476", "longitude": "-0.142000" }
                      ]
                    }
                  ],
                  "notificationsArray": [
                    {
                      "curatedNotificationId": 456,
                      "headline": "Welcome",
                      "body": "Thanks for visiting",
                      "type": "notification",
                      "activation": "ON_ENTER",
                      "published": true,
                      "coolingPeriodSeconds": 3600,
                      "maximumTriggers": 1
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.data(using: .utf8)!
    }

    private func geofenceRuntimeResponseWithDistinctEnterNotifications() -> Data {
        """
            {
              "geoCampaign": [
                {
                  "campaignId": 123,
                  "campaignName": "Distinct notifications",
                  "type": "GEO",
                  "active": "true",
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
                      "headline": "First welcome",
                      "body": "First",
                      "type": "notification",
                      "activation": "ON_ENTER",
                      "published": true,
                      "maximumTriggers": 1
                    },
                    {
                      "curatedNotificationId": 457,
                      "headline": "Second welcome",
                      "body": "Second",
                      "type": "notification",
                      "activation": "ON_ENTER",
                      "published": true,
                      "maximumTriggers": 1
                    }
                  ]
                }
              ],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.data(using: .utf8)!
    }

    private func manyGeofenceRuntimeResponse(count: Int) -> Data {
        let campaigns = (0..<count).map { index -> String in
            let latitude = 51.5 + (Double(index) * 0.01)
            let longitude = -0.14
            return """
                {
                  "campaignId": \(index),
                  "campaignName": "Region \(index)",
                  "type": "GEO",
                  "active": true,
                  "locationsArray": {
                    "locationId": \(index),
                    "geofence": [
                      { "latitude": "\(latitude)", "longitude": "\(longitude)" },
                      { "latitude": "\(latitude + 0.001)", "longitude": "\(longitude)" },
                      { "latitude": "\(latitude + 0.001)", "longitude": "\(longitude - 0.001)" },
                      { "latitude": "\(latitude)", "longitude": "\(longitude - 0.001)" }
                    ]
                  },
                  "notificationsArray": [
                    {
                      "curatedNotificationId": \(1000 + index),
                      "headline": "Region \(index)",
                      "body": "Body",
                      "activation": "ON_ENTER",
                      "published": true
                    }
                  ]
                }
            """
        }.joined(separator: ",")

        return """
            {
              "geoCampaign": [\(campaigns)],
              "pushCampaign": [],
              "configuration": {"notificationsCount":10,"daysCount":1,"batteryCount":10,"privacyText":"Privacy"}
            }
        """.data(using: .utf8)!
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
