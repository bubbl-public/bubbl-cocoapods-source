import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';

const root = process.cwd();
const strict = process.argv.includes('--strict');

function read(relativePath) {
  return readFileSync(join(root, relativePath), 'utf8');
}

function exists(relativePath) {
  return existsSync(join(root, relativePath));
}

function listFiles(relativePath) {
  const absolute = join(root, relativePath);
  if (!existsSync(absolute)) return [];

  return readdirSync(absolute)
    .map((name) => join(absolute, name))
    .filter((path) => statSync(path).isFile());
}

function json(relativePath) {
  return JSON.parse(read(relativePath));
}

function yamlVersion(source) {
  const match = source.match(/^\s*version:\s*["']?([^"'\n]+)["']?/m);
  return match?.[1]?.trim();
}

function add(checks, severity, id, pass, title, detail) {
  checks.push({ severity, id, pass, title, detail });
}

const packageJson = json('package.json');
const checks = [];
const version = packageJson.version;

add(
  checks,
  'blocker',
  'release.version-not-alpha',
  !/-alpha(?:\.|$)/.test(version),
  'Release version is still alpha',
  `Root package version is ${version}. Production should be beta/rc/ga before strict readiness passes.`,
);

const transportMap = json('contracts/transport-map.json');
add(
  checks,
  'blocker',
  'contracts.transport-version',
  transportMap.contractVersion === version,
  'Transport map version matches package version',
  `contracts/transport-map.json has ${transportMap.contractVersion}; package.json has ${version}.`,
);

add(
  checks,
  'blocker',
  'contracts.openapi-version',
  read('contracts/openapi.yaml').includes(`version: ${version}`),
  'OpenAPI version matches package version',
  `Expected contracts/openapi.yaml info.version to match ${version}.`,
);

const flutterPubspec = read('flutter/pubspec.yaml');
const flutterVersion = yamlVersion(flutterPubspec);
add(
  checks,
  'blocker',
  'release.flutter-version',
  flutterVersion === version,
  'Flutter package version matches package version',
  `flutter/pubspec.yaml has ${flutterVersion}; package.json has ${version}.`,
);

const reactNativePackage = json('react-native/package.json');
add(
  checks,
  'blocker',
  'release.react-native-version',
  reactNativePackage.version === version,
  'React Native package version matches package version',
  `react-native/package.json has ${reactNativePackage.version}; package.json has ${version}.`,
);

add(
  checks,
  'blocker',
  'ci.workflow',
  exists('.gitlab-ci.yml') || listFiles('.github/workflows').some((file) => /\.ya?ml$/.test(file)),
  'CI workflow exists',
  'Production needs a checked-in workflow for contract, native, wrapper, and canary validation.',
);

const rootScripts = packageJson.scripts ?? {};
for (const scriptName of ['test:contracts', 'test:android', 'test:ios', 'test:flutter', 'test:rn', 'test:wrappers']) {
  add(
    checks,
    'blocker',
    `ci.script.${scriptName}`,
    Boolean(rootScripts[scriptName]),
    `Root script ${scriptName} exists`,
    `Missing package.json script: ${scriptName}.`,
  );
}

add(
  checks,
  'blocker',
  'android.publishing',
  (
    /maven-publish/.test(read('android/build.gradle.kts')) && /publishing\s*\{/.test(read('android/build.gradle.kts'))
  ) || (
    /com\.vanniktech\.maven\.publish/.test(read('android/build.gradle.kts')) && /mavenPublishing\s*\{/.test(read('android/build.gradle.kts'))
  ),
  'Android Maven publishing is configured',
  'android/build.gradle.kts needs Maven publication, artifact coordinates, sources/javadoc artifacts, signing, and POM metadata.',
);

add(
  checks,
  'warning',
  'android.gradle-wrapper',
  exists('android/gradlew') || exists('../sdk/bubbl-android-sdk/gradlew'),
  'Android Gradle wrapper is available',
  'The SDK repo should own its Gradle wrapper before release instead of relying on a sibling legacy SDK wrapper.',
);

add(
  checks,
  'blocker',
  'ios.podspec',
  exists('ios/BubblSDK.podspec'),
  'iOS CocoaPods compatibility spec exists',
  'CocoaPods is transitional, but production migration still needs a podspec compatibility path.',
);

add(
  checks,
  'blocker',
  'ios.xcframework-script',
  exists('scripts/build-ios-xcframework.sh'),
  'iOS XCFramework build script exists',
  'Production release needs a repeatable Bubbl.xcframework build path for CI/release artifacts.',
);

add(
  checks,
  'blocker',
  'flutter.native-binding',
  exists('flutter/android') && exists('flutter/ios') && !/native_not_bound|Stream<BubblEvent>\.empty/.test(read('flutter/lib/bubbl_flutter_sdk.dart')),
  'Flutter wrapper is bound to native SDKs',
  'Flutter still has a Dart-only scaffold and must bridge Android/iOS native cores before production.',
);

add(
  checks,
  'blocker',
  'flutter.publishable',
  !/^\s*publish_to:\s*none\s*$/m.test(flutterPubspec),
  'Flutter package is publishable',
  'flutter/pubspec.yaml still has publish_to: none.',
);

add(
  checks,
  'blocker',
  'flutter.tests',
  exists('flutter/test'),
  'Flutter tests exist',
  'Flutter should have wrapper serialization/event tests before production.',
);

add(
  checks,
  'blocker',
  'react-native.native-binding',
  exists('react-native/android') && exists('react-native/ios') && !/native_not_bound/.test(read('react-native/src/index.ts')),
  'React Native wrapper is bound to native SDKs',
  'React Native still has a JS-only scaffold and must bridge Android/iOS native cores before production.',
);

add(
  checks,
  'blocker',
  'react-native.build-script',
  Boolean(reactNativePackage.scripts?.build || reactNativePackage.scripts?.typecheck),
  'React Native build/typecheck script exists',
  'react-native/package.json needs a repeatable typecheck/build command.',
);

add(
  checks,
  'blocker',
  'react-native.tests',
  exists('react-native/test') || exists('react-native/__tests__'),
  'React Native tests exist',
  'React Native should have wrapper serialization/event tests before production.',
);

add(
  checks,
  'warning',
  'notifications.media-richness',
  /BigPictureStyle|UNNotificationAttachment/.test(read('android/src/main/kotlin/tech/bubbl/sdk/Notifications.kt') + read('ios/Sources/BubblSDK/Notifications.swift')),
  'Rich media notification rendering is implemented',
  'Production notification UX still needs Android big-picture rendering and iOS media attachments.',
);

add(
  checks,
  'warning',
  'location.live-canaries',
  /live-movement|provider-delivered|CoreLocation callbacks/i.test(read('LEGACY_PARITY.md')),
  'Live movement canary requirement is tracked',
  'Requirement is tracked, but production still needs real provider/CoreLocation evidence.',
);

add(
  checks,
  'blocker',
  'docs.production-readiness',
  exists('PRODUCTION_READINESS.md'),
  'Production readiness plan exists',
  'Expected PRODUCTION_READINESS.md at repo root.',
);

const failures = checks.filter((check) => !check.pass);
const blockers = failures.filter((check) => check.severity === 'blocker');
const warnings = failures.filter((check) => check.severity === 'warning');

console.log('# Bubbl SDK Production Readiness');
console.log('');
console.log(blockers.length === 0 ? 'Status: READY FOR STRICT RELEASE GATE' : 'Status: NOT READY');
console.log(`Blockers: ${blockers.length}`);
console.log(`Warnings: ${warnings.length}`);
console.log('');

for (const check of failures) {
  const label = check.severity.toUpperCase();
  console.log(`[${label}] ${check.id}: ${check.title}`);
  console.log(`  ${check.detail}`);
}

if (failures.length === 0) {
  console.log('All readiness checks passed.');
}

if (strict && blockers.length > 0) {
  process.exit(1);
}
