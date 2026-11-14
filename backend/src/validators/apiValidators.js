const { z } = require('zod');

const monthlyStatsQuerySchema = z.object({
  months: z.coerce.number().int().min(1, 'Minimum 1 mois').max(24, 'Maximum 24 mois').default(6),
});

const exportCsvQuerySchema = z.object({
  from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Le format de date "from" doit être YYYY-MM-DD').optional(),
  to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Le format de date "to" doit être YYYY-MM-DD').optional(),
});

const alertsCheckBodySchema = z.object({
  userId: z.string().optional(),
  month: z.string().regex(/^\d{4}-\d{2}$/, 'Le format du mois doit être YYYY-MM').optional(),
});

module.exports = {
  monthlyStatsQuerySchema,
  exportCsvQuerySchema,
  alertsCheckBodySchema,
};
