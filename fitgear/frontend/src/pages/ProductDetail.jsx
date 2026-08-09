import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useCart } from '../context/CartContext';
import client from '../api/client';

function formatPrice(cents) {
  return `$${(cents / 100).toFixed(0)}`;
}

export default function ProductDetail() {
  const { slug } = useParams();
  const { addItem } = useCart();
  const [product, setProduct] = useState(null);
  const [quantity, setQuantity] = useState(1);
  const [loading, setLoading] = useState(true);
  const [added, setAdded] = useState(false);

  useEffect(() => {
    setLoading(true);
    client
      .get(`/products/${slug}`)
      .then((res) => setProduct(res.data))
      .catch(() => setProduct(null))
      .finally(() => setLoading(false));
  }, [slug]);

  if (loading) return <div className="loading-state">LOADING…</div>;
  if (!product) {
    return (
      <div className="empty-state">
        Couldn't find that piece of gear.
        <br />
        <Link to="/shop" className="btn-ghost" style={{ display: 'inline-block', marginTop: 20 }}>
          Back to Shop
        </Link>
      </div>
    );
  }

  return (
    <section className="section">
      <div
        className="wrap"
        style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 48, alignItems: 'start' }}
      >
        <div className="product-media" style={{ height: 380, borderRadius: 4 }}>
          {product.badge && <span className="tag-corner mono">{product.badge}</span>}
          <svg className="product-icon" viewBox="0 0 64 64" fill="none" style={{ width: 120, height: 120 }}>
            <rect x="10" y="26" width="44" height="12" rx="2" fill="#7d8494" />
            <circle cx="14" cy="32" r="8" fill="#EDE9DF" />
            <circle cx="50" cy="32" r="8" fill="#EDE9DF" />
          </svg>
        </div>

        <div>
          <div className="section-tag">{product.category_name}</div>
          <h1 className="page-title display" style={{ fontSize: 'clamp(28px,4vw,42px)', marginBottom: 16 }}>
            {product.name}
          </h1>
          <div className="product-specs mono" style={{ marginBottom: 20 }}>
            {(product.spec_tags || []).map((tag) => (
              <span key={tag}>{tag}</span>
            ))}
          </div>
          <p className="hero-sub" style={{ maxWidth: 460, marginTop: 0 }}>{product.description}</p>
          <div className="price" style={{ fontSize: 28, margin: '28px 0' }}>
            {formatPrice(product.price_cents)}
          </div>

          <div style={{ display: 'flex', gap: 16, alignItems: 'center' }}>
            <div className="qty-controls">
              <button onClick={() => setQuantity((q) => Math.max(1, q - 1))} aria-label="Decrease quantity">−</button>
              <span className="mono">{quantity}</span>
              <button onClick={() => setQuantity((q) => q + 1)} aria-label="Increase quantity">+</button>
            </div>
            <button
              className="btn-primary"
              onClick={() => {
                addItem(product, quantity);
                setAdded(true);
                setTimeout(() => setAdded(false), 2000);
              }}
            >
              {added ? 'Added ✓' : 'Add to Cart'}
            </button>
          </div>

          <p className="form-note" style={{ textAlign: 'left', marginTop: 24 }}>
            {product.stock > 0 ? `${product.stock} in stock` : 'Currently out of stock'}
          </p>
        </div>
      </div>
    </section>
  );
}
