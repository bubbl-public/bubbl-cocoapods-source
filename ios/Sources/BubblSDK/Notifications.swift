import Foundation
import UserNotifications

#if os(iOS)
import UIKit
#endif

public protocol BubblNotificationPresenting {
    func present(_ payload: BubblNotificationPayload) async throws -> BubblNotificationDisplayResult
}

public protocol BubblNotificationAttachmentLoading: Sendable {
    func attachment(for payload: BubblNotificationPayload) async throws -> UNNotificationAttachment?
}

public struct URLSessionBubblNotificationAttachmentLoader: BubblNotificationAttachmentLoading {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("BubblNotificationAttachments", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("BubblNotificationAttachments", isDirectory: true)
    }

    public func attachment(for payload: BubblNotificationPayload) async throws -> UNNotificationAttachment? {
        guard let media = payload.media,
              BubblNotificationAttachmentPlanner.isEligible(media),
              let fileExtension = BubblNotificationAttachmentPlanner.fileExtension(for: media) else {
            return nil
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = BubblNotificationAttachmentPlanner.fileName(
            notificationId: payload.id,
            fileExtension: fileExtension
        )
        let destination = directory.appendingPathComponent(fileName)

        if !FileManager.default.fileExists(atPath: destination.path) {
            let (temporaryURL, _) = try await URLSession.shared.download(from: media.url)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        }

        return try UNNotificationAttachment(identifier: payload.id, url: destination)
    }
}

public enum BubblNotificationAttachmentPlanner {
    public static func isEligible(_ media: BubblNotificationMedia) -> Bool {
        guard media.url.scheme == "http" || media.url.scheme == "https" else {
            return false
        }

        if let type = media.type?.lowercased() {
            return type == "image"
                || type.hasPrefix("image/")
                || type == "video"
                || type.hasPrefix("video/")
                || type == "audio"
                || type.hasPrefix("audio/")
        }

        return fileExtension(for: media) != nil
    }

    public static func fileExtension(for media: BubblNotificationMedia) -> String? {
        let explicit = media.url.pathExtension.lowercased()
        if !explicit.isEmpty {
            return explicit
        }

        guard let type = media.type?.lowercased() else {
            return nil
        }

        if type == "image" { return "jpg" }
        if type == "video" { return "mp4" }
        if type == "audio" { return "mp3" }

        let components = type.split(separator: "/")
        guard components.count == 2 else { return nil }

        switch components[1] {
        case "jpeg":
            return "jpg"
        case "png", "jpg", "gif", "webp", "mp4", "mpeg", "mp3", "wav", "m4a":
            return String(components[1])
        default:
            return nil
        }
    }

    public static func fileName(notificationId: String, fileExtension: String) -> String {
        let safeId = notificationId
            .map { character -> Character in
                character.isLetter || character.isNumber || character == "-" || character == "_"
                    ? character
                    : "_"
            }
        return "\(String(safeId)).\(fileExtension)"
    }
}

public struct SystemBubblNotificationPresenter: BubblNotificationPresenting {
    private let configuredCenter: UNUserNotificationCenter?
    private let attachmentLoader: any BubblNotificationAttachmentLoading

    public init(
        center: UNUserNotificationCenter? = nil,
        attachmentLoader: any BubblNotificationAttachmentLoading = URLSessionBubblNotificationAttachmentLoader()
    ) {
        self.configuredCenter = center
        self.attachmentLoader = attachmentLoader
    }

    public func present(_ payload: BubblNotificationPayload) async throws -> BubblNotificationDisplayResult {
        let center = configuredCenter ?? UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                return BubblNotificationDisplayResult(displayed: false, reason: "notification_permission_denied")
            }
        case .denied:
            return BubblNotificationDisplayResult(displayed: false, reason: "notification_permission_denied")
        default:
            break
        }

        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default
        content.userInfo = payload.userInfo

        if let cta = payload.cta {
            content.categoryIdentifier = BubblNotificationCategory.identifier(for: payload)
            await installCategory(for: cta, identifier: content.categoryIdentifier, center: center)
        }

        if let attachment = try? await attachmentLoader.attachment(for: payload) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: payload.id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        try await center.add(request)
        return BubblNotificationDisplayResult(displayed: true)
    }

    private func installCategory(
        for cta: BubblNotificationCTA,
        identifier: String,
        center: UNUserNotificationCenter
    ) async {
        let action = UNNotificationAction(
            identifier: cta.action ?? BubblNotificationCategory.defaultCTAAction,
            title: cta.label,
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: identifier,
            actions: [action],
            intentIdentifiers: [],
            options: []
        )
        let existing = await notificationCategories(center)
        var categories = Set(existing.filter { $0.identifier != identifier })
        categories.insert(category)
        center.setNotificationCategories(categories)
    }

    private func notificationCategories(_ center: UNUserNotificationCenter) async -> Set<UNNotificationCategory> {
        await withCheckedContinuation { continuation in
            center.getNotificationCategories { categories in
                continuation.resume(returning: categories)
            }
        }
    }
}

private enum BubblNotificationCategory {
    static let defaultCTAAction = "bubbl_cta"

    static func identifier(for payload: BubblNotificationPayload) -> String {
        "bubbl_notification_\(payload.id)"
    }
}

public final class BubblNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let sdk: BubblClient
    private let autoFlush: Bool

    public init(sdk: BubblClient = .shared, autoFlush: Bool = true) {
        self.sdk = sdk
        self.autoFlush = autoFlush
        super.init()
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        #if os(iOS)
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
        #else
        completionHandler([.sound, .badge])
        #endif
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task {
            _ = try? await sdk.handleNotificationResponse(response)
            if autoFlush {
                _ = await sdk.flush()
            }
            completionHandler()
        }
    }
}

#if os(iOS)
@MainActor
public enum BubblNotificationModalPresenter {
    public static func present(
        _ payload: BubblNotificationPayload,
        sdk: BubblClient = .shared
    ) -> Bool {
        guard let presenter = topViewController() else {
            return false
        }

        let viewController = BubblNotificationViewController(payload: payload, sdk: sdk)
        presenter.present(viewController, animated: true)
        return true
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let rootViewController = activeScene?
            .windows
            .first(where: \.isKeyWindow)?
            .rootViewController
            ?? activeScene?.windows.first?.rootViewController

        return topViewController(from: rootViewController)
    }

    private static func topViewController(from root: UIViewController?) -> UIViewController? {
        if let navigation = root as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }

        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }

        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }

        return root
    }
}

@MainActor
public final class BubblNotificationViewController: UIViewController {
    private let payload: BubblNotificationPayload
    private let sdk: BubblClient
    private var selectedChoices: [String: String] = [:]
    private var textAnswers: [String: UITextField] = [:]

    public init(payload: BubblNotificationPayload, sdk: BubblClient = .shared) {
        self.payload = payload
        self.sdk = sdk
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close", for: .normal)
        closeButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        closeButton.accessibilityLabel = "Close notification"
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        }, for: .touchUpInside)
        view.addSubview(closeButton)

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 24,
            leading: 24,
            bottom: 32,
            trailing: 24
        )
        scrollView.addSubview(contentStack)

        let topSpacer = UIView()
        let bottomSpacer = UIView()
        topSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        topSpacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        bottomSpacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.setContentHuggingPriority(.required, for: .vertical)

        contentStack.addArrangedSubview(topSpacer)
        contentStack.addArrangedSubview(stack)
        contentStack.addArrangedSubview(bottomSpacer)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            closeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentStack.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
            topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor)
        ])

        stack.addArrangedSubview(label(payload.title, font: .preferredFont(forTextStyle: .title2), weight: .bold))
        if !payload.body.isEmpty {
            stack.addArrangedSubview(label(payload.body, font: .preferredFont(forTextStyle: .body), weight: .regular))
        }

        if let media = payload.media {
            let button = button(media.altText ?? "View media") { [weak self] in
                guard let self else { return }
                Task {
                    try? await self.sdk.handleNotificationMediaViewed(self.payload)
                    _ = await self.sdk.flush()
                }
                UIApplication.shared.open(media.url)
            }
            stack.addArrangedSubview(button)
        }

        if let cta = payload.cta {
            let button = button(cta.label) { [weak self] in
                guard let self else { return }
                Task {
                    try? await self.sdk.handleNotificationCTA(self.payload, action: cta.action)
                    _ = await self.sdk.flush()
                }
                if let url = cta.url {
                    UIApplication.shared.open(url)
                }
            }
            stack.addArrangedSubview(button)
        }

        if let survey = payload.survey, !survey.questions.isEmpty {
            Task {
                try? await self.sdk.handleNotificationSurveyRequested(self.payload)
                _ = await self.sdk.flush()
            }
            stack.addArrangedSubview(label("Survey", font: .preferredFont(forTextStyle: .title3), weight: .bold))
            survey.questions.forEach { question in
                stack.addArrangedSubview(label(question.title, font: .preferredFont(forTextStyle: .headline), weight: .semibold))

                if question.choices.isEmpty {
                    let input = UITextField()
                    input.borderStyle = .roundedRect
                    input.placeholder = "Your answer"
                    textAnswers[question.id] = input
                    stack.addArrangedSubview(input)
                } else {
                    let choiceStack = UIStackView()
                    choiceStack.axis = .vertical
                    choiceStack.spacing = 8
                    question.choices.forEach { choice in
                        let choiceButton = button(choice.label) { [weak self] in
                            self?.selectedChoices[question.id] = choice.id
                        }
                        choiceButton.contentHorizontalAlignment = .leading
                        choiceStack.addArrangedSubview(choiceButton)
                    }
                    stack.addArrangedSubview(choiceStack)
                }
            }

            stack.addArrangedSubview(button("Submit") { [weak self] in
                self?.submitSurvey()
            })
        }
    }

    private func submitSurvey() {
        guard let curatedNotificationId = payload.curatedNotificationId else {
            return
        }

        let answers = (payload.survey?.questions ?? []).map { question in
            if let choiceId = selectedChoices[question.id] {
                return BubblSurveyAnswer(questionId: question.id, type: question.type, choiceIds: [choiceId])
            }

            return BubblSurveyAnswer(
                questionId: question.id,
                type: question.type,
                value: textAnswers[question.id]?.text
            )
        }

        Task {
            try? await self.sdk.submitSurveyResponse(
                BubblSurveyResponse(
                    curatedNotificationId: curatedNotificationId,
                    locationId: self.payload.locationId,
                    answers: answers
                )
            )
            _ = await self.sdk.flush()
        }
    }

    private func label(_ text: String, font: UIFont, weight: UIFont.Weight) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: font.pointSize, weight: weight)
        label.adjustsFontForContentSizeCategory = true
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private func button(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}
#endif

public enum BubblNotificationPayloadParser {
    public static func fromRuntimeResponse(_ data: Data) -> [BubblNotificationPayload] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        return campaignNotifications(json["pushCampaign"], source: .runtime)
            + campaignNotifications(json["geoCampaign"], source: .geofence)
    }

    public static func fromRemoteNotification(
        _ userInfo: [AnyHashable: Any],
        source: BubblNotificationSource = .apns
    ) -> BubblNotificationPayload? {
        let data = flatten(userInfo)
        let apsAlert = apsAlert(from: userInfo)
        let parsedTitle = firstPresent(data, "title", "headline", "notification_title", "notificationTitle")
            ?? apsAlert.title
        let parsedBody = firstPresent(data, "body", "message", "notification_body", "notificationBody", "description")
            ?? apsAlert.body

        if parsedTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false &&
            parsedBody?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return nil
        }

        let title: String
        if let parsedTitle, !parsedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = parsedTitle
        } else {
            title = "Bubbl"
        }
        let body = parsedBody ?? ""

        let curatedNotificationId = firstPresent(
            data,
            "curated_notification_id",
            "curatedNotificationId",
            "curated_notification",
            "curatedNotification",
            "n_id",
            "nId"
        )
        let locationId = firstPresent(data, "location_id", "locationId", "locationID")
        let id = firstPresent(
            data,
            "id",
            "message_id",
            "messageId",
            "push_id",
            "pushId",
            "notification_id",
            "notificationId",
            "gcm.message_id",
            "google.message_id"
        )
            ?? curatedNotificationId
            ?? stableId(title: title, body: body, curatedNotificationId: curatedNotificationId, locationId: locationId)

        return BubblNotificationPayload(
            id: id,
            title: title,
            body: body,
            source: source,
            locationId: locationId,
            curatedNotificationId: curatedNotificationId,
            correlationId: firstPresent(data, "correlation_id", "correlationId"),
            media: media(from: data),
            cta: cta(from: data),
            survey: survey(from: data),
            raw: data
        )
    }

    public static func fromFirebasePayload(_ payload: [String: String]) -> BubblNotificationPayload? {
        fromRemoteNotification(payload.reduce(into: [AnyHashable: Any]()) { result, item in
            result[item.key] = item.value
        }, source: .firebase)
    }

    private static func campaignNotifications(_ value: Any?, source: BubblNotificationSource) -> [BubblNotificationPayload] {
        guard let campaigns = value as? [[String: Any]] else {
            return []
        }

        return campaigns.flatMap { campaign -> [BubblNotificationPayload] in
            guard campaignIsRuntimeEnabled(campaign),
                  let notifications = campaign["notificationsArray"] as? [[String: Any]] else {
                return []
            }

            return notifications.compactMap { notification in
                guard runtimeBool(notification["published"], default: true) else {
                    return nil
                }

                return runtimePayload(campaign: campaign, notification: notification, source: source)
            }
        }
    }

    static func runtimePayload(
        campaign: [String: Any],
        notification: [String: Any],
        source: BubblNotificationSource
    ) -> BubblNotificationPayload? {
        var merged = campaign
        for (key, value) in notification {
            merged[key] = value
        }
        merged["campaignId"] = campaign["campaignId"]
        merged["campaignName"] = campaign["campaignName"]
        if merged["locationId"] == nil {
            merged["locationId"] = campaignLocationId(campaign)
        }

        if merged["mediaUrl"] == nil,
           let media = notification["media"] as? [Any],
           let firstMedia = media.first {
            if let mediaObject = firstMedia as? [String: Any] {
                merged["mediaUrl"] = firstPresent(mediaObject, "url", "mediaUrl", "media_url", "image", "imageUrl")
                merged["mediaType"] = firstPresent(mediaObject, "type", "mediaType", "media_type")
            } else {
                merged["mediaUrl"] = stringValue(firstMedia)
            }
        }

        if merged["ctaLabel"] == nil,
           let cta = notification["cta"] as? [[String: Any]],
           let firstCTA = cta.first {
            merged["ctaLabel"] = firstPresent(firstCTA, "label", "ctaLabel", "title")
            merged["ctaUrl"] = firstPresent(firstCTA, "url", "ctaUrl", "deepLink", "deep_link")
            merged["ctaAction"] = firstPresent(firstCTA, "action", "ctaAction")
        }

        return fromRemoteNotification(merged, source: source)
    }

    private static func flatten(_ userInfo: [AnyHashable: Any]) -> [String: String] {
        var data: [String: String] = [:]

        for (key, value) in userInfo {
            guard let key = key as? String else { continue }
            if key == "aps" { continue }
            data[key] = stringValue(value)
        }

        for key in ["notification_data", "notificationData", "bubbl_notification", "bubblNotification", "payload", "data"] {
            guard let nested = userInfo[key] else { continue }

            if let dictionary = nested as? [String: Any] {
                merge(dictionary, into: &data)
            } else if let json = nested as? String,
                      let jsonData = json.data(using: .utf8),
                      let dictionary = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                merge(dictionary, into: &data)
            }
        }

        return data
    }

    private static func merge(_ dictionary: [String: Any], into data: inout [String: String]) {
        for (key, value) in dictionary where data[key] == nil {
            data[key] = stringValue(value)
        }
    }

    private static func campaignLocationId(_ campaign: [String: Any]) -> String? {
        if let locationsArray = campaign["locationsArray"] as? [String: Any],
           let locationId = locationsArray["locationId"] {
            return stringValue(locationId)
        }

        if let locations = campaign["locations"] as? [Any],
           let firstLocation = locations.first {
            return stringValue(firstLocation)
        }

        return nil
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

    private static func campaignIsRuntimeEnabled(_ campaign: [String: Any]) -> Bool {
        guard runtimeBool(campaign["active"], default: true) else { return false }

        if runtimeBool(campaign["paused"], default: false) { return false }
        if runtimeBool(campaign["campaignPaused"], default: false) { return false }
        if runtimeBool(campaign["campaign_paused"], default: false) { return false }

        if let status = firstPresent(campaign, "status", "campaignStatus", "campaign_status")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
            return !["paused", "inactive", "disabled", "ended"].contains(status)
        }

        return true
    }

    private static func stringValue(_ value: Any) -> String {
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

    private static func apsAlert(from userInfo: [AnyHashable: Any]) -> (title: String?, body: String?) {
        guard let aps = userInfo["aps"] as? [String: Any] else {
            return (nil, nil)
        }

        if let alert = aps["alert"] as? String {
            return (nil, alert)
        }

        guard let alert = aps["alert"] as? [String: Any] else {
            return (nil, nil)
        }

        return (alert["title"] as? String, alert["body"] as? String)
    }

    private static func media(from data: [String: String]) -> BubblNotificationMedia? {
        guard let rawURL = firstPresent(data, "media_url", "mediaUrl", "image", "image_url", "imageUrl", "picture", "pictureUrl"),
              let url = URL(string: rawURL) else {
            return nil
        }

        return BubblNotificationMedia(
            url: url,
            type: firstPresent(data, "media_type", "mediaType", "image_type", "imageType"),
            altText: firstPresent(data, "media_alt", "mediaAlt", "alt", "altText")
        )
    }

    private static func cta(from data: [String: String]) -> BubblNotificationCTA? {
        guard let label = firstPresent(data, "cta_label", "ctaLabel", "button_label", "buttonLabel", "action_label", "actionLabel") else {
            return nil
        }

        let rawURL = firstPresent(data, "cta_url", "ctaUrl", "url", "deep_link", "deepLink")
        return BubblNotificationCTA(
            label: label,
            url: rawURL.flatMap(URL.init(string:)),
            action: firstPresent(data, "cta_action", "ctaAction", "action")
        )
    }

    private static func survey(from data: [String: String]) -> BubblNotificationSurvey? {
        guard let rawQuestions = firstPresent(data, "questions", "survey_questions", "surveyQuestions"),
              let questionsData = rawQuestions.data(using: .utf8),
              let questionJSON = try? JSONSerialization.jsonObject(with: questionsData) as? [[String: Any]] else {
            return nil
        }

        let questions = questionJSON.enumerated().map { index, question in
            BubblSurveyQuestion(
                id: firstPresent(question, "id", "question_id") ?? String(index),
                title: firstPresent(question, "title", "question") ?? "",
                type: firstPresent(question, "type") ?? "single_choice",
                choices: choices(from: (question["choices"] ?? question["options"]) as? [[String: Any]])
            )
        }

        return BubblNotificationSurvey(questions: questions)
    }

    private static func choices(from json: [[String: Any]]?) -> [BubblSurveyChoice] {
        guard let json else { return [] }

        return json.enumerated().map { index, choice in
            BubblSurveyChoice(
                id: firstPresent(choice, "id", "choice_id") ?? String(index),
                label: firstPresent(choice, "label", "title", "value") ?? ""
            )
        }
    }

    private static func firstPresent(_ data: [String: String], _ keys: String...) -> String? {
        keys.firstNonEmpty { data[$0] }
    }

    private static func firstPresent(_ data: [String: Any], _ keys: String...) -> String? {
        keys.firstNonEmpty { key in
            guard let value = data[key] else { return nil }
            return stringValue(value)
        }
    }

    private static func stableId(
        title: String,
        body: String,
        curatedNotificationId: String?,
        locationId: String?
    ) -> String {
        let seed = [curatedNotificationId, locationId, title, body].compactMap { $0 }.joined(separator: ":")
        var hash: UInt64 = 5_381
        for scalar in seed.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return "bubbl-\(hash)"
    }
}

private extension BubblNotificationPayload {
    var userInfo: [AnyHashable: Any] {
        var info = raw.reduce(into: [AnyHashable: Any]()) { result, item in
            result[item.key] = item.value
        }
        info["bubbl_notification_id"] = id
        info["bubbl_curated_notification_id"] = curatedNotificationId
        info["bubbl_location_id"] = locationId
        info["bubbl_correlation_id"] = correlationId
        info["bubbl_cta_url"] = cta?.url?.absoluteString
        info["bubbl_cta_action"] = cta?.action
        return info
    }
}

private extension Array where Element == String {
    func firstNonEmpty(_ transform: (String) -> String?) -> String? {
        for key in self {
            guard let value = transform(key)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                continue
            }
            return value
        }

        return nil
    }
}
