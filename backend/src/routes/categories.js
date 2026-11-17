const express = require('express');
const categoryController = require('../controllers/categoryController');
const { authenticate } = require('../middlewares/authenticate');

const router = express.Router();

router.use(authenticate);

router.get('/', categoryController.list);
router.post('/', categoryController.create);
router.patch('/:id', categoryController.rename);
router.delete('/:id', categoryController.remove);

module.exports = router;
