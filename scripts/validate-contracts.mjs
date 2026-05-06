import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const root = path.resolve(new URL('..', import.meta.url).pathname);

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(root, relativePath), 'utf8'));
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function assertKeys(object, keys, label) {
  for (const key of keys) {
    assert(Object.hasOwn(object, key), `${label} missing required key: ${key}`);
  }
}

function assertString(value, label) {
  assert(typeof value === 'string' && value.length > 0, `${label} must be a non-empty string`);
}

function assertArray(value, label) {
  assert(Array.isArray(value), `${label} must be an array`);
}

const transportMap = readJson('contracts/transport-map.json');
const openApi = fs.readFileSync(path.join(root, 'contracts/openapi.yaml'), 'utf8');

assert(transportMap.contractVersion === '3.0.0-beta.1', 'unexpected contract version');
assert(transportMap.ingest.registerDevice.path === '/api/device-registerd/create', 'Dashboard ingest must mirror legacy device path');
assert(transportMap.ingest.bootBatch.path === '/api/device-data', 'Dashboard ingest must mirror legacy device-data path');
assert(transportMap.ingest.trackGeofenceBatch.path === '/api/geofence-data', 'Dashboard ingest must mirror legacy geofence-data path');
assert(transportMap.ingest.trackEvent.path === '/api/activities', 'Dashboard ingest must mirror legacy activities path');
assert(transportMap.ingest.updateSegments.path === '/api/segments', 'Dashboard ingest must mirror legacy segments path');
assert(transportMap.ingest.submitSurveyResponse.path === '/api/survey-response', 'Dashboard ingest must mirror legacy survey path');
assert(transportMap.runtime.refreshGeofence.publicDistanceUnit === 'meters', 'refreshGeofence public distance unit must be meters');
assert(transportMap.runtime.refreshGeofence.wireDistanceUnit === 'miles', 'refreshGeofence Transmission v2 wire distance unit must be miles');
assert(transportMap.runtime.refreshGeofence.wireShape === 'legacy-transmission-v2', 'refreshGeofence must document Transmission v2 wire compatibility');

const expectedEnvironmentUrls = {
  development: ['https://nightly.api.bubbl.tech', 'https://nightly-platform.bubbl.tech'],
  nightly: ['https://nightly.api.bubbl.tech', 'https://nightly-platform.bubbl.tech'],
  staging: ['https://staging.api.bubbl.tech', 'https://staging-platform.bubbl.tech'],
  production: ['https://production.api.bubbl.tech', 'https://platform.bubbl.tech']
};

for (const [environment, [runtimeBaseUrl, ingestBaseUrl]] of Object.entries(expectedEnvironmentUrls)) {
  assert(
    transportMap.environments?.[environment]?.runtimeBaseUrl === runtimeBaseUrl,
    `${environment} runtimeBaseUrl must mirror legacy SDK endpoint`
  );
  assert(
    transportMap.environments?.[environment]?.ingestBaseUrl === ingestBaseUrl,
    `${environment} ingestBaseUrl must mirror legacy SDK endpoint`
  );
  assert(openApi.includes(`  - url: ${runtimeBaseUrl}`), `OpenAPI missing ${environment} runtime server ${runtimeBaseUrl}`);
  assert(openApi.includes(`  - url: ${ingestBaseUrl}`), `OpenAPI missing ${environment} ingest server ${ingestBaseUrl}`);
}

for (const group of ['runtime', 'ingest']) {
  for (const [name, route] of Object.entries(transportMap[group])) {
    assert(openApi.includes(`  ${route.path}:`), `OpenAPI missing ${group}.${name} path ${route.path}`);
  }
}

const device = readJson('contracts/fixtures/ingest/device-registration.json');
assertKeys(device, [
  'app_name',
  'api_key',
  'sdk_version',
  'platform',
  'os_version',
  'device_model',
  'device_name',
  'manufacturer',
  'country',
  'language',
  'device_id',
  'bubbl_id'
], 'device-registration fixture');
assertString(device.api_key, 'device api_key');
assert(Array.isArray(device.segmentations), 'device segmentations fixture must use array form');

const event = readJson('contracts/fixtures/ingest/event-geofence-entry.json');
assertKeys(event, ['device_registered_id', 'type', 'activity', 'time'], 'event fixture');
assert(['plugin', 'notification', 'geofence', 'media', 'location'].includes(event.type), 'event type is not supported by renewed legacy mirror');

const deviceData = readJson('contracts/fixtures/ingest/device-data.json');
assertKeys(deviceData, ['device_registered', 'plugin_activity', 'raw_data'], 'device-data fixture');
assertKeys(deviceData.device_registered, ['device_id', 'api_key', 'bubbl_id'], 'device-data.device_registered fixture');
assertKeys(deviceData.plugin_activity, ['device_registered_id', 'time', 'activity'], 'device-data.plugin_activity fixture');
assertKeys(deviceData.raw_data, ['event', 'request'], 'device-data.raw_data fixture');

const geofenceData = readJson('contracts/fixtures/ingest/geofence-data.json');
assertKeys(geofenceData, ['geo', 'location', 'notification'], 'geofence-data fixture');
assertKeys(geofenceData.geo, ['location_id', 'device_registered_id', 'time', 'activity', 'latitude', 'longitude'], 'geofence-data.geo fixture');
assertKeys(geofenceData.location, ['device_registered_id', 'time', 'activity', 'latitude', 'longitude'], 'geofence-data.location fixture');
assertKeys(geofenceData.notification, ['device_registered_id', 'time', 'activity', 'curated_notification_id', 'allow'], 'geofence-data.notification fixture');
assert(typeof geofenceData.notification.allow === 'boolean', 'geofence-data.notification.allow must be boolean');

const segments = readJson('contracts/fixtures/ingest/segments-update.json');
assertKeys(segments, ['device_registered_id', 'segmentation'], 'segments fixture');
assertArray(segments.segmentation, 'segments.segmentation');

const survey = readJson('contracts/fixtures/ingest/survey-response.json');
assertKeys(survey, ['device_registered_id', 'activity', 'curated_notification_id', 'responses'], 'survey fixture');
assertArray(survey.responses, 'survey.responses');

for (const fixture of [
  'contracts/fixtures/runtime/config-empty.json',
  'contracts/fixtures/runtime/geofence-empty.json',
  'contracts/fixtures/runtime/geofence-hit.json',
  'contracts/fixtures/runtime/push-empty.json'
]) {
  const json = readJson(fixture);
  if (fixture.includes('geofence')) {
    assertKeys(json, ['geoCampaign', 'pushCampaign', 'configuration'], fixture);
    assertArray(json.geoCampaign, `${fixture}.geoCampaign`);
    assertArray(json.pushCampaign, `${fixture}.pushCampaign`);
  }
  if (fixture.includes('push')) {
    assertKeys(json, ['pushCampaign', 'configuration'], fixture);
    assertArray(json.pushCampaign, `${fixture}.pushCampaign`);
  }
  assertKeys(json.configuration, ['notificationsCount', 'daysCount', 'batteryCount', 'privacyText'], `${fixture}.configuration`);
}

console.log('Contract fixtures and transport map are valid.');
