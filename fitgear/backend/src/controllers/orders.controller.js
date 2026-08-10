const db = require('../db');

// Body shape: { items: [{ productId, quantity }, ...] }
async function createOrder(req, res, next) {
  const client = await db.pool.connect();
  try {
    const { items } = req.body;
    if (!Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ error: 'Your cart is empty.' });
    }

    await client.query('BEGIN');

    let totalCents = 0;
    const lineItems = [];

    for (const item of items) {
      const productRes = await client.query('SELECT * FROM products WHERE id = $1 FOR UPDATE', [item.productId]);
      const product = productRes.rows[0];
      if (!product) {
        throw Object.assign(new Error(`Product ${item.productId} not found.`), { status: 404 });
      }
      if (product.stock < item.quantity) {
        throw Object.assign(new Error(`Not enough stock for "${product.name}".`), { status: 409 });
      }
      totalCents += product.price_cents * item.quantity;
      lineItems.push({ product, quantity: item.quantity });
    }

    const orderRes = await client.query(
      `INSERT INTO orders (user_id, status, total_cents) VALUES ($1,'pending',$2) RETURNING *`,
      [req.user.id, totalCents]
    );
    const order = orderRes.rows[0];

    for (const li of lineItems) {
      await client.query(
        `INSERT INTO order_items (order_id, product_id, quantity, unit_price_cents)
         VALUES ($1,$2,$3,$4)`,
        [order.id, li.product.id, li.quantity, li.product.price_cents]
      );
      await client.query(`UPDATE products SET stock = stock - $1 WHERE id = $2`, [li.quantity, li.product.id]);
    }

    await client.query('COMMIT');
    res.status(201).json({ order, items: lineItems.map((li) => ({ product: li.product.name, quantity: li.quantity })) });
  } catch (err) {
    await client.query('ROLLBACK');
    next(err);
  } finally {
    client.release();
  }
}

async function listMyOrders(req, res, next) {
  try {
    const orders = await db.query(
      `SELECT * FROM orders WHERE user_id = $1 ORDER BY created_at DESC`,
      [req.user.id]
    );
    res.json(orders.rows);
  } catch (err) {
    next(err);
  }
}

module.exports = { createOrder, listMyOrders };
