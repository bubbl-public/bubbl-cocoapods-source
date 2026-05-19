import Foundation

struct BubblGeofenceEvaluation: Sendable, Equatable {
    let transitions: [BubblGeofenceTransition]
    let notifications: [BubblGeofenceNotificationDispatch]
    let nextState: BubblGeofenceState
}

struct BubblGeofenceNotificationDispatch: Sendable, Equatable {
    let transition: BubblGeofenceTransition
    let payload: BubblNotificationPayload
}

enum BubblGeofenceTriggerMetadata {
    static let triggerKey = "bubblGeofenceTriggerKey"
    static let ctaSuspend = "bubblGeofenceCtaSuspend"
}

struct BubblGeofenceRegionCandidate: Sendable, Codable, Equatable {
    static let defaultMonitoringLimit = 20

    let identifier: String
    let campaignId: String?
    let locationId: String?
    let center: BubblLocation
    let radiusMeters: Double
}

struct BubblGeofenceState: Sendable, Codable, Equatable {
    var regions: [String: BubblGeofenceRegionState] = [:]
    var triggers: [String: BubblGeofenceTriggerState] = [:]
    var ctaSuspensions: Set<String> = []
    var lastLocation: BubblLocation?
}

struct BubblGeofenceRegionState: Sendable, Codable, Equatable {
    var inside: Bool
    var updatedAt: Date
}

struct BubblGeofenceTriggerState: Sendable, Codable, Equatable {
    var count: Int
    var lastTriggeredAt: Date?
}

enum BubblGeofenceEngine {
    static func regionCandidates(runtimeResponse data: Data) -> [BubblGeofenceRegionCandidate] {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return parseCampaigns(json).compactMap(regionCandidate)
    }

    static func nearestRegionCandidates(
        runtimeResponse data: Data,
        near location: BubblLocation?,
        limit: Int = BubblGeofenceRegionCandidate.defaultMonitoringLimit
    ) -> [BubblGeofenceRegionCandidate] {
        let cappedLimit = max(0, min(limit, BubblGeofenceRegionCandidate.defaultMonitoringLimit))
        guard cappedLimit > 0 else { return [] }

        let candidates = regionCandidates(runtimeResponse: data)
        let sorted: [BubblGeofenceRegionCandidate]
        if let location {
            sorted = candidates.sorted {
                distanceMeters(from: location, to: $0.center) < distanceMeters(from: location, to: $1.center)
            }
        } else {
            sorted = candidates
        }

        return Array(sorted.prefix(cappedLimit))
    }

    static func evaluate(
        runtimeResponse data: Data,
        location: BubblLocation,
        state: BubblGeofenceState,
        now: Date = Date()
    ) -> BubblGeofenceEvaluation {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let campaigns = parseCampaigns(json)
        var regions = state.regions
        var triggers = state.triggers
        var transitions: [BubblGeofenceTransition] = []
        var notifications: [BubblGeofenceNotificationDispatch] = []

        for campaign in campaigns {
            let inside = contains(location, polygon: campaign.polygon)
            let previous = state.regions[campaign.regionKey]
            let transitionType: BubblGeofenceTransitionType?

            if inside && previous?.inside != true {
                transitionType = .enter
            } else if !inside && previous?.inside == true {
                transitionType = .exit
            } else {
                transitionType = nil
            }

            regions[campaign.regionKey] = BubblGeofenceRegionState(inside: inside, updatedAt: now)

            guard let transitionType else { continue }

            let transition = BubblGeofenceTransition(
                type: transitionType,
                campaignId: campaign.campaignId,
                locationId: campaign.locationId,
                location: location
            )
            transitions.append(transition)

            for candidate in campaign.notifications where candidate.activation == transitionType {
                let triggerKey = [campaign.regionKey, candidate.payload.id, transitionType.rawValue].joined(separator: ":")
                let previousTrigger = triggers[triggerKey]
                guard candidate.canTrigger(
                    previous: previousTrigger,
                    ctaSuspended: state.ctaSuspensions.contains(triggerKey),
                    now: now
                ) else { continue }

                notifications.append(
                    BubblGeofenceNotificationDispatch(
                        transition: transition,
                        payload: candidate.payload.withGeofenceTriggerMetadata(
                            triggerKey: triggerKey,
                            ctaSuspend: candidate.ctaSuspend
                        )
                    )
                )
                triggers[triggerKey] = BubblGeofenceTriggerState(
                    count: (previousTrigger?.count ?? 0) + 1,
                    lastTriggeredAt: now
                )
            }
        }

        return BubblGeofenceEvaluation(
            transitions: transitions,
            notifications: notifications,
            nextState: BubblGeofenceState(
                regions: regions,
                triggers: triggers,
                ctaSuspensions: state.ctaSuspensions,
                lastLocation: location
            )
        )
    }

    private static func parseCampaigns(_ json: [String: Any]) -> [RuntimeGeofenceCampaign] {
        guard let campaigns = json["geoCampaign"] as? [[String: Any]] else {
            return []
        }

        let defaults = policyDefaults(json)
        var result: [RuntimeGeofenceCampaign] = []

        for (campaignIndex, campaign) in campaigns.enumerated() {
            guard runtimeBool(campaign["active"], default: true) else { continue }

            let campaignId = firstPresent(campaign, "campaignId", "id")
            let campaignPolicy = objectValue(campaign["deliveryPolicy"])
            let baseActivation = firstPresent(campaignPolicy, "activation", "trigger", "event", "eventType")
                ?? firstPresent(campaign, "activation", "trigger", "event", "eventType")
            let baseCooldown = firstInt(campaignPolicy, "coolingPeriodSeconds", "cooldownSeconds", "cooldown")
                ?? firstInt(campaign, "coolingPeriodSeconds", "cooldownSeconds", "cooldown")
            let baseMaximumTriggers = firstInt(campaignPolicy, "maximumTriggers", "maxTriggers")
                ?? firstInt(campaign, "maximumTriggers", "maxTriggers")
            let baseCTASuspend = firstBool(campaignPolicy, "ctaSuspend", "cta_suspend")
                ?? firstBool(campaign, "ctaSuspend", "cta_suspend")
            let notifications = notificationCandidates(
                campaign: campaign,
                campaignActivation: baseActivation,
                campaignCooldownSeconds: baseCooldown,
                campaignMaximumTriggers: baseMaximumTriggers,
                campaignCTASuspend: baseCTASuspend,
                defaults: defaults
            )
            guard !notifications.isEmpty else { continue }

            for shape in locationShapes(campaign) {
                let fallbackKey = "campaign-\(campaignIndex):location-\(result.count)"
                let keyParts = [campaignId, shape.locationId].compactMap { $0 }
                result.append(
                    RuntimeGeofenceCampaign(
                        regionKey: keyParts.isEmpty ? fallbackKey : keyParts.joined(separator: ":"),
                        campaignId: campaignId,
                        locationId: shape.locationId,
                        polygon: shape.polygon,
                        notifications: notifications
                    )
                )
            }
        }

        return result
    }

    private static func notificationCandidates(
        campaign: [String: Any],
        campaignActivation: String?,
        campaignCooldownSeconds: Int?,
        campaignMaximumTriggers: Int?,
        campaignCTASuspend: Bool?,
        defaults: RuntimeGeofencePolicyDefaults
    ) -> [RuntimeGeofenceNotification] {
        guard let notifications = campaign["notificationsArray"] as? [[String: Any]] else {
            return []
        }

        return notifications.compactMap { notification in
            guard runtimeBool(notification["published"], default: true),
                  let payload = BubblNotificationPayloadParser.runtimePayload(
                    campaign: campaign,
                    notification: notification,
                    source: .geofence
                  ) else {
                return nil
            }
            let policy = objectValue(notification["deliveryPolicy"])

            return RuntimeGeofenceNotification(
                payload: payload,
                activation: activation(
                    from: firstPresent(policy, "activation", "trigger", "event", "eventType")
                        ?? firstPresent(notification, "activation", "trigger", "event", "eventType")
                        ?? campaignActivation
                ),
                cooldownSeconds: firstInt(policy, "coolingPeriodSeconds", "cooldownSeconds", "cooldown")
                    ?? firstInt(notification, "coolingPeriodSeconds", "cooldownSeconds", "cooldown")
                    ?? campaignCooldownSeconds
                    ?? defaults.coolingPeriodSeconds,
                maximumTriggers: firstInt(policy, "maximumTriggers", "maxTriggers")
                    ?? firstInt(notification, "maximumTriggers", "maxTriggers")
                    ?? campaignMaximumTriggers
                    ?? defaults.maximumTriggers,
                ctaSuspend: firstBool(policy, "ctaSuspend", "cta_suspend")
                    ?? firstBool(notification, "ctaSuspend", "cta_suspend")
                    ?? campaignCTASuspend
                    ?? defaults.ctaSuspend
            )
        }
    }

    private static func policyDefaults(_ json: [String: Any]) -> RuntimeGeofencePolicyDefaults {
        let defaults = RuntimeGeofencePolicyDefaults()
        guard let configuration = json["configuration"] as? [String: Any],
              let frequencyDefaults = objectValue(configuration["frequencyDefaults"]) else {
            return defaults
        }

        return RuntimeGeofencePolicyDefaults(
            coolingPeriodSeconds: firstInt(frequencyDefaults, "coolingPeriodSeconds", "cooldownSeconds", "cooldown")
                ?? defaults.coolingPeriodSeconds,
            maximumTriggers: firstInt(frequencyDefaults, "maximumTriggers", "maxTriggers")
                ?? defaults.maximumTriggers,
            ctaSuspend: firstBool(frequencyDefaults, "ctaSuspend", "cta_suspend")
                ?? defaults.ctaSuspend
        )
    }

    private static func locationShapes(_ campaign: [String: Any]) -> [RuntimeGeofenceLocationShape] {
        if let location = campaign["locationsArray"] as? [String: Any] {
            return locationShape(location).map { [$0] } ?? []
        }

        if let locations = campaign["locationsArray"] as? [[String: Any]] {
            return locations.compactMap(locationShape)
        }

        return []
    }

    private static func locationShape(_ json: [String: Any]) -> RuntimeGeofenceLocationShape? {
        let points = json["geofence"] as? [Any]
            ?? json["polygon"] as? [Any]
            ?? json["coordinates"] as? [Any]
            ?? []
        let polygon = polygon(from: points)
        guard polygon.count >= 3 else { return nil }

        return RuntimeGeofenceLocationShape(
            locationId: firstPresent(json, "locationId", "location_id", "id"),
            polygon: polygon
        )
    }

    private static func polygon(from points: [Any]) -> [GeoPoint] {
        points.compactMap { point in
            if let dictionary = point as? [String: Any],
               let latitude = firstDouble(dictionary, "latitude", "lat"),
               let longitude = firstDouble(dictionary, "longitude", "lng", "lon") {
                return GeoPoint(latitude: latitude, longitude: longitude)
            }

            if let array = point as? [Any],
               array.count >= 2,
               let longitude = doubleValue(array[0]),
               let latitude = doubleValue(array[1]) {
                return GeoPoint(latitude: latitude, longitude: longitude)
            }

            return nil
        }
    }

    private static func regionCandidate(from campaign: RuntimeGeofenceCampaign) -> BubblGeofenceRegionCandidate? {
        guard !campaign.polygon.isEmpty else { return nil }

        let latitude = campaign.polygon.map(\.latitude).reduce(0, +) / Double(campaign.polygon.count)
        let longitude = campaign.polygon.map(\.longitude).reduce(0, +) / Double(campaign.polygon.count)
        let center = BubblLocation(latitude: latitude, longitude: longitude)
        let radius = campaign.polygon
            .map { point in
                distanceMeters(
                    from: center,
                    to: BubblLocation(latitude: point.latitude, longitude: point.longitude)
                )
            }
            .max()
            .map { max(100, $0 + 25) }
            ?? 100

        return BubblGeofenceRegionCandidate(
            identifier: regionIdentifier(for: campaign.regionKey),
            campaignId: campaign.campaignId,
            locationId: campaign.locationId,
            center: center,
            radiusMeters: radius
        )
    }

    private static func regionIdentifier(for key: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitized = key.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }

        return "tech.bubbl.sdk.geofence." + String(String(sanitized).prefix(180))
    }

    private static func contains(_ location: BubblLocation, polygon: [GeoPoint]) -> Bool {
        var inside = false
        var previousIndex = polygon.count - 1
        let x = location.longitude
        let y = location.latitude

        for index in polygon.indices {
            let current = polygon[index]
            let previous = polygon[previousIndex]
            let denominator = previous.latitude - current.latitude
            let divisor = denominator == 0 ? Double.leastNonzeroMagnitude : denominator
            let intersects = ((current.latitude > y) != (previous.latitude > y)) &&
                (x < (previous.longitude - current.longitude) * (y - current.latitude) / divisor + current.longitude)
            if intersects {
                inside.toggle()
            }
            previousIndex = index
        }

        return inside
    }

    static func distanceMeters(from start: BubblLocation, to end: BubblLocation) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let latitudeDelta = (end.latitude - start.latitude) * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2) +
            cos(startLatitude) * cos(endLatitude) *
            sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
    }

    private static func activation(from value: String?) -> BubblGeofenceTransitionType {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "ON_EXIT", "EXIT", "GEOFENCE_EXIT":
            return .exit
        default:
            return .enter
        }
    }

    private static func runtimeBool(_ value: Any?, default defaultValue: Bool) -> Bool {
        guard let value else { return defaultValue }

        if let bool = value as? Bool {
            return bool
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }

        if let string = value as? String {
            return string == "1"
                || string.caseInsensitiveCompare("true") == .orderedSame
                || string.caseInsensitiveCompare("yes") == .orderedSame
        }

        return defaultValue
    }

    private static func firstPresent(_ data: [String: Any], _ keys: String...) -> String? {
        guard let key = keys.first(where: { key in
            guard let value = data[key] else { return false }
            return !stringValue(value).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }), let value = data[key] else {
            return nil
        }

        return stringValue(value)
    }

    private static func firstPresent(_ data: [String: Any]?, _ keys: String...) -> String? {
        guard let data else { return nil }

        guard let key = keys.first(where: { key in
            guard let value = data[key] else { return false }
            return !stringValue(value).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }), let value = data[key] else {
            return nil
        }

        return stringValue(value)
    }

    private static func firstInt(_ data: [String: Any], _ keys: String...) -> Int? {
        keys.compactMap { key in
            guard let value = data[key] else { return nil }
            if let int = value as? Int { return int }
            if let number = value as? NSNumber { return number.intValue }
            if let string = value as? String { return Int(string) }
            return nil
        }.first
    }

    private static func firstInt(_ data: [String: Any]?, _ keys: String...) -> Int? {
        guard let data else { return nil }

        return keys.compactMap { key in
            guard let value = data[key] else { return nil }
            if let int = value as? Int { return int }
            if let number = value as? NSNumber { return number.intValue }
            if let string = value as? String { return Int(string) }
            return nil
        }.first
    }

    private static func firstBool(_ data: [String: Any]?, _ keys: String...) -> Bool? {
        guard let data else { return nil }

        return keys.compactMap { key in
            guard let value = data[key] else { return nil }
            if let bool = value as? Bool { return bool }
            if let number = value as? NSNumber { return number.boolValue }
            if let string = value as? String {
                if string == "1" || string.caseInsensitiveCompare("true") == .orderedSame || string.caseInsensitiveCompare("yes") == .orderedSame {
                    return true
                }
                if string == "0" || string.caseInsensitiveCompare("false") == .orderedSame || string.caseInsensitiveCompare("no") == .orderedSame {
                    return false
                }
            }
            return nil
        }.first
    }

    private static func objectValue(_ value: Any?) -> [String: Any]? {
        if let object = value as? [String: Any] {
            return object
        }

        if let string = value as? String,
           let data = string.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }

        return nil
    }

    private static func firstDouble(_ data: [String: Any], _ keys: String...) -> Double? {
        keys.compactMap { key in
            guard let value = data[key] else { return nil }
            return doubleValue(value)
        }.first
    }

    private static func doubleValue(_ value: Any) -> Double? {
        if let double = value as? Double {
            return double
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let string = value as? String {
            return Double(string)
        }

        return nil
    }

    private static func stringValue(_ value: Any) -> String {
        if value is NSNull {
            return ""
        }

        if let string = value as? String {
            return string
        }

        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        return String(describing: value)
    }
}

private struct RuntimeGeofenceCampaign: Sendable, Equatable {
    let regionKey: String
    let campaignId: String?
    let locationId: String?
    let polygon: [GeoPoint]
    let notifications: [RuntimeGeofenceNotification]
}

private struct RuntimeGeofenceLocationShape: Sendable, Equatable {
    let locationId: String?
    let polygon: [GeoPoint]
}

private struct RuntimeGeofenceNotification: Sendable, Equatable {
    let payload: BubblNotificationPayload
    let activation: BubblGeofenceTransitionType
    let cooldownSeconds: Int
    let maximumTriggers: Int?
    let ctaSuspend: Bool

    func canTrigger(previous: BubblGeofenceTriggerState?, ctaSuspended: Bool, now: Date) -> Bool {
        if ctaSuspend && ctaSuspended {
            return false
        }

        if let maximumTriggers, maximumTriggers > 0, (previous?.count ?? 0) >= maximumTriggers {
            return false
        }

        if let lastTriggeredAt = previous?.lastTriggeredAt, cooldownSeconds > 0 {
            return now.timeIntervalSince(lastTriggeredAt) >= Double(cooldownSeconds)
        }

        return true
    }
}

private struct RuntimeGeofencePolicyDefaults: Sendable, Equatable {
    var coolingPeriodSeconds = 259_200
    var maximumTriggers: Int? = 5
    var ctaSuspend = false
}

private struct GeoPoint: Sendable, Equatable {
    let latitude: Double
    let longitude: Double
}

private extension BubblNotificationPayload {
    func withGeofenceTriggerMetadata(triggerKey: String, ctaSuspend: Bool) -> BubblNotificationPayload {
        var updatedRaw = raw
        updatedRaw[BubblGeofenceTriggerMetadata.triggerKey] = triggerKey
        updatedRaw[BubblGeofenceTriggerMetadata.ctaSuspend] = String(ctaSuspend)

        return BubblNotificationPayload(
            id: id,
            title: title,
            body: body,
            source: source,
            locationId: locationId,
            curatedNotificationId: curatedNotificationId,
            correlationId: correlationId,
            media: media,
            cta: cta,
            survey: survey,
            raw: updatedRaw
        )
    }
}
