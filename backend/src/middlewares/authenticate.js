const authService = require('../services/authService');
const ApiError = require('../utils/ApiError');

async function authenticate(req, _res, next) {
  try {
    const header = req.headers.authorization || '';
    const match = header.match(/^Bearer (.+)$/);
    if (!match) {
      throw ApiError.unauthorized('Token manquant');
    }

    let decoded;
    try {
      decoded = authService.verifyAccessToken(match[1]);
    } catch (e) {
      throw ApiError.unauthorized(
        e.name === 'TokenExpiredError' ? 'Session expirée, reconnecte-toi' : 'Token invalide'
      );
    }

    const user = await authService.getProfile(decoded.sub);
    req.uid = user.id;
    req.user = user;
    return next();
  } catch (err) {
    return next(err);
  }
}

module.exports = { authenticate };
