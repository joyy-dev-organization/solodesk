import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  createServer,
  PORT,
  HOST,
  RUNTIME_TOKEN,
  getOrCreateRuntimeToken,
} from '../src/server.js';
import { checkOllamaReadiness, ACTIVE_MODEL_ID } from '../src/model.js';
import { runBriefCheck } from '../src/workflows/brief-check.js';
import { runScopeCheck } from '../src/workflows/scope-check.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES_PATH = path.resolve(__dirname, '..', '..', 'fixtures', 'synthetic-cases.json');

const fixtures = JSON.parse(fs.readFileSync(FIXTURES_PATH, 'utf8')) as {
  briefs: Array<{ id: string; niche: 'design' | 'writing' | 'general'; text: string; expectedOmissions: string[] }>;
  scopeRequests: Array<{
    id: string;
    requestText: string;
    scopeVersionId: string;
    scopeItems: Array<{ id: string; title: string; description: string }>;
    expectedClassification: string;
  }>;
};

describe('Milestone M1 Integration Spike & Benchmarking', () => {
  let server: http.Server;
  const testPort = 3142; // dedicated test port

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

  it('verifies Ollama readiness on local loopback', async () => {
    const readiness = await checkOllamaReadiness();
    expect(readiness.available, `Ollama should be available: ${readiness.error}`).toBe(true);
    expect(readiness.modelReady, `Model ${ACTIVE_MODEL_ID} should be pulled: found [${readiness.modelsFound.join(', ')}]`).toBe(true);
  });

  it('serves GET /health with loopback status and model info', async () => {
    const res = await fetch(`http://${HOST}:${testPort}/health`);
    expect(res.status).toBe(200);
    const body = await res.json() as { status: string; loopbackOnly: boolean; activeModel: string };
    expect(body.status).toBe('ok');
    expect(body.loopbackOnly).toBe(true);
    expect(body.activeModel).toBe(ACTIVE_MODEL_ID);
  });

  it('rejects unauthenticated requests to protected endpoints', async () => {
    const res = await fetch(`http://${HOST}:${testPort}/v1/brief-check`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ brief: 'Short brief' }),
    });
    expect(res.status).toBe(401);
    const body = await res.json() as { error: { code: string } };
    expect(body.error.code).toBe('INVALID_INPUT');
  });

  it('rejects oversized inputs (>8,000 characters)', async () => {
    const token = getOrCreateRuntimeToken();
    const oversizedText = 'A'.repeat(8005);
    const res = await fetch(`http://${HOST}:${testPort}/v1/brief-check`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
      body: JSON.stringify({ brief: oversizedText, niche: 'general' }),
    });
    expect(res.status).toBe(400);
    const body = await res.json() as { error: { code: string; message: string } };
    expect(body.error.code).toBe('INVALID_INPUT');
    expect(body.error.message).toContain('8000');
  });

  describe('Live Model Synthetic Benchmarking (3 Briefs + 3 Scope Requests)', () => {
    const latencyRecords: Array<{ test: string; durationMs: number; isWarm: boolean }> = [];

    // Test 1: Cold start BriefCheck
    it('executes Synthetic Brief 1 (Vague Branding) - Cold start', async () => {
      const briefFixture = fixtures.briefs[0];
      const start = Date.now();
      const output = await runBriefCheck({
        brief: briefFixture.text,
        niche: briefFixture.niche,
      });
      const durationMs = Date.now() - start;
      latencyRecords.push({ test: briefFixture.id, durationMs, isWarm: false });

      console.log(`[BENCHMARK] ${briefFixture.id} (COLD): ${durationMs}ms`);
      expect(output.statedRequirements.length).toBeGreaterThan(0);
      expect(output.omissions.length).toBeGreaterThan(0);
      expect(output.suggestedQuestions.length).toBeGreaterThan(0);
      expect(output.starterScopeItems.length).toBeGreaterThan(0);
    }, 120000);

    // Test 2: Warm BriefCheck
    it('executes Synthetic Brief 2 (Specified Copywriting) - Warm run', async () => {
      const briefFixture = fixtures.briefs[1];
      const start = Date.now();
      const output = await runBriefCheck({
        brief: briefFixture.text,
        niche: briefFixture.niche,
      });
      const durationMs = Date.now() - start;
      latencyRecords.push({ test: briefFixture.id, durationMs, isWarm: true });

      console.log(`[BENCHMARK] ${briefFixture.id} (WARM): ${durationMs}ms`);
      expect(output.statedRequirements.length).toBeGreaterThan(0);
      expect(durationMs).toBeLessThan(90000); // within bounded timeout
    }, 120000);

    // Test 3: Warm BriefCheck
    it('executes Synthetic Brief 3 (Web Development) - Warm run', async () => {
      const briefFixture = fixtures.briefs[2];
      const start = Date.now();
      const output = await runBriefCheck({
        brief: briefFixture.text,
        niche: briefFixture.niche,
      });
      const durationMs = Date.now() - start;
      latencyRecords.push({ test: briefFixture.id, durationMs, isWarm: true });

      console.log(`[BENCHMARK] ${briefFixture.id} (WARM): ${durationMs}ms`);
      expect(output.starterScopeItems.length).toBeGreaterThan(0);
    }, 120000);

    // Test 4: ScopeShield Included Revision
    it('executes ScopeShield 1 (Included Adjustment)', async () => {
      const scopeFixture = fixtures.scopeRequests[0];
      const start = Date.now();
      const output = await runScopeCheck({
        requestText: scopeFixture.requestText,
        scopeVersionId: scopeFixture.scopeVersionId,
        scopeItems: scopeFixture.scopeItems,
      });
      const durationMs = Date.now() - start;
      latencyRecords.push({ test: scopeFixture.id, durationMs, isWarm: true });

      console.log(`[BENCHMARK] ${scopeFixture.id} (WARM): ${durationMs}ms`);
      expect(output.evaluations.length).toBeGreaterThan(0);
      const classifications = output.evaluations.map(e => e.classification);
      expect(classifications).toContain('INCLUDED');
      expect(output.suggestedReply.length).toBeGreaterThan(10);
    }, 120000);

    // Test 5: ScopeShield Outside Deliverable
    it('executes ScopeShield 2 (Excluded Deliverable)', async () => {
      const scopeFixture = fixtures.scopeRequests[1];
      const start = Date.now();
      const output = await runScopeCheck({
        requestText: scopeFixture.requestText,
        scopeVersionId: scopeFixture.scopeVersionId,
        scopeItems: scopeFixture.scopeItems,
      });
      const durationMs = Date.now() - start;
      latencyRecords.push({ test: scopeFixture.id, durationMs, isWarm: true });

      console.log(`[BENCHMARK] ${scopeFixture.id} (WARM): ${durationMs}ms`);
      expect(output.evaluations.length).toBeGreaterThan(0);
      const classifications = output.evaluations.map(e => e.classification);
      expect(classifications).toContain('POTENTIALLY_OUTSIDE');
    }, 120000);

    // Test 6: ScopeShield Ambiguous Request
    it('executes ScopeShield 3 (Ambiguous Request)', async () => {
      const scopeFixture = fixtures.scopeRequests[2];
      const start = Date.now();
      const output = await runScopeCheck({
        requestText: scopeFixture.requestText,
        scopeVersionId: scopeFixture.scopeVersionId,
        scopeItems: scopeFixture.scopeItems,
      });
      const durationMs = Date.now() - start;
      latencyRecords.push({ test: scopeFixture.id, durationMs, isWarm: true });

      console.log(`[BENCHMARK] ${scopeFixture.id} (WARM): ${durationMs}ms`);
      expect(output.evaluations.length).toBeGreaterThan(0);
      expect(output.suggestedReply.length).toBeGreaterThan(10);
    }, 120000);
  });
});
