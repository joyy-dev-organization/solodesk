import { z } from 'zod';

export const ReminderToneEnum = z.enum(['gentle', 'polite', 'firm']);
export type ReminderTone = z.infer<typeof ReminderToneEnum>;

/**
 * Normalizes user-supplied tone aliases to standard enum
 */
export function normalizeTone(input?: string): ReminderTone {
  if (!input) return 'polite';
  const lower = input.toLowerCase().trim();
  if (lower.includes('gentle') || lower.includes('friendly') || lower.includes('soft')) return 'gentle';
  if (lower.includes('firm') || lower.includes('urgent') || lower.includes('final') || lower.includes('escalat')) return 'firm';
  return 'polite';
}

/**
 * Input schema for POST /api/invoice-reminder and /v1/invoice-reminder
 */
export const InvoiceReminderInputSchema = z.object({
  requestId: z.string().optional(),
  invoiceId: z.string().min(1, 'invoiceId is required and cannot be empty'),
  clientName: z.string().min(1, 'clientName is required and cannot be empty'),
  invoiceNumber: z.string().min(1, 'invoiceNumber is required and cannot be empty'),
  amountFormatted: z.string().min(1, 'amountFormatted is required (e.g. "$1,500.00" or "₦450,000.00")'),
  currency: z.string().length(3, 'currency must be a 3-letter ISO 4217 code').toUpperCase(),
  dueDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'dueDate must be a calendar date in YYYY-MM-DD format'),
  daysOverdue: z.number().int().min(0, 'daysOverdue must be >= 0 (0 for due today or upcoming)'),
  tone: z.string().default('polite'),
  optionalNotes: z.string().max(8000, 'optionalNotes cannot exceed 8,000 characters').optional(),
}).transform(data => ({
  requestId: data.requestId,
  invoiceId: data.invoiceId.trim(),
  clientName: data.clientName.trim(),
  invoiceNumber: data.invoiceNumber.trim(),
  amountFormatted: data.amountFormatted.trim(),
  currency: data.currency.trim().toUpperCase(),
  dueDate: data.dueDate.trim(),
  daysOverdue: data.daysOverdue,
  tone: normalizeTone(data.tone),
  optionalNotes: data.optionalNotes?.trim(),
}));

export type InvoiceReminderInput = z.infer<typeof InvoiceReminderInputSchema>;

/**
 * Output schema returned by the Mastra InvoiceReminder workflow
 */
export const InvoiceReminderOutputSchema = z.object({
  reminderDraft: z.string().min(1).describe('Courteous, empathetic payment reminder draft grounded strictly in verified invoice facts'),
  summary: z.string().min(1).describe('Concise operational summary of the reminder context and stance'),
  toneUsed: ReminderToneEnum.describe('The verified tone applied to the message draft'),
  // Aliases for frontend backward compatibility
  draft: z.string().optional(),
  suggestedMessage: z.string().optional(),
});

export type InvoiceReminderOutput = z.infer<typeof InvoiceReminderOutputSchema>;
