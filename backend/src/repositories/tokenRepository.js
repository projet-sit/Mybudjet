const { query } = require('../config/db');

async function saveRefreshToken({ userId, tokenHash, expiresAt }) {
  await query(
    'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
    [userId, tokenHash, expiresAt]
  );
  return true;
}

async function findRefreshToken(tokenHash) {
  const { rows } = await query(
    'SELECT * FROM refresh_tokens WHERE token_hash = $1 LIMIT 1',
    [tokenHash]
  );
  return rows[0] || null;
}

async function revokeRefreshToken(tokenHash) {
  await query(
    'UPDATE refresh_tokens SET revoked_at = now() WHERE token_hash = $1 AND revoked_at IS NULL',
    [tokenHash]
  );
  return true;
}

async function revokeAllRefreshTokens(userId) {
  await query(
    'UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
    [userId]
  );
  return true;
}

async function saveResetToken({ userId, tokenHash, expiresAt }) {
  await query(
    'INSERT INTO password_reset_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
    [userId, tokenHash, expiresAt]
  );
  return true;
}

async function findResetToken(tokenHash) {
  const { rows } = await query(
    'SELECT * FROM password_reset_tokens WHERE token_hash = $1 LIMIT 1',
    [tokenHash]
  );
  return rows[0] || null;
}

async function markResetTokenUsed(tokenHash) {
  await query(
    'UPDATE password_reset_tokens SET used_at = now() WHERE token_hash = $1 AND used_at IS NULL',
    [tokenHash]
  );
  return true;
}

module.exports = {
  saveRefreshToken,
  findRefreshToken,
  revokeRefreshToken,
  revokeAllRefreshTokens,
  saveResetToken,
  findResetToken,
  markResetTokenUsed,
};
