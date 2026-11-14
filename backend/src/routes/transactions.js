const express = require('express');
const transactionController = require('../controllers/transactionController');
const { authenticate } = require('../middlewares/authenticate');

// Monté sous /api/v1/wallets — chemins explicites pour garantir req.params.walletId.
const router = express.Router();

router.use(authenticate);

router.post('/:walletId/transactions', transactionController.create);
router.get('/:walletId/transactions', transactionController.list);
router.post('/:walletId/transactions/recalculate', transactionController.recalculate);
router.get('/:walletId/transactions/:txId', transactionController.get);
router.patch('/:walletId/transactions/:txId', transactionController.update);
router.delete('/:walletId/transactions/:txId', transactionController.remove);

module.exports = router;
