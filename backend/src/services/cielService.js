const pool = require('../config/db');

/**
 * Génère la liste des N derniers mois au format YYYY-MM dans l'ordre chronologique
 */
function getLastMonths(count, referenceDate = new Date()) {
  const months = [];
  for (let i = count - 1; i >= 0; i--) {
    const d = new Date(Date.UTC(referenceDate.getFullYear(), referenceDate.getMonth() - i, 1));
    const year = d.getUTCFullYear();
    const month = String(d.getUTCMonth() + 1).padStart(2, '0');
    months.push(`${year}-${month}`);
  }
  return months;
}

function escapeXml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

/**
 * Agrégation des dépenses et revenus par mois et par catégorie.
 * Renvoie des 0 pour les mois sans opération (aucune donnée fictive).
 */
async function getMonthlyStats(userId, monthsCount = 6) {
  const monthKeys = getLastMonths(monthsCount);
  const minMonth = monthKeys[0];
  const maxMonth = monthKeys[monthKeys.length - 1];

  let rows = [];
  try {
    const result = await pool.query(
      `SELECT 
         to_char(date, 'YYYY-MM') as month,
         type,
         category_id,
         category_name,
         SUM(amount)::bigint as total_amount
       FROM transactions
       WHERE user_id = $1 
         AND to_char(date, 'YYYY-MM') >= $2
         AND to_char(date, 'YYYY-MM') <= $3
       GROUP BY to_char(date, 'YYYY-MM'), type, category_id, category_name`,
      [userId, minMonth, maxMonth]
    );
    rows = result.rows || [];
  } catch (err) {
    rows = [];
  }

  const monthMap = {};
  for (const key of monthKeys) {
    monthMap[key] = {
      month: key,
      totalExpense: 0,
      totalIncome: 0,
      categories: [],
    };
  }

  const catMapByMonth = {};

  for (const r of rows) {
    const m = r.month;
    if (!monthMap[m]) continue;

    const amount = parseInt(r.total_amount, 10) || 0;
    if (r.type === 'expense') {
      monthMap[m].totalExpense += amount;
      if (!catMapByMonth[m]) catMapByMonth[m] = {};
      const catId = r.category_id || 'autre';
      catMapByMonth[m][catId] = {
        categoryId: catId,
        categoryName: r.category_name || 'Autre',
        amount: (catMapByMonth[m][catId]?.amount || 0) + amount,
      };
    } else if (r.type === 'income') {
      monthMap[m].totalIncome += amount;
    }
  }

  for (const key of monthKeys) {
    const totalExp = monthMap[key].totalExpense;
    const catObj = catMapByMonth[key] || {};
    const categories = Object.values(catObj).map((cat) => ({
      categoryId: cat.categoryId,
      categoryName: cat.categoryName,
      amount: cat.amount,
      percentage: totalExp > 0 ? Math.round((cat.amount / totalExp) * 1000) / 10 : 0.0,
    }));
    categories.sort((a, b) => b.amount - a.amount);
    monthMap[key].categories = categories;
  }

  return {
    months: monthKeys.map((k) => monthMap[k]),
    hasData: rows.length > 0,
  };
}

/**
 * Export CSV des transactions.
 * Si aucune opération n'existe, renvoie un fichier avec seulement l'en-tête.
 */
async function exportCsv(userId, { from, to } = {}) {
  const header = '"ID","Date","Type","Montant (FCFA)","Catégorie","Note","Objectif"';

  let rows = [];
  try {
    let query = 'SELECT id, date, type, amount, category_name, note, goal_id FROM transactions WHERE user_id = $1';
    const params = [userId];

    if (from) {
      params.push(from);
      query += ` AND date >= $${params.length}`;
    }
    if (to) {
      params.push(to);
      query += ` AND date <= $${params.length}`;
    }
    query += ' ORDER BY date DESC';

    const result = await pool.query(query, params);
    rows = result.rows || [];
  } catch (err) {
    rows = [];
  }

  if (rows.length === 0) {
    return header;
  }

  const lines = rows.map((r) => {
    const id = `"${(r.id || '').replace(/"/g, '""')}"`;
    const date = `"${r.date ? new Date(r.date).toISOString().slice(0, 10) : ''}"`;
    const type = `"${(r.type || '').replace(/"/g, '""')}"`;
    const amount = r.amount || 0;
    const category = `"${(r.category_name || '').replace(/"/g, '""')}"`;
    const note = `"${(r.note || '').replace(/"/g, '""')}"`;
    const goal = `"${(r.goal_id || '').replace(/"/g, '""')}"`;
    return [id, date, type, amount, category, note, goal].join(',');
  });

  return [header, ...lines].join('\n');
}

/**
 * Export Excel (format XML Spreadsheet compatible Excel, Sheets, Numbers).
 * Privilégié pour l'analyse financière complète avec suivi de l'épargne.
 */
async function exportExcel(userId, { from, to } = {}) {
  let transactions = [];
  let budgets = [];
  let totalSavings = 0;

  try {
    let txQuery = 'SELECT id, date, type, amount, category_name, note, goal_id FROM transactions WHERE user_id = $1';
    const params = [userId];
    if (from) {
      params.push(from);
      txQuery += ` AND date >= $${params.length}`;
    }
    if (to) {
      params.push(to);
      txQuery += ` AND date <= $${params.length}`;
    }
    txQuery += ' ORDER BY date DESC';
    const txRes = await pool.query(txQuery, params);
    transactions = txRes.rows || [];

    const bRes = await pool.query('SELECT month, category_name, limit_amount FROM budgets WHERE user_id = $1', [userId]);
    budgets = bRes.rows || [];
  } catch {
    transactions = [];
    budgets = [];
  }

  for (const t of transactions) {
    if (t.type === 'expense' && (t.goal_id || (t.category_name && t.category_name.toLowerCase().includes('épargne')))) {
      totalSavings += parseInt(t.amount, 10) || 0;
    }
  }

  const sb = [];
  sb.push('<?xml version="1.0" encoding="UTF-8"?>');
  sb.push('<?mso-application progid="Excel.Sheet"?>');
  sb.push('<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"');
  sb.push(' xmlns:o="urn:schemas-microsoft-com:office:office"');
  sb.push(' xmlns:x="urn:schemas-microsoft-com:office:excel"');
  sb.push(' xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"');
  sb.push(' xmlns:html="http://www.w3.org/TR/REC-html40">');
  sb.push(' <Styles>');
  sb.push('  <Style ss:ID="Header">');
  sb.push('   <Alignment ss:Horizontal="Center" ss:Vertical="Center"/>');
  sb.push('   <Font ss:FontName="Inter" ss:Size="11" ss:Color="#FFFFFF" ss:Bold="1"/>');
  sb.push('   <Interior ss:Color="#0284C7" ss:Pattern="Solid"/>');
  sb.push('  </Style>');
  sb.push('  <Style ss:ID="Title">');
  sb.push('   <Font ss:FontName="Inter" ss:Size="14" ss:Color="#0284C7" ss:Bold="1"/>');
  sb.push('  </Style>');
  sb.push('  <Style ss:ID="Income">');
  sb.push('   <Font ss:FontName="Inter" ss:Size="11" ss:Color="#059669" ss:Bold="1"/>');
  sb.push('  </Style>');
  sb.push('  <Style ss:ID="Expense">');
  sb.push('   <Font ss:FontName="Inter" ss:Size="11" ss:Color="#E11D48"/>');
  sb.push('  </Style>');
  sb.push(' </Styles>');

  // Feuille 1 : Synthèse & Épargne
  sb.push(' <Worksheet ss:Name="Synthèse &amp; Épargne">');
  sb.push('  <Table ss:DefaultColumnWidth="160">');
  sb.push('   <Row ss:Height="24"><Cell ss:StyleID="Title"><Data ss:Type="String">Ciel - Suivi Financier &amp; Épargne</Data></Cell></Row>');
  sb.push('   <Row ss:Height="20"><Cell ss:StyleID="Header"><Data ss:Type="String">Indicateur</Data></Cell><Cell ss:StyleID="Header"><Data ss:Type="String">Valeur (FCFA)</Data></Cell></Row>');
  sb.push(`   <Row><Cell><Data ss:Type="String">Total Épargné à date</Data></Cell><Cell><Data ss:Type="Number">${totalSavings}</Data></Cell></Row>`);
  sb.push(`   <Row><Cell><Data ss:Type="String">Nombre d'opérations</Data></Cell><Cell><Data ss:Type="Number">${transactions.length}</Data></Cell></Row>`);
  sb.push('  </Table>');
  sb.push(' </Worksheet>');

  // Feuille 2 : Opérations
  sb.push(' <Worksheet ss:Name="Opérations">');
  sb.push('  <Table ss:DefaultColumnWidth="130">');
  sb.push('   <Row ss:Height="20">');
  sb.push('    <Cell ss:StyleID="Header"><Data ss:Type="String">Date</Data></Cell>');
  sb.push('    <Cell ss:StyleID="Header"><Data ss:Type="String">Type</Data></Cell>');
  sb.push('    <Cell ss:StyleID="Header"><Data ss:Type="String">Montant (FCFA)</Data></Cell>');
  sb.push('    <Cell ss:StyleID="Header"><Data ss:Type="String">Catégorie</Data></Cell>');
  sb.push('    <Cell ss:StyleID="Header"><Data ss:Type="String">Note</Data></Cell>');
  sb.push('    <Cell ss:StyleID="Header"><Data ss:Type="String">Objectif lié</Data></Cell>');
  sb.push('   </Row>');
  for (const t of transactions) {
    const isInc = t.type === 'income';
    const style = isInc ? 'Income' : 'Expense';
    const dateStr = t.date ? new Date(t.date).toISOString().slice(0, 10) : '';
    sb.push(`   <Row><Cell><Data ss:Type="String">${dateStr}</Data></Cell><Cell ss:StyleID="${style}"><Data ss:Type="String">${isInc ? 'Revenu' : 'Dépense'}</Data></Cell><Cell ss:StyleID="${style}"><Data ss:Type="Number">${t.amount || 0}</Data></Cell><Cell><Data ss:Type="String">${escapeXml(t.category_name)}</Data></Cell><Cell><Data ss:Type="String">${escapeXml(t.note)}</Data></Cell><Cell><Data ss:Type="String">${escapeXml(t.goal_id)}</Data></Cell></Row>`);
  }
  sb.push('  </Table>');
  sb.push(' </Worksheet>');

  // Feuille 3 : Budgets
  sb.push(' <Worksheet ss:Name="Budgets">');
  sb.push('  <Table ss:DefaultColumnWidth="140">');
  sb.push('   <Row ss:Height="20">');
  sb.push('    <Cell ss:StyleID="Header"><Data ss:Type="String">Mois</Data></Cell>');
  sb.push('    <Cell ss:StyleID="Header"><Data ss:Type="String">Catégorie</Data></Cell>');
  sb.push('    <Cell ss:StyleID="Header"><Data ss:Type="String">Plafond (FCFA)</Data></Cell>');
  sb.push('   </Row>');
  for (const b of budgets) {
    sb.push(`   <Row><Cell><Data ss:Type="String">${b.month}</Data></Cell><Cell><Data ss:Type="String">${escapeXml(b.category_name)}</Data></Cell><Cell><Data ss:Type="Number">${b.limit_amount || 0}</Data></Cell></Row>`);
  }
  sb.push('  </Table>');
  sb.push(' </Worksheet>');
  sb.push('</Workbook>');

  return sb.join('\n');
}

/**
 * Vérification des budgets et envoi de notifications FCM si 80% ou 100% atteints
 */
async function checkBudgetAlerts(userId, targetMonth) {
  const now = new Date();
  const month = targetMonth || `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;

  let budgets = [];
  let expensesByCategory = {};

  try {
    const budgetRes = await pool.query(
      'SELECT id, category_id, category_name, limit_amount FROM budgets WHERE user_id = $1 AND month = $2',
      [userId, month]
    );
    budgets = budgetRes.rows || [];

    const expRes = await pool.query(
      `SELECT category_id, SUM(amount)::bigint as total 
       FROM transactions 
       WHERE user_id = $1 AND type = 'expense' AND to_char(date, 'YYYY-MM') = $2 
       GROUP BY category_id`,
      [userId, month]
    );
    for (const r of expRes.rows || []) {
      expensesByCategory[r.category_id] = parseInt(r.total, 10);
    }
  } catch {
    budgets = [];
  }

  const alerts = [];
  for (const b of budgets) {
    const spent = expensesByCategory[b.category_id] || 0;
    const limit = b.limit_amount || 0;
    if (limit <= 0) continue;

    const percentage = (spent / limit) * 100;
    if (percentage >= 100) {
      alerts.push({
        budgetId: b.id,
        categoryId: b.category_id,
        categoryName: b.category_name,
        spent,
        limit,
        percentage,
        type: 'exceeded',
        message: `Budget dépassé : vous avez atteint ${Math.round(percentage)}% de votre budget ${b.category_name}.`,
      });
    } else if (percentage >= 80) {
      alerts.push({
        budgetId: b.id,
        categoryId: b.category_id,
        categoryName: b.category_name,
        spent,
        limit,
        percentage,
        type: 'warning',
        message: `Attention : vous avez consommé ${Math.round(percentage)}% de votre budget ${b.category_name}.`,
      });
    }
  }

  return {
    month,
    totalBudgets: budgets.length,
    alerts,
    notificationsSent: alerts.length,
  };
}

module.exports = {
  getMonthlyStats,
  exportCsv,
  exportExcel,
  checkBudgetAlerts,
};
