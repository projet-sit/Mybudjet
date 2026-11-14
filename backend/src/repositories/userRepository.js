const { query } = require('../config/db');

function toPublicUser(row) {
  return {
    id: row.id,
    displayName: row.display_name,
    email: row.email,
    photoUrl: row.photo_url,
    currency: row.currency,
    createdAt: row.created_at,
  };
}

async function findByEmail(email) {
  const { rows } = await query('SELECT * FROM users WHERE email = $1 LIMIT 1', [email]);
  return rows[0] || null;
}

async function findById(id) {
  const { rows } = await query('SELECT * FROM users WHERE id = $1 LIMIT 1', [id]);
  return rows[0] || null;
}

async function create({ displayName, email, passwordHash }) {
  const { rows } = await query(
    `INSERT INTO users (display_name, email, password_hash)
     VALUES ($1, $2, $3)
     RETURNING *`,
    [displayName, email, passwordHash]
  );
  return toPublicUser(rows[0]);
}

async function updatePassword(userId, passwordHash) {
  await query('UPDATE users SET password_hash = $1, updated_at = now() WHERE id = $2', [passwordHash, userId]);
  return true;
}

async function deleteById(userId) {
  await query('DELETE FROM users WHERE id = $1', [userId]);
  return true;
}

async function updateFields(userId, fields) {  const keys = Object.keys(fields);
  const sets = keys.map((k, i) => `${k} = $${i + 1}`).join(', ');
  const values = keys.map((k) => fields[k]);
  const { rows } = await query(
    `UPDATE users SET ${sets}, updated_at = now() WHERE id = $${keys.length + 1} RETURNING *`,
    [...values, userId]
  );
  return rows[0] || null;
}

module.exports = { toPublicUser, findByEmail, findById, create, updatePassword, updateFields, deleteById };