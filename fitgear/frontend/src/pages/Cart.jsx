import { Link, useNavigate } from 'react-router-dom';
import { useState } from 'react';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';
import client from '../api/client';

function formatPrice(cents) {
  return `$${(cents / 100).toFixed(2)}`;
}

export default function Cart() {
  const { items, updateQuantity, removeItem, totalCents, clearCart } = useCart();
  const { user } = useAuth();
  const navigate = useNavigate();
  const [error, setError] = useState('');
  const [placing, setPlacing] = useState(false);

  async function handleCheckout() {
    if (!user) {
      navigate('/login');
      return;
    }
    setError('');
    setPlacing(true);
    try {
      await client.post('/orders', {
        items: items.map((i) => ({ productId: i.product.id, quantity: i.quantity })),
      });
      clearCart();
      navigate('/');
    } catch (err) {
      setError(err.response?.data?.error || 'Checkout failed. Try again.');
    } finally {
      setPlacing(false);
    }
  }

  if (items.length === 0) {
    return (
      <div className="empty-state">
        Your rack is empty.
        <br />
        <Link to="/shop" className="btn-ghost" style={{ display: 'inline-block', marginTop: 20 }}>
          Browse Gear
        </Link>
      </div>
    );
  }

  return (
    <section className="section">
      <div className="wrap">
        <h1 className="page-title display" style={{ marginBottom: 40 }}>Your Rack</h1>

        {items.map((item) => (
          <div className="cart-row" key={item.product.id}>
            <div>
              <div className="product-name">{item.product.name}</div>
              <div className="mono" style={{ fontSize: 12, color: 'var(--steel)' }}>
                {formatPrice(item.product.price_cents)} each
              </div>
            </div>
            <div className="qty-controls">
              <button onClick={() => updateQuantity(item.product.id, item.quantity - 1)} aria-label="Decrease quantity">−</button>
              <span className="mono">{item.quantity}</span>
              <button onClick={() => updateQuantity(item.product.id, item.quantity + 1)} aria-label="Increase quantity">+</button>
            </div>
            <div className="price">{formatPrice(item.product.price_cents * item.quantity)}</div>
            <button className="btn-ghost" onClick={() => removeItem(item.product.id)}>Remove</button>
          </div>
        ))}

        {error && <div className="form-error" style={{ marginTop: 24 }}>{error}</div>}

        <div className="cart-summary">
          <div className="cart-summary-row">
            <span>Subtotal</span>
            <span>{formatPrice(totalCents)}</span>
          </div>
          <div className="cart-summary-row">
            <span>Shipping</span>
            <span>{totalCents >= 7500 ? 'Free' : '$9.00'}</span>
          </div>
          <div className="cart-summary-row total">
            <span>Total</span>
            <span>{formatPrice(totalCents >= 7500 ? totalCents : totalCents + 900)}</span>
          </div>
          <button className="btn-primary" style={{ width: '100%', marginTop: 16 }} onClick={handleCheckout} disabled={placing}>
            {placing ? 'Placing Order…' : user ? 'Checkout' : 'Sign In to Checkout'}
          </button>
        </div>
      </div>
    </section>
  );
}
