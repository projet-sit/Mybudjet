const express = require('express');
const walletController = require('../controllers/walletController');
const { authenticate } = require('../middlewares/authenticate');

const router = express.Router();

// Toutes les routes portefeuille sont protégées.
router.use(authenticate);

router.get('/', walletController.list);
router.post('/', walletController.create);
router.get('/:id', walletController.get);
router.get('/:id/initial-amount/history', walletController.getHistory);
router.patch('/:id/initial-amount', walletController.updateInitialAmount);
router.patch('/:id/savings', walletController.setSavings);
router.post('/:id/reset', walletController.reset);

module.exports = router;
