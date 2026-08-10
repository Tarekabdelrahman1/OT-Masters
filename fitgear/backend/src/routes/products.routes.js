const express = require('express');
const { listCategories, listProducts, getProduct } = require('../controllers/products.controller');

const router = express.Router();

router.get('/categories', listCategories);
router.get('/', listProducts);
router.get('/:slug', getProduct);

module.exports = router;
