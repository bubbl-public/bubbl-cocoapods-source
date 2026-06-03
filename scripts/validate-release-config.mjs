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

const refName = process.env.GITHUB_REF_NAME ?? process.env.CI_COMMIT_TAG;
const isTag = process.env.GITHUB_REF_TYPE === 'tag' || Boolean(process.env.CI_COMMIT_TAG);
if (refName && isTag) {
  const tagMatch = refName === version ? [refName, version] : refName.match(/^(?:v|android-|ios-|flutter-|npm-|all-)(.+)$/);
  const normalizedRef = tagMatch?.[1];
  check('version.git-tag-format', Boolean(tagMatch), `Release tag must be the package version or use a supported prefix: android-, ios-, flutter-, npm-, all-, or v. Tag: ${refName}.`);
  check('version.git-tag', normalizedRef === version, `Release tag must match package version, with a supported release prefix. Tag: ${refName}; version: ${version}.`);
}

check('android.package-space', propertyValue(androidProperties, 'GROUP') === 'tech.bubbl.sdk', 'Android must keep Maven group tech.bubbl.sdk.');
check('android.artifact', /coordinates\([\s\S]*"bubbl-sdk"/.test(androidBuild), 'Android must keep Maven artifact bubbl-sdk.');
check('android.central-portal', /com\.vanniktech\.maven\.publish/.test(androidBuild) && /SonatypeHost\.CENTRAL_PORTAL/.test(androidBuild), 'Android must publish through the Maven Central Portal lane.');

check('ios.primary-pod', /s\.name = 'BubblSDK'/.test(iosPodspec), 'iOS primary pod must remain BubblSDK.');
const iosAliasPodspec = exists('ios/Bubbl-Sdk.podspec') ? read('ios/Bubbl-Sdk.podspec') : '';
check('ios.legacy-alias', /s\.name = 'Bubbl-Sdk'/.test(iosAliasPodspec), 'iOS legacy Bubbl-Sdk alias podspec must exist.');
check('ios.legacy-alias-version', iosAliasPodspec.includes(`s.version = '${version}'`), 'iOS legacy Bubbl-Sdk alias version must match package.json.');
check('ios.source', /github\.com\/bubbl-platform\/renewed-sdk\.git/.test(iosPodspec), 'iOS podspec source must point at renewed-sdk.');

check('flutter.package-space', yamlValue(flutterPubspec, 'name') === 'bubbl_flutter_sdk', 'Flutter must keep pub.dev package bubbl_flutter_sdk.');
check('flutter.publishable', !/^\s*publish_to:\s*none\s*$/m.test(flutterPubspec), 'Flutter pubspec must be publishable.');

check('react-native.package-space', rnPackage.name === '@bubblsdk/react-native-sdk', 'React Native npm package name must be @bubblsdk/react-native-sdk.');
check('react-native.public', rnPackage.publishConfig?.access === 'public', 'React Native publishConfig.access must be public.');

const hasGitLabCi = exists('.gitlab-ci.yml');
const hasGitHubRelease = exists('.github/workflows/sdk-release.yml');
check('workflow.release', hasGitLabCi || hasGitHubRelease, 'Monorepo release workflow must exist.');

if (hasGitLabCi) {
  const workflow = read('.gitlab-ci.yml');
  for (const expected of ['publishAndReleaseToMavenCentral', 'BUBBL_PUBLIC_REGISTRY_RELEASE', 'MAVEN_CENTRAL_USERNAME', 'flutter pub publish', 'PUB_DEV_GOOGLE_SERVICE_ACCOUNT_KEY_B64', 'PUB_DEV_CREDENTIALS_B64', 'npm publish', 'NPM_TOKEN']) {
    check(`workflow.${expected}`, workflow.includes(expected), `Legacy release workflow must include ${expected}.`);
  }
}

if (hasGitHubRelease) {
  const workflow = read('.github/workflows/sdk-release.yml');
  for (const expected of ['publishAndReleaseToMavenCentral', 'flutter pub publish', 'npm publish']) {
    check(`github-workflow.${expected}`, workflow.includes(expected), `GitHub release workflow must include ${expected}.`);
  }
  check(
    'github-workflow.public-registry-gate',
    workflow.includes('BUBBL_PUBLIC_REGISTRY_RELEASE') && workflow.includes("needs.validate.outputs.public_registry_release == 'true'"),
    'Public registry publish jobs must be gated behind BUBBL_PUBLIC_REGISTRY_RELEASE.',
  );
  check(
    'github-workflow.github-hosted-runners',
    workflow.includes('runs-on: ubuntu-latest') &&
      workflow.includes('runs-on: macos-15') &&
      !/codebuild-[\w-]+-runner/.test(workflow),
    'GitHub public publish jobs must use GitHub-hosted Linux/macOS runners, not CodeBuild runner labels.',
  );
  check(
    'github-workflow.ios-cocoapods',
    workflow.includes('iOS SDK checks') &&
      workflow.includes('iOS CocoaPods') &&
      workflow.includes('scripts/build-ios-xcframework.sh') &&
      workflow.includes('scripts/cocoapods-lint.sh') &&
      workflow.includes('scripts/cocoapods-publish.sh') &&
      workflow.includes('COCOAPODS_TRUNK_TOKEN') &&
      workflow.includes('BUBBL_COCOAPODS_TRUNK_RELEASE') &&
      workflow.includes('BUBBL_COCOAPODS_SOURCE_URL'),
    'GitHub release workflow must build/lint/publish the iOS SDK and CocoaPods trunk from GitHub-hosted macOS runners.',
  );
  check(
    'github-workflow.no-codemagic-sdk-release',
    !workflow.includes('api.codemagic.io') &&
      !workflow.includes('CODEMAGIC_API_KEY') &&
      !workflow.includes('cm-ios-sdk-'),
    'SDK release workflow must not trigger Codemagic.',
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
