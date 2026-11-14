class ApiError extends Error {
  constructor(statusCode, code, message, details) {
    super(message);
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
    this.isOperational = true;
  }

  static validation(message, details) {
    return new ApiError(400, 'VALIDATION_ERROR', message, details);
  }
  static unauthorized(message = 'Authentification requise') {
    return new ApiError(401, 'UNAUTHORIZED', message);
  }
  static forbidden(message = 'Accès interdit') {
    return new ApiError(403, 'FORBIDDEN', message);
  }
  static notFound(message = 'Ressource introuvable') {
    return new ApiError(404, 'NOT_FOUND', message);
  }
  static conflict(code, message, details) {
    return new ApiError(409, code, message, details);
  }
  static internal(message = 'Erreur interne du serveur') {
    return new ApiError(500, 'INTERNAL_ERROR', message);
  }
}

module.exports = ApiError;
