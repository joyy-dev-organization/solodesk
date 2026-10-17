import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  createServer,
  HOST,
  getOrCreateRuntimeToken,
  ErrorCode,
  setInferenceBusy,
  getInferenceBusy,
} from '../src/server.js';
import { checkOllamaReadiness } from '../src/model.js';
import { normalizeScopeOutput } from '../src/workflows/scope-check.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES_PATH = path.resolve(__dirname, '..', '..', 'fixtures', 'synthetic-cases.json');

const fixtures = JSON.parse(fs.readFileSync(FIXTURES_PATH, 'utf8')) as {
  scopeRequests: Array<{
    id: string;
    name: string;
    niche: string;
    scopeVersionId: string;
    scopeItems: Array<{ id: string; category?: string; title?: string; description: string }>;
    requestText: string;
    expectedClassification?: string;
  }>;
};

describe('Milestone M4: POST /api/scope-check Endpoint Suite', () => {
  let server: http.Server;
  const testPort = 3146; // dedicated isolated test port
  const token = getOrCreateRuntimeToken();
  const endpointUrl = `http://${HOST}:${testPort}/api/scope-check`;
  const legacyEndpointUrl = `http://${HOST}:${testPort}/v1/scope-check`;

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

  // --- UNIT TESTS: AUTHENTICATION & SECURITY ---
  describe('Authentication & Loopback Security', () => {
    it('returns 401 UNAUTHORIZED when Authorization header is missing', async () => {
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ requestText: 'Tweak the logo' }),
      });
      expect(res.status).toBe(401);
      const json = await res.json() as { error: { code: string; retryable: boolean } };
      expect(json.error.code).toBe(ErrorCode.UNAUTHORIZED);
      expect(json.error.retryable).toBe(false);
    });

    it('returns 401 UNAUTHORIZED when Bearer token is invalid', async () => {
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer bad-token-xyz-123',
        },
        body: JSON.stringify({ requestText: 'Tweak the logo' }),
      });
      expect(res.status).toBe(401);
      const json = await res.json() as { error: { code: string } };
      expect(json.error.code).toBe(ErrorCode.UNAUTHORIZED);
    });

    it('authenticates successfully on both /api/scope-check and /v1/scope-check routes', async () => {
      for (const url of [endpointUrl, legacyEndpointUrl]) {
        const res = await fetch(url, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`,
          },
          body: JSON.stringify({}),
        });
        expect(res.status).toBe(400); // 400 proves auth succeeded before input validation
      }
    });
  });

  // --- UNIT TESTS: INPUT VALIDATION & ADVERSARIAL ---
  describe('Input Validation & Boundary Testing', () => {
    it('returns 400 INVALID_INPUT on malformed JSON payload', async () => {
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: '{ "requestText": "Incomplete json...',
      });
      expect(res.status).toBe(400);
      const json = await res.json() as { error: { code: string } };
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
    });

    it('returns 400 INVALID_INPUT on empty or whitespace request text', async () => {
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          requestText: '   \n  ',
          scopeVersionId: 'v1',
          scopeItems: [{ id: '1', category: 'included', description: 'Logo' }],
        }),
      });
      expect(res.status).toBe(400);
      const json = await res.json() as { error: { code: string } };
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
    });

    it('returns 400 INVALID_INPUT on oversized request text (>8000 characters)', async () => {
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          requestText: 'B'.repeat(8005),
          scopeVersionId: 'v1',
          scopeItems: [{ id: '1', category: 'included', description: 'Logo' }],
        }),
      });
      expect(res.status).toBe(400);
      const json = await res.json() as { error: { code: string; message: string } };
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
      expect(json.error.message).toContain('8000');
    });

    it('executes Case 5: returns 400 INVALID_INPUT on stale or empty scopeVersionId', async () => {
      const case5 = fixtures.scopeRequests.find(c => c.id === 'scope-5-stale-version')!;
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          requestText: case5.requestText,
          scopeVersionId: case5.scopeVersionId,
          scopeItems: case5.scopeItems,
        }),
      });
      expect(res.status).toBe(400);
      const json = await res.json() as { error: { code: string } };
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
    });

    it('executes Case 6: returns 400 INVALID_INPUT on missing or empty scopeItems', async () => {
      const case6 = fixtures.scopeRequests.find(c => c.id === 'scope-6-missing-scope')!;
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          requestText: case6.requestText,
          scopeVersionId: case6.scopeVersionId,
          scopeItems: case6.scopeItems,
        }),
      });
      expect(res.status).toBe(400);
      const json = await res.json() as { error: { code: string } };
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
    });
  });

  // --- UNIT TESTS: CONCURRENCY CONTROL ---
  describe('Concurrency Mutex Lock', () => {
    it('returns 429 BUSY when inference mutex lock is active', async () => {
      expect(getInferenceBusy()).toBe(false);
      setInferenceBusy(true);

      try {
        const res = await fetch(endpointUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`,
          },
          body: JSON.stringify({
            requestText: 'Change color to green',
            scopeVersionId: 'v1',
            scopeItems: [{ id: '1', category: 'included', description: 'Logo' }],
          }),
        });
        expect(res.status).toBe(429);
        const json = await res.json() as { error: { code: string; retryable: boolean } };
        expect(json.error.code).toBe(ErrorCode.BUSY);
        expect(json.error.retryable).toBe(true);
      } finally {
        setInferenceBusy(false);
      }
    });
  });

  // --- UNIT TESTS: DEFENSIVE NORMALIZER ---
  describe('Defensive Output Normalizer', () => {
    it('recovers from alternative keys and uppercase classification enums', () => {
      const rawModelDrift = {
        evaluations: [
          {
            request_excerpt: 'tweak teal to navy',
            classification: 'INCLUDED',
            rationale: 'Covered under revision allowance',
            matched_scope_item_id: 'item-102',
          },
        ],
        suggested_reply: 'Sure, I can adjust the colors.',
      };

      const scopeItems = [
        { id: 'item-102', category: 'allowance', description: '2 rounds of color revisions' },
      ];

      const normalized = normalizeScopeOutput(rawModelDrift, scopeItems);
      expect(normalized.findings).toHaveLength(1);
      expect(normalized.findings[0].category).toBe('included');
      expect(normalized.findings[0].requestExcerpt).toBe('tweak teal to navy');
      expect(normalized.findings[0].matchedScopeItemId).toBe('item-102');
      expect(normalized.findings[0].matchedScopeItemDescription).toBe('2 rounds of color revisions');
      expect(normalized.replyDraft).toBe('Sure, I can adjust the colors.');
      expect(normalized.summary).toContain('1 included');
    });

    it('correctly normalizes null/none matched scope items', () => {
      const rawModelOutput = {
        findings: [
          {
            requestExcerpt: 'build a full mobile app',
            category: 'POTENTIALLY_OUTSIDE',
            matchedScopeItemId: 'none',
            explanation: 'Software development not in branding scope',
          },
        ],
        replyDraft: 'I can provide an estimate for the mobile app.',
      };

      const normalized = normalizeScopeOutput(rawModelOutput, []);
      expect(normalized.findings[0].category).toBe('out_of_scope');
      expect(normalized.findings[0].matchedScopeItemId).toBeNull();
      expect(normalized.findings[0].matchedScopeItemDescription).toBe('No matching scope deliverable found in approved agreement');
    });
  });

  // --- LIVE WORKFLOW INTEGRATION SUITE (Ollama Model Execution) ---
  describe('Live Model Integration Suite (M4 Synthetic Cases)', () => {
    it('executes Case 1: Included revision within agreed allowance', async () => {
      const readiness = await checkOllamaReadiness();
      if (!readiness.available || !readiness.modelReady) return;

      const case1 = fixtures.scopeRequests.find(c => c.id === 'scope-1-included-revision')!;
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          requestText: case1.requestText,
          scopeVersionId: case1.scopeVersionId,
          scopeItems: case1.scopeItems,
          niche: case1.niche,
        }),
      });

      expect(res.status).toBe(200);
      const json = await res.json() as {
        requestId: string;
        data: {
          findings: Array<{
            category: string;
            requestExcerpt: string;
            matchedScopeItemId?: string | null;
            explanation: string;
          }>;
          replyDraft: string;
          summary: string;
        };
      };

      expect(json.requestId).toBeDefined();
      expect(json.data.findings.length).toBeGreaterThan(0);
      const categories = json.data.findings.map(f => f.category);
      expect(categories).toContain('included');
      expect(json.data.replyDraft).toBeDefined();
      expect(json.data.replyDraft.length).toBeGreaterThan(10);
    }, 120000);

    it('executes Case 2: Explicit extra deliverable excluded from scope', async () => {
      const readiness = await checkOllamaReadiness();
      if (!readiness.available || !readiness.modelReady) return;

      const case2 = fixtures.scopeRequests.find(c => c.id === 'scope-2-outside-deliverable')!;
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          requestText: case2.requestText,
          scopeVersionId: case2.scopeVersionId,
          scopeItems: case2.scopeItems,
          niche: case2.niche,
        }),
      });

      expect(res.status).toBe(200);
      const json = await res.json() as {
        data: {
          findings: Array<{ category: string; matchedScopeItemId?: string | null }>;
          replyDraft: string;
        };
      };

      expect(json.data.findings.length).toBeGreaterThan(0);
      const finding = json.data.findings[0];
      expect(finding.category).toBe('out_of_scope');
    }, 120000);

    it('executes Case 3: Ambiguous and subjective request', async () => {
      const readiness = await checkOllamaReadiness();
      if (!readiness.available || !readiness.modelReady) return;

      const case3 = fixtures.scopeRequests.find(c => c.id === 'scope-3-ambiguous-request')!;
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          requestText: case3.requestText,
          scopeVersionId: case3.scopeVersionId,
          scopeItems: case3.scopeItems,
          niche: case3.niche,
        }),
      });

      expect(res.status).toBe(200);
      const json = await res.json() as {
        data: {
          findings: Array<{ category: string }>;
          replyDraft: string;
        };
      };

      expect(json.data.findings.length).toBeGreaterThan(0);
      expect(json.data.findings[0].category).toBe('needs_clarification');
    }, 120000);

    it('executes Case 4: Mixed request with both included revision and extra deliverable', async () => {
      const readiness = await checkOllamaReadiness();
      if (!readiness.available || !readiness.modelReady) return;

      const case4 = fixtures.scopeRequests.find(c => c.id === 'scope-4-mixed-request')!;
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          requestText: case4.requestText,
          scopeVersionId: case4.scopeVersionId,
          scopeItems: case4.scopeItems,
          niche: case4.niche,
        }),
      });

      expect(res.status).toBe(200);
      const json = await res.json() as {
        data: {
          findings: Array<{ category: string; requestExcerpt: string }>;
          replyDraft: string;
        };
      };

      expect(json.data.findings.length).toBeGreaterThanOrEqual(1);
      const categories = json.data.findings.map(f => f.category);
      expect(categories).toContain('included');
      expect(categories).toContain('out_of_scope');
    }, 120000);
  });
});
