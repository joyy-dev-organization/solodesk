import { z } from 'zod';
import { normalizeNiche } from './brief-check.schema.js';

/**
 * Scope item representation matching Flutter SQLite entity and M1 spike
 */
export const ScopeItemInputSchema = z.object({
  id: z.string().min(1, 'Scope item id is required'),
  category: z.string().optional().transform(val => {
    if (!val) return 'included';
    const lower = val.toLowerCase().trim();
    if (lower === 'included') return 'included';
    if (lower === 'excluded') return 'excluded';
    if (lower === 'allowance') return 'allowance';
    return 'included';
  }),
  description: z.string().min(1, 'Scope item description is required'),
  title: z.string().optional(),
});

export type ScopeItemInput = z.infer<typeof ScopeItemInputSchema>;

/**
 * Input schema for POST /api/scope-check and /v1/scope-check
 */
export const ScopeCheckInputSchema = z.object({
  requestId: z.string().optional(),
  request: z.string().optional(),
  requestText: z.string().optional(),
  niche: z.string().default('general'),
  scopeVersionId: z.string().min(1, 'scopeVersionId is required and cannot be empty'),
  scopeItems: z.array(ScopeItemInputSchema).min(1, 'At least one approved scope item is required for comparison'),
}).refine(data => {
  const text = (data.requestText ?? data.request ?? '').trim();
  return text.length >= 1 && text.length <= 8000;
}, {
  message: 'Request text must be between 1 and 8000 characters',
  path: ['requestText'],
}).transform(data => ({
  requestId: data.requestId,
  requestText: (data.requestText ?? data.request)!.trim(),
  niche: normalizeNiche(data.niche),
  scopeVersionId: data.scopeVersionId.trim(),
  scopeItems: data.scopeItems,
}));

export type ScopeCheckInput = z.infer<typeof ScopeCheckInputSchema>;

/**
 * Finding classification categories
 */
export const FindingCategoryEnum = z.enum([
  'included',
  'out_of_scope',
  'needs_clarification',
]);

export type FindingCategory = z.infer<typeof FindingCategoryEnum>;

/**
 * Item-level finding evaluating a specific excerpt from client request
 */
export const ScopeFindingSchema = z.object({
  category: FindingCategoryEnum.describe('Classification: included, out_of_scope, or needs_clarification'),
  classification: z.string().optional().describe('Legacy uppercase classification'),
  requestExcerpt: z.string().describe('Verbatim or trimmed excerpt from the client request message'),
  matchedScopeItemId: z.string().nullable().optional().describe('ID of the matching scope item if applicable, or null if none'),
  matchedScopeItemDescription: z.string().nullable().optional().describe('Description of the matching scope deliverable or "No matching scope item found"'),
  explanation: z.string().describe('Crisp rationale comparing excerpt against approved scope without legal conclusions'),
  rationale: z.string().optional().describe('Alias for explanation'),
});

export type ScopeFinding = z.infer<typeof ScopeFindingSchema>;

/**
 * Output schema returned by Mastra ScopeCheck workflow
 */
export const ScopeCheckOutputSchema = z.object({
  findings: z.array(ScopeFindingSchema).default([]).describe('Itemized classification of each part of the client request'),
  replyDraft: z.string().describe('Courteous, professional response draft. Never auto-sends or auto-charges.'),
  summary: z.string().describe('High-level summary of request scope status'),
  // Aliases for full backward compatibility
  evaluations: z.array(ScopeFindingSchema).optional(),
  suggestedReply: z.string().optional(),
});

export type ScopeCheckOutput = z.infer<typeof ScopeCheckOutputSchema>;
