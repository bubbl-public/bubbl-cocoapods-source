enum BubblEnvironment { development, nightly, staging, production }

enum BubblLogLevel { off, error, warn, info, debug }

enum BubblNotificationRenderingMode { sdkDefault, hostRendered, eventOnly }

enum BubblNotificationSource { firebase, apns, runtime, geofence, manual }

class BubblConfig {
  const BubblConfig({
    required this.apiKey,
    this.environment = BubblEnvironment.staging,
    this.runtimeBaseUrl,
    this.ingestBaseUrl,
    this.segments = const <String>[],
    this.correlationId,
    this.defaultDistanceMeters = 10,
    this.refreshIntervalSeconds = 300,
    this.enablePushHandling = true,
    this.enableLocationTracking = false,
    this.notificationRenderingMode = BubblNotificationRenderingMode.sdkDefault,
    this.enableDefaultNotificationModal = true,
    this.enableDefaultSurveyUi = true,
    this.logLevel = BubblLogLevel.warn,
  });

  final String apiKey;
  final BubblEnvironment environment;
  final String? runtimeBaseUrl;
  final String? ingestBaseUrl;
  final List<String> segments;
  final String? correlationId;
  final int defaultDistanceMeters;
  final int refreshIntervalSeconds;
  final bool enablePushHandling;
  final bool enableLocationTracking;
  final BubblNotificationRenderingMode notificationRenderingMode;
  final bool enableDefaultNotificationModal;
  final bool enableDefaultSurveyUi;
  final BubblLogLevel logLevel;
}

class BubblBootResult {
  const BubblBootResult({
    required this.ready,
    required this.fromCache,
    required this.deviceRegistered,
    required this.requiresPermission,
    required this.warnings,
  });

  final bool ready;
  final bool fromCache;
  final bool deviceRegistered;
  final List<String> requiresPermission;
  final List<String> warnings;
}

class BubblLocation {
  const BubblLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

enum BubblGeofenceTransitionType { enter, exit }

class BubblGeofenceTransition {
  const BubblGeofenceTransition({
    required this.type,
    required this.location,
    this.campaignId,
    this.locationId,
  });

  final BubblGeofenceTransitionType type;
  final BubblLocation location;
  final String? campaignId;
  final String? locationId;
}

class BubblConfiguration {
  const BubblConfiguration({
    required this.notificationsCount,
    required this.daysCount,
    required this.batteryCount,
    required this.privacyText,
  });

  final int notificationsCount;
  final int daysCount;
  final int batteryCount;
  final String privacyText;
}

class BubblTrackEvent {
  const BubblTrackEvent({
    required this.type,
    required this.activity,
    this.locationId,
    this.curatedNotificationId,
    this.latitude,
    this.longitude,
  });

  final String type;
  final String activity;
  final String? locationId;
  final String? curatedNotificationId;
  final double? latitude;
  final double? longitude;
}

class BubblSurveyResponse {
  const BubblSurveyResponse({
    required this.curatedNotificationId,
    required this.answers,
    this.locationId,
  });

  final String curatedNotificationId;
  final String? locationId;
  final List<BubblSurveyAnswer> answers;
}

class BubblSurveyAnswer {
  const BubblSurveyAnswer({
    required this.questionId,
    required this.type,
    this.value,
    this.choiceIds = const <String>[],
  });

  final String questionId;
  final String type;
  final String? value;
  final List<String> choiceIds;
}

class BubblNotificationPayload {
  const BubblNotificationPayload({
    required this.id,
    required this.title,
    required this.body,
    this.source = BubblNotificationSource.manual,
    this.locationId,
    this.curatedNotificationId,
    this.correlationId,
    this.media,
    this.cta,
    this.survey,
    this.raw = const <String, String>{},
  });

  final String id;
  final String title;
  final String body;
  final BubblNotificationSource source;
  final String? locationId;
  final String? curatedNotificationId;
  final String? correlationId;
  final BubblNotificationMedia? media;
  final BubblNotificationCta? cta;
  final BubblNotificationSurvey? survey;
  final Map<String, String> raw;
}

class BubblNotificationMedia {
  const BubblNotificationMedia({required this.url, this.type, this.altText});

  final String url;
  final String? type;
  final String? altText;
}

class BubblNotificationCta {
  const BubblNotificationCta({required this.label, this.url, this.action});

  final String label;
  final String? url;
  final String? action;
}

class BubblNotificationSurvey {
  const BubblNotificationSurvey({
    this.questions = const <BubblSurveyQuestion>[],
  });

  final List<BubblSurveyQuestion> questions;
}

class BubblSurveyQuestion {
  const BubblSurveyQuestion({
    required this.id,
    required this.title,
    required this.type,
    this.choices = const <BubblSurveyChoice>[],
  });

  final String id;
  final String title;
  final String type;
  final List<BubblSurveyChoice> choices;
}

class BubblSurveyChoice {
  const BubblSurveyChoice({required this.id, required this.label});

  final String id;
  final String label;
}

class BubblNotificationDisplayResult {
  const BubblNotificationDisplayResult({required this.displayed, this.reason});

  final bool displayed;
  final String? reason;
}

class BubblFlushResult {
  const BubblFlushResult({required this.pendingCount});

  final int pendingCount;
}

class BubblDiagnostics {
  const BubblDiagnostics({
    this.sdkVersion = '3.0.0-beta.1',
    this.platform = 'flutter',
    this.booted = false,
    this.pendingIngestCount = 0,
  });

  final String sdkVersion;
  final String platform;
  final bool booted;
  final int pendingIngestCount;
}

sealed class BubblEvent {
  const BubblEvent();
}

class BubblReadyEvent extends BubblEvent {
  const BubblReadyEvent();
}

class BubblDiagnosticEvent extends BubblEvent {
  const BubblDiagnosticEvent(this.diagnostics);

  final BubblDiagnostics diagnostics;
}

class BubblNotificationReceivedEvent extends BubblEvent {
  const BubblNotificationReceivedEvent(this.payload);

  final BubblNotificationPayload payload;
}

class BubblNotificationDisplayedEvent extends BubblEvent {
  const BubblNotificationDisplayedEvent(this.payload);

  final BubblNotificationPayload payload;
}

class BubblNotificationTappedEvent extends BubblEvent {
  const BubblNotificationTappedEvent(this.payload, {this.action});

  final BubblNotificationPayload payload;
  final String? action;
}

class BubblNotificationCtaTappedEvent extends BubblEvent {
  const BubblNotificationCtaTappedEvent(this.payload, {this.action});

  final BubblNotificationPayload payload;
  final String? action;
}

class BubblNotificationMediaViewedEvent extends BubblEvent {
  const BubblNotificationMediaViewedEvent(this.payload);

  final BubblNotificationPayload payload;
}

class BubblNotificationSurveyRequestedEvent extends BubblEvent {
  const BubblNotificationSurveyRequestedEvent(this.payload);

  final BubblNotificationPayload payload;
}

class BubblLocationUpdatedEvent extends BubblEvent {
  const BubblLocationUpdatedEvent(this.location);

  final BubblLocation location;
}

class BubblGeofenceEnteredEvent extends BubblEvent {
  const BubblGeofenceEnteredEvent(this.transition);

  final BubblGeofenceTransition transition;
}

class BubblGeofenceExitedEvent extends BubblEvent {
  const BubblGeofenceExitedEvent(this.transition);

  final BubblGeofenceTransition transition;
}

class BubblErrorEvent extends BubblEvent {
  const BubblErrorEvent({required this.code, required this.message});

  final String code;
  final String message;
}
