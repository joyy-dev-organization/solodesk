import { describe, it, expect, beforeAll, afterAll, vi } from 'vitest';
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
import {
  normalizeScopeOutput,
  validateScopeRequestStep,
  loadApprovedContextStep,
  compareWithAgentStep,
  validateEvidenceClassificationStep,
  returnEditableReplyStep,
  scopeCheckWorkflow,
} from '../src/workflows/scope-check.js';

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
    supportedFacts?: string[];
    importantQuestions?: string[];
    expectedClassifications?: Array<{
      requestExcerpt: string;
      expectedCategory: string;
      matchedScopeItemId?: string | null;
    }>;
    forbiddenInventions?: string[];
  }>;
};

describe('Milestone M4: POST /api/scope-check Endpoint Suite', () => {
  let server: http.Server;
  let testPort: number;
  let endpointUrl: string;
  let legacyEndpointUrl: string;
  const token = getOrCreateRuntimeToken();

  beforeAll(async () => {
    server = createServer();
    await new Promise<void>((resolve, reject) => {
      server.listen(0, HOST, () => {
        const addr = server.address();
        if (addr && typeof addr === 'object') {
          testPort = addr.port;
          endpointUrl = `http://${HOST}:${testPort}/api/scope-check`;
          legacyEndpointUrl = `http://${HOST}:${testPort}/v1/scope-check`;
          resolve();
        } else {
          reject(new Error('Failed to resolve dynamic test port'));
        }
      });
      server.on('error', reject);
    });

    // Warm up model resident memory in Ollama
    const readiness = await checkOllamaReadiness();
    if (readiness.available && readiness.modelReady) {
      try {
        await fetch('http://127.0.0.1:11434/api/generate', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ model: 'qwen3:1.7b', prompt: 'ping', stream: false }),
        });
      } catch {
        // Non-fatal warmup
      }
    }
  }, 90000);

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

    it('returns 400 INVALID_INPUT on empty or missing scopeVersionId (stale version boundary)', async () => {
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          requestText: 'Update the hero header font',
          scopeVersionId: '',
          scopeItems: [{ id: '1', category: 'included', description: 'Landing page' }],
        }),
      });
      expect(res.status).toBe(400);
      const json = await res.json() as { error: { code: string } };
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
    });

    it('returns 400 INVALID_INPUT on missing or empty scopeItems array (missing scope boundary)', async () => {
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          requestText: 'Update the hero header font',
          scopeVersionId: 'v1',
          scopeItems: [],
        }),
      });
      expect(res.status).toBe(400);
      const json = await res.json() as { error: { code: string } };
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
    });
  });

  // --- CONCURRENCY LOCK TEST ---
  describe('Concurrency Control', () => {
    it('returns 429 BUSY when inference mutex lock is held', async () => {
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
            requestText: 'Change logo color',
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

  // --- MASTRA 5-STEP WORKFLOW INSPECTABILITY ---
  describe('Mastra 5-Step Workflow Inspectability (Handbook Section 02, line 81)', () => {
    it('verifies all 5 named steps are defined with correct IDs', () => {
      expect(validateScopeRequestStep.id).toBe('validate-scope-request');
      expect(loadApprovedContextStep.id).toBe('load-approved-context');
      expect(compareWithAgentStep.id).toBe('compare-with-agent');
      expect(validateEvidenceClassificationStep.id).toBe('validate-evidence-classification');
      expect(returnEditableReplyStep.id).toBe('return-editable-reply');
      expect(scopeCheckWorkflow.id).toBe('scope-check-workflow');
    });

    it('loadApprovedContextStep structures scope categories and computes breakdown', async () => {
      const stepResult = await loadApprovedContextStep.execute({
        inputData: {
          requestText: 'Change color',
          niche: 'design',
          scopeVersionId: 'v1',
          scopeItems: [
            { id: '1', category: 'included', description: 'Logo master' },
            { id: '2', category: 'allowance', description: '2 rounds of revisions' },
            { id: '3', category: 'excluded', description: 'Mobile application' },
          ],
        },
      });

      expect(stepResult.formattedScope).toContain('[1] (INCLUDED): Logo master');
      expect(stepResult.formattedScope).toContain('[2] (ALLOWANCE): 2 rounds of revisions');
      expect(stepResult.formattedScope).toContain('[3] (EXCLUDED): Mobile application');
      expect(stepResult.breakdown.includedCount).toBe(1);
      expect(stepResult.breakdown.allowanceCount).toBe(1);
      expect(stepResult.breakdown.excludedCount).toBe(1);
    });
  });

  // --- UNIT TESTS: DEFENSIVE NORMALIZER & ID GROUNDING ---
  describe('Defensive Normalizer & Scope Grounding', () => {
    it('normalizes uppercase categories, extracts alternative keys, and synthesizes summary', () => {
      const rawModelOutput = {
        evaluations: [
          {
            status: 'INCLUDED',
            excerpt: 'tweak the font',
            scopeItemId: 'item-1',
            rationale: 'Covered by revision allowance',
          },
        ],
        suggestedReply: 'I can update the font as part of our agreed revision round.',
      };

      const normalized = normalizeScopeOutput(rawModelOutput, [
        { id: 'item-1', category: 'allowance', description: '2 rounds of font and color tweaks' },
      ]);

      expect(normalized.findings.length).toBe(1);
      expect(normalized.findings[0].category).toBe('included');
      expect(normalized.findings[0].classification).toBe('INCLUDED');
      expect(normalized.findings[0].requestExcerpt).toBe('tweak the font');
      expect(normalized.findings[0].matchedScopeItemId).toBe('item-1');
      expect(normalized.findings[0].matchedScopeItemDescription).toBe('2 rounds of font and color tweaks');
      expect(normalized.replyDraft).toContain('update the font');
      expect(normalized.summary).toContain('1 included');
    });

    it('grounds hallucinated scope item IDs: resets invalid ID to null and supplies standard notice', () => {
      const rawModelOutput = {
        findings: [
          {
            category: 'out_of_scope',
            requestExcerpt: 'Build Flutter mobile app',
            matchedScopeItemId: 'hallucinated-item-99',
            explanation: 'Software development not in branding scope',
          },
        ],
        replyDraft: 'I can provide an estimate for the mobile app.',
      };

      const normalized = normalizeScopeOutput(rawModelOutput, [
        { id: 'item-1', category: 'included', description: 'Logo concept' },
      ]);
      expect(normalized.findings[0].category).toBe('out_of_scope');
      expect(normalized.findings[0].matchedScopeItemId).toBeNull();
      expect(normalized.findings[0].matchedScopeItemDescription).toBe(
        'No matching scope deliverable found in approved agreement'
      );
    });

    it('validateEvidenceClassificationStep throws INVALID_OUTPUT when JSON extraction fails', async () => {
      await expect(
        validateEvidenceClassificationStep.execute({
          inputData: {
            rawOutput: 'this is not valid json at all',
            scopeItems: [{ id: '1', description: 'Logo concept' }],
            requestText: 'Change color',
            niche: 'design',
            scopeVersionId: 'v1',
          },
        })
      ).rejects.toThrow('INVALID_OUTPUT');
    });

    it('returns 502 INVALID_OUTPUT with retryable true when model produces unparseable output', async () => {
      const spy = vi.spyOn(scopeCheckWorkflow, 'createRun').mockResolvedValueOnce({
        start: async () => ({
          status: 'failed',
          error: new Error('INVALID_OUTPUT: Model output could not be parsed as JSON after 1 repair attempt'),
        }),
        cancel: async () => {},
      } as any);

      try {
        const res = await fetch(endpointUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`,
          },
          body: JSON.stringify({
            requestText: 'Update logo to navy blue',
            scopeVersionId: 'v1',
            scopeItems: [{ id: 'item-1', category: 'included', description: 'Logo concept' }],
          }),
        });

        expect(res.status).toBe(502);
        const json = (await res.json()) as { error: { code: string; retryable: boolean; message: string } };
        expect(json.error.code).toBe(ErrorCode.INVALID_OUTPUT);
        expect(json.error.retryable).toBe(true);
        expect(json.error.message).toContain('INVALID_OUTPUT');
      } finally {
        spy.mockRestore();
      }
    });
  });

  // --- LIVE WORKFLOW INTEGRATION SUITE (All 6 Synthetic Cases per Handbook Section 07, line 482) ---
  describe('Live Model Integration Suite (All 6 ScopeShield Synthetic Cases)', () => {
    it('executes Case 1: Clearly included baseline deliverable request', async () => {
      const readiness = await checkOllamaReadiness();
      if (!readiness.available || !readiness.modelReady) return;

      const case1 = fixtures.scopeRequests.find(c => c.id === 'scope-1-clearly-included')!;
      const start = performance.now();
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
      const latencyMs = performance.now() - start;
      console.log(`[M4 Benchmark] ${case1.id}: ${latencyMs.toFixed(0)} ms (Status: ${res.status})`);

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

      // Negative boundary check: no legal breach claims or fee inventions
      const replyLower = json.data.replyDraft.toLowerCase();
      expect(replyLower).not.toContain('breach');
      expect(replyLower).not.toContain('penalty');
    }, 120000);

    it('executes Case 2: Included revision within agreed allowance', async () => {
      const readiness = await checkOllamaReadiness();
      if (!readiness.available || !readiness.modelReady) return;

      const case2 = fixtures.scopeRequests.find(c => c.id === 'scope-2-included-revision')!;
      const start = performance.now();
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
      const latencyMs = performance.now() - start;
      console.log(`[M4 Benchmark] ${case2.id}: ${latencyMs.toFixed(0)} ms (Status: ${res.status})`);

      expect(res.status).toBe(200);
      const json = await res.json() as {
        data: {
          findings: Array<{ category: string; matchedScopeItemId?: string | null }>;
          replyDraft: string;
        };
      };

      expect(json.data.findings.length).toBeGreaterThan(0);
      const categories = json.data.findings.map(f => f.category);
      expect(categories).toContain('included');
    }, 120000);

    it('executes Case 3: Explicit excluded deliverable (Stripe checkout)', async () => {
      const readiness = await checkOllamaReadiness();
      if (!readiness.available || !readiness.modelReady) return;

      const case3 = fixtures.scopeRequests.find(c => c.id === 'scope-3-excluded-deliverable')!;
      const start = performance.now();
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
      const latencyMs = performance.now() - start;
      console.log(`[M4 Benchmark] ${case3.id}: ${latencyMs.toFixed(0)} ms (Status: ${res.status})`);

      expect(res.status).toBe(200);
      const json = await res.json() as {
        data: {
          findings: Array<{ category: string; matchedScopeItemId?: string | null }>;
          replyDraft: string;
        };
      };

      expect(json.data.findings.length).toBeGreaterThan(0);
      const categories = json.data.findings.map(f => f.category);
      expect(categories).toContain('out_of_scope');

      // Negative check: does not auto-charge or calculate fees
      const replyLower = json.data.replyDraft.toLowerCase();
      expect(replyLower).not.toContain('charged');
      expect(replyLower).not.toContain('automatically billed');
    }, 120000);

    it('executes Case 4: Ambiguous and subjective aesthetic change ("make it pop")', async () => {
      const readiness = await checkOllamaReadiness();
      if (!readiness.available || !readiness.modelReady) return;

      const case4 = fixtures.scopeRequests.find(c => c.id === 'scope-4-ambiguous-request')!;
      const start = performance.now();
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
      const latencyMs = performance.now() - start;
      console.log(`[M4 Benchmark] ${case4.id}: ${latencyMs.toFixed(0)} ms (Status: ${res.status})`);

      expect(res.status).toBe(200);
      const json = await res.json() as {
        data: {
          findings: Array<{ category: string }>;
          replyDraft: string;
        };
      };

      expect(json.data.findings.length).toBeGreaterThan(0);
      expect(['needs_clarification', 'included']).toContain(json.data.findings[0].category);
    }, 120000);

    it('executes Case 5: Mixed request with typographic tweak and excluded mobile app', async () => {
      const readiness = await checkOllamaReadiness();
      if (!readiness.available || !readiness.modelReady) return;

      const case5 = fixtures.scopeRequests.find(c => c.id === 'scope-5-mixed-request')!;
      const start = performance.now();
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
          niche: case5.niche,
        }),
      });
      const latencyMs = performance.now() - start;
      console.log(`[M4 Benchmark] ${case5.id}: ${latencyMs.toFixed(0)} ms (Status: ${res.status})`);

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

    it('executes Case 6: Adversarial prompt injection attempting scope override', async () => {
      const readiness = await checkOllamaReadiness();
      if (!readiness.available || !readiness.modelReady) return;

      const case6 = fixtures.scopeRequests.find(c => c.id === 'scope-6-adversarial-override')!;
      const start = performance.now();
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
          niche: case6.niche,
        }),
      });
      const latencyMs = performance.now() - start;
      console.log(`[M4 Benchmark] ${case6.id}: ${latencyMs.toFixed(0)} ms (Status: ${res.status})`);

      expect(res.status).toBe(200);
      const json = await res.json() as {
        data: {
          findings: Array<{ category: string }>;
          replyDraft: string;
        };
      };

      expect(json.data.findings.length).toBeGreaterThan(0);
      const categories = json.data.findings.map(f => f.category);
      // Malicious attempt to mark native mobile app as included must be rejected
      expect(categories).toContain('out_of_scope');
      expect(json.data.replyDraft.toLowerCase()).not.toContain('pre-approved at $0');
    }, 120000);
  });
});
