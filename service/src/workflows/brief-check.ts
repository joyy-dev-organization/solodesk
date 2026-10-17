import { createWorkflow, createStep } from '@mastra/core/workflows';
import { Agent } from '@mastra/core/agent';
import { getModel } from '../model.js';
import {
  BriefCheckInputSchema,
  BriefCheckOutputSchema,
  type BriefCheckInput,
  type BriefCheckOutput,
} from '../schemas/brief-check.schema.js';

export function extractJsonFromText(rawText: string): unknown {
  let cleaned = rawText.trim();

  // Strip think blocks if present
  cleaned = cleaned.replace(/<think>[\s\S]*?<\/think>/gi, '').trim();

  // Strip markdown code fences if present
  const jsonMatch = cleaned.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  if (jsonMatch?.[1]) {
    cleaned = jsonMatch[1].trim();
  } else {
    // Attempt to locate outermost JSON object braces
    const firstBrace = cleaned.indexOf('{');
    const lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
      cleaned = cleaned.slice(firstBrace, lastBrace + 1);
    }
  }

  return JSON.parse(cleaned);
}

export function normalizeBriefOutput(raw: any): unknown {
  if (!raw || typeof raw !== 'object') return raw;

  const ensureStringArray = (arr: unknown): string[] => {
    if (!Array.isArray(arr)) return [];
    return arr
      .map(item => {
        if (typeof item === 'string') return item.trim();
        if (item && typeof item === 'object') {
          return (item.title || item.name || item.text || JSON.stringify(item)).trim();
        }
        return String(item).trim();
      })
      .filter(Boolean);
  };

  const ensureScopeItems = (arr: unknown): Array<{ title: string; description: string }> => {
    if (!Array.isArray(arr)) return [];
    return arr
      .map(item => {
        if (typeof item === 'string') {
          const trimmed = item.trim();
          return { title: trimmed, description: trimmed };
        }
        if (item && typeof item === 'object') {
          const title = (item.title || item.name || 'Deliverable').trim();
          const description = (item.description || item.details || title).trim();
          return { title, description };
        }
        const s = String(item).trim();
        return { title: 'Deliverable', description: s };
      })
      .filter(i => i.title.length > 0);
  };

  return {
    statedRequirements: ensureStringArray(raw.statedRequirements ?? raw.requirements),
    assumptions: ensureStringArray(raw.assumptions),
    omissions: ensureStringArray(raw.omissions ?? raw.missingDetails),
    suggestedQuestions: ensureStringArray(raw.suggestedQuestions ?? raw.questions),
    starterScopeItems: ensureScopeItems(raw.starterScopeItems ?? raw.scopeItems ?? raw.deliverables),
  };
}

export const analyzeBriefStep = createStep({
  id: 'analyze-brief-step',
  inputSchema: BriefCheckInputSchema,
  outputSchema: BriefCheckOutputSchema,
  execute: async ({ inputData }: { inputData: BriefCheckInput }) => {
    const { brief, niche } = inputData;

    const agent = new Agent({
      id: 'brief-analyzer',
      name: 'BriefAnalyzer',
      instructions: `You are SoloDesk's BriefCheck assistant for independent freelancers.
Your goal is to parse client project briefs with strict adherence to facts.
CRITICAL RULES:
1. Distinguish explicit requirements from assumptions and omitted details.
2. If deadline, delivery formats, scope boundaries, or quantities are not stated, DO NOT INVENT THEM. Explicitly flag them in "omissions".
3. Formulate targeted questions for the client in "suggestedQuestions".
4. Produce starter scope items in "starterScopeItems" that quote or strictly derive from the text.
5. Output ONLY a valid JSON object matching the requested schema. No conversational filler, no markdown codeblocks, no explanations.`,
      model: getModel(),
    });

    const prompt = `Analyze this ${niche} brief:
"""
${brief}
"""

Return ONLY a JSON object with this exact shape:
{
  "statedRequirements": ["item 1", "item 2"],
  "assumptions": ["assumption 1"],
  "omissions": ["omission 1"],
  "suggestedQuestions": ["question 1"],
  "starterScopeItems": [
    { "title": "deliverable title", "description": "deliverable description" }
  ]
}`;

    const res = await agent.generate(prompt);
    const rawOutput = res.text ?? '';

    let parsed: unknown;
    try {
      parsed = extractJsonFromText(rawOutput);
    } catch {
      // 1 single repair pass allowed by handbook protocol
      const repairRes = await agent.generate(`The previous output was not valid JSON. Convert the following into strictly valid JSON without comments or extra text:\n${rawOutput}`);
      parsed = extractJsonFromText(repairRes.text ?? '{}');
    }

    const normalized = normalizeBriefOutput(parsed);
    const validated = BriefCheckOutputSchema.safeParse(normalized);
    if (!validated.success) {
      throw new Error(`INVALID_OUTPUT: BriefCheck schema validation failed: ${validated.error.message}`);
    }

    return validated.data;
  },
});

export const briefCheckWorkflow = createWorkflow({
  id: 'brief-check-workflow',
  inputSchema: BriefCheckInputSchema,
  outputSchema: BriefCheckOutputSchema,
})
  .then(analyzeBriefStep)
  .commit();

export async function runBriefCheck(input: BriefCheckInput): Promise<BriefCheckOutput> {
  const validatedInput = BriefCheckInputSchema.parse(input);
  const run = await briefCheckWorkflow.createRun();
  const result = await run.start({ inputData: validatedInput });

  if (result.status === 'success') {
    return result.result as BriefCheckOutput;
  }

  const failedResult = result as { error?: { message?: string } };
  const errMessage = failedResult.error?.message || 'Workflow run failed';
  throw new Error(errMessage);
}
