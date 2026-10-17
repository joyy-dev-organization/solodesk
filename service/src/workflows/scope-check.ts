import { createWorkflow, createStep } from '@mastra/core/workflows';
import { Agent } from '@mastra/core/agent';
import { getModel } from '../model.js';
import {
  ScopeCheckInputSchema,
  ScopeCheckOutputSchema,
  type ScopeCheckInput,
  type ScopeCheckOutput,
  type ScopeFinding,
  type FindingCategory,
} from '../schemas/scope-check.schema.js';
import { extractJsonFromText } from './brief-check.js';

/**
 * Normalizes model classification strings to standard FindingCategory
 */
export function normalizeCategory(val: unknown): FindingCategory {
  if (typeof val !== 'string') return 'needs_clarification';
  const lower = val.toLowerCase().trim();
  if (lower.includes('include') || lower === 'in_scope' || lower === 'in-scope') {
    return 'included';
  }
  if (
    lower.includes('outside') ||
    lower.includes('out_of_scope') ||
    lower.includes('out-of-scope') ||
    lower.includes('extra') ||
    lower.includes('excluded')
  ) {
    return 'out_of_scope';
  }
  if (lower.includes('clarif') || lower.includes('ambiguous') || lower.includes('unclear')) {
    return 'needs_clarification';
  }
  return 'needs_clarification';
}

/**
 * Defensive normalizer for small LLM outputs (e.g. qwen3:1.7b)
 */
export function normalizeScopeOutput(raw: any, scopeItems: ScopeCheckInput['scopeItems']): ScopeCheckOutput {
  if (!raw || typeof raw !== 'object') {
    throw new Error('INVALID_OUTPUT: ScopeCheck model produced non-object output');
  }

  const rawFindings = Array.isArray(raw.findings)
    ? raw.findings
    : Array.isArray(raw.evaluations)
    ? raw.evaluations
    : Array.isArray(raw.items)
    ? raw.items
    : [];

  const findings: ScopeFinding[] = rawFindings.map((item: any) => {
    const rawCat = item.category ?? item.classification ?? item.status;
    let category = normalizeCategory(rawCat);

    const requestExcerpt = (
      item.requestExcerpt ??
      item.excerpt ??
      item.request_excerpt ??
      item.quote ??
      item.text ??
      'Client request item'
    ).trim();

    let matchedScopeItemId: string | null = null;
    const rawMatchedId = item.matchedScopeItemId ?? item.matched_scope_item_id ?? item.scopeItemId;
    if (rawMatchedId && typeof rawMatchedId === 'string') {
      const trimmed = rawMatchedId.trim();
      if (trimmed && !['none', 'null', 'n/a', 'undefined', ''].includes(trimmed.toLowerCase())) {
        matchedScopeItemId = trimmed;
      }
    }

    let matchedScopeItemDescription: string | null = null;
    const rawMatchedDesc = item.matchedScopeItemDescription ?? item.matched_scope_item_description ?? item.scopeItemDescription;
    if (rawMatchedDesc && typeof rawMatchedDesc === 'string') {
      const trimmed = rawMatchedDesc.trim();
      if (trimmed && !['none', 'null', 'n/a', ''].includes(trimmed.toLowerCase())) {
        matchedScopeItemDescription = trimmed;
      }
    }

    // Auto-populate matched description from input scopeItems if ID matched but description missing
    if (matchedScopeItemId && !matchedScopeItemDescription) {
      const found = scopeItems.find(si => si.id === matchedScopeItemId);
      if (found) {
        matchedScopeItemDescription = found.description;
      }
    }

    // Defensive check: if model matched a scope item that permits revisions/allowances, or request specifies an agreed revision round,
    // ensure it is categorized as 'included' rather than 'needs_clarification'
    if (category === 'needs_clarification' && matchedScopeItemId) {
      const matched = scopeItems.find(si => si.id === matchedScopeItemId);
      if (matched && (matched.category === 'allowance' || matched.description.toLowerCase().includes('revision') || matched.description.toLowerCase().includes('adjustment'))) {
        const text = `${requestExcerpt} ${item.explanation ?? ''}`.toLowerCase();
        if ((text.includes('revision') || text.includes('round') || text.includes('tweak') || text.includes('change') || text.includes('adjust')) && !text.includes('pop')) {
          category = 'included';
        }
      }
    }

    if (!matchedScopeItemId && !matchedScopeItemDescription) {
      matchedScopeItemDescription = 'No matching scope deliverable found in approved agreement';
    }

    const explanation = (
      item.explanation ??
      item.rationale ??
      item.reason ??
      item.details ??
      `Item evaluated as ${category}`
    ).trim();

    // Mapping legacy classification uppercase
    const classification = category === 'included'
      ? 'INCLUDED'
      : category === 'out_of_scope'
      ? 'POTENTIALLY_OUTSIDE'
      : 'NEEDS_CLARIFICATION';

    return {
      category,
      classification,
      requestExcerpt,
      matchedScopeItemId,
      matchedScopeItemDescription,
      explanation,
      rationale: explanation,
    };
  });

  const replyDraft = (
    raw.replyDraft ??
    raw.reply_draft ??
    raw.suggestedReply ??
    raw.suggested_reply ??
    raw.reply ??
    'Thank you for your message. I have reviewed your request against our current project scope.'
  ).trim();

  let summary = (raw.summary ?? raw.overview ?? '').trim();
  if (!summary) {
    const inc = findings.filter(f => f.category === 'included').length;
    const out = findings.filter(f => f.category === 'out_of_scope').length;
    const clar = findings.filter(f => f.category === 'needs_clarification').length;
    summary = `Analyzed ${findings.length} request item(s): ${inc} included, ${out} out of scope, ${clar} needs clarification.`;
  }

  return {
    findings,
    evaluations: findings,
    replyDraft,
    suggestedReply: replyDraft,
    summary,
  };
}

export const evaluateScopeStep = createStep({
  id: 'evaluate-scope-step',
  inputSchema: ScopeCheckInputSchema,
  outputSchema: ScopeCheckOutputSchema,
  execute: async ({ inputData }: { inputData: ScopeCheckInput }) => {
    const { requestText, scopeItems, niche } = inputData;

    const formattedScope = scopeItems
      .map(item => `[${item.id}] (${item.category.toUpperCase()}): ${item.description}`)
      .join('\n');

    const agent = new Agent({
      id: 'scope-shield-analyzer',
      name: 'ScopeShieldAgent',
      instructions: `You are SoloDesk's ScopeShield assistant for independent freelancers (${niche} niche).
Your mission: Compare incoming client request text against agreed scope items and revision allowances.
CRITICAL RULES:
1. Categorize each discrete client request item into EXACTLY ONE category:
   - "included": Covered by an agreed baseline deliverable or within an agreed revision allowance (such as color tweaks, typographic adjustments, subheader/text edits, or minor revisions within agreed rounds).
   - "out_of_scope": Extra deliverable, new feature, or explicitly listed exclusion (e.g. building new apps, unagreed pages, new platform integration).
   - "needs_clarification": Truly vague, subjective, or abstract requests lacking actionable details (e.g. "make it pop", "add energy", "feel premium").
2. Specific revisions to existing deliverables within agreed rounds (e.g. color adjustments, font changes, headline updates) MUST be categorized as "included". Do NOT classify specific revisions as "needs_clarification".
3. For mixed requests: If the client asks for multiple things (e.g. an included revision AND a new deliverable), provide separate finding items for each part so each is evaluated independently.
4. NEVER make legal conclusions, claim contract breaches, or calculate fees/prices.
5. If a request item matches an agreed scope item or revision allowance, set "matchedScopeItemId" to that item ID. If no scope item matches, set "matchedScopeItemId" to null and "matchedScopeItemDescription" to "No matching scope deliverable found in approved agreement".
6. Write a courteous, professional, editable reply draft for the freelancer.
7. Output ONLY a valid JSON object matching the requested schema. No conversational preamble, no markdown fences.`,
      model: getModel(),
    });

    const prompt = `APPROVED SCOPE ITEMS:
${formattedScope}

NEW CLIENT REQUEST:
"""
${requestText}
"""

Instructions:
- Categorize specific revisions/adjustments within agreed rounds as "included".
- Categorize extra deliverables or new development as "out_of_scope".
- Only categorize abstract/subjective requests without concrete specifications as "needs_clarification".
- If the request contains both a revision and a new deliverable, create separate items in "findings" for each part.

Return ONLY a JSON object with this exact structure:
{
  "summary": "1-sentence summary of request scope status",
  "findings": [
    {
      "category": "included | out_of_scope | needs_clarification",
      "requestExcerpt": "short quote from client request",
      "matchedScopeItemId": "item-id or null",
      "matchedScopeItemDescription": "deliverable description or No matching scope deliverable found in approved agreement",
      "explanation": "1-sentence rationale comparing request against agreed scope"
    }
  ],
  "replyDraft": "2-3 sentence polite, editable response draft acknowledging included work and clarifying extra items"
}`;

    const res = await agent.generate(prompt);
    const rawOutput = res.text ?? '';

    let parsed: unknown;
    try {
      parsed = extractJsonFromText(rawOutput);
    } catch {
      // 1 single repair pass allowed by handbook protocol
      try {
        const repairRes = await agent.generate(
          `The previous output was not valid JSON. Convert the following text into strictly valid JSON without comments or markdown:\n${rawOutput}`
        );
        parsed = extractJsonFromText(repairRes.text ?? '{}');
      } catch (repairErr) {
        throw new Error(`INVALID_OUTPUT: ScopeCheck model output could not be parsed as JSON after 1 repair attempt: ${repairErr instanceof Error ? repairErr.message : String(repairErr)}`);
      }
    }

    const normalized = normalizeScopeOutput(parsed, scopeItems);
    const validated = ScopeCheckOutputSchema.safeParse(normalized);
    if (!validated.success) {
      throw new Error(`INVALID_OUTPUT: ScopeCheck schema validation failed: ${validated.error.message}`);
    }

    return validated.data;
  },
});

export const scopeCheckWorkflow = createWorkflow({
  id: 'scope-check-workflow',
  inputSchema: ScopeCheckInputSchema,
  outputSchema: ScopeCheckOutputSchema,
})
  .then(evaluateScopeStep)
  .commit();

export async function runScopeCheck(input: ScopeCheckInput): Promise<ScopeCheckOutput> {
  const validatedInput = ScopeCheckInputSchema.parse(input);
  const run = await scopeCheckWorkflow.createRun();
  const result = await run.start({ inputData: validatedInput });

  if (result.status === 'success') {
    return result.result as ScopeCheckOutput;
  }

  const failedResult = result as { error?: { message?: string } };
  const errMessage = failedResult.error?.message || 'Workflow run failed';
  throw new Error(errMessage);
}
