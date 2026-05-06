import 'package:bubbl_flutter_sdk/bubbl_flutter_sdk.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const BubblWrapperApp());
}

class BubblWrapperApp extends StatelessWidget {
  const BubblWrapperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bubbl SDK Wrapper',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF146C5A)),
        useMaterial3: true,
      ),
      home: const BubblWrapperHome(),
    );
  }
}

class BubblWrapperHome extends StatefulWidget {
  const BubblWrapperHome({super.key});

  @override
  State<BubblWrapperHome> createState() => _BubblWrapperHomeState();
}

class _BubblWrapperHomeState extends State<BubblWrapperHome> {
  final List<String> _log = <String>['Ready to call the local SDK wrapper.'];
  bool _busy = false;
  bool _listening = false;

  Future<void> _run(String label, Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _log.insert(0, '$label...');
    });

    try {
      final message = await action();
      if (!mounted) return;
      setState(() {
        _log.insert(0, message);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _log.insert(0, '$label failed: $error');
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<String> _boot() async {
    final result = await BubblSdk.instance.boot(
      const BubblConfig(
        apiKey: 'local-wrapper-smoke-key',
        environment: BubblEnvironment.staging,
        runtimeBaseUrl: 'https://example.invalid',
        ingestBaseUrl: 'https://example.invalid',
        segments: <String>['local-wrapper', 'beta'],
        correlationId: 'flutter-wrapper-smoke',
        enableLocationTracking: false,
        enablePushHandling: false,
        notificationRenderingMode: BubblNotificationRenderingMode.eventOnly,
        logLevel: BubblLogLevel.debug,
      ),
    );

    return 'Boot: ready=${result.ready}, cache=${result.fromCache}, warnings=${result.warnings.length}';
  }

  Future<String> _diagnostics() async {
    final diagnostics = await BubblSdk.instance.diagnostics();
    return 'Diagnostics: ${diagnostics.sdkVersion} ${diagnostics.platform}, booted=${diagnostics.booted}, pending=${diagnostics.pendingIngestCount}';
  }

  Future<String> _track() async {
    await BubblSdk.instance.track(
      const BubblTrackEvent(
        type: 'local_wrapper_smoke',
        activity: 'button_tap',
        latitude: 51.5072,
        longitude: -0.1276,
      ),
    );
    return 'Track: queued local wrapper smoke event.';
  }

  Future<String> _showNotification() async {
    final result = await BubblSdk.instance.handleNotificationPayload(
      const BubblNotificationPayload(
        id: 'local-wrapper-notification',
        title: 'Bubbl local wrapper',
        body: 'The app can call the local SDK notification surface.',
        source: BubblNotificationSource.manual,
        cta: BubblNotificationCta(label: 'Open', action: 'open', url: null),
      ),
    );
    return 'Notification: displayed=${result.displayed}, reason=${result.reason ?? 'none'}';
  }

  Future<String> _flush() async {
    final result = await BubblSdk.instance.flush();
    return 'Flush: pending=${result.pendingCount}';
  }

  void _listenForEvents() {
    if (_listening) return;
    _listening = true;
    BubblSdk.instance.events.listen(
      (event) {
        if (!mounted) return;
        setState(() {
          _log.insert(0, 'Event: ${event.runtimeType}');
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _log.insert(0, 'Event stream error: $error');
        });
      },
    );
    setState(() {
      _log.insert(0, 'Listening for SDK events.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bubbl SDK Wrapper')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            'Local SDK smoke app',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'This app consumes bubbl_flutter_sdk from ../../flutter and calls the native wrapper surface.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              FilledButton(
                onPressed: _busy ? null : () => _run('Boot', _boot),
                child: const Text('Boot'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run('Diagnostics', _diagnostics),
                child: const Text('Diagnostics'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _run('Track', _track),
                child: const Text('Track'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run('Notification', _showNotification),
                child: const Text('Notification'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _run('Flush', _flush),
                child: const Text('Flush'),
              ),
              OutlinedButton(
                onPressed: _busy || _listening ? null : _listenForEvents,
                child: const Text('Listen'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 20),
          Text('Log', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final item in _log.take(12))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(item),
            ),
        ],
      ),
    );
  }
}
