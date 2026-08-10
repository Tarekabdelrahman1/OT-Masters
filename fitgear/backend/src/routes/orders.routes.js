const express = require('express');
const { requireAuth } = require('../middleware/auth.middleware');
const { createOrder, listMyOrders } = require('../controllers/orders.controller');

const router = express.Router();

router.use(requireAuth);
router.post('/', createOrder);
router.get('/mine', listMyOrders);

module.exports = router;
