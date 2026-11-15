const { query, withTransaction } = require('../config/db');
const ApiError = require('../utils/ApiError');
const { monthEnd, toDateOnly } = require('../utils/dates');

function toWallet(row) {
  return {
    id: row.id,
    userId: row.user_id,
    name: row.name,
    initialAmount: Number(row.initial_amount),
    startDate: toDateOnly(row.start_date),
    currency: row.currency,
    balance: Number(row.balance),
    savingsAmount: Number(row.savings_amount || 0),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function findByUserId(userId) {
  const { rows } = await query(
    `SELECT * FROM wallets WHERE user_id = $1 ORDER BY created_at ASC`,
    [userId]
  );
  return rows.map(toWallet);
}

async function findById(walletId) {
  const { rows } = await query('SELECT * FROM wallets WHERE id = $1 LIMIT 1', [walletId]);
  return rows[0] ? toWallet(rows[0]) : null;
}

async function create({ userId, name, initialAmount, startDate, currency }) {
  return withTransaction(async (client) => {
    const { rows } = await client.query(
      `INSERT INTO wallets (user_id, name, initial_amount, start_date, currency, balance)
       VALUES ($1, $2, $3, $4, $5, $3)
       RETURNING *`,
      [userId, name, initialAmount, startDate, currency]
    );
    const wallet = toWallet(rows[0]);

    await client.query(
      `INSERT INTO periods (user_id, wallet_id, start_date, end_date, status)
       VALUES ($1, $2, $3, $4, 'active')`,
      [userId, wallet.id, startDate, monthEnd(startDate)]
    );

    if (initialAmount > 0) {
      await client.query(
        `INSERT INTO initial_amount_history (wallet_id, old_value, new_value) VALUES ($1, 0, $2)`,
        [wallet.id, initialAmount]
      );
    }
    return wallet;
  });
}

async function reservedSavings(client, walletId) {
  const { rows } = await client.query(
    'SELECT COALESCE(SUM(saved_amount), 0) AS total FROM goals WHERE wallet_id = $1',
    [walletId]
  );
  return Number(rows[0].total);
}

/**
 * Modifie le montant initial de façon atomique :
 * - met à jour initial_amount et balance (le solde suit le delta),
 * - enregistre l'historique, le tout dans la même transaction SQL.
 */
async function updateInitialAmount(walletId, newAmount) {
  return withTransaction(async (client) => {
    const current = await client.query(
      'SELECT initial_amount, balance FROM wallets WHERE id = $1 FOR UPDATE',
      [walletId]
    );
    if (current.rows.length === 0) return null;
    const oldValue = Number(current.rows[0].initial_amount);
    const balance = Number(current.rows[0].balance);
    const reserved = await reservedSavings(client, walletId);
    const newBalance = balance + (newAmount - oldValue);

    if (newBalance < reserved) {
      throw ApiError.conflict(
        'SAVINGS_LOCKED',
        'Ce montant est déjà réservé dans tes objectifs d’épargne',
        { reserved }
      );
    }

    const { rows } = await client.query(
      `UPDATE wallets
       SET initial_amount = $2::bigint,
           balance = balance + ($2::bigint - initial_amount),
           updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [walletId, newAmount]
    );
    await client.query(
      `INSERT INTO initial_amount_history (wallet_id, old_value, new_value) VALUES ($1, $2, $3)`,
      [walletId, oldValue, newAmount]
    );
    return toWallet(rows[0]);
  });
}

async function getInitialAmountHistory(walletId) {
  const { rows } = await query(
    `SELECT id, old_value, new_value, changed_at
     FROM initial_amount_history WHERE wallet_id = $1
     ORDER BY changed_at DESC LIMIT 100`,
    [walletId]
  );
  return rows.map((r) => ({
    id: r.id,
    oldValue: Number(r.old_value),
    newValue: Number(r.new_value),
    changedAt: r.changed_at,
  }));
}

module.exports = {
  toWallet,
  findByUserId,
  findById,
  create,
  updateInitialAmount,
  getInitialAmountHistory,
};
