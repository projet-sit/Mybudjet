const authService = require('../services/authService');
const { success } = require('../utils/response');
const ApiError = require('../utils/ApiError');

const parseBody = (body, fields) => {
  if (!body || typeof body !== 'object') {
    throw ApiError.validation('Corps de requête invalide');
  }
  const out = {};
  for (const f of fields) {
    out[f] = body[f];
  }
  return out;
};

async function register(req, res, next) {
  try {
    const { displayName, email, phone, password } = parseBody(req.body, ['displayName', 'email', 'phone', 'password']);
    const { user, tokens } = await authService.register({ displayName, email, phone, password });
    return success(res, { user, tokens }, 201);
  } catch (err) {
    return next(err);
  }
}

async function login(req, res, next) {
  try {
    const { email, phone, password } = parseBody(req.body, ['email', 'phone', 'password']);
    const { user, tokens } = await authService.login({ email, phone, password });
    return success(res, { user, tokens });
  } catch (err) {
    return next(err);
  }
}

async function refresh(req, res, next) {
  try {
    const { refreshToken } = parseBody(req.body, ['refreshToken']);
    const tokens = await authService.refresh({ refreshToken });
    return success(res, { tokens });
  } catch (err) {
    return next(err);
  }
}

async function logout(req, res, next) {
  try {
    const { refreshToken } = parseBody(req.body, ['refreshToken']);
    await authService.logout({ refreshToken });
    return success(res, { loggedOut: true });
  } catch (err) {
    return next(err);
  }
}

async function forgotPassword(req, res, next) {
  try {
    const { email } = parseBody(req.body, ['email']);
    const result = await authService.forgotPassword({ email });
    return success(res, result);
  } catch (err) {
    return next(err);
  }
}

async function resetPassword(req, res, next) {
  try {
    const { token, newPassword } = parseBody(req.body, ['token', 'newPassword']);
    await authService.resetPassword({ token, newPassword });
    return success(res, { passwordReset: true });
  } catch (err) {
    return next(err);
  }
}

async function me(req, res, next) {  try {
    const user = await authService.getProfile(req.uid);
    return success(res, { user });
  } catch (err) {
    return next(err);
  }
}

async function updateMe(req, res, next) {
  try {
    const { displayName, photoUrl, currency } = parseBody(req.body, ['displayName', 'photoUrl', 'currency']);
    const user = await authService.updateProfile(req.uid, { displayName, photoUrl, currency });
    return success(res, { user });
  } catch (err) {
    return next(err);
  }
}

async function deleteMe(req, res, next) {
  try {
    await authService.deleteAccount(req.uid);
    return success(res, { deleted: true });
  } catch (err) {
    return next(err);
  }
}

module.exports = { register, login, refresh, logout, forgotPassword, resetPassword, me, updateMe, deleteMe };