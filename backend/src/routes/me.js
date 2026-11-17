const express = require('express');
const authController = require('../controllers/authController');
const { authenticate } = require('../middlewares/authenticate');

// POST /api/v1/me/reset — réinitialisation complète du compte (JWT requis).
const router = express.Router();

router.post('/reset', authenticate, authController.resetMe);

module.exports = router;
