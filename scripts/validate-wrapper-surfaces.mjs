import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';

const root = process.cwd();
const requiredMethods = [
  'boot',
  'shutdown',
  'startLocationTracking',
  'stopLocationTracking',
  'refresh',
  'refreshGeofence',
  'handleLocationUpdate',
  'refreshPush',
  'getConfiguration',
  'getPrivacyText',
  'updateSegments',
  'setCorrelationId',
  'clearCorrelationId',
  'setDefaultNotificationModalEnabled',
  'setDefaultNotificationModalStyle',
  'registerPushToken',
  'handleFirebasePayload',
  'showNotification',
  'handleNotificationPayload',
  'handleNotificationOpen',
  'openNotificationModal',
  'handleNotificationCta',
  'handleNotificationMediaViewed',
  'handleNotificationSurveyRequested',
  'track',
  'submitSurveyResponse',
  'flush',
  'diagnostics',
];

function read(relativePath) {
  return readFileSync(join(root, relativePath), 'utf8');
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function validateFlutter() {
  const source = read('flutter/lib/bubbl_flutter_sdk.dart');
  const missing = requiredMethods.filter((method) => !new RegExp(`\\b${method}\\s*\\(`).test(source));

  assert(missing.length === 0, `Flutter facade missing methods: ${missing.join(', ')}`);
}

function validateReactNative() {
  const facade = read('react-native/src/index.ts');
  const turboSpec = read('react-native/src/specs/NativeBubblSdk.ts');
  const androidModule = read('react-native/android/src/main/kotlin/tech/bubbl/reactnative/BubblSdkModule.kt');
  const iosModule = read('react-native/ios/BubblSdk.swift');
  const rnConfig = read('react-native/react-native.config.js');
  const podspec = read('react-native/BubblReactNativeSdk.podspec');

  const missingFacade = requiredMethods.filter((method) => !new RegExp(`\\b${method}\\s*\\(`).test(facade));
  const missingSpec = requiredMethods.filter((method) => !new RegExp(`\\b${method}\\s*\\(`).test(turboSpec));
  const missingAndroid = requiredMethods.filter((method) => !new RegExp(`\\bfun\\s+${method}\\s*\\(`).test(androidModule));
  const missingIos = requiredMethods.filter((method) => !new RegExp(`\\bfunc\\s+${method}\\s*\\(`).test(iosModule));

  assert(missingFacade.length === 0, `React Native facade missing methods: ${missingFacade.join(', ')}`);
  assert(missingSpec.length === 0, `React Native TurboModule spec missing methods: ${missingSpec.join(', ')}`);
  assert(missingAndroid.length === 0, `React Native Android module missing methods: ${missingAndroid.join(', ')}`);
  assert(missingIos.length === 0, `React Native iOS module missing methods: ${missingIos.join(', ')}`);
  assert(!/native_not_bound/.test(facade), 'React Native facade still contains native_not_bound scaffold responses.');
  assert(/BubblSdkPackage/.test(rnConfig), 'React Native autolink config does not reference BubblSdkPackage.');
  assert(/BubblSDK/.test(podspec) && /React-Core/.test(podspec), 'React Native podspec must depend on BubblSDK and React-Core.');
  assert(/events\s*:\s*\{/.test(facade) && /BubblSdkEvent/.test(androidModule + iosModule), 'React Native wrapper must expose native SDK events.');
}

const onlyReactNative = process.argv.includes('--react-native');

if (!onlyReactNative) {
  validateFlutter();
}
validateReactNative();

console.log(`Wrapper surface validation passed (${requiredMethods.length} facade methods).`);
