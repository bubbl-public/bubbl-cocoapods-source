import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:bubbl_flutter_sdk/bubbl_flutter_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('tech.bubbl.sdk/flutter/methods');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'boot':
              final arguments = call.arguments as Map<Object?, Object?>;
              return <String, Object?>{
                'ready': true,
                'fromCache': false,
                'deviceRegistered': false,
                'requiresPermission': <String>[
                  if (arguments['enableLocationTracking'] == true) 'location',
                  if (arguments['enablePushHandling'] == true) 'push',
                ],
                'warnings': <String>[],
              };
            case 'diagnostics':
              return <String, Object?>{
                'sdkVersion': '3.0.0-beta.1',
                'platform': 'flutter',
                'booted': false,
                'pendingIngestCount': 0,
              };
            case 'showNotification':
              return <String, Object?>{'displayed': true};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('boot validates apiKey before invoking native binding', () async {
    expect(
      () => BubblSdk.instance.boot(const BubblConfig(apiKey: '   ')),
      throwsArgumentError,
    );
  });

  test('diagnostics returns scaffold platform defaults', () async {
    final diagnostics = await BubblSdk.instance.diagnostics();

    expect(diagnostics.sdkVersion, '3.0.0-beta.1');
    expect(diagnostics.platform, 'flutter');
    expect(diagnostics.booted, isFalse);
  });

  test('notification payloads serialize through native channel', () async {
    final result = await BubblSdk.instance.showNotification(
      const BubblNotificationPayload(
        id: 'notification-1',
        title: 'Hello',
        body: 'World',
        source: BubblNotificationSource.manual,
        cta: BubblNotificationCta(label: 'Open', url: 'https://bubbl.tech'),
      ),
    );

    expect(result.displayed, isTrue);
  });
}
