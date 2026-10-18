import { z } from 'zod';

export const OfferToneEnum = z.enum(['collaborative', 'professional', 'value_focused']);
export type OfferTone = z.infer<typeof OfferToneEnum>;

export const ServiceCadenceEnum = z.enum([
  'monthly',
  'quarterly',
  'bi-weekly',
  'weekly',
  'annual',
  'retainer',
]);
export type ServiceCadence = z.infer<typeof ServiceCadenceEnum>;

export function normalizeOfferTone(input?: string): OfferTone {
  if (!input) return 'collaborative';
  const lower = input.toLowerCase().trim();
  if (lower.includes('profess') || lower.includes('formal') || lower.includes('direct')) return 'professional';
  if (lower.includes('value') || lower.includes('roi') || lower.includes('growth') || lower.includes('impact')) return 'value_focused';
  return 'collaborative';
}

export function normalizeCadence(input?: string): ServiceCadence {
  if (!input) return 'monthly';
  const lower = input.toLowerCase().trim();
  if (lower.includes('quarter')) return 'quarterly';
  if (lower.includes('bi-week') || lower.includes('biweek') || lower.includes('fortnight')) return 'bi-weekly';
  if (lower.includes('week')) return 'weekly';
  if (lower.includes('annual') || lower.includes('year')) return 'annual';
  if (lower.includes('retain')) return 'retainer';
  return 'monthly';
}

/**
 * Input Schema for POST /v1/offer-draft
 */
export const OfferDraftInputSchema = z.object({
  requestId: z.string().optional(),
  clientName: z.string().min(1, 'clientName is required').max(200, 'clientName cannot exceed 200 chars'),
  serviceNiche: z.string().min(1, 'serviceNiche is required').max(100, 'serviceNiche cannot exceed 100 chars'),
  planTitle: z.string().min(1, 'planTitle is required').max(200, 'planTitle cannot exceed 200 chars'),
  deliverables: z.array(z.string().min(1)).min(1, 'At least one deliverable must be specified').max(50),
  exclusions: z.array(z.string().min(1)).default([]),
  revisionLimits: z.string().min(1, 'revisionLimits is required').max(200, 'revisionLimits cannot exceed 200 chars'),
  priceFormatted: z.string().min(1, 'priceFormatted is required (e.g. "$2,500/month" or "₦350,000/month")').max(50),
  currency: z.string().length(3, 'currency must be a 3-letter ISO code').toUpperCase().optional(),
  cadence: z.string().default('monthly'),
  tone: z.string().default('collaborative'),
  isRenewal: z.boolean().default(false),
  optionalNotes: z.string().max(8000, 'optionalNotes cannot exceed 8,000 characters').optional(),
}).transform(data => ({
  requestId: data.requestId,
  clientName: data.clientName.trim(),
  serviceNiche: data.serviceNiche.trim(),
  planTitle: data.planTitle.trim(),
  deliverables: data.deliverables.map(d => d.trim()).filter(Boolean),
  exclusions: data.exclusions.map(e => e.trim()).filter(Boolean),
  revisionLimits: data.revisionLimits.trim(),
  priceFormatted: data.priceFormatted.trim(),
  currency: data.currency?.trim().toUpperCase(),
  cadence: normalizeCadence(data.cadence),
  tone: normalizeOfferTone(data.tone),
  isRenewal: Boolean(data.isRenewal),
  optionalNotes: data.optionalNotes?.trim(),
}));

export type OfferDraftInput = z.infer<typeof OfferDraftInputSchema>;

/**
 * Intermediate Step Schemas
 */
export const OfferFactsEnrichedSchema = z.object({
  clientName: z.string(),
  serviceNiche: z.string(),
  planTitle: z.string(),
  deliverables: z.array(z.string()),
  exclusions: z.array(z.string()),
  revisionLimits: z.string(),
  priceFormatted: z.string(),
  currency: z.string().optional(),
  cadence: ServiceCadenceEnum,
  tone: OfferToneEnum,
  isRenewal: z.boolean(),
  relationshipContext: z.string(),
  optionalNotes: z.string().optional(),
});
export type OfferFactsEnriched = z.infer<typeof OfferFactsEnrichedSchema>;

export const OfferPreparedPromptSchema = z.object({
  facts: OfferFactsEnrichedSchema,
  systemInstructions: z.string(),
  userPrompt: z.string(),
});
export type OfferPreparedPrompt = z.infer<typeof OfferPreparedPromptSchema>;

export const OfferAgentRawOutputSchema = z.object({
  facts: OfferFactsEnrichedSchema,
  rawModelText: z.string(),
  parsedJson: z.record(z.string(), z.unknown()).optional(),
});
export type OfferAgentRawOutput = z.infer<typeof OfferAgentRawOutputSchema>;

/**
 * Output Schema returned by the Mastra OfferDraft workflow
 */
export const OfferDraftOutputSchema = z.object({
  offerText: z.string().min(1).describe('Ready-to-edit proposals/offers grounded strictly in verified plan facts'),
  deliverablesSummary: z.string().min(1).describe('Concise operational summary of included deliverables'),
  termsSummary: z.string().min(1).describe('Operational summary of pricing, cadence, revisions, and boundary exclusions'),
  factPreservation: z.object({
    pricePreserved: z.boolean().describe('True if exact formatted price appears in offer draft'),
    cadencePreserved: z.boolean().describe('True if cadence appears in offer draft'),
    revisionLimitsPreserved: z.boolean().describe('True if revision limits appear in offer draft'),
  }),
  // Ergonomic aliases
  draft: z.string().optional(),
  proposalDraft: z.string().optional(),
});

export type OfferDraftOutput = z.infer<typeof OfferDraftOutputSchema>;
