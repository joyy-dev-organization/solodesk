import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { checkOllamaReadiness, ACTIVE_MODEL_ID } from './model.js';
import { runBriefCheck, briefCheckWorkflow } from './workflows/brief-check.js';
import { runScopeCheck, scopeCheckWorkflow } from './workflows/scope-check.js';
import { BriefCheckInputSchema } from './schemas/brief-check.schema.js';
import { ScopeCheckInputSchema } from './schemas/scope-check.schema.js';

export const PORT = 3141;
export const HOST = '127.0.0.1';
export const SERVICE_VERSION = '0.1.0';
export const SERVICE_NAME = 'solodesk-service';
export const MAX_INPUT_CHARS = 8000;
export const INFERENCE_TIMEOUT_MS = 75000; // 75s bounded timeout

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TOKEN_FILE_PATH = path.resolve(__dirname, '..', '.runtime-token');

// Single-concurrency mutex lock
let isInferenceBusy = false;

export function getInferenceBusy(): boolean {
  return isInferenceBusy;
}

export function setInferenceBusy(busy: boolean): void {
  isInferenceBusy = busy;
}

// Generate ephemeral local token
export function getOrCreateRuntimeToken(): string {
  try {
    if (fs.existsSync(TOKEN_FILE_PATH)) {
      const existing = fs.readFileSync(TOKEN_FILE_PATH, 'utf8').trim();
      if (existing) return existing;
    }
  } catch {
    // Fall through to generate
  }

  const token = crypto.randomBytes(24).toString('hex');
  try {
    fs.writeFileSync(TOKEN_FILE_PATH, token, { mode: 0o600 });
  } catch {
    // If writing fails, token remains in memory
  }
  return token;
}

export const RUNTIME_TOKEN = getOrCreateRuntimeToken();

export const ErrorCode = {
  UNAUTHORIZED: 'UNAUTHORIZED',
  INVALID_INPUT: 'INVALID_INPUT',
  BUSY: 'BUSY',
  MODEL_UNAVAILABLE: 'MODEL_UNAVAILABLE',
  MODEL_NOT_FOUND: 'MODEL_NOT_FOUND',
  TIMEOUT: 'TIMEOUT',
  INVALID_OUTPUT: 'INVALID_OUTPUT',
} as const;

export type SafeErrorCode = (typeof ErrorCode)[keyof typeof ErrorCode];

export interface SafeErrorEnvelope {
  error: {
    code: SafeErrorCode;
    message: string;
    retryable: boolean;
    requestId: string;
  };
}

export function safeCompareTokens(a: string, b: string): boolean {
  const bufA = Buffer.from(a, 'utf8');
  const bufB = Buffer.from(b, 'utf8');
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

function sendJson(res: http.ServerResponse, statusCode: number, payload: unknown) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'X-SoloDesk-Loopback': 'true',
  });
  res.end(JSON.stringify(payload));
}

function sendError(
  res: http.ServerResponse,
  statusCode: number,
  code: SafeErrorCode,
  message: string,
  retryable: boolean,
  requestId: string
) {
  const envelope: SafeErrorEnvelope = {
    error: { code, message, retryable, requestId },
  };
  sendJson(res, statusCode, envelope);
}

function readBody(req: http.IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', chunk => {
      data += chunk;
      if (data.length > 100000) {
        reject(new Error('Payload too large'));
      }
    });
    req.on('end', () => resolve(data));
    req.on('error', reject);
  });
}

function authenticate(req: http.IncomingMessage): boolean {
  const authHeader = req.headers['authorization'];
  if (!authHeader) return false;
  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match?.[1]) return false;
  return safeCompareTokens(match[1].trim(), RUNTIME_TOKEN);
}

export async function getServiceHealth() {
  const ollamaStatus = await checkOllamaReadiness();
  return {
    status: ollamaStatus.available && ollamaStatus.modelReady ? 'ok' : 'degraded',
    service: SERVICE_NAME,
    version: SERVICE_VERSION,
    loopbackOnly: true,
    ollama: ollamaStatus,
    activeModel: ACTIVE_MODEL_ID,
  };
}

export function createServer(): http.Server {
  return http.createServer(async (req, res) => {
    const url = new URL(req.url ?? '/', `http://${HOST}:${PORT}`);
    const requestId = (req.headers['x-request-id'] as string) || crypto.randomUUID();

    // Health route: no auth required, strictly loopback
    if (req.method === 'GET' && url.pathname === '/health') {
      const health = await getServiceHealth();
      return sendJson(res, 200, health);
    }

    // All protected endpoints require local bearer authentication
    const isBriefCheck = req.method === 'POST' && (url.pathname === '/api/brief-check' || url.pathname === '/v1/brief-check');
    const isScopeCheck = req.method === 'POST' && (url.pathname === '/api/scope-check' || url.pathname === '/v1/scope-check');

    if (!authenticate(req)) {
      return sendError(res, 401, ErrorCode.UNAUTHORIZED, 'Unauthorized: Invalid or missing local bearer token', false, requestId);
    }

    // BriefCheck endpoint
    if (isBriefCheck) {
      if (isInferenceBusy) {
        return sendError(
          res,
          429,
          ErrorCode.BUSY,
          'Another inference task is currently executing. SoloDesk enforces single concurrency.',
          true,
          requestId
        );
      }

      let rawBody: string;
      try {
        rawBody = await readBody(req);
      } catch {
        return sendError(res, 400, ErrorCode.INVALID_INPUT, 'Failed to read request body', false, requestId);
      }

      let parsedJson: unknown;
      try {
        parsedJson = JSON.parse(rawBody);
      } catch {
        return sendError(res, 400, ErrorCode.INVALID_INPUT, 'Malformed JSON in request body', false, requestId);
      }

      const validated = BriefCheckInputSchema.safeParse(parsedJson);
      if (!validated.success) {
        const errorMsg = validated.error.issues.map(i => `${i.path.join('.')}: ${i.message}`).join('; ');
        return sendError(res, 400, ErrorCode.INVALID_INPUT, errorMsg, false, requestId);
      }

      // Check Ollama readiness
      const ollama = await checkOllamaReadiness();
      if (!ollama.available) {
        return sendError(res, 503, ErrorCode.MODEL_UNAVAILABLE, 'Local Ollama service is not running on 127.0.0.1:11434', true, requestId);
      }
      if (!ollama.modelReady) {
        return sendError(res, 503, ErrorCode.MODEL_NOT_FOUND, `Required model ${ACTIVE_MODEL_ID} is not pulled in local Ollama`, false, requestId);
      }

      isInferenceBusy = true;
      let activeRun: any = null;

      try {
        const timeoutPromise = new Promise<never>((_, reject) => {
          const timer = setTimeout(() => reject(new Error('TIMEOUT_EXCEEDED')), INFERENCE_TIMEOUT_MS);
          timer.unref();
        });

        const runPromise = (async () => {
          const run = await briefCheckWorkflow.createRun({ runId: requestId });
          activeRun = run;
          const executionResult = await run.start({ inputData: validated.data });
          if (executionResult.status !== 'success') {
            const failureMsg = (executionResult as any).error?.message || 'Workflow run failed';
            throw new Error(failureMsg);
          }
          return executionResult.result;
        })();

        const result = await Promise.race([runPromise, timeoutPromise]);
        return sendJson(res, 200, { requestId, data: result });
      } catch (err) {
        if (activeRun && typeof activeRun.cancel === 'function') {
          await activeRun.cancel().catch(() => {});
        }
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === 'TIMEOUT_EXCEEDED') {
          return sendError(res, 504, ErrorCode.TIMEOUT, `Inference exceeded maximum timeout of ${INFERENCE_TIMEOUT_MS / 1000} seconds`, true, requestId);
        }
        if (msg.includes('INVALID_OUTPUT')) {
          return sendError(res, 502, ErrorCode.INVALID_OUTPUT, msg, true, requestId);
        }
        return sendError(res, 500, ErrorCode.MODEL_UNAVAILABLE, `Inference execution failed: ${msg}`, true, requestId);
      } finally {
        isInferenceBusy = false;
      }
    }

    // ScopeCheck endpoint
    if (isScopeCheck) {
      if (isInferenceBusy) {
        return sendError(res, 429, ErrorCode.BUSY, 'Another inference task is currently executing. Bounded to single concurrency.', true, requestId);
      }

      let rawBody: string;
      try {
        rawBody = await readBody(req);
      } catch {
        return sendError(res, 400, ErrorCode.INVALID_INPUT, 'Failed to read request body', false, requestId);
      }

      let parsedJson: unknown;
      try {
        parsedJson = JSON.parse(rawBody);
      } catch {
        return sendError(res, 400, ErrorCode.INVALID_INPUT, 'Malformed JSON in request body', false, requestId);
      }

      const validated = ScopeCheckInputSchema.safeParse(parsedJson);
      if (!validated.success) {
        return sendError(res, 400, ErrorCode.INVALID_INPUT, validated.error.message, false, requestId);
      }

      const ollama = await checkOllamaReadiness();
      if (!ollama.available) {
        return sendError(res, 503, ErrorCode.MODEL_UNAVAILABLE, 'Local Ollama service is not running on 127.0.0.1:11434', true, requestId);
      }
      if (!ollama.modelReady) {
        return sendError(res, 503, ErrorCode.MODEL_NOT_FOUND, `Required model ${ACTIVE_MODEL_ID} is not pulled in local Ollama`, false, requestId);
      }

      isInferenceBusy = true;
      let activeRun: any = null;

      try {
        const timeoutPromise = new Promise<never>((_, reject) => {
          const timer = setTimeout(() => reject(new Error('TIMEOUT_EXCEEDED')), INFERENCE_TIMEOUT_MS);
          timer.unref();
        });

        const runPromise = (async () => {
          const run = await scopeCheckWorkflow.createRun({ runId: requestId });
          activeRun = run;
          const executionResult = await run.start({ inputData: validated.data });
          if (executionResult.status !== 'success') {
            const failureMsg = (executionResult as any).error?.message || 'Workflow run failed';
            throw new Error(failureMsg);
          }
          return executionResult.result;
        })();

        const result = await Promise.race([runPromise, timeoutPromise]);
        return sendJson(res, 200, { requestId, data: result });
      } catch (err) {
        if (activeRun && typeof activeRun.cancel === 'function') {
          await activeRun.cancel().catch(() => {});
        }
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === 'TIMEOUT_EXCEEDED') {
          return sendError(res, 504, ErrorCode.TIMEOUT, `Inference exceeded maximum timeout of ${INFERENCE_TIMEOUT_MS / 1000} seconds`, true, requestId);
        }
        if (msg.includes('INVALID_OUTPUT')) {
          return sendError(res, 502, ErrorCode.INVALID_OUTPUT, msg, true, requestId);
        }
        return sendError(res, 500, ErrorCode.MODEL_UNAVAILABLE, `Inference execution failed: ${msg}`, true, requestId);
      } finally {
        isInferenceBusy = false;
      }
    }

    return sendError(res, 404, ErrorCode.INVALID_INPUT, `Route ${req.method} ${url.pathname} not found`, false, requestId);
  });
}

export function startServer(port = PORT, host = HOST): Promise<http.Server> {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.listen(port, host, () => {
      console.log(`[SoloDesk] Service listening strictly on http://${host}:${port}`);
      resolve(server);
    });
    server.on('error', reject);
  });
}
