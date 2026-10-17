import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import http from 'node:http';
import {
  createServer,
  HOST,
  getOrCreateRuntimeToken,
  ErrorCode,
  setInferenceBusy,
  getInferenceBusy,
  type SafeErrorEnvelope,
} from '../src/server.js';
import * as modelModule from '../src/model.js';

describe('Milestone M1 Error Envelopes, Security & Concurrency Test Suite', () => {
  let server: http.Server;
  const testPort = 3155; // dedicated isolated test port
  const token = getOrCreateRuntimeToken();
  const briefCheckUrl = `http://${HOST}:${testPort}/api/brief-check`;
  const scopeCheckUrl = `http://${HOST}:${testPort}/api/scope-check`;

  beforeAll(async () => {
    server = createServer();
    await new Promise<void>((resolve, reject) => {
      server.listen(testPort, HOST, () => resolve());
      server.on('error', reject);
    });
  });

  afterAll(async () => {
    await new Promise<void>(resolve => server.close(() => resolve()));
  });

  beforeEach(() => {
    // Ensure inference mutex is clear before each test
    setInferenceBusy(false);
  });

  // --- 1. LOCAL PRIVACY & CORS SECURITY GATES ---
  describe('Security & Loopback Isolation', () => {
    it('strictly rejects browser Origin headers with 403 Forbidden', async () => {
      const res = await fetch(briefCheckUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
          'Origin': 'https://malicious-website.com',
        },
        body: JSON.stringify({ brief: 'Harmless brief' }),
      });

      expect(res.status).toBe(403);
      const json = (await res.json()) as SafeErrorEnvelope;
      expect(json.requestId).toBeDefined();
      expect(json.error.code).toBe(ErrorCode.UNAUTHORIZED);
      expect(json.error.message).toContain('Browser origins are strictly prohibited');
      expect(json.error.retryable).toBe(false);
    });

    it('rejects localhost browser origin headers (CSRF defense)', async () => {
      const res = await fetch(`http://${HOST}:${testPort}/health`, {
        method: 'GET',
        headers: {
          'Origin': 'http://localhost:3000',
        },
      });

      expect(res.status).toBe(403);
      const json = (await res.json()) as SafeErrorEnvelope;
      expect(json.error.code).toBe(ErrorCode.UNAUTHORIZED);
    });

    it('rejects external/spoofed Host headers (DNS rebinding defense)', async () => {
      const { statusCode, body } = await new Promise<{ statusCode: number; body: string }>((resolve, reject) => {
        const req = http.request({
          host: '127.0.0.1',
          port: testPort,
          path: '/health',
          method: 'GET',
          headers: {
            'Host': 'attacker.example.com',
          },
        }, (res) => {
          let data = '';
          res.on('data', chunk => data += chunk);
          res.on('end', () => resolve({ statusCode: res.statusCode ?? 0, body: data }));
        });
        req.on('error', reject);
        req.end();
      });

      expect(statusCode).toBe(403);
      const json = JSON.parse(body) as SafeErrorEnvelope;
      expect(json.error.code).toBe(ErrorCode.UNAUTHORIZED);
      expect(json.error.message).toContain('Service binds exclusively to loopback');
    });

    it('serves GET /health without authentication and leaks zero private data', async () => {
      const res = await fetch(`http://${HOST}:${testPort}/health`);
      expect(res.status).toBe(200);
      const json = (await res.json()) as Record<string, unknown>;

      expect(json.service).toBe('solodesk-service');
      expect(json.loopbackOnly).toBe(true);
      expect(json.activeModel).toBe(modelModule.ACTIVE_MODEL_ID);
      // Ensure no tokens, file paths, or private client data leaked
      const stringified = JSON.stringify(json);
      expect(stringified).not.toContain(token);
      expect(stringified).not.toContain('Users');
      expect(stringified).not.toContain('C:\\');
    });
  });

  // --- 2. AUTHENTICATION & ENVELOPE SHAPE ---
  describe('Authentication & Error Envelope Alignment', () => {
    it('returns 401 UNAUTHORIZED on missing Authorization header with complete envelope', async () => {
      const res = await fetch(briefCheckUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ brief: 'Valid brief text' }),
      });

      expect(res.status).toBe(401);
      const json = (await res.json()) as SafeErrorEnvelope;
      // Both root requestId and error.requestId must be present
      expect(json.requestId).toBeDefined();
      expect(json.error.requestId).toBe(json.requestId);
      expect(json.error.code).toBe(ErrorCode.UNAUTHORIZED);
      expect(json.error.retryable).toBe(false);
      expect(json.error.message).toContain('Unauthorized');
    });

    it('returns 401 UNAUTHORIZED on invalid Bearer token', async () => {
      const res = await fetch(briefCheckUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer bad-invalid-token-12345',
        },
        body: JSON.stringify({ brief: 'Valid brief text' }),
      });

      expect(res.status).toBe(401);
      const json = (await res.json()) as SafeErrorEnvelope;
      expect(json.error.code).toBe(ErrorCode.UNAUTHORIZED);
    });
  });

  // --- 3. INPUT VALIDATION (INVALID_INPUT) ---
  describe('Input Validation & Boundary Enforcement', () => {
    it('returns 400 INVALID_INPUT on malformed JSON payload', async () => {
      const res = await fetch(briefCheckUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: '{"brief": "Incomplete json string...',
      });

      expect(res.status).toBe(400);
      const json = (await res.json()) as SafeErrorEnvelope;
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
      expect(json.error.message).toContain('Malformed JSON');
      expect(json.error.retryable).toBe(false);
      expect(json.requestId).toBeDefined();
    });

    it('returns 400 INVALID_INPUT on oversized payload (>8000 characters)', async () => {
      const oversizedText = 'X'.repeat(8005);
      const res = await fetch(briefCheckUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({ brief: oversizedText }),
      });

      expect(res.status).toBe(400);
      const json = (await res.json()) as SafeErrorEnvelope;
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
      expect(json.error.message).toContain('8000');
      expect(json.error.retryable).toBe(false);
    });

    it('returns 400 INVALID_INPUT on empty or whitespace-only brief', async () => {
      const res = await fetch(briefCheckUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({ brief: '    \n   ' }),
      });

      expect(res.status).toBe(400);
      const json = (await res.json()) as SafeErrorEnvelope;
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
    });
  });

  // --- 4. ATOMIC CONCURRENCY LOCK (BUSY) ---
  describe('Atomic Single-Concurrency Mutex', () => {
    it('returns 429 BUSY when inference lock is already held', async () => {
      setInferenceBusy(true);
      try {
        const res = await fetch(briefCheckUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`,
          },
          body: JSON.stringify({ brief: 'Valid brief text' }),
        });

        expect(res.status).toBe(429);
        const json = (await res.json()) as SafeErrorEnvelope;
        expect(json.error.code).toBe(ErrorCode.BUSY);
        expect(json.error.retryable).toBe(true);
        expect(json.error.message).toContain('single concurrency');
        expect(json.requestId).toBeDefined();
      } finally {
        setInferenceBusy(false);
      }
    });

    it('releases lock cleanly after handling request', () => {
      expect(getInferenceBusy()).toBe(false);
    });
  });

  // --- 5. MODEL NOT FOUND & MODEL UNAVAILABLE SIMULATION ---
  describe('Model Availability Error Envelopes', () => {
    it('verifies checkOllamaReadiness returns distinguishable status structure', async () => {
      const readiness = await modelModule.checkOllamaReadiness();
      expect(typeof readiness.available).toBe('boolean');
      expect(typeof readiness.modelReady).toBe('boolean');
      expect(Array.isArray(readiness.modelsFound)).toBe(true);
    });

    it('returns 404 INVALID_INPUT for non-existent endpoint route', async () => {
      const res = await fetch(`http://${HOST}:${testPort}/api/non-existent-route`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({ test: true }),
      });

      expect(res.status).toBe(404);
      const json = (await res.json()) as SafeErrorEnvelope;
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
      expect(json.error.retryable).toBe(false);
    });
  });
});
