/**
 * SoloDesk local TypeScript/Mastra service
 * Loopback-only service orchestrating BriefCheck and ScopeShield
 */

export const SERVICE_NAME = 'solodesk-service';
export const SERVICE_VERSION = '0.1.0';
export const DEFAULT_HOST = '127.0.0.1';
export const DEFAULT_PORT = 3141;

export interface HealthResponse {
  status: 'ok' | 'degraded';
  version: string;
  service: string;
  loopbackOnly: boolean;
}

export function getServiceHealth(): HealthResponse {
  return {
    status: 'ok',
    version: SERVICE_VERSION,
    service: SERVICE_NAME,
    loopbackOnly: true,
  };
}

console.log(`${SERVICE_NAME} v${SERVICE_VERSION} scaffold initialized.`);
