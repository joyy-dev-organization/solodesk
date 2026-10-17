import { z } from 'zod';

export const ScopeItemInputSchema = z.object({
  id: z.string().min(1),
  title: z.string().min(1),
  description: z.string(),
});

export const ScopeCheckInputSchema = z.object({
  requestId: z.string().optional(),
  requestText: z.string().min(1, 'Request text cannot be empty').max(8000, 'Request text cannot exceed 8000 characters'),
  scopeVersionId: z.string().min(1),
  scopeItems: z.array(ScopeItemInputSchema).min(1, 'At least one approved scope item is required for comparison'),
});

export type ScopeCheckInput = z.infer<typeof ScopeCheckInputSchema>;

export const ScopeClassificationEnum = z.enum([
  'INCLUDED',
  'POTENTIALLY_OUTSIDE',
  'NEEDS_CLARIFICATION',
]);

export const ScopeItemEvaluationSchema = z.object({
  requestExcerpt: z.string().describe('The relevant snippet from the client request'),
  classification: ScopeClassificationEnum,
  rationale: z.string().describe('Clear rationale comparing the excerpt to approved scope items'),
  matchedScopeItemId: z.string().nullable().optional().describe('ID of the matching scope item if included or referenced, or null if none'),
});

export const ScopeCheckOutputSchema = z.object({
  evaluations: z.array(ScopeItemEvaluationSchema).describe('Itemized classification of each part of the client request'),
  suggestedReply: z.string().describe('A polite, professional response draft clearly acknowledging included items and politely clarifying extra items without auto-committing'),
});

export type ScopeCheckOutput = z.infer<typeof ScopeCheckOutputSchema>;
