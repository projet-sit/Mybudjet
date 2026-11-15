const express = require('express');
const walletController = require('../controllers/walletController');
const savingsController = require('../controllers/savingsController');
const { authenticate } = require('../middlewares/authenticate');

const router = express.Router();

// Toutes les routes portefeuille sont protégées.
router.use(authenticate);

router.get('/', walletController.list);
router.post('/', walletController.create);
router.get('/:id', walletController.get);
router.get('/:id/initial-amount/history', walletController.getHistory);
router.patch('/:id/initial-amount', walletController.updateInitialAmount);
router.post('/:id/savings/deposit', savingsController.deposit);
router.post('/:id/savings/withdraw', savingsController.withdraw);
router.post('/:id/savings/withdraw-all', savingsController.withdrawAll);
router.post('/:id/reset', walletController.reset);

module.exports = router;
