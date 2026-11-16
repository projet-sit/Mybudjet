const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const env = require('../config/env');
const ApiError = require('../utils/ApiError');
const userRepository = require('../repositories/userRepository');
const tokenRepository = require('../repositories/tokenRepository');

const BCRYPT_ROUNDS = 10;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
// Numéro international : + suivi du code pays puis 7 à 14 chiffres (ex. +22997000000)
const PHONE_RE = /^\+[1-9]\d{7,14}$/;

function signAccessToken(payload) {
  return jwt.sign(payload, env.jwt.secret, { expiresIn: env.jwt.accessExpiresIn });
}

function verifyAccessToken(token) {
  return jwt.verify(token, env.jwt.secret);
}

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

function generateRefreshToken() {
  return crypto.randomBytes(48).toString('hex');
}

function clean(name) {
  return String(name || '').trim().replace(/\s+/g, ' ');
}

async function register({ displayName, email, phone, password }) {
  const name = clean(displayName);
  const mail = String(email || '').trim().toLowerCase() || null;
  const tel = String(phone || '').trim();
  const pass = String(password || '');

  if (name.length < 2 || name.length > 100) {
    throw ApiError.validation('Le nom complet doit contenir entre 2 et 100 caractères', { field: 'displayName' });
  }
  // Le numéro de téléphone est le nouvel identifiant ; l'e-mail est facultatif
  // (réservé à la récupération de mot de passe). On accepte l'e-mail seul pour
  // les anciens clients (rétrocompatibilité).
  if (tel) {
    if (!PHONE_RE.test(tel)) {
      throw ApiError.validation('Numéro de téléphone invalide', { field: 'phone' });
    }
  } else if (mail && EMAIL_RE.test(mail)) {
    // Héritage : inscription possible avec e-mail seul via les anciennes versions.
  } else if (mail) {
    throw ApiError.validation('Adresse e-mail invalide', { field: 'email' });
  } else {
    throw ApiError.validation('Numéro de téléphone requis', { field: 'phone' });
  }
  if (mail && !EMAIL_RE.test(mail)) {
    throw ApiError.validation('Adresse e-mail invalide', { field: 'email' });
  }
  if (pass.length < 6) {
    throw ApiError.validation('Le mot de passe doit contenir au moins 6 caractères', { field: 'password' });
  }

  if (tel) {
    const existingPhone = await userRepository.findByPhone(tel);
    if (existingPhone) {
      throw ApiError.conflict('PHONE_ALREADY_IN_USE', 'Un compte existe déjà avec ce numéro', { field: 'phone' });
    }
  }
  if (mail) {
    const existing = await userRepository.findByEmail(mail);
    if (existing) {
      throw ApiError.conflict('EMAIL_ALREADY_IN_USE', 'Un compte existe déjà avec cet e-mail', { field: 'email' });
    }
  }

  const passwordHash = await bcrypt.hash(pass, BCRYPT_ROUNDS);
  const user = await userRepository.create({ displayName: name, email: mail, phone: tel || null, passwordHash });
  const tokens = await issueTokens(user.id);
  return { user, tokens };
}

async function login({ email, phone, password }) {
  // Connexion par téléphone (nouveau) ou e-mail (anciens comptes).
  const identifier = String(phone || email || '').trim();
  const pass = String(password || '');

  if (!identifier || pass.length === 0) {
    throw ApiError.validation('Numéro (ou e-mail) et mot de passe requis');
  }

  const user = await userRepository.findByIdentifier(identifier);
  if (!user) {
    throw ApiError.unauthorized('Numéro (ou e-mail) ou mot de passe incorrect');
  }

  const match = await bcrypt.compare(pass, user.password_hash);
  if (!match) {
    throw ApiError.unauthorized('Numéro (ou e-mail) ou mot de passe incorrect');
  }

  const tokens = await issueTokens(user.id);
  return { user: userRepository.toPublicUser(user), tokens };
}

async function issueTokens(userId) {
  const refreshToken = generateRefreshToken();
  const expiresAt = new Date(Date.now() + parseDurationMs(env.jwt.refreshExpiresIn));
  await tokenRepository.saveRefreshToken({ userId, tokenHash: hashToken(refreshToken), expiresAt });
  const accessToken = signAccessToken({ sub: userId });
  return { accessToken, refreshToken };
}

function parseDurationMs(value) {
  const match = String(value).match(/^(\d+)([smhd])?$/);
  if (!match) return 30 * 24 * 3600 * 1000;
  const n = parseInt(match[1], 10);
  const unit = match[2] || 's';
  const factor = { s: 1000, m: 60000, h: 3600000, d: 86400000 }[unit];
  return n * factor;
}

async function refresh({ refreshToken }) {
  if (!refreshToken) {
    throw ApiError.validation('Refresh token manquant', { field: 'refreshToken' });
  }
  const row = await tokenRepository.findRefreshToken(hashToken(refreshToken));
  if (!row || row.revoked_at || new Date(row.expires_at) < new Date()) {
    throw ApiError.unauthorized('Session invalide, reconnecte-toi');
  }
  await tokenRepository.revokeRefreshToken(hashToken(refreshToken));
  const tokens = await issueTokens(row.user_id);
  return tokens;
}

async function logout({ refreshToken }) {
  if (refreshToken) {
    await tokenRepository.revokeRefreshToken(hashToken(refreshToken));
  }
  return true;
}

async function forgotPassword({ email }) {
  const mail = String(email || '').trim().toLowerCase();
  if (!EMAIL_RE.test(mail)) {
    throw ApiError.validation('Adresse e-mail invalide', { field: 'email' });
  }

  const user = await userRepository.findByEmail(mail);
  if (user) {
    const token = crypto.randomBytes(32).toString('hex');
    const expiresAt = new Date(Date.now() + 3600 * 1000); // 1 heure
    await tokenRepository.saveResetToken({ userId: user.id, tokenHash: hashToken(token), expiresAt });
    // Ne jamais exposer le secret à l'appelant hors d'un poste de développement
    // explicitement configuré. En production, cette étape doit être remplacée
    // par l'envoi du lien/token via un fournisseur e-mail.
    if (env.exposeDevResetToken) {
      console.log(`[auth] reset token pour ${mail} : ${token}`);
      return { resetToken: token, delivered: 'development' };
    }
  }
  // Réponse strictement identique que l'e-mail existe ou non : pas
  // d'énumération de comptes, ni de divulgation du token de réinitialisation.
  return { delivered: 'email-pending' };
}

async function resetPassword({ token, newPassword }) {
  const pass = String(newPassword || '');
  if (pass.length < 6) {
    throw ApiError.validation('Le mot de passe doit contenir au moins 6 caractères', { field: 'newPassword' });
  }
  if (!token) {
    throw ApiError.validation('Token de réinitialisation manquant', { field: 'token' });
  }

  const row = await tokenRepository.findResetToken(hashToken(token));
  if (!row || row.used_at || new Date(row.expires_at) < new Date()) {
    throw ApiError.conflict('RESET_TOKEN_INVALID', 'Lien de réinitialisation invalide ou expiré');
  }

  const passwordHash = await bcrypt.hash(pass, BCRYPT_ROUNDS);
  await userRepository.updatePassword(row.user_id, passwordHash);
  // row.token_hash est déjà le hash stocké en base. Le hacher une seconde
  // fois empêchait de marquer le token comme consommé.
  await tokenRepository.markResetTokenUsed(row.token_hash);
  // Sécurité : révoquer toutes les sessions existantes après un changement de mot de passe.
  await tokenRepository.revokeAllRefreshTokens(row.user_id);
  return true;
}

async function getProfile(uid) {  const user = await userRepository.findById(uid);
  if (!user) throw ApiError.notFound('Utilisateur introuvable');
  return userRepository.toPublicUser(user);
}

async function updateProfile(uid, { displayName, photoUrl, currency }) {
  const updates = {};
  if (displayName !== undefined) {
    const name = clean(displayName);
    if (name.length < 2 || name.length > 100) {
      throw ApiError.validation('Le nom complet doit contenir entre 2 et 100 caractères', { field: 'displayName' });
    }
    updates.display_name = name;
  }
  if (photoUrl !== undefined) {
    updates.photo_url = photoUrl ? String(photoUrl).slice(0, 500) : null;
  }
  if (currency !== undefined) {
    if (typeof currency !== 'string' || currency.length > 8) {
      throw ApiError.validation('Devise invalide', { field: 'currency' });
    }
    updates.currency = currency;
  }
  if (Object.keys(updates).length === 0) {
    throw ApiError.validation('Aucune modification fournie');
  }
  const updated = await userRepository.updateFields(uid, updates);
  if (!updated) throw ApiError.notFound('Utilisateur introuvable');
  return userRepository.toPublicUser(updated);
}

async function deleteAccount(uid) {
  await userRepository.deleteById(uid);
  return true;
}

module.exports = {
  register,
  login,
  refresh,
  logout,
  forgotPassword,
  resetPassword,
  getProfile,
  updateProfile,
  deleteAccount,
  verifyAccessToken,
};
