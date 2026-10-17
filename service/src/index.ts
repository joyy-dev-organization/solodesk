/**
 * SoloDesk local TypeScript/Mastra service
 * Loopback-only service orchestrating BriefCheck and ScopeShield
 */

import { startServer, PORT, HOST, getOrCreateRuntimeToken } from './server.js';

export * from './model.js';
export * from './server.js';
export * from './schemas/brief-check.schema.js';
export * from './schemas/scope-check.schema.js';
export * from './schemas/invoice-reminder.schema.js';
export * from './workflows/brief-check.js';
export * from './workflows/scope-check.js';
export * from './workflows/invoice-reminder.js';

// Auto-start if run directly
if (process.argv[1]?.endsWith('index.js') || process.argv[1]?.endsWith('index.ts')) {
  const token = getOrCreateRuntimeToken();
  console.log(`[SoloDesk] Initializing local service...`);
  console.log(`[SoloDesk] Auth Token written to .runtime-token (Length: ${token.length})`);
  startServer(PORT, HOST).catch(err => {
    console.error(`[SoloDesk] Failed to start service:`, err);
    process.exit(1);
  });
}
