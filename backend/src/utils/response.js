function success(res, data, statusCode = 200) {
  return res.status(statusCode).json({ success: true, data });
}

function error(res, statusCode, code, message, details) {
  return res.status(statusCode).json({
    success: false,
    error: { code, message, ...(details ? { details } : {}) },
  });
}

module.exports = { success, error };
