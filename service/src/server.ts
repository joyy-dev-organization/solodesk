import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { checkOllamaReadiness, ACTIVE_MODEL_ID } from './model.js';
import { runBriefCheck } from './workflows/brief-check.js';
import { runScopeCheck } from './workflows/scope-check.js';
import { BriefCheckInputSchema } from './schemas/brief-check.schema.js';
import { ScopeCheckInputSchema } from './schemas/scope-check.schema.js';

export const PORT = 3141;
export const HOST = '127.0.0.1';
export const SERVICE_VERSION = '0.1.0';
export const SERVICE_NAME = 'solodesk-service';
export const MAX_INPUT_CHARS = 8000;
export const INFERENCE_TIMEOUT_MS = 90000; // 90s bounded timeout

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TOKEN_FILE_PATH = path.resolve(__dirname, '..', '.runtime-token');

// Single-concurrency mutex lock
let isInferenceBusy = false;

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

export interface SafeErrorEnvelope {
  error: {
    code: 'MODEL_UNAVAILABLE' | 'MODEL_NOT_FOUND' | 'INVALID_INPUT' | 'INVALID_OUTPUT' | 'TIMEOUT' | 'BUSY';
    message: string;
    retryable: boolean;
    requestId: string;
  };
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
  code: SafeErrorEnvelope['error']['code'],
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
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  return token === RUNTIME_TOKEN;
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

    // All /v1/ endpoints require local bearer authentication
    if (!authenticate(req)) {
      return sendError(res, 401, 'INVALID_INPUT', 'Unauthorized: Invalid or missing local bearer token', false, requestId);
    }

    // BriefCheck endpoint
    if (req.method === 'POST' && url.pathname === '/v1/brief-check') {
      if (isInferenceBusy) {
        return sendError(res, 429, 'BUSY', 'Another inference task is currently executing. Bounded to single concurrency.', true, requestId);
      }

      let rawBody: string;
      try {
        rawBody = await readBody(req);
      } catch {
        return sendError(res, 400, 'INVALID_INPUT', 'Failed to read request body', false, requestId);
      }

      let parsedJson: unknown;
      try {
        parsedJson = JSON.parse(rawBody);
      } catch {
        return sendError(res, 400, 'INVALID_INPUT', 'Malformed JSON in request body', false, requestId);
      }

      const validated = BriefCheckInputSchema.safeParse(parsedJson);
      if (!validated.success) {
        return sendError(res, 400, 'INVALID_INPUT', validated.error.message, false, requestId);
      }

      // Check Ollama readiness
      const ollama = await checkOllamaReadiness();
      if (!ollama.available) {
        return sendError(res, 503, 'MODEL_UNAVAILABLE', 'Local Ollama service is not running on 127.0.0.1:11434', true, requestId);
      }
      if (!ollama.modelReady) {
        return sendError(res, 503, 'MODEL_NOT_FOUND', `Required model ${ACTIVE_MODEL_ID} is not pulled in local Ollama`, false, requestId);
      }

      isInferenceBusy = true;
      try {
        const timeoutPromise = new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error('TIMEOUT_EXCEEDED')), INFERENCE_TIMEOUT_MS)
        );
        const result = await Promise.race([runBriefCheck(validated.data), timeoutPromise]);
        return sendJson(res, 200, { requestId, data: result });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === 'TIMEOUT_EXCEEDED') {
          return sendError(res, 504, 'TIMEOUT', 'Inference exceeded maximum timeout of 90 seconds', true, requestId);
        }
        if (msg.includes('INVALID_OUTPUT')) {
          return sendError(res, 502, 'INVALID_OUTPUT', msg, true, requestId);
        }
        return sendError(res, 500, 'MODEL_UNAVAILABLE', `Inference execution failed: ${msg}`, true, requestId);
      } finally {
        isInferenceBusy = false;
      }
    }

    // ScopeCheck endpoint
    if (req.method === 'POST' && url.pathname === '/v1/scope-check') {
      if (isInferenceBusy) {
        return sendError(res, 429, 'BUSY', 'Another inference task is currently executing. Bounded to single concurrency.', true, requestId);
      }

      let rawBody: string;
      try {
        rawBody = await readBody(req);
      } catch {
        return sendError(res, 400, 'INVALID_INPUT', 'Failed to read request body', false, requestId);
      }

      let parsedJson: unknown;
      try {
        parsedJson = JSON.parse(rawBody);
      } catch {
        return sendError(res, 400, 'INVALID_INPUT', 'Malformed JSON in request body', false, requestId);
      }

      const validated = ScopeCheckInputSchema.safeParse(parsedJson);
      if (!validated.success) {
        return sendError(res, 400, 'INVALID_INPUT', validated.error.message, false, requestId);
      }

      const ollama = await checkOllamaReadiness();
      if (!ollama.available) {
        return sendError(res, 503, 'MODEL_UNAVAILABLE', 'Local Ollama service is not running on 127.0.0.1:11434', true, requestId);
      }
      if (!ollama.modelReady) {
        return sendError(res, 503, 'MODEL_NOT_FOUND', `Required model ${ACTIVE_MODEL_ID} is not pulled in local Ollama`, false, requestId);
      }

      isInferenceBusy = true;
      try {
        const timeoutPromise = new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error('TIMEOUT_EXCEEDED')), INFERENCE_TIMEOUT_MS)
        );
        const result = await Promise.race([runScopeCheck(validated.data), timeoutPromise]);
        return sendJson(res, 200, { requestId, data: result });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg === 'TIMEOUT_EXCEEDED') {
          return sendError(res, 504, 'TIMEOUT', 'Inference exceeded maximum timeout of 90 seconds', true, requestId);
        }
        if (msg.includes('INVALID_OUTPUT')) {
          return sendError(res, 502, 'INVALID_OUTPUT', msg, true, requestId);
        }
        return sendError(res, 500, 'MODEL_UNAVAILABLE', `Inference execution failed: ${msg}`, true, requestId);
      } finally {
        isInferenceBusy = false;
      }
    }

    return sendError(res, 404, 'INVALID_INPUT', `Route ${req.method} ${url.pathname} not found`, false, requestId);
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
