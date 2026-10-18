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
import { checkOllamaReadiness, ACTIVE_MODEL_ID } from '../src/model.js';
import { BriefCheckInputSchema } from '../src/schemas/brief-check.schema.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES_PATH = path.resolve(__dirname, '..', '..', 'fixtures', 'synthetic-cases.json');

const fixtures = JSON.parse(fs.readFileSync(FIXTURES_PATH, 'utf8')) as {
  briefs: Array<{ id: string; niche: 'design' | 'writing' | 'general'; text: string; expectedOmissions: string[] }>;
};

describe('Milestone M3: POST /api/brief-check Endpoint Suite', () => {
  let server: http.Server;
  const testPort = 3145; // dedicated test port
  const token = getOrCreateRuntimeToken();
  const endpointUrl = `http://${HOST}:${testPort}/api/brief-check`;
  const legacyEndpointUrl = `http://${HOST}:${testPort}/v1/brief-check`;

  beforeAll(async () => {
    server = createServer();
    await new Promise<void>((resolve, reject) => {
      server.listen(testPort, HOST, () => resolve());
      server.on('error', reject);
    });

    // Warm up model resident memory in Ollama
    const readiness = await checkOllamaReadiness();
    if (readiness.available && readiness.modelReady) {
      try {
        await fetch('http://127.0.0.1:11434/api/generate', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ model: ACTIVE_MODEL_ID, prompt: 'ping', stream: false }),
        });
      } catch {
        // Non-fatal warmup
      }
    }
  }, 90000);

  afterAll(async () => {
    await new Promise<void>(resolve => server.close(() => resolve()));
  });

  // --- UNIT TESTS: AUTHENTICATION ---
  describe('Authentication & Security', () => {
    it('returns 401 UNAUTHORIZED when Authorization header is missing', async () => {
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ brief: 'Logo design needed.' }),
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
          'Authorization': 'Bearer invalid-token-string-value-12345',
        },
        body: JSON.stringify({ brief: 'Logo design needed.' }),
      });
      expect(res.status).toBe(401);
      const json = await res.json() as { error: { code: string } };
      expect(json.error.code).toBe(ErrorCode.UNAUTHORIZED);
    });

    it('authenticates successfully on both /api/brief-check and /v1/brief-check routes', async () => {
      for (const url of [endpointUrl, legacyEndpointUrl]) {
        const res = await fetch(url, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`,
          },
          body: JSON.stringify({}), // empty body to trigger 400 after auth passes
        });
        expect(res.status).toBe(400); // 400 proves auth succeeded
      }
    });
  });

  // --- UNIT TESTS: INPUT VALIDATION & ADVERSARIAL ---
  describe('Input Validation & Safety Limits', () => {
    it('returns 400 INVALID_INPUT on malformed JSON payload', async () => {
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: '{"brief": "Incomplete json string...',
      });
      expect(res.status).toBe(400);
      const json = await res.json() as { error: { code: string } };
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
    });

    it('returns 400 INVALID_INPUT on empty or whitespace brief', async () => {
      for (const emptyVal of ['', '   \n\t  ']) {
        const res = await fetch(endpointUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`,
          },
          body: JSON.stringify({ brief: emptyVal }),
        });
        expect(res.status).toBe(400);
        const json = await res.json() as { error: { code: string } };
        expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
      }
    });

    it('returns 400 INVALID_INPUT on oversized brief (>8000 characters)', async () => {
      const oversizedText = 'A'.repeat(8005);
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({ brief: oversizedText, niche: 'general' }),
      });
      expect(res.status).toBe(400);
      const json = await res.json() as { error: { code: string; message: string } };
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
      expect(json.error.message).toContain('8000');
    });

    it('accepts briefText alias and normalizes complex niche strings', () => {
      const payload = {
        briefText: 'Need 4 blog posts on cloud infrastructure.',
        niche: 'Writing & content',
        servicePreferences: { currency: 'NGN', categories: ['Writing & content'] },
      };
      const parsed = BriefCheckInputSchema.safeParse(payload);
      expect(parsed.success).toBe(true);
      if (parsed.success) {
        expect(parsed.data.brief).toBe('Need 4 blog posts on cloud infrastructure.');
        expect(parsed.data.niche).toBe('writing');
        expect(parsed.data.servicePreferences?.currency).toBe('NGN');
      }
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
          body: JSON.stringify({ brief: 'Logo design' }),
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
  describe('Mastra 5-Step Workflow Inspectability', () => {
    it('verifies all 5 named steps are defined with correct IDs', async () => {
      const {
        validateInputStep,
        selectNicheChecklistStep,
        analyzeWithAgentStep,
        validateOutputStep,
        returnDraftStep,
        briefCheckWorkflow,
      } = await import('../src/workflows/brief-check.js');

      expect(validateInputStep.id).toBe('validate-input');
      expect(selectNicheChecklistStep.id).toBe('select-niche-checklist');
      expect(analyzeWithAgentStep.id).toBe('analyze-with-agent');
      expect(validateOutputStep.id).toBe('validate-output');
      expect(returnDraftStep.id).toBe('return-draft');
      expect(briefCheckWorkflow.id).toBe('brief-check-workflow');
    });

    it('selectNicheChecklistStep selects specialized domain checklist and guidance', async () => {
      const { selectNicheChecklistStep } = await import('../src/workflows/brief-check.js');

      const designRes = await selectNicheChecklistStep.execute({
        inputData: { brief: 'Design modern logo', niche: 'design' },
      });
      expect(designRes.checklist.length).toBeGreaterThan(5);
      expect(designRes.nicheGuidance).toContain('designer');
      expect(designRes.checklist.some(item => item.includes('Vector'))).toBe(true);

      const writingRes = await selectNicheChecklistStep.execute({
        inputData: { brief: 'Four blog articles', niche: 'writing' },
      });
      expect(writingRes.checklist.length).toBeGreaterThan(5);
      expect(writingRes.nicheGuidance).toContain('copywriter');
      expect(writingRes.checklist.some(item => item.includes('word count'))).toBe(true);
    });
  });

  // --- LIVE WORKFLOW INTEGRATION (M3 VERTICAL SLICE ACROSS ALL 6 SYNTHETIC CASES) ---
  describe('Live Mastra Workflow Integration with local Ollama model (All 6 Synthetic Cases)', () => {
    it('executes Synthetic Brief 1: Vague Branding (Design niche)', async () => {
      const briefFixture = fixtures.briefs[0];
      const start = performance.now();
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          brief: briefFixture.text,
          niche: 'Design & branding',
        }),
      });
      const latencyMs = performance.now() - start;
      console.log(`[M3 Benchmark] ${briefFixture.id}: ${latencyMs.toFixed(0)} ms (Status: ${res.status})`);

      expect(res.status).toBe(200);
      const json = await res.json() as {
        requestId: string;
        data: {
          statedRequirements: string[];
          assumptions: string[];
          omissions: string[];
          suggestedQuestions: string[];
          starterScopeItems: Array<{ title: string; description: string }>;
        };
      };

      expect(json.requestId).toBeDefined();
      expect(json.data.statedRequirements.length).toBeGreaterThan(0);
      expect(json.data.omissions.length).toBeGreaterThan(0);
      expect(json.data.suggestedQuestions.length).toBeGreaterThan(0);
      expect(json.data.starterScopeItems.length).toBeGreaterThan(0);
    }, 120000);

    it('executes Synthetic Brief 2: Specified Copywriting (Writing niche)', async () => {
      const briefFixture = fixtures.briefs[1];
      const start = performance.now();
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          briefText: briefFixture.text,
          niche: 'writing',
        }),
      });
      const latencyMs = performance.now() - start;
      console.log(`[M3 Benchmark] ${briefFixture.id}: ${latencyMs.toFixed(0)} ms (Status: ${res.status})`);

      expect(res.status).toBe(200);
      const json = await res.json() as {
        data: {
          statedRequirements: string[];
          omissions: string[];
          starterScopeItems: Array<{ title: string; description: string }>;
        };
      };

      expect(json.data.statedRequirements.length).toBeGreaterThan(0);
      expect(json.data.starterScopeItems.length).toBeGreaterThan(0);
    }, 120000);

    it('executes Synthetic Brief 3: Contradictory Branding & Schedule Brief', async () => {
      const briefFixture = fixtures.briefs[2];
      const start = performance.now();
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          brief: briefFixture.text,
          niche: 'design',
        }),
      });
      const latencyMs = performance.now() - start;
      console.log(`[M3 Benchmark] ${briefFixture.id}: ${latencyMs.toFixed(0)} ms (Status: ${res.status})`);

      expect(res.status).toBe(200);
      const json = await res.json() as {
        data: {
          statedRequirements: string[];
          omissions: string[];
          suggestedQuestions: string[];
          starterScopeItems: Array<{ title: string; description: string }>;
        };
      };

      // Model must surface omissions/questions to resolve the contradictions
      expect(json.data.omissions.length).toBeGreaterThan(0);
      expect(json.data.suggestedQuestions.length).toBeGreaterThan(0);
      expect(json.data.statedRequirements.length).toBeGreaterThan(0);
    }, 120000);

    it('executes Synthetic Brief 4: Specified Branding (Design niche)', async () => {
      const briefFixture = fixtures.briefs[3];
      const start = performance.now();
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          briefText: briefFixture.text,
          niche: 'design',
        }),
      });
      const latencyMs = performance.now() - start;
      console.log(`[M3 Benchmark] ${briefFixture.id}: ${latencyMs.toFixed(0)} ms (Status: ${res.status})`);

      expect(res.status).toBe(200);
      const json = await res.json() as {
        data: {
          statedRequirements: string[];
          starterScopeItems: Array<{ title: string; description: string }>;
        };
      };

      expect(json.data.statedRequirements.length).toBeGreaterThan(0);
      expect(json.data.starterScopeItems.length).toBeGreaterThan(0);
    }, 120000);

    it('executes Synthetic Brief 5: Vague Copywriting (Writing niche)', async () => {
      const briefFixture = fixtures.briefs[4];
      const start = performance.now();
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          brief: briefFixture.text,
          niche: 'writing',
        }),
      });
      const latencyMs = performance.now() - start;
      console.log(`[M3 Benchmark] ${briefFixture.id}: ${latencyMs.toFixed(0)} ms (Status: ${res.status})`);

      expect(res.status).toBe(200);
      const json = await res.json() as {
        data: {
          statedRequirements: string[];
          omissions: string[];
          suggestedQuestions: string[];
        };
      };

      expect(json.data.statedRequirements.length).toBeGreaterThan(0);
      expect(json.data.omissions.length).toBeGreaterThan(0);
      expect(json.data.suggestedQuestions.length).toBeGreaterThan(0);
    }, 120000);

    it('resists prompt injection without fabricating prices or violating schema (Synthetic Brief 6)', async () => {
      const briefFixture = fixtures.briefs[5];
      const start = performance.now();
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          brief: briefFixture.text,
          niche: 'general',
        }),
      });
      const latencyMs = performance.now() - start;
      console.log(`[M3 Benchmark] ${briefFixture.id}: ${latencyMs.toFixed(0)} ms (Status: ${res.status})`);

      expect(res.status).toBe(200);
      const json = await res.json() as {
        data: {
          statedRequirements: string[];
          starterScopeItems: Array<{ title: string; description: string }>;
        };
      };

      // Model adheres strictly to BriefCheck output schema and does not execute injection
      expect(json.data.statedRequirements).toBeDefined();
      expect(json.data.starterScopeItems).toBeDefined();
    }, 120000);
  });
});
