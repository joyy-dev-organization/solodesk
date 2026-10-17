import { createOllama } from 'ollama-ai-provider-v2';

export const OLLAMA_HOST = '127.0.0.1';
export const OLLAMA_PORT = 11434;
export const OLLAMA_BASE_URL = `http://${OLLAMA_HOST}:${OLLAMA_PORT}/api`;

export const CANDIDATE_MODEL_4B = 'qwen3:4b';
export const CANDIDATE_MODEL_1_7B = 'qwen3:1.7b';
// Selected active model: qwen3:1.7b (chosen after empirical hardware latency benchmarking)
export const ACTIVE_MODEL_ID = CANDIDATE_MODEL_1_7B;

export const ollamaProvider = createOllama({
  baseURL: OLLAMA_BASE_URL,
});

/**
 * Returns the configured LanguageModel instance with deterministic bounded options and think: false.
 */
export function getModel(modelId = ACTIVE_MODEL_ID) {
  return ollamaProvider.chat(modelId as any, {
    think: false,
    options: {
      num_ctx: 2048,
      num_predict: 384,
      temperature: 0.1,
    },
  });
}

export interface OllamaReadiness {
  available: boolean;
  modelReady: boolean;
  modelsFound: string[];
  error?: string;
}

/**
 * Probes the local Ollama loopback server to verify service availability and loaded models.
 */
export async function checkOllamaReadiness(targetModel = ACTIVE_MODEL_ID): Promise<OllamaReadiness> {
  try {
    const res = await fetch(`http://${OLLAMA_HOST}:${OLLAMA_PORT}/api/tags`, {
      method: 'GET',
      headers: { 'Accept': 'application/json' },
    });

    if (!res.ok) {
      return {
        available: false,
        modelReady: false,
        modelsFound: [],
        error: `Ollama returned HTTP ${res.status}`,
      };
    }

    const data = await res.json() as { models?: Array<{ name: string }> };
    const modelsFound = (data.models ?? []).map(m => m.name);
    const modelReady = modelsFound.some(name => name.startsWith(targetModel) || targetModel.startsWith(name));

    return {
      available: true,
      modelReady,
      modelsFound,
    };
  } catch (err) {
    return {
      available: false,
      modelReady: false,
      modelsFound: [],
      error: err instanceof Error ? err.message : String(err),
    };
  }
}
