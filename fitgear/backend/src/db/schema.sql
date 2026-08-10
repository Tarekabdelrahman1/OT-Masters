-- FitGear database schema

CREATE TABLE IF NOT EXISTS users (
  id            SERIAL PRIMARY KEY,
  name          VARCHAR(120) NOT NULL,
  email         VARCHAR(160) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role          VARCHAR(20) NOT NULL DEFAULT 'customer',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS categories (
  id          SERIAL PRIMARY KEY,
  slug        VARCHAR(60) UNIQUE NOT NULL,
  name        VARCHAR(80) NOT NULL,
  plate_label VARCHAR(20) NOT NULL,   -- e.g. "45LB" — used by the plate-badge UI
  description TEXT
);

CREATE TABLE IF NOT EXISTS products (
  id           SERIAL PRIMARY KEY,
  name         VARCHAR(160) NOT NULL,
  slug         VARCHAR(160) UNIQUE NOT NULL,
  category_id  INTEGER REFERENCES categories(id) ON DELETE SET NULL,
  price_cents  INTEGER NOT NULL CHECK (price_cents >= 0),
  spec_tags    TEXT[] NOT NULL DEFAULT '{}',   -- e.g. {"STEEL CORE","KNURLED"}
  badge        VARCHAR(30),                     -- e.g. "Best Seller", "New"
  description  TEXT,
  stock        INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS orders (
  id           SERIAL PRIMARY KEY,
  user_id      INTEGER REFERENCES users(id) ON DELETE SET NULL,
  status       VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending | paid | shipped | cancelled
  total_cents  INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_items (
  id           SERIAL PRIMARY KEY,
  order_id     INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id   INTEGER REFERENCES products(id) ON DELETE SET NULL,
  quantity     INTEGER NOT NULL CHECK (quantity > 0),
  unit_price_cents INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);
