import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import http from 'node:http';
import type { AddressInfo } from 'node:net';
import {
  createServer,
  HOST,
  getOrCreateRuntimeToken,
  ErrorCode,
  setInferenceBusy,
} from '../src/server.js';
import { checkOllamaReadiness } from '../src/model.js';
import { normalizeOfferDraftOutput } from '../src/workflows/offer-draft.js';
import { OfferDraftInputSchema } from '../src/schemas/offer-draft.schema.js';

describe('Milestone M7: POST /v1/offer-draft Endpoint Suite', () => {
  let server: http.Server;
  let testPort: number;
  let endpointUrl: string;
  let aliasApiUrl: string;
  let aliasServicePlanUrl: string;
  const token = getOrCreateRuntimeToken();

  beforeAll(async () => {
    server = createServer();
    await new Promise<void>((resolve, reject) => {
      // Use ephemeral port 0 to prevent collisions
      server.listen(0, HOST, () => {
        testPort = (server.address() as AddressInfo).port;
        endpointUrl = `http://${HOST}:${testPort}/v1/offer-draft`;
        aliasApiUrl = `http://${HOST}:${testPort}/api/offer-draft`;
        aliasServicePlanUrl = `http://${HOST}:${testPort}/v1/service-plan-offer`;
        resolve();
      });
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
        body: JSON.stringify({ clientName: 'Amina Musa' }),
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
          'Authorization': 'Bearer bad-token-xyz-999',
        },
        body: JSON.stringify({ clientName: 'Amina Musa' }),
      });
      expect(res.status).toBe(401);
      const json = await res.json() as { error: { code: string } };
      expect(json.error.code).toBe(ErrorCode.UNAUTHORIZED);
    });

    it('returns 403 UNAUTHORIZED when browser Origin header is supplied (CSRF protection)', async () => {
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
          'Origin': 'http://evil-website.com',
        },
        body: JSON.stringify({ clientName: 'Amina Musa' }),
      });
      expect(res.status).toBe(403);
      const json = await res.json() as { error: { code: string; message: string } };
      expect(json.error.code).toBe(ErrorCode.UNAUTHORIZED);
      expect(json.error.message).toContain('Browser origins are strictly prohibited');
    });

    it('routes alias endpoints /api/offer-draft and /v1/service-plan-offer identically', async () => {
      // Missing auth should trigger 401 on both aliases
      const res1 = await fetch(aliasApiUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
      expect(res1.status).toBe(401);

      const res2 = await fetch(aliasServicePlanUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
      expect(res2.status).toBe(401);
    });
  });

  // --- UNIT TESTS: INPUT VALIDATION ---
  describe('Input Validation & Bound Enforcement', () => {
    it('returns 400 INVALID_INPUT on malformed JSON', async () => {
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: '{ clientName: "Broken JSON',
      });
      expect(res.status).toBe(400);
      const json = await res.json() as { error: { code: string; message: string } };
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
      expect(json.error.message).toContain('Malformed JSON');
    });

    it('returns 400 INVALID_INPUT when body exceeds MAX_INPUT_CHARS (8,000 chars)', async () => {
      const hugeString = 'a'.repeat(8500);
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          clientName: 'Amina Musa',
          planTitle: 'Design retainer',
          serviceNiche: 'Design & branding',
          deliverables: ['Logo assets'],
          revisionLimits: '2 rounds',
          priceFormatted: '₦150,000/mo',
          optionalNotes: hugeString,
        }),
      });
      expect(res.status).toBe(400);
      const json = await res.json() as { error: { code: string; message: string } };
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
      expect(json.error.message).toContain('exceeds maximum size');
    });

    it('returns 400 INVALID_INPUT when deliverables array is empty', async () => {
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          clientName: 'Amina Musa',
          planTitle: 'Design retainer',
          serviceNiche: 'Design & branding',
          deliverables: [],
          revisionLimits: '2 rounds',
          priceFormatted: '₦150,000/mo',
        }),
      });
      expect(res.status).toBe(400);
      const json = await res.json() as { error: { code: string; message: string } };
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
      expect(json.error.message).toContain('At least one deliverable');
    });

    it('returns 429 BUSY when inference mutex lock is held', async () => {
      setInferenceBusy(true);
      try {
        const res = await fetch(endpointUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`,
          },
          body: JSON.stringify({
            clientName: 'Amina Musa',
            planTitle: 'Design retainer',
            serviceNiche: 'Design & branding',
            deliverables: ['Logo assets'],
            revisionLimits: '2 rounds',
            priceFormatted: '₦150,000/mo',
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

  // --- UNIT TESTS: DEFENSIVE NORMALIZER & ANTI-OVERCLAIMING ---
  describe('Defensive Normalizer & Anti-Overclaiming Rules', () => {
    const sampleInput = OfferDraftInputSchema.parse({
      clientName: 'Amina Musa',
      planTitle: 'Monthly Content Package',
      serviceNiche: 'Writing & content',
      deliverables: ['4 Blog articles', '2 Newsletters'],
      exclusions: ['Video editing'],
      revisionLimits: '2 rounds per deliverable',
      priceFormatted: '₦180,000/month',
      cadence: 'monthly',
      tone: 'collaborative',
      isRenewal: true,
    });

    it('purges fabricated statements claiming client signed or renewed agreement', () => {
      const rawInjectedOutput = {
        offerText: 'Hi Amina Musa! Thank you for renewing your monthly retainer with us! As agreed in our signed contract, your card has been charged ₦180,000/month. We will provide 4 Blog articles and 2 Newsletters with 2 rounds per deliverable.',
        deliverablesSummary: '4 articles and 2 newsletters',
        termsSummary: '₦180,000/month; 2 rounds per deliverable',
      };

      const normalized = normalizeOfferDraftOutput(rawInjectedOutput, sampleInput);

      expect(normalized.offerText).not.toContain('Thank you for renewing');
      expect(normalized.offerText).not.toContain('signed contract');
      expect(normalized.offerText).not.toContain('card has been charged');
      expect(normalized.offerText).toContain('Amina Musa');
      expect(normalized.factPreservation.pricePreserved).toBe(true);
      expect(normalized.factPreservation.cadencePreserved).toBe(true);
      expect(normalized.factPreservation.revisionLimitsPreserved).toBe(true);
    });

    it('generates high-quality fallback proposal when model output is empty', () => {
      const normalized = normalizeOfferDraftOutput({}, sampleInput);

      expect(normalized.offerText).toContain('Hi Amina Musa');
      expect(normalized.offerText).toContain('Monthly Content Package');
      expect(normalized.offerText).toContain('4 Blog articles');
      expect(normalized.offerText).toContain('₦180,000/month');
      expect(normalized.offerText).toContain('2 rounds per deliverable');
      expect(normalized.offerText).toContain('Video editing');
      expect(normalized.factPreservation.pricePreserved).toBe(true);
      expect(normalized.factPreservation.cadencePreserved).toBe(true);
      expect(normalized.factPreservation.revisionLimitsPreserved).toBe(true);
    });

    it('appends structured terms block if model dropped fee or revision limits', () => {
      const rawIncompleteOutput = {
        offerText: 'Hi Amina Musa,\n\nI look forward to continuing our collaboration on content deliverables.',
      };

      const normalized = normalizeOfferDraftOutput(rawIncompleteOutput, sampleInput);

      expect(normalized.offerText).toContain('Proposed Plan Terms');
      expect(normalized.offerText).toContain('Proposed Fee: ₦180,000/month (monthly)');
      expect(normalized.offerText).toContain('Revision Limit: 2 rounds per deliverable');
    });
  });

  // --- LIVE MODEL TESTS (OLLAMA qwen3:1.7b) ---
  describe('Live Model Inference (Ollama)', () => {
    it('executes live Repeat Work proposal generation and preserves plan facts', async () => {
      const readiness = await checkOllamaReadiness();
      if (!readiness.available || !readiness.modelReady) {
        console.warn('[Live Skip] Local Ollama service or model not ready');
        return;
      }

      const payload = {
        clientName: 'Amina Musa',
        planTitle: 'Brand Maintenance Retainer',
        serviceNiche: 'Design & branding',
        deliverables: ['8 Social templates', '2 Banner graphics'],
        exclusions: ['3D Modeling'],
        revisionLimits: '2 rounds per deliverable',
        priceFormatted: '₦150,000/month',
        cadence: 'monthly',
        tone: 'collaborative',
        isRenewal: false,
      };

      const start = Date.now();
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify(payload),
      });

      const elapsed = Date.now() - start;
      console.log(`[M7 Benchmark] offer-draft-live: ${elapsed}ms (Status: ${res.status})`);

      expect(res.status).toBe(200);
      const json = await res.json() as {
        requestId: string;
        data: {
          offerText: string;
          deliverablesSummary: string;
          termsSummary: string;
          factPreservation: {
            pricePreserved: boolean;
            cadencePreserved: boolean;
            revisionLimitsPreserved: boolean;
          };
        };
      };

      expect(json.requestId).toBeDefined();
      expect(json.data.offerText).toBeDefined();
      expect(json.data.offerText.length).toBeGreaterThan(50);
      expect(json.data.offerText).toContain('Amina Musa');
      expect(json.data.factPreservation.pricePreserved).toBe(true);
      expect(json.data.factPreservation.cadencePreserved).toBe(true);
      expect(json.data.factPreservation.revisionLimitsPreserved).toBe(true);

      // CRITICAL M7 ASSERTION: Must NOT claim client agreed or renewed
      const lower = json.data.offerText.toLowerCase();
      expect(lower).not.toContain('thank you for renewing');
      expect(lower).not.toContain('signed agreement');
      expect(lower).not.toContain('card was charged');
    }, 120000);
  });
});
