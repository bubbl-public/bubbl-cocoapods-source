import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';

const root = process.cwd();
const failures = [];

function read(relativePath) {
  return readFileSync(join(root, relativePath), 'utf8');
}

function exists(relativePath) {
  return existsSync(join(root, relativePath));
}

function json(relativePath) {
  return JSON.parse(read(relativePath));
}

function yamlValue(source, key) {
  const match = source.match(new RegExp(`^\\s*${key}:\\s*["']?([^"'\\n]+)["']?`, 'm'));
  return match?.[1]?.trim();
}

function propertyValue(source, key) {
  const match = source.match(new RegExp(`^${key}=(.+)$`, 'm'));
  return match?.[1]?.trim();
}

function check(id, pass, detail) {
  if (!pass) failures.push({ id, detail });
}

const rootPackage = json('package.json');
const version = rootPackage.version;
const androidBuild = read('android/build.gradle.kts');
const androidProperties = read('android/gradle.properties');
const iosPodspec = read('ios/BubblSDK.podspec');
const flutterPubspec = read('flutter/pubspec.yaml');
const rnPackage = json('react-native/package.json');

check('version.root', /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(version), `Root version must be SemVer, got ${version}.`);
check('version.android', propertyValue(androidProperties, 'VERSION_NAME') === version, 'android/gradle.properties VERSION_NAME must match package.json.');
check('version.flutter', yamlValue(flutterPubspec, 'version') === version, 'flutter/pubspec.yaml version must match package.json.');
check('version.react-native', rnPackage.version === version, 'react-native/package.json version must match package.json.');
check('version.ios', iosPodspec.includes(`s.version = '${version}'`), 'ios/BubblSDK.podspec version must match package.json.');

const refName = process.env.GITHUB_REF_NAME;
if (refName && process.env.GITHUB_REF_TYPE === 'tag') {
  check('version.git-tag', refName === version, `Release tag must exactly match package version. Tag: ${refName}; version: ${version}.`);
}

check('android.package-space', propertyValue(androidProperties, 'GROUP') === 'tech.bubbl.sdk', 'Android must keep Maven group tech.bubbl.sdk.');
check('android.artifact', /coordinates\([\s\S]*"bubbl-sdk"/.test(androidBuild), 'Android must keep Maven artifact bubbl-sdk.');
check('android.central-portal', /com\.vanniktech\.maven\.publish/.test(androidBuild) && /SonatypeHost\.CENTRAL_PORTAL/.test(androidBuild), 'Android must publish through the Maven Central Portal lane.');

check('ios.primary-pod', /s\.name = 'BubblSDK'/.test(iosPodspec), 'iOS primary pod must remain BubblSDK.');
const iosAliasPodspec = exists('ios/Bubbl-Sdk.podspec') ? read('ios/Bubbl-Sdk.podspec') : '';
check('ios.legacy-alias', /s\.name = 'Bubbl-Sdk'/.test(iosAliasPodspec), 'iOS legacy Bubbl-Sdk alias podspec must exist.');
check('ios.legacy-alias-version', iosAliasPodspec.includes(`s.version = '${version}'`), 'iOS legacy Bubbl-Sdk alias version must match package.json.');
check('ios.source', /github\.com\/bubbl-repo\/renewed-sdk\.git/.test(iosPodspec), 'iOS podspec source must point at renewed-sdk.');

check('flutter.package-space', yamlValue(flutterPubspec, 'name') === 'bubbl_flutter_sdk', 'Flutter must keep pub.dev package bubbl_flutter_sdk.');
check('flutter.publishable', !/^\s*publish_to:\s*none\s*$/m.test(flutterPubspec), 'Flutter pubspec must be publishable.');

check('react-native.package-space', rnPackage.name === '@bubbl-tech/react-native-sdk', 'React Native npm package name must be @bubbl-tech/react-native-sdk.');
check('react-native.public', rnPackage.publishConfig?.access === 'public', 'React Native publishConfig.access must be public.');

check('workflow.release', exists('.github/workflows/sdk-release.yml'), 'Monorepo release workflow must exist.');
if (exists('.github/workflows/sdk-release.yml')) {
  const workflow = read('.github/workflows/sdk-release.yml');
  for (const expected of ['publishAndReleaseToMavenCentral', 'dart-lang/setup-dart/.github/workflows/publish.yml@v1', 'pod trunk push', 'npm publish']) {
    check(`workflow.${expected}`, workflow.includes(expected), `Release workflow must include ${expected}.`);
  }
  check(
    'workflow.private-registry-gate',
    workflow.includes('BUBBL_PUBLIC_REGISTRY_RELEASE') && workflow.includes("needs.validate.outputs.public_registry_release == 'true'"),
    'Public registry publish jobs must be gated behind BUBBL_PUBLIC_REGISTRY_RELEASE.',
  );
  check(
    'workflow.cocoapods-private-safe',
    workflow.includes('BUBBL_COCOAPODS_TRUNK_RELEASE') && workflow.includes('github.event.repository.private'),
    'CocoaPods trunk publish must be separately gated and disabled for private repositories.',
  );
}

console.log('# Bubbl SDK Release Config');
console.log('');
if (failures.length === 0) {
  console.log(`Status: READY (${version})`);
  process.exit(0);
}

console.log(`Status: NOT READY (${version})`);
for (const failure of failures) {
  console.log(`[FAIL] ${failure.id}: ${failure.detail}`);
}
process.exit(1);
