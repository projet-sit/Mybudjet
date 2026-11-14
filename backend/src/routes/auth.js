const express = require('express');
const rateLimit = require('express-rate-limit');
const authController = require('../controllers/authController');
const { authenticate } = require('../middlewares/authenticate');

const router = express.Router();

// Limitation renforcée sur les endpoints d'authentification.
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: { code: 'RATE_LIMITED', message: 'Trop de tentatives, réessaie dans 15 minutes' } },
});

router.post('/register', authLimiter, authController.register);
router.post('/login', authLimiter, authController.login);
router.post('/refresh', authLimiter, authController.refresh);
router.post('/logout', authController.logout);
router.post('/forgot-password', authLimiter, authController.forgotPassword);
router.post('/reset-password', authLimiter, authController.resetPassword);

// Routes protégées
router.get('/me', authenticate, authController.me);
router.patch('/me', authenticate, authController.updateMe);
router.delete('/me', authenticate, authController.deleteMe);
module.exports = router;
