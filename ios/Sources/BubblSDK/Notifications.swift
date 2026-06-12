import Foundation
import UserNotifications

#if os(iOS)
import UIKit
import WebKit
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
              let attachmentURL = BubblNotificationAttachmentPlanner.attachmentURL(for: media),
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
            let (temporaryURL, _) = try await URLSession.shared.download(from: attachmentURL)
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

        if youtubeThumbnailURL(for: media) != nil {
            return true
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
        if youtubeThumbnailURL(for: media) != nil {
            return "jpg"
        }

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

    public static func attachmentURL(for media: BubblNotificationMedia) -> URL? {
        guard media.url.scheme == "http" || media.url.scheme == "https" else {
            return nil
        }

        return youtubeThumbnailURL(for: media) ?? media.url
    }

    public static func youtubeEmbedURL(for media: BubblNotificationMedia) -> URL? {
        guard let id = youtubeVideoID(from: media.url) else {
            return nil
        }

        return URL(string: "https://www.youtube.com/embed/\(id)?playsinline=1&rel=0&origin=https%3A%2F%2Fbubbl.tech")
    }

    public static func youtubeEmbedHTML(for embedURL: URL) -> String {
        """
        <!doctype html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
              html, body { margin: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
              iframe { border: 0; width: 100%; height: 100%; background: #000; }
            </style>
          </head>
          <body>
            <iframe src="\(embedURL.absoluteString)" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>
          </body>
        </html>
        """
    }

    public static func inlineMediaHTML(for media: BubblNotificationMedia) -> String {
        let url = escapeHTML(media.url.absoluteString)
        let alt = escapeHTML(media.altText ?? "Notification media")
        let body: String

        if isImageMedia(media) {
            body = #"<img src="\#(url)" alt="\#(alt)" />"#
        } else if isAudioMedia(media) {
            body = #"<audio src="\#(url)" controls preload="metadata"></audio>"#
        } else {
            body = #"<video src="\#(url)" controls playsinline preload="metadata"></video>"#
        }

        return """
        <!doctype html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
              html, body { margin: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
              body { display: flex; align-items: center; justify-content: center; }
              img, video { width: 100%; height: 100%; object-fit: contain; background: #000; }
              audio { width: calc(100% - 24px); }
            </style>
          </head>
          <body>
            \(body)
          </body>
        </html>
        """
    }

    public static func youtubeThumbnailURL(for media: BubblNotificationMedia) -> URL? {
        guard let id = youtubeVideoID(from: media.url) else {
            return nil
        }

        return URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")
    }

    public static func isAudioMedia(_ media: BubblNotificationMedia) -> Bool {
        if let type = media.type?.lowercased() {
            return type == "audio" || type.hasPrefix("audio/")
        }

        let path = media.url.path.lowercased()
        return path.hasSuffix(".mp3")
            || path.hasSuffix(".m4a")
            || path.hasSuffix(".aac")
            || path.hasSuffix(".wav")
            || path.hasSuffix(".ogg")
    }

    public static func isImageMedia(_ media: BubblNotificationMedia) -> Bool {
        if let type = media.type?.lowercased() {
            return type == "image" || type.hasPrefix("image/")
        }

        let path = media.url.path.lowercased()
        return path.hasSuffix(".png")
            || path.hasSuffix(".jpg")
            || path.hasSuffix(".jpeg")
            || path.hasSuffix(".webp")
            || path.hasSuffix(".gif")
    }

    private static func youtubeVideoID(from url: URL) -> String? {
        guard var host = url.host?.lowercased() else {
            return nil
        }

        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }

        let segments = url.pathComponents.filter { $0 != "/" }

        if host == "youtu.be" {
            return validYoutubeID(segments.first)
        }

        guard host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") else {
            return nil
        }

        if let queryId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "v" })?
            .value,
           let valid = validYoutubeID(queryId) {
            return valid
        }

        for marker in ["embed", "shorts", "v"] {
            if let index = segments.firstIndex(of: marker),
               segments.indices.contains(index + 1),
               let valid = validYoutubeID(segments[index + 1]) {
                return valid
            }
        }

        return nil
    }

    private static func validYoutubeID(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.range(of: #"^[A-Za-z0-9_-]{6,}$"#, options: .regularExpression) != nil else {
            return nil
        }

        return value
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
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
    @MainActor private static var installedDelegate: BubblNotificationCenterDelegate?

    private let sdk: BubblClient
    private let autoFlush: Bool

    public init(sdk: BubblClient = .shared, autoFlush: Bool = true) {
        self.sdk = sdk
        self.autoFlush = autoFlush
        super.init()
    }

    @MainActor
    @discardableResult
    public static func installDefault(
        center: UNUserNotificationCenter = .current(),
        sdk: BubblClient = .shared,
        autoFlush: Bool = true
    ) -> BubblNotificationCenterDelegate {
        let delegate = BubblNotificationCenterDelegate(sdk: sdk, autoFlush: autoFlush)
        installedDelegate = delegate
        center.delegate = delegate
        return delegate
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
            await MainActor.run {
                completionHandler()
            }
        }
    }
}

#if os(iOS)
@MainActor
public enum BubblNotificationModalPresenter {
    public static func present(
        _ payload: BubblNotificationPayload,
        sdk: BubblClient = .shared
    ) async -> Bool {
        guard let presenter = topViewController() else {
            return false
        }

        let style = await sdk.defaultNotificationModalStyle()
        let viewController = BubblNotificationViewController(payload: payload, sdk: sdk, style: style)
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
    private let palette: BubblNotificationModalPalette
    private var selectedChoices: [String: String] = [:]
    private var textAnswers: [String: UITextField] = [:]
    private var choiceButtons: [String: [UIButton]] = [:]

    public init(
        payload: BubblNotificationPayload,
        sdk: BubblClient = .shared,
        style: BubblNotificationModalStyle = .default
    ) {
        self.payload = payload
        self.sdk = sdk
        self.palette = BubblNotificationModalPalette(style: style)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = palette.backdropColor

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .always
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        let card = UIView()
        card.backgroundColor = palette.cardBackgroundColor
        card.layer.cornerRadius = palette.cornerRadius
        card.layer.borderColor = palette.cardBorderColor.cgColor
        card.layer.borderWidth = 1
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.16
        card.layer.shadowRadius = 26
        card.layer.shadowOffset = CGSize(width: 0, height: 16)
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 14
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 24, leading: 24, bottom: 22, trailing: 24)
        stack.setContentHuggingPriority(.required, for: .vertical)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        let icon = UILabel()
        icon.text = "!"
        icon.textAlignment = .center
        icon.textColor = palette.iconTextColor
        icon.font = .systemFont(ofSize: 27, weight: .black)
        icon.backgroundColor = palette.iconBackgroundColor
        icon.layer.cornerRadius = 26
        icon.clipsToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(icon)
        stack.addArrangedSubview(iconContainer)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
            card.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            card.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            iconContainer.heightAnchor.constraint(equalToConstant: 52),
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.topAnchor.constraint(equalTo: iconContainer.topAnchor),
            icon.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 52),
            icon.heightAnchor.constraint(equalToConstant: 52)
        ])

        stack.addArrangedSubview(label(payload.title, font: .preferredFont(forTextStyle: .title2), weight: .black, color: palette.titleColor, alignment: .center))
        if !payload.body.isEmpty {
            stack.addArrangedSubview(label(payload.body, font: .preferredFont(forTextStyle: .body), weight: .regular, color: palette.bodyColor, alignment: .center))
        }

        if let media = payload.media {
            trackMediaViewed()
            if let embedURL = BubblNotificationAttachmentPlanner.youtubeEmbedURL(for: media) {
                stack.addArrangedSubview(youtubeMediaView(embedURL: embedURL))
            } else {
                stack.addArrangedSubview(inlineMediaView(media: media))
            }
        }

        if let cta = payload.cta {
            let button = primaryButton(cta.label) { [weak self] in
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
            let surveyPanel = UIStackView()
            surveyPanel.axis = .vertical
            surveyPanel.spacing = 10
            surveyPanel.alignment = .fill
            surveyPanel.isLayoutMarginsRelativeArrangement = true
            surveyPanel.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
            surveyPanel.backgroundColor = palette.surveyBackgroundColor
            surveyPanel.layer.cornerRadius = 18
            surveyPanel.layer.borderColor = palette.cardBorderColor.cgColor
            surveyPanel.layer.borderWidth = 1

            survey.questions.forEach { question in
                surveyPanel.addArrangedSubview(label(question.title, font: .preferredFont(forTextStyle: .headline), weight: .bold, color: palette.titleColor, alignment: .center))

                if question.choices.isEmpty {
                    let input = UITextField()
                    input.placeholder = "Your answer"
                    input.backgroundColor = palette.inputBackgroundColor
                    input.textColor = palette.inputTextColor
                    input.layer.cornerRadius = 14
                    input.layer.borderColor = palette.inputBorderColor.cgColor
                    input.layer.borderWidth = 1
                    input.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
                    input.leftViewMode = .always
                    input.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
                    textAnswers[question.id] = input
                    surveyPanel.addArrangedSubview(input)
                } else {
                    let choiceStack = UIStackView()
                    choiceStack.axis = .vertical
                    choiceStack.spacing = 10
                    choiceButtons[question.id] = []
                    question.choices.forEach { choice in
                        let choiceButton = makeChoiceButton(choice.label)
                        choiceButton.addAction(UIAction { [weak self, weak choiceButton] _ in
                            self?.selectChoice(questionId: question.id, choiceId: choice.id, tappedButton: choiceButton)
                        }, for: .touchUpInside)
                        choiceButton.contentHorizontalAlignment = .leading
                        choiceButtons[question.id]?.append(choiceButton)
                        choiceStack.addArrangedSubview(choiceButton)
                    }
                    surveyPanel.addArrangedSubview(choiceStack)
                }
            }

            let submit = primaryButton("Submit") { [weak self] in
                self?.submitSurvey()
            }
            surveyPanel.addArrangedSubview(submit)
            stack.addArrangedSubview(surveyPanel)
        }

        let closeButton = textButton("Close") { [weak self] in
            self?.dismiss(animated: true)
        }
        stack.addArrangedSubview(closeButton)
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

    private func selectChoice(questionId: String, choiceId: String, tappedButton: UIButton?) {
        selectedChoices[questionId] = choiceId
        choiceButtons[questionId]?.forEach { button in
            applyChoiceStyle(button, selected: button === tappedButton)
        }
    }

    private func label(_ text: String, font: UIFont, weight: UIFont.Weight, color: UIColor, alignment: NSTextAlignment) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: font.pointSize, weight: weight)
        label.textColor = color
        label.textAlignment = alignment
        label.adjustsFontForContentSizeCategory = true
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.setTitleColor(palette.primaryButtonTextColor, for: .normal)
        button.backgroundColor = palette.primaryButtonBackgroundColor
        button.layer.cornerRadius = palette.buttonCornerRadius
        button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 18, bottom: 14, right: 18)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = primaryButton(title, action: action)
        button.setTitleColor(palette.secondaryButtonTextColor, for: .normal)
        button.backgroundColor = palette.secondaryButtonBackgroundColor
        button.layer.borderColor = palette.cardBorderColor.cgColor
        button.layer.borderWidth = 1
        return button
    }

    private func youtubeMediaView(embedURL: URL) -> UIView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.layer.cornerRadius = 16
        webView.clipsToBounds = true
        webView.heightAnchor.constraint(equalToConstant: 210).isActive = true
        webView.loadHTMLString(
            BubblNotificationAttachmentPlanner.youtubeEmbedHTML(for: embedURL),
            baseURL: URL(string: "https://bubbl.tech")
        )
        return webView
    }

    private func inlineMediaView(media: BubblNotificationMedia) -> UIView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.layer.cornerRadius = 16
        webView.clipsToBounds = true
        webView.heightAnchor.constraint(equalToConstant: BubblNotificationAttachmentPlanner.isAudioMedia(media) ? 88 : 210).isActive = true
        webView.loadHTMLString(
            BubblNotificationAttachmentPlanner.inlineMediaHTML(for: media),
            baseURL: URL(string: "https://bubbl.tech")
        )
        return webView
    }

    private func trackMediaViewed() {
        Task {
            try? await sdk.handleNotificationMediaViewed(payload)
            _ = await sdk.flush()
        }
    }

    private func makeChoiceButton(_ title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.lineBreakMode = .byWordWrapping
        button.contentHorizontalAlignment = .center
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
        applyChoiceStyle(button, selected: false)
        return button
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.setTitleColor(palette.textButtonColor, for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func applyChoiceStyle(_ button: UIButton, selected: Bool) {
        button.backgroundColor = selected ? palette.primaryButtonBackgroundColor : palette.inputBackgroundColor
        button.setTitleColor(selected ? palette.primaryButtonTextColor : palette.inputTextColor, for: .normal)
        button.layer.cornerRadius = palette.buttonCornerRadius
        button.layer.borderColor = (selected ? palette.primaryButtonBackgroundColor : palette.inputBorderColor).cgColor
        button.layer.borderWidth = 1
    }
}

private struct BubblNotificationModalPalette {
    let backdropColor: UIColor
    let cardBackgroundColor: UIColor
    let cardBorderColor: UIColor
    let titleColor: UIColor
    let bodyColor: UIColor
    let iconBackgroundColor: UIColor
    let iconTextColor: UIColor
    let primaryButtonBackgroundColor: UIColor
    let primaryButtonTextColor: UIColor
    let secondaryButtonBackgroundColor: UIColor
    let secondaryButtonTextColor: UIColor
    let textButtonColor: UIColor
    let surveyBackgroundColor: UIColor
    let inputBackgroundColor: UIColor
    let inputTextColor: UIColor
    let inputBorderColor: UIColor
    let cornerRadius: CGFloat
    let buttonCornerRadius: CGFloat

    init(style: BubblNotificationModalStyle) {
        let dark = style.theme == .dark
        let ink = dark ? UIColor(red: 0.95, green: 0.97, blue: 1, alpha: 1) : UIColor(red: 0.03, green: 0.07, blue: 0.12, alpha: 1)
        let slate = dark ? UIColor(red: 0.76, green: 0.82, blue: 0.90, alpha: 1) : UIColor(red: 0.29, green: 0.33, blue: 0.40, alpha: 1)
        let card = dark ? UIColor(red: 0.04, green: 0.08, blue: 0.14, alpha: 1) : .white
        let panel = dark ? UIColor(red: 0.07, green: 0.12, blue: 0.20, alpha: 1) : UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1)
        let border = dark ? UIColor(red: 0.18, green: 0.26, blue: 0.36, alpha: 1) : UIColor(red: 0.88, green: 0.91, blue: 0.95, alpha: 1)
        let input = dark ? UIColor(red: 0.02, green: 0.05, blue: 0.09, alpha: 1) : .white
        let secondary = dark ? UIColor(red: 0.12, green: 0.18, blue: 0.27, alpha: 1) : UIColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1)
        let teal = UIColor(red: 0.16, green: 0.77, blue: 0.73, alpha: 1)

        backdropColor = style.transparentBackdrop
            ? .clear
            : UIColor.bubblHex(style.backdropColor, fallback: UIColor(white: 0, alpha: 0.32))
        cardBackgroundColor = UIColor.bubblHex(style.cardBackgroundColor, fallback: card)
        cardBorderColor = UIColor.bubblHex(style.cardBorderColor, fallback: border)
        titleColor = UIColor.bubblHex(style.titleColor, fallback: ink)
        bodyColor = UIColor.bubblHex(style.bodyColor, fallback: slate)
        iconBackgroundColor = UIColor.bubblHex(style.iconBackgroundColor ?? style.accentColor, fallback: teal)
        iconTextColor = UIColor.bubblHex(style.iconTextColor, fallback: dark ? UIColor(red: 0.02, green: 0.05, blue: 0.09, alpha: 1) : ink)
        primaryButtonBackgroundColor = UIColor.bubblHex(style.primaryButtonBackgroundColor ?? style.accentColor, fallback: teal)
        primaryButtonTextColor = UIColor.bubblHex(style.primaryButtonTextColor, fallback: dark ? UIColor(red: 0.02, green: 0.05, blue: 0.09, alpha: 1) : ink)
        secondaryButtonBackgroundColor = UIColor.bubblHex(style.secondaryButtonBackgroundColor, fallback: secondary)
        secondaryButtonTextColor = UIColor.bubblHex(style.secondaryButtonTextColor, fallback: ink)
        textButtonColor = UIColor.bubblHex(style.textButtonColor, fallback: slate)
        surveyBackgroundColor = UIColor.bubblHex(style.surveyBackgroundColor, fallback: panel)
        inputBackgroundColor = UIColor.bubblHex(style.inputBackgroundColor, fallback: input)
        inputTextColor = UIColor.bubblHex(style.inputTextColor, fallback: ink)
        inputBorderColor = UIColor.bubblHex(style.inputBorderColor, fallback: dark ? border : UIColor(red: 0.80, green: 0.84, blue: 0.90, alpha: 1))
        cornerRadius = CGFloat(style.cornerRadius ?? 24)
        buttonCornerRadius = CGFloat(style.buttonCornerRadius ?? 26)
    }
}

private extension UIColor {
    static func bubblHex(_ value: String?, fallback: UIColor) -> UIColor {
        guard var raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return fallback
        }
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard let int = UInt64(raw, radix: 16) else {
            return fallback
        }
        switch raw.count {
        case 6:
            return UIColor(
                red: CGFloat((int >> 16) & 0xff) / 255,
                green: CGFloat((int >> 8) & 0xff) / 255,
                blue: CGFloat(int & 0xff) / 255,
                alpha: 1
            )
        case 8:
            return UIColor(
                red: CGFloat((int >> 24) & 0xff) / 255,
                green: CGFloat((int >> 16) & 0xff) / 255,
                blue: CGFloat((int >> 8) & 0xff) / 255,
                alpha: CGFloat(int & 0xff) / 255
            )
        default:
            return fallback
        }
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
