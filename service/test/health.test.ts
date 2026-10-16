import { describe, it, expect } from 'vitest';
import { getServiceHealth, SERVICE_NAME, SERVICE_VERSION } from '../src/index.js';

describe('Service Health Check', () => {
  it('returns status ok and verifies loopback configuration', () => {
    const health = getServiceHealth();
    expect(health.status).toBe('ok');
    expect(health.service).toBe(SERVICE_NAME);
    expect(health.version).toBe(SERVICE_VERSION);
    expect(health.loopbackOnly).toBe(true);
  });
});
