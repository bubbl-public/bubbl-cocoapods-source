library bubbl_flutter_sdk;

export 'src/models.dart';

import 'dart:async';

import 'package:flutter/services.dart';

import 'src/models.dart';

class BubblSdk {
  BubblSdk._();

  static final BubblSdk instance = BubblSdk._();

  static const MethodChannel _methods = MethodChannel(
    'tech.bubbl.sdk/flutter/methods',
  );
  static const EventChannel _eventChannel = EventChannel(
    'tech.bubbl.sdk/flutter/events',
  );

  late final Stream<BubblEvent> events = _eventChannel
      .receiveBroadcastStream()
      .map((event) => _eventFromMap(_asMap(event)));

  Future<BubblBootResult> boot(BubblConfig config) async {
    if (config.apiKey.trim().isEmpty) {
      throw ArgumentError.value(config.apiKey, 'apiKey', 'apiKey is required');
    }

    final result = await _invokeMap('boot', config._toMap());
    return _bootResultFromMap(result);
  }

  Future<void> shutdown() => _invokeVoid('shutdown');
  Future<void> startLocationTracking() => _invokeVoid('startLocationTracking');
  Future<void> stopLocationTracking() => _invokeVoid('stopLocationTracking');
  Future<void> refresh() => _invokeVoid('refresh');

  Future<void> refreshGeofence(BubblLocation location) =>
      _invokeVoid('refreshGeofence', location._toMap());

  Future<void> handleLocationUpdate(BubblLocation location) =>
      _invokeVoid('handleLocationUpdate', location._toMap());

  Future<void> refreshPush() => _invokeVoid('refreshPush');

  Future<BubblConfiguration?> getConfiguration() async {
    final result = await _methods.invokeMethod<Object?>('getConfiguration');
    if (result == null) return null;
    return _configurationFromMap(_asMap(result));
  }

  Future<String> getPrivacyText() async =>
      (await _methods.invokeMethod<String>('getPrivacyText')) ?? '';

  Future<void> updateSegments(List<String> tags) =>
      _invokeVoid('updateSegments', <String, Object?>{'tags': tags});

  Future<void> setCorrelationId(String value) =>
      _invokeVoid('setCorrelationId', <String, Object?>{'value': value});

  Future<void> clearCorrelationId() => _invokeVoid('clearCorrelationId');

  Future<void> setDefaultNotificationModalEnabled(bool enabled) =>
      _invokeVoid('setDefaultNotificationModalEnabled', <String, Object?>{
        'enabled': enabled,
      });

  Future<void> disableDefaultNotificationModal() =>
      setDefaultNotificationModalEnabled(false);

  Future<void> enableDefaultNotificationModal() =>
      setDefaultNotificationModalEnabled(true);

  Future<void> registerPushToken(String token) =>
      _invokeVoid('registerPushToken', <String, Object?>{'token': token});

  Future<BubblNotificationPayload?> handleFirebasePayload(
    Map<String, String> payload,
  ) async {
    final result = await _methods.invokeMethod<Object?>(
      'handleFirebasePayload',
      <String, Object?>{'payload': payload},
    );
    if (result == null) return null;
    return _notificationPayloadFromMap(_asMap(result));
  }

  Future<BubblNotificationDisplayResult> showNotification(
    BubblNotificationPayload payload,
  ) async {
    final result = await _invokeMap('showNotification', payload._toMap());
    return _displayResultFromMap(result);
  }

  Future<BubblNotificationDisplayResult> handleNotificationPayload(
    BubblNotificationPayload payload,
  ) async {
    final result = await _invokeMap(
      'handleNotificationPayload',
      payload._toMap(),
    );
    return _displayResultFromMap(result);
  }

  Future<void> handleNotificationOpen(
    BubblNotificationPayload payload, {
    String? action,
  }) => _invokeVoid('handleNotificationOpen', <String, Object?>{
    'payload': payload._toMap(),
    if (action != null) 'action': action,
  });

  Future<bool> openNotificationModal(
    BubblNotificationPayload payload, {
    String? action,
  }) async {
    final result = await _methods.invokeMethod<bool>(
      'openNotificationModal',
      <String, Object?>{
        'payload': payload._toMap(),
        if (action != null) 'action': action,
      },
    );
    return result ?? false;
  }

  Future<void> handleNotificationCta(
    BubblNotificationPayload payload, {
    String? action,
  }) => _invokeVoid('handleNotificationCta', <String, Object?>{
    'payload': payload._toMap(),
    if (action != null) 'action': action,
  });

  Future<void> handleNotificationMediaViewed(
    BubblNotificationPayload payload,
  ) => _invokeVoid('handleNotificationMediaViewed', payload._toMap());

  Future<void> handleNotificationSurveyRequested(
    BubblNotificationPayload payload,
  ) => _invokeVoid('handleNotificationSurveyRequested', payload._toMap());

  Future<void> track(BubblTrackEvent event) =>
      _invokeVoid('track', event._toMap());

  Future<void> submitSurveyResponse(BubblSurveyResponse response) =>
      _invokeVoid('submitSurveyResponse', response._toMap());

  Future<BubblFlushResult> flush() async {
    final result = await _invokeMap('flush');
    return BubblFlushResult(pendingCount: _int(result['pendingCount']));
  }

  Future<BubblDiagnostics> diagnostics() async {
    final result = await _invokeMap('diagnostics');
    return _diagnosticsFromMap(result);
  }

  static Future<void> _invokeVoid(String method, [Object? arguments]) async {
    await _methods.invokeMethod<void>(method, arguments);
  }

  static Future<Map<String, Object?>> _invokeMap(
    String method, [
    Object? arguments,
  ]) async {
    final result = await _methods.invokeMethod<Object?>(method, arguments);
    return _asMap(result);
  }
}

extension on BubblConfig {
  Map<String, Object?> _toMap() => <String, Object?>{
    'apiKey': apiKey,
    'environment': environment.name,
    'runtimeBaseUrl': runtimeBaseUrl,
    'transmissionBaseUrl': transmissionBaseUrl,
    'ingestBaseUrl': ingestBaseUrl,
    'segments': segments,
    'correlationId': correlationId,
    'defaultDistanceMeters': defaultDistanceMeters,
    'refreshIntervalSeconds': refreshIntervalSeconds,
    'enablePushHandling': enablePushHandling,
    'enableLocationTracking': enableLocationTracking,
    'notificationRenderingMode': notificationRenderingMode.name,
    'enableDefaultNotificationModal': enableDefaultNotificationModal,
    'enableDefaultSurveyUi': enableDefaultSurveyUi,
    'logLevel': logLevel.name,
  };
}

extension on BubblLocation {
  Map<String, Object?> _toMap() => <String, Object?>{
    'latitude': latitude,
    'longitude': longitude,
  };
}

extension on BubblTrackEvent {
  Map<String, Object?> _toMap() => <String, Object?>{
    'type': type,
    'activity': activity,
    'locationId': locationId,
    'curatedNotificationId': curatedNotificationId,
    'latitude': latitude,
    'longitude': longitude,
  };
}

extension on BubblSurveyResponse {
  Map<String, Object?> _toMap() => <String, Object?>{
    'curatedNotificationId': curatedNotificationId,
    'locationId': locationId,
    'answers': answers.map((answer) => answer._toMap()).toList(),
  };
}

extension on BubblSurveyAnswer {
  Map<String, Object?> _toMap() => <String, Object?>{
    'questionId': questionId,
    'type': type,
    'value': value,
    'choiceIds': choiceIds,
  };
}

extension on BubblNotificationPayload {
  Map<String, Object?> _toMap() => <String, Object?>{
    'id': id,
    'title': title,
    'body': body,
    'source': source.name,
    'locationId': locationId,
    'curatedNotificationId': curatedNotificationId,
    'correlationId': correlationId,
    'media': media?._toMap(),
    'cta': cta?._toMap(),
    'survey': survey?._toMap(),
    'raw': raw,
  };
}

extension on BubblNotificationMedia {
  Map<String, Object?> _toMap() => <String, Object?>{
    'url': url,
    'type': type,
    'altText': altText,
  };
}

extension on BubblNotificationCta {
  Map<String, Object?> _toMap() => <String, Object?>{
    'label': label,
    'url': url,
    'action': action,
  };
}

extension on BubblNotificationSurvey {
  Map<String, Object?> _toMap() => <String, Object?>{
    'questions': questions.map((question) => question._toMap()).toList(),
  };
}

extension on BubblSurveyQuestion {
  Map<String, Object?> _toMap() => <String, Object?>{
    'id': id,
    'title': title,
    'type': type,
    'choices': choices.map((choice) => choice._toMap()).toList(),
  };
}

extension on BubblSurveyChoice {
  Map<String, Object?> _toMap() => <String, Object?>{'id': id, 'label': label};
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  throw StateError('Expected native map response, got ${value.runtimeType}.');
}

List<String> _stringList(Object? value) => (value as List? ?? const <Object?>[])
    .map((item) => item.toString())
    .toList();

List<Map<String, Object?>> _mapList(Object? value) =>
    (value as List? ?? const <Object?>[]).map(_asMap).toList();

int _int(Object? value) => value is num ? value.toInt() : 0;
double _double(Object? value) => value is num ? value.toDouble() : 0;
bool _bool(Object? value) => value == true;
String? _stringOrNull(Object? value) => value?.toString();

T _enumByName<T extends Enum>(List<T> values, Object? value, T fallback) {
  final name = value?.toString();
  for (final candidate in values) {
    if (candidate.name == name) return candidate;
  }
  return fallback;
}

BubblBootResult _bootResultFromMap(Map<String, Object?> map) => BubblBootResult(
  ready: _bool(map['ready']),
  fromCache: _bool(map['fromCache']),
  deviceRegistered: _bool(map['deviceRegistered']),
  requiresPermission: _stringList(map['requiresPermission']),
  warnings: _stringList(map['warnings']),
);

BubblConfiguration _configurationFromMap(Map<String, Object?> map) =>
    BubblConfiguration(
      notificationsCount: _int(map['notificationsCount']),
      daysCount: _int(map['daysCount']),
      batteryCount: _int(map['batteryCount']),
      privacyText: map['privacyText']?.toString() ?? '',
    );

BubblDiagnostics _diagnosticsFromMap(Map<String, Object?> map) =>
    BubblDiagnostics(
      sdkVersion: map['sdkVersion']?.toString() ?? '3.1.2',
      platform: map['platform']?.toString() ?? 'flutter',
      booted: _bool(map['booted']),
      pendingIngestCount: _int(map['pendingIngestCount']),
      pushTokenSuffix: map['pushTokenSuffix']?.toString(),
    );

BubblLocation _locationFromMap(Map<String, Object?> map) => BubblLocation(
  latitude: _double(map['latitude']),
  longitude: _double(map['longitude']),
);

BubblGeofenceTransition _transitionFromMap(Map<String, Object?> map) =>
    BubblGeofenceTransition(
      type: _enumByName(
        BubblGeofenceTransitionType.values,
        map['type'],
        BubblGeofenceTransitionType.enter,
      ),
      campaignId: _stringOrNull(map['campaignId']),
      locationId: _stringOrNull(map['locationId']),
      location: _locationFromMap(_asMap(map['location'])),
    );

BubblGeofenceVertex _geofenceVertexFromMap(Map<String, Object?> map) =>
    BubblGeofenceVertex(
      latitude: _double(map['latitude']),
      longitude: _double(map['longitude']),
    );

BubblGeofencePolygon _geofencePolygonFromMap(Map<String, Object?> map) =>
    BubblGeofencePolygon(
      campaignId: _stringOrNull(map['campaignId']),
      campaignName: _stringOrNull(map['campaignName']),
      locationId: _stringOrNull(map['locationId']),
      vertices: _mapList(map['vertices']).map(_geofenceVertexFromMap).toList(),
    );

BubblGeofenceCircle _geofenceCircleFromMap(Map<String, Object?> map) =>
    BubblGeofenceCircle(
      campaignId: _stringOrNull(map['campaignId']),
      campaignName: _stringOrNull(map['campaignName']),
      locationId: _stringOrNull(map['locationId']),
      center: _geofenceVertexFromMap(_asMap(map['center'])),
      radiusMeters: _double(map['radiusMeters']),
    );

BubblGeofenceSnapshot _geofenceSnapshotFromMap(Map<String, Object?> map) =>
    BubblGeofenceSnapshot(
      stats: BubblGeofenceSnapshotStats(
        campaignsTotal: _int(_asMap(map['stats'])['campaignsTotal']),
        polygonsTotal: _int(_asMap(map['stats'])['polygonsTotal']),
      ),
      polygons: _mapList(map['polygons']).map(_geofencePolygonFromMap).toList(),
      circles: _mapList(map['circles']).map(_geofenceCircleFromMap).toList(),
    );

BubblNotificationPayload _notificationPayloadFromMap(
  Map<String, Object?> map,
) => BubblNotificationPayload(
  id: map['id']?.toString() ?? '',
  title: map['title']?.toString() ?? '',
  body: map['body']?.toString() ?? '',
  source: _enumByName(
    BubblNotificationSource.values,
    map['source'],
    BubblNotificationSource.manual,
  ),
  locationId: _stringOrNull(map['locationId']),
  curatedNotificationId: _stringOrNull(map['curatedNotificationId']),
  correlationId: _stringOrNull(map['correlationId']),
  media: map['media'] == null
      ? null
      : _notificationMediaFromMap(_asMap(map['media'])),
  cta: map['cta'] == null ? null : _notificationCtaFromMap(_asMap(map['cta'])),
  survey: map['survey'] == null
      ? null
      : _notificationSurveyFromMap(_asMap(map['survey'])),
  raw: (_asNullableMap(map['raw']) ?? const <String, Object?>{}).map(
    (key, value) => MapEntry(key, value?.toString() ?? ''),
  ),
);

Map<String, Object?>? _asNullableMap(Object? value) =>
    value == null ? null : _asMap(value);

BubblNotificationMedia _notificationMediaFromMap(Map<String, Object?> map) =>
    BubblNotificationMedia(
      url: map['url']?.toString() ?? '',
      type: _stringOrNull(map['type']),
      altText: _stringOrNull(map['altText']),
    );

BubblNotificationCta _notificationCtaFromMap(Map<String, Object?> map) =>
    BubblNotificationCta(
      label: map['label']?.toString() ?? '',
      url: _stringOrNull(map['url']),
      action: _stringOrNull(map['action']),
    );

BubblNotificationSurvey _notificationSurveyFromMap(Map<String, Object?> map) =>
    BubblNotificationSurvey(
      questions: (map['questions'] as List? ?? const <Object?>[])
          .map((item) => _surveyQuestionFromMap(_asMap(item)))
          .toList(),
    );

BubblSurveyQuestion _surveyQuestionFromMap(Map<String, Object?> map) =>
    BubblSurveyQuestion(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      choices: (map['choices'] as List? ?? const <Object?>[])
          .map((item) => _surveyChoiceFromMap(_asMap(item)))
          .toList(),
    );

BubblSurveyChoice _surveyChoiceFromMap(Map<String, Object?> map) =>
    BubblSurveyChoice(
      id: map['id']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
    );

BubblNotificationDisplayResult _displayResultFromMap(
  Map<String, Object?> map,
) => BubblNotificationDisplayResult(
  displayed: _bool(map['displayed']),
  reason: _stringOrNull(map['reason']),
);

BubblEvent _eventFromMap(Map<String, Object?> map) {
  switch (map['type']) {
    case 'ready':
      return const BubblReadyEvent();
    case 'diagnostic':
      return BubblDiagnosticEvent(
        _diagnosticsFromMap(_asMap(map['diagnostics'])),
      );
    case 'notificationReceived':
      return BubblNotificationReceivedEvent(
        _notificationPayloadFromMap(_asMap(map['payload'])),
      );
    case 'notificationDisplayed':
      return BubblNotificationDisplayedEvent(
        _notificationPayloadFromMap(_asMap(map['payload'])),
      );
    case 'notificationTapped':
      return BubblNotificationTappedEvent(
        _notificationPayloadFromMap(_asMap(map['payload'])),
        action: _stringOrNull(map['action']),
      );
    case 'notificationCtaTapped':
      return BubblNotificationCtaTappedEvent(
        _notificationPayloadFromMap(_asMap(map['payload'])),
        action: _stringOrNull(map['action']),
      );
    case 'notificationMediaViewed':
      return BubblNotificationMediaViewedEvent(
        _notificationPayloadFromMap(_asMap(map['payload'])),
      );
    case 'notificationSurveyRequested':
      return BubblNotificationSurveyRequestedEvent(
        _notificationPayloadFromMap(_asMap(map['payload'])),
      );
    case 'locationUpdated':
      return BubblLocationUpdatedEvent(
        _locationFromMap(_asMap(map['location'])),
      );
    case 'geofenceSnapshot':
      return BubblGeofenceSnapshotEvent(
        _geofenceSnapshotFromMap(_asMap(map['snapshot'])),
      );
    case 'geofenceEntered':
      return BubblGeofenceEnteredEvent(
        _transitionFromMap(_asMap(map['transition'])),
      );
    case 'geofenceExited':
      return BubblGeofenceExitedEvent(
        _transitionFromMap(_asMap(map['transition'])),
      );
    case 'error':
      return BubblErrorEvent(
        code: map['code']?.toString() ?? 'unknown',
        message: map['message']?.toString() ?? '',
      );
    default:
      return BubblErrorEvent(
        code: 'unknown_event',
        message: 'Unknown Bubbl event type: ${map['type']}',
      );
  }
}
