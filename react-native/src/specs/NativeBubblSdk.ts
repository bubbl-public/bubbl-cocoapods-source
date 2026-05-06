import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export type BubblBootOptions = {
  apiKey: string;
  environment?: string;
  runtimeBaseUrl?: string | null;
  ingestBaseUrl?: string | null;
  segments?: string[];
  correlationId?: string | null;
  defaultDistanceMeters?: number;
  refreshIntervalSeconds?: number;
  enablePushHandling?: boolean;
  enableLocationTracking?: boolean;
  notificationRenderingMode?: string;
  enableDefaultNotificationModal?: boolean;
  enableDefaultSurveyUi?: boolean;
  logLevel?: string;
};

export interface Spec extends TurboModule {
  boot(config: BubblBootOptions): Promise<Object>;
  shutdown(): Promise<void>;
  startLocationTracking(): Promise<void>;
  stopLocationTracking(): Promise<void>;
  refresh(): Promise<void>;
  refreshGeofence(latitude: number, longitude: number): Promise<void>;
  handleLocationUpdate(latitude: number, longitude: number): Promise<void>;
  refreshPush(): Promise<void>;
  getConfiguration(): Promise<Object | null>;
  getPrivacyText(): Promise<string>;
  updateSegments(tags: string[]): Promise<void>;
  setCorrelationId(value: string): Promise<void>;
  clearCorrelationId(): Promise<void>;
  registerPushToken(token: string): Promise<void>;
  handleFirebasePayload(payload: Object): Promise<Object | null>;
  showNotification(payload: Object): Promise<Object>;
  handleNotificationPayload(payload: Object): Promise<Object>;
  handleNotificationOpen(payload: Object, action?: string | null): Promise<void>;
  handleNotificationCta(payload: Object, action?: string | null): Promise<void>;
  handleNotificationMediaViewed(payload: Object): Promise<void>;
  handleNotificationSurveyRequested(payload: Object): Promise<void>;
  track(event: Object): Promise<void>;
  submitSurveyResponse(response: Object): Promise<void>;
  flush(): Promise<Object>;
  diagnostics(): Promise<Object>;
}

export default TurboModuleRegistry.get<Spec>('BubblSdk');
