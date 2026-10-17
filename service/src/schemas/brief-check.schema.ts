import { z } from 'zod';

export function normalizeNiche(input?: string): 'design' | 'writing' | 'general' {
  if (!input) return 'general';
  const lower = input.toLowerCase();
  if (lower.includes('design') || lower.includes('brand')) return 'design';
  if (lower.includes('writing') || lower.includes('content') || lower.includes('copy')) return 'writing';
  return 'general';
}

export const BriefCheckInputSchema = z.object({
  requestId: z.string().optional(),
  brief: z.string().optional(),
  briefText: z.string().optional(),
  niche: z.string().default('general'),
  servicePreferences: z.object({
    currency: z.string().optional(),
    categories: z.array(z.string()).optional(),
  }).optional(),
}).refine(data => {
  const text = (data.briefText ?? data.brief ?? '').trim();
  return text.length >= 1 && text.length <= 8000;
}, {
  message: 'Brief text must be between 1 and 8000 characters',
  path: ['brief'],
}).transform(data => ({
  requestId: data.requestId,
  brief: (data.briefText ?? data.brief)!.trim(),
  niche: normalizeNiche(data.niche),
  servicePreferences: data.servicePreferences,
}));

export type BriefCheckInput = z.infer<typeof BriefCheckInputSchema>;

export const StarterScopeItemSchema = z.object({
  title: z.string().min(1, 'Deliverable title required'),
  description: z.string().min(1, 'Deliverable description required'),
});

export const BriefCheckOutputSchema = z.object({
  statedRequirements: z.array(z.string()).default([]).describe('Directly expressed requirements from the brief'),
  assumptions: z.array(z.string()).default([]).describe('Inferred assumptions that need confirmation'),
  omissions: z.array(z.string()).default([]).describe('Important details missing from the brief like deadline or deliverables'),
  suggestedQuestions: z.array(z.string()).default([]).describe('Targeted clarification questions to ask the client'),
  starterScopeItems: z.array(StarterScopeItemSchema).default([]).describe('Draft scope deliverables grounded strictly in stated facts'),
});

export type BriefCheckOutput = z.infer<typeof BriefCheckOutputSchema>;
