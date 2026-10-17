import { createWorkflow, createStep } from '@mastra/core/workflows';
import { Agent } from '@mastra/core/agent';
import { getModel } from '../model.js';
import {
  ScopeCheckInputSchema,
  ScopeCheckOutputSchema,
  type ScopeCheckInput,
  type ScopeCheckOutput,
} from '../schemas/scope-check.schema.js';
import { extractJsonFromText } from './brief-check.js';

export const evaluateScopeStep = createStep({
  id: 'evaluate-scope-step',
  inputSchema: ScopeCheckInputSchema,
  outputSchema: ScopeCheckOutputSchema,
  execute: async ({ inputData }: { inputData: ScopeCheckInput }) => {
    const { requestText, scopeItems } = inputData;

    const formattedScope = scopeItems
      .map(item => `- [${item.id}] ${item.title}: ${item.description}`)
      .join('\n');

    const agent = new Agent({
      id: 'scope-shield-analyzer',
      name: 'ScopeShieldAgent',
      instructions: `You are SoloDesk's ScopeShield assistant for independent freelancers.
Your goal is to compare a client request against an approved scope agreement.
CRITICAL RULES:
1. Classify each requested item into one of three values:
   - "INCLUDED": Clearly covered by an existing scope deliverable or within an agreed revision limit.
   - "POTENTIALLY_OUTSIDE": A new feature, extra deliverable, or excluded item not in approved scope.
   - "NEEDS_CLARIFICATION": Ambiguous, vague, or missing details making determination uncertain.
2. DO NOT make legal enforceability determinations or calculate extra billing amounts.
3. A normal revision within an agreed deliverable must NOT automatically be labelled outside scope.
4. Draft a polite, clear, editable response for the freelancer. Never auto-send.
5. Output ONLY a valid JSON object matching the requested schema. No conversational filler, no markdown codeblocks, no explanations.`,
      model: getModel(),
    });

    const prompt = `APPROVED SCOPE:
${formattedScope}

NEW CLIENT REQUEST:
"""
${requestText}
"""

Return ONLY a JSON object with this exact shape:
{
  "evaluations": [
    {
      "requestExcerpt": "relevant quote from client request",
      "classification": "INCLUDED | POTENTIALLY_OUTSIDE | NEEDS_CLARIFICATION",
      "rationale": "specific comparison rationale against approved items",
      "matchedScopeItemId": "item id if applicable or null"
    }
  ],
  "suggestedReply": "polite, professional response acknowledging what is underway and clarifying extra requests"
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

    const validated = ScopeCheckOutputSchema.safeParse(parsed);
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

