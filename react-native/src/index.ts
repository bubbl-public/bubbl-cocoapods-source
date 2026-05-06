import {
  NativeEventEmitter,
  NativeModules,
  type EmitterSubscription,
} from 'react-native';
import NativeBubblSdk from './specs/NativeBubblSdk';

export type BubblEnvironment = 'development' | 'nightly' | 'staging' | 'production';
export type BubblLogLevel = 'off' | 'error' | 'warn' | 'info' | 'debug';
export type BubblNotificationRenderingMode = 'sdkDefault' | 'hostRendered' | 'eventOnly';
export type BubblNotificationSource = 'firebase' | 'apns' | 'runtime' | 'geofence' | 'manual';

export type BubblConfig = {
  apiKey: string;
  environment?: BubblEnvironment;
  runtimeBaseUrl?: string | null;
  ingestBaseUrl?: string | null;
  segments?: string[];
  correlationId?: string | null;
  defaultDistanceMeters?: number;
  refreshIntervalSeconds?: number;
  enablePushHandling?: boolean;
  enableLocationTracking?: boolean;
  notificationRenderingMode?: BubblNotificationRenderingMode;
  enableDefaultNotificationModal?: boolean;
  enableDefaultSurveyUi?: boolean;
  logLevel?: BubblLogLevel;
};

export type BubblBootResult = {
  ready: boolean;
  fromCache: boolean;
  deviceRegistered: boolean;
  requiresPermission: string[];
  warnings: string[];
};

export type BubblLocation = {
  latitude: number;
  longitude: number;
};

export type BubblGeofenceTransitionType = 'enter' | 'exit';

export type BubblGeofenceTransition = {
  type: BubblGeofenceTransitionType;
  campaignId?: string | null;
  locationId?: string | null;
  location: BubblLocation;
};

export type BubblGeofenceVertex = BubblLocation;

export type BubblGeofencePolygon = {
  campaignId?: string | null;
  campaignName?: string | null;
  locationId?: string | null;
  vertices: BubblGeofenceVertex[];
};

export type BubblGeofenceCircle = {
  campaignId?: string | null;
  campaignName?: string | null;
  locationId?: string | null;
  center: BubblGeofenceVertex;
  radius: number;
};

export type BubblGeofenceSnapshot = {
  stats: {
    campaignsTotal: number;
    polygonsTotal: number;
  };
  polygons: BubblGeofencePolygon[];
  circles: BubblGeofenceCircle[];
};

export type BubblTrackEvent = {
  type: string;
  activity: string;
  locationId?: string | null;
  curatedNotificationId?: string | null;
  latitude?: number | null;
  longitude?: number | null;
};

export type BubblSurveyAnswer = {
  questionId: string;
  type: string;
  value?: string | null;
  choiceIds?: string[];
};

export type BubblSurveyResponse = {
  curatedNotificationId: string;
  locationId?: string | null;
  answers: BubblSurveyAnswer[];
};

export type BubblNotificationPayload = {
  id: string;
  title: string;
  body: string;
  source?: BubblNotificationSource;
  locationId?: string | null;
  curatedNotificationId?: string | null;
  correlationId?: string | null;
  media?: BubblNotificationMedia | null;
  cta?: BubblNotificationCta | null;
  survey?: BubblNotificationSurvey | null;
  raw?: Record<string, string>;
};

export type BubblNotificationMedia = {
  url: string;
  type?: string | null;
  altText?: string | null;
};

export type BubblNotificationCta = {
  label: string;
  url?: string | null;
  action?: string | null;
};

export type BubblNotificationSurvey = {
  questions?: BubblSurveyQuestion[];
};

export type BubblSurveyQuestion = {
  id: string;
  title: string;
  type: string;
  choices?: BubblSurveyChoice[];
};

export type BubblSurveyChoice = {
  id: string;
  label: string;
};

export type BubblNotificationDisplayResult = {
  displayed: boolean;
  reason?: string | null;
};

export type BubblDiagnostics = {
  sdkVersion: string;
  platform: 'react-native';
  booted: boolean;
  pendingIngestCount: number;
};

export type BubblEvent =
  | { type: 'ready' }
  | { type: 'diagnostic'; diagnostics: BubblDiagnostics }
  | { type: 'notificationReceived'; payload: BubblNotificationPayload }
  | { type: 'notificationDisplayed'; payload: BubblNotificationPayload }
  | { type: 'notificationTapped'; payload: BubblNotificationPayload; action?: string | null }
  | { type: 'notificationCtaTapped'; payload: BubblNotificationPayload; action?: string | null }
  | { type: 'notificationMediaViewed'; payload: BubblNotificationPayload }
  | { type: 'notificationSurveyRequested'; payload: BubblNotificationPayload }
  | { type: 'locationUpdated'; location: BubblLocation }
  | { type: 'geofenceSnapshot'; snapshot: BubblGeofenceSnapshot }
  | { type: 'geofenceEntered'; transition: BubblGeofenceTransition }
  | { type: 'geofenceExited'; transition: BubblGeofenceTransition }
  | { type: 'error'; code: string; message: string };

export type BubblEventSubscription = Pick<EmitterSubscription, 'remove'>;

const EVENT_NAME = 'BubblSdkEvent';

type NativeBubblSdkShape = NonNullable<typeof NativeBubblSdk>;

function nativeModule(): NativeBubblSdkShape {
  const module = NativeBubblSdk ?? NativeModules.BubblSdk;
  if (!module) {
    throw new Error('BubblSdk native module is not linked.');
  }

  return module as NativeBubblSdkShape;
}

function eventEmitter(): NativeEventEmitter {
  return new NativeEventEmitter(NativeModules.BubblSdk ?? (NativeBubblSdk as object | null));
}

function validateApiKey(config: BubblConfig): void {
  if (!config.apiKey?.trim()) {
    throw new Error('apiKey is required');
  }
}

export const Bubbl = {
  async boot(config: BubblConfig): Promise<BubblBootResult> {
    validateApiKey(config);
    return nativeModule().boot(config) as Promise<BubblBootResult>;
  },
  async shutdown(): Promise<void> {
    return nativeModule().shutdown();
  },
  async startLocationTracking(): Promise<void> {
    return nativeModule().startLocationTracking();
  },
  async stopLocationTracking(): Promise<void> {
    return nativeModule().stopLocationTracking();
  },
  async refresh(): Promise<void> {
    return nativeModule().refresh();
  },
  async refreshGeofence(location: BubblLocation): Promise<void> {
    return nativeModule().refreshGeofence(location.latitude, location.longitude);
  },
  async handleLocationUpdate(location: BubblLocation): Promise<void> {
    return nativeModule().handleLocationUpdate(location.latitude, location.longitude);
  },
  async refreshPush(): Promise<void> {
    return nativeModule().refreshPush();
  },
  async getConfiguration(): Promise<Record<string, unknown> | null> {
    return nativeModule().getConfiguration() as Promise<Record<string, unknown> | null>;
  },
  async getPrivacyText(): Promise<string> {
    return nativeModule().getPrivacyText();
  },
  async updateSegments(tags: string[]): Promise<void> {
    return nativeModule().updateSegments(tags);
  },
  async setCorrelationId(value: string): Promise<void> {
    return nativeModule().setCorrelationId(value);
  },
  async clearCorrelationId(): Promise<void> {
    return nativeModule().clearCorrelationId();
  },
  async registerPushToken(token: string): Promise<void> {
    return nativeModule().registerPushToken(token);
  },
  async handleFirebasePayload(payload: Record<string, string>): Promise<BubblNotificationPayload | null> {
    return nativeModule().handleFirebasePayload(payload) as Promise<BubblNotificationPayload | null>;
  },
  async showNotification(payload: BubblNotificationPayload): Promise<BubblNotificationDisplayResult> {
    return nativeModule().showNotification(payload) as Promise<BubblNotificationDisplayResult>;
  },
  async handleNotificationPayload(payload: BubblNotificationPayload): Promise<BubblNotificationDisplayResult> {
    return nativeModule().handleNotificationPayload(payload) as Promise<BubblNotificationDisplayResult>;
  },
  async handleNotificationOpen(payload: BubblNotificationPayload, action?: string | null): Promise<void> {
    return nativeModule().handleNotificationOpen(payload, action);
  },
  async handleNotificationCta(payload: BubblNotificationPayload, action?: string | null): Promise<void> {
    return nativeModule().handleNotificationCta(payload, action);
  },
  async handleNotificationMediaViewed(payload: BubblNotificationPayload): Promise<void> {
    return nativeModule().handleNotificationMediaViewed(payload);
  },
  async handleNotificationSurveyRequested(payload: BubblNotificationPayload): Promise<void> {
    return nativeModule().handleNotificationSurveyRequested(payload);
  },
  async track(event: BubblTrackEvent): Promise<void> {
    return nativeModule().track(event);
  },
  async submitSurveyResponse(response: BubblSurveyResponse): Promise<void> {
    return nativeModule().submitSurveyResponse(response);
  },
  async flush(): Promise<{ pendingCount: number }> {
    return nativeModule().flush() as Promise<{ pendingCount: number }>;
  },
  async diagnostics(): Promise<BubblDiagnostics> {
    return nativeModule().diagnostics() as Promise<BubblDiagnostics>;
  },
  events: {
    addListener(listener: (event: BubblEvent) => void): BubblEventSubscription {
      return eventEmitter().addListener(EVENT_NAME, listener);
    },
  },
};

export default Bubbl;
