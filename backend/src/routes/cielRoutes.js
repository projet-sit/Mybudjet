const express = require('express');
const { verifyIdToken } = require('../middlewares/verifyIdToken');
const {
  monthlyStatsQuerySchema,
  exportCsvQuerySchema,
  alertsCheckBodySchema,
} = require('../validators/apiValidators');
const cielService = require('../services/cielService');
const { success } = require('../utils/response');
const ApiError = require('../utils/ApiError');

const router = express.Router();

/**
 * GET /stats/monthly?months=6
 * Agrégation des dépenses par mois et par catégorie (renvoie 0 pour les mois vides).
 */
router.get('/stats/monthly', verifyIdToken, async (req, res, next) => {
  try {
    const parseRes = monthlyStatsQuerySchema.safeParse(req.query);
    if (!parseRes.success) {
      throw ApiError.validation('Paramètres invalides', parseRes.error.flatten().fieldErrors);
    }

    const { months } = parseRes.data;
    const data = await cielService.getMonthlyStats(req.uid, months);
    return success(res, data);
  } catch (err) {
    return next(err);
  }
});

/**
 * GET /export/excel (ou /export/xlsx)
 * Export Excel complet (feuilles Synthèse & Épargne, Opérations, Budgets).
 */
router.get(['/export/excel', '/export/xlsx'], verifyIdToken, async (req, res, next) => {
  try {
    const parseRes = exportCsvQuerySchema.safeParse(req.query);
    if (!parseRes.success) {
      throw ApiError.validation('Paramètres de dates invalides', parseRes.error.flatten().fieldErrors);
    }

    const excelXml = await cielService.exportExcel(req.uid, parseRes.data);
    res.setHeader('Content-Type', 'application/vnd.ms-excel; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename="ciel_finances.xls"');
    return res.status(200).send(excelXml);
  } catch (err) {
    return next(err);
  }
});

/**
 * GET /export/csv?from&to
 * Export CSV (fichier avec seulement l'en-tête si aucune opération).
 */
router.get('/export/csv', verifyIdToken, async (req, res, next) => {
  try {
    const parseRes = exportCsvQuerySchema.safeParse(req.query);
    if (!parseRes.success) {
      throw ApiError.validation('Paramètres de dates invalides', parseRes.error.flatten().fieldErrors);
    }

    const csvContent = await cielService.exportCsv(req.uid, parseRes.data);
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename="ciel_operations.csv"');
    return res.status(200).send(`\uFEFF${csvContent}`);
  } catch (err) {
    return next(err);
  }
});

/**
 * POST /alerts/check
 * Vérifie les budgets et simule / envoie les notifications FCM (seuils 80% et 100%).
 */
router.post('/alerts/check', verifyIdToken, async (req, res, next) => {
  try {
    const parseRes = alertsCheckBodySchema.safeParse(req.body || {});
    if (!parseRes.success) {
      throw ApiError.validation('Données invalides', parseRes.error.flatten().fieldErrors);
    }

    const targetUserId = parseRes.data.userId || req.uid;
    const data = await cielService.checkBudgetAlerts(targetUserId, parseRes.data.month);
    return success(res, data);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
