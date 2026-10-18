import { createWorkflow, createStep } from '@mastra/core/workflows';
import { Agent } from '@mastra/core/agent';
import { z } from 'zod';
import { getModel } from '../model.js';
import {
  BriefCheckInputSchema,
  BriefCheckOutputSchema,
  normalizeNiche,
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

export const NICHE_CHECKLISTS: Record<'design' | 'writing' | 'general', { guidance: string; items: string[] }> = {
  design: {
    guidance:
      'Analyze as a graphic/brand designer. Focus on visual asset specifications, vector vs raster formats, color hierarchy, typography, dielines for print, and web usage. Check for contradictory artistic/technical constraints.',
    items: [
      'Vector source files (.SVG, .EPS) vs raster assets (.PNG, .JPG)',
      'Color palette codes (Hex, RGB, CMYK, Pantone)',
      'Typography & font licensing specifications',
      'Exact deliverable formats & dimensions (print vs digital)',
      'Printer dieline templates & bleeds (if physical goods)',
      'Explicit revision rounds & feedback limits',
      'Target turnaround deadline & launch schedule',
      'Agreed budget, payment milestones, or deposit',
    ],
  },
  writing: {
    guidance:
      'Analyze as a professional copywriter/content strategist. Focus on editorial requirements, word counts, SEO parameters, source materials, revision allowances, and publishing workflows.',
    items: [
      'Target word count per deliverable',
      'Total number of articles or content pieces',
      'Target audience persona & reader seniority',
      'Brand voice, tone, and editorial style guidelines',
      'SEO target keywords & search intent specifications',
      'Source materials, outlines, or subject-matter expert interviews',
      'Delivery format (Markdown, Google Docs, CMS draft)',
      'Revision rounds & structural proofreading allowance',
      'Publishing cadence, draft deadlines & final delivery',
      'Agreed rate (per-word, per-post, or flat fee)',
    ],
  },
  general: {
    guidance:
      'Analyze as an independent professional service provider. Focus on explicit deliverable definitions, technical constraints, timeline feasibility, and commercial clarity.',
    items: [
      'Clear, non-conflicting deliverable boundaries',
      'Target audience and functional goals',
      'Technical specifications and hosting/platform environment',
      'Asset delivery formats and dependencies',
      'Realistic timeline and intermediate milestones',
      'Explicit commercial terms, pricing, and payment milestones',
      'Revision policy and out-of-scope boundaries',
    ],
  },
};

export const Step1InputSchema = BriefCheckInputSchema;
export const Step1OutputSchema = z.object({
  requestId: z.string().optional(),
  brief: z.string(),
  niche: z.enum(['design', 'writing', 'general']),
});

export const validateInputStep = createStep({
  id: 'validate-input',
  inputSchema: Step1InputSchema,
  outputSchema: Step1OutputSchema,
  execute: async ({ inputData }) => {
    const brief = (inputData.brief ?? '').trim();
    if (!brief || brief.length < 1 || brief.length > 8000) {
      throw new Error('INVALID_INPUT: Brief text must be between 1 and 8000 characters');
    }
    return {
      requestId: inputData.requestId,
      brief,
      niche: normalizeNiche(inputData.niche),
    };
  },
});

export const Step2InputSchema = Step1OutputSchema;
export const Step2OutputSchema = z.object({
  requestId: z.string().optional(),
  brief: z.string(),
  niche: z.enum(['design', 'writing', 'general']),
  checklist: z.array(z.string()),
  nicheGuidance: z.string(),
});

export const selectNicheChecklistStep = createStep({
  id: 'select-niche-checklist',
  inputSchema: Step2InputSchema,
  outputSchema: Step2OutputSchema,
  execute: async ({ inputData }) => {
    const nicheConfig = NICHE_CHECKLISTS[inputData.niche] ?? NICHE_CHECKLISTS.general;
    return {
      requestId: inputData.requestId,
      brief: inputData.brief,
      niche: inputData.niche,
      checklist: nicheConfig.items,
      nicheGuidance: nicheConfig.guidance,
    };
  },
});

export const Step3InputSchema = Step2OutputSchema;
export const Step3OutputSchema = z.object({
  requestId: z.string().optional(),
  niche: z.enum(['design', 'writing', 'general']),
  rawOutput: z.string(),
});

export const analyzeWithAgentStep = createStep({
  id: 'analyze-with-agent',
  inputSchema: Step3InputSchema,
  outputSchema: Step3OutputSchema,
  execute: async ({ inputData }) => {
    const { brief, niche, checklist, nicheGuidance } = inputData;

    const agent = new Agent({
      id: 'brief-analyzer',
      name: 'BriefAnalyzer',
      instructions: `You are SoloDesk's BriefCheck assistant for independent freelancers.
Your goal is to parse client project briefs with strict adherence to facts.
CRITICAL RULES:
1. Distinguish explicit requirements from assumptions and omitted details.
2. If deadline, delivery formats, scope boundaries, budget/pricing, or quantities are not stated, DO NOT INVENT THEM. Explicitly flag them in "omissions".
3. If requirements contradict each other (e.g. conflicting timelines, aesthetic paradoxes, or zero budget with commercial buyouts), explicitly flag the contradiction in "omissions" and generate targeted clarifying questions.
4. Formulate targeted questions for the client in "suggestedQuestions".
5. Produce starter scope items in "starterScopeItems" that quote or strictly derive from the text.
6. Keep each bullet point concise (under 20 words).
7. Output ONLY a valid JSON object matching the requested schema. No conversational filler, no markdown codeblocks, no explanations, no <think> tags.`,
      model: getModel(),
    });

    const checklistFormatted = checklist.map(c => `- ${c}`).join('\n');
    const prompt = `Analyze this ${niche} brief using the domain checklist below.
Domain Guidance: ${nicheGuidance}

Checklist reference points to evaluate:
${checklistFormatted}

Client Brief:
"""
${brief}
"""

Return strictly a valid JSON object starting with { and ending with }. Keep entries concise. Do NOT include <think> tags or reasoning text:
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
    let rawOutput = res.text ?? '';

    // If unparseable, execute 1 repair pass
    try {
      extractJsonFromText(rawOutput);
    } catch {
      try {
        const repairRes = await agent.generate(
          `The previous output was not valid JSON. Convert the following into strictly valid JSON without comments or markdown:\n${rawOutput}`
        );
        rawOutput = repairRes.text ?? '{}';
        extractJsonFromText(rawOutput);
      } catch (repairErr) {
        throw new Error(
          `INVALID_OUTPUT: BriefCheck model output could not be parsed as JSON after 1 repair attempt: ${
            repairErr instanceof Error ? repairErr.message : String(repairErr)
          }`
        );
      }
    }

    return {
      requestId: inputData.requestId,
      niche: inputData.niche,
      rawOutput,
    };
  },
});

export const Step4InputSchema = Step3OutputSchema;
export const Step4OutputSchema = BriefCheckOutputSchema;

export const validateOutputStep = createStep({
  id: 'validate-output',
  inputSchema: Step4InputSchema,
  outputSchema: Step4OutputSchema,
  execute: async ({ inputData }) => {
    let parsed: unknown;
    try {
      parsed = extractJsonFromText(inputData.rawOutput);
    } catch (err) {
      throw new Error(
        `INVALID_OUTPUT: Could not extract valid JSON from model output: ${
          err instanceof Error ? err.message : String(err)
        }`
      );
    }

    const normalized = normalizeBriefOutput(parsed);
    const validated = BriefCheckOutputSchema.safeParse(normalized);
    if (!validated.success) {
      throw new Error(`INVALID_OUTPUT: BriefCheck schema validation failed: ${validated.error.message}`);
    }

    return validated.data;
  },
});

export const Step5InputSchema = Step4OutputSchema;
export const Step5OutputSchema = BriefCheckOutputSchema;

export const returnDraftStep = createStep({
  id: 'return-draft',
  inputSchema: Step5InputSchema,
  outputSchema: Step5OutputSchema,
  execute: async ({ inputData }) => {
    return Object.freeze({
      statedRequirements: [...inputData.statedRequirements],
      assumptions: [...inputData.assumptions],
      omissions: [...inputData.omissions],
      suggestedQuestions: [...inputData.suggestedQuestions],
      starterScopeItems: inputData.starterScopeItems.map(item => ({ ...item })),
    });
  },
});

export const briefCheckWorkflow = createWorkflow({
  id: 'brief-check-workflow',
  inputSchema: BriefCheckInputSchema,
  outputSchema: BriefCheckOutputSchema,
})
  .then(validateInputStep)
  .then(selectNicheChecklistStep)
  .then(analyzeWithAgentStep)
  .then(validateOutputStep)
  .then(returnDraftStep)
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
