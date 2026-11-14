const { query, withTransaction } = require('../config/db');
const ApiError = require('../utils/ApiError');
const { toDateOnly } = require('../utils/dates');
const { toWallet } = require('./walletRepository');

function toGoal(row) {
  return {
    id: row.id,
    userId: row.user_id,
    walletId: row.wallet_id,
    name: row.name,
    targetAmount: Number(row.target_amount),
    savedAmount: Number(row.saved_amount),
    deadline: toDateOnly(row.deadline),
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function list(walletId) {
  const { rows } = await query(
    `SELECT * FROM goals WHERE wallet_id = $1
     ORDER BY CASE WHEN status = 'active' THEN 0 ELSE 1 END, created_at ASC`,
    [walletId]
  );
  return rows.map(toGoal);
}

async function findById(walletId, goalId) {
  const { rows } = await query(
    'SELECT * FROM goals WHERE id = $1 AND wallet_id = $2 LIMIT 1',
    [goalId, walletId]
  );
  return rows[0] ? toGoal(rows[0]) : null;
}

async function create({ userId, walletId, name, targetAmount, deadline }) {
  const { rows } = await query(
    `INSERT INTO goals (user_id, wallet_id, name, target_amount, deadline)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING *`,
    [userId, walletId, name, targetAmount, deadline || null]
  );
  return toGoal(rows[0]);
}

async function update({ walletId, goalId, name, targetAmount, deadline }) {
  return withTransaction(async (client) => {
    const existing = await client.query(
      'SELECT * FROM goals WHERE id = $1 AND wallet_id = $2 FOR UPDATE',
      [goalId, walletId]
    );
    if (!existing.rows[0]) throw ApiError.notFound('Objectif introuvable');
    const goal = toGoal(existing.rows[0]);

    const status = goal.savedAmount >= targetAmount ? 'completed' : 'active';
    const { rows } = await client.query(
      `UPDATE goals
       SET name = $2, target_amount = $3, deadline = $4, status = $5, updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [goalId, name, targetAmount, deadline || null, status]
    );
    return toGoal(rows[0]);
  });
}

async function remove(walletId, goalId) {
  return withTransaction(async (client) => {
    const existing = await client.query(
      'SELECT * FROM goals WHERE id = $1 AND wallet_id = $2 FOR UPDATE',
      [goalId, walletId]
    );
    if (!existing.rows[0]) throw ApiError.notFound('Objectif introuvable');
    if (Number(existing.rows[0].saved_amount) > 0) {
      throw ApiError.conflict(
        'GOAL_HAS_SAVINGS',
        'Retire d’abord l’argent placé sur cet objectif avant de le supprimer'
      );
    }
    await client.query('DELETE FROM goals WHERE id = $1', [goalId]);
    return { deleted: true };
  });
}

async function contribute({ walletId, goalId, amount }) {
  return withTransaction(async (client) => {
    const walletRes = await client.query(
      'SELECT * FROM wallets WHERE id = $1 FOR UPDATE',
      [walletId]
    );
    if (!walletRes.rows[0]) throw ApiError.notFound('Portefeuille introuvable');
    const wallet = toWallet(walletRes.rows[0]);

    const goalRes = await client.query(
      'SELECT * FROM goals WHERE id = $1 AND wallet_id = $2 FOR UPDATE',
      [goalId, walletId]
    );
    if (!goalRes.rows[0]) throw ApiError.notFound('Objectif introuvable');
    const goal = toGoal(goalRes.rows[0]);

    const available = wallet.balance - wallet.savingsAmount;
    if (amount > available) {
      throw ApiError.conflict(
        'INSUFFICIENT_AVAILABLE',
        'Solde disponible insuffisant pour cet objectif',
        { available }
      );
    }

    const remaining = goal.targetAmount - goal.savedAmount;
    if (remaining <= 0) {
      throw ApiError.conflict('GOAL_COMPLETED', 'Cet objectif est déjà atteint');
    }
    if (amount > remaining) {
      throw ApiError.validation(
        `Il ne reste que ${remaining} FCFA à ajouter sur cet objectif`,
        { field: 'amount', remaining }
      );
    }

    const newSaved = goal.savedAmount + amount;
    const status = newSaved >= goal.targetAmount ? 'completed' : 'active';
    const updatedGoal = await client.query(
      `UPDATE goals
       SET saved_amount = $2, status = $3, updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [goalId, newSaved, status]
    );

    const updatedWallet = await client.query(
      `UPDATE wallets
       SET savings_amount = savings_amount + $2::bigint, updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [walletId, amount]
    );

    return {
      goal: toGoal(updatedGoal.rows[0]),
      wallet: toWallet(updatedWallet.rows[0]),
    };
  });
}

async function withdraw({ walletId, goalId, amount }) {
  return withTransaction(async (client) => {
    const walletRes = await client.query(
      'SELECT * FROM wallets WHERE id = $1 FOR UPDATE',
      [walletId]
    );
    if (!walletRes.rows[0]) throw ApiError.notFound('Portefeuille introuvable');
    const wallet = toWallet(walletRes.rows[0]);

    const goalRes = await client.query(
      'SELECT * FROM goals WHERE id = $1 AND wallet_id = $2 FOR UPDATE',
      [goalId, walletId]
    );
    if (!goalRes.rows[0]) throw ApiError.notFound('Objectif introuvable');
    const goal = toGoal(goalRes.rows[0]);

    if (amount > goal.savedAmount) {
      throw ApiError.validation(
        `Tu ne peux retirer que ${goal.savedAmount} FCFA de cet objectif`,
        { field: 'amount', saved: goal.savedAmount }
      );
    }
    if (amount > wallet.savingsAmount) {
      throw ApiError.conflict(
        'SAVINGS_LOCKED',
        'Épargne insuffisante pour retirer ce montant'
      );
    }

    const newSaved = goal.savedAmount - amount;
    const status = newSaved >= goal.targetAmount ? 'completed' : 'active';
    const updatedGoal = await client.query(
      `UPDATE goals
       SET saved_amount = $2, status = $3, updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [goalId, newSaved, status]
    );

    const updatedWallet = await client.query(
      `UPDATE wallets
       SET savings_amount = savings_amount - $2::bigint, updated_at = now()
       WHERE id = $1
       RETURNING *`,
      [walletId, amount]
    );

    return {
      goal: toGoal(updatedGoal.rows[0]),
      wallet: toWallet(updatedWallet.rows[0]),
    };
  });
}

async function sumSaved(walletId) {
  const { rows } = await query(
    'SELECT COALESCE(SUM(saved_amount), 0) AS total FROM goals WHERE wallet_id = $1',
    [walletId]
  );
  return Number(rows[0].total);
}

module.exports = {
  toGoal,
  list,
  findById,
  create,
  update,
  remove,
  contribute,
  withdraw,
  sumSaved,
};
