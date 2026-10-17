import { z } from 'zod';

export const BriefCheckInputSchema = z.object({
  requestId: z.string().optional(),
  brief: z.string().min(1, 'Brief cannot be empty').max(8000, 'Brief cannot exceed 8000 characters'),
  niche: z.enum(['design', 'writing', 'general']).default('general'),
});

export type BriefCheckInput = z.infer<typeof BriefCheckInputSchema>;

export const StarterScopeItemSchema = z.object({
  title: z.string().min(1),
  description: z.string().min(1),
});

export const BriefCheckOutputSchema = z.object({
  statedRequirements: z.array(z.string()).describe('Directly expressed requirements from the brief'),
  assumptions: z.array(z.string()).describe('Inferred assumptions that need confirmation'),
  omissions: z.array(z.string()).describe('Important details missing from the brief like deadline or deliverables'),
  suggestedQuestions: z.array(z.string()).describe('Targeted clarification questions to ask the client'),
  starterScopeItems: z.array(StarterScopeItemSchema).describe('Draft scope deliverables grounded strictly in stated facts'),
});

export type BriefCheckOutput = z.infer<typeof BriefCheckOutputSchema>;
