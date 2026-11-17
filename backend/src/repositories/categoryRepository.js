const { query, withTransaction } = require('../config/db');
const ApiError = require('../utils/ApiError');
const { validateName, normalizeName, DEFAULT_ORDER, DEFAULT_LAST, MAX_CUSTOM_PER_TYPE } = require('../utils/categoryNames');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function toCategory(row) {
  return {
    id: row.id,
    name: row.name,
    type: row.type,
    isDefault: row.is_default,
    iconKey: row.icon_key,
  };
}

/** Tri : défauts (ordre produit) → personnalisées (par nom) → « Autres » en dernier. */
function sortCategories(rows) {
  const otherKey = (r) => (r.normalized_name === normalizeName(DEFAULT_LAST) ? 1 : 0);
  const defaultIndex = (r, type) => {
    if (!r.is_default || r.normalized_name === normalizeName(DEFAULT_LAST)) return 999;
    const order = DEFAULT_ORDER[type] || [];
    const idx = order.findIndex((n) => normalizeName(n) === r.normalized_name);
    return idx === -1 ? 500 : idx;
  };
  return [...rows].sort((a, b) => {
    if (otherKey(a) !== otherKey(b)) return otherKey(a) - otherKey(b);
    if (a.is_default !== b.is_default) return a.is_default ? -1 : 1;
    if (a.is_default) return defaultIndex(a, a.type) - defaultIndex(b, b.type);
    return a.normalized_name.localeCompare(b.normalized_name, 'fr');
  });
}

/** Catégories visibles pour un utilisateur (défauts système + siennes), triées. */
async function listVisible(uid, type) {
  if (type && !['expense', 'income'].includes(type)) {
    throw ApiError.validation("Le type doit être 'expense' ou 'income'", { field: 'type' });
  }
  const params = [uid];
  let sql = `SELECT * FROM categories WHERE (user_id = $1 OR user_id IS NULL)`;
  if (type) { sql += ` AND type = $2`; params.push(type); }
  const { rows } = await query(sql, params);
  const byType = { expense: [], income: [] };
  for (const row of rows) byType[row.type].push(row);
  return {
    categories: sortCategories(type ? rows : [...byType.expense, ...byType.income]).map(toCategory),
    byType: {
      expense: sortCategories(byType.expense).map(toCategory),
      income: sortCategories(byType.income).map(toCategory),
    },
  };
}

async function countCustom(uid, type) {
  const { rows } = await query(
    `SELECT COUNT(*)::int AS n FROM categories WHERE user_id = $1 AND is_default = false AND type = $2`,
    [uid, type]
  );
  return rows[0].n;
}

/**
 * Crée une catégorie personnalisée.
 * - Dédoublonnage insensible casse/accents, y compris avec les catégories par défaut.
 * - `id` client accepté (idempotence des rejeux outbox hors-ligne).
 */
async function create(uid, { id, type, name } = {}) {
  if (!['expense', 'income'].includes(String(type || ''))) {
    throw ApiError.validation("Le type doit être 'expense' ou 'income'", { field: 'type' });
  }
  const check = validateName(name);
  if (!check.ok) throw ApiError.validation(check.error, { field: 'name' });
  if (id != null && !UUID_RE.test(String(id))) {
    throw ApiError.validation('Identifiant de catégorie invalide', { field: 'id' });
  }

  // Idempotence : un rejeu avec le même id retourne la catégorie existante.
  if (id) {
    const byId = await query('SELECT * FROM categories WHERE id = $1', [id]);
    if (byId.rows[0]) {
      const row = byId.rows[0];
      if (row.user_id === null || row.user_id === uid) {
        return { category: toCategory(row), created: false, fused: true };
      }
      throw ApiError.conflict('CATEGORY_EXISTS', 'Cette catégorie existe déjà, elle est sélectionnée', {
        category: toCategory(row),
      });
    }
  }

  const exists = await query(
    `SELECT * FROM categories
     WHERE type = $2 AND normalized_name = $3 AND (user_id = $1 OR user_id IS NULL)
     LIMIT 1`,
    [uid, type, check.normalized]
  );
  if (exists.rows[0]) {
    throw ApiError.conflict('CATEGORY_EXISTS', 'Cette catégorie existe déjà, elle est sélectionnée', {
      category: toCategory(exists.rows[0]),
    });
  }

  const current = await countCustom(uid, type);
  if (current >= MAX_CUSTOM_PER_TYPE) {
    throw ApiError.validation(`Maximum ${MAX_CUSTOM_PER_TYPE} catégories personnalisées par type`, { field: 'name' });
  }

  const { rows } = await query(
    `INSERT INTO categories (id, user_id, type, name, normalized_name, is_default, icon_key)
     VALUES ($1, $2, $3, $4, $5, false, 'label')
     RETURNING *`,
    [id || require('crypto').randomUUID(), uid, type, check.value, check.normalized]
  );
  return { category: toCategory(rows[0]), created: true, fused: false };
}

async function rename(uid, categoryId, name) {
  if (!UUID_RE.test(String(categoryId || ''))) throw ApiError.validation('Identifiant invalide', { field: 'id' });
  const check = validateName(name);
  if (!check.ok) throw ApiError.validation(check.error, { field: 'name' });

  return withTransaction(async (client) => {
    const { rows } = await client.query('SELECT * FROM categories WHERE id = $1 FOR UPDATE', [categoryId]);
    const row = rows[0];
    if (!row || row.user_id !== uid) throw ApiError.notFound('Catégorie introuvable');
    if (row.is_default) throw ApiError.validation('Les catégories par défaut ne peuvent pas être renommées', { field: 'id' });

    const dup = await client.query(
      `SELECT * FROM categories
       WHERE type = $2 AND normalized_name = $3 AND id <> $4
         AND (user_id = $1 OR user_id IS NULL)
       LIMIT 1`,
      [uid, row.type, check.normalized, categoryId]
    );
    if (dup.rows[0]) {
      throw ApiError.conflict('CATEGORY_EXISTS', 'Cette catégorie existe déjà, elle est sélectionnée', {
        category: toCategory(dup.rows[0]),
      });
    }

    const upd = await client.query(
      'UPDATE categories SET name = $2, normalized_name = $3 WHERE id = $1 RETURNING *',
      [categoryId, check.value, check.normalized]
    );
    // Tient à jour le texte dénormalisé (affichage, recherche, CSV).
    await client.query('UPDATE transactions SET category = $2, updated_at = now() WHERE category_id = $1', [categoryId, check.value]);
    await client.query('UPDATE budgets SET category = $2, updated_at = now() WHERE category_id = $1', [categoryId, check.value]);
    return { category: toCategory(upd.rows[0]) };
  });
}

/**
 * Supprime une catégorie personnalisée.
 * - Les opérations passent en « Autres » (même type), jamais perdues.
 * - Les budgets liés sont supprimés (le client demande confirmation avant).
 * Deux temps : d'abord un essai sans `confirmBudgets` → 409 avec la liste des budgets ;
 * puis `confirmBudgets=true` après validation utilisateur.
 */
async function remove(uid, categoryId, { confirmBudgets = false } = {}) {
  if (!UUID_RE.test(String(categoryId || ''))) throw ApiError.validation('Identifiant invalide', { field: 'id' });

  const { rows } = await query('SELECT * FROM categories WHERE id = $1', [categoryId]);
  const row = rows[0];
  if (!row || row.user_id !== uid) throw ApiError.notFound('Catégorie introuvable');
  if (row.is_default) throw ApiError.validation('Les catégories par défaut ne peuvent pas être supprimées', { field: 'id' });

  const budgets = await query('SELECT id, wallet_id, category, limit_amount FROM budgets WHERE category_id = $1', [categoryId]);
  if (budgets.rows.length > 0 && !confirmBudgets) {
    throw ApiError.conflict('CATEGORY_HAS_BUDGET', 'Un budget est lié à cette catégorie', {
      budgets: budgets.rows.map((b) => ({ id: b.id, category: row.name, limitAmount: Number(b.limit_amount) })),
    });
  }

  return withTransaction(async (client) => {
    // Réaffectation en « Autres » par type (jamais de perte d'opération).
    await client.query(
      `UPDATE transactions
       SET category_id = (SELECT id FROM categories WHERE user_id IS NULL AND type = 'expense' AND normalized_name = $2 LIMIT 1),
           category = 'Autres', updated_at = now()
       WHERE category_id = $1 AND type = 'expense'`,
      [categoryId, normalizeName(DEFAULT_LAST)]
    );
    await client.query(
      `UPDATE transactions
       SET category_id = (SELECT id FROM categories WHERE user_id IS NULL AND type = 'income' AND normalized_name = $2 LIMIT 1),
           category = 'Autres', updated_at = now()
       WHERE category_id = $1 AND type = 'income'`,
      [categoryId, normalizeName(DEFAULT_LAST)]
    );
    if (budgets.rows.length > 0) {
      await client.query('DELETE FROM budgets WHERE category_id = $1', [categoryId]);
    }
    await client.query('DELETE FROM categories WHERE id = $1', [categoryId]);
    return { deleted: true, reassignedTo: 'Autres', budgetsDeleted: budgets.rows.length };
  });
}

/**
 * Résolution d'une catégorie à l'écriture (transaction ou budget).
 * - `categoryId` gagne ; sinon le nom est cherché (personnalisée utilisateur puis défaut).
 */
async function resolve(uid, type, { categoryId, category } = {}) {
  if (categoryId) {
    const { rows } = await query(
      `SELECT * FROM categories WHERE id = $1 AND type = $2 AND (user_id = $3 OR user_id IS NULL)`,
      [categoryId, type, uid]
    );
    if (!rows[0]) throw ApiError.validation('Catégorie inconnue', { field: 'categoryId' });
    return { id: rows[0].id, name: rows[0].name };
  }
  const text = String(category || '').trim();
  if (!text) throw ApiError.validation('Catégorie requise', { field: 'category' });
  const normalized = normalizeName(text);
  const { rows } = await query(
    `SELECT * FROM categories
     WHERE type = $2 AND normalized_name = $3 AND (user_id = $1 OR user_id IS NULL)
     ORDER BY user_id NULLS LAST
     LIMIT 1`,
    [uid, type, normalized]
  );
  if (!rows[0]) {
    const allowed = await query(
      `SELECT name FROM categories WHERE type = $2 AND (user_id = $1 OR user_id IS NULL)
       ORDER BY is_default DESC, name ASC`,
      [uid, type]
    );
    throw ApiError.validation(
      type === 'expense' ? 'Catégorie invalide pour une dépense' : 'Catégorie invalide pour un revenu',
      { field: 'category', allowed: allowed.rows.map((r) => r.name) }
    );
  }
  return { id: rows[0].id, name: rows[0].name };
}

module.exports = { listVisible, create, rename, remove, resolve, countCustom, toCategory, sortCategories };
