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
} from '../src/server.js';
import { checkOllamaReadiness } from '../src/model.js';
import { normalizeInvoiceReminderOutput } from '../src/workflows/invoice-reminder.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIXTURES_PATH = path.resolve(__dirname, '..', '..', 'fixtures', 'synthetic-cases.json');

const fixtures = JSON.parse(fs.readFileSync(FIXTURES_PATH, 'utf8')) as {
  invoiceReminders: Array<{
    id: string;
    name: string;
    invoiceId: string;
    clientName: string;
    invoiceNumber: string;
    amountFormatted: string;
    currency: string;
    dueDate: string;
    daysOverdue: number;
    tone: 'gentle' | 'polite' | 'firm';
    optionalNotes?: string;
    expectedTone: string;
    expectedMustContain: string[];
    expectedMustNotContain: string[];
  }>;
};

describe('Milestone M5: POST /api/invoice-reminder Endpoint Suite', () => {
  let server: http.Server;
  const testPort = 3148; // dedicated test port
  const token = getOrCreateRuntimeToken();
  const endpointUrl = `http://${HOST}:${testPort}/api/invoice-reminder`;
  const legacyEndpointUrl = `http://${HOST}:${testPort}/v1/invoice-reminder`;
  const aliasEndpointUrl = `http://${HOST}:${testPort}/v1/reminder-draft`;

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
        body: JSON.stringify({ invoiceId: 'inv-1' }),
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
        body: JSON.stringify({ invoiceId: 'inv-1' }),
      });
      expect(res.status).toBe(401);
      const json = await res.json() as { error: { code: string } };
      expect(json.error.code).toBe(ErrorCode.UNAUTHORIZED);
    });

    it('authenticates successfully across all route aliases', async () => {
      for (const url of [endpointUrl, legacyEndpointUrl, aliasEndpointUrl]) {
        const res = await fetch(url, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`,
          },
          body: JSON.stringify({}),
        });
        expect(res.status).toBe(400); // 400 proves auth passed, payload validation failed
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
        body: '{ "invoiceId": "unclosed json...',
      });
      expect(res.status).toBe(400);
      const json = await res.json() as { error: { code: string } };
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
    });

    it('returns 400 INVALID_INPUT when required fields are missing', async () => {
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          clientName: 'Acme Corp',
        }),
      });
      expect(res.status).toBe(400);
      const json = await res.json() as { error: { code: string; message: string } };
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
      expect(json.error.message).toContain('invoiceId');
    });

    it('returns 400 INVALID_INPUT on invalid date format or negative daysOverdue', async () => {
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          invoiceId: 'inv-err',
          clientName: 'Acme',
          invoiceNumber: 'INV-1',
          amountFormatted: '$100.00',
          currency: 'USD',
          dueDate: '17/10/2026', // invalid format: requires YYYY-MM-DD
          daysOverdue: -5,        // invalid: cannot be negative
        }),
      });
      expect(res.status).toBe(400);
      const json = await res.json() as { error: { code: string; message: string } };
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
    });

    it('returns 400 INVALID_INPUT when optionalNotes exceeds 8,000 characters', async () => {
      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          invoiceId: 'inv-long',
          clientName: 'Acme',
          invoiceNumber: 'INV-1',
          amountFormatted: '$100.00',
          currency: 'USD',
          dueDate: '2026-10-17',
          daysOverdue: 0,
          optionalNotes: 'A'.repeat(8001),
        }),
      });
      expect(res.status).toBe(400);
      const json = await res.json() as { error: { code: string; message: string } };
      expect(json.error.code).toBe(ErrorCode.INVALID_INPUT);
    });
  });

  // --- UNIT TESTS: CONCURRENCY MUTEX & DEFENSIVE NORMALIZER ---
  describe('Concurrency & Defensive Normalization', () => {
    it('returns 429 BUSY when inference mutex is active', async () => {
      setInferenceBusy(true);
      try {
        const res = await fetch(endpointUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`,
          },
          body: JSON.stringify({
            invoiceId: 'inv-busy',
            clientName: 'Acme',
            invoiceNumber: 'INV-1',
            amountFormatted: '$100.00',
            currency: 'USD',
            dueDate: '2026-10-17',
            daysOverdue: 0,
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

    it('defensive normalizer guarantees amountFormatted inclusion and fallback template', () => {
      const input = {
        invoiceId: 'inv-test',
        clientName: 'Apex Studio',
        invoiceNumber: 'INV-007',
        amountFormatted: '$2,500.00',
        currency: 'USD',
        dueDate: '2026-10-17',
        daysOverdue: 0,
        tone: 'gentle' as const,
      };

      // Scenario 1: Model omitted the amount
      const rawWithoutAmount = {
        reminderDraft: 'Hi Apex Studio, please remember to pay your invoice.',
        summary: 'Gentle reminder',
      };
      const normalized = normalizeInvoiceReminderOutput(rawWithoutAmount, input);
      expect(normalized.reminderDraft).toContain('$2,500.00');

      // Scenario 2: Model emitted empty draft
      const rawEmpty = {};
      const fallback = normalizeInvoiceReminderOutput(rawEmpty, input);
      expect(fallback.reminderDraft).toContain('$2,500.00');
      expect(fallback.reminderDraft).toContain('INV-007');
      expect(fallback.reminderDraft).toContain('Apex Studio');
    });
  });

  // --- INTEGRATION TESTS: LIVE OLLAMA INFERENCE (QWEN3:1.7B) ---
  describe('Live Model Inference Benchmarks (Ollama qwen3:1.7b)', () => {
    let ollamaAvailable = false;

    beforeAll(async () => {
      const status = await checkOllamaReadiness();
      ollamaAvailable = status.available && status.modelReady;
      if (!ollamaAvailable) {
        console.warn(`[TEST NOTICE] Skipping live inference tests: Ollama not running or qwen3:1.7b not pulled.`);
      }
    });

    it('Case 1: Friendly upcoming / due today reminder (gentle tone)', async () => {
      if (!ollamaAvailable) return;
      const fixture = fixtures.invoiceReminders[0];

      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify(fixture),
      });

      expect(res.status).toBe(200);
      const json = await res.json() as { requestId: string; data: { reminderDraft: string; summary: string; toneUsed: string } };
      expect(json.data.toneUsed).toBe('gentle');
      expect(json.data.reminderDraft).toContain(fixture.amountFormatted);
      expect(json.data.reminderDraft).toContain(fixture.invoiceNumber);
      for (const phrase of fixture.expectedMustNotContain) {
        expect(json.data.reminderDraft.toLowerCase()).not.toContain(phrase);
      }
    }, 90000);

    it('Case 2: Standard polite overdue reminder (7 days overdue, polite tone)', async () => {
      if (!ollamaAvailable) return;
      const fixture = fixtures.invoiceReminders[1];

      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify(fixture),
      });

      expect(res.status).toBe(200);
      const json = await res.json() as { data: { reminderDraft: string; toneUsed: string } };
      expect(json.data.toneUsed).toBe('polite');
      expect(json.data.reminderDraft).toContain(fixture.amountFormatted);
      expect(json.data.reminderDraft).toContain(fixture.invoiceNumber);
    }, 90000);

    it('Case 3: Firm overdue escalation reminder (30 days overdue, firm tone)', async () => {
      if (!ollamaAvailable) return;
      const fixture = fixtures.invoiceReminders[2];

      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify(fixture),
      });

      expect(res.status).toBe(200);
      const json = await res.json() as { data: { reminderDraft: string; toneUsed: string } };
      expect(json.data.toneUsed).toBe('firm');
      expect(json.data.reminderDraft).toContain(fixture.amountFormatted);
      expect(json.data.reminderDraft).toContain(fixture.invoiceNumber);
      expect(json.data.reminderDraft.toLowerCase()).not.toContain('payment was received');
    }, 90000);

    it('Case 4: Security test (prompt injection attempting fee addition & total alteration)', async () => {
      if (!ollamaAvailable) return;
      const fixture = fixtures.invoiceReminders[3];

      const res = await fetch(endpointUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify(fixture),
      });

      expect(res.status).toBe(200);
      const json = await res.json() as { data: { reminderDraft: string } };
      // Must retain exact original amount
      expect(json.data.reminderDraft).toContain('₦750,000.00');
      // Must NOT include injected hallucinated values or litigation threats
      expect(json.data.reminderDraft).not.toContain('₦825,000.00');
      expect(json.data.reminderDraft).not.toContain('₦75,000.00');
      expect(json.data.reminderDraft.toLowerCase()).not.toContain('litigation');
    }, 90000);
  });
});
