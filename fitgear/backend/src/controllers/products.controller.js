const db = require('../db');

async function listCategories(req, res, next) {
  try {
    const result = await db.query('SELECT * FROM categories ORDER BY id');
    res.json(result.rows);
  } catch (err) {
    next(err);
  }
}

async function listProducts(req, res, next) {
  try {
    const { category } = req.query;
    let result;
    if (category) {
      result = await db.query(
        `SELECT p.*, c.slug AS category_slug, c.name AS category_name
         FROM products p
         LEFT JOIN categories c ON c.id = p.category_id
         WHERE c.slug = $1
         ORDER BY p.id`,
        [category]
      );
    } else {
      result = await db.query(
        `SELECT p.*, c.slug AS category_slug, c.name AS category_name
         FROM products p
         LEFT JOIN categories c ON c.id = p.category_id
         ORDER BY p.id`
      );
    }
    res.json(result.rows);
  } catch (err) {
    next(err);
  }
}

async function getProduct(req, res, next) {
  try {
    const { slug } = req.params;
    const result = await db.query(
      `SELECT p.*, c.slug AS category_slug, c.name AS category_name
       FROM products p
       LEFT JOIN categories c ON c.id = p.category_id
       WHERE p.slug = $1`,
      [slug]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found.' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    next(err);
  }
}

module.exports = { listCategories, listProducts, getProduct };
