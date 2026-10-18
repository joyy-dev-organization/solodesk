import { createWorkflow, createStep } from '@mastra/core/workflows';
import { Agent } from '@mastra/core/agent';
import { getModel } from '../model.js';
import {
  OfferDraftInputSchema,
  OfferDraftOutputSchema,
  OfferFactsEnrichedSchema,
  OfferPreparedPromptSchema,
  OfferAgentRawOutputSchema,
  type OfferDraftInput,
  type OfferDraftOutput,
  type OfferFactsEnriched,
  type OfferPreparedPrompt,
  type OfferAgentRawOutput,
} from '../schemas/offer-draft.schema.js';
import { extractJsonFromText } from './brief-check.js';

export const PROHIBITED_FABRICATION_KEYWORDS = [
  'contract signed',
  'contract has been signed',
  'agreement signed',
  'agreement has been signed',
  'you have renewed',
  'you renewed',
  'thank you for renewing',
  'thanks for renewing',
  'renewal is confirmed',
  'renewal has been confirmed',
  'payment was processed',
  'payment has been processed',
  'payment received',
  'card was charged',
  'card has been charged',
  'deposit charged',
  'late fee',
  'late payment penalty',
  'penalty',
  'interest',
  'surcharge',
  'legal action',
  'litigation',
  'binding arbitration',
];

/**
 * Normalizes model output defensively, enforcing strict factual grounding
 * and eliminating any fabricated claims of client acceptance or signed renewals.
 */
export function normalizeOfferDraftOutput(raw: any, input: OfferFactsEnriched | OfferDraftInput): OfferDraftOutput {
  let offerText = (
    raw?.offerText ??
    raw?.offerDraft ??
    raw?.draft ??
    raw?.proposalDraft ??
    raw?.proposal ??
    raw?.message ??
    ''
  ).trim();

  // Fallback template if model produced empty output
  if (!offerText) {
    const deliverablesList = input.deliverables.map((d: string) => `• ${d}`).join('\n');
    const exclusionsList = input.exclusions.length > 0
      ? input.exclusions.map((e: string) => `• ${e}`).join('\n')
      : '• Custom requests outside the agreed deliverables list are quoted separately.';

    if (input.isRenewal) {
      offerText = `Hi ${input.clientName},\n\nI've loved collaborating with you on our recent work and would be thrilled to continue supporting you with our ongoing ${input.planTitle}.\n\n### Agreed Deliverables:\n${deliverablesList}\n\n### Package Scope & Limits:\n• Revision limits: ${input.revisionLimits}\n• Out-of-scope items:\n${exclusionsList}\n\n### Retainer Terms:\n• Investment: ${input.priceFormatted} (${input.cadence})\n\nBefore we begin the next cycle, let's confirm your upcoming priorities and ensure this package continues to align with your goals. Would you like to proceed with this retainer for the next period?\n\nBest regards,`;
    } else {
      offerText = `Hi ${input.clientName},\n\nFollowing our discussion regarding ${input.serviceNiche.toLowerCase()}, I'd like to propose a recurring ${input.planTitle} tailored to your ongoing needs.\n\n### Included Deliverables:\n${deliverablesList}\n\n### Package Scope & Limits:\n• Revision limits: ${input.revisionLimits}\n• Out-of-scope items:\n${exclusionsList}\n\n### Proposed Package Fee:\n• Investment: ${input.priceFormatted} (${input.cadence})\n\nThis predictable arrangement ensures dedicated availability and consistent turnaround. Please take a look at the proposed deliverables and terms, and let me know if you would like to discuss or adjust any details before we begin.\n\nBest regards,`;
    }
  }

  // Guard against fabrication of client acceptance, signed contracts, or unagreed fees
  const lines = offerText.split('\n');
  const cleanLines = lines.map((line: string) => {
    const sentences = line.split(/(?<=[.!?])\s+/);
    const cleanSentences = sentences.filter((sentence: string) => {
      const s = sentence.toLowerCase();
      for (const forbidden of PROHIBITED_FABRICATION_KEYWORDS) {
        if (s.includes(forbidden)) {
          return false;
        }
      }
      return true;
    });
    return cleanSentences.join(' ');
  }).filter((l: string) => l.trim().length > 0);

  offerText = cleanLines.join('\n\n').trim();

  // HARD ENFORCEMENT OF FACTUAL INVARIANTS:
  // 1. Client Name Greeting
  if (!offerText.toLowerCase().includes(input.clientName.toLowerCase())) {
    offerText = `Hi ${input.clientName},\n\n${offerText}`;
  }

  // 2. Exact Formatted Price and Cadence preservation
  const cleanTargetPrice = input.priceFormatted.replace(/\s+/g, '').toLowerCase();
  const cleanOutput = offerText.replace(/\s+/g, '').toLowerCase();
  const pricePreserved = cleanOutput.includes(cleanTargetPrice);
  const cadencePreserved = cleanOutput.includes(input.cadence.toLowerCase()) || cleanOutput.includes('month');
  const revisionLimitsPreserved = cleanOutput.includes(input.revisionLimits.toLowerCase()) || cleanOutput.includes('revision');

  // If critical terms were dropped by a small model, append structured terms block
  if (!pricePreserved || !cadencePreserved || !revisionLimitsPreserved) {
    offerText += `\n\n### Proposed Plan Terms\n- Proposed Fee: ${input.priceFormatted} (${input.cadence})\n- Revision Limit: ${input.revisionLimits}\n- Scope Boundary: Deliverables outside this package are estimated separately.`;
  }

  // Construct summaries
  let deliverablesSummary = (raw?.deliverablesSummary ?? raw?.deliverablesOverview ?? '').trim();
  if (!deliverablesSummary) {
    deliverablesSummary = input.deliverables.join('; ');
  }

  let termsSummary = (raw?.termsSummary ?? raw?.termsOverview ?? '').trim();
  if (!termsSummary) {
    termsSummary = `${input.priceFormatted} (${input.cadence}); ${input.revisionLimits}`;
    if (input.exclusions.length > 0) {
      termsSummary += `; Excludes: ${input.exclusions.join(', ')}`;
    }
  }

  return {
    offerText,
    deliverablesSummary,
    termsSummary,
    factPreservation: {
      pricePreserved: true,
      cadencePreserved: true,
      revisionLimitsPreserved: true,
    },
    draft: offerText,
    proposalDraft: offerText,
  };
}

// ----------------------------------------------------------------------------
// STEP 1: Fact Validation Step
// ----------------------------------------------------------------------------
export const validateOfferFactsStep = createStep({
  id: 'validate-offer-facts',
  inputSchema: OfferDraftInputSchema,
  outputSchema: OfferFactsEnrichedSchema,
  execute: async ({ inputData }: { inputData: OfferDraftInput }): Promise<OfferFactsEnriched> => {
    if (!inputData.deliverables || inputData.deliverables.length === 0) {
      throw new Error('INVALID_INPUT: Service plan must have at least one deliverable.');
    }

    const relationshipContext = inputData.isRenewal
      ? 'Continuing collaboration / renewal proposal following completed milestones'
      : 'New recurring service agreement / retainer proposal';

    return {
      clientName: inputData.clientName,
      serviceNiche: inputData.serviceNiche,
      planTitle: inputData.planTitle,
      deliverables: inputData.deliverables,
      exclusions: inputData.exclusions,
      revisionLimits: inputData.revisionLimits,
      priceFormatted: inputData.priceFormatted,
      currency: inputData.currency,
      cadence: inputData.cadence,
      tone: inputData.tone,
      isRenewal: inputData.isRenewal,
      relationshipContext,
      optionalNotes: inputData.optionalNotes,
    };
  },
});

// ----------------------------------------------------------------------------
// STEP 2: Prepare Prompt Step
// ----------------------------------------------------------------------------
export const prepareOfferPromptStep = createStep({
  id: 'prepare-offer-prompt',
  inputSchema: OfferFactsEnrichedSchema,
  outputSchema: OfferPreparedPromptSchema,
  execute: async ({ inputData }: { inputData: OfferFactsEnriched }): Promise<OfferPreparedPrompt> => {
    const {
      clientName,
      serviceNiche,
      planTitle,
      deliverables,
      exclusions,
      revisionLimits,
      priceFormatted,
      cadence,
      tone,
      isRenewal,
      relationshipContext,
      optionalNotes,
    } = inputData;

    const deliverablesFormatted = deliverables.map(d => `  * ${d}`).join('\n');
    const exclusionsFormatted = exclusions.length > 0
      ? exclusions.map(e => `  * ${e}`).join('\n')
      : '  * None explicitly specified (all work outside deliverables quoted separately)';

    const systemInstructions = `You are SoloDesk's Repeat Work proposal assistant for independent freelancers.
Your role: Draft an editable, clear, professional recurring service proposal or renewal invitation grounded strictly in verified plan facts.

CRITICAL BOUNDARY RULES:
1. STRICT FACTUAL GROUNDING: You must use the exact client name "${clientName}", plan title "${planTitle}", formatted fee "${priceFormatted}", and cadence "${cadence}".
2. ZERO ACCEPTANCE / RENEWAL FABRICATION (NON-NEGOTIABLE):
   - You must NEVER claim, state, or imply that the client has already signed, agreed, accepted, or renewed this plan.
   - Even when isRenewal is true, the text must present this strictly as an INVITATION or PROPOSAL to continue working together for a new period.
   - Prohibited phrasing: "Thank you for renewing", "As we agreed in our contract", "Under our signed agreement", "Your card was charged", "Your renewal is confirmed".
   - Approved phrasing: "I would love to propose continuing our partnership...", "Here is a proposed ongoing retainer for our next cycle...", "Let me know if this plan and cadence align with your upcoming goals...".
3. CLEAR SCOPE BOUNDARIES:
   - Accurately list the deliverables:
${deliverablesFormatted}
   - Accurately list the revision limits: "${revisionLimits}".
   - Explicitly highlight that work outside these deliverables will be quoted separately.
4. TONE GUIDELINES:
   - "collaborative": Warm, relationship-focused, client-centered partnership.
   - "professional": Clear, direct, structured, and polished commercial terms.
   - "value_focused": Strategic, outcome-oriented, emphasizing peace of mind and consistency.
5. NO INVENTED COMMERCIAL TERMS: Never invent lock-in contracts, cancellation penalties, interest, setup fees, or unmentioned discounts.
6. OUTPUT FORMAT: Output ONLY a valid JSON object matching the requested schema. No conversational preamble, no markdown fences.`;

    const userPrompt = `<plan_facts>
- Client Name: ${clientName}
- Service Niche: ${serviceNiche}
- Plan Title: ${planTitle}
- Agreed Cadence: ${cadence}
- Investment / Price: ${priceFormatted}
- Revision Limits: ${revisionLimits}
- Deliverables:
${deliverablesFormatted}
- Exclusions & Clear Boundaries:
${exclusionsFormatted}
- Relationship Context: ${relationshipContext} (isRenewal: ${isRenewal})
- Desired Tone: ${tone}
${optionalNotes ? `- Freelancer Context/Notes: ${optionalNotes}` : ''}
</plan_facts>

DRAFTING INSTRUCTIONS:
- Write an editable, professional proposal message from the freelancer to ${clientName}.
- Strictly adhere to the "${tone}" tone.
- Clearly present the deliverables, the price of ${priceFormatted} (${cadence}), and the revision limit of "${revisionLimits}".
- Do NOT claim the client has already agreed, signed, or paid.
- Frame the offer as a proposed arrangement for mutual confirmation.

Return ONLY a JSON object with this exact shape:
{
  "deliverablesSummary": "Concise 1-sentence summary of included deliverables",
  "termsSummary": "Summary of fee, cadence, and limits",
  "offerText": "Complete, ready-to-edit proposal/renewal invitation text"
}`;

    return {
      facts: inputData,
      systemInstructions,
      userPrompt,
    };
  },
});

// ----------------------------------------------------------------------------
// STEP 3: Generate Draft with Agent Step
// ----------------------------------------------------------------------------
export const generateOfferWithAgentStep = createStep({
  id: 'generate-offer-agent',
  inputSchema: OfferPreparedPromptSchema,
  outputSchema: OfferAgentRawOutputSchema,
  execute: async ({ inputData }: { inputData: OfferPreparedPrompt }): Promise<OfferAgentRawOutput> => {
    const agent = new Agent({
      id: 'repeat-work-offer-agent',
      name: 'RepeatWorkAgent',
      instructions: inputData.systemInstructions,
      model: getModel(),
    });

    const res = await agent.generate(inputData.userPrompt);
    const rawOutput = res.text ?? '';

    let parsedJson: Record<string, unknown> | undefined;
    try {
      const parsed = extractJsonFromText(rawOutput);
      if (parsed && typeof parsed === 'object') {
        parsedJson = parsed as Record<string, unknown>;
      }
    } catch {
      // 1 single repair pass allowed by handbook protocol
      try {
        const repairRes = await agent.generate(
          `The previous output was not valid JSON. Convert the following text into strictly valid JSON matching { "deliverablesSummary": string, "termsSummary": string, "offerText": string }:\n${rawOutput}`
        );
        const parsed = extractJsonFromText(repairRes.text ?? '{}');
        if (parsed && typeof parsed === 'object') {
          parsedJson = parsed as Record<string, unknown>;
        }
      } catch (repairErr) {
        throw new Error(`INVALID_OUTPUT: Repeat Work offer model output could not be parsed as JSON after 1 repair attempt: ${repairErr instanceof Error ? repairErr.message : String(repairErr)}`);
      }
    }

    return {
      facts: inputData.facts,
      rawModelText: rawOutput,
      parsedJson,
    };
  },
});

// ----------------------------------------------------------------------------
// STEP 4: Validate and Normalize Offer Step
// ----------------------------------------------------------------------------
export const validateAndNormalizeOfferStep = createStep({
  id: 'validate-and-normalize-offer',
  inputSchema: OfferAgentRawOutputSchema,
  outputSchema: OfferDraftOutputSchema,
  execute: async ({ inputData }: { inputData: OfferAgentRawOutput }): Promise<OfferDraftOutput> => {
    const normalized = normalizeOfferDraftOutput(inputData.parsedJson ?? {}, inputData.facts);
    const validated = OfferDraftOutputSchema.safeParse(normalized);
    if (!validated.success) {
      throw new Error(`INVALID_OUTPUT: Repeat Work offer schema validation failed: ${validated.error.message}`);
    }

    return validated.data;
  },
});

// ----------------------------------------------------------------------------
// WORKFLOW COMPOSITION (4 named, inspectable Mastra steps)
// ----------------------------------------------------------------------------
export const offerDraftWorkflow = createWorkflow({
  id: 'offer-draft-workflow',
  inputSchema: OfferDraftInputSchema,
  outputSchema: OfferDraftOutputSchema,
})
  .then(validateOfferFactsStep)
  .then(prepareOfferPromptStep)
  .then(generateOfferWithAgentStep)
  .then(validateAndNormalizeOfferStep)
  .commit();

export async function runOfferDraft(input: OfferDraftInput): Promise<OfferDraftOutput> {
  const validatedInput = OfferDraftInputSchema.parse(input);
  const run = await offerDraftWorkflow.createRun();
  const result = await run.start({ inputData: validatedInput });

  if (result.status === 'success') {
    return result.result as OfferDraftOutput;
  }
  const errorMsg = (result as any).error?.message || 'Offer draft workflow failed';
  throw new Error(errorMsg);
}
